ALTER TABLE old_parent DETACH PARTITION kept_child;

DROP TABLE IF EXISTS old_parent CASCADE;

CREATE TABLE IF NOT EXISTS new_parent (
    id integer NOT NULL,
    region text NOT NULL
) PARTITION BY LIST (region);

ALTER TABLE new_parent ATTACH PARTITION standalone FOR VALUES IN ('us');
