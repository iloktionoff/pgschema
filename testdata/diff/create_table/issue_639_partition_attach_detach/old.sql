-- Drift on the target, in three independent partition hierarchies.
--
-- events (PG17+ identity on the parent, foreign key to the partitioned
-- accounts): events_2026_01 was re-attached with a narrower bound and
-- events_2026_02 was detached. Both keep the primary key, foreign key and
-- check constraint they inherited while they were partitions, and DETACH
-- removed the identity from events_2026_02. events_2026_03 is a standalone
-- table prepared for attach: it has the check constraint but no key of its
-- own. events_2026_04 is still attached. audit_log references events_2026_01.
--
-- metrics: a two-level hierarchy whose leaves hang off metrics_low.
-- metrics_high is a standalone partitioned table, without keys, with one leaf.
--
-- old_parent: a list-partitioned parent with one child; standalone is a plain
-- table.
CREATE TABLE public.accounts (
    id integer PRIMARY KEY
) PARTITION BY RANGE (id);

CREATE TABLE public.accounts_all PARTITION OF public.accounts FOR VALUES FROM (0) TO (1000000);

CREATE TABLE public.events (
    id bigint GENERATED ALWAYS AS IDENTITY,
    at date NOT NULL,
    account_id integer NOT NULL REFERENCES public.accounts (id),
    amount integer CHECK (amount > 0),
    PRIMARY KEY (id, at)
) PARTITION BY RANGE (at);

CREATE TABLE public.events_2026_01 PARTITION OF public.events FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE public.events_2026_02 PARTITION OF public.events FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE TABLE public.events_2026_04 PARTITION OF public.events FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');

ALTER TABLE public.events DETACH PARTITION public.events_2026_01;
ALTER TABLE public.events ATTACH PARTITION public.events_2026_01 FOR VALUES FROM ('2026-01-01') TO ('2026-01-15');
ALTER TABLE public.events DETACH PARTITION public.events_2026_02;

CREATE TABLE public.events_2026_03 (
    id bigint NOT NULL,
    at date NOT NULL,
    account_id integer NOT NULL,
    amount integer CONSTRAINT events_amount_check CHECK (amount > 0)
);

CREATE TABLE public.audit_log (
    event_id bigint NOT NULL,
    at date NOT NULL,
    FOREIGN KEY (event_id, at) REFERENCES public.events_2026_01 (id, at)
);

CREATE TABLE public.metrics (
    id integer NOT NULL,
    bucket integer NOT NULL,
    PRIMARY KEY (id, bucket)
) PARTITION BY RANGE (bucket);

CREATE TABLE public.metrics_low PARTITION OF public.metrics FOR VALUES FROM (0) TO (100) PARTITION BY RANGE (bucket);

CREATE TABLE public.metrics_low_a PARTITION OF public.metrics_low FOR VALUES FROM (0) TO (10);
CREATE TABLE public.metrics_low_b PARTITION OF public.metrics_low FOR VALUES FROM (10) TO (20);
CREATE TABLE public.metrics_low_d PARTITION OF public.metrics_low FOR VALUES FROM (20) TO (30);

CREATE TABLE public.metrics_high (
    id integer NOT NULL,
    bucket integer NOT NULL
) PARTITION BY RANGE (bucket);

CREATE TABLE public.metrics_high_a PARTITION OF public.metrics_high FOR VALUES FROM (100) TO (150);

CREATE TABLE public.old_parent (
    id integer NOT NULL,
    region text NOT NULL
) PARTITION BY LIST (region);

CREATE TABLE public.kept_child PARTITION OF public.old_parent FOR VALUES IN ('eu');

CREATE TABLE public.standalone (
    id integer NOT NULL,
    region text NOT NULL
);
