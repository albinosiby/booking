// Field-value / boundary tests for the Hall module: halls, capacities, hourly tariffs, session and
// full-day packages with weekday / seasonal prices, quote helpers and the configure() service.
import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { HttpException } from "@nestjs/common";
import { ZodError } from "zod";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { HallService } from "../src/hall/hall.service";
import { Actor } from "../src/common/auth.guard";
import {
  hallConfigurationSchema,
  hallSaveSchema,
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
const isClient = (e: any) =>
  e instanceof ZodError ||
  (e instanceof HttpException && e.getStatus() < 500) ||
  e?.code === "23505";
async function bad(fn: () => Promise<unknown>, label = "") {
  let threw: any;
  try {
    await fn();
  } catch (e) {
    threw = e;
  }
  assert.ok(threw, `expected rejection ${label}`);
  assert.ok(
    isClient(threw),
    `expected 4xx, got ${threw?.code ?? threw?.name}: ${threw?.message} ${label}`,
  );
  return threw;
}
const hours = {
  days: [1, 2, 3, 4, 5, 6, 7],
  opens_at: "06:00",
  closes_at: "00:00",
  date_from: null as string | null,
  date_until: null as string | null,
};
const option = (
  name: string,
  opens: string,
  closes: string,
  price: number | null,
) => ({
  id: randomUUID(),
  name,
  enabled: true,
  hours: { ...structuredClone(hours), opens_at: opens, closes_at: closes },
  prices: [
    {
      id: randomUUID(),
      days: [1, 2, 3, 4, 5, 6, 7],
      date_from: null as string | null,
      date_until: null as string | null,
      price_minor: price,
    },
  ],
});
function base(): any {
  return {
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
  };
}
type Case = [string, (c: any) => void];
function sweep(cases: Case[], expectValid: boolean) {
  const failures: string[] = [];
  for (const [label, mutate] of cases) {
    const c = base();
    let ok: boolean,
      why = "";
    try {
      mutate(c);
      const r = hallConfigurationSchema.safeParse(c);
      ok = r.success;
      if (!r.success) why = r.error.issues.map((i) => i.message).join("|");
    } catch (e: any) {
      ok = false;
      why = "threw " + e?.message;
    }
    if (ok !== expectValid)
      failures.push(
        `${expectValid ? "rejected valid" : "accepted invalid"}: ${label} ${why}`,
      );
  }
  assert.deepEqual(failures, []);
}
const set =
  (path: (string | number)[], value: any): Case[1] =>
  (c) => {
    let o = c;
    for (const p of path.slice(0, -1)) o = o[p];
    o[path[path.length - 1]] = value;
  };
const gen = (name: string, path: (string | number)[], values: any[]): Case[] =>
  values.map(
    (v) =>
      [
        `${name}=${typeof v === "number" && !Number.isFinite(v) ? String(v) : JSON.stringify(v)}`,
        set(path, v),
      ] as Case,
  );
const H0 = (...r: (string | number)[]) => ["halls", 0, ...r];

test("hall identity: name, environment, amenities, enabled flags", () => {
  sweep(
    [
      ...gen("name", H0("name"), ["", " ", "a", "h".repeat(101), null, 5]),
      ["duplicate hall names", (c) => (c.halls[1].name = c.halls[0].name)],
      [
        "duplicate hall names, different case",
        (c) => (c.halls[1].name = c.halls[0].name.toUpperCase()),
      ],
      ["duplicate hall ids", (c) => (c.halls[1].id = c.halls[0].id)],
      ...gen("environment", H0("environment"), ["", "covered", "Indoor", null]),
      ...gen("amenities", H0("amenities"), ["a".repeat(1001), null, 5, []]),
      ...gen("enabled", H0("enabled"), ["true", 1, null]),
      ...gen("hourly_enabled", H0("hourly_enabled"), ["true", 0, null]),
      [
        "51 halls",
        (c) =>
          (c.halls = Array.from({ length: 51 }, (_, i) => ({
            ...structuredClone(c.halls[0]),
            id: randomUUID(),
            name: "H" + i + "x",
          }))),
      ],
      ["unknown hall key", set(H0("extra"), 1)],
      ["wrong kind", set(["kind"], "court_v1")],
      ["schema_version 2", set(["schema_version"], 2)],
      ["unknown top key", set(["extra"], 1)],
      ["pricing_basis", set(H0("pricing_basis"), "hourly")],
    ],
    false,
  );
  sweep(
    [
      ...gen("name", H0("name"), [
        "ab",
        "h".repeat(100),
        "Ünï Hall 名前 🎉",
        "Hall'); DROP TABLE resources;--",
      ]),
      ...gen("amenities", H0("amenities"), [
        "",
        " ",
        "a".repeat(1000),
        "AC, Ünï 😀",
      ]),
      ["no halls (draft)", set(["halls"], [])],
      ["unspecified environment", set(H0("environment"), "unspecified")],
      [
        "50 halls",
        (c) =>
          (c.halls = Array.from({ length: 50 }, (_, i) => ({
            ...structuredClone(c.halls[0]),
            id: randomUUID(),
            name: "H" + i + "x",
            sessions: c.halls[0].sessions.map((s: any) => ({
              ...s,
              id: randomUUID(),
              prices: s.prices.map((p: any) => ({ ...p, id: randomUUID() })),
            })),
            full_day: {
              ...c.halls[0].full_day,
              id: randomUUID(),
              prices: c.halls[0].full_day.prices.map((p: any) => ({
                ...p,
                id: randomUUID(),
              })),
            },
            tariffs: c.halls[0].tariffs.map((t: any) => ({
              ...t,
              id: randomUUID(),
            })),
          }))),
      ],
    ],
    true,
  );
});
test("hall capacity and seated capacity", () => {
  sweep(
    [
      ...gen("capacity", H0("capacity"), [
        0,
        -1,
        10001,
        1.5,
        NaN,
        Infinity,
        "100",
        null,
        1e9,
      ]),
      ...gen("seated_capacity", H0("seated_capacity"), [
        -1,
        10001,
        0.5,
        NaN,
        Infinity,
        "80",
        null,
      ]),
      [
        "seated > capacity",
        (c) => {
          c.halls[0].capacity = 50;
          c.halls[0].seated_capacity = 51;
        },
      ],
    ],
    false,
  );
  sweep(
    [
      [
        "capacity 1 seated 0",
        (c) => {
          c.halls[0].capacity = 1;
          c.halls[0].seated_capacity = 0;
        },
      ],
      [
        "capacity 1 seated 1",
        (c) => {
          c.halls[0].capacity = 1;
          c.halls[0].seated_capacity = 1;
        },
      ],
      [
        "capacity 10000",
        (c) => {
          c.halls[0].capacity = 10000;
          c.halls[0].seated_capacity = 10000;
        },
      ],
      [
        "seated == capacity",
        (c) => {
          c.halls[0].capacity = 77;
          c.halls[0].seated_capacity = 77;
        },
      ],
    ],
    true,
  );
});
test("hall durations, default duration, buffers and hourly tariff prices", () => {
  const R = H0("tariffs", 0, "rates", 0);
  sweep(
    [
      ...gen(
        "tariff price",
        [...R, "price_minor"],
        [
          -1,
          0.5,
          1000.99,
          0.1 + 0.2,
          NaN,
          Infinity,
          "100",
          true,
          100000001,
          1e21,
          undefined,
        ],
      ),
      ...gen(
        "tariff duration",
        [...R, "duration_minutes"],
        [29, 0, 1441, 60.5, NaN, "60", null],
      ),
      ...gen("buffer_before", H0("buffer_before"), [
        -1,
        241,
        1.5,
        NaN,
        "0",
        null,
      ]),
      ...gen("buffer_after", H0("buffer_after"), [
        -1,
        241,
        1.5,
        NaN,
        "0",
        null,
      ]),
      ...gen("default_duration", H0("default_duration_minutes"), [
        29,
        1441,
        60.5,
        "60",
        null,
        90,
      ]),
      ["no durations", set(H0("durations"), [])],
      [
        "11 durations",
        set(
          H0("durations"),
          Array.from({ length: 11 }, (_, i) => 30 + i * 30),
        ),
      ],
      ["duplicate durations", set(H0("durations"), [60, 60])],
      ["tariff misses a duration", set(H0("durations"), [60, 90])],
      [
        "tariff overlaps",
        (c) => (c.halls[0].tariffs[1].hours.opens_at = "17:00"),
      ],
      [
        "tariff outside operating hours",
        (c) => (c.halls[0].tariffs[0].hours.opens_at = "05:00"),
      ],
      [
        "duplicate tariff ids",
        (c) => (c.halls[0].tariffs[1].id = c.halls[0].tariffs[0].id),
      ],
      [
        "41 tariffs",
        set(
          H0("tariffs"),
          Array.from({ length: 41 }, () => ({
            id: randomUUID(),
            hours: {
              ...hours,
              days: [1],
              opens_at: "06:00",
              closes_at: "07:00",
            },
            rates: [{ duration_minutes: 60, price_minor: 1 }],
          })),
        ),
      ],
      [
        "tariff seasonal without end",
        set(H0("tariffs", 0, "hours", "date_from"), "2026-01-01"),
      ],
    ],
    false,
  );
  sweep(
    [
      ...gen("tariff price", [...R, "price_minor"], [0, 1, 100000000, null]),
      ...gen("buffer_before", H0("buffer_before"), [0, 240]),
      ...gen("buffer_after", H0("buffer_after"), [0, 240]),
      [
        "tariffs ignored when hourly is off",
        (c) => {
          c.halls[0].hourly_enabled = false;
          c.halls[0].tariffs[0].hours.opens_at = "05:00";
        },
      ],
      ["no tariffs", set(H0("tariffs"), [])],
    ],
    true,
  );
});
test("hall operating hours: clock strings, days, no seasonal window", () => {
  const O = (k: string) => H0("operating", k);
  sweep(
    [
      ...gen("days", O("days"), [
        [],
        [0],
        [8],
        [1, 1],
        [1.5],
        ["1"],
        null,
        [1, 2, 3, 4, 5, 6, 7, 1],
      ]),
      ...gen("opens_at", O("opens_at"), [
        "",
        "24:00",
        "6:00",
        "06:60",
        "06:00:00",
        null,
        600,
      ]),
      ...gen("closes_at", O("closes_at"), ["", "24:00", "7", null]),
      ["opens == closes", set(O("closes_at"), "06:00")],
      [
        "operating date window",
        (c) => {
          c.halls[0].operating.date_from = "2026-01-01";
          c.halls[0].operating.date_until = "2026-12-31";
        },
      ],
      ["operating all_day flag is not supported", set(O("all_day"), true)],
    ],
    false,
  );
  sweep(
    [
      [
        "overnight hall",
        (c) => {
          const h = c.halls[0];
          h.operating.opens_at = "18:00";
          h.operating.closes_at = "04:00";
          h.tariffs = [
            {
              id: randomUUID(),
              hours: { ...hours, opens_at: "18:00", closes_at: "04:00" },
              rates: [{ duration_minutes: 60, price_minor: 1 }],
            },
          ];
          h.sessions = [option("Night", "20:00", "02:00", 100)];
          h.full_day = option("Full", "18:00", "04:00", 100);
        },
      ],
      [
        "weekend only",
        (c) => {
          const h = c.halls[0];
          h.operating.days = [6, 7];
          h.tariffs.forEach((t: any) => (t.hours.days = [6, 7]));
          [...h.sessions, h.full_day].forEach((o: any) => {
            o.hours.days = [6, 7];
            o.prices.forEach((p: any) => (p.days = [6, 7]));
          });
        },
      ],
    ],
    true,
  );
});
test("hall packages: names, hours, ids, count and fit within opening hours", () => {
  const S = (i: number, ...r: (string | number)[]) => H0("sessions", i, ...r);
  sweep(
    [
      ...gen("session name", S(0, "name"), [
        "",
        " ",
        "a",
        "n".repeat(101),
        null,
      ]),
      [
        "duplicate session names",
        (c) => (c.halls[0].sessions[1].name = c.halls[0].sessions[0].name),
      ],
      [
        "duplicate session names, other case",
        (c) => (c.halls[0].sessions[1].name = "MORNING"),
      ],
      [
        "duplicate option ids",
        (c) => (c.halls[0].sessions[1].id = c.halls[0].full_day.id),
      ],
      [
        "13 sessions",
        set(
          H0("sessions"),
          Array.from({ length: 13 }, (_, i) =>
            option("S" + i + "x", "09:00", "10:00", 1),
          ),
        ),
      ],
      ["session opens before hall", set(S(0, "hours", "opens_at"), "05:00")],
      [
        "session closes after hall (overnight not allowed)",
        set(S(0, "hours", "closes_at"), "01:00"),
      ],
      [
        "session on a closed day",
        (c) => {
          c.halls[0].operating.days = [1, 2, 3];
          c.halls[0].tariffs.forEach((t: any) => (t.hours.days = [1, 2, 3]));
        },
      ],
      ["session opens == closes", set(S(0, "hours", "closes_at"), "09:00")],
      [
        "session has a date window",
        (c) => {
          c.halls[0].sessions[0].hours.date_from = "2026-01-01";
          c.halls[0].sessions[0].hours.date_until = "2026-02-01";
        },
      ],
      ["session hours bad clock", set(S(0, "hours", "opens_at"), "9:00")],
      ["session enabled string", set(S(0, "enabled"), "yes")],
      [
        "full day outside hours",
        set(H0("full_day", "hours", "opens_at"), "05:00"),
      ],
      ["full day missing", (c) => delete c.halls[0].full_day],
      ["session unknown key", set(S(0, "extra"), 1)],
    ],
    false,
  );
  sweep(
    [
      ["no sessions", set(H0("sessions"), [])],
      [
        "12 sessions",
        set(
          H0("sessions"),
          Array.from({ length: 12 }, (_, i) =>
            option("S" + i + "x", "09:00", "10:00", 1),
          ),
        ),
      ],
      [
        "session spans the full opening window",
        (c) => {
          c.halls[0].sessions[0].hours.opens_at = "06:00";
          c.halls[0].sessions[0].hours.closes_at = "00:00";
        },
      ],
      [
        "overlapping sessions are allowed",
        (c) => {
          c.halls[0].sessions[1].hours.opens_at = "11:00";
        },
      ],
      [
        "disabled session outside hours is not checked",
        (c) => {
          c.halls[0].sessions[0].enabled = false;
          c.halls[0].sessions[0].hours.opens_at = "05:00";
        },
      ],
      ["unicode session name", set(S(0, "name"), "Mañana 朝 🌅")],
    ],
    true,
  );
});
test("hall package prices: bounds, weekdays, seasonal windows and overlaps", () => {
  const P = (...r: (string | number)[]) => H0("full_day", "prices", 0, ...r);
  const price = (extra: Record<string, any>) => ({
    id: randomUUID(),
    days: [1, 2, 3, 4, 5, 6, 7],
    date_from: null,
    date_until: null,
    price_minor: 1,
    ...extra,
  });
  sweep(
    [
      ...gen("price", P("price_minor"), [
        -1,
        0.5,
        1800000.5,
        0.1 + 0.2,
        NaN,
        Infinity,
        "1800000",
        true,
        100000001,
        Number.MAX_SAFE_INTEGER,
        1e21,
        undefined,
      ]),
      ...gen("days", P("days"), [
        [],
        [0],
        [8],
        [1, 1],
        [1.5],
        ["1"],
        null,
        [1, 2, 3, 4, 5, 6, 7, 1],
      ]),
      [
        "price day not in package hours",
        (c) => {
          c.halls[0].full_day.hours.days = [1, 2, 3];
        },
      ],
      ["date_from without date_until", set(P("date_from"), "2026-01-01")],
      ["date_until without date_from", set(P("date_until"), "2026-01-01")],
      [
        "inverted window",
        (c) => {
          c.halls[0].full_day.prices[0].date_from = "2026-12-31";
          c.halls[0].full_day.prices[0].date_until = "2026-01-01";
        },
      ],
      ...gen("date_from", P("date_from"), [
        "2026-02-30",
        "26-01-01",
        "",
        "today",
        20260101,
        "2026-01-01T00:00:00Z",
      ]),
      [
        "duplicate price ids",
        (c) =>
          c.halls[0].full_day.prices.push({ ...c.halls[0].full_day.prices[0] }),
      ],
      [
        "overlapping default prices",
        (c) => c.halls[0].full_day.prices.push(price({ days: [1] })),
      ],
      [
        "overlapping seasonal prices",
        (c) => {
          c.halls[0].full_day.prices.push(
            price({
              days: [6, 7],
              date_from: "2026-12-01",
              date_until: "2026-12-31",
            }),
            price({
              days: [7],
              date_from: "2026-12-31",
              date_until: "2027-01-02",
            }),
          );
        },
      ],
      [
        "41 prices",
        set(
          H0("full_day", "prices"),
          Array.from({ length: 41 }, (_, i) =>
            price({
              days: [1],
              date_from: `2026-01-${String((i % 28) + 1).padStart(2, "0")}`,
              date_until: `2026-01-${String((i % 28) + 1).padStart(2, "0")}`,
            }),
          ),
        ),
      ],
      ["price unknown key", set(P("extra"), 1)],
    ],
    false,
  );
  sweep(
    [
      ...gen("price", P("price_minor"), [0, 1, 99999999, 100000000, null]),
      [
        "weekday vs weekend prices",
        (c) => {
          c.halls[0].full_day.prices[0].days = [1, 2, 3, 4, 5];
          c.halls[0].full_day.prices.push(price({ days: [6, 7] }));
        },
      ],
      [
        "seasonal override on same days",
        (c) =>
          c.halls[0].full_day.prices.push(
            price({
              date_from: "2026-12-24",
              date_until: "2026-12-26",
              price_minor: 3000000,
            }),
          ),
      ],
      [
        "single-day seasonal window",
        (c) =>
          c.halls[0].full_day.prices.push(
            price({ date_from: "2026-12-25", date_until: "2026-12-25" }),
          ),
      ],
      [
        "leap day window",
        (c) =>
          c.halls[0].full_day.prices.push(
            price({ date_from: "2028-02-29", date_until: "2028-02-29" }),
          ),
      ],
      [
        "no prices on a disabled package",
        (c) => {
          c.halls[0].full_day.enabled = false;
          c.halls[0].full_day.prices = [];
        },
      ],
    ],
    true,
  );
  sweep(
    [
      [
        "non-leap Feb 29",
        (c) =>
          c.halls[0].full_day.prices.push(
            price({ date_from: "2027-02-29", date_until: "2027-02-29" }),
          ),
      ],
    ],
    false,
  );
});
test("hall completeness for activation", () => {
  assert.ok(assertHallComplete(base()));
  const none = base();
  none.halls.forEach((h: any) => (h.enabled = false));
  assert.throws(() => assertHallComplete(none), /Enable at least one hall/);
  const unpricedHourly = base();
  unpricedHourly.halls[0].tariffs[0].rates[0].price_minor = null;
  assert.throws(
    () => assertHallComplete(unpricedHourly),
    /Complete hall prices/,
  );
  const noTariffs = base();
  noTariffs.halls[0].tariffs = [];
  assert.throws(() => assertHallComplete(noTariffs), /Complete hall prices/);
  const unpricedPackage = base();
  unpricedPackage.halls[0].full_day.prices[0].price_minor = null;
  assert.throws(
    () => assertHallComplete(unpricedPackage),
    /Complete enabled session and full-day prices/,
  );
  const noPrices = base();
  noPrices.halls[0].sessions[0].prices = [];
  assert.throws(
    () => assertHallComplete(noPrices),
    /Complete enabled session and full-day prices/,
  );
  const noOption = base();
  const h = noOption.halls[0];
  h.hourly_enabled = false;
  h.full_day.enabled = false;
  h.sessions.forEach((s: any) => (s.enabled = false));
  assert.throws(
    () => assertHallComplete(noOption),
    /at least one booking option/,
  );
  const free = base();
  free.halls[0].full_day.prices[0].price_minor = 0;
  assert.ok(assertHallComplete(free));
  const tooLong = base();
  tooLong.halls[0].operating = {
    ...hours,
    opens_at: "10:00",
    closes_at: "10:30",
  };
  tooLong.halls[0].tariffs = [
    {
      id: randomUUID(),
      hours: { ...hours, opens_at: "10:00", closes_at: "10:30" },
      rates: [{ duration_minutes: 60, price_minor: 1 }],
    },
  ];
  tooLong.halls[0].sessions = [];
  tooLong.halls[0].full_day = option("Full day", "10:00", "10:30", 1);
  assert.throws(() => assertHallComplete(tooLong), /valid durations/);
  assert.throws(() => assertHallComplete(null));
  for (const v of [
    null,
    undefined,
    5,
    "x",
    [],
    { version: 1 },
    { configuration: base() },
    { version: 1, configuration: base(), extra: 1 },
  ])
    assert.equal(hallSaveSchema.safeParse(v).success, false, JSON.stringify(v));
});
test("hall quotes: garbage inputs return null; money is exact; zero price is a real price", () => {
  const c = hallConfigurationSchema.parse(base()),
    h = c.halls[0];
  const hourly = (date: string, time: string, d: number, id = h.id) =>
    hallHourlyPriceAtStart(c, id, date, time, d);
  assert.equal(hourly("2026-10-14", "10:00", 60), 100000);
  assert.equal(hourly("2026-10-14", "18:00", 60), 150000);
  assert.equal(hourly("2026-10-14", "10:00", 75), 125000);
  for (const [date, time, d] of [
    ["2026-02-30", "10:00", 60],
    ["", "10:00", 60],
    ["2026-10-14", "24:00", 60],
    ["2026-10-14", "10:60", 60],
    ["2026-10-14", "", 60],
    ["2026-10-14", "10:00", 0],
    ["2026-10-14", "10:00", -60],
    ["2026-10-14", "10:00", 59],
    ["2026-10-14", "10:00", 60.5],
    ["2026-10-14", "10:00", NaN],
    ["2026-10-14", "10:00", Infinity],
    ["2026-10-14", "10:00", 1441],
    ["2026-10-14", "05:59", 60],
    ["2026-10-14", "23:30", 60],
    ["'; DROP", "10:00", 60],
  ] as [string, string, number][])
    assert.equal(hourly(date, time, d), null, `${date} ${time} ${d}`);
  assert.equal(hourly("2026-10-14", "10:00", 60, randomUUID()), null);
  const pkg = (date: string, id = h.full_day.id) =>
    hallPackagePrice(c, h.id, id, date);
  assert.equal(pkg("2026-10-14"), 1800000);
  assert.equal(
    hallPackagePrice(c, h.id, h.sessions[0].id, "2026-10-14"),
    500000,
  );
  for (const date of [
    "2026-02-30",
    "",
    "tomorrow",
    "2026-1-1",
    "2026-10-14T00:00:00Z",
  ])
    assert.equal(pkg(date), null, date);
  assert.equal(pkg("2026-10-14", randomUUID()), null);
  assert.equal(
    hallPackagePrice(c, randomUUID(), h.full_day.id, "2026-10-14"),
    null,
  );
  const z = structuredClone(c);
  z.halls[0].full_day.prices[0].price_minor = 0;
  assert.equal(hallPackagePrice(z, h.id, h.full_day.id, "2026-10-14"), 0);
  const n = structuredClone(c);
  n.halls[0].full_day.prices[0].price_minor = null;
  assert.equal(hallPackagePrice(n, h.id, h.full_day.id, "2026-10-14"), null);
  const d = structuredClone(c);
  d.halls[0].full_day.enabled = false;
  assert.equal(hallPackagePrice(d, h.id, h.full_day.id, "2026-10-14"), null);
  const e = structuredClone(c);
  e.halls[0].enabled = false;
  assert.equal(hallPackagePrice(e, h.id, h.full_day.id, "2026-10-14"), null);
  assert.equal(
    hallHourlyPriceAtStart(e, h.id, "2026-10-14", "10:00", 60),
    null,
  );
  const off = structuredClone(c);
  off.halls[0].hourly_enabled = false;
  assert.equal(
    hallHourlyPriceAtStart(off, h.id, "2026-10-14", "10:00", 60),
    null,
  );
});
test("hall package price: a seasonal price wins over the weekday default exactly on its boundary dates", () => {
  const raw = base();
  raw.halls[0].full_day.prices.push({
    id: randomUUID(),
    days: [1, 2, 3, 4, 5, 6, 7],
    date_from: "2026-12-24",
    date_until: "2026-12-26",
    price_minor: 3000000,
  });
  const c = hallConfigurationSchema.parse(raw),
    h = c.halls[0];
  const q = (d: string) => hallPackagePrice(c, h.id, h.full_day.id, d);
  assert.equal(q("2026-12-23"), 1800000);
  assert.equal(q("2026-12-24"), 3000000);
  assert.equal(q("2026-12-26"), 3000000);
  assert.equal(q("2026-12-27"), 1800000);
});

// ------------------------------------------------------------ service level
async function fixture(type = "hall") {
  const uid = randomUUID(),
    owner: Actor = { uid, email: `${uid}@example.com`, name: "Owner" };
  await workspace.createOrganization(owner, {
    name: "Hall Field QA",
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
    name: "Halls",
    type,
    location_id: w.locations[0].id,
  });
  return { owner, id: b.id };
}
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());
test("hall configure: version rules, replay and stale saves", async () => {
  const { owner, id } = await fixture(),
    c = hallConfigurationSchema.parse(base());
  for (const version of [0, -1, 1.5, "1", null, undefined, NaN, Infinity, true])
    await bad(
      () => service.configure(owner, id, { version, configuration: c }),
      String(version),
    );
  await assert.rejects(
    () => service.configure(owner, id, { version: 2, configuration: c }),
    /Reload before saving/,
  );
  assert.equal(
    (await service.configure(owner, id, { version: 1, configuration: c }))
      .version,
    2,
  );
  await assert.rejects(
    () => service.configure(owner, id, { version: 1, configuration: c }),
    /Reload before saving/,
  );
});
test("hall configure: invalid bodies leave resources and version intact", async () => {
  const { owner, id } = await fixture(),
    good = hallConfigurationSchema.parse(base());
  await service.configure(owner, id, { version: 1, configuration: good });
  const snap = async () => {
    const b = (await workspace.workspace(owner)).businesses[0];
    return JSON.stringify({
      v: b.version,
      r: b.resources.map((x: any) => x.id).sort(),
      c: b.configuration,
    });
  };
  const s0 = await snap();
  for (const body of [
    null,
    undefined,
    5,
    "x",
    [],
    {},
    { version: 2 },
    { version: 2, configuration: good, extra: 1 },
    { version: 2, configuration: { ...good, kind: "pool_v1" } },
    {
      version: 2,
      configuration: { ...good, halls: [{ ...good.halls[0], capacity: 0 }] },
    },
  ])
    await bad(
      () => service.configure(owner, id, body),
      JSON.stringify(body)?.slice(0, 70),
    );
  assert.equal(await snap(), s0);
});
test("hall configure: wrong business type, foreign tenant and non-owner are rejected", async () => {
  const { owner, id } = await fixture(),
    c = hallConfigurationSchema.parse(base());
  const court = await fixture("badminton");
  await assert.rejects(
    () =>
      service.configure(court.owner, court.id, {
        version: 1,
        configuration: c,
      }),
    /hall business/i,
  );
  await assert.rejects(
    () => service.configure(court.owner, id, { version: 1, configuration: c }),
    /Business not found/,
  );
  await assert.rejects(
    () =>
      service.configure(owner, randomUUID(), { version: 1, configuration: c }),
    /Business not found/,
  );
  const staff: Actor = {
    uid: randomUUID(),
    email: `${randomUUID()}@example.com`,
    name: "S",
  };
  const m = await workspace.member(owner);
  await db.query(
    `INSERT INTO memberships(id,organization_id,user_id,email,display_name,role,permissions) VALUES($1,$2,$3,$4,'S','staff','["manage_bookings"]')`,
    [randomUUID(), m.organization_id, staff.uid, staff.email],
  );
  await assert.rejects(
    () => service.configure(staff, id, { version: 1, configuration: c }),
    /Only the owner/,
  );
});
test("hall configure: unicode and SQL-looking names persist literally; stolen ids rejected atomically", async () => {
  const a = await fixture(),
    b = await fixture(),
    c = hallConfigurationSchema.parse(base());
  c.halls[0].name = "Hall'); DROP TABLE resources;-- 名前 🎉";
  await service.configure(a.owner, a.id, { version: 1, configuration: c });
  assert.ok(
    (await workspace.workspace(a.owner)).businesses[0].resources.some(
      (r: any) => r.name === c.halls[0].name,
    ),
  );
  const stolen = hallConfigurationSchema.parse(base());
  stolen.halls[0].id = c.halls[0].id;
  await bad(() =>
    service.configure(b.owner, b.id, { version: 1, configuration: stolen }),
  );
  assert.equal((await workspace.workspace(b.owner)).businesses[0].version, 1);
});
test(
  "hall configure: a NUL byte in a hall name is a client error, not a server error",
  { todo: "BUG-4" },
  async () => {
    const { owner, id } = await fixture(),
      c = hallConfigurationSchema.parse(base());
    c.halls[0].name = "Bad\u0000Hall";
    await bad(() =>
      service.configure(owner, id, { version: 1, configuration: c }),
    );
  },
);
test("hall configure: parallel saves at the same version apply exactly once", async () => {
  const { owner, id } = await fixture();
  const r = await Promise.allSettled(
    [1, 2, 3].map(() =>
      service.configure(owner, id, {
        version: 1,
        configuration: hallConfigurationSchema.parse(base()),
      }),
    ),
  );
  assert.equal(r.filter((x) => x.status === "fulfilled").length, 1);
  assert.equal((await workspace.workspace(owner)).businesses[0].version, 2);
});
test("hall configure: an active hall rejects an unpriced edit atomically", async () => {
  const { owner, id } = await fixture(),
    c = hallConfigurationSchema.parse(base());
  await service.configure(owner, id, { version: 1, configuration: c });
  await workspace.activate(owner, id);
  const b = (await workspace.workspace(owner)).businesses[0];
  const broken = structuredClone(c);
  broken.halls[0].full_day.prices[0].price_minor = null;
  await assert.rejects(
    () =>
      service.configure(owner, id, {
        version: b.version,
        configuration: broken,
      }),
    /Complete enabled session and full-day prices/,
  );
  const after_ = (await workspace.workspace(owner)).businesses[0];
  assert.equal(after_.version, b.version);
  assert.equal(after_.status, "ready");
});
