# Income

Income is opened from **Profile → Income**, or from **Accounts → Income by payment method → View all**. It mirrors the Expenses page.

## Using the feature

- Switch Monthly/Yearly, use ‹ › or the calendar to change the period, and tap a month in the yearly graph to open it.
- **Source** filter: Bookings, Admissions, or one extra-income category. The filter sheet (tune icon) adds business, space and "Received into" account.
- The total card shows total income, the number of entries, refunds, and net after refunds. Totals use the same rule as "Total income" on Accounts: booking payments + admission payments + extra income. Refunds are listed separately and subtracted for the net. Reversals reduce income on the date they were recorded. Transfers are excluded.
- **By source** lists Bookings, Admissions and each category. Tap a row to filter by it.
- **All income** is grouped by day. Tap an entry to open the existing transaction detail screen.
- **Download PDF / Excel** exports the selected period and filters: a summary, source totals, every entry and the payment split.
- **Add income** opens the existing "Add extra income" form. Its category is now picked from the managed list. If the server has no income categories yet (migration not applied), the form keeps the old typed category field.
- Owners can add, rename, archive and restore income categories (category icon in the app bar). Renaming keeps history; archiving blocks new entries but keeps reports.

## Permissions

- Viewing the page, totals and reports: owner or `view_finance`. Staff only see income for their assigned businesses and spaces; organization-level extra income is owner-only, the same as Expenses.
- Recording income: owner or `collect_payments`. Staff with only `collect_payments` see the explanation text and the Add income button.
- Managing categories: owner only, checked on the server.

## Architecture

- Backend: `backend/src/income/` (`IncomeService`, `IncomeController`, `income.report.ts`, validation). Income entries are still saved by `AccountsService.createEntry`, which now accepts `income_category_id`. Older app versions that send only a typed category get it matched to, or added to, `income_categories`.
- Hosted function routes are added in `backend/edge/handler.ts` and `entry.ts`. Health revision: `2026-10-21-income`.
- Flutter: `lib/modules/income/{models,repositories,cubit,screens}`. The period bar and bar chart are shared with Expenses in `lib/modules/accounts/widgets/finance_period_widgets.dart`.
- API: GET `/v1/income/catalog`, POST/PATCH `/v1/income/categories[/id]`, GET `/v1/income/overview`, GET/POST `/v1/income`, GET `/v1/income/reports/pdf|xlsx`. Query: `from`, `until`, optional `source` (`bookings`, `admissions` or a category UUID), `business_id`, `resource_id`, `account_id`, `q`; list `cursor` is an offset, 50 per page. Periods are limited to one year and exports to 20,000 entries.
- Receipt attachments on income are not included.

## Migration — apply this yourself before deploying the API

No live database migration or deployment was performed.

The new API writes `finance_events.income_category_id`, so **apply the migration before deploying the API**. Otherwise recording extra income fails.

1. Back up the database and save the currently deployed function source. Supabase **booking** project, reference `scwwkaywewecspsrskft`.
2. Prerequisites: earlier migrations are applied, especially accounts, expenses and admissions (`20261020120000_admissions.sql`). The database needs schema `booking_app`, role `booking_api`, and the `organizations`, `finance_events`, `finance_lines` and `schema_migrations` tables. `finance_events` must have its existing unique `(id, organization_id)` key.
3. Optional, so you can confirm the ledger is unchanged afterwards:

```sql
SELECT count(*) AS events, (SELECT coalesce(sum(amount_minor),0) FROM booking_app.finance_lines) AS line_total
FROM booking_app.finance_events;
```

4. In the Supabase SQL Editor, run the **entire** file [20261021120000_income_categories.sql](../supabase/migrations/20261021120000_income_categories.sql) once. It includes BEGIN/COMMIT, a 10-second lock timeout, restricted grants, RLS and the `schema_migrations` record. It does not delete or change any amounts; it only adds a nullable column and fills it for existing extra-income entries. Do not also run the backend copy in `backend/migrations`, and do not run a blind `supabase db push`.
5. Verify with these read-only queries:

```sql
SELECT to_regclass('booking_app.income_categories') AS new_table;
SELECT name FROM booking_app.schema_migrations
WHERE name='20261021120000_income_categories.sql';
SELECT o.name, count(c.id) AS categories
FROM booking_app.organizations o LEFT JOIN booking_app.income_categories c ON c.organization_id=o.id
GROUP BY o.name ORDER BY o.name;
SELECT count(*) AS uncategorized_income FROM booking_app.finance_events
WHERE kind='income' AND income_category_id IS NULL;
SELECT conname FROM pg_constraint WHERE conname='finance_income_category_fk';
SELECT indexname FROM pg_indexes WHERE schemaname='booking_app'
AND indexname IN ('income_category_name_idx','income_category_period_idx');
SELECT grantee, privilege_type FROM information_schema.role_table_grants
WHERE table_schema='booking_app' AND table_name='income_categories';
```

Expected: the table exists; the migration name appears once; every organization has at least the 7 default categories (plus any typed categories found on old entries); `uncategorized_income` is 0; the foreign key and both indexes exist; only `booking_api` has SELECT, INSERT and UPDATE. If you ran step 3, run it again: both numbers must be identical.

If the SQL fails, run `ROLLBACK;` in that session, read the error, fix the prerequisite and run the whole file again. A lock timeout means a long transaction held `finance_events`; retry at a quieter time. Do not insert the `schema_migrations` row by hand.

If extra income was recorded by the old API between applying the migration and deploying the new one, link it with:

```sql
BEGIN;
SET LOCAL search_path=booking_app,pg_catalog;
INSERT INTO income_categories(organization_id,name)
 SELECT DISTINCT organization_id,trim(category) FROM finance_events
 WHERE kind='income' AND income_category_id IS NULL AND length(trim(category)) BETWEEN 2 AND 80 ON CONFLICT DO NOTHING;
UPDATE finance_events e SET income_category_id=c.id FROM income_categories c
 WHERE e.kind='income' AND e.income_category_id IS NULL AND e.organization_id=c.organization_id AND lower(trim(e.category))=lower(c.name);
UPDATE finance_events e SET income_category_id=c.id FROM income_categories c
 WHERE e.kind='income' AND e.income_category_id IS NULL AND e.organization_id=c.organization_id AND c.default_key='other';
COMMIT;
```

## Deploy the API yourself

Run in order, stopping on any failure:

```sh
cd "/Users/albinosiby/Tatos Dev/booking"
npm --prefix backend run build
npm --prefix backend run edge:check
npm --prefix backend run edge:build
npx supabase functions deploy booking-api --project-ref scwwkaywewecspsrskft --use-api --no-verify-jwt
curl -sS "https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/health"
```

Expected health revision: `2026-10-21-income`. Keep the existing secrets and function-side Supabase Auth verification unchanged.

Then reload the updated app. Check: Profile → Income loads; the yearly total matches Accounts "Total income" for the same period and scope; filtering by Bookings shows refunds; adding extra income with a category shows it under that source; PDF and Excel download.

## Recovery

- API problem after deploy: redeploy the saved previous function. The old API ignores the new column and table, so the migrated database keeps working with it.
- Undo the migration **only if the new API was never deployed, or has been rolled back**, and you accept losing category links made since:

```sql
BEGIN;
SET LOCAL search_path=booking_app,pg_catalog;
ALTER TABLE finance_events DROP CONSTRAINT IF EXISTS finance_income_category_fk;
DROP INDEX IF EXISTS income_category_period_idx;
ALTER TABLE finance_events DROP COLUMN IF EXISTS income_category_id;
DROP TABLE IF EXISTS income_categories;
DELETE FROM schema_migrations WHERE name='20261021120000_income_categories.sql';
COMMIT;
```

This removes only category links. Amounts and the typed `category` text on each entry are untouched. Never delete ledger rows to recover.
