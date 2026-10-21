# Page retention and read snapshots

Booking OS retains page state and keeps loaded content visible while data refreshes. This is a client change: the hosted Supabase API, authentication, database and authoritative booking/payment validation remain unchanged. The app does not need a Mac server.

## Ownership and flow

Screens bind models and invoke Cubits. Cubits depend on feature repository contracts. REST repository adapters explicitly opt read operations into the generic `RetainedReadCache` through `RestApiService.retainedRead`. No widget or Cubit accesses Dio or secure storage.

The five primary tabs remain in GoRouter's indexed stateful shell. Selecting the current tab no longer resets its branch. Filters, selected calendar dates, navigation stacks and scroll positions survive tab changes. Configuration forms continue using their existing encrypted local draft repositories; final Save/Activate still publishes to Supabase.

Loaded bookings, booking details, Home metrics, Accounts summaries, transactions, bank settings, team lists and location choices remain visible during refresh. On Accounts, Income and Expenses, a new date/filter keeps the previous figures visible but faded and not tappable, under a thin progress line, until the new result arrives; if that load fails, the previous figures are cleared rather than left under the new period. Other screens clear the previous result rather than mislabeling it. Network errors retain valid content and expose retry; authorization failures clear sensitive retained content.

## Read policy

| Repository read | Fresh window | Maximum snapshot age |
| --- | --- | --- |
| Booking catalog, lists, counts, details, Home dashboard | 20 seconds | 15 minutes |
| Accounts catalog, summaries, transactions | 20 seconds | 15 minutes |
| Team | 20 seconds | 5 minutes |
| Customer search | 5 seconds | 1 minute |
| Countries, states, timezones | 24 hours | 7 days |
| Organization logo | 1 hour | 1 day |

Fresh hits avoid another request. Stale usable hits return immediately and start one deduplicated background refresh. An update notifies feature Cubits through repository streams. Expired reads wait for the server. Failed background refreshes notify the page and use a 10-second retry backoff; explicit refresh invalidates snapshots and immediately tries the server.

Tabs request revalidation at most once per 20 seconds; fresh entries still avoid network calls. Resuming the app rechecks the workspace at most once per 30 seconds, then revalidates retained reads. A workspace save already in progress is not interrupted by a resume refresh. No periodic polling or realtime subscription is introduced.

## Persistence and authorization

Application data snapshots use Flutter Secure Storage: up to 80 LRU entries with a 2 MiB encoded-data budget, debounced disk writes and serialized storage operations. This is app-level data retention, separate from HTTP response caching. The shared Dio HTTP interceptor uses a bounded in-memory store, respects the server's `no-store` directive and never falls back on authentication failures. Tokens, HTTP headers and downloaded reports are not written into application read snapshots.

A cold start still performs an authenticated workspace request. Only after that succeeds are stored snapshots restored for the matching API URL, user, organization, membership/access and business configuration. This deliberately does not provide a fully offline cold start. Expired snapshots are skipped, malformed storage falls back to server reads, and storage failures do not prevent normal operation.

Logout/account changes purge memory and encrypted snapshots. Organization, permission, space assignment or configuration scope changes prevent restoration of the old scope. Responses started under another account, or invalidated while in flight, cannot repopulate snapshots. HTTP 401/403 locks and purges snapshots until workspace access is confirmed again. Read-only pages reset and reload after an access-scope change; financial command forms retain their existing requirement to reopen after access changes.

## Writes and critical reads

Mutations conservatively invalidate all retained read snapshots before dispatch and after success; success notifies open pages to reload. Conservative invalidation covers booking-to-Accounts effects, bank mapping changes, configuration activation and staff access changes without a dependency graph that could omit an affected feature.

Availability, quotes, command-result recovery, final booking/payment writes, authentication and PDF/Excel downloads always contact the server. Read-only availability/quote POSTs do not evict page snapshots. The server remains responsible for slot conflicts, current price rules, authorization, balances and idempotency.

## Verification

Tests cover request deduplication, freshness/expiry, background success and failure, query separation, mutation invalidation, old in-flight results, restart restoration, logout/tenant isolation, permission denial, LRU eviction, corrupt persistence, HTTP no-store behavior, always-fresh availability, visible cards during pending refreshes and retained navigation/filter state. Existing feature tests continue covering configuration, split payments, rescheduling, bank accounts and reports.
