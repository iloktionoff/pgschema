CREATE TABLE public.metrics (
    id integer NOT NULL,
    bucket integer NOT NULL
) PARTITION BY RANGE (bucket);

CREATE TABLE public.metrics_a PARTITION OF public.metrics FOR VALUES FROM (0) TO (10);
CREATE TABLE public.metrics_b PARTITION OF public.metrics FOR VALUES FROM (10) TO (20);
