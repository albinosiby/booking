# Sarvam voice agent

Callers phone your Sarvam voice agent to book, find, reschedule or cancel court, turf, pool or hall bookings. The agent calls the booking API through Sarvam **API tools**. The owner connects Sarvam and controls the agent from **Profile → Sarvam voice agent**, and reads call logs, transcripts and recordings in the app.

No live migration, secret change or deployment was performed. Follow the steps below yourself.

## How it works

- **The voice agent is a restricted staff member.** Saving the settings creates an internal membership (`user_id` `sarvam:<organization id>`) with only `view_bookings` and `manage_bookings`, assigned to the businesses you tick. It never appears in Team & access. Turning the agent off deactivates it immediately.
- **The same booking rules as staff.** Every tool call goes through the existing booking service, so prices, quotes, slot blocks, buffers, inventory conflicts, opening hours and past-time checks apply unchanged.
- **Bookings are confirmed instantly and unpaid.** The note says "Booked by phone through the Sarvam voice agent (call …)", and history shows the voice agent as the actor. Payment is collected at the venue as usual.
- **Callers can only change their own bookings.** Reschedule and cancel only find upcoming confirmed bookings whose phone matches the calling number (last 10 digits). Admissions/coaching visits are excluded. A call without a caller number cannot change bookings.
- **Retries are safe.** When Sarvam retries the same tool call in the same call (same Interaction ID and inputs), the earlier result is returned and nothing is booked twice.
- **Keys are stored safely.**
  - **Tool key:** Sarvam sends it as `X-API-Key`. Only its SHA-256 hash is stored. It is shown once and can be replaced.
  - **Sarvam API key:** used to read call logs. It is encrypted (AES-256-GCM) with the server-only `BOOKING_SECRETS_KEY` and never returned to the app; the app sees only its last four characters.
- **Owner-only.** Only the owner can open the settings and call logs, in the app or through the API.

## 1. Migration — apply this yourself

1. Back up the database. Use the Supabase **booking** project, reference `scwwkaywewecspsrskft`.
2. **Prerequisites:**
   - Schema `booking_app` and role `booking_api` exist.
   - The `organizations`, `memberships`, `staff_assignments`, `businesses` and `schema_migrations` tables exist.
   - `memberships` has its existing unique `(id, organization_id)` constraint.
   - Earlier project migrations (admissions, slot blocks) are applied; the voice tools use `bookings.admission_id`.
   - Don't apply unrelated pending migrations blindly.
3. In Supabase SQL Editor, run the whole file [20261022100000_sarvam_voice_agent.sql](../supabase/migrations/20261022100000_sarvam_voice_agent.sql). It includes BEGIN/COMMIT, restricted grants and the `schema_migrations` registration. Apply it once. Don't also run the `backend/migrations` copy or `supabase db push`.
4. Verify with read-only SQL:

```sql
SELECT to_regclass('booking_app.sarvam_integrations') AS new_table;
SELECT name FROM booking_app.schema_migrations
WHERE name='20261022100000_sarvam_voice_agent.sql';
SELECT grantee, privilege_type FROM information_schema.role_table_grants
WHERE table_schema='booking_app' AND table_name='sarvam_integrations' ORDER BY 1,2;
SELECT grantee, privilege_type FROM information_schema.role_table_grants
WHERE table_schema='booking_app' AND table_name IN ('memberships','staff_assignments')
  AND grantee='booking_api' ORDER BY 1,2;
SELECT count(*) AS integrations FROM booking_app.sarvam_integrations;
```

Expected results:
- The table exists and the migration name appears once.
- `booking_api` has SELECT, INSERT and UPDATE on `sarvam_integrations`, and anon, authenticated and PUBLIC have no access.
- `booking_api` already has SELECT, INSERT, UPDATE and DELETE on `memberships`/`staff_assignments`. Staff invitations need them too, so if any are missing, stop and investigate before deploying.
- The new table starts empty. Existing data is unchanged.

**If the SQL fails:** run `ROLLBACK;`, fix the prerequisite, and retry. Don't record the migration as applied by hand.

**To turn the feature off later**, keep the data and switch it off:

```sql
BEGIN;
UPDATE booking_app.sarvam_integrations SET enabled=false, tool_key_hash=NULL, tool_key_prefix='';
UPDATE booking_app.memberships SET active=false WHERE user_id LIKE 'sarvam:%';
COMMIT;
```

Bookings already made by the agent stay valid. Don't drop the table while the deployed API still includes the Sarvam routes.

## 2. Server secret — set it yourself

Generate a 32-byte key and store it only as an Edge Function secret:

```bash
openssl rand -base64 32
```

```bash
npx supabase secrets set BOOKING_SECRETS_KEY='<paste the value>' --project-ref scwwkaywewecspsrskft
```

Keep a copy in your password manager.
- **If it's lost or changed**, the saved Sarvam API key can't be decrypted: call logs show an error until you paste the Sarvam key again. Phone booking keeps working because tool keys are hashed, not encrypted.
- **Without the secret**, saving a Sarvam API key fails with "Server secret storage is not configured".

## 3. Deploy the API — do this yourself

Run in order, stopping on any failure:

```bash
cd "/Users/albinosiby/Tatos Dev/booking" && npm --prefix backend test && npm --prefix backend run edge:check && npm --prefix backend run edge:build
```

```bash
npx supabase functions deploy booking-api --project-ref scwwkaywewecspsrskft --use-api --no-verify-jwt
```

```bash
curl -sS "https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/health"
```

The expected health revision is `2026-10-22-sarvam-voice-agent`. Keep `verify_jwt = false`. Sarvam authenticates with the tool key, and app routes still verify Supabase user tokens themselves.

Check that a tool call without a key is refused (expect HTTP 401):

```bash
curl -sS -X POST "https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/voice/v1/catalog"
```

Then rebuild the app from this source; no APK was built.

## 4. Connect in the app

Profile → **Sarvam voice agent** (owner only):

1. **Connect Sarvam:** paste the Sarvam API key, Organization ID, Workspace ID and App ID. For the Edens Sport app these are the IDs in the Sarvam analytics guide. **Save settings**, then **Test connection**.
2. **Sarvam tool setup:** tap **Generate**, copy the key and keep it for step 5. It is shown once. **Replace** invalidates the old key immediately.
3. **Voice booking:** tick the businesses the agent may book and turn on **Accept phone bookings**. **Save settings**.
4. **View call logs** lists the day's calls with Sarvam's summary. Tap one for details and transcript; **Save recording** downloads the WAV.

## 5. Configure the Sarvam agent

In Sarvam, add one **API tool** per endpoint. Copy each URL from the app; they share the base `https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/voice/v1`.

Common settings for every tool:
- **Method:** `POST`
- **Auth:** `api_key`, header name `X-API-Key`, value = the tool key, stored as a Sarvam secret
- **Header:** `Content-Type: application/json`
- **Max wait:** 15 s
- **Response template:** `{{message}}`
- **If it fails:** "Sorry, I couldn't reach the booking system. Please call the venue."
- **Body:** add `caller_phone` = call-context **User Identifier** and `interaction_id` = call-context **Interaction ID** wherever listed below. Fill the other fields from agent variables the agent collects.

| Tool name | Path | Body fields |
|---|---|---|
| `list_spaces` (lifecycle **on_start**, save `message` into variable `spaces`) | `/catalog` | none |
| `check_availability` | `/availability` | `space`, `activity`, `business`, `date`, `duration_minutes`, `people`, `preferred_time` |
| `book_slot` | `/bookings` | `space`, `activity`, `business`, `date`, `time`, `duration_minutes`, `people`, `customer_name`, `contact_phone`, `expected_total`, `caller_phone`, `interaction_id` |
| `my_bookings` | `/my-bookings` | `caller_phone` |
| `reschedule_booking` | `/reschedule` | `reference`, `date`, `time`, `duration_minutes`, `space`, `caller_phone`, `interaction_id` |
| `cancel_booking` | `/cancel` | `reference`, `reason`, `caller_phone`, `interaction_id` |

Field formats:
- `date` is `YYYY-MM-DD`, `today` or `tomorrow`.
- `time` is `19:00` or `7 pm`.
- `space`, `activity` and `business` are names as listed by `/catalog`. Partial names work when they are unambiguous. `business` and `activity` can be left empty when there is only one match.
- `duration_minutes` defaults to the option's default.
- `expected_total` is in rupees, as quoted to the caller. If the price changed, booking is refused with the new price so the agent can re-confirm.
- `contact_phone` overrides the caller ID, for example when booking for someone else.
- `reference` is the booking reference, such as `BK-1A2B3C4D5E6F`.

Every response has `ok` and a spoken `message`. Refusals return HTTP 200 with `ok:false` and a reason, so the agent can relay it: slot taken, ambiguous space, not the caller's booking, missing details. Only a bad or disabled key (401/403) and server faults are HTTP errors.

Suggested agent instructions:

> You take bookings for {organization}. Bookable spaces: {{spaces}}. Always check availability before offering a time. Read the price to the caller and get a clear yes before booking. Ask for the caller's name. After booking, read the reference slowly. To change or cancel, ask for the booking reference (or use my_bookings to find it), confirm the details, and get a clear yes before cancelling. Never invent availability or prices; only say what the tools return.

## 6. Test before going live

Use a future day with no real bookings and the owner's own phone.

1. Ask for availability, then book a slot. In the app, check that the booking appears with the voice-agent note and is unpaid.
2. Call again from the same phone: list your bookings, move it to another time, then cancel it.
3. From a different phone, try cancelling that reference; it must be refused.
4. Turn **Accept phone bookings** off and make sure the agent can no longer book.
5. Open Call logs and confirm the calls, transcripts and recording download.

## API (owner app)

All routes are under `/v1/sarvam`, owner only:

| Method | Path | Purpose |
|---|---|---|
| GET | `/settings` | Connection state, IDs, assigned businesses, tool key prefix and tool base URL. The secret key itself is never returned. |
| PUT | `/settings` | `{version, enabled, business_ids, sarvam_org_id, workspace_id, app_id, api_key?}`. Omitting `api_key` keeps it; `null` removes it. A stale `version` returns 409. |
| POST | `/tool-key` | Issues a new tool key (returned once) and invalidates the old one |
| POST | `/test` | Reads the last 24 hours of Sarvam interactions |
| GET | `/calls?start&end` | Proxied interactions (ISO times, at most 31 days) |
| GET | `/transcript?interaction_id=` | Transcript messages |
| GET | `/recording?interaction_id=` | WAV audio, at most 25 MB |

## Limits

- **Call log pagination:** the call list shows Sarvam's first page; the app says when more calls exist. Sarvam's paging beyond the first page wasn't verified (see the analytics guide).
- **Recordings** are downloaded and saved rather than played in the app; no audio player package was added.
- **Caller identity** relies on the caller ID Sarvam reports. Treat a spoofed number as possible, the same as phone bookings taken by staff.
- **Pickers:** the agent picks a space by name, and a booking duration must be one the option allows.
