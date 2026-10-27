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
