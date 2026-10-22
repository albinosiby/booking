BEGIN;
SET LOCAL search_path=booking_app,pg_catalog;
SET LOCAL lock_timeout='10s';
CREATE TABLE booking_website_images (
 id uuid PRIMARY KEY,
 website_id uuid NOT NULL,
 organization_id uuid NOT NULL,
 kind text NOT NULL CHECK(kind IN ('hero','space')),
 business_id uuid,
 resource_id text CHECK(length(resource_id) BETWEEN 1 AND 100),
 position integer NOT NULL CHECK(position BETWEEN 0 AND 3),
 content_type text NOT NULL CHECK(content_type IN ('image/jpeg','image/png','image/webp')),
 data bytea NOT NULL CHECK(octet_length(data) BETWEEN 24 AND 1048576),
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(website_id,organization_id) REFERENCES booking_websites(id,organization_id),
 FOREIGN KEY(business_id,organization_id) REFERENCES businesses(id,organization_id),
 CHECK((kind='hero' AND business_id IS NULL AND resource_id IS NULL AND position=0)
    OR (kind='space' AND business_id IS NOT NULL AND resource_id IS NOT NULL))
);
CREATE UNIQUE INDEX website_hero_image_idx ON booking_website_images(website_id) WHERE kind='hero';
CREATE UNIQUE INDEX website_space_image_idx ON booking_website_images(website_id,business_id,resource_id,position) WHERE kind='space';
CREATE INDEX website_images_scope_idx ON booking_website_images(website_id,organization_id);
REVOKE ALL ON booking_website_images FROM PUBLIC;

REVOKE ALL ON booking_website_images FROM anon,authenticated;
ALTER TABLE booking_website_images ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,DELETE ON booking_website_images TO booking_api;
CREATE POLICY website_image_server ON booking_website_images TO booking_api USING(true) WITH CHECK(true);
INSERT INTO schema_migrations(name) VALUES ('20261022045215_booking_website_images.sql');
COMMIT;
