CREATE TABLE public.metrics (
    id integer NOT NULL,
    bucket integer NOT NULL,
    PRIMARY KEY (id, bucket)
) PARTITION BY RANGE (bucket);

CREATE TABLE public.metrics_low PARTITION OF public.metrics FOR VALUES FROM (0) TO (100) PARTITION BY RANGE (bucket);

CREATE TABLE public.metrics_low_a PARTITION OF public.metrics_low FOR VALUES FROM (0) TO (10);
CREATE TABLE public.metrics_low_b PARTITION OF public.metrics_low FOR VALUES FROM (10) TO (20);
