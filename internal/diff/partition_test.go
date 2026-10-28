package diff

import (
	"testing"

	"github.com/pgplex/pgschema/ir"
)

func constraintColumns(names ...string) []*ir.ConstraintColumn {
	columns := make([]*ir.ConstraintColumn, len(names))
	for i, name := range names {
		columns[i] = &ir.ConstraintColumn{Name: name, Position: i + 1}
	}
	return columns
}

// ATTACH PARTITION adopts an existing child constraint by its columns alone and
// keeps the child's own deferrability and referential actions, so a copy that
// differs from the parent's constraint in those must not be kept. (#639)
func TestParentSuppliesConstraint(t *testing.T) {
	parentPK := &ir.Constraint{Name: "events_pkey", Type: ir.ConstraintTypePrimaryKey, Columns: constraintColumns("id", "at")}
	parentFK := &ir.Constraint{
		Name: "events_account_id_fkey", Type: ir.ConstraintTypeForeignKey,
		Columns: constraintColumns("account_id"), ReferencedSchema: "public", ReferencedTable: "accounts",
		ReferencedColumns: constraintColumns("id"), DeleteRule: "SET NULL", DeleteSetColumns: []string{"account_id"}, UpdateRule: "NO ACTION",
	}
	parent := &ir.Table{Schema: "public", Name: "events", Constraints: map[string]*ir.Constraint{parentPK.Name: parentPK, parentFK.Name: parentFK}}

	childPK := *parentPK
	childPK.Name = "events_2026_01_pkey"
	deferrablePK := childPK
	deferrablePK.Deferrable = true
	childFK := *parentFK
	childFK.Name = "events_2026_01_account_id_fkey"
	setNullAllFK := childFK
	setNullAllFK.DeleteSetColumns = nil
	checkCopy := &ir.Constraint{Name: "events_amount_check", Type: ir.ConstraintTypeCheck, CheckClause: "CHECK (amount > 0)"}

	tests := []struct {
		name       string
		constraint *ir.Constraint
		want       bool
	}{
		{"primary key copy", &childPK, true},
		{"primary key with different deferrability", &deferrablePK, false},
		{"foreign key copy", &childFK, true},
		{"foreign key with different SET NULL column list", &setNullAllFK, false},
		{"check constraint", checkCopy, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := parentSuppliesConstraint(parent, tt.constraint); got != tt.want {
				t.Errorf("parentSuppliesConstraint() = %v, want %v", got, tt.want)
			}
		})
	}
}

// A detached partition keeps its parent's PK/UNIQUE/FK copies as local
// constraints under the names the catalog gave them, so the old state used for
// the diff must list them; the inspected table itself is left untouched. (#639)
func TestWithConstraintsRetainedByDetach(t *testing.T) {
	parentPK := &ir.Constraint{Schema: "public", Table: "events", Name: "events_pkey", Type: ir.ConstraintTypePrimaryKey, Columns: constraintColumns("id", "at"), Comment: "parent comment"}
	parentFK := &ir.Constraint{Schema: "public", Table: "events", Name: "events_account_id_fkey", Type: ir.ConstraintTypeForeignKey, Columns: constraintColumns("account_id"), ReferencedTable: "accounts", ReferencedColumns: constraintColumns("id")}
	parent := &ir.Table{Schema: "public", Name: "events", Constraints: map[string]*ir.Constraint{parentPK.Name: parentPK, parentFK.Name: parentFK}}
	check := &ir.Constraint{Schema: "public", Table: "events_2026_01", Name: "events_amount_check", Type: ir.ConstraintTypeCheck}
	child := &ir.Table{
		Schema: "public", Name: "events_2026_01", PartitionOf: "events",
		Constraints:          map[string]*ir.Constraint{check.Name: check},
		InheritedConstraints: map[string]string{"events_pkey": "events_2026_01_pkey", "events_account_id_fkey": "events_account_id_fkey", "gone": "gone_copy"},
	}

	got := withConstraintsRetainedByDetach(child, parent)

	if len(child.Constraints) != 1 {
		t.Fatalf("inspected table modified: %d constraints", len(child.Constraints))
	}
	if len(got.Constraints) != 3 {
		t.Fatalf("got %d constraints, want 3", len(got.Constraints))
	}
	pk := got.Constraints["events_2026_01_pkey"]
	if pk == nil || pk.Type != ir.ConstraintTypePrimaryKey || pk.Table != "events_2026_01" || pk.Comment != "" {
		t.Errorf("retained primary key = %+v", pk)
	}
	if fk := got.Constraints["events_account_id_fkey"]; fk == nil || fk.ReferencedTable != "accounts" || fk.Table != "events_2026_01" {
		t.Errorf("retained foreign key = %+v", fk)
	}
	if got.Constraints[check.Name] != check {
		t.Error("child's own constraint not carried over")
	}
	if same := withConstraintsRetainedByDetach(child, nil); same != child {
		t.Error("expected the table itself when the parent is unknown")
	}
}
