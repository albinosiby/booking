-- Booking invoices. Per-organization on/off switch (default ON when no row exists) and an immutable
-- history of generated invoice snapshots. Nothing existing is altered.
-- Do not apply to a live database without owner authorization.
-- Rollback: see end of file.
CREATE TABLE booking_invoice_settings (
 organization_id uuid PRIMARY KEY REFERENCES organizations(id) ON DELETE CASCADE,
 enabled boolean NOT NULL DEFAULT true,
 updated_by text NOT NULL,
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE booking_invoice_counters (
 organization_id uuid PRIMARY KEY REFERENCES organizations(id) ON DELETE CASCADE,
 last_number integer NOT NULL DEFAULT 0
);
CREATE TABLE booking_invoices (
 id uuid PRIMARY KEY,
 organization_id uuid NOT NULL REFERENCES organizations(id),
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
 FOREIGN KEY(booking_id,organization_id) REFERENCES bookings(id,organization_id),
 UNIQUE(organization_id,invoice_number),
 UNIQUE(organization_id,command_key)
);
CREATE INDEX booking_invoices_booking_idx ON booking_invoices(organization_id,booking_id,generated_at DESC);
CREATE FUNCTION booking_invoices_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 RAISE EXCEPTION 'Generated invoices cannot be changed or deleted.';
END;
$$;
CREATE TRIGGER booking_invoices_no_change BEFORE UPDATE OR DELETE ON booking_invoices
 FOR EACH ROW EXECUTE FUNCTION booking_invoices_immutable();
-- Rollback: DROP TABLE booking_invoices; DROP FUNCTION booking_invoices_immutable();
--           DROP TABLE booking_invoice_counters; DROP TABLE booking_invoice_settings;
