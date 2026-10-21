-- Coaches are team members now (the "coach" permission). Remove the coach
-- contacts stored in pool and court configurations and unassign the coaching
-- plans that pointed at them; owners reassign those plans to staff coaches.
UPDATE businesses b
SET configuration = (b.configuration - 'coaches')
      || jsonb_build_object('plans', COALESCE((
        SELECT jsonb_agg(
          CASE WHEN x.p->>'coach_id' IN (
            SELECT c->>'id' FROM jsonb_array_elements(b.configuration->'coaches') c
          ) THEN jsonb_set(x.p, '{coach_id}', 'null'::jsonb) ELSE x.p END
          ORDER BY x.n)
        FROM jsonb_array_elements(b.configuration->'plans') WITH ORDINALITY AS x(p, n)
      ), '[]'::jsonb)),
    version = b.version + 1
WHERE b.configuration->>'kind' IN ('pool_v1', 'court_v1')
  AND b.configuration ? 'coaches';

-- Older pool plans may name a team member directly; keep them as coaches.
UPDATE memberships m
SET permissions = m.permissions || '["coach"]'::jsonb
WHERE NOT m.permissions ? 'coach'
  AND EXISTS (
    SELECT 1 FROM businesses b
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(b.configuration->'plans', '[]'::jsonb)) p
    WHERE b.organization_id = m.organization_id
      AND b.configuration->>'kind' IN ('pool_v1', 'court_v1')
      AND p->>'coach_id' = m.id::text
  );
