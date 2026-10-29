# Remove a configured business

Owners can open **Profile → Businesses → business options (⋮) → Remove business** on mobile or desktop. The confirmation names the business and explains that booking, payment and report history stays available. Draft, active and turned-off businesses can be removed. Staff cannot remove businesses.

Removal archives the business; it does not delete its resources, configuration, customers, bookings, admissions, payments, allocations or ledger. Businesses disappear from setup, Home and new-booking choices, website settings and the public website. Historical booking and finance filters retain a **(removed)** label. Existing staff assignments continue to authorize historical records. Another business may reuse the removed name with a new ID. Removing the last business leaves the owner able to open history, accounts and settings.

Removal is blocked with a readable message if any non-cancelled booking has not ended (including an ongoing booking), or an admission is active/upcoming, including memberships. Finish/cancel the bookings and resolve admissions through their normal workflows first. Cancellation does not erase payments or refunds due. Expired/completed/cancelled/deleted admissions do not block removal by themselves. There is no automatic cancellation, refund or restore button in this feature.

## Architecture and API

The Flutter screen captures a typed removal action containing the displayed ID, name and version, confirms it, and calls BusinessManagementCubit → BusinessRepository → WorkspaceRepository → REST. A synchronous lock prevents duplicate submissions. Existing session reconciliation refreshes the workspace after success or uncertain outcomes; transport writes invalidate retained reads. Blocked requests retain the business and surface the server message. Permission and stale-version checks run again after confirmation.

`DELETE /v1/businesses/<uuid>` requires a verified authenticated active owner in that organization and JSON:

```json
{"version":3}
```

Success: HTTP 200, `{"id":"<uuid>"}`. Repeating removal of an already archived business succeeds without another version change or audit event. Wrong-organization/missing IDs return 404; staff get 403; malformed UUIDs/versions return 400/422 according to the API adapter; stale versions and unresolved bookings/admissions return 409. Both Nest and Edge routes support the operation, including parsing JSON DELETE bodies.

The server locks owner membership, the organization ordering row, and then the business inside one transaction. Booking/admission/public-website commits use the same business row lock, so the blocker check cannot race with a new booking or enrollment. Archive increments business version and organization business-order revision and records `business.archived` in the existing audit log. Normal configuration/activation routes cannot edit an archived business. Read/history/payment endpoints retain ordinary tenant and staff scope checks.

## Storage and prerequisites

Migration: `20261029082454_business_archival.sql`.

- Hosted Supabase: `supabase/migrations/20261029082454_business_archival.sql` (transaction, private-schema search path and migration ledger entry included).
- Nest/local schema: `backend/migrations/20261029082454_business_archival.sql` (same schema changes; the established runner supplies transaction and ledger entry).

It adds nullable `businesses.archived_at` and `archived_by`, permits status `archived`, and requires both metadata fields exactly when archived. A partial unique `(organization_id,name)` index enforces names for current businesses and allows reuse after removal. Existing rows stay unchanged. Foreign keys, RLS, grants, views and historical IDs are retained. Existing business/time and admission scope indexes support blocker queries; no new public tables, RPCs or secrets are introduced.

Before applying, verify the intended project/environment; take a database backup containing the private `booking_app` schema, and save baseline business, booking, admission, payment and ledger counts. Use an administrator connection with certificate-verified TLS. The schema must already have `organizations.business_order_revision`, `businesses.version/display_order`, `bookings.ends_at`, the current `admission_balances` view (including membership/deletion support), `audit_events` and `schema_migrations`. `booking_api` must have its existing table-level business SELECT/UPDATE grants. The old `businesses_status_check` and `businesses_organization_id_name_key` constraints must exist; partial installations need review first.

## Exact hosted release steps — user applies the migration

No live migration or deployment is performed by implementation/testing. Do not run a blanket migration push, and do not start a live Nest server with automatic migrations enabled. Use `DATABASE_MIGRATE=false` for deployments where migrations are managed separately.

1. Back up the target database and record the counts below. Set `BOOKING_MIGRATION_DATABASE_URL` in your own shell to the intended administrator connection; do not commit or paste it into documentation. Include `sslmode=verify-full` and your trusted CA configuration.
2. From the repository root, inspect the exact SQL and run these read-only preflight checks through your SQL editor or `psql`:

```sql
SELECT current_database(), current_user;
SELECT name FROM booking_app.schema_migrations
 WHERE name='20261029082454_business_archival.sql'; -- must return no rows
SELECT conname,pg_get_constraintdef(oid)
 FROM pg_constraint WHERE conrelid='booking_app.businesses'::regclass
 AND conname IN ('businesses_status_check','businesses_organization_id_name_key');
-- Both old constraints must exist. Neither new metadata column should exist yet.
SELECT column_name FROM information_schema.columns
 WHERE table_schema='booking_app' AND table_name='businesses'
 AND column_name IN ('archived_at','archived_by');
SELECT to_regclass('booking_app.admission_balances'); -- must be non-null
SELECT 'businesses' AS entity,count(*) FROM booking_app.businesses
 UNION ALL SELECT 'bookings',count(*) FROM booking_app.bookings
 UNION ALL SELECT 'admissions',count(*) FROM booking_app.admissions
 UNION ALL SELECT 'booking_payments',count(*) FROM booking_app.booking_payments
 UNION ALL SELECT 'admission_payments',count(*) FROM booking_app.admission_payments
 UNION ALL SELECT 'finance_events',count(*) FROM booking_app.finance_events;
```

3. During a quiet maintenance window, apply **only** this file (or paste the entire file into the target project's SQL editor):

```sh
psql "$BOOKING_MIGRATION_DATABASE_URL" -X --set ON_ERROR_STOP=1 --file supabase/migrations/20261029082454_business_archival.sql
```

4. Validate before deploying the API/client:

```sql
SELECT name FROM booking_app.schema_migrations
 WHERE name='20261029082454_business_archival.sql'; -- exactly one row
SELECT status,count(*) FROM booking_app.businesses GROUP BY status;
SELECT count(*) AS invalid_archive_metadata FROM booking_app.businesses
 WHERE (status='archived' AND (archived_at IS NULL OR archived_by IS NULL OR length(archived_by)=0))
 OR (status<>'archived' AND (archived_at IS NOT NULL OR archived_by IS NOT NULL)); -- zero
SELECT indexdef FROM pg_indexes WHERE schemaname='booking_app'
 AND indexname='businesses_current_name_idx'; -- UNIQUE, WHERE status <> archived
SELECT relrowsecurity,relacl FROM pg_class
 WHERE oid='booking_app.businesses'::regclass; -- compare with backup
SELECT has_column_privilege('booking_api','booking_app.businesses','archived_at','SELECT') AS api_read,
       has_column_privilege('booking_api','booking_app.businesses','archived_at','UPDATE') AS api_write;
-- Both true. Re-run the baseline count query: every count must be unchanged.
```

5. Build/check the API from `backend`: `npm run build`, `npm run edge:check`, `npm run edge:build`. Release the generated `booking-api` function through the established deployment process, retaining its authentication settings. Health reports revision `2026-10-29-business-archival`. Then release the Flutter client. The SQL file must be applied before any removal request.
6. In a test organization, verify cancelling a confirmation changes nothing; an empty draft can be removed; future/ongoing bookings and active admissions block removal; historical bookings, payments and reports remain readable. Confirm staff cannot remove a business. Avoid using a real business for a destructive smoke test.

## Recovery

The hosted migration is transactional and has a 10-second lock timeout. If it fails before COMMIT, its changes and ledger entry roll back; resolve the cause before retrying the same file. Check the ledger and constraints after any interrupted connection before retrying.

If application deployment fails after the migration, disable removal/revert the new client and prefer a forward fix. Keep the additive metadata and archive constraint in place. Older APIs do not filter archived rows consistently; **do not route production traffic to an older API after businesses have been archived** without reviewing compatibility. Do not drop metadata or restore a backup over newer bookings/payments.

If a business was removed accidentally, an administrator can prepare a targeted transaction after checking its saved configuration, blockers, any current business reusing its name, and the removal audit event. Restore it to `paused`, clear both archive metadata fields, increment business version and organization ordering revision, and record a recovery audit event. Re-enable bookings only through the normal owner validation flow. Recovery is a separate, explicitly authorized operation; this implementation does not execute it.

## Verification

Focused tests cover production migration row/grant/RLS preservation, metadata constraints, name reuse, owner/staff/tenant boundaries, invalid/stale versions, duplicate retries, ordering after removal, future/ongoing bookings, active/upcoming admissions, blocked stale booking/enrollment requests, unchanged historical financial rows and post-removal balance collection. Flutter tests cover repository DELETE payload/cache invalidation, Cubit failure/duplicate/stale/permission handling, mobile/desktop confirmations, draft removal, cancellation and last-business history navigation. Run these alongside existing workspace, booking, admission, account, website and route regressions before release.

```sh
# Repository root
flutter test --no-pub --concurrency=1 test/business_removal_test.dart test/business_availability_test.dart test/business_management_test.dart test/business_order_sync_test.dart test/business_details_test.dart test/route_guard_test.dart
# From backend/
node --import tsx --test --test-concurrency=1 test/business-archival.test.ts test/business-archival-migration.test.ts test/edge.test.ts test/field-edge.test.ts
```

Verified on 29 October 2026: the removal/migration backend tests pass; final Edge checks pass (52 passed, one existing BUG-22 TODO); the removal/navigation/team Flutter run passes (48 passed, four existing router skips); the existing business-management/detail/ordering/availability tests pass (29 passed). Backend build, Edge type check, generated-bundle freshness and targeted Flutter analysis pass. Broader booking, admission, account, website, team-email and Sarvam regression tests passed; two intermediate Edge failures were resolved by preserving legacy DELETE-body behavior and rebuilding the bundle. Project-wide Flutter analysis still reports existing warnings/info in unrelated field-test files. No live schema, business data, deployment or device installation was changed.
