# Removed owner deletion repair

Preserves agent-service requests and migrated login identities after deleting an
inactive team membership. Original actor/membership IDs remain unchanged; only
the two foreign-key dependencies are removed. Active membership is still required
for organization access. No login, business, booking, payment, attendance, request
or migration identity is deleted by this migration. Other protected references,
such as cash settlements, still block deletion and roll back the entire operation.

## Prerequisites

Use the **booking** project (`scwwkaywewecspsrskft`) SQL Editor as database owner.
Have a restorable backup and securely export the removed membership/invitations
before confirming permanent deletion. Keep another active owner signed in.
Do not run provisioning scripts against the existing project.

```sql
SELECT c.conrelid::regclass AS table_name,c.conname,pg_get_constraintdef(c.oid)
FROM pg_constraint c WHERE c.contype='f'
AND c.confrelid='booking_app.memberships'::regclass ORDER BY 1;
SELECT name FROM booking_app.schema_migrations
WHERE name='20261029054331_preserve_removed_owner_identity.sql';
```

Before the first run, expect the agent request FK. The migration-identity FK may
be absent on newer installations. If the migration is already recorded, validate
it rather than running again. Stop if the expected table/constraint differs.

## Apply migration yourself

Run the entire file in the SQL Editor:

`supabase/migrations/20261029054331_preserve_removed_owner_identity.sql`

Use this Supabase copy, not the backend copy. It explicitly qualifies tables with
`booking_app`, runs transactionally and has a 10-second lock timeout. On failure,
run `ROLLBACK;` and resolve the error before retrying. No live migration has been
applied by the agent.

## Validate

```sql
SELECT name FROM booking_app.schema_migrations
WHERE name='20261029054331_preserve_removed_owner_identity.sql';
-- Expect one row above and zero below.
SELECT conname FROM pg_constraint
WHERE connamespace='booking_app'::regnamespace AND conname IN (
 'agent_call_requests_membership_id_organization_id_fkey',
 'migrated_identities_actor_id_fkey');
-- Both historical identity columns remain NOT NULL.
SELECT table_name,column_name,is_nullable FROM information_schema.columns
WHERE table_schema='booking_app' AND
 ((table_name='agent_call_requests' AND column_name='membership_id') OR
 (table_name='migrated_identities' AND column_name='actor_id'));
```

## Deploy API after migration

```sh
cd "/Users/albinosiby/Tatos Dev/booking"
npm --prefix backend run build
npm --prefix backend run edge:check
npm --prefix backend run edge:build
npx supabase functions deploy booking-api --project-ref scwwkaywewecspsrskft --use-api --no-verify-jwt
curl -i "https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/health"
```

Expected revision: `2026-10-29-preserve-removed-owner-identity`.
The gateway flag retains existing configuration; internal Supabase Auth and
organization authorization remain enforced. No client/APK update is required.
Refresh Team & access and retry the intended permanent deletion as the remaining
owner. Check the named person before confirming. Confirm businesses/history stay,
the removed login cannot access the organization, and the agent request remains
visible in admin with `Removed team member` as its requester label. Do not delete
real users just to test deployment.

## Recovery

Before deletion, the constraints can be restored if there are no orphan links.
After deletion, restore the exact team/invitation records from backup first.
Never delete agent requests or identity mappings just to satisfy constraints.
Check these queries return no rows before restoring constraints:

```sql
SELECT r.id,r.membership_id FROM booking_app.agent_call_requests r
LEFT JOIN booking_app.memberships m
 ON m.id=r.membership_id AND m.organization_id=r.organization_id WHERE m.id IS NULL;
SELECT i.email,i.actor_id FROM booking_app.migrated_identities i
LEFT JOIN booking_app.memberships m ON m.user_id=i.actor_id WHERE m.id IS NULL;
```

Then, only if restoring the previous schema is necessary:

```sql
BEGIN;
SET LOCAL lock_timeout='10s';
ALTER TABLE booking_app.agent_call_requests
 ADD CONSTRAINT agent_call_requests_membership_id_organization_id_fkey
 FOREIGN KEY(membership_id,organization_id)
 REFERENCES booking_app.memberships(id,organization_id);
ALTER TABLE booking_app.migrated_identities
 ADD CONSTRAINT migrated_identities_actor_id_fkey
 FOREIGN KEY(actor_id) REFERENCES booking_app.memberships(user_id);
DELETE FROM booking_app.schema_migrations
WHERE name='20261029054331_preserve_removed_owner_identity.sql';
COMMIT;
```

Omit the identity ALTER if that constraint/table did not exist before the repair.
Revert the local migration file before restarting a backend configured to apply
migrations automatically. Code rollback alone cannot restore deleted team records.
Re-granting access creates a new membership, not restoration of the old identity.
