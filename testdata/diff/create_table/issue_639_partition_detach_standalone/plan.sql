ALTER TABLE events DETACH PARTITION events_2026_02;

ALTER TABLE events_2026_02 DROP CONSTRAINT events_account_id_fkey;

ALTER TABLE events_2026_02 DROP CONSTRAINT events_amount_check;
