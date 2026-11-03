import { ServiceUnavailableException } from "@nestjs/common";
import { createHmac, timingSafeEqual } from "node:crypto";

/** Cashfree status as reported by the shared payment backend (payout-backend). */
export type GatewayOrder = {
  orderId: string;
  orderStatus: "ACTIVE" | "PAID" | "EXPIRED" | "TERMINATED" | string;
  amountPaise: number;
  currency: string;
  payment: {
    cfPaymentId: string;
    status: string;
    method: string;
  } | null;
};

const config = () => ({
  base: (process.env.PAYMENT_API_BASE_URL ?? "").trim().replace(/\/+$/, ""),
  key: (process.env.BOOKING_PG_API_KEY ?? "").trim(),
});

/** Server-to-server client. The Cashfree secret stays on the payment backend. */
export class PaymentGateway {
  http: typeof fetch = (...a) => fetch(...a);
  configured() {
    const c = config();
    return !!c.base && !!c.key;
  }
  private async request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const c = config();
    if (!c.base || !c.key)
      throw new ServiceUnavailableException(
        "Online recharge is not available yet.",
      );
    let res: Response;
    try {
      res = await this.http(c.base + path, {
        ...init,
        signal: AbortSignal.timeout(20000),
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${c.key}`,
        },
      });
    } catch {
      throw new ServiceUnavailableException(
        "The payment service is unavailable. Please try again.",
      );
    }
    const body = (await res.json().catch(() => null)) as any;
    if (!res.ok) {
      // The payment backend's reason is safe to log and names the failing field
      // or Cashfree's message; secrets are never part of it.
      console.error("[call-wallet] payment service refused", {
        path: path.replace(/booking_[A-Za-z0-9_-]+/, "booking_…"),
        status: res.status,
        error: String(body?.error ?? "").slice(0, 200),
        detail: String(body?.detail ?? "").slice(0, 300),
      });
      throw new ServiceUnavailableException(
        res.status === 401
          ? "Online recharge is not set up correctly. Please contact support."
          : "The payment service could not process this request. Please try again.",
      );
    }
    return body as T;
  }
  createOrder(input: {
    orderId: string;
    amountPaise: number;
    customer: { id: string; name: string; email: string; phone: string };
    returnUrl?: string;
  }) {
    return this.request<{
      orderId: string;
      paymentSessionId: string;
      environment: "sandbox" | "production";
    }>("/booking/pg/orders", {
      method: "POST",
      body: JSON.stringify(input),
    });
  }
  order(orderId: string) {
    return this.request<GatewayOrder>(
      `/booking/pg/orders/${encodeURIComponent(orderId)}`,
    );
  }
}

/** Payment events forwarded by the payment backend sign `timestamp.order_id.event_type`. */
export function verifyPaymentEvent(input: {
  timestamp: string | null;
  signature: string | null;
  orderId: string;
  eventType: string;
  now?: number;
}) {
  const secret = (process.env.BOOKING_PG_EVENT_SECRET ?? "").trim();
  const ts = Number(input.timestamp);
  if (!secret || !input.signature || !Number.isFinite(ts)) return false;
  if (Math.abs((input.now ?? Date.now()) - ts) > 5 * 60000) return false;
  const expected = createHmac("sha256", secret)
    .update(`${input.timestamp}.${input.orderId}.${input.eventType}`)
    .digest("base64");
  const a = Buffer.from(expected),
    b = Buffer.from(input.signature);
  return a.length === b.length && timingSafeEqual(a, b);
}
