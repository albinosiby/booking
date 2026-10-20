import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { PoolService } from "../src/pool/pool.service";
import { Actor } from "../src/common/auth.guard";
import {
  PoolConfiguration,
  poolConfigurationSchema,
  assertPoolComplete,
  poolPriceAtStart,
  poolGroupPrice,
  poolPlanExpiry,
} from "../src/pool/pool.validation";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  workspace = new WorkspaceService(db),
  service = new PoolService(db, workspace);
const actor = (): Actor => {
  const uid = randomUUID();
  return { uid, email: `${uid}@example.com`, name: "Owner" };
};
const hours = {
  days: [1, 2, 3, 4, 5, 6, 7],
  opens_at: "06:00",
  closes_at: "00:00",
  date_from: null,
  date_until: null,
};
function configuration(): PoolConfiguration {
  const pools = [20, 50].map((capacity, i) => ({
    id: randomUUID(),
    name: `Pool ${i + 1}`,
    capacity,
    depth_min_ft: 3 + i,
    depth_max_ft: 5 + i,
    enabled: true,
    regular_swimming: true,
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
        rates: [{ duration_minutes: 60, price_minor: 20000 }],
      },
      {
        id: randomUUID(),
        hours: { ...structuredClone(hours), opens_at: "18:00" },
        rates: [{ duration_minutes: 60, price_minor: 25000 }],
      },
    ],
  }));
  return poolConfigurationSchema.parse({
    kind: "pool_v1",
    schema_version: 1,
    pools,
    group_offers: [
      {
        id: randomUUID(),
        name: "Family group",
        pool_ids: pools.map((p) => p.id),
        group_mode: "up_to",
        people: 15,
        duration_minutes: 90,
        price_minor: 250000,
        enabled: true,
        availability: structuredClone(hours),
      },
    ],
    plans: [
      {
        id: randomUUID(),
        name: "25-day access",
        kind: "swimming",
        pool_ids: pools.map((p) => p.id),
        allowance: 25,
        expiry_mode: "after_start",
        expiry_days: 45,
        expiry_date: null,
        price_minor: 300000,
        enabled: true,
        availability: structuredClone(hours),
        class_duration_minutes: null,
        class_seats: null,
        coach_id: null,
        renewal: "none",
      },
      {
        id: randomUUID(),
        name: "Beginner coaching",
        kind: "coaching",
        pool_ids: [pools[0].id],
        allowance: 25,
        expiry_mode: "fixed_date",
        expiry_days: null,
        expiry_date: "2030-12-31",
        price_minor: 500000,
        enabled: true,
        availability: structuredClone(hours),
        class_duration_minutes: 60,
        class_seats: 10,
        coach_id: null,
        renewal: "none",
      },
    ],
  });
}
async function fixture() {
  const owner = actor();
  await workspace.createOrganization(owner, {
    name: "Eden",
    contact_phone: "9876543210",
    currency: "INR",
    location: {
      name: "Kochi",
      address_line_1: "Road 1",
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
    name: "Swimming",
    type: "pool",
    location_id: w.locations[0].id,
  });
  return { owner, id: b.id };
}
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());
test("pool capacities/depths and multiple products persist, activate and support consecutive edits", async () => {
  const { owner, id } = await fixture(),
    c = configuration();
  await service.configure(owner, id, { version: 1, configuration: c });
  await workspace.activate(owner, id);
  let b = (await workspace.workspace(owner)).businesses[0];
  assert.equal(b.status, "ready");
  assert.equal(b.version, 3);
  assert.deepEqual(
    b.resources
      .map((r: any) => r.capacity)
      .sort((a: number, b: number) => a - b),
    [20, 50],
  );
  assert.deepEqual(b.configuration, c);
  [c.pools[0].name, c.pools[1].name] = [c.pools[1].name, c.pools[0].name];
  c.pools[1].capacity = 60;
  await service.configure(owner, id, { version: b.version, configuration: c });
  await workspace.activate(owner, id);
  b = (await workspace.workspace(owner)).businesses[0];
  assert.equal(b.version, 5);
  assert.equal(b.configuration.plans[0].allowance, 25);
  assert.equal(b.configuration.plans[0].expiry_days, 45);
  assert.equal(b.configuration.plans[1].expiry_date, "2030-12-31");
  assert.equal(
    b.resources.find((r: any) => r.id === c.pools[1].id).capacity,
    60,
  );
});
test("pool start-time prices support seasonal precedence, per-person totals and canonical midnight", () => {
  const c = configuration(),
    p = c.pools[0];
  p.tariffs.push({
    id: randomUUID(),
    hours: {
      ...structuredClone(hours),
      days: [6, 7],
      opens_at: "09:00",
      closes_at: "18:00",
      date_from: "2026-10-17",
      date_until: "2026-10-18",
    },
    rates: [{ duration_minutes: 60, price_minor: 30000 }],
  });
  poolConfigurationSchema.parse(c);
  assert.equal(poolPriceAtStart(c, p.id, "2026-10-16", "17:30", 60, 2), 40000);
  assert.equal(poolPriceAtStart(c, p.id, "2026-10-17", "17:30", 60, 2), 60000);
  assert.equal(poolPriceAtStart(c, p.id, "2026-10-17", "18:00", 60), 25000);
  assert.equal(poolPriceAtStart(c, p.id, "2026-10-17", "23:00", 60), 25000);
  assert.equal(poolPriceAtStart(c, p.id, "2026-10-17", "23:01", 60), null);
  assert.equal(poolPriceAtStart(c, p.id, "2026-10-17", "24:00", 60), null);
  assert.equal(poolPriceAtStart(c, p.id, "2026-10-17", "10:00", 60, 21), null);
  p.tariffs.splice(1, 1);
  assert.equal(poolPriceAtStart(c, p.id, "2026-10-17", "18:00", 60), null);
});
test("pool calendar validity handles months, leap years and backward compatible days", () => {
  const c = configuration(),
    p = c.plans[1];
  p.expiry_mode = "after_months";
  p.expiry_days = null;
  p.expiry_date = null;
  p.expiry_months = 1;
  poolConfigurationSchema.parse(c);
  assert.equal(poolPlanExpiry(p, "2026-01-31"), "2026-02-28");
  assert.equal(poolPlanExpiry(p, "2024-01-31"), "2024-02-29");
  p.expiry_months = null;
  p.expiry_mode = "after_years";
  p.expiry_years = 1;
  poolConfigurationSchema.parse(c);
  assert.equal(poolPlanExpiry(p, "2024-02-29"), "2025-02-28");
  p.expiry_years = 0;
  assert.equal(poolConfigurationSchema.safeParse(c).success, false);
  p.expiry_years = 1;
  p.expiry_days = 30;
  assert.equal(poolConfigurationSchema.safeParse(c).success, false);
  p.expiry_days = null;
  p.expiry_years = 11;
  assert.equal(poolConfigurationSchema.safeParse(c).success, false);
  const legacy = configuration().plans[0];
  assert.equal(poolPlanExpiry(legacy, "2026-01-01"), "2026-02-15");
  assert.equal(
    poolPlanExpiry(configuration().plans[1], "2026-01-01"),
    "2030-12-31",
  );
});
test("coach contacts save with the plan without creating a staff account", async () => {
  const { owner, id } = await fixture();
  const c = configuration();
  const coach = {
    id: randomUUID(),
    name: "Alex Coach",
    phone: "+91 98765 43210",
  };
  c.coaches = [coach];
  c.plans[1].coach_id = coach.id;
  c.plans[1].expiry_mode = "after_years";
  c.plans[1].expiry_date = null;
  c.plans[1].expiry_years = 1;
  const before = (await workspace.team(owner)).members.length;
  await service.configure(owner, id, { version: 1, configuration: c });
  const saved = (await workspace.workspace(owner)).businesses.find(
    (b: any) => b.id === id,
  ).configuration;
  assert.deepEqual(saved.coaches, [coach]);
  assert.equal(saved.plans[1].coach_id, coach.id);
  assert.equal(saved.plans[1].expiry_years, 1);
  assert.equal((await workspace.team(owner)).members.length, before);
  const invalid = structuredClone(c);
  invalid.coaches![0].phone = "abc";
  assert.equal(poolConfigurationSchema.safeParse(invalid).success, false);
  invalid.coaches = [
    coach,
    { ...coach, id: randomUUID(), phone: "+919876543210" },
  ];
  assert.equal(poolConfigurationSchema.safeParse(invalid).success, false);
  const foreign = { ...c, coaches: [], plans: c.plans.map((p) => ({ ...p })) };
  await assert.rejects(() =>
    service.configure(owner, id, { version: 2, configuration: foreign }),
  );
});
test("direct coach spaces are validated and constrain coaching-plan assignment", async () => {
  const { owner, id } = await fixture();
  const c = configuration();
  const coach = {
    id: randomUUID(),
    name: "Pool Coach",
    phone: "9876543212",
    pool_ids: [c.pools[0].id],
  };
  c.coaches = [coach];
  const members = (await workspace.team(owner)).members.length;
  await service.configure(owner, id, { version: 1, configuration: c });
  let b = (await workspace.workspace(owner)).businesses.find(
    (b: any) => b.id === id,
  );
  assert.deepEqual(b.configuration.coaches[0].pool_ids, [c.pools[0].id]);
  assert.equal((await workspace.team(owner)).members.length, members);
  const bad = structuredClone(c);
  bad.coaches![0].pool_ids = [randomUUID()];
  assert.equal(poolConfigurationSchema.safeParse(bad).success, false);
  bad.coaches![0].pool_ids = [c.pools[0].id, c.pools[0].id];
  assert.equal(poolConfigurationSchema.safeParse(bad).success, false);
  c.plans[1].coach_id = coach.id;
  c.plans[1].pool_ids = c.pools.map((p) => p.id);
  await assert.rejects(() =>
    service.configure(owner, id, { version: 2, configuration: c }),
  );
  coach.pool_ids = c.pools.map((p) => p.id);
  await service.configure(owner, id, { version: 2, configuration: c });
  coach.pool_ids = [];
  assert.equal(poolConfigurationSchema.safeParse(c).success, false);
  c.plans[1].coach_id = null;
  await service.configure(owner, id, { version: 3, configuration: c });
  b = (await workspace.workspace(owner)).businesses.find(
    (b: any) => b.id === id,
  );
  assert.deepEqual(b.configuration.coaches[0].pool_ids, []);
  assert.equal(b.configuration.plans[1].coach_id, null);
  await assert.rejects(() =>
    service.configure(owner, id, { version: 3, configuration: c }),
  );
});
test("pool group packages enforce exact/up-to sizes with one total price", () => {
  const c = configuration(),
    o = c.group_offers[0],
    p = c.pools[0];
  assert.equal(
    poolGroupPrice(c, o.id, p.id, "2026-10-17", "09:00", 10),
    250000,
  );
  assert.equal(poolGroupPrice(c, o.id, p.id, "2026-10-17", "09:00", 16), null);
  o.group_mode = "exact";
  assert.equal(poolGroupPrice(c, o.id, p.id, "2026-10-17", "09:00", 10), null);
  assert.equal(
    poolGroupPrice(c, o.id, p.id, "2026-10-17", "09:00", 15),
    250000,
  );
});
test("at-least pool offers accept the minimum and above at one total price within capacity", () => {
  const c = configuration(),
    o = c.group_offers[0],
    p = c.pools[0];
  o.group_mode = "at_least";
  poolConfigurationSchema.parse(c);
  for (const people of [15, 16, 20]) {
    assert.equal(
      poolGroupPrice(c, o.id, p.id, "2026-10-17", "09:00", people),
      250000,
    );
  }
  for (const people of [0, 14, 21, 15.5]) {
    assert.equal(
      poolGroupPrice(c, o.id, p.id, "2026-10-17", "09:00", people),
      null,
    );
  }
  o.people = 21;
  assert.equal(poolConfigurationSchema.safeParse(c).success, false);
});
test("pool validation rejects invalid depth, overlapping rates, excess group/class size and expired plans", () => {
  const c = configuration();
  let x = structuredClone(c);
  x.pools[0].depth_min_ft = 7;
  assert.equal(poolConfigurationSchema.safeParse(x).success, false);
  x = structuredClone(c);
  x.pools[0].tariffs.push({
    ...structuredClone(x.pools[0].tariffs[0]),
    id: randomUUID(),
  });
  assert.equal(poolConfigurationSchema.safeParse(x).success, false);
  x = structuredClone(c);
  x.group_offers[0].people = 21;
  assert.equal(poolConfigurationSchema.safeParse(x).success, false);
  x = structuredClone(c);
  x.plans[1].class_seats = 21;
  assert.equal(poolConfigurationSchema.safeParse(x).success, false);
  x = structuredClone(c);
  x.plans[1].expiry_date = "2025-12-31";
  assert.throws(() => assertPoolComplete(x, "2026-10-14"));
  x = structuredClone(c);
  x.pools[0].depth_min_ft = null;
  poolConfigurationSchema.parse(x);
  assert.throws(() => assertPoolComplete(x));
  const renewal = structuredClone(c) as any;
  renewal.plans[0].renewal = "monthly";
  assert.equal(poolConfigurationSchema.safeParse(renewal).success, false);
});
test("pool tenant/version guards and pending staff scopes prevent partial writes", async () => {
  const first = await fixture(),
    second = await fixture(),
    c = configuration();
  await service.configure(first.owner, first.id, {
    version: 1,
    configuration: c,
  });
  await assert.rejects(() =>
    service.configure(first.owner, first.id, {
      version: 1,
      configuration: configuration(),
    }),
  );
  await assert.rejects(() =>
    service.configure(second.owner, first.id, { version: 2, configuration: c }),
  );
  await assert.rejects(() =>
    service.configure(second.owner, second.id, {
      version: 1,
      configuration: c,
    }),
  );
  assert.equal(
    (await workspace.workspace(second.owner)).businesses[0].resources.length,
    0,
  );
  const invite = await workspace.invite(first.owner, {
    email: actor().email,
    display_name: "Pool staff",
    role: "staff",
    permissions: ["view_bookings"],
    assignments: [{ business_id: first.id, resource_ids: [c.pools[0].id] }],
  });
  await assert.rejects(() =>
    service.configure(first.owner, first.id, {
      version: 2,
      configuration: configuration(),
    }),
  );
  assert.equal(
    (await workspace.workspace(first.owner)).businesses[0].version,
    2,
  );
  await workspace.revoke(first.owner, invite.id, true);
  await assert.rejects(() =>
    workspace.configure(first.owner, first.id, {
      version: 2,
      ...hours,
      duration_minutes: 60,
      price_minor: 20000,
      buffer_minutes: 0,
      plan_name: "Wrong legacy",
      validity_days: 30,
      entitlement: "attendance_days",
      visit_limit: 25,
    }),
  );
});
test("pool staff projections and coach permissions stay within assigned pools", async () => {
  const { owner, id } = await fixture(),
    c = configuration();
  const visibleCoach = {
    id: randomUUID(),
    name: "Assigned pool coach",
    phone: "9876543210",
  };
  const hiddenCoach = {
    id: randomUUID(),
    name: "Other pool coach",
    phone: "9876543211",
  };
  const directCoach = {
    id: randomUUID(),
    name: "Direct pool coach",
    phone: "9876543213",
    pool_ids: c.pools.map((p) => p.id),
  };
  c.coaches = [visibleCoach, hiddenCoach, directCoach];
  c.plans[1].coach_id = visibleCoach.id;
  c.plans.push({
    ...structuredClone(c.plans[1]),
    id: randomUUID(),
    pool_ids: [c.pools[1].id],
    coach_id: hiddenCoach.id,
  });
  await service.configure(owner, id, { version: 1, configuration: c });
  const staff = actor();
  const invite = await workspace.invite(owner, {
    email: staff.email,
    display_name: "Coach",
    role: "staff",
    permissions: ["view_bookings"],
    assignments: [{ business_id: id, resource_ids: [c.pools[0].id] }],
  });
  await workspace.accept(
    staff,
    new URL(invite.invitation_url).searchParams.get("token")!,
  );
  const b = (await workspace.workspace(staff)).businesses[0];
  assert.equal(b.configuration.pools.length, 1);
  assert.deepEqual(b.configuration.group_offers[0].pool_ids, [c.pools[0].id]);
  assert.equal(b.resources[0].capacity, 20);
  assert.deepEqual(b.configuration.coaches, [
    visibleCoach,
    { ...directCoach, pool_ids: [c.pools[0].id] },
  ]);
  await assert.rejects(() =>
    service.configure(staff, id, { version: 2, configuration: c }),
  );
  const member = (await workspace.team(owner)).members.find(
    (m: any) => m.user_id === staff.uid,
  );
  c.plans[1].coach_id = member.id;
  await service.configure(owner, id, { version: 2, configuration: c });
  c.plans[1].pool_ids = [c.pools[1].id];
  await assert.rejects(() =>
    service.configure(owner, id, { version: 3, configuration: c }),
  );
  c.plans[1].pool_ids = [c.pools[0].id];
  await workspace.revoke(owner, member.id, false);
  await assert.rejects(() => workspace.activate(owner, id));
  c.plans[1].enabled = false;
  await service.configure(owner, id, { version: 3, configuration: c });
  await workspace.activate(owner, id);
});
test("legacy pool resource identifiers survive adoption of pool_v1", async () => {
  const { owner, id } = await fixture();
  await workspace.addResource(owner, id, {
    name: "Original pool",
    capacity: 20,
  });
  const b = (await workspace.workspace(owner)).businesses[0],
    c = configuration(),
    old = c.pools[0].id;
  c.pools[0].id = b.resources[0].id;
  c.pools[0].name = b.resources[0].name;
  c.group_offers[0].pool_ids = c.group_offers[0].pool_ids.map((x) =>
    x === old ? c.pools[0].id : x,
  );
  for (const p of c.plans)
    p.pool_ids = p.pool_ids.map((x) => (x === old ? c.pools[0].id : x));
  await service.configure(owner, id, { version: b.version, configuration: c });
  assert(
    (await workspace.workspace(owner)).businesses[0].resources.some(
      (r: any) => r.id === b.resources[0].id,
    ),
  );
});

test("invalid active pool edits leave the ready configuration and version intact", async () => {
  const { owner, id } = await fixture(),
    c = configuration();
  await service.configure(owner, id, { version: 1, configuration: c });
  await workspace.activate(owner, id);
  const bad = structuredClone(c);
  bad.plans[1].expiry_date = "2020-01-01";
  await assert.rejects(() =>
    service.configure(owner, id, { version: 3, configuration: bad }),
  );
  const b = (await workspace.workspace(owner)).businesses[0];
  assert.equal(b.status, "ready");
  assert.equal(b.version, 3);
  assert.deepEqual(b.configuration, c);
});
