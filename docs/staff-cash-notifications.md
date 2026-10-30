# Owner-confirmed cash collection notifications

When an owner confirms collecting staff cash, the collection screen shows the
actual collected amount, staff name and remaining balance. A phone notification
goes to that collecting owner and the involved staff member. Other owners, staff
and organizations receive no alert for this handover. Staff must still have
collection or finance access at delivery time. Giving money back to staff and
collecting customer payments do not create this event.

Example staff message:

> Albino collected ₹1,500.00 from you.
> Remaining to hand over: ₹250.00.

The amount, currency, participant names and remaining balance are captured when
the financial transaction is confirmed. Subsequent profile edits or collections
do not rewrite a delayed notification. Android/iOS use the existing registered
devices, notification permission, sound and dispatcher schedule. A collection
confirmed on web can notify the participants' registered phones. Browser push is
not added. Updated app versions accept the new event and open Payments on tap,
after checking the signed-in recipient and current access.

## Implementation and delivery guarantees

The existing private `booking_notification_events` outbox gains an optional
tenant-scoped settlement link and cash snapshot. A source constraint preserves
required booking fields for ordinary booking events and permits the separate
`staff_cash_collected` shape. Existing RLS, device ownership checks and trusted
runtime grants stay in force. No new public endpoint or client-selected push
recipient is introduced. The FCM data payload carries event, settlement and
recipient IDs; amounts appear in the requested notification text.

Enqueue happens inside the handover transaction. Failure to enqueue rolls the
handover back. Replaying the same command returns its original settlement and
does not create another event. Each event/device has one delivery record. Existing
leases, bounded retries, expiry, logout/rebinding checks and invalid-token handling
apply to both event types. Push providers can accept a send before a network
timeout is observed; stable event IDs, Android notification tags and foreground
deduplication reduce repeat displays. A push failure after commit does not undo
the confirmed financial handover. Delivery still depends on registered devices,
OS permission and the existing configured sender/scheduler.

## User-applied migration and release

No live migration or deployment has been performed for this change.

Prerequisites:

1. Use the existing Booking OS project and private `booking_app` schema.
2. Apply all prerequisite migrations, including
   `20261023071831_firebase_booking_notifications.sql` and
   `20261026100000_staff_cash_settlements.sql`.
3. Take a restorable database backup and retain the deployed API, sender and app
   versions. Choose a short low-traffic migration window: the schema changes
   take table locks, with a 10-second lock timeout rather than indefinite waiting.
4. Keep the current Firebase credentials, device registrations, internal dispatch
   secret and scheduler configuration. `BOOKING_PUSH_ENQUEUE_ENABLED` must not be
   `false`, and `BOOKING_PUSH_DISPATCH_ENABLED` must be `true`. No new secret or
   job is required.

Apply in this order:

1. In Supabase SQL Editor, run the entire
   [production migration](../supabase/migrations/20261029143630_staff_cash_collection_notifications.sql).
   It includes BEGIN/COMMIT and a migration marker. Do not run the backend mirror
   against production, and do not push unrelated pending migrations.
2. Run the read-only validation queries below.
3. From `backend`, run `npm run build`, `npm run edge:check`, then
   `npm run edge:build` to regenerate both functions.
4. Deploy the updated **booking-notifications sender first**, preserving its
   internal-secret protection, credentials and existing authentication settings.
5. Deploy the updated **booking-api**. Never deploy this API before the migration:
   it enqueues inside the financial transaction. The older sender cannot route
   this new event correctly, so sender-before-API order matters too.
6. Rebuild/release the native and Flutter web clients. Previously shared APK/web
   archives do not contain this notification update. Older native versions do not
   understand the new notification tap payload.

Validation SQL (run as the database administrator):

```sql
select name, applied_at from booking_app.schema_migrations
where name='20261029143630_staff_cash_collection_notifications.sql';
-- One row.

select column_name,is_nullable from information_schema.columns
where table_schema='booking_app' and table_name='booking_notification_events'
and column_name in ('history_id','booking_id','business_id','resource_id','settlement_id','cash_details');
-- All six are nullable; source checks enforce the required fields for each kind.

select conname,pg_get_constraintdef(oid) from pg_constraint
where conrelid='booking_app.booking_notification_events'::regclass
and conname in ('notification_settlement_org_fk','notification_event_source_check','booking_notification_events_kind_check');
-- Three constraints, including the settlement+organization foreign key.

select relrowsecurity from pg_class
where oid='booking_app.booking_notification_events'::regclass;
-- true.

select role_name,has_table_privilege(role_name,'booking_app.booking_notification_events','SELECT') as can_read
from (values ('anon'),('authenticated'),('booking_api')) r(role_name);
-- false, false, true respectively.
```

Smoke check with authorized test accounts and a real cash handover: register both
phones, collect a partial amount, and verify the owner's amount-specific success
message and both phone alerts. Repeating the same command key must not create
another event. Verify the remaining balance, tap routing, and that unrelated staff
receive nothing. Revoke access before a pending retry and verify it is skipped.
No live financial transaction or actual phone send is performed by automated tests.

## Recovery

A migration error before COMMIT rolls back the schema change. Preserve the error,
confirm its marker is absent and retry the complete file only after resolving the
cause. Do not hide partial mismatches with `IF NOT EXISTS`.

For an application rollback, restore the previous API/client while retaining the
updated sender and additive schema. Existing confirmed cash handovers and pending
notifications remain valid. Do not delete settlements, financial ledger entries,
booking history or notification tables to undo this UI/push feature. If sending
must be paused, use the existing `BOOKING_PUSH_DISPATCH_ENABLED=false` switch;
it also pauses booking pushes, without reversing financial transactions. Prefer a
forward fix over removing the extended schema.

## Verification

Backend isolated PostgreSQL tests cover collection-only participants, other staff
and owners, cross-tenant constraints, full and partial amounts, snapshot content,
idempotent replay, atomic rollback, revoked permissions before retry and private
runtime grants. Existing booking notification and FCM transport tests remain in
the regression suite. All sending uses fake transports in these tests.

Flutter tests cover recipient/type parsing, notification deduplication and account
switching, Payments tap destinations and the owner's confirmed amount message.
Run the notification lifecycle/field tests, staff cash tests, staff Payments tests
and targeted analysis before release.
