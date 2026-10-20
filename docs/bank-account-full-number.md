# Full bank account numbers

New bank accounts require a full account number (6–34 ASCII digits). This is an application format check, not bank verification. Numbers remain text so leading zeros survive. The server derives `last_four` from the complete value, ignoring any separately supplied suffix. Owner Bank account settings displays the full value as selectable text. Old accounts retain their existing last-four display; the missing digits cannot be reconstructed. Existing accounts are not automatically changed or duplicated.

`account_number` is nullable for pre-existing accounts and system cash/clearing accounts. A database constraint validates any stored full number and its suffix. No index is added: accounts continue being accessed by existing organization/account keys. Full numbers are returned only in owner finance account responses, not staff responses or booking payment catalogs. Existing authorization and secure retained-cache storage continue to apply. Full numbers are not added to audit details, transaction references, logs or reports.

## Apply this migration yourself

No live schema or deployment has been changed by this task. **Apply SQL first, deploy the API second, then run the updated Flutter app.** The old Flutter bank form cannot create a bank account through the updated API because the full number is required.

1. Open the Supabase dashboard for project **booking** (`scwwkaywewecspsrskft`). Confirm the current database backup/recovery point is available. Use SQL Editor with the database owner role, not the restricted mobile/API role.
2. Run this preflight (no account numbers are selected):
   ```sql
   select to_regclass('booking_app.money_accounts') as accounts_table,
          to_regclass('booking_app.schema_migrations') as migrations_table;
   select count(*) as account_count from booking_app.money_accounts;
   select column_name from information_schema.columns
   where table_schema='booking_app' and table_name='money_accounts'
     and column_name='account_number';
   ```
   Both tables must exist. Save the row count. The column query should return no rows before a first application. If it already exists, inspect its migration status instead of rerunning the ALTER statements.
3. Open and run the entire prepared transactional script:
   `/Users/albinosiby/Tatos Dev/booking/supabase/migrations/20261020054343_bank_account_full_number.sql`
   It adds only a nullable column/constraint and records the backend migration name. It does not rewrite old numbers, change balances or change permissions. A lock timeout rolls the transaction back; retry when account writes are quiet.
4. Validate:
   ```sql
   select column_name, data_type, is_nullable
   from information_schema.columns
   where table_schema='booking_app' and table_name='money_accounts'
     and column_name='account_number';
   -- Expect: account_number / text / YES.
   select conname from pg_constraint
   where conrelid='booking_app.money_accounts'::regclass
     and conname='money_accounts_account_number_check';
   select name from booking_app.schema_migrations
   where name='20261020054343_bank_account_full_number.sql';
   select count(*) as account_count from booking_app.money_accounts;
   -- Must match the preflight count.
   ```
5. Deploy the generated function from:
   `/Users/albinosiby/Tatos Dev/booking/supabase/functions/booking-api/index.ts`
   Copy it into **Edge Functions → booking-api → Code → index.ts → Deploy updates**. Keep the existing secrets and Auth verification settings.
6. Check the function health URL:
   `https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/health`
   The bank-number-only revision was `2026-10-20-bank-account-number`. If deploying the combined template update, apply its migration too and expect `2026-10-20-message-templates`; see `docs/whatsapp-booking-templates.md`.
7. Run the updated Flutter app. Add a bank account using a test number with a leading zero and verify the same full number is visible after reopening Bank account settings. Reject blank/short/non-digit inputs. Existing last-four-only accounts should still open normally. Do not enter real account data into chat or test logs.

## Recovery

If SQL fails, execute `ROLLBACK;` in that editor session if necessary, inspect the error and rerun preflight before retrying. The migration is transactional and should not leave partial changes.

If the app/API needs repair, leave the additive column and saved data in place. Do not drop the column or backfill invented numbers. Keep owner-only account-number redaction in any replacement API: an older implementation that returns raw `a.*` to staff must not be redeployed unchanged after full numbers have been stored. No data deletion or reverse migration is needed for a client-side rollback.

## Local verification

The backend in-memory test database applies the companion migration under `backend/migrations/`; this does not connect to or migrate Supabase. Tests cover leading-zero persistence, derived suffixes, repeated commands, malformed values, database constraints and staff redaction. Flutter tests verify the full number reaches the repository without numeric conversion. No APK was built or installed.
