import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { writeFileSync } from "node:fs";
import ExcelJS from "exceljs";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { AccountsService } from "../src/accounts/accounts.service";
import { StaffCashService } from "../src/accounts/staff-cash.service";
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
  bookings = new BookingService(db, w),
  cashSvc = new StaffCashService(db, w);
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

let staff: Actor, staffId: string;
const book = async (who: Actor, hour: string, payments: object[]) => {
  const selection = {
    business_id: business,
    resource_id: space,
    option_id: (await bookings.catalog(owner)).businesses[0].resources[0]
      .options[0].id,
    date: "2030-06-05",
    time: hour,
    duration_minutes: 60,
    people: 1,
  };
  const q = await bookings.quote(who, { selection, exclude_booking_id: null });
  return bookings.create(who, {
    command_key: randomUUID(),
    selection,
    quote_token: q.quote_token,
    customer: { id: null, name: "Walk in", phone: "9876543210", email: null },
    notes: "",
    payments,
  });
};
const pay = (method: string, amount_minor: number) => ({
  method,
  amount_minor,
  reference: "",
  received_at: new Date().toISOString(),
});
const settle = (
  direction: string,
  amount_minor: number,
  expected_balance_minor: number,
  command_key = randomUUID(),
) =>
  cashSvc.settle(owner, staffId, {
    command_key,
    direction,
    amount_minor,
    expected_balance_minor,
    note: "",
  });
test("staff cash holding counts bookings and cash income, minus expenses, with partial handover and give-back", async () => {
  staff = actor();
  const inv = await w.invite(owner, {
    email: staff.email,
    display_name: "Pool staff",
    role: "staff",
    permissions: [
      "manage_bookings",
      "view_bookings",
      "collect_payments",
      "record_expenses",
      "view_finance",
    ],
    assignments: [{ business_id: business, resource_ids: [space] }],
  });
  await w.accept(staff, new URL(inv.invitation_url).searchParams.get("token")!);
  staffId = (
    await db.query<{ id: string }>(
      "SELECT id FROM memberships WHERE user_id=$1",
      [staff.uid],
    )
  ).rows[0].id;
  await book(staff, "09:00", [pay("upi", 50000), pay("cash", 15000)]);
  await book(owner, "11:00", [pay("cash", 65000)]);
  let me = await cashSvc.me(staff, {});
  assert.equal(me.cash_holding_minor, 15000);
  assert.equal(me.by_method.cash, 15000);
  assert.equal(me.by_method.upi, 50000);
  assert.equal(me.bank_minor, 50000);
  assert.equal(me.collected_minor, 65000);
  assert.equal(me.transactions.length, 2);
  assert.equal(
    me.transactions.every((t) => t.mine),
    true,
  );
  assert.equal(
    me.transactions.every((t) => t.customer_name === "Walk in"),
    true,
  );
  await s.createEntry(staff, entry("income", 5000, cash));
  await s.createEntry(staff, entry("expense", 2000, cash));
  me = await cashSvc.me(staff, {});
  assert.equal(me.cash_holding_minor, 18000);
  assert.equal(me.expenses_minor, 2000);
  // Partial collect, stale balance, wrong direction and over-collect.
  const key = randomUUID();
  const done = await settle("collect", 8000, 18000, key);
  assert.equal(done.balance_after_minor, 10000);
  assert.deepEqual(await settle("collect", 8000, 18000, key), done);
  await assert.rejects(() => settle("collect", 1000, 18000));
  await assert.rejects(() => settle("give", 1000, 10000));
  await assert.rejects(() => settle("collect", 10001, 10000));
  assert.equal((await cashSvc.me(staff, {})).cash_holding_minor, 10000);
  // Staff spends more than held: owner now owes staff.
  await s.createEntry(staff, entry("expense", 13000, cash));
  assert.equal((await cashSvc.me(staff, {})).cash_holding_minor, -3000);
  await assert.rejects(() => settle("collect", 1000, -3000));
  assert.equal((await settle("give", 1000, -3000)).balance_after_minor, -2000);
  assert.equal(
    (await cashSvc.overview(owner)).staff.find(
      (x) => x.membership_id === staffId,
    )?.holding_minor,
    -2000,
  );
  const personal = await cashSvc.me(staff, {});
  assert.equal(personal.handed_over_minor, 8000);
  assert.equal(personal.received_from_owner_minor, 1000);
  const history = await cashSvc.history(owner, filter);
  assert.equal(history.items.length, 2);
  await assert.rejects(() => cashSvc.settle(staff, staffId, {}));
  await assert.rejects(() => cashSvc.overview(staff));
  await assert.rejects(() => cashSvc.me(owner, {}));
});
test("reversal of a staff cash entry credits the original recorder", async () => {
  const before = (await cashSvc.me(staff, {})).cash_holding_minor;
  const e = await s.createEntry(staff, entry("income", 4000, cash));
  assert.equal((await cashSvc.me(staff, {})).cash_holding_minor, before + 4000);
  await s.reverse(owner, e.id, {
    command_key: randomUUID(),
    reason: "Mistake",
  });
  assert.equal((await cashSvc.me(staff, {})).cash_holding_minor, before);
});

test("collection-only staff get personal paginated payments and complete handover totals without finance access", async () => {
  const collector = actor();
  const invitation = await w.invite(owner, {
    email: collector.email,
    display_name: "Collection-only staff",
    role: "staff",
    permissions: ["collect_payments"],
    assignments: [{ business_id: business, resource_ids: [space] }],
  });
  await w.accept(
    collector,
    new URL(invitation.invitation_url).searchParams.get("token")!,
  );
  const member = await w.member(collector);
  // Real ledger rows in the isolated in-memory database; include admission refunds
  // and owner-recorded reversals so attribution and summaries exercise the SQL.
  async function ledger(
    kind: string,
    amount: number,
    method = "cash",
    by = collector.uid,
    reverses: string | null = null,
  ) {
    const id = randomUUID();
    await db.query(
      `INSERT INTO finance_events(id,organization_id,kind,business_id,resource_id,reason,reference,occurred_at,recorded_by,reverses_id)
      VALUES($1,$2,$3,$4,$5,'Personal payment','PAYMENT',now(),$6,$7)`,
      [id, member.organization_id, kind, business, space, by, reverses],
    );
    await db.query(
      `INSERT INTO finance_lines(id,organization_id,event_id,account_id,method,amount_minor) VALUES($1,$2,$3,$4,$5,$6)`,
      [
        randomUUID(),
        member.organization_id,
        id,
        method === "cash" ? cash : bank,
        method,
        amount,
      ],
    );
    return id;
  }
  for (let i = 0; i < 53; i++) await ledger("income", 10000);
  await ledger("income", 20000, "upi");
  await ledger("admission_refund", -3000);
  const expense = await ledger("expense", -2000);
  await ledger("reversal", 2000, "cash", owner.uid, expense);
  const initial = await cashSvc.me(collector, {});
  assert.equal(initial.collected_minor, 550000);
  assert.equal(initial.refunded_minor, 3000);
  assert.equal(initial.expenses_minor, 0);
  assert.equal(initial.cash_holding_minor, 527000);
  assert.equal(initial.transactions.length, 50);
  assert.equal(initial.next_cursor, 50);
  const next = await cashSvc.me(collector, {
    cursor: "50",
    date: initial.date,
  });
  assert.equal(next.transactions.length, 7);
  assert.equal(next.next_cursor, null);
  assert.equal(
    new Set([...initial.transactions, ...next.transactions].map((t) => t.id))
      .size,
    57,
  );
  assert.equal(
    [...initial.transactions, ...next.transactions].some(
      (t) => t.id === expense,
    ),
    true,
  );
  assert.equal(
    [...initial.transactions, ...next.transactions].some(
      (t) => t.kind === "reversal" && !t.mine,
    ),
    true,
  );
  assert.equal(JSON.stringify(initial).includes("Primary HDFC"), false);
  assert.equal("accounts" in initial, false);
  for (let i = 0; i < 51; i++)
    await cashSvc.settle(owner, member.id, {
      command_key: randomUUID(),
      direction: "collect",
      amount_minor: 1000,
      expected_balance_minor: 527000 - i * 1000,
    });
  const handed = await cashSvc.me(collector, {});
  assert.equal(handed.handed_over_minor, 51000);
  assert.equal(handed.received_from_owner_minor, 0);
  assert.equal(handed.cash_holding_minor, 476000);
  assert.equal(handed.settlements.length, 50);
  assert.equal(handed.next_settlement_cursor, 50);
  const older = await cashSvc.me(collector, { settlement_cursor: "50" });
  assert.equal(older.settlements.length, 1);
  assert.equal(older.next_settlement_cursor, null);
  assert.equal(older.handed_over_minor, 51000);
  assert.equal(
    new Set([...handed.settlements, ...older.settlements].map((t) => t.id))
      .size,
    51,
  );
  const past = await cashSvc.me(collector, { date: "2020-01-01" });
  assert.equal(past.transactions.length, 0);
  assert.equal(past.collected_minor, 0);
  assert.equal(past.cash_holding_minor, 476000);
  assert.equal(past.handed_over_minor, 51000);
  await assert.rejects(() => cashSvc.overview(collector));
  await assert.rejects(() => cashSvc.history(collector, filter));
  await assert.rejects(() =>
    cashSvc.settle(collector, member.id, {
      command_key: randomUUID(),
      direction: "collect",
      amount_minor: 1000,
      expected_balance_minor: 476000,
    }),
  );
  assert.equal((await cashSvc.me(collector, {})).handed_over_minor, 51000);
  await assert.rejects(() => cashSvc.me(collector, { cursor: -1 }));
  await db.query(
    `UPDATE memberships SET permissions='["view_bookings"]'::jsonb WHERE id=$1`,
    [member.id],
  );
  await assert.rejects(() => cashSvc.me(collector, {}));
});
