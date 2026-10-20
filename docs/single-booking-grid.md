# Single booking grid and business cards

## Behavior

Business choices appear directly in the Spaces section as horizontally scrollable, equal-width and equal-height cards. Cards show the business icon, name, type and selected checkmark. Long names have a two-line limit with their full label available through accessibility and a tooltip. Selecting the current business does not reset the form. The business bottom sheet and Change row have been removed. Rescheduling retains the existing same-business restriction.

For flexible hourly bookings, one grid contains the day's operating time boundaries. The initial start-availability snapshot stays visible while the server validates possible ends. The grid does not change into a separate finish-only list. A start/end/duration summary stays above it.

- Tap an available start, then an allowed end. Minimum duration comes from the configured space; longer bookings use the existing 15-minute increments.
- The selected start and end are highlighted, together with the intervening range.
- Tap the selected end to clear only the end and price. The start and validated end choices remain.
- Tap the selected start to clear the range and price. Original start choices remain visible.
- After a complete range, another valid start begins a new selection.
- A time blocked as a start can still be a valid end: a new booking beginning at 10:30 permits the previous booking to end at 10:30.
- Midnight endpoints have their own date and appear as 24:00 with a next-day label. Boundaries are keyed by date and time, so the next day's midnight is distinct from the current day's midnight.
- Availability failure keeps the original grid and shows retry; invalid/unvalidated ends cannot be selected. Generation and selection-key checks discard late requests after deselection, account changes or a changed space/date.

Pool groups and hall sessions/full-day packages retain their fixed-duration behavior. Availability and quotes still come from the repository and server. No long-lived availability cache was introduced. Booking creation/rescheduling still recheck full-interval inventory and price. Cleanup remains informational.

## Models, repositories and Cubit

`BookingFormModel` retains start and end validity separately and exposes typed `BookingTimeCell` projections for one grid. `BookingFormCubit` owns selection, deselection, asynchronous validation and quote invalidation. Repositories retain their existing typed availability contract. The API now includes operating-boundary rows marked `end_only` in start availability; these are not selectable as starts.

## Deploy the API yourself

No SQL migration or existing data rewrite is needed. No API deployment, APK build or installation was performed.

1. Save the currently deployed booking-api source as a rollback copy.
2. Copy the latest generated function:

   ```sh
   pbcopy < "/Users/albinosiby/Tatos Dev/booking/supabase/functions/booking-api/index.ts"
   ```

3. In Supabase → booking → Edge Functions → booking-api → Code, replace index.ts and choose Deploy updates.
4. Preserve existing secrets, `BOOKING_DATABASE_URL` and function-managed authentication (`verify_jwt=false`).
5. Verify https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/health returns revision `2026-10-19-quarter-hour-bookings`.
6. Run the latest Flutter source. The cards, persistent grid and deselection need the updated client source; the API update supplies all operating boundaries before the first start is chosen. Existing installed app binaries do not gain client changes automatically.

Validate 09:30–10:30, 09:30–12:00, below-minimum ends, crossing a booked interval, midnight and an end at another booking's start. Clear the end, then the start; switch businesses/dates rapidly and confirm late requests do not restore cleared selections. Confirm equal card dimensions and horizontal scrolling at narrow widths and enlarged text.

To recover from an API issue, restore the saved previous function and redeploy. No database rollback is needed. Keep the previous app build/source available if reverting the client interaction too.

## Verification

53 focused Flutter booking, card, agenda, retained-state and transport tests passed, plus the loading animation regression checks. 52 booking/24-hour backend tests and 11 Edge routing tests passed. Flutter analysis, TypeScript build, Edge type-check and generated Edge bundle build passed. Light/dark previews were checked, including selection, deselection and enlarged-text layouts.
