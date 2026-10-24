BEGIN;
SET LOCAL search_path = booking_app, pg_catalog;
SET LOCAL lock_timeout = '10s';
-- Keep support conversations when an inactive team membership is deleted.
ALTER TABLE booking_app.support_tickets ALTER COLUMN membership_id DROP NOT NULL;
ALTER TABLE booking_app.support_tickets
  DROP CONSTRAINT support_tickets_membership_id_organization_id_fkey,
  ADD CONSTRAINT support_tickets_membership_id_organization_id_fkey
    FOREIGN KEY(membership_id,organization_id) REFERENCES booking_app.memberships(id,organization_id)
    ON DELETE SET NULL (membership_id);
CREATE INDEX support_tickets_membership_idx ON booking_app.support_tickets(membership_id,organization_id);
INSERT INTO booking_app.schema_migrations(name) VALUES ('20261024050810_permanent_team_deletion.sql');
COMMIT;
