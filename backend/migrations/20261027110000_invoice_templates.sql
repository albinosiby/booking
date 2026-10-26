-- Invoice design chosen by the owner. Existing and new organizations start on 'classic'.
-- Generated invoices keep the design they were created with (stored in their snapshot).
-- Do not apply to a live database without owner authorization.
-- Rollback: ALTER TABLE booking_invoice_settings DROP COLUMN template;
ALTER TABLE booking_invoice_settings ADD COLUMN template text NOT NULL DEFAULT 'classic' CHECK(template IN ('classic','modern','minimal'));
