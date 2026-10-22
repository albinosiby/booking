# Court plans, coaching and admissions

Badminton, tennis and basketball businesses can now sell **court plans** (like swimming plans: a number of play days) and **coaching plans** through **Profile → Plans & Coaching**, the same way pools do. Admissions, attendance, remaining classes, renewals, payments and coaches behave as described in [Admissions & Coaching](admissions-coaching.md); this page covers what differs for courts.

## Owner setup

1. **Court settings → Plans & coaching → Add coaching plan** (or **Add court plan**, see below). Choose the courts the plan can run on, number of classes, validity (days, months, years or fixed date), total price, class duration, maximum students per class and the coaching days/times. The coaching times must fit inside the opening hours of every selected court. Coaching plans are optional; a court business without plans is unchanged.
2. **Save changes** (or Activate). Enabled plans need at least one court and a price before an active business can be saved.
3. **Team & access → Edit staff → Coaching plans.** Coaches are team members with **Also a coach** turned on in their staff access (see [Staff coaches](staff-coaches.md)). Their courts are the courts of that staff access. **Assign coaching plans** offers only plans whose courts they cover.

**Court plans** (Court settings → Plans & coaching → Add court plan) give a player a number of play days within validity. There is no class size or coach. Each visit reserves the whole court like an ordinary booking: a second player cannot use that court at the same time. Visits use the court's minimum duration and can be extended in 30-minute steps. Flexible plans deduct one day per attendance date. Fixed schedules reserve every visit up front, and each reserved visit counts once it ends. In Plans & Coaching, court plans appear in the **Plans** tab for the selected court, and the booking form offers **Court booking / Court plan / Coaching**.

## Enrolling students

Use **Profile → Plans & Coaching → New admission**, or the booking form: on a court business, pick a court, then choose **Coaching** instead of **Court booking**. Select the plan, activation date and attendance mode:

- **Fixed weekly schedule:** chosen weekdays and start time reserve every class up front, within validity.
- **Flexible:** no advance student reservation. **Mark present** automatically joins the matching coaching class currently running on the selected court, using its scheduled start/end time. If no class is running, no arbitrary class is created; attendance is marked from a scheduled class. Ordinary flexible court access plans use the server's current business-local time and the admission's saved visit duration. There is no attendance time picker.

## How a batch uses the court

A batch is a plan + court + exact start and end time.

- The **first student** of a batch needs the court to be free for that interval; this reserves the whole court, so ordinary court bookings and slot blocks treat it as booked.
- **Later students** of the same plan, court and time join that batch without needing extra court capacity, up to the plan's *maximum students per class*. One more is rejected with "This coaching class is full."
- A different plan (or an ordinary booking) cannot use that court while the batch is running.
- A coach cannot run two overlapping batches, on the same or a different court.
- Cancelling or expiring one student's admission releases only their seat. The court stays reserved while any student of that batch still holds the class.
- Court preparation/cleanup buffers apply to ordinary bookings only, not to class reservations.

Deleting a court with admission history is refused; disable it after its admissions end. Court hours or plan changes that would invalidate reserved classes are refused until those sessions are rescheduled.

## Data and API

- `court_v1` business configuration supports an **optional** `plans` array: `plans` (`kind: "play"` or `"coaching"`; play plans keep `class_duration_minutes`, `class_seats` and `coach_id` null; `court_ids`, validity, `price_minor`, `availability`, `class_duration_minutes`, `class_seats`, `coach_id`, `renewal: "none"`). Coach identities reference active team memberships; separate `coaches` contact arrays are rejected. Existing configurations without plans stay valid.
- Admissions already use the generic `admissions.resource_id`, `bookings` and `booking_allocations` tables, so court admissions reuse them unchanged. Court visits use the same inventory key as ordinary court bookings (`<business>:<court>`).
- `GET /v1/admissions/catalog` now also lists ready court businesses. Each business has `type` and `space_kind` (`pool` or `court`). Spaces are still returned under `pools`, and plan space IDs under `pool_ids`, so older clients keep parsing the response.
- No new routes: the existing Nest controllers and the hosted Edge routes in `backend/edge/handler.ts` already expose admissions and `PATCH /v1/businesses/:id/court-configuration`.

## Database migration

**Court plans need no schema change.** Plan definitions and their staff-coach IDs live in the existing `businesses.configuration` JSON, and the admissions schema from `20261020120000_admissions.sql` already stores any resource. That migration must already be applied (it is a prerequisite for pool admissions too). Staff-coach conversion and the unified permission backfill are additional data-migration prerequisites described in [Unified staff management](team-coaches.md).

Check it is present (read-only):

```sql
SELECT name, applied_at FROM booking_app.schema_migrations
WHERE name = '20261020120000_admissions.sql';
-- Expect one row.
```

## Deploy (you run these; nothing has been deployed)

1. Back up the current `booking-api` Edge Function source (Supabase Dashboard → existing **booking** project → Edge Functions → booking-api → download).
2. From `backend`, run:
   ```bash
   npm --prefix "/Users/albinosiby/Tatos Dev/booking/backend" run build
   ```
   ```bash
   npm --prefix "/Users/albinosiby/Tatos Dev/booking/backend" run edge:check
   ```
   ```bash
   npm --prefix "/Users/albinosiby/Tatos Dev/booking/backend" run edge:build
   ```
3. Replace the function's `index.ts` with the generated `supabase/functions/booking-api/index.ts` and choose **Deploy updates**. Keep existing secrets and the custom Auth setting (`verify_jwt=false`). The generated bundle also contains any other undeployed backend changes in this working tree (for example the Income page work); deploy those together or not at all.
4. **Deploy the API before releasing the app.** An older API rejects court configurations that contain new plan fields (strict validation), so saving a court plan from the new app against the old API fails with a validation error. Courts without plans keep saving normally on either API.
5. Release the updated Flutter app.

## Smoke checks after deployment

1. On a test court business, add a coaching plan (2 seats) on Court 1 and save.
2. Invite a staff member with Coach on and Court 1 assigned; after acceptance, assign the plan from their staff details and explicitly enable Mark attendance if needed.
3. Enroll student A on a fixed schedule. Confirm the class appears on Calendar and that an ordinary booking for Court 1 at that time is unavailable, while Court 2 is still bookable.
4. Enroll student B at the same time and plan: accepted. Student C: "This coaching class is full."
5. Try a second plan with the same coach on Court 2 at that time: "The coach has another overlapping class."
6. Mark attendance from Calendar, collect a payment and check it in Accounts.
7. Cancel student A: Court 1 must stay unavailable for ordinary bookings because student B still holds the batch.

## Recovery

- API problems: redeploy the backed-up Edge Function source. Court businesses that saved plans keep them in JSON; the old API refuses further edits to those businesses until the new API is restored, but bookings and existing admissions continue to work.
- To remove coaching from a court business, disable or remove its plans in Court settings and save. Existing admissions keep their purchased plan snapshot, reservations, attendance and payments; cancel them explicitly if needed.
- No database rollback is involved because no schema changed.

## Verification completed

- Backend: all 200 tests pass in isolated in-memory PostgreSQL, including the new `test/court-admissions.test.ts`. That file covers optional plans/coach validation, the catalog, shared batch reservations and seat limits, blocking other plans and ordinary bookings, coach conflicts, flexible check-in and protection against deleting a court. `npm run build` and `npm run edge:check` pass.
- Flutter: `flutter analyze` reports no issues. New tests are in `test/court_coaching_test.dart` and `test/admissions_test.dart`. They cover model round-trip and validation, the setup cubit, Team coaches for courts, the coaching editor at 320px and court labels in the admission form.
