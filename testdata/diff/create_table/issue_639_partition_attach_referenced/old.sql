CREATE TABLE public.events (
    id bigint NOT NULL,
    at date NOT NULL,
    PRIMARY KEY (id, at)
) PARTITION BY RANGE (at);

CREATE TABLE public.events_2026_01 PARTITION OF public.events FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');

CREATE TABLE public.events_2026_02 (
    id bigint NOT NULL,
    at date NOT NULL
);
