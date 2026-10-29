# Turn businesses off and on

In Profile → Businesses, open a configured business card's three-dot menu.
Choose **Turn off business**, review the confirmation, and choose **Turn off**.
The card shows **Off**. The menu then offers **Turn on business**. Confirmation
re-enables the saved configuration after the normal activation validation.
Draft businesses continue through setup rather than bypassing configuration.

Only an active owner can change this. Turning off keeps business/resource IDs,
configuration, staff assignments, bookings, payments and attendance history.
New bookings, availability/quotes, public website bookings and new admissions
are rejected by current server status, including a confirmation using an old quote.
Existing bookings remain visible, existing balances can be collected and existing
admission attendance can still be marked. New reschedules/replacement sessions
remain subject to the normal ready-for-booking checks. Turning off does not cancel
any booking, refund money or alter plan expiry. No automatic message is sent.

The business row is locked in the status transaction, and a required version
prevents stale confirmations overwriting newer changes. The UI prevents duplicate
submissions and requires fresh confirmation if the business changes. Errors retain
the existing list. Shared transport invalidates cached reads after the write.

## API

`PATCH /v1/businesses/:id/booking-status`

```json
{"enabled": false, "version": 3}
```

Response: `{"id":"<business UUID>"}`. Use `enabled: true` with the current version
only for an off business. Validation is strict; owner and tenant checks apply.
A stale version/status returns 409. Existing activation still validates full setup
when turning on. No migration is required; `paused` already exists in the schema.

## Deploy (user-owned)

Run the updated Flutter source/client to see the controls. No APK was built.
Build and deploy the API before using them:

```sh
cd "/Users/albinosiby/Tatos Dev/booking"
npm --prefix backend run build
npm --prefix backend run edge:check
npm --prefix backend run edge:build
npx supabase functions deploy booking-api --project-ref scwwkaywewecspsrskft --use-api --no-verify-jwt
curl -i "https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/health"
```

Expected revision: `2026-10-29-business-booking-status`. The JWT gateway setting
preserves the existing configuration: the function itself verifies Auth and
organization permissions. Earlier unrelated pending migrations are not replaced
by this feature; follow their own instructions if still outstanding.

## Verify and recovery

Use a configured test business. Cancel once and verify no change. Turn it off,
confirm it disappears from new-booking/admission/public choices, confirm an old
quote cannot create a booking, and verify saved configuration/resources remain.
Open an existing booking and collect a pending balance; mark existing admission
attendance. Turn on again and verify choices return. Staff/cross-organization
attempts and stale versions must be rejected. Public tabs already open may display
old choices until refreshed, but writes always check current server status.

Recovery is **Turn on business**, not database restoration. If saved configuration
fails validation, correct it in settings and activate it through configuration.
If rolling back application/API code, first restore the desired business status
using the updated client. Old clients have no control to turn an off business on.
