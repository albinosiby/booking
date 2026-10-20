import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { writeFileSync } from "node:fs";
import ExcelJS from "exceljs";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { AccountsService } from "../src/accounts/accounts.service";
import { BookingService } from "../src/bookings/booking.service";
import { CourtService } from "../src/court/court.service";
import { renderReport } from "../src/accounts/accounts.report";
import { Actor } from "../src/common/auth.guard";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  w = new WorkspaceService(db),
  s = new AccountsService(db, w),
  bookings = new BookingService(db, w);
const actor = (): Actor => ({
  uid: randomUUID(),
  email: `${randomUUID()}@example.com`,
  name: "Finance owner",
});
const now = new Date().toISOString(),
  day = now.slice(0, 10),
  filter = { from: "2020-01-01", until: day };
let owner: Actor,
  other: Actor,
  business: string,
  space: string,
  spaceB: string,
  cash: string,
  bank: string,
  bankB: string,
  bookingId: string;
const bankInput = (name: string, opening = 0) => ({
  command_key: randomUUID(),
  name,
  bank_name: "QA Bank",
  last_four: "1234",
  account_number: "001234561234",
  opening_minor: opening,
  opening_at: "2000-01-01T00:00:00Z",
  is_primary: false,
});
const entry = (kind = "income", amount = 10000, account = bank) => ({
  command_key: randomUUID(),
  kind,
  business_id: business,
  resource_id: space,
  category: kind === "expense" ? "Maintenance" : "Equipment rental",
  reason: "Finance verification",
  reference: "QA",
  occurred_at: now,
  lines: [
    {
      account_id: account,
      method: account === cash ? "cash" : "upi",
      amount_minor: amount,
    },
  ],
});
before(async () => {
  await db.onModuleInit();
  owner = actor();
  other = actor();
  for (const a of [owner, other])
    await w.createOrganization(a, {
      name: "Finance QA",
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
  const ws = await w.workspace(owner),
    b = await w.createBusiness(owner, {
      name: "Badminton",
      type: "badminton",
      location_id: ws.locations[0].id,
    });
  business = b.id;
  const hours = {
    days: [1, 2, 3, 4, 5, 6, 7],
    opens_at: "06:00",
    closes_at: "00:00",
    date_from: null,
    date_until: null,
  };
  const courts = [1, 2].map((n) => ({
    id: randomUUID(),
    name: `Court ${n}`,
    enabled: true,
    environment: "indoor",
    surface: "",
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
        rates: [{ duration_minutes: 60, price_minor: 65000 }],
      },
    ],
  }));
  await new CourtService(db, w).configure(owner, business, {
    version: 1,
    configuration: { kind: "court_v1", schema_version: 1, courts },
  });
  await w.activate(owner, business);
  cash = (await s.catalog(owner)).accounts.find((a) => a.kind === "cash")!.id;
  bank = (await s.createAccount(owner, bankInput("Primary HDFC", 100000))).id;
  bankB = (await s.createAccount(owner, bankInput("Secondary SBI"))).id;
  const bc = await bookings.catalog(owner);
  space = bc.businesses[0].resources[0].id;
  spaceB = bc.businesses[0].resources[1].id;
});
after(() => db.onModuleDestroy());
test("full bank numbers retain leading zeros, derive their suffix and reject invalid values", async () => {
  const input = {
    ...bankInput("Full number QA"),
    account_number: "001234567890",
    last_four: "9999",
  };
  const id = (await s.createAccount(owner, input)).id;
  const stored = (
    await db.query(
      "SELECT account_number,last_four FROM money_accounts WHERE id=$1",
      [id],
    )
  ).rows[0];
  assert.equal(stored.account_number, "001234567890");
  assert.equal(stored.last_four, "7890");
  const viewed = (await s.catalog(owner)).accounts.find((a) => a.id === id);
  assert.equal(viewed?.account_number, "001234567890");
  assert.equal((await s.createAccount(owner, input)).id, id);
  for (const value of ["", "12345", "12345A7890", "1".repeat(35)]) {
    await assert.rejects(() =>
      s.createAccount(owner, {
        ...bankInput("Invalid number"),
        account_number: value,
      }),
    );
  }
  await assert.rejects(() =>
    s.createAccount(owner, {
      ...bankInput("Numeric JSON"),
      account_number: 1234567890,
    }),
  );
  await assert.rejects(() =>
    db.query("UPDATE money_accounts SET account_number='12' WHERE id=$1", [id]),
  );
});
test("first bank becomes primary; tenant boundaries and primary switching", async () => {
  assert.equal(
    (await s.catalog(owner)).accounts.find((a) => a.id === bank)?.is_primary,
    true,
  );
  await assert.rejects(() =>
    s.updateAccount(other, bank, { is_primary: true }),
  );
  await s.updateAccount(owner, bankB, { is_primary: true });
  assert.equal(
    (await s.catalog(owner)).accounts.filter((a) => a.is_primary).length,
    1,
  );
  await s.updateAccount(owner, bank, { is_primary: true });
});
test("space mapping overrides business default, and split payment is posted exactly once", async () => {
  await s.route(owner, {
    business_id: business,
    resource_id: null,
    method: "upi",
    account_id: bank,
  });
  await s.route(owner, {
    business_id: business,
    resource_id: space,
    method: "upi",
    account_id: bankB,
  });
  const selection = {
    business_id: business,
    resource_id: space,
    option_id: (await bookings.catalog(owner)).businesses[0].resources[0]
      .options[0].id,
    date: "2030-06-04",
    time: "09:00",
    duration_minutes: 60,
    people: 1,
  };
  const q = await bookings.quote(owner, {
      selection,
      exclude_booking_id: null,
    }),
    req = {
      command_key: randomUUID(),
      selection,
      quote_token: q.quote_token,
      customer: {
        id: null,
        name: "Split customer",
        phone: "9876543210",
        email: null,
      },
      notes: "",
      payments: [
        {
          method: "upi",
          amount_minor: 50000,
          reference: "UPI example",
          received_at: now,
        },
        {
          method: "cash",
          amount_minor: 15000,
          reference: "Cash example",
          received_at: now,
        },
      ],
    };
  bookingId = (await bookings.create(owner, req)).id;
  await bookings.create(owner, req);
  const payments = (await s.transactions(owner, filter, true)).items;
  assert.equal(payments.length, 2);
  assert.equal(
    payments.find((p) => p.lines[0].method === "upi")?.lines[0].account_id,
    bankB,
  );
  const o = await s.overview(owner, filter);
  assert.equal(o.selected.collections_minor, 65000);
  assert.equal(o.selected.methods.upi, 50000);
  assert.equal(o.selected.methods.cash, 15000);
  await s.route(owner, {
    business_id: business,
    resource_id: space,
    method: "upi",
    account_id: bank,
  });
  assert.equal(
    (await s.overview(owner, filter)).accounts.find((a) => a.id === bankB)
      ?.balance_minor,
    50000,
  );
});
test("split expenses and extra income are idempotent", async () => {
  const i = entry();
  await s.createEntry(owner, i);
  await s.createEntry(owner, i);
  await assert.rejects(() =>
    s.createEntry(owner, { ...i, reason: "Changed payload" }),
  );
  await s.createEntry(owner, {
    ...entry("expense", 2000, cash),
    lines: [
      { account_id: cash, method: "cash", amount_minor: 2000 },
      { account_id: bank, method: "upi", amount_minor: 3000 },
    ],
  });
  const o = await s.overview(owner, filter);
  assert.equal(o.selected.extra_income_minor, 10000);
  assert.equal(o.selected.expenses_minor, 5000);
  assert.equal(o.selected.net_minor, 70000);
});
test("cash deposit and withdrawal conserve balances and do not count as income", async () => {
  const before = await s.overview(owner, filter);
  const t = {
    ...entry("transfer", 5000, cash),
    business_id: null,
    resource_id: null,
    to_account_id: bank,
  };
  await s.createEntry(owner, t);
  await s.createEntry(owner, t);
  await s.createEntry(owner, {
    ...entry("transfer", 1000, bank),
    business_id: null,
    resource_id: null,
    to_account_id: cash,
  });
  const after = await s.overview(owner, filter);
  assert.equal(after.selected.income_minor, before.selected.income_minor);
  assert.equal(after.selected.expenses_minor, before.selected.expenses_minor);
  assert.equal(
    after.accounts.reduce((n, a) => n + a.balance_minor, 0),
    before.accounts.reduce((n, a) => n + a.balance_minor, 0),
  );
  assert.equal(
    after.accounts.find((a) => a.id === cash)?.balance_minor,
    before.accounts.find((a) => a.id === cash)!.balance_minor - 4000,
  );
  await assert.rejects(() =>
    s.createEntry(owner, {
      ...t,
      command_key: randomUUID(),
      to_account_id: cash,
    }),
  );
});
test("invalid accounts, cross-tenant accounts and spaces reject without partial writes", async () => {
  const external = (await s.catalog(other)).accounts.find(
      (a) => a.kind === "cash",
    )!.id,
    before = (await s.transactions(owner, filter, true)).items.length;
  await assert.rejects(() =>
    s.createEntry(owner, {
      ...entry(),
      lines: [{ account_id: external, method: "cash", amount_minor: 1000 }],
    }),
  );
  await assert.rejects(() =>
    s.route(owner, {
      business_id: business,
      resource_id: randomUUID(),
      method: "upi",
      account_id: bank,
    }),
  );
  assert.equal(
    (await s.transactions(owner, filter, true)).items.length,
    before,
  );
});
test("reversals preserve history, undo expenses once, archive guards protect routing", async () => {
  const e = await s.createEntry(owner, entry("expense", 7000, bank)),
    v = { command_key: randomUUID(), reason: "Duplicate expense correction" };
  await s.reverse(owner, e.id, v);
  await s.reverse(owner, e.id, v);
  await assert.rejects(() =>
    s.reverse(owner, e.id, { ...v, command_key: randomUUID() }),
  );
  assert.equal((await s.overview(owner, filter)).selected.expenses_minor, 5000);
  await assert.rejects(() => s.updateAccount(owner, bank, { archive: true }));
});
test("reports contain 650 tariff, 500 UPI and 150 cash, and valid PDF/Excel bytes", async () => {
  const d = await s.report(owner, filter),
    b = d.bookings.find((b: any) => b.id === bookingId);
  assert.equal(b.total_minor, 65000);
  assert.equal(
    b.payments.find((p: any) => p.method === "upi").amount_minor,
    50000,
  );
  assert.equal(
    b.payments.find((p: any) => p.method === "cash").amount_minor,
    15000,
  );
  const bytes = await renderReport(d, "xlsx", "monthly"),
    wb = new ExcelJS.Workbook();
  await wb.xlsx.load(bytes as any);
  assert.equal(wb.getWorksheet("Bookings")!.getRow(2).getCell(7).value, 650);
  assert.equal(wb.getWorksheet("Bookings")!.getRow(2).getCell(12).value, 500);
  const discounted = {
    ...d,
    bookings: [
      {
        ...b,
        total_minor: 60000,
        price_snapshot: {
          ...b.price_snapshot,
          subtotal_minor: 65000,
          discount_minor: 5000,
        },
      },
    ],
  };
  const dwb = new ExcelJS.Workbook();
  await dwb.xlsx.load(
    (await renderReport(discounted, "xlsx", "monthly")) as any,
  );
  assert.equal(dwb.getWorksheet("Bookings")!.getRow(2).getCell(7).value, 650);
  assert.equal(dwb.getWorksheet("Bookings")!.getRow(2).getCell(8).value, 50);
  assert.equal(dwb.getWorksheet("Bookings")!.getRow(2).getCell(9).value, 600);
  const pdf = await renderReport(d, "pdf", "monthly");
  assert.equal(pdf.subarray(0, 4).toString(), "%PDF");
  writeFileSync("/private/tmp/booking-accounts-qa.pdf", pdf);
  writeFileSync("/private/tmp/booking-accounts-qa.xlsx", bytes);
});
test("staff finance is restricted to assigned spaces and does not reveal bank balances", async () => {
  const staff = actor(),
    m = await w.member(owner),
    mid = randomUUID();
  await db.query(
    `INSERT INTO memberships(id,organization_id,user_id,email,display_name,role,permissions) VALUES($1,$2,$3,$4,'Finance staff','staff',$5)`,
    [
      mid,
      m.organization_id,
      staff.uid,
      staff.email,
      JSON.stringify(["view_finance", "record_expenses", "collect_payments"]),
    ],
  );
  await db.query(
    "INSERT INTO staff_assignments(membership_id,organization_id,business_id,resource_ids) VALUES($1,$2,$3,$4)",
    [mid, m.organization_id, business, JSON.stringify([spaceB])],
  );
  assert.equal((await s.overview(staff, filter)).selected.income_minor, 0);
  assert.equal((await s.overview(staff, filter)).accounts.length, 0);
  assert.equal((await s.report(staff, filter)).bookings.length, 0);
  assert.ok(
    (await s.catalog(staff)).accounts.every(
      (a) => a.balance_minor === null && a.account_number === null,
    ),
  );
  await assert.rejects(() => s.createEntry(staff, entry()));
  await assert.rejects(() =>
    s.createEntry(staff, { ...entry(), business_id: null, resource_id: null }),
  );
  await assert.rejects(() => s.createAccount(staff, bankInput("Forbidden")));
  await s.createEntry(staff, {
    ...entry("expense", 1000, bank),
    resource_id: spaceB,
  });
  assert.equal((await s.overview(staff, filter)).selected.expenses_minor, 1000);
});

test("opening balances are excluded before their date; cash opening is set once and does not create income", async () => {
  const date = new Date().toISOString(),
    newBank = await s.createAccount(owner, {
      ...bankInput("New bank", 25000),
      opening_at: date,
    });
  const old = await s.report(owner, {
    from: "2024-01-01",
    until: "2024-12-31",
  });
  assert.equal(
    old.account_statement.find((a) => a.id === newBank.id)?.closing_minor,
    0,
  );
  const before = await s.overview(owner, filter),
    v = {
      command_key: randomUUID(),
      opening_minor: 50000,
      opening_at: "2000-01-01T00:00:00Z",
    };
  await s.cashOpening(owner, v);
  await s.cashOpening(owner, v);
  await assert.rejects(() =>
    s.cashOpening(owner, {
      ...v,
      command_key: randomUUID(),
      opening_minor: 60000,
    }),
  );
  const after = await s.overview(owner, filter);
  assert.equal(after.selected.income_minor, before.selected.income_minor);
  assert.equal(
    after.accounts.find((a) => a.id === cash)?.balance_minor,
    before.accounts.find((a) => a.id === cash)!.balance_minor + 50000,
  );
});
test("period comparisons align month-to-date and exports include all transaction pages", async () => {
  const o = await s.overview(owner, {
    from: "2026-10-01",
    until: "2026-10-15",
  });
  assert.equal(o.previous_from, "2026-09-01");
  assert.equal(o.previous_until, "2026-09-15");
  for (let i = 0; i < 103; i++)
    await s.createEntry(owner, {
      ...entry("income", 1, bank),
      resource_id: spaceB,
      reason: `Pagination income ${i}`,
    });
  const first = await s.transactions(owner, filter),
    second = await s.transactions(owner, {
      ...filter,
      cursor: first.next_cursor,
    });
  assert.equal(first.items.length, 100);
  assert.ok(second.items.length > 0);
  assert.ok(second.items.every((e) => !first.items.some((f) => f.id === e.id)));
  const report = await s.report(owner, filter);
  assert.equal(
    report.transactions.length,
    first.items.length + second.items.length,
  );
});

test("migration preserves historical split payments and keeps unknown digital destinations unassigned", async () => {
  const { PGlite } = await import("@electric-sql/pglite"),
    { readFileSync } = await import("node:fs");
  const legacy = new PGlite();
  await legacy.waitReady;
  try {
    await legacy.exec(readFileSync("migrations/001_workspace.sql", "utf8"));
    await legacy.exec(readFileSync("migrations/002_bookings.sql", "utf8"));
    const org = randomUUID(),
      location = randomUUID(),
      biz = randomUUID(),
      resource = randomUUID(),
      customer = randomUUID(),
      booking = randomUUID();
    await legacy.query(
      `INSERT INTO organizations(id,name,contact_phone,currency,created_by) VALUES($1,'Legacy','9876543210','INR','legacy')`,
      [org],
    );
    await legacy.query(
      `INSERT INTO locations(id,organization_id,name,address_line_1,city,country_code,postal_code,timezone) VALUES($1,$2,'Main','Road','Kochi','IN','682001','Asia/Kolkata')`,
      [location, org],
    );
    await legacy.query(
      `INSERT INTO businesses(id,organization_id,location_id,name,type) VALUES($1,$2,$3,'Court','badminton')`,
      [biz, org, location],
    );
    await legacy.query(
      `INSERT INTO resources(id,organization_id,business_id,name) VALUES($1,$2,$3,'Court A')`,
      [resource, org, biz],
    );
    await legacy.query(
      `INSERT INTO customers(id,organization_id,name,phone) VALUES($1,$2,'Customer','9876543210')`,
      [customer, org],
    );
    await legacy.query(
      `INSERT INTO bookings(id,organization_id,business_id,resource_id,customer_id,reference,starts_at,ends_at,total_minor,selection,price_snapshot,customer_snapshot,people,created_by) VALUES($1,$2,$3,$4,$5,'BK-OLD','2026-10-15T09:00Z','2026-10-15T10:00Z',65000,'{}','{}','{}',1,'legacy')`,
      [booking, org, biz, resource, customer],
    );
    for (const [method, amount] of [
      ["cash", 15000],
      ["upi", 50000],
    ])
      await legacy.query(
        `INSERT INTO booking_payments(id,organization_id,booking_id,kind,method,amount_minor,received_at,recorded_by) VALUES($1,$2,$3,'collection',$4,$5,'2026-10-15T09:00Z','legacy')`,
        [randomUUID(), org, booking, method, amount],
      );
    await legacy.exec(readFileSync("migrations/003_accounts.sql", "utf8"));
    const rows = (
      await legacy.query<any>(
        `SELECT a.system_key,l.amount_minor FROM finance_lines l JOIN money_accounts a ON a.id=l.account_id`,
      )
    ).rows;
    assert.equal(rows.find((r) => r.system_key === "cash").amount_minor, 15000);
    assert.equal(
      rows.find((r) => r.system_key === "unassigned").amount_minor,
      50000,
    );
    assert.equal(rows.length, 2);
  } finally {
    await legacy.close();
  }
});

test("empty-period PDF and Excel exports remain valid with no booking or transaction rows", async () => {
  const data = await s.report(owner, {
    from: "2024-01-01",
    until: "2024-12-31",
  });
  assert.equal(data.bookings.length, 0);
  assert.equal(data.transactions.length, 0);
  assert.equal(data.trend.length, 0);
  const pdf = await renderReport(data, "pdf", "yearly");
  assert.equal(pdf.subarray(0, 4).toString(), "%PDF");
  writeFileSync("/private/tmp/accounts-empty-period-check.pdf", pdf);
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load((await renderReport(data, "xlsx", "yearly")) as any);
  assert.equal(wb.getWorksheet("Bookings")!.rowCount, 1);
  assert.equal(wb.getWorksheet("Account movements")!.rowCount, 1);
});
