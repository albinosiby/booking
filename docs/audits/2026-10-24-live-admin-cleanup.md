# Live admin data diagnosis and completed cleanup

**Completed with the user's explicit QA-only approval on 24 October 2026 at 15:15 IST.** A fresh restricted read-only connection independently confirmed zero remaining candidate QA organizations. See the completion details below.

Confirmed project: `scwwkaywewecspsrskft`, as clarified by the user. No project switch was performed. The connected Supabase account cannot access this project, so verification used the existing restricted server connection in a repeatable-read, read-only transaction. Credentials were not printed. Railway CLI was not authenticated, so deployed runtime variables could not be inspected.

Before cleanup, the database contained 53 organizations and 59 memberships. The read-only preview identified 51 QA organizations, 55 memberships, 50 businesses, 13 bookings and 13 customers. Candidate names were exactly `Eden’s Area` (34), `Eden Booking QA` (13), and `QA first-module organization` (4), with owner addresses in the reserved `example.com` domain. No candidate membership used a different email domain. The genuine organizations `JK Group` and `RK Groups` were preserved.

These are persisted QA records in the actual database, not a hardcoded frontend dataset. Removing decorative content or refreshing the pages cannot remove those rows. Their presence explains why overview totals and organization/user lists include apparent dummy data. Live route rendering still needs comparison after cleanup and deployment; database verification alone does not prove the deployed panel's current configuration.

The [exact read-only candidate manifest](2026-10-24-live-qa-preview.json) freezes the organization IDs approved and removed. It remains a historical pre-cleanup snapshot. No broad name-pattern or email-domain deletion was used.

## Approved procedure

1. Confirm deletion of only the 51 candidate organization IDs and their test-owned dependent records, preserving JK Group, RK Groups and all their records. Keep Supabase Auth identities outside this operation unless separately identified and approved; memberships are application access records, not necessarily distinct Auth users.
2. Re-read the frozen candidates and check their owner domains, membership domains and related records against this preview. Stop on changed ownership, a real email domain, an unexpected cross-organization relationship or other scope drift.
3. Prepare and verify a current restorable backup/export of affected records and dependencies before deletion. Inventory the actual foreign-key graph, including bookings, payments, ledger entries, uploads, invitations, commands and support data. The counts above cover the main entities, not every dependent table.
4. Prepare a deletion plan in foreign-key order, restricted to frozen candidate IDs, and validate it against an isolated restored database. Do not disable constraints, truncate tables or alter the schema.
5. Apply the approved deletion transaction only after the backup and dependency review succeed. Roll back on mismatched affected counts. Leave real organizations and their linked rows untouched.
6. Compare overview and lists to database totals, refresh the admin routes, and verify real memberships and bookings still resolve. Reconcile totals to actual remaining rows rather than assuming historical counts are still current.

Recovery before commit is transaction rollback. Recovery after commit requires the verified export/backup and dependency-aware restoration, preserving identifiers; restoring an old whole-database snapshot could overwrite new real activity and must not be the default response.

## Local source safeguards

The admin now requires an explicit `BOOKING_API_BASE_URL`; it no longer silently falls back to a hardcoded project. The expected live value remains `https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api`. Overview, organizations, users and audit pages refresh every 30 seconds while visible and outside a focused form. Other routes retain manual refresh to protect editing. Existing no-store API reads and server authorization remain in place.

Validation: the admin production build passed and five focused API-origin, overview-total and redirect regressions passed. Earlier admin service authorization/query tests also passed. The approved cleanup was a live data deletion only; no deployment, grants, schema changes or migrations were performed.

## Completion and verification

The selected rows were backed up locally with directory permissions `0700` and file permissions `0600`:

`.local/backups/approved-qa-cleanup-0bW5f9/`

`backup.json` contains only the selected QA rows plus restoration metadata and baseline checksums, not a database password. `verification.json` records the backup checksum and a successful isolated deletion/restoration rehearsal with primary keys, unique constraints, standalone unique indexes and every foreign key enforced. Global Supabase Auth identities, platform admin records, notification devices, schema history and platform admin audit records were outside the deletion scope.

The first production attempt used the restricted application role, which could not delete an income-category row. The entire transaction rolled back. The successful attempt used the existing project's administrator connection without changing grants. It revalidated the frozen IDs, QA ownership, approved counts, schema inventory, constraints and absence of user triggers. Every non-target row across all 43 application tables matched its pre-deletion checksum before commit.

Removed dependent test data also included 35 booking payments, 35 finance events, 35 finance lines, 102 money accounts, 510 expense categories, 357 income categories, 83 resources, 51 locations, 51 legacy identity mappings, 9 invitations, 4 assignments, 24 booking commands, 24 booking history entries, 13 allocations and 348 organization-scoped audit events. These were selected by exact organization ownership or foreign-key dependency, not global table clearing.

After commit, an independent restricted read-only connection observed:

| Entity | Remaining |
| --- | ---: |
| Organizations | 2 — JK Group and RK Groups |
| Application memberships | 4, including 3 active |
| Businesses | 8 |
| Bookings | 7 |
| Customers | 6 |
| Candidate QA organizations | 0 |

The admin overview/organizations/users queries read these application tables. Refresh the deployed admin page to request the updated database data. Authenticated browser rendering remains unverified; no frontend deployment was required to remove the stored QA rows.

For recovery, use only the verified selected-row backup and its dependency order (`order` reversed for inserts), inside a reviewed transaction. Reinsert explicit original columns/identifiers through typed `json_populate_recordset`, verify every backed-up table's row count, and abort on identifier conflicts. Do not overwrite real rows, disable constraints or restore an older whole database over current real activity. Any production restoration requires a new explicit request. The one-off cleanup script refuses to run again after its 51-row precondition no longer holds.
