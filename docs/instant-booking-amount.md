# Immediate booking amount

The booking form displays an estimated total synchronously from the loaded start slot price. Flexible bookings scale that minimum-duration price to the selected duration, rounded to minor currency units. Fixed packages retain the loaded price. Clearing the end hides the preview; changing date, space, option or participant count clears availability and its price together.

The footer labels this preview Estimated total until the live quote replaces it. A pool per-person preview may differ slightly due to unit-price rounding. Review, payments and confirmation continue using only the server quote. The quote starts on the next event-loop turn without the previous 200 ms delay. Availability and final write checks remain authoritative against concurrent bookings and changed tariffs.

No database migration or API deployment is needed for this change. Run the updated Flutter app to test it. No APK was built or installed.

Validation: choose 09:00–10:15 with a 60-minute minimum rate of ₹500; ₹625 appears immediately, before quote completion. Clearing the end removes it. Check that the server quote replaces the estimate and confirmation cannot bypass live verification.

## Immediate review

Review booking remains available while a quote is in progress. After local customer, time-range and payment checks, the review summary opens from the current selection without waiting for the network. It shows verification status and retains the estimated total. Confirm remains disabled while verification is pending; on failure, Retry verification starts another check. Final confirmation checks split payments against the authoritative total again. If a paid booking has no loaded tariff at all, review waits for a known total to validate those payments.
