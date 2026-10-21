BEGIN;
SET LOCAL search_path = booking_app, pg_catalog;
SET LOCAL lock_timeout = '10s';
CREATE TABLE sarvam_integrations (
 organization_id uuid PRIMARY KEY REFERENCES organizations(id),
 membership_id uuid NOT NULL UNIQUE,
 enabled boolean NOT NULL DEFAULT false,
 api_key_ciphertext text CHECK(api_key_ciphertext IS NULL OR length(api_key_ciphertext)<=2000),
 api_key_last4 text NOT NULL DEFAULT '' CHECK(length(api_key_last4)<=4),
 sarvam_org_id text NOT NULL DEFAULT '' CHECK(sarvam_org_id ~ '^[A-Za-z0-9_-]{0,100}$'),
 workspace_id text NOT NULL DEFAULT '' CHECK(workspace_id ~ '^[A-Za-z0-9_-]{0,100}$'),
 app_id text NOT NULL DEFAULT '' CHECK(app_id ~ '^[A-Za-z0-9_-]{0,100}$'),
 tool_key_hash text UNIQUE CHECK(tool_key_hash IS NULL OR tool_key_hash ~ '^[a-f0-9]{64}$'),
 tool_key_prefix text NOT NULL DEFAULT '' CHECK(length(tool_key_prefix)<=20),
 version integer NOT NULL DEFAULT 1 CHECK(version>0),
 updated_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(membership_id,organization_id) REFERENCES memberships(id,organization_id)
);
REVOKE ALL ON sarvam_integrations FROM PUBLIC;
REVOKE ALL ON sarvam_integrations FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON sarvam_integrations TO booking_api;
INSERT INTO schema_migrations(name) VALUES ('20261022100000_sarvam_voice_agent.sql');
COMMIT;
