ALTER TABLE organizations ADD COLUMN business_order_revision integer NOT NULL DEFAULT 0 CHECK (business_order_revision >= 0);
ALTER TABLE businesses ADD COLUMN display_order integer NOT NULL DEFAULT 0 CHECK (display_order >= 0);
WITH ranked AS (
  SELECT id, (row_number() OVER (
    PARTITION BY organization_id
    ORDER BY CASE type WHEN 'turf' THEN 0 WHEN 'pool' THEN 1 WHEN 'badminton' THEN 2 WHEN 'tennis' THEN 3 WHEN 'basketball' THEN 4 ELSE 5 END, name, id
  ) - 1)::integer AS position FROM businesses
)
UPDATE businesses b SET display_order = ranked.position FROM ranked WHERE ranked.id = b.id;
CREATE INDEX businesses_display_order_idx ON businesses (organization_id, display_order, id);
