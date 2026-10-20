# Loading performance improvements

This update reduces duplicate network work across the app and removes sequential waits on independently authorized data reads. It preserves Screen → Cubit → repository → transport boundaries.

- Concurrent identical GET requests share one in-flight HTTP request. Separate completed reads still follow repository freshness policies and HTTP cache directives; this is not an additional response cache.
- GET requests started after mutations do not join older pending requests. Different users, query strings and invalidation generations have separate keys. Each caller receives an isolated response map/list.
- Booking details, booking rescheduling, expense lists, expense details and Add expense load independent data concurrently. Server authorization and existing Cubit identity/generation checks remain in place. Data requests dependent on permissions, location date or selected filters remain ordered where necessary.
- A transient background-refresh failure keeps an otherwise valid retained snapshot visible during the existing 10-second retry cooldown. This does not extend retention limits. Uncached/expired data still reports failure, and authentication/authorization errors still purge cached data.
- Availability and price quotes continue to go to the server. Booking/payment mutations and downloads are not cached or merged.

The change does not shorten network timeouts, skip server checks or add artificial animation delays. First loads still depend on network latency and hosted API response time; no on-phone timing claim is made.

No backend deployment, database migration, APK build or phone installation is needed/performed for these source-only Flutter changes. Test by running the updated Flutter source. For an already-installed app, the changes become available in a future app update.

Validation: cache deduplication, response isolation, mutation invalidation, access-denial/account isolation, retained content during refresh failures, expiration, and booking/Accounts/Expenses regression tests.
