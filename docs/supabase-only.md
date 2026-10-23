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

## Google sign-in

The Supabase sign-in and registration pages offer **Continue with Google** alongside email/password. The button uses the existing Supabase client to generate a PKCE OAuth authorization URL, requests Google's account selector, and opens the browser in the same web tab or in the native external browser. The installed Supabase Flutter SDK handles the callback and session exchange. Only a completed, verified Supabase session can open authenticated pages. The legacy Firebase connection does not advertise Google sign-in.

Google client IDs/secrets belong in the Supabase Google provider settings, not Flutter source. The user configures these settings. Native Google sign-in here uses browser OAuth; it does not consume `google-services.json` or require a native Google SDK. The native installation/bundle identifier is `bookingservice.tatos.tech`, while the registered browser return scheme is independently `com.bookingos.app://auth-callback/`.

Allow the exact mobile callback above and the web app's callback in Supabase Authentication → URL Configuration. The web callback is resolved beside the sign-in page: `/app/sign-in` returns to `/app/auth-callback`, while an app served at the domain root returns to `/auth-callback`. The shared deployment uses `https://bookingos.online/app/auth-callback`. These app return URLs differ from the Supabase `/auth/v1/callback` URL registered in Google Cloud. No provider secrets are bundled with the app.

### Google blocks sign-in with `400: redirect_uri_mismatch`

A read-only live authorization check on 23 October 2026 reproduced this error. Supabase redirects to Google using client ID `340652751420-3tauqp55b468b3jnide6gb0lgvt5v5uu.apps.googleusercontent.com` and callback `https://scwwkaywewecspsrskft.supabase.co/auth/v1/callback`. Google rejects that callback for the currently configured client.

The project owner should open Google Cloud → Google Auth Platform → Clients (or APIs & Services → Credentials), select the OAuth client matching the ID above, and add this exact URL under **Authorized redirect URIs**:

```text
https://scwwkaywewecspsrskft.supabase.co/auth/v1/callback
```

Save while preserving any existing valid redirect URIs, then begin a fresh Google sign-in attempt. This browser-based Supabase flow requires a **Web application** OAuth client, including when launched from Android. If the currently configured client is a native/Android client, configure a Web application client and enter its matching client ID/secret in Supabase → Authentication → Sign In / Providers → Google. Keep the secret server-side.

The app return URL `com.bookingos.app://auth-callback/` and web return URL `https://bookingos.online/app/auth-callback` belong in Supabase → Authentication → URL Configuration → Redirect URLs. Google returns to the Supabase HTTPS callback first, and Supabase subsequently returns to the app. Updating Flutter callback constants or Firebase Messaging settings cannot repair Google's remote redirect allowlist.

No Google Cloud or Supabase provider settings were changed during this diagnostic. After the owner saves the fix, verify a fresh authorization request reaches Google's account selection/consent instead of the mismatch page, then complete sign-in and check the app receives its Supabase session. See [Supabase Google setup](https://supabase.com/docs/guides/auth/social-sign-in/auth-google) and [Google redirect URI requirements](https://developers.google.com/identity/protocols/oauth2/web-server#redirect-uri-validation).

Before leaving for Google, `AuthCubit` saves the invitation token and a validated, application-relative return path through `AuthContinuationRepository`. The secure-storage adapter scopes this private context to the Supabase project and expires it after 30 minutes. Startup restores it before publishing auth state; routing consumes it after restoring the destination. Cancelled OAuth callbacks retain the invitation for retry, while launch failures, password sign-in, explicit sign-out and completed routing clear it. Private invitation tokens are not appended to Google's authorization URL or the app's OAuth callback URL. Existing exact-email invitation acceptance, verification and role/resource checks remain authoritative. Reopen the original invitation if the temporary context has expired.

Release checks: use a test owner and a separately invited staff account to complete Google sign-in on web and Android. Check account selection, cancel/retry, callback routing, wrong invited email rejection, app restart during the browser flow and sign-out. New Google users without an invitation follow organization setup; invited users return to acceptance before setup. No application schema migration or API deployment is required for this UI/auth integration.

Implementation verification: all 44 focused Flutter tests passed across Google launch/PKCE, invitation recovery, cancellation and retry, corrupt/expired storage, auth routing, responsive auth layouts, existing startup/invitation links and authenticated Profile/business layouts. Targeted analysis is clean. The `/app/` release web build and Android debug APK build passed; both contain the bundled Google graphic, and the APK package is `bookingservice.tatos.tech`. Phone (320/390 px) and desktop (1440 px) layouts were rendered and reviewed. A read-only public auth-settings request confirmed Google is enabled on the configured Supabase project. Full Google-account consent/callback acceptance still requires a real-account check after opening the updated build. No hosted deployment, device installation, provider-setting change or schema migration was performed.

## Build and browser deployment

From `backend`, run `npm ci`, `npm run build`, `npm run edge:check`, `npm test`, and `npm run edge:build`. The generated, credential-free `supabase/functions/booking-api/index.ts` is the browser-editor deployment artifact. Edit the shared services/Edge source and rebuild; do not maintain a second handwritten copy of business rules in the generated file.

The user requested dashboard deployment. `scripts/edge_browser_handoff.py` temporarily serves only the generated source on a random loopback path for copying into the dashboard editor; stop it afterwards. It never serves server credentials. In the booking project, open Edge Functions → booking-api → Code, replace the source, Deploy updates and confirm. Keep the function's custom Auth verification configuration. `supabase/config.toml` records the equivalent configuration for future CLI use.

Flutter's default configuration and `dart-defines.example.json` use the cloud endpoint. Build with `flutter build apk --debug --target-platform android-arm64 --dart-define-from-file=dart-defines.example.json`; production signing remains a separate release requirement. No API server, Firebase emulator, LAN IP, ADB reverse or running Mac is required by the installed cloud build. Wireless debugging is needed only for development/installation.

## Verification and recovery

Check hosted `/health`, public countries/states, and 401 responses for missing/invalid sessions. Verify the existing organization, configurations, bookings, Accounts, bank settings and exports on the installed app with the Mac API stopped and ports 3000/9099 unforwarded. Do not create live test bookings or financial entries merely to test connectivity.

Mac forwarding's LaunchAgent is disabled and the Nest API stopped. Local historical database/backup files are preserved as recovery material, not used by the app. Never restore an old local snapshot over newer cloud data. To roll back application code, deploy a previously verified Edge build against the same cloud database. Database backups, restoration and plan-specific retention must be managed in Supabase; no backup/PITR entitlement is implied by this change.

Monitor Edge startup failures, request IDs, auth failures, database connection saturation, timeouts and report CPU/memory limits. Logs contain error names and request IDs, not credentials or request bodies. Changes to worker configuration must be tested on the hosted runtime: its environment is read-only and it differs from a standalone Deno process.
