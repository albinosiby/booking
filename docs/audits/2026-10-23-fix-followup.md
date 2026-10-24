# Audit fix follow-up

The original 13 local fixes remain applied. Additional repository changes address the two outstanding findings as far as the current single-process deployment allows. No deployment, live migration or CDN change was performed.

## Admin login attempt budget — AUD-10

The sign-in action now reserves a budget before password comparison or asynchronous authentication work. Each gateway-supplied peer gets ten attempts per fixed ten-minute window. Further attempts return a recoverable form error. Successful sign-in clears that peer's budget; blocked requests do not extend the window. A bounded map refuses new keys at capacity rather than evicting active restrictions. Keys are hashed and not logged. Tests cover parallel reservation semantics, expiry boundaries, successful reset, peer isolation and capacity flooding.

The peer comes from `X-Forwarded-For`, which the packaged Nginx gateway overwrites. Keep the admin listener private and reachable only through that gateway. Do not expose the Next server directly or trust an arbitrary client-supplied forwarded header. Railway may present a shared proxy address, so operators behind that address can share a budget; validate the effective peer address in staging before release. Do not change trusted proxy configuration without verifying the platform's actual trust boundary.

This budget is process-local. It fits the current one-admin-process container and resets on process restart; replicas have independent budgets. Distributed attempt limiting remains required before scaling to multiple admin processes/replicas. Use a shared atomic store or trusted edge rate limiting. This change does not introduce MFA or named administrator identities.

## Flutter cache policy — AUD-08

Flutter responses now carry `Cache-Control: no-store, no-cache, must-revalidate`, `CDN-Cache-Control: no-store`, `Cloudflare-CDN-Cache-Control: no-store` and `Surrogate-Control: no-store`. The smoke test now checks the effective cache policy of all three unversioned entry scripts: `flutter_bootstrap.js`, `flutter.js` and `main.dart.js`. Hashed Next assets retain their existing immutable cache policy.

The observed live four-hour TTL can still be caused by CDN rules overriding origin headers or previously cached responses. Repository changes alone cannot purge those entries. After an approved deployment:

1. Configure any CDN cache rule to bypass caching for `/app/*` and retain the existing private/no-store policy for `/admin/*` and dynamic/public API responses.
2. Purge previously cached `/app/*` responses using the hosting/CDN control plane.
3. Run `node deploy/smoke.mjs https://bookingos.online PUBLISHED_TEST_SLUG bookingos.online` using an existing published test venue. This script checks routes and assets without creating bookings.
4. Inspect cache headers on `/app/`, `/app/flutter_bootstrap.js`, `/app/flutter.js` and `/app/main.dart.js`. Confirm no edge override restores the four-hour TTL.
5. Test an existing browser session through reload and navigation across the deployment.

Recovery: restore the previous application image if needed; no database rollback is involved. A cache purge cannot be undone, but it does not delete business data. For multiple replicas, ship shared attempt limiting before enabling additional admin workers rather than treating this process-local budget as distributed protection.

## Validation limits

Focused login-budget and redirect regressions pass. The admin production build and routing checks are recorded in the follow-up validation output. Nginx and Docker are not installed on this host, so the effective gateway cache-header assertions must run through the existing container CI/staging smoke before release. The earlier authenticated-production browser limitation remains unresolved.
