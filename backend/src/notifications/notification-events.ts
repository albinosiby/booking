import type { Queryable } from "../common/database";

// Uses the authoritative booking row aliased as b, including its pricing snapshot.
export const notificationDetailsSql = `jsonb_build_object(
  'customer_name',b.customer_snapshot->>'name',
  'space_name',b.price_snapshot->>'space_name',
  'starts_at',b.starts_at,'ends_at',b.ends_at,
  'timezone',b.price_snapshot->>'timezone')`;

/** Called inside the booking transaction, after its authoritative history row. */
export async function enqueueBookingNotification(
  db: Queryable,
  historyId: string,
) {
  if (process.env.BOOKING_PUSH_ENQUEUE_ENABLED === "false") return;
  await db.query(
    `INSERT INTO booking_notification_events(id,history_id,booking_id,organization_id,business_id,resource_id,kind,reference)
     SELECT h.id,h.id,b.id,b.organization_id,b.business_id,b.resource_id,h.action,b.reference
     FROM booking_history h JOIN bookings b ON b.id=h.booking_id
     WHERE h.id=$1 AND h.action IN ('created','cancelled','rescheduled') AND b.admission_id IS NULL
     ON CONFLICT(history_id) DO NOTHING`,
    [historyId],
  );
}

/** Enqueue in the same transaction as the confirmed handover; its UUID is the event key. */
export async function enqueueStaffCashNotification(
  db: Queryable,
  settlementId: string,
) {
  if (process.env.BOOKING_PUSH_ENQUEUE_ENABLED === "false") return;
  await db.query(
    `INSERT INTO booking_notification_events(id,settlement_id,organization_id,kind,reference,cash_details)
    SELECT s.id,s.id,s.organization_id,'staff_cash_collected','Cash handover',
      jsonb_build_object('amount_minor',s.amount_minor,'balance_after_minor',s.balance_after_minor,
        'currency',o.currency,'staff_name',m.display_name,'collector_name',owner.display_name)
    FROM staff_cash_settlements s JOIN organizations o ON o.id=s.organization_id
    JOIN memberships m ON m.id=s.membership_id AND m.organization_id=s.organization_id
    JOIN memberships owner ON owner.user_id=s.settled_by AND owner.organization_id=s.organization_id
    WHERE s.id=$1 AND s.direction='collect'
    ON CONFLICT(settlement_id) DO NOTHING`,
    [settlementId],
  );
}
