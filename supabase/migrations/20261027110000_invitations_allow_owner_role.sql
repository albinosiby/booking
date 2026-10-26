BEGIN;
SET LOCAL search_path = booking_app, pg_catalog;
SET LOCAL lock_timeout = '10s';
-- Lets an owner invite another owner. memberships.role already allows 'owner'.
ALTER TABLE invitations DROP CONSTRAINT invitations_role_check;
ALTER TABLE invitations ADD CONSTRAINT invitations_role_check CHECK(role IN ('owner','manager','staff'));
INSERT INTO schema_migrations(name) VALUES ('20261027110000_invitations_allow_owner_role.sql');
COMMIT;
