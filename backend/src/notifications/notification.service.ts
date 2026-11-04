import { createHash, timingSafeEqual } from "node:crypto";
import {
  Injectable,
  ForbiddenException,
  ConflictException,
} from "@nestjs/common";
import { z } from "zod";
import { Database } from "../common/database";
import type { Actor } from "../common/auth.guard";
import { eligibleNotificationRecipientSql } from "./notification-dispatcher";
import { notificationDetailsSql } from "./notification-events";
import {
  bookingNotificationBody,
  callWalletNotificationBody,
  staffCashNotificationBody,
  subscriptionFeeNotificationBody,
  type BookingNotificationDetails,
  type CallWalletNotificationDetails,
  type StaffCashNotificationDetails,
  type SubscriptionFeeDetails,
} from "./notification-content";

const registration = z
  .object({
    installation_id: z.uuid(),
    installation_secret: z.string().regex(/^[a-f0-9]{64}$/),
    token: z.string().min(20).max(4096),
    platform: z.enum(["android", "ios"]),
  })
  .strict();
const proof = z
  .object({ installation_secret: registration.shape.installation_secret })
  .strict();
function hash(value: string) {
  return createHash("sha256").update(value).digest("hex");
}
function matches(value: string, expected: string) {
  return timingSafeEqual(
    Buffer.from(hash(value), "hex"),
    Buffer.from(expected, "hex"),
  );
}

@Injectable()
export class NotificationService {
  constructor(private readonly db: Database) {}

  async list(actor: Actor, before?: string) {
    if (actor.uid.startsWith("sarvam:"))
      throw new ForbiddenException("User session required.");
    const cursor = before ? z.uuid().parse(before) : null;
    type Row = {
      id: string;
      created_at: Date | string;
      kind: string;
      reference: string;
      booking_id: string | null;
      admission_id: string | null;
      for_staff: boolean;
      cash_details: StaffCashNotificationDetails | null;
      wallet_details: CallWalletNotificationDetails | null;
      fee_details: SubscriptionFeeDetails | null;
      details: BookingNotificationDetails | null;
    };
    const rows = (
      await this.db.query<Row>(
        `SELECT e.id,e.created_at,e.kind,e.reference,e.booking_id,e.admission_id,
          (m.id=s.membership_id) AS for_staff,e.cash_details,e.wallet_details,e.fee_details,
          COALESCE(h.details->'notification',CASE WHEN b.resource_id=e.resource_id
            THEN ${notificationDetailsSql} END) AS details
        FROM booking_notification_events e
        JOIN LATERAL (SELECT $1::text AS user_id) d ON true
        JOIN memberships m ON m.user_id=d.user_id AND m.organization_id=e.organization_id
        LEFT JOIN staff_cash_settlements s ON s.id=e.settlement_id AND s.organization_id=e.organization_id
        LEFT JOIN booking_history h ON h.id=e.history_id
        LEFT JOIN bookings b ON b.id=e.booking_id AND b.organization_id=e.organization_id
        LEFT JOIN admissions ad ON ad.id=e.admission_id AND ad.organization_id=e.organization_id
          AND NOT ad.cancelled AND ad.deleted_at IS NULL
        WHERE ${eligibleNotificationRecipientSql}
          AND (e.kind IN ('staff_cash_collected','call_wallet_low','call_wallet_empty')
            OR b.id IS NOT NULL OR ad.id IS NOT NULL)
          AND ($2::uuid IS NULL OR (e.created_at,e.id)<(
            SELECT created_at,id FROM booking_notification_events WHERE id=$2))
        ORDER BY e.created_at DESC,e.id DESC LIMIT 51`,
        [actor.uid, cursor],
      )
    ).rows;
    const page = rows.slice(0, 50);
    return {
      items: page.map((row) => {
        const title =
          (
            {
              created: "Order placed",
              cancelled: "Order cancelled",
              rescheduled: "Order rescheduled",
              staff_cash_collected: "Cash collection confirmed",
              call_wallet_low: "Call balance is low",
              call_wallet_empty: "Call balance is empty",
              subscription_fee_due: "Subscription fee due",
            } as Record<string, string>
          )[row.kind] ?? "Notification";
        let body: string;
        try {
          body =
            row.kind === "staff_cash_collected"
              ? staffCashNotificationBody(row.cash_details!, row.for_staff)
              : row.kind === "subscription_fee_due"
                ? subscriptionFeeNotificationBody(row.fee_details!)
                : row.kind.startsWith("call_wallet_")
                  ? callWalletNotificationBody(
                      row.wallet_details!,
                      row.kind === "call_wallet_empty",
                    )
                  : bookingNotificationBody(row.reference, row.details);
        } catch {
          body = row.reference;
        }
        const route =
          row.kind === "staff_cash_collected"
            ? "/payments"
            : row.kind === "subscription_fee_due"
              ? `/admissions/${row.admission_id}`
              : row.kind.startsWith("call_wallet_")
                ? "/profile/agent-calls/wallet"
                : `/booking/${row.booking_id}`;
        return {
          id: row.id,
          created_at: row.created_at,
          kind: row.kind,
          title,
          body,
          route,
        };
      }),
      next_cursor: rows.length > 50 ? page.at(-1)!.id : null,
    };
  }

  async register(actor: Actor, input: unknown) {
    const v = registration.parse(input);
    if (actor.uid.startsWith("sarvam:"))
      throw new ForbiddenException("User session required.");
    return this.db.transaction(async (db) => {
      // Serializes the first registration too, when no row exists to lock yet.
      await db.query("SELECT pg_advisory_xact_lock(hashtext($1))", [
        v.installation_id,
      ]);
      const old = (
        await db.query<{ id: string; proof_hash: string }>(
          "SELECT id,proof_hash FROM notification_devices WHERE id=$1 FOR UPDATE",
          [v.installation_id],
        )
      ).rows[0];
      if (old && !matches(v.installation_secret, old.proof_hash))
        throw new ForbiddenException("Installation proof is invalid.");
      const collision = (
        await db.query<{ id: string }>(
          "SELECT id FROM notification_devices WHERE token=$1 AND id<>$2",
          [v.token, v.installation_id],
        )
      ).rows[0];
      if (collision)
        throw new ConflictException(
          "Refresh this device's notification registration.",
        );
      await db.query(
        `INSERT INTO notification_devices(id,user_id,proof_hash,token,platform)
         VALUES($1,$2,$3,$4,$5)
         ON CONFLICT(id) DO UPDATE SET user_id=EXCLUDED.user_id,token=EXCLUDED.token,platform=EXCLUDED.platform,
         version=CASE WHEN notification_devices.token<>EXCLUDED.token OR notification_devices.user_id<>EXCLUDED.user_id OR NOT notification_devices.enabled THEN notification_devices.version+1 ELSE notification_devices.version END,
         bound_at=CASE WHEN notification_devices.user_id<>EXCLUDED.user_id OR NOT notification_devices.enabled THEN now() ELSE notification_devices.bound_at END,
         enabled=true,updated_at=now(),last_seen_at=now()`,
        [
          v.installation_id,
          actor.uid,
          hash(v.installation_secret),
          v.token,
          v.platform,
        ],
      );
      return { id: v.installation_id, registered: true };
    });
  }

  async unregister(actor: Actor, id: string, input: unknown) {
    z.uuid().parse(id);
    const v = proof.parse(input);
    return this.disable(id, v.installation_secret, actor.uid);
  }

  /** Allows a logged-out installation to finish its own previously failed unlink. */
  async revokeInstallation(input: unknown) {
    const v = proof.extend({ installation_id: z.uuid() }).parse(input);
    return this.disable(v.installation_id, v.installation_secret);
  }

  private async disable(id: string, secret: string, userId?: string) {
    // The proof is an unguessable 256-bit device credential; never return token/account data.
    await this.db.query(
      `UPDATE notification_devices SET enabled=false,version=version+1,updated_at=now()
       WHERE id=$1 AND proof_hash=$2 AND ($3::text IS NULL OR user_id=$3) AND enabled`,
      [id, hash(secret), userId ?? null],
    );
    return { unregistered: true };
  }
}
