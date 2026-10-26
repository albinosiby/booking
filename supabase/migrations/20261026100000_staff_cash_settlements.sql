BEGIN;
SET LOCAL search_path = booking_app, pg_catalog;
SET LOCAL lock_timeout = '10s';
DO $$
BEGIN
 IF to_regclass('booking_app.memberships') IS NULL OR to_regclass('booking_app.finance_events') IS NULL THEN
  RAISE EXCEPTION 'booking_app.memberships or finance_events is missing. Select the live Booking OS project scwwkaywewecspsrskft and apply its prerequisite migrations first.';
 END IF;
END;
$$;
CREATE TABLE booking_app.staff_cash_settlements (
 id uuid PRIMARY KEY,
 organization_id uuid NOT NULL REFERENCES booking_app.organizations(id),
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
 FOREIGN KEY(membership_id,organization_id) REFERENCES booking_app.memberships(id,organization_id),
 UNIQUE(organization_id,command_key),
 CHECK(balance_after_minor = balance_before_minor + CASE WHEN direction='collect' THEN -amount_minor ELSE amount_minor END)
);
CREATE INDEX staff_cash_settlements_staff_idx ON booking_app.staff_cash_settlements(organization_id,membership_id,settled_at DESC);
CREATE TABLE booking_app.staff_cash_tracking (
 organization_id uuid PRIMARY KEY REFERENCES booking_app.organizations(id) ON DELETE CASCADE,
 started_at timestamptz NOT NULL
);
-- Cash collected before this moment is not counted as held by staff. Organizations created later count from the start.
INSERT INTO booking_app.staff_cash_tracking(organization_id,started_at) SELECT id,now() FROM booking_app.organizations;
ALTER TABLE booking_app.staff_cash_settlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE booking_app.staff_cash_tracking ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON booking_app.staff_cash_settlements, booking_app.staff_cash_tracking FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON booking_app.staff_cash_settlements TO booking_api;
GRANT SELECT ON booking_app.staff_cash_tracking TO booking_api;
CREATE POLICY staff_cash_settlements_server_access ON booking_app.staff_cash_settlements TO booking_api USING (true) WITH CHECK (true);
CREATE POLICY staff_cash_tracking_server_access ON booking_app.staff_cash_tracking TO booking_api USING (true) WITH CHECK (true);
INSERT INTO booking_app.schema_migrations(name) VALUES ('20261026100000_staff_cash_settlements.sql');
COMMIT;
