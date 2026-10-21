CREATE TABLE IF NOT EXISTS income_categories (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL REFERENCES organizations(id),
 name text NOT NULL CHECK(length(name) BETWEEN 2 AND 80), default_key text,
 active boolean NOT NULL DEFAULT true, created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(id,organization_id), UNIQUE(organization_id,default_key)
);
CREATE UNIQUE INDEX IF NOT EXISTS income_category_name_idx ON income_categories(organization_id,lower(name));
INSERT INTO income_categories(organization_id,name,default_key)
 SELECT o.id,v.name,v.key FROM organizations o CROSS JOIN (VALUES
 ('sponsorship','Sponsorship'),('events','Events'),('rentals','Rentals'),('coaching','Coaching fees'),
 ('food','Food & beverages'),('merchandise','Merchandise'),('other','Other')
 ) AS v(key,name) ON CONFLICT DO NOTHING;
INSERT INTO income_categories(organization_id,name)
 SELECT DISTINCT organization_id,trim(category) FROM finance_events WHERE kind='income' AND length(trim(category)) BETWEEN 2 AND 80 ON CONFLICT DO NOTHING;
ALTER TABLE finance_events ADD COLUMN IF NOT EXISTS income_category_id uuid;
UPDATE finance_events e SET income_category_id=c.id FROM income_categories c WHERE e.kind='income' AND e.income_category_id IS NULL AND e.organization_id=c.organization_id AND lower(trim(e.category))=lower(c.name);
UPDATE finance_events e SET income_category_id=c.id FROM income_categories c WHERE e.kind='income' AND e.income_category_id IS NULL AND e.organization_id=c.organization_id AND c.default_key='other';
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conname='finance_income_category_fk') THEN
 ALTER TABLE finance_events ADD CONSTRAINT finance_income_category_fk FOREIGN KEY(income_category_id,organization_id) REFERENCES income_categories(id,organization_id);
 END IF;
END $$;
CREATE INDEX IF NOT EXISTS income_category_period_idx ON finance_events(organization_id,income_category_id,occurred_at,id) WHERE kind IN ('income','reversal');
ALTER TABLE income_categories ENABLE ROW LEVEL SECURITY;
