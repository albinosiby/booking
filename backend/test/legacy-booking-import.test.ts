import "reflect-metadata";
import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { BookingService } from "../src/bookings/booking.service";
import { systemAccounts, postBookingPayment } from "../src/accounts/ledger";
import {
  applyBookingImport,
  buildBookingImport,
  hash,
  sourceTime,
  type ImportDestination,
  type LegacyExport,
  type SpaceMapping,
} from "../scripts/legacy-booking-import";

delete process.env.DATABASE_URL;
delete process.env.DATABASE_MIGRATE;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database();
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());

async function fixture() {
  const org = randomUUID(),
    location = randomUUID(),
    turf = randomUUID(),
    pool = randomUUID();
  const half = randomUUID(),
    full = randomUUID(),
    water = randomUUID();
  const sectionA = randomUUID(),
    sectionB = randomUUID(),
    ground = randomUUID();
  const halfOption = randomUUID(),
    fullOption = randomUUID();
  const owner = {
    uid: randomUUID(),
    email: "owner@example.test",
    name: "Owner",
  };
  await db.query(
    "INSERT INTO organizations(id,name,contact_phone,currency,created_by) VALUES($1,'Import fixture','9876543210','INR',$2)",
    [org, owner.uid],
  );
  await db.query(
    "INSERT INTO locations(id,organization_id,name,address_line_1,city,country_code,postal_code,timezone) VALUES($1,$2,'Arena','Road','Kochi','IN','682001','Asia/Kolkata')",
    [location, org],
  );
  await db.query(
    "INSERT INTO memberships(id,organization_id,user_id,email,display_name,role) VALUES($1,$2,$3,$4,'Owner','owner')",
    [randomUUID(), org, owner.uid, owner.email],
  );
  const config = {
    kind: "turf_v1",
    schema_version: 1,
    grounds: [
      {
        id: ground,
        name: "Ground",
        sections: [
          { id: sectionA, name: "A" },
          { id: sectionB, name: "B" },
        ],
      },
    ],
    layouts: [
      { id: half, name: "Half A", ground_id: ground, section_ids: [sectionA] },
      {
        id: full,
        name: "Full",
        ground_id: ground,
        section_ids: [sectionA, sectionB],
      },
    ],
    offerings: [
      { id: halfOption, layout_id: half },
      { id: fullOption, layout_id: full },
    ],
  };
  const poolConfig = {
    kind: "pool_v1",
    schema_version: 1,
    pools: [{ id: water, name: "Pool", capacity: 8 }],
  };
  for (const [id, name, type, configuration] of [
    [turf, "Turf", "turf", config],
    [pool, "Pool", "pool", poolConfig],
  ])
    await db.query(
      "INSERT INTO businesses(id,organization_id,location_id,name,type,status,configuration) VALUES($1,$2,$3,$4,$5,'ready',$6)",
      [id, org, location, name, type, JSON.stringify(configuration)],
    );
  for (const [id, business, name, capacity] of [
    [half, turf, "Half A", 1],
    [full, turf, "Full", 1],
    [water, pool, "Pool", 8],
  ])
    await db.query(
      "INSERT INTO resources(id,organization_id,business_id,name,capacity) VALUES($1,$2,$3,$4,$5)",
      [id, org, business, name, capacity],
    );
  await systemAccounts(db, org);
  const existingCustomer = randomUUID(),
    existingBank = randomUUID(),
    existingBooking = randomUUID();
  await db.query(
    "INSERT INTO customers(id,organization_id,name,phone,email) VALUES($1,$2,'Existing customer','9876543210',null)",
    [existingCustomer, org],
  );
  await db.query(
    "INSERT INTO money_accounts(id,organization_id,name,kind,bank_name,last_four,account_number,is_primary) VALUES($1,$2,'Existing bank','bank','Unrelated bank','1111','11111111',true)",
    [existingBank, org],
  );
  await db.query(
    "INSERT INTO bookings(id,organization_id,business_id,resource_id,customer_id,reference,starts_at,ends_at,total_minor,selection,price_snapshot,customer_snapshot,notes,people,created_by) VALUES($1,$2,$3,$4,$5,'EXISTING','2020-01-01T10:00Z','2020-01-01T11:00Z',1000,'{}',$6,$7,'Never change this',1,$8)",
    [
      existingBooking,
      org,
      turf,
      half,
      existingCustomer,
      JSON.stringify({ timezone: "Asia/Kolkata" }),
      JSON.stringify({
        name: "Existing customer",
        phone: "9876543210",
        email: null,
      }),
      owner.uid,
    ],
  );
  const existingPayment = randomUUID();
  await db.query(
    "INSERT INTO booking_payments(id,organization_id,booking_id,kind,method,amount_minor,received_at,recorded_by) VALUES($1,$2,$3,'collection','cash',1000,'2020-01-01T10:00Z',$4)",
    [existingPayment, org, existingBooking, owner.uid],
  );
  await postBookingPayment(
    db,
    org,
    existingPayment,
    owner.uid,
    {
      booking_id: existingBooking,
      method: "cash",
      amount_minor: 1000,
      received_at: "2020-01-01T10:00:00Z",
      reference: "Original payment",
    },
    "collection",
    "",
  );

  const source: LegacyExport = {
    source_project: "source-project",
    source_business_id: "source-business",
    exported_at: "2026-11-17T11:00:00Z",
    data: {
      businesses: [{ id: "source-business" }],
      locations: [{ id: "source-location", timezone: "Asia/Kolkata" }],
      location_services: [
        { id: "source-turf-service", location_id: "source-location" },
        { id: "source-pool-service", location_id: "source-location" },
      ],
      assets: [
        {
          id: "source-turf",
          business_id: "source-business",
          location_service_id: "source-turf-service",
          buffer_minutes: 0,
        },
        {
          id: "source-pool",
          business_id: "source-business",
          location_service_id: "source-pool-service",
          buffer_minutes: 0,
        },
      ],
      asset_booking_options: [
        {
          id: "source-half",
          asset_id: "source-turf",
          name: "Half A",
          resource_keys: ["a"],
        },
        {
          id: "source-full",
          asset_id: "source-turf",
          name: "Full turf",
          resource_keys: ["a", "b"],
        },
        {
          id: "source-water",
          asset_id: "source-pool",
          name: "Pool",
          resource_keys: ["water"],
        },
      ],
      customers: [
        {
          id: "c1",
          business_id: "source-business",
          name: "Existing customer",
          phone: "9876543210",
          email: null,
        },
        {
          id: "c2",
          business_id: "source-business",
          name: "Phone unavailable",
          phone: "",
          email: null,
        },
        {
          id: "c3",
          business_id: "source-business",
          name: "Pool customer",
          phone: "9876543212",
          email: null,
        },
      ],
      bookings: [
        {
          id: "b1",
          customer_id: "c1",
          asset_id: "source-turf",
          booking_option_id: "source-half",
          ref: "REF-1",
          starts_at: "2026-09-25T22:00:00",
          ends_at: "2026-09-25T23:00:00",
          status: "confirmed",
          party_size: null,
          checked_in: true,
        },
        {
          id: "b2",
          customer_id: "c2",
          asset_id: "source-turf",
          booking_option_id: "source-full",
          ref: "REF-1",
          starts_at: "2026-09-26T23:30:00",
          ends_at: "2026-09-27T00:30:00",
          status: "confirmed",
          party_size: 1,
          checked_in: false,
        },
        {
          id: "b3",
          customer_id: "c3",
          asset_id: "source-pool",
          booking_option_id: "source-water",
          ref: "REF-3",
          starts_at: "2026-09-25T22:00:00",
          ends_at: "2026-09-25T23:00:00",
          status: "confirmed",
          party_size: 3,
          checked_in: false,
        },
        {
          id: "b4",
          customer_id: "c1",
          asset_id: "source-turf",
          booking_option_id: "source-half",
          ref: "REF-4",
          starts_at: "2026-09-25T22:00:00",
          ends_at: "2026-09-25T23:00:00",
          status: "cancelled",
          party_size: 1,
          checked_in: false,
        },
      ].map((b) => ({
        ...b,
        business_id: "source-business",
        created_at: "2026-09-25T15:00:00.123456",
        payment_status: "partial",
        source: "phone",
        notes: "Original booking note",
      })),
      booking_lines: [1000, 2000, 600, 500].map((amount, i) => ({
        id: i + 1,
        booking_id: `b${i + 1}`,
        label: "Booking",
        amount,
      })),
      booking_payments: [
        {
          id: 1,
          booking_id: "b1",
          method: "cash",
          amount: 200,
          bank_account_id: null,
        },
        {
          id: 2,
          booking_id: "b1",
          method: "upi",
          amount: 300,
          bank_account_id: "bank-source",
        },
        {
          id: 3,
          booking_id: "b1",
          method: "discount",
          amount: 100,
          bank_account_id: null,
        },
        {
          id: 4,
          booking_id: "b2",
          method: "upi",
          amount: 2000,
          bank_account_id: null,
        },
      ].map((p) => ({
        ...p,
        created_at: "2026-09-25T20:00:00.123456",
        note: "Original payment reference",
        collected_by_user_id: "old-user",
      })),
      app_users: [{ id: "old-user", name: "Original collector" }],
      bank_accounts: [
        {
          id: "bank-source",
          business_id: "source-business",
          label: "Source bank",
          bank_name: "Source bank",
          last4: "5678",
          account_number: "12345678",
        },
        {
          id: "unused",
          business_id: "source-business",
          label: "Unused bank",
          bank_name: "Other bank",
          last4: "1234",
          account_number: "99991234",
        },
      ],
      booking_collection_corrections: [],
    },
  };
  const mappings: SpaceMapping = {
    "source-half": {
      business_id: turf,
      resource_id: half,
      option_id: halfOption,
      inventory: { a: `${turf}:${sectionA}` },
    },
    "source-full": {
      business_id: turf,
      resource_id: full,
      option_id: fullOption,
      inventory: { a: `${turf}:${sectionA}`, b: `${turf}:${sectionB}` },
    },
    "source-water": {
      business_id: pool,
      resource_id: water,
      option_id: "regular",
      inventory: { water: `${pool}:${water}` },
    },
  };
  const destination: ImportDestination = { organization_id: org, data: {} };
  for (const t of [
    "organizations",
    "locations",
    "businesses",
    "resources",
    "customers",
    "money_accounts",
    "bookings",
  ])
    destination.data[t] = (
      await db.query(
        `SELECT * FROM ${t} WHERE ${t === "organizations" ? "id" : "organization_id"}=$1`,
        [org],
      )
    ).rows;
  const plan = buildBookingImport(
    source,
    destination,
    mappings,
    "2026-11-17T12:00:00Z",
  );
  return {
    org,
    owner,
    existingCustomer,
    existingBank,
    existingBooking,
    source,
    destination,
    mappings,
    plan,
  };
}

test("legacy times preserve local slots and UTC payment instants, including microseconds", () => {
  assert.equal(
    sourceTime("2026-09-25T22:00:00", "Asia/Kolkata"),
    "2026-09-25T16:30:00Z",
  );
  assert.equal(
    sourceTime("2026-09-25T20:00:00.123456"),
    "2026-09-25T20:00:00.123456Z",
  );
  assert.equal(
    sourceTime("2026-09-25T20:00:00+05:30"),
    "2026-09-25T20:00:00+05:30",
  );
});

test("bookings and real payments work through the stable detail API without changing existing data", async () => {
  const f = await fixture();
  const before = hash(f.source);
  const existing = (
    await db.query("SELECT * FROM bookings WHERE id=$1", [f.existingBooking])
  ).rows;
  const membershipBefore = (
    await db.query("SELECT * FROM memberships WHERE organization_id=$1", [
      f.org,
    ])
  ).rows;
  const accountBefore = (
    await db.query("SELECT * FROM money_accounts WHERE id=$1", [f.existingBank])
  ).rows;
  const result = await db.transaction((tx) => applyBookingImport(tx, f.plan));
  assert.equal(result.already_imported, false);
  assert.equal(result.bookings, 4);
  assert.equal(result.payments, 3);
  assert.equal(result.collected_minor, 250000);
  assert.equal(result.discount_minor, 10000);
  assert.equal(result.active_balance_minor, 100000);
  assert.equal(f.plan.rows.customers!.length, 2);
  assert.equal(f.plan.rows.money_accounts!.length, 1);
  assert.equal(f.plan.renamed_references.length, 1);
  assert.equal(f.plan.customer_map.c1, f.existingCustomer);
  assert.deepEqual(
    (await db.query("SELECT * FROM bookings WHERE id=$1", [f.existingBooking]))
      .rows,
    existing,
  );
  assert.deepEqual(
    (
      await db.query("SELECT * FROM memberships WHERE organization_id=$1", [
        f.org,
      ])
    ).rows,
    membershipBefore,
  );
  assert.deepEqual(
    (
      await db.query("SELECT * FROM money_accounts WHERE id=$1", [
        f.existingBank,
      ])
    ).rows,
    accountBefore,
  );
  assert.equal(hash(f.source), before);
  const service = new BookingService(db, new WorkspaceService(db));
  const booking = f.plan.rows.bookings!.find(
    (b) => b.price_snapshot.legacy_import.source_booking_id === "b1",
  )!;
  const shown: Record<string, any> = await service.detail(f.owner, booking.id);
  assert.equal(shown.local_start, "2026-09-25T22:00");
  assert.equal(shown.total_minor, 90000);
  assert.equal(shown.net_paid_minor, 50000);
  assert.equal(shown.balance_minor, 40000);
  assert.equal(shown.price_snapshot.discount_minor, 10000);
  assert.equal(shown.payments.length, 2);
  assert.equal(shown.payments[0].local_received, "2026-09-26T01:30");
  assert.ok(shown.history.some((h: any) => h.action === "checked_in"));
  const cancelled = f.plan.rows.bookings!.find(
    (b) => b.status === "cancelled",
  )!;
  assert.equal(
    (
      await db.query("SELECT * FROM booking_allocations WHERE booking_id=$1", [
        cancelled.id,
      ])
    ).rows.length,
    0,
  );
  const full = f.plan.rows.bookings!.find(
    (b) => b.price_snapshot.legacy_import.source_booking_id === "b2",
  )!;
  assert.equal(
    (
      await db.query("SELECT * FROM booking_allocations WHERE booking_id=$1", [
        full.id,
      ])
    ).rows.length,
    2,
  );
  const water = f.plan.rows.bookings!.find((b) => b.people === 3)!;
  assert.equal(
    (
      await db.query<any>(
        "SELECT quantity FROM booking_allocations WHERE booking_id=$1",
        [water.id],
      )
    ).rows[0].quantity,
    3,
  );
});

test("repeating the import adds nothing and rejects a changed source export", async () => {
  const f = await fixture();
  await db.transaction((tx) => applyBookingImport(tx, f.plan));
  const count = async () =>
    (
      await db.query<any>(
        "SELECT count(*)::int AS n FROM finance_events WHERE organization_id=$1",
        [f.org],
      )
    ).rows[0].n;
  const n = await count();
  const again = await db.transaction((tx) => applyBookingImport(tx, f.plan));
  assert.equal(again.already_imported, true);
  assert.equal(await count(), n);
  const changed = structuredClone(f.source);
  changed.data.booking_lines![0]!.amount += 1;
  const plan = buildBookingImport(
    changed,
    f.destination,
    f.mappings,
    "2026-11-17T13:00:00Z",
  );
  await assert.rejects(
    db.transaction((tx) => applyBookingImport(tx, plan)),
    /different export was already imported/,
  );
  assert.equal(await count(), n);
});

test("a late foreign-key failure rolls back every inserted booking and payment", async () => {
  const f = await fixture();
  f.plan.rows.finance_lines![0]!.account_id = randomUUID();
  await assert.rejects(db.transaction((tx) => applyBookingImport(tx, f.plan)));
  assert.equal(
    (
      await db.query<any>(
        "SELECT count(*)::int AS n FROM bookings WHERE organization_id=$1",
        [f.org],
      )
    ).rows[0].n,
    1,
  );
  assert.equal(
    (
      await db.query<any>(
        "SELECT count(*)::int AS n FROM booking_payments WHERE organization_id=$1",
        [f.org],
      )
    ).rows[0].n,
    1,
  );
  assert.equal(
    (
      await db.query(
        "SELECT * FROM booking_commands WHERE organization_id=$1",
        [f.org],
      )
    ).rows.length,
    0,
  );
  assert.equal(
    (
      await db.query("SELECT * FROM customers WHERE organization_id=$1", [
        f.org,
      ])
    ).rows.length,
    1,
  );
});

test("rejects cross-tenant mappings, wrong inventory sections and invalid discounts", async () => {
  const f = await fixture();
  const wrong = structuredClone(f.mappings);
  wrong["source-half"]!.business_id = randomUUID();
  assert.throws(
    () =>
      buildBookingImport(
        f.source,
        f.destination,
        wrong,
        "2026-11-17T12:00:00Z",
      ),
    /topology/,
  );
  const keys = structuredClone(f.mappings);
  keys["source-full"]!.inventory.b = "another-tenant:section";
  assert.throws(
    () =>
      buildBookingImport(f.source, f.destination, keys, "2026-11-17T12:00:00Z"),
    /inventory topology/,
  );
  const discounts = structuredClone(f.source);
  discounts.data.booking_payments![2]!.amount = 100000;
  assert.throws(
    () =>
      buildBookingImport(
        discounts,
        f.destination,
        f.mappings,
        "2026-11-17T12:00:00Z",
      ),
    /discount/,
  );
});
