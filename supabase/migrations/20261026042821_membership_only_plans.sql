BEGIN;
SET LOCAL search_path = booking_app, pg_catalog;
SET LOCAL lock_timeout = '10s';
DO $$ BEGIN
 IF to_regclass('booking_app.admissions') IS NULL THEN
  RAISE EXCEPTION 'booking_app.admissions is missing. Use the live Booking OS database and apply prerequisite migrations first.';
 END IF;
END $$;
ALTER TABLE booking_app.admissions DROP CONSTRAINT admissions_mode_check;
ALTER TABLE booking_app.admissions ADD CONSTRAINT admissions_mode_check CHECK(mode IN ('fixed','flexible','membership'));
ALTER TABLE booking_app.admissions DROP CONSTRAINT admissions_allowance_check;
ALTER TABLE booking_app.admissions ADD CONSTRAINT admissions_allowance_check CHECK(
 (mode='membership' AND allowance=0) OR (mode<>'membership' AND allowance BETWEEN 1 AND 10000));
ALTER TABLE booking_app.admissions
 ADD COLUMN deleted_at timestamptz,
 ADD COLUMN deleted_by text,
 ADD COLUMN deletion_reason text NOT NULL DEFAULT '',
 ADD CONSTRAINT admissions_deletion_metadata_check CHECK(
 (deleted_at IS NULL AND deleted_by IS NULL AND deletion_reason='') OR
 (deleted_at IS NOT NULL AND deleted_by IS NOT NULL AND length(deletion_reason) BETWEEN 2 AND 500));
CREATE INDEX admissions_expiry_attention_idx ON booking_app.admissions(organization_id,expires_on,id) WHERE deleted_at IS NULL;
DROP VIEW booking_app.admission_balances;
CREATE VIEW booking_app.admission_balances WITH (security_invoker=true) AS
 SELECT a.*,
 CASE WHEN a.mode='membership' THEN 0 ELSE COALESCE(u.used,0) END::integer AS used,
 CASE WHEN a.mode='membership' THEN 0 ELSE GREATEST(0,a.allowance-COALESCE(u.used,0)) END::integer AS remaining,
 CASE WHEN a.deleted_at IS NOT NULL THEN 'deleted'
      WHEN a.cancelled THEN 'cancelled'
      WHEN a.mode<>'membership' AND COALESCE(u.used,0)>=a.allowance THEN 'completed'
      WHEN (now() AT TIME ZONE a.timezone)::date>a.expires_on THEN 'expired'
      WHEN (now() AT TIME ZONE a.timezone)::date<a.starts_on THEN 'upcoming'
      ELSE 'active' END AS status
 FROM booking_app.admissions a LEFT JOIN LATERAL (
  SELECT CASE WHEN a.mode='fixed' THEN count(*) FILTER(WHERE b.ends_at<=now() AND NOT b.admission_waived)
   ELSE count(DISTINCT (b.starts_at AT TIME ZONE a.timezone)::date) FILTER(WHERE b.admission_attendance='present') END AS used
  FROM booking_app.bookings b WHERE b.admission_id=a.id AND b.status<>'cancelled' AND a.mode<>'membership'
 ) u ON true;
GRANT SELECT ON booking_app.admission_balances TO booking_api;
INSERT INTO booking_app.schema_migrations(name) VALUES ('20261026042821_membership_only_plans.sql');
COMMIT;
