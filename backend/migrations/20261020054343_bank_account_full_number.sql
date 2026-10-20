ALTER TABLE money_accounts ADD COLUMN account_number text;
ALTER TABLE money_accounts ADD CONSTRAINT money_accounts_account_number_check
CHECK (account_number IS NULL OR
  (kind = 'bank' AND account_number ~ '^[0-9]{6,34}$' AND last_four = right(account_number, 4)));
