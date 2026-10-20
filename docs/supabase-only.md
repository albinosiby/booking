# Supabase-only runtime

The connected mobile build uses the existing **booking** project, `scwwkaywewecspsrskft`, with its existing private `booking_app` database. The database was not recreated or copied during this cutover. Existing organization IDs, memberships, booking records, ledger entries and trusted identity mappings remain in place.

## Runtime and client contracts

`Flutter screen → Cubit → feature repository → shared HTTPS transport → Supabase Edge Function → Supabase PostgreSQL`.

Auth and secure sessions continue through Supabase Auth. The API base is `https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/v1`. Existing feature models, repository contracts and Cubits are retained. The transport adds the public project key only for this project's Functions requests, alongside the user's bearer token. Device configuration drafts retain their existing project/user/business scope. Final Save/Activate still publishes to the database.

The Edge entry instantiates the same domain services used by the development Nest API. `backend/edge/handler.ts` supplies HTTP routing, bounded request bodies, typed errors, explicit CORS, private no-store responses and per-worker burst protection. The build replaces framework decorators/exceptions with compatible HTTP primitives; domain validation, SQL transactions, locks, idempotent command handling, quote checks, pool capacity and physical turf allocations are shared. There is no development database fallback or automatic migration path in the Edge runtime.

Public endpoints are `/health`, `/v1/catalog`, `/v1/catalog/states/:country`, and the validated invitation redirect. Every business, booking and accounts endpoint verifies the bearer token using Supabase Auth, rejects anonymous/unverified identities, and applies the existing organization/staff permission checks. Legacy-secret-only gateway validation is disabled by user approval because the function performs current Auth verification itself.

## Server configuration

The project owner entered `BOOKING_DATABASE_URL` in Supabase's encrypted Edge Function Secrets. It uses the existing restricted `booking_api` role, never the database administrator or a client key. Do not paste it into chat or commit it. Certificate verification is mandatory; the public Supabase root certificate is bundled. The private schema remains unexposed to the Data API, with its existing RLS and role grants.

Connections are lazy, limited to two per worker, close idle connections after ten seconds and use bounded connection, statement and lock timeouts. The current connection uses the project's existing session pooler. Before increasing users/workers, evaluate aggregate connection limits and a tested transaction-pooling configuration. Burst limits are local to each worker and are not a global quota.

## Reports and invitations

PDF and Excel exports remain protected, generated on demand from the same financial snapshot. The PDF's licensed Noto Sans font is embedded in the deployment; no Mac font path or asset server is needed. Node-compatible PDFKit and ExcelJS versions are pinned for Edge. The Noto license remains in `backend/assets/fonts/OFL.txt`.

Staff invitation URLs use the hosted function. A validated `/invite?token=...` redirects into the installed mobile app. A typed invitation-link model, repository and Cubit forward it into the existing invitation screen and authentication guards. Acceptance still requires the exact invited verified email. No invitation is accepted by opening a link, and no email is sent automatically. A separate customer booking website is outside this migration.

## Build and browser deployment

From `backend`, run `npm ci`, `npm run build`, `npm run edge:check`, `npm test`, and `npm run edge:build`. The generated, credential-free `supabase/functions/booking-api/index.ts` is the browser-editor deployment artifact. Edit the shared services/Edge source and rebuild; do not maintain a second handwritten copy of business rules in the generated file.

The user requested dashboard deployment. `scripts/edge_browser_handoff.py` temporarily serves only the generated source on a random loopback path for copying into the dashboard editor; stop it afterwards. It never serves server credentials. In the booking project, open Edge Functions → booking-api → Code, replace the source, Deploy updates and confirm. Keep the function's custom Auth verification configuration. `supabase/config.toml` records the equivalent configuration for future CLI use.

Flutter's default configuration and `dart-defines.example.json` use the cloud endpoint. Build with `flutter build apk --debug --target-platform android-arm64 --dart-define-from-file=dart-defines.example.json`; production signing remains a separate release requirement. No API server, Firebase emulator, LAN IP, ADB reverse or running Mac is required by the installed cloud build. Wireless debugging is needed only for development/installation.

## Verification and recovery

Check hosted `/health`, public countries/states, and 401 responses for missing/invalid sessions. Verify the existing organization, configurations, bookings, Accounts, bank settings and exports on the installed app with the Mac API stopped and ports 3000/9099 unforwarded. Do not create live test bookings or financial entries merely to test connectivity.

Mac forwarding's LaunchAgent is disabled and the Nest API stopped. Local historical database/backup files are preserved as recovery material, not used by the app. Never restore an old local snapshot over newer cloud data. To roll back application code, deploy a previously verified Edge build against the same cloud database. Database backups, restoration and plan-specific retention must be managed in Supabase; no backup/PITR entitlement is implied by this change.

Monitor Edge startup failures, request IDs, auth failures, database connection saturation, timeouts and report CPU/memory limits. Logs contain error names and request IDs, not credentials or request bodies. Changes to worker configuration must be tested on the hosted runtime: its environment is read-only and it differs from a standalone Deno process.
