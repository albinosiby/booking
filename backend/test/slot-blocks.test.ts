import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { CourtService } from "../src/court/court.service";
import { PoolService } from "../src/pool/pool.service";
import { TurfService } from "../src/turf/turf.service";
import { HallService } from "../src/hall/hall.service";
import { BookingService } from "../src/bookings/booking.service";
import {
  zonedTime,
  buildQuote,
  quoteContext,
} from "../src/bookings/booking.inventory";
import { SlotBlocksService } from "../src/slot-blocks/slot-blocks.service";
import { Actor } from "../src/common/auth.guard";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  workspace = new WorkspaceService(db),
  service = new BookingService(db, workspace),
  courts = new CourtService(db, workspace);
const date = "2030-06-04";
const hours = {
  days: [1, 2, 3, 4, 5, 6, 7],
  opens_at: "06:00",
  closes_at: "00:00",
  date_from: null,
  date_until: null,
};
const actor = (): Actor => {
  const uid = randomUUID();
  return { uid, email: `${uid}@example.com`, name: "Owner" };
};
function example(kind: string) {
  const input = JSON.parse(
    readFileSync(`examples/${kind}-configuration.json`, "utf8"),
  ).configuration;
  const ids = new Map<string, string>();
  function visit(v: any): any {
    if (typeof v === "string" && /^[a-f0-9-]{36}$/.test(v)) {
      if (!ids.has(v)) ids.set(v, randomUUID());
      return ids.get(v);
    }
    if (Array.isArray(v)) return v.map(visit);
    if (v && typeof v === "object")
      return Object.fromEntries(
        Object.entries(v).map(([k, x]) => [k, visit(x)]),
      );
    return v;
  }
  return visit(input);
}
async function fixture(type = "badminton", buffers = false) {
  const owner = actor();
  await workspace.createOrganization(owner, {
    name: "Eden",
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
  const w = await workspace.workspace(owner),
    b = await workspace.createBusiness(owner, {
      name: "Bookings",
      type,
      location_id: w.locations[0].id,
    });
  let config: any;
  if (type === "badminton") {
    config = {
      kind: "court_v1",
      schema_version: 1,
      courts: [1, 2].map((n) => ({
        id: randomUUID(),
        name: `Court ${n}`,
        enabled: true,
        environment: "indoor",
        surface: "",
        operating: hours,
        durations: [60],
        default_duration_minutes: 60,
        buffer_before: buffers ? 10 : 0,
        buffer_after: buffers ? 5 : 0,
        pricing_basis: "start_time",
        tariffs: [
          {
            id: randomUUID(),
            hours: { ...hours, closes_at: "18:00" },
            rates: [{ duration_minutes: 60, price_minor: 50000 }],
          },
          {
            id: randomUUID(),
            hours: { ...hours, opens_at: "18:00" },
            rates: [{ duration_minutes: 60, price_minor: 60000 }],
          },
        ],
      })),
    };
    await courts.configure(owner, b.id, { version: 1, configuration: config });
  } else {
    config = example(type);
    if (buffers) {
      for (const resource of config.offerings ?? config.pools ?? config.halls) {
        resource.buffer_before = 10;
        resource.buffer_after = 5;
      }
    }
    const saver =
      type === "turf"
        ? new TurfService(db, workspace)
        : type === "pool"
          ? new PoolService(db, workspace)
          : new HallService(db, workspace);
    await saver.configure(owner, b.id, { version: 1, configuration: config });
  }
  await workspace.activate(owner, b.id);
  const catalog = await service.catalog(owner),
    business = catalog.businesses[0],
    resource = business.resources[0],
    option = resource.options[0];
  const selection = {
    business_id: b.id,
    resource_id: resource.id,
    option_id: option.id,
    date,
    time: option.fixed_time ?? (type === "turf" ? "07:00" : "09:00"),
    duration_minutes: option.durations[0],
    people: 1,
  };
  return { owner, id: b.id, config, selection, catalog };
}
const payment = (method = "cash", amount = 10000) => ({
  method,
  amount_minor: amount,
  reference: "Manual entry",
  received_at: new Date().toISOString(),
});
async function request(
  f: any,
  selection = f.selection,
  payments: any[] = [],
  owner = f.owner,
) {
  const q = await service.quote(owner, { selection, exclude_booking_id: null });
  return {
    command_key: randomUUID(),
    selection,
    quote_token: q.quote_token,
    customer: {
      id: null,
      name: "Booking Customer",
      phone: "9876543210",
      email: null,
    },
    notes: "Manual booking",
    payments,
  };
}
async function create(
  f: any,
  selection = f.selection,
  payments: any[] = [],
  owner = f.owner,
) {
  return service.create(owner, await request(f, selection, payments, owner));
}
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());

const blocks = new SlotBlocksService(db);
const block = (f: any, extra: any = {}) => ({
  command_key: randomUUID(),
  business_id: f.id,
  resource_ids: [f.selection.resource_id],
  date,
  all_day: false,
  start_time: f.selection.time,
  end_time: "12:00",
  ...extra,
});
test("blocks close capacity across business types and unblock restores it", async () => {
  for (const type of ["badminton", "turf", "pool", "hall"]) {
    const f = await fixture(type),
      input = block(f),
      saved = await blocks.create(f.owner, input);
    assert.deepEqual(await blocks.create(f.owner, input), saved);
    await assert.rejects(
      () =>
        service.quote(f.owner, {
          selection: f.selection,
          exclude_booking_id: null,
        }),
      /blocked/,
    );
    const page = await blocks.list(f.owner, { business_id: f.id, date });
    assert.equal(page.items.length, 1);
    assert.equal(page.items[0].can_unblock, true);
    await blocks.unblock(f.owner, saved.id, {});
    await blocks.unblock(f.owner, saved.id, {});
    await service.quote(f.owner, {
      selection: f.selection,
      exclude_booking_id: null,
    });
    assert.equal(
      (
        await db.query<any>(
          "SELECT count(*)::int n FROM audit_events WHERE entity_id=$1",
          [saved.id],
        )
      ).rows[0].n,
      2,
    );
    assert.equal(
      (
        await db.query<any>(
          "SELECT count(*)::int n FROM bookings WHERE business_id=$1",
          [f.id],
        )
      ).rows[0].n,
      0,
    );
  }
});
test("existing bookings prevent a block; adjacent boundaries remain available", async () => {
  const f = await fixture();
  await create(f);
  await assert.rejects(() => blocks.create(f.owner, block(f)), /booking/i);
  await blocks.create(
    f.owner,
    block(f, { start_time: "10:00", end_time: "11:00" }),
  );
  await service.quote(f.owner, {
    selection: { ...f.selection, time: "11:00" },
    exclude_booking_id: null,
  });
});
test("a block invalidates an earlier quote before booking commit", async () => {
  const f = await fixture(),
    req = await request(f);
  await blocks.create(f.owner, block(f));
  await assert.rejects(() => service.create(f.owner, req), /blocked/);
});
test("all-day and overnight blocks use real next-day intervals", async () => {
  const f = await fixture();
  const overnight = await blocks.create(
    f.owner,
    block(f, { start_time: "23:00", end_time: "03:00" }),
  );
  const row = (
    await db.query<any>(
      "SELECT starts_at,ends_at FROM booking_slot_blocks WHERE id=$1",
      [overnight.id],
    )
  ).rows[0];
  assert.equal(
    Date.parse(row.ends_at) - Date.parse(row.starts_at),
    4 * 3600000,
  );
  assert.equal(
    (await blocks.list(f.owner, { business_id: f.id, date: "2030-06-05" }))
      .items.length,
    1,
  );
  await blocks.unblock(f.owner, overnight.id, {});
  const full = await blocks.create(f.owner, block(f, { all_day: true }));
  const day = (
    await db.query<any>(
      "SELECT starts_at,ends_at FROM booking_slot_blocks WHERE id=$1",
      [full.id],
    )
  ).rows[0];
  assert.equal(
    Date.parse(day.ends_at) - Date.parse(day.starts_at),
    24 * 3600000,
  );
});
test("invalid inputs, reason and cross-organization access are rejected", async () => {
  const f = await fixture(),
    other = await fixture();
  for (const extra of [
    { resource_ids: [randomUUID()] },
    { resource_ids: [f.selection.resource_id, f.selection.resource_id] },
    { reason: "closed" },
    { date: "9999-01-01" },
  ])
    await assert.rejects(() => blocks.create(f.owner, block(f, extra)));
  const saved = await blocks.create(f.owner, block(f));
  await assert.rejects(() =>
    blocks.list(other.owner, { business_id: f.id, date }),
  );
  await assert.rejects(() => blocks.unblock(other.owner, saved.id, {}));
  await assert.rejects(() =>
    blocks.create(
      f.owner,
      block(f, { command_key: saved.id, end_time: "13:00" }),
    ),
  );
});
test("slot grid marks booked, blocked and available half hours of the selected spaces", async () => {
  const f = await fixture();
  await create(f);
  await blocks.create(
    f.owner,
    block(f, { start_time: "10:00", end_time: "12:00" }),
  );
  const grid = await blocks.slots(f.owner, {
    business_id: f.id,
    date,
    resource_ids: f.selection.resource_id,
  });
  const status = Object.fromEntries(
    grid.slots.map((s: any) => [s.time, s.status]),
  );
  assert.equal(grid.slots.length, 48);
  assert.equal(grid.step_minutes, 30);
  assert.equal(status["08:30"], "available");
  assert.equal(status["09:00"], "booked");
  assert.equal(status["09:30"], "booked");
  assert.equal(status["10:00"], "blocked");
  assert.equal(status["11:30"], "blocked");
  assert.equal(status["12:00"], "available");
  const other = f.catalog.businesses[0].resources.find(
    (r: any) => r.id !== f.selection.resource_id,
  );
  if (other) {
    const free = await blocks.slots(f.owner, {
      business_id: f.id,
      date,
      resource_ids: other.id,
    });
    assert.ok(free.slots.every((s: any) => s.status === "available"));
  }
  await assert.rejects(() =>
    blocks.slots(f.owner, {
      business_id: f.id,
      date,
      resource_ids: randomUUID(),
    }),
  );
});
test("multi-space blocks close every selected court", async () => {
  const f = await fixture(),
    ids = f.catalog.businesses[0].resources.map((r: any) => r.id);
  await blocks.create(f.owner, block(f, { resource_ids: ids }));
  for (const resource_id of ids)
    await assert.rejects(
      () =>
        service.quote(f.owner, {
          selection: { ...f.selection, resource_id },
          exclude_booking_id: null,
        }),
      /blocked/,
    );
});
test("turf physical sections block both sports and Full Ground while leaving the other half open", async () => {
  const f = await fixture("turf");
  await blocks.create(f.owner, block(f));
  for (const resource of f.catalog.businesses[0].resources) {
    for (const option of resource.options) {
      const selection = {
        ...f.selection,
        resource_id: resource.id,
        option_id: option.id,
      };
      if (resource.id === f.config.layouts[1].id)
        await service.quote(f.owner, { selection, exclude_booking_id: null });
      else
        await assert.rejects(
          () => service.quote(f.owner, { selection, exclude_booking_id: null }),
          /blocked/,
        );
    }
  }
});
test("staff can manage assigned spaces only and cannot unblock a multi-space owner block", async () => {
  const f = await fixture(),
    staff = actor();
  const invite = await workspace.invite(f.owner, {
    email: staff.email,
    display_name: "Staff",
    role: "staff",
    permissions: ["view_bookings", "manage_bookings"],
    assignments: [
      { business_id: f.id, resource_ids: [f.selection.resource_id] },
    ],
  });
  await workspace.accept(
    staff,
    new URL(invite.invitation_url).searchParams.get("token")!,
  );
  await assert.rejects(() =>
    blocks.create(staff, block(f, { resource_ids: [f.config.courts[1].id] })),
  );
  const saved = await blocks.create(
    f.owner,
    block(f, { resource_ids: f.config.courts.map((c: any) => c.id) }),
  );
  const listed = await blocks.list(staff, { business_id: f.id, date });
  assert.equal(listed.items.length, 1);
  assert.equal(listed.items[0].can_unblock, false);
  assert.equal(listed.items[0].spaces.length, 1);
  await assert.rejects(() => blocks.unblock(staff, saved.id, {}));
});
test("rescheduling with a previously issued quote cannot enter a newly blocked interval", async () => {
  const f = await fixture(),
    saved = await create(f),
    detail = await service.detail(f.owner, saved.id);
  const selection = { ...f.selection, time: "13:00" },
    q = await service.quote(f.owner, {
      selection,
      exclude_booking_id: saved.id,
    });
  await blocks.create(
    f.owner,
    block(f, { start_time: "13:00", end_time: "14:00" }),
  );
  await assert.rejects(
    () =>
      service.reschedule(f.owner, saved.id, {
        command_key: randomUUID(),
        version: detail.version,
        selection,
        quote_token: q.quote_token,
        reason: "Move booking",
      }),
    /blocked/,
  );
  assert.deepEqual(
    (await service.detail(f.owner, saved.id)).starts_at,
    detail.starts_at,
  );
});
test("concurrent reservation and block cannot both commit overlapping inventory", async () => {
  const f = await fixture(),
    req = await request(f);
  const results = await Promise.allSettled([
    blocks.create(f.owner, block(f)),
    service.create(f.owner, req),
  ]);
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
  assert.equal(results.filter((r) => r.status === "rejected").length, 1);
});
test("configuration cannot remove inventory while future blocks exist", async () => {
  const f = await fixture();
  await blocks.create(f.owner, block(f));
  const w = await workspace.workspace(f.owner),
    b = w.businesses.find((b: any) => b.id === f.id)!;
  await assert.rejects(
    () =>
      courts.configure(f.owner, f.id, {
        version: b.version,
        configuration: { ...f.config, courts: [f.config.courts[1]] },
      }),
    /Unblock/,
  );
});
