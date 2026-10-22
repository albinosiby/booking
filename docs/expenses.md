# Expenses

Expenses is accessed from **Profile → Expenses**, not the Accounts action menu. Accounts continues to include expense movements in balances and cash-flow totals.

## Using the feature

- Switch Monthly/Yearly and choose a period. Tap a month in the yearly graph to see that month's full list.
- Tap a daily bar to highlight it and list only transactions on that day. The selected date and chart total appear below the graph; **Show all days** restores the full period. Category/source, business, space and account filters still apply. **Load more** stays within the selected day. The selection survives refresh and clears when changing month/year or switching to Yearly. Totals, graphs and PDF/Excel reports continue to cover the selected full month/year. Dates follow the organization timezone, including refunds and reversals on their recorded day.
- Filter by category, business, space or payment account. All categories includes archived and migrated historical categories.
- Download PDF or Excel for the selected full month/year and filters. Clear Category to export the whole period. Reports include category totals, each expense, payment splits, invoice counts and reversal identifiers; private invoice URLs are never exported.
- Add expense: category, reason, date/time, scope, optional reference and one or more payment sources. Each source has a method, account and amount; their sum is the expense total.
- Attach up to ten JPEG/PNG/WebP images or PDFs, up to 15 MiB each. Camera/photo selections are resized to 2000px and quality 85 by the platform image picker. Original files selected through Files remain intact.
- Money is recorded idempotently before uploading files. Retry invoices uses the existing expense ID. If leaving after a failed upload, open the saved expense and select the same file for its pending upload, or remove the pending file and attach a replacement.
- Owners can add, rename, archive and restore categories. Renaming retains category identity; archiving preserves reports and prevents new selections.

## Architecture and security

Flutter feature: `lib/modules/expenses/{models,repositories,cubit,screens,widgets}`. ExpensesCubit owns periods, filters, pagination and exports; ExpenseFormCubit owns creation and upload retries; ExpenseDetailCubit owns invoice viewing and recovery. Persistence, provider mapping, file selection, signed upload/download and cache policy stay in repositories. The existing models/repository/Cubit structure in Accounts is preserved.

The trusted hosted Booking API enforces organization membership, `view_finance`, `record_expenses` and staff space assignments before returning financial data. Only the owner or recording staff member with expense permission can attach files. Owner-only category management is checked server-side.

`expense_categories` and `expense_attachments` are in the private `booking_app` schema with RLS. Only the existing trusted `booking_api` role has server access; mobile Supabase roles have no direct table grants. Invoice bucket `expense-invoices` is private, restricted to approved MIME types and 15 MiB. The server issues upload grants, verifies object size/MIME/signature before marking ready, and issues five-minute signed viewing URLs after checking expense access. Built-in Supabase service credentials remain inside the function runtime. No service credential is included in Flutter.

Invoices are uploaded sequentially directly to Storage; they do not pass through the API's 3 MiB JSON request limit. Financial entry idempotency is independent of attachment IDs. Standard upload failures can be retried; partially prepared metadata is visible in expense details. Pending files count against the ten-file limit. Do not delete ready invoices or historical ledger entries to correct an expense; use the existing financial reversal flow.

Dates and report bounds use organization timezone on the server. Reversals reduce expenses on their recorded date, preserving original expense history. Transfers are excluded. Query bounds support the existing time indexes. Exports are bounded to 20,000 movements and one year; narrower periods can be used for larger ledgers. These are expense ledger reports, not tax returns.

## Deployment and verification

Canonical cloud migration is generated using `supabase migration new expenses` under `supabase/migrations`; backend test migration is the same schema without cloud-only schema/role/bucket provisioning. `backend/scripts/expenses-cloud-migration.mjs` applies the additive cloud migration transactionally, checks ledger count is unchanged and reports bucket privacy/RLS. It reads the existing database password in memory and never copies credentials.

Build the hosted function with `npm run edge:build` from backend, deploy the generated `supabase/functions/booking-api/index.ts`, preserving `verify_jwt=false`: the function verifies current tokens with Supabase Auth itself. Local API/emulators are not needed.

API: GET `/v1/expenses/catalog`, POST/PATCH `/v1/expenses/categories[/id]`, GET `/v1/expenses/overview`, GET/POST `/v1/expenses`, GET `/v1/expenses/:id`, GET `/v1/expenses/reports/pdf|xlsx`; POST `/:id/attachments`, POST `/:id/attachments/:file/complete`, GET `/:id/attachments/:file`, DELETE pending `/:id/attachments/:file`.

List/report queries: `from`, `until` (inclusive dates), optional `category_id`, `business_id`, `resource_id`, `account_id`, `q`; list `cursor` is an offset, 50 entries per page. Responses follow the existing API error contract and are HTTP `no-store`. Repositories retain encrypted authorized page snapshots; no signed URLs, invoice bytes or reports are written to page caches.

Existing infrastructure backups and monitoring cover the ledger. Storage objects require separate backup/retention arrangements before relying on invoices as the only copy of originals. No automated invoice deletion is enabled.
