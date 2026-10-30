# Permanent business deletion

Owners open **Profile → Businesses → options (⋮) → Delete business**. The confirmation names the business, says it cannot be undone in the app, and requires **Delete permanently**. Staff cannot delete businesses.

Deletion removes the business row, its spaces/configuration, payment-routing defaults, staff assignments, website business/space settings and business-specific website images. It preserves the organization, other businesses, staff accounts, bank accounts and existing audit events. One `business.deleted` event remains as a receipt. Another business can reuse the deleted name.

Any booking, admission or financial history blocks deletion, including cancelled bookings, cancelled/deleted/expired admissions and reversed financial entries. Notification and slot-block history also block deletion. Active pending invitations must be cancelled or updated first. These refusals are HTTP 409 messages; no history or partial configuration is deleted. **Turn off business** remains the alternative for a business with history.

## API and concurrency

`DELETE /v1/businesses/<uuid>` accepts `{"version":4}` and returns HTTP 200 `{"id":"<uuid>"}`. It requires an authenticated active owner in the same organization. Invalid input is 400/422, foreign/unknown IDs are 404, staff are 403, and stale versions or linked history are 409. Both Nest and Edge route to the same service. Only this DELETE route reads JSON; legacy DELETE-body behavior remains unchanged.

The transaction locks the owner membership, organization ordering row (`FOR NO KEY UPDATE`), organization website rows, and business, in that order. Website writers lock the website before inventory, while the non-key organization lock allows ordinary foreign-key checks to finish. Booking/admission commits use the business lock, and remaining foreign keys protect records from unsafe concurrent removal. A newly introduced protected foreign-key reference causes the entire transaction to roll back with a readable conflict.

Only enumerated configuration tables are cleaned up, scoped to both business and organization. Website version is advanced and previews are invalidated if website settings were removed. Organization order revision advances once so stale order editors refresh. Other business positions are retained. Retrying a deleted ID succeeds only when the same organization has a `business.deleted` audit receipt; unknown or foreign IDs remain 404.

The Flutter repository continues sending the displayed version and invalidates retained catalogs. The Cubit prevents duplicate submissions, refreshes session state, and retains readable server errors. Deleting the last business preserves access to history, settings and Add business instead of forcing onboarding.

## Schema and release

**No new database migration is required.** This implementation does not read/write archive metadata or set the archived status. It works with the live pre-archival schema and with environments that already have archival columns. Do not apply `20261029082454_business_archival.sql` merely to enable permanent deletion. Those migration files remain in repository history for environments that previously used archival; this change does not drop existing columns, constraints, grants or historical archive data.

The existing booking, admissions, accounting, notifications and website tables must be available. Keep current private-schema privileges, RLS and authentication settings. The runtime needs its established SELECT/DELETE privileges on configuration tables and INSERT on audit events. No public RPC, credential or new exposed table is introduced.

1. From `backend`, run `npm run build`, `npm run edge:check`, and `npm run edge:build`.
2. Release the rebuilt `supabase/functions/booking-api/index.ts` through the established deployment process. Retain the current custom Auth verification and function settings. Health revision: `2026-10-30-permanent-business-deletion`.
3. Release the updated Flutter client so the permanent-deletion warning is visible. Existing clients send the compatible versioned DELETE payload; the updated API independently blocks historical businesses.
4. In a test organization, verify cancellation changes nothing; an unused draft and its configured space can be deleted; a second request is harmless; unknown/foreign IDs and staff fail; and any cancelled/past booking or admission still blocks deletion. Verify current business order and website settings refresh after deletion.

Do not automatically apply pending migrations on a live Nest startup. The project's migration ownership rule remains in effect.

## Verification and recovery

Focused backend tests cover actual row removal, linked setup cleanup, retained staff accounts, audit/retry behavior, name reuse, stale ordering, tenant/owner/version validation, cancelled historical records, independent income, pending invitations, foreign-key rollback and the pre-archival schema. Flutter tests cover irreversible wording, cancellation, confirmation, blocked server messages, duplicate/stale attempts, cache invalidation and narrow/desktop layouts.

```sh
# From backend/
node --import tsx --test --test-concurrency=1 test/business-deletion.test.ts test/edge.test.ts test/workspace.test.ts test/field-edge.test.ts
# From repository root
flutter test --no-pub --concurrency=1 test/business_removal_test.dart test/business_availability_test.dart test/route_guard_test.dart
```

An error before transaction commit rolls back every deletion. An interrupted response can be retried with the same ID/version: the deletion receipt identifies a completed request. Do not bypass history checks with cascading deletes.

For an operator-run deletion, save a consistent private recovery snapshot of the exact business, child configuration, organization ordering revision and affected website versions before mutation. After commit verify the business and its configuration are absent, exactly one deletion audit exists, protected history counts remain zero, and the other business rows are unchanged. Recovery requires an administrator and a reviewed transaction using that snapshot. Check name/ID reuse and newer website settings before restoring; never restore an entire older database over newer bookings or payments. There is no in-app restore action.

## Release verification — 30 October 2026

The user explicitly approved permanently deleting Edens Party Hall. Its one space and one website space setting were removed in a checked transaction after saving a private recovery snapshot. Final read-only verification found zero business/resource/website-space rows for that ID, zero booking/admission/financial history, one `business.deleted` audit receipt, and unchanged other businesses. The private snapshot and verification receipt are in `.local/releases/party-hall-permanent-deletion-2026-10-30T04-44-15.468Z/` (excluded from Git). The operator audit is explicitly labelled `operator:codex-user-authorized`, rather than attributing an administrator-run operation to an owner's login.

The deployed booking-api source matched the committed baseline before release and was saved in `.local/releases/permanent-business-deletion-backend-before/`. Backend version **77** is active; public health returns `2026-10-30-permanent-business-deletion`, and the pre-existing custom authentication setting is retained. No schema migration, grants, secrets or notification-function deployment was changed.

Backend build and Edge type checks pass. The focused deletion/Edge run passed 34 tests; workspace/Edge/legacy migration regressions passed 46 tests with the existing BUG-22 TODO. Flutter removal, availability and route checks passed 19 tests, and targeted analysis is clean. The rebuilt API bundle is verified against source. The Flutter confirmation/menu source is updated, but publishing the web client is pending because `railway status --json` returned `Unauthorized`; authenticate with `railway login` before releasing that client through the established Railway process.
