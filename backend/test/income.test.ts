import "reflect-metadata";
import { before, after, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import ExcelJS from "exceljs";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { AccountsService } from "../src/accounts/accounts.service";
import { IncomeService } from "../src/income/income.service";
import { renderIncomeReport } from "../src/income/income.report";
import { Actor } from "../src/common/auth.guard";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  workspace = new WorkspaceService(db),
  accounts = new AccountsService(db, workspace),
  income = new IncomeService(db, workspace, accounts);
const owner: Actor = {
    uid: randomUUID(),
    email: "income-owner@example.com",
    name: "Owner",
  },
  other: Actor = {
    uid: randomUUID(),
    email: "other-income@example.com",
    name: "Other",
  };
let org: string, sponsorship: string, events: string, cash: string;
let sponsorshipId: string;
const now = new Date().toISOString(),
  today = now.slice(0, 10),
  filter = { from: today, until: today };
async function ledger(kind: string, amount: number) {
  const id = randomUUID();
  await db.query(
    "INSERT INTO finance_events(id,organization_id,kind,reason,occurred_at,recorded_by) VALUES($1,$2,$3,'Seeded',$4,$5)",
    [id, org, kind, now, owner.uid],
  );
  await db.query(
    "INSERT INTO finance_lines(id,organization_id,event_id,account_id,method,amount_minor) VALUES($1,$2,$3,$4,'cash',$5)",
    [randomUUID(), org, id, cash, amount],
  );
}
const input = (category?: string, amount = 20000) => ({
  command_key: randomUUID(),
  kind: "income",
  ...(category ? { income_category_id: category } : {}),
  category: "Typed by older app",
  reason: "Tournament sponsor",
  reference: "SP-1",
  occurred_at: now,
  business_id: null,
  resource_id: null,
  lines: [{ account_id: cash, method: "cash", amount_minor: amount }],
});
before(async () => {
  await db.onModuleInit();
  for (const actor of [owner, other])
    await workspace.createOrganization(actor, {
      name: "Income QA",
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
  org = (await workspace.member(owner)).organization_id;
  const c = await income.catalog(owner);
  sponsorship = (c.categories as any[]).find(
    (c) => c.name === "Sponsorship",
  ).id;
  events = (c.categories as any[]).find((c) => c.name === "Events").id;
  const a = await accounts.catalog(owner);
  cash = (a.accounts as any[]).find((a) => a.kind === "cash").id;
  await ledger("booking_collection", 50000);
  await ledger("booking_refund", -10000);
  await ledger("admission_collection", 30000);
});
after(() => db.onModuleDestroy());
test("income is idempotent, requires a category and is grouped by source", async () => {
  const v = input(sponsorship);
  sponsorshipId = (await income.create(owner, v)).id;
  assert.equal((await income.create(owner, v)).id, sponsorshipId);
  await assert.rejects(() => income.create(owner, input()));
  await assert.rejects(() =>
    accounts.createEntry(owner, {
      ...input(),
      kind: "expense",
      income_category_id: sponsorship,
    }),
  );
  const s = await income.overview(owner, filter);
  assert.equal(s.total_minor, 100000);
  assert.equal(s.refunds_minor, 10000);
  assert.equal(s.net_minor, 90000);
  assert.equal(s.count, 4);
  const day = (s.days as any[]).find((d) => d.day === today);
  assert.ok(day);
  assert.equal(Number(day.total_minor), 100000);
  assert.equal(Number(day.refunds_minor), 10000);
  assert.equal(Number(day.income_count), 3);
  assert.equal(Number(day.refund_count), 1);
  assert.deepEqual(day.methods, [{ method: "cash", total_minor: 90000 }]);
  assert.equal(Number(day.purpose_count), 3);
  assert.deepEqual(
    (day.purposes as any[]).map((p) => [
      p.purpose,
      p.space,
      Number(p.total_minor),
    ]),
    [
      ["Bookings", "No space", 50000],
      ["Admissions", "No space", 30000],
      ["Tournament sponsor", "No space", 20000],
    ],
  );
  assert.deepEqual(s.methods, [{ method: "cash", total_minor: 90000 }]);
  assert.deepEqual(
    (s.sources as any[]).map((r) => [r.source_name, Number(r.total_minor)]),
    [
      ["Bookings", 50000],
      ["Admissions", 30000],
      ["Sponsorship", 20000],
    ],
  );
});
test("income total matches the Accounts overview", async () => {
  const a = await accounts.overview(owner, filter);
  assert.equal(
    (await income.overview(owner, filter)).total_minor,
    a.selected.income_minor,
  );
});
test("source filters split bookings, admissions and categories", async () => {
  const bookings = await income.overview(owner, {
    ...filter,
    source: "bookings",
  });
  assert.equal(bookings.total_minor, 50000);
  assert.equal(bookings.refunds_minor, 10000);
  assert.equal(
    (await income.overview(owner, { ...filter, source: "admissions" }))
      .total_minor,
    30000,
  );
  const page = await income.list(owner, { ...filter, source: sponsorship });
  assert.equal(page.items.length, 1);
  assert.equal(page.items[0].source_name, "Sponsorship");
  assert.equal(page.items[0].lines.length, 1);
  assert.equal(
    (await income.overview(owner, { ...filter, source: events })).total_minor,
    0,
  );
});
test("older apps sending a typed category get a managed category", async () => {
  await accounts.createEntry(owner, {
    ...input(undefined, 5000),
    category: "Parking",
  });
  const parking = ((await income.catalog(owner)).categories as any[]).find(
    (c) => c.name === "Parking",
  );
  assert.ok(parking);
  assert.equal(
    (await income.overview(owner, { ...filter, source: parking.id }))
      .total_minor,
    5000,
  );
});
test("archived categories reject new income and renames keep history", async () => {
  await income.category(
    owner,
    { name: "Sponsors", active: false },
    sponsorship,
  );
  await assert.rejects(() => income.create(owner, input(sponsorship)));
  assert.equal(
    (await income.list(owner, { ...filter, source: sponsorship })).items[0]
      .source_name,
    "Sponsors",
  );
  await income.category(
    owner,
    { name: "Sponsorship", active: true },
    sponsorship,
  );
  await assert.rejects(() =>
    income.category(owner, { name: "events", active: true }),
  );
});
test("access is limited to finance viewers in the same organization", async () => {
  assert.equal((await income.overview(other, filter)).total_minor, 0);
  await assert.rejects(() => income.category(other, { name: "Hack" }, events));
  const staff: Actor = {
      uid: randomUUID(),
      email: "income-staff@example.com",
      name: "Staff",
    },
    mid = randomUUID();
  await db.query(
    `INSERT INTO memberships(id,organization_id,user_id,email,display_name,role,permissions) VALUES($1,$2,$3,$4,'Desk','staff',$5)`,
    [mid, org, staff.uid, staff.email, JSON.stringify(["collect_payments"])],
  );
  assert.ok((await income.catalog(staff)).categories.length > 0);
  await assert.rejects(() => income.overview(staff, filter));
  await db.query("UPDATE memberships SET permissions=$1 WHERE id=$2", [
    JSON.stringify(["view_finance"]),
    mid,
  ]);
  // Unassigned staff never see organization-level or other business income.
  assert.equal((await income.overview(staff, filter)).total_minor, 0);
});
test("reversals reduce income and exports include every row", async () => {
  await accounts.reverse(owner, sponsorshipId, {
    command_key: randomUUID(),
    reason: "Sponsor cancelled",
  });
  const d = await income.report(owner, { ...filter, source: sponsorship });
  assert.equal(d.items.length, 2);
  assert.equal(d.total_minor, 0);
  assert.equal(d.source_filter, "Sponsorship");
  const categoryYear = await income.report(owner, {
    from: `${today.slice(0, 4)}-01-01`,
    until: `${today.slice(0, 4)}-12-31`,
    source: sponsorship,
  });
  assert.equal(categoryYear.items.length, 2);
  assert.equal(categoryYear.source_filter, "Sponsorship");
  const all = await income.report(owner, filter);
  assert.equal(all.total_minor, 85000);
  assert.equal(all.refunds_minor, 10000);
  const xlsx = await renderIncomeReport(all, "xlsx"),
    wb = new ExcelJS.Workbook();
  await wb.xlsx.load(xlsx as any);
  assert.equal(wb.getWorksheet("Income")!.rowCount, all.items.length + 1);
  assert.equal(wb.getWorksheet("Sources")!.rowCount, all.sources.length + 1);
  assert.ok(Number.isFinite(Date.parse(all.exported_at)));
  assert.equal(wb.getWorksheet("Summary")!.getCell("A4").value, "Exported at");
  assert.match(String(wb.getWorksheet("Summary")!.getCell("B4").value), /UTC/);
  const pdf = await renderIncomeReport(all, "pdf");
  assert.equal(pdf.subarray(0, 5).toString(), "%PDF-");
});
test("income export groups split payments and refunds without losing their dates", async () => {
  const data = {
    name: "Eden",
    currency: "INR",
    timezone: "Asia/Kolkata",
    from: "2026-10-01",
    until: "2026-10-31",
    exported_at: "2026-10-30T12:00:00Z",
    total_minor: 20000,
    refunds_minor: 5000,
    net_minor: 15000,
    count: 2,
    sources: [],
    items: [
      {
        id: "payment",
        booking_id: "booking",
        booking_reference: "BK-12",
        customer_name: "Asha",
        booking_date: "2026-10-28",
        local_date: "2026-10-27",
        local_time: "2026-10-27 14:05:00",
        space_name: "Main Turf",
        source_name: "Bookings",
        amount_minor: 20000,
        lines: [
          { method: "cash", amount_minor: 10000, account_name: "Cash" },
          { method: "upi", amount_minor: 10000, account_name: "Bank" },
        ],
      },
      {
        id: "refund",
        booking_id: "booking",
        booking_reference: "BK-12",
        customer_name: "Asha",
        booking_date: "2026-10-28",
        local_date: "2026-10-29",
        local_time: "2026-10-29 09:30:00",
        space_name: "Main Turf",
        source_name: "Bookings",
        is_refund: true,
        amount_minor: -5000,
        lines: [{ method: "cash", amount_minor: -5000, account_name: "Cash" }],
      },
    ],
  };
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.load((await renderIncomeReport(data, "xlsx")) as any);
  const grouped = workbook.getWorksheet("Bookings and income")!;
  assert.equal(grouped.rowCount, 2);
  assert.equal(grouped.getCell("A2").value, "#BK-12 Asha");
  assert.equal(grouped.getCell("B2").value, "28 Oct 2026");
  assert.equal(grouped.getCell("C2").value, "27 Oct 2026, 29 Oct 2026");
  assert.equal(grouped.getCell("E2").value, 50);
  assert.equal(grouped.getCell("F2").value, 100);
  assert.equal(grouped.getCell("G2").value, 150);
  assert.equal(workbook.getWorksheet("Payment details")!.rowCount, 4);
  assert.equal(
    workbook.getWorksheet("Summary")!.getCell("A14").value,
    "Cash received (net)",
  );
  assert.equal(workbook.getWorksheet("Summary")!.getCell("B14").value, 50);
  assert.equal(
    workbook.getWorksheet("Summary")!.getCell("A15").value,
    "Bank / digital received (net)",
  );
  assert.equal(workbook.getWorksheet("Summary")!.getCell("B15").value, 100);
  assert.match(
    String(workbook.getWorksheet("Summary")!.getCell("B4").value),
    /Asia\/Kolkata/,
  );
});
test("Accounts splits selected, previous and today totals from one scan", async () => {
  const yesterday = new Date(Date.now() - 86400000).toISOString();
  const id = randomUUID();
  await db.query(
    "INSERT INTO finance_events(id,organization_id,kind,reason,occurred_at,recorded_by) VALUES($1,$2,'booking_collection','Seeded',$3,$4)",
    [id, org, yesterday, owner.uid],
  );
  await db.query(
    "INSERT INTO finance_lines(id,organization_id,event_id,account_id,method,amount_minor) VALUES($1,$2,$3,$4,'cash',7000)",
    [randomUUID(), org, id, cash],
  );
  const o = await accounts.overview(owner, filter);
  const i = await income.overview(owner, filter);
  assert.equal(o.selected.income_minor, i.total_minor);
  assert.equal(o.today.income_minor, i.total_minor);
  assert.equal(o.previous.income_minor, 7000);
  assert.equal(o.previous.methods.cash, 7000);
});
test("UPI collections and refunds appear in the correct daily and period method totals", async () => {
  const before = await income.overview(owner, filter);
  const beforeCash = Number(
    (before.methods as any[]).find((m) => m.method === "cash")?.total_minor ??
      0,
  );
  const bank = randomUUID();
  await db.query(
    "INSERT INTO money_accounts(id,organization_id,name,kind,is_primary) VALUES($1,$2,'Test bank','bank',false)",
    [bank, org],
  );
  for (const [kind, amount] of [
    ["booking_collection", 7500],
    ["booking_refund", -2500],
  ] as const) {
    const id = randomUUID();
    await db.query(
      "INSERT INTO finance_events(id,organization_id,kind,reason,occurred_at,recorded_by) VALUES($1,$2,$3,'UPI test',$4,$5)",
      [id, org, kind, now, owner.uid],
    );
    await db.query(
      "INSERT INTO finance_lines(id,organization_id,event_id,account_id,method,amount_minor) VALUES($1,$2,$3,$4,'upi',$5)",
      [randomUUID(), org, id, bank, amount],
    );
  }
  const overview = await income.overview(owner, filter);
  const day = (overview.days as any[]).find((d) => d.day === today);
  assert.deepEqual(
    (day.methods as any[]).map((m) => [m.method, Number(m.total_minor)]),
    [
      ["cash", beforeCash],
      ["upi", 5000],
    ],
  );
  assert.deepEqual(
    (overview.methods as any[]).map((m) => [m.method, Number(m.total_minor)]),
    [
      ["cash", beforeCash],
      ["upi", 5000],
    ],
  );
});
