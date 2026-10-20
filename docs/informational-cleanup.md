# Informational cleanup

Cleanup defaults to 5 minutes for newly configured turf offerings, courts, pools and halls. Existing explicit cleanup settings, including zero, are preserved. Booking details read the cleanup minutes from the booking's price snapshot, defaulting to 5 for older snapshots without that field. Changing configuration later does not rewrite historical snapshots.

Preparation and cleanup are internal information only. Availability, quotes, creation, rescheduling, operating-hour checks and pool capacity use the customer's actual start/end times. A booking ending at 10:30 permits another to start at 10:30. Actual overlapping reservations still block the same inventory, including shared turf halves and hall packages, or consume pool capacity.

Existing allocation records may contain padded times from the older API. The updated API reads their bookings' actual start/end times, so no data rewrite or SQL migration is needed. New allocations store actual times. Models, repositories and Cubit remain the data/state path for booking details.

## Deploy the API yourself

Prerequisite: access to the existing `booking` Supabase project and permission to update `booking-api`. Keep a copy of the currently deployed function before replacing it.

1. Open the Supabase dashboard → booking → Edge Functions → booking-api → Code.
2. Copy the complete contents of `supabase/functions/booking-api/index.ts` from this workspace and replace the function's index.ts. On macOS:

   ```sh
   pbcopy < "/Users/albinosiby/Tatos Dev/booking/supabase/functions/booking-api/index.ts"
   ```
3. Deploy updates. Preserve existing secrets, including `BOOKING_DATABASE_URL`, and the existing function-managed Supabase Auth verification setting. Do not enable the legacy gateway JWT verification switch.
4. Run the updated Flutter source normally to test. No APK was built or installed for this change.

## Validate

- Set minimum duration to 60 minutes and cleanup to 5 minutes.
- Book 09:30–10:30. Booking details show `Cleanup time: 5 minutes` and an informational note.
- Book 10:30–11:30 on the same space; it succeeds. A genuinely overlapping interval remains unavailable.
- Repeat on turf, courts, pools and halls. Pool bookings share configured capacity; full-ground turf bookings still share half-ground inventory.
- Verify a booking can start at opening and finish exactly at closing, even with nonzero preparation/cleanup.
- An older booking with padded allocations must also allow an adjacent booking.

No SQL migration or validation query is required. To recover from a deployment problem, restore the previous function source and redeploy. Be aware that the previous API resumes treating cleanup as blocking; avoid accepting new bookings until the intended version is deployed.
