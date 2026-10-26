BEGIN;
SET LOCAL search_path = booking_app, pg_catalog;
SET LOCAL lock_timeout = '10s';
DO $$
BEGIN
 IF to_regclass('booking_app.bookings') IS NULL OR to_regclass('booking_app.organizations') IS NULL THEN
  RAISE EXCEPTION 'booking_app.bookings or organizations is missing. Select the live Booking OS project scwwkaywewecspsrskft and apply its prerequisite migrations first.';
 END IF;
END;
$$;
CREATE TABLE booking_app.booking_invoice_settings (
 organization_id uuid PRIMARY KEY REFERENCES booking_app.organizations(id) ON DELETE CASCADE,
 enabled boolean NOT NULL DEFAULT true,
 updated_by text NOT NULL,
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE booking_app.booking_invoice_counters (
 organization_id uuid PRIMARY KEY REFERENCES booking_app.organizations(id) ON DELETE CASCADE,
 last_number integer NOT NULL DEFAULT 0
);
CREATE TABLE booking_app.booking_invoices (
 id uuid PRIMARY KEY,
 organization_id uuid NOT NULL REFERENCES booking_app.organizations(id),
 booking_id uuid NOT NULL,
 invoice_number text NOT NULL CHECK(length(invoice_number) BETWEEN 5 AND 40),
 total_minor bigint NOT NULL CHECK(total_minor>=0),
 paid_minor bigint NOT NULL,
 balance_minor bigint NOT NULL CHECK(balance_minor>=0),
 currency varchar(3) NOT NULL,
 content_hash text NOT NULL,
 snapshot jsonb NOT NULL,
 logo_data bytea,
 logo_content_type text,
 qr_data bytea,
 qr_content_type text,
 generated_by text NOT NULL,
 generated_by_name text NOT NULL,
 generated_at timestamptz NOT NULL DEFAULT now(),
 command_key uuid NOT NULL,
 FOREIGN KEY(booking_id,organization_id) REFERENCES booking_app.bookings(id,organization_id),
 UNIQUE(organization_id,invoice_number),
 UNIQUE(organization_id,command_key)
);
CREATE INDEX booking_invoices_booking_idx ON booking_app.booking_invoices(organization_id,booking_id,generated_at DESC);
CREATE FUNCTION booking_app.booking_invoices_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 RAISE EXCEPTION 'Generated invoices cannot be changed or deleted.';
END;
$$;
CREATE TRIGGER booking_invoices_no_change BEFORE UPDATE OR DELETE ON booking_app.booking_invoices
 FOR EACH ROW EXECUTE FUNCTION booking_app.booking_invoices_immutable();
ALTER TABLE booking_app.booking_invoice_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE booking_app.booking_invoice_counters ENABLE ROW LEVEL SECURITY;
ALTER TABLE booking_app.booking_invoices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON booking_app.booking_invoice_settings, booking_app.booking_invoice_counters, booking_app.booking_invoices FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION booking_app.booking_invoices_immutable() FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON booking_app.booking_invoice_settings TO booking_api;
GRANT SELECT, INSERT, UPDATE ON booking_app.booking_invoice_counters TO booking_api;
GRANT SELECT, INSERT ON booking_app.booking_invoices TO booking_api;
CREATE POLICY booking_invoice_settings_server_access ON booking_app.booking_invoice_settings TO booking_api USING (true) WITH CHECK (true);
CREATE POLICY booking_invoice_counters_server_access ON booking_app.booking_invoice_counters TO booking_api USING (true) WITH CHECK (true);
CREATE POLICY booking_invoices_server_access ON booking_app.booking_invoices TO booking_api USING (true) WITH CHECK (true);
INSERT INTO booking_app.schema_migrations(name) VALUES ('20261027100000_booking_invoices.sql');
COMMIT;
