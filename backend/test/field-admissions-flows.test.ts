// Field-value / boundary tests for Admissions (pool plans): preview, create, payments (collection/refund),
// cancel, delete, check-in, attendance, session changes, list filters, roles and cross-tenant access.
// (Named "-flows" because test/field-admissions.test.ts covers the pure admission rule helpers.)
import "reflect-metadata";
import { before, after, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { HttpException } from "@nestjs/common";
import { ZodError } from "zod";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { PoolService } from "../src/pool/pool.service";
import { AccountsService } from "../src/accounts/accounts.service";
import { AdmissionService } from "../src/admissions/admission.service";
import { localStamp } from "../src/bookings/booking.inventory";
import { Actor } from "../src/common/auth.guard";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  w = new WorkspaceService(db),
  adm = new AdmissionService(db),
  accounts = new AccountsService(db, w);
const actor = (): Actor => ({
  uid: randomUUID(),
  email: `${randomUUID()}@example.com`,
  name: "Admission owner",
});
const isClient = (e: any) =>
  e instanceof ZodError ||
  (e instanceof HttpException && e.getStatus() < 500) ||
  e?.code === "23505";
async function bad(fn: () => Promise<unknown>, label = "") {
  let threw: any;
  try {
    await fn();
  } catch (e) {
    threw = e;
  }
  assert.ok(threw, `expected rejection ${label}`);
  assert.ok(
    isClient(threw),
    `expected a 4xx, got server error ${threw?.code ?? threw?.name}: ${threw?.message} ${label}`,
  );
  return threw;
}
const hours = {
  days: [1, 2, 3, 4, 5, 6, 7],
  opens_at: "00:00",
  closes_at: "00:00",
  all_day: true,
  date_from: null,
  date_until: null,
};
const today = localStamp(Date.now(), "UTC").slice(0, 10);
const plus = (days: number) =>
  new Date(Date.parse(today) + days * 86400000).toISOString().slice(0, 10);
let owner: Actor,
  other: Actor,
  business: string,
  pool: string,
  tracked: string,
  membership: string,
  otherBusiness: string,
  otherPool: string,
  otherPlan: string,
  orgId: string;
const setupOrg = async (a: Actor) => {
  await w.createOrganization(a, {
    name: "Admission Field QA",
    contact_phone: "9876543210",
    currency: "INR",
    location: {
      name: "Pool",
      address_line_1: "Main road",
      address_line_2: null,
      city: "Kochi",
      state_code: "KL",
      country_code: "IN",
      postal_code: "682001",
      timezone: "UTC",
    },
  });
  const ws = await w.workspace(a);
  const b = await w.createBusiness(a, {
    name: "Swimming",
    type: "pool",
    location_id: ws.locations[0].id,
  });
  const poolId = randomUUID(),
    plan = randomUUID(),
    memberPlan = randomUUID();
  const common = {
    kind: "swimming",
    pool_ids: [poolId],
    expiry_months: null,
    expiry_years: null,
    expiry_date: null,
    enabled: true,
    availability: hours,
    class_duration_minutes: null,
    class_seats: null,
    coach_id: null,
    renewal: "none",
  };
  const configuration = {
    kind: "pool_v1",
    schema_version: 1,
    pools: [
      {
        id: poolId,
        name: "Main pool",
        capacity: 5,
        depth_min_ft: 3,
        depth_max_ft: 5,
        enabled: true,
        regular_swimming: true,
        operating: hours,
        durations: [60],
        default_duration_minutes: 60,
        buffer_before: 0,
        buffer_after: 0,
        pricing_basis: "start_time",
        tariffs: [
          {
            id: randomUUID(),
            hours,
            rates: [{ duration_minutes: 60, price_minor: 1000 }],
          },
        ],
      },
    ],
    group_offers: [],
    plans: [
      {
        ...common,
        id: plan,
        name: "Three day plan",
        allowance: 3,
        track_attendance: true,
        expiry_mode: "after_start",
        expiry_days: 45,
        price_minor: 10000,
      },
      {
        ...common,
        id: memberPlan,
        name: "Monthly membership",
        allowance: 0,
        track_attendance: false,
        expiry_mode: "after_months",
        expiry_days: null,
        expiry_months: 1,
        price_minor: 5000,
      },
    ],
  };
  await new PoolService(db, w).configure(a, b.id, {
    version: 1,
    configuration,
  });
  await w.activate(a, b.id);
  return {
    business: b.id,
    pool: poolId,
    tracked: plan,
    membership: memberPlan,
  };
};
async function staff(
  perms: string[],
  assign = true,
  business_ = business,
): Promise<Actor> {
  const a = actor(),
    id = randomUUID();
  await db.query(
    `INSERT INTO memberships(id,organization_id,user_id,email,display_name,role,permissions) VALUES($1,$2,$3,$4,'Adm staff','staff',$5)`,
    [id, orgId, a.uid, a.email, JSON.stringify(perms)],
  );
  if (assign)
    await db.query(
      "INSERT INTO staff_assignments(membership_id,organization_id,business_id,resource_ids) VALUES($1,$2,$3,'[]')",
      [id, orgId, business_],
    );
  return a;
}
const enrollment = (extra: Record<string, any> = {}): Record<string, any> => ({
  business_id: business,
  resource_id: pool,
  plan_id: tracked,
  starts_on: today,
  mode: "flexible",
  weekdays: [],
  time: "09:00",
  duration_minutes: 60,
  customer: { id: null, name: "Swimmer One", phone: "9876543210", email: null },
  payments: [],
  renewed_from: null,
  ...extra,
});
const membershipInput = (extra: Record<string, any> = {}) =>
  enrollment({
    plan_id: membership,
    mode: "membership",
    time: "00:00",
    ...extra,
  });
async function enroll(input = enrollment(), who = owner) {
  const q = await adm.preview(who, input);
  const command = {
    ...input,
    preview_token: q.preview_token,
    command_key: randomUUID(),
  };
  const r = await adm.create(who, command);
  return { id: r.id, input, command, q };
}
const pay = (amount_minor: number, extra: Record<string, any> = {}) => ({
  method: "cash",
  amount_minor,
  reference: "",
  received_at: new Date().toISOString(),
  ...extra,
});
const payBody = (
  version: number,
  kind: string,
  payments: any[],
  extra: Record<string, any> = {},
) => ({
  command_key: randomUUID(),
  version,
  kind,
  reason: kind === "refund" ? "Customer left" : "",
  payments,
  ...extra,
});
const detail = (id: string, who = owner) => adm.detail(who, id);
before(async () => {
  await db.onModuleInit();
  owner = actor();
  other = actor();
  ({ business, pool, tracked, membership } = await setupOrg(owner));
  ({
    business: otherBusiness,
    pool: otherPool,
    tracked: otherPlan,
  } = await setupOrg(other));
  orgId = (await w.member(owner)).organization_id;
});
after(() => db.onModuleDestroy());

// ---------------------------------------------------------------- preview: ids and structure
test("preview: ids must be uuids of the caller's organisation, space and plan", async () => {
  for (const k of ["business_id", "resource_id", "plan_id"])
    for (const v of ["", "x", null, 5, undefined])
      await bad(() => adm.preview(owner, enrollment({ [k]: v })), `${k}=${v}`);
  await assert.rejects(
    () => adm.preview(owner, enrollment({ business_id: randomUUID() })),
    /Pool or court business not found/,
  );
  await assert.rejects(
    () => adm.preview(owner, enrollment({ business_id: otherBusiness })),
    /Pool or court business not found/,
  ); // cross-tenant
  await assert.rejects(
    () => adm.preview(other, enrollment()),
    /Pool or court business not found/,
  );
  await assert.rejects(
    () => adm.preview(owner, enrollment({ resource_id: randomUUID() })),
    /enabled space and plan/,
  );
  await assert.rejects(
    () => adm.preview(owner, enrollment({ resource_id: otherPool })),
    /enabled space and plan/,
  );
  await assert.rejects(
    () => adm.preview(owner, enrollment({ plan_id: randomUUID() })),
    /enabled space and plan/,
  );
  await assert.rejects(
    () => adm.preview(owner, enrollment({ plan_id: otherPlan })),
    /enabled space and plan/,
  );
  await bad(() => adm.preview(owner, enrollment({ extra: 1 })));
  await bad(() => adm.preview(owner, null));
  await bad(() => adm.preview(owner, []));
});
test("preview: starts_on must be a real calendar date, not in the past", async () => {
  for (const starts_on of [
    "",
    "tomorrow",
    "2026-02-30",
    "2026-13-01",
    "2026-1-1",
    `${today}T00:00:00Z`,
    "20260101",
    null,
    20260101,
    undefined,
  ])
    await bad(
      () => adm.preview(owner, enrollment({ starts_on })),
      String(starts_on),
    );
  await assert.rejects(
    () => adm.preview(owner, enrollment({ starts_on: plus(-1) })),
    /activation date/,
  );
  await assert.rejects(
    () => adm.preview(owner, enrollment({ starts_on: "2000-01-01" })),
    /activation date/,
  );
  assert.ok(
    (await adm.preview(owner, enrollment({ starts_on: today }))).preview_token,
  );
  assert.ok(
    (await adm.preview(owner, enrollment({ starts_on: plus(400) })))
      .preview_token,
  );
});
test("preview: mode must match the plan's tracking type and schedule fields", async () => {
  for (const mode of ["", "FIXED", "daily", null, 1, undefined])
    await bad(() => adm.preview(owner, enrollment({ mode })), String(mode));
  await assert.rejects(
    () => adm.preview(owner, enrollment({ mode: "membership" })),
    /tracking mode/,
  );
  await assert.rejects(
    () => adm.preview(owner, membershipInput({ mode: "flexible" })),
    /tracking mode/,
  );
  await assert.rejects(
    () => adm.preview(owner, membershipInput({ mode: "fixed", weekdays: [1] })),
    /tracking mode/,
  );
  await assert.rejects(
    () => adm.preview(owner, membershipInput({ weekdays: [1] })),
    /scheduled weekdays/,
  );
  await assert.rejects(
    () => adm.preview(owner, enrollment({ mode: "flexible", weekdays: [1] })),
    /fixed weekdays/,
  );
  await assert.rejects(
    () =>
      adm.preview(
        owner,
        enrollment({ mode: "fixed", weekdays: [], starts_on: plus(3) }),
      ),
    /unique weekdays/,
  );
});
test("preview: weekdays are unique integers 1..7, at most 7", async () => {
  for (const weekdays of [
    [0],
    [8],
    [-1],
    [1.5],
    ["1"],
    [null],
    [1, 1],
    [1, 2, 3, 4, 5, 6, 7, 1],
    "1",
    null,
    {},
    [NaN],
    [Infinity],
  ])
    await bad(
      () =>
        adm.preview(
          owner,
          enrollment({ mode: "fixed", weekdays, starts_on: plus(3) }),
        ),
      JSON.stringify(weekdays),
    );
  assert.ok(
    (
      await adm.preview(
        owner,
        enrollment({
          mode: "fixed",
          weekdays: [1, 2, 3, 4, 5, 6, 7],
          starts_on: plus(3),
        }),
      )
    ).sessions.length === 3,
  );
});
test("preview: time uses strict HH:MM and duration is an integer in 30..1440 on the 30-minute grid above the minimum", async () => {
  for (const time of [
    "24:00",
    "9:00",
    "09:60",
    "09:00:00",
    "",
    " 09:00",
    "0900",
    null,
    900,
    undefined,
  ])
    await bad(() => adm.preview(owner, enrollment({ time })), String(time));
  for (const duration_minutes of [
    0,
    29,
    -60,
    30.5,
    60.0001,
    "60",
    NaN,
    Infinity,
    null,
    undefined,
    1441,
    1e9,
  ])
    await bad(
      () => adm.preview(owner, enrollment({ duration_minutes })),
      String(duration_minutes),
    );
  // Minimum is 60; 30 is below it, 75 is off the grid, 90 is valid, 1440 is the cap.
  await assert.rejects(
    () => adm.preview(owner, enrollment({ duration_minutes: 30 })),
    /visit duration/,
  );
  await assert.rejects(
    () => adm.preview(owner, enrollment({ duration_minutes: 75 })),
    /visit duration/,
  );
  assert.ok(
    (await adm.preview(owner, enrollment({ duration_minutes: 90 })))
      .preview_token,
  );
  assert.ok(
    (await adm.preview(owner, enrollment({ duration_minutes: 1440 })))
      .preview_token,
  );
});
test("preview: customer name, phone and email boundaries", async () => {
  const c = (extra: Record<string, any>) => ({
    id: null,
    name: "Valid Name",
    phone: "9876543210",
    email: null,
    ...extra,
  });
  for (const extra of [
    { name: "" },
    { name: "  " },
    { name: "a" },
    { name: "n".repeat(101) },
    { name: null },
    { name: 7 },
    { phone: "" },
    { phone: "abc" },
    { phone: "123456" }, // 6 digits
    { phone: "1".repeat(16) },
    { phone: "+" + "1".repeat(16) },
    { phone: "1".repeat(26) },
    { phone: "98765-4321x" },
    { phone: "+(+)-----" },
    { phone: null },
    { phone: 9876543210 },
    { email: "" },
    { email: "not-an-email" },
    { email: "a@b" },
    { email: "x".repeat(200) + "@example.com" },
    { email: 5 },
    { id: "nope" },
    { id: 5 },
    { surprise: 1 },
  ])
    await bad(
      () => adm.preview(owner, enrollment({ customer: c(extra) })),
      JSON.stringify(extra),
    );
  for (const extra of [
    { name: "ab" },
    { name: "n".repeat(100) },
    { name: "Ünï 名前 ☕" },
    { name: "Robert'); DROP TABLE customers;--" },
    { phone: "+91 98765-43210" },
    { phone: "(0484) 123-4567" },
    { phone: "1234567" },
    { phone: "1".repeat(15) },
    { email: "a@b.co" },
  ])
    assert.ok(
      (await adm.preview(owner, enrollment({ customer: c(extra) })))
        .preview_token,
      JSON.stringify(extra),
    );
});
test("preview: payments array shape and payment fields", async () => {
  const L = (p: any) => enrollment({ payments: [p] });
  for (const p of [
    pay(0),
    pay(-1),
    pay(0.5),
    pay(99.99),
    pay(NaN),
    pay(Infinity),
    pay(100000001),
    pay(Number.MAX_SAFE_INTEGER),
    pay(1e21),
    pay("100" as any),
    pay(100, { method: "transfer" }),
    pay(100, { method: "CASH" }),
    pay(100, { method: "" }),
    pay(100, { received_at: "2024-01-01" }),
    pay(100, { received_at: "garbage" }),
    pay(100, { reference: "r".repeat(201) }),
    pay(100, { account_id: "nope" }),
    pay(100, { surprise: 1 }),
  ])
    await bad(() => adm.preview(owner, L(p)), JSON.stringify(p));
  await bad(() =>
    adm.preview(owner, enrollment({ payments: Array(21).fill(pay(1)) })),
  );
  await bad(() => adm.preview(owner, enrollment({ payments: "x" })));
  await bad(() => adm.preview(owner, enrollment({ payments: null })));
  assert.ok(
    (await adm.preview(owner, enrollment({ payments: Array(20).fill(pay(1)) })))
      .preview_token,
  );
});

// ---------------------------------------------------------------- create
test("create: preview_token and command_key formats; stale tokens and changed inputs conflict", async () => {
  const input = enrollment();
  const q = await adm.preview(owner, input);
  for (const preview_token of [
    "",
    "abc",
    "G".repeat(64),
    q.preview_token.toUpperCase(),
    q.preview_token + "0",
    null,
    5,
    undefined,
  ])
    await bad(
      () =>
        adm.create(owner, {
          ...input,
          preview_token,
          command_key: randomUUID(),
        }),
      String(preview_token),
    );
  for (const command_key of ["", "x", null, undefined, 5])
    await bad(
      () =>
        adm.create(owner, {
          ...input,
          preview_token: q.preview_token,
          command_key,
        }),
      String(command_key),
    );
  await assert.rejects(
    () =>
      adm.create(owner, {
        ...input,
        preview_token: "0".repeat(64),
        command_key: randomUUID(),
      }),
    /changed/,
  );
  await assert.rejects(
    () =>
      adm.create(owner, {
        ...input,
        customer: { ...input.customer, name: "Someone Else" },
        preview_token: q.preview_token,
        command_key: randomUUID(),
      }),
    /changed/,
  );
  await assert.rejects(
    () =>
      adm.create(owner, {
        ...input,
        duration_minutes: 90,
        preview_token: q.preview_token,
        command_key: randomUUID(),
      }),
    /changed/,
  );
  await bad(() =>
    adm.create(owner, {
      ...input,
      preview_token: q.preview_token,
      command_key: randomUUID(),
      extra: 1,
    }),
  );
});
test("create: duplicate submit and parallel submits create exactly one admission", async () => {
  const input = enrollment({
    customer: {
      id: null,
      name: "Idempotent Person",
      phone: "9000000001",
      email: null,
    },
  });
  const q = await adm.preview(owner, input);
  const command = {
    ...input,
    preview_token: q.preview_token,
    command_key: randomUUID(),
  };
  const ids = await Promise.all(
    [1, 2, 3, 4].map(() => adm.create(owner, command)),
  );
  assert.equal(new Set(ids.map((i) => i.id)).size, 1);
  const n = (
    await db.query<any>(
      "SELECT count(*)::int n FROM customers WHERE organization_id=$1 AND name='Idempotent Person'",
      [orgId],
    )
  ).rows[0].n;
  assert.equal(n, 1);
  // same key with another body
  await assert.rejects(
    () =>
      adm.create(owner, {
        ...command,
        customer: { ...input.customer, phone: "9000000002" },
      }),
    /different data|changed/,
  );
  // another actor in the same org re-using the key
  const manager = await staff(["manage_subscriptions", "view_bookings"]);
  await assert.rejects(() => adm.create(manager, command), /different data/);
  // another organisation re-using the key does not replay our response
  await assert.rejects(
    () => adm.create(other, command),
    /not found|different|not ready|enabled space/i,
  );
});
test("create: payments cannot exceed the plan price (overpayment) and exact payment sets are fine", async () => {
  await assert.rejects(
    () => enroll(enrollment({ payments: [pay(10001)] })),
    /exceeds the outstanding/,
  );
  await assert.rejects(
    () => enroll(enrollment({ payments: [pay(5000), pay(5001)] })),
    /exceeds the outstanding/,
  );
  await assert.rejects(
    () => enroll(enrollment({ payments: Array(20).fill(pay(501)) })),
    /exceeds the outstanding/,
  );
  const e = await enroll(
    enrollment({ payments: [pay(5000), pay(5000, { method: "upi" })] }),
  );
  const d = await detail(e.id);
  assert.equal(d.net_paid_minor, 10000);
  assert.equal(d.balance_minor, 0);
});
test("create: payment dates are bounded between 2000 and now+60s", async () => {
  for (const received_at of [
    "1999-12-31T23:59:59Z",
    new Date(Date.now() + 3 * 60000).toISOString(),
    new Date(Date.now() + 86400000 * 30).toISOString(),
  ])
    await assert.rejects(
      () => enroll(enrollment({ payments: [pay(100, { received_at })] })),
      /between 2000 and now/,
    );
  assert.ok(
    (
      await enroll(
        enrollment({
          payments: [pay(100, { received_at: "2000-01-01T00:00:00Z" })],
        }),
      )
    ).id,
  );
  assert.ok(
    (
      await enroll(
        enrollment({
          payments: [
            pay(100, {
              received_at: new Date(Date.now() + 30000).toISOString(),
            }),
          ],
        }),
      )
    ).id,
  );
});
test("create: payment account must match the method and the organisation", async () => {
  const cashAcc = (await accounts.catalog(owner)).accounts.find(
    (a: any) => a.kind === "cash",
  ).id;
  const clearing = (await accounts.catalog(owner)).accounts.find(
    (a: any) => a.kind === "clearing",
  ).id;
  const bankId = (
    await accounts.createAccount(owner, {
      command_key: randomUUID(),
      name: "Adm bank",
      bank_name: "QA",
      account_number: "123456789",
      opening_minor: 0,
      opening_at: "2000-01-01T00:00:00Z",
      is_primary: false,
    })
  ).id;
  const foreignCash = (await accounts.catalog(other)).accounts.find(
    (a: any) => a.kind === "cash",
  ).id;
  for (const p of [
    pay(100, { method: "cash", account_id: bankId }),
    pay(100, { method: "upi", account_id: cashAcc }),
    pay(100, { method: "upi", account_id: clearing }),
    pay(100, { method: "cash", account_id: foreignCash }),
    pay(100, { method: "cash", account_id: randomUUID() }),
  ])
    await assert.rejects(
      () => enroll(enrollment({ payments: [p] })),
      /matching the payment method/,
    );
  assert.ok(
    (
      await enroll(
        enrollment({
          payments: [pay(100, { method: "upi", account_id: bankId })],
        }),
      )
    ).id,
  );
});
test("create: customer id must belong to this organisation", async () => {
  const foreign = randomUUID();
  await db.query(
    "INSERT INTO customers(id,organization_id,name,phone,email) SELECT $1,organization_id,'Foreign cust','9111111111',NULL FROM memberships WHERE user_id=$2",
    [foreign, other.uid],
  );
  await assert.rejects(
    () =>
      enroll(
        enrollment({
          customer: {
            id: foreign,
            name: "Foreign cust",
            phone: "9111111111",
            email: null,
          },
        }),
      ),
    /Customer not found/,
  );
  await assert.rejects(
    () =>
      enroll(
        enrollment({
          customer: {
            id: randomUUID(),
            name: "Ghost",
            phone: "9111111112",
            email: null,
          },
        }),
      ),
    /Customer not found/,
  );
});
test("create: customer text with unicode and SQL fragments is stored literally and phone is normalised", async () => {
  const e = await enroll(
    enrollment({
      customer: {
        id: null,
        name: "Robert'); DROP TABLE customers;-- 名",
        phone: "+91 (98765)-43211",
        email: "o'brien@example.com",
      },
    }),
  );
  const row = (
    await db.query<any>(
      "SELECT name,phone,email FROM customers WHERE id=(SELECT customer_id FROM admissions WHERE id=$1)",
      [e.id],
    )
  ).rows[0];
  assert.equal(row.name, "Robert'); DROP TABLE customers;-- 名");
  assert.equal(row.phone, "+919876543211");
  assert.equal(row.email, "o'brien@example.com");
});
test(
  "create: NUL byte in the customer name is a client error, not a server error",
  { todo: "BUG-4" },
  async () => {
    await bad(() =>
      enroll(
        enrollment({
          customer: {
            id: null,
            name: "Bad\u0000Name",
            phone: "9000000077",
            email: null,
          },
        }),
      ),
    );
  },
);
test("create: renewed_from must reference a completed/expired admission of the same customer", async () => {
  const e = await enroll();
  const d = await detail(e.id);
  for (const renewed_from of ["x", 5, ""])
    await bad(
      () => adm.preview(owner, enrollment({ renewed_from })),
      String(renewed_from),
    );
  await assert.rejects(
    () =>
      adm.preview(
        owner,
        enrollment({
          renewed_from: randomUUID(),
          customer: { ...enrollment().customer, id: d.customer_id },
        }),
      ),
    /not found/,
  );
  await assert.rejects(
    () =>
      adm.preview(
        owner,
        enrollment({
          renewed_from: e.id,
          customer: { ...enrollment().customer, id: d.customer_id },
        }),
      ),
    /completed or expired/,
  );
  await assert.rejects(
    () => adm.preview(other, enrollment({ renewed_from: e.id })),
    /not found|business/i,
  );
});
test("create: roles - manage_subscriptions required, assigned business required, other tenants denied", async () => {
  const viewer = await staff(["view_bookings"]),
    collector = await staff(["collect_payments"]),
    manager = await staff(["manage_subscriptions"]),
    unassigned = await staff(["manage_subscriptions"], false),
    nobody = await staff([]);
  await assert.rejects(
    () => adm.preview(viewer, enrollment()),
    /Subscription management/,
  );
  await assert.rejects(
    () => adm.preview(collector, enrollment()),
    /Subscription management/,
  );
  await assert.rejects(
    () => adm.preview(nobody, enrollment()),
    /Admission access/,
  );
  await assert.rejects(
    () => adm.preview(unassigned, enrollment()),
    /not assigned/,
  );
  await assert.rejects(
    () => adm.preview(actor(), enrollment()),
    /Admission access/,
  );
  // a manager without collect_payments cannot attach payments
  await assert.rejects(
    () => enroll(enrollment({ payments: [pay(100)] }), manager),
    /Payment collection permission/,
  );
  assert.ok((await enroll(enrollment(), manager)).id);
});

// ---------------------------------------------------------------- payments
test("payments: body fields (version, kind, reason, payments array, unknown keys)", async () => {
  const e = await enroll();
  const v = (await detail(e.id)).version;
  for (const version of [0, -1, 1.5, "1", NaN, Infinity, null, undefined, true])
    await bad(
      () =>
        adm.payments(
          owner,
          e.id,
          payBody(version as any, "collection", [pay(100)]),
        ),
      String(version),
    );
  for (const kind of ["", "COLLECTION", "payment", null, undefined, 1])
    await bad(
      () => adm.payments(owner, e.id, payBody(v, kind as any, [pay(100)])),
      String(kind),
    );
  await bad(() => adm.payments(owner, e.id, payBody(v, "collection", [])));
  await bad(() =>
    adm.payments(owner, e.id, payBody(v, "collection", Array(21).fill(pay(1)))),
  );
  await bad(() =>
    adm.payments(
      owner,
      e.id,
      payBody(v, "collection", [pay(1)], { reason: "r".repeat(501) }),
    ),
  );
  await bad(() =>
    adm.payments(
      owner,
      e.id,
      payBody(v, "collection", [pay(1)], { reason: null }),
    ),
  );
  await bad(() =>
    adm.payments(
      owner,
      e.id,
      payBody(v, "collection", [pay(1)], { command_key: "nope" }),
    ),
  );
  await bad(() =>
    adm.payments(owner, e.id, payBody(v, "collection", [pay(1)], { extra: 1 })),
  );
  await bad(() => adm.payments(owner, e.id, null));
  await assert.rejects(
    () => adm.payments(owner, e.id, payBody(v + 1, "collection", [pay(1)])),
    /changed/,
  );
  await assert.rejects(
    () => adm.payments(owner, e.id, payBody(v - 1, "collection", [pay(1)])),
    /changed|positive|Too small/,
  );
  assert.equal((await detail(e.id)).net_paid_minor, 0); // nothing leaked through
});
test("payments: amount boundaries (0, negative, decimal, NaN, Infinity, max+1) never change the balance", async () => {
  const e = await enroll();
  const v = (await detail(e.id)).version;
  for (const amount of [
    0,
    -1,
    -10000,
    0.5,
    100.0001,
    NaN,
    Infinity,
    -Infinity,
    "100",
    null,
    true,
    100000001,
    Number.MAX_SAFE_INTEGER,
    1e21,
  ])
    await bad(
      () =>
        adm.payments(
          owner,
          e.id,
          payBody(v, "collection", [pay(amount as any)]),
        ),
      String(amount),
    );
  const d = await detail(e.id);
  assert.equal(d.net_paid_minor, 0);
  assert.equal(d.version, v);
});
test("payments: collection above the outstanding balance is rejected, exact balance accepted, then nothing more", async () => {
  const e = await enroll();
  let v = (await detail(e.id)).version;
  await assert.rejects(
    () => adm.payments(owner, e.id, payBody(v, "collection", [pay(10001)])),
    /exceeds the outstanding/,
  );
  await assert.rejects(
    () =>
      adm.payments(
        owner,
        e.id,
        payBody(v, "collection", [pay(6000), pay(4001)]),
      ),
    /exceeds the outstanding/,
  );
  await adm.payments(
    owner,
    e.id,
    payBody(v, "collection", [pay(6000), pay(4000, { method: "upi" })]),
  );
  let d = await detail(e.id);
  assert.equal(d.net_paid_minor, 10000);
  assert.equal(d.balance_minor, 0);
  v = d.version;
  await assert.rejects(
    () => adm.payments(owner, e.id, payBody(v, "collection", [pay(1)])),
    /exceeds the outstanding/,
  );
  assert.equal(
    Number(
      (
        await db.query<any>(
          "SELECT count(*) n FROM admission_payments WHERE admission_id=$1",
          [e.id],
        )
      ).rows[0].n,
    ),
    2,
  );
});
test("payments: refund cannot exceed what was paid and needs a reason and the owner role", async () => {
  const e = await enroll(enrollment({ payments: [pay(4000)] }));
  let v = (await detail(e.id)).version;
  await assert.rejects(
    () => adm.payments(owner, e.id, payBody(v, "refund", [pay(4001)])),
    /exceeds the outstanding balance or refundable/,
  );
  await assert.rejects(
    () =>
      adm.payments(owner, e.id, payBody(v, "refund", [pay(2000), pay(2001)])),
    /exceeds the outstanding balance or refundable/,
  );
  for (const reason of ["", " ", "x"])
    await assert.rejects(
      () =>
        adm.payments(owner, e.id, payBody(v, "refund", [pay(100)], { reason })),
      /refund reason/,
    );
  await adm.payments(owner, e.id, payBody(v, "refund", [pay(1500)]));
  v = (await detail(e.id)).version;
  assert.equal((await detail(e.id)).net_paid_minor, 2500);
  await assert.rejects(
    () => adm.payments(owner, e.id, payBody(v, "refund", [pay(2501)])),
    /refundable/,
  );
  await adm.payments(owner, e.id, payBody(v, "refund", [pay(2500)]));
  v = (await detail(e.id)).version;
  await assert.rejects(
    () => adm.payments(owner, e.id, payBody(v, "refund", [pay(1)])),
    /refundable/,
  ); // nothing left
  assert.equal((await detail(e.id)).net_paid_minor, 0);
  const staffer = await staff(["collect_payments", "view_bookings"]);
  const e2 = await enroll(enrollment({ payments: [pay(1000)] }));
  const v2 = (await detail(e2.id)).version;
  await assert.rejects(
    () => adm.payments(staffer, e2.id, payBody(v2, "refund", [pay(100)])),
    /Only the owner/,
  );
});
test("payments: a refund with nothing collected is rejected", async () => {
  const e = await enroll();
  const v = (await detail(e.id)).version;
  await assert.rejects(
    () => adm.payments(owner, e.id, payBody(v, "refund", [pay(1)])),
    /refundable/,
  );
});
test("payments: duplicate submit and parallel submits post exactly once; key reuse with other data conflicts", async () => {
  const e = await enroll();
  const v = (await detail(e.id)).version;
  const body = payBody(v, "collection", [pay(2500)]);
  const r = await Promise.all(
    [1, 2, 3, 4, 5].map(() => adm.payments(owner, e.id, body)),
  );
  assert.equal(new Set(r.map((x) => x.id)).size, 1);
  const d = await detail(e.id);
  assert.equal(d.net_paid_minor, 2500);
  const ledger = (
    await db.query<any>(
      "SELECT count(*)::int n FROM finance_events WHERE admission_payment_id IN (SELECT id FROM admission_payments WHERE admission_id=$1)",
      [e.id],
    )
  ).rows[0].n;
  assert.equal(ledger, 1);
  await assert.rejects(
    () => adm.payments(owner, e.id, { ...body, payments: [pay(2501)] }),
    /different data/,
  );
  // parallel distinct commands from the same version: only one wins
  const v2 = d.version;
  const res = await Promise.allSettled(
    [1, 2, 3].map(() =>
      adm.payments(owner, e.id, payBody(v2, "collection", [pay(7500)])),
    ),
  );
  assert.equal(res.filter((x) => x.status === "fulfilled").length, 1);
  assert.equal((await detail(e.id)).net_paid_minor, 10000);
});
test("payments: posts the same ledger amount as the admission payment, signed by kind", async () => {
  const e = await enroll();
  let v = (await detail(e.id)).version;
  await adm.payments(owner, e.id, payBody(v, "collection", [pay(3333)]));
  v = (await detail(e.id)).version;
  await adm.payments(owner, e.id, payBody(v, "refund", [pay(1111)]));
  const rows = (
    await db.query<any>(
      "SELECT fe.kind,sum(fl.amount_minor)::int amt FROM finance_events fe JOIN finance_lines fl ON fl.event_id=fe.id WHERE fe.admission_payment_id IN (SELECT id FROM admission_payments WHERE admission_id=$1) GROUP BY fe.kind ORDER BY fe.kind",
      [e.id],
    )
  ).rows;
  assert.deepEqual(rows, [
    { kind: "admission_collection", amt: 3333 },
    { kind: "admission_refund", amt: -1111 },
  ]);
});
test("payments: tenant and role denial", async () => {
  const e = await enroll();
  const v = (await detail(e.id)).version;
  const viewer = await staff(["view_bookings"]);
  await assert.rejects(
    () => adm.payments(other, e.id, payBody(v, "collection", [pay(10)])),
    /not found|Admission access/i,
  );
  await assert.rejects(
    () => adm.payments(viewer, e.id, payBody(v, "collection", [pay(10)])),
    /permission/,
  );
  await assert.rejects(
    () =>
      adm.payments(owner, randomUUID(), payBody(v, "collection", [pay(10)])),
    /not found/,
  );
  await bad(() =>
    adm.payments(owner, "not-a-uuid", payBody(v, "collection", [pay(10)])),
  );
  assert.equal((await detail(e.id)).net_paid_minor, 0);
});
test("payments: ledger-created admission payments cannot be reversed through the Accounts API", async () => {
  const e = await enroll(enrollment({ payments: [pay(100)] }));
  const ev = (
    await db.query<any>(
      "SELECT id FROM finance_events WHERE admission_payment_id IN (SELECT id FROM admission_payments WHERE admission_id=$1)",
      [e.id],
    )
  ).rows[0].id;
  await assert.rejects(
    () =>
      accounts.reverse(owner, ev, {
        command_key: randomUUID(),
        reason: "Try to bypass",
      }),
    /Only manual entries/,
  );
});

// ---------------------------------------------------------------- cancel / delete
test("cancel: reason, version, status and tenant rules", async () => {
  const e = await enroll();
  const v = (await detail(e.id)).version;
  for (const reason of ["", " ", "x", "r".repeat(501), null, 5, undefined])
    await bad(
      () =>
        adm.cancel(owner, e.id, {
          command_key: randomUUID(),
          version: v,
          reason,
        }),
      String(reason),
    );
  for (const version of [0, -1, 1.5, "1", null, NaN])
    await bad(
      () =>
        adm.cancel(owner, e.id, {
          command_key: randomUUID(),
          version,
          reason: "valid reason",
        }),
      String(version),
    );
  await bad(() =>
    adm.cancel(owner, e.id, {
      command_key: randomUUID(),
      version: v,
      reason: "valid reason",
      extra: 1,
    }),
  );
  await assert.rejects(
    () =>
      adm.cancel(owner, e.id, {
        command_key: randomUUID(),
        version: v + 5,
        reason: "valid reason",
      }),
    /changed/,
  );
  await assert.rejects(
    () =>
      adm.cancel(other, e.id, {
        command_key: randomUUID(),
        version: v,
        reason: "valid reason",
      }),
    /not found|Admission access/i,
  );
  const viewer = await staff(["view_bookings"]);
  await assert.rejects(
    () =>
      adm.cancel(viewer, e.id, {
        command_key: randomUUID(),
        version: v,
        reason: "valid reason",
      }),
    /permission/,
  );
  const key = randomUUID();
  const ok = await adm.cancel(owner, e.id, {
    command_key: key,
    version: v,
    reason: "Customer moved",
  });
  assert.deepEqual(
    await adm.cancel(owner, e.id, {
      command_key: key,
      version: v,
      reason: "Customer moved",
    }),
    ok,
  ); // replay
  const v2 = (await detail(e.id)).version;
  await assert.rejects(
    () =>
      adm.cancel(owner, e.id, {
        command_key: randomUUID(),
        version: v2,
        reason: "Again please",
      }),
    /active or upcoming/,
  );
  assert.equal((await detail(e.id)).status, "cancelled");
});
test("delete membership: reason, version, double deletion and tenant rules", async () => {
  const e = await enroll(
    membershipInput({
      customer: {
        id: null,
        name: "Member Del",
        phone: "9222222222",
        email: null,
      },
    }),
  );
  const v = (await detail(e.id)).version;
  for (const reason of ["", " ", "x", "r".repeat(501), null])
    await bad(
      () =>
        adm.deleteMembership(owner, e.id, {
          command_key: randomUUID(),
          version: v,
          reason,
        }),
      String(reason),
    );
  for (const version of [0, -3, 2.5, "1", null])
    await bad(
      () =>
        adm.deleteMembership(owner, e.id, {
          command_key: randomUUID(),
          version,
          reason: "valid reason",
        }),
      String(version),
    );
  await bad(() =>
    adm.deleteMembership(owner, e.id, {
      command_key: randomUUID(),
      version: v,
      reason: "valid reason",
      extra: 1,
    }),
  );
  await assert.rejects(
    () =>
      adm.deleteMembership(owner, e.id, {
        command_key: randomUUID(),
        version: v + 9,
        reason: "valid reason",
      }),
    /changed/,
  );
  await assert.rejects(
    () =>
      adm.deleteMembership(other, e.id, {
        command_key: randomUUID(),
        version: v,
        reason: "valid reason",
      }),
    /not found|Admission access/i,
  );
  await adm.deleteMembership(owner, e.id, {
    command_key: randomUUID(),
    version: v,
    reason: "Duplicate membership",
  });
  const v2 = (
    await db.query<any>("SELECT version FROM admissions WHERE id=$1", [e.id])
  ).rows[0].version;
  await assert.rejects(
    () =>
      adm.deleteMembership(owner, e.id, {
        command_key: randomUUID(),
        version: v2,
        reason: "Delete twice",
      }),
    /already deleted/,
  );
});

// ---------------------------------------------------------------- check-in and attendance
test("check-in: body shape (union), version and mode rules", async () => {
  const e = await enroll();
  const v = (await detail(e.id)).version;
  const key = () => randomUUID();
  for (const body of [
    { command_key: key(), version: 0 },
    { command_key: key(), version: -1 },
    { command_key: key(), version: 1.5 },
    { command_key: key(), version: "1" },
    { command_key: "x", version: v },
    { version: v },
    { command_key: key(), version: v, start_class: "yes" },
    { command_key: key(), version: v, start_class: null },
    { command_key: key(), version: v, extra: 1 },
    { command_key: key(), version: v, date: today }, // explicit shape needs time and duration
    {
      command_key: key(),
      version: v,
      date: "2026-02-30",
      time: "09:00",
      duration_minutes: 60,
    },
    {
      command_key: key(),
      version: v,
      date: today,
      time: "25:00",
      duration_minutes: 60,
    },
    {
      command_key: key(),
      version: v,
      date: today,
      time: "09:00",
      duration_minutes: 29,
    },
    {
      command_key: key(),
      version: v,
      date: today,
      time: "09:00",
      duration_minutes: 1441,
    },
    {
      command_key: key(),
      version: v,
      date: today,
      time: "09:00",
      duration_minutes: 60.5,
    },
    {
      command_key: key(),
      version: v,
      date: today,
      time: "09:00",
      duration_minutes: "60",
    },
    null,
  ])
    await bad(() => adm.checkIn(owner, e.id, body), JSON.stringify(body));
  await assert.rejects(
    () => adm.checkIn(owner, e.id, { command_key: key(), version: v + 4 }),
    /changed/,
  );
  await assert.rejects(
    () =>
      adm.checkIn(owner, e.id, {
        command_key: key(),
        version: v,
        date: plus(1),
        time: "09:00",
        duration_minutes: 60,
      }),
    /not active|current time|expired/,
  );
  await assert.rejects(
    () =>
      adm.checkIn(owner, e.id, {
        command_key: key(),
        version: v,
        date: plus(-1),
        time: "09:00",
        duration_minutes: 60,
      }),
    /not active|current time|expired/,
  );
  assert.equal((await detail(e.id)).used, 0);
});
test("check-in: same-day repeat does not deduct twice; fixed and membership admissions reject check-in", async () => {
  const e = await enroll();
  const first = await adm.checkIn(owner, e.id, {
    command_key: randomUUID(),
    version: (await detail(e.id)).version,
  });
  assert.ok(first.visit_id);
  await adm.checkIn(owner, e.id, {
    command_key: randomUUID(),
    version: (await detail(e.id)).version,
  });
  const d = await detail(e.id);
  assert.equal(d.used, 1);
  assert.equal(d.remaining, 2);
  const fixed = await enroll(
    enrollment({
      mode: "fixed",
      weekdays: [1, 2, 3, 4, 5, 6, 7],
      starts_on: plus(5),
      customer: {
        id: null,
        name: "Fixed Person",
        phone: "9333333333",
        email: null,
      },
    }),
  );
  await assert.rejects(
    async () =>
      adm.checkIn(owner, fixed.id, {
        command_key: randomUUID(),
        version: (await detail(fixed.id)).version,
      }),
    /scheduled session/,
  );
  const m = await enroll(
    membershipInput({
      customer: {
        id: null,
        name: "Member Chk",
        phone: "9444444444",
        email: null,
      },
    }),
  );
  await assert.rejects(
    async () =>
      adm.checkIn(owner, m.id, {
        command_key: randomUUID(),
        version: (await detail(m.id)).version,
      }),
    /Attendance is limited/,
  );
});
test("check-in: role denial, tenant isolation and cancelled admissions", async () => {
  const e = await enroll();
  const v = (await detail(e.id)).version;
  const collector = await staff(["collect_payments"]);
  const booker = await staff(["view_bookings"]);
  await assert.rejects(
    () =>
      adm.checkIn(collector, e.id, { command_key: randomUUID(), version: v }),
    /permission/,
  );
  await assert.rejects(
    () => adm.checkIn(booker, e.id, { command_key: randomUUID(), version: v }),
    /permission/,
  );
  await assert.rejects(
    () => adm.checkIn(other, e.id, { command_key: randomUUID(), version: v }),
    /not found|Admission access/i,
  );
  await adm.cancel(owner, e.id, {
    command_key: randomUUID(),
    version: v,
    reason: "Cancelled for test",
  });
  await assert.rejects(
    async () =>
      adm.checkIn(owner, e.id, {
        command_key: randomUUID(),
        version: (await detail(e.id)).version,
      }),
    /not active|expired|remaining/,
  );
});
test("check-in: allowance exhaustion cannot be bypassed with parallel submissions", async () => {
  const e = await enroll();
  const v = (await detail(e.id)).version;
  const r = await Promise.allSettled(
    [1, 2, 3, 4].map(() =>
      adm.checkIn(owner, e.id, { command_key: randomUUID(), version: v }),
    ),
  );
  assert.equal(r.filter((x) => x.status === "fulfilled").length >= 1, true);
  assert.equal((await detail(e.id)).used, 1);
});
test("attendance: enum, reason, version and visit identity", async () => {
  const e = await enroll();
  await adm.checkIn(owner, e.id, {
    command_key: randomUUID(),
    version: (await detail(e.id)).version,
  });
  const d = await detail(e.id);
  const s = d.sessions[0];
  const body = (extra: Record<string, any> = {}) => ({
    command_key: randomUUID(),
    version: s.version,
    attendance: "absent",
    reason: "Wrong marking",
    ...extra,
  });
  for (const extra of [
    { attendance: "" },
    { attendance: "PRESENT" },
    { attendance: "late" },
    { attendance: null },
    { attendance: true },
    { reason: "r".repeat(501) },
    { reason: null },
    { reason: 5 },
    { version: 0 },
    { version: -1 },
    { version: 1.5 },
    { version: "1" },
    { command_key: "x" },
    { extra: 1 },
  ])
    await bad(
      () => adm.attendance(owner, e.id, s.id, body(extra)),
      JSON.stringify(extra),
    );
  await bad(() => adm.attendance(owner, e.id, "not-a-uuid", body()));
  await assert.rejects(
    () => adm.attendance(owner, e.id, randomUUID(), body()),
    /cancelled or unavailable/,
  );
  await assert.rejects(
    () => adm.attendance(owner, e.id, s.id, body({ version: s.version + 3 })),
    /changed/,
  );
  const other_e = await enroll(
    enrollment({
      customer: {
        id: null,
        name: "Other Admission",
        phone: "9555555555",
        email: null,
      },
    }),
  );
  await assert.rejects(
    () => adm.attendance(owner, other_e.id, s.id, body()),
    /cancelled or unavailable/,
  ); // visit of a different admission
  await assert.rejects(
    () => adm.attendance(other, e.id, s.id, body()),
    /not found|Admission access/i,
  );
  // an owner correction needs a reason of at least 2 characters
  await assert.rejects(
    () => adm.attendance(owner, e.id, s.id, body({ reason: "" })),
    /reason/,
  );
  await assert.rejects(
    () => adm.attendance(owner, e.id, s.id, body({ reason: " x " })),
    /reason/,
  );
  const staffer = await staff(["mark_attendance", "view_bookings"]);
  await assert.rejects(
    () => adm.attendance(staffer, e.id, s.id, body()),
    /owner must provide a reason/,
  );
  await adm.attendance(owner, e.id, s.id, body({ attendance: "unmarked" }));
  assert.equal((await detail(e.id)).used, 0);
});
test("session change: action enum, reason, date/time formats and fixed-only rule", async () => {
  const e = await enroll(
    enrollment({
      mode: "fixed",
      weekdays: [1, 2, 3, 4, 5, 6, 7],
      starts_on: plus(10),
      customer: {
        id: null,
        name: "Fixed Change",
        phone: "9666666666",
        email: null,
      },
    }),
  );
  const s = (await detail(e.id)).sessions[0];
  const body = (extra: Record<string, any> = {}) => ({
    command_key: randomUUID(),
    version: s.version,
    action: "reschedule",
    reason: "Customer asked",
    date: plus(20),
    time: "10:00",
    ...extra,
  });
  for (const extra of [
    { action: "" },
    { action: "delete" },
    { action: "CANCEL" },
    { action: null },
    { reason: "" },
    { reason: "x" },
    { reason: "r".repeat(501) },
    { date: "2026-02-30" },
    { date: "soon" },
    { date: 5 },
    { time: "25:00" },
    { time: "7:00" },
    { version: 0 },
    { version: 1.5 },
    { extra: 1 },
  ])
    await bad(
      () => adm.sessionChange(owner, e.id, s.id, body(extra)),
      JSON.stringify(extra),
    );
  await bad(() => adm.sessionChange(owner, e.id, "bad", body()));
  await assert.rejects(
    () => adm.sessionChange(owner, e.id, s.id, body({ date: undefined })),
    /future session/,
  );
  await assert.rejects(
    () => adm.sessionChange(owner, e.id, s.id, body({ time: undefined })),
    /future session/,
  );
  await assert.rejects(
    () => adm.sessionChange(owner, e.id, s.id, body({ date: plus(-1) })),
    /future session/,
  );
  await assert.rejects(
    () =>
      adm.sessionChange(owner, e.id, s.id, body({ version: s.version + 2 })),
    /changed/,
  );
  await assert.rejects(
    () => adm.sessionChange(owner, e.id, randomUUID(), body()),
    /fixed session/,
  );
  await assert.rejects(
    () => adm.sessionChange(other, e.id, s.id, body()),
    /not found|Admission access/i,
  );
  // waive on a future session is owner-only and requires an ended session
  const e2 = await enroll(
    enrollment({
      mode: "fixed",
      weekdays: [1, 2, 3, 4, 5, 6, 7],
      starts_on: plus(11),
      customer: {
        id: null,
        name: "Fixed Waive",
        phone: "9777777777",
        email: null,
      },
    }),
  );
  const s2 = (await detail(e2.id)).sessions[0];
  await assert.rejects(
    () =>
      adm.sessionChange(
        owner,
        e2.id,
        s2.id,
        body({ action: "waive", version: s2.version }),
      ),
    /restore credit/,
  );
  const flexible = await enroll();
  await assert.rejects(
    () => adm.sessionChange(owner, flexible.id, randomUUID(), body()),
    /fixed session/,
  );
});
test("session change: rescheduling beyond the plan expiry or before its start date must be rejected", async () => {
  const e = await enroll(
    enrollment({
      mode: "fixed",
      weekdays: [1, 2, 3, 4, 5, 6, 7],
      starts_on: plus(30),
      customer: {
        id: null,
        name: "Fixed Expiry",
        phone: "9666000001",
        email: null,
      },
    }),
  );
  const d = await detail(e.id);
  const s = d.sessions[0];
  const body = (date: string) => ({
    command_key: randomUUID(),
    version: s.version,
    action: "reschedule",
    reason: "Customer asked",
    date,
    time: "10:00",
  });
  await bad(
    () => adm.sessionChange(owner, e.id, s.id, body(plus(30 + 45 + 200))),
    "after expiry",
  );
  await bad(
    () => adm.sessionChange(owner, e.id, s.id, body(plus(5))),
    "before start",
  );
});

// ---------------------------------------------------------------- lists, search and detail
test("list: enum and id filters, cursor bounds and unknown keys", async () => {
  for (const q of [
    { kind: "yoga" },
    { kind: "" },
    { kind: "SWIMMING" },
    { status: "paused" },
    { status: "ACTIVE" },
    { business_id: "x" },
    { resource_id: "x" },
    { plan_id: 5 },
    { previous_plans: "yes" },
    { previous_plans: true },
    { needs_renewal: "1" },
    { cursor: -1 },
    { cursor: "-1" },
    { cursor: 100001 },
    { cursor: "abc" },
    { cursor: "1.5" },
    { q: "q".repeat(101) },
    { q: 5 },
    { extra: 1 },
  ])
    await bad(() => adm.list(owner, q), JSON.stringify(q));
  for (const q of [
    {},
    { kind: "swimming" },
    { status: "active" },
    { status: "deleted" },
    { cursor: 100000 },
    { cursor: "5" },
    { q: "q".repeat(100) },
    { previous_plans: "true" },
    { needs_renewal: "true" },
  ])
    assert.ok(await adm.list(owner, q), JSON.stringify(q));
  await bad(() => adm.expired(owner, { cursor: -1 }));
  await bad(() => adm.expired(owner, { extra: 1 }));
  assert.ok(await adm.expired(owner, {}));
});
test("list: search is case-insensitive and SQL fragments are inert", async () => {
  await enroll(
    enrollment({
      customer: {
        id: null,
        name: "Zelda Findable",
        phone: "9888000011",
        email: null,
      },
    }),
  );
  const n = async (q: string) => (await adm.list(owner, { q })).items.length;
  assert.equal(await n("zelda"), 1);
  assert.equal(await n("ZELDA FIND"), 1);
  assert.equal(await n("9888000011"), 1);
  assert.equal(await n("' OR '1'='1"), 0);
  assert.equal(await n("'; DROP TABLE admissions;--"), 0);
  assert.equal(await n("zzzz-no-such"), 0);
});
test(
  "list: % and _ are literal search characters, not wildcards",
  { todo: "BUG-8" },
  async () => {
    const total = (await adm.list(owner, {})).items.length;
    assert.ok(total > 1);
    assert.equal((await adm.list(owner, { q: "%" })).items.length, 0);
    assert.equal((await adm.list(owner, { q: "_" })).items.length, 0);
    assert.equal((await adm.list(owner, { q: "%%%" })).items.length, 0);
  },
);
test("customers search: short input returns nothing; roles enforced; tenant isolated", async () => {
  await enroll(
    enrollment({
      customer: {
        id: null,
        name: "Wilma Wildcard",
        phone: "9123000022",
        email: null,
      },
    }),
  );
  assert.deepEqual(await adm.customers(owner, ""), { items: [] });
  assert.deepEqual(await adm.customers(owner, "ab"), { items: [] });
  assert.deepEqual(await adm.customers(owner, "  a  "), { items: [] });
  assert.equal((await adm.customers(owner, "wilma")).items.length, 1);
  assert.equal((await adm.customers(owner, "912300")).items.length, 1);
  assert.equal((await adm.customers(owner, "' OR '1'='1")).items.length, 0);
  await bad(() => adm.customers(owner, "q".repeat(101)));
  await bad(() => adm.customers(owner, 5 as any));
  await bad(() => adm.customers(owner, ["a"] as any));
  const nobody = await staff([]);
  await assert.rejects(
    () => adm.customers(nobody, "wilma"),
    /Admission access/,
  );
  assert.equal((await adm.customers(other, "wilma")).items.length, 0); // other tenant
});
test(
  "customers search: '%%%' must not list every customer",
  { todo: "BUG-8" },
  async () => {
    assert.equal((await adm.customers(owner, "%%%")).items.length, 0);
    assert.equal((await adm.customers(owner, "___")).items.length, 0);
  },
);
test("detail/list: other tenants and unassigned staff cannot read an admission", async () => {
  const e = await enroll(
    enrollment({
      customer: {
        id: null,
        name: "Private Person",
        phone: "9555000033",
        email: null,
      },
    }),
  );
  await assert.rejects(
    () => adm.detail(other, e.id),
    /not found|Admission access/i,
  );
  await assert.rejects(() => adm.detail(owner, randomUUID()), /not found/);
  await bad(() => adm.detail(owner, "not-a-uuid"));
  const unassigned = await staff(
    ["view_bookings", "manage_subscriptions"],
    false,
  );
  await assert.rejects(() => adm.detail(unassigned, e.id), /not assigned/);
  assert.equal((await adm.list(unassigned, {})).items.length, 0);
  assert.equal(
    (await adm.list(other, { q: "Private Person" })).items.length,
    0,
  );
  assert.equal(
    (await adm.list(other, { business_id: business })).items.length,
    0,
  );
});

// ---------------------------------------------------------------- coaches
test("coach conflicts: field validation, owner-only and tenant scoping", async () => {
  const ok = {
    business_id: business,
    coach_id: "coach-1",
    plan_ids: [tracked],
  };
  for (const extra of [
    { business_id: "x" },
    { business_id: null },
    { coach_id: "" },
    { coach_id: "c".repeat(101) },
    { coach_id: null },
    { coach_id: 5 },
    { plan_ids: "x" },
    { plan_ids: null },
    { plan_ids: Array(51).fill("p") },
    { plan_ids: [""] },
    { plan_ids: [5] },
    { extra: 1 },
  ])
    await bad(
      () => adm.coachConflicts(owner, { ...ok, ...extra }),
      JSON.stringify(extra).slice(0, 60),
    );
  assert.deepEqual(await adm.coachConflicts(owner, { ...ok, plan_ids: [] }), {
    items: [],
  });
  assert.deepEqual(
    await adm.coachConflicts(owner, {
      ...ok,
      coach_id: "c".repeat(100),
      plan_ids: Array(50).fill("p"),
    }),
    { items: [] },
  );
  assert.deepEqual(
    await adm.coachConflicts(owner, { ...ok, plan_ids: ["' OR 1=1 --"] }),
    { items: [] },
  );
  await assert.rejects(
    () => adm.coachConflicts(other, ok),
    /Pool or court business not found/,
  );
  await assert.rejects(
    () => adm.coachConflicts(owner, { ...ok, business_id: otherBusiness }),
    /Pool or court business not found/,
  );
  const manager = await staff(["manage_subscriptions", "view_bookings"]);
  await assert.rejects(() => adm.coachConflicts(manager, ok), /Only the owner/);
});
test("coach classes: date validation and coach-only access", async () => {
  for (const date of ["", "2026-02-30", "soon", "2026-1-1", null, 5, undefined])
    await bad(() => adm.classes(owner, { date }), String(date));
  await bad(() => adm.classes(owner, { date: today, extra: 1 }));
  await bad(() => adm.classes(owner, null));
  const manager = await staff(["manage_subscriptions", "view_bookings"]);
  await assert.rejects(
    () => adm.classes(manager, { date: today }),
    /Only coaches/,
  );
  await assert.rejects(
    () => adm.classes(actor(), { date: today }),
    /Admission access/,
  );
});
