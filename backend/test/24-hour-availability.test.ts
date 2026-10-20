import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { TurfService } from "../src/turf/turf.service";
import { CourtService } from "../src/court/court.service";
import { PoolService } from "../src/pool/pool.service";
import { BookingService } from "../src/bookings/booking.service";
import { buildQuote, zonedTime } from "../src/bookings/booking.inventory";
import {
  assertTurfComplete,
  turfConfigurationSchema,
  turfPriceAtStart,
} from "../src/turf/turf.validation";
import {
  assertCourtComplete,
  courtConfigurationSchema,
  courtPriceAtStart,
} from "../src/court/court.validation";
import {
  assertPoolComplete,
  poolConfigurationSchema,
  poolPriceAtStart,
} from "../src/pool/pool.validation";
import { windowsOverlap } from "../src/common/operating-hours";

delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  workspace = new WorkspaceService(db),
  bookings = new BookingService(db, workspace);
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());
const kinds = ["turf", "court", "pool"] as const;
type Kind = (typeof kinds)[number];
const schemas = {
  turf: turfConfigurationSchema,
  court: courtConfigurationSchema,
  pool: poolConfigurationSchema,
};
const complete = {
  turf: assertTurfComplete,
  court: assertCourtComplete,
  pool: assertPoolComplete,
};
const fullDay = (days = [1, 2, 3, 4, 5, 6, 7]) => ({
  days,
  opens_at: "00:00",
  closes_at: "00:00",
  all_day: true,
  date_from: null,
  date_until: null,
});
function configuration(kind: Kind, days = [1, 2, 3, 4, 5, 6, 7]): any {
  const input = JSON.parse(
    readFileSync(`examples/${kind}-configuration.json`, "utf8"),
  ).configuration;
  const ids = new Map<string, string>();
  function remap(v: any): any {
    if (typeof v === "string" && /^[a-f0-9-]{36}$/.test(v)) {
      if (!ids.has(v)) ids.set(v, randomUUID());
      return ids.get(v);
    }
    if (Array.isArray(v)) return v.map(remap);
    if (v && typeof v === "object")
      return Object.fromEntries(
        Object.entries(v).map(([k, x]) => [k, remap(x)]),
      );
    return v;
  }
  const c = remap(input);
  if (kind === "turf") {
    c.operating = {
      days,
      opens_at: "00:00",
      closes_at: "00:00",
      all_day: true,
    };
    for (const o of c.offerings) {
      o.hours_override = null;
      o.pricing_rules = [
        {
          ...o.pricing_rules[0],
          days,
          starts_at: "00:00",
          ends_at: "00:00",
          all_day: true,
        },
      ];
    }
  } else {
    for (const p of c.courts ?? c.pools) {
      p.operating = fullDay(days);
      p.tariffs = [{ ...p.tariffs[0], hours: fullDay(days) }];
    }
    if (kind === "pool") {
      c.group_offers = [];
      c.plans = [];
    }
  }
  return c;
}
function selection(kind: Kind, c: any) {
  return {
    business_id: randomUUID(),
    resource_id:
      kind === "turf" ? c.layouts[0].id : (c.courts ?? c.pools)[0].id,
    option_id:
      kind === "turf"
        ? c.offerings.find(
            (o: any) => o.layout_id === c.layouts[0].id && o.enabled,
          ).id
        : kind === "court"
          ? "hourly"
          : "regular",
    date: "2030-06-04",
    time: "23:30",
    duration_minutes: 60,
    people: 1,
  };
}
function price(kind: Kind, c: any, day: number, time: string) {
  const s = selection(kind, c),
    date = `2030-06-0${day + 2}`; // Monday is June 3.
  return kind === "turf"
    ? turfPriceAtStart(c, s.option_id, day, time, 60)
    : kind === "court"
      ? courtPriceAtStart(c, s.resource_id, date, time, 60)
      : poolPriceAtStart(c, s.resource_id, date, time, 60);
}
for (const kind of kinds) {
  test(`${kind}: explicit full-day schemas retain legacy equal-time rejection`, () => {
    const c = configuration(kind);
    assert.doesNotThrow(() => complete[kind](c));
    const hours =
      kind === "turf" ? c.operating : (c.courts ?? c.pools)[0].operating;
    delete hours.all_day;
    assert.equal(schemas[kind].safeParse(c).success, false);
    hours.all_day = true;
    hours.opens_at = "06:00";
    assert.equal(schemas[kind].safeParse(c).success, false);
  });
  test(`${kind}: quotes span midnight only on consecutive open days; buffers stay informational`, () => {
    const c = configuration(kind, [2, 3]),
      s = selection(kind, c);
    assert.notEqual(price(kind, c, 2, "23:30"), null);
    const quote = buildQuote(
      {
        id: s.business_id,
        name: "24-hour business",
        version: 1,
        configuration: c,
      },
      s,
      "Asia/Kolkata",
      Date.parse("2029-01-01"),
    );
    assert.equal(quote.local_end, "2030-06-05T00:30");
    assert.equal(price(kind, c, 3, "23:30"), null);
    const p =
      kind === "turf"
        ? c.offerings.find((o: any) => o.id === s.option_id)
        : (c.courts ?? c.pools)[0];
    p.buffer_before = 30;
    assert.notEqual(price(kind, c, 2, "00:00"), null);
    assert.notEqual(price(kind, c, 3, "00:00"), null);
    p.buffer_before = 0;
    p.buffer_after = 15;
    assert.notEqual(price(kind, c, 3, "23:00"), null);
    p.buffer_after = 0;
    assert.notEqual(price(kind, c, 3, "23:00"), null);
    assert.throws(() =>
      buildQuote(
        {
          id: s.business_id,
          name: "Closed Thursday",
          version: 1,
          configuration: c,
        },
        { ...s, date: "2030-06-05" },
        "Asia/Kolkata",
        Date.parse("2029-01-01"),
      ),
    );
  });
  test(`${kind}: full-day configuration saves, activates and creates a midnight booking in an isolated database`, async () => {
    const uid = randomUUID(),
      owner = { uid, email: `${uid}@example.com`, name: "Owner" };
    await workspace.createOrganization(owner, {
      name: "All day QA",
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
      name: "Full-day service",
      type: kind === "court" ? "badminton" : kind,
      location_id: w.locations[0].id,
    });
    const c = configuration(kind);
    const service =
      kind === "turf"
        ? new TurfService(db, workspace)
        : kind === "court"
          ? new CourtService(db, workspace)
          : new PoolService(db, workspace);
    await service.configure(owner, b.id, { version: 1, configuration: c });
    await workspace.activate(owner, b.id);
    const saved = (await workspace.workspace(owner)).businesses[0];
    assert.equal(saved.status, "ready");
    assert.deepEqual(saved.configuration, c);
    const s = { ...selection(kind, c), business_id: b.id };
    const q = await bookings.quote(owner, {
      selection: s,
      exclude_booking_id: null,
    });
    const created = await bookings.create(owner, {
      command_key: randomUUID(),
      selection: s,
      quote_token: q.quote_token,
      customer: {
        id: null,
        name: "QA customer",
        phone: "9876543210",
        email: null,
      },
      notes: "Isolated 24-hour test",
      payments: [],
    });
    const detail = await bookings.detail(owner, created.id);
    assert.equal(detail.local_end, "2030-06-05T00:30");
    await assert.rejects(() =>
      bookings.quote(owner, {
        selection: kind === "pool" ? { ...s, people: c.pools[0].capacity } : s,
        exclude_booking_id: null,
      }),
    );
  });
}
test("full-day pricing checks weekday wrapping and adjacent seasonal dates", () => {
  const a = {
    ...fullDay([1]),
    all_day: false,
    opens_at: "22:00",
    closes_at: "02:00",
    date_from: "2030-06-03",
    date_until: "2030-06-03",
  };
  const b = {
    ...fullDay([2]),
    all_day: false,
    opens_at: "01:00",
    closes_at: "03:00",
    date_from: "2030-06-04",
    date_until: "2030-06-04",
  };
  assert.equal(windowsOverlap(a, b), true);
  assert.equal(windowsOverlap(a, { ...b, opens_at: "02:00" }), false);
  for (const kind of kinds) {
    const c = configuration(kind),
      p = kind === "turf" ? c.offerings[0] : (c.courts ?? c.pools)[0];
    if (kind === "turf")
      p.pricing_rules = [
        {
          ...p.pricing_rules[0],
          days: [1],
          starts_at: "22:00",
          ends_at: "02:00",
          all_day: false,
        },
        {
          ...p.pricing_rules[0],
          id: randomUUID(),
          days: [2],
          starts_at: "01:00",
          ends_at: "03:00",
          all_day: false,
        },
      ];
    else
      p.tariffs = [
        { ...p.tariffs[0], hours: a },
        { ...p.tariffs[0], id: randomUUID(), hours: b },
      ];
    assert.equal(schemas[kind].safeParse(c).success, false);
  }
});

for (const kind of kinds) {
  test(`${kind}: full-day inventory uses actual elapsed time on daylight-saving days`, () => {
    const c = configuration(kind, [7]);
    if (kind === "turf") {
      for (const o of c.offerings) {
        o.rates = o.pricing_rules[0].rates
          .map((r: any) => ({ ...r, duration_minutes: 1440 }))
          .slice(0, 1);
        o.default_duration_minutes = 1440;
        for (const band of o.pricing_rules) band.rates = o.rates;
      }
    } else {
      for (const p of c.courts ?? c.pools) {
        p.durations = [1440];
        p.default_duration_minutes = 1440;
        for (const t of p.tariffs)
          t.rates = [{ duration_minutes: 1440, price_minor: 60000 }];
      }
    }
    assert.doesNotThrow(() => complete[kind](c));
    const s = {
      ...selection(kind, c),
      date: "2030-11-03",
      time: "00:30",
      duration_minutes: 1440,
    };
    const b = {
      id: s.business_id,
      name: "DST check",
      version: 1,
      configuration: c,
    };
    const q = buildQuote(b, s, "America/New_York", Date.parse("2029-01-01"));
    assert.equal(q.local_end, "2030-11-03T23:30");
    assert.throws(() =>
      buildQuote(
        b,
        { ...s, date: "2030-03-10" },
        "America/New_York",
        Date.parse("2029-01-01"),
      ),
    );
    assert.throws(() =>
      buildQuote(
        b,
        { ...s, time: "01:30" },
        "America/New_York",
        Date.parse("2029-01-01"),
      ),
    );
  });
  test(`${kind}: overnight pricing uses the prior weekday under 24-hour opening`, () => {
    const c = configuration(kind),
      p = kind === "turf" ? c.offerings[0] : (c.courts ?? c.pools)[0];
    if (kind === "turf")
      p.pricing_rules = [
        {
          ...p.pricing_rules[0],
          days: [1],
          starts_at: "22:00",
          ends_at: "02:00",
          all_day: false,
        },
      ];
    else
      p.tariffs = [
        {
          ...p.tariffs[0],
          hours: {
            ...fullDay([1]),
            all_day: false,
            opens_at: "22:00",
            closes_at: "02:00",
          },
        },
      ];
    assert.doesNotThrow(() => complete[kind](c));
    assert.notEqual(price(kind, c, 2, "01:00"), null);
    assert.equal(price(kind, c, 2, "02:00"), null);
  });
}
