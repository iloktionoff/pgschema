-- Drift on the target: one partition was re-attached with a narrower bound and
-- the other was detached. The detached table keeps the primary key, foreign
-- key and check constraint it inherited while it was a partition.
CREATE TABLE public.accounts (
    id integer PRIMARY KEY
);

CREATE TABLE public.events (
    id bigint NOT NULL,
    at date NOT NULL,
    account_id integer NOT NULL REFERENCES public.accounts (id),
    amount integer CHECK (amount > 0),
    PRIMARY KEY (id, at)
) PARTITION BY RANGE (at);

CREATE TABLE public.events_2026_01 PARTITION OF public.events FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE public.events_2026_02 PARTITION OF public.events FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');

ALTER TABLE public.events DETACH PARTITION public.events_2026_01;
ALTER TABLE public.events ATTACH PARTITION public.events_2026_01 FOR VALUES FROM ('2026-01-01') TO ('2026-01-15');
ALTER TABLE public.events DETACH PARTITION public.events_2026_02;
