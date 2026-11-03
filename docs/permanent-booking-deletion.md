# Permanent booking deletion

## Behavior

Booking Details shows **Delete booking permanently** to organization owners for regular bookings. The owner must type the exact booking reference. The API checks the owner role, reference, booking version, and admission links before deleting in one transaction. Staff and the voice agent cannot use this action. Admission visits must be managed in Admissions & Coaching.

Deletion removes the booking, slot allocations, payment and refund rows, corresponding finance events and lines, booking history and notification queue entries, generated invoices, and prior booking command responses. Finance reports, account balances and available slots update from the remaining rows. Shared customer records and invoice number counters stay intact. Staff cash settlements are independent records without a booking link; a previous settlement may need manual reconciliation after its underlying cash payment is erased. The delete command's ID-only result remains in `booking_commands` so a lost response can be retried safely. Already delivered messages or downloaded invoices cannot be recalled.

## API

`POST /v1/bookings/{booking_uuid}/delete` with a valid owner access token:

```json
{
  "command_key": "a-new-uuid-for-this-attempt",
  "version": 2,
  "confirm_reference": "BK-EXAMPLE"
}
```

Success: `{"id":"booking_uuid","deleted":true}`. The same command key and body return the same result. A staff request returns 403; missing booking returns 404; stale version returns 409; wrong reference or admission-linked booking returns 400. `GET /v1/bookings/commands/{command_key}` can recover a committed delete result after a network interruption.

## Production migration and release

The owner applies database migrations. **No production migration or deployment was performed for this feature.** The target is Supabase project `scwwkaywewecspsrskft`, schema `booking_app`. Confirm the selected project before opening SQL Editor. Take and verify a current database backup or restore point first because future deletions cannot be undone by reverting code.

1. Check prerequisites in that project's SQL Editor:

   ```sql
   SELECT to_regclass('booking_app.bookings') AS bookings,
          to_regclass('booking_app.booking_invoices') AS invoices,
          to_regclass('booking_app.booking_notification_events') AS notifications,
          to_regclass('booking_app.finance_events') AS finance_events,
          to_regclass('booking_app.schema_migrations') AS migrations;
   SELECT name FROM booking_app.schema_migrations
    WHERE name IN ('20261027100000_booking_invoices.sql',
                   '20261023071831_firebase_booking_notifications.sql');
   ```

   All five relations and both migration names must exist. Apply any missing prerequisite migrations in order before continuing.

2. Run the complete [production migration](../supabase/migrations/20261103190000_permanent_booking_deletion.sql) once in SQL Editor. Use the `supabase/migrations` file; the `backend/migrations` copy is for the isolated local database. The migration changes the invoice trigger and grants the server role the required deletes. It deletes no existing data.
3. Validate without deleting a real booking:

   ```sql
   SELECT name FROM booking_app.schema_migrations
    WHERE name='20261103190000_permanent_booking_deletion.sql';
   SELECT has_table_privilege('booking_api','booking_app.bookings','DELETE') AS bookings_delete,
          has_table_privilege('booking_api','booking_app.booking_invoices','DELETE') AS invoices_delete,
          has_table_privilege('booking_api','booking_app.finance_events','DELETE') AS finance_delete;
   SELECT pg_get_functiondef('booking_app.booking_invoices_immutable()'::regprocedure);
   ```

   The migration name should appear, the three privilege values should be true, and the function should include the owner membership and booking ID checks.
4. Deploy the generated `booking-api` Edge Function from this checkout, then release the updated Flutter app. Test the flow first with a disposable booking in an isolated environment. In production, verify the action is visible to owners and absent for staff, but do not delete a live booking merely as a smoke test.

## Recovery

If the feature behaves incorrectly before any deletion, restore the previous API/app release and leave the migration in place while preparing a forward fix. After the API rollback, disable invoice deletion with this SQL in the same production project:

```sql
BEGIN;
CREATE OR REPLACE FUNCTION booking_app.booking_invoices_immutable()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'Generated invoices cannot be changed or deleted.';
END;
$$;
REVOKE DELETE ON booking_app.booking_invoices FROM booking_api;
COMMIT;
```

Keep the other grants until their existing uses are checked. Leave the `schema_migrations` entry in place; a future re-enable needs a new forward migration rather than rerunning this one.

If a booking has been deleted, code rollback cannot recreate its payments or invoice. Restore the verified database backup or restore point to a separate database, reconcile subsequent legitimate changes, and then perform an approved recovery. The invoice counter intentionally keeps gaps and must not be reset or reused.
