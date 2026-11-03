# Call agent wallet (prepaid, Cashfree recharge)

Owners prepay for the AI call agent. Each call is charged per started minute at
the rate set in the admin panel. Owners open **Recharge** from the top right of
the **Call booking** page, pick one of the admin's plans (default ₹250, ₹500,
₹750, ₹1,000) or, when the admin allows it, enter a custom amount above a set
minimum.

## Admin controls

- **Call billing** page (admin panel → Operations): the default per-minute rate,
  the 1–6 recharge plans, whether custom amounts are allowed, the "allowed
  above" minimum and maximum for custom amounts, and the low-balance alert level.
  Stored in `call_billing_settings` (one row). Until a rate is saved, recharge is
  off and calls are recorded at ₹0, so a later rate is never applied backwards.
- **Organization page → Call wallet**: balance, totals, every Cashfree order, the
  full wallet history, per-client price overrides (empty field = default) and
  **Add balance** for money paid outside Cashfree, or a deduction to fix a mistake.
  Each credit records the admin, how the client paid and the receipt number.
  The form's request ID stops a double submit from adding money twice.
- Every change is written to the admin audit log (`call_billing.defaults`,
  `call_billing.client`, `call_wallet.adjust`). Changes need a super admin.
- A new rate applies to calls charged after it is saved. Each charge stores the
  rate it used (`call_wallet_ledger.rate_paise_per_minute`).

## Low-balance alerts

When a charge takes the balance below the alert level, owners get one push
notification ("Call balance is low"). They get another when it reaches ₹0
("Call balance is empty"). A recharge or admin credit back above the level
re-arms the alert (`call_wallets.low_alert_sent`, `empty_alert_sent`). Alerts go
through the existing push queue (`booking_notification_events` kinds
`call_wallet_low` and `call_wallet_empty`), so the `booking-notifications`
function must be redeployed too.

## How money moves

```
App ──► BookingOS API ──► payout-backend (/api/booking/pg/orders) ──► Cashfree order
 ◄── payment_session_id ◄─────────────────────────────────────────┘
App opens Cashfree checkout (flutter_cashfree_pg_sdk, web checkout)
 ├─ checkout closes ──► POST /v1/call-wallet/orders/:id/verify
 │                        └─► payout-backend GET /api/booking/pg/orders/:id ──► Cashfree status
 └─ Cashfree webhook ──► payout-backend /api/orders/payment/webhook (signature checked)
                           └─► signed POST /v1/call-wallet/payment-events ──► same status check
```

- The wallet and ledger live only in the BookingOS database. The payout-backend
  only talks to Cashfree and never touches BookingOS data.
- A wallet is credited only after the server reads `PAID` from Cashfree for the
  exact order amount. The app's checkout callback and the webhook both run the same
  check. A database lock and the unique key `(organization_id, kind, reference)`
  make sure a recharge is credited once.
- Calls are charged when Sarvam's end-of-call event arrives
  (`/voice/v1/call-events`). Calls that missed that event are charged when call
  history syncs, once they are more than 3 hours old. Calls that started before
  the organization's wallet was created are never charged.
- The balance may go below zero, because a call is charged after it ends.
  Low or negative balance does **not** yet pause the call service.

## API

| Route | Auth | Purpose |
| --- | --- | --- |
| `GET /v1/call-wallet` | owner | Balance, rate, minutes left, plans, custom amount limits, alert level, last 20 entries |
| `GET /v1/call-wallet/transactions?offset=` | owner | Ledger pages of 50 |
| `POST /v1/call-wallet/orders` `{amount_paise}` | owner | Creates a Cashfree order and returns `payment_session_id` |
| `POST /v1/call-wallet/orders/:id/verify` | owner | Confirms with Cashfree and returns `status` plus the updated wallet |
| `POST /v1/call-wallet/payment-events` | HMAC | Events forwarded from the payout-backend |
| `GET/PUT /v1/admin/call-billing` | admin / super admin | Default pricing (PUT needs the current `version`) |
| `GET /v1/admin/organizations/:id/call-wallet?offset=` | admin | One client's wallet, totals, orders and history |
| `PUT /v1/admin/organizations/:id/call-wallet/pricing` | super admin | Client overrides; `null` clears one |
| `POST /v1/admin/organizations/:id/call-wallet/adjustments` | super admin | Manual credit or deduction |

`GET /v1/agent-calls/calls` now also returns `charge_paise` for each billed call.

`status` is one of `paid`, `pending`, `created`, `failed`, `cancelled`, `expired`.

## Configuration

BookingOS API (Railway and Supabase function secrets):

| Variable | Value |
| --- | --- |
| `PAYMENT_API_BASE_URL` | `https://api.shotify.store/api` |
| `BOOKING_PG_API_KEY` | Random secret, for example `openssl rand -base64 48`. Must match the payout-backend. |
| `BOOKING_PG_EVENT_SECRET` | A second random secret. Must match the payout-backend. |
| `CALL_WALLET_RETURN_URL` | Web app only: `https://<app-domain>/profile/agent-calls/wallet?order_id={order_id}` |

payout-backend (Railway):

| Variable | Value |
| --- | --- |
| `BOOKING_PG_API_KEY` | Same as above |
| `BOOKING_PG_EVENT_SECRET` | Same as above |
| `BOOKING_PG_EVENTS_URL` | `https://<booking-api-host>/v1/call-wallet/payment-events` (for the Supabase function: `https://<project>.supabase.co/functions/v1/booking-api/v1/call-wallet/payment-events`) |

The payout-backend's existing `CASHFREE_CLIENT_ID`, `CASHFREE_CLIENT_SECRET` and
`CASHFREE_ENV` are reused. Recharge stays disabled in the app until
`PAYMENT_API_BASE_URL` and `BOOKING_PG_API_KEY` are set on the BookingOS API.

Cashfree dashboard (production): whitelist the app's Android package, iOS
bundle ID and web domain under Developers → Whitelisting.

## Migration `20261102120000_call_wallet.sql`

The migration only adds three new tables (`call_wallets`, `call_wallet_orders`,
`call_wallet_ledger`). It does not change any existing table.

Prerequisites: the workspace and call service migrations are already applied
(`booking_app.organizations` and `booking_app.agent_call_logs` exist). Take a
database backup first.

Apply:

1. Supabase/Postgres (`booking_app` schema): run
   `supabase/migrations/20261102120000_call_wallet.sql` in a single session, for
   example `psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261102120000_call_wallet.sql`.
   The file has its own `BEGIN`/`COMMIT` and records itself in
   `booking_app.schema_migrations`.
2. Deploy the API (Railway uses `backend/migrations`; with
   `DATABASE_MIGRATE=false` the API refuses to start until the migration is
   recorded).
3. Deploy the `booking-api` edge function (`npm run edge:build` already
   regenerated `supabase/functions/booking-api/index.ts`).

Validate:

```sql
SELECT name FROM booking_app.schema_migrations WHERE name='20261102120000_call_wallet.sql';
SELECT to_regclass('booking_app.call_wallets'), to_regclass('booking_app.call_wallet_orders'), to_regclass('booking_app.call_wallet_ledger');
SELECT relname, relrowsecurity FROM pg_class WHERE relname LIKE 'call_wallet%' AND relkind='r';
-- After a sandbox recharge, the balance equals the sum of the ledger:
SELECT w.organization_id, w.balance_paise, COALESCE(sum(l.amount_paise),0) AS ledger_total
FROM booking_app.call_wallets w LEFT JOIN booking_app.call_wallet_ledger l USING(organization_id)
GROUP BY 1,2 HAVING w.balance_paise <> COALESCE(sum(l.amount_paise),0);  -- expect no rows
```

Recovery:

- If the migration fails, the transaction rolls back. Fix the prerequisite and
  run the whole file again.
- To roll back the application, redeploy the previous API, function and app
  builds. Leave the tables in place: they keep the payment records.
- Only if no real payment was ever recorded: `DROP TABLE booking_app.call_wallet_ledger, booking_app.call_wallet_orders, booking_app.call_wallets; DELETE FROM booking_app.schema_migrations WHERE name='20261102120000_call_wallet.sql';`

## Migration `20261103120000_call_wallet_billing.sql`

Adds admin-managed pricing and alerts:

- the `call_billing_settings` table, with defaults of ₹250/500/750/1,000, custom
  amounts on above ₹1,000 up to ₹50,000, an alert below ₹250 and **no rate**;
- override and alert columns on `call_wallets`;
- rate and admin columns on `call_wallet_ledger`;
- `wallet_details` and the two alert kinds on `booking_notification_events`.

**It clears `call_wallets.rate_paise_per_minute` for every existing wallet**, so
all clients move to the admin default rate.

Prerequisites: `20261102120000_call_wallet.sql` and
`20261029143630_staff_cash_collection_notifications.sql` are applied. Take a
backup.

Apply in this order:

1. Run `supabase/migrations/20261103120000_call_wallet_billing.sql` (it has its own
   `BEGIN`/`COMMIT`).
2. Deploy both edge functions, `booking-api` and `booking-notifications`. Both were
   regenerated by `npm run edge:build`.
3. Deploy the admin panel, then set the rate on **Call billing**.
4. Release the app build with the Recharge page. Older builds keep working: the API
   still sends `presets_paise`/`min_paise`/`max_paise`, and refuses amounts that
   are not allowed.

Validate:

```sql
SELECT name FROM booking_app.schema_migrations WHERE name='20261103120000_call_wallet_billing.sql';
SELECT * FROM booking_app.call_billing_settings;            -- one row, rate NULL until set
SELECT count(*) FROM booking_app.call_wallets WHERE rate_paise_per_minute IS NOT NULL;  -- 0
SELECT relrowsecurity FROM pg_class WHERE oid='booking_app.call_billing_settings'::regclass;  -- true
```

Recovery: a failed run rolls back on its own. To undo it before any admin credit or
alert has been recorded, redeploy the previous builds, then:

```sql
BEGIN;
SET LOCAL search_path = booking_app, pg_catalog;
DELETE FROM booking_notification_events WHERE kind IN ('call_wallet_low','call_wallet_empty');
ALTER TABLE booking_notification_events DROP CONSTRAINT notification_event_source_check,
 DROP CONSTRAINT booking_notification_events_kind_check, DROP COLUMN wallet_details;
ALTER TABLE booking_notification_events
 ADD CONSTRAINT booking_notification_events_kind_check CHECK(kind IN ('created','cancelled','rescheduled','staff_cash_collected')),
 ADD CONSTRAINT notification_event_source_check CHECK(
  (kind IN ('created','cancelled','rescheduled') AND history_id IS NOT NULL AND booking_id IS NOT NULL
   AND business_id IS NOT NULL AND resource_id IS NOT NULL AND settlement_id IS NULL AND cash_details IS NULL)
  OR (kind='staff_cash_collected' AND settlement_id IS NOT NULL AND history_id IS NULL AND booking_id IS NULL
   AND business_id IS NULL AND resource_id IS NULL AND cash_details IS NOT NULL AND jsonb_typeof(cash_details)='object'));
ALTER TABLE call_wallet_ledger DROP COLUMN rate_paise_per_minute, DROP COLUMN admin_email,
 DROP COLUMN payment_mode, DROP COLUMN external_reference;
UPDATE call_wallets SET rate_paise_per_minute=500 WHERE rate_paise_per_minute IS NULL;
ALTER TABLE call_wallets ALTER COLUMN rate_paise_per_minute SET DEFAULT 500,
 ALTER COLUMN rate_paise_per_minute SET NOT NULL, DROP COLUMN plans_paise, DROP COLUMN custom_enabled,
 DROP COLUMN custom_above_paise, DROP COLUMN custom_max_paise, DROP COLUMN low_balance_paise,
 DROP COLUMN low_alert_sent, DROP COLUMN empty_alert_sent;
DROP TABLE call_billing_settings;
DELETE FROM schema_migrations WHERE name='20261103120000_call_wallet_billing.sql';
COMMIT;
```

## Migration `20261103140000_notification_kinds_combined.sql`

`20261102090000_subscription_fee_notifications.sql` and the billing migration each
recreate the push outbox CHECKs without the other's kind. This migration restores
one CHECK that allows all of them: booking, cash handover, `subscription_fee_due`,
`call_wallet_low` and `call_wallet_empty`. Apply it after both. It only replaces
the two CHECK constraints.

```sql
SELECT pg_get_constraintdef(oid) FROM pg_constraint
WHERE conname='booking_notification_events_kind_check';  -- lists all seven kinds
```

## Operations

- **Stuck `created`/`pending` order:** the owner can reopen the wallet page, or an
  operator can call `POST /v1/call-wallet/orders/:id/verify` as the owner. Either
  re-reads Cashfree and credits a paid order.
- **Manual credit or deduction:** use **Add balance** on the client's organization
  page in the admin panel. Do not edit the ledger by hand.

## Not done yet

- Pausing the call service automatically at zero balance (calls still connect
  and the balance can go below ₹0).
- GST on recharges.
- A scheduled job that re-checks Sarvam history for calls that missed charging.
