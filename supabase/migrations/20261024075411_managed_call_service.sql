BEGIN;
SET LOCAL search_path = booking_app, pg_catalog;
SET LOCAL lock_timeout = '10s';
ALTER TABLE agent_call_requests
 ADD COLUMN requested_services text[] NOT NULL DEFAULT ARRAY['booking','rescheduling','enquiry','cancellation']::text[],
 ADD COLUMN approved_services text[] NOT NULL DEFAULT '{}'::text[],
 ADD COLUMN version integer NOT NULL DEFAULT 1 CHECK(version > 0),
 ADD CONSTRAINT call_requested_services_valid CHECK(cardinality(requested_services) BETWEEN 1 AND 4 AND requested_services <@ ARRAY['booking','rescheduling','enquiry','cancellation']::text[]),
 ADD CONSTRAINT call_approved_services_valid CHECK(approved_services <@ requested_services);
ALTER TABLE sarvam_integrations
 ADD COLUMN phone_number text NOT NULL DEFAULT '' CHECK(phone_number='' OR phone_number ~ '^\+[1-9][0-9]{7,14}$'),
 ADD COLUMN deployment_id text NOT NULL DEFAULT '' CHECK(length(deployment_id)<=200),
 ADD COLUMN verified_at timestamptz,
 ADD COLUMN verified_by text NOT NULL DEFAULT '';
CREATE UNIQUE INDEX call_service_phone_unique ON sarvam_integrations(phone_number) WHERE phone_number<>'';
CREATE UNIQUE INDEX call_service_agent_unique ON sarvam_integrations(sarvam_org_id,workspace_id,app_id) WHERE app_id<>'';
-- Existing integrations need an admin to verify their phone deployment and services.
UPDATE agent_call_requests SET approved_services=requested_services,
 status=CASE WHEN status='active' THEN 'setting_up' ELSE status END,
 user_message=CASE WHEN status='active' THEN 'We are verifying your call service connection.' ELSE user_message END,
 version=version+1;
UPDATE sarvam_integrations SET enabled=false,version=version+1;
UPDATE memberships SET active=false WHERE id IN (SELECT membership_id FROM sarvam_integrations);
-- Freeze old business-wide grants to today's explicit spaces; future spaces stay off.
UPDATE staff_assignments a SET resource_ids=COALESCE((SELECT jsonb_agg(r.id::text) FROM resources r WHERE r.business_id=a.business_id),'[]'::jsonb)
 WHERE a.membership_id IN (SELECT membership_id FROM sarvam_integrations) AND jsonb_array_length(a.resource_ids)=0;
DELETE FROM staff_assignments WHERE membership_id IN (SELECT membership_id FROM sarvam_integrations) AND jsonb_array_length(resource_ids)=0;
CREATE TABLE agent_call_logs (
 organization_id uuid NOT NULL REFERENCES organizations(id),
 interaction_id text NOT NULL CHECK(length(interaction_id) BETWEEN 1 AND 200),
 provider_scope text NOT NULL,
 started_at timestamptz,
 data jsonb NOT NULL DEFAULT '{}'::jsonb CHECK(jsonb_typeof(data)='object'),
 transcript jsonb CHECK(transcript IS NULL OR jsonb_typeof(transcript)='object'),
 updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(organization_id,interaction_id)
);
CREATE INDEX agent_call_logs_history ON agent_call_logs(organization_id,started_at DESC,interaction_id);
REVOKE ALL ON agent_call_logs FROM PUBLIC;

REVOKE ALL ON agent_call_logs FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON agent_call_logs TO booking_api;
INSERT INTO schema_migrations(name) VALUES ('20261024075411_managed_call_service.sql');
COMMIT;
