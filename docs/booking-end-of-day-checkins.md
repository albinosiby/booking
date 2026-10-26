# End-of-day booking check-in

## Approved behavior

For regular bookings, staff may still use **Check in** when the customer arrives.
After the booking's local calendar day ends, an unchecked, finished, confirmed
booking receives an automatic check-in. The detail screen labels it **Auto
checked in**, and retained history identifies **Booking OS automation** with the
reason that an actual arrival time was not recorded.

The fallback excludes cancelled, no-show, completed, already checked-in and
admission/coaching visit bookings. Membership attendance is unaffected. Booking
status, amounts, payments, dues, inventory, customer data and booking times are
preserved. Only booking version and check-in history change. Existing check-in
rules still apply: once checked in, the ordinary no-show action is unavailable.
Staff should record known no-shows before the end-of-day fallback.

Each booking uses the business timezone saved in its price snapshot, falling
back to its location timezone for legacy data. A booking ending exactly at
midnight belongs to the preceding day. A booking crossing midnight waits until
the midnight following its actual end; it is never checked in while running.

Activation includes bookings ending during the activation day's local calendar
day, including bookings created earlier. It does not backfill preceding days.
For example, after activation on 26 October in Kolkata, a booking ending at
22:00 that day becomes eligible at 00:00 on 27 October. A booking ending at
01:00 on 27 October becomes eligible at 00:00 on 28 October.

## Architecture and security

The private SQL function `booking_app.booking_end_of_day_checkins()` runs through
the named database job `booking-end-of-day-checkins` every minute. The first run
after local midnight handles eligible bookings even if every app is closed.
Supabase Cron supports database functions and records execution status in its
job history: [Supabase Cron documentation](https://supabase.com/docs/guides/cron).

Each run processes at most 500 bookings across at most 25 businesses. Locked
businesses/bookings are skipped and retried on subsequent runs. Business locks
match the existing API mutation lock order. A unique partial check-in history
index, transaction boundaries and source metadata prevent duplicate manual or
automatic check-ins. Backlogs continue on following ticks.

The function uses `SECURITY INVOKER` with a fixed private search path in
production. The scheduler runs as the database administrator; `anon`,
`authenticated`, `booking_api` and PUBLIC receive no execution access. The
singleton automation settings table has RLS enabled and no client grants.
There is no new public API endpoint, service-role token or client-side timer.
Existing booking APIs expose the retained history; the updated Flutter client
distinguishes its `automatic_end_of_day` source from manual arrivals.

## Production activation and release

On 26 October 2026, the user explicitly approved
`20261026055830_booking_end_of_day_checkins.sql` and its recurring database job
for production project **scwwkaywewecspsrskft**. The migration was applied over
certificate-verified TLS. Job **3**, `booking-end-of-day-checkins`, is enabled
every minute under the database administrator. Activation is recorded as
`2026-10-26T06:16:02.558Z`. The activation smoke check processed zero bookings,
all existing records were preserved, client execution/settings access is denied,
both indexes are valid and the migration marker is present exactly once.
The first real scheduled execution succeeded at `2026-10-26T06:17:00.015Z`
and completed at `2026-10-26T06:17:00.025Z`. A fresh connection confirmed the
active job and committed schema, with zero historical-day backfills. The
private backup folder also contains `scheduled-run-verification.json`.

A private logical snapshot of ten affected booking, customer, payment, finance
and admission tables, schema metadata, original migration and verification
receipts is saved in `.local/releases/booking-eod-2026-10-26T06-16-04.870Z/`.
It is not a full project/Auth backup. Files are owner-only, and the folder is
ignored by Git. `backend/scripts/apply-booking-eod-migration.mjs` defaults to
read-only preflight/verification; the explicitly authorized `--apply` mode used
a transaction, preserved records and runtime grants, and rechecked committed
state. Repeated execution detects the existing marker.

No API or client deployment was included. The automatic job uses the existing
`checked_in` action recognized by deployed clients. The distinct **Auto checked
in** display and friendly actor name require the separately authorized release
of the updated client/API.

The following installation steps are for another environment where the
migration is still absent. Do not reapply it to the confirmed production project.

1. Confirm project **scwwkaywewecspsrskft**, PostgreSQL 15+, existing private
   `booking_app` booking/admissions/history tables and the application migration
   registry. Use the project database administrator. The read-only production
   check on 26 October 2026 found `pg_cron` 1.6.4 installed and zero duplicate
   check-in histories.
2. Save a restorable backup of bookings, booking history, payments, finance
   records, relevant grants and schema definitions. Save deployed API/client
   revisions. Check that no existing job uses the proposed name.
3. Run the entire
   `supabase/migrations/20261026055830_booking_end_of_day_checkins.sql` once,
   including BEGIN/COMMIT. This creates the private setting/function, indexes,
   one minute-by-minute job, and migration marker atomically. Existing booking
   and payment rows are not modified by migration application. Once activated,
   the job writes only eligible new-day check-in history and booking versions.
4. If an error occurs before COMMIT, verify rollback and the absent marker before
   retrying the complete file. The 10-second migration lock timeout prevents
   indefinite blocking. Do not remove the unique index or delete history to
   force the migration to pass.
5. Run the read-only checks below. Confirm the job has a successful execution
   after its next tick. Deploy the updated API/client through the separately
   authorized release process to show the explicit automatic label and actor
   name. Older clients still recognize the existing `checked_in` action.

The matching backend migration is for isolated/local database runners; it
creates the same function and constraints without installing a hosted cron job.
Never paste that backend copy into Supabase SQL Editor.

```sql
SELECT name, applied_at FROM booking_app.schema_migrations
WHERE name='20261026055830_booking_end_of_day_checkins.sql';
-- Exactly one row after activation.

SELECT enabled, enabled_at FROM booking_app.booking_checkin_automation;
-- One enabled setting; activation begins on this timestamp's local date.

SELECT jobid, jobname, schedule, active, username, database
FROM cron.job WHERE jobname='booking-end-of-day-checkins';
-- One active job, schedule '* * * * *', owned by the database administrator.

SELECT status, start_time, end_time, return_message
FROM cron.job_run_details
WHERE jobid IN (SELECT jobid FROM cron.job WHERE jobname='booking-end-of-day-checkins')
ORDER BY start_time DESC LIMIT 10;

SELECT role_name,
 has_function_privilege(role_name,
  'booking_app.booking_end_of_day_checkins(timestamptz,integer)','EXECUTE') AS can_run,
 has_table_privilege(role_name,'booking_app.booking_checkin_automation','SELECT') AS can_read_settings
FROM (VALUES ('anon'),('authenticated'),('booking_api')) roles(role_name);
-- Both privileges false for every client/API role.

SELECT i.indisvalid, c.relname
FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid
WHERE c.oid IN (to_regclass('booking_app.booking_single_checkin_idx'),
               to_regclass('booking_app.booking_end_of_day_candidates_idx'));
-- Two valid indexes.

SELECT count(*) AS duplicate_checkins FROM (
 SELECT booking_id FROM booking_app.booking_history WHERE action='checked_in'
 GROUP BY booking_id HAVING count(*)>1
) duplicates;
-- Zero.

SELECT details->>'booking_date' AS booking_date,
 details->>'timezone' AS timezone, count(*) AS automatic_checkins
FROM booking_app.booking_history
WHERE action='checked_in' AND details->>'source'='automatic_end_of_day'
GROUP BY 1,2 ORDER BY 1 DESC,2 LIMIT 50;
```

## Recovery and monitoring

On a failure before COMMIT, all migration statements roll back. Diagnose the
error and confirm absence of the marker, function/settings and job before
retrying. If the migration committed, keep the schema and financial/history
records. To pause future automatic check-ins, obtain authorization for this
specific operational change, then run as database administrator:

```sql
BEGIN;
UPDATE booking_app.booking_checkin_automation SET enabled=false WHERE singleton;
SELECT cron.unschedule(jobid) FROM cron.job
WHERE jobname='booking-end-of-day-checkins';
COMMIT;
```

This stops future work and keeps existing check-ins. Do not delete automatic
history, decrease booking versions, erase payment dues or restore stale booking
rows over newer payments. Review any erroneous check-in individually before a
separately approved correction. Monitor cron failures, last successful run,
batch backlogs and duplicate counts. Do not log customer details or secrets.

## Verification

The isolated PostgreSQL tests cover inclusive midnight, activation cutoff,
overnight and midnight-ending bookings, multiple timezones and DST, skipped
statuses/visits/manual arrivals, retries, batching, pause, private grants, the
production SQL with a scheduler stub, preserved dues and unchanged ledger data.
The scheduler stub verifies migration wiring; the separately approved production
activation and actual successful pg_cron execution are recorded above.

```sh
cd backend
node --import tsx --test --test-concurrency=1 test/booking-end-of-day.test.ts test/bookings.test.ts
npm run build
npm run edge:check
npm run edge:build
cd ..
flutter test --concurrency=1 test/booking_payment_summary_test.dart test/booking_module_test.dart
flutter analyze
```

All 50 focused backend tests and 34 focused Flutter tests passed locally. The
phone and desktop tests confirm the automatic label and preserved balance due.
