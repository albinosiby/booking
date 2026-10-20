CREATE TABLE IF NOT EXISTS customers (
 id uuid PRIMARY KEY, organization_id uuid NOT NULL REFERENCES organizations(id),
 name text NOT NULL, phone text NOT NULL, email text, created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(id,organization_id)
);
CREATE INDEX IF NOT EXISTS customers_phone_idx ON customers(organization_id,phone);
CREATE UNIQUE INDEX IF NOT EXISTS resource_scope_identity_idx ON resources(id,business_id,organization_id);
CREATE TABLE IF NOT EXISTS bookings (
 id uuid PRIMARY KEY, organization_id uuid NOT NULL, business_id uuid NOT NULL, resource_id uuid NOT NULL,
 customer_id uuid NOT NULL, reference text NOT NULL, status text NOT NULL DEFAULT 'confirmed' CHECK(status IN ('confirmed','completed','cancelled','no_show')),
 starts_at timestamptz NOT NULL, ends_at timestamptz NOT NULL CHECK(ends_at>starts_at),
 total_minor integer NOT NULL CHECK(total_minor BETWEEN 0 AND 100000000),
 selection jsonb NOT NULL, price_snapshot jsonb NOT NULL, customer_snapshot jsonb NOT NULL,
 notes text NOT NULL DEFAULT '', people integer NOT NULL CHECK(people BETWEEN 1 AND 10000),
 version integer NOT NULL DEFAULT 1, created_by text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(business_id,organization_id) REFERENCES businesses(id,organization_id),
 FOREIGN KEY(resource_id,business_id,organization_id) REFERENCES resources(id,business_id,organization_id),
 FOREIGN KEY(customer_id,organization_id) REFERENCES customers(id,organization_id),
 UNIQUE(id,organization_id),UNIQUE(organization_id,reference)
);
CREATE INDEX IF NOT EXISTS booking_business_time_idx ON bookings(business_id,starts_at,ends_at);
CREATE INDEX IF NOT EXISTS booking_org_time_idx ON bookings(organization_id,starts_at);
CREATE TABLE IF NOT EXISTS booking_allocations (
 booking_id uuid NOT NULL REFERENCES bookings(id), inventory_key text NOT NULL,
 starts_at timestamptz NOT NULL, ends_at timestamptz NOT NULL CHECK(ends_at>starts_at),
 quantity integer NOT NULL CHECK(quantity>0), PRIMARY KEY(booking_id,inventory_key)
);
CREATE INDEX IF NOT EXISTS allocations_overlap_idx ON booking_allocations(inventory_key,starts_at,ends_at);
CREATE TABLE IF NOT EXISTS booking_payments (
 id uuid PRIMARY KEY, organization_id uuid NOT NULL, booking_id uuid NOT NULL,
 kind text NOT NULL CHECK(kind IN ('collection','refund')), method text NOT NULL CHECK(method IN ('cash','upi','card','bank_transfer')),
 amount_minor integer NOT NULL CHECK(amount_minor BETWEEN 1 AND 100000000), reference text NOT NULL DEFAULT '', reason text NOT NULL DEFAULT '',
 received_at timestamptz NOT NULL, recorded_by text NOT NULL, recorded_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(booking_id,organization_id) REFERENCES bookings(id,organization_id)
);
CREATE INDEX IF NOT EXISTS payments_org_date_idx ON booking_payments(organization_id,received_at);
CREATE INDEX IF NOT EXISTS payments_booking_idx ON booking_payments(booking_id);
CREATE TABLE IF NOT EXISTS booking_history (
 id uuid PRIMARY KEY, booking_id uuid NOT NULL REFERENCES bookings(id), actor_id text NOT NULL,
 action text NOT NULL, details jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS booking_commands (
 organization_id uuid NOT NULL REFERENCES organizations(id), command_key uuid NOT NULL,
 actor_id text NOT NULL, kind text NOT NULL, request_hash text NOT NULL, response jsonb,
 PRIMARY KEY(organization_id,command_key)
);
