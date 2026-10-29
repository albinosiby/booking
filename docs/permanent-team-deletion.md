# Permanently delete removed team records

## What changes

In Profile → Team & access, **Delete permanently** appears on removed staff/managers and cancelled, unaccepted invitations. Active people must first have access removed. Pending invitations must first be cancelled. Owner identities and service identities are protected by the API. A confirmation names the saved person/email and explicitly says the action cannot be undone.

Deleting a removed member deletes their organization membership, any residual assignments, and that email's accepted/cancelled invitation records in the same organization. An outstanding pending grant must be cancelled first. Coaching references are cleared. Deleting a cancelled invitation deletes only that invitation. Bookings, payments, admissions, attendance, transaction/audit history and Supabase Auth login accounts are retained. No Auth admin deletion API is called. Historical author IDs and names already stored in history remain; this is not an erasure of historical transactions.

Support tickets/messages are also preserved. The migration allows a ticket's member reference to become NULL when a membership is deleted, without clearing its organization. Admin ticket lists/details use a left join and show “Removed team member” instead of hiding the ticket.

The Cubit removes a confirmed deleted record from its cached list before reloading. If deletion fails, the tile stays with an error/retry path. Server authorization and eligibility are rechecked inside the transaction. Email-grant locking prevents an invitation claim from racing with deletion. Other protected foreign-key references cause a rollback with a clear conflict rather than deletion of unrelated data.

## Required migration — user applies

**Apply the migration before deploying this API.** No live data has been deleted and no live schema change has been applied by the agent.

File: `supabase/migrations/20261024050810_permanent_team_deletion.sql`.

Prerequisites:

- Use project `scwwkaywewecspsrskft` (booking), as its database owner.
- PostgreSQL 15+ supports setting only the member column of a composite foreign key to NULL. See the [PostgreSQL foreign-key documentation](https://www.postgresql.org/docs/15/ddl-constraints.html#DDL-CONSTRAINTS-FK).
- Apply earlier project migrations first, including the admin/support tables. The existing application schema is `booking_app`.
- Take a project backup/snapshot first. Before using permanent deletion, privately back up the selected membership, assignments, invitations and ticket member references if recovery might be needed. Do not commit exports containing personal data.

Read-only prerequisite check in Supabase SQL Editor:

```sql
SHOW server_version;
SELECT column_name, is_nullable
FROM information_schema.columns
WHERE table_schema='booking_app' AND table_name='support_tickets'
  AND column_name IN ('membership_id','organization_id');
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid='booking_app.support_tickets'::regclass AND contype='f';
SELECT name FROM booking_app.schema_migrations
WHERE name='20261024050810_permanent_team_deletion.sql';
```

If already recorded, do not apply it twice. Otherwise open the migration file, copy its complete contents into SQL Editor and run it once. It is wrapped in a transaction with a lock timeout and records its own migration name. It changes a constraint/index only; it does not delete existing team records. If a lock timeout or missing prerequisite stops it, fix the prerequisite and rerun the complete file, rather than running fragments.

If SQL Editor reports `relation "support_tickets" does not exist`, do not recreate the table. The live table belongs to `booking_app`. Use the **Supabase** migration file above, not the unqualified `backend/migrations/` copy used by local tests. Run its complete contents (BEGIN through COMMIT), with no selected fragment. The Supabase file qualifies every table explicitly. If a previous query left an aborted transaction, run `ROLLBACK;` first, then rerun the complete file. Confirm the migration is not already recorded before rerunning it.

Validation queries:

```sql
SELECT name FROM booking_app.schema_migrations
WHERE name='20261024050810_permanent_team_deletion.sql';
SELECT is_nullable FROM information_schema.columns
WHERE table_schema='booking_app' AND table_name='support_tickets'
  AND column_name='membership_id';
SELECT pg_get_constraintdef(oid) FROM pg_constraint
WHERE conrelid='booking_app.support_tickets'::regclass
  AND conname='support_tickets_membership_id_organization_id_fkey';
SELECT to_regclass('booking_app.support_tickets_membership_idx');
```

Expected: migration row present; `YES`; foreign key includes `ON DELETE SET NULL (membership_id)`; index exists. `organization_id` remains NOT NULL.

## Deploy the prepared API, then update the app/web client

From the repository root, using the configured Node/npm environment and an authenticated Supabase CLI:

```sh
cd "/Users/albinosiby/Tatos Dev/booking"
npm --prefix backend run build
npm --prefix backend run edge:check
npm --prefix backend run edge:build
npx supabase functions deploy booking-api --project-ref scwwkaywewecspsrskft --use-api --no-verify-jwt
curl -i "https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/health"
```

Expected health revision: `2026-10-24-permanent-team-deletion`. Keep existing secrets and internal Supabase Auth verification. The existing gateway configuration is unchanged. Update the Flutter app/web client through your usual release process; API deployment alone cannot add a button to an old client. No APK build or installation was performed.

Endpoints (owner-authenticated):

- `DELETE /v1/team/:id/permanent` — inactive staff/manager only.
- `DELETE /v1/invitations/:id/permanent` — cancelled, unaccepted invitation only.

Both return `{ "id": "…", "deleted": true }`. Active/otherwise ineligible records return conflict; missing or foreign-organization records are not deleted.

## Verify safely

Use disposable records in a test organization first. Cancel the dialog once and check no request changed data. Confirm deletion and check the tile disappears. Confirm another active staff member, owner and pending invitation have no permanent-delete action. Check existing bookings, payments and attendance still have their original author IDs. If the deleted staff member had a support ticket, confirm the ticket/messages remain in the organization and admin views. Confirm their Supabase Auth account still exists; signing in does not restore membership without a new explicit owner grant.

Read-only checks after deleting a test member (replace UUID):

```sql
SELECT id FROM booking_app.memberships WHERE id='<member UUID>'::uuid;
SELECT membership_id FROM booking_app.staff_assignments
WHERE membership_id='<member UUID>'::uuid;
SELECT action, actor_id, created_at FROM booking_app.audit_events
WHERE entity_id='<member UUID>' ORDER BY created_at DESC;
```

Expected: no team/assignment rows; `staff.permanently_deleted` audit event remains. Verify selected history row IDs before/after; do not run broad deletes manually.

## Recovery

Before any permanent deletions, this migration can be rolled back transactionally after checking there are no NULL ticket references:

```sql
SELECT count(*) FROM booking_app.support_tickets WHERE membership_id IS NULL;
```

If zero, and permanent-delete routes have been disabled or rolled back in the API:

```sql
BEGIN;
SET LOCAL search_path=booking_app,pg_catalog;
SET LOCAL lock_timeout='10s';
ALTER TABLE support_tickets
  DROP CONSTRAINT support_tickets_membership_id_organization_id_fkey,
  ADD CONSTRAINT support_tickets_membership_id_organization_id_fkey
    FOREIGN KEY(membership_id,organization_id) REFERENCES memberships(id,organization_id);
ALTER TABLE support_tickets ALTER COLUMN membership_id SET NOT NULL;
DROP INDEX support_tickets_membership_idx;
DELETE FROM schema_migrations WHERE name='20261024050810_permanent_team_deletion.sql';
COMMIT;
```

After permanent deletion, code rollback cannot restore a deleted member/invitation or the old ticket reference. Keep the nullable schema unless the exact records and references have been restored from a backup under review. Do not invent an owner/author replacement merely to satisfy NOT NULL. An owner can grant access again using the existing login email; that creates a new team membership, not a restoration of the deleted identity. Historical bookings/payments/attendance remain intact either way. Database backups may retain deleted team records until their normal retention period ends.


## Removed owner linked-record repair

For deletion blocked by an agent-service request or migrated login identity, apply the follow-up described in [Removed owner deletion repair](removed-owner-deletion-repair.md). It preserves both records and their original identity IDs. Removed owners can be deleted by another active owner; active owners and self-deletion remain protected. Other protected references still block deletion.
