# Block slots

## Using the feature

Open Bookings or Calendar and tap the lock/clock icon in the app bar. Blocked slots shows a date strip (and business cards when there are several businesses), a day header with the number of blocks, and one card per block with its time range, spaces, creator and Unblock. Tap **Block slots** (bottom right) to add one.

The Block slots form uses the same layout as New booking: **1 Select spaces** (space cards, Select all/Clear) and **2 Date & time** (date strip, then Entire day or Specific hours). For Specific hours the form shows the day's half-hour slot grid for the selected spaces, coloured like New booking: Available, Booked (struck through, not selectable), Blocked (red, not selectable) and the selection. Tap the first half hour, then the last one; tap the start again to clear. A range cannot cross a booked or blocked half hour. Past half hours are hidden. **Enter exact times** switches to start/finish pickers for non-half-hour or overnight blocks (Pick from slots returns to the grid). For Entire day the form warns when the day already has bookings. The bottom bar always shows what will be blocked; Review block opens a summary, then Confirm block saves. There is no reason field. Times use the location's timezone. A finish time at or before the start means the following day (maximum one day). Entire day runs from local midnight to the following midnight.

A block closes physical inventory: turf halves/full ground and sports sharing the selected ground conflict with it. Pool blocks close the pool regardless of available capacity, including plan attendance. Existing reservations prevent a conflicting block; resolve them first. Blocks never cancel reservations or enter booking counts, income or reports. Strict interval boundaries allow bookings ending exactly when a block starts, or starting exactly when it ends.

Unblock from the selected day's list to allow bookings again. Owner or staff with manage_bookings permission and business/space assignments can manage blocks. Staff cannot unblock a block containing spaces outside their assignment. Block and unblock operations retain audit entries. While future blocks exist, unblock them before deleting spaces or changing shared-ground footprints.

The app uses typed models, separate list/form Cubits and an abstract repository with a REST implementation. Existing cached booking catalog is reused, existing content stays visible during list refresh, writes invalidate retained availability data, and unknown save results retry the same command instead of creating duplicate blocks. The server always rechecks availability on final booking/reschedule/attendance commit. Booking and block creation share the business transaction lock.

## Migration — apply this yourself before deploying

No live database migration or deployment was performed.

1. Back up the current database and save the currently deployed function source. Use the Supabase **booking** project, reference `scwwkaywewecspsrskft`.
2. Check that earlier project migrations have been applied, especially admissions (`20261020120000_admissions.sql`): this API's inventory query already uses admission balances. Do not apply unrelated pending migrations blindly. The database must have schema `booking_app`, role `booking_api`, the existing organizations, businesses, resources, memberships, audit_events, bookings, booking_allocations and admission_balances tables, and businesses' existing unique `(id, organization_id)` constraint.
3. In Supabase SQL Editor, run the entire file [20261020122907_booking_slot_blocks.sql](../supabase/migrations/20261020122907_booking_slot_blocks.sql). It includes BEGIN/COMMIT, restricted grants and this project's custom schema_migrations registration. Apply it once. Do not also run the backend copy or a blind `supabase db push`.
4. Verify with the following read-only SQL before deploying:

```sql
SELECT to_regclass('booking_app.booking_slot_blocks') AS new_table,
       to_regclass('booking_app.admission_balances') AS admissions_table;
SELECT name FROM booking_app.schema_migrations
WHERE name='20261020122907_booking_slot_blocks.sql';
SELECT indexname FROM pg_indexes
WHERE schemaname='booking_app' AND tablename='booking_slot_blocks';
SELECT grantee, privilege_type FROM information_schema.role_table_grants
WHERE table_schema='booking_app' AND table_name='booking_slot_blocks';
SELECT count(*) AS blocks FROM booking_app.booking_slot_blocks;
```

Expected: both tables exist; migration name appears once; primary key and two interval/org indexes exist; booking_api has SELECT, INSERT, UPDATE, with no direct anon/authenticated/PUBLIC access. New table starts empty. Existing bookings and financial rows are unchanged. The API enforces user/tenant/assignment permissions; this table is not exposed for direct client writes.

If SQL fails, run `ROLLBACK;` in that session, inspect the error and prerequisites, and retry only after correcting them. Do not mark the migration applied manually or proceed to API deployment with a missing table.

## Deploy the API yourself

Run in order, stopping on any failure:

```sh
cd "/Users/albinosiby/Tatos Dev/booking"
npm --prefix backend run build
npm --prefix backend run edge:check
npm --prefix backend run edge:build
npx supabase functions deploy booking-api --project-ref scwwkaywewecspsrskft --use-api --no-verify-jwt
curl -sS "https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/health"
```

Expected health revision: `2026-10-21-block-slot-grid` (adds the read-only slot grid route; no further database migration). Keep the existing function-side Supabase Auth verification, database secret and role unchanged. The legacy gateway remains disabled; protected endpoints still verify Supabase user tokens and application permissions.

Reload the updated app source to test the UI; no APK was built. Test an empty future day first: block a court interval, verify it shows Blocked in New booking and cannot be submitted through an earlier quote, then unblock and verify availability returns. Check a shared turf half/full-ground combination, a pool, an overnight interval on both dates, an existing booking conflict and an assigned staff account.

## API contract

All routes require an authenticated user with booking management permission and the relevant assignments:

- GET `/v1/booking-blocks?business_id=<uuid>&date=2030-06-04&cursor=0`: active overlapping blocks for the local day, up to 100, with `items` and `next_cursor`.
- GET `/v1/booking-blocks/slots?business_id=<uuid>&date=2030-06-04&resource_ids=<uuid>,<uuid>`: the local day in 30-minute cells for the selected spaces, `{ "date", "timezone", "step_minutes": 30, "slots": [{ "time": "09:00", "status": "available|booked|blocked|past" }] }`. Uses the same physical inventory keys as blocking (shared turf sections included). Times skipped by a daylight-saving change are omitted.
- POST `/v1/booking-blocks`: `{ "command_key":"<uuid>", "business_id":"<uuid>", "resource_ids":["<uuid>"], "date":"2030-06-04", "all_day":false, "start_time":"23:00", "end_time":"03:00", "end_date":"2030-06-05" }`. Full-day requests need no time fields. Returns `{ "id":"<uuid>" }`. Reuse command_key for the same retry; never for changed inputs.
- POST `/v1/booking-blocks/<id>/unblock`: `{}`. Returns `{ "id":"<uuid>" }`; repeating is safe.

Unknown fields (including reason), unassigned resources and invalid dates are rejected. Conflicts return 409; denied access returns 403; missing resources return 404; invalid payloads use the existing validation error envelope. Conflict messages include permitted reservation references and ask the user to resolve them first.

## Recovery and validation after release

Do not drop the table or restore an API that ignores blocks while active blocks exist: it would allow reservations in closed intervals. Keep the table and data on rollback. If an enforcement deployment fails, pause affected booking activity and restore the last working version that enforces blocks. Reverting to the pre-feature API is safe only after all active blocks have been intentionally resolved/unblocked and staff are informed. Do not delete reservations or finance records as recovery.

Audit verification:

```sql
SELECT id,business_id,starts_at,ends_at,created_by,unblocked_by,unblocked_at
FROM booking_app.booking_slot_blocks ORDER BY created_at DESC LIMIT 20;
SELECT action,entity_id,actor_id FROM booking_app.audit_events
WHERE action IN ('booking_slots_blocked','booking_slots_unblocked') LIMIT 20;
```

Local validation: 81 backend tests passed (bookings, blocks, admissions and Edge routes), 34 Flutter tests passed across the new module and booking regression suite, and the new form also passed narrow-screen light/dark checks. TypeScript and Edge type-check/build passed.
