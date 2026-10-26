-- Lets an owner invite another owner. memberships.role already allows 'owner'.
-- Do not apply to a live database without owner authorization.
-- Rollback: see end of file.
ALTER TABLE invitations DROP CONSTRAINT invitations_role_check;
ALTER TABLE invitations ADD CONSTRAINT invitations_role_check CHECK(role IN ('owner','manager','staff'));
-- Rollback (fails if owner invitations exist; cancel/delete them first):
--   ALTER TABLE invitations DROP CONSTRAINT invitations_role_check;
--   ALTER TABLE invitations ADD CONSTRAINT invitations_role_check CHECK(role IN ('manager','staff'));
