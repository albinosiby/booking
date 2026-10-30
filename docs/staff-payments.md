# Staff Payments

## User flow

Staff with `collect_payments` get a Payments destination in the phone bottom bar
and the existing tablet/desktop sidebar. Owners keep Accounts. Finance-only staff
keep Accounts and its My cash action; staff who have both permissions open their
personal Payments page first and can reach Accounts and reports from its app bar.

The page shows:

- Current cash to hand over, or cash the owner owes the staff member when negative.
- All recorded cash given to the owner.
- Collections by payment method, refunds and expenses for the selected date.
- Personal payment activity, including booking/admission customer and reference,
  method, location, time and owner-recorded corrections attributed to the staff member.
- Owner-confirmed handovers, with amount, timestamp, remaining balance and note.

The collection date uses the API's organization reporting timezone (the first
configured location), including its current date for the date picker. The current
cash balance and all-time handover totals are independent of that date. Cash
tracking retains its existing activation cutoff; older collections do not become
new cash held merely by releasing this page. Organization bank balances and other
staff members' activity are excluded from personal responses.

Only the owner confirms receiving/giving cash through Accounts → Staff cash to
collect. Partial handovers are supported. Existing balance checks, command-key
idempotency, audit events, and protection against over-collection remain in place.
After a confirmed collection, the owner's success message names the amount and
staff member. The collecting owner and involved staff member receive a phone
notification with the confirmed amount and remaining balance. This additional
push feature requires the migration and release sequence in
[Cash collection notifications](staff-cash-notifications.md).
Handovers do not create another income entry or change the organization's account
balances. Digital receipts routed to the business bank are excluded from cash held.

## Architecture and API

`StaffCashScreen → StaffCashCubit → IStaffCashRepository` reuses the staff cash
ledger. The Cubit retains a selected date and previous valid data during network
failures, marking it as previously loaded; authorization failures clear it.
Membership, permission, organization and assignment changes clear protected data,
invalidate late responses and reload only if access remains permitted.

`WorkspaceNavigation` controls destination visibility and direct routes. Collection
permission permits `/payments` and `/staff-cash`; `/accounts/overview`, account
reports and other shared finance routes still require `view_finance`.

`GET /v1/staff-cash/me` checks the active membership and requires collection or
finance permission. Owners use the existing owner overview. Response headers
remain `private, no-store`; money balances do not use a stale HTTP cache.

Optional query parameters:

| Parameter | Meaning |
| --- | --- |
| `date` | Collection date, `YYYY-MM-DD`; defaults to reporting-local today |
| `cursor` | Personal activity offset; integer 0–1,000,000, default 0 |
| `settlement_cursor` | Independent handover offset; same bounds, default 0 |

Each history returns at most 50 rows and its own nullable `next_cursor` or
`next_settlement_cursor`. Rows have stable timestamp/UUID ordering and the client
deduplicates IDs while appending. Summary queries cover all matching ledger rows,
independent of history pagination. Refresh restarts both histories. The existing
organization/date ledger and organization/member handover indexes remain in use.

New response fields are `today`, `handed_over_minor`, `received_from_owner_minor`,
`next_cursor` and `next_settlement_cursor`. Transaction rows include
`customer_name` and a booking/admission reference where available. Admission
refunds and reversed expenses retain their correct summary categories.

## Release

The staff Payments page itself requires no new database migration, environment secret or payment provider.
The existing user-applied
`supabase/migrations/20261026100000_staff_cash_settlements.sql` is a prerequisite.
Do not rerun or apply migrations automatically. No live schema change was made.

1. Run backend `npm run build`, `npm run edge:check` and `npm run edge:build`.
2. Deploy the generated existing `booking-api` function through the normal release
   process, retaining its authentication settings and secrets.
3. Release the updated Flutter web/native clients. Deploy the API first: the new
   client requires complete handover totals and will not substitute zero for
   missing summary fields from an older API.
4. Grant Collect payments through staff access settings. Confirm visibility after
   the workspace refreshes. A separate View finance grant is not required.

For recovery, restore the previous client while retaining the updated API and
existing financial records. No ledger rollback or table removal is needed.

## Verification

Run `flutter test test/staff_payments_test.dart test/staff_cash_test.dart
test/access_navigation_test.dart test/route_guard_test.dart
test/retained_navigation_test.dart test/accounts_module_test.dart` and targeted
Flutter analysis. Backend tests use isolated in-memory PostgreSQL:
`node --import tsx --test test/staff-cash.test.ts test/accounts.test.ts test/edge.test.ts`.

Check a collection-only staff account, owner and finance-only account. Record a
cash collection and a digital collection. Confirm a partial owner handover and
refresh the staff page: remaining cash must decrease, while digital receipts
stay outside cash held. Select an older collection date and verify the current
handover balance remains unchanged. Check refunds, reversed expenses, history
beyond 50 entries, access revocation, small phones with enlarged text and desktop.
Monitor request failures through existing request IDs; never log tokens or raw
payment/customer payloads. Retain the existing database backup/recovery process.
