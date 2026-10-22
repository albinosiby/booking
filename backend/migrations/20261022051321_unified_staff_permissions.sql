-- Preserve previously granted abilities while separating staff responsibilities.
-- No schema changes. Do not apply to a live database without owner authorization.
-- Keep the legacy marker for old clients until all clients have been upgraded.
UPDATE memberships m
SET permissions = m.permissions
  || CASE WHEN (m.permissions ? 'manage_attendance' OR m.permissions ? 'coach'
       OR EXISTS (
         SELECT 1 FROM businesses b
         CROSS JOIN LATERAL jsonb_array_elements(COALESCE(b.configuration->'plans', '[]'::jsonb)) p
         WHERE b.organization_id=m.organization_id AND p->>'coach_id'=m.id::text
       )) AND NOT m.permissions ? 'mark_attendance'
     THEN '["mark_attendance"]'::jsonb ELSE '[]'::jsonb END
  || CASE WHEN m.permissions ? 'manage_bookings' AND NOT m.permissions ? 'manage_subscriptions'
     THEN '["manage_subscriptions"]'::jsonb ELSE '[]'::jsonb END
WHERE (m.permissions ?| ARRAY['manage_attendance','coach','manage_bookings'])
   OR EXISTS (
     SELECT 1 FROM businesses b
     CROSS JOIN LATERAL jsonb_array_elements(COALESCE(b.configuration->'plans', '[]'::jsonb)) p
     WHERE b.organization_id=m.organization_id AND p->>'coach_id'=m.id::text
   );

-- Pending links retain the capabilities the owner originally invited.
UPDATE invitations i
SET permissions = i.permissions
  || CASE WHEN i.permissions ?| ARRAY['manage_attendance','coach'] AND NOT i.permissions ? 'mark_attendance'
     THEN '["mark_attendance"]'::jsonb ELSE '[]'::jsonb END
  || CASE WHEN i.permissions ? 'manage_bookings' AND NOT i.permissions ? 'manage_subscriptions'
     THEN '["manage_subscriptions"]'::jsonb ELSE '[]'::jsonb END
WHERE i.accepted_at IS NULL AND i.revoked_at IS NULL AND i.expires_at > now();
