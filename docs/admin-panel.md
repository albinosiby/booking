# Admin panel

Next.js app in `admin-panel/` (port 3100, base path `/admin`). Open `http://127.0.0.1:3100/admin/login` for local development. It talks only to the booking API under `/v1/admin/*`; admin routes verify signed server requests from the password-protected panel. Credentials are never returned for any organization. For the shared container, follow [Railway deployment](railway-deployment.md).

## Pages
Overview, Organizations (+ full detail: profile, team, businesses, locations, invitations, website, bookings summary, tickets, call-service request), Users (activate/deactivate), Support inbox (reply, status), Agent call requests (status, user-facing message, internal notes), Audit log.

## Interface

The admin workspace uses a light theme with white cards, a soft grey canvas and green accents. Navigation is grouped into Workspace and Operations, with an active-page indicator. At narrow widths a native modal navigation drawer supports keyboard focus and Escape dismissal. Overview uses live totals and the five most recently created organizations; its active-user bar is calculated from the returned membership counts. There are no invented trends or chart datasets.

Organization and user searches use shareable query parameters. Support and agent-call filters retain their URL-based behavior. Mutation buttons show a pending state. Loading, empty and retry views use the same visual system. The login keeps a single password field with an optional show/hide control; signing and session checks remain server-side. No extra UI, animation, chart or font dependency is required.

Preview locally with the existing production build and `npm run start`. The disposable `deploy/test/mock-api.mjs` supports populated directory and overview screens and empty support/agent/audit screens for verification; it is never part of the production image. A Railway redeploy is required to publish source changes.

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
2. Admin: **Agent calls** opens a responsive request tile grid (three columns on desktop, two on tablet, one on mobile). Each tile shows live organization/requester details, status, requested/approved services, a customer-note preview and timestamps. Status tabs filter the API results, ordered by latest update; the count is the number shown, not a platform-wide total. Select any tile to open its organization-specific setup screen. There are no inline configuration forms on the list.
3. The setup screen identifies the organization and provides four section links: **Connection**, **Agent tools**, **Verification**, and **Client status**. Save provider IDs, phone number, API key and approved services; generate the tool key (shown once) and configure the provider tools. Review the full customer note here. Configuration changes disable service access and require verification again.
4. Verify the connection and then set the client status to **Active**. Client-facing messages and private admin notes are edited in **Client status**. Existing server-side permissions, version conflict checks and verification requirements remain enforced. The client selects spaces and enables approved services after activation.

The list and setup routes have separate loading placeholders and a scoped retry view. This interface change requires only an admin-panel deployment; it introduces no schema migration, API contract change or live data cleanup.

## Support
Owners and team members use Profile → Help & support to report issues; admins reply from the panel and the thread updates in the app.

## Removed
The owner-facing connect/publish/disconnect screens and routes (`/v1/sarvam/*` owner routes) are gone; call routes moved to `/v1/agent-calls/*`. Old installed app builds will lose that screen. The tool/OAuth callback routes remain.
