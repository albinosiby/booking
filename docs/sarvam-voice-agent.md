# Sarvam automatic booking connection

The owner enters the Sarvam workspace API key, organization ID, workspace ID and agent App ID, selects businesses, and presses **Connect**. BookingOS verifies the API credentials, opens Sarvam sign-in for authoring authorization, then creates and verifies the booking integration. **Publish changes is a separate, explicit action.**

This source change does not apply a live migration, deploy code, publish an agent, place a call or install an APK.

## Architecture and authentication

- Flutter uses the existing authenticated booking API. Only the organization owner can connect, change booking access, publish, disconnect or read call logs.
- The workspace API key is used for call analytics. New credentials are staged encrypted; a failed reconnect does not replace a working analytics credential.
- Authoring uses Sarvam's supported [OAuth MCP interface](https://docs.sarvam.ai/voice-agents/mcp), not undocumented dashboard REST endpoints or browser cookies.
- Public discovery was verified at `https://mcp.sarvam.ai/.well-known/oauth-protected-resource/voice-agents` and `https://mcp.sarvam.ai/.well-known/oauth-authorization-server/voice-agents`. They advertise dynamic client registration, authorization code, PKCE S256 and public-client authentication. Registration requests only the authorization-code grant. Although discovery advertises refresh-token support, the current MCP guide describes 24-hour sessions without refresh tokens; fresh Sarvam sign-in is needed when such a session expires.
- The backend registers an OAuth client, stores a hashed single-use state and encrypted PKCE verifier, and exchanges the authorization code server-side. Links expire after ten minutes. Access/refresh tokens are encrypted using the existing `BOOKING_SECRETS_KEY` and are never returned to Flutter.
- The MCP authorization is scoped to the Sarvam workspace selected during sign-in. Before any secret/tool/configuration write, BookingOS checks that the returned agent's organization, workspace and App ID match the entered IDs. A mismatched login must be authorized again.
- Booking tool keys are generated inside the backend. Flutter never receives them. The backend stores their hashes for request authentication, with encrypted copies for safe retry/reconnect. Sarvam stores the credential in its secret store.
- The agent is an internal membership limited to booking permissions and selected businesses. It uses the normal BookingService for validation, inventory, pricing and history.
- Starting Connect does not rotate the live booking key or switch the deployed version. Publish promotes the configured key and business selection. Existing auto-configured connections reuse their key during reconnect.

The MCP adapter negotiates a Streamable HTTP session and accepts JSON or SSE results. A partially applied MCP write is a setup failure. Each short setup request is fenced by a database lease, and resource names/ownership metadata survive interruptions. The UI advances one durable step per request; reloading or retrying resumes from server state.

## Prerequisites

1. The booking backend and `booking_app` private schema are already configured.
2. The original voice migration `20261022100000_sarvam_voice_agent.sql` is applied, as are the earlier booking/admissions/slot-block prerequisites. Do not blindly apply unrelated pending migrations.
3. `BOOKING_SECRETS_KEY` is a server-only base64-encoded 32-byte key. Keep it backed up in a password manager. Losing it requires reconnecting the integrations.
4. The backend public URL is HTTPS. The Supabase runtime derives it from the project URL; a Node deployment uses `PUBLIC_APP_URL`.
5. Sarvam account permissions allow secrets, agent configuration, API tools, version commit, deployment reads and deployment updates. Workspace capabilities are checked during setup. Automatic setup currently supports a single-state agent.
6. A phone deployment for that agent already exists. This feature does not purchase numbers or create campaigns. If none exists, configure telephony in Sarvam, then reconnect to refresh the deployment list.
7. **Sarvam must allow-list the exact production HTTPS callback below.** The public registration endpoint currently accepts loopback HTTPS callbacks or exact URLs on its deployment allow-list. A custom Supabase HTTPS callback is not automatically accepted. Ask Sarvam support to approve it before using Connect.
8. If Sarvam supplies a pre-registered public PKCE client for that approved callback, set its client ID as server-only `SARVAM_OAUTH_CLIENT_ID`. A client ID does not itself approve a different callback. This setting is optional when dynamic registration of the approved URL is allowed.

For the current Supabase project, the exact callback is:

```
https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/v1/sarvam/oauth/callback
```

A Node deployment uses `<PUBLIC_APP_URL>/v1/sarvam/oauth/callback`.

The registration request was tested against Sarvam with the exact callback above. Sarvam returned HTTP 400, `invalid_redirect_uri`, because that callback is not allow-listed. This is a provider configuration prerequisite, not a workspace permission problem, and repeated retries cannot resolve it. The app now shows the specific approval requirement instead of a generic HTTP error. Real sign-in and subsequent setup still need validation after Sarvam approves the callback. No real secrets or calls are needed for the local test suite.

## Migration: owner applies it

The new additive migration is:

`supabase/migrations/20261022110000_sarvam_automatic_setup.sql`

The CLI generated the initial migration file; its timestamp was advanced to sort **after the existing future-dated voice migration**. The backend copy is for local development/test database initialization only.

Before applying:

1. Take a database backup.
2. In the Supabase **booking** project (`scwwkaywewecspsrskft`), verify the prerequisites with read-only SQL:

```sql
SELECT to_regclass('booking_app.sarvam_integrations');
SELECT name FROM booking_app.schema_migrations
WHERE name IN ('20261022100000_sarvam_voice_agent.sql',
               '20261022110000_sarvam_automatic_setup.sql');
SELECT grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema='booking_app' AND table_name='sarvam_integrations'
ORDER BY grantee, privilege_type;
```

The original table/migration must exist; the new migration must not already be recorded. `booking_api` needs SELECT/INSERT/UPDATE, while PUBLIC/anon/authenticated must not have access. Existing membership/staff-assignment grants from the original feature remain required.

Run the **whole new Supabase migration file once** in SQL Editor. It includes BEGIN/COMMIT and registers itself in `booking_app.schema_migrations`. Do not also run the backend copy or use `supabase db push` to apply all pending files.

Validate after applying:

```sql
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema='booking_app' AND table_name='sarvam_integrations'
  AND column_name IN ('setup_status','setup_state','setup_error',
                     'setup_lease','setup_lease_until','tool_key_ciphertext',
                     'pending_tool_key_hash','authoring_ciphertext',
                     'oauth_state_hash','oauth_pending_ciphertext')
ORDER BY column_name;
SELECT indexname, indexdef FROM pg_indexes
WHERE schemaname='booking_app' AND tablename='sarvam_integrations';
SELECT name FROM booking_app.schema_migrations
WHERE name='20261022110000_sarvam_automatic_setup.sql';
SELECT setup_status, count(*) FROM booking_app.sarvam_integrations GROUP BY setup_status;
```

Expect ten new columns, the existing primary/key indexes, a unique OAuth-state index, a partial unique `sarvam_one_managed_agent` index and one migration registration. Existing integrations start as `legacy`; their enabled flags, booking keys, assignments and bookings are preserved. Legacy owners can turn phone booking off or upgrade using Connect.

If application fails, run `ROLLBACK;`, correct the prerequisite and retry. Do not register the migration manually. The change is additive: for application rollback, leave the columns in place and disable phone booking; dropping them discards encrypted credentials and recovery state.

## Deploy and validate

Run local checks from the repository:

```bash
npm --prefix backend test
npm --prefix backend run edge:check
npm --prefix backend run edge:build
flutter analyze
flutter test test/sarvam_test.dart test/web_layout_settings_test.dart
```

If a sandbox prevents the tsx CLI from creating its IPC socket, the equivalent backend test command, run inside `backend`, is:

```bash
node --import tsx --test --test-concurrency=2 test/*.test.ts
```

After the owner has applied and validated the migration, deploy the backend using the existing project deployment procedure:

```bash
npx supabase functions deploy booking-api --project-ref scwwkaywewecspsrskft --use-api --no-verify-jwt
curl -sS https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/health
```

Expected health revision: `2026-10-22-sarvam-automatic-setup`. Keep `verify_jwt=false` for this multi-route function: user routes validate the Supabase session themselves; voice routes authenticate their own tool keys; the OAuth callback validates expiring single-use state. The removed `/v1/sarvam/tool-key` route must not return a key.

Rebuild the Flutter app from this source. APK installation remains a separate user action.

## Owner workflow

1. Open **Profile → Sarvam voice agent**.
2. Enter the four connection fields and select businesses.
3. Press **Connect**. When the sign-in page opens, authorize the intended Sarvam workspace. If a browser blocks the automatic popup, use **Authorize with Sarvam**.
4. Return to the app. Returning to the foreground resumes setup; **Continue setup** also refreshes it. Setup configures the secret, catalog hook, six tools, variables and booking instructions, then verifies the readback.
5. Review/test the draft in Sarvam. The existing voice, languages and phone deployment remain in place. BookingOS replaces the agent's booking instructions with its managed flow. It disables the recognized old BookingOS API tools in the draft to avoid duplicate booking flows.
6. Select a phone deployment and press **Publish changes**. Confirm the reviewed version. Publication commits that version, changes only the selected deployment's agent version, then verifies the deployment readback. A timeout can be retried without intentionally committing another version or creating another deployment.
7. Turn **Accept phone bookings** on. First connections remain off until publication and this explicit switch.

Turning the switch **off** immediately rejects booking, finding bookings, rescheduling and cancellation through the voice API and deactivates the voice membership. It does not delete bookings or prevent the phone number from answering general enquiries.

**Disconnect Sarvam** immediately disables booking access, revokes active/pending keys, removes the analytics credential and cancels pending OAuth. It then disables only BookingOS-managed draft tools and replaces its managed remote secret with an unusable value. Existing bookings and the phone deployment are preserved. Authoring credentials are kept encrypted only while cleanup is pending and removed when cleanup completes. Non-secret resource ownership metadata is retained so reconnect can reuse the same resources. Disconnect does not revoke a shared workspace-wide API key at Sarvam.

If cleanup fails, the status says **Disconnected — cleanup pending** and booking access stays blocked. Retry cleanup. A request that was already in flight is fenced locally; allow up to 90 seconds for its lease to expire before retrying. Sign-in can be renewed if authoring access expired. Cleanup and setup resume while the screen is open; this implementation does not run a background job when the app is closed.

## API

All routes below require the authenticated organization owner, except the OAuth callback.

| Method | Path under `/v1/sarvam` | Request / purpose |
|---|---|---|
| GET | `/settings` | Safe status, step/error, credential suffix, businesses and deployment choices |
| POST | `/connect` | `{version, sarvam_org_id, workspace_id, app_id, business_ids, api_key?}`; version 0 is valid initially |
| POST | `/setup` | Advance/resume one durable step; no body fields |
| PUT | `/booking-enabled` | `{version, enabled}`; turning off is allowed with a stale version |
| POST | `/disconnect` | Revoke local access first; safe to repeat |
| POST | `/publish` | `{version, deployment_id}`; explicitly authorize publishing the prepared version |
| GET | `/oauth/callback` | Public OAuth callback with single-use state, code and optional issuer |
| POST | `/test` | Verify analytics access only, not phone-booking configuration |
| GET | `/calls`, `/transcript`, `/recording` | Existing owner-only call analytics |

All mutation routes return refreshed safe settings. Stale/concurrent changes return 409; validation/permission problems return actionable errors without provider response bodies or credentials. Setup failures also persist safe status for reload/retry. No raw internal tool key, OAuth verifier or access/refresh token is returned.

The six managed tools are `bookingos_list_spaces`, `bookingos_check_availability`, `bookingos_book_slot`, `bookingos_my_bookings`, `bookingos_reschedule_booking` and `bookingos_cancel_booking`. Their endpoints remain `/voice/v1/catalog`, `/availability`, `/bookings`, `/my-bookings`, `/reschedule` and `/cancel`. Caller number and interaction ID use Sarvam system variables. Business refusals are HTTP 200 with `ok:false`; the prompt requires interpreting this rather than treating HTTP success as booking success.

## Controlled rollout and recovery

Before serving regular callers, use the owner's own phone and an appropriate test slot to verify a booking, duplicate-request retry, another caller's access denial, reschedule, cancellation, unpaid balance, switch-off and Disconnect. Test English and Malayalam and confirm the correct phone deployment/version. Live calls and bookings are not created by the automated test suite.

Local tests cover OAuth state replay, wrong workspace, missing capabilities, invalid analytics keys, interrupted tool/secret writes, duplicate Connect, resource reuse, explicit publishing, revocation, Cubit cancellation and responsive layout.

For an emergency backend shutdown, the owner can run:

```sql
BEGIN;
UPDATE booking_app.sarvam_integrations SET enabled=false, version=version+1;
UPDATE booking_app.memberships SET active=false WHERE user_id LIKE 'sarvam:%';
COMMIT;
```

Bookings remain valid. Use the app for normal reconnection and cleanup. Do not drop the integration table while the API uses it.

Remaining constraints: caller identity relies on provider-reported caller ID rather than OTP; recordings remain downloadable; call logs retain the existing first-page pagination limit. Setup does not add payment collection or automatic messaging. Monitor failed setup stages, cleanup-pending integrations, tool errors/latency and actual booking outcomes using the existing audit history, backend logs and Sarvam analytics. Do not log request bodies, OAuth callback queries or tokens.
