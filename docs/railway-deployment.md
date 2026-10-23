# One Railway service for all four frontends

The repository-root `Dockerfile` builds the landing page, public booking website, Flutter owner/staff web app and admin panel into one image. Nginx is the public entry point on Railway's `PORT`. Two standalone Next.js servers listen only on container loopback. The landing page and Flutter app are static files. The API, Auth and database continue using the existing Supabase project.

| Public route | Destination |
| --- | --- |
| `/` | BookingOS marketing landing page |
| `https://<organisation-slug>.bookingos.online/` | That organisation's published booking homepage |
| `/_landing/*` | Landing scripts, styles, images and video |
| `/app/` and `/app/*` | Flutter app, including direct-route refreshes |
| `/admin` and `/admin/*` | Admin panel and its separate assets |
| `/<organisation-slug>` and its booking subpaths | Public booking website |
| `/api/sites/*`, `/_next/*` | Public booking API proxy and assets |
| `/_health` | Readiness of the two Next.js servers and essential static files |

The gateway also redirects `/login` and `/sign-in` to `/app/sign-in`, and `/register`, `/signup`, `/sign-up` to `/app/register`, retaining query parameters. Missing Flutter/landing assets return 404. Admin pages require a signed session; its cookie is scoped to `/admin`.

## Railway settings

1. Push the complete change, including `landing-page/`, `admin-panel/`, `deploy/`, `Dockerfile`, `.dockerignore` and `railway.json`, to your repository.
2. Create **one Railway service** from that repository.
3. Set **Root Directory** to `/` (or leave it blank). The Dockerfile and Railway config paths are `Dockerfile` and `/railway.json` respectively.
4. Use the Dockerfile builder. Clear any old custom build/start commands: the Dockerfile's entry point starts the complete service.
5. Add the variables below before deploying.
6. Deploy. `railway.json` sets `/_health` as the deployment health check, with a 120-second startup timeout and an on-failure restart policy.
7. In **Settings → Networking → Public Networking**, choose **Generate Domain**. Use the listener port Railway assigns through `PORT`; the Docker default is 8080. Only the gateway is public.
8. Complete the Supabase URL configuration below, then run the smoke checks against the generated HTTPS URL.

Initial builds download the pinned Flutter 3.44.1 SDK and web engine. Subsequent builds reuse Docker layers. Frontend compiler stages are ordered to reduce peak build memory. All four frontends share CPU, memory, restarts and deployment revisions; monitor actual memory use and increase the service's resources if builds or runtime reach its limit. No persistent volume is required for these frontends.

## Railway variables

Use `deploy/railway.env.example` as the variable list. Do not copy local `.env.local` files into the image.

| Variable | Value / purpose |
| --- | --- |
| `SUPABASE_URL` | Current project HTTPS URL |
| `SUPABASE_PUBLISHABLE_KEY` | Public project key for Flutter |
| `BOOKING_API_BASE_URL` | `https://<project>.supabase.co/functions/v1/booking-api`, without a trailing `/v1` |
| `BOOKING_API_PUBLISHABLE_KEY` | Same public project key, used by the booking and admin servers |
| `ADMIN_PANEL_PASSWORD` | `tatos tech` — set this runtime variable for the password-only login; no username is requested |
| `ADMIN_SESSION_SECRET` | Random signing secret, at least 32 characters; generate with `openssl rand -hex 32` and set the same value in booking-api backend secrets |
| `BOOKING_APP_URL` | `/app` (already the image default) |
| `BOOKING_ROUTING_MODE` | `auto` (image default); custom-domain subdomains use booking pages and the generated Railway host keeps path routing. `subdomain` also enables this routing; `path` explicitly disables it. |
| `BOOKING_SITE_DOMAIN` | `bookingos.online` (image default); the base domain without `https://`, `*.` or a path |

The container refuses to start if a required setting is missing. It never prints variable values. The public booking server does not receive admin credentials, and neither Next.js child receives unrelated database secrets.

`SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` and `BOOKING_API_BASE_URL` are also declared as public Docker build arguments for Flutter. Railway makes matching variables available to the Docker build. Changing these values requires rebuilding the image; runtime changes alone cannot alter compiled Flutter JavaScript. Defaults match `dart-defines.example.json`. `AUTH_PROVIDER=supabase`, `USE_AUTH_EMULATOR=false` and Flutter's `/app/` base path are set by the Dockerfile.

The panel login is `tatos tech` with no username. Remove `ADMIN_SERVICE_EMAIL` and `ADMIN_SERVICE_PASSWORD` from Railway if previously added. Keep admin passwords and session secrets as runtime variables. No service-role key, database URL or private Firebase credentials belong in the frontend build.

## Supabase configuration after generating the URL

Substitute `https://YOUR-SERVICE.up.railway.app` below. These are manual settings, not schema migrations:

1. **Auth → URL Configuration:** use `https://YOUR-SERVICE.up.railway.app/app/auth-callback` as the web **Site URL**, because the current Flutter web Auth adapter uses the configured Site URL for email verification and password recovery. Add that exact callback to allowed redirects. Retain the existing mobile callback and any other legitimate redirect URLs. Confirm your email templates use the configured redirect destination.
2. **booking-api Edge Function secrets:** set `BOOKING_WEB_ORIGIN=https://YOUR-SERVICE.up.railway.app`. The API merges this exact origin with `BOOKING_CORS_ORIGINS`, preserving existing clients. There is no `/app` path or trailing slash in a CORS origin. This setting belongs in Supabase, not only in Railway. During a custom-domain transition, set `BOOKING_WEB_ORIGIN=https://bookingos.online,https://YOUR-SERVICE.up.railway.app` to keep both exact origins working. The API splits this comma-separated list and preserves the separate existing allowlist. Changing or removing `BOOKING_WEB_ORIGIN` reverses this addition without rewriting the original allowlist.
3. For temporary path-based organisation URLs, set `BOOKING_WEBSITE_URL=https://YOUR-SERVICE.up.railway.app` and remove `BOOKING_WEBSITE_DOMAIN` from the Edge Function's secrets. Generated links then use `https://YOUR-SERVICE.up.railway.app/<slug>`. This is backend configuration; setting these only in Railway does not update the hosted API.
4. Set `ADMIN_SESSION_SECRET` in the **booking-api Edge Function secrets** to the same random value as Railway. Deploy the updated `booking-api` with signed admin request support before testing the panel. Keep the existing `verify_jwt = false` function setting: application code verifies admin signatures and owner/staff tokens separately. No Supabase Auth admin account or `ADMIN_SERVICE_EMAIL` / `ADMIN_SERVICE_PASSWORD` is needed.

See [Supabase redirect URL configuration](https://supabase.com/docs/guides/auth/redirect-urls). Do not replace the existing restricted database credentials or reset the database for this deployment.

## Database prerequisites — user owns migrations

This deployment adds no database migration and runs no migration on build/start. Public booking and admin require their existing migrations. Review the prerequisites, validation queries and recovery instructions in [Public booking website](public-booking-website.md) and [Admin panel](admin-panel.md) before applying any missing migration yourself. The password-only panel does not require a platform_admins membership row.

Check the known prerequisites without changing data:

```sql
SELECT name FROM booking_app.schema_migrations
WHERE name IN (
  '20261022034634_public_booking_websites.sql',
  '20261022045215_booking_website_images.sql',
  '20261022140000_booking_website_design.sql',
  '20261023100000_admin_panel.sql'
)
ORDER BY name;

SELECT to_regclass('booking_app.admin_audit_log'),
       to_regclass('booking_app.support_tickets');
```

The admin tables require the existing admin migration. Do not execute any rollback DDL merely to redeploy a frontend. Existing bookings and finances remain in Supabase.

## Local verification

Build from the repository root:

```sh
docker build -t bookingos:railway .
```

Copy `deploy/railway.env.example` to a private, gitignored file such as `.local/railway.env` and fill its required values. Run:

```sh
docker run --rm --name bookingos-web -p 127.0.0.1:8080:8080 \
  --env-file .local/railway.env bookingos:railway
```

In another terminal:

```sh
node deploy/smoke.mjs http://127.0.0.1:8080
```

For the actual deployment:

```sh
node deploy/smoke.mjs https://YOUR-SERVICE.up.railway.app
```

The script reads pages and assets only. It verifies readiness, landing assets, Flutter deep links and missing-file handling, owner-login redirects, and unauthenticated admin redirects/assets. Complete browser verification with a verified owner account and the configured admin password. Test password recovery and verification links, a direct refresh of an existing booking website, and logging out of admin. Use isolated fixture data for booking creation tests; the smoke script never creates live records.

CI's `web-container` job builds the complete image and starts a disposable local container with `deploy/test/mock-api.mjs` instead of Supabase. It checks the fixture's organisation homepage, booking page, API proxy, all four frontend routes and admin login/logout with server-rendered forms. Custom Host headers verify tenant homepages, clean booking links, assets, apex/www marketing pages and forwarded-host isolation. It also checks admin credential isolation and that a stopped frontend causes the whole service to fail. `deploy/test/auth-smoke.mjs` refuses non-local targets. These fixture scripts are not copied into the production runtime image.

### Verification of this change

- All three Next.js production builds, their TypeScript checks and the Flutter release build for `/app/` passed. Flutter's lockfile was enforced. The existing twelve public-booking regression tests passed.
- A Linux runtime image assembled from those locally built outputs passed the fixture routing/asset checks, admin HTML-form login/logout, signed-cookie scoping, booking API proxy and forwarded-host checks. Browser checks verified Flutter sign-in and enhanced admin login/logout through the same gateway.
- The runtime ran as UID 1000, excluded admin credentials from the booking server, exited with code 1 when its admin process was stopped, and exited with code 0 on graceful container shutdown. The disposable container was removed after verification.
- The complete multi-stage Linux build was attempted but its Flutter SDK setup stage stalled on the local Docker engine. That full build is not claimed as verified locally. The new CI job runs the complete build after the change is pushed; no remote CI run or Railway deployment is claimed here.

The custom-domain routing update additionally passed 13 public-website tests, three gateway configuration tests, booking/admin production builds, and local Nginx routing checks in both automatic and explicit path modes. The current admin build passed fixture login/logout. A local production booking server also rendered the published RK Groups page from the public API with its saved title and clean booking links. The local Nginx check used the platform's MIME-types file and disabled gzip only in the temporary test configuration; the production template retains both. These checks do not claim a new full Docker build or Railway deployment.

## Monitoring, shutdown and recovery

`deploy/start.mjs` supervises both Next.js servers and Nginx. If any process exits unexpectedly, it terminates its siblings and exits unsuccessfully so Railway can restart the whole service. On termination it closes readiness and gracefully stops children, with a ten-second forced-shutdown limit. Tini reaps orphan processes. Runtime processes run as the unprivileged `node` user.

`/_health` returns 503 until the frontend processes respond and essential landing/Flutter files exist. It tests frontend readiness, not Supabase availability or account privileges. Railway's configured health check gates deployments; use an uptime monitor for ongoing checks and separately monitor the hosted API. Docker also has a periodic health check. Gateway access logging is disabled and error logging is limited to critical messages to avoid recording private preview query strings.

Monitor Railway memory, CPU, restarts, deployment logs, availability and the Supabase API's error rate. Rotate the panel password and session secret when needed; replacing the signing secret invalidates existing admin sessions. All frontends share one browser origin, so cookie paths improve scoping but are not a separate security boundary between applications.

Rollback by redeploying the previous verified image/commit and restoring any changed Railway variables from your private record. Restore previous Supabase URL/CORS/website secrets separately if they changed. Do not restore old database data for a frontend rollback. Supabase backups remain managed separately.

## Connecting a domain later

The gateway recognizes customer subdomains on `BOOKING_SITE_DOMAIN` and forwards their homepage to the booking server. The apex, `www` and generated Railway hostname retain the BookingOS marketing homepage. On the generated Railway hostname, existing `/<slug>` links continue to work. Tenant booking pages use clean `/book/<business-id>` links, and `/app` and `/admin` remain available.

For `bookingos.online`:

1. Attach `bookingos.online` and `*.bookingos.online` to the same Railway service in **Settings → Networking**. Add the exact DNS records Railway provides and wait for domain/certificate validation. Also attach `www.bookingos.online` if it should serve the marketing homepage.
2. In the service's **Variables**, set `BOOKING_SITE_DOMAIN=bookingos.online`, `BOOKING_ROUTING_MODE=auto` and `BOOKING_APP_URL=/app`. An old explicit `BOOKING_ROUTING_MODE=path` overrides the new image default and must be changed or removed. `subdomain` is also accepted.
3. Deploy the commit containing `deploy/routing.mjs` and the host-aware gateway template. Changing DNS or variables without the updated image will still send tenant homepages to the marketing page.
4. Keep the API's `BOOKING_WEBSITE_DOMAIN=bookingos.online` so saved addresses use `https://<slug>.bookingos.online`. For owner access on both domains, preserve both exact CORS origins as described above. Public booking calls use the same-origin `/api/sites/*` proxy and do not require wildcard CORS.
5. For owner sign-in on the apex, add `https://bookingos.online/app/auth-callback` to Supabase Auth allowed redirects and use it as the Site URL when moving email verification/recovery to the custom domain. Retain the Railway callback during the transition.
6. Open `https://rk-sports.bookingos.online/` (the site must be published), follow a booking link and refresh it. Check `https://bookingos.online/`, `/app/sign-in`, `/admin` and the existing Railway path link separately.

Local fixture verification with custom-domain routing enabled:

```sh
node --test deploy/test/routing.test.mjs
node deploy/smoke.mjs http://127.0.0.1:8080 railway-smoke bookingos.online
```

These settings add no database migration. To temporarily restore path-only frontend routing, set `BOOKING_ROUTING_MODE=path` and redeploy. On the API, remove `BOOKING_WEBSITE_DOMAIN` and restore `BOOKING_WEBSITE_URL=https://YOUR-SERVICE.up.railway.app` if generated links must also fall back to `/<slug>`. Restore the previous image and recorded variables if a full rollback is required; no booking or design data is changed by the routing update.

Railway references: [Dockerfiles](https://docs.railway.com/builds/dockerfiles), [config as code](https://docs.railway.com/config-as-code/reference), [public domains](https://docs.railway.com/networking/domains/working-with-domains).

For a CORS configuration rollback, first restore `BOOKING_WEB_ORIGIN` to a single exact origin, then redeploy an older API bundle if necessary. The older handler does not parse a comma-separated `BOOKING_WEB_ORIGIN` value; rolling it back while that value contains multiple origins would block them. Keep `BOOKING_CORS_ORIGINS` unchanged. The transition fix requires an API deployment and secret update only, with no database migration or Railway frontend rebuild.
