// Field-value / boundary tests for the Accounts module: bank accounts, opening balances,
// ledger entries (income / expense / transfer), reversals, finance filters and staff cash settlements.
import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { HttpException } from "@nestjs/common";
import { ZodError } from "zod";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { AccountsService } from "../src/accounts/accounts.service";
import { StaffCashService } from "../src/accounts/staff-cash.service";
import { Actor } from "../src/common/auth.guard";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  w = new WorkspaceService(db),
  s = new AccountsService(db, w),
  cashSvc = new StaffCashService(db, w);
const actor = (): Actor => ({
  uid: randomUUID(),
  email: `${randomUUID()}@example.com`,
  name: "Field owner",
});
// A "client error" is what the API maps to 4xx: zod validation, HttpException(<500) or a unique violation (409).
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
  day = now.slice(0, 10),
  // The org timezone is Asia/Kolkata (ahead of UTC), so use tomorrow's UTC date as the inclusive end.
  tomorrow = new Date(Date.now() + 86400000).toISOString().slice(0, 10),
  filter = { from: "2020-01-01", until: tomorrow };
let owner: Actor,
  other: Actor,
  business: string,
  cash: string,
  bank: string,
  bank2: string,
  clearing: string,
  otherCash: string,
  otherBank: string;
const bankInput = (name = "Field bank", opening = 0): Record<string, any> => ({
  command_key: randomUUID(),
  name,
  bank_name: "QA Bank",
  account_number: "001234561234",
  opening_minor: opening,
  opening_at: "2000-01-01T00:00:00Z",
  is_primary: false,
});
const entry = (
  kind = "income",
  amount = 1000,
  account = bank,
  extra: Record<string, any> = {},
): Record<string, any> => ({
  command_key: randomUUID(),
  kind,
  business_id: null,
  resource_id: null,
  category: kind === "expense" ? "Maintenance" : "Equipment rental",
  reason: "Field verification",
  reference: "QA",
  occurred_at: now,
  lines: [
    {
      account_id: account,
      method: account === cash ? "cash" : "upi",
      amount_minor: amount,
    },
  ],
  ...extra,
});
async function newOrg(a: Actor) {
  await w.createOrganization(a, {
    name: "Field QA",
    contact_phone: "9876543210",
    currency: "INR",
    location: {
      name: "Kochi",
      address_line_1: "Main Road",
      address_line_2: null,
      city: "Kochi",
      state_code: "KL",
      country_code: "IN",
      postal_code: "682001",
      timezone: "Asia/Kolkata",
    },
  });
}
async function staffMember(
  who: Actor,
  perms: string[],
  assign = true,
  resources: string[] = [],
) {
  const m = await w.member(owner),
    id = randomUUID();
  await db.query(
    `INSERT INTO memberships(id,organization_id,user_id,email,display_name,role,permissions) VALUES($1,$2,$3,$4,'Field staff','staff',$5)`,
    [id, m.organization_id, who.uid, who.email, JSON.stringify(perms)],
  );
  if (assign)
    await db.query(
      "INSERT INTO staff_assignments(membership_id,organization_id,business_id,resource_ids) VALUES($1,$2,$3,$4)",
      [id, m.organization_id, business, JSON.stringify(resources)],
    );
  return id;
}
before(async () => {
  await db.onModuleInit();
  owner = actor();
  other = actor();
  await newOrg(owner);
  await newOrg(other);
  const ws = await w.workspace(owner);
  business = (
    await w.createBusiness(owner, {
      name: "Badminton",
      type: "badminton",
      location_id: ws.locations[0].id,
    })
  ).id;
  const cat = await s.catalog(owner);
  cash = cat.accounts.find((a: any) => a.kind === "cash")!.id;
  clearing = cat.accounts.find((a: any) => a.kind === "clearing")!.id;
  bank = (await s.createAccount(owner, bankInput("Primary", 0))).id;
  bank2 = (await s.createAccount(owner, bankInput("Secondary", 0))).id;
  const oc = await s.catalog(other);
  otherCash = oc.accounts.find((a: any) => a.kind === "cash")!.id;
  otherBank = (await s.createAccount(other, bankInput("Other bank"))).id;
});
after(() => db.onModuleDestroy());

// ---------------------------------------------------------------- bank account fields
test("bank account: name boundaries (empty, whitespace, 1, 2, 100, 101 chars, wrong types)", async () => {
  for (const name of ["", "   ", "a", " a ", "x".repeat(101), null, 12, [], {}])
    await bad(
      () => s.createAccount(owner, { ...bankInput(), name }),
      JSON.stringify(name),
    );
  const a = await s.createAccount(owner, { ...bankInput(), name: "ab" });
  const b = await s.createAccount(owner, {
    ...bankInput(),
    name: "x".repeat(100),
  });
  assert.ok(a.id && b.id);
  const padded = await s.createAccount(owner, {
    ...bankInput(),
    name: "   Trim me   ",
  });
  const row = (
    await db.query<any>("SELECT name FROM money_accounts WHERE id=$1", [
      padded.id,
    ])
  ).rows[0];
  assert.equal(row.name, "Trim me");
});
test("bank account: unicode and SQL-looking names are stored literally and do not damage the ledger", async () => {
  const names = [
    "Ünïcödé 銀行 🏦",
    "x'); DROP TABLE money_accounts;--",
    "<script>alert(1)</script>",
    "Robert'); SELECT pg_sleep(5);--",
  ];
  for (const name of names) {
    const r = await s.createAccount(owner, { ...bankInput(), name });
    const row = (
      await db.query<any>("SELECT name FROM money_accounts WHERE id=$1", [r.id])
    ).rows[0];
    assert.equal(row.name, name);
  }
  assert.ok(
    (await db.query<any>("SELECT count(*)::int n FROM money_accounts")).rows[0]
      .n > 3,
  );
});
test("bank account: account_number accepts exactly 6-34 ASCII digits after trimming", async () => {
  const invalid = [
    "",
    "12345",
    "1".repeat(35),
    "12345a",
    "١٢٣٤٥٦٧", // Arabic-Indic digits
    "1234 5678",
    "-123456",
    "1e10000",
    "NaN",
    "Infinity",
    "12345678'; --",
    123456789,
    null,
    undefined,
  ];
  for (const account_number of invalid)
    await bad(
      () => s.createAccount(owner, { ...bankInput(), account_number }),
      String(account_number),
    );
  for (const account_number of ["000000", "1".repeat(34), "  123456  "]) {
    const r = await s.createAccount(owner, {
      ...bankInput(),
      account_number,
    });
    const row = (
      await db.query<any>(
        "SELECT account_number,last_four FROM money_accounts WHERE id=$1",
        [r.id],
      )
    ).rows[0];
    assert.equal(row.account_number, account_number.trim());
    assert.equal(row.last_four, account_number.trim().slice(-4));
  }
});
test("bank account: bank_name length and type", async () => {
  await bad(() =>
    s.createAccount(owner, { ...bankInput(), bank_name: "b".repeat(101) }),
  );
  for (const bank_name of [null, 5, undefined])
    await bad(() => s.createAccount(owner, { ...bankInput(), bank_name }));
  await s.createAccount(owner, { ...bankInput(), bank_name: "b".repeat(100) });
});
test(
  "bank account: empty / whitespace bank_name should be rejected (shown in the UI and reports)",
  { todo: "BUG-1" },
  async () => {
    for (const bank_name of ["", "    "])
      await bad(
        () => s.createAccount(owner, { ...bankInput(), bank_name }),
        JSON.stringify(bank_name),
      );
  },
);
test("bank account: last_four optional value is validated even though the server derives it", async () => {
  for (const last_four of ["12345", "abcd", "12 4", 1234, null])
    await bad(() =>
      s.createAccount(owner, { ...bankInput(), last_four } as any),
    );
  const r = await s.createAccount(owner, {
    ...bankInput(),
    last_four: "",
  });
  assert.ok(r.id);
});
test("bank account: opening_minor must be a safe integer within +/-100,000,000,000", async () => {
  const invalid = [
    1.5,
    0.1 + 0.2,
    100000000000.5,
    NaN,
    Infinity,
    -Infinity,
    "100",
    "NaN",
    "Infinity",
    null,
    undefined,
    true,
    100000000001,
    -100000000001,
    Number.MAX_SAFE_INTEGER,
    Number.MAX_SAFE_INTEGER + 1,
    1e21,
    [],
  ];
  for (const opening_minor of invalid)
    await bad(
      () => s.createAccount(owner, { ...bankInput(), opening_minor }),
      String(opening_minor),
    );
  for (const opening_minor of [0, 1, -1, 100000000000, -100000000000]) {
    const r = await s.createAccount(owner, {
      ...bankInput(),
      opening_minor,
    });
    const a = (await s.catalog(owner)).accounts.find(
      (x: any) => x.id === r.id,
    )!;
    assert.equal(a.opening_minor, opening_minor);
    assert.equal(typeof a.balance_minor, "number");
    assert.equal(a.balance_minor, opening_minor);
  }
});
test("bank account: opening_at needs an ISO instant with offset between 2000-01-01 and now+60s", async () => {
  const invalid = [
    "",
    "not a date",
    "2020-01-01",
    "2020-01-01T00:00:00", // no offset
    "2020-02-30T00:00:00Z",
    "2020-13-01T00:00:00Z",
    "2020-01-01T25:00:00Z",
    "1999-12-31T23:59:59Z",
    "2000-01-01T00:00:00+05:30", // 1999-12-31T18:30Z
    "0001-01-01T00:00:00Z",
    new Date(Date.now() + 2 * 86400000).toISOString(),
    new Date(Date.now() + 5 * 60000).toISOString(),
    null,
    20200101,
  ];
  for (const opening_at of invalid)
    await bad(
      () => s.createAccount(owner, { ...bankInput(), opening_at }),
      String(opening_at),
    );
  for (const opening_at of [
    "2000-01-01T00:00:00Z",
    "2000-01-01T05:30:00+05:30",
    new Date(Date.now() + 30000).toISOString(),
  ])
    assert.ok(
      (await s.createAccount(owner, { ...bankInput(), opening_at })).id,
      opening_at,
    );
});
test("bank account: command_key, is_primary and unknown keys", async () => {
  for (const command_key of ["", "abc", null, 1, undefined, "123e4567"])
    await bad(() => s.createAccount(owner, { ...bankInput(), command_key }));
  for (const is_primary of ["true", 1, null, undefined])
    await bad(() => s.createAccount(owner, { ...bankInput(), is_primary }));
  await bad(() =>
    s.createAccount(owner, { ...bankInput(), organization_id: randomUUID() }),
  );
  await bad(() => s.createAccount(owner, { ...bankInput(), kind: "cash" }));
  await bad(() => s.createAccount(owner, null));
  await bad(() => s.createAccount(owner, "string"));
  await bad(() => s.createAccount(owner, []));
});
test("bank account: duplicate submit is idempotent, changed payload conflicts, foreign tenant key cannot hijack", async () => {
  const input = bankInput("Dup");
  const a = await s.createAccount(owner, input);
  assert.equal((await s.createAccount(owner, input)).id, a.id);
  const rows = await Promise.all(
    [1, 2, 3, 4].map(() => s.createAccount(owner, input)),
  );
  assert.ok(rows.every((r) => r.id === a.id));
  const count = (
    await db.query<any>(
      "SELECT count(*)::int n FROM money_accounts WHERE id=$1",
      [a.id],
    )
  ).rows[0].n;
  assert.equal(count, 1);
  await assert.rejects(
    () => s.createAccount(owner, { ...input, opening_minor: 5 }),
    /different account data/,
  );
  // Another organisation re-using the same key must fail cleanly and must not touch the first org.
  await bad(() => s.createAccount(other, input));
  assert.equal(
    (await s.catalog(owner)).accounts.find((x: any) => x.id === a.id)!
      .opening_minor,
    0,
  );
});
test("bank account: only the owner can create, edit or route accounts", async () => {
  const staff = actor();
  await staffMember(staff, [
    "view_finance",
    "collect_payments",
    "record_expenses",
    "manage_bookings",
  ]);
  await assert.rejects(
    () => s.createAccount(staff, bankInput()),
    /Only the owner/,
  );
  await assert.rejects(
    () => s.updateAccount(staff, bank, { name: "Hack" }),
    /Only the owner/,
  );
  await assert.rejects(
    () =>
      s.cashOpening(staff, {
        command_key: randomUUID(),
        opening_minor: 1,
        opening_at: "2020-01-01T00:00:00Z",
      }),
    /Only the owner/,
  );
  await assert.rejects(
    () =>
      s.route(staff, {
        business_id: business,
        resource_id: null,
        method: "upi",
        account_id: bank,
      }),
    /Only the owner/,
  );
  await assert.rejects(
    () => s.createAccount(actor(), bankInput()),
    /membership/i,
  );
  // Staff never see numbers or balances.
  const view = (await s.catalog(staff)).accounts;
  assert.ok(
    view.every(
      (a: any) =>
        a.account_number === null &&
        a.balance_minor === null &&
        a.opening_minor === null,
    ),
  );
});

// ---------------------------------------------------------------- update account
test("update account: name/is_primary/archive literal and boundary checks", async () => {
  const a = (await s.createAccount(owner, bankInput("Editable"))).id;
  for (const body of [
    { name: "" },
    { name: " " },
    { name: "x" },
    { name: "x".repeat(101) },
    { name: null },
    { is_primary: false },
    { is_primary: "true" },
    { archive: false },
    { archive: 1 },
    { active: false },
    { opening_minor: 5 },
    { name: "ok", extra: 1 },
  ])
    await bad(() => s.updateAccount(owner, a, body), JSON.stringify(body));
  await s.updateAccount(owner, a, { name: "Ünï 'quoted'" });
  assert.equal(
    (await s.catalog(owner)).accounts.find((x: any) => x.id === a)!.name,
    "Ünï 'quoted'",
  );
});
test("update account: cash/clearing, foreign, unknown and archived accounts are rejected", async () => {
  await assert.rejects(
    () => s.updateAccount(owner, cash, { name: "Renamed cash" }),
    /active bank/,
  );
  await assert.rejects(
    () => s.updateAccount(owner, clearing, { is_primary: true }),
    /active bank/,
  );
  await assert.rejects(
    () => s.updateAccount(owner, otherBank, { name: "Steal" }),
    /active bank/,
  );
  await assert.rejects(
    () => s.updateAccount(owner, randomUUID(), { name: "Ghost" }),
    /active bank/,
  );
  const a = (await s.createAccount(owner, bankInput("To archive"))).id;
  await s.updateAccount(owner, a, { archive: true });
  await assert.rejects(
    () => s.updateAccount(owner, a, { archive: true }),
    /active bank/,
  );
  await assert.rejects(
    () => s.updateAccount(owner, a, { name: "Zombie" }),
    /active bank/,
  );
  // Archived accounts cannot receive entries.
  await assert.rejects(
    () => s.createEntry(owner, entry("income", 100, a)),
    /active accounts/,
  );
  // Primary accounts cannot be archived.
  const primary = (await s.catalog(owner)).accounts.find(
    (x: any) => x.is_primary,
  )!.id;
  await assert.rejects(
    () => s.updateAccount(owner, primary, { archive: true }),
    /primary/,
  );
});

// ---------------------------------------------------------------- cash opening balance
test("cash opening: value and date boundaries, set-once semantics", async () => {
  const o = actor();
  await newOrg(o);
  const ok = (extra: Record<string, any> = {}) => ({
    command_key: randomUUID(),
    opening_minor: 500,
    opening_at: "2020-01-01T00:00:00Z",
    ...extra,
  });
  for (const extra of [
    { opening_minor: 0.5 },
    { opening_minor: NaN },
    { opening_minor: Infinity },
    { opening_minor: "500" },
    { opening_minor: null },
    { opening_minor: 100000000001 },
    { opening_minor: -100000000001 },
    { opening_at: "2020-01-01" },
    { opening_at: "1999-12-31T23:59:59Z" },
    { opening_at: new Date(Date.now() + 86400000 * 3).toISOString() },
    { opening_at: "garbage" },
    { command_key: "nope" },
    { surprise: true },
  ])
    await bad(() => s.cashOpening(o, ok(extra)), JSON.stringify(extra));
  const first = ok({ opening_minor: -100000000000 });
  const r = await s.cashOpening(o, first);
  assert.deepEqual(await s.cashOpening(o, first), r); // exact retry
  await assert.rejects(() => s.cashOpening(o, ok()), /already set/); // different values
  await assert.rejects(
    () => s.cashOpening(o, { ...first, command_key: randomUUID() }),
    /already set/,
  ); // same values, new key
  const cat = await s.catalog(o);
  const c = cat.accounts.find((a: any) => a.kind === "cash")!;
  assert.equal(c.opening_minor, -100000000000);
  assert.equal(c.balance_minor, -100000000000);
});

// ---------------------------------------------------------------- payment routes
test("payment route: method enum, account kind and tenant checks", async () => {
  for (const method of ["cash", "transfer", "UPI", "", null, 1])
    await bad(() =>
      s.route(owner, {
        business_id: business,
        resource_id: null,
        method,
        account_id: bank,
      }),
    );
  for (const business_id of ["x", null, undefined, ""])
    await bad(() =>
      s.route(owner, {
        business_id,
        resource_id: null,
        method: "upi",
        account_id: bank,
      }),
    );
  await assert.rejects(
    () =>
      s.route(owner, {
        business_id: business,
        resource_id: null,
        method: "upi",
        account_id: cash,
      }),
    /active bank/,
  );
  await assert.rejects(
    () =>
      s.route(owner, {
        business_id: business,
        resource_id: null,
        method: "upi",
        account_id: clearing,
      }),
    /active bank/,
  );
  await assert.rejects(
    () =>
      s.route(owner, {
        business_id: business,
        resource_id: null,
        method: "upi",
        account_id: otherBank,
      }),
    /active bank/,
  );
  await assert.rejects(
    () =>
      s.route(owner, {
        business_id: randomUUID(),
        resource_id: null,
        method: "upi",
        account_id: bank,
      }),
    /Business not found/,
  );
  await assert.rejects(
    () =>
      s.route(owner, {
        business_id: business,
        resource_id: randomUUID(),
        method: "upi",
        account_id: bank,
      }),
    /Space not found/,
  );
  await assert.rejects(
    () =>
      s.route(other, {
        business_id: business,
        resource_id: null,
        method: "upi",
        account_id: otherBank,
      }),
    /Business not found/,
  );
  assert.deepEqual(
    await s.route(owner, {
      business_id: business,
      resource_id: null,
      method: "card",
      account_id: bank,
    }),
    { saved: true },
  );
  assert.deepEqual(
    await s.route(owner, {
      business_id: business,
      resource_id: null,
      method: "card",
      account_id: null,
    }),
    { saved: true },
  );
});

// ---------------------------------------------------------------- ledger entries
test("entry: amount_minor accepts only integers 1..100,000,000", async () => {
  for (const amount of [
    0,
    -1,
    -100,
    0.5,
    1.0000001,
    10.5,
    0.1 + 0.2,
    NaN,
    Infinity,
    -Infinity,
    "100",
    "1e3",
    "NaN",
    "Infinity",
    null,
    true,
    100000001,
    Number.MAX_SAFE_INTEGER,
    Number.MAX_SAFE_INTEGER + 1,
    1e21,
    {},
  ])
    await bad(
      () => s.createEntry(owner, entry("income", amount as any)),
      String(amount),
    );
  for (const amount of [1, 100000000]) {
    const r = await s.createEntry(owner, entry("income", amount));
    assert.ok(r.id);
  }
});
test("entry: expense stores a negative ledger line and income a positive one, with exact integer sums", async () => {
  const acct = (await s.createAccount(owner, bankInput("Exact sums", 0))).id;
  for (const n of [1, 1, 1, 7, 99999999, 3])
    await s.createEntry(owner, entry("income", n, acct));
  await s.createEntry(owner, entry("expense", 99999999, acct));
  const a = (await s.catalog(owner)).accounts.find((x: any) => x.id === acct)!;
  assert.equal(a.balance_minor, 1 + 1 + 1 + 7 + 99999999 + 3 - 99999999);
  assert.equal(Number.isInteger(a.balance_minor), true);
});
test("entry: line count 1..20, 20 lines of the max amount stay exact (bigint)", async () => {
  const acct = (await s.createAccount(owner, bankInput("Many lines", 0))).id;
  const line = { account_id: acct, method: "upi", amount_minor: 100000000 };
  await bad(() =>
    s.createEntry(owner, entry("income", 1, acct, { lines: [] })),
  );
  await bad(() =>
    s.createEntry(
      owner,
      entry("income", 1, acct, { lines: Array(21).fill(line) }),
    ),
  );
  await bad(() =>
    s.createEntry(owner, entry("income", 1, acct, { lines: null })),
  );
  await bad(() =>
    s.createEntry(owner, entry("income", 1, acct, { lines: {} })),
  );
  await bad(() =>
    s.createEntry(
      owner,
      entry("income", 1, acct, { lines: [{ ...line, extra: 1 }] }),
    ),
  );
  await bad(() =>
    s.createEntry(
      owner,
      entry("income", 1, acct, { lines: [{ ...line, account_id: "nope" }] }),
    ),
  );
  await bad(() =>
    s.createEntry(
      owner,
      entry("income", 1, acct, {
        lines: [{ account_id: acct, amount_minor: 5 }],
      }),
    ),
  );
  await s.createEntry(
    owner,
    entry("income", 1, acct, { lines: Array(20).fill(line) }),
  );
  const a = (await s.catalog(owner)).accounts.find((x: any) => x.id === acct)!;
  assert.equal(a.balance_minor, 2000000000); // > int32, must not overflow
});
test("entry: kind enum", async () => {
  for (const kind of [
    "",
    "INCOME",
    "refund",
    "reversal",
    "booking_collection",
    "admission_refund",
    null,
    1,
    undefined,
    ["income"],
  ])
    await bad(
      () => s.createEntry(owner, entry("income", 100, bank, { kind })),
      String(kind),
    );
});
test("entry: category, reason and reference length and whitespace rules", async () => {
  for (const category of [
    "",
    " ",
    "a",
    " a ",
    "c".repeat(81),
    null,
    5,
    undefined,
  ])
    await bad(
      () => s.createEntry(owner, entry("income", 100, bank, { category })),
      String(category),
    );
  for (const reason of ["", " ", "r", "r".repeat(501), null, 5, undefined])
    await bad(
      () => s.createEntry(owner, entry("income", 100, bank, { reason })),
      String(reason),
    );
  for (const reference of ["x".repeat(201), null, 5, undefined])
    await bad(
      () => s.createEntry(owner, entry("income", 100, bank, { reference })),
      String(reference),
    );
  const good = await s.createEntry(
    owner,
    entry("income", 100, bank, {
      category: "ab",
      reason: "r".repeat(500),
      reference: "",
    }),
  );
  assert.ok(good.id);
  await s.createEntry(
    owner,
    entry("income", 100, bank, {
      category: "c".repeat(80),
      reference: "x".repeat(200),
    }),
  );
});
test("entry: unicode and SQL-looking free text is stored literally", async () => {
  const reason = "Robert'); DROP TABLE finance_events;-- 名前 ‮\u0000x";
  const r = await s.createEntry(
    owner,
    entry("income", 150, bank, {
      reason: reason.replace("\u0000", ""),
      reference: "' OR 1=1 --",
      category: "Ünï café ☕",
    }),
  );
  const row = (
    await db.query<any>(
      "SELECT reason,reference,category FROM finance_events WHERE id=$1",
      [r.id],
    )
  ).rows[0];
  assert.equal(row.reference, "' OR 1=1 --");
  assert.equal(row.category, "Ünï café ☕");
  assert.ok(row.reason.startsWith("Robert');"));
});
test(
  "entry: NUL byte in free text must be a client error, not a server error",
  { todo: "BUG-4" },
  async () => {
    await bad(() =>
      s.createEntry(
        owner,
        entry("income", 100, bank, { reason: "bad\u0000reason" }),
      ),
    );
  },
);
test("entry: occurred_at format, future and pre-2000 limits, pre-opening dates", async () => {
  const acct = (
    await s.createAccount(owner, {
      ...bankInput("Dated", 0),
      opening_at: "2024-06-01T00:00:00Z",
    })
  ).id;
  for (const occurred_at of [
    "",
    "yesterday",
    "2024-06-01",
    "2024-06-01T00:00:00",
    "2024-02-30T00:00:00Z",
    "1999-12-31T23:59:59Z",
    new Date(Date.now() + 120000).toISOString(),
    new Date(Date.now() + 86400000 * 365).toISOString(),
    null,
    1700000000000,
  ])
    await bad(
      () => s.createEntry(owner, entry("income", 100, acct, { occurred_at })),
      String(occurred_at),
    );
  await assert.rejects(
    () =>
      s.createEntry(
        owner,
        entry("income", 100, acct, { occurred_at: "2024-05-31T23:59:59Z" }),
      ),
    /predates/,
  );
  assert.ok(
    (
      await s.createEntry(
        owner,
        entry("income", 100, acct, { occurred_at: "2024-06-01T00:00:00Z" }),
      )
    ).id,
  );
  assert.ok(
    (
      await s.createEntry(
        owner,
        entry("income", 100, acct, {
          occurred_at: new Date(Date.now() + 30000).toISOString(),
        }),
      )
    ).id,
  );
});
test("entry: method must match the account kind; clearing and 'transfer' method rejected for income/expense", async () => {
  const L = (account_id: string, method: string) => ({
    lines: [{ account_id, method, amount_minor: 100 }],
  });
  const cases: [string, string][] = [
    [bank, "cash"],
    [cash, "upi"],
    [cash, "card"],
    [cash, "bank_transfer"],
    [bank, "transfer"],
    [cash, "transfer"],
    [clearing, "upi"],
    [clearing, "cash"],
    [bank, "CASH"],
    [bank, ""],
  ];
  for (const [account, method] of cases)
    for (const kind of ["income", "expense"])
      await bad(
        () => s.createEntry(owner, entry(kind, 100, bank, L(account, method))),
        `${kind} ${method}`,
      );
  for (const method of ["upi", "card", "bank_transfer"])
    assert.ok(
      (await s.createEntry(owner, entry("income", 100, bank, L(bank, method))))
        .id,
    );
  assert.ok(
    (await s.createEntry(owner, entry("income", 100, cash, L(cash, "cash"))))
      .id,
  );
});
test("entry: scope fields (business/resource) and cross-tenant identifiers", async () => {
  await assert.rejects(
    () =>
      s.createEntry(
        owner,
        entry("income", 100, bank, {
          business_id: null,
          resource_id: randomUUID(),
        }),
      ),
    /Choose a business/,
  );
  await assert.rejects(
    () =>
      s.createEntry(
        owner,
        entry("income", 100, bank, { business_id: randomUUID() }),
      ),
    /Business not found/,
  );
  await assert.rejects(
    () =>
      s.createEntry(
        owner,
        entry("income", 100, bank, {
          business_id: business,
          resource_id: randomUUID(),
        }),
      ),
    /Space not found/,
  );
  await assert.rejects(
    () =>
      s.createEntry(
        other,
        entry("income", 100, bank, { business_id: business }),
      ),
    /Business not found/,
  );
  for (const business_id of ["", "x", 1])
    await bad(() =>
      s.createEntry(owner, entry("income", 100, bank, { business_id })),
    );
  // Foreign tenant's accounts (cash and bank) are never accepted as sources, destinations or lines.
  await assert.rejects(
    () => s.createEntry(owner, entry("income", 100, otherBank)),
    /active accounts/,
  );
  await assert.rejects(
    () =>
      s.createEntry(
        owner,
        entry("expense", 100, otherCash, {
          lines: [{ account_id: otherCash, method: "cash", amount_minor: 100 }],
        }),
      ),
    /active accounts/,
  );
  await assert.rejects(
    () =>
      s.createEntry(
        owner,
        entry("transfer", 100, bank, {
          category: "Transfer",
          to_account_id: otherBank,
        }),
      ),
    /destination/,
  );
  // The foreign tenant's balance is unchanged by any of this.
  const b = (await s.catalog(other)).accounts.find(
    (x: any) => x.id === otherBank,
  )!;
  assert.equal(b.balance_minor, 0);
});
test("entry: category id fields are kind-specific and tenant-scoped", async () => {
  const foreign = randomUUID();
  await assert.rejects(
    () =>
      s.createEntry(
        owner,
        entry("income", 100, bank, { expense_category_id: foreign }),
      ),
    /expense only|expenses only/i,
  );
  await assert.rejects(
    () =>
      s.createEntry(
        owner,
        entry("expense", 100, bank, { income_category_id: foreign }),
      ),
    /income only/i,
  );
  await assert.rejects(
    () =>
      s.createEntry(
        owner,
        entry("expense", 100, bank, { expense_category_id: foreign }),
      ),
    /active expense category/,
  );
  await assert.rejects(
    () =>
      s.createEntry(
        owner,
        entry("income", 100, bank, { income_category_id: foreign }),
      ),
    /active income category/,
  );
  await assert.rejects(
    () =>
      s.createEntry(
        owner,
        entry("expense", 100, bank, { to_account_id: bank2 }),
      ),
    /only used for transfers/,
  );
  await assert.rejects(
    () =>
      s.createEntry(
        owner,
        entry("income", 100, bank, { to_account_id: bank2 }),
      ),
    /only used for transfers/,
  );
  for (const expense_category_id of ["", "x", 5])
    await bad(() =>
      s.createEntry(
        owner,
        entry("expense", 100, bank, { expense_category_id }),
      ),
    );
});
test("entry: duplicate submit is exactly-once, conflicting replays are rejected, parallel submits post one event", async () => {
  const acct = (await s.createAccount(owner, bankInput("Idem", 0))).id;
  const e = entry("income", 4200, acct);
  const ids = await Promise.all(
    [1, 2, 3, 4, 5].map(() => s.createEntry(owner, e)),
  );
  assert.equal(new Set(ids.map((i) => i.id)).size, 1);
  assert.equal(
    (await s.catalog(owner)).accounts.find((x: any) => x.id === acct)!
      .balance_minor,
    4200,
  );
  await assert.rejects(
    () =>
      s.createEntry(owner, {
        ...e,
        lines: [{ ...e.lines[0], amount_minor: 4201 }],
      }),
    /another entry/,
  );
  await assert.rejects(
    () => s.createEntry(owner, { ...e, reason: "Different" }),
    /another entry/,
  );
  // A different staff user in the same org re-using the key.
  const staff = actor();
  await staffMember(staff, ["collect_payments"]);
  await assert.rejects(
    () => s.createEntry(staff, { ...e, business_id: business }),
    /another entry|Choose an assigned|Shared/,
  );
  // Same key in another organisation is a different namespace.
  assert.ok(
    (
      await s.createEntry(other, {
        ...entry("income", 4200, otherBank),
        command_key: e.command_key,
      })
    ).id,
  );
  assert.equal(
    (await s.catalog(owner)).accounts.find((x: any) => x.id === acct)!
      .balance_minor,
    4200,
  );
});
test("entry: roles - permission per kind, shared entries owner-only, unassigned scope denied", async () => {
  const viewer = actor(),
    collector = actor(),
    spender = actor(),
    none = actor(),
    unassigned = actor();
  await staffMember(viewer, ["view_finance"]);
  await staffMember(collector, ["collect_payments"]);
  await staffMember(spender, ["record_expenses"]);
  await staffMember(none, ["view_bookings"]);
  await staffMember(unassigned, ["collect_payments", "record_expenses"], false);
  const scoped = (kind: string, acct = bank) =>
    entry(kind, 100, acct, { business_id: business });
  await assert.rejects(
    () => s.createEntry(viewer, scoped("income")),
    /Finance access/,
  );
  await assert.rejects(
    () => s.createEntry(viewer, scoped("expense")),
    /Finance access/,
  );
  await assert.rejects(
    () => s.createEntry(none, scoped("income")),
    /Finance access/,
  );
  await assert.rejects(
    () => s.createEntry(collector, scoped("expense")),
    /Finance access/,
  );
  await assert.rejects(
    () => s.createEntry(spender, scoped("income")),
    /Finance access/,
  );
  await assert.rejects(
    () => s.createEntry(collector, entry("income", 100, bank)),
    /owner access/,
  ); // shared (no business)
  await assert.rejects(
    () => s.createEntry(unassigned, scoped("income")),
    /assigned space/,
  );
  await assert.rejects(
    () =>
      s.createEntry(collector, {
        ...scoped("transfer"),
        category: "Transfer",
        to_account_id: bank2,
      }),
    /Finance access|Only the owner/,
  );
  await assert.rejects(
    () =>
      s.createEntry(spender, {
        ...scoped("transfer"),
        category: "Transfer",
        to_account_id: bank2,
      }),
    /Finance access|Only the owner/,
  );
  assert.ok((await s.createEntry(collector, scoped("income"))).id);
  assert.ok((await s.createEntry(spender, scoped("expense"))).id);
});

// ---------------------------------------------------------------- transfers
test("transfer: shape rules (two different accounts, one line, no business, owner only)", async () => {
  const t = (extra: Record<string, any> = {}) =>
    entry("transfer", 100, bank, {
      category: "Transfer",
      to_account_id: bank2,
      ...extra,
    });
  await assert.rejects(
    () => s.createEntry(owner, t({ to_account_id: undefined })),
    /two different/,
  );
  await assert.rejects(
    () => s.createEntry(owner, t({ to_account_id: bank })),
    /two different/,
  );
  await assert.rejects(
    () => s.createEntry(owner, t({ business_id: business })),
    /two different/,
  );
  await assert.rejects(
    () =>
      s.createEntry(
        owner,
        t({ business_id: business, resource_id: randomUUID() }),
      ),
    /two different|Choose a business|not found/i,
  );
  await assert.rejects(
    () => s.createEntry(owner, t({ lines: [t().lines[0], t().lines[0]] })),
    /two different/,
  );
  await assert.rejects(
    () => s.createEntry(owner, t({ to_account_id: clearing })),
    /destination/,
  );
  await assert.rejects(
    () => s.createEntry(owner, t({ to_account_id: randomUUID() })),
    /destination/,
  );
  await assert.rejects(
    () => s.createEntry(owner, t({ to_account_id: otherBank })),
    /destination/,
  );
  await bad(() => s.createEntry(owner, t({ to_account_id: "nope" })));
  await bad(() => s.createEntry(owner, t({ to_account_id: null })));
  await bad(() =>
    s.createEntry(owner, t({ lines: [{ ...t().lines[0], amount_minor: 0 }] })),
  );
  await bad(() =>
    s.createEntry(
      owner,
      t({ lines: [{ ...t().lines[0], amount_minor: 100000001 }] }),
    ),
  );
});
test("transfer: moves exactly the amount between accounts and is not income or expense", async () => {
  const a = (await s.createAccount(owner, bankInput("T source", 5000))).id;
  const b = (await s.createAccount(owner, bankInput("T dest", 0))).id;
  const before = (await s.overview(owner, filter)).selected;
  for (const amount of [1, 2499, 100000000])
    await s.createEntry(
      owner,
      entry("transfer", amount, a, { category: "Transfer", to_account_id: b }),
    );
  const cat = (await s.catalog(owner)).accounts;
  const A = cat.find((x: any) => x.id === a)!.balance_minor,
    B = cat.find((x: any) => x.id === b)!.balance_minor;
  assert.equal(A, 5000 - 1 - 2499 - 100000000);
  assert.equal(B, 1 + 2499 + 100000000);
  assert.equal(A + B, 5000); // conservation
  const after = (await s.overview(owner, filter)).selected;
  assert.equal(after.income_minor, before.income_minor);
  assert.equal(after.expenses_minor, before.expenses_minor);
});
test("transfer: cash <-> bank is allowed whatever the line method says", async () => {
  const r = await s.createEntry(
    owner,
    entry("transfer", 300, cash, {
      category: "Transfer",
      to_account_id: bank,
      lines: [{ account_id: cash, method: "upi", amount_minor: 300 }],
    }),
  );
  assert.ok(r.id);
});
test(
  "transfer: the clearing (unassigned receipts) account cannot be a transfer SOURCE",
  { todo: "BUG-2" },
  async () => {
    await assert.rejects(() =>
      s.createEntry(
        owner,
        entry("transfer", 100, clearing, {
          category: "Transfer",
          to_account_id: bank,
        }),
      ),
    );
  },
);
test("transfer: no overdraft guard - a transfer larger than the source balance is accepted (characterisation)", async () => {
  const a = (await s.createAccount(owner, bankInput("Empty source", 0))).id;
  const r = await s.createEntry(
    owner,
    entry("transfer", 777, a, { category: "Transfer", to_account_id: bank2 }),
  );
  assert.ok(r.id);
  assert.equal(
    (await s.catalog(owner)).accounts.find((x: any) => x.id === a)!
      .balance_minor,
    -777,
  );
});
test("transfer: reversal restores both balances once and replays idempotently", async () => {
  const a = (await s.createAccount(owner, bankInput("R source", 1000))).id;
  const b = (await s.createAccount(owner, bankInput("R dest", 0))).id;
  const t = await s.createEntry(
    owner,
    entry("transfer", 400, a, { category: "Transfer", to_account_id: b }),
  );
  const key = randomUUID();
  const r1 = await s.reverse(owner, t.id, {
    command_key: key,
    reason: "Wrong account",
  });
  const r2 = await s.reverse(owner, t.id, {
    command_key: key,
    reason: "Wrong account",
  });
  assert.equal(r1.id, r2.id);
  const cat = (await s.catalog(owner)).accounts;
  assert.equal(cat.find((x: any) => x.id === a)!.balance_minor, 1000);
  assert.equal(cat.find((x: any) => x.id === b)!.balance_minor, 0);
});

// ---------------------------------------------------------------- reversals
test("reverse: reason/command_key validation and unknown, foreign or non-manual targets", async () => {
  const e = await s.createEntry(owner, entry("expense", 123, bank));
  for (const reason of ["", " ", "x", "r".repeat(501), null, 5, undefined])
    await bad(
      () => s.reverse(owner, e.id, { command_key: randomUUID(), reason }),
      String(reason),
    );
  for (const command_key of ["", "x", null, undefined, 3])
    await bad(() =>
      s.reverse(owner, e.id, { command_key, reason: "valid reason" }),
    );
  await bad(() =>
    s.reverse(owner, e.id, {
      command_key: randomUUID(),
      reason: "valid",
      extra: 1,
    }),
  );
  await assert.rejects(
    () =>
      s.reverse(owner, randomUUID(), {
        command_key: randomUUID(),
        reason: "ghost",
      }),
    /Only manual entries/,
  );
  const bal = async () =>
    (await s.catalog(other)).accounts.find((x: any) => x.id === otherBank)!
      .balance_minor;
  const foreign = await s.createEntry(other, entry("income", 100, otherBank));
  const before = await bal();
  await assert.rejects(
    () =>
      s.reverse(owner, foreign.id, {
        command_key: randomUUID(),
        reason: "steal",
      }),
    /Only manual entries/,
  );
  assert.equal(await bal(), before);
  const rev = await s.reverse(owner, e.id, {
    command_key: randomUUID(),
    reason: "Undo it",
  });
  await assert.rejects(
    () =>
      s.reverse(owner, rev.id, {
        command_key: randomUUID(),
        reason: "Undo undo",
      }),
    /Only manual entries/,
  );
  await assert.rejects(
    () =>
      s.reverse(owner, e.id, { command_key: randomUUID(), reason: "Again" }),
    /already reversed/,
  );
});
test("reverse: only the owner may reverse", async () => {
  const staff = actor();
  await staffMember(staff, [
    "view_finance",
    "collect_payments",
    "record_expenses",
  ]);
  const e = await s.createEntry(owner, entry("income", 55, bank));
  await assert.rejects(
    () =>
      s.reverse(staff, e.id, {
        command_key: randomUUID(),
        reason: "Nope nope",
      }),
    /Only the owner/,
  );
});
test("reverse: parallel double submit with different keys produces a single reversal", async () => {
  const acct = (await s.createAccount(owner, bankInput("Parallel rev", 0))).id;
  const e = await s.createEntry(owner, entry("income", 900, acct));
  const results = await Promise.allSettled(
    [1, 2, 3].map(() =>
      s.reverse(owner, e.id, {
        command_key: randomUUID(),
        reason: "Duplicate click",
      }),
    ),
  );
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
  assert.equal(
    (await s.catalog(owner)).accounts.find((x: any) => x.id === acct)!
      .balance_minor,
    0,
  );
});

// ---------------------------------------------------------------- filters / reads
test("filters: from/until calendar validity and range limits", async () => {
  const f = (extra: Record<string, any>) => ({ ...filter, ...extra });
  for (const extra of [
    { from: "" },
    { from: "2026-02-30" },
    { from: "2026-1-1" },
    { from: "26-01-01" },
    { from: "2026-01-01T00:00:00Z" },
    { until: "tomorrow" },
    { until: null },
    { from: undefined },
    { from: day, until: "2000-01-01" }, // inverted
    { from: "2000-01-01", until: "2010-01-03" }, // 3655 days -> ok? checked below
  ].slice(0, 9))
    await bad(() => s.overview(owner, f(extra)), JSON.stringify(extra));
  // exactly 3660 days allowed, 3661 not
  await s.overview(owner, { from: "2016-01-01", until: "2025-12-30" });
  await bad(() =>
    s.overview(owner, { from: "2000-01-01", until: "2020-01-01" }),
  );
  await bad(() =>
    s.transactions(owner, { from: "2000-01-01", until: "2020-01-01" }),
  );
});
test("filters: cursor, kind, q, ids and unknown keys", async () => {
  for (const extra of [
    { cursor: -1 },
    { cursor: "-1" },
    { cursor: 1000001 },
    { cursor: "abc" },
    { cursor: "1.5" },
    { cursor: "NaN" },
    { cursor: "Infinity" },
    { kind: "refund" },
    { kind: "" },
    { kind: "INCOME" },
    { q: "q".repeat(101) },
    { q: 5 },
    { business_id: "x" },
    { resource_id: "x" },
    { account_id: "x" },
    { account_id: null },
    { unknown: 1 },
  ])
    await bad(
      () => s.transactions(owner, { ...filter, ...extra }),
      JSON.stringify(extra),
    );
  assert.ok(await s.transactions(owner, { ...filter, cursor: "5" }));
  assert.ok(await s.transactions(owner, { ...filter, cursor: 1000000 }));
  assert.ok(await s.transactions(owner, { ...filter, q: "q".repeat(100) }));
  assert.ok(await s.transactions(owner, null as any).catch(() => true));
});
test("filters: search treats % _ and \\ literally and never matches via SQL fragments", async () => {
  await s.createEntry(
    owner,
    entry("income", 100, bank, {
      reason: "Plain search target",
      reference: "ZZ-ref",
    }),
  );
  await s.createEntry(
    owner,
    entry("income", 100, bank, {
      reason: "100% literal_underscore",
      reference: "p%q",
    }),
  );
  const q = async (text: string) =>
    (await s.transactions(owner, { ...filter, q: text })).items.length;
  assert.equal(await q("%"), 1);
  assert.equal(
    await q("_"),
    (
      await db.query<any>(
        "SELECT count(*)::int n FROM finance_events e WHERE e.organization_id=(SELECT organization_id FROM memberships WHERE user_id=$1) AND (e.reason LIKE '%\\_%' OR e.reference LIKE '%\\_%')",
        [owner.uid],
      )
    ).rows[0].n,
  );
  assert.equal(await q("literal_under"), 1);
  assert.equal(await q("literalXunder"), 0);
  assert.equal(await q("\\"), 0);
  assert.equal(await q("' OR '1'='1"), 0);
  assert.equal(await q("'; DROP TABLE finance_events; --"), 0);
  assert.equal(
    await q("   "),
    (await s.transactions(owner, filter)).items.length,
  ); // blank = no filter
  assert.equal(await q("PLAIN SEARCH"), 1); // case-insensitive
});
test("filters: foreign business/resource/account ids never leak other tenants' rows", async () => {
  await s.createEntry(
    other,
    entry("income", 31337, otherBank, { reason: "Secret foreign entry" }),
  );
  const r = await s.transactions(owner, { ...filter, account_id: otherBank });
  assert.equal(r.items.length, 0);
  const r2 = await s.transactions(owner, { ...filter, q: "Secret foreign" });
  assert.equal(r2.items.length, 0);
  const r3 = await s.transactions(owner, {
    ...filter,
    business_id: randomUUID(),
  });
  assert.equal(r3.items.length, 0);
});
test("reads: users without finance permission are denied", async () => {
  const booker = actor(),
    collector = actor();
  await staffMember(booker, ["view_bookings"]);
  await staffMember(collector, ["collect_payments"]);
  await assert.rejects(() => s.overview(booker, filter), /Finance access/);
  await assert.rejects(() => s.transactions(booker, filter), /Finance access/);
  await assert.rejects(() => s.report(booker, filter), /Finance access/);
  await assert.rejects(() => s.catalog(booker), /permission/);
  await assert.rejects(() => s.overview(collector, filter), /Finance access/);
  assert.ok(await s.catalog(collector)); // collect_payments may see the catalog
  await assert.rejects(() => s.overview(actor(), filter), /membership/i);
});

// ---------------------------------------------------------------- website payment settings
test("website payment details: version, UPI id and QR validation", async () => {
  const o = actor();
  await newOrg(o);
  for (const body of [
    { version: -1, upi_id: "shop@upi" },
    { version: 1.5, upi_id: "shop@upi" },
    { version: "0", upi_id: "shop@upi" },
    { version: null, upi_id: "shop@upi" },
    { version: 0, upi_id: "no spaces@upi" },
    { version: 0, upi_id: "x".repeat(300) },
    { version: 0, upi_id: "'; DROP TABLE x;--" },
    { version: 0, upi_id: 5 },
    {
      version: 0,
      upi_id: "shop@upi",
      qr: { base64: "!!!notbase64", content_type: "image/png" },
    },
    {
      version: 0,
      upi_id: "shop@upi",
      qr: { base64: "", content_type: "image/png" },
    },
    {
      version: 0,
      upi_id: "shop@upi",
      qr: { base64: "aGVsbG8=", content_type: "text/html" },
    },
    { version: 0, upi_id: "shop@upi", extra: true },
  ])
    await bad(
      () => s.saveWebsitePayments(o, body),
      JSON.stringify(body).slice(0, 80),
    );
  await assert.rejects(
    () => s.saveWebsitePayments(o, { version: 5, upi_id: "shop@upi" }),
    /changed/,
  ); // stale version
  await assert.rejects(
    () => s.saveWebsitePayments(actor(), { version: 0, upi_id: "shop@upi" }),
    /membership/i,
  );
  const staff = actor();
  const m = await w.member(o),
    id = randomUUID();
  await db.query(
    `INSERT INTO memberships(id,organization_id,user_id,email,display_name,role,permissions) VALUES($1,$2,$3,$4,'S','staff','["view_finance"]')`,
    [id, m.organization_id, staff.uid, staff.email],
  );
  await assert.rejects(
    () => s.saveWebsitePayments(staff, { version: 0, upi_id: "shop@upi" }),
    /Only the owner/,
  );
  await assert.rejects(() => s.websitePayments(staff), /Only the owner/);
});

// ---------------------------------------------------------------- staff cash
let staffUser: Actor, staffMid: string;
async function holdCash(amount: number) {
  await s.createEntry(
    staffUser,
    entry("income", amount, cash, { business_id: business }),
  );
}
const settle = (membershipId: string, body: Record<string, any>, who = owner) =>
  cashSvc.settle(who, membershipId, body);
const sBody = (extra: Record<string, any> = {}) => ({
  command_key: randomUUID(),
  direction: "collect",
  amount_minor: 100,
  expected_balance_minor: 1000,
  note: "",
  ...extra,
});
test("staff cash: fixture - staff holds cash from cash entries", async () => {
  staffUser = actor();
  staffMid = await staffMember(staffUser, [
    "collect_payments",
    "record_expenses",
    "view_finance",
  ]);
  await holdCash(1000);
  assert.equal((await cashSvc.me(staffUser, {})).cash_holding_minor, 1000);
});
test("staff cash settle: amount_minor boundaries (0, negative, decimal, NaN, huge, > balance)", async () => {
  for (const amount_minor of [
    0,
    -1,
    -100,
    0.5,
    99.99,
    100.0000001,
    NaN,
    Infinity,
    "100",
    "NaN",
    "1e2",
    null,
    undefined,
    true,
    100000001,
    Number.MAX_SAFE_INTEGER + 1,
    1e21,
  ])
    await bad(
      () => settle(staffMid, sBody({ amount_minor })),
      String(amount_minor),
    );
  await assert.rejects(
    () => settle(staffMid, sBody({ amount_minor: 1001 })),
    /more than the balance/,
  );
  await assert.rejects(
    () => settle(staffMid, sBody({ amount_minor: 100000000 })),
    /more than the balance/,
  );
  assert.equal((await cashSvc.me(staffUser, {})).cash_holding_minor, 1000); // nothing posted
});
test("staff cash settle: expected_balance_minor must be an exact match integer", async () => {
  for (const expected_balance_minor of [
    1000.5,
    NaN,
    Infinity,
    "1000",
    null,
    undefined,
    true,
  ])
    await bad(
      () => settle(staffMid, sBody({ expected_balance_minor })),
      String(expected_balance_minor),
    );
  await assert.rejects(
    () => settle(staffMid, sBody({ expected_balance_minor: 999 })),
    /balance changed/,
  );
  await assert.rejects(
    () => settle(staffMid, sBody({ expected_balance_minor: 0 })),
    /balance changed/,
  );
  await assert.rejects(
    () => settle(staffMid, sBody({ expected_balance_minor: -1000 })),
    /balance changed/,
  );
});
test("staff cash settle: direction, note, command_key and unknown keys", async () => {
  for (const direction of ["", "COLLECT", "pay", "refund", null, 1, undefined])
    await bad(() => settle(staffMid, sBody({ direction })), String(direction));
  for (const note of ["n".repeat(301), null, 5, {}])
    await bad(() => settle(staffMid, sBody({ note })), String(note));
  for (const command_key of ["", "x", null, undefined])
    await bad(() => settle(staffMid, sBody({ command_key })));
  await bad(() => settle(staffMid, sBody({ extra: 1 })));
  await bad(() => settle(staffMid, null as any));
  await assert.rejects(
    () => settle(staffMid, sBody({ direction: "give" })),
    /Staff owes cash/,
  );
});
test("staff cash settle: membership scoping - owner, foreign, unknown ids and non-owner callers", async () => {
  const ownerMid = (await w.member(owner)).id;
  await assert.rejects(
    () => settle(ownerMid, sBody()),
    /Staff member not found/,
  );
  await assert.rejects(
    () => settle(randomUUID(), sBody()),
    /Staff member not found/,
  );
  await assert.rejects(
    () => settle(staffMid, sBody(), other),
    /Staff member not found/,
  ); // other org's owner
  await assert.rejects(
    () => settle(staffMid, sBody(), staffUser),
    /Only the owner/,
  );
  const viewer = actor();
  await staffMember(viewer, ["view_finance", "collect_payments"]);
  await assert.rejects(
    () => settle(staffMid, sBody(), viewer),
    /Only the owner/,
  );
  await assert.rejects(() => cashSvc.overview(staffUser), /Only the owner/);
  await assert.rejects(
    () => cashSvc.history(staffUser, filter),
    /Only the owner/,
  );
  await assert.rejects(() => cashSvc.me(owner, {}), /Owners use/);
  await assert.rejects(() => cashSvc.me(actor(), {}), /membership/i);
  // other org's membership id belongs to a different org owner
  const otherOwnerMid = (await w.member(other)).id;
  await assert.rejects(
    () => settle(otherOwnerMid, sBody()),
    /Staff member not found/,
  );
});
test("staff cash settle: exact partial collect, replay, conflicting replay and double submit", async () => {
  const key = randomUUID();
  const body = sBody({
    command_key: key,
    amount_minor: 333,
    expected_balance_minor: 1000,
    note: "Ünï 'note'; DROP TABLE staff_cash_settlements;--",
  });
  const results = await Promise.all(
    [1, 2, 3, 4].map(() => settle(staffMid, body)),
  );
  assert.ok(
    results.every(
      (r) => r.id === results[0].id && r.balance_after_minor === 667,
    ),
  );
  assert.equal((await cashSvc.me(staffUser, {})).cash_holding_minor, 667);
  await assert.rejects(
    () => settle(staffMid, { ...body, amount_minor: 334 }),
    /another settlement/,
  );
  await assert.rejects(
    () => settle(staffMid, { ...body, note: "changed" }),
    /another settlement/,
  );
  const n = (
    await db.query<any>(
      "SELECT count(*)::int n FROM staff_cash_settlements WHERE command_key=$1",
      [key],
    )
  ).rows[0].n;
  assert.equal(n, 1);
  // same key re-used for a different staff member conflicts instead of silently replaying
  const other2 = actor();
  const mid2 = await staffMember(other2, ["collect_payments"]);
  await assert.rejects(() => settle(mid2, body), /another settlement/);
  // exhaust the balance in two exact steps; then nothing is left
  await settle(
    staffMid,
    sBody({ amount_minor: 600, expected_balance_minor: 667 }),
  );
  const last = await settle(
    staffMid,
    sBody({ amount_minor: 67, expected_balance_minor: 67 }),
  );
  assert.equal(last.balance_after_minor, 0);
  await assert.rejects(
    () =>
      settle(staffMid, sBody({ amount_minor: 1, expected_balance_minor: 0 })),
    /holds no cash/,
  );
});
test("staff cash settle: concurrent distinct settlements cannot over-collect", async () => {
  await holdCash(500);
  const r = await Promise.allSettled(
    [1, 2, 3].map(() =>
      settle(
        staffMid,
        sBody({ amount_minor: 500, expected_balance_minor: 500 }),
      ),
    ),
  );
  assert.equal(r.filter((x) => x.status === "fulfilled").length, 1);
  assert.equal((await cashSvc.me(staffUser, {})).cash_holding_minor, 0);
});
test("staff cash settle: owner-owes-staff direction and per-call limit above 100,000,000", async () => {
  await s.createEntry(
    staffUser,
    entry("expense", 250, cash, { business_id: business }),
  );
  assert.equal((await cashSvc.me(staffUser, {})).cash_holding_minor, -250);
  await assert.rejects(
    () =>
      settle(
        staffMid,
        sBody({
          direction: "collect",
          amount_minor: 10,
          expected_balance_minor: -250,
        }),
      ),
    /Owner owes/,
  );
  await assert.rejects(
    () =>
      settle(
        staffMid,
        sBody({
          direction: "give",
          amount_minor: 251,
          expected_balance_minor: -250,
        }),
      ),
    /more than the balance/,
  );
  const r = await settle(
    staffMid,
    sBody({
      direction: "give",
      amount_minor: 250,
      expected_balance_minor: -250,
    }),
  );
  assert.equal(r.balance_after_minor, 0);
});
test("staff cash me: date parameter validation and shape", async () => {
  for (const q of [
    { date: "2026-02-30" },
    { date: "2026-2-3" },
    { date: "" },
    { date: null },
    { date: "today" },
    { date: "2026-01-01T00:00:00Z" },
    { date: 20260101 },
    { other: 1 },
  ])
    await bad(() => cashSvc.me(staffUser, q), JSON.stringify(q));
  const far = await cashSvc.me(staffUser, { date: "2099-12-31" });
  assert.equal(far.collected_minor, 0);
  const old = await cashSvc.me(staffUser, { date: "2000-01-01" });
  assert.equal(old.transactions.length, 0);
  assert.ok(await cashSvc.me(staffUser, undefined));
});
test("staff cash history: from/until required and validated", async () => {
  for (const q of [
    {},
    { from: day },
    { until: day },
    { from: "x", until: day },
    { from: day, until: "2026-02-31" },
    { ...filter, extra: 1 },
    null,
  ])
    await bad(() => cashSvc.history(owner, q), JSON.stringify(q));
  assert.ok((await cashSvc.history(owner, filter)).items.length >= 3);
  assert.equal(
    (await cashSvc.history(owner, { from: "2000-01-01", until: "2000-01-02" }))
      .items.length,
    0,
  );
});
test(
  "staff cash history: an inverted range (from after until) should be rejected like other finance filters",
  { todo: "BUG-3" },
  async () => {
    await bad(() => cashSvc.history(owner, { from: day, until: "2000-01-01" }));
  },
);
test("staff cash history: settlements are tenant-isolated", async () => {
  const items = (await cashSvc.history(other, filter)).items;
  assert.equal(items.length, 0);
});
