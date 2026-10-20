import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { HallService } from "../src/hall/hall.service";
import { Actor } from "../src/common/auth.guard";
import {
  HallConfiguration,
  hallConfigurationSchema,
  assertHallComplete,
  hallHourlyPriceAtStart,
  hallPackagePrice,
} from "../src/hall/hall.validation";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  workspace = new WorkspaceService(db),
  service = new HallService(db, workspace);
const hours = {
  days: [1, 2, 3, 4, 5, 6, 7],
  opens_at: "06:00",
  closes_at: "00:00",
  date_from: null,
  date_until: null,
};
function option(name: string, opens: string, closes: string, price: number) {
  return {
    id: randomUUID(),
    name,
    enabled: true,
    hours: { ...structuredClone(hours), opens_at: opens, closes_at: closes },
    prices: [
      {
        id: randomUUID(),
        days: [1, 2, 3, 4, 5, 6, 7],
        date_from: null,
        date_until: null,
        price_minor: price,
      },
    ],
  };
}
function configuration(): HallConfiguration {
  return hallConfigurationSchema.parse({
    kind: "hall_v1",
    schema_version: 1,
    halls: [1, 2].map((n) => ({
      id: randomUUID(),
      name: `Hall ${n}`,
      enabled: true,
      environment: "indoor",
      amenities: "AC, parking",
      capacity: n * 100,
      seated_capacity: n * 80,
      hourly_enabled: true,
      operating: structuredClone(hours),
      durations: [60],
      default_duration_minutes: 60,
      buffer_before: 0,
      buffer_after: 0,
      pricing_basis: "start_time",
      tariffs: [
        {
          id: randomUUID(),
          hours: { ...structuredClone(hours), closes_at: "18:00" },
          rates: [{ duration_minutes: 60, price_minor: n * 100000 }],
        },
        {
          id: randomUUID(),
          hours: { ...structuredClone(hours), opens_at: "18:00" },
          rates: [{ duration_minutes: 60, price_minor: n * 150000 }],
        },
      ],
      sessions: [
        option("Morning", "09:00", "13:00", 500000),
        option("Evening", "17:00", "22:00", 700000),
      ],
      full_day: option("Full day", "09:00", "23:00", 1800000),
    })),
  });
}
async function fixture(type = "hall") {
  const uid = randomUUID(),
    owner: Actor = { uid, email: `${uid}@example.com`, name: "Owner" };
  await workspace.createOrganization(owner, {
    name: "Eden",
    contact_phone: "9876543210",
    currency: "INR",
    location: {
      name: "Kochi",
      address_line_1: "Road",
      address_line_2: null,
      city: "Kochi",
      state_code: "KL",
      country_code: "IN",
      postal_code: "682001",
      timezone: "Asia/Kolkata",
    },
  });
  const w = await workspace.workspace(owner);
  const b = await workspace.createBusiness(owner, {
    name: "Courts",
    type,
    location_id: w.locations[0].id,
  });
  return { owner, id: b.id };
}
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());
test("halls persist all option types and support consecutive active edits with stable resources", async () => {
  const { owner, id } = await fixture(),
    c = configuration();
  await service.configure(owner, id, { version: 1, configuration: c });
  await workspace.activate(owner, id);
  let b = (await workspace.workspace(owner)).businesses[0];
  assert.equal(b.status, "ready");
  assert.deepEqual(b.configuration, c);
  assert.deepEqual(
    b.resources.map((r: any) => r.capacity),
    [100, 200],
  );
  [c.halls[0].name, c.halls[1].name] = [c.halls[1].name, c.halls[0].name];
  c.halls[1].capacity = 300;
  await service.configure(owner, id, { version: b.version, configuration: c });
  await workspace.activate(owner, id);
  b = (await workspace.workspace(owner)).businesses[0];
  c.halls[0].full_day.prices[0].price_minor = 2000000;
  await service.configure(owner, id, { version: b.version, configuration: c });
  await workspace.activate(owner, id);
  b = (await workspace.workspace(owner)).businesses[0];
  assert.equal(b.version, 7);
  assert.equal(b.status, "ready");
  assert.deepEqual(
    b.resources.map((r: any) => r.id).sort(),
    c.halls.map((p) => p.id).sort(),
  );
  assert.equal(
    b.resources.find((r: any) => r.id === c.halls[1].id).capacity,
    300,
  );
});
test("hourly start-time totals and session/full-day totals stay independent on the same hall", () => {
  const c = configuration(),
    p = c.halls[0];
  assert.equal(
    hallHourlyPriceAtStart(c, p.id, "2026-10-16", "17:30", 60),
    100000,
  );
  assert.equal(
    hallHourlyPriceAtStart(c, p.id, "2026-10-16", "18:00", 60),
    150000,
  );
  assert.equal(
    hallPackagePrice(c, p.id, p.sessions[0].id, "2026-10-16"),
    500000,
  );
  assert.equal(
    hallPackagePrice(c, p.id, p.sessions[1].id, "2026-10-16"),
    700000,
  );
  assert.equal(hallPackagePrice(c, p.id, p.full_day.id, "2026-10-16"), 1800000);
  assert.equal(
    hallPackagePrice(c, c.halls[1].id, p.full_day.id, "2026-10-16"),
    null,
  );
  assert.equal(
    hallHourlyPriceAtStart(c, p.id, "2026-10-16", "23:00", 60),
    150000,
  );
  assert.equal(
    hallHourlyPriceAtStart(c, p.id, "2026-10-16", "23:01", 60),
    null,
  );
});
test("per-hall options can be selected independently and require enabled prices only", () => {
  const c = configuration(),
    p = c.halls[0];
  p.hourly_enabled = false;
  p.tariffs = [];
  p.full_day.enabled = false;
  p.full_day.prices = [];
  p.sessions[1].enabled = false;
  p.sessions[1].prices = [];
  assertHallComplete(c);
  assert.equal(
    hallHourlyPriceAtStart(c, p.id, "2026-10-16", "10:00", 60),
    null,
  );
  assert.equal(hallPackagePrice(c, p.id, p.full_day.id, "2026-10-16"), null);
  p.sessions[0].enabled = false;
  assert.throws(() => assertHallComplete(c));
  p.sessions[0].enabled = true;
  p.sessions[0].prices[0].price_minor = null;
  assert.throws(() => assertHallComplete(c));
});
test("package weekday/seasonal rules, gaps and ambiguous prices are validated", () => {
  const c = configuration(),
    p = c.halls[0],
    o = p.full_day;
  o.prices[0].days = [1, 2, 3, 4, 5];
  o.prices.push({
    id: randomUUID(),
    days: [6, 7],
    date_from: null,
    date_until: null,
    price_minor: 2200000,
  });
  o.prices.push({
    id: randomUUID(),
    days: [6, 7],
    date_from: "2026-12-26",
    date_until: "2026-12-27",
    price_minor: 2500000,
  });
  assertHallComplete(c);
  assert.equal(hallPackagePrice(c, p.id, o.id, "2026-10-16"), 1800000);
  assert.equal(hallPackagePrice(c, p.id, o.id, "2026-10-17"), 2200000);
  assert.equal(hallPackagePrice(c, p.id, o.id, "2026-12-26"), 2500000);
  o.prices.push({ ...o.prices[0], id: randomUUID() });
  assert.equal(hallConfigurationSchema.safeParse(c).success, false);
  o.prices.splice(1);
  assert.equal(hallPackagePrice(c, p.id, o.id, "2026-10-17"), null);
});
test("capacity and opening hours reject invalid active changes; buffers are informational", async () => {
  const { owner, id } = await fixture(),
    c = configuration();
  let x = structuredClone(c);
  x.halls[0].seated_capacity = 101;
  assert.equal(hallConfigurationSchema.safeParse(x).success, false);
  x = structuredClone(c);
  x.halls[0].buffer_after = 120;
  assert.equal(hallConfigurationSchema.safeParse(x).success, true);
  x = structuredClone(c);
  x.halls[0].sessions[0].hours.opens_at = "05:00";
  assert.equal(hallConfigurationSchema.safeParse(x).success, false);
  await service.configure(owner, id, { version: 1, configuration: c });
  await workspace.activate(owner, id);
  x = structuredClone(c);
  x.halls[0].full_day.prices = [];
  await assert.rejects(() =>
    service.configure(owner, id, { version: 3, configuration: x }),
  );
  const b = (await workspace.workspace(owner)).businesses[0];
  assert.equal(b.status, "ready");
  assert.equal(b.version, 3);
  assert.deepEqual(b.configuration, c);
});
test("tenant, stale version, wrong business type and foreign resources are rejected", async () => {
  const a = await fixture(),
    b = await fixture(),
    wrong = await fixture("turf"),
    c = configuration();
  await service.configure(a.owner, a.id, { version: 1, configuration: c });
  await assert.rejects(() =>
    service.configure(a.owner, a.id, {
      version: 1,
      configuration: configuration(),
    }),
  );
  await assert.rejects(() =>
    service.configure(b.owner, a.id, { version: 2, configuration: c }),
  );
  await assert.rejects(() =>
    service.configure(b.owner, b.id, { version: 1, configuration: c }),
  );
  await assert.rejects(() =>
    service.configure(wrong.owner, wrong.id, {
      version: 1,
      configuration: configuration(),
    }),
  );
});
test("hall staff projections and pending scopes preserve privacy and resource identity", async () => {
  const { owner, id } = await fixture(),
    c = configuration();
  await service.configure(owner, id, { version: 1, configuration: c });
  const uid = randomUUID(),
    staff: Actor = { uid, email: `${uid}@example.com`, name: "Staff" };
  const invite = await workspace.invite(owner, {
    email: staff.email,
    display_name: "Staff",
    role: "staff",
    permissions: ["view_bookings"],
    assignments: [{ business_id: id, resource_ids: [c.halls[0].id] }],
  });
  const removed = { ...c, halls: c.halls.slice(1) };
  await assert.rejects(() =>
    service.configure(owner, id, { version: 2, configuration: removed }),
  );
  await workspace.accept(
    staff,
    new URL(invite.invitation_url).searchParams.get("token")!,
  );
  const visible = (await workspace.workspace(staff)).businesses[0];
  assert.deepEqual(
    visible.configuration.halls.map((p: any) => p.id),
    [c.halls[0].id],
  );
  await assert.rejects(() =>
    service.configure(staff, id, { version: 2, configuration: c }),
  );
  await assert.rejects(() =>
    service.configure(owner, id, { version: 2, configuration: removed }),
  );
  await assert.rejects(() =>
    workspace.addResource(owner, id, { name: "Bypass", capacity: 100 }),
  );
});
