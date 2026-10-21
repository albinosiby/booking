# Swimming plan visit duration

New booking → Swimming plan and standalone New admission use a minus/plus counter. It starts at the selected pool's configured default booking duration, treated as the minimum. Each tap changes the duration by 30 minutes. For a 60-minute minimum, valid choices are 60, 90, 120, 150, etc., up to one day. Below-minimum choices and other increments are rejected in both app review and API validation. Selecting another pool/plan resets the duration to its configured value. Coaching keeps its configured class duration, without a counter. Plan package price and attendance-day allowance are unchanged.

Flexible attendance saves the selected duration; actual attendance still checks pool/plan opening hours and inventory. Fixed weekly schedules reserve sessions for that duration and still check expiry, opening hours and conflicts. Changing pool settings cannot invalidate durations of active swimming admissions.

## Deployment — user runs these steps

No new database migration is needed. Existing admissions and slot-block migrations from previous features must already be applied before deploying the combined API bundle. No live database changes or deployment were performed.

```sh
cd "/Users/albinosiby/Tatos Dev/booking"
npm --prefix backend run build
npm --prefix backend run edge:check
npm --prefix backend run edge:build
npx supabase functions deploy booking-api --project-ref scwwkaywewecspsrskft --use-api --no-verify-jwt
curl -sS "https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/health"
```

Stop if any command fails. Expected revision: `2026-10-21-swimming-duration`. Keep existing secrets and function-side Supabase Auth verification unchanged. Reload the updated Flutter source to test; no APK was built.

Verify: a pool with a 60-minute minimum starts at 60, minus is disabled, plus selects 90/120, and longer flexible/fixed admissions confirm when otherwise valid. Coaching duration remains fixed. Check a known overlapping reservation and a session outside pool opening hours still fails. Save a copy of the previous deployed function before deployment. If restoring the older API, longer admissions will again be rejected by its old duration rules; pause affected admissions until the updated API is restored. No schema rollback is required.
