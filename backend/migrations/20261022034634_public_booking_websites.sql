CREATE TABLE booking_websites (
 id uuid PRIMARY KEY, organization_id uuid NOT NULL UNIQUE REFERENCES organizations(id),
 slug text NOT NULL UNIQUE CHECK(length(slug) BETWEEN 3 AND 80 AND slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
 title text NOT NULL CHECK(length(title) BETWEEN 2 AND 120), description text NOT NULL DEFAULT '' CHECK(length(description)<=1200),
 contact_phone text NOT NULL, instructions text NOT NULL DEFAULT '' CHECK(length(instructions)<=2000),
 cancellation_policy text NOT NULL DEFAULT '' CHECK(length(cancellation_policy)<=2000),
 status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','published','paused','unpublished')),
 publish_logo boolean NOT NULL DEFAULT false,
 notice_minutes integer NOT NULL DEFAULT 0 CHECK(notice_minutes BETWEEN 0 AND 10080),
 advance_days integer NOT NULL DEFAULT 30 CHECK(advance_days BETWEEN 1 AND 365),
 version integer NOT NULL DEFAULT 1 CHECK(version>0), first_published_at timestamptz,
 preview_hash text, preview_expires_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(id,organization_id)
);
CREATE TABLE booking_website_businesses (
 website_id uuid NOT NULL, organization_id uuid NOT NULL, business_id uuid NOT NULL,
 display_order integer NOT NULL CHECK(display_order>=0), PRIMARY KEY(website_id,business_id),
 FOREIGN KEY(website_id,organization_id) REFERENCES booking_websites(id,organization_id),
 FOREIGN KEY(business_id,organization_id) REFERENCES businesses(id,organization_id)
);
CREATE INDEX website_business_scope_idx ON booking_website_businesses(organization_id,business_id);
ALTER TABLE bookings ADD COLUMN booking_source text CHECK(booking_source IN ('website'));
ALTER TABLE bookings ADD COLUMN booking_website_id uuid;
ALTER TABLE bookings ADD CONSTRAINT bookings_website_scope_fk FOREIGN KEY(booking_website_id,organization_id) REFERENCES booking_websites(id,organization_id);
ALTER TABLE bookings ADD CONSTRAINT bookings_website_source_check CHECK((booking_source IS NULL)=(booking_website_id IS NULL));
CREATE INDEX bookings_website_idx ON bookings(booking_website_id,starts_at) WHERE booking_website_id IS NOT NULL;
CREATE TABLE booking_website_limits (
 website_id uuid NOT NULL REFERENCES booking_websites(id), bucket text NOT NULL,
 used integer NOT NULL CHECK(used>0), expires_at timestamptz NOT NULL,
 PRIMARY KEY(website_id,bucket)
);
CREATE INDEX website_limits_expiry_idx ON booking_website_limits(website_id,expires_at);
REVOKE ALL ON booking_websites,booking_website_businesses,booking_website_limits FROM PUBLIC;
