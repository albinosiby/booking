-- Read-only; run as the project database owner. Never select device tokens or proof hashes.
SELECT name FROM booking_app.schema_migrations
 WHERE name='20261023071831_firebase_booking_notifications.sql';
SELECT n.nspname AS schema_name,c.relname,c.relrowsecurity
 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='booking_app' AND c.relname IN ('notification_devices','booking_notification_events','notification_deliveries');
SELECT schemaname,tablename,policyname,roles FROM pg_policies
 WHERE schemaname='booking_app' AND tablename IN ('notification_devices','booking_notification_events','notification_deliveries');
SELECT role_name,table_name,
 has_table_privilege(role_name,'booking_app.'||table_name,'SELECT') AS can_select,
 has_table_privilege(role_name,'booking_app.'||table_name,'INSERT') AS can_insert,
 has_table_privilege(role_name,'booking_app.'||table_name,'UPDATE') AS can_update,
 has_table_privilege(role_name,'booking_app.'||table_name,'DELETE') AS can_delete
 FROM (VALUES('booking_api'),('anon'),('authenticated')) r(role_name)
 CROSS JOIN (VALUES('notification_devices'),('booking_notification_events'),('notification_deliveries')) t(table_name);
-- Expected: booking_api SELECT/INSERT/UPDATE true, DELETE false; anon/authenticated all false; RLS enabled.
SELECT platform,enabled,count(*) FROM booking_app.notification_devices GROUP BY platform,enabled;
SELECT kind,expanded,count(*),min(created_at) AS oldest FROM booking_app.booking_notification_events GROUP BY kind,expanded;
SELECT state,last_error,count(*),min(next_attempt_at) AS oldest_due FROM booking_app.notification_deliveries GROUP BY state,last_error;
-- These should return zero rows.
SELECT event_id,device_id,count(*) FROM booking_app.notification_deliveries GROUP BY event_id,device_id HAVING count(*)>1;
SELECT e.id FROM booking_app.booking_notification_events e JOIN booking_app.bookings b ON b.id=e.booking_id WHERE b.admission_id IS NOT NULL;
-- After schedule installation, run separately:
-- SELECT jobid,jobname,schedule,active FROM cron.job WHERE jobname='booking-push-dispatch';
-- SELECT id,status_code,timed_out,created FROM net._http_response ORDER BY created DESC LIMIT 10;
