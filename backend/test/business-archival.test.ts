import "reflect-metadata";
import { before, after, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { BookingService } from "../src/bookings/booking.service";
import { AdmissionService } from "../src/admissions/admission.service";
import { AccountsService } from "../src/accounts/accounts.service";
import { addDate, localStamp } from "../src/bookings/booking.inventory";
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
    `archive-${randomUUID().slice(0, 8)}`,
    allTypes,
  );
  const bookings = new BookingService(db, f.workspace);
  const catalog = await bookings.catalog(f.owner);
  const business = catalog.businesses.find((b: any) => b.type === "badminton")!;
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
    )!;
  return { ...f, bookings, business, request, current };
}

test("archive hides setup/public/new bookings, preserves configuration, supports safe retries and name reuse", async () => {
  const f = await fixture();
  const before = await f.current();
  const w = await f.workspace.workspace(f.owner);
  await f.workspace.archiveBusiness(f.owner, before.id, {
    version: before.version,
  });
  await f.workspace.archiveBusiness(f.owner, before.id, {
    version: before.version,
  });
  assert.equal((await f.workspace.workspace(f.owner)).businesses.length, 0);
  assert.equal((await f.website.settings(f.owner)).businesses.length, 0);
  assert.equal((await f.website.catalog(f.slug)).businesses.length, 0);
  const catalog = await f.bookings.catalog(f.owner);
  assert.equal(catalog.businesses.length, 0);
  assert.equal(catalog.filter_businesses[0].id, before.id);
  const after = await f.current();
  assert.equal(after.status, "archived");
  assert.equal(after.archived_by, f.owner.uid);
  assert.ok(after.archived_at);
  assert.equal(after.version, before.version + 1);
  assert.deepEqual(after.configuration, before.configuration);
  assert.deepEqual(after.resources, before.resources);
  assert.equal(
    (await f.workspace.workspace(f.owner)).organization.business_order_revision,
    w.organization.business_order_revision + 1,
  );
  assert.equal(
    (
      await db.query<any>(
        "SELECT count(*)::int n FROM audit_events WHERE entity_id=$1 AND action='business.archived'",
        [before.id],
      )
    ).rows[0].n,
    1,
  );
  await assert.rejects(
    () => f.workspace.activate(f.owner, before.id),
    /not found/i,
  );
  await assert.rejects(
    () =>
      f.workspace.renameBusiness(f.owner, before.id, { name: "Resurrected" }),
    /not found/i,
  );
  await assert.rejects(
    () => f.workspace.addResource(f.owner, before.id, { name: "New space" }),
    /not found/i,
  );
  await assert.rejects(
    () => f.bookings.create(f.owner, f.request),
    /not ready/i,
  );
  const newBusiness = await f.workspace.createBusiness(f.owner, {
    name: before.name,
    type: before.type,
    location_id: before.location_id,
  });
  assert.notEqual(newBusiness.id, before.id);
  const latest = await f.workspace.workspace(f.owner);
  await f.workspace.reorderBusinesses(f.owner, {
    business_ids: [newBusiness.id],
    revision: latest.organization.business_order_revision,
  });
  await assert.rejects(
    () =>
      f.workspace.reorderBusinesses(f.owner, {
        business_ids: [before.id],
        revision: w.organization.business_order_revision,
      }),
    /changed/i,
  );
});

test("archive rejects staff, foreign owners, missing IDs, malformed versions and stale confirmations", async () => {
  const f = await fixture(),
    other = await fixture();
  const business = await f.current();
  await assert.rejects(
    () =>
      f.workspace.archiveBusiness(other.owner, business.id, {
        version: business.version,
      }),
    /not found/i,
  );
  await assert.rejects(
    () => f.workspace.archiveBusiness(f.owner, randomUUID(), { version: 1 }),
    /not found/i,
  );
  for (const input of [
    {},
    { version: "1" },
    { version: 0 },
    { version: 1, force: true },
  ])
    await assert.rejects(() =>
      f.workspace.archiveBusiness(f.owner, business.id, input),
    );
  const memberId = randomUUID(),
    staff = { uid: randomUUID(), email: "staff@example.com", name: "Staff" };
  await db.query(
    "INSERT INTO memberships(id,organization_id,user_id,email,display_name,role) VALUES($1,$2,$3,$4,$5,'staff')",
    [memberId, business.organization_id, staff.uid, staff.email, staff.name],
  );
  await db.query(
    "INSERT INTO staff_assignments(membership_id,organization_id,business_id) VALUES($1,$2,$3)",
    [memberId, business.organization_id, business.id],
  );
  await assert.rejects(
    () =>
      f.workspace.archiveBusiness(staff, business.id, {
        version: business.version,
      }),
    /owner/i,
  );
  await f.workspace.setBookingEnabled(f.owner, business.id, {
    version: business.version,
    enabled: false,
  });
  await assert.rejects(
    () =>
      f.workspace.archiveBusiness(f.owner, business.id, {
        version: business.version,
      }),
    /changed/i,
  );
  await f.workspace.archiveBusiness(f.owner, business.id, {
    version: (await f.current()).version,
  });
  assert.equal((await f.workspace.workspace(staff)).businesses.length, 0);
  // Retained assignments still grant historical access; removing a business
  // must not make unrelated team-permission edits invalid.
  await f.workspace.validateAssignments(db, business.organization_id, [
    { business_id: business.id, resource_ids: [] },
  ]);
});

test("future and ongoing bookings block removal; cancelled future bookings allow it", async () => {
  const f = await fixture(),
    business = await f.current();
  const created = await f.bookings.create(f.owner, f.request);
  await assert.rejects(
    () =>
      f.workspace.archiveBusiness(f.owner, business.id, {
        version: business.version,
      }),
    /resolve/i,
  );
  assert.equal((await f.current()).status, "ready");
  await db.query(
    "UPDATE bookings SET starts_at=now()-interval '1 hour',ends_at=now()+interval '1 hour' WHERE id=$1",
    [created.id],
  );
  await assert.rejects(
    () =>
      f.workspace.archiveBusiness(f.owner, business.id, {
        version: business.version,
      }),
    /resolve/i,
  );
  await f.bookings.status(f.owner, created.id, {
    command_key: randomUUID(),
    version: 1,
    status: "cancelled",
    reason: "Venue closing",
  });
  await f.workspace.archiveBusiness(f.owner, business.id, {
    version: business.version,
  });
  assert.equal(
    (await f.bookings.detail(f.owner, created.id)).status,
    "cancelled",
  );
});

test("historical bookings, customers, payments and ledger remain unchanged and readable after removal", async () => {
  const f = await fixture();
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
  await db.query(
    "UPDATE bookings SET starts_at=now()-interval '2 days',ends_at=now()-interval '47 hours' WHERE id=$1",
    [created.id],
  );
  const business = await f.current();
  const snapshot = async () => {
    const data: Record<string, unknown> = {};
    for (const table of [
      "customers",
      "bookings",
      "booking_payments",
      "finance_events",
    ])
      data[table] = (
        await db.query(
          `SELECT to_jsonb(t) AS row FROM ${table} t WHERE organization_id=$1 ORDER BY id`,
          [business.organization_id],
        )
      ).rows;
    data.history = (
      await db.query(
        "SELECT to_jsonb(h) AS row FROM booking_history h WHERE booking_id=$1 ORDER BY id",
        [created.id],
      )
    ).rows;
    return data;
  };
  const before = await snapshot();
  await f.workspace.archiveBusiness(f.owner, business.id, {
    version: business.version,
  });
  assert.deepEqual(await snapshot(), before);
  const detail = await f.bookings.detail(f.owner, created.id);
  assert.equal(detail.net_paid_minor, 1000);
  assert.equal(
    (await f.bookings.list(f.owner, { business_id: business.id })).items[0].id,
    created.id,
  );
  const accounts = new AccountsService(db, f.workspace);
  assert.ok(
    (await accounts.catalog(f.owner)).businesses.some(
      (b: any) => b.id === business.id,
    ),
  );
  // Historical balance collection remains available after removal.
  await f.bookings.payments(f.owner, created.id, {
    command_key: randomUUID(),
    version: detail.version,
    kind: "collection",
    reason: "",
    payments: [
      {
        method: "cash",
        amount_minor: 100,
        reference: "",
        received_at: new Date().toISOString(),
      },
    ],
  });
  assert.equal(
    (await f.bookings.detail(f.owner, created.id)).net_paid_minor,
    1100,
  );
});

test("active and upcoming admissions block removal; cancellation preserves admission history and stops new enrollments", async () => {
  const f = await fixture(true),
    admissions = new AdmissionService(db);
  const business = (await f.workspace.workspace(f.owner)).businesses.find(
    (b: any) => b.type === "pool",
  )!;
  const plan = business.configuration.plans.find(
    (p: any) => p.kind === "swimming",
  );
  let staleRequest: any;
  for (const offset of [0, 2]) {
    const input = {
      business_id: business.id,
      resource_id: plan.pool_ids[0],
      plan_id: plan.id,
      starts_on: addDate(
        localStamp(Date.now(), "Asia/Kolkata").slice(0, 10),
        offset,
      ),
      mode: "flexible",
      weekdays: [],
      time: "09:00",
      duration_minutes: 60,
      customer: f.request.customer,
      payments: [],
      renewed_from: null,
    };
    const quote = await admissions.preview(f.owner, input);
    staleRequest = {
      ...input,
      command_key: randomUUID(),
      preview_token: quote.preview_token,
    };
    const created = await admissions.create(f.owner, staleRequest);
    const a = await admissions.detail(f.owner, created.id);
    assert.equal(a.status, offset ? "upcoming" : "active");
    await assert.rejects(
      () =>
        f.workspace.archiveBusiness(f.owner, business.id, {
          version: business.version,
        }),
      /resolve/i,
    );
    await admissions.cancel(f.owner, created.id, {
      command_key: randomUUID(),
      version: a.version,
      reason: "Venue closing",
    });
  }
  await f.workspace.archiveBusiness(f.owner, business.id, {
    version: business.version,
  });
  assert.ok(
    !(await admissions.catalog(f.owner)).businesses.some(
      (b: any) => b.id === business.id,
    ),
  );
  await assert.rejects(
    () =>
      admissions.create(f.owner, {
        ...staleRequest,
        command_key: randomUUID(),
      }),
    /not ready|turned off/i,
  );
  const history = (
    await db.query<any>(
      "SELECT count(*)::int n FROM admissions WHERE business_id=$1",
      [business.id],
    )
  ).rows[0].n;
  assert.equal(history, 2);
});
