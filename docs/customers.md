# Customers and booking history

Open Profile → Customers. The directory searches the beginning of a phone number, ignoring spaces, parentheses, hyphens and `+`. Include a country code when that code was saved with the number. An empty search lists customers. Results load 50 phone groups per page; Load more customers continues the list.

Open a customer to see their accessible bookings, newest first, with date, start/end time, venue timezone, business/space, the name saved on the booking, booking status, payment status, total and any amount/refund due. Tap a booking for its existing detail screen. Load more bookings retrieves older history in pages of 50. Refresh rechecks current payment states.

Records with identical phone digits share a directory entry and booking history, without changing customer IDs or merging records. Shared numbers can therefore show bookings under different names; the screen explains this. Numbers saved with and without a country code remain distinct. History joins the canonical customer record, and retains each booking's original snapshot for display.

## Access and implementation

The existing workspace organization and booking permissions apply. Owners see their organization's customers. Staff need view_bookings, manage_bookings or collect_payments and see only customers with bookings in their assigned businesses/spaces; history applies the same scope to every booking. Foreign-organization and inaccessible customer UUIDs return 404. No direct Flutter database access, new RLS policy or Data API schema exposure is required.

The Customers feature uses typed models, a repository and list/detail Cubits. Searches debounce by 300 ms. Generation checks discard superseded responses; workspace access changes clear visible data and invalidate pending loads. Existing API read invalidation refreshes booking/payment history.

Both Nest and Edge expose authenticated GET endpoints:

- `/v1/bookings/customer-directory?q=98765&after=<opaque-phone-key>` returns `{items:[{id,name,phone,phone_key,record_count}],next:null|string}`.
- `/v1/bookings/customer-directory/:id?cursor=<opaque-cursor>` returns `{customer:{id,name,phone,record_count},currency,items:[BookingRecord],next:null|string}`. Each BookingRecord includes `local_start`, `local_end`, `price_snapshot.space_name`, `payment_status`, `balance_minor` and `refund_due_minor`.

Query inputs are validated, parameterized and capped. Cursors are server-generated; invalid history cursors fail with HTTP 400, malformed UUIDs with 422, missing authentication with 401 and missing permission with 403. Client cache behavior uses the existing account/session isolation.

## Supabase migration: user applies

Only the new index migration `backend/migrations/20261016113744_customer_directory.sql` is required for this feature. It adds two non-unique indexes for phone prefix search and customer history. No new tables, data backfill, extension, column or uniqueness constraint is needed. It does not apply any other pending migration.

1. Confirm the project and that the existing `booking_app` schema contains `customers`, `bookings` and `schema_migrations` from the workspace/booking migrations. In Supabase SQL Editor, run:

   ```sql
   SELECT to_regclass('booking_app.customers') AS customers,
          to_regclass('booking_app.bookings') AS bookings,
          to_regclass('booking_app.schema_migrations') AS migrations;
   ```

   All three must be non-null. Use an authorized database admin session. Preserve the normal database backup/recovery point before release.
2. Open `backend/manual-migrations/customer-directory-supabase.sql`, paste its complete contents into Supabase Dashboard → SQL Editor, and run it. The script sets the correct private-schema search path and records the exact migration filename in the application's ledger. Existing deployments with another schema must adapt that schema explicitly first.
3. The final queries should return **two index rows** and **one migration row**. Index creation is transactional and briefly locks writes; use a quiet period for large installations. A lock timeout aborts the transaction. If it fails, run `ROLLBACK;`, investigate the reported error and retry the complete script after resolving it. Do not insert the ledger row separately on failure.
4. Deploy the rebuilt `booking-api` Edge Function from `supabase/functions/booking-api/index.ts` with the existing custom authentication configuration, then rebuild/release the Flutter app. The migration alone does not add HTTP routes to the deployed function. Edge never applies migrations automatically. The standalone Nest runtime must have all its own required migrations applied before starting with `DATABASE_MIGRATE=false`.
5. Validate with an authorized account: search a known phone prefix, open the customer, compare booking date/time/space and payment state to existing booking details, then repeat with staff and confirm assigned-space restrictions.

This change prepares local source and the bundle only. It does not apply the migration, deploy the backend, build an APK or install on a phone.

## Recovery

Rolling back the application can leave these indexes safely in place. If a database rollback is required, run the following manually only after reverting the application version that expects the migration ledger entry:

```sql
BEGIN;
SET LOCAL lock_timeout = '10s';
DROP INDEX IF EXISTS booking_app.customers_phone_digits_idx;
DROP INDEX IF EXISTS booking_app.bookings_customer_history_idx;
DELETE FROM booking_app.schema_migrations
WHERE name = '20261016113744_customer_directory.sql';
COMMIT;
```

This removes only the two indexes and migration ledger entry. Customer, booking and payment rows remain intact. Do not roll back unrelated migrations.

## Verification

Backend tests cover formatted-phone grouping, history and payment state, tenant isolation, assigned-space access, directory pagination, invalid cursors and Edge dispatch/authentication. Flutter tests cover stale search responses, access changes, history paging, payment invalidation and the search-to-history flow at narrow width with enlarged text. Existing booking/payment tests cover collection/refund calculations reused by this endpoint.

Local verification on 16 October 2026: Nest compilation, Edge type checking and bundle generation passed; the full backend suite passed 121 tests before adding the history tie-breaker case, and the final focused customer run passed all 4 cases. Customers tests passed 3 cases, Profile/business navigation passed 8 cases, and router/access/architecture checks passed. Targeted Flutter analysis reported no issues. Full-library analysis reported four pre-existing style hints in `organization_edit_cubit.dart`; that separate feature was left untouched. No live database or deployed function was changed.
