# Call agent wallet (prepaid, Cashfree recharge)

Owners prepay for the AI call agent. Each call is charged **₹5 per started
minute** (`call_wallets.rate_paise_per_minute`, default 500, can be changed per
organization). Owners recharge any amount from ₹100 to ₹50,000 on the
**Call booking** page.

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
| `GET /v1/call-wallet` | owner | Balance, rate, minutes left, recharge limits, last 20 entries |
| `GET /v1/call-wallet/transactions?offset=` | owner | Ledger pages of 50 |
| `POST /v1/call-wallet/orders` `{amount_paise}` | owner | Creates a Cashfree order and returns `payment_session_id` |
| `POST /v1/call-wallet/orders/:id/verify` | owner | Confirms with Cashfree and returns `status` plus the updated wallet |
| `POST /v1/call-wallet/payment-events` | HMAC | Events forwarded from the payout-backend |

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

## Operations

- **Stuck `created`/`pending` order:** the owner can reopen the wallet page, or an
  operator can call `POST /v1/call-wallet/orders/:id/verify` as the owner. Either
  re-reads Cashfree and credits a paid order.
- **Manual credit or refund:** insert an `adjustment`/`refund` ledger row and
  update `call_wallets.balance_paise` in the same transaction, using a unique
  `reference`.

## Not done yet

- Pausing the call service automatically at zero balance, and low-balance
  push notifications.
- An admin panel view for wallets, rates and manual adjustments.
- A scheduled job that re-checks Sarvam history for calls that missed charging.
