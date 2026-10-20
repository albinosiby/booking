CREATE TABLE IF NOT EXISTS organizations (
 id uuid PRIMARY KEY, name text NOT NULL CHECK(length(name) BETWEEN 2 AND 120),
 contact_phone text NOT NULL, currency varchar(3) NOT NULL,
 logo_storage_key uuid, created_by text NOT NULL UNIQUE, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS locations (
 id uuid PRIMARY KEY, organization_id uuid NOT NULL REFERENCES organizations(id),
 name text NOT NULL, address_line_1 text NOT NULL, address_line_2 text,
 city text NOT NULL, state_code text, country_code varchar(2) NOT NULL,
 postal_code text NOT NULL, timezone text NOT NULL, UNIQUE(id, organization_id)
);
CREATE TABLE IF NOT EXISTS memberships (
 id uuid PRIMARY KEY, organization_id uuid NOT NULL REFERENCES organizations(id),
 user_id text NOT NULL UNIQUE, email text NOT NULL, display_name text NOT NULL,
 role text NOT NULL CHECK(role IN ('owner','manager','staff')),
 permissions jsonb NOT NULL DEFAULT '[]', active boolean NOT NULL DEFAULT true,
 UNIQUE(id, organization_id)
);
CREATE TABLE IF NOT EXISTS businesses (
 id uuid PRIMARY KEY, organization_id uuid NOT NULL REFERENCES organizations(id),
 location_id uuid NOT NULL, name text NOT NULL CHECK(length(name) BETWEEN 2 AND 120),
 type text NOT NULL CHECK(type IN ('turf','badminton','tennis','basketball','pool','hall')),
 status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','ready','paused')),
 configuration jsonb, version integer NOT NULL DEFAULT 1,
 FOREIGN KEY(location_id,organization_id) REFERENCES locations(id,organization_id),
 UNIQUE(id,organization_id), UNIQUE(organization_id,name)
);
CREATE TABLE IF NOT EXISTS resources (
 id uuid PRIMARY KEY, organization_id uuid NOT NULL, business_id uuid NOT NULL,
 name text NOT NULL CHECK(length(name) BETWEEN 1 AND 100), capacity integer NOT NULL DEFAULT 1 CHECK(capacity BETWEEN 1 AND 10000),
 FOREIGN KEY(business_id,organization_id) REFERENCES businesses(id,organization_id),
 UNIQUE(id,organization_id), UNIQUE(business_id,name)
);
CREATE TABLE IF NOT EXISTS staff_assignments (
 membership_id uuid NOT NULL, organization_id uuid NOT NULL, business_id uuid NOT NULL,
 resource_ids jsonb NOT NULL DEFAULT '[]',
 PRIMARY KEY(membership_id,business_id),
 FOREIGN KEY(membership_id,organization_id) REFERENCES memberships(id,organization_id),
 FOREIGN KEY(business_id,organization_id) REFERENCES businesses(id,organization_id)
);
CREATE TABLE IF NOT EXISTS invitations (
 id uuid PRIMARY KEY, organization_id uuid NOT NULL REFERENCES organizations(id),
 email text NOT NULL, display_name text NOT NULL, role text NOT NULL CHECK(role IN ('manager','staff')),
 permissions jsonb NOT NULL, assignments jsonb NOT NULL,
 token_hash text NOT NULL UNIQUE, expires_at timestamptz NOT NULL,
 accepted_at timestamptz, revoked_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS pending_invitation ON invitations(organization_id,email) WHERE accepted_at IS NULL AND revoked_at IS NULL;
CREATE TABLE IF NOT EXISTS logo_assets (
 id uuid PRIMARY KEY, organization_id uuid NOT NULL UNIQUE REFERENCES organizations(id),
 content_type text NOT NULL, data bytea NOT NULL CHECK(octet_length(data) <= 2097152)
);
CREATE TABLE IF NOT EXISTS audit_events (
 id uuid PRIMARY KEY, organization_id uuid NOT NULL REFERENCES organizations(id),
 actor_id text NOT NULL, action text NOT NULL, entity_id uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS business_org_idx ON businesses(organization_id);
CREATE INDEX IF NOT EXISTS resources_business_idx ON resources(business_id);
CREATE INDEX IF NOT EXISTS audit_org_date_idx ON audit_events(organization_id,created_at);
