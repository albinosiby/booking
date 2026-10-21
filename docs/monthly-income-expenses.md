# Monthly income, expenses and space breakdown

## Behavior

Payments/Accounts now shows Income & expenses in place of the old Income growth
progress rows. It has paired bars for January–December of the year containing
the selected period's end date. The year is printed above the chart. Existing
business/space/account filters apply to the chart too. Monthly bars always cover
the full month, even when the page's other summaries use a partial date range.

Tap a month to display its income, expenses, refunds when nonzero and net cash
flow. This selection is owned by AccountsOverviewCubit and reads the already
loaded year snapshot; it does not request the server again. Background refreshes
retain the selected month. It does not silently change the other page summaries,
transaction list or report-export date range.

Expand Income & expenses by space to see each space's income, expenses, refunds
and net cash flow for the chosen month. Authorized configured spaces without
entries show zero. Historical spaces with activity remain visible. Organization
and business entries without a resource appear in separate Shared groups; no
shared expense is arbitrarily allocated to every space. Expanding the section
stays open while changing months.

## Accounting and access

This follows the existing received-money ledger basis:
- Income is received booking payments plus extra income, including applicable
  reversing entries. Unpaid booking tariff is not collected income.
- Expenses are ledger expense entries net of their corrections.
- Refunds are shown separately and deducted in net cash flow.
- Net cash flow = income - expenses - refunds; it is not an accrual profit report.
- Transfers, opening balances and movement between accounts are not income or
  expenses. Transfer reversals are excluded too.
- Corrections can make a month's income or expense negative. Such bars are drawn
  below zero on the same linear scale rather than clamped or converted to positive.

One grouped, parameterized annual read in the existing authorized overview
snapshot supplies the monthly and per-space values. It uses organization and
staff-assignment filters before grouping. There is no query per month or space,
no invoice/report download, and no full transaction history fetched by the chart.
The additive overview field is `monthly_analysis` (12 rows):

```
month, income_minor, expenses_minor, refunds_minor,
spaces: [business_id, resource_id, business_name, space_name,
         income_minor, expenses_minor, refunds_minor]
```

Existing overview totals, trend data, report formats and persistence contracts
are preserved. The REST repository maps the additive response into typed models;
screens do not process backend maps. Existing user-scoped caching/invalidation
continues to apply. If the older API lacks the additive field, other account
content stays available and the panel shows an unavailable state rather than
invented zero values.

## Deploy yourself

This feature needs no database migration. Apply any outstanding migrations from
other project features before deploying the combined current bundle. Do not run
`db push` just for this feature. Keep a copy of your current function code to
restore if a deployment fails.

Run these commands in order and stop if one fails:

```sh
cd "/Users/albinosiby/Tatos Dev/booking"
npm --prefix backend run edge:build
npx supabase functions deploy booking-api --project-ref scwwkaywewecspsrskft --use-api --no-verify-jwt
curl -sS "https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/health"
```

Expected revision: `2026-10-20-monthly-space-finance`.
Keep the existing function-side Supabase Auth verification and secrets unchanged.
Restart/reload the updated app source, then refresh Accounts to replace any older
cached overview response. Tap two different month bars and expand the space
section. Check a known booking collection, an expense assigned to a space, and
an organization-wide expense. Their corresponding month/group should agree with
the recorded ledger. Verify an assigned staff account cannot see other spaces.

If rollback is needed, restore the saved previous function code. No schema
rollback is needed; all existing financial events are preserved. An older API
will continue to serve the page's existing totals but not the new analysis panel.

No live schema changes, deployment, APK packaging or phone installation were
performed. Local tests cover accounting reconciliation/reversals, tenant/staff
isolation, zero-activity spaces, instant month selection, selection retention,
expandable groups and 320px layouts in light/dark themes with enlarged text.
