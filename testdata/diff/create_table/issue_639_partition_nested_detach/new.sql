-- A leaf of a two-level hierarchy becomes a standalone table. Its primary key
-- copy derives from the root's constraint through the intermediate partition,
-- whose own copy is not part of its IR, so the copy the leaf keeps after DETACH
-- must be resolved up the ancestor chain: it is kept, not added a second time.
CREATE TABLE public.metrics (
    id integer NOT NULL,
    bucket integer NOT NULL,
    PRIMARY KEY (id, bucket)
) PARTITION BY RANGE (bucket);

CREATE TABLE public.metrics_low PARTITION OF public.metrics FOR VALUES FROM (0) TO (100) PARTITION BY RANGE (bucket);

CREATE TABLE public.metrics_low_a PARTITION OF public.metrics_low FOR VALUES FROM (0) TO (10);

CREATE TABLE public.metrics_low_b (
    id integer NOT NULL,
    bucket integer NOT NULL,
    PRIMARY KEY (id, bucket)
);
