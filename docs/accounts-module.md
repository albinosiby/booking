# Accounts module

## Website UPI details

Profile → Accounts & payments now includes an owner-only Website payment details card, with a UPI ID field and QR upload/preview/replace/remove actions. Explicit saving persists both through the accounts API; only raster images up to 1 MB are accepted. These are public checkout instructions, not bank credentials or verified receipt of money. See [UPI checkout and migration instructions](public-booking-website.md#upi-checkout-and-per-space-advance-collection) before deploying. The new migration is prepared but must be applied by the user; no live schema or payment records were changed.

Payments navigation now opens Accounts. The dashboard shows today's booking collections, selected-period income, expenses, net cash flow, outstanding booking dues, income by payment method, period growth, organization account balances, and recent activity. Business and space filters apply to activity and financial totals. Recorded account balances are always labeled as organization-wide.

## Entry points

- Accounts tab: dashboard, Add entry, transactions, report downloads and account settings.
- Profile → Account settings: cash opening balance, multiple bank accounts, primary bank, routing and transfers.
- Booking payment forms: receiving/paying account selector alongside existing split Cash, UPI, Card and Bank transfer methods.

## Financial behavior

The ledger uses immutable events and signed account movements in integer paise. Booking payment and ledger posting commit atomically. A unique booking-payment link and command keys prevent double counting on retries. Historical booking payments are migrated once: cash goes to Cash in hand and digital payments to Unassigned bank receipts, without guessing a historical bank. Transfer unassigned receipts to the bank that actually received them.

UPI, card and bank transfer are methods, not separate balances. Destination priority is an explicit payment account, a space mapping, a business mapping, then the primary bank. Without a configured bank, digital booking payments remain unassigned. Routing changes do not rewrite historical destinations. This is manual accounting: recording a card payment means the user is recording it as received, without a live settlement/bank feed.

Expense and extra-income entries require category, reason, occurrence time, scope and positive split lines. Scope can be shared organization, a business or a space. Shared entries are recorded once and excluded from business/space-only totals. Cash lines use the cash account; digital lines use an active bank. Expense sources and income destinations are individually selectable.

Transfers support cash deposits, withdrawals, bank-to-bank movements and allocation from unassigned receipts. The transfer form has no category field; the client submits the fixed category `Transfer` for compatibility with existing APIs. Income and expense categories remain required. Two opposing movements commit together; transfers never count as income or expenses. Manual income/expense/transfer entries can be reversed once by an owner, preserving original history and a correction reason. Booking refunds remain in the booking refund flow.

The first bank automatically becomes primary; primary switching is transactional and uniqueness is enforced by a partial index. A mapped/primary bank cannot be archived until its defaults are replaced. Archived accounts retain history. Bank opening balances are set at creation. Cash opening balance can be explicitly set once. Only movements at/after an account's opening time affect its recorded balance; older activity remains visible in reports. Opening balances are not income. There is no automatic bank reconciliation or payment collection.

## Periods and reports

Reports use the organization's reporting timezone, selected deterministically from its first location; each export records that timezone. Monthly/yearly presets support calendar periods; custom dates also support financial years. Collections follow receipt dates, independent of booking dates. Booking reports include bookings in the booking-date range or with receipts/refunds in the payment-date range. Tariff, received in the period, received through cutoff and outstanding are separate figures.

Month-to-date compares to matching elapsed dates in the preceding month, full months to full preceding months, and year-to-date to matching dates in the preceding year. Custom ranges compare to the immediately preceding equal-length range. Zero/nonpositive previous income shows no baseline instead of an invalid percentage.

PDF and Excel use a repeatable-read database snapshot. PDF includes organization, filters, summary, method totals, monthly totals, booking-level split payments, all account movements and organization opening/closing balances. Excel has Summary, Bookings, Account movements, Income and expenses, Monthly totals and Account balances sheets, with numeric currency values. Exports use all matching entries, independent of list pagination. A 20,000-record cap produces an explicit range-reduction error instead of truncating a report. The client opens the platform Save dialog and distinguishes cancellation from success. No public export URLs or report files are retained on the server.

## Architecture

Flutter lives under `lib/modules/accounts/`: immutable domain/screen models, repository contract/REST implementation, Cubits and screens/widgets. Screens invoke Cubit actions; persistence stays in repositories. Factories are registered in feature injection. Overview listens for finance and booking changes; Cubits reject stale responses and invalidate sensitive state on session/access changes. Uncertain writes retry their original command payload.

Backend: `src/accounts`, migration `003_accounts.sql`; existing booking payment writes call the shared ledger helper. Tables: `money_accounts`, `payment_routes`, `finance_events`, `finance_lines`. Composite foreign keys enforce organization and business/space relationships. Indexes cover organization/date, scoped dates, account movements and unique primary/mappings/payment origins.

## API

All routes require the existing Firebase bearer authentication and active membership.

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/v1/accounts/catalog` | Permissions, visible businesses/spaces, accounts and routes |
| GET | `/v1/accounts/overview` | Period totals, growth, today and balances |
| GET | `/v1/accounts/transactions` | Scoped transactions, 100 per page |
| POST | `/v1/accounts/banks` | Create bank with opening balance and command key |
| PATCH | `/v1/accounts/banks/:id` | Rename, make primary or archive |
| POST | `/v1/accounts/cash/opening` | Set cash opening balance once |
| POST | `/v1/accounts/routes` | Set/remove business or space payment mapping |
| POST | `/v1/accounts/entries` | Record income, expense or transfer |
| POST | `/v1/accounts/entries/:id/reverse` | Owner correction |
| GET | `/v1/accounts/reports/pdf` | Protected PDF export |
| GET | `/v1/accounts/reports/xlsx` | Protected Excel export |

Read filters: `from`, `until` (inclusive YYYY-MM-DD), optional `business_id`, `resource_id`, `account_id`, `kind`, `q`, `cursor`. Reports additionally require `type=monthly|yearly|bookings|cash_flow`. Ranges are bounded to ten years. Main report UI passes date/business/space filters.

Example expense request:

```json
{
  "command_key": "<uuid>",
  "kind": "expense",
  "business_id": "<business uuid>",
  "resource_id": "<space uuid>",
  "category": "Maintenance",
  "reason": "Court lighting repair",
  "reference": "Invoice 10",
  "occurred_at": "2026-10-15T10:00:00Z",
  "lines": [
    {"account_id": "<cash uuid>", "method": "cash", "amount_minor": 15000},
    {"account_id": "<bank uuid>", "method": "upi", "amount_minor": 50000}
  ]
}
```

Transfers use one source line and `to_account_id`; business/resource are null. Entry/account creation returns `{ "id": "<uuid>" }`. Typed validation/authorization/conflict failures use existing API error mapping. Bank account identifiers are optional last-four digits; no full account credentials are collected.

## Access and operations

Owners manage accounts, routes, transfers, reversals and organization balances. Staff use explicit `view_finance`, `record_expenses` and `collect_payments` permissions within assigned business/resource scopes. Staff never receive bank balances/opening amounts and cannot write shared organization entries. Exports enforce the same visibility. Mutations write audit events.

Run `npm ci && npm run build` in backend, then restart the API with its existing environment. Database startup applies the migration transactionally. Preserve the existing Auth emulator and its persisted accounts. Back up the closed embedded database before upgrading; a pre-Accounts backup path is recorded locally in `.local/accounts-backup-path.txt`. In hosted Postgres, use a database snapshot and normal migration rollout. Existing release signing, HTTPS/Firebase production checks and deployment configuration remain required.

Report dependencies are locked in package-lock.json. Noto Sans font and SIL Open Font License are bundled in backend/assets/fonts. The ExcelJS UUID dependency is overridden to its patched compatible version. The existing Firebase dependency tree retains separately tracked advisories; no unrelated major auth upgrade was made.
