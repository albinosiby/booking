# Faster New booking time slots

## Changes

- Removed the fixed 250 ms client delay for selection changes. A zero-delay event coalesces synchronous business → sport → space → option initialization into one request.
- Selecting the same business, sport, space, option or date leaves the current slot grid intact instead of clearing it and repeating the request. Retry still performs a fresh availability read.
- Availability creates the bookable-space catalog once per request instead of once per candidate. Timezone conversions and local time labels for repeated values are memoized within that request only. Both start and finish grids use the same calculation path as authoritative quotes.
- Inventory reads filter to the selected physical inventory keys: shared turf sections for half/full grounds, or the selected court, pool or hall. Other spaces no longer inflate the loaded allocation set.
- Availability no longer takes an exclusive business-row lock. This is an advisory read; final quote/create/reschedule validation and transactional conflict protection are unchanged.

There is no cross-request slot cache. Permission checks, timezone/DST validation, operating-hour checks, pricing, pool capacity and shared-space overlap checks still run on the server. Old/out-of-order client responses remain guarded by generation and selection keys.

## Deployment — performed by the user

No SQL migration is needed. No database schema or existing data was changed. No APK was built or installed.

For server improvements to take effect, update the existing `booking-api` function in the booking Supabase project (`scwwkaywewecspsrskft`):

1. Save a copy of the currently deployed function for rollback.
2. Copy this workspace's generated bundle:

   ```sh
   pbcopy < "/Users/albinosiby/Tatos Dev/booking/supabase/functions/booking-api/index.ts"
   ```

3. In Supabase → Edge Functions → booking-api → Code, replace index.ts and select Deploy updates.
4. Preserve existing secrets, `BOOKING_DATABASE_URL`, and the existing function-managed authentication verification configuration (`verify_jwt=false`).
5. Run the updated Flutter source. Previously installed app binaries do not gain the client changes until updated.

Validate: change space/date and choose a start then finish; repeat the current selection without clearing the grid; switch dates rapidly and verify only the last date's results appear; check shared turf halves/full ground, capacity-limited pools, adjacent bookings and real overlaps. No validation SQL is required.

If the deployed API has a problem, restore the saved previous function source and redeploy. This rollback makes no data changes; it restores the earlier availability performance and behavior.

## Verification

- 35 backend booking tests passed, including authoritative-quote equivalence for all four business types, selected-court isolation, cross-sport turf footprints, pool capacity, finish-grid minimums, conflicts, rescheduling and DST behavior.
- 35 focused Flutter booking/cache/retained-state tests passed, including next-event slot loading, coalesced date edits and no reload on identical selections.
- TypeScript build and Edge type-check/bundle generation passed.
- A local calculation-only benchmark (96 candidates, warmed median samples using example configurations) measured court 26.2→13.7 ms, turf 21.7→13.9 ms, pool 26.1→13.9 ms and hall 28.0→13.3 ms. Candidate validity counts matched. These figures exclude database queries, network latency and phone rendering; they are not end-to-end latency promises.
