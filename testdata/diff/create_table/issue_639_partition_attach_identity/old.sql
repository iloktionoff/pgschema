-- PG17+: a partition's identity column belongs to the parent. DETACH removes
-- it from the child and ATTACH rejects a child that has one of its own, so the
-- plan must not add identity to the detached table before re-attaching it.
CREATE TABLE public.events (
    id bigint GENERATED ALWAYS AS IDENTITY,
    at date NOT NULL,
    PRIMARY KEY (id, at)
) PARTITION BY RANGE (at);

CREATE TABLE public.events_2026_01 PARTITION OF public.events FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE public.events_2026_02 PARTITION OF public.events FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');

ALTER TABLE public.events DETACH PARTITION public.events_2026_02;
