ALTER TABLE events DETACH PARTITION events_2026_01;

ALTER TABLE events DETACH PARTITION events_2026_04;

ALTER TABLE old_parent DETACH PARTITION kept_child;

ALTER TABLE metrics_low DETACH PARTITION metrics_low_a;

ALTER TABLE metrics_low DETACH PARTITION metrics_low_b;

ALTER TABLE metrics_low DETACH PARTITION metrics_low_d;

DROP TABLE IF EXISTS old_parent CASCADE;

CREATE TABLE IF NOT EXISTS audit (
    event_id bigint NOT NULL,
    at date NOT NULL,
    note text
);

CREATE TABLE IF NOT EXISTS metrics_high_notes (
    metric_id integer NOT NULL,
    bucket integer NOT NULL,
    note text
);

CREATE TABLE IF NOT EXISTS metrics_low_c PARTITION OF metrics_low FOR VALUES FROM (18) TO (20);

CREATE TABLE IF NOT EXISTS new_parent (
    id integer NOT NULL,
    region text NOT NULL
) PARTITION BY LIST (region);

ALTER TABLE audit_log DROP CONSTRAINT audit_log_event_id_at_fkey;

ALTER TABLE events_2026_04 DROP CONSTRAINT events_account_id_fkey;

ALTER TABLE events_2026_04 DROP CONSTRAINT events_amount_check;

ALTER TABLE events ATTACH PARTITION events_2026_01 FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');

ALTER TABLE events ATTACH PARTITION events_2026_02 FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');

ALTER TABLE events ATTACH PARTITION events_2026_03 FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');

ALTER TABLE metrics ATTACH PARTITION metrics_high FOR VALUES FROM (100) TO (200);

ALTER TABLE metrics_low ATTACH PARTITION metrics_low_a FOR VALUES FROM (0) TO (15);

ALTER TABLE metrics_low ATTACH PARTITION metrics_low_b FOR VALUES FROM (15) TO (18);

ALTER TABLE new_parent ATTACH PARTITION standalone FOR VALUES IN ('us');

ALTER TABLE audit
ADD CONSTRAINT audit_event_id_at_fkey FOREIGN KEY (event_id, at) REFERENCES events_2026_03 (id, at);

ALTER TABLE audit_log
ADD CONSTRAINT audit_log_event_id_at_fkey FOREIGN KEY (event_id, at) REFERENCES events_2026_03 (id, at) NOT VALID;

ALTER TABLE audit_log VALIDATE CONSTRAINT audit_log_event_id_at_fkey;

ALTER TABLE metrics_high_notes
ADD CONSTRAINT metrics_high_notes_metric_id_bucket_fkey FOREIGN KEY (metric_id, bucket) REFERENCES metrics_high_a (id, bucket);
