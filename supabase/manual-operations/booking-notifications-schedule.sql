-- USER-APPLIED after migration, sender deployment, secrets, and manual dispatch verification.
-- Enable pg_cron and pg_net in Dashboard -> Database -> Extensions first.
-- Add these named secrets through Dashboard -> Integrations -> Vault:
-- booking_push_project_url = https://scwwkaywewecspsrskft.supabase.co
-- booking_push_dispatch_secret = same random value as BOOKING_PUSH_DISPATCH_SECRET
BEGIN;
DO $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_cron') OR
    NOT EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_net') THEN
   RAISE EXCEPTION 'Enable pg_cron and pg_net before scheduling';
 END IF;
 IF (SELECT count(*) FROM vault.decrypted_secrets WHERE name='booking_push_project_url'
       AND decrypted_secret='https://scwwkaywewecspsrskft.supabase.co')<>1 OR
    (SELECT count(*) FROM vault.decrypted_secrets WHERE name='booking_push_dispatch_secret'
       AND length(decrypted_secret)>=32)<>1 THEN
   RAISE EXCEPTION 'Create exactly one valid Vault secret for each required name';
 END IF;
END $$;
-- A named schedule updates the existing job instead of creating duplicates.
SELECT cron.schedule('booking-push-dispatch','10 seconds',$job$
 SELECT net.http_post(
   url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='booking_push_project_url') || '/functions/v1/booking-notifications',
   headers := jsonb_build_object('Content-Type','application/json','x-booking-push-secret',
     (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='booking_push_dispatch_secret')),
   body := '{}'::jsonb,
   timeout_milliseconds := 120000
 );
$job$);
COMMIT;
