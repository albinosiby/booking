# Customer suggestions and background preloading

## Customer entry

New booking searches the existing organization-scoped customer endpoint after a
300 ms typing pause and at least three phone digits, only while the name is empty.
Matching names are choices; no name is automatically selected. Tap a result to
fill the existing customer's details, or type a new name using the same number.
Editing a selected name or number detaches its old customer ID, so the backend
records the entered customer rather than silently reusing the previous identity.
Late search results are discarded after edits, access changes or disposal.
Optional lookup failures leave manual entry available. Existing server access
rules restrict staff results to their visible booking history.

The existing customers table has no unique constraint on phone numbers. No new
migration, API change or deployment is needed for this feature.

## Background reads

WorkspaceCubit starts an optional injected WorkspacePreloader after authoritative
workspace access succeeds. Home emits ready first; preloading waits 600 ms so it
does not hold startup. Two workers perform one repository operation per job.

Priority reads: booking catalog (businesses/spaces), first Bookings page, today's
Calendar list and its initial 31-day count window. These use the same default
filters as the corresponding screens. The workspace already includes business
configuration and resource data.

Next: permitted finance catalog (including bank settings), current-month account
overview/transactions and expenses overview/list/categories, and owner Team list.
Financial date filters use the catalog's business-local today value. Default
Calendar dates continue to follow the current screen's device-local date policy.

The coordinator calls repository interfaces only. Existing scoped encrypted read
caches deduplicate concurrent screen requests and keep retained data visible
while stale entries refresh. Existing mutation invalidation and cache limits
remain in force. Completed warm-ups are throttled for ten minutes per access
scope; sign-out resets the throttle. Queued work stops when workspace access or
its generation changes. In-flight requests cannot be recalled, but their normal
transport authorization/cache-scope checks remain active.

Reports, attachments, historical pagination, availability and price quotes are
not prefetched. Final booking/payment writes retain authoritative validation.
Warm-up failures do not block Home or replace page retry/error handling. A first
visit before its warm-up finishes may still need to wait for the shared request.

## Verification

Run `flutter analyze` and:

```
flutter test test/customer_suggestions_preload_test.dart test/startup_background_test.dart test/home_dashboard_test.dart test/booking_module_test.dart
```

No database migration, Supabase API deployment or APK is required/prepared.

## Phone lookup performance follow-up

The typing pause is now 180 ms. Each booking form retains up to 12 query result
sets (at most 40 customers each), cleared on access-scope changes and released
when the form closes. Narrowing the phone input immediately displays known
matching names, while a fresh bounded lookup checks for additional matches.
Optional network failure preserves the suggestions already displayed. Phone
formatting is stripped from cache keys, avoiding redundant requests for spaces
and punctuation. Repository freshness is 30 seconds with a two-minute retained
window; authoritative customer access is still checked when saving a booking.

The API now filters staff-visible customers in the lookup SQL, instead of running
one booking-history query per matching customer. It applies organization and
resource permissions before the 40-result limit. Matching ignores formatting and
still supports partial numbers and multiple names sharing a number.

### Deploy this API update yourself

No new database migration is needed. Existing migrations required by previously
implemented features must still be applied before deploying the combined bundle;
see the bank-number and message-template guides if those are outstanding.

1. Save a copy of the currently deployed function code for rollback.
2. Copy the complete generated file:
   `/Users/albinosiby/Tatos Dev/booking/supabase/functions/booking-api/index.ts`.
3. In the Supabase **booking** project, open Edge Functions → **booking-api** →
   Code, replace the entry file with that generated bundle, and deploy.
   Keep existing secrets and the function's own Supabase Auth verification setup.
4. Open `https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/health`.
   Confirm revision `2026-10-20-customer-lookup-performance`.
5. Run the updated Flutter source. With the name empty, type a known number:
   check matching names, formatted numbers and manual entry. With a staff account,
   confirm customers outside assigned spaces remain hidden.

The earlier statement that the initial suggestions feature needed no API update
applies to that initial implementation; this performance follow-up does require
the above redeployment. No APK is prepared and no live deployment was performed.
If deployment fails, restore the saved function code; no database rollback is
needed for this update. Cloud cold starts/network latency can still affect the
first lookup for an uncached number. No live-device latency measurements were
made for this change.
