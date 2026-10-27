-- The boundary between metrics_a and metrics_b moves, and metrics_c takes the
-- range metrics_b gives up. Every detach must run before the create and the
-- re-attaches, or the bounds overlap while the change is applied.
CREATE TABLE public.metrics (
    id integer NOT NULL,
    bucket integer NOT NULL
) PARTITION BY RANGE (bucket);

CREATE TABLE public.metrics_a PARTITION OF public.metrics FOR VALUES FROM (0) TO (15);
CREATE TABLE public.metrics_b PARTITION OF public.metrics FOR VALUES FROM (15) TO (18);
CREATE TABLE public.metrics_c PARTITION OF public.metrics FOR VALUES FROM (18) TO (30);
