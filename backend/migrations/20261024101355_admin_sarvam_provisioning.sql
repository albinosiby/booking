CREATE TABLE sarvam_admin_connection (
 id boolean PRIMARY KEY DEFAULT true CHECK(id),
 sarvam_org_id text NOT NULL DEFAULT '',
 workspace_id text NOT NULL DEFAULT '',
 template_app_id text NOT NULL DEFAULT '',
 api_key_ciphertext text,
 api_key_last4 text NOT NULL DEFAULT '',
 authoring_ciphertext text,
 expires_at timestamptz,
 oauth_client_id text,
 oauth_state_hash text,
 oauth_pending_ciphertext text,
 version integer NOT NULL DEFAULT 1 CHECK(version>0),
 updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO sarvam_admin_connection(id) VALUES(true);
-- A number is reserved before provisioning; a second client cannot race to select it.
CREATE UNIQUE INDEX call_service_deployment_unique ON sarvam_integrations(sarvam_org_id,workspace_id,deployment_id) WHERE deployment_id<>'';
