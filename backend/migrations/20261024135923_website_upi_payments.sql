CREATE TABLE website_payment_settings (
 organization_id uuid PRIMARY KEY REFERENCES organizations(id) ON DELETE CASCADE,
 upi_id text NOT NULL DEFAULT '' CHECK(length(upi_id)<=100),
 qr_data bytea,
 qr_content_type text,
 version integer NOT NULL DEFAULT 1 CHECK(version>0),
 updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK((qr_data IS NULL AND qr_content_type IS NULL) OR
       (qr_data IS NOT NULL AND qr_content_type IS NOT NULL AND octet_length(qr_data) BETWEEN 24 AND 1048576 AND qr_content_type IN ('image/png','image/jpeg','image/webp')))
);
ALTER TABLE website_payment_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE booking_website_spaces
 ADD COLUMN payment_required boolean NOT NULL DEFAULT false,
 ADD COLUMN payment_percentages integer[] NOT NULL DEFAULT '{}',
 ADD CONSTRAINT website_payment_percentages_valid CHECK(
 cardinality(payment_percentages)<=3 AND array_position(payment_percentages,NULL) IS NULL AND 0<ALL(payment_percentages) AND 100>=ALL(payment_percentages)
 AND (NOT payment_required OR cardinality(payment_percentages)>0));
ALTER TABLE bookings ADD COLUMN website_payment_submission jsonb;
ALTER TABLE bookings ADD CONSTRAINT website_payment_submission_valid CHECK(website_payment_submission IS NULL OR (
 jsonb_typeof(website_payment_submission)='object'
 AND website_payment_submission->>'status'='pending_verification'
 AND length(website_payment_submission->>'transaction_id') BETWEEN 6 AND 64
 AND (website_payment_submission->>'percentage')::integer BETWEEN 1 AND 100
 AND (website_payment_submission->>'amount_minor')::bigint>0) IS TRUE);
CREATE UNIQUE INDEX website_payment_transaction_unique ON bookings(organization_id,upper(website_payment_submission->>'transaction_id'))
 WHERE website_payment_submission IS NOT NULL;
