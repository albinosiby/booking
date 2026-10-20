# Booking payments and discounts

The New booking Payments section shows subtotal, discount, final/estimated total, received and balance due. Each split payment has an amount field and a payment-method dropdown on the same row. UPI, Card and Bank transfer show a receiving-bank selector underneath; Cash uses the cash account automatically. Add other payment appends another row. Receiving accounts continue using the space mapping/primary-account defaults, with a picker for overrides. Reference and payment date/time are under optional details. Bookings may remain unpaid.

Add discount expands an editor with amount or percentage and an optional reason (200 characters). Removing it restores the full tariff. Percentage supports two decimal places, stored as integer basis points; fixed amounts use currency minor units. The preview responds locally. Quotes and final writes recompute the discount on the server, reject negative/over-subtotal/over-100% values and bind the discount into the quote token. Split payments may not exceed the discounted total. Rescheduling retains the original discount and applies it to the newly quoted subtotal.

The existing `selection` and `price_snapshot` JSON columns store the discount, subtotal and reduction. Existing bookings without those fields continue displaying their original total. Booking details and Accounts PDF/Excel booking rows show discounts; financial totals use the final booking amount. Discounts are reductions to booking value, not cash expenses or refunds.

## Deployment — performed by you

**No database migration, SQL, new secrets or auth setting changes are required.** Deploy the API before running the updated Flutter client; the older API rejects the new discount field.

1. Save a copy of the current `booking-api` function code for recovery.
2. Open `/Users/albinosiby/Tatos Dev/booking/supabase/functions/booking-api/index.ts` and copy its contents. On macOS you can use:
   ```sh
   pbcopy < "/Users/albinosiby/Tatos Dev/booking/supabase/functions/booking-api/index.ts"
   ```
3. In Supabase dashboard, select **booking → Edge Functions → booking-api → Code**. Replace `index.ts` with the prepared code and deploy the update. Preserve the existing secrets and function-level Auth verification setup.
4. Open `https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/health`. The revision should be `2026-10-20-booking-discounts`.
5. Run the updated Flutter app yourself. No APK has been built or installed.

## Check

- For a ₹500 booking, apply 10%: final ₹450. Cash ₹100 + UPI ₹350 leaves zero balance; ₹451 of collections is rejected.
- Apply ₹50 instead: final ₹450. Remove it: final ₹500.
- Reject percentages above 100 and fixed discounts above subtotal. Confirm a 100% discount without payment.
- Save a discounted booking, reopen details and reschedule it: subtotal/discount/final total remain consistent.
- Download monthly PDF/Excel: the booking subtotal, reduction, final tariff and actual payment split agree.
- Confirm older bookings still open with no discount.

## Recovery

Restore the saved function and previous Flutter code together if needed. No data rollback is required. Do not manually increase existing discounted booking totals: those records retain their original pricing snapshot and collections. Avoid rescheduling discounted bookings through an older app/API that does not understand discounts.

## Payment entry shortcuts

New booking displays one initial blank Cash row without recording a payment. Blank amount/reference rows are omitted at confirmation; entering a reference without an amount is still validated. Digital methods display the mapped or primary receiving bank in a compact To/Change row. Changing a method clears its previous explicit destination so the new method gets the correct default. No bank account numbers are invented or downloaded for this display.

Pay balance fills a row with the total minus all other payments. Add other payment prefills the remaining balance when it is positive. Removing an entry updates the balance immediately; removing all entries restores the blank row. Invalid amounts and overpayments are shown beside the amount field. Subtotal and discount details only appear in the summary once a discount is added. Payment editing and bank selection use already loaded models and do not request another quote or availability response.

These entry improvements require only the updated Flutter source. No additional API deployment or migration is needed beyond the discount API described above.

## Reusable payment entry

`lib/modules/bookings/widgets/booking_payment_editor.dart` is shared by New booking and Booking details → Record payment (including collection opened from Home). `booking_widgets.dart` re-exports it to preserve existing imports. `models/booking_payment_entry_model.dart` centralizes remaining-balance calculations, per-row limits, inline validation and filtering of empty rows; each screen retains its own Cubit and repository operations.

Details collection starts with a blank Cash row, displays the outstanding amount/collecting/remaining summary and uses the same bank selector and balance shortcuts. It requires at least one nonempty, valid payment before submission. A blank extra row is omitted rather than saved. Refunds use the same editor with Refund due/Refund balance/From bank labels and are limited to the actual refundable amount, with a reason still required. No discount editing is exposed when collecting or refunding an existing booking.

This reuse requires no migration or additional API deployment. No APK was built or installed.
