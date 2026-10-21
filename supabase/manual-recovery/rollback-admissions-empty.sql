-- USER-APPLIED ONLY. Restore the previous API/client before reopening writes.
BEGIN;
SET LOCAL search_path=booking_app,pg_catalog;
SET LOCAL lock_timeout='10s';
LOCK TABLE admissions,admission_payments,admission_history,bookings,finance_events IN ACCESS EXCLUSIVE MODE;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM admissions) OR EXISTS(SELECT 1 FROM admission_payments)
 OR EXISTS(SELECT 1 FROM bookings WHERE admission_id IS NOT NULL)
 OR EXISTS(SELECT 1 FROM finance_events WHERE admission_payment_id IS NOT NULL OR kind IN ('admission_collection','admission_refund'))
 THEN RAISE EXCEPTION 'Admission data exists. Retain the schema and deploy a forward fix.'; END IF;
END $$;
DROP VIEW admission_balances;
ALTER TABLE finance_events DROP COLUMN admission_payment_id;
ALTER TABLE finance_events DROP CONSTRAINT finance_events_kind_check;
ALTER TABLE finance_events ADD CONSTRAINT finance_events_kind_check CHECK(kind IN ('booking_collection','booking_refund','income','expense','transfer','reversal'));
ALTER TABLE bookings DROP CONSTRAINT bookings_admission_presence_check;
ALTER TABLE bookings DROP CONSTRAINT bookings_admission_scope_fk;
ALTER TABLE bookings DROP COLUMN admission_replacement_for;
ALTER TABLE bookings DROP COLUMN admission_id;
ALTER TABLE bookings DROP COLUMN admission_attendance;
ALTER TABLE bookings DROP COLUMN admission_waived;
DROP TABLE admission_history;
DROP TABLE admission_payments;
DROP TABLE admissions;
DELETE FROM schema_migrations WHERE name='20261020120000_admissions.sql';
COMMIT;
