ALTER TABLE booking_websites ADD COLUMN hero_heading text NOT NULL DEFAULT '' CHECK(length(hero_heading)<=120);
ALTER TABLE booking_websites ADD COLUMN social_links jsonb NOT NULL DEFAULT '{}'::jsonb CHECK(jsonb_typeof(social_links)='object');
ALTER TABLE booking_website_businesses ADD COLUMN card_description text NOT NULL DEFAULT '' CHECK(length(card_description)<=300);
CREATE TABLE booking_website_spaces (
 website_id uuid NOT NULL,
 organization_id uuid NOT NULL,
 business_id uuid NOT NULL,
 resource_id text NOT NULL CHECK(length(resource_id) BETWEEN 1 AND 100),
 visible boolean NOT NULL DEFAULT true,
 notice_minutes integer CHECK(notice_minutes BETWEEN 0 AND 10080),
 advance_days integer CHECK(advance_days BETWEEN 1 AND 365),
 rules text NOT NULL DEFAULT '' CHECK(length(rules)<=1000),
 PRIMARY KEY(website_id,business_id,resource_id),
 FOREIGN KEY(website_id,organization_id) REFERENCES booking_websites(id,organization_id),
 FOREIGN KEY(business_id,organization_id) REFERENCES businesses(id,organization_id)
);
CREATE INDEX website_spaces_scope_idx ON booking_website_spaces(organization_id,business_id);
ALTER TABLE booking_website_images DROP CONSTRAINT booking_website_images_kind_check;
ALTER TABLE booking_website_images DROP CONSTRAINT booking_website_images_check;
ALTER TABLE booking_website_images ADD CONSTRAINT booking_website_images_kind_check CHECK(kind IN ('hero','logo','card','space'));
ALTER TABLE booking_website_images ADD CONSTRAINT booking_website_images_scope_check CHECK(
    (kind IN ('hero','logo') AND business_id IS NULL AND resource_id IS NULL AND position=0)
 OR (kind='card' AND business_id IS NOT NULL AND resource_id IS NULL AND position=0)
 OR (kind='space' AND business_id IS NOT NULL AND resource_id IS NOT NULL));
CREATE UNIQUE INDEX website_logo_image_idx ON booking_website_images(website_id) WHERE kind='logo';
CREATE UNIQUE INDEX website_card_image_idx ON booking_website_images(website_id,business_id) WHERE kind='card';
