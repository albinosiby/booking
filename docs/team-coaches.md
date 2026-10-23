# Unified staff and coaching responsibilities

Open **Profile → Team & access → Add team member**. There is one staff list for everyone, including coaches. Enter name, email and responsibility (Staff or Manager), optionally enable **Also a coach**, select businesses and optionally restrict them to resources. Permissions start off. Adding the person saves pending access and sends an access-summary email with app/web login links through Nodemailer. They sign in with the same verified email (including Google) and go directly to the dashboard; no shared link or Accept step is required. Pending access remains until cancelled. Team shows email delivery status and supports resend and pending-access edits. See [email-based team access and deployment](team-email-access.md).

Older token invitations retain their original seven-day validity and explicit acceptance. They are not automatically converted to email grants.

Coach status makes an active team member eligible to teach coaching plans. It does not grant bookings, payments, subscriptions or attendance access. Staff and Manager remain responsibility labels; selected permissions and assignments determine access. Compact staff tiles identify coaches with a badge. Tap a tile to open staff details; its menu contains Edit staff and Remove access. Phone layouts use one column and wide screens use a grid. The former `/team/coaches` URL redirects to Team & access; there is no separate Coaches page.

## Permissions

- **View bookings** (`view_bookings`): booking visibility within assigned resources.
- **Create and edit bookings** (`manage_bookings`): ordinary booking operations.
- **Mark attendance** (`mark_attendance`): attendance/check-in within assigned resources. Coaches are additionally limited to the plans they currently teach. A coach with this permission disabled can still see their own classes, but cannot mark students present or absent. Coach status alone does not grant general admissions or booking access.
- **Manage subscriptions** (`manage_subscriptions`): enrollments, renewals, and subscription session management. It does not grant ordinary booking creation or attendance marking.
- **Record collections**, **Record expenses**, and **View financial reports** remain separate permissions.

Owner permissions continue to cover all operations. Attendance corrections still require the owner and a reason. Staff first marks remain limited to fixed sessions that have started and ended no more than 24 hours ago. Flexible check-in requires attendance access and follows the existing allowance, current-time, capacity and expiry rules.

## Assign coaching plans inside staff details

Once a team member has signed in, tap that person’s tile or choose **Edit staff** from its menu. Coach status, business/resource access, permissions and the **Coaching plans** section are managed here in both web and app layouts. **Save staff access** keeps the details page open.

Save changes to Coach status or resource assignments before changing coaching plans. The plan section explains this and disables assignments until access has been saved. New team entries explain that plans can be assigned after first sign-in. Under each eligible business, choose **Assign coaching plans**, select covered plans, and **Save assignments**. These plan changes have their own explicit save and publish immediately. Only plans fully covered by the staff member's saved resources are offered, together with already-assigned plans so they can be removed. Selecting another coach's plan replaces its coach. Existing overlap warnings and version-conflict rejection are preserved. Failed saves retain edits and report the error.

Removing access, disabling Coach or narrowing resources releases coaching plans that are no longer eligible, after the existing confirmation. Removing only attendance permission preserves teaching assignments. Owners open their own Team tile to enable **Also a coach** and assign their own plans, within staff management.

## Permission data migration: user applies it

No tables, columns, indexes, authentication settings or secrets change. Existing membership and invitation permission arrays need a one-time compatibility backfill:

- Existing `manage_bookings` grants receive `manage_subscriptions`, preserving previous subscription-management access.
- Existing `manage_attendance` grants receive `mark_attendance`.
- Existing coaches (including team members referenced by legacy coaching plans) receive `mark_attendance`, preserving their previous attendance ability. Going forward, turning Coach on grants nothing automatically.
- Pending, unexpired, uncancelled invitations receive equivalent grants. Cancelled/expired invitations are unchanged.
- The legacy `manage_attendance` marker remains accepted as an attendance grant for older clients; new staff saves replace that marker with the explicit attendance permission. For coaches, attendance remains limited to their own current plans, including when a legacy attendance marker is present.

**No migration or deployment has been applied by this implementation.**

### Prerequisites and backup

1. Confirm the correct booking project, private `booking_app` schema, and that the existing workspace/admissions/staff-coach migrations have been applied, including `20261022120000_staff_coaches.sql`. Do not run the earlier staff-coach migration again if it is already recorded.
2. Arrange a short maintenance window for staff/invitation edits. Keep the previous deployed Edge Function and Flutter web/APK builds for recovery.
3. In Supabase SQL Editor, run the following read-only queries and save their results as SQL text. These produce exact restoration statements for the current permission arrays. Keep these files private:

   ```sql
   SELECT format('UPDATE booking_app.memberships SET permissions=%L::jsonb WHERE id=%L::uuid;', permissions::text, id::text) AS recovery_sql
   FROM booking_app.memberships ORDER BY id;
   SELECT format('UPDATE booking_app.invitations SET permissions=%L::jsonb WHERE id=%L::uuid;', permissions::text, id::text) AS recovery_sql
   FROM booking_app.invitations ORDER BY id;
   SELECT name FROM booking_app.schema_migrations
   WHERE name IN ('20261022120000_staff_coaches.sql', '20261022051321_unified_staff_permissions.sql');
   ```

### Apply and release

1. Deploy the prepared `supabase/functions/booking-api/index.ts` to the existing `booking-api` Edge Function, preserving its current environment and custom JWT verification configuration. Keep staff edits paused until migration and updated clients are ready.
2. Open `supabase/migrations/20261022051321_unified_staff_permissions.sql` and execute its complete contents in Supabase SQL Editor. It contains its transaction, private-schema search path, lock timeout and application migration-ledger entry. On failure, the transaction rolls back; diagnose before retrying. Do not rerun a recorded migration, especially after owners have changed attendance grants.
3. Release the updated Flutter web and app builds together, then reopen staff management. Retire older clients before editing the new explicit permissions; older clients cannot represent all the new controls.
4. Node deployments use the matching file in `backend/migrations/`. Apply it with the project's migration process and record the same filename in `schema_migrations`; do not execute both versions on the same database.

### Validation

```sql
SELECT name FROM booking_app.schema_migrations
WHERE name='20261022051321_unified_staff_permissions.sql';
SELECT id, display_name, role, permissions
FROM booking_app.memberships ORDER BY display_name;
SELECT id, email, permissions, expires_at
FROM booking_app.invitations
WHERE accepted_at IS NULL AND revoked_at IS NULL AND expires_at > now();
```

Immediately after the backfill, before owners edit permissions, legacy coaches/attendance staff should have `mark_attendance`, and legacy booking managers should have `manage_subscriptions`. After release, removing an explicit permission intentionally changes that expectation.

Verify on web and phone: invite a coach without attendance; accept as the exact email; assign resources, save, then assign a covered coaching plan. Confirm classes are visible with attendance disabled. Enable attendance and verify first marking on their own current classes only. Disable it and confirm the next API request is rejected. Confirm booking creation and subscription management can be enabled independently. Narrow resource access and confirm the affected plans become Unassigned; cancel the confirmation to preserve access. Check an old `/team/coaches` link returns to Team & access.

### Recovery

Keep staff edits paused. If the SQL transaction failed, it rolled back and no restoration is needed. If recovering a completed rollout before staff edits resume, restore the saved membership/invitation permission statements in one transaction, then delete only `20261022051321_unified_staff_permissions.sql` from `booking_app.schema_migrations` in that transaction. Restore compatible previous API and client builds together. If owners have already changed permissions, reconcile each affected record against audit history rather than overwriting their changes with the old backup. Coaching assignments are not changed by this migration and must not be reverted as part of permission recovery.


## Verification of the unified flow

- Targeted Flutter analysis: no issues. The unrelated full-project analysis finding in `test/admission_overview_test.dart` was left untouched.
- All 49 focused Flutter tests passed across staff assignment, staff coaching, My classes, responsive workspace layouts, admissions, route guards/configuration, repository isolation and court coaching. These cover explicit permission selection, failed staff saves, edits during an in-flight save, saved resource eligibility, owner coaching, and plan assignment inside staff details.
- All 41 focused backend tests passed across admissions, court admissions, workspace authorization and permission migration. Coach-only invitations do not acquire operational permissions, attendance grants/revocation and current resource/plan boundaries are enforced, booking and subscription grants are independent, and the compatibility backfill preserves pending invitations without duplicate grants. All database tests use isolated in-memory storage.
- TypeScript build, Edge type check and generated Edge bundle build passed.
- JavaScript Flutter web debug build passed with `--no-wasm-dry-run`; this disables the optional extra Wasm compatibility compilation. Desktop and phone staff layouts were rendered and reviewed locally.
- Android debug APK build passed; the APK is `build/app/outputs/flutter-apk/app-debug.apk`. It was not installed on a device.
- An optional full backend run was stopped after 147 passing checks because concurrent compilation caused severe resource contention; it is not recorded as a full-suite pass. The final affected backend suites were rerun serially and passed as listed above.

No hosted deployment, live migration or device installation was performed.
