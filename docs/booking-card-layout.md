# Shared booking card layout

Home, Bookings and Calendar use the same CompactBookingCard. The reference-inspired card has an initials avatar, prominent customer name, phone and space/sport details, a small status badge, and a divider before the date/time footer. Business context stays visible. Date labels use day/month/year; times retain the app's 24-hour convention, including 24:00 for midnight. Overnight finish dates are explicit to avoid an ambiguous time range. The card follows light/dark theme tokens and wraps on narrow screens.

Due/paid/refund information uses one compact line. Collect appears only with collection permission and a positive, non-cancelled balance. The card still opens booking details; Collect opens the collection action. Admission session cards retain the existing attendance controls and admission-details route. No check-in or cancellation behavior is changed.

The existing outstanding-balances API response now includes customer_phone, local_end, total_minor and option_name, allowing Home payment cards to show the same information with no additional network requests. The new fields are optional in the repository-facing models, so older responses remain usable (phone/end information is omitted when unavailable). Bookings/Calendar already have those details in their normal booking data. No database migration is needed.

## Deploy the additive API update yourself

Existing migrations for earlier features must already be applied. Save a copy of the currently deployed function, then run these in order and stop on failure:

```sh
cd "/Users/albinosiby/Tatos Dev/booking"
npm --prefix backend run build
npm --prefix backend run edge:check
npm --prefix backend run edge:build
npx supabase functions deploy booking-api --project-ref scwwkaywewecspsrskft --use-api --no-verify-jwt
curl -sS "https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/health"
```

Expected revision: `2026-10-21-booking-cards`. Keep existing secrets and internal Supabase Auth verification unchanged. Reload the updated Flutter source. Check a paid booking, unpaid booking with Collect, cancelled booking without Collect, cross-midnight booking and staff without collection permission on all three pages. No APK was built, phone installation performed, live data changed or API deployed.

If reverting the function, use the prior saved version. The new card tolerates the older outstanding-response shape, but Home phone and finish-time fields will be absent. No schema recovery is required.
