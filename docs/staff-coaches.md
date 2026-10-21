# Staff coaches

A coach is a team member: staff, a manager or the owner with **Coach** turned on. There are no separate coach contacts any more.

## Setting up

1. **Team management → Invite staff** (or **Edit assignments**): turn on **Coach** and choose the businesses and spaces the coach teaches in. An unrestricted business covers all of its pools or courts. Team → Coaches → **Invite coach** opens the same form with Coach already on.
2. The owner coaches too after switching on **I also coach** in Team → Coaches; owners cover every space.
3. **Team management → Coaches → Assign coaching plans** lists the plans whose spaces the coach covers. Saving changes only the plans' coaches, so a ready business stays ready. If the coach would teach overlapping upcoming classes, the app lists them and asks before saving.

Turning Coach off, removing a business or space from a coach's access, or removing their access asks first in the app. The server then sets every plan the person can no longer teach to **Unassigned**.

## My classes

Coaches open **My classes** from Home or Profile. It shows one day's classes for the plans they coach: plan, time, space and students. Each class's students share one entry.

Coaches mark **Present/Absent** for their own classes, one at a time or with **Mark all present**. They don't need the "Manage subscriptions and attendance" permission for this. The existing rules apply: only first marks of fixed-schedule sessions, from the start until 24 hours after the end. The owner corrects marks from the admission. The overlap check and the coach shown on admissions always use each plan's current coach.

## API

- `coach` is a new value in membership and invitation `permissions`.
- `PUT /v1/team/me/coach` `{coach: boolean}` lets the owner opt in or out. Opting out returns `released`, the number of plans set to Unassigned.
- `PATCH /v1/businesses/:id/plan-coaches` `{version, coaches: {planId: membershipId | null}}` sets plan coaches only. It is version checked and keeps the business status.
- `PATCH /v1/team/:id` and `DELETE /v1/team/:id` now also return `released`.
- `GET /v1/admissions/classes?date=YYYY-MM-DD` returns the caller's classes with `students[].markable`.
- `POST /v1/admissions/:id/sessions/:visitId/attendance` also accepts the plan's current coach.
- Pool and court configurations reject a non-empty `coaches` array. A plan's `coach_id` must be an active coach assigned to every space of the plan.

## Rollout (the owner applies the migration)

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
5. Reassign the plans that became Unassigned: Team → Coaches.

Recovery: restore each backed-up row with `UPDATE booking_app.businesses b SET configuration = k.configuration, version = b.version + 1 FROM booking_app.businesses_coach_backup k WHERE k.id = b.id;`, and do the same for `memberships.permissions`. Then redeploy the previous Edge Function. Delete the `schema_migrations` row only if you also roll back the API.
