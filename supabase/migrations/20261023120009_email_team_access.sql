BEGIN;
SET LOCAL search_path = booking_app, pg_catalog;
SET LOCAL lock_timeout = '10s';
-- Owner-created email grants activate only on a verified sign-in.
-- Legacy invitation rows retain token-based acceptance.
ALTER TABLE invitations
  ADD COLUMN join_mode text NOT NULL DEFAULT 'link'
    CHECK (join_mode IN ('link','email_login')),
  ADD COLUMN email_status text NOT NULL DEFAULT 'not_requested'
    CHECK (email_status IN ('not_requested','pending','sending','sent','failed')),
  ADD COLUMN email_attempt_id uuid,
  ADD COLUMN email_attempted_at timestamptz,
  ADD COLUMN email_sent_at timestamptz,
  ADD CONSTRAINT email_team_access_no_expiry
    CHECK (join_mode <> 'email_login' OR expires_at = 'infinity'::timestamptz);

-- A verified email must never choose an arbitrary organization at sign-in.
CREATE UNIQUE INDEX pending_email_team_access
ON invitations (lower(email))
WHERE join_mode='email_login' AND accepted_at IS NULL AND revoked_at IS NULL;
CREATE INDEX active_membership_email ON memberships (lower(email)) WHERE active=true;
INSERT INTO schema_migrations(name) VALUES ('20261023120009_email_team_access.sql');
COMMIT;
