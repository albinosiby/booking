BEGIN;
SET LOCAL search_path = booking_app, pg_catalog;
SET LOCAL lock_timeout = '10s';
DO $$ BEGIN
 IF to_regclass('booking_app.booking_notification_events') IS NULL
 OR to_regclass('booking_app.staff_cash_settlements') IS NULL THEN
  RAISE EXCEPTION 'Apply the existing Firebase notifications and staff cash settlements migrations first.';
 END IF;
END $$;
-- Extend the existing private notification outbox for owner-confirmed cash collections.
ALTER TABLE staff_cash_settlements ADD CONSTRAINT staff_cash_settlements_org_key UNIQUE(id,organization_id);
ALTER TABLE booking_notification_events
 ALTER COLUMN history_id DROP NOT NULL,
 ALTER COLUMN booking_id DROP NOT NULL,
 ALTER COLUMN business_id DROP NOT NULL,
 ALTER COLUMN resource_id DROP NOT NULL,
 ADD COLUMN settlement_id uuid UNIQUE,
 ADD COLUMN cash_details jsonb,
 DROP CONSTRAINT booking_notification_events_kind_check;
ALTER TABLE booking_notification_events
 ADD CONSTRAINT notification_settlement_org_fk FOREIGN KEY(settlement_id,organization_id)
  REFERENCES staff_cash_settlements(id,organization_id),
 ADD CONSTRAINT booking_notification_events_kind_check CHECK(kind IN ('created','cancelled','rescheduled','staff_cash_collected')),
 ADD CONSTRAINT notification_event_source_check CHECK(
  (kind IN ('created','cancelled','rescheduled') AND history_id IS NOT NULL AND booking_id IS NOT NULL
   AND business_id IS NOT NULL AND resource_id IS NOT NULL AND settlement_id IS NULL AND cash_details IS NULL)
  OR
  (kind='staff_cash_collected' AND settlement_id IS NOT NULL AND history_id IS NULL AND booking_id IS NULL
   AND business_id IS NULL AND resource_id IS NULL AND cash_details IS NOT NULL AND jsonb_typeof(cash_details)='object')
 );
-- Existing RLS, private-schema restrictions and trusted-server table grants remain in force.
INSERT INTO booking_app.schema_migrations(name) VALUES ('20261029143630_staff_cash_collection_notifications.sql');
COMMIT;
