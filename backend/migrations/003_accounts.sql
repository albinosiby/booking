CREATE TABLE money_accounts (
 id uuid PRIMARY KEY, organization_id uuid NOT NULL REFERENCES organizations(id),
 name text NOT NULL CHECK(length(name) BETWEEN 2 AND 100), kind text NOT NULL CHECK(kind IN ('cash','bank','clearing')),
 bank_name text NOT NULL DEFAULT '', last_four text NOT NULL DEFAULT '' CHECK(length(last_four)<=4),
 request_hash text, system_key text, is_primary boolean NOT NULL DEFAULT false, active boolean NOT NULL DEFAULT true,
 opening_set boolean NOT NULL DEFAULT false, opening_minor bigint NOT NULL DEFAULT 0 CHECK(abs(opening_minor)<=100000000000), opening_at timestamptz NOT NULL DEFAULT '2000-01-01',
 created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(id,organization_id), UNIQUE(organization_id,system_key),
 CHECK(NOT is_primary OR (kind='bank' AND active))
);
CREATE UNIQUE INDEX money_primary_idx ON money_accounts(organization_id) WHERE is_primary;
CREATE TABLE payment_routes (
 id uuid PRIMARY KEY, organization_id uuid NOT NULL REFERENCES organizations(id), business_id uuid NOT NULL, resource_id uuid,
 method text NOT NULL CHECK(method IN ('upi','card','bank_transfer')), account_id uuid NOT NULL,
 FOREIGN KEY(business_id,organization_id) REFERENCES businesses(id,organization_id),
 FOREIGN KEY(resource_id,business_id,organization_id) REFERENCES resources(id,business_id,organization_id),
 FOREIGN KEY(account_id,organization_id) REFERENCES money_accounts(id,organization_id)
);
CREATE UNIQUE INDEX route_business_idx ON payment_routes(organization_id,business_id,method) WHERE resource_id IS NULL;
CREATE UNIQUE INDEX route_space_idx ON payment_routes(organization_id,business_id,resource_id,method) WHERE resource_id IS NOT NULL;
CREATE TABLE finance_events (
 id uuid PRIMARY KEY, organization_id uuid NOT NULL REFERENCES organizations(id),
 kind text NOT NULL CHECK(kind IN ('booking_collection','booking_refund','income','expense','transfer','reversal')),
 business_id uuid, resource_id uuid, booking_payment_id uuid UNIQUE REFERENCES booking_payments(id),
 category text NOT NULL DEFAULT '', reason text NOT NULL, reference text NOT NULL DEFAULT '',
 occurred_at timestamptz NOT NULL, recorded_at timestamptz NOT NULL DEFAULT now(), recorded_by text NOT NULL,
 command_key uuid, request_hash text, reverses_id uuid UNIQUE REFERENCES finance_events(id),
 FOREIGN KEY(business_id,organization_id) REFERENCES businesses(id,organization_id),
 FOREIGN KEY(resource_id,business_id,organization_id) REFERENCES resources(id,business_id,organization_id),
 UNIQUE(organization_id,command_key), UNIQUE(id,organization_id), CHECK(resource_id IS NULL OR business_id IS NOT NULL)
);
CREATE TABLE finance_lines (
 id uuid PRIMARY KEY, organization_id uuid NOT NULL, event_id uuid NOT NULL, account_id uuid NOT NULL,
 method text NOT NULL CHECK(method IN ('cash','upi','card','bank_transfer','transfer')), amount_minor bigint NOT NULL CHECK(amount_minor<>0),
 FOREIGN KEY(event_id,organization_id) REFERENCES finance_events(id,organization_id),
 FOREIGN KEY(account_id,organization_id) REFERENCES money_accounts(id,organization_id)
);
CREATE INDEX finance_org_date_idx ON finance_events(organization_id,occurred_at,id);
CREATE INDEX finance_business_date_idx ON finance_events(organization_id,business_id,resource_id,occurred_at);
CREATE INDEX finance_account_idx ON finance_lines(account_id,event_id);
INSERT INTO money_accounts(id,organization_id,name,kind,system_key)
 SELECT gen_random_uuid(),id,'Cash in hand','cash','cash' FROM organizations;
INSERT INTO money_accounts(id,organization_id,name,kind,system_key)
 SELECT gen_random_uuid(),id,'Unassigned bank receipts','clearing','unassigned' FROM organizations;
INSERT INTO finance_events(id,organization_id,kind,business_id,resource_id,booking_payment_id,reason,reference,occurred_at,recorded_by)
 SELECT gen_random_uuid(),p.organization_id,CASE WHEN p.kind='collection' THEN 'booking_collection' ELSE 'booking_refund' END,
 b.business_id,b.resource_id,p.id,CASE WHEN p.reason='' THEN 'Booking '||b.reference ELSE p.reason END,p.reference,p.received_at,p.recorded_by
 FROM booking_payments p JOIN bookings b ON b.id=p.booking_id;
INSERT INTO finance_lines(id,organization_id,event_id,account_id,method,amount_minor)
 SELECT gen_random_uuid(),e.organization_id,e.id,a.id,p.method,CASE WHEN p.kind='collection' THEN p.amount_minor ELSE -p.amount_minor END
 FROM finance_events e JOIN booking_payments p ON p.id=e.booking_payment_id
 JOIN money_accounts a ON a.organization_id=e.organization_id AND a.system_key=CASE WHEN p.method='cash' THEN 'cash' ELSE 'unassigned' END;
