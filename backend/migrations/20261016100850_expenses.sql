CREATE TABLE IF NOT EXISTS expense_categories (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL REFERENCES organizations(id),
 name text NOT NULL CHECK(length(name) BETWEEN 2 AND 80), default_key text,
 active boolean NOT NULL DEFAULT true, created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(id,organization_id), UNIQUE(organization_id,default_key)
);
CREATE UNIQUE INDEX IF NOT EXISTS expense_category_name_idx ON expense_categories(organization_id,lower(name));
INSERT INTO expense_categories(organization_id,name,default_key)
 SELECT o.id,v.name,v.key FROM organizations o CROSS JOIN (VALUES
 ('maintenance','Maintenance'),('food','Food'),('cleaning','Cleaning & supplies'),('utilities','Utilities'),
 ('staff','Staff & wages'),('equipment','Equipment & purchases'),('rent','Rent & lease'),('marketing','Marketing'),('transport','Transport'),('other','Other')
 ) AS v(key,name) ON CONFLICT DO NOTHING;
INSERT INTO expense_categories(organization_id,name)
 SELECT DISTINCT organization_id,trim(category) FROM finance_events WHERE kind='expense' AND length(trim(category)) BETWEEN 2 AND 80 ON CONFLICT DO NOTHING;
ALTER TABLE finance_events ADD COLUMN IF NOT EXISTS expense_category_id uuid;
UPDATE finance_events e SET expense_category_id=c.id FROM expense_categories c WHERE e.kind='expense' AND e.expense_category_id IS NULL AND e.organization_id=c.organization_id AND lower(trim(e.category))=lower(c.name);
UPDATE finance_events e SET expense_category_id=c.id FROM expense_categories c WHERE e.kind='expense' AND e.expense_category_id IS NULL AND e.organization_id=c.organization_id AND c.default_key='other';
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conname='finance_expense_category_fk') THEN
 ALTER TABLE finance_events ADD CONSTRAINT finance_expense_category_fk FOREIGN KEY(expense_category_id,organization_id) REFERENCES expense_categories(id,organization_id);
 END IF;
END $$;
CREATE INDEX IF NOT EXISTS expense_category_period_idx ON finance_events(organization_id,expense_category_id,occurred_at,id) WHERE kind IN ('expense','reversal');
CREATE TABLE IF NOT EXISTS expense_attachments (
 id uuid PRIMARY KEY, organization_id uuid NOT NULL, event_id uuid NOT NULL,
 name text NOT NULL CHECK(length(name) BETWEEN 1 AND 180), content_type text NOT NULL CHECK(content_type IN ('image/jpeg','image/png','image/webp','application/pdf')),
 size_bytes integer NOT NULL CHECK(size_bytes BETWEEN 1 AND 15728640), object_path text NOT NULL UNIQUE,
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','ready')),
 uploaded_by text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(event_id,organization_id) REFERENCES finance_events(id,organization_id), UNIQUE(id,organization_id)
);
CREATE INDEX IF NOT EXISTS expense_attachments_event_idx ON expense_attachments(event_id,status);
ALTER TABLE expense_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense_attachments ENABLE ROW LEVEL SECURITY;
