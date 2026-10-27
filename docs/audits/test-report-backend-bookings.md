# Backend field-value and module test report: bookings area

Scope: `backend/src/bookings`, `slot-blocks`, `common` (operating hours, minimum booking), `website` (settings, public booking site, payments, images, design), `messages`, `invoices` (booking invoices and invoice templates), and the pure rules in `admissions/admission.rules.ts`.

Method: every request schema, controller parameter and service guard in these modules was read, then boundary and invalid-value tests were written against the service layer (PGlite in-memory database, no network, no migrations applied, no source or existing test file edited). Failures that are real defects are kept as `{ todo: 'BUG-<n>' }` tests so the suite stays green and runnable. Bug IDs belong to this report only (the `BUG-2` slot was used and retired because the test proved the behaviour correct).

Run a file with `cd backend && npx tsx --test test/<file>.test.ts`.

## Summary

| Metric | Count |
| --- | --- |
| New test files | 8 |
| Tests written | 139 |
| Passing | 119 |
| Failing unexpectedly | 0 |
| Failing = confirmed bugs (`todo`, suite stays green) | 20 tests covering 16 distinct bugs |

The last full run (all eight files together) was 139 tests, 118 pass, 1 fail, 20 todo. The one failure was my own far-future date expectation; it exposed the end-of-range part of BUG-7, the test was corrected and re-run (passes, and BUG-7 now also covers `9999-12-31`).

| File | Tests | Todo (bugs) |
| --- | --- | --- |
| `backend/test/field-bookings.test.ts` | 43 | 7 (BUG-1, 3, 4, 5, 6, 7, 14) |
| `backend/test/field-slot-blocks.test.ts` | 11 | 0 |
| `backend/test/field-common.test.ts` | 15 | 3 (BUG-7, 8, 9) |
| `backend/test/field-messages.test.ts` | 14 | 4 (BUG-10, 11, 12, 14) |
| `backend/test/field-invoices.test.ts` | 12 | 1 (BUG-13) |
| `backend/test/field-website.test.ts` | 23 | 2 (BUG-14, 17) |
| `backend/test/field-website-public.test.ts` | 14 | 3 (BUG-14, 15, 16) |
| `backend/test/field-admissions.test.ts` | 7 | 0 |

## Issues

Severity: Medium = wrong behaviour reachable by normal or unauthenticated callers; Low = edge case or hardening; Info = latent (callers validate today).

| ID | Sev | Module | Field / input | Expected | Actual | Cause (file:line) | Suggested fix |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BUG-14 | Medium | all text fields (bookings, website, messages, public guest) | any free text containing `\u0000` (booking `notes`, `customer.name`, `payment.reference`, discount `reason`, status `reason`, list `q`, template `name`/`body`/`website_url`, website `title`/`description`/`instructions`/`cancellation_policy`/`hero_heading`/space `rules`, public guest `customer.name`) | 4xx validation error | Postgres `invalid byte sequence for encoding "UTF8": 0x00` (or `unsupported Unicode escape sequence` for JSONB columns) surfaces as an unhandled 500. Reachable unauthenticated through `POST /public/v1/sites/:slug/bookings` | No NUL filtering in any zod string schema; `common/errors.filter.ts:36` only maps `23505` | Add a shared `safeText` zod refinement rejecting `\u0000` and use it for all free-text fields, and/or map Postgres `22021` and `22P05` to 400 in `errors.filter.ts` |
| BUG-7 | Medium | bookings / common | `selection.date`, list/dateCounts/outstanding/collections `date`, `date_until` with year `0000`-`1499` or `9999-12-31` | 422/400 | `quote` and `availability` throw `RangeError: Invalid time value` (500); `list`, `dateCounts`, `outstanding`, `collections` throw Postgres `date/time field value out of range: "0000-01-01"` (500). `9999-12-30` 23:00 and `9999-12-31` also crash `zonedTime` | `bookings/booking.validation.ts:2-10` (`calendarDate` accepts every ISO date); crash sites `bookings/booking.inventory.ts:45-60` (`localStamp`, `zonedTime`) and the SQL date casts in `booking.service.ts` | Restrict `calendarDate` to a supported window (slot blocks already use 2000-2100: `slot-blocks.service.ts:19-22`) |
| BUG-3 | Medium | bookings | `customer.id` with different posted `name`/`phone` on `create` and `editCustomer` | snapshot equals the stored customer (or posted values rejected) | `customer_id` points at customer A but `customer_snapshot` (used by invoices, lists, notifications) holds the posted name/phone, so the booking shows "Someone Else" for customer "Real Person" | `bookings/booking.service.ts:500` and `:742` (`{ ...v.customer, id: customerId }`) | When `customer.id` is set, load the customer row and snapshot its stored name/phone/email, ignoring posted ones |
| BUG-15 | Medium | website | `customer.phone` formatting on public booking | per-phone limit (3 per hour) applies to one number however it is written | `9555000222`, `+919555000222`, `+91 95550-00222` hash differently, so 5 of 6 variants were accepted (limit is 3). Only the site-wide cap of 30/hour remains | `website/website.service.ts:1116` (hash of raw digits with leading zeros stripped, no country-code normalisation) | Normalise to E.164 or the last 10 digits (strip country code) before hashing |
| BUG-16 | Low | website | `POST /public/v1/sites/:slug/bookings` on an unpublished or draft slug | 404 identical to an unknown slug (`catalog` already does this) | 409 "Online bookings are paused" reveals that the address exists | `website/website.service.ts:1037` (`site(..., allowHidden=true)`), status check after the replay lookup | Return 404 for `unpublished`/`draft` unless the command is a replay of an accepted booking; keep 409 only for `paused` |
| BUG-13 | Low | invoices | `generate` by staff with only `view_bookings` | requires a write permission (it consumes invoice numbers and writes rows) | succeeds; any staff who can read the booking can issue invoices | `invoices/invoices.service.ts:268-275` (only `member()` plus `bookings.detail()` read access) | Require `manage_bookings` or `collect_payments` (confirm intended policy) |
| BUG-5 | Low | bookings | `list` `q` containing `%` or `_` | literal match | wildcard: `q=%` returns every booking, `A%e` matches "Alice Anderson" | `bookings/booking.service.ts:846,916,921` (`"%"+q+"%"` unescaped) | Escape `\`, `%`, `_` and add `ESCAPE '\'` |
| BUG-6 | Low | bookings | `GET /v1/bookings/customers?q=1&q=2` (repeated param, arrives as array) | 4xx or ignore | `TypeError: search.replace is not a function` (500) | `bookings/booking.service.ts:941`, `booking.controller.ts` (`@Query("q") q = ""`) | `z.string().max(100).catch("")` on the controller input |
| BUG-1 | Low | bookings | `selection.people` > 1 for court/turf bookings (admin) | rejected like the public site does ("only required for pool bookings") | accepted and stored (e.g. 9999 people on a court) | `bookings/booking.inventory.ts:296-302` (people used only by pool/hall), `booking.validation.ts` `selectionSchema.people` | Reject `people !== 1` for non-pool, non-hall types in `buildQuote` |
| BUG-4 | Low | bookings | `editCustomer` on a cancelled, completed or no-show booking | refused (final records are immutable) | accepted; customer snapshot and notes of a final booking can be rewritten | `bookings/booking.service.ts:717-750` (no status check, unlike reschedule/status) | Require `status = 'confirmed'`, or allow notes only |
| BUG-10 | Low | messages | custom template named `Booking confirmation` | refused as a duplicate of the built-in template | accepted; two indistinguishable entries | `messages/messages.service.ts:165` (duplicate check ignores the built-in name at `:70`) | Include the built-in name in the duplicate check |
| BUG-11 | Low | messages | `website_url` = `https://user:secret@example.com` | refused (website social links refuse credentials) | accepted and sent to customers verbatim | `messages/messages.service.ts:114-126` | Reject `username`/`password` in the parsed URL |
| BUG-12 | Low | messages | `website_url` with trailing space, newline or tab (`https://a.com\n`) | trimmed or refused | stored with the control character (the `new URL` check ignores trailing whitespace) | `messages/messages.service.ts:114-126` | `.trim()` before validation |
| BUG-17 | Low | website | PNG/JPEG/WebP upload whose bytes after the header are arbitrary (e.g. valid PNG signature + IHDR followed by `<script>...`) | rejected or fully decoded | accepted and served from the public domain (mitigated by fixed `Content-Type` and `nosniff`; upload is owner-only) | `website/website.images.ts:31-100` (only signature and dimensions are read) | Validate chunk structure (PNG IDAT/IEND, JPEG EOI, WebP size) or re-encode |
| BUG-8 | Info | common | `fitsOperatingInterval(..., duration < 0, ...)` | `false` | `true` (callers validate `duration >= 1` today) | `common/operating-hours.ts:106-119` | Guard `duration > 0` and finite inputs |
| BUG-9 | Info | common | `minimumBookingPrice` with a negative tariff | `null` | returns a negative price (`-200`); schemas currently forbid negative tariffs | `common/minimum-booking.ts:17-21` | Return `null` when `base < 0` or non-finite |

## Behaviour confirmed correct (no bug)

- Zod 4 counts code points, so a single emoji is rejected by the 2-character name minimum.
- Slug input is trimmed before validation (`"abc\n"` becomes `abc`); an empty `preview` value is treated as no preview.
- Cross-tenant access is consistently denied (404 or 403) and leaves data untouched for bookings, payments, status, reschedule, customer edit, slot blocks, message templates, invoices, website settings, images and QR.
- Idempotency keys behave correctly: identical retry returns the original result, changed payload returns 409, parallel duplicates create exactly one record, keys are independent per organisation.
- Overlap logic: identical, containing, partial and adjacent intervals, other spaces, bookings versus blocks, DST gaps (nonexistent and ambiguous local times are rejected) and 23h/25h all-day blocks.
- Staff scoping (unassigned, wrong space, wrong business, view-only, finance-only, collector cannot refund, revoked membership) is enforced on every read and write checked.

## Fields covered

Bookings (`field-bookings`): `selection.business_id`, `resource_id`, `option_id`, `date`, `time`, `duration_minutes`, `people`, `discount.type/value/reason`; `exclude_booking_id`; `command_key`; `quote_token`; `customer.id/name/phone/email`; `notes`; `payments[].method/amount_minor/reference/received_at/account_id` and list size; reschedule `version/reason/selection`; payments `kind/reason/payments/version`; status `status/reason/version`; editCustomer `customer/notes/version`; list `date/date_until/overlap/resource_id/business_id/q/status/cursor`; dateCounts range 1-62 days; customers lookup; customerDirectory `q/after`; customerHistory `cursor/id`; dashboard `business_id`; outstanding and collections `business_id/date/today/cursor`; commandResult key.

Slot blocks (`field-slot-blocks`): `command_key`, `business_id`, `resource_ids` (empty, duplicate, 100 max, foreign), `date` (2000-2100, past), `all_day`, `start_time`, `end_time`, `end_date`; list `business_id/date/cursor`; slots `resource_ids` string form; unblock `id` and body; overlap, adjacency, bookings, DST, scopes, tenants.

Common (`field-common`): `hoursSpan`, `hoursWithin`, `windowsOverlap`, `windowApplies`, `weeklyWindowApplies`, `fitsOperatingInterval`, `allDayDatesCover`, `acceptsMinimumDuration`, `minimumBookingPrice`, `calendarDate`, `clock`, `selectionSchema`, `paymentSchema`, `customerSchema`, `moneyStatus`, `addDate`, `localStamp`, `zonedTime`.

Website (`field-website`, `field-website-public`): `slug`, `version`, `title`, `description`, `contact_phone`, `instructions`, `cancellation_policy`, `publish_logo`, `notice_minutes`, `advance_days`, `hero_heading`, `social_links`, `card_descriptions`, `business_ids`, `spaces[].business_id/resource_id/visible/notice_minutes/advance_days/rules/payment_required/payment_percentages`; publication transitions; preview tokens (format, expiry, ownership, re-issue, revoke on save); image `kind/business_id/resource_id/content_type/base64/version`, PNG/JPEG/WebP dimension and size limits, slot and 40-photo caps, removal and owner/public image ids; UPI `upi_id`, `qr`, `version`; payment policy and `transaction_id`/`percentage`; public selection fields, booking window and notice period, pool participants, hidden spaces, guest `name`/`phone`, `command_key`, `quote_token`, paused/preview/draft states, per-phone and per-site limits, cross-site ids.

Messages (`field-messages`): `command_key`, `name`, `body` (placeholders, braces, 6000 limit, emoji length), `website_url`, 50-template cap, primary `id`, remove `id`, catalog role matrix, tenant isolation.

Invoices (`field-invoices`): settings `enabled/template`, preview `template`, generate `command_key` and booking id, duplicate and parallel generation, numbering, monetary boundaries (zero total, full discount, paid, cancelled), unicode/emoji/markup/maximum-length customer, notes and discount reason through PDF rendering, download id, disabled state, scopes, tenants.

Admissions rules (`field-admissions`): enrolment schema fields, `expiryFrom`, `fixedDates`, `validSwimmingDuration`, `interval` (operating hours, overnight, 24-hour spaces, DST), small helpers. The admissions service itself (check-in, attendance, plans) was not covered in this pass.

## Not covered

- Admissions service endpoints (`admission.service.ts`, 1,900 lines); only its pure rules were tested.
- HTTP transport behaviour (Nest pipes, auth guard, throttler); tests exercise the service layer, so `ParseUUIDPipe` on route ids is assumed (service-level malformed ids are still refused).
- Invoice PDF visual layout, and notification delivery of booking messages.
- Behaviour on a real PostgreSQL server (all runs used PGlite; error text for NUL bytes and out-of-range dates matches Postgres).
