BEGIN;
SET LOCAL search_path = booking_app, pg_catalog;
SET LOCAL lock_timeout = '10s';
DO $$
BEGIN
 IF to_regclass('booking_app.booking_invoices') IS NULL
    OR to_regclass('booking_app.bookings') IS NULL THEN
   RAISE EXCEPTION 'Booking invoice prerequisites are missing in booking_app.';
 END IF;
END;
$$;
CREATE OR REPLACE FUNCTION booking_app.booking_invoices_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP = 'DELETE'
    AND current_setting('booking_app.delete_booking_id', true) = OLD.booking_id::text
    AND EXISTS (
      SELECT 1 FROM booking_app.memberships m
      WHERE m.organization_id = OLD.organization_id
        AND m.user_id = current_setting('booking_app.delete_booking_actor', true)
        AND m.role = 'owner' AND m.active = true
    ) THEN
   RETURN OLD;
 END IF;
 RAISE EXCEPTION 'Generated invoices cannot be changed or deleted.';
END;
$$;
GRANT DELETE ON booking_app.bookings, booking_app.booking_allocations,
 booking_app.booking_payments, booking_app.booking_history,
 booking_app.booking_commands, booking_app.booking_notification_events,
 booking_app.notification_deliveries,
 booking_app.finance_events, booking_app.finance_lines,
 booking_app.booking_invoices TO booking_api;
CREATE POLICY booking_permanent_delete_server ON booking_app.bookings
 FOR DELETE TO booking_api USING (true);
CREATE POLICY booking_permanent_delete_server ON booking_app.booking_allocations
 FOR DELETE TO booking_api USING (true);
CREATE POLICY booking_permanent_delete_server ON booking_app.booking_payments
 FOR DELETE TO booking_api USING (true);
CREATE POLICY booking_permanent_delete_server ON booking_app.booking_history
 FOR DELETE TO booking_api USING (true);
CREATE POLICY booking_permanent_delete_server ON booking_app.booking_commands
 FOR DELETE TO booking_api USING (true);
CREATE POLICY booking_permanent_delete_server ON booking_app.finance_events
 FOR DELETE TO booking_api USING (true);
CREATE POLICY booking_permanent_delete_server ON booking_app.finance_lines
 FOR DELETE TO booking_api USING (true);
-- Invoices and notification tables already have all-command booking_api policies.
INSERT INTO booking_app.schema_migrations(name)
 VALUES ('20261103190000_permanent_booking_deletion.sql');
COMMIT;
