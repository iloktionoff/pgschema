CREATE TABLE IF NOT EXISTS audit (
    event_id bigint NOT NULL,
    at date NOT NULL,
    note text
);

ALTER TABLE events ATTACH PARTITION events_2026_02 FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');

ALTER TABLE audit
ADD CONSTRAINT audit_event_id_at_fkey FOREIGN KEY (event_id, at) REFERENCES events_2026_02 (id, at);
