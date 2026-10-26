# Booking details: payment summary and check-in

## Screen

The payment summary appears before booking details. It highlights balance due,
refund due, or fully paid, followed by subtotal/discount when relevant, booking
total, net amount received and a received-versus-total indicator. An authorized
Collect payment button opens the existing reusable split-payment editor and
scrolls to it. The editor and its entered values are retained if Collect is
pressed again. Refunds retain their existing permission and balance checks.

Payment history and Booking history are not rendered on this screen. Their data
is preserved for audit and existing reporting behavior. The booking section
keeps space, schedule, customer, notes and informational cleanup time.

## Check-in

For the approved end-of-day fallback, its distinct automatic label, scheduler,
activation migration and verification/recovery instructions, see
[End-of-day booking check-in](booking-end-of-day-checkins.md). This applies to
regular bookings only and preserves payment dues.

The previous Mark completed button is replaced by Check in for managers of a
confirmed booking which has not been checked in. It opens a confirmation section
with an optional arrival note. An empty note records "Customer checked in".
An entered note follows existing reason validation (2–500 characters).
Early arrival is permitted; the confirmation explicitly says booking/payment
status will not change. After saving, the booking shows Checked in and the
Check in/Mark no-show actions are hidden.

The Cubit submits the existing idempotent status-command repository operation,
with `status: "checked_in"`, command UUID and expected booking version. The server
locks and authorizes the booking, stores a `checked_in` activity with server time
and actor, and increments its version. The booking remains `confirmed`.
Payments, tariff, allocations and booking times are unchanged. Duplicate commands
are idempotent, subsequent distinct check-ins are rejected, and checked-in
customers cannot be marked no-show. Cancelled/final bookings cannot check in.
Existing completion semantics remain available to old API consumers; this page
no longer offers Mark completed. Check-in records remain associated with the
booking if it is subsequently edited or cancelled.

No new database migration is needed: the existing booking_history table stores
arrival events. The model derives its checked-in flag from this activity; the
history need not be visible to the user.

## Manual deployment

Do not run any new SQL for this change. Previously pending feature migrations
(bank full numbers/message templates, if any) still need to be applied before
using the combined latest API bundle.

1. Keep a copy of the currently deployed function code for rollback.
2. Copy all of `/Users/albinosiby/Tatos Dev/booking/supabase/functions/booking-api/index.ts`.
3. In Supabase project **booking** → Edge Functions → **booking-api** → Code,
   replace its entry file with the generated bundle, then deploy. Keep existing
   secrets and the approved function-side Supabase Auth verification settings.
4. Visit `https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/health`.
   Confirm revision `2026-10-20-booking-check-in`. This bundle also includes the
   customer lookup performance fix from the previous update.
5. Run the updated Flutter source. Confirm an unpaid booking opens its summary,
   Collect opens split payment, Check in shows a confirmation, and saving changes
   its arrival label without changing the pending amount. Check an assigned staff
   account and a cancelled booking as well.

Until that API deployment, the older server will reject the new checked_in
command; the app will report the error rather than pretend it was saved.
To recover from a failed deployment, restore the saved function code. No schema
rollback is needed; existing activity remains stored. An older client may not
display the new arrival label, so keep the updated client when testing check-in.

No live database change, deployment, phone installation or APK build was performed.
