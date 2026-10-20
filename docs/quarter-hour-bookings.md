# 15-minute booking extensions

For flexible hourly turf, court, pool and hall bookings, the configured minimum remains unchanged. After reaching it, end times are accepted in 15-minute increments. With a 60-minute minimum and a 06:00 start, 07:00, 07:15, 07:30 and 07:45 are valid if opening hours and booking inventory allow them. 06:15/06:30/06:45 remain below the minimum. Arbitrary minutes such as 07:05 remain unsupported.

The start-time tariff remains the pricing basis. Prices are proportional to the minimum duration and rounded to minor currency units. A ₹600 minimum-hour rate gives ₹750 for 75 minutes and ₹1,050 for 105 minutes. Fixed group offers, sessions and full-day packages keep their configured durations and pricing.

Both Cubit validators and server duration/price validation now accept the 15-minute step. The server catalog and end-availability candidates expose the same step. Pricing help text has been updated across business settings. Models, repositories and Cubit remain the data/state boundaries.

## Deploy the updated API yourself

No database migration or data rewrite is needed. No live API deployment or APK build/installation was performed.

1. Save the currently deployed booking-api source as a rollback copy.
2. Copy the prepared bundle:

   ```sh
   pbcopy < "/Users/albinosiby/Tatos Dev/booking/supabase/functions/booking-api/index.ts"
   ```

3. Open Supabase → booking → Edge Functions → booking-api → Code, replace index.ts, then Deploy updates.
4. Preserve the existing secrets and function-managed authentication configuration (`verify_jwt=false`).
5. Verify https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/health returns revision `2026-10-19-quarter-hour-bookings`.
6. Run the latest Flutter source so its client-side validation also accepts the new step.

Validate 60-, 75-, 90- and 105-minute bookings, proportional totals, minimum-duration rejection and a range crossing an existing booking. To recover from an API problem, restore the saved source and redeploy; no database rollback is needed. Existing bookings remain stored unchanged. If reverting to an older server, its 30-minute extension rules may prevent editing/rescheduling newly created 75-/105-minute bookings until the newer server is restored.

## Verification

50 backend tests passed for minimum durations, 15-minute quote/availability behavior across all hourly businesses, inventory conflicts and Edge routing. Flutter booking/card regression tests and Flutter analysis passed. Edge type-check and the generated function bundle build passed.
