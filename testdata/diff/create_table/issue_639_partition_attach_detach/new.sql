-- events: events_2026_01 goes back to its full bound (DETACH + ATTACH) and the
-- detached events_2026_02 is re-attached. Both keep the constraint copies they
-- retained, since ATTACH reuses them, and events_2026_02 is attached without an
-- ADD GENERATED ... AS IDENTITY first, which ATTACH would reject. events_2026_03
-- is attached and only then has the parent's primary key, so the foreign key of
-- the new audit table that references it is added after the attach rather than
-- inline with CREATE TABLE, and the foreign key of audit_log, retargeted from
-- events_2026_01 to it, is dropped up front and re-added after the attach rather
-- than recreated in place. events_2026_04 leaves the hierarchy and becomes a
-- standalone table: DETACH turns its copies of the parent's primary key, foreign
-- key and check constraint into local constraints, so the primary key it still
-- declares (under the name PostgreSQL gave the copy) is kept rather than added
-- a second time, and the foreign key and check constraint it no longer declares
-- are dropped. The foreign keys to the partitioned accounts also own internal
-- per-partition sub-constraints, which must not pass for inherited copies.
--
-- metrics: the boundary between metrics_low_a and metrics_low_b moves and
-- metrics_low_c takes the range metrics_low_b gives up, so every detach must
-- run before the create and the re-attaches or the bounds overlap mid-apply.
-- metrics_low_d becomes standalone; the primary key copy it keeps derives from
-- the root's constraint through metrics_low, whose own copy is not part of its
-- IR, so it is resolved up the ancestor chain and kept, not added again.
-- metrics_high is attached as a partitioned partition: ATTACH gives the primary
-- key to its leaf metrics_high_a as well, so the foreign key of the new
-- metrics_high_notes that references the leaf is added after the attach.
--
-- old_parent goes away but kept_child stays as a standalone table, so it must
-- be detached before the parent's DROP ... CASCADE. standalone becomes a
-- partition of a parent created in the same migration.
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
CREATE TABLE public.events_2026_03 PARTITION OF public.events FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');

CREATE TABLE public.events_2026_04 (
    id bigint NOT NULL,
    at date NOT NULL,
    account_id integer NOT NULL,
    amount integer,
    PRIMARY KEY (id, at)
);

CREATE TABLE public.audit (
    event_id bigint NOT NULL,
    at date NOT NULL,
    note text,
    FOREIGN KEY (event_id, at) REFERENCES public.events_2026_03 (id, at)
);

CREATE TABLE public.audit_log (
    event_id bigint NOT NULL,
    at date NOT NULL,
    FOREIGN KEY (event_id, at) REFERENCES public.events_2026_03 (id, at)
);

CREATE TABLE public.metrics (
    id integer NOT NULL,
    bucket integer NOT NULL,
    PRIMARY KEY (id, bucket)
) PARTITION BY RANGE (bucket);

CREATE TABLE public.metrics_low PARTITION OF public.metrics FOR VALUES FROM (0) TO (100) PARTITION BY RANGE (bucket);

CREATE TABLE public.metrics_low_a PARTITION OF public.metrics_low FOR VALUES FROM (0) TO (15);
CREATE TABLE public.metrics_low_b PARTITION OF public.metrics_low FOR VALUES FROM (15) TO (18);
CREATE TABLE public.metrics_low_c PARTITION OF public.metrics_low FOR VALUES FROM (18) TO (20);

CREATE TABLE public.metrics_low_d (
    id integer NOT NULL,
    bucket integer NOT NULL,
    PRIMARY KEY (id, bucket)
);

CREATE TABLE public.metrics_high PARTITION OF public.metrics FOR VALUES FROM (100) TO (200) PARTITION BY RANGE (bucket);

CREATE TABLE public.metrics_high_a PARTITION OF public.metrics_high FOR VALUES FROM (100) TO (150);

CREATE TABLE public.metrics_high_notes (
    metric_id integer NOT NULL,
    bucket integer NOT NULL,
    note text,
    FOREIGN KEY (metric_id, bucket) REFERENCES public.metrics_high_a (id, bucket)
);

CREATE TABLE public.kept_child (
    id integer NOT NULL,
    region text NOT NULL
);

CREATE TABLE public.new_parent (
    id integer NOT NULL,
    region text NOT NULL
) PARTITION BY LIST (region);

CREATE TABLE public.standalone PARTITION OF public.new_parent FOR VALUES IN ('us');
