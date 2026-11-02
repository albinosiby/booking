BEGIN;
SET LOCAL search_path = booking_app, pg_catalog;
SET LOCAL lock_timeout = '10s';
DO $$ BEGIN
 IF to_regclass('booking_app.organizations') IS NULL
 OR to_regclass('booking_app.agent_call_logs') IS NULL THEN
  RAISE EXCEPTION 'Apply the existing workspace and call service migrations first.';
 END IF;
END $$;
-- Prepaid call-agent wallet. Money is stored as whole paise; the ledger is append-only.
CREATE TABLE call_wallets (
 organization_id uuid PRIMARY KEY REFERENCES organizations(id),
 balance_paise bigint NOT NULL DEFAULT 0,
 rate_paise_per_minute integer NOT NULL DEFAULT 500 CHECK(rate_paise_per_minute BETWEEN 0 AND 100000),
 billing_starts_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE call_wallet_orders (
 order_id text PRIMARY KEY CHECK(order_id ~ '^booking_[A-Za-z0-9_-]{8,40}$'),
 organization_id uuid NOT NULL REFERENCES organizations(id),
 membership_id uuid NOT NULL,
 amount_paise bigint NOT NULL CHECK(amount_paise BETWEEN 10000 AND 5000000),
 status text NOT NULL DEFAULT 'creating' CHECK(status IN ('creating','created','pending','paid','failed','cancelled','expired')),
 payment_session_id text,
 cf_payment_id text,
 payment_method text,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 paid_at timestamptz
);
CREATE INDEX call_wallet_orders_org ON call_wallet_orders(organization_id,created_at DESC);
CREATE TABLE call_wallet_ledger (
 id uuid PRIMARY KEY,
 organization_id uuid NOT NULL REFERENCES organizations(id),
 kind text NOT NULL CHECK(kind IN ('recharge','call_charge','adjustment','refund')),
 amount_paise bigint NOT NULL,
 balance_after_paise bigint NOT NULL,
 reference text NOT NULL CHECK(length(reference) BETWEEN 1 AND 200),
 call_seconds integer CHECK(call_seconds IS NULL OR call_seconds >= 0),
 note text NOT NULL DEFAULT '' CHECK(length(note) <= 500),
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(organization_id,kind,reference)
);
CREATE INDEX call_wallet_ledger_history ON call_wallet_ledger(organization_id,created_at DESC,id);
ALTER TABLE call_wallets ENABLE ROW LEVEL SECURITY;
CREATE POLICY call_wallets_api ON call_wallets TO booking_api USING (true) WITH CHECK (true);
REVOKE ALL ON call_wallets FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON call_wallets TO booking_api;
ALTER TABLE call_wallet_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY call_wallet_orders_api ON call_wallet_orders TO booking_api USING (true) WITH CHECK (true);
REVOKE ALL ON call_wallet_orders FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON call_wallet_orders TO booking_api;
-- The ledger is append-only for the API role.
ALTER TABLE call_wallet_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY call_wallet_ledger_api ON call_wallet_ledger TO booking_api USING (true) WITH CHECK (true);
REVOKE ALL ON call_wallet_ledger FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON call_wallet_ledger TO booking_api;
INSERT INTO booking_app.schema_migrations(name) VALUES ('20261102120000_call_wallet.sql');
COMMIT;
