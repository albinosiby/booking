# Booking details history

Home → Collect and Booking details share the same updated screen. Payment history uses one section surface with compact method/amount rows, collection/refund labels, staff and local timestamps, and expandable reference/notes. Refund amounts have a minus sign. Booking history uses a timeline with readable event labels, staff/time, previous/new reschedule times and expandable reasons. Both lists show entry counts, newest first; empty states have no enclosing card.

The history header shows Collect plus the outstanding balance only for an authorized collector on a non-cancelled booking with a positive balance. Tapping opens the shared payment editor and scrolls to it. If collection is already open, current entries are preserved. Pending commands disable the action. Successful payment submission reloads the record and histories; the Collect button disappears once the balance is zero.

Feature models project immutable sorted histories and collection eligibility; Cubit guards collection and owns save/reload. Widgets contain presentation and scroll behavior. Existing repositories and APIs are unchanged.

No database migration or API deployment is required. No APK was built or installed. Run the updated Flutter app to test partial collection, full settlement, cancelled bookings, staff permissions, refunds and expandable history details.
