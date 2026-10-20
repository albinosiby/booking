> Superseded runtime note (16 October 2026): the remaining Mac API has moved to Supabase Edge Functions. See [Supabase-only runtime](supabase-only.md). The historical migration details below are retained for recovery.

# Supabase connection plan

## Requested destination

Use the user-created **booking** project (`scwwkaywewecspsrskft`), in **albinosiby1@gmail.com** organization (`niuvohxgboltluqufsuc`), Tokyo (`ap-northeast-1`). This supersedes the earlier proposed project name and location. The dashboard confirms the project is healthy. Do not use the unrelated **booking os** project visible to the old connector account.

The user reauthorized the Supabase plugin, but the connector available in this chat still returns only the old organization and explicitly denies access to this project. Do not repeat the same reconnection loop. Dashboard discovery confirmed an IPv4 session pooler at `aws-0-ap-northeast-1.pooler.supabase.com:5432`, database `postgres`, user `postgres.scwwkaywewecspsrskft`. A direct server-side connection is an alternative once the user enters the existing database password in the private ignored `.local/supabase-db-password.txt` file. Never print that password or embed it in Flutter.

## Intended design

- Supabase Auth replaces the local Firebase Auth emulator for the connected build.
- Supabase PostgreSQL stores the current relational model and configuration JSON. Preserve booking, split-payment, ledger, balance, staff and resource rules.
- Retain the existing Nest API for transactional booking/accounts logic. Cloud Auth/database alone do not host this API; it remains Mac-dependent until separately deployed online.
- Retain Flutter screen models, abstract repositories and Cubit. Add a Supabase implementation of AuthRepository and provider configuration; the feature repositories continue using the existing authenticated API.
- Use only the project URL and publishable key in Flutter. Database credentials and privileged keys belong only in server configuration.
- Keep application tables in an unexposed private schema; explicitly control privileges and RLS. Keep the public Data API inaccessible to application tables unless an intentional tenant-scoped policy is implemented.
- Use TLS with certificate verification and a bounded PostgreSQL pool. Verify pooler compatibility with existing SQL transactions.

## Existing-account/data preservation

The requested existing login was restored in the local Auth emulator with its verified original RK Groups owner ID. That ID is a Firebase-style text ID; Supabase Auth uses UUID subjects. Preserve the original business actor IDs using a server-controlled identity mapping rather than rewriting historical ledger/audit identities or trusting user-editable metadata. New accounts can use their Supabase subject directly. Mapping claims are inserted only by trusted migration code. The first Supabase user with a server-verified matching email binds that claim once; later logins use that fixed subject. User-editable metadata never selects an actor ID.

Before cloud cutover: take a consistent local backup, migrate the relational graph transactionally, check row counts/IDs/totals and verify the owner scope. Do not change the working local connection until cloud verification passes. Never remove old data as part of connection setup. User password entry/reset remains private.

## Verification before cutover

Verify registration, sign-in/session refresh, owner/staff authorization and account-to-organization mapping. Check turf shared-ground conflicts, court exclusivity, pool capacity, midnight/24-hour pricing and rescheduling. Verify split payments, transfers, opening balances and reports against migration totals. Run Supabase security/performance advisors and a real read/write test in an isolated test organization. Ensure service credentials never enter Flutter artifacts, logs or committed configuration.

## Current status

Connected to the user-created **booking** project in Tokyo on 15 October 2026. The connector remains scoped to the old account, so the connection was completed through PostgreSQL using the user's privately supplied password and the official Supabase CA certificate.

- A consistent full backup and JSON snapshot were saved under `.local/supabase-backup-2026-10-15T17-48-47.894Z` before migrating. The earlier backup is retained too.
- All 19 application tables were copied, preserving the complete existing local development dataset, including its historical test organizations. Every row was compared after normalizing database integer types; ledger totals match. No historical IDs were rewritten.
- The private `booking_app` schema contains 21 tables including migration tracking and trusted identity claims. All have RLS. `anon` and `authenticated` have no schema usage. A dedicated `booking_api` role has scoped application access and cannot access `auth`, create databases, or create roles. Tenant authorization continues in the API.
- The API uses session pooling over certificate-verified TLS, with migrations disabled for the runtime role. Startup confirms the existing migrations are present. Server secrets are in ignored private configuration, never Flutter.
- Supabase Auth is the default Flutter provider. Existing Firebase support remains selectable for isolated legacy development. Feature models, repository contracts and Cubits remain in place. Mobile sessions use OS secure storage, with PKCE email links.
- The exact callback `com.bookingos.app://auth-callback/` was approved by the user, saved in Supabase, and verified in the dashboard.
- Existing authentication passwords were not imported or invented. `albinosiby1@gmail.com` completed cloud registration, verification and sign-in. A database check confirmed its Supabase subject is bound to the preserved RK Groups owner ID with the owner role. No duplicate organization was created. New migrated users follow the same verified-email claim flow.
- The API health check succeeds. A restricted-role TLS and SQL permission audit verified all 21 tables have RLS and no direct public/client schema access. Supabase's management advisor tool cannot access this account from the current connector; this was checked using explicit database permissions instead.

The API still runs on this Mac. Supabase login no longer requires the local Auth emulator, but bookings and accounts still require the API and phone forwarding until the API is separately deployed to HTTPS hosting.

## Local run

Build/run with `--dart-define-from-file=.local/dart-defines-supabase.json`. Start the API from `backend` using `node --env-file=.env dist/main.js`. Never ship a database password, connection string, private backup, or privileged key in Flutter. The checked-in example contains only the public URL/publishable key and the local development API address.

## Recovery

The original backend configuration is retained at `.local/backend-before-supabase.env` and the original local database is unchanged. If cloud verification fails, stop the current API before restoring that configuration and using the local database. Do not run two API processes against PGlite. Data entered into Supabase after cutover must be reconciled before any rollback; switching configuration alone would not copy new cloud records back to the old snapshot.

## Verification results

- Backend TypeScript build and all 93 backend tests passed (including four Supabase verification/identity tests).
- Flutter analysis and all 107 Flutter tests passed (including PKCE signup confirmation and invalid-credential mapping).
- Cloud smoke checks verified RK Groups with three existing businesses, the booking dashboard, monthly report queries, PDF signature and Excel ZIP signature.
- The owner reported successful phone sign-in, and an independent database check confirmed the bound subject, RK Groups organization and owner role. On-device inspection showed the Calendar page and the existing RK Groups badminton court configuration. The user was actively navigating settings, so no configuration fields were changed during verification.

## Phone startup correction

The first installed build exposed a GoRouter assertion because its callback route ended with a slash. The callback allowlist and native scheme remain unchanged; the GoRouter route is now `/auth-callback`. A new regression test constructs the complete application router, and all seven router configuration/guard tests pass. This verifies configuration construction in addition to the earlier route-redirect unit tests.

The corrected Android APK was installed successfully on the wireless debugging phone. On-device inspection confirmed the registration form renders with owner name, email, password and Create account controls, with no red route error. The owner subsequently completed verified cloud signup/sign-in successfully. APK inspection confirmed neither the database administrator password nor the restricted API database password is present in the build.

## Signup rate-limit observation

The owner briefly saw a rate-limit message after requesting confirmation. A read-only Auth check confirmed the account existed and a confirmation had been requested. The owner then successfully verified and signed in. No rate limits or verification requirements were disabled or weakened.
