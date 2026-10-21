CREATE TABLE booking_slot_blocks (
 id uuid PRIMARY KEY,
 organization_id uuid NOT NULL REFERENCES organizations(id),
 business_id uuid NOT NULL,
 FOREIGN KEY(business_id,organization_id) REFERENCES businesses(id,organization_id),
 resource_ids jsonb NOT NULL CHECK(jsonb_typeof(resource_ids)='array' AND jsonb_array_length(resource_ids) BETWEEN 1 AND 100),
 resource_names jsonb NOT NULL CHECK(jsonb_typeof(resource_names)='array'),
 inventory_keys text[] NOT NULL CHECK(cardinality(inventory_keys) BETWEEN 1 AND 512),
 starts_at timestamptz NOT NULL,
 ends_at timestamptz NOT NULL CHECK(ends_at>starts_at),
 all_day boolean NOT NULL,
 timezone text NOT NULL,
 request_hash text NOT NULL CHECK(request_hash ~ '^[0-9a-f]{64}$'),
 created_by text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 unblocked_by text,
 unblocked_at timestamptz,
 CHECK((unblocked_at IS NULL)=(unblocked_by IS NULL))
);
CREATE INDEX booking_slot_blocks_active_interval_idx ON booking_slot_blocks(business_id,starts_at,ends_at) WHERE unblocked_at IS NULL;
CREATE INDEX booking_slot_blocks_org_idx ON booking_slot_blocks(organization_id,business_id);
REVOKE ALL ON booking_slot_blocks FROM PUBLIC;
