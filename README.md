# Booking OS

A Flutter owner/staff app with a Supabase-hosted API for one organization operating multiple businesses. The approved palette is black `#0F0F0F`, charcoal `#202020`, lime `#5DD62C`, green `#337418`, and off-white `#F8F8F8`.

## Implemented

- Owner registration/sign-in, password reset, email verification, secure persistent Supabase sessions (legacy Firebase support remains selectable) and sign-out.
- Organization and first location: name, contact, separate address columns, country/state dropdowns, city, text postal code, IANA timezone and currency.
- Optional, private organization logo (PNG/JPEG/WebP, up to 2 MB).
- Six separate business types: Turf, Badminton Court, Tennis Court, Basketball Court, Swimming Pool and Party Hall.
- Resource creation/removal, capacity, operating days/hours, prices in integer minor units, duration and buffers.
- Multiple pools with capacities/depths, per-person time tariffs, configurable group offers, coaching plans and 25/custom attendance-day plans with separate expiry.
- Configuration saved independently per business; activation requires a resource and valid rules. Configure disappears after activation; editing remains in Profile.
- Staff invitations via private expiring links; acceptance checks the exact invited email. Owner can change business/resource assignments, permissions and revoke access.
- Elevated Home / Calendar / Bookings / Payments / Profile navigation with preserved tab state.
- Server-enforced owner operations and staff visibility. No passwords or service keys are stored in the application database.

Bookings, daily Calendar and manual payment collections are implemented, including split payments and atomic rescheduling. Home shows live booking and collection figures. No payment gateway, email-delivery provider, public booking website, plan-attendance deduction is included.

## Current Supabase setup

The connected app uses Supabase Auth, Supabase PostgreSQL and the hosted `booking-api` Edge Function in the **booking** project. Existing data stays in the private `booking_app` schema. The app works over the internet without a running Mac, local API or ADB forwarding.

```sh
flutter pub get
flutter run --dart-define-from-file=dart-defines.example.json
```

See [Supabase-only deployment and recovery](docs/supabase-only.md) for the API architecture, server secrets, reports and verification. The Nest runtime and emulators below are optional legacy development tools; they are not used by the connected app.

Existing local owners must create their cloud login once using their original email and verify it. A server-controlled, one-time identity claim then restores their existing organization and historical actor IDs. Do not create another organization. See [migration and verification](docs/supabase-migration-plan.md) for backups, restricted-role security, migration totals and rollback limitations.

## Optional legacy local emulator setup

Requirements: Flutter 3.44.1 / Dart 3.12+, Node 22+ (tested on Node 24), npm. Docker is unnecessary for local development.

Terminal 1:

```sh
cd backend
npm ci
npm run emulators
```

This starts the Firebase Auth emulator at `127.0.0.1:9099` and its UI at `127.0.0.1:4000`. The demo project cannot access real Firebase services. Local auth data is imported/exported under `.local/auth` on clean shutdown. Run from `backend`, because migration paths are relative to it.

Terminal 2:

```sh
cd backend
cp .env.example .env
npm run build
node --env-file=.env dist/main.js
```

The API uses persistent embedded PostgreSQL in `.local/postgres`. Never run two API processes against that same embedded directory. A real PostgreSQL server is selected when `DATABASE_URL` is set.

Terminal 3:

```sh
flutter pub get
flutter run -d chrome --web-port 8080 --dart-define=AUTH_PROVIDER=firebase --dart-define=USE_AUTH_EMULATOR=true
```

Register your own local owner account. Local verification links/reset links are printed by the Auth emulator. Emulator mode intentionally bypasses the production email-verification gate; production requires verification.

For a stable built preview:

```sh
flutter build web --debug --no-web-resources-cdn --dart-define=AUTH_PROVIDER=firebase --dart-define=USE_AUTH_EMULATOR=true
python3 scripts/serve_web.py
```

Do not run both web servers on port 8080. Clean URLs, including staff invitation links, require SPA fallback; the included development server provides it.

### Android emulator

```sh
flutter run -d <android-emulator-id> --dart-define=AUTH_PROVIDER=firebase --dart-define=USE_AUTH_EMULATOR=true \
  --dart-define=API_URL=http://10.0.2.2:3000/v1 \
  --dart-define=AUTH_EMULATOR_HOST=10.0.2.2
```

Minimum Android API: 23. For a physical phone, use `adb reverse tcp:3000 tcp:3000` and `adb reverse tcp:9099 tcp:9099`, then set both hosts to `127.0.0.1`. Alternatively use a trusted LAN and explicit emulator binding; the emulator is loopback-only by default. Development HTTP is enabled only in Android's debug manifest. Do not install on a personal device without requesting that action.

### Legacy automatic phone connection on macOS

`scripts/android_connection.py` restores the Auth (`9099`) and API (`3000`) reverse mappings when your selected phone reconnects through wireless debugging or USB. It checks every five seconds, retries temporary ADB failures and repairs missing/incorrect mappings. It uses the existing ADB pairing and leaves unrelated devices/ports untouched. No app rebuild is needed when the installed app already uses localhost/127.0.0.1.

Install once, substituting your phone's identifiers from `adb devices -l`. For a wireless serial such as `adb-PHONE_SERIAL-session._adb-tls-connect._tcp`, use the stable prefix `adb-PHONE_SERIAL-`; `--device` also supports the exact USB serial:

```sh
python3 scripts/android_connection.py --install \
  --device PHONE_SERIAL --device-prefix adb-PHONE_SERIAL-
python3 scripts/android_connection.py --status
```

The user LaunchAgent `com.bookingos.android-connection` starts immediately and at macOS login, independently of the terminal. Pass `--adb /absolute/path/to/adb` if ADB is not on PATH. Logs rotate under `.local/android-connection/connection.log`. Reinstall with updated identifiers if you change phones; reinstall after moving this checkout or the Python/ADB installation.

The Mac must be awake, your user must be logged in, the phone must reconnect to ADB, and both local servers must remain running. The helper restores forwarding; it does not pair phones, turn on wireless debugging, restart servers or make the local app accessible away from this Mac.

```sh
# Stop the helper and remove automatic startup (keeps existing port mappings):
python3 scripts/android_connection.py --uninstall
# Foreground alternative on macOS/Linux, stopped with Ctrl+C:
python3 scripts/android_connection.py --run --device PHONE_SERIAL
# Device-free regression checks:
python3 -m unittest discover -s scripts -p 'test_*.py' -v
```

### iOS

Minimum iOS: 15. Configure a full Xcode installation and CocoaPods, then run on a simulator. Local development transport configuration is documented in `docs/deployment.md`. iOS builds were not verified on this host because full Xcode and CocoaPods are missing.

## Verification

```sh
flutter analyze
flutter test
cd backend
npm run build
npm test
# With both local services running:
node test/local-e2e.mjs
```

The tests cover exact money parsing, failed writes, stale async loads after logout, narrow-screen/large-text layouts, database invariants, stale configuration protection, cross-organization access, pool validation, staff invitation scope and revocation. HTTP E2E creates disposable QA identities/organizations in the local emulator/database; it never touches a real Firebase project. Only use the E2E script with the documented demo services.

## Production configuration

See `docs/deployment.md`. Both client and server fail closed for unsafe release defaults. Production needs Supabase email/password authentication, verified emails, a private PostgreSQL schema and restricted server connection, HTTPS API hosting, explicit CORS and a public application URL. Supabase SDKs own refresh; mobile sessions use secure storage, and Dio obtains current access tokens per request. The backend validates tokens with the Supabase Auth server and enforces membership permissions. For legacy Firebase deployment, supply real Firebase project/platform configuration and select that provider explicitly. Do not place private service-account keys in Flutter defines.

See `docs/verification.md` for checked outcomes, and `docs/api.md`, `docs/architecture.md` and `docs/user-guide.md` for contracts, design boundaries and operating instructions.

## Module structure and backend replacement

Implemented features keep models, repository contracts/implementations, Cubits and screens inside their module. Screens invoke named Cubit commands; typed models carry data and repositories own persistence. The current feature repositories reach Supabase PostgreSQL through the Nest API. The API runs on this Mac during development; PGlite is retained for isolated tests and explicitly selected legacy development. Replace bindings in `lib/di/feature_injection.dart` when adopting another data source; keep contracts stable to preserve screen/Cubit code. See [architecture](docs/architecture.md) for the shared session coordinator and cloud migration requirements.

## Turf setup

Turf businesses now open a dedicated six-step wizard from Home → Configure. The default is one ground split into Half A, Half B and a shared Full Ground, with football and cricket on every layout. Configure independent additional grounds and offering names/formats. In Timing & pricing, choose a sport and then a space to set allowed/default durations, weekday/time prices, buffers and optional hours overrides. Continue advances immediately and checkpoints a private local draft; final Save or Activate publishes to Supabase after validation. See [local configuration drafts](docs/local-configuration-drafts.md). Activate after every enabled offering is configured. Prices use the booking’s start time. See [turf configuration](docs/turf-configuration.md).

Profile → Business settings → Turf opens a direct editor with section cards. Select an area and Save changes; active configurations stay active after valid saves. Home → Configure retains the first-time guided setup.

## Swimming pool setup

Home → Configure or Profile → Business settings → your pool opens direct section editing. Configure pool capacities/depths, timing/pricing, group offers, coaching and swimming plans. Swimming plans default to 25 attendance days or a custom count with separate expiry; purchases and attendance recording remain future modules. See [pool configuration](docs/pool-configuration.md).

## Court setup

Badminton, Tennis and Basketball use independent courts with per-court hours, durations and weekday/seasonal prices. Copy settings preserves court details. Home → Configure and Profile → Business settings open direct editing with activation. See [court configuration](docs/court-configuration.md).

## Party hall setup

Each hall independently offers hourly bookings, named morning/evening sessions and/or a full-day package. Configure separate prices, copy options to other halls and edit directly from Business settings. All options share the physical hall resource. See [hall configuration](docs/hall-configuration.md).

## Booking operations

Create bookings from Home, Calendar or Bookings. The full-screen form supports configured spaces/options, authoritative availability/prices, customers and split manual payments. Booking details supports additional collections, rescheduling, cancellation, owner-recorded refunds and history. See [booking module](docs/booking-module.md).

## Accounts and reports

The Accounts tab replaces Payments with income, expenses, cash flow, growth, booking dues and recorded cash/bank balances. Profile → Account settings manages multiple banks, the primary account, cash opening balance and business/space payment routing. Booking payments use those defaults and allow account selection. Add entry records split expenses, extra income and transfers. Reports downloads monthly, yearly, booking collections and cash-flow reports as PDF or Excel. See [accounts module](docs/accounts-module.md) for accounting rules, API, permissions and migration/backup guidance.

## App logo and launcher icons

The Booking OS B/check logo uses lime on near-black. Android includes legacy, adaptive and themed launcher assets; iOS and web icons use the same mark. Source artwork, the generation prompt and regeneration instructions are in [branding](assets/branding/README.md). Run `dart run scripts/prepare_branding.dart` followed by `dart run flutter_launcher_icons` after changing the source mark.

Page state retention, encrypted read snapshots and freshness policies are documented in [Page caching](docs/page-caching.md).

Shared loading motion and usage are documented in [Loading animations](docs/loading-animations.md).

### Profile and business management

Profile now links to organization details, Businesses, team and payment settings. Businesses provides visible detail, rename and configuration actions, plus an organization-wide saved display order used by business selectors and groups throughout the app. See [business management](docs/business-management.md), including migration `004_business_order.sql`, before deploying the updated API.
