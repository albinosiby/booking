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
REVOKE ALL ON call_wallets,call_wallet_orders,call_wallet_ledger FROM PUBLIC;
