-- events_2026_02 leaves its parent and becomes a standalone table. DETACH turns
-- the copies of the parent's primary key, foreign key and check constraint into
-- local constraints of the child: the primary key it still declares (under the
-- name PostgreSQL gave the copy) is kept rather than added a second time, and
-- the foreign key and check constraint it no longer declares are dropped.
CREATE TABLE public.accounts (
    id integer PRIMARY KEY
);

CREATE TABLE public.events (
    id bigint NOT NULL,
    at date NOT NULL,
    account_id integer REFERENCES public.accounts (id),
    amount integer CHECK (amount > 0),
    PRIMARY KEY (id, at)
) PARTITION BY RANGE (at);

CREATE TABLE public.events_2026_01 PARTITION OF public.events FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');

CREATE TABLE public.events_2026_02 (
    id bigint NOT NULL,
    at date NOT NULL,
    account_id integer,
    amount integer,
    PRIMARY KEY (id, at)
);
