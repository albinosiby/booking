BEGIN;
SET LOCAL search_path=booking_app,pg_catalog;
SET LOCAL lock_timeout='10s';
-- Every finance read joins lines to their event; without this index each
-- lookup scans the whole finance_lines table.
CREATE INDEX IF NOT EXISTS finance_lines_event_idx ON finance_lines(event_id);
INSERT INTO schema_migrations(name) VALUES ('20261021130000_finance_lines_event_index.sql');
COMMIT;
