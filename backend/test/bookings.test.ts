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
test("hourly businesses accept 3-hour bookings and half-hour extensions at the start rate", async () => {
  for (const type of ["badminton", "turf", "pool", "hall"]) {
    const f = await fixture(type);
    const base = await service.quote(f.owner, {
      selection: { ...f.selection, duration_minutes: 60 },
      exclude_booking_id: null,
    });
    const long = await service.quote(f.owner, {
      selection: { ...f.selection, duration_minutes: 180 },
      exclude_booking_id: null,
    });
    assert.equal(long.total_minor, base.total_minor * 3, type);
    const half = await service.quote(f.owner, {
      selection: { ...f.selection, duration_minutes: 90 },
      exclude_booking_id: null,
    });
    assert.equal(half.total_minor, Math.round(base.total_minor * 1.5), type);
    for (const duration of [30, 61, 1450]) {
      await assert.rejects(() =>
        service.quote(f.owner, {
          selection: { ...f.selection, duration_minutes: duration },
          exclude_booking_id: null,
        }),
      );
    }
  }
});
test("06:00 to 09:00 occupies the entire court interval", async () => {
  const f = await fixture();
  await create(f, { ...f.selection, time: "06:00", duration_minutes: 180 });
  await assert.rejects(() => create(f, { ...f.selection, time: "08:30" }));
  await create(f, { ...f.selection, time: "09:00" });
});
test("fixed pool group and hall packages keep their configured durations", async () => {
  const pool = await fixture("pool");
  const space = pool.catalog.businesses[0].resources[0];
  const group = space.options.find((o: any) => o.group_mode);
  assert.ok(group);
  assert.equal(group.minimum_duration, null);
  assert.equal(group.durations.length, 1);
  await assert.rejects(() =>
    service.quote(pool.owner, {
      selection: {
        ...pool.selection,
        option_id: group.id,
        duration_minutes: group.durations[0] + 30,
        people: group.group_people,
      },
      exclude_booking_id: null,
    }),
  );
  const hall = await fixture("hall");
  const session = hall.catalog.businesses[0].resources[0].options.find(
    (o: any) => o.fixed_time,
  );
  assert.ok(session);
  assert.equal(session.durations.length, 1);
  await assert.rejects(() =>
    service.quote(hall.owner, {
      selection: {
        ...hall.selection,
        option_id: session.id,
        time: session.fixed_time,
        duration_minutes: session.durations[0] + 30,
      },
      exclude_booking_id: null,
    }),
  );
});
test("finish-time grid enforces the minimum and checks the full selected interval", async () => {
  const f = await fixture();
  await create(f, { ...f.selection, time: "10:00" });
  const ends = await service.availability(f.owner, {
    selection: { ...f.selection, time: "09:00" },
    exclude_booking_id: null,
    end_times: true,
  });
  assert.equal(
    ends.slots.find((s: any) => s.duration_minutes === 30)?.status,
    "minimum",
  );
  assert.equal(
    ends.slots.find((s: any) => s.duration_minutes === 60)?.available,
    true,
  );
  assert.equal(
    ends.slots.find((s: any) => s.duration_minutes === 90)?.available,
    false,
  );
  const early = await service.availability(f.owner, {
    selection: { ...f.selection, time: "06:00" },
    exclude_booking_id: null,
    end_times: true,
  });
  const eight = early.slots.find((s: any) => s.time === "08:00");
  assert.equal(eight?.available, true);
  assert.equal(eight?.duration_minutes, 120);
  const nine = early.slots.find((s: any) => s.time === "09:00");
  assert.equal(nine?.duration_minutes, 180);
  assert.equal(nine?.total_minor, 150000);
  const evening = await service.availability(f.owner, {
    selection: { ...f.selection, time: "23:00" },
    exclude_booking_id: null,
    end_times: true,
  });
  assert.equal(
    evening.slots.find((s: any) => s.time === "00:00")?.available,
    true,
  );
});
test("split cash/UPI/card payment is atomic, exactly-once and visible in scoped totals", async () => {
  const f = await fixture(),
    v = await request(f, f.selection, [
      payment("cash", 10000),
      payment("upi", 20000),
      payment("card", 20000),
    ]);
  const [a, again] = await Promise.all([
    service.create(f.owner, v),
    service.create(f.owner, v),
  ]);
  assert.equal(a.id, again.id);
  const b = await service.detail(f.owner, a.id);
  assert.equal(b.net_paid_minor, 50000);
  assert.equal(b.balance_minor, 0);
  assert.equal(b.payment_status, "paid");
  assert.equal(b.payments.length, 3);
  const p = await service.paymentList(f.owner, {});
  assert.equal(p.items.length, 3);
  assert.equal(
    p.totals.reduce((n: any, p: any) => n + p.total_minor, 0),
    50000,
  );
  await assert.rejects(() =>
    service.create(f.owner, { ...v, notes: "Changed payload" }),
  );
});
test("simultaneous bookings cannot reserve the same court and adjacent slots remain independent", async () => {
  const f = await fixture(),
    a = await request(f),
    b = await request(f);
  const results = await Promise.allSettled([
    service.create(f.owner, a),
    service.create(f.owner, b),
  ]);
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
  await create(f, { ...f.selection, time: "10:00" });
  await create(f, { ...f.selection, resource_id: f.config.courts[1].id });
  const list = await service.list(f.owner, {});
  assert.equal(list.items.length, 3);
});
test("partial split collections, overpayment rejection and payment retry preserve ledger entries", async () => {
  const f = await fixture(),
    { id } = await create(f, f.selection, [
      payment("cash", 10000),
      payment("upi", 20000),
    ]);
  let b = await service.detail(f.owner, id);
  assert.equal(b.payment_status, "partial");
  const v = {
    command_key: randomUUID(),
    version: b.version,
    payments: [payment("card", 20000)],
    kind: "collection",
    reason: "",
  };
  await service.payments(f.owner, id, v);
  await service.payments(f.owner, id, v);
  b = await service.detail(f.owner, id);
  assert.equal(b.payments.length, 3);
  assert.equal(b.balance_minor, 0);
  await assert.rejects(() =>
    service.payments(f.owner, id, {
      ...v,
      command_key: randomUUID(),
      version: b.version,
      payments: [payment("cash", 1)],
    }),
  );
});
test("rescheduling keeps reference/payments and moves reservations atomically; lower prices create refundable credit", async () => {
  const f = await fixture(),
    { id } = await create(f, f.selection, [payment("cash", 50000)]);
  let b = await service.detail(f.owner, id);
  const next = { ...f.selection, time: "19:00" },
    q = await service.quote(f.owner, {
      selection: next,
      exclude_booking_id: id,
    });
  const v = {
    command_key: randomUUID(),
    version: b.version,
    selection: next,
    quote_token: q.quote_token,
    reason: "Customer requested evening",
  };
  await service.reschedule(f.owner, id, v);
  await service.reschedule(f.owner, id, v);
  let updated = await service.detail(f.owner, id);
  assert.equal(updated.reference, b.reference);
  assert.equal(updated.net_paid_minor, 50000);
  assert.equal(updated.balance_minor, 10000);
  await create(f, f.selection);
  await assert.rejects(() => create(f, next));
  const changed = structuredClone(f.config);
  changed.courts[0].tariffs[0].rates[0].price_minor = 30000;
  await courts.configure(f.owner, f.id, { version: 3, configuration: changed });
  await workspace.activate(f.owner, f.id);
  const cheaper = { ...f.selection, date: "2030-06-05" };
  const quote = await service.quote(f.owner, {
    selection: cheaper,
    exclude_booking_id: id,
  });
  await service.reschedule(f.owner, id, {
    command_key: randomUUID(),
    version: updated.version,
    selection: cheaper,
    quote_token: quote.quote_token,
    reason: "Move to next day",
  });
  updated = await service.detail(f.owner, id);
  assert.equal(updated.refund_due_minor, 20000);
  await service.payments(f.owner, id, {
    command_key: randomUUID(),
    version: updated.version,
    payments: [payment("cash", 20000)],
    kind: "refund",
    reason: "Price difference",
  });
  assert.equal((await service.detail(f.owner, id)).refund_due_minor, 0);
});
test("failed reschedule leaves original slot, totals, payments and version untouched", async () => {
  const f = await fixture(),
    a = await create(f),
    target = { ...f.selection, time: "11:00" };
  const q = await service.quote(f.owner, {
    selection: target,
    exclude_booking_id: a.id,
  });
  await create(f, target);
  const before = await service.detail(f.owner, a.id);
  await assert.rejects(() =>
    service.reschedule(f.owner, a.id, {
      command_key: randomUUID(),
      version: before.version,
      selection: target,
      quote_token: q.quote_token,
      reason: "Conflicting move",
    }),
  );
  const after = await service.detail(f.owner, a.id);
  assert.equal(after.version, before.version);
  assert.equal(after.starts_at.toISOString(), before.starts_at.toISOString());
  await assert.rejects(() => create(f));
});
test("turf cross-sport halves share footprints and full ground occupies both halves", async () => {
  const f = await fixture("turf"),
    catalog = await service.catalog(f.owner),
    resources = catalog.businesses[0].resources;
  const half = resources[0],
    other = resources[1],
    full = resources[2];
  await create(f, {
    ...f.selection,
    resource_id: half.id,
    option_id: half.options[0].id,
  });
  await assert.rejects(() =>
    create(f, {
      ...f.selection,
      resource_id: half.id,
      option_id: half.options[1].id,
    }),
  );
  await create(f, {
    ...f.selection,
    resource_id: other.id,
    option_id: other.options[0].id,
  });
  await assert.rejects(() =>
    create(f, {
      ...f.selection,
      resource_id: full.id,
      option_id: full.options[0].id,
    }),
  );
});
test("pool admissions and group offers share capacity over every overlapping subinterval", async () => {
  const f = await fixture("pool");
  await create(f, { ...f.selection, people: 10, time: "09:00" });
  await create(f, { ...f.selection, people: 10, time: "10:00" });
  await assert.rejects(() =>
    create(f, { ...f.selection, people: 15, time: "09:30" }),
  );
  await create(f, { ...f.selection, people: 5, time: "09:30" });
  const opts = (await service.catalog(f.owner)).businesses[0].resources[0]
    .options;
  const group = opts.find((o: any) => o.group_mode);
  if (group)
    await assert.rejects(() =>
      create(f, {
        ...f.selection,
        option_id: group.id,
        people: 15,
        time: "09:00",
        duration_minutes: group.durations[0],
      }),
    );
});
test("hall full-day/session/hourly options reserve one exclusive hall resource", async () => {
  const f = await fixture("hall"),
    p = (await service.catalog(f.owner)).businesses[0].resources[0],
    full = p.options.find((o: any) => o.kind === "full_day");
  await create(f, {
    ...f.selection,
    option_id: full.id,
    time: full.fixed_time,
    duration_minutes: full.durations[0],
  });
  await assert.rejects(() => create(f, { ...f.selection, time: "11:00" }));
  const morning = p.options.find((o: any) => o.kind === "session");
  await assert.rejects(() =>
    create(f, {
      ...f.selection,
      option_id: morning.id,
      time: morning.fixed_time,
      duration_minutes: morning.durations[0],
    }),
  );
});
test("staff scopes and separate booking/payment permissions are authoritative and failed collection rolls back the whole booking", async () => {
  const f = await fixture(),
    staff = actor(),
    invite = await workspace.invite(f.owner, {
      email: staff.email,
      display_name: "Booking staff",
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
    create(
      f,
      { ...f.selection, resource_id: f.config.courts[1].id },
      [],
      staff,
    ),
  );
  await assert.rejects(() => create(f, f.selection, [payment()], staff));
  assert.equal((await service.list(f.owner, {})).items.length, 0);
  const b = await create(f, f.selection, [], staff);
  const hidden = await create(f, {
    ...f.selection,
    resource_id: f.config.courts[1].id,
  });
  await assert.rejects(() => service.detail(staff, hidden.id));
  assert.equal((await service.list(staff, {})).items.length, 1);
  const stranger = await fixture();
  await assert.rejects(() => service.detail(stranger.owner, b.id));
});
test("cancellation releases inventory, records reason and requires a separately recorded refund", async () => {
  const f = await fixture(),
    { id } = await create(f, f.selection, [payment("cash", 50000)]),
    b = await service.detail(f.owner, id);
  await service.status(f.owner, id, {
    command_key: randomUUID(),
    version: b.version,
    status: "cancelled",
    reason: "Customer cancelled",
  });
  const c = await service.detail(f.owner, id);
  assert.equal(c.refund_due_minor, 50000);
  assert.equal(c.payments.length, 1);
  await create(f);
  await assert.rejects(() =>
    service.reschedule(f.owner, id, {
      command_key: randomUUID(),
      version: c.version,
      selection: f.selection,
      quote_token: "0".repeat(64),
      reason: "Invalid cancelled move",
    }),
  );
});
test("cancel then refund supports cash and UPI from the selected account without automatic payouts", async () => {
  for (const method of ["cash", "upi"]) {
    const f = await fixture();
    const org = (
      await db.query<{ organization_id: string }>(
        "SELECT organization_id FROM businesses WHERE id=$1",
        [f.id],
      )
    ).rows[0].organization_id;
    const bank = randomUUID();
    await db.query(
      "INSERT INTO money_accounts(id,organization_id,name,kind,is_primary) VALUES($1,$2,'Refund bank','bank',true)",
      [bank, org],
    );
    const cash = (
      await db.query<{ id: string }>(
        "SELECT id FROM money_accounts WHERE organization_id=$1 AND kind='cash'",
        [org],
      )
    ).rows[0].id;
    const { id } = await create(f, f.selection, [payment("cash", 50000)]);
    const before = await service.detail(f.owner, id);
    await assert.rejects(
      () =>
        service.payments(f.owner, id, {
          command_key: randomUUID(),
          version: before.version,
          kind: "refund",
          payments: [payment(method, 50000)],
          reason: "Refund before cancellation",
        }),
      /refund due/,
    );
    const cancellation = {
      command_key: randomUUID(),
      version: before.version,
      status: "cancelled",
      reason: "Customer cancelled",
    };
    await service.status(f.owner, id, cancellation);
    await service.status(f.owner, id, cancellation);
    const cancelled = await service.detail(f.owner, id);
    assert.equal(cancelled.status, "cancelled");
    assert.equal(cancelled.refund_due_minor, 50000);
    assert.equal(cancelled.payments.length, 1);
    const source = method === "cash" ? cash : bank;
    const refund = {
      command_key: randomUUID(),
      version: cancelled.version,
      kind: "refund",
      payments: [{ ...payment(method, 50000), account_id: source }],
      reason: "Returned to customer",
    };
    await service.payments(f.owner, id, refund);
    await service.payments(f.owner, id, refund);
    const after = await service.detail(f.owner, id);
    assert.equal(after.status, "cancelled");
    assert.equal(after.refund_due_minor, 0);
    assert.equal(after.net_paid_minor, 0);
    assert.equal(after.payments.length, 2);
    assert.equal(
      after.history.filter((h: any) => h.action === "cancelled").length,
      1,
    );
    assert.equal(
      after.history.filter((h: any) => h.action === "refund_recorded").length,
      1,
    );
    const posted = (
      await db.query<{ account_id: string; amount_minor: string }>(
        "SELECT l.account_id,l.amount_minor FROM finance_lines l JOIN finance_events e ON e.id=l.event_id JOIN booking_payments p ON p.id=e.booking_payment_id WHERE p.booking_id=$1 AND p.kind='refund'",
        [id],
      )
    ).rows;
    assert.equal(posted.length, 1);
    assert.equal(posted[0].account_id, source);
    assert.equal(Number(posted[0].amount_minor), -50000);
  }
});
test("changed tariff requires new quote and future bookings protect topology/capacity and history", async () => {
  const f = await fixture(),
    v = await request(f),
    c = structuredClone(f.config);
  c.courts[0].tariffs[0].rates[0].price_minor = 55000;
  await courts.configure(f.owner, f.id, { version: 3, configuration: c });
  await workspace.activate(f.owner, f.id);
  await assert.rejects(() => service.create(f.owner, v));
  await create(f);
  const b = (await workspace.workspace(f.owner)).businesses[0];
  await assert.rejects(() =>
    courts.configure(f.owner, f.id, {
      version: b.version,
      configuration: { ...c, courts: c.courts.slice(1) },
    }),
  );
});
test("timezone conversion rejects nonexistent/ambiguous DST times and keeps India midnight exact", () => {
  assert.equal(
    new Date(zonedTime("2030-06-04", "00:00", "Asia/Kolkata")).toISOString(),
    "2030-06-03T18:30:00.000Z",
  );
  assert.throws(() => zonedTime("2030-03-10", "02:30", "America/New_York"));
  assert.throws(() => zonedTime("2030-11-03", "01:30", "America/New_York"));
});
test("availability excludes only the authorized original booking and calendar filters use location dates", async () => {
  const f = await fixture(),
    { id } = await create(f);
  let slots = await service.availability(f.owner, {
    selection: f.selection,
    exclude_booking_id: null,
  });
  assert.equal(
    slots.slots.find((s: any) => s.time === f.selection.time)?.available,
    false,
  );
  assert.equal(
    slots.slots.find((s: any) => s.time === f.selection.time)?.status,
    "booked",
  );
  slots = await service.availability(f.owner, {
    selection: f.selection,
    exclude_booking_id: id,
  });
  assert.equal(
    slots.slots.find((s: any) => s.time === f.selection.time)?.available,
    true,
  );
  assert.equal(
    (
      await service.list(f.owner, {
        date,
        resource_id: f.selection.resource_id,
      })
    ).items.length,
    1,
  );
  assert.equal(
    (await service.list(f.owner, { date: "2030-06-05" })).items.length,
    0,
  );
  assert.equal(
    (
      await service.list(f.owner, {
        date: "2030-06-01",
        date_until: "2030-06-07",
      })
    ).items.length,
    1,
  );
});
test("collection pagination keeps complete totals and Home separates collections from booking value", async () => {
  const f = await fixture(),
    { id } = await create(f, f.selection, [payment("cash", 1)]);
  let b = await service.detail(f.owner, id);
  for (const count of [20, 20, 20, 20, 20, 4]) {
    await service.payments(f.owner, id, {
      command_key: randomUUID(),
      version: b.version,
      payments: Array.from({ length: count }, () => payment("cash", 1)),
      kind: "collection",
      reason: "",
    });
    b = await service.detail(f.owner, id);
  }
  const first = await service.paymentList(f.owner, {}),
    next = await service.paymentList(f.owner, { cursor: 100 });
  assert.equal(first.items.length, 100);
  assert.equal(next.items.length, 5);
  assert.equal(first.totals[0].total_minor, 105);
  const home = await service.dashboard(f.owner);
  assert.equal(home.today_count, 0);
  assert.equal(home.collected_minor, 105);
  assert.equal(home.booking_value_minor, 0);
  assert.equal(home.outstanding_minor, 49895);
});
test("overnight bookings block next-day calendar/availability intervals using the operating weekday", async () => {
  const f = await fixture(),
    c = structuredClone(f.config);
  c.courts[0].operating = {
    ...hours,
    days: [2],
    opens_at: "22:00",
    closes_at: "02:00",
  };
  c.courts[0].tariffs = [
    {
      id: randomUUID(),
      hours: structuredClone(c.courts[0].operating),
      rates: [{ duration_minutes: 60, price_minor: 50000 }],
    },
  ];
  await courts.configure(f.owner, f.id, { version: 3, configuration: c });
  await workspace.activate(f.owner, f.id);
  const a = await create(f, { ...f.selection, time: "23:30" });
  assert.equal(
    (await service.detail(f.owner, a.id)).local_end,
    "2030-06-05T00:30",
  );
  assert.equal(
    (await service.list(f.owner, { date: "2030-06-05", overlap: "true" })).items
      .length,
    1,
  );
  assert.deepEqual(
    (await service.dateCounts(f.owner, { date, date_until: "2030-06-05" }))
      .items,
    [
      { date, count: 1 },
      { date: "2030-06-05", count: 1 },
    ],
  );
  await assert.rejects(() =>
    create(f, { ...f.selection, date: "2030-06-05", time: "00:00" }),
  );
  await create(f, { ...f.selection, date: "2030-06-05", time: "00:30" });
});
test("simultaneous collectors cannot double-apply a stale balance", async () => {
  const f = await fixture(),
    { id } = await create(f),
    b = await service.detail(f.owner, id);
  const make = () => ({
    command_key: randomUUID(),
    version: b.version,
    payments: [payment("cash", 10000)],
    kind: "collection",
    reason: "",
  });
  const result = await Promise.allSettled([
    service.payments(f.owner, id, make()),
    service.payments(f.owner, id, make()),
  ]);
  assert.equal(result.filter((r) => r.status === "fulfilled").length, 1);
  assert.equal((await service.detail(f.owner, id)).net_paid_minor, 10000);
});
test("future bookings cannot be completed or marked no-show early", async () => {
  const f = await fixture(),
    { id } = await create(f),
    b = await service.detail(f.owner, id);
  for (const status of ["completed", "no_show"])
    await assert.rejects(() =>
      service.status(f.owner, id, {
        command_key: randomUUID(),
        version: b.version,
        status,
        reason: "Too early",
      }),
    );
  assert.equal((await service.detail(f.owner, id)).status, "confirmed");
});
test("per-person multiplication cannot overflow the supported booking total", async () => {
  const f = await fixture("pool"),
    c = structuredClone(f.config);
  for (const t of c.pools[0].tariffs)
    for (const r of t.rates) r.price_minor = 100000000;
  await new PoolService(db, workspace).configure(f.owner, f.id, {
    version: 3,
    configuration: c,
  });
  await workspace.activate(f.owner, f.id);
  await assert.rejects(
    () =>
      service.quote(f.owner, {
        selection: { ...f.selection, people: 2 },
        exclude_booking_id: null,
      }),
    /total exceeds/,
  );
});
test("outstanding view separates unpaid balances from cancellation refunds and respects finance-only scopes", async () => {
  const f = await fixture(),
    a = await create(f, f.selection, [payment("cash", 30000)]),
    b = await create(
      f,
      { ...f.selection, resource_id: f.config.courts[1].id },
      [payment("cash", 50000)],
    );
  const old = await service.detail(f.owner, b.id);
  await service.status(f.owner, b.id, {
    command_key: randomUUID(),
    version: old.version,
    status: "cancelled",
    reason: "Event cancelled",
  });
  let due = await service.outstanding(f.owner, {});
  assert.equal(due.balance_total_minor, 20000);
  assert.equal(due.refund_total_minor, 50000);
  assert.equal(due.items.length, 2);
  assert.equal(due.items[0].customer_phone, "9876543210");
  assert.ok(due.items[0].local_end);
  assert.equal(typeof due.items[0].total_minor, "number");
  const staff = actor(),
    invite = await workspace.invite(f.owner, {
      email: staff.email,
      display_name: "Finance staff",
      role: "staff",
      permissions: ["view_finance"],
      assignments: [
        { business_id: f.id, resource_ids: [f.selection.resource_id] },
      ],
    });
  await workspace.accept(
    staff,
    new URL(invite.invitation_url).searchParams.get("token")!,
  );
  due = await service.outstanding(staff, {});
  assert.equal(due.balance_total_minor, 20000);
  assert.equal(due.refund_total_minor, 0);
  assert.deepEqual(
    due.items.map((p) => p.id),
    [a.id],
  );
  assert.equal((await service.catalog(staff)).can_view, false);
  await assert.rejects(() => service.detail(staff, a.id));
});

test("daily counts aggregate beyond pagination, include zeros and preserve filters and scopes", async () => {
  const f = await fixture();
  const a = await create(f);
  await create(f, { ...f.selection, resource_id: f.config.courts[1].id });
  // Independent reporting fixtures: no inventory writes are needed for aggregate coverage.
  await db.query(
    `INSERT INTO bookings(id,organization_id,business_id,resource_id,customer_id,reference,status,starts_at,ends_at,total_minor,selection,price_snapshot,customer_snapshot,people,created_by)
    SELECT gen_random_uuid(),organization_id,business_id,resource_id,customer_id,reference||'-copy-'||n,status,starts_at,ends_at,total_minor,selection,price_snapshot,customer_snapshot,people,created_by FROM bookings CROSS JOIN generate_series(1,104) n WHERE id=$1`,
    [a.id],
  );
  let counts = await service.dateCounts(f.owner, {
    date,
    date_until: "2030-06-05",
  });
  assert.deepEqual(counts.items, [
    { date, count: 106 },
    { date: "2030-06-05", count: 0 },
  ]);
  counts = await service.dateCounts(f.owner, {
    date,
    date_until: date,
    resource_id: f.selection.resource_id,
    q: "Customer",
  });
  assert.equal(counts.items[0].count, 105);
  assert.equal(
    (
      await service.dateCounts(f.owner, {
        date,
        date_until: date,
        status: "cancelled",
      })
    ).items[0].count,
    0,
  );
  const other = await fixture();
  assert.equal(
    (await service.dateCounts(other.owner, { date, date_until: date })).items[0]
      .count,
    0,
  );
  const staff = actor();
  const invite = await workspace.invite(f.owner, {
    email: staff.email,
    display_name: "Calendar staff",
    role: "staff",
    permissions: ["view_bookings"],
    assignments: [{ business_id: f.id, resource_ids: [f.config.courts[1].id] }],
  });
  await workspace.accept(
    staff,
    new URL(invite.invitation_url).searchParams.get("token")!,
  );
  assert.equal(
    (await service.dateCounts(staff, { date, date_until: date })).items[0]
      .count,
    1,
  );
  assert.equal(
    (
      await service.dateCounts(staff, {
        date,
        date_until: date,
        resource_id: f.selection.resource_id,
      })
    ).items[0].count,
    0,
  );
  await assert.rejects(
    () => service.dateCounts(f.owner, { date, date_until: "2031-06-04" }),
    /1–62 days/,
  );
});

test("availability marks past starts as display-only and quotes still reject them", async () => {
  const f = await fixture();
  const selection = { ...f.selection, date: "2000-06-04" };
  const result = await service.availability(f.owner, {
    selection,
    exclude_booking_id: null,
  });
  assert.ok(result.slots.length > 0);
  assert.ok(
    result.slots.every((s: any) => !s.available && s.status === "past"),
  );
  await assert.rejects(() =>
    service.quote(f.owner, { selection, exclude_booking_id: null }),
  );
});

test("turf catalog provides explicit sports and formats for space cards", async () => {
  const f = await fixture("turf");
  const options = f.catalog.businesses[0].resources.flatMap(
    (p: any) => p.options,
  );
  assert.ok(options.length > 0);
  for (const option of options) {
    const configured = f.config.offerings.find((o: any) => o.id === option.id);
    assert.equal(option.sport, configured.sport);
    assert.equal(option.format, configured.format);
  }
});

test("customer directory groups formatted phones and returns complete paid history", async () => {
  const f = await fixture();
  const ids: string[] = [];
  for (const [time, phone, paid] of [
    ["09:00", "9876543210", 0],
    ["10:00", "98765 43210", 10000],
    ["11:00", "98765-43210", 50000],
  ] as const) {
    const command = await request(
      f,
      { ...f.selection, time },
      paid ? [payment("cash", paid)] : [],
    );
    command.customer.phone = phone;
    ids.push((await service.create(f.owner, command)).id);
  }
  const directory = await service.customerDirectory(f.owner, { q: "98765" });
  assert.equal(directory.items.length, 1);
  assert.equal(directory.items[0].record_count, 3);
  const suggestions = await service.customers(f.owner, "987 654");
  assert.equal(suggestions.items.length, 3);
  assert.equal(new Set(suggestions.items.map((c: any) => c.id)).size, 3);

  const history = await service.customerHistory(
    f.owner,
    directory.items[0].id,
    {},
  );
  assert.equal(history.currency, "INR");
  assert.equal(history.customer.record_count, 3);
  assert.deepEqual(
    history.items.map((b: any) => b.id),
    ids.toReversed(),
  );
  assert.deepEqual(
    history.items.map((b: any) => b.payment_status),
    ["paid", "partial", "unpaid"],
  );
  assert.ok(
    history.items.every(
      (b: any) => b.local_start.includes(date) && b.price_snapshot.space_name,
    ),
  );
  assert.equal(
    (await service.customerDirectory(f.owner, { q: "123" })).items.length,
    0,
  );
  const other = await fixture();
  await assert.rejects(
    () => service.customerHistory(other.owner, directory.items[0].id, {}),
    /Customer not found/,
  );
  await assert.rejects(
    () =>
      service.customerHistory(f.owner, directory.items[0].id, {
        cursor: "broken",
      }),
    /Invalid booking history cursor/,
  );
});

test("customer directory and history respect staff resource assignments", async () => {
  const f = await fixture();
  await create(f);
  const hidden = await request(f, {
    ...f.selection,
    resource_id: f.config.courts[1].id,
  });
  hidden.customer.phone = "9000000000";
  await service.create(f.owner, hidden);
  await create(f, {
    ...f.selection,
    resource_id: f.config.courts[1].id,
    time: "10:00",
  });
  const staff = actor();
  const invite = await workspace.invite(f.owner, {
    email: staff.email,
    display_name: "Customer staff",
    role: "staff",
    permissions: ["view_bookings"],
    assignments: [
      { business_id: f.id, resource_ids: [f.selection.resource_id] },
    ],
  });
  await workspace.accept(
    staff,
    new URL(invite.invitation_url).searchParams.get("token")!,
  );
  const suggestions = await service.customers(staff, "987 654");
  assert.equal(suggestions.items.length, 1);
  assert.equal(suggestions.items[0].phone, "9876543210");
  assert.equal((await service.customers(staff, "90000")).items.length, 0);
  const otherOwner = await fixture();
  assert.equal(
    (await service.customers(otherOwner.owner, "987654")).items.length,
    0,
  );
  const directory = await service.customerDirectory(staff, {});
  assert.equal(directory.items.length, 1);
  assert.equal(directory.items[0].phone, "9876543210");
  assert.equal(directory.items[0].record_count, 1);
  const all = await service.customerDirectory(f.owner, {});
  const inaccessible = all.items.find((c: any) => c.phone === "9000000000")!;
  await assert.rejects(
    () => service.customerHistory(staff, inaccessible.id, {}),
    /Customer not found/,
  );
  assert.equal(
    (await service.customerHistory(staff, directory.items[0].id, {})).items
      .length,
    1,
  );
});

test("customer directory uses bounded pages without duplicate phone groups", async () => {
  const f = await fixture();
  const member = await workspace.workspace(f.owner);
  for (let i = 0; i < 53; i++) {
    await db.query(
      "INSERT INTO customers(id,organization_id,name,phone) VALUES($1,$2,$3,$4)",
      [
        randomUUID(),
        member.organization.id,
        `Customer ${i}`,
        `88888${String(i).padStart(5, "0")}`,
      ],
    );
  }
  const first = await service.customerDirectory(f.owner, { q: "88888" });
  assert.equal(first.items.length, 50);
  assert.ok(first.next);
  const second = await service.customerDirectory(f.owner, {
    q: "88888",
    after: first.next,
  });
  assert.equal(second.items.length, 3);
  assert.equal(second.next, null);
  assert.equal(
    new Set([...first.items, ...second.items].map((c: any) => c.id)).size,
    53,
  );
});

test("customer history cursor retains every booking when start times tie", async () => {
  const f = await fixture();
  const original = await create(f);
  // Archived cancelled bookings need no active allocations; identical starts exercise the UUID tie-breaker.
  for (let i = 0; i < 52; i++) {
    const id = randomUUID();
    await db.query(
      `INSERT INTO bookings(id,organization_id,business_id,resource_id,customer_id,reference,status,starts_at,ends_at,total_minor,selection,price_snapshot,customer_snapshot,people,created_by)
      SELECT $1,organization_id,business_id,resource_id,customer_id,$2,'cancelled',starts_at,ends_at,total_minor,selection,price_snapshot,customer_snapshot,people,created_by FROM bookings WHERE id=$3`,
      [id, `ARCHIVE-${i}`, original.id],
    );
  }
  const customer = (await service.customerDirectory(f.owner, {})).items[0];
  const first = await service.customerHistory(f.owner, customer.id, {});
  assert.equal(first.items.length, 50);
  assert.ok(first.next);
  const last = await service.customerHistory(f.owner, customer.id, {
    cursor: first.next,
  });
  assert.equal(last.items.length, 3);
  assert.equal(last.next, null);
  assert.equal(
    new Set([...first.items, ...last.items].map((b: any) => b.id)).size,
    53,
  );
});

test("cleanup is informational at opening, closing and adjacent historical bookings", async () => {
  const f = await fixture("badminton", true);
  const early = await service.quote(f.owner, {
    selection: { ...f.selection, time: "06:00" },
    exclude_booking_id: null,
  });
  assert.equal(early.occupied_from, early.starts_at);
  assert.equal(early.occupied_until, early.ends_at);
  assert.equal(early.cleanup_minutes, 5);
  await service.quote(f.owner, {
    selection: { ...f.selection, time: "23:00" },
    exclude_booking_id: null,
  });
  const first = await create(f, { ...f.selection, time: "09:30" });
  // Simulate allocations saved by the previous API, with padded buffer times.
  await db.query(
    "UPDATE booking_allocations SET starts_at=starts_at - interval '10 minutes', ends_at=ends_at + interval '5 minutes' WHERE booking_id=$1",
    [first.id],
  );
  await assert.rejects(() =>
    service.quote(f.owner, {
      selection: { ...f.selection, time: "10:00" },
      exclude_booking_id: null,
    }),
  );
  const next = await create(f, { ...f.selection, time: "10:30" });
  assert.ok(next.id);
});

test("all business types ignore preparation and cleanup when reserving adjacent bookings", async () => {
  for (const type of ["badminton", "turf", "pool", "hall"]) {
    const f = await fixture(type, true);
    const q = await service.quote(f.owner, {
      selection: f.selection,
      exclude_booking_id: null,
    });
    assert.equal(q.cleanup_minutes, 5);
    assert.equal(q.occupied_from, q.starts_at);
    assert.equal(q.occupied_until, q.ends_at);
    await create(f);
    const nextTime = new Date(Date.parse(q.ends_at) + 330 * 60000)
      .toISOString()
      .slice(11, 16);
    await create(f, { ...f.selection, time: nextTime });
  }
});

test("request-local slot computation matches authoritative quotes across all business types", async () => {
  for (const type of ["badminton", "turf", "pool", "hall"]) {
    const f = await fixture(type);
    const b = {
      id: f.id,
      name: "Bookings",
      configuration: f.config,
      version: 3,
    };
    const context = quoteContext(b, "Asia/Kolkata");
    for (const time of ["06:00", "09:30", "18:00", "23:00"]) {
      const selection = { ...f.selection, time };
      function result(reuse: boolean) {
        try {
          return buildQuote(
            b,
            selection,
            "Asia/Kolkata",
            Number.NEGATIVE_INFINITY,
            reuse ? context : undefined,
          );
        } catch (error) {
          return { error: (error as Error).message };
        }
      }
      assert.deepEqual(result(true), result(false));
    }
  }
});
test("availability filters selected court inventory without hiding genuine conflicts", async () => {
  const f = await fixture();
  await create(f);
  const blocked = await service.availability(f.owner, {
    selection: f.selection,
    exclude_booking_id: null,
  });
  assert.equal(
    blocked.slots.find((s: any) => s.time === f.selection.time)?.available,
    false,
  );
  const other = f.catalog.businesses[0].resources.find(
    (r: any) => r.id !== f.selection.resource_id,
  );
  const free = await service.availability(f.owner, {
    selection: { ...f.selection, resource_id: other.id },
    exclude_booking_id: null,
  });
  assert.equal(
    free.slots.find((s: any) => s.time === f.selection.time)?.available,
    true,
  );
});

test("narrow availability lookup preserves shared turf footprints and pool capacity", async () => {
  const turf = await fixture("turf");
  const resources = turf.catalog.businesses[0].resources;
  const [half, other, full] = resources;
  await create(turf);
  for (const [resource, optionIndex, available] of [
    [half, 1, false],
    [full, 0, false],
    [other, 0, true],
  ] as const) {
    const result = await service.availability(turf.owner, {
      selection: {
        ...turf.selection,
        resource_id: resource.id,
        option_id: resource.options[optionIndex].id,
      },
      exclude_booking_id: null,
    });
    assert.equal(
      result.slots.find((s: any) => s.time === turf.selection.time)?.available,
      available,
    );
  }
  const pool = await fixture("pool");
  const resource = pool.catalog.businesses[0].resources[0];
  await create(pool, { ...pool.selection, people: resource.capacity });
  const result = await service.availability(pool.owner, {
    selection: pool.selection,
    exclude_booking_id: null,
  });
  assert.equal(
    result.slots.find((s: any) => s.time === pool.selection.time)?.available,
    false,
  );
});

test("unified grid includes closing boundaries and permits an end where the next booking starts", async () => {
  const f = await fixture();
  await create(f, { ...f.selection, time: "10:30" });
  const selection = { ...f.selection, time: "09:30" };
  const start = await service.availability(f.owner, {
    selection,
    exclude_booking_id: null,
  });
  assert.equal(
    start.slots.find((slot: any) => slot.time === "10:30")?.available,
    false,
  );
  assert.ok(
    start.slots.some(
      (slot: any) => slot.time === "23:45" && slot.status === "end_only",
    ),
  );
  assert.ok(
    start.slots.some(
      (slot: any) =>
        slot.time === "00:00" &&
        slot.date === "2030-06-05" &&
        slot.status === "end_only",
    ),
  );
  const end = await service.availability(f.owner, {
    selection,
    end_times: true,
    exclude_booking_id: null,
  });
  assert.equal(
    end.slots.find((slot: any) => slot.time === "10:30")?.available,
    true,
  );
  assert.equal(
    end.slots.find((slot: any) => slot.time === "11:00")?.available,
    false,
  );
});

test("all hourly business types accept 15-minute extensions and expose them as finish choices", async () => {
  for (const type of ["badminton", "turf", "pool", "hall"]) {
    const f = await fixture(type);
    const selection = {
      ...f.selection,
      time: type === "turf" ? "07:00" : "09:00",
    };
    const base = await service.quote(f.owner, {
      selection: { ...selection, duration_minutes: 60 },
      exclude_booking_id: null,
    });
    for (const duration of [75, 105]) {
      const quote = await service.quote(f.owner, {
        selection: { ...selection, duration_minutes: duration },
        exclude_booking_id: null,
      });
      assert.equal(
        quote.total_minor,
        Math.round((base.total_minor * duration) / 60),
      );
    }
    const ends = await service.availability(f.owner, {
      selection,
      end_times: true,
      exclude_booking_id: null,
    });
    for (const duration of [60, 75, 90, 105])
      assert.equal(
        ends.slots.find((s: any) => s.duration_minutes === duration)?.available,
        true,
      );
    await assert.rejects(() =>
      service.quote(f.owner, {
        selection: { ...selection, duration_minutes: 65 },
        exclude_booking_id: null,
      }),
    );
  }
});

test("preloaded ends match fresh end-time checks across all hourly businesses", async () => {
  for (const type of ["badminton", "turf", "pool", "hall"]) {
    const f = await fixture(type);
    const start = await service.availability(f.owner, {
      selection: f.selection,
      exclude_booking_id: null,
    });
    const row = start.slots.find((slot: any) => slot.time === f.selection.time);
    assert.ok(row?.end_options?.length, type);
    const ends = await service.availability(f.owner, {
      selection: f.selection,
      end_times: true,
      exclude_booking_id: null,
    });
    assert.deepEqual(
      row!.end_options,
      ends.slots
        .filter((slot: any) => slot.available)
        .map((slot: any) => [
          slot.duration_minutes,
          `${slot.date}T${slot.time}`,
        ]),
      type,
    );
  }
});
test("preloaded ends stop at the first inventory conflict and final quotes still recheck", async () => {
  const f = await fixture();
  await create(f, { ...f.selection, time: "10:30" });
  const response = await service.availability(f.owner, {
    selection: f.selection,
    exclude_booking_id: null,
  });
  const ends = response.slots.find(
    (slot: any) => slot.time === "09:00",
  )!.end_options;
  assert.deepEqual(
    ends.map((end: any) => end[0]),
    [60, 75, 90],
  );
  // Add a valid booking on the previously free start after the snapshot.
  await create(f, { ...f.selection, time: "09:00" });
  await assert.rejects(() =>
    service.quote(f.owner, {
      selection: { ...f.selection, duration_minutes: 75 },
      exclude_booking_id: null,
    }),
  );
});

test("discounts are signed, persisted and bounded for all business types", async () => {
  for (const type of ["badminton", "turf", "pool", "hall"]) {
    const f = await fixture(type);
    const base = await service.quote(f.owner, {
      selection: f.selection,
      exclude_booking_id: null,
    });
    const selection = {
      ...f.selection,
      discount: { type: "percent", value: 1250, reason: "Regular customer" },
    };
    const q = await service.quote(f.owner, {
      selection,
      exclude_booking_id: null,
    });
    assert.equal(q.subtotal_minor, base.total_minor);
    assert.equal(q.discount_minor, Math.round(base.total_minor * 0.125));
    assert.equal(q.total_minor, base.total_minor - q.discount_minor);
    assert.notEqual(q.quote_token, base.quote_token);
    const fixed = await service.quote(f.owner, {
      selection: {
        ...f.selection,
        discount: { type: "amount", value: 1000, reason: "Offer" },
      },
      exclude_booking_id: null,
    });
    assert.equal(fixed.total_minor, base.total_minor - 1000);
    const free = await service.quote(f.owner, {
      selection: {
        ...f.selection,
        discount: { type: "percent", value: 10000, reason: "Complimentary" },
      },
      exclude_booking_id: null,
    });
    assert.equal(free.total_minor, 0);
    const command = await request(f, selection);
    await assert.rejects(() =>
      service.create(f.owner, {
        ...command,
        selection: {
          ...selection,
          discount: { ...selection.discount, value: 5000 },
        },
      }),
    );
    const created = await service.create(f.owner, command);
    const saved = (
      await db.query(
        "SELECT total_minor,price_snapshot,selection FROM bookings WHERE id=$1",
        [created.id],
      )
    ).rows[0];
    assert.equal(saved.total_minor, q.total_minor);
    assert.equal(saved.price_snapshot.discount_minor, q.discount_minor);
    assert.equal(saved.selection.discount.reason, "Regular customer");
    for (const discount of [
      { type: "amount", value: base.total_minor + 1, reason: "" },
      { type: "percent", value: 10001, reason: "" },
      { type: "amount", value: -1, reason: "" },
    ]) {
      await assert.rejects(() =>
        service.quote(f.owner, {
          selection: { ...f.selection, discount },
          exclude_booking_id: null,
        }),
      );
    }
  }
});

test("check-in is idempotent arrival metadata and keeps balances and inventory unchanged", async () => {
  const f = await fixture(),
    { id } = await create(f),
    before = await service.detail(f.owner, id);
  const input = {
    command_key: randomUUID(),
    version: before.version,
    status: "checked_in",
    reason: "Customer checked in",
  };
  const outsider = await fixture();
  await assert.rejects(() => service.status(outsider.owner, id, input));
  await service.status(f.owner, id, input);
  await service.status(f.owner, id, input);
  const after = await service.detail(f.owner, id);
  assert.equal(after.status, "confirmed");
  assert.equal(after.total_minor, before.total_minor);
  assert.equal(after.balance_minor, before.balance_minor);
  assert.equal(after.net_paid_minor, before.net_paid_minor);
  assert.equal(after.version, before.version + 1);
  assert.equal(
    after.history.filter((e: any) => e.action === "checked_in").length,
    1,
  );
  assert.equal(
    (
      await service.availability(f.owner, {
        selection: f.selection,
        exclude_booking_id: null,
      })
    ).slots.find((s: any) => s.time === f.selection.time)?.available,
    false,
  );
  await assert.rejects(
    () =>
      service.status(f.owner, id, {
        ...input,
        command_key: randomUUID(),
        version: after.version,
      }),
    /already checked in/,
  );
  await assert.rejects(
    () =>
      service.status(f.owner, id, {
        ...input,
        command_key: randomUUID(),
        version: after.version,
        status: "no_show",
      }),
    /cannot be marked no-show/,
  );
  const cancelled = await create(f, { ...f.selection, time: "12:00" });
  await service.status(f.owner, cancelled.id, {
    command_key: randomUUID(),
    version: 1,
    status: "cancelled",
    reason: "Customer cancelled",
  });
  await assert.rejects(
    () =>
      service.status(f.owner, cancelled.id, {
        ...input,
        command_key: randomUUID(),
        version: 2,
      }),
    /final status/,
  );
});

test("booking notification enqueue follows successful command history exactly once", async () => {
  const f = await fixture(),
    command = await request(f);
  const { id } = await service.create(f.owner, command);
  await service.create(f.owner, command);
  let b = await service.detail(f.owner, id);
  const originalStart = b.starts_at;
  const selection = { ...f.selection, time: "11:00" };
  const quote = await service.quote(f.owner, {
    selection,
    exclude_booking_id: id,
  });
  const move = {
    command_key: randomUUID(),
    version: b.version,
    selection,
    quote_token: quote.quote_token,
    reason: "New time",
  };
  await service.reschedule(f.owner, id, move);
  await service.reschedule(f.owner, id, move);
  b = await service.detail(f.owner, id);
  const cancel = {
    command_key: randomUUID(),
    version: b.version,
    status: "cancelled",
    reason: "Changed plans",
  };
  await service.status(f.owner, id, cancel);
  await service.status(f.owner, id, cancel);
  const events = (
    await db.query<{ kind: string; details: any }>(
      "SELECT e.kind,h.details->'notification' AS details FROM booking_notification_events e JOIN booking_history h ON h.id=e.history_id WHERE e.booking_id=$1 ORDER BY e.created_at,e.id",
      [id],
    )
  ).rows;
  assert.deepEqual(events.map((e) => e.kind).sort(), [
    "cancelled",
    "created",
    "rescheduled",
  ]);
  for (const event of events) {
    assert.equal(event.details.customer_name, command.customer.name);
    assert.equal(event.details.space_name, b.price_snapshot.space_name);
    assert.equal(event.details.timezone, b.price_snapshot.timezone);
    assert.equal(
      new Date(event.details.starts_at).getTime(),
      new Date(
        event.kind === "created" ? originalStart : b.starts_at,
      ).getTime(),
    );
  }
});

test("turning a business off rejects stale quotes, keeps collections and restores saved setup", async () => {
  const f = await fixture();
  const existing = await create(f);
  const pending = await request(f, { ...f.selection, time: "12:00" });
  const before = (await workspace.workspace(f.owner)).businesses.find(
    (b: any) => b.id === f.id,
  );
  await workspace.setBookingEnabled(f.owner, f.id, {
    enabled: false,
    version: before.version,
  });
  assert.equal((await service.catalog(f.owner)).businesses.length, 0);
  await assert.rejects(service.create(f.owner, pending), /not ready/i);
  await assert.rejects(
    service.quote(f.owner, {
      selection: f.selection,
      exclude_booking_id: null,
    }),
    /not ready/i,
  );
  await assert.rejects(
    service.availability(f.owner, {
      selection: f.selection,
      exclude_booking_id: null,
    }),
    /not ready/i,
  );
  const detail = await service.detail(f.owner, existing.id);
  await service.payments(f.owner, existing.id, {
    command_key: randomUUID(),
    version: detail.version,
    payments: [payment("cash", 10000)],
    kind: "collection",
    reason: "",
  });
  assert.equal((await service.detail(f.owner, existing.id)).payments.length, 1);
  const off = (await workspace.workspace(f.owner)).businesses.find(
    (b: any) => b.id === f.id,
  );
  assert.equal(off.status, "paused");
  assert.deepEqual(off.configuration, before.configuration);
  assert.deepEqual(off.resources, before.resources);
  await workspace.setBookingEnabled(f.owner, f.id, {
    enabled: true,
    version: off.version,
  });
  assert.equal((await service.catalog(f.owner)).businesses.length, 1);
  assert.equal((await service.detail(f.owner, existing.id)).id, existing.id);
});
