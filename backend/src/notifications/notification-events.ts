import type { Queryable } from "../common/database";

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
