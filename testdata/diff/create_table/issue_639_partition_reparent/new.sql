-- old_parent goes away but kept_child stays as a standalone table, so it must
-- be detached before the parent's DROP ... CASCADE. standalone becomes a
-- partition of a parent created in the same migration.
CREATE TABLE public.kept_child (
    id integer NOT NULL,
    region text NOT NULL
);

CREATE TABLE public.new_parent (
    id integer NOT NULL,
    region text NOT NULL
) PARTITION BY LIST (region);

CREATE TABLE public.standalone PARTITION OF public.new_parent FOR VALUES IN ('us');
