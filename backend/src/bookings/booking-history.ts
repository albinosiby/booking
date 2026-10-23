import { randomUUID } from "node:crypto";
import type { Queryable } from "../common/database";
import {
  enqueueBookingNotification,
  notificationDetailsSql,
} from "../notifications/notification-events";

/** Append audit history and its notification event inside the booking transaction. */
export async function recordBookingHistory(
  db: Queryable,
  bookingId: string,
  actorId: string,
  action: string,
  details: Record<string, unknown>,
) {
  const id = randomUUID();
  const result = await db.query<{ id: string }>(
    `INSERT INTO booking_history(id,booking_id,actor_id,action,details)
     SELECT $1,b.id,$3,$4,$5::jsonb || CASE
       WHEN $4 IN ('created','cancelled','rescheduled')
       THEN jsonb_build_object('notification',${notificationDetailsSql})
       ELSE '{}'::jsonb END
     FROM bookings b WHERE b.id=$2 RETURNING id`,
    [id, bookingId, actorId, action, JSON.stringify(details)],
  );
  if (!result.rows.length)
    throw new Error("Booking history source unavailable");
  if (["created", "cancelled", "rescheduled"].includes(action))
    await enqueueBookingNotification(db, id);
  return id;
}
