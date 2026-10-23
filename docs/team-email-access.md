# Email-based team access

## Owner and staff workflow

In **Profile → Team & access → Add team member**, enter the person's name and email, select Staff or Manager, choose their businesses/resources and enable only the permissions they need. Add team member saves pending access and sends an email through Nodemailer. The email names the organization, responsibility, businesses/resources and permissions, with **Web login** and **App login** links. Owners do not copy or share a private invitation link.

The person signs in with Google using that exact email. A server-verified email/password session with the same email also works. The authenticated workspace bootstrap activates the saved membership and assignments before returning the workspace, so routing opens the dashboard without an Accept button or organization setup. The pending entry has no seven-day deadline: it remains available until the owner cancels it. It does not itself create a Google/Supabase account or set a password.

Team reads current server state on each visit and **Refresh team** action. It shows **Awaiting sign-in** separately from active members, with Email sent, Email not sent, Sending email or Email pending. Each pending card has a visible **Cancel access** button (or **Cancel invitation** for older link invitations); its menu supports **Edit access** and **Resend access email**. Editing pending access sends an updated summary. Active staff cards show an edit icon and a visible **Remove access** button on both app and web. Owner and already-removed cards have no removal button. Cancelling pending access and removing an active member require confirmation. Removal takes effect on subsequent authorized API requests; it does not delete the person's Google account. Re-adding a removed person to the same organization requires a fresh explicit owner grant.

Nodemailer sends HTML and plain-text versions. An SMTP acceptance is recorded as sent; it is not proof of inbox delivery. A delivery failure preserves the saved grant and shows an actionable message. Resend is limited to once per 30 seconds. An interrupted send can be retried after its two-minute sending lease; a duplicate notification is possible if the provider accepted a message but the request was interrupted. There is no scheduled delivery worker: owners retry failed or interrupted emails from Team.

The app link is `bookingservice.tatos.tech://login/sign-in`; it opens the installed app. Some email clients block custom schemes. The email also includes the HTTPS web login and tells the recipient to open the app manually if necessary. This does not install the app or redirect through an app store. Existing `com.bookingos.app://invite/invite` links remain supported for older invitations.

## Architecture and API

UI → feature Cubit → TeamRepository → authenticated API → private `booking_app` tables. Identity comes from the server's verified authentication check, never a submitted email, UI state or user metadata. API authorization remains scoped to current membership, permissions and assignments.

- `POST /v1/team`: owner only. Existing staff draft body (`display_name`, `email`, `role`, `permissions`, `assignments`). Saves a pending email grant, commits, attempts mail, and returns `{ "id": "<uuid>", "delivery": "sent" }` or `"failed"`. No invitation URL or login token is returned.
- `PATCH /v1/invitations/:id/access`: owner only, same body. Edits a pending email grant in the same organization. Email cannot be changed; cancel and add the correct address instead. Returns its ID and delivery status.
- `POST /v1/invitations/:id/email`: owner only. Resends the access summary for a pending email grant in the same organization. Returns delivery status. A recent/in-progress send or changed entry returns 409.
- `POST /v1/workspace/session`: authenticated verified identity, body `{}`. Activates a matching owner-created email grant and returns the regular workspace response. Existing active members retain their current organization. Ordinary `GET /v1/workspace` remains read-only.
- Existing `PATCH /v1/team/:id`, `DELETE /v1/team/:id` and `DELETE /v1/invitations/:id` handle accepted-member edits, removal and pending cancellation.
- Legacy `POST /v1/invitations` and token acceptance remain compatible. Legacy invitations do not auto-activate.

Pending email grants use `invitations.join_mode='email_login'`; older rows default to `link`. Delivery state and attempt timestamps are stored on the same row. A partial unique index permits only one uncancelled, unaccepted email grant per normalized email across organizations. Membership's unique user ID, transaction locks and an email-specific advisory lock make repeated/concurrent session activation idempotent. Only assigned businesses/resources are copied, and accepted/cancelled rows cannot grant access again. Existing private-schema permissions are retained; there are no public tables, new RLS bypasses or service keys in the client.

## Configure the sender

Nodemailer is the SMTP client; the SMTP provider supplies the outgoing mail service. Supabase's Google client ID/secret and its Auth email templates do not configure this application email transport. See [Nodemailer SMTP settings](https://nodemailer.com/smtp).

Set these in the **booking-api Edge Function's server secrets**, or in the Node API's server environment. Keep the password out of Flutter, web bundles, Git, screenshots and chat:

```dotenv
SMTP_HOST=smtp.your-provider.example
SMTP_PORT=465
SMTP_USER=your-provider-username
SMTP_PASSWORD=your-provider-secret
SMTP_FROM=team@your-domain.example
TEAM_LOGIN_WEB_URL=https://bookingos.online/app/sign-in
```

`SMTP_FROM` is a single sender email address authorized by the provider. Configure its required sender/domain verification and DNS records. Port 465 uses immediate TLS; another configured port requires STARTTLS and a valid certificate. Confirm the chosen SMTP host/port is reachable from the hosted runtime. Connections and reads have bounded timeouts; SMTP credentials, responses and message bodies are not logged or returned to clients.

The optional `TEAM_LOGIN_WEB_URL` must be an HTTPS URL ending in `/sign-in`, without credentials, query or fragment. Its default is the URL above. The local Node environment may use an HTTP localhost sign-in URL. It is independent of `PUBLIC_APP_URL`, which other services already use for API/legacy-link URLs.

## Migration: project owner applies

No hosted schema change, deployment or real email send was performed by this implementation.

Migration: `supabase/migrations/20261023120009_email_team_access.sql`. Node counterpart: `backend/migrations/20261023120009_email_team_access.sql`. Apply only the version for the database being deployed; never execute both on the same database.

### Prerequisites and backup

1. Confirm the booking project (`scwwkaywewecspsrskft`), private `booking_app` schema, and all earlier migrations, including the unified staff permissions, staff coaches and admin panel migrations. Keep compatible previous API/client builds for recovery.
2. Pause team edits and new staff onboarding during rollout. Take the project's normal database backup and export the current invitations, memberships, staff assignments and relevant audit events privately.
3. In Supabase SQL Editor, run these read-only checks:

```sql
SELECT name FROM booking_app.schema_migrations ORDER BY name;
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema='booking_app' AND table_name='invitations'
ORDER BY ordinal_position;
SELECT id, email, organization_id, accepted_at, revoked_at, expires_at
FROM booking_app.invitations ORDER BY created_at DESC;
```

### Apply and release

1. Execute the complete Supabase migration in SQL Editor. It includes a transaction, private search path, 10-second lock timeout and the application migration-ledger entry. Do not rerun it if its filename is already recorded. A failed transaction rolls back; diagnose the error before retrying.
2. Configure the sender secrets above on `booking-api`. The application database role needs its existing invitation SELECT/INSERT/UPDATE and membership/assignment permissions; adding columns does not require a new public grant.
3. Deploy the rebuilt `supabase/functions/booking-api/index.ts` with its existing authentication configuration. Its public `/health` response should report revision `2026-10-23-team-email-access`. No `booking-notifications` deployment is required for this feature. For a Node deployment, apply the matching backend migration through the normal migration process and release the updated backend.
4. Release Flutter web and app together. Updated clients use the new session-bootstrap endpoint and require the updated API. Retain earlier mobile callback allowlist entries during the existing auth transition. The new login app link is handled by the updated app; it is not an OAuth callback and does not replace the configured Supabase callback.
5. Run the validation below, then reopen team edits. Do not automatically apply this migration from the Flutter app or an API request.

### Validate

```sql
SELECT name FROM booking_app.schema_migrations
WHERE name='20261023120009_email_team_access.sql';
SELECT indexname, indexdef FROM pg_indexes
WHERE schemaname='booking_app'
AND indexname IN ('pending_email_team_access','active_membership_email');
SELECT id, email, join_mode, email_status, email_attempted_at, email_sent_at,
       accepted_at, revoked_at
FROM booking_app.invitations ORDER BY created_at DESC;
```

Add a test team member with restricted resources and only View bookings. Confirm the email's organization, role, scope and both login links. Sign in with the exact email through Google on web and the updated app: it must open the dashboard without Accept or organization setup. Another email must not receive the access. Check the granted membership/assignments in SQL. Edit active permissions and verify API enforcement, cancel an unused pending entry and verify sign-in cannot claim it, then remove active access and verify subsequent operations are denied. Test SMTP failure and Resend without adding duplicate grants. Do not use customer addresses for release testing without authorization.

### Recovery

If the migration transaction fails, no rollback script is needed. If the application rollout fails after migration, restore the compatible earlier API and client builds together; additive columns can remain safely. Pause team onboarding until the new flow is restored. Old clients cannot activate new email grants.

For a complete schema rollback, export new email-grant rows and their associated activation audit events first. Reconcile already-active staff individually: dropping notification columns must not silently remove legitimate memberships or restore removed access. Cancel remaining pending email grants before returning them to the legacy schema, then execute this only after all updated clients/API are retired:

```sql
BEGIN;
SET LOCAL search_path=booking_app,pg_catalog;
SET LOCAL lock_timeout='10s';
UPDATE invitations SET revoked_at=now()
WHERE join_mode='email_login' AND accepted_at IS NULL AND revoked_at IS NULL;
DROP INDEX pending_email_team_access;
DROP INDEX active_membership_email;
ALTER TABLE invitations DROP CONSTRAINT email_team_access_no_expiry,
  DROP COLUMN join_mode, DROP COLUMN email_status, DROP COLUMN email_attempt_id,
  DROP COLUMN email_attempted_at, DROP COLUMN email_sent_at;
DELETE FROM schema_migrations WHERE name='20261023120009_email_team_access.sql';
COMMIT;
```

This preserves existing active memberships and legacy invitations. Recovery is owner-operated; never automatically restore a pre-rollout backup over subsequent owner edits.

## Local verification

- 66 focused Flutter tests passed across the new email workflow/repository, staff assignment/coaching, responsive team layouts, Google sign-in, route guards, startup and HTTP cache isolation. These include 320px and 1440px pending-access actions, failed email resend, cancellation confirmation, preserving a successful grant after a failed refresh, and direct dashboard routing.
- 54 focused backend tests passed across email access, Edge routing, workspace authorization, staff permissions and verified Supabase identity. The email suite exercises SMTP acceptance/rejection through a fake transport, preserves grants after failure, escapes names, prevents foreign resource/organization access, rejects duplicate grants and keeps concurrent activation idempotent. Tests used isolated in-memory storage and sent no network email.
- Targeted Flutter analysis and strict Node/Edge TypeScript source checks passed. Edge bundling passed. The generated handler imported successfully in Deno and Nodemailer 10.2.0 rendered a MIME message through a local stream transport. The dependency is pinned in both package lock and Edge mapping.
- An additional strict `deno check` on the minified JavaScript bundle stored as `index.ts` produced generated-code inference diagnostics. The authoritative type checks are `npm run build` and `npm run edge:check` on the TypeScript sources; the Deno smoke check verifies runtime loading without re-type-checking the generated JavaScript.
- Release web build passed with `/app/` as its base path. Android debug APK build passed; packaged application ID `bookingservice.tatos.tech` and its `/sign-in` login intent were verified. Build-source fingerprints stayed unchanged, and original BookingOS artwork was verified in both outputs. No APK was installed. iOS was not built in this verification.

Live SMTP delivery and end-to-end Google sign-in against the deployed email-access API still require the owner-operated configuration, migration and rollout checks above.
