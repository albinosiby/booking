# Minimum booking duration and start/end selection

Hourly bookings now use a minimum duration with 30-minute extensions. The change covers turf, individual courts, regular swimming admissions and hourly hall bookings. Pool group packages, coaching classes, hall sessions and full-day packages retain their configured fixed durations.

## Configure and book

1. Open a space's timing/pricing settings. Choose **Minimum booking duration**, such as 60 minutes.
2. Enter its minimum-duration price in each weekday/time rule. A new minimum selection uses a single base duration; enter its price if that duration had no configured rate.
3. Save the configuration as usual. Continue retains the existing local-draft workflow; final Save/Activate publishes it.
4. On New booking, choose a date, then tap a start in the grid. The grid switches to **Choose finish time**; tap a finish there. Review remains disabled until a valid finish has been chosen. A 06:00 start and 09:00 end is a 180-minute booking. The displayed booking length updates immediately.
5. End can be the following day, including 24:00/00:00, within the existing 24-hour maximum. The UI identifies next-day endings. A minimum of 60 permits 60, 90, 120, 150, 180 minutes and so on. A minimum of 90 permits 90, 120, 150 and so on.

The server verifies the entire interval against opening hours, operating dates, pool capacity, shared turf footprints, existing reservations and buffers. Rescheduling uses the same selection and quote rules. Duration cannot be below the minimum or off the 30-minute extension step.

## Pricing

Price is the rate applicable at the booking's **start time**, multiplied by booking minutes / minimum minutes. A 60-minute rate of ₹600 makes 90 minutes ₹900 and three hours ₹1,800. Crossing a pricing-band boundary does not split the price. Existing weekday, seasonal and missing-rate rules still apply.

Money is rounded to the nearest minor currency unit. Regular pool admission scales the per-person price before multiplying by swimmer count. Group package prices are not converted into hourly rates.

The existing `default_duration_minutes` is now the minimum/base billing duration. Existing stored prices for other durations remain intact until a user explicitly changes the minimum, but flexible hourly quotes use the base rate rather than those other duration-specific prices. Review the selected minimum and its base price before using this billing change. Existing completed bookings and financial entries are not rewritten.

## Models, repositories and Cubit

Booking options expose minimum-duration metadata from the inventory repository. Booking form state retains a duration and derives its end time; the Cubit validates end-time edits and refreshes the existing quote/availability flow. Configuration Cubits select the minimum and preserve or initialize its base rate. Screens do not access Supabase or storage directly. Backend pricing uses shared integer-currency scaling while retaining each business's operating-window and occupancy checks.

## Deployment / migration

**No SQL migration is needed.** Existing configuration fields are reused. The hosted `booking-api` must be redeployed before testing flexible bookings with the latest Flutter source.

The updated, generated source is `supabase/functions/booking-api/index.ts`. In the existing booking Supabase project (`scwwkaywewecspsrskft`), open **Edge Functions → booking-api → Code**, replace `index.ts`, then choose **Deploy updates**. Download the previous function source first if a rollback copy is needed. Preserve existing secrets and `verify_jwt=false`; the function keeps its internal Auth verification.

Copy the generated code on the Mac with:

```bash
pbcopy < "/Users/albinosiby/Tatos Dev/booking/supabase/functions/booking-api/index.ts"
```

Run the latest app source and refresh booking choices after deployment. Test 06:00–09:00, a half-hour extension, a below-minimum interval, a booked overlap and an end beyond closing. Confirm fixed group/session durations remain fixed. Existing duration-specific discounts are no longer used for flexible hourly quotes, so retain a copy of old configuration if reverting billing behavior.

No hosted deployment, database migration, APK build or phone installation was performed as part of this source update.

## Verification

- 60 focused Flutter booking/turf/court/pool/hall tests passed, plus 11 business-management tests after the final summary changes.
- 67 backend tests passed, including 3-hour/90-minute pricing for each hourly business type, 06:00–09:00 conflict protection, minor-unit rounding and fixed package duration protection. The final turf activation change also passed its 12-test regression suite.
- Flutter analysis reported no issues. TypeScript build, Edge type-check and generated Edge bundle build passed.

## Start/finish grid correction

The earlier implementation kept grid taps as start-only selection and required a separate end picker. It now uses two explicit phases in the same grid. Duration chips and separate flexible-duration pickers are removed. **Change start time** returns to the start grid and resets the duration to the configured minimum. Totals remain blank until a finish is chosen; the authoritative quote then prices the complete interval.

The availability API accepts optional `end_times: true` on the existing POST `/v1/bookings/availability`. For this mode it returns finish candidates with `duration_minutes`, local end date/time, availability and total. A finish exactly at another booking's start or at closing is allowed when the complete interval and buffers fit. Short candidates are disabled with a minimum-duration explanation. All full-interval conflicts, shared turf footprints and pool-capacity checks use one allocation snapshot per request. This operation makes no bookings or financial writes.

Catalog mapping can derive the hourly minimum from the configured default if older catalog metadata lacks the explicit minimum. That does not remove the requirement to deploy the updated server: older servers do not support finish-time availability requests. Redeploy the latest generated function and run the latest Flutter source; no migration is needed. This change has not been deployed to the live project or installed on a phone.

The correction passed 41 focused Flutter tests (booking flow, narrow-screen interactions, cached transport and agenda navigation), 30 backend booking tests (including 06:00–08:00, 06:00–09:00, short finishes, conflicts and midnight), Flutter analysis, TypeScript build, Edge type-check and Edge bundle generation. No APK was built.
