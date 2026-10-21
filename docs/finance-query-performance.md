# Finance query performance

Accounts, Income and Expenses were slow to open a period that wasn't cached. Measured locally with a year of data (6,000 bookings and 2,000 expenses), median of 7 runs:

| Endpoint | Before | After code changes + index |
|---|---|---|
| Accounts overview | ~5,400 ms, 11 queries | ~500 ms, 8 queries |
| Income overview | ~940 ms, 6 queries | ~100 ms, 3 queries |
| Expenses overview | ~270 ms, 6 queries | ~20 ms, 3 queries |
| Lists | 50–110 ms | 20–40 ms |

These numbers come from the embedded test database, which is slower than hosted Postgres. The hosted backend also pays a network round trip per query, so cutting the number of queries matters there too.

## What changed

1. **Missing index (migration).** `finance_lines` had no index on `event_id`, so every join or lookup from an entry to its payment lines scanned the whole table. Cost grew with the square of the ledger size. This was the main cause.
2. **Accounts date filter.** It filtered on `(occurred_at AT TIME ZONE tz)::date BETWEEN …`, which can't use the date index. It now uses the equivalent `occurred_at` range in the organization's timezone, so results are identical.
3. **Accounts overview.** The selected-period, previous-period and today totals come from one grouped query instead of three. Booking and admission dues come from one query instead of two.
4. **Income and Expenses overview.** The total, daily bars and breakdown come from one statement instead of a transaction of three. A single statement already reads one consistent snapshot.

The response shapes didn't change. Code changes 2–4 work without the migration; the migration is what removes the full-table scans.

## Migration — apply this yourself

No live database migration or deployment was performed. This migration is independent of the income categories migration and can be applied before or after it.

1. Prerequisites: schema `booking_app` with `finance_lines` and `schema_migrations`.
2. In the Supabase SQL Editor (project `scwwkaywewecspsrskft`), run the **entire** file [20261021130000_finance_lines_event_index.sql](../supabase/migrations/20261021130000_finance_lines_event_index.sql) once. It builds one index inside a transaction with a 10-second lock timeout. Building it blocks writes to `finance_lines` for a moment (milliseconds to a few seconds at your data size); reads continue. Do not run the backend copy or a blind `supabase db push`.
3. Verify (read-only):

```sql
SELECT indexname, indexdef FROM pg_indexes
WHERE schemaname='booking_app' AND indexname='finance_lines_event_idx';
SELECT name FROM booking_app.schema_migrations
WHERE name='20261021130000_finance_lines_event_index.sql';
EXPLAIN SELECT sum(amount_minor) FROM booking_app.finance_lines
WHERE event_id='00000000-0000-0000-0000-000000000000';
```

Expected: the index exists on `(event_id)`, the migration name appears once, and the plan shows `Index Scan` or `Bitmap Index Scan` using `finance_lines_event_idx`, not `Seq Scan`.

If it fails with a lock timeout, a long transaction was writing to `finance_lines`; run `ROLLBACK;` and retry at a quieter time. Do not insert the `schema_migrations` row by hand.

Recovery: the index only speeds up reads and changes no data. To remove it:

```sql
BEGIN;
SET LOCAL search_path=booking_app,pg_catalog;
DROP INDEX IF EXISTS finance_lines_event_idx;
DELETE FROM schema_migrations WHERE name='20261021130000_finance_lines_event_index.sql';
COMMIT;
```

## Deploy the API yourself

After the migration, rebuild and redeploy the hosted function. Run in order, stopping on any failure:

```sh
cd "/Users/albinosiby/Tatos Dev/booking"
npm --prefix backend run build
npm --prefix backend run edge:check
npm --prefix backend run edge:build
npx supabase functions deploy booking-api --project-ref scwwkaywewecspsrskft --use-api --no-verify-jwt
curl -sS "https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/health"
```

The health revision is whatever `backend/edge/handler.ts` contains at build time. Other work in progress has changed it, so check it matches that file. Then open Accounts, Income and Expenses and step to a month you haven't opened in this session; it should load in well under a second.
