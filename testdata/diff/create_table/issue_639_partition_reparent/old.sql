CREATE TABLE public.old_parent (
    id integer NOT NULL,
    region text NOT NULL
) PARTITION BY LIST (region);

CREATE TABLE public.kept_child PARTITION OF public.old_parent FOR VALUES IN ('eu');

CREATE TABLE public.standalone (
    id integer NOT NULL,
    region text NOT NULL
);
