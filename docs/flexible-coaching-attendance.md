# Flexible coaching attendance

Flexible enrolments appear on **Home → Today’s students → Flexible students** and **My classes** before a visit has been reserved. The selected date must be today in the business's time zone. The roster includes the caller's currently assigned coaching plans and resources, and keeps a student's final used day visible after marking.

Each tile shows the student, plan, space/business, remaining attendance days, class interval and saved attendance time. A flexible student is not automatically marked absent. Historical visits remain available when browsing earlier class dates.

- **Start class & mark present** creates the first student's visit and attendance together. The class starts at the server's current business-local minute and lasts the admission's configured coaching duration. An empty class is not created.
- **Mark present** joins the unique running class for the same plan, space and duration, preserving its exact start/end interval. A stale Start action also joins an already-running class safely.
- The server records the actual attendance timestamp separately from the scheduled class interval. Both are displayed in the business's time zone.
- Marked flexible students have one tile, rather than appearing again as a duplicate scheduled student. Past class history is retained.
- When a plan/space is unavailable, attendance permission is missing, a class is full or a conflicting reservation exists, the roster shows the reason. Writes recheck these rules inside the business-locked transaction.
- A response lost after saving leaves **Finish attendance save** on Home and **Retry attendance save** in My classes. Both reuse the original command key, admission version and start intent. Other attendance writes stay disabled until that request is resolved; it cannot create another class or deduct another day.

Existing allowance rules remain: flexible usage counts distinct business-local class dates, not button presses. Existing expiry, operating days/hours, coach overlap, pool capacity, court reservations and slot-block rules apply. Coaches require both current plan/resource assignment and attendance permission. Only owners correct recorded attendance with a reason.

## API changes

`GET /v1/admissions/classes?date=YYYY-MM-DD` retains `classes` and adds `flexible_students`. Each entry includes:

```json
{
  "admission_id": "<uuid>",
  "version": 1,
  "name": "Student",
  "plan_name": "Beginner coaching",
  "business_name": "Academy",
  "space_name": "Pool A",
  "today": "2026-10-24",
  "remaining": 5,
  "duration_minutes": 60,
  "action": "start",
  "reason": null,
  "local_start": "2026-10-24T12:10",
  "local_end": "2026-10-24T13:10",
  "local_marked_at": null
}
```

`action` is `start`, `join`, `present` or `unavailable`. Read actions are advisory: capacity or permission may change before saving.

`POST /v1/admissions/:id/check-ins` accepts:

```json
{"command_key":"<uuid>","version":1,"start_class":true}
```

`start_class: true` permits starting a coaching class if none is running. Only the assigned coach with attendance permission, or the owner, may use this option. A running class is joined instead. The client sends no clock, date or duration. The response includes `class_started`, `local_start`, `local_end`, `marked_at` and `local_marked_at` for a new attendance record. Idempotent replays return the original result. Requests without `start_class` preserve the existing join-only automatic coaching behaviour; legacy explicit interval requests remain supported.

## Deployment

No database migration or live schema change is required. This update uses existing admissions, bookings, inventory allocations, command responses and audit history. Deploy the API before the updated web/native clients. Older clients continue to receive `classes`; new clients need the API's additional roster data and start option.

From macOS Terminal:

```sh
cd "/Users/albinosiby/Tatos Dev/booking/backend"
npm ci
npm run build
npm run edge:check
npm run edge:build

cd "/Users/albinosiby/Tatos Dev/booking"
npx --yes supabase@2.122.0 functions deploy booking-api \
  --project-ref scwwkaywewecspsrskft --no-verify-jwt --use-api
```

Use the existing Supabase CLI login and server secrets. The project's Edge handler verifies authentication and authorization itself.

Check the [API health response](https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/health) for revision `2026-10-24-flexible-coach-attendance`. Then deploy the updated repository through the existing Railway Docker frontend pipeline and distribute the updated native app. The local Android debug APK is for development/testing; production signing remains part of release distribution.

## Verification and recovery

Use test students and a coach assigned to the plan and space with **Mark attendance** enabled. Check both Home and My classes on web and phone:

1. Add a flexible coaching enrolment with no reserved visit. Its student must appear immediately after roster refresh.
2. Start a class with the first student. Verify one present visit, the configured duration and actual saved attendance time.
3. Mark another flexible student present. Verify the same class interval and no extra court reservation.
4. Retry the original request after a simulated lost response. Verify one visit and one date credit.
5. Verify full/blocked spaces, future overlapping bookings, missing attendance permission, reassigned coaches, expiry and exhausted allowance reject writes. Check a business whose local date differs from UTC.
6. Browse an earlier date: existing attendance history must remain visible, with no action to mark a flexible student on that date.

Rollback by restoring the previous app/web and API versions together. Existing recorded visits and audit history remain; rollback does not reverse attendance or credits. Use the existing owner correction workflow with a reason if an attendance record itself needs correction. Do not delete historical records or alter balances with ad hoc SQL.
