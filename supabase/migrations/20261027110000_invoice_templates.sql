BEGIN;
SET LOCAL search_path = booking_app, pg_catalog;
SET LOCAL lock_timeout = '10s';
DO $$
BEGIN
 IF to_regclass('booking_app.booking_invoice_settings') IS NULL THEN
  RAISE EXCEPTION 'booking_app.booking_invoice_settings is missing. Apply 20261027100000_booking_invoices.sql first.';
 END IF;
END;
$$;
ALTER TABLE booking_app.booking_invoice_settings ADD COLUMN template text NOT NULL DEFAULT 'classic' CHECK(template IN ('classic','modern','minimal'));
INSERT INTO booking_app.schema_migrations(name) VALUES ('20261027110000_invoice_templates.sql');
COMMIT;
