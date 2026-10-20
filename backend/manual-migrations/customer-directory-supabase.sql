-- USER-RUN SCRIPT: Supabase Dashboard > SQL Editor.
-- Target: existing private booking_app schema. No customer/booking data is changed.
-- Prerequisites: 001_workspace.sql and 002_bookings.sql already applied.
BEGIN;
SET LOCAL search_path = booking_app, pg_catalog;
SET LOCAL lock_timeout = '10s';

CREATE INDEX IF NOT EXISTS customers_phone_digits_idx
ON customers (organization_id, (regexp_replace(phone, '[^0-9]', '', 'g')) text_pattern_ops);
CREATE INDEX IF NOT EXISTS bookings_customer_history_idx
ON bookings (organization_id, customer_id, starts_at DESC, id DESC);

INSERT INTO schema_migrations (name)
VALUES ('20261016113744_customer_directory.sql')
ON CONFLICT (name) DO NOTHING;
COMMIT;

-- Validation: expect 2 index rows and 1 migration row.
SELECT indexname, indexdef FROM pg_indexes
WHERE schemaname = 'booking_app'
AND indexname IN ('customers_phone_digits_idx', 'bookings_customer_history_idx');
SELECT name, applied_at FROM booking_app.schema_migrations
WHERE name = '20261016113744_customer_directory.sql';
