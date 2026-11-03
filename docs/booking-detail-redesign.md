# Booking details screen redesign

Status: approved and implemented locally. Flutter verification is recorded in the task response.

## Problem and users

Owners and staff need to identify a booking, see its time and payment state, and take the right action quickly. The current mobile screen puts a large reference at the top, repeats payment actions, opens an inline form below unrelated details, and labels a normal collection as a split payment. This makes it unclear whether the user has started, completed, or still needs to save a payment.

## Mobile layout

```text
< Back                 Booking details                Share
BK-6C2135F45446   [Confirmed]

Main Ground · Half A
Today, 3 Nov · 11:30 AM–1:30 PM
RK Groups Turf                 [View customer]

Payment
Balance due                         ₹1,000
Received ₹0 of ₹1,000
[ Collect ₹1,000 ]

Actions
[ Check in ]          [ Reschedule ]
[ More actions ▾ ]

Details ▾
Customer · sport · notes · timezone · cleanup time

Invoices ▾ (when available)
```

The reference is selectable and copyable. The booking status remains visible near it. The time uses the business timezone and a human-readable date. Space, court and booking time lead the page. Keep the payment summary compact, with balance, received and total visible together. Hide internal-only cleanup text in Details. The same structure works on desktop within the existing max-width layout.

## Payment interaction

Tap the sole `Collect ₹…` button to open a dedicated collection sheet. The booking page stays behind it, so a draft payment is never mistaken for a recorded one.

```text
Collect payment                         Close
For BK-6C2135F45446
Balance due                         ₹1,000

Amount                              [1,000.00]
Method                    [Cash | UPI | Card | Bank]
Destination                   Cash in hand / bank
Reference and payment date ▾
Note (optional)                         [     ]

[ Add another payment method ]
Collecting ₹1,000 · Remaining ₹0
[ Record ₹1,000 payment ]
```

The amount remains prefilled with the balance. `Add another payment method` adds a second row and updates the collected/remaining totals; only then is the flow described as a split payment. The final button records the payment and closes the sheet after a confirmed server result. The payment must never be counted locally before the server accepts it. When a network outcome is uncertain, keep the sheet open and offer a clearly labelled retry with the existing idempotency key. Back and close are disabled during an unresolved payment, and field validation is shown beside the affected field.

## Other actions and states

- Show `Check in` and `Reschedule` only when allowed by current status and permissions. After check-in, show the checked-in state instead of the action.
- Put `Edit customer & notes`, `Cancel booking`, `Cancel & refund`, and `Record refund` inside `More actions`, with destructive actions visually separated and confirmed. Keep the existing cancel-then-refund sequence; do not imply that cancellation itself transfers money.
- Show submitted website transaction IDs as `Unverified website payment` in a compact notice. Recording a verified collection remains a separate explicit action.
- If fully paid, replace the collection button with `Paid in full`; if cancelled with a refund due, show the refund due and its action. If the booking is loading, show a skeleton in this same hierarchy; if the request fails, retain any last known booking details with a retry message.
- Retain invoice access, share action, accessibility labels, and all existing permission checks.

## Architecture and data

This is a Flutter presentation change in `booking_detail_screen.dart`, `booking_payment_summary.dart`, and `booking_payment_editor.dart`, using the existing `BookingDetailCubit`, repository, and booking/payment endpoints. No new API, database table, or migration is required. Keep command idempotency, version checks, bank destination mapping, and accounting math unchanged. Navigation back to the booking list and deep links into collection must continue to work.

## Verification

- Widget tests: unpaid, partially paid, fully paid, cancelled/refund due, website payment awaiting verification, loading, error, and permission-limited staff.
- Interaction tests: one-method collection, split cash/UPI collection, amount above balance, required refund reason, save success, network-uncertain retry, cancel/edit state, and deep link that opens collection.
- Manual mobile QA: narrow Android screen, keyboard open, long business/space names, large text scale, screen reader order, dark theme, and desktop width.

## Delivery sequence

1. Refactor the detail header, summary, and action hierarchy.
2. Present the existing payment editor in a focused collection sheet and adjust labels for single versus split payment.
3. Update widget tests, run Flutter analysis and the relevant test suite, and check the screen on a device or emulator if available.
