-- Local backend copy. Production uses the schema-qualified Supabase migration and its cron job.
CREATE TABLE booking_checkin_automation (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 enabled boolean NOT NULL DEFAULT true,
 enabled_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO booking_checkin_automation(singleton) VALUES(true);
ALTER TABLE booking_checkin_automation ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON booking_checkin_automation FROM PUBLIC;
CREATE UNIQUE INDEX booking_single_checkin_idx ON booking_history(booking_id) WHERE action='checked_in';
CREATE INDEX booking_end_of_day_candidates_idx ON bookings(business_id,ends_at,id) WHERE status='confirmed' AND admission_id IS NULL;

CREATE FUNCTION booking_end_of_day_checkins(p_now timestamptz DEFAULT now(),p_limit integer DEFAULT 500)
RETURNS integer LANGUAGE plpgsql SECURITY INVOKER
SET search_path FROM CURRENT
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
 SELECT enabled_at INTO v_enabled_at FROM booking_checkin_automation WHERE singleton AND enabled;
 IF v_enabled_at IS NULL OR p_now<v_enabled_at THEN RETURN 0; END IF;
 FOR v_business IN
  SELECT b.id,l.timezone FROM businesses b JOIN locations l ON l.id=b.location_id
  WHERE EXISTS(SELECT 1 FROM bookings candidate WHERE candidate.business_id=b.id AND candidate.status='confirmed' AND candidate.admission_id IS NULL
      AND candidate.ends_at > (date_trunc('day',v_enabled_at AT TIME ZONE COALESCE(candidate.price_snapshot->>'timezone',l.timezone)) AT TIME ZONE COALESCE(candidate.price_snapshot->>'timezone',l.timezone))
      AND candidate.ends_at <= (date_trunc('day',p_now AT TIME ZONE COALESCE(candidate.price_snapshot->>'timezone',l.timezone)) AT TIME ZONE COALESCE(candidate.price_snapshot->>'timezone',l.timezone))
      AND NOT EXISTS(SELECT 1 FROM booking_history h WHERE h.booking_id=candidate.id AND h.action='checked_in'))
  ORDER BY b.id LIMIT 25 FOR UPDATE OF b SKIP LOCKED
 LOOP
  FOR v_booking IN
   SELECT booking.id,booking.ends_at,COALESCE(booking.price_snapshot->>'timezone',v_business.timezone) AS timezone
   FROM bookings booking WHERE booking.business_id=v_business.id AND booking.status='confirmed' AND booking.admission_id IS NULL
      AND booking.ends_at > (date_trunc('day',v_enabled_at AT TIME ZONE COALESCE(booking.price_snapshot->>'timezone',v_business.timezone)) AT TIME ZONE COALESCE(booking.price_snapshot->>'timezone',v_business.timezone))
      AND booking.ends_at <= (date_trunc('day',p_now AT TIME ZONE COALESCE(booking.price_snapshot->>'timezone',v_business.timezone)) AT TIME ZONE COALESCE(booking.price_snapshot->>'timezone',v_business.timezone))
      AND NOT EXISTS(SELECT 1 FROM booking_history h WHERE h.booking_id=booking.id AND h.action='checked_in')
   ORDER BY booking.ends_at,booking.id LIMIT (p_limit-v_count) FOR UPDATE OF booking SKIP LOCKED
  LOOP
   INSERT INTO booking_history(id,booking_id,actor_id,action,details,created_at)
   VALUES(gen_random_uuid(),v_booking.id,'system:booking_end_of_day','checked_in',
    jsonb_build_object('source','automatic_end_of_day','reason','Auto checked in at end of day; actual arrival time was not recorded.',
     'booking_date',((v_booking.ends_at-interval '1 microsecond') AT TIME ZONE v_booking.timezone)::date,
     'timezone',v_booking.timezone,'automated_at',p_now,'policy_version',1),p_now)
   ON CONFLICT(booking_id) WHERE action='checked_in' DO NOTHING;
   GET DIAGNOSTICS v_inserted=ROW_COUNT;
   IF v_inserted=1 THEN
    UPDATE bookings SET version=version+1 WHERE id=v_booking.id;
    v_count:=v_count+1;
   END IF;
   IF v_count>=p_limit THEN RETURN v_count; END IF;
  END LOOP;
 END LOOP;
 RETURN v_count;
END;
$function$;
REVOKE ALL ON FUNCTION booking_end_of_day_checkins(timestamptz,integer) FROM PUBLIC;
DO $permissions$
DECLARE role_name text;
BEGIN
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','booking_api'] LOOP
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=role_name) THEN
   EXECUTE format('REVOKE ALL ON booking_checkin_automation FROM %I',role_name);
   EXECUTE format('REVOKE ALL ON FUNCTION booking_end_of_day_checkins(timestamptz,integer) FROM %I',role_name);
  END IF;
 END LOOP;
END;
$permissions$;

