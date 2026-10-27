# Flutter finance and facility field/value test report

Scope: lib/modules accounts, expenses, income, admissions, court, turf, hall, pool (coaching: see gaps).
No lib or existing test files were edited. No APK, device or migration work was done.

## New test files
| File | Focus |
|---|---|
| test/field_validation_test.dart | Validation.priceMinor/name/email/password, pool/court shared validators |
| test/field_pool_test.dart | Pool model: name, capacity, depth, durations, buffers, hours, tariffs, offers, plans, validity arithmetic, json |
| test/field_pool_screens_test.dart | Pool widgets at 320x568: details form, pricing field, offers/plans fields, every section at 2.0 text scale, double tap |
| test/field_court_test.dart | Court model: names, surface, durations, buffers, hours, tariffs, plans, json |
| test/field_hall_test.dart | Hall model: names, capacity/seated, amenities, hours, tariffs, sessions/full-day packages |
| test/field_turf_test.dart | Turf model: names, formats, prices, hours, price rules, sports completeness |
| test/field_accounts_test.dart | FinanceEntryCubit (income/expense/transfer), BankAccountCubit, opening balance, money formatting, search filter, screens at 320x568 / 2.0 text |
| test/field_expenses_test.dart | ExpenseFormCubit, invoices, double submit, category dialog, ExpenseFormScreen at 320x568 |
| test/field_income_test.dart | IncomeFilter/Summary/Cubit, IncomeScreen states (populated/empty/error/no access/huge) |
| test/field_admissions_test.dart | Customer fields, payment drafts and balance maths, plan expiry arithmetic |

Counts (last runs): validation 19 pass/1 skip; pool 67/2; pool screens ~27 pass/1 skip; court 35/0; hall 42/2; turf 33/3; accounts ~65 pass/6 skip; expenses ~51 pass/6 skip; income 20/3; admissions 20/3 (verified). Skips are all `BUG-n`.
Roughly 380 test cases, about 24 skipped for 21 bugs.

Verification: every skipped test was run unskipped and confirmed failing, except BUG-13/14/15/17 (expenses file) and BUG-19/20 (income file); those could not be re-verified because the disk filled up (234 MB free) during the final runs. Treat those six as probable, not proven.

## Issues
| ID | Sev | Screen | Field/input | Expected | Actual | Location | Suggested fix |
|---|---|---|---|---|---|---|---|
| BUG-1 | Low | Pool/Court/Hall setup | capacity, seats, allowance, depth ints | "0x10", "+5" rejected | int.tryParse accepts hex and plus sign | pool_editors.dart:13, court_editors.dart:13, hall_editors.dart:13 and models (int.tryParse) | Validate with RegExp(r'^\d+$') |
| BUG-2 | Low | Pool plans | fixed expiry date | Past date rejected | Accepted (court plans use `today`) | pool_configuration.dart PoolConfiguration.validate plans loop | Pass `today` like CourtPlan.validate |
| BUG-3 | Medium | Pool pricing step | price field of disabled pool | Blank allowed (cubit allows) | Field validator blocks Continue with "Enter a valid amount" | pool_pricing_screen.dart:252 | Use `!p.enabled && v.isEmpty ? null : poolPrice(v)` |
| BUG-4 | Low | Hall sessions | session name | Not equal to Full day name | Accepted, two options with same name | hall_configuration.dart:~610 session uniqueness | Include fullDay in the name uniqueness set |
| BUG-5 | Low | Turf grounds/spaces/offerings | names and format | Trimmed in payload | Sent untrimmed (pool/court/hall trim) | turf_configuration.dart TurfGround/TurfLayout/TurfOffering.toJson | `.trim()` in toJson |
| BUG-6 | Low | Turf model | offering durations | 30..1440, unique | 0, negative, huge accepted | turf_configuration.dart validate/validateTurfOffering | Add duration bounds |
| BUG-7 | Low | Turf model | buffers | 0..240 | Unbounded | turf_configuration.dart validate | Add bounds as in pool |
| BUG-8 | Medium | Add expense/income/transfer entry | reason, category, reference | Limits 500/80/200 enforced before send | No maxLength or cubit check; server rejects with generic error | finance_entry_screen.dart:267, accounts_cubits.dart:519 | maxLength + cubit checks |
| BUG-9 | Low | Add bank account | name, bank name | <=100 chars | No limit; server rejects | account_settings_screen.dart:1194, accounts_cubits.dart:306 | maxLength 100 + check |
| BUG-11 | Low | Transactions search | query | Trimmed, max 100, whitespace ignored | Sent as typed; whitespace-only hides Staff cash section; >100 rejected by server | accounts_models.dart FinanceFilter.toJson, accounts_transactions_screen.dart:66 | Trim, clamp to 100 |
| BUG-12 | Medium | Accounts overview | Net card | No overflow at 320px, 2.0 text | Row overflows 60-88px | accounts_overview_widgets.dart:284 | Wrap/Flexible |
| BUG-13 | Low | Add expense | reason, reference | Cubit rejects >500/>200 | Only widget maxLength guards (probable, unverified) | expense_form_cubit.dart save | Add checks |
| BUG-14 | Low | Category dialogs (expenses, income) | name | Message for blank/1 char | Save silently does nothing (probable, unverified) | expenses_screen.dart:87, income_screen.dart:100 | Show validation text |
| BUG-15 | Low | Add expense | single total amount | Capped like split amount (12) | No maxLength (probable, unverified) | expense_form_screen.dart:112 | maxLength 12 |
| BUG-17 | Low | Add expense (split) | amount prefix | Uses org currency | Hardcoded "₹ " (probable, unverified) | expense_form_screen.dart:97 | Use catalog.currency |
| BUG-18 | Medium | Category dialogs, reverse dialog | TextEditingController | Not used after dispose | Disposed right after showDialog returns while dialog animates out; debug assertion storms | expenses_screen.dart:96, income_screen.dart:109, accounts_transactions_screen.dart:~229 | Use a StatefulWidget dialog owning the controller |
| BUG-19 | Low | Income/Expenses charts | day keys | Bad key ignored | DateTime.parse throws (probable, unverified) | income_models.dart bars, expense_models.dart bars | tryParse |
| BUG-20 | Low | IncomeCubit/ExpensesCubit.category | name | Guard blank | Forwards blank/1-char (probable, unverified) | income_cubit.dart:category | Validate in cubit |
| BUG-21 | Medium | Manage categories sheet | duplicate name error | Visible | Error rendered on page beneath modal sheet | expenses_screen.dart:260, income_screen.dart:308 | Show in sheet/snackbar |
| BUG-22 | Medium | Admission form (BookingCustomer) | phone | Needs digits | "-------", "((((((((" accepted | booking_models.dart:444 | Require >=7 digits |
| BUG-23 | Low | Admission form | email | Whitespace-only treated as empty | Fails validation though toJson sends null | booking_models.dart:446 | Use email.trim().isNotEmpty |
| BUG-24 | Low | AdmissionPlan.expiryFor | start | Impossible date rejected | 2026-02-30 rolls over | admission_models.dart expiryFor | Validate round-trip |

BUG-10 and BUG-16 numbers were retired during drafting (not bugs). Note: another agent's field_bookings_test may also report BUG-22/23 against BookingCustomer; dedupe by location.

## Screens and fields covered
- Pool: name, capacity, min/max depth, enabled, durations, buffers, hours/days/dates, price rules, group offer name/people/mode/duration/price, plan name/allowance/validity/date/price/seats/class duration, resource limits. Screens: overview, pools, pricing, groups, plans, coaching, review at 320x568 and 2.0 scale.
- Court: name, environment, surface, durations, buffers, hours, tariffs, plan name/classes/seats/validity/date/price/class duration, court and plan limits, json.
- Hall: name, guests, seated capacity, environment, amenities, hours, durations, buffers, tariffs, session and full-day package names/prices/weekdays, json.
- Turf: ground/space/offering names, format, prices, operating hours/override, durations, rules overlap, sports.
- Accounts: entry reason/category/reference/amount/split lines/accounts/destination, bank name/bank/account number/opening balance, cash opening, search, money formatting, settings and reports screens at 320x568.
- Expenses: reason, reference, category, amounts, splits, invoices (10 limit, retry), category dialog, form screen.
- Income: filters, search, day selection, categories, export, screen states.
- Admissions: customer name/phone/email, payment amount/reference/time/balance, expiry arithmetic.

## Gaps (not covered)
- Coaching module (coach classes, flexible students panel): existing tests exist; no new field tests were written.
- Admission form/detail/list widgets (admission_detail_screen.dart has uncommitted user work), admission dialogs (reason, refund reason: refund reason has no max 500 check, unreported), AdmissionCubit review matrix, admissions search field.
- Pickers/dialogs needing platform plugins (DeviceInvoicePicker), date/time pickers, expense detail screen, website payment settings card UPI field, rename-bank dialog.
- Court, hall, turf widget screens (only model level) and pool/court coaching screens.
- Run state: final reruns were interrupted by a full disk and concurrent test runs from other agents; full-file runs passed earlier for all files except where noted.
