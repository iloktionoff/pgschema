-- events_2026_02 has no key of its own until ATTACH gives it the parent's
-- primary key, so the foreign key of the new audit table that references it
-- must be added after the attach rather than inline with CREATE TABLE.
CREATE TABLE public.events (
    id bigint NOT NULL,
    at date NOT NULL,
    PRIMARY KEY (id, at)
) PARTITION BY RANGE (at);

CREATE TABLE public.events_2026_01 PARTITION OF public.events FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE public.events_2026_02 PARTITION OF public.events FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');

CREATE TABLE public.audit (
    event_id bigint NOT NULL,
    at date NOT NULL,
    note text,
    FOREIGN KEY (event_id, at) REFERENCES public.events_2026_02 (id, at)
);
