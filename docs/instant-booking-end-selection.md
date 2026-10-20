# Instant end-time selection

The initial availability read now includes compact valid-end options for each available flexible start. Tapping a start reads those already-loaded options from the typed slot model: no second availability request is made, and end picking does not enter a loading state. Deselecting/reselecting the same start reuses that form snapshot.

The server uses the same configuration, inventory, participant count, staff permissions and rescheduling exclusion as the initial grid. For each fixed start, valid intervals form a prefix: extending cannot undo an existing conflict, reopen a closed interval or reduce the proportional price. A bounded binary search identifies the longest valid interval, then its 15-minute endpoints are included as compact `[duration, local-end-date-time]` pairs. Endpoint dates come from server timezone conversion, rather than the phone timezone.

No additional database reads are introduced for this preload. The initial response carries more data and calculation work so that later start taps need no round trip. This does not eliminate the initial page/slot request. Quotes after selecting an end and final create/reschedule operations still validate current inventory, price and access. Preloaded choices are a form-session availability snapshot, not a reservation or a guarantee against another staff member booking later.

Models, repositories and Cubit remain the boundaries: `BookingSlot` exposes immutable typed end choices mapped from the response; `BookingFormCubit` enables them immediately. Existing APIs without the preload field retain the previous checked fallback, so both the new API and latest Flutter source are required to remove the end-picking request.

## Deploy this update yourself

No SQL migration is required. Existing data is unchanged. No live deployment, APK build or installation was performed.

1. Keep a copy of the currently deployed booking-api source for rollback.
2. Copy the generated bundle:

   ```sh
   pbcopy < "/Users/albinosiby/Tatos Dev/booking/supabase/functions/booking-api/index.ts"
   ```

3. In Supabase → booking → Edge Functions → booking-api → Code, replace index.ts and Deploy updates.
4. Preserve existing secrets, `BOOKING_DATABASE_URL`, and function-managed authentication (`verify_jwt=false`).
5. Verify https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/health returns revision `2026-10-19-preloaded-booking-ends`.
6. Run the latest Flutter source, reopen New booking and load a space/date. Tap a start: its end choices should enable immediately. End selection still checks the live price.

Validate minimum-hour/15-minute ends, tap-to-deselect, different dates/spaces/participant counts, midnight, pool capacity and actual overlaps. A booking added after the preload must still be rejected by fresh quote/create validation. Fixed group packages and hall sessions keep their existing behavior.

To recover from an API problem, restore the previous saved function source and redeploy. No database rollback is needed. The updated client falls back to the earlier availability request if the server omits preload metadata.

## Checks

66 backend tests passed across bookings, 24-hour behavior and Edge routing, including preload equivalence for turf/courts/pools/halls, conflict boundaries and fresh validation after another booking. 34 Flutter booking/transport tests passed, including zero extra availability calls after a start tap and immutable midnight endpoint mapping.
