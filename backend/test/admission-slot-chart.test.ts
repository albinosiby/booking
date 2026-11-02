import "reflect-metadata";
import { before, after, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { PoolService } from "../src/pool/pool.service";
import { BookingService } from "../src/bookings/booking.service";
import { AdmissionService } from "../src/admissions/admission.service";
import { slotLabel } from "../src/bookings/slot-holders";
import { localStamp } from "../src/bookings/booking.inventory";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  workspace = new WorkspaceService(db),
  service = new AdmissionService(db),
  bookings = new BookingService(db, workspace);
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());
async function fixture(
  mode = "fixed",
  kind = "swimming",
  allowance = 2,
  expiryDays = 45,
) {
  const owner = {
    uid: randomUUID(),
    email: randomUUID() + "@example.com",
    name: "Owner",
  };
  await workspace.createOrganization(owner, {
    name: "Admissions test",
    contact_phone: "9876543210",
    currency: "INR",
    location: {
      name: "Pool",
      address_line_1: "Main road",
      address_line_2: null,
      city: "Kochi",
      state_code: "KL",
      country_code: "IN",
      postal_code: "682001",
      timezone: "UTC",
    },
  });
  const w = await workspace.workspace(owner);
  const b = await workspace.createBusiness(owner, {
    name: "Swimming",
    type: "pool",
    location_id: w.locations[0].id,
  });
  const c = JSON.parse(
    readFileSync("examples/pool-configuration.json", "utf8"),
  ).configuration;
  const today = localStamp(Date.now(), "UTC").slice(0, 10);
  // IDs must be independent across fixtures.
  const ids = new Map<string, string>();
  const replace = (v: any): any =>
    typeof v === "string" && /^[a-f0-9-]{36}$/.test(v)
      ? ids.has(v)
        ? ids.get(v)
        : (ids.set(v, randomUUID()), ids.get(v))
      : Array.isArray(v)
        ? v.map(replace)
        : v && typeof v === "object"
          ? Object.fromEntries(
              Object.entries(v).map(([k, x]) => [k, replace(x)]),
            )
          : v;
  const config = replace(c);
  for (const p of config.pools) {
    p.capacity = 2;
    p.operating = {
      ...p.operating,
      all_day: true,
      opens_at: "00:00",
      closes_at: "00:00",
    };
    p.tariffs = [
      {
        id: randomUUID(),
        hours: p.operating,
        rates: [{ duration_minutes: 60, price_minor: 1000 }],
      },
    ];
  }
  config.group_offers = [];
  for (const p of config.plans) {
    p.allowance = allowance;
    if (p.kind === "coaching") p.class_seats = 2;
    p.expiry_mode = "after_start";
    p.expiry_days = expiryDays;
    p.expiry_date = null;
    p.availability = { ...config.pools[0].operating };
  }
  await new PoolService(db, workspace).configure(owner, b.id, {
    version: 1,
    configuration: config,
  });
  await workspace.activate(owner, b.id);
  const plan = config.plans.find((p: any) => p.kind === kind);
  const start = mode === "fixed" ? "2030-06-04" : today;
  const input = {
    business_id: b.id,
    resource_id: config.pools[0].id,
    plan_id: plan.id,
    starts_on: start,
    mode,
    weekdays: mode === "fixed" ? [1, 2, 3, 4, 5, 6, 7] : [],
    time: "09:00",
    duration_minutes: 60,
    customer: { id: null, name: "Swimmer", phone: "9876543210", email: null },
    payments: [],
    renewed_from: null,
  };
  const q = await service.preview(owner, input);
  const command = {
    ...input,
    preview_token: q.preview_token,
    command_key: randomUUID(),
  };
  const created = await service.create(owner, command);
  return { owner, config, input, q, command, id: created.id, today };
}
async function enrol(f: any, name: string, phone: string) {
  const input = {
    ...f.input,
    customer: { id: null, name, phone, email: null },
  };
  const q = await service.preview(f.owner, input);
  return service.create(f.owner, {
    ...input,
    preview_token: q.preview_token,
    command_key: randomUUID(),
  });
}
const chartInput = (f: any) => ({
  business_id: f.input.business_id,
  resource_id: f.input.resource_id,
  plan_id: f.input.plan_id,
  starts_on: f.input.starts_on,
  weekdays: f.input.weekdays,
  duration_minutes: 60,
});

test("slot labels read as local day, date and 12-hour time", () => {
  assert.equal(slotLabel("2030-06-04T09:00"), "Tue, 4 Jun 2030 at 9:00 AM");
  assert.equal(slotLabel("2030-06-09T17:30"), "Sun, 9 Jun 2030 at 5:30 PM");
  assert.equal(slotLabel("2030-06-10T00:15"), "Mon, 10 Jun 2030 at 12:15 AM");
});

test("a full slot names its date and holders when previewing an admission", async () => {
  const f = await fixture();
  await enrol(f, "Rahul", "9876500001");
  await assert.rejects(
    () =>
      service.preview(f.owner, {
        ...f.input,
        customer: { id: null, name: "Arun", phone: "9876500002", email: null },
      }),
    (e: any) => {
      assert.equal(e.status, 409);
      assert.match(e.message, /^Tue, 4 Jun 2030 at 9:00 AM is held by /);
      assert.match(e.message, /Swimmer \(.+ AD-[0-9A-F]{12}\)/);
      assert.match(e.message, /Rahul \(.+ AD-[0-9A-F]{12}\)/);
      assert.match(e.message, /Not enough pool capacity for this interval\.$/);
      return true;
    },
  );
});

test("slot chart marks every term date of a weekly time and lists who holds clashes", async () => {
  const f = await fixture();
  let chart = await service.slotChart(f.owner, chartInput(f));
  assert.deepEqual(chart.dates, ["2030-06-04", "2030-06-05"]);
  assert.equal(chart.slots.length, 48);
  const at = (t: string) => chart.slots.find((s: any) => s.time === t)!;
  assert.equal(at("09:00").status, "available");
  assert.equal(at("09:00").remaining_capacity, 1);
  assert.equal(at("08:30").remaining_capacity, 1);
  assert.equal(at("10:00").remaining_capacity, 2);
  assert.equal(at("10:00").end_time, "11:00");
  assert.equal(at("10:00").session_count, 2);
  assert.equal(at("10:00").capacity, 2);

  await enrol(f, "Rahul", "9876500001");
  chart = await service.slotChart(f.owner, chartInput(f));
  const taken = at("09:00");
  assert.equal(taken.status, "taken");
  assert.equal(taken.clash_count, 2);
  assert.equal(taken.clashes[0].date, "2030-06-04");
  assert.equal(taken.clashes[0].label, "Tue, 4 Jun 2030 at 9:00 AM");
  assert.equal(taken.clashes[0].holder_count, 2);
  const names = taken.clashes[0].holders.map((h: any) => h.name).sort();
  assert.deepEqual(names, ["Rahul", "Swimmer"]);
  for (const h of taken.clashes[0].holders) {
    assert.equal(h.kind, "admission");
    assert.match(h.reference, /^AD-/);
    assert.deepEqual(h.weekdays, [1, 2, 3, 4, 5, 6, 7]);
    assert.equal(typeof h.plan_name, "string");
  }
  // Half an hour either side overlaps the 09:00 sessions too.
  assert.equal(at("08:30").status, "taken");
  assert.equal(at("09:30").status, "taken");
  assert.equal(at("10:00").status, "available");

  // Holders of one dated interval, for the booking slot chart.
  const held = await bookings.slotHolders(f.owner, {
    business_id: f.input.business_id,
    resource_id: f.input.resource_id,
    date: "2030-06-04",
    time: "09:00",
    duration_minutes: 30,
  });
  assert.deepEqual(held.items.map((h: any) => h.name).sort(), [
    "Rahul",
    "Swimmer",
  ]);
  assert.equal(held.items[0].local_start, "2030-06-04T09:00");
  assert.equal(held.items[0].local_end, "2030-06-04T10:00");
  const free = await bookings.slotHolders(f.owner, {
    business_id: f.input.business_id,
    resource_id: f.input.resource_id,
    date: "2030-06-04",
    time: "10:00",
    duration_minutes: 60,
  });
  assert.deepEqual(free.items, []);
});

test("slot chart validates its schedule and is scoped to the organization", async () => {
  const f = await fixture();
  await assert.rejects(
    () => service.slotChart(f.owner, { ...chartInput(f), weekdays: [] }),
    /weekdays|Too small|at least/i,
  );
  await assert.rejects(
    () => service.slotChart(f.owner, { ...chartInput(f), weekdays: [2, 2] }),
    /unique weekdays/,
  );
  await assert.rejects(
    () =>
      service.slotChart(f.owner, { ...chartInput(f), starts_on: "2020-01-01" }),
    /activation date/,
  );
  const outsider = { uid: randomUUID(), email: "x@example.com", name: "X" };
  await assert.rejects(
    () => service.slotChart(outsider, chartInput(f)),
    /access/,
  );
  await assert.rejects(
    () =>
      bookings.slotHolders(outsider, {
        business_id: f.input.business_id,
        resource_id: f.input.resource_id,
        date: "2030-06-04",
        time: "09:00",
        duration_minutes: 60,
      }),
    /access|Forbidden|not found/i,
  );
});

test("slot chart for a year of daily sessions stays fast", async () => {
  const f = await fixture("fixed", "swimming", 365, 364);
  const started = Date.now();
  const chart = await service.slotChart(f.owner, chartInput(f));
  const took = Date.now() - started;
  assert.equal(chart.dates.length, 365);
  assert.equal(
    chart.slots.find((s: any) => s.time === "09:00")!.remaining_capacity,
    1,
  );
  assert.ok(took < 10000, `slot chart took ${took} ms`);
  console.log(
    `slot chart: ${chart.dates.length} dates x ${chart.slots.length} times in ${took} ms`,
  );
});
