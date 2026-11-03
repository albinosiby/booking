-- Admin-managed call pricing. One row of platform defaults; NULL rate keeps recharge off until an admin sets it.
CREATE TABLE call_billing_settings (
 id boolean PRIMARY KEY DEFAULT true CHECK(id),
 rate_paise_per_minute integer CHECK(rate_paise_per_minute BETWEEN 1 AND 100000),
 plans_paise integer[] NOT NULL DEFAULT '{25000,50000,75000,100000}'
  CHECK(cardinality(plans_paise) BETWEEN 1 AND 6 AND 10000 <= ALL(plans_paise) AND 5000000 >= ALL(plans_paise)),
 custom_enabled boolean NOT NULL DEFAULT true,
 custom_above_paise integer NOT NULL DEFAULT 100000 CHECK(custom_above_paise BETWEEN 0 AND 4990000),
 custom_max_paise integer NOT NULL DEFAULT 5000000 CHECK(custom_max_paise BETWEEN 10000 AND 5000000),
 low_balance_paise integer NOT NULL DEFAULT 25000 CHECK(low_balance_paise BETWEEN 0 AND 5000000),
 version integer NOT NULL DEFAULT 1,
 updated_by text NOT NULL DEFAULT '',
 updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK(custom_max_paise > custom_above_paise)
);
INSERT INTO call_billing_settings DEFAULT VALUES;
-- Per-client overrides: NULL means the client follows the platform default.
ALTER TABLE call_wallets
 ALTER COLUMN rate_paise_per_minute DROP NOT NULL,
 ALTER COLUMN rate_paise_per_minute DROP DEFAULT,
 ADD COLUMN plans_paise integer[]
  CHECK(plans_paise IS NULL OR (cardinality(plans_paise) BETWEEN 1 AND 6 AND 10000 <= ALL(plans_paise) AND 5000000 >= ALL(plans_paise))),
 ADD COLUMN custom_enabled boolean,
 ADD COLUMN custom_above_paise integer CHECK(custom_above_paise BETWEEN 0 AND 4990000),
 ADD COLUMN custom_max_paise integer CHECK(custom_max_paise BETWEEN 10000 AND 5000000),
 ADD COLUMN low_balance_paise integer CHECK(low_balance_paise BETWEEN 0 AND 5000000),
 ADD COLUMN low_alert_sent boolean NOT NULL DEFAULT false,
 ADD COLUMN empty_alert_sent boolean NOT NULL DEFAULT false;
-- Existing wallets move to the admin-set default rate.
UPDATE call_wallets SET rate_paise_per_minute=NULL;
-- Each charge keeps the rate it used; admin credits record who added them and how the client paid.
ALTER TABLE call_wallet_ledger
 ADD COLUMN rate_paise_per_minute integer CHECK(rate_paise_per_minute IS NULL OR rate_paise_per_minute >= 0),
 ADD COLUMN admin_email text CHECK(admin_email IS NULL OR length(admin_email) <= 320),
 ADD COLUMN payment_mode text CHECK(payment_mode IS NULL OR payment_mode IN ('cash','upi','bank_transfer','cheque','other')),
 ADD COLUMN external_reference text CHECK(external_reference IS NULL OR length(external_reference) <= 100);
-- Low and empty balance alerts reuse the private push outbox; owners are the only recipients.
ALTER TABLE booking_notification_events
 ADD COLUMN wallet_details jsonb,
 DROP CONSTRAINT booking_notification_events_kind_check,
 DROP CONSTRAINT notification_event_source_check;
ALTER TABLE booking_notification_events
 ADD CONSTRAINT booking_notification_events_kind_check CHECK(kind IN ('created','cancelled','rescheduled','staff_cash_collected','call_wallet_low','call_wallet_empty')),
 ADD CONSTRAINT notification_event_source_check CHECK(
  (kind IN ('created','cancelled','rescheduled') AND history_id IS NOT NULL AND booking_id IS NOT NULL
   AND business_id IS NOT NULL AND resource_id IS NOT NULL AND settlement_id IS NULL AND cash_details IS NULL AND wallet_details IS NULL)
  OR
  (kind='staff_cash_collected' AND settlement_id IS NOT NULL AND history_id IS NULL AND booking_id IS NULL
   AND business_id IS NULL AND resource_id IS NULL AND cash_details IS NOT NULL AND jsonb_typeof(cash_details)='object' AND wallet_details IS NULL)
  OR
  (kind IN ('call_wallet_low','call_wallet_empty') AND history_id IS NULL AND booking_id IS NULL AND business_id IS NULL
   AND resource_id IS NULL AND settlement_id IS NULL AND cash_details IS NULL AND wallet_details IS NOT NULL AND jsonb_typeof(wallet_details)='object')
 );
REVOKE ALL ON call_billing_settings FROM PUBLIC;
