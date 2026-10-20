# Current connected deployment

The app now uses the Supabase-hosted API. Follow [Supabase-only runtime](supabase-only.md) for its configuration, security, deployment and verification. A running Mac and ADB forwarding are not required.

The standalone Nest/Firebase deployment instructions below describe an optional legacy runtime.

# Deployment and recovery

## Client

- Use real Firebase app configuration per Android/iOS/web target; `dart-defines.example.json` contains only emulator values.
- Set `USE_AUTH_EMULATOR=false`, `FIREBASE_PROJECT_ID`, `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_SENDER_ID`, and an HTTPS `API_URL`.
- Firebase API keys are client identifiers; never include admin/service-account credentials in Flutter. Enable email/password sign-in, authorized web domains, and suitable Firebase password/reset/verification policies.
- Run `flutter build web --release --dart-define-from-file=<production-config>` or `flutter build appbundle --dart-define-from-file=<android-production-config>`.
- Android release builds require private `android/key.properties` with `storeFile`, `storePassword`, `keyAlias` and `keyPassword`; they cannot silently use debug signing. Configure signing outside version control. iOS needs a valid bundle identity and signing setup.
- Hosting must serve `index.html` for unknown application routes. Static assets should return 404 when genuinely absent. Serve HTTPS with security headers and appropriate caching.
- Android debug HTTP is scoped to the debug manifest. For iOS local testing, create a Debug-only Info.plist configuration allowing local networking; do not enable arbitrary production transport exceptions.

## API

- `NODE_ENV=production`, `DATABASE_URL`, `FIREBASE_PROJECT_ID`, `CORS_ORIGINS` (comma separated exact origins) and `PUBLIC_APP_URL=https://...` are required.
- Remove `FIREBASE_AUTH_EMULATOR_HOST`. Use workload identity/application default credentials with least privilege to verify Firebase identities.
- TLS certificate verification is enabled for PostgreSQL. If necessary set `DATABASE_CA_FILE` to a mounted CA file, never disable certificate verification.
- Back up PostgreSQL before reviewed migrations. The initial startup installs the first-module schema; future migrations must be versioned and staged before production promotion.
- Accounts requires migration `003_accounts.sql`. Ship `backend/assets/fonts` (including its license), `migrations`, compiled `dist` and production dependencies together, and start from the backend directory so PDF reports can locate their font. Protected exports are generated on demand and are not served as public files. See `docs/accounts-module.md` for ledger and opening-balance behavior.
- Development binds to loopback by default; `APP_BIND_HOST` can explicitly override it for trusted local testing. Production binds to `0.0.0.0` by default. Serve behind an HTTPS reverse proxy. Do not expose the auth emulator, emulator UI or embedded database in production.
- Invitation links are manually shared. An email provider and delivery-status workflow have not been provisioned.

## CI and monitoring

The CI workflow runs Flutter analysis/tests and a debug web build, plus backend compilation and database-rule tests. HTTP smoke testing runs locally with the emulator, separately from the unit CI job.

Monitor API failures, auth failures, database connectivity, latency, request IDs and audit events. Never collect auth headers or sensitive bodies in monitoring. Set explicit retention for customer/staff data when those workflows go live.

## Recovery

For local work, stop the API cleanly before copying `.local/postgres`; stop the Firebase emulator cleanly to export `.local/auth`. These folders contain private local test data and are gitignored.

For production, provision encrypted daily backups and point-in-time recovery. Restore to a separate database, verify memberships/resources/audit history, and rehearse cutover. Recovery targets are not claimed until a real hosting service is configured and restoration has been tested.

## Host limitations

This host has incomplete Xcode and no CocoaPods. Android SDK licenses are not all accepted. Do not auto-accept license agreements or install tooling as part of CI troubleshooting; resolve them in the developer's normal platform setup.
