# Activation: JSON content type fix

## Cause and change

Activate has no required request fields. The mobile transport previously sent a
POST with null data. An empty HTTP body may still arrive as a body stream at the
Edge runtime, where the JSON parser checked Content-Type before inspecting its
length. A zero-byte stream without an application/json header was rejected with
415 "JSON content type is required."

RestApiService now sends `{}` with application/json for bodyless POST/PATCH/PUT
calls, protecting activation of pools, turf, courts and halls. Existing nonempty
request payloads are preserved. The Edge parser accepts an actually empty body
stream; nonempty bodies still require application/json, valid JSON and the
existing size limit. Authentication and business permissions are unchanged.

## Apply through Terminal

No new SQL migration is needed. Keep existing required migrations and secrets.
Run these commands in order, stopping if any command fails:

```sh
cd "/Users/albinosiby/Tatos Dev/booking"
npm --prefix backend run edge:build
npx supabase functions deploy booking-api --project-ref scwwkaywewecspsrskft --use-api --no-verify-jwt
curl -sS "https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/health"
```

Confirm revision `2026-10-20-activation-json`. The function performs its own
Supabase Auth verification; keep that existing configuration. This bundle also
includes the earlier check-in and customer lookup updates.

Then retry Activate in the existing app. The API fix supports its empty-body
request, so this specific fix does not require a new APK. The transport safeguard
also takes effect when running the updated Flutter source.

Before deploying, retain a copy of the current function code for recovery. If
needed, restore that previous code; no schema rollback is involved. This update
was prepared locally, not deployed, and no APK was built or installed.
