# Backend field-value test report: finance, admissions and facility modules

Scope: accounts (bank accounts, opening balances, entries, transfers, reversals, staff cash settlements,
website payment details), expenses, income, admissions (pool plans: tracked and membership-only, payments,
refunds, attendance, check-in, session changes, coach endpoints), and the court, turf, hall and pool
configuration modules.

No source or existing test file was edited. All tests are new files that use an in-memory PGlite database.
No migration was applied to any database.

## Summary

| File | Tests | Pass | Fail | Todo (known bug) |
|---|---|---|---|---|
| `backend/test/field-accounts.test.ts` | 55 | 51 | 0 | 4 |
| `backend/test/field-expenses.test.ts` | 30 | 26 | 0 | 4 |
| `backend/test/field-income.test.ts` | 17 | 14 | 0 | 3 |
| `backend/test/field-admissions-flows.test.ts` | 43 | 39 | 0 | 4 |
| `backend/test/field-court.test.ts` | 18 | 17 | 0 | 1 |
| `backend/test/field-turf.test.ts` | 17 | 16 | 0 | 1 |
| `backend/test/field-hall.test.ts` | 16 | 15 | 0 | 1 |
| `backend/test/field-pool.test.ts` | 18 | 17 | 0 | 1 |
| Total | 214 | 195 | 0 | 19 |

Run one file at a time, for example `cd backend && npx tsx --test test/field-accounts.test.ts`.
Each `node:test` "test" here sweeps many values, so a test is a field group, not one assertion.
The suite stays green: every failing assertion is wrapped in `{ todo: 'BUG-n' }`.
The 19 todo tests map to 9 distinct defects (BUG-4 repeats across 8 files; BUG-8 has 2 tests).

File name note: another run created `backend/test/field-admissions.test.ts` (pure rule helpers) while this
work was in progress and overwrote the first version of the admissions flow tests. The flow tests were
recreated as `field-admissions-flows.test.ts`. Do not merge them by name.

## Issues found

Severity: Medium means wrong data or a server error on user-controllable input; Low means a UX, consistency
or hardening gap.

| ID | Sev | Module | Field / input | Expected | Actual | Cause (file:line) | Suggested fix |
|---|---|---|---|---|---|---|---|
| BUG-1 | Low | accounts | `POST /v1/accounts/banks` `bank_name` = `""` or whitespace | 400 (bank name is shown in the UI and reports) | Accepted and stored as empty string | `backend/src/accounts/accounts.validation.ts:38` (`.trim().max(100)` has no `.min`) | `.min(2)` (or `.min(1)`) |
| BUG-2 | Medium | accounts | Transfer whose source line account is the "Unassigned bank receipts" clearing account | 400, same as every other entry kind (clearing is a holding account for unrouted receipts) | Accepted: money is moved out of the clearing account into a real account | `backend/src/accounts/accounts.service.ts:551-557` (clearing check is wrapped in `v.kind !== "transfer"`; only the destination is checked at `:565-571`) | Reject `a.kind === "clearing"` for the transfer source line too |
| BUG-3 | Low | accounts / staff cash | `GET /v1/staff-cash/history` with `from` after `until`, or an unbounded range | 4xx like the other finance filters ("Choose a date range up to ten years") | Returns empty list; no range cap beyond the 500-row limit | `backend/src/accounts/staff-cash.service.ts:264-267` | Reuse the `filterSchema` refine (from <= until, max range) |
| BUG-4 | Medium | accounts, expenses, income, admissions, court, turf, hall, pool | A NUL byte (`\u0000`) in any free-text field: entry `reason`/`category`/`reference`, expense and income category `name`, customer `name`, court/layout/hall/pool `name` | 4xx validation error | PostgreSQL error 22021 "invalid byte sequence for encoding UTF8: 0x00" surfaces as HTTP 500 | No NUL guard in any string schema (`accounts.validation.ts`, `expenses.validation.ts:25`, `bookings/booking.validation.ts:48`, `court/turf/hall/pool` `name`); `backend/src/common/errors.filter.ts` only maps `23505` | Add a shared `noNul` refine to the string schemas, or map SQLSTATE `22021`/`22P05` to 422 in `ErrorsFilter` |
| BUG-5 | Low | expenses, income | `POST /categories` `{name, active:false}` | Category created archived | Category is always created active (the `active` field is validated then ignored) | `backend/src/expenses/expenses.service.ts:123-127`, `backend/src/income/income.service.ts:89-93` (INSERT has no `active` column) | Insert `active` from the payload |
| BUG-6 | Medium | expenses, income | `PATCH /categories/:id` `{name}` on an archived category | Stays archived (partial update) | Silently re-activated, so new entries can use a category the owner archived | `backend/src/expenses/expenses.validation.ts:26` (`active` defaults to `true`) combined with `expenses.service.ts:117` and `income.service.ts:83` (`SET name=$1,active=$2`) | Make `active` optional on PATCH (no default) and only update when provided |
| BUG-7 | Low | expenses | `GET /v1/expenses/overview` `total_minor` type | Number, as the income and accounts overviews return | String (bigint `SUM` is passed through as returned) | `backend/src/expenses/expenses.service.ts:210` (`total_minor: r.total_minor`); `list` rows' `amount_minor` also come back as strings | `Number(r.total_minor)` like `income.service.ts` does |
| BUG-8 | Low | admissions | `GET /v1/admissions?q=%` or `_`, and `GET /v1/admissions/customers?q=%%%` | `%` and `_` match literally (accounts/expenses/income escape them) | Wildcards: `q=%` lists every admission, `q=%%%` lists up to 20 customers | `backend/src/admissions/admission.service.ts:236` and `:1164-1165` (no escaping). Same pattern in `backend/src/bookings/booking.service.ts:846,916,920,921` (outside this audit) | Escape with `q.replace(/[\\%_]/g, "\\$&")` as `accounts.service.ts:761` does |
| BUG-9 | Medium | admissions | `POST /:id/sessions/:visitId/change` `action:"reschedule"` to a date after `expires_on` or before `starts_on` | 400 "Choose a future session within admission validity" | Accepted; the session is moved outside the plan validity window | `backend/src/admissions/admission.service.ts:1746-1747` compares a `YYYY-MM-DD` string with `a.starts_on` / `a.expires_on`, which the driver returns as JS `Date` objects, so `string < Date` and `string > Date` are always false. `common/database.ts` registers no date type parser. The same pattern is at `:580`, `:1463`, `:1528-1529`, `:1537` and `:1782` (not individually exercised) | Parse `date` columns as strings (pg `types.setTypeParser(1082, v => v)` and the PGlite equivalent), or normalise with `toISOString().slice(0,10)` before comparing |

### Behaviour that looks intentional but is worth a decision (not marked as bugs)

- Transfers have no overdraft guard: moving more than the source balance is accepted and leaves a negative
  balance (characterisation test: `transfer: no overdraft guard`).
- Draft facility configurations accept plans with `expiry_mode: "fixed_date"` and no date, and past expiry
  dates. Activation (`assertPoolComplete`, `assertCourtComplete`) rejects both. This is covered by tests.
- Admission `customer_snapshot` takes name, phone and email from the request even when `customer.id` is an
  existing customer (the bookings module behaves the same way).
- Payments and refunds on a cancelled or deleted admission are not blocked (documented behaviour for dues).

## Fields covered

Every row below was tested with: empty, whitespace, null, wrong type, missing key, unknown key (all schemas are
`.strict()`), negative, zero, decimals, NaN / Infinity (as numbers and strings), max and max+1, huge numbers
(`Number.MAX_SAFE_INTEGER`, `1e21`), unicode, SQL-like text, invalid enums, past and future dates, duplicate
and parallel submit, role denial and cross-tenant access, unless the row says otherwise.

### Accounts (`field-accounts.test.ts`)
- Bank account create: `command_key`, `name`, `bank_name`, `account_number` (6-34 ASCII digits, leading zeros,
  Arabic-Indic digits, padding), `last_four`, `opening_minor` (+/-1e11 bounds, decimals, NaN), `opening_at`
  (offset required, 2000-01-01 boundary including timezone offset, now+60s), `is_primary`.
  Idempotent replay, changed payload conflict, cross-tenant key reuse, owner-only.
- Bank account update: `name`, `is_primary` (literal true), `archive` (literal true), cash/clearing/foreign/archived
  targets, primary cannot be archived, archived account cannot receive entries.
- Cash opening: `opening_minor`, `opening_at`, set-once semantics, exact retry vs conflicting retry.
- Payment routes: `method`, `business_id`, `resource_id`, `account_id` (cash, clearing, foreign, unknown), clear route.
- Entries (income, expense, transfer): `kind`, `amount_minor` 1..1e8, `lines` (0, 1, 20, 21), 20 x max stays exact
  in bigint, `category`, `reason`, `reference`, `occurred_at` (format, future, pre-2000, before account opening),
  method vs account kind matrix, `business_id`/`resource_id`, `expense_category_id`, `income_category_id`,
  `to_account_id`, `command_key` idempotency (sequential, parallel, other actor, other tenant), permission matrix
  per kind, shared entries owner-only, unassigned scope.
- Transfers: shape rules, conservation of money, not counted as income/expense, cash-bank, reversal restores both
  sides, overdraft behaviour, clearing source (BUG-2).
- Reversals: `reason`, `command_key`, unknown, foreign, reversal-of-reversal, double reversal, parallel reversal,
  owner-only, admission payments cannot be reversed here.
- Filters: `from`, `until`, 3660-day limit, `cursor`, `kind`, `q` (wildcards, SQL text), id filters, unknown key,
  foreign ids, permission denial.
- Website payment details: `version`, `upi_id`, `qr.base64`, `qr.content_type`, stale version, owner-only.
- Staff cash: `settle` (`command_key`, `direction`, `amount_minor` 1..1e8, `expected_balance_minor`, `note` 300 chars,
  unknown key, owner/foreign/unknown membership ids, over-collect, wrong direction, stale balance, replay,
  conflicting replay, key reuse across staff, concurrent over-collection), `me` (`date`), `history` (`from`/`until`).

### Expenses (`field-expenses.test.ts`)
- Categories: `name` (2..80, trim, unicode, SQL text, NUL), `active`, case-insensitive uniqueness, rename
  collision, foreign/unknown ids, owner-only, catalog access.
- Create: kind and category id rules, amounts 1..1e8, split lines sum exactly, text fields, dates, ids, idempotency,
  roles, cross-tenant accounts, archived category.
- Reads: `from`/`until`, 366-day limit, `cursor`, ids, `q` wildcards, role and tenant isolation, reversal netting.
- Attachments: `id`, `name` (0, 180, 181, traversal, unicode), `content_type` allow-list, `size_bytes` 1..15 MiB,
  object path built only from ids, id hijack across event and tenant, 10-file limit, complete / retrieve / remove
  lifecycle, recording-staff rule.

### Income (`field-income.test.ts`)
- Categories (same checks as expenses), create (`income_category_id`, amounts, text, dates, split cash+bank
  sums), idempotency, roles, filters including `source` (`bookings`, `admissions`, uuid, invalid), foreign source
  id, `q` wildcards, overview number types, reversal.

### Admissions (`field-admissions-flows.test.ts`)
- Preview/create: `business_id`, `resource_id`, `plan_id`, `starts_on`, `mode` vs plan tracking type, `weekdays`,
  `time`, `duration_minutes` (30-minute grid above minimum, 1440 cap), `customer.{id,name,phone,email}`,
  `payments[]` (count, amount, method, `received_at`, `reference`, `account_id`), `renewed_from`,
  `preview_token`, `command_key`; overpayment, account/method mismatch, foreign customer, parallel submit.
- Payments: `version`, `kind`, `reason`, amount boundaries, collection > outstanding, refund > paid, refund reason
  and owner-only, nothing left to refund, duplicate and parallel submit, ledger signs, tenant and role denial.
- Cancel, delete membership, check-in (union body shape), attendance, session change, list/expired/customers
  search, detail access, coach conflicts, coach classes.
- Not covered: court admission flows (only pool plans are exercised end to end; court plan fields are covered in
  the court configuration tests).

### Court / Turf / Hall / Pool (`field-court|turf|hall|pool.test.ts`)
- Names (length, whitespace, case-insensitive duplicates, unicode, SQL text), counts and maxima (50 courts, 10
  grounds, 60 offerings, 50 halls, 30 pools, 12 sessions, 40 tariffs, 50 plans), `environment`, `surface`,
  `amenities`, capacities and seated capacity, `durations`, `default_duration_minutes`, buffers 0..240, prices
  (0..1e8, null, decimals, NaN, Infinity, strings), operating and tariff hours (clock format, days, overnight,
  24-hour, seasonal date windows, Feb 30, leap day), tariff overlap and fit, pricing rules (turf), package prices
  and weekday/seasonal overlap (hall), pool depths in 0.01 steps (0.07, 1.15, 4.35 and other float traps),
  group offers (`exact`/`up_to`/`at_least`, people vs capacity), plans (allowance, expiry combinations, fixed
  date, class seats and duration, coach), completeness checks for activation, quote helpers (garbage
  date/time/duration/people return null, rounding and exactness, zero vs null price), expiry arithmetic.
- Service `configure`: `version` (0, negative, decimal, string, null, stale, replay), body shape and unknown
  keys, atomic rejection (version and resources unchanged), wrong business type, foreign tenant, unknown id,
  non-owner, stolen identifiers, parallel saves, active configuration cannot be made incomplete, coach
  validation (pool).
