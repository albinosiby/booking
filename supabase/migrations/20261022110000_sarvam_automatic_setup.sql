BEGIN;
SET LOCAL search_path = booking_app, pg_catalog;
SET LOCAL lock_timeout = '10s';
ALTER TABLE sarvam_integrations
 ADD COLUMN setup_status text NOT NULL DEFAULT 'legacy'
   CHECK (setup_status IN ('legacy','disconnected','connecting','authorization_required','configured','failed','publishing','cleanup_pending')),
 ADD COLUMN setup_state jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(setup_state)='object'),
 ADD COLUMN setup_error text NOT NULL DEFAULT '' CHECK (length(setup_error)<=500),
 ADD COLUMN setup_lease uuid,
 ADD COLUMN setup_lease_until timestamptz,
 ADD COLUMN tool_key_ciphertext text,
 ADD COLUMN pending_tool_key_hash text CHECK (pending_tool_key_hash IS NULL OR pending_tool_key_hash ~ '^[a-f0-9]{64}$'),
 ADD COLUMN authoring_ciphertext text,
 ADD COLUMN oauth_state_hash text UNIQUE,
 ADD COLUMN oauth_pending_ciphertext text;
CREATE UNIQUE INDEX sarvam_one_managed_agent ON sarvam_integrations(sarvam_org_id,workspace_id,app_id) WHERE app_id<>'' AND setup_status NOT IN ('legacy','disconnected');
INSERT INTO schema_migrations(name) VALUES ('20261022110000_sarvam_automatic_setup.sql');
COMMIT;
