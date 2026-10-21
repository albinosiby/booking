-- Application service owns tenant authorization; these tables remain private.
CREATE TABLE admissions (
 id uuid PRIMARY KEY, organization_id uuid NOT NULL REFERENCES organizations(id),
 business_id uuid NOT NULL, resource_id uuid NOT NULL, customer_id uuid NOT NULL,
 reference text NOT NULL, plan_id uuid NOT NULL, plan_snapshot jsonb NOT NULL,
 customer_snapshot jsonb NOT NULL, timezone text NOT NULL,
 mode text NOT NULL CHECK(mode IN ('fixed','flexible')),
 starts_on date NOT NULL, expires_on date NOT NULL CHECK(expires_on>=starts_on),
 allowance integer NOT NULL CHECK(allowance BETWEEN 1 AND 10000),
 total_minor integer NOT NULL CHECK(total_minor BETWEEN 0 AND 100000000),
 schedule jsonb NOT NULL, cancelled boolean NOT NULL DEFAULT false,
 renewed_from uuid, version integer NOT NULL DEFAULT 1,
 created_by text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(id,organization_id), UNIQUE(organization_id,reference),
 UNIQUE(id,organization_id,business_id,resource_id,customer_id),
 FOREIGN KEY(business_id,organization_id) REFERENCES businesses(id,organization_id),
 FOREIGN KEY(resource_id,business_id,organization_id) REFERENCES resources(id,business_id,organization_id),
 FOREIGN KEY(customer_id,organization_id) REFERENCES customers(id,organization_id),
 FOREIGN KEY(renewed_from,organization_id) REFERENCES admissions(id,organization_id)
);
CREATE UNIQUE INDEX admissions_renewal_idx ON admissions(renewed_from) WHERE renewed_from IS NOT NULL;
CREATE INDEX admissions_scope_idx ON admissions(organization_id,business_id,resource_id,created_at,id);
CREATE INDEX admissions_customer_idx ON admissions(organization_id,customer_id);
ALTER TABLE bookings ADD COLUMN admission_id uuid;
ALTER TABLE bookings ADD COLUMN admission_attendance text CHECK(admission_attendance IN ('unmarked','present','absent'));
ALTER TABLE bookings ADD COLUMN admission_replacement_for uuid UNIQUE REFERENCES bookings(id);
ALTER TABLE bookings ADD COLUMN admission_waived boolean NOT NULL DEFAULT false;
ALTER TABLE bookings ADD CONSTRAINT bookings_admission_scope_fk FOREIGN KEY(admission_id,organization_id,business_id,resource_id,customer_id) REFERENCES admissions(id,organization_id,business_id,resource_id,customer_id);
ALTER TABLE bookings ADD CONSTRAINT bookings_admission_presence_check CHECK((admission_id IS NULL AND admission_attendance IS NULL) OR (admission_id IS NOT NULL AND admission_attendance IS NOT NULL));
CREATE INDEX bookings_admission_idx ON bookings(admission_id,starts_at);
CREATE TABLE admission_payments (
 id uuid PRIMARY KEY, organization_id uuid NOT NULL, admission_id uuid NOT NULL,
 kind text NOT NULL CHECK(kind IN ('collection','refund')),
 method text NOT NULL CHECK(method IN ('cash','upi','card','bank_transfer')),
 amount_minor integer NOT NULL CHECK(amount_minor BETWEEN 1 AND 100000000),
 reference text NOT NULL DEFAULT '', reason text NOT NULL DEFAULT '',
 received_at timestamptz NOT NULL, recorded_by text NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(id,organization_id),
 FOREIGN KEY(admission_id,organization_id) REFERENCES admissions(id,organization_id)
);
CREATE INDEX admission_payments_admission_idx ON admission_payments(admission_id,recorded_at);
ALTER TABLE finance_events ADD COLUMN admission_payment_id uuid UNIQUE;
ALTER TABLE finance_events ADD CONSTRAINT finance_admission_payment_scope_fk FOREIGN KEY(admission_payment_id,organization_id) REFERENCES admission_payments(id,organization_id);
CREATE TABLE admission_history (
 id uuid PRIMARY KEY, organization_id uuid NOT NULL, admission_id uuid NOT NULL,
 actor_id text NOT NULL, action text NOT NULL, details jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(admission_id,organization_id) REFERENCES admissions(id,organization_id)
);
CREATE INDEX admission_history_admission_idx ON admission_history(admission_id,created_at);
-- Derived usage makes fixed sessions count on time even without a scheduled job.
-- Attendance corrections immediately recalculate balances; original actions remain audited.
CREATE VIEW admission_balances WITH (security_invoker=true) AS
 SELECT a.*,
 COALESCE(u.used,0)::integer AS used,
 GREATEST(0,a.allowance-COALESCE(u.used,0))::integer AS remaining,
 CASE WHEN a.cancelled THEN 'cancelled'
      WHEN COALESCE(u.used,0)>=a.allowance THEN 'completed'
      WHEN (now() AT TIME ZONE a.timezone)::date>a.expires_on THEN 'expired'
      WHEN (now() AT TIME ZONE a.timezone)::date<a.starts_on THEN 'upcoming'
      ELSE 'active' END AS status
 FROM admissions a LEFT JOIN LATERAL (
  SELECT CASE WHEN a.mode='fixed' THEN count(*) FILTER(WHERE b.ends_at<=now() AND NOT b.admission_waived)
   ELSE count(DISTINCT (b.starts_at AT TIME ZONE a.timezone)::date) FILTER(WHERE b.admission_attendance='present') END AS used
  FROM bookings b WHERE b.admission_id=a.id AND b.status<>'cancelled'
 ) u ON true;

ALTER TABLE finance_events DROP CONSTRAINT finance_events_kind_check;
ALTER TABLE finance_events ADD CONSTRAINT finance_events_kind_check CHECK(kind IN ('booking_collection','booking_refund','admission_collection','admission_refund','income','expense','transfer','reversal'));
