// Field-value / boundary tests for the Expenses module: categories, expense creation, filters and invoice attachments.
import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { HttpException } from "@nestjs/common";
import { ZodError } from "zod";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { AccountsService } from "../src/accounts/accounts.service";
import { ExpensesService } from "../src/expenses/expenses.service";
import { InvoiceStorage } from "../src/expenses/invoice-storage";
import { Actor } from "../src/common/auth.guard";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  w = new WorkspaceService(db),
  accounts = new AccountsService(db, w),
  expenses = new ExpensesService(db, w, accounts);
const actor = (): Actor => ({
  uid: randomUUID(),
  email: `${randomUUID()}@example.com`,
  name: "Expense owner",
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
const files = new Set<string>();
const storage: InvoiceStorage = {
  async upload(path) {
    return `https://example.test/${path}`;
  },
  async verify(path) {
    if (!files.has(path)) throw new Error("Not uploaded");
  },
  async download(path) {
    return `https://example.test/read/${path}`;
  },
  async remove(paths) {
    paths.forEach((p) => files.delete(p));
  },
};
const now = new Date().toISOString(),
  tomorrow = new Date(Date.now() + 86400000).toISOString().slice(0, 10),
  yearFilter = {
    from: new Date(Date.now() - 300 * 86400000).toISOString().slice(0, 10),
    until: tomorrow,
  },
  filter = yearFilter;
let owner: Actor,
  other: Actor,
  business: string,
  category: string,
  cash: string,
  bank: string,
  otherCategory: string,
  otherOrgId: string;
const mk = (a: Actor) =>
  w.createOrganization(a, {
    name: "Expense Field QA",
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
  kind: "expense",
  expense_category_id: category,
  category: "Ignored",
  reason: "Ground repairs",
  reference: "INV-1",
  occurred_at: now,
  business_id: null,
  resource_id: null,
  lines: [{ account_id: cash, method: "cash", amount_minor: 1000 }],
  ...extra,
});
async function staff(perms: string[], assign = true, resources: string[] = []) {
  const a = actor(),
    m = await w.member(owner),
    id = randomUUID();
  await db.query(
    `INSERT INTO memberships(id,organization_id,user_id,email,display_name,role,permissions) VALUES($1,$2,$3,$4,'Exp staff','staff',$5)`,
    [id, m.organization_id, a.uid, a.email, JSON.stringify(perms)],
  );
  if (assign)
    await db.query(
      "INSERT INTO staff_assignments(membership_id,organization_id,business_id,resource_ids) VALUES($1,$2,$3,$4)",
      [id, m.organization_id, business, JSON.stringify(resources)],
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
  const c = await expenses.catalog(owner);
  category = c.categories.find((x: any) => x.name === "Maintenance").id;
  otherCategory = (await expenses.catalog(other)).categories.find(
    (x: any) => x.name === "Maintenance",
  ).id;
  const a = await accounts.catalog(owner);
  cash = a.accounts.find((x: any) => x.kind === "cash").id;
  bank = (
    await accounts.createAccount(owner, {
      command_key: randomUUID(),
      name: "Expense bank",
      bank_name: "QA",
      account_number: "123456789",
      opening_minor: 0,
      opening_at: "2000-01-01T00:00:00Z",
      is_primary: true,
    })
  ).id;
  otherOrgId = (await w.member(other)).organization_id;
  expenses.storage = storage;
});
after(() => db.onModuleDestroy());

// ---------------------------------------------------------------- categories
test("category: name length, whitespace, type and unknown-key rules", async () => {
  for (const name of [
    "",
    " ",
    "a",
    " a ",
    "n".repeat(81),
    null,
    5,
    undefined,
    [],
    {},
  ])
    await bad(
      () => expenses.category(owner, { name, active: true }),
      String(name),
    );
  await bad(() =>
    expenses.category(owner, { name: "Valid name", active: "false" }),
  );
  await bad(() =>
    expenses.category(owner, { name: "Valid name", active: null }),
  );
  await bad(() => expenses.category(owner, { name: "Valid name", active: 0 }));
  await bad(() => expenses.category(owner, { name: "Valid name", extra: 1 }));
  await bad(() => expenses.category(owner, null));
  await bad(() => expenses.category(owner, "x"));
  const a = await expenses.category(owner, { name: "ab" });
  const b = await expenses.category(owner, { name: "n".repeat(80) });
  assert.ok(a.id && b.id);
  const padded = await expenses.category(owner, { name: "   Padded name   " });
  const row = (
    await db.query<any>("SELECT name FROM expense_categories WHERE id=$1", [
      padded.id,
    ])
  ).rows[0];
  assert.equal(row.name, "Padded name");
});
test("category: unicode and SQL-looking names are stored literally", async () => {
  for (const name of [
    "Café ☕ 設備",
    "x'); DROP TABLE expense_categories;--",
    "<b>bold</b>",
  ]) {
    const r = await expenses.category(owner, { name });
    assert.equal(
      (
        await db.query<any>("SELECT name FROM expense_categories WHERE id=$1", [
          r.id,
        ])
      ).rows[0].name,
      name,
    );
  }
  assert.ok((await expenses.catalog(owner)).categories.length >= 10);
});
test(
  "category: NUL byte in the name is a client error, not a server error",
  { todo: "BUG-4" },
  async () => {
    await bad(() => expenses.category(owner, { name: "bad\u0000name" }));
  },
);
test("category: names are unique ignoring case and surrounding spaces; rename collisions conflict", async () => {
  await assert.rejects(
    () => expenses.category(owner, { name: "maintenance" }),
    /already exists/,
  );
  await assert.rejects(
    () => expenses.category(owner, { name: "  MAINTENANCE  " }),
    /already exists/,
  );
  const x = await expenses.category(owner, { name: "Unique rename source" });
  await assert.rejects(
    () => expenses.category(owner, { name: "food" }, x.id),
    /already exists/,
  );
  // The same name may exist in another organisation.
  assert.ok(
    (await expenses.category(other, { name: "Unique rename source" })).id,
  );
});
test("category: foreign or unknown ids are not editable", async () => {
  await assert.rejects(
    () => expenses.category(owner, { name: "Hijack" }, otherCategory),
    /not found/,
  );
  await assert.rejects(
    () => expenses.category(owner, { name: "Ghost" }, randomUUID()),
    /not found/,
  );
  const row = (
    await db.query<any>("SELECT name FROM expense_categories WHERE id=$1", [
      otherCategory,
    ])
  ).rows[0];
  assert.equal(row.name, "Maintenance");
});
test("category: only the owner may manage categories; viewers may read the catalog", async () => {
  const viewer = await staff(["view_finance"]),
    spender = await staff(["record_expenses"]),
    nobody = await staff(["view_bookings"]);
  await assert.rejects(
    () => expenses.category(viewer, { name: "Viewer made" }),
    /Only the owner/,
  );
  await assert.rejects(
    () => expenses.category(spender, { name: "Spender made" }, category),
    /Only the owner/,
  );
  assert.ok((await expenses.catalog(viewer)).categories.length);
  assert.ok((await expenses.catalog(spender)).categories.length);
  await assert.rejects(() => expenses.catalog(nobody), /Expense access/);
  await assert.rejects(() => expenses.catalog(actor()), /membership/i);
});
test("category: creating a category with active=false should create an archived category", async () => {
  const r = await expenses.category(owner, {
    name: "Born archived",
    active: false,
  });
  const row = (
    await db.query<any>("SELECT active FROM expense_categories WHERE id=$1", [
      r.id,
    ])
  ).rows[0];
  assert.equal(row.active, false);
});
test("category: renaming an archived category without sending 'active' must not silently re-activate it", async () => {
  const r = await expenses.category(owner, { name: "Archive then rename" });
  await expenses.category(
    owner,
    { name: "Archive then rename", active: false },
    r.id,
  );
  await expenses.category(owner, { name: "Archive then renamed" }, r.id);
  const row = (
    await db.query<any>("SELECT active FROM expense_categories WHERE id=$1", [
      r.id,
    ])
  ).rows[0];
  assert.equal(row.active, false);
});

// ---------------------------------------------------------------- creating expenses
test("expense create: kind and category id are mandatory and typed", async () => {
  await assert.rejects(
    () => expenses.create(owner, input({ kind: "income" })),
    /Choose an expense category/,
  );
  await assert.rejects(
    () => expenses.create(owner, input({ kind: "transfer" })),
    /Choose an expense category/,
  );
  await assert.rejects(
    () => expenses.create(owner, input({ expense_category_id: undefined })),
    /Choose an expense category/,
  );
  for (const expense_category_id of ["", "x", 5, null])
    await bad(
      () => expenses.create(owner, input({ expense_category_id })),
      String(expense_category_id),
    );
  await assert.rejects(
    () => expenses.create(owner, input({ expense_category_id: otherCategory })),
    /active expense category/,
  );
  await assert.rejects(
    () => expenses.create(owner, input({ expense_category_id: randomUUID() })),
    /active expense category/,
  );
  await assert.rejects(
    () => expenses.create(owner, input({ income_category_id: randomUUID() })),
    /income only|Income categories/i,
  );
});
test("expense create: amounts accept integers 1..100,000,000 only; no partial writes on rejection", async () => {
  const before = (await expenses.overview(owner, filter)).count;
  const mkLine = (amount_minor: any) => ({
    lines: [{ account_id: cash, method: "cash", amount_minor }],
  });
  for (const a of [
    0,
    -1,
    -0.01,
    0.5,
    12.345,
    0.1 + 0.2,
    NaN,
    Infinity,
    "500",
    "1e3",
    null,
    true,
    100000001,
    Number.MAX_SAFE_INTEGER,
    1e21,
  ])
    await bad(() => expenses.create(owner, input(mkLine(a))), String(a));
  assert.equal((await expenses.overview(owner, filter)).count, before);
  await expenses.create(owner, input(mkLine(1)));
  await expenses.create(owner, input(mkLine(100000000)));
  assert.equal((await expenses.overview(owner, filter)).count, before + 2);
});
test("expense create: split lines add exactly (no rounding drift) and report totals match", async () => {
  const lines = [333, 333, 334].map((n) => ({
    account_id: cash,
    method: "cash",
    amount_minor: n,
  }));
  const r = await expenses.create(
    owner,
    input({ lines, reason: "Three way split" }),
  );
  const d = await expenses.detail(owner, r.id);
  assert.equal(d.amount_minor, 1000);
  assert.equal(d.lines.length, 3);
  const row = (await expenses.list(owner, { ...filter, q: "Three way" }))
    .items[0];
  assert.equal(Number(row.amount_minor), 1000);
});
test("expense create: text fields, dates and ids follow the shared entry rules", async () => {
  for (const extra of [
    { reason: "" },
    { reason: " " },
    { reason: "x" },
    { reason: "r".repeat(501) },
    { reference: "x".repeat(201) },
    { category: "x" },
    { category: "c".repeat(81) },
    { occurred_at: "2024-01-01" },
    { occurred_at: "nonsense" },
    { occurred_at: "1999-12-31T23:59:59Z" },
    { occurred_at: new Date(Date.now() + 3600000).toISOString() },
    { lines: [] },
    { lines: [{ account_id: randomUUID(), method: "cash", amount_minor: 10 }] },
    { lines: [{ account_id: bank, method: "cash", amount_minor: 10 }] },
    { lines: [{ account_id: cash, method: "upi", amount_minor: 10 }] },
    { business_id: randomUUID() },
    { resource_id: randomUUID() },
    { to_account_id: bank },
    { command_key: "nope" },
    { surprise: 1 },
  ])
    await bad(
      () => expenses.create(owner, input(extra)),
      JSON.stringify(extra),
    );
  const r = await expenses.create(
    owner,
    input({ reason: "ab", reference: "", category: "ab" }),
  );
  assert.ok(r.id);
  const u = await expenses.create(
    owner,
    input({ reason: "Unï ☕ '); DROP TABLE finance_events;--" }),
  );
  assert.ok((await expenses.detail(owner, u.id)).reason.includes("DROP TABLE"));
});
test("expense create: duplicate submit posts once; same key with different data conflicts", async () => {
  const v = input({ reason: "Idempotent expense" });
  const ids = await Promise.all(
    [1, 2, 3, 4].map(() => expenses.create(owner, v)),
  );
  assert.equal(new Set(ids.map((i) => i.id)).size, 1);
  assert.equal(
    (await expenses.list(owner, { ...filter, q: "Idempotent expense" })).items
      .length,
    1,
  );
  await assert.rejects(
    () =>
      expenses.create(owner, {
        ...v,
        lines: [{ account_id: cash, method: "cash", amount_minor: 1001 }],
      }),
    /another entry/,
  );
});
test("expense create: role denial - needs record_expenses, scope and an assigned space", async () => {
  const viewer = await staff(["view_finance"]),
    collector = await staff(["collect_payments"]),
    spender = await staff(["record_expenses"]),
    loose = await staff(["record_expenses"], false);
  await assert.rejects(
    () => expenses.create(viewer, input({ business_id: business })),
    /Finance access/,
  );
  await assert.rejects(
    () => expenses.create(collector, input({ business_id: business })),
    /Finance access/,
  );
  await assert.rejects(() => expenses.create(spender, input()), /owner access/); // shared expense
  await assert.rejects(
    () => expenses.create(loose, input({ business_id: business })),
    /assigned space/,
  );
  await assert.rejects(
    () => expenses.create(other, input({ business_id: business })),
    /Business not found/,
  );
  assert.ok(
    (await expenses.create(spender, input({ business_id: business }))).id,
  );
});
test("expense create: cross-tenant cash/bank accounts are rejected without side effects", async () => {
  const foreignCash = (await accounts.catalog(other)).accounts.find(
    (a: any) => a.kind === "cash",
  ).id;
  await assert.rejects(
    () =>
      expenses.create(
        owner,
        input({
          lines: [
            { account_id: foreignCash, method: "cash", amount_minor: 100 },
          ],
        }),
      ),
    /active accounts/,
  );
  const bal = (await accounts.catalog(other)).accounts.find(
    (a: any) => a.id === foreignCash,
  ).balance_minor;
  assert.equal(bal, 0);
});
test("expense create: archived category rejects new entries but keeps old ones visible", async () => {
  const c = await expenses.category(owner, { name: "Soon archived" });
  const e = await expenses.create(
    owner,
    input({ expense_category_id: c.id, reason: "Before archive" }),
  );
  await expenses.category(
    owner,
    { name: "Soon archived", active: false },
    c.id,
  );
  await assert.rejects(
    () => expenses.create(owner, input({ expense_category_id: c.id })),
    /active expense category/,
  );
  assert.equal(
    (await expenses.detail(owner, e.id)).category_name,
    "Soon archived",
  );
});

// ---------------------------------------------------------------- reads / filters
test("expense filters: dates, range limit (max 366 days), cursor, ids and q", async () => {
  const f = (extra: Record<string, any>) => ({ ...yearFilter, ...extra });
  for (const extra of [
    { from: "" },
    { from: "2026-02-30" },
    { from: "2026-1-1" },
    { until: "x" },
    { until: null },
    { from: tomorrow, until: "2000-01-01" },
    { cursor: -1 },
    { cursor: "-5" },
    { cursor: 1000001 },
    { cursor: "abc" },
    { cursor: "1.5" },
    { category_id: "x" },
    { business_id: "x" },
    { resource_id: 5 },
    { account_id: "" },
    { q: "q".repeat(101) },
    { q: 3 },
    { extra: true },
  ])
    for (const call of [
      expenses.overview.bind(expenses),
      expenses.list.bind(expenses),
    ])
      await bad(() => call(owner, f(extra)), JSON.stringify(extra));
  // 366 days apart is allowed, 367 is not.
  await expenses.overview(owner, { from: "2024-01-01", until: "2025-01-01" });
  await bad(() =>
    expenses.overview(owner, { from: "2024-01-01", until: "2025-01-02" }),
  );
  await bad(() =>
    expenses.report(owner, { from: "2020-01-01", until: "2024-01-01" }),
  );
  assert.ok(await expenses.list(owner, f({ cursor: "3" })));
  assert.ok(await expenses.list(owner, f({ q: "q".repeat(100) })));
});
test("expense filters: q matches % and _ literally and treats SQL fragments as text", async () => {
  await expenses.create(
    owner,
    input({ reason: "Paint 50% off_sale", reference: "c:\\path" }),
  );
  const n = async (q: string) =>
    (await expenses.list(owner, { ...filter, q })).items.length;
  assert.equal(await n("50% off"), 1);
  assert.equal(await n("off_sale"), 1);
  assert.equal(await n("offXsale"), 0);
  assert.equal(await n("c:\\path"), 1);
  assert.equal(await n("%%%"), 0);
  assert.equal(await n("' OR 1=1 --"), 0);
  assert.equal(await n("'; DROP TABLE finance_events;--"), 0);
});
test("expense reads: roles and tenant isolation", async () => {
  const e = await expenses.create(owner, input({ reason: "Tenant isolation" }));
  const spender = await staff(["record_expenses"]),
    booker = await staff(["view_bookings"]),
    viewer = await staff(["view_finance"], true, []);
  await assert.rejects(
    () => expenses.overview(spender, filter),
    /Expense access/,
  ); // needs view_finance
  await assert.rejects(() => expenses.list(booker, filter), /Expense access/);
  await assert.rejects(() => expenses.detail(booker, e.id), /Expense access/);
  await assert.rejects(() => expenses.detail(other, e.id), /not found/);
  await assert.rejects(() => expenses.detail(owner, randomUUID()), /not found/);
  await assert.rejects(() => expenses.detail(viewer, e.id), /not found/); // shared (no business) is outside an assigned scope
  assert.equal(
    (await expenses.list(other, { ...filter, q: "Tenant isolation" })).items
      .length,
    0,
  );
  assert.equal(
    (await expenses.list(other, { ...filter, category_id: category })).items
      .length,
    0,
  );
  assert.equal(
    (await expenses.overview(other, { ...filter, business_id: business }))
      .count,
    0,
  );
});
test(
  "expense overview: total type is consistent (number) with the income module",
  { todo: "BUG-7" },
  async () => {
    const o = await expenses.overview(owner, filter);
    assert.equal(typeof o.total_minor, "number");
  },
);
test("expense overview: reversal nets to zero and is traceable", async () => {
  const e = await expenses.create(
    owner,
    input({
      reason: "Net zero check",
      lines: [{ account_id: cash, method: "cash", amount_minor: 777 }],
    }),
  );
  const before = Number((await expenses.overview(owner, filter)).total_minor);
  await accounts.reverse(owner, e.id, {
    command_key: randomUUID(),
    reason: "Entered twice",
  });
  const after = Number((await expenses.overview(owner, filter)).total_minor);
  assert.equal(before - after, 777);
  assert.equal((await expenses.detail(owner, e.id)).reversals.length, 1);
});

// ---------------------------------------------------------------- attachments
const att = (extra: Record<string, any> = {}) => ({
  id: randomUUID(),
  name: "bill.pdf",
  content_type: "application/pdf",
  size_bytes: 100,
  ...extra,
});
let eventId: string;
test("attachment fixture", async () => {
  eventId = (
    await expenses.create(owner, input({ reason: "Attachment target" }))
  ).id;
});
test("attachment: name length, whitespace, unicode and path-like names never influence the storage path", async () => {
  for (const name of ["", "   ", "n".repeat(181), null, 5, undefined])
    await bad(
      () => expenses.prepare(owner, eventId, att({ name })),
      String(name),
    );
  for (const name of [
    "x",
    "n".repeat(180),
    "../../etc/passwd",
    "bill 😀 税.pdf",
    "a'; DROP TABLE expense_attachments;--.pdf",
  ]) {
    const v = att({ name });
    await expenses.prepare(owner, eventId, v);
    const row = (
      await db.query<any>(
        "SELECT name,object_path FROM expense_attachments WHERE id=$1",
        [v.id],
      )
    ).rows[0];
    assert.equal(row.name, name);
    assert.equal(
      row.object_path,
      `${(await w.member(owner)).organization_id}/${eventId}/${v.id}`,
    );
  }
});
test("attachment: content_type must be an exact allowed MIME type", async () => {
  for (const content_type of [
    "image/gif",
    "IMAGE/PNG",
    "image/png ",
    "application/pdf; charset=utf-8",
    "text/html",
    "application/octet-stream",
    "",
    null,
    5,
    undefined,
    "image/svg+xml",
    "image/*",
  ])
    await bad(
      () => expenses.prepare(owner, eventId, att({ content_type })),
      String(content_type),
    );
});
test("attachment: size_bytes accepts integers 1..15 MiB", async () => {
  const max = 15 * 1024 * 1024;
  for (const size_bytes of [
    0,
    -1,
    0.5,
    1.5,
    NaN,
    Infinity,
    "100",
    null,
    undefined,
    max + 1,
    Number.MAX_SAFE_INTEGER,
    1e21,
  ])
    await bad(
      () => expenses.prepare(owner, eventId, att({ size_bytes })),
      String(size_bytes),
    );
  const e2 = (await expenses.create(owner, input({ reason: "Size bounds" })))
    .id;
  assert.equal(
    (await expenses.prepare(owner, e2, att({ size_bytes: 1 }))).ready,
    false,
  );
  assert.equal(
    (await expenses.prepare(owner, e2, att({ size_bytes: max }))).ready,
    false,
  );
});
test("attachment: id must be a uuid; unknown keys rejected; identifiers cannot be hijacked", async () => {
  for (const id of ["", "x", 5, null, undefined])
    await bad(() => expenses.prepare(owner, eventId, att({ id })), String(id));
  await bad(() => expenses.prepare(owner, eventId, att({ extra: 1 })));
  const v = att();
  const e2 = (await expenses.create(owner, input({ reason: "Hijack target" })))
    .id;
  await expenses.prepare(owner, eventId, v);
  await assert.rejects(
    () => expenses.prepare(owner, eventId, { ...v, size_bytes: 101 }),
    /different upload/,
  );
  await assert.rejects(
    () => expenses.prepare(owner, eventId, { ...v, name: "other.pdf" }),
    /different upload/,
  );
  await assert.rejects(
    () => expenses.prepare(owner, e2, v),
    /different upload/,
  ); // other event
  // A foreign organisation cannot attach to or probe this event
  await assert.rejects(
    () => expenses.prepare(other, eventId, att()),
    /not found/,
  );
  await assert.rejects(
    () => expenses.complete(other, eventId, v.id),
    /not found/,
  );
  await assert.rejects(
    () => expenses.attachment(other, eventId, v.id),
    /not found/,
  );
  await assert.rejects(
    () => expenses.removePending(other, eventId, v.id),
    /not found/,
  );
});
test("attachment: an attachment id used by another organisation cannot be re-used", async () => {
  const mine = att();
  await expenses.prepare(owner, eventId, mine);
  const foreignExpense = await expenses.create(other, {
    ...input(),
    expense_category_id: otherCategory,
    lines: [
      {
        account_id: (await accounts.catalog(other)).accounts.find(
          (a: any) => a.kind === "cash",
        ).id,
        method: "cash",
        amount_minor: 10,
      },
    ],
  });
  await assert.rejects(
    () => expenses.prepare(other, foreignExpense.id, mine),
    /different upload/,
  );
});
test("attachment: at most 10 files per expense", async () => {
  const e = (await expenses.create(owner, input({ reason: "Ten files" }))).id;
  for (let i = 0; i < 10; i++) await expenses.prepare(owner, e, att());
  await assert.rejects(() => expenses.prepare(owner, e, att()), /up to 10/);
});
test("attachment: pending files can be completed only after upload, retrieved only when ready, and removed only while pending", async () => {
  const e = (await expenses.create(owner, input({ reason: "Lifecycle" }))).id;
  const v = att();
  assert.equal((await expenses.prepare(owner, e, v)).ready, false);
  await assert.rejects(() => expenses.complete(owner, e, v.id)); // storage has no object
  await assert.rejects(() => expenses.attachment(owner, e, v.id), /not found/); // not ready
  await assert.rejects(
    () => expenses.complete(owner, e, randomUUID()),
    /not found/,
  );
  await assert.rejects(
    () => expenses.removePending(owner, e, randomUUID()),
    /Pending invoice not found/,
  );
  const path = (
    await db.query<any>(
      "SELECT object_path FROM expense_attachments WHERE id=$1",
      [v.id],
    )
  ).rows[0].object_path;
  files.add(path);
  assert.deepEqual(await expenses.complete(owner, e, v.id), { id: v.id });
  assert.deepEqual(await expenses.complete(owner, e, v.id), { id: v.id }); // idempotent
  assert.ok((await expenses.attachment(owner, e, v.id)).url.includes(path));
  await assert.rejects(
    () => expenses.removePending(owner, e, v.id),
    /Pending invoice not found/,
  ); // ready files stay
  // pending removal
  const p = att();
  await expenses.prepare(owner, e, p);
  await expenses.removePending(owner, e, p.id);
  await assert.rejects(
    () => expenses.removePending(owner, e, p.id),
    /Pending invoice not found/,
  );
});
test("attachment: staff may attach only to expenses they recorded in their scope", async () => {
  const s1 = await staff(["record_expenses", "view_finance"]),
    s2 = await staff(["record_expenses", "view_finance"]),
    viewer = await staff(["view_finance"]);
  const e = (
    await expenses.create(
      s1,
      input({ business_id: business, reason: "Staff owned" }),
    )
  ).id;
  assert.equal((await expenses.prepare(s1, e, att())).ready, false);
  await assert.rejects(
    () => expenses.prepare(s2, e, att()),
    /Only the owner or recording staff/,
  );
  await assert.rejects(
    () => expenses.prepare(viewer, e, att()),
    /Expense access/,
  );
  assert.equal((await expenses.prepare(owner, e, att())).ready, false);
  assert.equal((await expenses.detail(s2, e)).can_attach, false);
  assert.equal((await expenses.detail(s1, e)).can_attach, true);
});
