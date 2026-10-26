-- Staff cash handover. Records cash the owner collects from, or gives to, a staff member.
-- The ledger is NOT changed: cash already sits in the "Cash in hand" account when staff collect it.
-- Do not apply to a live database without owner authorization.
-- Rollback: see end of file.
CREATE TABLE staff_cash_settlements (
 id uuid PRIMARY KEY,
 organization_id uuid NOT NULL REFERENCES organizations(id),
 membership_id uuid NOT NULL,
 direction text NOT NULL CHECK(direction IN ('collect','give')),
 amount_minor bigint NOT NULL CHECK(amount_minor BETWEEN 1 AND 100000000000),
 balance_before_minor bigint NOT NULL,
 balance_after_minor bigint NOT NULL,
 settled_by text NOT NULL,
 settled_at timestamptz NOT NULL DEFAULT now(),
 note text NOT NULL DEFAULT '' CHECK(length(note)<=300),
 command_key uuid NOT NULL,
 request_hash text NOT NULL,
 FOREIGN KEY(membership_id,organization_id) REFERENCES memberships(id,organization_id),
 UNIQUE(organization_id,command_key),
 CHECK(balance_after_minor = balance_before_minor + CASE WHEN direction='collect' THEN -amount_minor ELSE amount_minor END)
);
CREATE INDEX staff_cash_settlements_staff_idx ON staff_cash_settlements(organization_id,membership_id,settled_at DESC);
-- Cash collected before this date is not counted as held by staff. Orgs created later count from the start.
CREATE TABLE staff_cash_tracking (
 organization_id uuid PRIMARY KEY REFERENCES organizations(id),
 started_at timestamptz NOT NULL
);
INSERT INTO staff_cash_tracking(organization_id,started_at) SELECT id,now() FROM organizations;
-- Rollback: DROP TABLE staff_cash_settlements; DROP TABLE staff_cash_tracking;
