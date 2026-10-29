-- These are historical/authentication identities, not grants of team access.
-- Keep original IDs after membership deletion; never cascade these records.
ALTER TABLE agent_call_requests
  DROP CONSTRAINT agent_call_requests_membership_id_organization_id_fkey;
COMMENT ON COLUMN agent_call_requests.membership_id IS
  'Original requesting membership ID; retained after team membership deletion. Not an access grant.';
-- This table exists only on installations migrated from the original auth store.
DO $$
BEGIN
  IF to_regclass('migrated_identities') IS NOT NULL THEN
    ALTER TABLE migrated_identities DROP CONSTRAINT IF EXISTS migrated_identities_actor_id_fkey;
    COMMENT ON COLUMN migrated_identities.actor_id IS
      'Stable authentication actor ID, independent of current team membership. Authorization requires an active membership.';
  END IF;
END $$;
