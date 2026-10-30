# Firebase booking notifications

The implementation registers signed-in Android/iOS installations with the authenticated booking API. Placed, cancelled and rescheduled ordinary bookings create durable events in their existing transaction. The dedicated Supabase `booking-notifications` function sends them through FCM HTTP v1 to owners and active staff with `manage_bookings` and matching business/resource assignments. Website and voice bookings use the same queue. Admission/coaching sessions, customer payments and check-ins are excluded. Owner-confirmed staff cash collections also use this queue, with separate participant-only eligibility; see [Cash collection notifications](staff-cash-notifications.md).

Notification titles identify order placed, cancelled or rescheduled. The body includes the customer name, space name, booking date and time range in the venue timezone, and booking reference. These details are saved in the existing booking-history JSON when each event is recorded, so delayed alerts retain that event's details after a reschedule or customer edit. For older events without a history snapshot, the sender uses the current booking details if the resource still matches the event; otherwise it sends only the reference to avoid exposing details of a newly assigned space. Phone numbers, email, notes and payment information are excluded. The notification data payload contains only the existing navigation/account identifiers. An eligible actor receives the notification too. Multiple devices per account are supported. Web/desktop push and customer push are outside this feature.

This document is a deployment handoff: no hosted migration, function deployment, secrets update, scheduler installation, or device installation has been performed by this work.

## 1. Prerequisites and preflight

- Confirm the intended Supabase project is `scwwkaywewecspsrskft` and the application schema is private `booking_app`. Preserve the current deployed function sources and secure database backup before deployment; do not overwrite cloud data from a local snapshot.
- Existing workspace, booking, website and admissions migrations must be applied. The new migration needs `bookings.admission_id`, `booking_history`, `memberships`, and `staff_assignments`.
- The existing `booking_api` database role must exist. It uses the same trusted server connection as the current API. No new database login or service-role client key is needed.
- Use the supplied Android Firebase project configuration. Its app package must match `bookingservice.tatos.tech`. The service account in step 3 must send for that same Firebase project.
- Enable the Firebase Cloud Messaging HTTP v1 API in that Google Cloud/Firebase project. Provision a dedicated service account with the Firebase Cloud Messaging API Admin role for that project, or a narrower custom role allowing message creation. Obtain its JSON key through your secure deployment process.
- Keep the key JSON out of Flutter assets, build defines, Git, chat messages and browser-delivered files. Use server secrets only.
- For scheduled delivery, enable Supabase `pg_cron` and `pg_net`. Supabase Vault must be available. The scheduling script is a separate, user-applied operation.

Run these read-only queries in Supabase SQL Editor as the database owner:

```sql
select current_database(), current_user;
select to_regnamespace('booking_app'), to_regrole('booking_api');
select column_name from information_schema.columns
where table_schema='booking_app' and table_name='bookings' and column_name='admission_id';
select name from booking_app.schema_migrations
where name='20261023071831_firebase_booking_notifications.sql';
select to_regclass('booking_app.notification_devices'),
       to_regclass('booking_app.booking_notification_events'),
       to_regclass('booking_app.notification_deliveries');
```

The schema, role and `admission_id` must exist. For a fresh application, the migration history query returns no row and the last three values are null. If the history row already exists, validate rather than rerun. If only some tables/history exist, stop and reconcile the partial deployment first. The script intentionally fails on existing tables rather than silently accepting a different schema.

## 2. Apply only this migration

In SQL Editor, paste and run the complete contents of:

`supabase/migrations/20261023071831_firebase_booking_notifications.sql`

It contains its own transaction, private search path, timeouts and application migration-history insert. It creates three empty tables and indexes, enables RLS, denies public/anon/authenticated access, and grants the existing trusted `booking_api` role SELECT/INSERT/UPDATE through server-only policies. Runtime DELETE privileges are explicitly removed. It does not rewrite existing booking or membership data.

The corresponding `backend/migrations/20261023071831_firebase_booking_notifications.sql` is the unwrapped source used by the isolated test/development migration runner. **Do not run both copies. Do not run the backend migration runner against production or push all pending Supabase migrations for this change.**

Run `supabase/manual-operations/booking-notifications-validation.sql`. Expect one history row, all three tables under `booking_app`, RLS enabled, only the trusted server role with table privileges, and no device/event/delivery rows until the feature is exercised. Keep `booking_app` outside the exposed Data API schemas.

Apply the migration before deploying the updated API. The API enqueues notifications by default; deploying it first would cause booking writes to fail when queue tables do not exist. For emergency application rollback, `BOOKING_PUSH_ENQUEUE_ENABLED=false` disables enqueueing without touching booking behavior.

## 3. Configure Supabase function secrets

Use Dashboard → Edge Functions → Secrets. Keep the existing `BOOKING_DATABASE_URL` and verified database CA settings used by `booking-api`. Both functions use that restricted connection with the private schema search path.

Add:

| Secret | Value |
| --- | --- |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | Complete service-account JSON, including `project_id`, `client_email`, and `private_key`. |
| `BOOKING_PUSH_DISPATCH_SECRET` | Cryptographically random value of at least 32 characters; use 32 random bytes encoded as hex. |
| `BOOKING_PUSH_DISPATCH_ENABLED` | `false` during deployment; set to `true` after validation. |
| `BOOKING_PUSH_ENQUEUE_ENABLED` | `true`, after the migration is applied. |

You can generate a dispatch secret locally with `openssl rand -hex 32` and transfer it securely to the Dashboard and Vault. Do not commit it. This secret authenticates only queue dispatch; it cannot choose recipients or message content.

For CLI-managed secrets, use a private environment file outside the repository and shell history, then:

```sh
supabase secrets set --env-file /absolute/private/path/booking-push.env --project-ref scwwkaywewecspsrskft
```

Set the JSON value as a single environment variable; preserve the private key's JSON `\n` escapes. Dashboard secret entry avoids shell quoting issues. Supabase function secrets are project-wide: application code accesses the sender credential only in `booking-notifications`.

## 4. Build and deploy the two functions

For the notification name/space/time update, deploy both functions using the steps below: `booking-api` records the event details and `booking-notifications` formats and sends them. No database migration, new secret, scheduler change or app rebuild is needed. Keep the existing scheduler and credentials. After deployment, create a new website booking and verify the customer, space and local time; reschedule and cancel it to verify the other titles and times. Already-sent alerts are not resent. For rollback, restore the previous two function versions; the additive history JSON remains compatible with older code.

From `backend`:

```sh
npm ci
npm run build
npm run edge:check
npm test
npm run edge:build
```

From the repository root, with an authenticated Supabase CLI:

```sh
supabase functions deploy booking-api --project-ref scwwkaywewecspsrskft --no-verify-jwt --use-api
supabase functions deploy booking-notifications --project-ref scwwkaywewecspsrskft --no-verify-jwt --use-api
```

Alternatively, use Dashboard function editors and paste the generated `supabase/functions/booking-api/index.ts` and `supabase/functions/booking-notifications/index.ts` into their respective functions, retaining Node module support. Disable gateway legacy JWT verification for both: the API verifies actual user sessions itself, and the sender requires the constant-time checked `x-booking-push-secret`. `supabase/config.toml` records this configuration. Never make the sender public by removing its internal check.

The build generates both standalone entrypoints from shared source. Edit `backend/src/notifications` and `backend/edge`, then rebuild; do not hand-edit generated copies. No credentials are embedded in these generated files.

Use the Dashboard invocation tester for `booking-notifications`: POST an empty JSON object with `x-booking-push-secret` set securely. With dispatch disabled expect `{"disabled":true}`. Without the header expect 401. Now set `BOOKING_PUSH_DISPATCH_ENABLED=true`; an empty queue returns aggregate zero counts. Actual delivery is verified only after a configured device has logged in and a booking event exists. Caller-supplied tokens/message bodies are deliberately ignored.

## 5. Install scheduled dispatch

In Dashboard Vault, add exactly one secret for each name:

- `booking_push_project_url`: `https://scwwkaywewecspsrskft.supabase.co`
- `booking_push_dispatch_secret`: the identical value used for `BOOKING_PUSH_DISPATCH_SECRET`

Run `supabase/manual-operations/booking-notifications-schedule.sql` as the database owner. It checks prerequisites and creates or updates the named `booking-push-dispatch` job to invoke the sender every 10 seconds. This is database scheduling; no Codex recurring task is involved. If the installed pg_cron rejects second-based intervals, use `* * * * *` instead of `10 seconds` in that script for once-per-minute dispatch.

```sql
select jobid,jobname,schedule,active from cron.job where jobname='booking-push-dispatch';
select id,status_code,timed_out,created from net._http_response order by created desc limit 10;
```

Expect one active job and HTTP 200 responses. The sender claims up to 20 delivery targets per invocation with four concurrent sends. Increase capacity through a reviewed server batch/concurrency change if queue age grows; do not create duplicate schedules. Overlapping invocations use leases and `SKIP LOCKED` to avoid simultaneous delivery of the same queued target.

Supabase notes that decrypted request headers are temporarily stored in `net.http_request_queue`; database login users must therefore be trusted. Use the dedicated dispatch-only secret above, keep Vault/queue access restricted, and never substitute a broad service-role key. See [Supabase scheduling guidance](https://supabase.com/docs/guides/functions/schedule-functions).

## 6. Android configuration and build

The code adds Firebase Messaging, local foreground notification display, the Google Services Gradle plugin, Android 13+ notification permission, a high-importance `booking_orders_bell_v2` channel, a monochrome status icon, background handling and notification taps.

`Firebase.initializeApp()` runs for notifications independently of Supabase Auth, using native Firebase configuration. No Firebase authentication login is needed. The supplied `android/app/google-services.json` must belong to the intended Firebase project and package. The Android minimum is now API 24 (Android 7), matching the notification package requirements. Devices need Google Play services.

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

For production, configure the existing private release signing file and use `flutter build apk --release`. Test with the Supabase authentication provider (the default). The alternate Firebase Auth emulator path is retained, but device push registration is intentionally limited to the production Supabase identity/API flow.

Building does not install the APK. Install or distribute it yourself when ready, log in, and grant notification permission. Registration also runs for a restored session and on token refresh. Temporary network/APNs failures retry with bounded delay and on app resume. A denied permission leaves login and bookings usable; re-enable it in OS settings and resume the app.

### Custom Android notification sound

Placed, cancelled and rescheduled push notifications use the existing
`android/app/src/main/res/raw/new_booking_bell.mp3`. Foreground local alerts and
the `booking_orders_bell_v2` channel select `new_booking_bell`; the FCM sender
sets both `android.notification.channel_id` and `android.notification.sound`.
The manifest default channel matches, so console test messages without an
explicit channel also use the bell after the app has initialized the channel.
The sound and status icon are explicitly retained during resource shrinking.

Android channel sounds cannot be changed after channel creation. The new ID
replaces `booking_orders` for future alerts without deleting the old channel.
Users can still change or mute the new channel in system settings. See
[Android channel behavior](https://developer.android.com/develop/ui/views/notifications/channels)
and [FCM sound/channel fields](https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages#AndroidNotification).

To roll out this configuration:

1. Rebuild and distribute the Android app, then open it and log in once to
   create the channel before testing background/terminated delivery. Hot reload
   does not update native resources or the manifest.
2. From `backend`, run `npm run edge:build`. From the repository root, deploy
   `supabase functions deploy booking-notifications --project-ref scwwkaywewecspsrskft`.
   This sound change needs no database migration or secrets change. An existing
   Nest server deployment instead needs the rebuilt backend containing the sender.
3. Test all three booking events with the app open, in the background and after
   a normal close. Confirm the bell plays and the alert opens the correct booking.
   For a bare Firebase console test, put the app in the background; foreground
   alerts require the valid booking/account data used by the booking sender.
   Check notification permission, channel sound, notification volume and Do Not
   Disturb if a delivered notification is silent.

The MP3 is an Android resource. iOS continues to use its default notification
sound. Real-device sound playback and FCM delivery require testing after rollout;
the earlier test-send attempt was rejected with `403 PERMISSION_DENIED`.

## 7. iOS provisioning

Push entitlements, debug/development versus release/production APNs environment, background modes, the UIScene-compatible messaging delegate, and foreground presentation code are prepared. Complete the account-specific provisioning:

1. In Firebase, register the iOS app with bundle ID `bookingservice.tatos.tech` in the same project.
2. Download its `GoogleService-Info.plist`; add it through Xcode to the Runner target and verify target membership and Copy Bundle Resources. This file is not present in the current checkout and cannot be invented.
3. In `ios/Runner.xcworkspace`, select your Apple development team and valid provisioning profiles. Enable Push Notifications and Background Modes → Background fetch / Remote notifications. Confirm the profile allows the `aps-environment` entitlement. Keep Firebase method swizzling enabled.
4. Upload your APNs `.p8` authentication key, key ID and Apple team ID in Firebase → Project settings → Cloud Messaging. Keep the `.p8` private.
5. Build/sign through your normal iOS distribution process and test on a provisioned physical device. The client waits for the APNs token before fetching an FCM token; failures retry rather than blocking login.

See [Firebase Flutter messaging setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started). iOS delivery remains unverified until provisioning and real-device acceptance are complete.

## 8. Acceptance and monitoring

Use an owner device, an assigned staff device with `manage_bookings`, and a separate organization/unassigned staff account. Log in before creating the test booking; devices newly registered after an event do not receive historical alerts.

Place a booking through the app and public website, reschedule it, then cancel it. Exercise the voice path when configured. Verify eligible devices receive the three events and unrelated accounts/spaces receive nothing. Verify foreground, background and normal terminated launches; taps must open the correct booking after authentication/workspace restoration. A freshly fetched detail still enforces server access. Android force-stop and Apple force-quit can prevent background delivery until reopening.

Verify logout and account switching do not reuse the previous account's registration. Logout attempts server unlink and token deletion before clearing credentials and removes displayed local notifications. An installation proof permits retrying failed unlink after session expiry; it allows only revocation of that installation, never sending. The 256-bit proof stays in device secure storage; only its SHA-256 hash is stored server-side. Offline logout cannot guarantee immediate server revocation or recall notifications already accepted by FCM. Pending cleanup is retained and retried before registering another account.

Run the validation SQL again. Monitor unexpanded event age, due delivery age, `retry`/`dead` counts and sanitized error codes. Function logs contain aggregate counts, not device tokens or customer details. `sent` means FCM accepted the message, not that an OS displayed it. Events expire after 24 hours; installations not seen for 60 days are excluded. Transient errors retry up to eight attempts with exponential delay and provider Retry-After support. Only an explicit `UNREGISTERED` FCM error disables a token, and a version check protects a newly refreshed token. Delivery is at least once; stable event IDs/Android tags/foreground deduplication reduce duplicates but cannot guarantee exactly-once display after an uncertain network response.

Suggested operator retention, after reviewing your own audit policy: prune expanded events older than 30 days only when none of their deliveries is pending/processing (delivery rows cascade), and prune disabled devices older than 60 days only after confirming no active delivery refers to them. Do not delete booking history as part of notification cleanup. No destructive retention job is installed automatically.

Useful failure codes: `FCM_CREDENTIALS`/`FCM_OAUTH` require credential/API/IAM checks; `FCM_HTTP_401`/`403` require sender/project authorization checks; `FCM_HTTP_429` and network/5xx errors retry; `UNREGISTERED` means reinstall/refresh the client; `INELIGIBLE_OR_EXPIRED` is an intentional access/age skip. Never dump a provider response, device token, or full credentials to diagnose these errors.

## 9. Recovery and rollback

1. Set `BOOKING_PUSH_DISPATCH_ENABLED=false` and pause the scheduler:

   ```sql
   update cron.job set active=false where jobname='booking-push-dispatch';
   ```

2. Set `BOOKING_PUSH_ENQUEUE_ENABLED=false` if stopping event collection. Booking transactions continue normally. Existing leases expire after three minutes; do not manually resend messages already marked `sent`.
3. Fix/redeploy credentials or application functions, review queue age and current permissions, re-enable dispatch and the same job. Events older than 24 hours are skipped. To retry reviewed dead deliveries still within the age limit, reset only the selected event/device rows to `pending`, `attempts=0`, `next_attempt_at=now()`, and null lease fields; this can duplicate a message whose response was lost.
4. For application rollback, restore the saved previous function sources and app release while leaving the additive tables in place. This is the preferred recovery route.
5. Only if intentionally removing the feature: stop dispatch/enqueue, revert the API first, export any required queue audit data securely, then as database owner run:

   ```sql
   select cron.unschedule(jobid) from cron.job where jobname='booking-push-dispatch';
   begin;
   set local search_path=booking_app,pg_catalog;
   drop table notification_deliveries;
   drop table booking_notification_events;
   drop table notification_devices;
   delete from schema_migrations where name='20261023071831_firebase_booking_notifications.sql';
   commit;
   ```

   This removes registration and notification audit data. It does not remove bookings/history. Remove obsolete Vault/function secrets only after confirming no other deployment uses them; rotate the sender key if exposed. Do not apply this removal while the new API is still enqueueing.

## API contracts

All responses use no-store. Device data is private and is never returned by listing APIs.

- `POST /v1/notifications/devices`: authenticated Supabase user; JSON `{installation_id, installation_secret, token, platform}`. The server derives user identity. Returns `{id, registered:true}`. Idempotent for the same installation/token. Wrong installation proof is forbidden; a token claimed by a different installation conflicts.
- `POST /v1/notifications/devices/:id/unregister`: authenticated owner plus `{installation_secret}`; idempotently returns `{unregistered:true}`.
- `POST /v1/notifications/installations/revoke`: `{installation_id, installation_secret}`; proof-authenticated cleanup usable after logout, rate limited, with the same idempotent result. Incorrect proof changes nothing and reveals no account data.
- `POST /functions/v1/booking-notifications`: internal `x-booking-push-secret`; empty body. Returns `{claimed,sent,skipped,retry,dead}`. No caller-selected recipients or payloads.

Invalid registration data uses the existing structured validation errors; missing user auth is 401, wrong proof is 403, token collision is 409. Setup/delivery failures never turn a successful login or already committed booking into a failure.

## Implementation verification — 23 October 2026

- Backend: 276 regression tests passed. Additional protocol/private-schema tests (3) and a concurrent-dispatch/retry-limit test (1) passed: 280 distinct backend tests verified. The final hosted migration was exercised in an isolated database with `booking_api`, `anon` and `authenticated` roles; runtime DELETE and public client access are denied.
- Backend formatting, TypeScript build, Edge source type checking and both generated Edge bundles passed.
- Flutter: final analysis is clean; formatting checked across 427 source/test files. All 18 focused notification/authentication tests passed, including startup/session restoration, permission denial, token refresh, stale callbacks, logout serialization and the initialization/logout race.
- The full Flutter suite completed with 534 passes and two UI failures: the 320px invitation auth form overflows by 20 pixels; the call-log transcript test expects a missing “Talk time” label. Both failures were reproduced in the original source at Git revision `8d21655` in a separate temporary snapshot. These existing UI issues were left outside this notification change.
- The final-source Android debug APK built successfully at `build/app/outputs/flutter-apk/app-debug.apk`; no device installation was performed. Manifest inspection confirmed package `bookingservice.tatos.tech`, minimum API 24, POST_NOTIFICATIONS permission, FCM service/receiver, default channel and disabled pre-login auto initialization.
- The web debug build passed with `--no-web-resources-cdn`. Device-registration writes bypass booking read-cache invalidation, and the legacy Firebase Auth path uses a separate named Firebase app so native Messaging configuration does not collide with emulator options.
- iOS project/plist/entitlement syntax checks passed. A signed iOS build and real-device delivery remain pending the Firebase plist, Apple/APNs provisioning and deployment steps above. Live Supabase validation is also pending user application; no hosted data, secrets or schema were changed.
