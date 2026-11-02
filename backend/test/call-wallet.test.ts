import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { createHmac, randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import {
  CallWalletService,
  chargeCall,
} from "../src/call-wallet/call-wallet.service";
import type { Actor } from "../src/common/auth.guard";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
process.env.PAYMENT_API_BASE_URL = "https://pay.example.test/api";
process.env.BOOKING_PG_API_KEY = "test-api-key";
process.env.BOOKING_PG_EVENT_SECRET = "test-event-secret";
const db = new Database(),
  workspace = new WorkspaceService(db),
  wallet = new CallWalletService(db, workspace);
const actor = (): Actor => ({
  uid: randomUUID(),
  email: `${randomUUID()}@example.com`,
  name: "Owner",
});
const owner = actor();
let orgId = "";
type Remote = {
  status: string;
  amountPaise?: number;
  payment?: { cfPaymentId: string; status: string; method: string } | null;
};
const remote = new Map<string, Remote>();
const requests: { url: string; auth: string; body: any }[] = [];
wallet.gateway.http = async (input, init) => {
  const url = String(input);
  requests.push({
    url,
    auth: String((init?.headers as any)?.Authorization ?? ""),
    body: init?.body ? JSON.parse(String(init.body)) : null,
  });
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { "Content-Type": "application/json" },
    });
  if (url.endsWith("/booking/pg/orders")) {
    const b = JSON.parse(String(init!.body));
    remote.set(b.orderId, { status: "ACTIVE", amountPaise: b.amountPaise });
    return json({
      orderId: b.orderId,
      paymentSessionId: `session_${b.orderId}`,
      environment: "sandbox",
    });
  }
  const id = decodeURIComponent(url.split("/").pop()!);
  const r = remote.get(id);
  if (!r) return json({ error: "Not found" }, 404);
  return json({
    orderId: id,
    orderStatus: r.status,
    amountPaise: r.amountPaise,
    currency: "INR",
    payment: r.payment ?? null,
  });
};
const sign = (orderId: string, eventType: string, ts = String(Date.now())) => ({
  timestamp: ts,
  signature: createHmac("sha256", "test-event-secret")
    .update(`${ts}.${orderId}.${eventType}`)
    .digest("base64"),
});
before(async () => {
  await db.onModuleInit();
  await workspace.createOrganization(owner, {
    name: "Eden",
    contact_phone: "+91 98765 43210",
    currency: "INR",
    location: {
      name: "Main",
      address_line_1: "Road",
      address_line_2: null,
      city: "Kochi",
      state_code: "KL",
      country_code: "IN",
      postal_code: "682001",
      timezone: "Asia/Kolkata",
    },
  } as never);
  orgId = (await workspace.member(owner)).organization_id;
});
after(() => db.onModuleDestroy());

test("calls are charged per started minute, once per call", async () => {
  await chargeCall(db, orgId, "call-1", 61);
  await chargeCall(db, orgId, "call-1", 61);
  await chargeCall(db, orgId, "call-2", 0);
  let s = await wallet.status(owner);
  assert.equal(s.balance_paise, -1000);
  assert.equal(s.rate_paise_per_minute, 500);
  assert.equal(s.minutes_left, 0);
  assert.equal(s.transactions.length, 1);
  assert.equal(s.transactions[0].kind, "call_charge");
  assert.equal(s.transactions[0].call_seconds, 61);
  // History from before the wallet existed is never billed.
  await chargeCall(db, orgId, "old-call", 120, "2020-01-01T00:00:00Z");
  s = await wallet.status(owner);
  assert.equal(s.balance_paise, -1000);
});

test("recharge credits only after the gateway reports PAID", async () => {
  await assert.rejects(
    wallet.createOrder(owner, { amount_paise: 5000 }),
    /at least/,
  );
  const order = await wallet.createOrder(owner, { amount_paise: 100000 });
  assert.match(order.order_id, /^booking_/);
  assert.equal(order.payment_session_id, `session_${order.order_id}`);
  const created = requests.find((r) => r.url.endsWith("/booking/pg/orders"))!;
  assert.equal(created.auth, "Bearer test-api-key");
  assert.equal(created.body.customer.phone, "9876543210");
  assert.equal(created.body.customer.id, orgId);

  let v = await wallet.verify(owner, order.order_id);
  assert.equal(v.status, "created");
  remote.get(order.order_id)!.payment = {
    cfPaymentId: "1",
    status: "FAILED",
    method: "upi",
  };
  v = await wallet.verify(owner, order.order_id);
  assert.equal(v.status, "failed");
  assert.equal(v.wallet.balance_paise, -1000);

  Object.assign(remote.get(order.order_id)!, {
    status: "PAID",
    payment: { cfPaymentId: "2", status: "SUCCESS", method: "upi" },
  });
  // The app's verify call and the forwarded webhook race; the wallet is credited once.
  const [a, b] = await Promise.all([
    wallet.verify(owner, order.order_id),
    wallet.paymentEvent(sign(order.order_id, "PAYMENT_SUCCESS_WEBHOOK"), {
      order_id: order.order_id,
      event_type: "PAYMENT_SUCCESS_WEBHOOK",
    }),
  ]);
  assert.equal(a.status, "paid");
  assert.equal(b.status, "paid");
  const s = await wallet.status(owner);
  assert.equal(s.balance_paise, 99000);
  assert.equal(s.minutes_left, 198);
  assert.equal(s.transactions[0].kind, "recharge");
  assert.equal(s.transactions[0].payment_method, "upi");
  assert.equal(s.transactions.filter((t) => t.kind === "recharge").length, 1);
});

test("payment events must be signed and recent", async () => {
  const order = await wallet.createOrder(owner, { amount_paise: 20000 });
  const body = {
    order_id: order.order_id,
    event_type: "PAYMENT_SUCCESS_WEBHOOK",
  };
  await assert.rejects(
    wallet.paymentEvent(
      { timestamp: String(Date.now()), signature: "bad" },
      body,
    ),
    /Invalid payment event/,
  );
  await assert.rejects(
    wallet.paymentEvent(
      sign(order.order_id, body.event_type, String(Date.now() - 600000)),
      body,
    ),
    /Invalid payment event/,
  );
  await assert.rejects(
    wallet.paymentEvent(sign(order.order_id, "OTHER"), body),
    /Invalid payment event/,
  );
});

test("a paid amount that differs from the order is never credited", async () => {
  const order = await wallet.createOrder(owner, { amount_paise: 30000 });
  Object.assign(remote.get(order.order_id)!, {
    status: "PAID",
    amountPaise: 100,
  });
  const before = (await wallet.status(owner)).balance_paise;
  await assert.rejects(wallet.verify(owner, order.order_id), /does not match/);
  assert.equal((await wallet.status(owner)).balance_paise, before);
});

test("orders belong to their organization", async () => {
  const order = await wallet.createOrder(owner, { amount_paise: 10000 });
  const stranger = actor();
  await workspace.createOrganization(stranger, {
    name: "Other",
    contact_phone: "9876543211",
    currency: "INR",
    location: {
      name: "Main",
      address_line_1: "Road",
      address_line_2: null,
      city: "Kochi",
      state_code: "KL",
      country_code: "IN",
      postal_code: "682001",
      timezone: "Asia/Kolkata",
    },
  } as never);
  await assert.rejects(
    wallet.verify(stranger, order.order_id),
    /Recharge not found/,
  );
  await assert.rejects(wallet.verify(owner, "../../etc"));
});
