import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { AccountsService } from "../src/accounts/accounts.service";
import { InvoicesService } from "../src/invoices/invoices.service";
import { BookingService } from "../src/bookings/booking.service";
import { CourtService } from "../src/court/court.service";
import { Actor } from "../src/common/auth.guard";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  w = new WorkspaceService(db),
  s = new AccountsService(db, w),
  bookings = new BookingService(db, w),
  invoices = new InvoicesService(db, w, bookings);
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

const png =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jXioAAAAASUVORK5CYII=";
const book = async (who: Actor, hour: string, paid: number) => {
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
    customer: { id: null, name: "Asha Nair", phone: "9876500011", email: null },
    notes: "",
    payments: paid
      ? [
          {
            method: "cash",
            amount_minor: paid,
            reference: "",
            received_at: new Date().toISOString(),
          },
        ]
      : [],
  });
};
const generate = (who: Actor, id: string, key = randomUUID()) =>
  invoices.generate(who, id, { command_key: key });
test("invoices are on by default and only the owner can switch them off", async () => {
  assert.deepEqual(await invoices.settings(owner), { enabled: true });
  const inv = await w.invite(owner, {
    email: "staff@example.com",
    display_name: "Desk staff",
    role: "staff",
    permissions: ["view_bookings", "manage_bookings", "collect_payments"],
    assignments: [{ business_id: business, resource_ids: [space] }],
  });
  const staff = actor();
  staff.email = "staff@example.com";
  await w.accept(staff, new URL(inv.invitation_url).searchParams.get("token")!);
  await assert.rejects(
    () => invoices.saveSettings(staff, { enabled: false }),
    /owner/i,
  );
  await assert.rejects(() =>
    invoices.saveSettings(owner, { enabled: "no", extra: 1 }),
  );
  assert.deepEqual(await invoices.settings(staff), { enabled: true });
  const booking = await book(owner, "07:00", 0);
  assert.deepEqual(await invoices.saveSettings(owner, { enabled: false }), {
    enabled: false,
  });
  assert.deepEqual(await invoices.settings(staff), { enabled: false });
  await assert.rejects(() => generate(owner, booking.id), /turned off/);
  await invoices.saveSettings(owner, { enabled: true });
  assert.equal(
    (await generate(staff, booking.id)).invoice_number,
    "INV-000001",
  );
});
test("invoice keeps full original details, history is immutable and re-downloadable", async () => {
  await invoices.saveSettings(owner, { enabled: true });
  await w.uploadLogo(owner, { content_type: "image/png", base64: png });
  await s.saveWebsitePayments(owner, {
    version: 0,
    upi_id: "venue@bank",
    qr: { content_type: "image/png", base64: png },
  });
  await s.route(owner, {
    business_id: business,
    resource_id: space,
    method: "bank_transfer",
    account_id: bankB,
  });
  const booking = await book(owner, "09:00", 20000);
  const first = await generate(owner, booking.id);
  assert.match(first.invoice_number, /^INV-\d{6}$/);
  assert.equal(first.total_minor, 65000);
  assert.equal(first.paid_minor, 20000);
  assert.equal(first.balance_minor, 45000);
  assert.equal(first.reused, false);
  const row = (
    await db.query<any>("SELECT snapshot FROM booking_invoices WHERE id=$1", [
      first.id,
    ])
  ).rows[0].snapshot;
  assert.equal(row.organization.name, "Finance QA");
  assert.equal(row.organization.phone, "9876543210");
  assert.ok(row.organization.address_lines.join(" ").includes("Main Road"));
  assert.equal(row.customer.name, "Asha Nair");
  assert.equal(row.customer.phone, "9876500011");
  assert.equal(
    row.booking.reference,
    (await bookings.detail(owner, booking.id)).reference,
  );
  assert.equal(row.upi_id, "venue@bank");
  assert.deepEqual(
    row.bank_accounts.map((a: any) => [a.name, a.account_number]),
    [["Secondary SBI", "001234561234"]],
  );
  const file = await invoices.pdf(owner, first.id);
  assert.equal(file.filename, `${first.invoice_number}.pdf`);
  assert.equal(file.bytes.subarray(0, 5).toString(), "%PDF-");
  // Same data -> the existing invoice is returned instead of numbering a duplicate.
  const again = await generate(owner, booking.id);
  assert.equal(again.id, first.id);
  assert.equal(again.reused, true);
  // Replaying a command key returns the same invoice.
  const key = randomUUID();
  const replayA = await generate(owner, booking.id, key);
  assert.equal((await generate(owner, booking.id, key)).id, replayA.id);
  // A payment changes the invoice: new number, old snapshot untouched.
  await bookings.payments(owner, booking.id, {
    command_key: randomUUID(),
    version: (await bookings.detail(owner, booking.id)).version,
    kind: "collection",
    reason: "",
    payments: [
      {
        method: "cash",
        amount_minor: 45000,
        reference: "",
        received_at: new Date().toISOString(),
      },
    ],
  });
  const second = await generate(owner, booking.id);
  assert.notEqual(second.id, first.id);
  assert.equal(second.balance_minor, 0);
  assert.equal(second.paid_minor, 65000);
  const old = (await invoices.list(owner, booking.id)).invoices;
  assert.deepEqual(
    old.map((i) => i.id),
    [second.id, first.id],
  );
  assert.equal(old[1].balance_minor, 45000);
  // Changing organization details later does not alter the stored original.
  await db.query(
    "UPDATE organizations SET name='Renamed' WHERE id=(SELECT organization_id FROM memberships WHERE user_id=$1)",
    [owner.uid],
  );
  const stored = (
    await db.query<any>("SELECT snapshot FROM booking_invoices WHERE id=$1", [
      first.id,
    ])
  ).rows[0].snapshot;
  assert.equal(stored.organization.name, "Finance QA");
  await assert.rejects(
    () =>
      db.query("UPDATE booking_invoices SET total_minor=1 WHERE id=$1", [
        first.id,
      ]),
    /cannot be changed/,
  );
  await assert.rejects(
    () => db.query("DELETE FROM booking_invoices WHERE id=$1", [first.id]),
    /cannot be changed/,
  );
  assert.equal(
    (await invoices.pdf(owner, first.id)).bytes.subarray(0, 5).toString(),
    "%PDF-",
  );
});
test("invoices are scoped to the organization and booking access", async () => {
  const booking = await book(owner, "12:00", 0);
  const made = await generate(owner, booking.id);
  await assert.rejects(() => generate(other, booking.id));
  await assert.rejects(() => invoices.pdf(other, made.id));
  await assert.rejects(() => invoices.list(other, booking.id));
});
