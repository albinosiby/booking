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
