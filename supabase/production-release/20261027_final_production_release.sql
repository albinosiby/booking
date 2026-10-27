-- FINAL PRODUCTION RELEASE: Booking OS (Supabase project scwwkaywewecspsrskft, schema booking_app).
-- Consolidates every migration from 20261026042821 onward. NOT yet applied: the owner runs it.
-- Safe to re-run: each step runs only if its name is absent from booking_app.schema_migrations,
-- and the whole file is one transaction (any failure rolls everything back).
-- Prerequisites: full DB backup; pg_cron enabled (end-of-day check-ins); app deploy AFTER this file.
-- Steps included:
--   20261026042821_membership_only_plans.sql
--   20261026055830_booking_end_of_day_checkins.sql
--   20261026100000_staff_cash_settlements.sql
--   20261027100000_booking_invoices.sql
--   20261027110000_invitations_allow_owner_role.sql
--   20261027110000_invoice_templates.sql
-- Rollback: per-step rollback notes are in backend/migrations/<name>.sql; restore backup for anything else.
BEGIN;
SET LOCAL search_path = booking_app, pg_catalog;
SET LOCAL lock_timeout = '10s';
DO $guard$
BEGIN
 IF to_regclass('booking_app.schema_migrations') IS NULL THEN
  RAISE EXCEPTION 'booking_app.schema_migrations is missing. Wrong database/project.';
 END IF;
END;
$guard$;

-- ===== 20261026042821_membership_only_plans.sql
DO $step$
BEGIN
 IF EXISTS(SELECT 1 FROM booking_app.schema_migrations WHERE name='20261026042821_membership_only_plans.sql') THEN
  RAISE NOTICE 'skip 20261026042821_membership_only_plans.sql (already applied)';
 ELSE
  EXECUTE $mig$DO $$ BEGIN
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
$mig$;
  RAISE NOTICE 'applied 20261026042821_membership_only_plans.sql';
 END IF;
END;
$step$;

-- ===== 20261026055830_booking_end_of_day_checkins.sql
DO $step$
BEGIN
 IF EXISTS(SELECT 1 FROM booking_app.schema_migrations WHERE name='20261026055830_booking_end_of_day_checkins.sql') THEN
  RAISE NOTICE 'skip 20261026055830_booking_end_of_day_checkins.sql (already applied)';
 ELSE
  EXECUTE $mig$DO $prerequisites$
BEGIN
 IF to_regclass('booking_app.admissions') IS NULL OR to_regclass('booking_app.booking_history') IS NULL THEN
  RAISE EXCEPTION 'Use the existing Booking OS project and apply prerequisite admissions/booking migrations.';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_cron') THEN
  RAISE EXCEPTION 'Enable pg_cron before applying the end-of-day check-in migration.';
 END IF;
 IF EXISTS(SELECT 1 FROM cron.job WHERE jobname='booking-end-of-day-checkins') THEN
  RAISE EXCEPTION 'An end-of-day check-in job already exists; review its owner and migration marker before continuing.';
 END IF;
 IF EXISTS(SELECT 1 FROM booking_app.booking_history WHERE action='checked_in' GROUP BY booking_id HAVING count(*)>1) THEN
  RAISE EXCEPTION 'Duplicate check-in history needs review; existing history will not be deleted automatically.';
 END IF;
END;
$prerequisites$;
CREATE TABLE booking_app.booking_checkin_automation (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 enabled boolean NOT NULL DEFAULT true,
 enabled_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO booking_app.booking_checkin_automation(singleton) VALUES(true);
ALTER TABLE booking_app.booking_checkin_automation ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON booking_app.booking_checkin_automation FROM PUBLIC;
CREATE UNIQUE INDEX booking_single_checkin_idx ON booking_app.booking_history(booking_id) WHERE action='checked_in';
CREATE INDEX booking_end_of_day_candidates_idx ON booking_app.bookings(business_id,ends_at,id) WHERE status='confirmed' AND admission_id IS NULL;

CREATE FUNCTION booking_app.booking_end_of_day_checkins(p_now timestamptz DEFAULT now(),p_limit integer DEFAULT 500)
RETURNS integer LANGUAGE plpgsql SECURITY INVOKER
SET search_path = booking_app, pg_catalog
AS $function$
DECLARE
 v_enabled_at timestamptz;
 v_business record;
 v_booking record;
 v_count integer := 0;
 v_inserted integer;
BEGIN
 IF p_now IS NULL OR NOT isfinite(p_now) OR p_limit IS NULL OR p_limit<1 OR p_limit>1000 THEN
  RAISE EXCEPTION 'Supply a finite run time and a batch limit from 1 to 1000.';
 END IF;
 SELECT enabled_at INTO v_enabled_at FROM booking_app.booking_checkin_automation WHERE singleton AND enabled;
 IF v_enabled_at IS NULL OR p_now<v_enabled_at THEN RETURN 0; END IF;
 FOR v_business IN
  SELECT b.id,l.timezone FROM booking_app.businesses b JOIN booking_app.locations l ON l.id=b.location_id
  WHERE EXISTS(SELECT 1 FROM booking_app.bookings candidate WHERE candidate.business_id=b.id AND candidate.status='confirmed' AND candidate.admission_id IS NULL
      AND candidate.ends_at > (date_trunc('day',v_enabled_at AT TIME ZONE COALESCE(candidate.price_snapshot->>'timezone',l.timezone)) AT TIME ZONE COALESCE(candidate.price_snapshot->>'timezone',l.timezone))
      AND candidate.ends_at <= (date_trunc('day',p_now AT TIME ZONE COALESCE(candidate.price_snapshot->>'timezone',l.timezone)) AT TIME ZONE COALESCE(candidate.price_snapshot->>'timezone',l.timezone))
      AND NOT EXISTS(SELECT 1 FROM booking_app.booking_history h WHERE h.booking_id=candidate.id AND h.action='checked_in'))
  ORDER BY b.id LIMIT 25 FOR UPDATE OF b SKIP LOCKED
 LOOP
  FOR v_booking IN
   SELECT booking.id,booking.ends_at,COALESCE(booking.price_snapshot->>'timezone',v_business.timezone) AS timezone
   FROM booking_app.bookings booking WHERE booking.business_id=v_business.id AND booking.status='confirmed' AND booking.admission_id IS NULL
      AND booking.ends_at > (date_trunc('day',v_enabled_at AT TIME ZONE COALESCE(booking.price_snapshot->>'timezone',v_business.timezone)) AT TIME ZONE COALESCE(booking.price_snapshot->>'timezone',v_business.timezone))
      AND booking.ends_at <= (date_trunc('day',p_now AT TIME ZONE COALESCE(booking.price_snapshot->>'timezone',v_business.timezone)) AT TIME ZONE COALESCE(booking.price_snapshot->>'timezone',v_business.timezone))
      AND NOT EXISTS(SELECT 1 FROM booking_app.booking_history h WHERE h.booking_id=booking.id AND h.action='checked_in')
   ORDER BY booking.ends_at,booking.id LIMIT (p_limit-v_count) FOR UPDATE OF booking SKIP LOCKED
  LOOP
   INSERT INTO booking_app.booking_history(id,booking_id,actor_id,action,details,created_at)
   VALUES(gen_random_uuid(),v_booking.id,'system:booking_end_of_day','checked_in',
    jsonb_build_object('source','automatic_end_of_day','reason','Auto checked in at end of day; actual arrival time was not recorded.',
     'booking_date',((v_booking.ends_at-interval '1 microsecond') AT TIME ZONE v_booking.timezone)::date,
     'timezone',v_booking.timezone,'automated_at',p_now,'policy_version',1),p_now)
   ON CONFLICT(booking_id) WHERE action='checked_in' DO NOTHING;
   GET DIAGNOSTICS v_inserted=ROW_COUNT;
   IF v_inserted=1 THEN
    UPDATE booking_app.bookings SET version=version+1 WHERE id=v_booking.id;
    v_count:=v_count+1;
   END IF;
   IF v_count>=p_limit THEN RETURN v_count; END IF;
  END LOOP;
 END LOOP;
 RETURN v_count;
END;
$function$;
REVOKE ALL ON FUNCTION booking_app.booking_end_of_day_checkins(timestamptz,integer) FROM PUBLIC;
DO $permissions$
DECLARE role_name text;
BEGIN
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','booking_api'] LOOP
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=role_name) THEN
   EXECUTE format('REVOKE ALL ON booking_app.booking_checkin_automation FROM %I',role_name);
   EXECUTE format('REVOKE ALL ON FUNCTION booking_app.booking_end_of_day_checkins(timestamptz,integer) FROM %I',role_name);
  END IF;
 END LOOP;
END;
$permissions$;

SELECT cron.schedule('booking-end-of-day-checkins','* * * * *',
 $job$SET lock_timeout='2s'; SET statement_timeout='45s'; SELECT booking_app.booking_end_of_day_checkins();$job$);
INSERT INTO booking_app.schema_migrations(name) VALUES('20261026055830_booking_end_of_day_checkins.sql');
$mig$;
  RAISE NOTICE 'applied 20261026055830_booking_end_of_day_checkins.sql';
 END IF;
END;
$step$;

-- ===== 20261026100000_staff_cash_settlements.sql
DO $step$
BEGIN
 IF EXISTS(SELECT 1 FROM booking_app.schema_migrations WHERE name='20261026100000_staff_cash_settlements.sql') THEN
  RAISE NOTICE 'skip 20261026100000_staff_cash_settlements.sql (already applied)';
 ELSE
  EXECUTE $mig$DO $$
BEGIN
 IF to_regclass('booking_app.memberships') IS NULL OR to_regclass('booking_app.finance_events') IS NULL THEN
  RAISE EXCEPTION 'booking_app.memberships or finance_events is missing. Select the live Booking OS project scwwkaywewecspsrskft and apply its prerequisite migrations first.';
 END IF;
END;
$$;
CREATE TABLE booking_app.staff_cash_settlements (
 id uuid PRIMARY KEY,
 organization_id uuid NOT NULL REFERENCES booking_app.organizations(id),
 membership_id uuid NOT NULL,
 direction text NOT NULL CHECK(direction IN ('collect','give')),
 amount_minor bigint NOT NULL CHECK(amount_minor BETWEEN 1 AND 100000000000),
 balance_before_minor bigint NOT NULL,
 balance_after_minor bigint NOT NULL,
 settled_by text NOT NULL,
 settled_at timestamptz NOT NULL DEFAULT now(),
 note text NOT NULL DEFAULT '' CHECK(length(note)<=300),
 command_key uuid NOT NULL,
 request_hash text NOT NULL,
 FOREIGN KEY(membership_id,organization_id) REFERENCES booking_app.memberships(id,organization_id),
 UNIQUE(organization_id,command_key),
 CHECK(balance_after_minor = balance_before_minor + CASE WHEN direction='collect' THEN -amount_minor ELSE amount_minor END)
);
CREATE INDEX staff_cash_settlements_staff_idx ON booking_app.staff_cash_settlements(organization_id,membership_id,settled_at DESC);
CREATE TABLE booking_app.staff_cash_tracking (
 organization_id uuid PRIMARY KEY REFERENCES booking_app.organizations(id) ON DELETE CASCADE,
 started_at timestamptz NOT NULL
);
-- Cash collected before this moment is not counted as held by staff. Organizations created later count from the start.
INSERT INTO booking_app.staff_cash_tracking(organization_id,started_at) SELECT id,now() FROM booking_app.organizations;
ALTER TABLE booking_app.staff_cash_settlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE booking_app.staff_cash_tracking ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON booking_app.staff_cash_settlements, booking_app.staff_cash_tracking FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON booking_app.staff_cash_settlements TO booking_api;
GRANT SELECT ON booking_app.staff_cash_tracking TO booking_api;
CREATE POLICY staff_cash_settlements_server_access ON booking_app.staff_cash_settlements TO booking_api USING (true) WITH CHECK (true);
CREATE POLICY staff_cash_tracking_server_access ON booking_app.staff_cash_tracking TO booking_api USING (true) WITH CHECK (true);
INSERT INTO booking_app.schema_migrations(name) VALUES ('20261026100000_staff_cash_settlements.sql');
$mig$;
  RAISE NOTICE 'applied 20261026100000_staff_cash_settlements.sql';
 END IF;
END;
$step$;

-- ===== 20261027100000_booking_invoices.sql
DO $step$
BEGIN
 IF EXISTS(SELECT 1 FROM booking_app.schema_migrations WHERE name='20261027100000_booking_invoices.sql') THEN
  RAISE NOTICE 'skip 20261027100000_booking_invoices.sql (already applied)';
 ELSE
  EXECUTE $mig$DO $$
BEGIN
 IF to_regclass('booking_app.bookings') IS NULL OR to_regclass('booking_app.organizations') IS NULL THEN
  RAISE EXCEPTION 'booking_app.bookings or organizations is missing. Select the live Booking OS project scwwkaywewecspsrskft and apply its prerequisite migrations first.';
 END IF;
END;
$$;
CREATE TABLE booking_app.booking_invoice_settings (
 organization_id uuid PRIMARY KEY REFERENCES booking_app.organizations(id) ON DELETE CASCADE,
 enabled boolean NOT NULL DEFAULT true,
 updated_by text NOT NULL,
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE booking_app.booking_invoice_counters (
 organization_id uuid PRIMARY KEY REFERENCES booking_app.organizations(id) ON DELETE CASCADE,
 last_number integer NOT NULL DEFAULT 0
);
CREATE TABLE booking_app.booking_invoices (
 id uuid PRIMARY KEY,
 organization_id uuid NOT NULL REFERENCES booking_app.organizations(id),
 booking_id uuid NOT NULL,
 invoice_number text NOT NULL CHECK(length(invoice_number) BETWEEN 5 AND 40),
 total_minor bigint NOT NULL CHECK(total_minor>=0),
 paid_minor bigint NOT NULL,
 balance_minor bigint NOT NULL CHECK(balance_minor>=0),
 currency varchar(3) NOT NULL,
 content_hash text NOT NULL,
 snapshot jsonb NOT NULL,
 logo_data bytea,
 logo_content_type text,
 qr_data bytea,
 qr_content_type text,
 generated_by text NOT NULL,
 generated_by_name text NOT NULL,
 generated_at timestamptz NOT NULL DEFAULT now(),
 command_key uuid NOT NULL,
 FOREIGN KEY(booking_id,organization_id) REFERENCES booking_app.bookings(id,organization_id),
 UNIQUE(organization_id,invoice_number),
 UNIQUE(organization_id,command_key)
);
CREATE INDEX booking_invoices_booking_idx ON booking_app.booking_invoices(organization_id,booking_id,generated_at DESC);
CREATE FUNCTION booking_app.booking_invoices_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 RAISE EXCEPTION 'Generated invoices cannot be changed or deleted.';
END;
$$;
CREATE TRIGGER booking_invoices_no_change BEFORE UPDATE OR DELETE ON booking_app.booking_invoices
 FOR EACH ROW EXECUTE FUNCTION booking_app.booking_invoices_immutable();
ALTER TABLE booking_app.booking_invoice_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE booking_app.booking_invoice_counters ENABLE ROW LEVEL SECURITY;
ALTER TABLE booking_app.booking_invoices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON booking_app.booking_invoice_settings, booking_app.booking_invoice_counters, booking_app.booking_invoices FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION booking_app.booking_invoices_immutable() FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON booking_app.booking_invoice_settings TO booking_api;
GRANT SELECT, INSERT, UPDATE ON booking_app.booking_invoice_counters TO booking_api;
GRANT SELECT, INSERT ON booking_app.booking_invoices TO booking_api;
CREATE POLICY booking_invoice_settings_server_access ON booking_app.booking_invoice_settings TO booking_api USING (true) WITH CHECK (true);
CREATE POLICY booking_invoice_counters_server_access ON booking_app.booking_invoice_counters TO booking_api USING (true) WITH CHECK (true);
CREATE POLICY booking_invoices_server_access ON booking_app.booking_invoices TO booking_api USING (true) WITH CHECK (true);
INSERT INTO booking_app.schema_migrations(name) VALUES ('20261027100000_booking_invoices.sql');
$mig$;
  RAISE NOTICE 'applied 20261027100000_booking_invoices.sql';
 END IF;
END;
$step$;

-- ===== 20261027110000_invitations_allow_owner_role.sql
DO $step$
BEGIN
 IF EXISTS(SELECT 1 FROM booking_app.schema_migrations WHERE name='20261027110000_invitations_allow_owner_role.sql') THEN
  RAISE NOTICE 'skip 20261027110000_invitations_allow_owner_role.sql (already applied)';
 ELSE
  EXECUTE $mig$-- Lets an owner invite another owner. memberships.role already allows 'owner'.
ALTER TABLE invitations DROP CONSTRAINT invitations_role_check;
ALTER TABLE invitations ADD CONSTRAINT invitations_role_check CHECK(role IN ('owner','manager','staff'));
INSERT INTO schema_migrations(name) VALUES ('20261027110000_invitations_allow_owner_role.sql');
$mig$;
  RAISE NOTICE 'applied 20261027110000_invitations_allow_owner_role.sql';
 END IF;
END;
$step$;

-- ===== 20261027110000_invoice_templates.sql
DO $step$
BEGIN
 IF EXISTS(SELECT 1 FROM booking_app.schema_migrations WHERE name='20261027110000_invoice_templates.sql') THEN
  RAISE NOTICE 'skip 20261027110000_invoice_templates.sql (already applied)';
 ELSE
  EXECUTE $mig$DO $$
BEGIN
 IF to_regclass('booking_app.booking_invoice_settings') IS NULL THEN
  RAISE EXCEPTION 'booking_app.booking_invoice_settings is missing. Apply 20261027100000_booking_invoices.sql first.';
 END IF;
END;
$$;
ALTER TABLE booking_app.booking_invoice_settings ADD COLUMN template text NOT NULL DEFAULT 'classic' CHECK(template IN ('classic','modern','minimal'));
INSERT INTO booking_app.schema_migrations(name) VALUES ('20261027110000_invoice_templates.sql');
$mig$;
  RAISE NOTICE 'applied 20261027110000_invoice_templates.sql';
 END IF;
END;
$step$;

COMMIT;

-- VALIDATION (run after):
-- SELECT name FROM booking_app.schema_migrations WHERE name>='20261026042821' ORDER BY name;  -- all steps listed
-- SELECT to_regclass('booking_app.staff_cash_settlements'),to_regclass('booking_app.booking_invoices'),
--        to_regclass('booking_app.booking_checkin_automation');                              -- none null
-- SELECT column_name FROM information_schema.columns WHERE table_schema='booking_app'
--   AND table_name='booking_invoice_settings' AND column_name='template';                    -- 1 row
-- SELECT jobname,schedule FROM cron.job WHERE jobname='booking-end-of-day-checkins';          -- 1 row
-- SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='invitations_role_check'; -- includes 'owner'
