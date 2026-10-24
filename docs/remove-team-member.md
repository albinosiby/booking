# Remove staff or manager

## Owner flow

Open Profile → Team & access. Use Remove staff / Remove manager on a member tile, or open the member and use the removal button below the access/coaching settings. Confirm the saved member's name and email. Choosing Keep member makes no request; unsaved form edits are not saved by removal.

Removal is a soft deletion. The member remains in team history as Access removed. Their membership is deactivated, business/space assignments are cleared, assigned coaching plans become Unassigned, and outstanding invitations for that email in the same organization are cancelled. Bookings, payments, customer records, attendance and audit history are retained. Their authentication account is not deleted.

Only an organization owner can remove staff or managers in that organization. Owners and service accounts cannot be removed through this action. Duplicate clicks are disabled while saving. A failure keeps the details screen available for retry. The team list keeps a confirmed removal visible even if its subsequent refresh fails.

The server rejects removed members immediately. Their open app clears restricted content on its next successful access check (normally within 30 seconds in the foreground, plus network time), on resume, or after a denied API request. An offline device cannot receive a permission update, but it cannot bypass server authorization to save.

## Migration

**Access removal itself needs no database migration.** The current codebase also includes permanent deletion: apply its [required migration](permanent-team-deletion.md) before deploying the latest API. Access removal uses the existing membership active flag, staff assignments, invitations, coaching configuration and audit tables. Do not delete membership, booking, payment or attendance rows manually.

## API deployment

The app UI changes require updated Flutter code. The assignment and pending-invitation cleanup requires deploying the updated booking-api. Existing function secrets and private-schema privileges are reused.

From a terminal:

```sh
cd "/Users/albinosiby/Tatos Dev/booking"
npm --prefix backend run build
npm --prefix backend run edge:check
npm --prefix backend run edge:build
npx supabase functions deploy booking-api --project-ref scwwkaywewecspsrskft --use-api --no-verify-jwt
curl -i "https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/health"
```

Prerequisites: use the existing Node/npm setup, sign the Supabase CLI into the project-owning account, and keep the existing BOOKING_DATABASE_URL/CA secrets. The function already verifies Supabase Auth internally; the existing gateway configuration is unchanged. For the latest health revision, see the [permanent deletion deployment guide](permanent-team-deletion.md). No APK is built or installed by these steps.

## Validate

Use a disposable staff account in a test organization. Create/assign a coaching plan and save a booking/payment/attendance record under that member. Cancel the removal dialog once; verify no changes. Confirm removal, then verify the member shows Access removed, their spaces are no longer assigned and the plan is Unassigned. Verify previous bookings, payments and attendance retain their recorded author. Test a manager, forbidden non-owner access, and a foreign-organization member. The owner must have no removal control.

Optional read-only SQL in Supabase SQL Editor (replace the member UUID first):

```sql
SELECT id, display_name, active FROM booking_app.memberships
WHERE id = '<member UUID>'::uuid;
SELECT business_id, resource_ids FROM booking_app.staff_assignments
WHERE membership_id = '<member UUID>'::uuid;
SELECT action, actor_id, created_at FROM booking_app.audit_events
WHERE entity_id = '<member UUID>' ORDER BY created_at DESC;
```

Expected: the membership still exists with active=false, no assignments remain, and a staff.revoked event is present. Use the member's existing email in Team & access to grant access again if removal was accidental. Review permissions and reassign spaces/coaching plans explicitly; removal does not automatically restore old assignments. Historical data remains unchanged. No schema rollback is needed. To roll back code, deploy the previous reviewed function bundle and Flutter source; this does not reactivate removed members.
