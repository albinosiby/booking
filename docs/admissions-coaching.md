# Plans & Coaching

## Workspace flow

Open **Profile → Plans & Coaching**. Search appears first, followed by the
**Plans** (swimming/court access packages) and **Coaching** (taught classes) tabs.
Each tab directly lists enrolled students across all permitted businesses and
spaces. Use the app bar's **Filter admissions** button to narrow business,
pool/court and status. **Apply filters** commits changes together; **Cancel**
leaves the current list unchanged; **Clear filters** restores all locations and
statuses while preserving search. Applied filters appear as removable chips.
Search by name, phone or admission number and submit the search to update results.
**Load more students** fetches additional enrollments. Students from previous,
disabled or removed packages remain included. Student cards open the existing
attendance, payment and renewal details.

The **New admission** floating action button opens **New plan admission** or
**New coaching admission** according to the current tab. It preserves any
selected business and space. **Plan & schedule → Admission type** lets staff
choose **Plan** or **Coaching** before selecting a matching plan. Changing type
preserves customer, location and schedule entries and clears the incompatible
plan selection. The selector remains available when a category has no plans;
renewals keep their original admission type. Embedded booking controls retain
their existing layout. Returning from forms/details refreshes the roster while
retaining the tab and filters. The two tabs remember their own location and
status filters, with a shared search query. Coaches continue to use
**My classes** for their daily roster and attendance.

The Flutter screen is owned by `AdmissionCubit`; typed `AdmissionOverview` and
`AdmissionRoster` models hold selection and per-kind loading, errors, rows and
cursors. Plans uses separate swimming and court requests, while Coaching uses
one coaching request. This retains every kind's pagination across locations.
Late responses are discarded after
scope/selection changes; access failures clear protected data. Student rows
are built lazily, and retained rows remain visible during refresh failures.

The existing `GET /v1/admissions` accepts `resource_id` and `plan_id`
(UUIDs), and `previous_plans=true` for enrollments without a currently enabled
matching plan in that space. These combine with `business_id`, `kind`, `q`,
`status` and `cursor` before the 50-row pagination limit. Membership and staff
resource restrictions apply to every query. The existing admission scope index
supports business/space filtering. This student list omits plan partitioning and
includes historical plans through the ordinary list response. The redesign
requires no API, database or environment changes against the current API.

**Release:** rebuild/release the Flutter web and native clients for this redesign.
For installations upgrading from before automatic attendance, deploy the updated
API before releasing the client; older APIs
reject the new strict query parameters and require a manually supplied check-in
time. Run backend `npm run build`,
`npm run edge:check`, `npm run edge:build`, then deploy the generated existing
`booking-api` function through the normal release process. No live deployment,
database change or device installation is performed by this UI change. The
prerequisite admissions migration described below remains unchanged.

Verification: `flutter analyze`; Flutter tests `admission_overview_test.dart`,
`admission_type_selector_test.dart`, `admissions_test.dart`,
`web_layout_admissions_test.dart`, `court_coaching_test.dart`,
`pool_booking_options_test.dart`, `coach_classes_test.dart`; backend tests
`admissions.test.ts`, `court-admissions.test.ts`, `coach-classes.test.ts`.

## What is included

Profile → Plans & Coaching manages customer purchases of configured swimming and coaching plans for pool businesses, and access/coaching plans for court businesses (see [Court coaching](court-coaching.md)). The booking form links to the same admission form. Select a customer, business, pool or court and plan, activation date, attendance mode, and optional split payments. Review the calculated expiry and every fixed session before confirming.

- **Fixed weekly schedule:** selected weekdays/time reserve the complete allowance, up to 1,000 sessions, within validity. Each non-cancelled session uses one unit after its end, even when absent or unmarked. Present/Absent records actual attendance separately. An insufficient schedule or a full interval rejects the entire purchase; it never silently skips a day.
- **Flexible access plans:** no standing reservation. Tap **Mark present** on arrival; there is no date/time picker. The server uses the current minute in the admission's business timezone and the saved visit duration. The visit reserves capacity and consumes one unit per location-local attendance date. Multiple non-overlapping visits on the same date use one unit.
- **Coaching attendance:** scheduled-session **Present** uses that session's original time. Flexible students appear on coach Home and My classes before a reserved visit exists. **Mark present** joins the unique running class for the same plan, pool/court and duration, preserving its exact interval and seat limit. **Start class & mark present** starts an eligible class at server time with its first student when none is running; the saved attendance time is shown separately. Join-only requests from the admission detail retain their existing behaviour when no class is running. If multiple matching intervals are running, the request is rejected. Existing expiry, opening-hours, coach-conflict and capacity checks still apply. Flexible coaching retains its day-based allowance rule. See [Flexible coaching attendance](flexible-coaching-attendance.md).
- **Coaching:** configured class duration, seats, pool and snapshotted coach apply. Matching plan/pool/start/end reservations share a class capacity. Independent overlapping classes cannot use the same coach. Calendar displays each student's reservation so attendance can be marked individually. Dedicated named batches and bulk roster attendance are not included.
- **Completed:** all units used. The final flexible visit remains valid until its end; repeat visits on that final attendance date remain subject to capacity and expiry. No later-date attendance can be added.
- **Expired:** the location-local date is later than the inclusive expiry date. Unused units remain visible but cannot be used. Visits must end within validity. Existing day/month/year expiry calculations are retained, including clamping month/year boundaries.
- **Renew:** completed/expired admissions can be renewed once. Renewal creates a separate admission using the current enabled plan and pricing, preserving the customer and previous history. No unused balance or money is automatically transferred. Each renewed admission can itself be renewed later.
- **Corrections:** owners can change recorded attendance with a reason. Clearing flexible attendance restores its date credit only when no other present visit remains on that date. Fixed usage is independent of attendance. Owners can restore credit for an ended fixed session, then schedule one makeup session before expiry; the original stays in history. Future fixed sessions can be cancelled or rescheduled with a reason and fresh capacity checks.
- **Cancellation:** future reservations are cancelled/released. Historical attendance and payment dues remain. Refunds are explicit owner-recorded transactions, never automatic.

All reservation views and availability use the existing booking inventory. Admission sessions have a zero visit price: the plan is charged once on the admission. Collections/refunds post into the existing money accounts and financial reports as `admission_collection` / `admission_refund`. Dues can be collected after completion or expiry. No payment gateway or customer self-service login is introduced.

## Permissions and architecture

Permissions are explicit: `view_bookings` for reading, `manage_subscriptions` for enrollment/renewal/schedule management, `mark_attendance` for check-in/attendance, and `collect_payments` for collections. Ordinary booking creation remains `manage_bookings`. The legacy `manage_attendance` marker is accepted as an attendance grant for older clients. Owners can refund and correct attendance. All reads/writes check current organization membership and assigned business/resource scope. Coach status alone permits My classes visibility; marking their own current classes additionally requires attendance permission. Coach status, resource assignments and coaching plans are managed inside staff details. See [Unified staff management](team-coaches.md), including the required permission data migration.

Flutter feature: `lib/modules/admissions/{models,repositories,cubit,screens,widgets}`. Screens call Cubit commands; repositories own HTTP mapping. Session/access changes clear protected state and invalidate in-flight results. Unknown write outcomes retain the original command key and lock editing until retry resolves them. Calendar uses current admission/session versions for attendance.

API: `backend/src/admissions`. Both Nest and hosted Edge route adapters expose:

| Method | Route | Purpose |
|---|---|---|
| GET | `/v1/admissions/catalog` | Permitted pools, enabled plans, permissions |
| GET | `/v1/admissions/customers?q=987` | Scoped existing-customer search |
| POST | `/v1/admissions/preview` | Authoritative price, expiry, sessions, review token |
| POST | `/v1/admissions` | Atomic purchase with review token and command key |
| GET | `/v1/admissions` | Kind, business, status, customer search; 50-row pages |
| GET | `/v1/admissions/:id` | Balance, visits, payments, history, renewal link |
| POST | `/v1/admissions/:id/check-ins` | Atomic flexible visit and attendance |
| POST | `/v1/admissions/:id/sessions/:visitId/attendance` | Present/Absent/Unmarked |
| POST | `/v1/admissions/:id/sessions/:visitId/change` | Cancel/reschedule/waive fixed session |
| POST | `/v1/admissions/:id/payments` | Collections/refunds |
| POST | `/v1/admissions/:id/cancel` | Cancel admission |

Automatic check-in sends only `{ "command_key": "<uuid>", "version": 1 }` to
`POST /v1/admissions/:id/check-ins`. Clock resolution happens inside the existing
business-locked, idempotent command, after permissions are checked. Replaying the
same command returns the original visit even if the clock has advanced. The API
still accepts the legacy complete `date`, `time`, `duration_minutes` payload;
partial clock payloads are rejected. The Flutter Cubit refreshes the admission
before submission, prevents repeated taps, and retains the exact version/key for
uncertain retries. A failed refresh never records attendance using stale data.

Verify with `flutter test test/automatic_attendance_test.dart` and the backend
admissions, court-admissions and coach-classes tests. No database migration is
required for automatic attendance; deploy the generated API before the app.

Creation body includes `business_id`, `resource_id`, `plan_id`, `starts_on`, `mode`, `weekdays`, `time`, `duration_minutes`, `customer`, `payments`, nullable `renewed_from`, plus `preview_token` and `command_key`. Preview accepts the same body without token/key. Customer and payment formats match ordinary bookings. Mutations use UUID command keys and optimistic versions. Errors use the existing 401/403, 404, 409 and validation envelopes.

The `admission_balances` view calculates fixed usage from ended sessions and flexible usage from distinct present dates. No cron job or live schema mutation is required for expiry/completion. Availability ignores future allocations on closed admissions while retaining occupancy of already-started visits. Tenant-scoped foreign keys prevent attaching visits to another admission's customer or pool. Business row locks serialize purchases/check-ins with ordinary booking capacity changes.

## Membership-only plans and retained deletions

In the business configuration, open **Plans** (pool) or **Plans & coaching**
(court) and edit a plan. **Track sessions & attendance** defaults to on for
existing plans. Turn it off for a membership that needs only customer details,
activation/expiry, fees and renewal. This is set separately for every plan,
including coaching. Membership-only plans create no classes, attendance credits
or inventory reservations. Their enrollment form hides schedule and attendance
inputs; validity and payment collection remain available.

The saved purchase snapshots its mode and price. Changing the plan toggle does
not change existing purchases or their attendance history. A renewal uses the
current plan settings and creates a new linked term. Old unpaid fees remain on
the old term; they are not transferred or silently forgiven.

Home shows **Expired members · action needed** for memberships whose inclusive
expiry date has passed in the business timezone, including tracked plans whose
attendance is already completed. **Renew** opens the renewal form, **Collect
amount** opens payment collection, and **View membership** opens the details.
Renewed, cancelled and deleted terms leave this queue. The queue loads 50 rows at
a time, supports retry/refresh and refreshes on return, on app resume and once a
minute while foregrounded. Business/resource permissions still apply. Amounts
and the collection action are shown only with the relevant financial permission.

From membership details, staff with **manage subscriptions** can choose
**Delete membership**, enter a reason and confirm. This removes the membership
from current lists and Home. The database retains the membership, customer,
payments, dues and audit history with deletion actor/time/reason. Future sessions
are cancelled and their reservations released; a running session must finish
before deletion. Historical attendance stays read-only. This action does not
delete the customer, refund money or write off a debt. Use the **Deleted** status
filter to reopen retained details and collect an outstanding amount later.

The API adds:

| Method | Route | Body/query | Purpose |
|---|---|---|---|
| GET | `/v1/admissions/expired` | Optional `cursor` | Scoped expiry queue, 50 rows per page |
| POST | `/v1/admissions/:id/delete` | `command_key` UUID, current `version`, `reason` (2–500 characters) | Idempotent logical deletion |

Plan configuration accepts `track_attendance: false`. Enrollment preview/create
use `mode: "membership"`, `weekdays: []`; the existing API still requires the
legacy `time` and `duration_minutes` fields, but this mode does not schedule or
reserve them. The server rejects a mode that disagrees with current plan
configuration. Membership allowance/used/remaining are zero. A deleted term has
status `deleted`; ordinary lists omit it unless `status=deleted` is requested.
Deletion uses the existing tenant/business lock, permission checks, optimistic
version, command-key retry mechanism and audit transaction. Payments retain
their existing accounting path.

### User-applied membership migration

Production status, 26 October 2026: after explicit user approval overriding the
earlier no-live-migrations restriction for this file only,
`20261026042821_membership_only_plans.sql` was applied to project
**scwwkaywewecspsrskft** through the existing terminal database credentials over
certificate-verified TLS. All existing records were unchanged, the migration
marker is present, the expiry index is valid and private view/runtime grants
passed validation. No API or client deployment was performed.

A private logical snapshot of the nine affected admissions, customer, booking
and finance tables, pre-change schema definitions and grants, migration hash and
verification receipts is stored under
`.local/releases/membership-only-2026-10-26T05-40-51.076Z/`. This is an affected-data
snapshot, not a full project/Auth backup. The directory is owner-only (0700), its
files are owner-only (0600), and it is ignored by Git. The runner
`backend/scripts/apply-membership-only-migration.mjs` defaults to a read-only
preflight or verification; `--apply` requires explicit production authorization.
It backs up before mutation, validates inside the transaction and checks the
committed state again. Repeated execution detects the existing migration marker.

The steps below document application to an environment where this migration is
still absent. Do not reapply it to the confirmed production project. Deploy the
updated API next, then release the updated Flutter client through the separately
authorized release process.

If SQL Editor reports `relation "admissions" does not exist`, check whether the
local backend copy was pasted: that copy uses unqualified names supplied by its
local runner's search path. The production Supabase file below explicitly uses
`booking_app.admissions`. Confirm the prerequisite with this read-only query:

```sql
SELECT to_regclass('booking_app.admissions') AS admissions_table;
```

A non-null result means the table exists: use the entire production file below.
A null result means the prerequisite table is absent in the selected project;
verify the project and original admissions migration before continuing.

1. Confirm project **scwwkaywewecspsrskft** and the private **booking_app** schema.
   Ensure prior repository migrations, including admissions, court admissions
   and financial accounts, are applied. PostgreSQL 15+, `booking_api`, the current
   `admission_balances` view and `booking_app.schema_migrations` are required.
2. Take a restorable database backup including admissions, bookings, allocations,
   customer/payment/history/finance tables and grants. Save deployed API/client
   versions. Use a short maintenance window for migration and API release.
3. In that project's Supabase SQL Editor, run the **entire** file
   `supabase/migrations/20261026042821_membership_only_plans.sql` once. Do not run
   the backend copy against production. All production object names are
   explicitly qualified with `booking_app`; do not substitute `public`.
4. The migration is transactional with a 10-second lock timeout. On failure,
   retain the error, confirm rollback and absent marker, fix the prerequisite
   issue and retry the full file. Do not remove constraints to force completion.
5. Run the read-only validation below. Then build the backend and generated Edge
   function (`npm run build`, `npm run edge:check`, `npm run edge:build` in
   `backend`) and use the normal API/client release process.

```sql
SELECT name, applied_at FROM booking_app.schema_migrations
WHERE name='20261026042821_membership_only_plans.sql';
-- One row after successful application.

SELECT column_name, data_type FROM information_schema.columns
WHERE table_schema='booking_app' AND table_name='admissions'
AND column_name IN ('deleted_at','deleted_by','deletion_reason');
-- Three columns.

SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
WHERE conrelid='booking_app.admissions'::regclass
AND conname IN ('admissions_mode_check','admissions_allowance_check',
               'admissions_deletion_metadata_check');
-- Membership mode requires allowance=0; tracked modes require 1..10000.

SELECT reloptions FROM pg_class
WHERE oid='booking_app.admission_balances'::regclass;
-- Must include security_invoker=true.

SELECT role_name,
 has_table_privilege(role_name,'booking_app.admission_balances','SELECT') AS can_read
FROM (VALUES ('anon'),('authenticated'),('booking_api')) roles(role_name);
-- false, false, true respectively.

SELECT to_regclass('booking_app.admissions_expiry_attention_idx');
-- Non-null.

SELECT count(*) AS invalid_memberships FROM booking_app.admission_balances
WHERE (mode='membership' AND (allowance<>0 OR used<>0 OR remaining<>0))
OR (deleted_at IS NOT NULL AND status<>'deleted');
-- Zero.
```

Smoke-test a disposable membership-only plan and a tracked plan: enroll, review
expiry, renew, collect part payment, delete with a reason and verify the Deleted
filter, history, remaining dues and Accounts totals. Confirm future tracked
reservations release on deletion and restricted staff cannot delete or see
financial amounts without permission. Test date boundaries only in isolation.

**Recovery:** a pre-COMMIT error rolls back the transaction. After successful
application, retain the additive schema if reverting the client. Once membership
mode or deletion records exist, do not redeploy an older API that interprets zero
allowance as completion or permits attendance on deleted terms. Pause affected
writes and ship a forward fix. Do not convert memberships to flexible mode with
invented allowance, clear deletion metadata or remove ledger/history records.
A full backup restore requires a separate recovery decision accounting for all
payments and bookings created since the backup.

Local verification commands for this addition:

```sh
flutter test --concurrency=1 test/membership_only_test.dart test/home_dashboard_test.dart test/router_configuration_test.dart
flutter analyze
cd backend
node --import tsx --test --test-concurrency=1 test/membership-only.test.ts test/membership-migration.test.ts test/admissions.test.ts test/court-admissions.test.ts test/pool.test.ts test/court.test.ts
npm run build
npm run edge:check
npm run edge:build
```

The backend tests use isolated in-memory PostgreSQL and include membership-only
pool/court enrollment, inclusive expiry, linked renewal, retained debt,
post-deletion collection, tenant/permission/version guards, original tracking
snapshots, released future reservations and production migration privileges.
The Flutter tests cover configuration serialization, enrollment presentation,
deletion history/collection, Home action navigation at phone/desktop widths and
expiry-feed refresh/access revocation.

Verified locally on 26 October 2026: all 56 focused backend tests and all seven
new membership tests passed. The seven Home/router regression tests also passed.
Flutter analysis reported no issues; the backend build, Edge type check and
generated Edge builds succeeded. These checks used isolated data and preceded
the separately approved production migration recorded above. No API or client
deployment was performed.

## Original admissions production migration

**This is the original prerequisite migration. Its marker was confirmed in the
live database on 26 October 2026. Do not reapply it there; the instructions below
are for an environment where the original admissions schema is absent.**

### Prerequisites

1. Confirm the existing `booking` project and `booking_app` private schema; do not create another project/schema.
2. Ensure all previous repository migrations are applied, including accounts, customer directory, business order, expenses, bank account numbers and message templates. This migration depends on the existing `bookings`, `customers`, `finance_events`, `schema_migrations`, and `booking_api` role.
3. Use PostgreSQL 15+ (the view uses `security_invoker`). Keep `booking_app` out of exposed Data API schemas.
4. Take a restorable database backup, including `booking_app` tables and grants. Save the current deployed Edge function/client versions.
5. Schedule a short write-maintenance window for migration and API deployment. `lock_timeout` is 10 seconds; a busy database aborts the transaction rather than waiting indefinitely.

### Apply

1. Open Supabase Dashboard → the existing project → SQL Editor.
2. Run the **entire** `supabase/migrations/20261020120000_admissions.sql` file once as the project database administrator. It contains BEGIN/COMMIT, private role grants/RLS, schema additions and the application migration marker. Do not run the backend copy against production; that copy is for isolated/local migration runners.
3. If it fails, preserve the error and verify the transaction rolled back before fixing/retrying. Do not add `IF NOT EXISTS` to hide a partial schema mismatch.
4. Run the validation queries below. They should show one migration marker, three private tables with RLS enabled, the view, and no public client access.
5. From `backend`, run `npm run build`, `npm run edge:check`, `npm run edge:build`.
6. Deploy the generated `supabase/functions/booking-api/index.ts` to the existing `booking-api` Edge Function. Preserve secrets and the existing custom authentication / `verify_jwt=false` setup. No function deployment is performed automatically.
7. Release the updated Flutter client, grant staff attendance permission where needed, and run the smoke checks below. Older clients do not understand admission visits; update operating devices together.

### Validation SQL (read-only)

```sql
SELECT name, applied_at FROM booking_app.schema_migrations
WHERE name='20261020120000_admissions.sql';

SELECT c.relname,c.relrowsecurity
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='booking_app'
AND c.relname IN ('admissions','admission_payments','admission_history');

SELECT to_regclass('booking_app.admission_balances') AS balances_view;

SELECT role_name,object_name,
 has_table_privilege(role_name,'booking_app.'||object_name,'SELECT') AS can_select
FROM (VALUES ('anon'),('authenticated'),('booking_api')) r(role_name)
CROSS JOIN (VALUES ('admissions'),('admission_payments'),('admission_history'),('admission_balances')) t(object_name)
ORDER BY role_name,object_name;
-- anon/authenticated false; booking_api true for all four.

SELECT count(*) AS invalid_balances FROM booking_app.admission_balances
WHERE used<0 OR remaining<0 OR used>allowance OR expires_on<starts_on;
-- Expect zero.

SELECT count(*) AS mismatched_visits
FROM booking_app.bookings b JOIN booking_app.admissions a ON a.id=b.admission_id
WHERE (b.organization_id,b.business_id,b.resource_id,b.customer_id)
 IS DISTINCT FROM (a.organization_id,a.business_id,a.resource_id,a.customer_id);
-- Expect zero.
```

### Smoke checks

Create a small fixed swimming plan purchase; confirm its dates appear on Calendar and reduce ordinary slot capacity. Mark attendance from Calendar. Create a flexible admission; mark present twice and confirm one date deduction and one overlapping visit. Check coaching seats and coach conflicts. Verify collections/refunds in Accounts. On a test admission, confirm completion/expiry prevents later visits and renewal creates a new balance with the same customer. Check a restricted staff account and a revoked assignment.

Use isolated test data for boundary-time changes; do not alter production timestamps to simulate expiry.

### Recovery

- A migration error before COMMIT leaves the prior schema intact. Diagnose the error and rerun the complete migration only after verifying the marker is absent.
- If the migration succeeded but no admissions have been created, restore the previous API/client and use `supabase/manual-recovery/rollback-admissions-empty.sql`. Its guards refuse to run if admission data or financial entries exist. Back up first.
- If admissions or payments exist, **do not drop tables or admission columns** and do not restore an older API that can mutate admission visits as ordinary bookings. Stop admission writes and deploy a forward fix while retaining history, reservations and ledger entries. Restore a full backup only with an explicit recovery decision that accounts for all later bookings/payments.

## Verification and monitoring

Run Flutter analysis/tests, backend build and focused booking/admission/accounts/Edge tests against in-memory PostgreSQL only. Check the prepared production migration against an isolated schema/role fixture. Monitor failed admission commands by request ID, capacity conflicts, failed payments, nonzero validation counts, and restore/renewal actions. Do not log customer phone numbers or tokens.
