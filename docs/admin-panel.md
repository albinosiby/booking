# Admin panel

Next.js app in `admin-panel/` (port 3100, base path `/admin`). Open `http://127.0.0.1:3100/admin/login` for local development. It talks only to the booking API under `/v1/admin/*`; admin routes verify signed server requests from the password-protected panel. Credentials are never returned for any organization. For the shared container, follow [Railway deployment](railway-deployment.md).

## Pages
Overview, Organizations (+ full detail: profile, team, businesses, locations, invitations, website, bookings summary, tickets, call-service request), Users (activate/deactivate), Support inbox (reply, status), Agent call requests (status, user-facing message, internal notes), Audit log.

## Prerequisites (you apply these)
1. Apply `supabase/migrations/20261023100000_admin_panel.sql` (not applied by this change).
2. Generate a random secret with `openssl rand -hex 32`. Set `ADMIN_SESSION_SECRET` to that same value in the panel environment (Railway variables in production) and the `booking-api` Edge Function secrets. Keep this separate from the login password. Backend secret setup is documented by [Supabase](https://supabase.com/docs/guides/functions/secrets).
3. Build and deploy the updated `booking-api` function with signed admin request support. Keep `verify_jwt = false` in `supabase/config.toml`; the application checks admin signatures and retains Supabase Auth checks for owner/staff routes.
4. Set `ADMIN_PANEL_PASSWORD="tatos tech"` in the panel environment. No Supabase Auth user, platform-admin membership row, service email or service password is needed for the panel.

Validate the existing tables without changing data:
```sql
SELECT to_regclass('booking_app.admin_audit_log'),
       to_regclass('booking_app.support_tickets'),
       to_regclass('booking_app.agent_call_requests');
```
After deployment, check that `/v1/admin/overview` rejects unsigned requests and that signing in to `/admin/login` loads the overview. Owner/staff routes must still reject requests without their normal user token.

For recovery from an authentication rollout, restore the previous API and panel releases together and their previous environment configuration. Rotate the shared signing secret on both servers together to invalidate sessions and request signatures. No schema change is introduced by password-only authentication.

Rollback (only if unused): `DROP TABLE booking_app.admin_audit_log, booking_app.support_messages, booking_app.support_tickets, booking_app.agent_call_requests, booking_app.platform_admins; DELETE FROM booking_app.schema_migrations WHERE name='20261023100000_admin_panel.sql';`

## Run
```bash
cd admin-panel && cp .env.example .env.local   # configure the matching signing secret and public API key
npm install && npm run dev
```
The login asks for one password, **`tatos tech`**, with no username. This value is configured by the server-side `ADMIN_PANEL_PASSWORD` variable in the local environment and deployment template. Set that same variable in Railway and redeploy to apply it there. The panel creates a signed, twelve-hour httpOnly session cookie scoped to `/admin`. The server signs each API request using the random shared secret; signatures expire after 60 seconds and cover the HTTP method, path, query and JSON body. The session cookie cannot be used as an API signature. `ADMIN_SERVICE_EMAIL` and `ADMIN_SERVICE_PASSWORD` are no longer used. Admin actions are audited as `admin-panel@bookingos.internal`; a shared password does not identify individual operators. Expired sessions return to `/admin/login`.

## Agent call service flow
1. Owner: Profile → Agent call service → Request service (no provider name is shown anywhere in the app).
2. Admin: Agent call requests → move status (Requested → In review → Setting up), write the message the owner sees, open **Connection** to save the provider IDs/API key and businesses, and generate the tool key (shown once; paste it into the provider agent with the tool base URL).
3. Admin sets the request to **Active**. The owner's page then shows the on/off switch and Call logs. The service is "ready" only when Active *and* a connection and tool key exist; turning on also needs at least one business assigned.

## Support
Owners and team members use Profile → Help & support to report issues; admins reply from the panel and the thread updates in the app.

## Removed
The owner-facing connect/publish/disconnect screens and routes (`/v1/sarvam/*` owner routes) are gone; call routes moved to `/v1/agent-calls/*`. Old installed app builds will lose that screen. The tool/OAuth callback routes remain.
