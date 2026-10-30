import { randomUUID } from "node:crypto";
import type { Database } from "../common/database";
import { PushFailure, PushSender } from "./fcm-sender";
import type {
  BookingNotificationDetails,
  StaffCashNotificationDetails,
} from "./notification-content";
import { notificationDetailsSql } from "./notification-events";

// Booking scope and cash-handover participants are checked again on every retry.
const eligible = `m.active AND m.user_id=d.user_id AND m.organization_id=e.organization_id
 AND m.user_id NOT LIKE 'sarvam:%'
 AND (
  (e.kind='staff_cash_collected' AND s.id IS NOT NULL AND s.direction='collect' AND
   ((m.user_id=s.settled_by AND m.role='owner') OR
    (m.id=s.membership_id AND m.role<>'owner' AND (m.permissions ? 'collect_payments' OR m.permissions ? 'view_finance'))))
  OR
  (e.kind<>'staff_cash_collected' AND (m.role='owner' OR (m.permissions ? 'manage_bookings' AND EXISTS (
    SELECT 1 FROM staff_assignments a WHERE a.membership_id=m.id AND a.business_id=e.business_id
    AND a.organization_id=e.organization_id AND (jsonb_array_length(a.resource_ids)=0 OR a.resource_ids ? e.resource_id::text)))))
 )`;
type Delivery = {
  event_id: string;
  device_id: string;
  recipient_user_id: string;
};
type Target = {
  token: string;
  version: number;
  kind: string;
  reference: string;
  booking_id: string | null;
  settlement_id: string | null;
  cash_details: StaffCashNotificationDetails | null;
  for_staff: boolean;
  details: BookingNotificationDetails | null;
};

export class NotificationDispatcher {
  constructor(
    private readonly db: Pick<Database, "query" | "transaction">,
    private readonly sender: PushSender,
  ) {}
  async dispatch(limit = 20) {
    limit = Math.max(1, Math.min(40, Math.floor(limit)));
    await this.expand(limit);
    const lease = randomUUID();
    const work = await this.db.transaction(async (db) => {
      await db.query(`UPDATE notification_deliveries SET state='dead',last_error='ATTEMPTS_EXHAUSTED',lease_id=NULL,lease_until=NULL
        WHERE state IN ('pending','processing') AND attempts>=8 AND (lease_until IS NULL OR lease_until<now())`);
      return (
        await db.query<Delivery>(
          `WITH pending AS (
        SELECT event_id,device_id FROM notification_deliveries
        WHERE attempts<8 AND ((state='pending' AND next_attempt_at<=now()) OR (state='processing' AND lease_until<now()))
        ORDER BY next_attempt_at,event_id,device_id FOR UPDATE SKIP LOCKED LIMIT $1
      ) UPDATE notification_deliveries n SET state='processing',attempts=n.attempts+1,lease_id=$2,lease_until=now()+interval '3 minutes'
        FROM pending p WHERE n.event_id=p.event_id AND n.device_id=p.device_id
        RETURNING n.event_id,n.device_id,n.recipient_user_id`,
          [limit, lease],
        )
      ).rows;
    });
    const counts = {
      claimed: work.length,
      sent: 0,
      skipped: 0,
      retry: 0,
      dead: 0,
    };
    // Four sends at once; 40 targets fit comfortably inside the 3-minute lease.
    for (let start = 0; start < work.length; start += 4)
      await Promise.all(
        work.slice(start, start + 4).map(async (item) => {
          const result = await this.deliver(item, lease);
          counts[result]++;
        }),
      );
    return counts;
  }
  private async expand(limit: number) {
    await this.db.transaction(async (db) => {
      const events = (
        await db.query<{ id: string }>(
          `SELECT id FROM booking_notification_events WHERE NOT expanded ORDER BY created_at,id FOR UPDATE SKIP LOCKED LIMIT $1`,
          [limit],
        )
      ).rows;
      for (const event of events) {
        await db.query(
          `INSERT INTO notification_deliveries(event_id,device_id,recipient_user_id)
          SELECT e.id,d.id,d.user_id FROM booking_notification_events e
          LEFT JOIN staff_cash_settlements s ON s.id=e.settlement_id AND s.organization_id=e.organization_id
          JOIN notification_devices d ON d.enabled AND d.bound_at<=e.created_at AND d.last_seen_at>now()-interval '60 days'
          JOIN memberships m ON m.user_id=d.user_id
          WHERE e.id=$1 AND e.created_at>now()-interval '24 hours' AND ${eligible}
          ON CONFLICT(event_id,device_id) DO NOTHING`,
          [event.id],
        );
        await db.query(
          "UPDATE booking_notification_events SET expanded=true WHERE id=$1",
          [event.id],
        );
      }
    });
  }
  private async deliver(
    item: Delivery,
    lease: string,
  ): Promise<"sent" | "skipped" | "retry" | "dead"> {
    const target = (
      await this.db.query<Target>(
        `SELECT d.token,d.version,e.kind,e.reference,e.booking_id,e.settlement_id,e.cash_details,(m.id=s.membership_id) AS for_staff,
        COALESCE(h.details->'notification',CASE WHEN b.resource_id=e.resource_id
          THEN ${notificationDetailsSql} END) AS details
      FROM notification_deliveries n JOIN booking_notification_events e ON e.id=n.event_id
      LEFT JOIN staff_cash_settlements s ON s.id=e.settlement_id AND s.organization_id=e.organization_id
      LEFT JOIN booking_history h ON h.id=e.history_id
      LEFT JOIN bookings b ON b.id=e.booking_id AND b.organization_id=e.organization_id
      JOIN notification_devices d ON d.id=n.device_id
      JOIN memberships m ON m.user_id=d.user_id
      WHERE n.event_id=$1 AND n.device_id=$2 AND n.lease_id=$3 AND n.state='processing'
      AND d.enabled AND n.recipient_user_id=d.user_id AND d.bound_at<=e.created_at
      AND d.last_seen_at>now()-interval '60 days' AND e.created_at>now()-interval '24 hours'
      AND (e.kind='staff_cash_collected' OR b.id IS NOT NULL) AND ${eligible}`,
        [item.event_id, item.device_id, lease],
      )
    ).rows[0];
    if (!target) {
      await this.finish(item, lease, "skipped", "INELIGIBLE_OR_EXPIRED");
      return "skipped";
    }
    try {
      await this.sender.send({
        token: target.token,
        eventId: item.event_id,
        bookingId: target.booking_id,
        settlementId: target.settlement_id,
        cashDetails: target.cash_details,
        forStaff: target.for_staff,
        userId: item.recipient_user_id,
        kind: target.kind,
        reference: target.reference,
        details: target.details,
      });
      await this.finish(item, lease, "sent", "");
      return "sent";
    } catch (error) {
      const failure =
        error instanceof PushFailure
          ? error
          : new PushFailure("SEND_FAILED", true);
      if (failure.unregistered)
        await this.db.query(
          "UPDATE notification_devices SET enabled=false,version=version+1,updated_at=now() WHERE id=$1 AND version=$2",
          [item.device_id, target.version],
        );
      const state = failure.retryable ? "pending" : "dead";
      const result = await this.db.query<{ state: string }>(
        `UPDATE notification_deliveries SET
        state=CASE WHEN attempts>=8 THEN 'dead' ELSE $4 END,last_error=$5,
        next_attempt_at=now()+make_interval(secs=>GREATEST($6::integer,LEAST(3600,30*power(2,attempts-1)::integer))),
        lease_id=NULL,lease_until=NULL
        WHERE event_id=$1 AND device_id=$2 AND lease_id=$3 AND state='processing' RETURNING state`,
        [
          item.event_id,
          item.device_id,
          lease,
          state,
          failure.code,
          Math.ceil(failure.retryAfterSeconds),
        ],
      );
      return result.rows[0]?.state === "pending" ? "retry" : "dead";
    }
  }
  private async finish(
    item: Delivery,
    lease: string,
    state: string,
    error: string,
  ) {
    await this.db.query(
      `UPDATE notification_deliveries SET state=$4,last_error=$5,accepted_at=CASE WHEN $4='sent' THEN now() ELSE NULL END,
      lease_id=NULL,lease_until=NULL WHERE event_id=$1 AND device_id=$2 AND lease_id=$3 AND state='processing'`,
      [item.event_id, item.device_id, lease, state, error],
    );
  }
}
