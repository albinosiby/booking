# Admissions & Coaching

## What is included

Profile → Admissions & Coaching manages customer purchases of configured swimming and coaching plans for pool businesses, and coaching plans for court businesses (see [Court coaching](court-coaching.md)). The booking form links to the same admission form. Select a customer, business, pool and plan, activation date, attendance mode, and optional split payments. Review the calculated expiry and every fixed session before confirming.

- **Fixed weekly schedule:** selected weekdays/time reserve the complete allowance, up to 1,000 sessions, within validity. Each non-cancelled session uses one unit after its end, even when absent or unmarked. Present/Absent records actual attendance separately. An insufficient schedule or a full interval rejects the entire purchase; it never silently skips a day.
- **Flexible:** no standing reservation. Mark present on arrival, selecting a start time whose configured duration contains the current time. The visit reserves one pool place and consumes one unit per location-local attendance date. Multiple non-overlapping visits on the same date use one unit. This day-based rule also applies to flexible coaching in this release.
- **Coaching:** configured class duration, seats, pool and snapshotted coach apply. Matching plan/pool/start/end reservations share a class capacity. Independent overlapping classes cannot use the same coach. Calendar displays each student's reservation so attendance can be marked individually. Dedicated named batches and bulk roster attendance are not included.
- **Completed:** all units used. The final flexible visit remains valid until its end; repeat visits on that final attendance date remain subject to capacity and expiry. No later-date attendance can be added.
- **Expired:** the location-local date is later than the inclusive expiry date. Unused units remain visible but cannot be used. Visits must end within validity. Existing day/month/year expiry calculations are retained, including clamping month/year boundaries.
- **Renew:** completed/expired admissions can be renewed once. Renewal creates a separate admission using the current enabled plan and pricing, preserving the customer and previous history. No unused balance or money is automatically transferred. Each renewed admission can itself be renewed later.
- **Corrections:** owners can change recorded attendance with a reason. Clearing flexible attendance restores its date credit only when no other present visit remains on that date. Fixed usage is independent of attendance. Owners can restore credit for an ended fixed session, then schedule one makeup session before expiry; the original stays in history. Future fixed sessions can be cancelled or rescheduled with a reason and fresh capacity checks.
- **Cancellation:** future reservations are cancelled/released. Historical attendance and payment dues remain. Refunds are explicit owner-recorded transactions, never automatic.

All reservation views and availability use the existing booking inventory. Admission sessions have a zero visit price: the plan is charged once on the admission. Collections/refunds post into the existing money accounts and financial reports as `admission_collection` / `admission_refund`. Dues can be collected after completion or expiry. No payment gateway or customer self-service login is introduced.

## Permissions and architecture

Existing permissions are reused: `view_bookings` for reading, `manage_bookings` for enrollment/schedule management, `manage_attendance` for check-in/attendance, and `collect_payments` for collections. Owners can refund and correct attendance. All reads/writes check current organization membership and assigned business/resource scope. Coaches are staff (or the owner) with the `coach` permission; they mark attendance for their own classes in My classes without `manage_attendance`. See [Staff coaches](staff-coaches.md).

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

Creation body includes `business_id`, `resource_id`, `plan_id`, `starts_on`, `mode`, `weekdays`, `time`, `duration_minutes`, `customer`, `payments`, nullable `renewed_from`, plus `preview_token` and `command_key`. Preview accepts the same body without token/key. Customer and payment formats match ordinary bookings. Mutations use UUID command keys and optimistic versions. Errors use the existing 401/403, 404, 409 and validation envelopes.

The `admission_balances` view calculates fixed usage from ended sessions and flexible usage from distinct present dates. No cron job or live schema mutation is required for expiry/completion. Availability ignores future allocations on closed admissions while retaining occupancy of already-started visits. Tenant-scoped foreign keys prevent attaching visits to another admission's customer or pool. Business row locks serialize purchases/check-ins with ordinary booking capacity changes.

## User-applied production migration

**Do not deploy the new API before applying this migration. No live migration has been applied by Codex.**

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
