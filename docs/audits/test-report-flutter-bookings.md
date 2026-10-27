# Flutter field/screen test report: bookings area

Scope: `lib/modules/` bookings, booking_blocks, booking_website, customers, dashboard, messages, notifications.
No lib or existing test files were edited. New files only: `test/field_{bookings,booking_blocks,booking_website,customers,messages,notifications,dashboard}_test.dart`.

## Summary

| File | Passing | Skipped (BUG) |
|---|---|---|
| field_bookings_test.dart | 91 | 9 |
| field_booking_blocks_test.dart | 25 | 3 |
| field_booking_website_test.dart | 22 | 5 |
| field_customers_test.dart | 12 | 2 |
| field_messages_test.dart | 18 | 4 |
| field_notifications_test.dart | 7 | 1 |
| field_dashboard_test.dart | 16 | 0 |
| **Total** | **191** | **24** |

- Written: 215 test cases (table-driven loops counted as one case per generated test). Passing: 191. Skipped as bugs: 24 covering 23 distinct issues (BUG-1 to BUG-21, BUG-23, BUG-24; BUG-20 has two skipped cases; id 22 unused).
- Every BUG skip was confirmed by temporarily un-skipping a copy of the file and watching it fail (bookings, blocks, website, customers, messages, notifications). Website BUG-20 was confirmed by direct failing runs (overflow 36px and 64px). The temp copies were deleted.
- Website widget tests are slow on a loaded machine (several minutes); other files run in under a minute. Under heavy CPU load (load average above 500) one customers debounce test was flaky; it now polls for completion.
- Not covered: live REST repositories, real date/time picker dialogs for payment time, booking agenda/list calendar screens beyond the cubit, Firebase repository internals.

## Issues

| ID | Sev | Screen | Field / input | Expected | Actual | Location | Suggested fix |
|---|---|---|---|---|---|---|---|
| BUG-1 | Medium | New booking, booking detail customer edit | Customer phone | `-------`, `(((((((`, `+ ()-()`, `12345 6` rejected | Accepted (regex counts separators as digits; also 6-digit with a space) | lib/modules/bookings/models/booking_models.dart:442-445 | Count digits (7-15) like the website phone validator |
| BUG-2 | Low | same | Customer phone | More than 15 digits rejected | Up to 25 digits accepted | booking_models.dart:444 | Enforce 7-15 digits |
| BUG-3 | Low | same | Email, whitespace only | Treated as empty (toJson sends null) | Rejected with "Enter a valid email" | booking_models.dart:446 | Use `email.trim().isNotEmpty` |
| BUG-4 | Low | same | Customer name | Single emoji or zero-width characters rejected | Accepted (length in UTF-16 units; 51 emoji rejected as >100) | booking_models.dart:442 | Count `characters`, strip zero-width |
| BUG-5 | Low | New booking | People count | Sensible upper bound | `99999999` accepted, sent to quote and availability | lib/modules/bookings/models/booking_form_model.dart:selection; cubit people() booking_form_cubit.dart:~470 | Cap by capacity / 1000 |
| BUG-6 | Low | New booking | Date (cubit) | Past or malformed date refused | `date('2020-01-01')`, `date('not-a-date')` stored; only the picker limits | lib/modules/bookings/cubit/booking_form_cubit.dart:~415 | Validate against business.today and format |
| BUG-7 | Medium | New booking | Time (cubit) | Malformed time ignored | `time('abc')` stored; `draft.startMinute`/`endTime` then throw FormatException | booking_form_cubit.dart:~420; booking_form_model.dart:`startMinute` | Validate `HH:mm` in `time()` |
| BUG-8 | Low | New booking, reschedule | Notes, reschedule reason | Length cap (as discount reason and payment reference have) | 10001 chars accepted client-side | booking_form_cubit.dart:512-513 | Cap notes/reason (e.g. 500/200) |
| BUG-9 | Low | Booking detail | Status/refund/collection reason | Length cap | No maximum | lib/modules/bookings/cubit/booking_detail_cubit.dart:~240 | Cap at 200 |
| BUG-10 | Medium | Block slots | Custom start/end | Equal start and end refused | `10:00`-`10:00` becomes a 24 hour block (endDate rolls to next day) | lib/modules/booking_blocks/models/slot_block_models.dart:endDate, validation | Reject start == end |
| BUG-11 | Low | Block slots | Date (cubit) | Past/malformed refused | Accepted; `endDate` then throws FormatException on build | lib/modules/booking_blocks/cubit/slot_block_cubits.dart:~224 | Validate in `date()` |
| BUG-12 | Low | Block slots | Launch date | Malformed launch date falls back to today | String compare: `garbage` > `2030-...` is used | slot_block_cubits.dart:~155 | Parse with DateTime.tryParse |
| BUG-13 | Low | Website settings | Min notice / advance days | Invalid number flagged immediately | Invalid input dropped in onChanged; Save stays disabled with no error until another edit | lib/modules/booking_website/screens/website_settings_screen.dart:~490-520 | `autovalidateMode: onUserInteraction` |
| BUG-14 | Low | Website settings | Social links | `https://..`, `https://.com`, `https://a b.com` refused | Accepted (only `host.contains('.')`) | website_settings_screen.dart:~470-480 | Validate host labels, no spaces |
| BUG-15 | Low | Website settings | Website name | Reserved names (www, api, admin, mail) refused | Pass client validation | lib/modules/booking_website/models/website_settings.dart:135 | Add reserved list (server must also) |
| BUG-16 | Low | Customers | Search query | Clamped to 50 chars | Cubit forwards raw query; limit only on TextField | lib/modules/customers/cubit/customer_cubits.dart:search | Clamp in cubit |
| BUG-17 | Low | Template editor | Body | 6000 characters limit counts characters | Counts UTF-16 units: 3001 emoji refused | lib/modules/messages/models/message_template.dart:validateMessageBody | Use `characters.length` |
| BUG-18 | Low | Template editor | Website URL | `https://exa mple.com` refused | Accepted | lib/modules/messages/cubit/message_cubits.dart:~160 | Stricter host check |
| BUG-19 | Low | Template editor | Name on copy | Prefilled name within 80 chars | `<name> (copy)` unbounded; 75+ char names prefill invalid | message_cubits.dart:~118 | Truncate source name |
| BUG-20 | Medium | Website settings | Layout at 320x568, 2.0 text | No overflow | RenderFlex overflow 36px (long values) and 64px (load-error state) | website_settings_screen.dart:775-805 (AppPage fixedBody/header; exact widget not isolated) | Make header/error body scrollable |
| BUG-21 | Low | Push notifications | recipient_user_id | Whitespace-only refused | `"   "` accepted | lib/modules/notifications/models/booking_notification.dart:~28 | `trim().isEmpty` |
| BUG-23 | Medium | Template editor | Layout at 320x568, 2.0 text with placeholder error | No overflow | RenderFlex overflow 87px right | lib/modules/messages/screens/template_editor_screen.dart:~118-135 | Wrap error/row content |
| BUG-24 | Low | Customers | Search `"   "` | Treated as no search ("No customers yet") | Shows "No matching phone numbers" (untrimmed query stored) | customer_cubits.dart:search; customers_screen.dart:~85 | Trim in `search()` |

## Screens and fields covered

- Bookings: new booking form cubit and customer fields widget (name, phone, email, notes), people count, date button/picker clamping, time/end-time, discount editor widget (amount/percent/reason, 320px and 2.0 scale), payment editor widget (amount, reference, add cap 20, huge values), payment draft and entry model (zero, negative, decimal, huge, unicode, future time, overpay), discount model, price parser, double-tap confirm/review, booking detail cubit (collection amounts, status reason, customer edit, double submit).
- Booking blocks: new block cubit (date, custom time regex, overnight, space selection, grid picks over booked/blocked/past cells, double confirm, edits frozen while saving), list cubit (unblock double tap, date/business), screens at 320x568 with 1.0 and 2.0 text (grid, review, forbidden, no businesses, empty, long names).
- Booking website: address validator, social link normaliser, cubit (address save, double save, photo size boundaries, picker failure), screen fields (title, phone, Instagram link, min notice, advance days, maxLength clipping), save failure, load failure, long-value layouts.
- Customers: search debounce and odd queries, load more double tap, error mapping, list/detail screens (long, emoji, RTL names; empty, error, loading; 50-char field clamp).
- Messages: body validator, render, money formatter, editor cubit (name 2-80, website URL, double save), preview cubit (share/copy double tap, invalid template), editor screen small screen.
- Notifications: payload parsing (UUID, kinds, types), account states (unverified, recovery, failure, 150 events).
- Dashboard: greeting card name/organization handling, RTL/emoji/long text, small screen, 3.0 text scale, corrupt logo bytes.
