BEGIN;
SET LOCAL search_path = booking_app, pg_catalog;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '45s';
-- User-applied migration; use the private booking_app search path in production.
CREATE TABLE notification_devices (
 id uuid PRIMARY KEY, user_id text NOT NULL CHECK(length(user_id) BETWEEN 1 AND 256),
 proof_hash text NOT NULL CHECK(proof_hash ~ '^[a-f0-9]{64}$'),
 token text NOT NULL UNIQUE CHECK(length(token) BETWEEN 20 AND 4096),
 platform text NOT NULL CHECK(platform IN ('android','ios')),
 enabled boolean NOT NULL DEFAULT true, version integer NOT NULL DEFAULT 1 CHECK(version>0),
 bound_at timestamptz NOT NULL DEFAULT now(), created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(), last_seen_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX notification_devices_user_idx ON notification_devices(user_id) WHERE enabled;
CREATE TABLE booking_notification_events (
 id uuid PRIMARY KEY, history_id uuid NOT NULL UNIQUE REFERENCES booking_history(id),
 booking_id uuid NOT NULL REFERENCES bookings(id), organization_id uuid NOT NULL REFERENCES organizations(id),
 business_id uuid NOT NULL, resource_id uuid NOT NULL,
 kind text NOT NULL CHECK(kind IN ('created','cancelled','rescheduled')),
 reference text NOT NULL, expanded boolean NOT NULL DEFAULT false,
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(business_id,organization_id) REFERENCES businesses(id,organization_id),
 FOREIGN KEY(resource_id,business_id,organization_id) REFERENCES resources(id,business_id,organization_id)
);
CREATE INDEX booking_notification_pending_idx ON booking_notification_events(created_at) WHERE NOT expanded;
CREATE TABLE notification_deliveries (
 event_id uuid NOT NULL REFERENCES booking_notification_events(id) ON DELETE CASCADE,
 device_id uuid NOT NULL REFERENCES notification_devices(id) ON DELETE CASCADE,
 recipient_user_id text NOT NULL,
 state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','processing','sent','skipped','dead')),
 attempts integer NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 8),
 next_attempt_at timestamptz NOT NULL DEFAULT now(), lease_id uuid, lease_until timestamptz,
 last_error text NOT NULL DEFAULT '' CHECK(length(last_error)<=100), accepted_at timestamptz,
 PRIMARY KEY(event_id,device_id)
);
CREATE INDEX notification_delivery_pending_idx ON notification_deliveries(next_attempt_at) WHERE state IN ('pending','processing');
ALTER TABLE notification_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE booking_notification_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_deliveries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON notification_devices,booking_notification_events,notification_deliveries FROM PUBLIC;
-- Keep local isolated tests portable; hosted runtime role already exists in production.
DO $$
DECLARE r text;
BEGIN
 FOREACH r IN ARRAY ARRAY['anon','authenticated'] LOOP
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=r) THEN
   EXECUTE format('REVOKE ALL ON notification_devices,booking_notification_events,notification_deliveries FROM %I',r);
  END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='booking_api') THEN
  REVOKE ALL ON notification_devices,booking_notification_events,notification_deliveries FROM booking_api;
  GRANT SELECT,INSERT,UPDATE ON notification_devices,booking_notification_events,notification_deliveries TO booking_api;
  CREATE POLICY notification_devices_server ON notification_devices TO booking_api USING(true) WITH CHECK(true);
  CREATE POLICY booking_notification_events_server ON booking_notification_events TO booking_api USING(true) WITH CHECK(true);
  CREATE POLICY notification_deliveries_server ON notification_deliveries TO booking_api USING(true) WITH CHECK(true);
 END IF;
END $$;
INSERT INTO schema_migrations(name) VALUES ('20261023071831_firebase_booking_notifications.sql');
COMMIT;
