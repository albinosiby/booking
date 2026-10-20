BEGIN;
SET LOCAL search_path = booking_app, pg_catalog;
SET LOCAL lock_timeout = '10s';
CREATE TABLE booking_message_templates (
 id uuid PRIMARY KEY,
 organization_id uuid NOT NULL REFERENCES organizations(id),
 name text NOT NULL CHECK(length(trim(name)) BETWEEN 2 AND 80),
 body text NOT NULL CHECK(length(trim(body)) BETWEEN 1 AND 6000),
 website_url text NOT NULL DEFAULT '' CHECK(length(website_url)<=500),
 is_primary boolean NOT NULL DEFAULT false,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX booking_message_templates_name_idx ON booking_message_templates(organization_id,lower(name));
CREATE UNIQUE INDEX booking_message_templates_primary_idx ON booking_message_templates(organization_id) WHERE is_primary;
REVOKE ALL ON booking_message_templates FROM PUBLIC;
REVOKE ALL ON booking_message_templates FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON booking_message_templates TO booking_api;
INSERT INTO schema_migrations(name) VALUES ('20261020055734_booking_message_templates.sql');
COMMIT;
