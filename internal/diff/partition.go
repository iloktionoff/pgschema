package diff

import (
	"fmt"

	"github.com/pgplex/pgschema/ir"
)

// Partition attachment changes (issue #639).
//
// PostgreSQL cannot alter a partition's bound in place, and a partition cannot
// change parent without leaving the old one, so a changed parent or bound is
// applied as DETACH + ATTACH. The two halves are deliberately far apart:
//
//   - Every DETACH runs in the drop phase, before tables are dropped and before
//     any table is created. A child whose old parent is dropped must leave it
//     before DROP ... CASCADE takes it along, and sibling partitions whose
//     bounds shift against each other, or new partitions created in the space
//     a re-bounded sibling gives up, would overlap while the old bound is
//     still in place.
//   - Every ATTACH runs at the end of the table modifications, once the child
//     has the columns and constraints the parent requires of it.

// partitionParentSchema returns the schema of the table's partition parent, or
// "" when the table is not a partition.
func partitionParentSchema(table *ir.Table) string {
	if table.PartitionOf == "" {
		return ""
	}
	if table.PartitionOfSchema != "" {
		return table.PartitionOfSchema
	}
	return table.Schema
}

// partitionParentKey returns the schema.table key of the table's partition
// parent, or "" when the table is not a partition.
func partitionParentKey(table *ir.Table) string {
	if table.PartitionOf == "" {
		return ""
	}
	return partitionParentSchema(table) + "." + table.PartitionOf
}

// diffPartition records a changed partition parent or bound on the diff.
func diffPartition(diff *tableDiff, oldTable, newTable *ir.Table) {
	if oldTable.PartitionOf == newTable.PartitionOf &&
		partitionParentSchema(oldTable) == partitionParentSchema(newTable) &&
		oldTable.PartitionBound == newTable.PartitionBound {
		return
	}
	diff.PartitionChanged = true
	diff.OldPartitionOf = oldTable.PartitionOf
	diff.OldPartitionOfSchema = partitionParentSchema(oldTable)
}

// keepConstraintsAdoptedByAttach drops from DroppedConstraints the primary
// key, unique and foreign key constraints that ATTACH PARTITION will adopt
// from the table being attached.
//
// A detached partition keeps the copies of its parent's constraints as local
// constraints, which the desired-state partition does not list (the inspector
// skips inherited copies). Dropping them only to have ATTACH rebuild the same
// index and re-validate the same foreign key would be wasted work on a large
// table, and ATTACH reuses an existing constraint that matches the parent's.
func (td *tableDiff) keepConstraintsAdoptedByAttach(parent *ir.Table) {
	if parent == nil || len(td.DroppedConstraints) == 0 {
		return
	}
	kept := td.DroppedConstraints[:0]
	for _, constraint := range td.DroppedConstraints {
		if !parentSuppliesConstraint(parent, constraint) {
			kept = append(kept, constraint)
		}
	}
	td.DroppedConstraints = kept
}

// parentSuppliesConstraint reports whether attaching to parent recreates an
// equivalent of constraint, so an existing copy on the child is reused.
func parentSuppliesConstraint(parent *ir.Table, constraint *ir.Constraint) bool {
	switch constraint.Type {
	case ir.ConstraintTypePrimaryKey, ir.ConstraintTypeUnique, ir.ConstraintTypeForeignKey:
	default:
		return false
	}
	for _, candidate := range parent.Constraints {
		if candidate.Type != constraint.Type || !sameConstraintColumns(candidate.Columns, constraint.Columns) {
			continue
		}
		if constraint.Type == ir.ConstraintTypeForeignKey {
			if candidate.ReferencedSchema != constraint.ReferencedSchema ||
				candidate.ReferencedTable != constraint.ReferencedTable ||
				!sameConstraintColumns(candidate.ReferencedColumns, constraint.ReferencedColumns) ||
				candidate.DeleteRule != constraint.DeleteRule ||
				candidate.UpdateRule != constraint.UpdateRule ||
				candidate.MatchFull != constraint.MatchFull ||
				candidate.Deferrable != constraint.Deferrable ||
				candidate.InitiallyDeferred != constraint.InitiallyDeferred {
				continue
			}
		} else if candidate.NullsNotDistinct != constraint.NullsNotDistinct {
			continue
		}
		return true
	}
	return false
}

func sameConstraintColumns(a, b []*ir.ConstraintColumn) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i].Name != b[i].Name {
			return false
		}
	}
	return true
}

// generateDetachPartitionsSQL emits DETACH PARTITION for every modified table
// that leaves its old parent (for a new parent, a new bound, or to stand
// alone). It belongs in the drop phase; see the note at the top of this file.
func generateDetachPartitionsSQL(diffs []*tableDiff, targetSchema string, collector *diffCollector) {
	for _, td := range diffs {
		if !td.PartitionChanged || td.OldPartitionOf == "" {
			continue
		}
		parentName := getTableNameWithSchema(td.OldPartitionOfSchema, td.OldPartitionOf, targetSchema)
		tableName := getTableNameWithSchema(td.Table.Schema, td.Table.Name, targetSchema)
		sql := fmt.Sprintf("ALTER TABLE %s DETACH PARTITION %s;", parentName, tableName)
		collector.collect(td.partitionContext(DiffOperationDetach), sql)
	}
}

// generateAttachPartitionsSQL emits ATTACH PARTITION for every modified table
// that joins a parent (new or with a new bound). It belongs at the end of the
// table modifications; see the note at the top of this file.
func generateAttachPartitionsSQL(diffs []*tableDiff, targetSchema string, collector *diffCollector) {
	for _, td := range diffs {
		if !td.PartitionChanged || td.Table.PartitionOf == "" || td.Table.PartitionBound == "" {
			continue
		}
		parentName := getTableNameWithSchema(partitionParentSchema(td.Table), td.Table.PartitionOf, targetSchema)
		tableName := getTableNameWithSchema(td.Table.Schema, td.Table.Name, targetSchema)
		sql := fmt.Sprintf("ALTER TABLE %s ATTACH PARTITION %s %s;", parentName, tableName, td.Table.PartitionBound)
		collector.collect(td.partitionContext(DiffOperationAttach), sql)
	}
}

func (td *tableDiff) partitionContext(operation DiffOperation) *diffContext {
	return &diffContext{
		Type:                DiffTypeTablePartition,
		Operation:           operation,
		Path:                fmt.Sprintf("%s.%s", td.Table.Schema, td.Table.Name),
		Source:              td.Table,
		CanRunInTransaction: true,
	}
}
