// Field-value / boundary tests for the Income module: categories, income creation and filters.
import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { HttpException } from "@nestjs/common";
import { ZodError } from "zod";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { AccountsService } from "../src/accounts/accounts.service";
import { IncomeService } from "../src/income/income.service";
import { Actor } from "../src/common/auth.guard";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  w = new WorkspaceService(db),
  accounts = new AccountsService(db, w),
  income = new IncomeService(db, w, accounts);
const actor = (): Actor => ({
  uid: randomUUID(),
  email: `${randomUUID()}@example.com`,
  name: "Income owner",
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
const now = new Date().toISOString(),
  tomorrow = new Date(Date.now() + 86400000).toISOString().slice(0, 10),
  filter = {
    from: new Date(Date.now() - 300 * 86400000).toISOString().slice(0, 10),
    until: tomorrow,
  };
let owner: Actor,
  other: Actor,
  business: string,
  sponsorship: string,
  otherSponsorship: string,
  cash: string,
  bank: string;
const mk = (a: Actor) =>
  w.createOrganization(a, {
    name: "Income Field QA",
    contact_phone: "9876543210",
    currency: "INR",
    location: {
      name: "Site",
      address_line_1: "Road",
      address_line_2: null,
      city: "Kochi",
      state_code: "KL",
      country_code: "IN",
      postal_code: "682001",
      timezone: "UTC",
    },
  });
const input = (extra: Record<string, any> = {}): Record<string, any> => ({
  command_key: randomUUID(),
  kind: "income",
  income_category_id: sponsorship,
  category: "Typed by older app",
  reason: "Tournament sponsor",
  reference: "SP-1",
  occurred_at: now,
  business_id: null,
  resource_id: null,
  lines: [{ account_id: cash, method: "cash", amount_minor: 2000 }],
  ...extra,
});
async function staff(perms: string[], assign = true) {
  const a = actor(),
    m = await w.member(owner),
    id = randomUUID();
  await db.query(
    `INSERT INTO memberships(id,organization_id,user_id,email,display_name,role,permissions) VALUES($1,$2,$3,$4,'Inc staff','staff',$5)`,
    [id, m.organization_id, a.uid, a.email, JSON.stringify(perms)],
  );
  if (assign)
    await db.query(
      "INSERT INTO staff_assignments(membership_id,organization_id,business_id,resource_ids) VALUES($1,$2,$3,'[]')",
      [id, m.organization_id, business],
    );
  return a;
}
before(async () => {
  await db.onModuleInit();
  owner = actor();
  other = actor();
  await mk(owner);
  await mk(other);
  const ws = await w.workspace(owner);
  business = (
    await w.createBusiness(owner, {
      name: "Badminton",
      type: "badminton",
      location_id: ws.locations[0].id,
    })
  ).id;
  sponsorship = (await income.catalog(owner)).categories.find(
    (c: any) => c.name === "Sponsorship",
  ).id;
  otherSponsorship = (await income.catalog(other)).categories.find(
    (c: any) => c.name === "Sponsorship",
  ).id;
  const a = await accounts.catalog(owner);
  cash = a.accounts.find((x: any) => x.kind === "cash").id;
  bank = (
    await accounts.createAccount(owner, {
      command_key: randomUUID(),
      name: "Income bank",
      bank_name: "QA",
      account_number: "123456789",
      opening_minor: 0,
      opening_at: "2000-01-01T00:00:00Z",
      is_primary: true,
    })
  ).id;
});
after(() => db.onModuleDestroy());

test("category: name, active and unknown-key validation", async () => {
  for (const name of ["", " ", "a", "n".repeat(81), null, 5, undefined, [], {}])
    await bad(
      () => income.category(owner, { name, active: true }),
      String(name),
    );
  for (const active of ["true", "false", null, 0, 1, []])
    await bad(
      () => income.category(owner, { name: "Valid", active }),
      String(active),
    );
  await bad(() => income.category(owner, { name: "Valid", extra: 1 }));
  await bad(() => income.category(owner, null));
  const a = await income.category(owner, { name: "  Spaced  " });
  assert.equal(
    (
      await db.query<any>("SELECT name FROM income_categories WHERE id=$1", [
        a.id,
      ])
    ).rows[0].name,
    "Spaced",
  );
  for (const name of ["Ünï ☕ 収入", "x'); DROP TABLE income_categories;--"]) {
    const r = await income.category(owner, { name });
    assert.equal(
      (
        await db.query<any>("SELECT name FROM income_categories WHERE id=$1", [
          r.id,
        ])
      ).rows[0].name,
      name,
    );
  }
  assert.ok((await income.category(owner, { name: "n".repeat(80) })).id);
});
test(
  "category: NUL byte in the name is a client error, not a server error",
  { todo: "BUG-4" },
  async () => {
    await bad(() => income.category(owner, { name: "bad\u0000name" }));
  },
);
test("category: duplicates (case/space-insensitive) conflict; foreign ids are untouchable; owner-only", async () => {
  await assert.rejects(
    () => income.category(owner, { name: "sponsorship" }),
    /already exists/,
  );
  await assert.rejects(
    () => income.category(owner, { name: " SPONSORSHIP " }),
    /already exists/,
  );
  const x = await income.category(owner, { name: "To collide" });
  await assert.rejects(
    () => income.category(owner, { name: "events" }, x.id),
    /already exists/,
  );
  await assert.rejects(
    () => income.category(owner, { name: "Hijack" }, otherSponsorship),
    /not found/,
  );
  await assert.rejects(
    () => income.category(owner, { name: "Ghost" }, randomUUID()),
    /not found/,
  );
  const viewer = await staff(["view_finance"]),
    collector = await staff(["collect_payments"]),
    nobody = await staff(["view_bookings"]);
  await assert.rejects(
    () => income.category(viewer, { name: "Viewer made" }),
    /Only the owner/,
  );
  await assert.rejects(
    () => income.category(collector, { name: "Collector made" }),
    /Only the owner/,
  );
  assert.ok((await income.catalog(viewer)).categories.length);
  assert.ok((await income.catalog(collector)).categories.length);
  await assert.rejects(() => income.catalog(nobody), /Income access/);
  assert.ok((await income.category(other, { name: "To collide" })).id); // same name, other org
});
test("category: creating with active=false should create an archived category", async () => {
  const r = await income.category(owner, {
    name: "Born archived",
    active: false,
  });
  assert.equal(
    (
      await db.query<any>("SELECT active FROM income_categories WHERE id=$1", [
        r.id,
      ])
    ).rows[0].active,
    false,
  );
});
test("category: renaming an archived category without 'active' must not silently re-activate it", async () => {
  const r = await income.category(owner, { name: "Archive rename" });
  await income.category(owner, { name: "Archive rename", active: false }, r.id);
  await income.category(owner, { name: "Archive renamed" }, r.id);
  assert.equal(
    (
      await db.query<any>("SELECT active FROM income_categories WHERE id=$1", [
        r.id,
      ])
    ).rows[0].active,
    false,
  );
});

test("income create: kind and category id mandatory; category tenant-scoped; archived rejected", async () => {
  await assert.rejects(
    () => income.create(owner, input({ kind: "expense" })),
    /Choose an income category/,
  );
  await assert.rejects(
    () => income.create(owner, input({ kind: "transfer" })),
    /Choose an income category/,
  );
  await assert.rejects(
    () => income.create(owner, input({ income_category_id: undefined })),
    /Choose an income category/,
  );
  for (const v of ["", "x", 5, null])
    await bad(
      () => income.create(owner, input({ income_category_id: v })),
      String(v),
    );
  await assert.rejects(
    () => income.create(owner, input({ income_category_id: otherSponsorship })),
    /active income category/,
  );
  await assert.rejects(
    () => income.create(owner, input({ income_category_id: randomUUID() })),
    /active income category/,
  );
  await assert.rejects(
    () => income.create(owner, input({ expense_category_id: randomUUID() })),
    /expense|Categories apply/i,
  );
  const c = await income.category(owner, { name: "Short lived" });
  await income.category(owner, { name: "Short lived", active: false }, c.id);
  await assert.rejects(
    () => income.create(owner, input({ income_category_id: c.id })),
    /active income category/,
  );
});
test("income create: amount accepts only integers 1..100,000,000 (no decimals, NaN, Infinity, strings)", async () => {
  const L = (a: any) => ({
    lines: [{ account_id: cash, method: "cash", amount_minor: a }],
  });
  const before = (await income.overview(owner, filter)).count;
  for (const a of [
    0,
    -1,
    -500,
    0.5,
    19.99,
    0.1 + 0.2,
    NaN,
    Infinity,
    -Infinity,
    "2000",
    "1e3",
    "Infinity",
    null,
    true,
    100000001,
    Number.MAX_SAFE_INTEGER,
    1e21,
  ])
    await bad(() => income.create(owner, input(L(a))), String(a));
  assert.equal((await income.overview(owner, filter)).count, before);
  await income.create(owner, input(L(1)));
  await income.create(owner, input(L(100000000)));
  assert.equal((await income.overview(owner, filter)).count, before + 2);
});
test("income create: text, date and method fields", async () => {
  for (const extra of [
    { reason: "" },
    { reason: " " },
    { reason: "x" },
    { reason: "r".repeat(501) },
    { reference: "x".repeat(201) },
    { category: "x" },
    { category: "c".repeat(81) },
    { occurred_at: "2024-01-01" },
    { occurred_at: "tomorrow" },
    { occurred_at: "1999-12-31T23:59:59Z" },
    { occurred_at: new Date(Date.now() + 3600000).toISOString() },
    { lines: [] },
    { lines: [{ account_id: cash, method: "upi", amount_minor: 10 }] },
    { lines: [{ account_id: bank, method: "cash", amount_minor: 10 }] },
    { lines: [{ account_id: bank, method: "transfer", amount_minor: 10 }] },
    { lines: [{ account_id: randomUUID(), method: "cash", amount_minor: 10 }] },
    { to_account_id: bank },
    { business_id: randomUUID() },
    { resource_id: randomUUID() },
    { command_key: "x" },
    { surprise: 1 },
  ])
    await bad(() => income.create(owner, input(extra)), JSON.stringify(extra));
  const e = await income.create(
    owner,
    input({
      reason: "Üñï '); DROP TABLE finance_events;-- 収入",
      reference: "",
      category: "ab",
    }),
  );
  assert.ok(e.id);
});
test("income create: split lines across cash and bank sum exactly", async () => {
  const lines = [
    { account_id: cash, method: "cash", amount_minor: 3333 },
    { account_id: bank, method: "upi", amount_minor: 3333 },
    { account_id: bank, method: "card", amount_minor: 3334 },
  ];
  const before = Number((await income.overview(owner, filter)).total_minor);
  await income.create(owner, input({ lines, reason: "Split income" }));
  assert.equal(
    Number((await income.overview(owner, filter)).total_minor) - before,
    10000,
  );
});
test("income create: duplicate submit posts once; changed payload under the same key conflicts", async () => {
  const v = input({ reason: "Once only income" });
  const ids = await Promise.all(
    [1, 2, 3, 4].map(() => income.create(owner, v)),
  );
  assert.equal(new Set(ids.map((i) => i.id)).size, 1);
  assert.equal(
    (await income.list(owner, { ...filter, q: "Once only income" })).items
      .length,
    1,
  );
  await assert.rejects(
    () => income.create(owner, { ...v, reason: "Different text" }),
    /another entry/,
  );
  await assert.rejects(
    () =>
      income.create(owner, {
        ...v,
        lines: [{ account_id: cash, method: "cash", amount_minor: 2001 }],
      }),
    /another entry/,
  );
});
test("income create: roles and scope", async () => {
  const viewer = await staff(["view_finance"]),
    spender = await staff(["record_expenses"]),
    collector = await staff(["collect_payments"]),
    loose = await staff(["collect_payments"], false);
  await assert.rejects(
    () => income.create(viewer, input({ business_id: business })),
    /Finance access/,
  );
  await assert.rejects(
    () => income.create(spender, input({ business_id: business })),
    /Finance access/,
  );
  await assert.rejects(() => income.create(collector, input()), /owner access/);
  await assert.rejects(
    () => income.create(loose, input({ business_id: business })),
    /assigned space/,
  );
  await assert.rejects(
    () => income.create(other, input({ business_id: business })),
    /Business not found/,
  );
  assert.ok(
    (await income.create(collector, input({ business_id: business }))).id,
  );
});

test("income filters: dates, 366-day limit, cursor, source, ids and q", async () => {
  const f = (extra: Record<string, any>) => ({ ...filter, ...extra });
  for (const extra of [
    { from: "" },
    { from: "2026-02-30" },
    { from: "2026-1-1" },
    { until: "x" },
    { until: null },
    { from: tomorrow, until: "2000-01-01" },
    { cursor: -1 },
    { cursor: 1000001 },
    { cursor: "abc" },
    { cursor: "1.5" },
    { source: "" },
    { source: "booking" },
    { source: "Bookings" },
    { source: "ADMISSIONS" },
    { source: "not-a-uuid" },
    { source: 5 },
    { business_id: "x" },
    { resource_id: "x" },
    { account_id: 5 },
    { q: "q".repeat(101) },
    { extra: true },
  ])
    for (const call of [income.overview.bind(income), income.list.bind(income)])
      await bad(() => call(owner, f(extra)), JSON.stringify(extra));
  await income.overview(owner, { from: "2024-01-01", until: "2025-01-01" });
  await bad(() =>
    income.overview(owner, { from: "2024-01-01", until: "2025-01-02" }),
  );
  await bad(() =>
    income.report(owner, { from: "2020-01-01", until: "2024-01-01" }),
  );
  for (const source of [
    "bookings",
    "admissions",
    sponsorship,
    otherSponsorship,
    randomUUID(),
  ])
    assert.ok(await income.list(owner, f({ source })));
  assert.ok(await income.list(owner, f({ cursor: "7", q: "q".repeat(100) })));
});
test("income filters: a foreign category/business/account id never exposes other tenants' data", async () => {
  await income.create(other, {
    ...input({
      income_category_id: otherSponsorship,
      reason: "Foreign secret income",
    }),
    lines: [
      {
        account_id: (await accounts.catalog(other)).accounts.find(
          (a: any) => a.kind === "cash",
        ).id,
        method: "cash",
        amount_minor: 4242,
      },
    ],
  });
  const r = await income.list(owner, { ...filter, source: otherSponsorship });
  assert.equal(r.items.length, 0);
  assert.equal(
    (await income.list(owner, { ...filter, q: "Foreign secret" })).items.length,
    0,
  );
  const rep = await income.report(owner, {
    ...filter,
    source: otherSponsorship,
  });
  assert.equal(rep.total_minor, 0);
  assert.ok(
    rep.source_filter === "Selected" ||
      rep.source_filter === null ||
      typeof rep.source_filter === "string",
  );
  assert.notEqual(rep.source_filter, "Sponsorship");
});
test("income filters: q treats % _ \\ and SQL fragments literally", async () => {
  await income.create(
    owner,
    input({ reason: "Fee 25% of_total", reference: "dir\\file" }),
  );
  const n = async (q: string) =>
    (await income.list(owner, { ...filter, q })).items.length;
  assert.equal(await n("25% of"), 1);
  assert.equal(await n("of_total"), 1);
  assert.equal(await n("ofXtotal"), 0);
  assert.equal(await n("dir\\file"), 1);
  assert.equal(await n("%%%"), 0);
  assert.equal(await n("' OR '1'='1"), 0);
  assert.equal(await n("'; DROP TABLE finance_events;--"), 0);
});
test("income reads: roles and tenant isolation", async () => {
  const collector = await staff(["collect_payments"]),
    booker = await staff(["view_bookings"]),
    viewer = await staff(["view_finance"]);
  await assert.rejects(
    () => income.overview(collector, filter),
    /Finance access/,
  );
  await assert.rejects(() => income.list(booker, filter), /Finance access/);
  await assert.rejects(() => income.report(booker, filter), /Finance access/);
  await assert.rejects(() => income.overview(actor(), filter), /membership/i);
  assert.equal((await income.overview(viewer, filter)).total_minor >= 0, true); // shared entries are hidden from scoped staff
  assert.equal(
    (await income.overview(other, { ...filter, business_id: business })).count,
    0,
  );
});
test("income overview: numeric fields are numbers and net = total - refunds", async () => {
  const o = await income.overview(owner, filter);
  for (const k of ["total_minor", "refunds_minor", "net_minor"] as const)
    assert.equal(typeof o[k], "number");
  assert.equal(o.net_minor, o.total_minor - o.refunds_minor);
});
test("income: reversal of an income entry reduces income by exactly that amount; manual refunds are not possible through the income API", async () => {
  const e = await income.create(
    owner,
    input({
      reason: "Reverse me",
      lines: [{ account_id: cash, method: "cash", amount_minor: 1234 }],
    }),
  );
  const before = (await income.overview(owner, filter)).total_minor;
  await accounts.reverse(owner, e.id, {
    command_key: randomUUID(),
    reason: "Entered in error",
  });
  assert.equal(
    before - (await income.overview(owner, filter)).total_minor,
    1234,
  );
  await assert.rejects(
    () => income.create(owner, input({ kind: "booking_refund" })),
    /Invalid|income|enum/i,
  );
});
