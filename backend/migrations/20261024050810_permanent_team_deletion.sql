-- Keep support conversations when an inactive team membership is deleted.
ALTER TABLE support_tickets ALTER COLUMN membership_id DROP NOT NULL;
ALTER TABLE support_tickets
  DROP CONSTRAINT support_tickets_membership_id_organization_id_fkey,
  ADD CONSTRAINT support_tickets_membership_id_organization_id_fkey
    FOREIGN KEY(membership_id,organization_id) REFERENCES memberships(id,organization_id)
    ON DELETE SET NULL (membership_id);
CREATE INDEX support_tickets_membership_idx ON support_tickets(membership_id,organization_id);
