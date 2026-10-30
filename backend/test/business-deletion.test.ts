import "reflect-metadata";
import { before, after, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { BookingService } from "../src/bookings/booking.service";
import { AdmissionService } from "../src/admissions/admission.service";
import { addDate, localStamp } from "../src/bookings/booking.inventory";
import { businessConfigurationTables } from "../src/workspace/business-deletion";
import { seedWebsite } from "../scripts/website-fixtures";

delete process.env.DATABASE_URL;
delete process.env.DATABASE_MIGRATE;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
process.env.BOOKING_WEBSITE_URL = "http://localhost:3000";
const db = new Database();
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());
async function fixture(allTypes = false) {
  const f = await seedWebsite(
    db,
    `delete-${randomUUID().slice(0, 8)}`,
    allTypes,
  );
  const bookings = new BookingService(db, f.workspace);
  const business = (await bookings.catalog(f.owner)).businesses.find(
    (b: any) => b.type === "badminton",
  )!;
  const resource = business.resources[0],
    option = resource.options[0];
  const selection = {
    business_id: business.id,
    resource_id: resource.id,
    option_id: option.id,
    date: addDate(business.today, 2),
    time: "10:00",
    duration_minutes: option.default_duration,
    people: 1,
  };
  const quote = await bookings.quote(f.owner, {
    selection,
    exclude_booking_id: null,
  });
  const request = {
    command_key: randomUUID(),
    selection,
    quote_token: quote.quote_token,
    customer: {
      id: null,
      name: "Test customer",
      phone: "9876543210",
      email: null,
    },
    notes: "",
    payments: [],
  };
  const current = async (id = business.id) =>
    (await f.workspace.workspace(f.owner, true)).businesses.find(
      (b: any) => b.id === id,
    );
  return { ...f, bookings, business, request, current };
}

test("permanent deletion removes configuration and website links, retains one audit and supports idempotent retry and name reuse", async () => {
  const f = await fixture(),
    b = await f.current();
  const previous = await f.workspace.workspace(f.owner),
    website = await f.website.settings(f.owner);
  await db.query(
    "INSERT INTO booking_website_spaces(website_id,organization_id,business_id,resource_id) VALUES($1,$2,$3,$4)",
    [website.id, b.organization_id, b.id, b.resources[0].id],
  );
  const member = randomUUID();
  await db.query(
    "INSERT INTO memberships(id,organization_id,user_id,email,display_name,role) VALUES($1,$2,$3,'staff@example.com','Staff','staff')",
    [member, b.organization_id, randomUUID()],
  );
  await db.query(
    "INSERT INTO staff_assignments(membership_id,organization_id,business_id) VALUES($1,$2,$3)",
    [member, b.organization_id, b.id],
  );
  await f.workspace.deleteBusiness(f.owner, b.id, { version: b.version });
  await f.workspace.deleteBusiness(f.owner, b.id, { version: b.version });
  assert.equal(await f.current(), undefined);
  for (const table of businessConfigurationTables)
    assert.equal(
      (await db.query(`SELECT 1 FROM ${table} WHERE business_id=$1`, [b.id]))
        .rows.length,
      0,
      table,
    );
  assert.equal((await f.website.settings(f.owner)).businesses.length, 0);
  assert.equal((await f.website.catalog(f.slug)).businesses.length, 0);
  assert.equal(
    (await f.website.settings(f.owner)).version,
    website.version + 1,
  );
  assert.equal((await f.bookings.catalog(f.owner)).filter_businesses.length, 0);
  assert.equal(
    (await f.workspace.workspace(f.owner)).organization.business_order_revision,
    previous.organization.business_order_revision + 1,
  );
  assert.equal(
    (
      await db.query(
        "SELECT 1 FROM audit_events WHERE entity_id=$1 AND action='business.deleted'",
        [b.id],
      )
    ).rows.length,
    1,
  );
  assert.equal(
    (await db.query("SELECT 1 FROM memberships WHERE id=$1", [member])).rows
      .length,
    1,
  );
  await assert.rejects(
    () => f.bookings.create(f.owner, f.request),
    /not found/i,
  );
  const next = await f.workspace.createBusiness(f.owner, {
    name: b.name,
    type: b.type,
    location_id: b.location_id,
  });
  assert.notEqual(next.id, b.id);
  await assert.rejects(
    () =>
      f.workspace.reorderBusinesses(f.owner, {
        business_ids: [b.id],
        revision: previous.organization.business_order_revision,
      }),
    /changed/i,
  );
});

test("deletion enforces tenant, owner, input and version checks; unknown missing IDs are not successful retries", async () => {
  const f = await fixture(),
    other = await fixture(),
    b = await f.current();
  await assert.rejects(
    () => f.workspace.deleteBusiness(other.owner, b.id, { version: b.version }),
    /not found/i,
  );
  await assert.rejects(
    () => f.workspace.deleteBusiness(f.owner, randomUUID(), { version: 1 }),
    /not found/i,
  );
  for (const input of [
    {},
    { version: "1" },
    { version: 0 },
    { version: 1, force: true },
  ])
    await assert.rejects(() =>
      f.workspace.deleteBusiness(f.owner, b.id, input),
    );
  await db.query("UPDATE memberships SET role='staff' WHERE user_id=$1", [
    f.owner.uid,
  ]);
  await assert.rejects(
    () => f.workspace.deleteBusiness(f.owner, b.id, { version: b.version }),
    /owner/i,
  );
  await db.query("UPDATE memberships SET role='owner' WHERE user_id=$1", [
    f.owner.uid,
  ]);
  await f.workspace.setBookingEnabled(f.owner, b.id, {
    version: b.version,
    enabled: false,
  });
  await assert.rejects(
    () => f.workspace.deleteBusiness(f.owner, b.id, { version: b.version }),
    /changed/i,
  );
  await f.workspace.deleteBusiness(f.owner, b.id, {
    version: (await f.current()).version,
  });
});

test("all booking history blocks deletion, including cancelled and past bookings; payments and ledger remain unchanged", async () => {
  const f = await fixture(),
    b = await f.current();
  const created = await f.bookings.create(f.owner, {
    ...f.request,
    payments: [
      {
        method: "cash",
        amount_minor: 1000,
        reference: "",
        received_at: new Date().toISOString(),
      },
    ],
  });
  const snapshot = async () => {
    const data: Record<string, unknown> = {};
    for (const table of [
      "bookings",
      "booking_payments",
      "finance_events",
      "customers",
    ])
      data[table] = (
        await db.query(
          `SELECT to_jsonb(t) AS row FROM ${table} t WHERE organization_id=$1 ORDER BY id`,
          [b.organization_id],
        )
      ).rows;
    return data;
  };
  for (const status of ["confirmed", "cancelled"]) {
    await db.query(
      "UPDATE bookings SET status=$1,starts_at=now()-interval '2 days',ends_at=now()-interval '47 hours' WHERE id=$2",
      [status, created.id],
    );
    const before = await snapshot();
    await assert.rejects(
      () => f.workspace.deleteBusiness(f.owner, b.id, { version: b.version }),
      /history/i,
    );
    assert.deepEqual(await snapshot(), before);
    assert.ok(await f.current());
  }
  assert.equal(
    (await f.bookings.detail(f.owner, created.id)).net_paid_minor,
    1000,
  );
});

test("cancelled admissions still block permanent deletion", async () => {
  const f = await fixture(true),
    admissions = new AdmissionService(db);
  const b = (await f.workspace.workspace(f.owner)).businesses.find(
    (b: any) => b.type === "pool",
  )!;
  const plan = b.configuration.plans.find((p: any) => p.kind === "swimming");
  const input = {
    business_id: b.id,
    resource_id: plan.pool_ids[0],
    plan_id: plan.id,
    starts_on: localStamp(Date.now(), "Asia/Kolkata").slice(0, 10),
    mode: "flexible",
    weekdays: [],
    time: "09:00",
    duration_minutes: 60,
    customer: f.request.customer,
    payments: [],
    renewed_from: null,
  };
  const preview = await admissions.preview(f.owner, input);
  const created = await admissions.create(f.owner, {
    ...input,
    command_key: randomUUID(),
    preview_token: preview.preview_token,
  });
  await admissions.cancel(f.owner, created.id, {
    command_key: randomUUID(),
    version: 1,
    reason: "Not attending",
  });
  await assert.rejects(
    () => f.workspace.deleteBusiness(f.owner, b.id, { version: b.version }),
    /history/i,
  );
  assert.equal(
    (await admissions.detail(f.owner, created.id)).status,
    "cancelled",
  );
});

test("independent financial entries block deletion without a booking", async () => {
  const f = await fixture(),
    b = await f.current();
  await db.query(
    "INSERT INTO finance_events(id,organization_id,business_id,kind,reason,occurred_at,recorded_by) VALUES($1,$2,$3,'income','Income',now(),$4)",
    [randomUUID(), b.organization_id, b.id, f.owner.uid],
  );
  await assert.rejects(
    () => f.workspace.deleteBusiness(f.owner, b.id, { version: b.version }),
    /financial.*history/i,
  );
  assert.ok(await f.current());
});

test("pending invitations and unexpected references block deletion without partial cleanup", async () => {
  const f = await fixture(),
    b = await f.current();
  const invite = await f.workspace.invite(f.owner, {
    email: "pending@example.com",
    display_name: "Pending staff",
    role: "staff",
    permissions: ["view_bookings"],
    assignments: [{ business_id: b.id, resource_ids: [] }],
  });
  await assert.rejects(
    () => f.workspace.deleteBusiness(f.owner, b.id, { version: b.version }),
    /pending invitations/i,
  );
  await db.query(
    "UPDATE invitations SET revoked_at=now() WHERE organization_id=$1",
    [b.organization_id],
  );
  await db.query(
    "CREATE TABLE protected_business_resource (resource_id uuid REFERENCES resources(id))",
  );
  await db.query("INSERT INTO protected_business_resource VALUES($1)", [
    b.resources[0].id,
  ]);
  await assert.rejects(
    () => f.workspace.deleteBusiness(f.owner, b.id, { version: b.version }),
    /linked records/i,
  );
  assert.equal((await f.current()).resources.length, b.resources.length);
  assert.ok(
    (await f.website.settings(f.owner)).businesses.some(
      (x: any) => x.id === b.id,
    ),
  );
  await db.query("DROP TABLE protected_business_resource");
});

test("unused draft deletion works without the unapplied archival columns or status migration", async () => {
  const f = await fixture(),
    w = await f.workspace.workspace(f.owner);
  const draft = await f.workspace.createBusiness(f.owner, {
    name: "Unused Party Hall",
    type: "hall",
    location_id: w.locations[0].id,
  });
  // Isolated in-memory database only: reproduce the pre-archival live schema.
  await db.query(
    "ALTER TABLE businesses DROP CONSTRAINT businesses_archive_metadata_check, DROP COLUMN archived_at, DROP COLUMN archived_by, DROP CONSTRAINT businesses_status_check",
  );
  await db.query(
    "ALTER TABLE businesses ADD CONSTRAINT businesses_status_check CHECK(status IN ('draft','ready','paused'))",
  );
  await f.workspace.deleteBusiness(f.owner, draft.id, { version: 1 });
  assert.equal(
    (await db.query("SELECT id FROM businesses WHERE id=$1", [draft.id])).rows
      .length,
    0,
  );
});
