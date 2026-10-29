# Admin voice MCP credential migration

The user applies this migration. Implementation and tests use an isolated,
in-memory database; no live migration has been applied.

Files:

- Hosted Supabase: `supabase/migrations/20261029105442_admin_voice_mcp_credentials.sql`.
- API migration ledger / local test database: `backend/migrations/20261029105442_admin_voice_mcp_credentials.sql`.

The migration creates only `booking_app.admin_mcp_credentials`. Existing client
bookings and Sarvam configuration are not changed. Raw automation tokens are
never stored in the table. The new transport does not use `ADMIN_SESSION_SECRET`.

## Before application

1. Confirm the target project and database are the BookingOS production project,
   not another linked Supabase project. Back up the database using the normal
   project backup procedure.
2. Confirm the previously released migrations are applied, the `booking_app`
   schema and `booking_api` role exist, and `BOOKING_SECRETS_KEY` remains configured
   on the backend. Keep that existing encryption key unchanged.
3. Read the hosted SQL file. Run it once in the project's SQL editor as the
   migration owner. It uses a transaction, a ten-second lock timeout, a schema
   search path, RLS, explicit API-role privileges and the backend migration ledger.
   Alternatively apply this exact file through the project's existing reviewed
   migration deployment process.
4. Deploy the matching backend only after successful application. Do not start a
   production API with automatic migrations enabled. Use `DATABASE_MIGRATE=false`.

## Validation

Run these metadata queries; they do not reveal credential hashes or values:

```sql
SELECT name, applied_at
FROM booking_app.schema_migrations
WHERE name = '20261029105442_admin_voice_mcp_credentials.sql';

SELECT c.relname, c.relrowsecurity
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'booking_app' AND c.relname = 'admin_mcp_credentials';

SELECT grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'booking_app'
  AND table_name = 'admin_mcp_credentials'
  AND grantee IN ('anon', 'authenticated', 'booking_api')
ORDER BY grantee, privilege_type;
```

Expect one ledger row, `relrowsecurity=true`, no grants to `anon` or
`authenticated`, and only SELECT/UPDATE for `booking_api`. An explicit RLS policy
allows that backend role to authenticate and update last-used timestamps; no
owner/staff policy is created. Create the first scoped, expiring automation
credential through the documented private bootstrap process after deployment.

## Revocation and recovery

Revoke a credential immediately by its known ID without exposing its hash:

```sql
UPDATE booking_app.admin_mcp_credentials
SET revoked_at = now()
WHERE id = 'REPLACE_WITH_CREDENTIAL_UUID' AND revoked_at IS NULL;
```

Every new request checks revocation and expiry. Revocation disables the MCP
transport; it does not disable client bookings or the normal admin panel. If the
application version must be rolled back, revoke the new credentials and roll back
the application first. Leave this additive table and its ledger row in place;
older application versions ignore it. Do not drop the table or alter existing
client setup state as an automatic rollback.

If application fails before COMMIT, the migration transaction rolls back. Inspect
the error and metadata before retrying the same file; do not mark its ledger row
applied independently. If any setup was already started, resume/reconcile its
saved provider references after repairing authorization. Do not delete unrelated
provider deployments or repeat a secret/agent creation blindly.

An `OUTCOME_UNKNOWN` failure means a remote operation may already have succeeded.
Keep the same job and operation identifiers and reconcile the saved unique
agent/secret name, tool definition, immutable version or number deployment. An
immediate empty read after a timeout is not proof that creation failed. Wait for
provider read-back or review the operation; do not allocate a second resource.
An existing secret name alone does not prove its value. If the provider cannot
update the job-owned secret through its supported API, stop for private
credential recovery rather than deploying with an unverified reference.
