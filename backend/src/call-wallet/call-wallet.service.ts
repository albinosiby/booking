import {
  ConflictException,
  HttpException,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from "@nestjs/common";
import { randomBytes, randomUUID } from "node:crypto";
import { z } from "zod";
import { Database, Queryable } from "../common/database";
import type { Actor } from "../common/auth.guard";
import { WorkspaceService } from "../workspace/workspace.service";
import { enqueueCallWalletNotification } from "../notifications/notification-events";
import {
  ORDER_MAX_PAISE,
  ORDER_MIN_PAISE,
  customMinPaise,
  effectiveBilling,
  validRecharge,
  type Billing,
} from "./call-billing";
import {
  PaymentGateway,
  verifyPaymentEvent,
  type GatewayOrder,
} from "./payment-gateway";

const createSchema = z
  .object({
    amount_paise: z
      .number()
      .int()
      .min(ORDER_MIN_PAISE, "Recharge at least ₹100.")
      .max(ORDER_MAX_PAISE, "Recharge at most ₹50,000."),
  })
  .strict();
const orderId = z.string().regex(/^booking_[A-Za-z0-9_-]{8,40}$/);
const historySchema = z
  .object({ offset: z.coerce.number().int().min(0).max(100000).default(0) })
  .strict();
const eventSchema = z
  .object({ order_id: orderId, event_type: z.string().max(100) })
  .strict();

export type OrderStatus =
  | "creating"
  | "created"
  | "pending"
  | "paid"
  | "failed"
  | "cancelled"
  | "expired";

export async function lockWallet(db: Queryable, org: string) {
  await db.query(
    "INSERT INTO call_wallets(organization_id) VALUES($1) ON CONFLICT DO NOTHING",
    [org],
  );
  return (
    await db.query<any>(
      "SELECT * FROM call_wallets WHERE organization_id=$1 FOR UPDATE",
      [org],
    )
  ).rows[0];
}

export type WalletEntry = {
  kind: "recharge" | "call_charge" | "adjustment";
  amount: number;
  reference: string;
  callSeconds?: number;
  rate?: number | null;
  note?: string;
  adminEmail?: string;
  paymentMode?: string | null;
  externalReference?: string | null;
};

/** Appends one ledger entry to a locked wallet, once per (kind, reference).
 * A debit that crosses the low or empty threshold queues one owner alert;
 * a credit back above it re-arms that alert. */
export async function applyEntry(
  tx: Queryable,
  w: any,
  billing: Billing,
  e: WalletEntry,
) {
  const next = Number(w.balance_paise) + e.amount;
  const id = randomUUID();
  const inserted = await tx.query(
    `INSERT INTO call_wallet_ledger(id,organization_id,kind,amount_paise,balance_after_paise,reference,call_seconds,note,
      rate_paise_per_minute,admin_email,payment_mode,external_reference)
     VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) ON CONFLICT DO NOTHING RETURNING id`,
    [
      id,
      w.organization_id,
      e.kind,
      e.amount,
      next,
      e.reference,
      e.callSeconds ?? null,
      e.note ?? "",
      e.rate ?? null,
      e.adminEmail ?? null,
      e.paymentMode ?? null,
      e.externalReference ?? null,
    ],
  );
  if (!inserted.rows.length) return null;
  let low = Boolean(w.low_alert_sent),
    empty = Boolean(w.empty_alert_sent),
    alert: "call_wallet_low" | "call_wallet_empty" | null = null;
  if (e.amount < 0) {
    if (next <= 0 && !empty) [alert, empty, low] = ["call_wallet_empty", true, true];
    else if (next > 0 && next < billing.low_balance_paise && !low)
      [alert, low] = ["call_wallet_low", true];
  } else {
    if (next > 0) empty = false;
    if (next >= billing.low_balance_paise) low = false;
  }
  await tx.query(
    "UPDATE call_wallets SET balance_paise=$2,low_alert_sent=$3,empty_alert_sent=$4,updated_at=now() WHERE organization_id=$1",
    [w.organization_id, next, low, empty],
  );
  if (alert) {
    const rate = billing.rate_paise_per_minute ?? 0;
    await enqueueCallWalletNotification(tx, id, w.organization_id, alert, {
      balance_paise: next,
      minutes_left: rate > 0 && next > 0 ? Math.floor(next / rate) : 0,
      currency: "INR",
    });
  }
  return { id, balance_paise: next };
}

/** Charges each started minute once per call at the client's current rate.
 * Calls before the wallet existed are free; with no rate set, the call is
 * recorded at ₹0 so a later rate is never applied retroactively. */
export async function chargeCall(
  db: Database,
  org: string,
  interactionId: string,
  seconds: number,
  startedAt?: string | null,
) {
  if (!interactionId || !Number.isFinite(seconds) || seconds <= 0) return;
  await db.transaction(async (tx) => {
    const w = await lockWallet(tx, org);
    if (
      startedAt &&
      Date.parse(startedAt) < new Date(w.billing_starts_at).getTime()
    )
      return;
    const billing = await effectiveBilling(tx, w);
    const rate = billing.rate_paise_per_minute;
    await applyEntry(tx, w, billing, {
      kind: "call_charge",
      amount: 0 - Math.ceil(seconds / 60) * (rate ?? 0),
      reference: interactionId,
      callSeconds: Math.round(seconds),
      rate: rate ?? 0,
      note: rate == null ? "No call rate was set." : "",
    });
  });
}

/** What each listed call cost, keyed by interaction ID. */
export async function callCharges(db: Queryable, org: string, ids: string[]) {
  const charges = new Map<string, number>();
  if (!ids.length) return charges;
  const rows = (
    await db.query<any>(
      "SELECT reference,amount_paise FROM call_wallet_ledger WHERE organization_id=$1 AND kind='call_charge' AND reference = ANY($2::text[])",
      [org, ids],
    )
  ).rows;
  for (const r of rows) charges.set(r.reference, 0 - Number(r.amount_paise));
  return charges;
}

export function ledgerItem(r: any) {
  return {
    id: r.id,
    kind: r.kind,
    amount_paise: Number(r.amount_paise),
    balance_after_paise: Number(r.balance_after_paise),
    reference: r.reference,
    call_seconds: r.call_seconds == null ? null : Number(r.call_seconds),
    rate_paise_per_minute:
      r.rate_paise_per_minute == null ? null : Number(r.rate_paise_per_minute),
    payment_method: r.payment_method ?? r.payment_mode ?? "",
    external_reference: r.external_reference ?? "",
    note: r.note,
    created_at: new Date(r.created_at).toISOString(),
  };
}

function gatewayStatus(g: GatewayOrder): OrderStatus {
  if (g.orderStatus === "PAID") return "paid";
  if (g.orderStatus === "EXPIRED" || g.orderStatus === "TERMINATED")
    return "expired";
  const payment = g.payment?.status;
  if (payment === "FAILED") return "failed";
  if (payment === "USER_DROPPED" || payment === "CANCELLED") return "cancelled";
  return g.payment ? "pending" : "created";
}

@Injectable()
export class CallWalletService {
  gateway = new PaymentGateway();
  constructor(
    private readonly db: Database,
    private readonly workspace: WorkspaceService,
  ) {}
  async status(actor: Actor) {
    const m = await this.workspace.member(actor, true);
    return this.summary(m.organization_id);
  }
  async transactions(actor: Actor, input: unknown) {
    const q = historySchema.parse(input);
    const m = await this.workspace.member(actor, true);
    return this.page(m.organization_id, q.offset, 50);
  }
  private async summary(org: string) {
    const w = (
      await this.db.query<any>(
        "SELECT * FROM call_wallets WHERE organization_id=$1",
        [org],
      )
    ).rows[0];
    const b = await effectiveBilling(this.db, w);
    const balance = Number(w?.balance_paise ?? 0),
      rate = b.rate_paise_per_minute;
    const plans = [...b.plans_paise].sort((x, y) => x - y);
    const customMin = customMinPaise(b);
    const recent = await this.page(org, 0, 20);
    return {
      currency: "INR",
      balance_paise: balance,
      rate_paise_per_minute: rate ?? 0,
      rate_set: rate != null,
      minutes_left: rate && balance > 0 ? Math.floor(balance / rate) : 0,
      low_balance_paise: b.low_balance_paise,
      recharge: {
        enabled: this.gateway.configured() && rate != null,
        plans_paise: plans,
        custom_enabled: b.custom_enabled,
        custom_min_paise: customMin,
        custom_max_paise: b.custom_max_paise,
        // Read by app builds released before admin-managed plans.
        presets_paise: plans,
        min_paise: b.custom_enabled
          ? Math.min(customMin, plans[0] ?? customMin)
          : (plans[0] ?? ORDER_MIN_PAISE),
        max_paise: b.custom_enabled
          ? Math.max(b.custom_max_paise, plans.at(-1) ?? 0)
          : (plans.at(-1) ?? ORDER_MIN_PAISE),
      },
      transactions: recent.items,
      next_offset: recent.next_offset,
    };
  }
  private async page(org: string, offset: number, limit: number) {
    const rows = (
      await this.db.query<any>(
        `SELECT l.*,o.payment_method
   FROM call_wallet_ledger l LEFT JOIN call_wallet_orders o ON l.kind='recharge' AND o.order_id=l.reference
   WHERE l.organization_id=$1 ORDER BY l.created_at DESC,l.id LIMIT $2 OFFSET $3`,
        [org, limit + 1, offset],
      )
    ).rows;
    return {
      items: rows.slice(0, limit).map(ledgerItem),
      next_offset: rows.length > limit ? offset + limit : null,
    };
  }
  async createOrder(actor: Actor, input: unknown) {
    const v = createSchema.parse(input);
    const m = await this.workspace.member(actor, true);
    const billing = await effectiveBilling(
      this.db,
      (
        await this.db.query<any>(
          "SELECT * FROM call_wallets WHERE organization_id=$1",
          [m.organization_id],
        )
      ).rows[0],
    );
    if (billing.rate_paise_per_minute == null)
      throw new ConflictException("Online recharge is not available yet.");
    validRecharge(billing, v.amount_paise);
    const recent = Number(
      (
        await this.db.query<any>(
          "SELECT count(*) AS n FROM call_wallet_orders WHERE organization_id=$1 AND created_at > now() - interval '1 hour'",
          [m.organization_id],
        )
      ).rows[0].n,
    );
    if (recent >= 20)
      throw new HttpException(
        "Too many recharge attempts. Please try again later.",
        429,
      );
    const org = (
      await this.db.query<any>(
        "SELECT name,contact_phone FROM organizations WHERE id=$1",
        [m.organization_id],
      )
    ).rows[0];
    const id = `booking_${Date.now().toString(36)}_${randomBytes(6).toString("hex")}`;
    await this.db.query(
      "INSERT INTO call_wallet_orders(order_id,organization_id,membership_id,amount_paise) VALUES($1,$2,$3,$4)",
      [id, m.organization_id, m.id, v.amount_paise],
    );
    try {
      const order = await this.gateway.createOrder({
        orderId: id,
        amountPaise: v.amount_paise,
        customer: {
          id: m.organization_id,
          name: String(actor.name || org?.name || "").slice(0, 100),
          email: String(actor.email ?? "").slice(0, 100),
          phone: String(org?.contact_phone ?? "")
            .replace(/\D/g, "")
            .slice(-10),
        },
        returnUrl: process.env.CALL_WALLET_RETURN_URL?.trim() || undefined,
      });
      await this.db.query(
        "UPDATE call_wallet_orders SET status='created',payment_session_id=$2,updated_at=now() WHERE order_id=$1",
        [id, order.paymentSessionId],
      );
      return {
        order_id: id,
        payment_session_id: order.paymentSessionId,
        environment: order.environment,
        amount_paise: v.amount_paise,
      };
    } catch (error) {
      await this.db.query(
        "UPDATE call_wallet_orders SET status='failed',updated_at=now() WHERE order_id=$1",
        [id],
      );
      throw error;
    }
  }
  /** Called by the app after checkout. Cashfree's server status decides, never the client. */
  async verify(actor: Actor, id: unknown) {
    const order = orderId.parse(id);
    const m = await this.workspace.member(actor, true);
    const row = (
      await this.db.query<any>(
        "SELECT amount_paise FROM call_wallet_orders WHERE order_id=$1 AND organization_id=$2",
        [order, m.organization_id],
      )
    ).rows[0];
    if (!row) throw new NotFoundException("Recharge not found.");
    const status = await this.sync(order);
    return {
      order_id: order,
      status,
      amount_paise: Number(row.amount_paise),
      wallet: await this.summary(m.organization_id),
    };
  }
  /** Signed Cashfree event forwarded by the payment backend. */
  async paymentEvent(
    headers: { timestamp: string | null; signature: string | null },
    input: unknown,
  ) {
    const parsed = eventSchema.safeParse(input);
    if (
      !parsed.success ||
      !verifyPaymentEvent({
        ...headers,
        orderId: parsed.data.order_id,
        eventType: parsed.data.event_type,
      })
    )
      throw new UnauthorizedException("Invalid payment event.");
    const status = await this.sync(parsed.data.order_id);
    return { received: true, status };
  }
  private async sync(id: string): Promise<OrderStatus | "unknown"> {
    const row = (
      await this.db.query<any>(
        "SELECT status FROM call_wallet_orders WHERE order_id=$1",
        [id],
      )
    ).rows[0];
    if (!row) return "unknown";
    if (row.status === "paid") return "paid";
    const g = await this.gateway.order(id);
    const status = gatewayStatus(g);
    if (status === "paid") {
      await this.credit(id, g);
      return "paid";
    }
    await this.db.query(
      "UPDATE call_wallet_orders SET status=$2,cf_payment_id=COALESCE($3,cf_payment_id),payment_method=COALESCE($4,payment_method),updated_at=now() WHERE order_id=$1 AND status<>'paid'",
      [id, status, g.payment?.cfPaymentId || null, g.payment?.method || null],
    );
    return status;
  }
  private async credit(id: string, g: GatewayOrder) {
    await this.db.transaction(async (tx) => {
      const order = (
        await tx.query<any>(
          "SELECT * FROM call_wallet_orders WHERE order_id=$1 FOR UPDATE",
          [id],
        )
      ).rows[0];
      if (order.status === "paid") return;
      const amount = Number(order.amount_paise);
      if (g.currency !== "INR" || Number(g.amountPaise) !== amount)
        throw new ConflictException(
          "The paid amount does not match this recharge.",
        );
      const w = await lockWallet(tx, order.organization_id);
      await applyEntry(tx, w, await effectiveBilling(tx, w), {
        kind: "recharge",
        amount,
        reference: id,
      });
      await tx.query(
        "UPDATE call_wallet_orders SET status='paid',cf_payment_id=$2,payment_method=$3,paid_at=now(),updated_at=now() WHERE order_id=$1",
        [id, g.payment?.cfPaymentId || null, g.payment?.method || null],
      );
    });
  }
}
