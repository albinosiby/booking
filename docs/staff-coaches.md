# Staff coaches

A coach is a team member: staff, a manager or the owner with **Coach** turned on. There are no separate coach contacts any more.

## Setting up

1. **Team & access → Invite staff** (or **Edit staff**): enter name/email/responsibility, enable **Also a coach**, and select businesses and resources. Enable **Mark attendance** independently if needed. New operational permissions start off.
2. The owner chooses **Manage responsibilities** on their own Team card, then enables **Also a coach**; owners cover every space and retain full permissions.
3. After acceptance, open **Edit staff → Coaching plans → Assign coaching plans**. Save resource/coach-status changes with **Save staff access** first; the details page stays open. Plan selection offers only covered plans and preserves overlap warnings and version checks. There is no separate Coaches page.


Turning Coach off, removing a business or space from a coach's access, or removing their access asks first in the app. The server then sets every plan the person can no longer teach to **Unassigned**.

## My classes

Coaches open **My classes** from Home or Profile. It shows one day's classes for the plans they coach: plan, time, space and students. Each class's students share one entry.

Coaches mark **Present/Absent** for their own classes, one at a time or with **Mark all present**. They require the explicit **Mark attendance** permission, independently of coach status. Subscription management has a separate permission. The existing rules apply: only first marks of fixed-schedule sessions, from the start until 24 hours after the end. The owner corrects marks from the admission. The overlap check and the coach shown on admissions always use each plan's current coach.

## API

- `coach` identifies coaching responsibility. `mark_attendance` and `manage_subscriptions` are independent grants in membership and invitation `permissions`.
- `PUT /v1/team/me/coach` `{coach: boolean}` lets the owner opt in or out. Opting out returns `released`, the number of plans set to Unassigned.
- `PATCH /v1/businesses/:id/plan-coaches` `{version, coaches: {planId: membershipId | null}}` sets plan coaches only. It is version checked and keeps the business status.
- `PATCH /v1/team/:id` and `DELETE /v1/team/:id` now also return `released`.
- `GET /v1/admissions/classes?date=YYYY-MM-DD` returns the caller's classes with `students[].markable`.
- `POST /v1/admissions/:id/sessions/:visitId/attendance` requires attendance permission; coaches may mark only their currently assigned plans within their resource access.
- Pool and court configurations reject a non-empty `coaches` array. A plan's `coach_id` must be an active coach assigned to every space of the plan.

## Earlier staff-coach migration (the owner applies it once)

For the current unified staff rollout, also follow [permission migration and recovery](team-coaches.md). The older migration below remains a prerequisite; do not rerun it if already recorded.

Migration: `backend/migrations/20261022120000_staff_coaches.sql`, with the Supabase copy at `supabase/migrations/20261022120000_staff_coaches.sql`.

What it does:
- removes `coaches` from every `pool_v1` and `court_v1` configuration;
- sets plans that pointed at a removed contact to `coach_id = null`, and bumps those businesses' `version`;
- adds `coach` to members that older pool plans already name as their coach, so those plans stay assigned.

It creates and alters no tables, and the API refuses to start until it is applied.

1. Back up the data it changes:
   `CREATE TABLE booking_app.businesses_coach_backup AS SELECT id, configuration, version FROM booking_app.businesses WHERE configuration ? 'coaches';`
   `CREATE TABLE booking_app.memberships_coach_backup AS SELECT id, permissions FROM booking_app.memberships;`
2. Apply the Supabase migration file.
3. Validate:
   - `SELECT count(*) FROM booking_app.businesses WHERE configuration ? 'coaches';` should return 0.
   - `SELECT name FROM booking_app.schema_migrations WHERE name = '20261022120000_staff_coaches.sql';` should return one row.
   - `SELECT b.id, p->>'name' AS plan FROM booking_app.businesses b, jsonb_array_elements(b.configuration->'plans') p WHERE p->>'coach_id' IS NOT NULL AND NOT EXISTS (SELECT 1 FROM booking_app.memberships m WHERE m.id::text = p->>'coach_id' AND m.permissions ? 'coach');` should return no rows.
4. Deploy the `booking-api` Edge Function (`npm run edge:build` output), then release the app. Older app builds can't save pool or court settings that still contain coach contacts.
5. Reassign the plans that became Unassigned: Team & access → Edit staff → Coaching plans.

Recovery: restore each backed-up row with `UPDATE booking_app.businesses b SET configuration = k.configuration, version = b.version + 1 FROM booking_app.businesses_coach_backup k WHERE k.id = b.id;`, and do the same for `memberships.permissions`. Then redeploy the previous Edge Function. Delete the `schema_migrations` row only if you also roll back the API.
