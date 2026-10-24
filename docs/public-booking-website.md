# Public booking website

One organisation has one public website at `https://<organisation-slug>.bookingos.online` (see [Subdomains and Design website](#subdomains-and-design-website--deployment-update)); `/<organisation-slug>` path routing remains for local/IP hosts and old links on the main domain redirect to the subdomain. Its enabled, active businesses share the existing booking inventory with the owner/staff app and phone bookings. The organisation homepage introduces the venue with its description, an optional uploaded hero image and service cards with starting tariffs. Each card opens a dedicated booking page at `/<slug>/book/<business-id>`. The screenshot-based booking interface uses navy/teal cards, a horizontal date strip, illustrated turf/court/pool spaces, uploaded space galleries, start/finish selection, and a reservation summary. Courts have no duration chips or increment controls.

## Included

- Profile → **Design website** (native app and Flutter web): subdomain address, title, hero heading, description, public phone, website logo upload (or the organisation logo), homepage hero image, enabled services with homepage card photo and description, per-space show/hide, booking page photos and booking rules (notice, window, visitor rules, copy to all spaces), social media links, default rules, venue instructions and cancellation policy.
- Automatic private draft for new organisations; existing organisations get their draft on first opening settings. Select businesses and publish explicitly.
- Preview links expire after one hour, are read-only and are revoked by settings/publication changes or another preview. Treat them as private capabilities. Redact `preview` query parameters from hosting/access logs; never log request bodies. Next development request logging is disabled.
- Publish, pause/resume, unpublish, open and copy-link actions. Owners can change the address after publication. The previous address stops resolving to the website after a rename; update shared links and ask visitors with an in-progress booking at the old address to contact the venue before retrying.
- Normal turf, court, pool and hall bookings. Group offers, coaching, admissions, swimming plans and recurring purchases are excluded by the public server policy as well as the UI.
- Name/phone checkout, review and confirmation. Pool bookings include participant count and per-person pricing. Owner-configured UPI transfers can be declared at checkout with a transaction ID, but no gateway, automatic collection or bank verification is provided. Customer login, OTP, public booking lookup, cancellation and rescheduling endpoints are not exposed.
- Booking confirmation is unpaid unless the price is zero, even when a customer submits a UPI reference. Collections remain in the existing staff flow after bank verification. Browsing, quotes and transfers made outside the application never hold inventory.
- Confirmations use the existing business lock, shared allocation checks and slot blocks. Persisted command keys prevent duplicate writes. Uncertain confirmations retain the exact command in session storage for up to 24 hours; retries remain locked to that command and are removed on success/definitive rejection. No customer data goes into browser URLs.

The owner approves public contact/location information when publishing. The existing private organisation logo is public only when explicitly enabled. Guest phone numbers are validated but their ownership is not verified. Guest input never overwrites an existing customer profile based on an unverified phone number.

### UPI checkout and per-space advance collection

**Owner flow:** Profile → Accounts & payments → Website payment details. Upload a static payment QR (PNG/JPEG/WebP up to 1 MB), enter its matching UPI ID, then save. Preview, replacement and removal are supported. Both fields are needed to offer UPI checkout. Use a QR without a fixed amount and verify its beneficiary yourself: uploading an image does not authenticate the QR or prove that it matches the typed ID. Only owners can configure these details; stale versions cannot overwrite another edit.

Profile → Design website → Services & spaces → expand a space → **Collect payment mandatory**. Select Half (50%), Full (100%) and/or one custom whole percentage from 1–99 other than 50. Combinations such as 25% + 50%, 50% + 100%, or all three work. Mandatory collection needs at least one choice. Copy booking rules does not copy payment policies. Disable mandatory collection on all configured spaces before removing the organization's UPI ID or QR.

**Customer flow:** Review checkout shows the QR, copyable UPI ID, amount chips and a transaction ID/UTR field for a selected UPI option. Mandatory spaces cannot submit without a configured choice and a 6–64-character reference. Other spaces retain Pay at venue and may offer Full via UPI. Percentages use the full server-calculated booking total, rounded up to the nearest minor unit. Free bookings need no payment; UPI is only offered for INR. QR requests carry the settings version, preventing a new QR from being paired with an old checkout UPI ID.

References are uppercase-normalized and unique per organization. The booking stores the claimed percentage, server-calculated amount, UPI snapshot and reference as `pending_verification`. Quote tokens cover payment terms, and retries replay the exact command safely. Owner/staff booking details display the reference for reconciliation. This does not create a ledger entry, reduce the balance or confirm receipt of money. After checking the bank, staff record the verified collection using existing payment controls. The submission remains a historical customer claim, not a bank verification status.

**Limitations:** This is manual payment reporting, not a verified payment gateway. False references and mismatching QR images cannot be detected reliably. Browsing and external payment do not hold inventory; the venue must reconcile/refund a transfer if booking subsequently fails. Checkout warns against paying twice after a failed request. Automated verification, payment webhooks, refunds and inventory holds require separate work.

#### API contract

- Owner GET `/v1/accounts/website-payments`: `{version, upi_id, has_qr, qr: {content_type, base64} | null}`.
- Owner POST the same route: `{version, upi_id, qr?: {content_type, base64} | null}`. Omission preserves the QR; null removes it. Invalid images/IDs fail validation, stale versions return 409, and non-owners are forbidden. No-store applies.
- Website-settings space fields: `payment_required`, `payment_percentages`. Older clients omitting these fields preserve existing mandatory policies; the new app sends every space explicitly so policies can also be disabled.
- Public quote adds `payment: {required, upi_id, has_qr, version, options: [{percentage, amount_minor}]}`. Public GET `.../payment-qr?v=<version>` returns raster bytes for an accessible website only.
- Public booking accepts `payment: {percentage, transaction_id}` when a customer chooses UPI. Mandatory policies require it. Invented percentages, extra amount/status fields, stale terms and reused references are rejected. Replies include `website_payment_submission` or null; ordinary `payment_status` remains unpaid unless the booking is free.

#### Migration and rollout — user applies

No production schema, payment details or bookings were changed. Back up `booking_app` first. Confirm the live project is `scwwkaywewecspsrskft` and earlier migrations through `20261024101355_admin_sarvam_provisioning.sql` are applied. The existing runtime `booking_api` role must exist.

1. Run the complete `supabase/migrations/20261024135923_website_upi_payments.sql` once in that project's SQL editor. It contains BEGIN/COMMIT, the `booking_app` search path, lock timeout and application migration-history entry. Do not apply the backend copy to the same database. The new table has RLS and server-role-only access; no direct anonymous/authenticated access is granted.
2. Validate before deployment:

If the SQL editor reports `relation "organizations" does not exist`, first run `SELECT to_regclass('booking_app.organizations');` in the selected project. A null result means the required application table is absent in that database: stop and check the project and prerequisite migrations. A non-null result means the table exists; use the complete schema-qualified Supabase migration above, not the local backend copy or a selected fragment. Do not create a replacement empty `public.organizations` table.

```sql
SELECT name FROM booking_app.schema_migrations
WHERE name='20261024135923_website_upi_payments.sql';
SELECT to_regclass('booking_app.website_payment_settings'),
       to_regclass('booking_app.website_payment_transaction_unique');
SELECT relrowsecurity FROM pg_class
WHERE oid='booking_app.website_payment_settings'::regclass;
SELECT column_name FROM information_schema.columns
WHERE table_schema='booking_app' AND
 ((table_name='booking_website_spaces' AND column_name IN ('payment_required','payment_percentages'))
 OR (table_name='bookings' AND column_name='website_payment_submission'));
SELECT grantee,privilege_type FROM information_schema.role_table_grants
WHERE table_schema='booking_app' AND table_name='website_payment_settings';
```

Expect one migration-history row, both objects, RLS true, all three columns and SELECT/INSERT/UPDATE for the application role `booking_api` (no PUBLIC/anon/authenticated grants). Database owners retain their normal administrative rights. Existing spaces default to optional collection. If a lock timeout or statement fails, the transaction rolls back; investigate before retrying rather than inserting migration history manually.

3. Deploy the updated backend/Edge bundle first, then the public website and Flutter client. Do not publish clients against an old API. Local tests apply only the matching backend migration in isolated in-memory PGlite, never production.
4. Configure real QR/UPI settings and exercise a test space before broad rollout. Do not make real transfers just to smoke-test this interface without a separately approved test plan.

**Recovery:** Prefer a forward fix. Pause affected public websites before rolling back to an API that cannot enforce mandatory collection. Preserve/export the payment-settings table, per-space columns and booking submission data, which may be needed for reconciliation. Do not drop these during an app rollback. Destructive schema recovery requires a verified backup and a separately approved plan; this feature does not perform refunds or reversals.

#### Local verification

The affected Flutter regression suite passed 57 tests, including QR upload/save/remove, UPI validation, percentage combinations and the new custom field's separate scroll-state key. Flutter static analysis reported no issues. Backend accounts/website regression checks passed 35 tests; the final focused payment and production-migration suite passed seven tests, including legacy-client policy preservation, server-calculated amounts, required references, duplicate detection, idempotent retries, stale terms/QR versions, owner/tenant boundaries, RLS, grants and database constraints. These counts overlap and should not be added together. The public website's existing 16 tests, typecheck and production build passed; backend and Edge typechecks/builds passed.

Read-only HTTP checks against an isolated in-memory fixture verified the production checkout route, QR PNG proxy and stale-version rejection. Interactive browser verification was unavailable because the browser connection could not be opened; no desktop/mobile checkout-click or real bank-transfer verification is claimed. No production migration, deployment or financial transaction was performed.

The Flutter web release build also completed successfully (`flutter build web --release --no-pub --no-wasm-dry-run`). The final public website production rebuild passed after the receipt-copy updates. These builds produce local artifacts only.

### Browser tab logo

The organisation homepage and each business booking page use the same public logo as the header for their favicon: an uploaded website logo takes priority, followed by the organisation profile logo when its publication switch is enabled. Without a public logo, the tab uses the bundled BookingOS icon (`booking-website/assets/bookingos-icon.png`, copied from `web/icons/Icon-192.png`). The shared `siteIcons` metadata helper uses the existing public logo proxy, including the preview token on preview pages, and does not expose private profile logos. This works on organisation subdomains and path-based URLs. Updating an already-open tab may require a reload because browsers retain favicons.

Verification: the production website build and all 13 existing website tests passed. A temporary, isolated local production fixture verified 16 homepage/booking favicon combinations across two organisations, no-logo fallback, preview tokens, path URLs and tenant Host headers. Each rendered page emitted exactly one icon link; its image returned the expected PNG bytes, and public logo proxy responses retained `no-store`. No hosted deployment or database change was performed.

## Source boundaries

- `booking-website/`: pinned Next.js/React application. Server-only API proxy forwards only the public site operations, bounds JSON requests to 16 KiB, and never forwards owner bearer tokens. Metadata and initial HTML share a request-scoped public read. Customer/quote/availability responses are `no-store`.
- `backend/src/website/`: owner settings and restricted public operations. Public responses are explicit projections without business configuration, staff, coaching definitions, customer directories or bank/payment routing.
- `backend/src/bookings/booking.availability.ts`: existing authoritative availability algorithm extracted without changing booking rules, shared with `BookingService`.
- `lib/modules/booking_website/`: typed settings model, repository, owner-scoped Cubit and settings screen. Access changes/disposal discard in-flight results.
- `backend/scripts/website-preview.ts`: isolated in-memory preview only. It refuses remote persistence through its fixtures and clears inherited database configuration before startup.

Availability and pricing use each business location's timezone. Money is in integer minor units. Use the configured minimum duration and current 15-minute extension rules; fixed hall sessions/full-day offerings retain their configured duration. The selected start time determines the applicable tariff.

## Local setup

Requirements: Node.js 22+ (verified with Node 24), the repository's Flutter SDK, and npm. Install dependencies once:

```sh
cd "/Users/albinosiby/Tatos Dev/booking/backend"
npm ci
cd ../booking-website
npm ci
```

To preview all six business types without touching any persistent or live data, use two terminals:

```sh
cd "/Users/albinosiby/Tatos Dev/booking/backend"
node --import tsx scripts/website-preview.ts
```

```sh
cd "/Users/albinosiby/Tatos Dev/booking/booking-website"
BOOKING_API_BASE_URL=http://127.0.0.1:3101 npm run dev
```

Open `http://localhost:3000/eden-sports`. **This contains fictional fixture data, not the live organisation.** Preview bookings disappear when the API process stops. Ctrl+C stops each process. The preview provides public booking only; use the real authenticated app to exercise owner settings against an appropriately migrated development database.

For an ordinary API connection, copy `booking-website/.env.example` to `.env.local` and set:

| Variable | Location | Purpose |
| --- | --- | --- |
| `BOOKING_API_BASE_URL` | Next server | API origin/function base **without** trailing `/v1` |
| `BOOKING_API_PUBLISHABLE_KEY` | Next server | Supabase publishable project key, when using hosted Edge |
| `BOOKING_WEBSITE_URL` | API/Edge secret configuration | Required public website origin, e.g. `https://book.example.com` |

Do not put a service-role key, database URL or owner token in the website. HTTPS is required except explicit localhost development. For the legacy Nest API, use a different port such as `PORT=3100` because the website uses port 3000. Private owner APIs remain protected by the existing authentication and membership checks.

## Database migration — user applies

**No live migration is applied by this implementation.** Apply the exact reviewed file only when ready:

`supabase/migrations/20261022034634_public_booking_websites.sql`

Then apply the photo migration described below: `supabase/migrations/20261022045215_booking_website_images.sql`. If the base migration is already applied, apply only the photo migration.

The filename was generated with `supabase migration new public_booking_websites`. `backend/migrations/20261022034634_public_booking_websites.sql` is the equivalent application-schema DDL for isolated/local databases; it is not the cloud handoff file.

Prerequisites:

1. Take a current database backup and save the currently deployed `booking-api` source. Confirm how to restore that backup before proceeding.
2. Apply the existing project migrations first. The `booking_app` schema, `schema_migrations`, organisation/business/resource/booking tables, business display order and restricted `booking_api` role must exist. Use an administrator capable of DDL and role grants; never change the application's connection to an administrator.
3. Confirm this migration has not been applied and its new tables do not already exist:

```sql
SELECT name FROM booking_app.schema_migrations
WHERE name = '20261022034634_public_booking_websites.sql';
SELECT to_regclass('booking_app.booking_websites'),
       to_regclass('booking_app.booking_website_businesses'),
       to_regclass('booking_app.booking_website_limits');
SELECT count(*) AS existing_bookings FROM booking_app.bookings;
```

The first query should return no rows; the three table names should resolve to null. Record the booking count. If the state differs, investigate rather than rerunning or dropping tables.

4. Open the reviewed cloud migration in the Supabase SQL editor and run its entire contents once. It sets the private schema, uses a 10-second lock timeout, creates scoped foreign keys and server-only RLS policies, grants the existing restricted role access, and records its migration in one transaction. The new booking source fields are nullable, preserving unknown historical sources. Existing bookings/payments are not rewritten.

Alternatively, with the administrator connection configured privately in the environment:

```sh
psql "$BOOKING_MIGRATION_DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f "/Users/albinosiby/Tatos Dev/booking/supabase/migrations/20261022034634_public_booking_websites.sql"
```

5. Validate before deploying the new API:

```sql
SELECT name,applied_at FROM booking_app.schema_migrations
WHERE name = '20261022034634_public_booking_websites.sql';
SELECT count(*) AS existing_bookings FROM booking_app.bookings;
SELECT column_name FROM information_schema.columns
WHERE table_schema='booking_app' AND table_name='bookings'
AND column_name IN ('booking_source','booking_website_id');
SELECT tablename,rowsecurity FROM pg_tables
WHERE schemaname='booking_app'
AND tablename IN ('booking_websites','booking_website_businesses','booking_website_limits');
SELECT grantee,table_name,privilege_type FROM information_schema.role_table_grants
WHERE table_schema='booking_app'
AND table_name IN ('booking_websites','booking_website_businesses','booking_website_limits')
AND grantee IN ('anon','authenticated','booking_api')
ORDER BY table_name,grantee,privilege_type;
SELECT count(*) AS invalid_website_scope FROM booking_app.booking_website_businesses wb
JOIN booking_app.businesses b ON b.id=wb.business_id
JOIN booking_app.booking_websites w ON w.id=wb.website_id
WHERE wb.organization_id<>b.organization_id OR wb.organization_id<>w.organization_id;
```

Expect the migration entry, unchanged historical booking count, both new columns, RLS enabled on all three new tables, grants only for `booking_api` among the listed roles, and zero invalid scopes. These tables stay in the existing unexposed private schema.

## Deployment order

1. User applies and verifies the migration above.
2. Build/type-check the shared API and generate the Edge artifact:

```sh
cd "/Users/albinosiby/Tatos Dev/booking/backend"
npm run build
npm run edge:check
npm run edge:build
```

3. Set `BOOKING_WEBSITE_URL` to the final HTTPS website origin in the API/Edge configuration. Keep existing database credentials and internal Auth validation. The current function already uses `verify_jwt=false` with explicit route-level authentication; public endpoints do not change authentication on the existing owner/staff routes.
4. Deploy the generated `supabase/functions/booking-api/index.ts` using the project's existing deployment process. Deploy the updated Flutter app and the Next application. `npm run build` creates the website production build; use hosting that supports Next.js server routes. For standalone hosting, place HTTPS in front of `next start` and configure its host/port for that host. This is not a static-export application.
5. In Profile → Booking website, verify the URL, choose businesses, approve public contact/location/logo content, save, preview, and publish. Run a deliberate test booking only in an approved test organisation. Verify it appears in the app and blocks the same slot; do not create unrequested live bookings to test connectivity.

No hosted deployment, migration application or device installation is performed by the local build workflow.

## API contracts

Owner, verified bearer session and organisation owner required:

| Method | Path | Body |
| --- | --- | --- |
| GET | `/v1/booking-website` | — |
| PUT | `/v1/booking-website` | Complete settings, `version`, `business_ids` |
| POST | `/v1/booking-website/publish` | `{ "version": 2 }` |
| POST | `/v1/booking-website/pause` | `{ "version": 3 }` |
| POST | `/v1/booking-website/unpublish` | `{ "version": 4 }` |
| POST | `/v1/booking-website/preview` | `{}`; returns one-hour read-only URL |

Public, no customer account required:

| Method | Path |
| --- | --- |
| GET | `/public/v1/sites/:slug` or `/catalog` |
| GET | `/public/v1/sites/:slug/logo` (explicitly published logo only) |
| POST | `/public/v1/sites/:slug/availability` |
| POST | `/public/v1/sites/:slug/quote` |
| POST | `/public/v1/sites/:slug/bookings` |

Availability body: `{ "selection": { "business_id": "UUID", "resource_id": "UUID", "option_id": "hourly", "date": "2026-10-25", "time": "10:00", "duration_minutes": 60, "people": 1 }, "end_times": false }`. The option ID comes from the public catalog. Set `end_times` true after choosing a start. Pool count affects capacity and price.

Quote accepts `{ "selection": ... }` and returns the authoritative price, local/UTC times, currency and `quote_token`. Confirmation accepts `{ "command_key": "UUID", "selection": ..., "quote_token": "TOKEN", "customer": { "name": "Customer name", "phone": "+919000000000" } }`. Reuse the exact body/key after network uncertainty; never generate another key to retry that write. The response contains `reference`, `status`, `payment_status`, times and total. Existing customer IDs, discounts, payments, notes and arbitrary organisation IDs are rejected.

Errors use the existing safe API contract: validation 422, private/unknown website or business 404, denied owner access 403, conflicts/changed quotes 409, and rate limits 429. Quotes never grant access to another site or reserve capacity.

## Abuse controls and monitoring

Shared database counters enforce 1,200 public reads/attempts per website per minute, 30 new confirmations per website per hour, and three per normalized phone per hour. These conservative launch limits are code-defined; review them against actual venue demand before a wider rollout. A phone is not a verified identity, and global limits can also affect legitimate users during abuse. Expired buckets are removed on public reads. Edge burst controls remain supplemental.

Monitor request IDs, safe error names, website failure/conflict rates, 429s, latency, and aggregate database connection use. Never log customer bodies or preview capabilities. Back up the existing database and periodically test restoration; no backup/PITR entitlement is assumed.

## Recovery

- A failed migration transaction rolls back as a unit. Confirm its history entry is absent, fix the cause (for example a lock timeout), and have the user rerun the full reviewed file. Do not mark it applied manually.
- To stop bookings, use **Pause bookings** or **Unpublish**. For an emergency database-side shutdown, the user can run:

```sql
UPDATE booking_app.booking_websites SET status='unpublished',
  version=version+1,preview_hash=NULL,preview_expires_at=NULL,updated_at=now();
```

- Restore the previously saved API/frontend builds if needed. Keep the additive schema and website-origin bookings: the previous app still reads ordinary bookings and inventory allocations. Do not drop tables/columns or delete bookings as a code rollback.
- Do not restore an old database snapshot over newer bookings. Database disaster recovery needs a deliberate reconciliation of bookings and financial records after the backup.

## Verification

```sh
cd "/Users/albinosiby/Tatos Dev/booking/backend"
node --import tsx --test test/website.test.ts test/website-images.test.ts test/website-edge.test.ts test/bookings.test.ts test/edge.test.ts
npm run build
npm run edge:check
cd ../booking-website
npm run typecheck
npm run build
cd ..
flutter test test/booking_website_test.dart test/router_configuration_test.dart test/business_management_test.dart
```

The website tests cover normal-only projections, guest input restrictions, tenant/owner scope, command replay, capacity/shared footprints, start/end choices, publication, read-only preview and shared rate limits. Browser QA uses only the isolated in-memory preview. Hosted schema/deployment verification remains pending the user's migration and deployment steps.

### Checked locally on 22 October 2026

- Full backend suite: **239 tests passed**. The final focused website/Edge checks also passed after the final projection/history adjustments.
- Affected Flutter settings, routing and profile/business tests: **17 passed**; targeted Flutter analysis reported no issues.
- Next production build/type-check, TypeScript build, Edge check and generated Edge bundle passed.
- Browser checks exercised desktop and narrow layouts, court start/finish pricing, and a complete one-hour turf booking in the isolated database. The exact-minimum duration now refreshes its quote, and success does not trigger another quote or show a stale inventory error.
- Screenshots: `screenshots/public-booking-desktop.png` and `screenshots/public-booking-confirmation.png`. These show fictional local data.
- No live migration, hosted deployment, APK build or phone installation was performed.

## Homepage and photos — deployment update

**User applies this additional migration; it has not been applied live:**
`supabase/migrations/20261022045215_booking_website_images.sql`

This filename was generated by the Supabase CLI. The matching `backend/migrations/20261022045215_booking_website_images.sql` is only the local application-schema DDL. Do not apply both versions to the same database.

### Product and data flow

Visitors land on `/<slug>`, read the organisation description and browse enabled services. Service cards show the lowest configured normal tariff with its duration (and per-person label for pools). Selecting one opens `/<slug>/book/<business-id>`, which contains only that service. A gallery follows the selected resource; selecting a different court or turf layout updates the gallery. An **All services** link returns to the homepage. Direct links work, missing/disabled services return 404, and owner preview tokens carry through both routes. Normal-only restrictions and shared inventory remain enforced by the existing API. Pending confirmation retries are scoped to each service in session storage.

Owners manage photos from **Profile → Design website**. Select or replace a logo, hero, service-card or space photo alongside other design edits. Selections preview locally with a **Not saved yet** label; selecting, replacing and removing photos do not write to the server. **Save changes** applies the pending photos and form edits. An explicit publication action also saves pending changes before updating publication status. Photos become visible on an already-published site only after that explicit save; drafts remain private. The first space photo is the cover. Photos belonging to removed resources remain removable in the settings screen and stay hidden from visitors. Removing the hero restores the styled fallback. Removing all space photos leaves the existing illustration available.

The Flutter repository accepts static JPEG/PNG/WebP sources up to 2 MiB, decodes them with a 24-megapixel limit, honours orientation, removes EXIF/camera metadata, resizes to a maximum 1920-pixel edge, and encodes JPEG (maximum 1 MiB). Native encoding runs in a worker isolate. The server independently validates type, file signatures, dimensions and size; it accepts no remote URLs or SVG. Owner-side decoded previews are bounded to the screen repository lifetime and scoped to the website; originals are never sent to the public catalogue.

### Schema, access and capacity

`booking_website_images` stores a bounded image blob plus its UUID, website/organisation, `hero` or `space` kind, optional business/resource and display position. Composite foreign keys enforce organisation ownership. Partial unique indexes enforce one hero and four numbered positions per resource. Site-row locking enforces the overall maximum of 40 photos and optimistic version checks across concurrent uploads/removals. Replacing/removing a photo deletes the old blob atomically and revokes existing preview tokens. Audit events record image IDs, never image bytes.

This reuses the private PostgreSQL asset approach already used for organisation logos; no public Storage bucket or service-role key is added. Assets count toward database size and backups. Monitor asset bytes, image-endpoint latency and database storage. The bounded photo repository/API can later move blobs to private object storage without changing the owner or guest flow. Public image reads are deliberately `no-store` so unpublishing/disabling a service immediately blocks new reads; previously downloaded files cannot be recalled.

Owner writes require the same verified identity, membership and owner role as website settings. Public reads resolve the site publication/preview capability, enabled active business and existing normal resource on every request. The catalogue exposes only image IDs. Private, disabled, deleted or other-organisation image IDs cannot be fetched through another site. Public photo reads share the existing site read quota; no guest upload endpoint exists.

### API additions

| Method | Path | Access/result |
| --- | --- | --- |
| POST | `/v1/booking-website/images` | Owner; upload/replace, returns updated settings/version |
| GET | `/v1/booking-website/images/:id` | Owner; image bytes, private/no-store |
| POST | `/v1/booking-website/images/:id/remove` | Owner; `{version}`, returns updated settings/version |
| GET | `/public/v1/sites/:slug/images/:id?preview=...` | Publication-aware public/preview image bytes |

Hero upload body: `{version, kind:"hero", content_type:"image/jpeg", base64:"<encoded JPEG>"}`.
Space upload additionally uses `kind:"space", business_id:"<uuid>", resource_id:"<configured resource id>"`.
Settings now include `images:[{id,kind,business_id,resource_id,position}]` and `businesses[].resources:[{id,name}]`. The public catalogue adds `hero_image` (nullable UUID) and `businesses[].resources[].images` (ordered image UUIDs). Stale versions return 409; inaccessible photos return 404; invalid dimensions/types and full galleries return validation errors. The existing error envelope remains unchanged.

### Prerequisites and exact migration steps

1. Save the current API/frontend/app release references and verify a current database backup. Keep photo uploads unavailable until the schema and API are ready.
2. Confirm the base website migration is already recorded and the restricted API role exists:

```sql
SELECT name FROM booking_app.schema_migrations
WHERE name IN ('20261022034634_public_booking_websites.sql',
               '20261022045215_booking_website_images.sql');
SELECT to_regclass('booking_app.booking_websites');
SELECT rolname FROM pg_roles WHERE rolname='booking_api';
```

3. In the correct Supabase project's SQL editor, run the **complete contents** of `supabase/migrations/20261022045215_booking_website_images.sql` once. It runs in a transaction with a 10-second lock timeout. If either migration is missing, apply the base first. Do not run a broad migration push that could include unrelated pending files.
4. Validate the schema and privileges before deploying the rebuilt Edge API, Next application and Flutter app:

```sql
SELECT name FROM booking_app.schema_migrations
WHERE name='20261022045215_booking_website_images.sql';
SELECT relrowsecurity FROM pg_class
WHERE oid='booking_app.booking_website_images'::regclass;
SELECT indexname FROM pg_indexes
WHERE schemaname='booking_app' AND tablename='booking_website_images';
SELECT has_table_privilege('anon','booking_app.booking_website_images','SELECT') AS anon_read,
       has_table_privilege('authenticated','booking_app.booking_website_images','INSERT') AS guest_write,
       has_table_privilege('booking_api','booking_app.booking_website_images','INSERT') AS server_write;
SELECT kind, count(*), COALESCE(sum(octet_length(data)),0) AS bytes
FROM booking_app.booking_website_images GROUP BY kind;
```

Expect RLS=true, both public privilege checks=false and server_write=true. An empty image table is valid.
5. In a development organisation, upload a hero and two court photos. Verify homepage → service → gallery → normal booking, resource switching, removal, direct service links, draft previews and unpublishing. Confirm another account cannot read or mutate the assets through owner endpoints.

### Recovery

A failed migration rolls back as one transaction. Resolve the reported lock/prerequisite issue, check the migration ledger and table existence, then rerun the complete file only if it was not applied. If the table or ledger is only partially present, inspect and reconcile before retrying.

For a code rollback, restore the previous app/API/Next releases and keep the additive image table and stored assets. Booking records are unaffected. Do not drop the table or restore a whole old database over newer bookings. To remove an unwanted image, use its owning organisation's settings; to make a site private, unpublish it through existing website settings. Photo recovery after permanent removal requires the database backup and a deliberate asset-only restore; it does not require replacing booking/finance tables.


### Homepage/photo verification on 22 October 2026

- Affected backend regression suite: **90 passed**, including all 17 website/photo/Edge tests, existing bookings and workspace permissions. TypeScript build, Edge type-check and regenerated credential-free Edge bundle passed.
- Affected Flutter tests: **21 passed**, including nine website/settings/encoding tests and existing routing/business tests. Targeted analysis passed.
- Next production build and type-check passed with both homepage and dedicated booking routes. Browser checks verified the service cards, pool/court routes, start/finish UI and navigation back to the homepage against the isolated fixture API.
- Screenshots: `screenshots/public-booking-homepage.png` and `screenshots/public-booking-services.png` show the homepage fallback and service cards before any venue photos are uploaded.
- No live migration or hosted deployment was performed. The local homepage remains fictional test data.


## One grid for start and end selection

The public website now matches the app's **New Booking** behaviour: choose a start tile, then an end tile in the same persistent grid. Both selected boundaries remain visible with the interval highlighted. Start, End and Duration appear above the grid. Tap End again to clear only the end; tap Start again to clear the range. After completing a range, another available tile starts a new one.

The client keeps the original start list and merges valid finish boundaries by date and time. A time that is booked as a start may still be a valid end, and next-day midnight remains distinct from midnight on the selected date. Prevalidated `end_options` avoid replacing or reloading the grid when choosing a start. If those options are absent, an abortable end-availability request fills the same grid. Minimum durations, blocks, capacity and notice rules still come from the existing booking API; selecting an end requests an authoritative quote. Fixed hall sessions retain their single-click selection.

Checked locally: **8 grid regression tests passed**, Next type-check/production build passed, and browser checks confirmed a one-hour court quote, persistent start/end highlights, interval highlights and clearing either boundary. The local preview stays running with isolated fixture data. Screenshot: `screenshots/public-booking-shared-slot-grid.png`.

To run the standalone grid tests with the verified Node 24 runtime:

```sh
cd "/Users/albinosiby/Tatos Dev/booking/booking-website"
npm test
npm run typecheck
```

This update changes only the website UI/state. No database migration or backend deployment is needed for the grid update on an already configured booking website.


## Review and confirmation screens

The review step and final confirmation use a shared booking receipt: venue/space, local date and start/end time, duration/timezone, customer name/phone, pool party size where applicable, venue address and a separate amount/pay-at-venue panel. These stages use one full-width card rather than duplicating the booking details in a second sidebar. The layout stacks on small screens, includes reduced-motion support, and keeps configured venue instructions and cancellation guidance available.

The review step preserves the original confirmation guards, preview restrictions and locked retry behaviour. Editing returns to the retained customer details. The final screen adds a success heading, confirmed status, booking reference, user-triggered clipboard copy with success/error feedback, browser printing and another-booking/contact links. Nothing sends messages or collects an online payment. Zero-value bookings show that no payment is due. The print layout excludes navigation and action controls.

Verified locally with fictional customer details and an in-memory court reservation: retained edits, the one-hour ₹400 review, successful confirmation and reference-copy feedback. Next production build/type-check and all eight existing frontend grid regression tests passed. Screenshots: `screenshots/public-booking-review.png` and `screenshots/public-booking-confirmation-redesign.png`. This presentation update requires no database migration or API change; the local development servers remain running.

## Customer details screen

The customer details step now matches the review/confirmation design, with booking progress, a compact contact form and an integrated navy-headed recap showing the chosen space, local date/time, duration, timezone, pool party size where applicable, location and quoted amount. The review button follows the fields directly; venue instructions, cancellation guidance and contact links appear below the card. The layout stacks on narrow screens and uses labelled, autofill-enabled fields with visible keyboard focus.

The existing client/server validation and booking state remain in place. Details are retained when returning from review or changing the selected time. Entering details and reviewing do not submit a reservation. Browser checks against isolated fixture data verified required fields, phone digit validation, error recovery, review navigation and retained time/customer details. The production build/type-check and eight grid regression tests passed. Screenshot: `screenshots/public-booking-customer-details.png`. No database migration or API change is required.

## Basketball, tennis and hall illustrations

The homepage service cards and booking space selectors now share dedicated vector illustrations for basketball, tennis and halls. Basketball has a wood floor, hoops, painted keys, free-throw circles, three-point arcs and a centre circle. Tennis has a blue playing surface, green surround, singles/doubles lines, service boxes and a centre net. The hall shows a stage, tables/chairs, a central aisle and an entrance. These are decorative illustrations, not configured floor plans, seat maps or representations of bookable capacity.

Labels sit outside the playing/room area, with responsive SVG proportions and the existing selected-card treatment. The booking API, prices, availability and capacity rules are unchanged. Browser checks verified all three homepage cards, their dedicated booking pages and selecting another court/hall; the production build and TypeScript checks passed. Screenshot: `screenshots/public-booking-venue-layouts.png`. No migration is required.

## Subdomains and Design website — deployment update

Every organisation's website is served from its own subdomain, `https://<slug>.bookingos.online`. The slug is the address the owner chooses in **Design website → Website address**; it must be 3–63 lowercase letters, numbers or single hyphens, unique, and not reserved (`www`, `api`, `app`, `admin`, `book`, `mail`, …). The owner can rename it before or after publication. Saving a new name changes the public URL immediately without changing publication status, bookings or website design; the old address is released and has no redirect.

How a request is resolved (`booking-website/proxy.ts`, `lib/site-host.ts`):

| Request | Result |
| --- | --- |
| `eden.bookingos.online/` | Rewritten internally to `/eden` (homepage) |
| `eden.bookingos.online/book/<business-id>` | Rewritten to `/eden/book/<business-id>` |
| `eden.bookingos.online/eden/...` | 308 to the clean subdomain path |
| `bookingos.online/eden/...` or `www.` | 308 to `https://eden.bookingos.online/...` (keeps old links working) |
| `bookingos.online/` | Generic landing page |
| `/login`, `/sign-in`, `/register`, `/signup` on the main domain or any website | 307 to the owner app (`https://app.bookingos.online/sign-in` or `/register`; override with `BOOKING_APP_URL`) |
| Any other host (IP, hosting preview URL) | Unchanged `/<slug>` path routing |

`/api/sites/<slug>/...` is never rewritten. The proxy sets an internal `x-booking-site-host` header to render subdomain-relative links and strips any client-supplied copy on path-routed hosts. The host is read from `X-Forwarded-Host` (first value) or `Host`, so the hosting layer must pass the visitor's host through.

For the shared Railway service, deploy the host-aware gateway and set `BOOKING_ROUTING_MODE=auto` (or `subdomain`) with `BOOKING_SITE_DOMAIN=bookingos.online`. The gateway sends tenant `/` requests to this booking server and keeps the marketing homepage on the apex, `www` and Railway host. An old explicit `BOOKING_ROUTING_MODE=path` disables tenant homepages even when DNS is connected. See [Railway custom-domain setup and verification](railway-deployment.md#connecting-a-domain-later); this routing change requires no migration.

### What the owner configures

- **Address:** a fixed `https://` prefix, editable website name and fixed `.bookingos.online` suffix (the configured domain is used). The fixed domain wraps below the input on narrow screens with enlarged text. **Save** updates only the address while preserving other unsaved design changes, and the saved URL appears in the summary above **Website address**. Validation and address conflicts appear beside the name; failed saves keep the existing saved link. The address remains editable after publication.
- **Brand & homepage:** website logo (square, header of every page; falls back to the organisation profile logo when that switch is on), website title, hero heading (empty keeps the default), description, contact phone, hero image.
- **Spaces on your website:** per service — show on website, homepage card photo (falls back to the first space photo) and card description (falls back to the standard text). Per space — show/hide (hidden spaces disappear from the catalog, cannot be quoted or booked, and their photos are not served), up to 4 booking page photos, minimum notice, advance window and visitor rules. Empty rule fields use the website defaults. **Copy these rules to all spaces** copies notice, window and rules (not visibility) to every space; save to apply.
- **Social media:** Instagram, Facebook, X, YouTube, LinkedIn, WhatsApp. Only full `https://` links are accepted; the app adds `https://` to pasted addresses such as `instagram.com/venue`.
- **Default booking rules & policies:** the defaults every space inherits, venue instructions and cancellation policy.

Photo selections and removals stay in the page draft until **Save changes** (or an explicit publication action); pending text edits are preserved and do not block photo selection. Per-space rules are enforced by the API for availability, quotes and confirmations, not only in the browser. Older app versions that do not send the new fields keep the saved design values.

### Hosting prerequisites (one-time)

1. **DNS** at the `bookingos.online` registrar/DNS provider: point both the apex `bookingos.online` and the wildcard `*.bookingos.online` at the Next.js website host (for example the records your host gives for a custom domain). `www` is covered by the wildcard.
2. **TLS:** issue a certificate covering `bookingos.online` and `*.bookingos.online`. Wildcard certificates need a DNS-01 challenge; managed hosts such as Vercel do this automatically when the domain uses their nameservers. With your own reverse proxy (Caddy, nginx + certbot, Cloudflare), enable a wildcard certificate and forward the original `Host`/`X-Forwarded-Host` to `next start`.
3. **Website environment:** `BOOKING_SITE_DOMAIN=bookingos.online` (the default when unset) plus the existing `BOOKING_API_BASE_URL` and `BOOKING_API_PUBLISHABLE_KEY`.
4. **API/Edge secret:** set `BOOKING_WEBSITE_DOMAIN=bookingos.online`. Settings, preview links and publishing then use `https://<slug>.bookingos.online`. `BOOKING_WEBSITE_URL` is now only a path-based fallback when the domain is not set.

Check DNS before announcing addresses:

```sh
dig +short eden-sports.bookingos.online
curl -sI https://eden-sports.bookingos.online | head -1
curl -sI https://bookingos.online/eden-sports | grep -i '^location'
```

The first should return your host's address, the second `HTTP/2 200` (an unknown or unpublished slug shows the “isn’t available yet” page), the third `location: https://eden-sports.bookingos.online/`.

### Database migration — user applies

**Not applied by this implementation.** Cloud handoff file:

`supabase/migrations/20261022140000_booking_website_design.sql`

(`backend/migrations/20261022140000_booking_website_design.sql` is the equivalent DDL for isolated/local databases.) It adds `hero_heading` and `social_links` to `booking_websites`, `card_description` to `booking_website_businesses`, a new server-only `booking_website_spaces` table (per-space visibility and rule overrides; spaces without a row stay visible with the defaults, so existing websites are unchanged), and widens `booking_website_images.kind` to `hero`, `logo`, `card` and `space` with one logo per website and one card photo per service. No existing rows are rewritten.

Prerequisites:

1. Take a current database backup and keep the currently deployed `booking-api` and website builds. Confirm how to restore the backup.
2. `20261022034634_public_booking_websites.sql` and `20261022045215_booking_website_images.sql` must already be applied. Run as an administrator capable of DDL and grants.
3. Confirm the state before running:

```sql
SELECT name FROM booking_app.schema_migrations
WHERE name IN ('20261022045215_booking_website_images.sql','20261022140000_booking_website_design.sql');
SELECT to_regclass('booking_app.booking_website_spaces');
SELECT conname FROM pg_constraint
WHERE conrelid='booking_app.booking_website_images'::regclass AND contype='c' ORDER BY conname;
SELECT kind,count(*) FROM booking_app.booking_website_images GROUP BY kind;
SELECT slug FROM booking_app.booking_websites
WHERE length(slug)>63 OR slug IN ('www','app','api','admin','book','booking','bookingos','mail','email','support','help','status','docs','blog','static','assets','cdn','dashboard');
```

Expect only the images migration in the first result, `null` for the new table, `booking_website_images_kind_check` and `booking_website_images_check` among the constraint names (the migration drops exactly these two and fails safely if either is missing), only `hero`/`space` kinds, and no slugs in the last query. A slug listed there cannot be served as a subdomain: if that site is unpublished, change its address in Design website after deploying; if it was already published, contact support/rename deliberately before switching to subdomains. If any check differs, stop and investigate.

4. Open the reviewed file in the Supabase SQL editor and run its entire contents once (single transaction, 10-second lock timeout), or:

```sh
psql "$BOOKING_MIGRATION_DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f "/Users/albinosiby/Tatos Dev/booking/supabase/migrations/20261022140000_booking_website_design.sql"
```

5. Validate before deploying the new API:

```sql
SELECT name,applied_at FROM booking_app.schema_migrations
WHERE name='20261022140000_booking_website_design.sql';
SELECT table_name,column_name FROM information_schema.columns
WHERE table_schema='booking_app'
AND (table_name,column_name) IN (('booking_websites','hero_heading'),('booking_websites','social_links'),('booking_website_businesses','card_description'));
SELECT tablename,rowsecurity FROM pg_tables
WHERE schemaname='booking_app' AND tablename='booking_website_spaces';
SELECT grantee,privilege_type FROM information_schema.role_table_grants
WHERE table_schema='booking_app' AND table_name='booking_website_spaces'
AND grantee IN ('anon','authenticated','booking_api') ORDER BY grantee,privilege_type;
SELECT conname,pg_get_constraintdef(oid) FROM pg_constraint
WHERE conrelid='booking_app.booking_website_images'::regclass
AND conname IN ('booking_website_images_kind_check','booking_website_images_scope_check');
SELECT indexname FROM pg_indexes
WHERE schemaname='booking_app' AND indexname IN ('website_logo_image_idx','website_card_image_idx');
SELECT kind,count(*) FROM booking_app.booking_website_images GROUP BY kind;
```

Expect the migration entry, all three columns, RLS enabled on `booking_website_spaces`, only `booking_api` with `DELETE`, `INSERT`, `SELECT`, both constraints (kind lists the four kinds), both indexes, and the same image counts as before.

### Deployment order

1. User applies and validates the migration above.
2. Configure DNS, the wildcard certificate and `BOOKING_SITE_DOMAIN` on the website host.
3. Set `BOOKING_WEBSITE_DOMAIN=bookingos.online` on the API/Edge function, then deploy the regenerated `supabase/functions/booking-api/index.ts` (`npm run build && npm run edge:check && npm run edge:build` in `backend/`).
4. Deploy the website (`npm run build` in `booking-website/`) and the Flutter app.
5. In Profile → Design website, set the subdomain, logo, hero, spaces, photos, rules and links; save, preview, then publish. Open `https://<slug>.bookingos.online` to confirm.

Deploying the API before the migration fails safely on website reads/saves (missing columns); keep the order above.

### Recovery

- A failed migration rolls back as a unit; confirm its history row is absent, fix the cause and rerun the full file. Never mark it applied manually.
- Code rollback: redeploy the previous API/website/app. The schema change is additive and the previous API keeps working with it (it only uses `hero`/`space` photos). Do not drop the new table or columns; logo/card photos and space rules simply stop being used until redeployed.
- If subdomains misbehave, unset `BOOKING_WEBSITE_DOMAIN` on the API to fall back to `BOOKING_WEBSITE_URL/<slug>` links, and serve the website on a host outside `BOOKING_SITE_DOMAIN` so path routing applies.
- To hide one space quickly without a deploy, switch it off in Design website. Emergency stop for a whole site is unchanged (Pause bookings / Unpublish).

### Local testing

```sh
cd "/Users/albinosiby/Tatos Dev/booking/backend"
WEBSITE_PREVIEW_PORT=3101 node --import tsx scripts/website-preview.ts
```

```sh
cd "/Users/albinosiby/Tatos Dev/booking/booking-website"
BOOKING_API_BASE_URL=http://127.0.0.1:3101 BOOKING_SITE_DOMAIN=localhost npm run dev
```

Open `http://eden-sports.localhost:3000` (browsers resolve `*.localhost` to this machine); `http://localhost:3000/eden-sports` redirects there. Fixture data only.

Verification:

```sh
cd "/Users/albinosiby/Tatos Dev/booking/backend"
node --import tsx --test test/website.test.ts test/website-images.test.ts test/website-design.test.ts test/website-edge.test.ts test/bookings.test.ts test/edge.test.ts
cd ../booking-website && npm test && npm run typecheck && npm run build
cd .. && flutter test test/booking_website_test.dart
```

## Website address editing update

This update removes the application/API lock on renaming previously published websites. It uses the existing version-checked `PUT /v1/booking-website` contract, owner authorization, reserved-name validation, DNS-label limit and unique slug constraint. No database migration or DNS change is required when wildcard hosting is already configured.

Deploy the API change together with the updated Flutter app. Validate locally from `backend/` using `npm run build`, `npm run edge:check` and `npx tsx --test test/website-design.test.ts test/website.test.ts`; the tests use isolated in-memory databases. Build the hosted API with `npm run edge:build`, then deploy it using the existing hosting procedure. No live database schema, website address or production deployment was changed while implementing this feature.

After deployment, open **Design website**, change only the website name and press its **Save** button. Confirm the summary above **Website address** shows the server-returned URL, the new URL opens the published website, and publication status and design settings are preserved. A taken or reserved name must fail without changing the saved URL. Saving an address with other draft changes must leave those changes unsaved until **Save changes** is pressed.

The old address no longer opens the website and can be claimed by another owner. Update QR codes, bookmarks and shared links after renaming. Existing bookings remain in the owner/staff app; visitors with uncertain confirmations at the old address should contact the venue instead of starting another booking. To undo a rename, save the previous name again if it is still available. Rolling back the app/API does not automatically undo saved address changes.

## Responsive Design website editor

The Flutter Design website screen has five groups: Website address, Brand & homepage, Services & spaces, Social media, and Booking policies. Wide windows show section navigation beside an independently scrolling editor. Phones use expandable cards. All main-section inputs remain mounted when collapsed so edits and validation are retained; saving reveals and scrolls to the first invalid field. A persistent Save changes / Preview bar reports unsaved changes. Photo slots show upload placeholders and photo-limit feedback.

Publication, pause/resume and sharing controls remain with the website summary. Website address retains its separate Save action, which does not persist pending photos or other design edits. Photo operations stay local until the main Save changes action, and remain available alongside unsaved text edits. Preview remains disabled until changes are saved. Existing owner authorization, repository/Cubit state, optimistic version checks, API contracts and database schema are unchanged. Rebuild Flutter web with `/app/` as the base path for Railway; rebuild the native app through the normal release process to ship the same layouts.

Responsive checks: `flutter test --no-pub test/agent_calls_test.dart test/booking_website_test.dart test/web_layout_test.dart test/booking_agenda_test.dart`. Coverage includes narrow screens with enlarged text, independent desktop editor navigation, collapsed-field validation, retained edits, address conflict handling, publication order, service setup states and call-detail controls.

The address editor always shows the fixed URL parts, including when the API returns `domain: null` for temporary Railway path hosting. The summary uses the saved name for the BookingOS address and labels the current working path-based link separately until custom hosting is connected. Selecting Website address in the desktop sidebar returns to the summary above the address input. Regression coverage includes null-domain responses on narrow and wide layouts, saving and sidebar navigation. This display fix does not configure DNS or change the API’s hosting mode.

Space expansion panels have their own PageStorage keys, scoped by business and space. This prevents expansion booleans from colliding with the editor’s numeric scroll offset when a service is enabled after scrolling or the form is rebuilt after saving. That collision previously produced a gray Flutter error block in release builds. The desktop sidebar now tracks the visible section during manual scrolling as well as sidebar navigation. Regression tests cover enabling after scrolling, editing and saving space rules, preserving panel state and updating the sidebar highlight on mobile/desktop layouts. This fix only requires rebuilding/redeploying the Flutter app; API and database changes are not required.

### Manual photo saving

Logo, hero, service-card and space-photo selections are prepared locally as bounded JPEGs. Pending selections count toward the existing 40-photo website and four-photo space limits. Replacing a selection again keeps only its latest version; removing a new selection cancels its pending upload. Leaving or reloading the page before saving discards these page-local selections.

The main save validates the form, saves changed settings, removes photos that need deletion, then uploads pending selections using the latest returned version for each request. Single-photo replacements use the existing atomic replacement endpoint. If a later request fails, acknowledged changes remain saved and the remaining edits stay in the editor; a retry does not repeat acknowledged uploads. For an uncertain network result, reload settings before retrying. Preview/share remain disabled while changes are pending. Workspace changes clear the draft and stop further requests from the old editor.

This change reuses the existing owner-authorized API and requires a Flutter web/native rebuild only. It adds no API contract or database migration. Regression tests cover all photo kinds, replacement, removal, address-only saves, gallery limits, partial failures, workspace changes and the mobile/desktop Save button flow.
