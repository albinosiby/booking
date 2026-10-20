-- Manual application only: see docs/bank-account-full-number.md.
BEGIN;
SET LOCAL search_path = booking_app, pg_catalog;
SET LOCAL lock_timeout = '10s';
ALTER TABLE money_accounts ADD COLUMN account_number text;
ALTER TABLE money_accounts ADD CONSTRAINT money_accounts_account_number_check
CHECK (account_number IS NULL OR
  (kind = 'bank' AND account_number ~ '^[0-9]{6,34}$' AND last_four = right(account_number, 4)));
INSERT INTO schema_migrations(name) VALUES ('20261020054343_bank_account_full_number.sql');
COMMIT;
