-- Existing records and customer IDs are preserved. Run in the application's schema.
CREATE INDEX IF NOT EXISTS customers_phone_digits_idx
ON customers (organization_id, (regexp_replace(phone, '[^0-9]', '', 'g')) text_pattern_ops);
CREATE INDEX IF NOT EXISTS bookings_customer_history_idx
ON bookings (organization_id, customer_id, starts_at DESC, id DESC);
