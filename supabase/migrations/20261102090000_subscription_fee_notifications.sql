BEGIN;
SET LOCAL search_path = booking_app, pg_catalog;
SET LOCAL lock_timeout = '10s';
DO $$ BEGIN
 IF to_regclass('booking_app.booking_notification_events') IS NULL
 OR to_regclass('booking_app.admissions') IS NULL
 OR NOT EXISTS(SELECT 1 FROM booking_app.schema_migrations WHERE name='20261029143630_staff_cash_collection_notifications.sql') THEN
  RAISE EXCEPTION 'Apply the admissions, Firebase notification and staff cash notification migrations first.';
 END IF;
END $$;
-- Monthly subscription fees reuse the private push outbox. The notification
-- sender queues one event per admission and due date on the fee's local day.
ALTER TABLE booking_notification_events
 ADD COLUMN admission_id uuid,
 ADD COLUMN due_on date,
 ADD COLUMN fee_details jsonb,
 DROP CONSTRAINT booking_notification_events_kind_check,
 DROP CONSTRAINT notification_event_source_check;
ALTER TABLE booking_notification_events
 ADD CONSTRAINT notification_admission_org_fk FOREIGN KEY(admission_id,organization_id)
  REFERENCES admissions(id,organization_id),
 ADD CONSTRAINT notification_subscription_fee_key UNIQUE(admission_id,due_on),
 ADD CONSTRAINT booking_notification_events_kind_check
  CHECK(kind IN ('created','cancelled','rescheduled','staff_cash_collected','subscription_fee_due')),
 ADD CONSTRAINT notification_event_source_check CHECK(
  (kind IN ('created','cancelled','rescheduled') AND history_id IS NOT NULL AND booking_id IS NOT NULL
   AND business_id IS NOT NULL AND resource_id IS NOT NULL AND settlement_id IS NULL AND cash_details IS NULL
   AND admission_id IS NULL AND due_on IS NULL AND fee_details IS NULL)
  OR
  (kind='staff_cash_collected' AND settlement_id IS NOT NULL AND history_id IS NULL AND booking_id IS NULL
   AND business_id IS NULL AND resource_id IS NULL AND cash_details IS NOT NULL AND jsonb_typeof(cash_details)='object'
   AND admission_id IS NULL AND due_on IS NULL AND fee_details IS NULL)
  OR
  (kind='subscription_fee_due' AND admission_id IS NOT NULL AND due_on IS NOT NULL
   AND business_id IS NOT NULL AND resource_id IS NOT NULL AND history_id IS NULL AND booking_id IS NULL
   AND settlement_id IS NULL AND cash_details IS NULL
   AND fee_details IS NOT NULL AND jsonb_typeof(fee_details)='object')
 );
-- Running subscriptions the sender scans for fees due today.
CREATE INDEX admissions_running_subscriptions_idx ON admissions(expires_on)
 WHERE plan_snapshot ? 'subscription' AND NOT cancelled AND deleted_at IS NULL;
-- Existing RLS, private-schema restrictions and trusted-server table grants remain in force.
INSERT INTO booking_app.schema_migrations(name) VALUES ('20261102090000_subscription_fee_notifications.sql');
COMMIT;
