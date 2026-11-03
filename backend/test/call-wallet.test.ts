import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { createHmac, randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import {
  CallWalletService,
  callCharges,
  chargeCall,
} from "../src/call-wallet/call-wallet.service";
import { AdminService } from "../src/admin/admin.service";
import { AdminCallBillingService } from "../src/admin/admin-call-billing.service";
import type { Actor } from "../src/common/auth.guard";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
process.env.PAYMENT_API_BASE_URL = "https://pay.example.test/api";
process.env.BOOKING_PG_API_KEY = "test-api-key";
process.env.BOOKING_PG_EVENT_SECRET = "test-event-secret";
const db = new Database(),
  workspace = new WorkspaceService(db),
  wallet = new CallWalletService(db, workspace),
  billing = new AdminCallBillingService(
    db,
    new AdminService(db, undefined as never),
  );
const actor = (): Actor => ({
  uid: randomUUID(),
  email: `${randomUUID()}@example.com`,
  name: "Owner",
});
const owner = actor(),
  platformAdmin = actor();
let orgId = "";
const location = {
  name: "Main",
  address_line_1: "Road",
  address_line_2: null,
  city: "Kochi",
  state_code: "KL",
  country_code: "IN",
  postal_code: "682001",
  timezone: "Asia/Kolkata",
};
const defaults = {
  version: 1,
  rate_paise_per_minute: 500,
  plans_paise: [25000, 50000, 75000, 100000],
  custom_enabled: true,
  custom_above_paise: 100000,
  custom_max_paise: 5000000,
  low_balance_paise: 25000,
};
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
  await db.query(
    "INSERT INTO platform_admins(user_id,email,role) VALUES($1,$2,'super_admin')",
    [platformAdmin.uid, platformAdmin.email],
  );
});

test("recharge stays off and calls cost nothing until an admin sets a rate", async () => {
  let s = await wallet.status(owner);
  assert.equal(s.rate_set, false);
  assert.equal(s.recharge.enabled, false);
  await chargeCall(db, orgId, "free-call", 61);
  s = await wallet.status(owner);
  assert.equal(s.balance_paise, 0);
  assert.equal(s.transactions[0].amount_paise, 0);
  await assert.rejects(
    wallet.createOrder(owner, { amount_paise: 25000 }),
    /not available/,
  );
});

test("only platform admins change the default pricing", async () => {
  await assert.rejects(
    billing.saveDefaults(owner, defaults),
    /Admin access required/,
  );
  await assert.rejects(
    billing.saveDefaults(platformAdmin, {
      ...defaults,
      custom_above_paise: 5000000,
    }),
  );
  const saved = await billing.saveDefaults(platformAdmin, defaults);
  assert.equal(saved.version, 2);
  assert.equal(saved.updated_by, platformAdmin.email);
  await assert.rejects(
    billing.saveDefaults(platformAdmin, defaults),
    /Someone else changed/,
  );
  const s = await wallet.status(owner);
  assert.equal(s.rate_set, true);
  assert.equal(s.recharge.enabled, true);
  assert.deepEqual(s.recharge.plans_paise, defaults.plans_paise);
  assert.equal(s.recharge.custom_min_paise, 100100);
  const audit = await db.query<any>(
    "SELECT detail FROM admin_audit_log WHERE action='call_billing.defaults'",
  );
  assert.equal(audit.rows.length, 1);
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
  assert.equal(s.transactions.length, 2);
  assert.equal(s.transactions[0].kind, "call_charge");
  assert.equal(s.transactions[0].call_seconds, 61);
  assert.equal(s.transactions[0].rate_paise_per_minute, 500);
  assert.deepEqual(
    [...(await callCharges(db, orgId, ["call-1", "free-call", "none"]))],
    [
      ["free-call", 0],
      ["call-1", 1000],
    ].sort(),
  );
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
  const order = await wallet.createOrder(owner, { amount_paise: 25000 });
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
  const order = await wallet.createOrder(owner, { amount_paise: 50000 });
  Object.assign(remote.get(order.order_id)!, {
    status: "PAID",
    amountPaise: 100,
  });
  const before = (await wallet.status(owner)).balance_paise;
  await assert.rejects(wallet.verify(owner, order.order_id), /does not match/);
  assert.equal((await wallet.status(owner)).balance_paise, before);
});

test("orders belong to their organization", async () => {
  const order = await wallet.createOrder(owner, { amount_paise: 75000 });
  const stranger = actor();
  await workspace.createOrganization(stranger, {
    name: "Other",
    contact_phone: "9876543211",
    currency: "INR",
    location,
  } as never);
  await assert.rejects(
    wallet.verify(stranger, order.order_id),
    /Recharge not found/,
  );
  await assert.rejects(wallet.verify(owner, "../../etc"));
});

test("recharge amounts follow the plans and custom amount rules", async () => {
  await assert.rejects(
    wallet.createOrder(owner, { amount_paise: 30000 }),
    /more than ₹1,000/,
  );
  await assert.rejects(
    wallet.createOrder(owner, { amount_paise: 150050 }),
    /whole rupees/,
  );
  assert.match(
    (await wallet.createOrder(owner, { amount_paise: 100100 })).order_id,
    /^booking_/,
  );
  // A client override turns custom amounts off and replaces the plans.
  await assert.rejects(
    billing.saveOverrides(owner, orgId, { custom_enabled: false }),
    /Admin access required/,
  );
  await billing.saveOverrides(platformAdmin, orgId, {
    custom_enabled: false,
    plans_paise: [20000],
    rate_paise_per_minute: 1080,
  });
  await assert.rejects(
    wallet.createOrder(owner, { amount_paise: 100100 }),
    /Choose one of the recharge plans/,
  );
  await wallet.createOrder(owner, { amount_paise: 20000 });
  let s = await wallet.status(owner);
  assert.deepEqual(s.recharge.plans_paise, [20000]);
  assert.equal(s.recharge.custom_enabled, false);
  assert.equal(s.rate_paise_per_minute, 1080);
  await assert.rejects(
    billing.saveOverrides(platformAdmin, orgId, { custom_above_paise: 5000000 }),
  );
  const view = await billing.saveOverrides(platformAdmin, orgId, {
    custom_enabled: null,
    plans_paise: null,
    rate_paise_per_minute: null,
  });
  assert.deepEqual(view.overrides, {});
  s = await wallet.status(owner);
  assert.deepEqual(s.recharge.plans_paise, defaults.plans_paise);
  assert.equal(s.rate_paise_per_minute, 500);
});

test("admins credit offline payments once and alerts fire on crossing", async () => {
  const client = actor();
  await workspace.createOrganization(client, {
    name: "Alerts",
    contact_phone: "9876543212",
    currency: "INR",
    location,
  } as never);
  const org = (await workspace.member(client)).organization_id;
  const events = async () =>
    (
      await db.query<any>(
        "SELECT kind,wallet_details FROM booking_notification_events WHERE organization_id=$1 ORDER BY created_at,id",
        [org],
      )
    ).rows;
  const credit = {
    request_id: randomUUID(),
    amount_paise: 30000,
    payment_mode: "cash",
    external_reference: "RCPT-1",
    note: "Paid at the front desk",
  };
  await assert.rejects(
    billing.adjust(platformAdmin, org, { ...credit, payment_mode: null }),
    /how the client paid/,
  );
  let r = await billing.adjust(platformAdmin, org, credit);
  assert.equal(r.duplicate, false);
  assert.equal(r.wallet.balance_paise, 30000);
  // The same form submitted twice adds the money once.
  r = await billing.adjust(platformAdmin, org, credit);
  assert.equal(r.duplicate, true);
  assert.equal(r.wallet.balance_paise, 30000);
  assert.equal(r.wallet.ledger[0].admin_email, platformAdmin.email);
  const entry = (await wallet.status(client)).transactions[0];
  assert.equal(entry.kind, "adjustment");
  assert.equal(entry.payment_method, "cash");
  assert.equal("admin_email" in entry, false);

  await chargeCall(db, org, "a1", 120); // 29000
  assert.equal((await events()).length, 0);
  await chargeCall(db, org, "a2", 600); // 24000: below ₹250
  await chargeCall(db, org, "a3", 60); // 23500: already warned
  assert.deepEqual(
    (await events()).map((e) => e.kind),
    ["call_wallet_low"],
  );
  assert.deepEqual((await events())[0].wallet_details, {
    balance_paise: 24000,
    minutes_left: 48,
    currency: "INR",
  });
  await chargeCall(db, org, "a4", 3000); // -1500
  assert.deepEqual(
    (await events()).map((e) => e.kind),
    ["call_wallet_low", "call_wallet_empty"],
  );
  await assert.rejects(
    billing.adjust(platformAdmin, org, {
      request_id: randomUUID(),
      amount_paise: -100,
      note: "Correction",
    }),
    /below ₹0/,
  );
  await billing.adjust(platformAdmin, org, {
    request_id: randomUUID(),
    amount_paise: 50000,
    payment_mode: "upi",
  }); // 48500 re-arms both alerts
  await chargeCall(db, org, "a5", 4900); // 7500
  assert.deepEqual(
    (await events()).map((e) => e.kind),
    ["call_wallet_low", "call_wallet_empty", "call_wallet_low"],
  );
  const view = await billing.wallet(platformAdmin, org, {});
  assert.equal(view.balance_paise, 7500);
  assert.equal(view.totals.added_paise, 80000);
  assert.equal(view.totals.spent_paise, 72500);
  assert.equal(view.totals.calls, 5);
  const audit = await db.query<any>(
    "SELECT 1 FROM admin_audit_log WHERE action='call_wallet.adjust' AND target_id=$1",
    [org],
  );
  assert.equal(audit.rows.length, 2);
});

test("payment backend refusals name a key mismatch and are logged", async () => {
  const http = wallet.gateway.http;
  const logged: unknown[] = [];
  const error = console.error;
  console.error = (...a: unknown[]) => void logged.push(a);
  try {
    for (const [status, message] of [
      [401, /not set up correctly/],
      [502, /could not process/],
    ] as const) {
      wallet.gateway.http = async () =>
        new Response(
          JSON.stringify({ error: "Refused", detail: "order_meta.notify_url : invalid" }),
          { status, headers: { "Content-Type": "application/json" } },
        );
      await assert.rejects(
        wallet.createOrder(owner, { amount_paise: 25000 }),
        message,
      );
    }
  } finally {
    wallet.gateway.http = http;
    console.error = error;
  }
  assert.match(JSON.stringify(logged), /notify_url/);
  assert.doesNotMatch(JSON.stringify(logged), /test-api-key/);
});
