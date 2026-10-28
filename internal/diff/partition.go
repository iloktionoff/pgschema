package diff

import (
	"fmt"
	"slices"

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
//
// Constraints follow the child across the two halves. DETACH turns the copies
// of the parent's PRIMARY KEY, UNIQUE and FOREIGN KEY constraints into local
// constraints of the child (its CHECK copies already appear in the IR), so
// withConstraintsRetainedByDetach adds them to the old state before the diff:
// a standalone table that declares the same constraint keeps it, one that does
// not drops it. ATTACH in turn adopts an existing copy that matches the new
// parent's constraint, so keepConstraintsAdoptedByAttach leaves those in place
// rather than rebuilding the index or re-validating the foreign key.
//
// Not handled: DETACH fails when rows of the partition are referenced through
// a foreign key that points at the parent (PostgreSQL checks the referencing
// rows at detach time). Dropping and re-validating such foreign keys around
// the re-attach is left to the operator.

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

// partitionChanged reports whether the table's partition parent or bound
// differs between the two states.
func partitionChanged(oldTable, newTable *ir.Table) bool {
	return oldTable.PartitionOf != newTable.PartitionOf ||
		partitionParentSchema(oldTable) != partitionParentSchema(newTable) ||
		oldTable.PartitionBound != newTable.PartitionBound
}

// diffPartition records a changed partition parent or bound on the diff.
func diffPartition(diff *tableDiff, oldTable, newTable *ir.Table) {
	if !partitionChanged(oldTable, newTable) {
		return
	}
	diff.PartitionChanged = true
	diff.OldPartitionOf = oldTable.PartitionOf
	diff.OldPartitionOfSchema = partitionParentSchema(oldTable)
}

// withConstraintsRetainedByDetach returns a copy of the partition oldTable
// whose constraints include the copies of its parent's primary key, unique and
// foreign key constraints, under the names PostgreSQL gave them on the child.
// The inspector leaves those copies out of a partition's IR, but once the table
// is detached they are ordinary local constraints: a desired standalone table
// that declares the same constraint under the same name must not add it again
// (PostgreSQL refuses a second primary key), and one that does not declare it
// must drop it. Copies whose catalog name is unknown are left out.
func withConstraintsRetainedByDetach(oldTable, parent *ir.Table) *ir.Table {
	if parent == nil || len(oldTable.InheritedConstraints) == 0 {
		return oldTable
	}
	table := *oldTable
	table.Constraints = make(map[string]*ir.Constraint, len(oldTable.Constraints)+len(oldTable.InheritedConstraints))
	for name, constraint := range oldTable.Constraints {
		table.Constraints[name] = constraint
	}
	for parentName, childName := range oldTable.InheritedConstraints {
		source := parent.Constraints[parentName]
		if source == nil || table.Constraints[childName] != nil {
			continue
		}
		switch source.Type {
		case ir.ConstraintTypePrimaryKey, ir.ConstraintTypeUnique, ir.ConstraintTypeForeignKey:
		default:
			continue
		}
		retained := *source
		retained.Schema = oldTable.Schema
		retained.Table = oldTable.Name
		retained.Name = childName
		retained.Comment = ""
		table.Constraints[childName] = &retained
	}
	return &table
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
		// ATTACH adopts a copy by its columns and index shape alone and keeps
		// the copy's own deferrability and referential actions, so anything
		// that would leave the child differing from the parent must instead
		// be dropped and rebuilt by the attach.
		if candidate.Deferrable != constraint.Deferrable ||
			candidate.InitiallyDeferred != constraint.InitiallyDeferred ||
			candidate.IsTemporal != constraint.IsTemporal {
			continue
		}
		if constraint.Type == ir.ConstraintTypeForeignKey {
			if candidate.ReferencedSchema != constraint.ReferencedSchema ||
				candidate.ReferencedTable != constraint.ReferencedTable ||
				!sameConstraintColumns(candidate.ReferencedColumns, constraint.ReferencedColumns) ||
				candidate.DeleteRule != constraint.DeleteRule ||
				!slices.Equal(slices.Sorted(slices.Values(candidate.DeleteSetColumns)), slices.Sorted(slices.Values(constraint.DeleteSetColumns))) ||
				candidate.UpdateRule != constraint.UpdateRule ||
				candidate.MatchFull != constraint.MatchFull {
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
