-- Permit invoice deletion only inside the owner-verified booking deletion transaction.
-- Generated invoices remain immutable for all other operations.
CREATE OR REPLACE FUNCTION booking_invoices_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP = 'DELETE'
    AND current_setting('booking_app.delete_booking_id', true) = OLD.booking_id::text
    AND EXISTS (
      SELECT 1 FROM memberships m
      WHERE m.organization_id = OLD.organization_id
        AND m.user_id = current_setting('booking_app.delete_booking_actor', true)
        AND m.role = 'owner' AND m.active = true
    ) THEN
   RETURN OLD;
 END IF;
 RAISE EXCEPTION 'Generated invoices cannot be changed or deleted.';
END;
$$;
