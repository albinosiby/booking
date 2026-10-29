BEGIN;
SET LOCAL search_path = booking_app, pg_catalog;
SET LOCAL lock_timeout = '10s';
CREATE TABLE admin_mcp_credentials (
 id uuid PRIMARY KEY,
 name text NOT NULL CHECK(length(name) BETWEEN 1 AND 120),
 operator_email text NOT NULL CHECK(operator_email=lower(operator_email) AND length(operator_email) BETWEEN 3 AND 320),
 issued_by text NOT NULL CHECK(length(issued_by) BETWEEN 1 AND 320),
 token_hash text NOT NULL UNIQUE CHECK(token_hash ~ '^[a-f0-9]{64}$'),
 token_prefix text NOT NULL CHECK(token_prefix ~ '^bkam_[A-Za-z0-9_-]{5,12}$'),
 scopes text[] NOT NULL CHECK(cardinality(scopes) BETWEEN 1 AND 3 AND scopes <@ ARRAY['voice:read','voice:write','voice:credentials:install']::text[]),
 created_at timestamptz NOT NULL DEFAULT now(),
 expires_at timestamptz NOT NULL CHECK(expires_at>created_at),
 revoked_at timestamptz,
 last_used_at timestamptz
);
CREATE INDEX admin_mcp_credentials_expiry ON admin_mcp_credentials(expires_at) WHERE revoked_at IS NULL;
ALTER TABLE admin_mcp_credentials ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON admin_mcp_credentials FROM PUBLIC, anon, authenticated;
GRANT SELECT, UPDATE ON admin_mcp_credentials TO booking_api;
CREATE POLICY admin_mcp_backend_access ON admin_mcp_credentials TO booking_api USING(true) WITH CHECK(true);
INSERT INTO schema_migrations(name) VALUES('20261029105442_admin_voice_mcp_credentials.sql');
COMMIT;
