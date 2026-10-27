// Field-value / boundary tests for the Court module (badminton / tennis / basketball configuration),
// including coaching/play plans, pricing helpers and the configure() service.
import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { HttpException } from "@nestjs/common";
import { ZodError } from "zod";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { CourtService } from "../src/court/court.service";
import { Actor } from "../src/common/auth.guard";
import {
  courtConfigurationSchema,
  courtSaveSchema,
  assertCourtComplete,
  courtPriceAtStart,
} from "../src/court/court.validation";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  workspace = new WorkspaceService(db),
  service = new CourtService(db, workspace);
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
function base(): any {
  const courts = [1, 2].map((n) => ({
    id: randomUUID(),
    name: `Court ${n}`,
    enabled: true,
    environment: "indoor",
    surface: "Synthetic",
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
        rates: [{ duration_minutes: 60, price_minor: 40000 }],
      },
      {
        id: randomUUID(),
        hours: { ...structuredClone(hours), opens_at: "18:00" },
        rates: [{ duration_minutes: 60, price_minor: 60000 }],
      },
    ],
  }));
  return {
    kind: "court_v1",
    schema_version: 1,
    courts,
    plans: [
      {
        id: randomUUID(),
        name: "Play pass",
        kind: "play",
        court_ids: [courts[0].id],
        allowance: 10,
        track_attendance: true,
        expiry_mode: "after_start",
        expiry_days: 30,
        expiry_months: null,
        expiry_years: null,
        expiry_date: null,
        price_minor: 5000,
        enabled: true,
        availability: structuredClone(hours),
        class_duration_minutes: null,
        class_seats: null,
        coach_id: null,
        renewal: "none",
      },
    ],
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
      const r = courtConfigurationSchema.safeParse(c);
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
const C0 = (...rest: (string | number)[]) => ["courts", 0, ...rest];
const P0 = (...rest: (string | number)[]) => ["plans", 0, ...rest];

test("court names: length, whitespace, type, uniqueness (case-insensitive)", () => {
  sweep(
    [
      ...gen("name", C0("name"), [
        "",
        " ",
        "a",
        "x".repeat(101),
        null,
        5,
        undefined,
        [],
        {},
      ]),
      ["duplicate name", (c) => (c.courts[1].name = c.courts[0].name)],
      [
        "duplicate name different case",
        (c) => (c.courts[1].name = c.courts[0].name.toUpperCase()),
      ],
      [
        "duplicate after trim",
        (c) => (c.courts[1].name = "  " + c.courts[0].name + "  "),
      ],
    ],
    false,
  );
  sweep(
    [
      ...gen("name", C0("name"), [
        "ab",
        "x".repeat(100),
        "Ünï Court 名前 🏸",
        "Court'); DROP TABLE resources;--",
        "  padded  ",
      ]),
    ],
    true,
  );
});
test("court fields: environment, surface, enabled, pricing_basis", () => {
  sweep(
    [
      ...gen("environment", C0("environment"), [
        "",
        "Indoor",
        "covered",
        null,
        1,
      ]),
      ...gen("surface", C0("surface"), ["s".repeat(81), null, 5]),
      ...gen("enabled", C0("enabled"), ["true", 1, null, undefined]),
      ...gen("pricing_basis", C0("pricing_basis"), [
        "hourly",
        "",
        null,
        "end_time",
      ]),
      ["unknown court key", set(C0("extra"), 1)],
      ["missing id", (c) => delete c.courts[0].id],
      ...gen("id", C0("id"), ["", "x", 5, null]),
    ],
    false,
  );
  sweep(
    [
      ...gen("environment", C0("environment"), [
        "unspecified",
        "indoor",
        "outdoor",
      ]),
      ...gen("surface", C0("surface"), ["", " ", "s".repeat(80), "Ünï 😀"]),
      [
        "disabled court",
        (c) => {
          c.courts[0].enabled = false;
          c.plans = [];
        },
      ],
    ],
    true,
  );
});
test("court durations, default duration and buffers", () => {
  const rates = (d: number) => (c: any) => {
    c.courts[0].durations = [d];
    c.courts[0].default_duration_minutes = d;
    c.courts[0].tariffs.forEach(
      (t: any) => (t.rates = [{ duration_minutes: d, price_minor: 100 }]),
    );
  };
  sweep(
    [
      ...[29, 0, -30, 1441, 30.5, NaN, Infinity].map(
        (d) => [`duration ${d}`, rates(d)] as Case,
      ),
      ["duration string", (c) => (c.courts[0].durations = ["60"])],
      ["duration null", (c) => (c.courts[0].durations = [null])],
      ["no durations", (c) => (c.courts[0].durations = [])],
      [
        "11 durations",
        (c) => {
          c.courts[0].durations = Array.from(
            { length: 11 },
            (_, i) => 30 + i * 30,
          );
        },
      ],
      ["duplicate durations", (c) => (c.courts[0].durations = [60, 60])],
      ["default not in durations", set(C0("default_duration_minutes"), 90)],
      ...gen("default_duration", C0("default_duration_minutes"), [
        0,
        29,
        1441,
        60.5,
        "60",
        null,
        NaN,
      ]),
      ...gen("buffer_before", C0("buffer_before"), [
        -1,
        241,
        1.5,
        NaN,
        Infinity,
        "5",
        null,
        1e9,
      ]),
      ...gen("buffer_after", C0("buffer_after"), [
        -1,
        241,
        1.5,
        NaN,
        Infinity,
        "5",
        null,
        1e9,
      ]),
      ["tariff misses a duration", (c) => (c.courts[0].durations = [60, 90])],
      [
        "tariff prices a disallowed duration",
        (c) =>
          c.courts[0].tariffs[0].rates.push({
            duration_minutes: 90,
            price_minor: 1,
          }),
      ],
      [
        "tariff rates repeated",
        (c) =>
          c.courts[0].tariffs[0].rates.push({
            duration_minutes: 60,
            price_minor: 1,
          }),
      ],
    ],
    false,
  );
  sweep(
    [
      ...[30, 60].map((d) => [`duration ${d}`, rates(d)] as Case),
      [
        "duration 1440 (no plans)",
        (c) => {
          rates(1440)(c);
          c.plans = [];
        },
      ],
      ...gen("buffer_before", C0("buffer_before"), [0, 1, 240]),
      ...gen("buffer_after", C0("buffer_after"), [0, 1, 240]),
      [
        "10 durations",
        (c) => {
          const d = Array.from({ length: 10 }, (_, i) => 30 + i * 30);
          c.courts[0].durations = d;
          c.courts[0].default_duration_minutes = 30;
          c.courts[0].tariffs.forEach(
            (t: any) =>
              (t.rates = d.map((x) => ({
                duration_minutes: x,
                price_minor: x,
              }))),
          );
        },
      ],
    ],
    true,
  );
});
test("court prices: integers 0..100,000,000 or null; never decimals, NaN, Infinity, strings", () => {
  const P = ["courts", 0, "tariffs", 0, "rates", 0, "price_minor"];
  sweep(
    [
      ...gen("price", P, [
        -1,
        -0.01,
        0.5,
        100.5,
        12.345,
        0.1 + 0.2,
        NaN,
        Infinity,
        -Infinity,
        "400",
        "1e3",
        true,
        100000001,
        Number.MAX_SAFE_INTEGER,
        1e21,
        undefined,
      ]),
      ...gen(
        "duration",
        ["courts", 0, "tariffs", 0, "rates", 0, "duration_minutes"],
        ["60", null, NaN],
      ),
      ["no rates", set(["courts", 0, "tariffs", 0, "rates"], [])],
      [
        "11 rates",
        (c) =>
          (c.courts[0].tariffs[0].rates = Array.from(
            { length: 11 },
            (_, i) => ({ duration_minutes: 30 + i, price_minor: 1 }),
          )),
      ],
      [
        "rate unknown key",
        set(["courts", 0, "tariffs", 0, "rates", 0, "currency"], "INR"),
      ],
    ],
    false,
  );
  sweep([...gen("price", P, [0, 1, 99999999, 100000000, null])], true);
});
test("court operating hours: days, clock strings, all_day and date windows", () => {
  const O = (k: string) => C0("operating", k);
  sweep(
    [
      ...gen("days", O("days"), [
        [],
        [0],
        [8],
        [-1],
        [1.5],
        ["1"],
        [1, 1],
        [1, 2, 3, 4, 5, 6, 7, 1],
        null,
        "1",
        {},
        [NaN],
      ]),
      ...gen("opens_at", O("opens_at"), [
        "",
        "24:00",
        "6:00",
        "06:60",
        "06:00:00",
        " 06:00",
        "0600",
        null,
        600,
        "ab:cd",
      ]),
      ...gen("closes_at", O("closes_at"), ["", "24:00", "7", "12:60", null]),
      [
        "opens == closes",
        (c) =>
          (c.courts[0].operating.closes_at = c.courts[0].operating.opens_at),
      ],
      [
        "all_day with non-midnight",
        (c) => (c.courts[0].operating.all_day = true),
      ],
      ["all_day string", set(O("all_day"), "true")],
      [
        "court operating with date_from",
        (c) => {
          c.courts[0].operating.date_from = "2026-01-01";
          c.courts[0].operating.date_until = "2026-12-31";
        },
      ],
      ["date_from without date_until", set(O("date_from"), "2026-01-01")],
      [
        "inverted dates",
        (c) => {
          c.courts[0].operating.date_from = "2026-12-31";
          c.courts[0].operating.date_until = "2026-01-01";
        },
      ],
      ...gen("date_from", O("date_from"), [
        "2026-02-30",
        "26-01-01",
        "2026-1-1",
        "",
        "today",
        20260101,
        "2026-01-01T00:00:00Z",
        "0000-00-00",
      ]),
    ],
    false,
  );
  sweep(
    [
      ...[[1], [7], [1, 2, 3], [7, 1]].map(
        (d) =>
          [
            `days ${JSON.stringify(d)}`,
            (c: any) => {
              c.courts[0].operating.days = d;
              c.courts[0].tariffs.forEach((t: any) => (t.hours.days = d));
              c.plans = [];
            },
          ] as Case,
      ),
      [
        "24h court",
        (c) => {
          c.courts[0].operating = {
            ...c.courts[0].operating,
            all_day: true,
            opens_at: "00:00",
            closes_at: "00:00",
          };
        },
      ],
      [
        "overnight",
        (c) => {
          c.courts[0].operating.opens_at = "18:00";
          c.courts[0].operating.closes_at = "02:00";
          c.courts[0].tariffs = [
            {
              id: randomUUID(),
              hours: { ...hours, opens_at: "18:00", closes_at: "02:00" },
              rates: [{ duration_minutes: 60, price_minor: 1 }],
            },
          ];
          c.plans = [];
        },
      ],
    ],
    true,
  );
});
test("court tariff windows: within opening hours, no overlap on the same tier, valid seasonal dates", () => {
  sweep(
    [
      [
        "tariff outside court hours",
        (c) => (c.courts[0].tariffs[0].hours.opens_at = "05:00"),
      ],
      [
        "tariff on a day the court is closed",
        (c) => {
          c.courts[0].operating.days = [1, 2, 3];
        },
      ],
      [
        "overlapping default tariffs",
        (c) => (c.courts[0].tariffs[1].hours.opens_at = "17:59"),
      ],
      [
        "duplicate tariff ids",
        (c) => (c.courts[0].tariffs[1].id = c.courts[0].tariffs[0].id),
      ],
      [
        "tariff seasonal date_from without until",
        (c) => (c.courts[0].tariffs[0].hours.date_from = "2026-01-01"),
      ],
      [
        "tariff seasonal inverted",
        (c) => {
          c.courts[0].tariffs[0].hours.date_from = "2026-05-01";
          c.courts[0].tariffs[0].hours.date_until = "2026-04-01";
        },
      ],
      [
        "tariff seasonal Feb 30",
        (c) => {
          c.courts[0].tariffs[0].hours.date_from = "2026-02-30";
          c.courts[0].tariffs[0].hours.date_until = "2026-03-30";
        },
      ],
      [
        "41 tariffs",
        (c) =>
          (c.courts[0].tariffs = Array.from({ length: 41 }, () => ({
            id: randomUUID(),
            hours: {
              ...hours,
              days: [1],
              opens_at: "06:00",
              closes_at: "07:00",
            },
            rates: [{ duration_minutes: 60, price_minor: 1 }],
          }))),
      ],
      ["tariff id not uuid", set(["courts", 0, "tariffs", 0, "id"], "t1")],
      [
        "tariff hours unknown key",
        set(["courts", 0, "tariffs", 0, "hours", "x"], 1),
      ],
    ],
    false,
  );
  sweep(
    [
      [
        "seasonal override same tier different dates",
        (c) =>
          c.courts[0].tariffs.push({
            id: randomUUID(),
            hours: {
              ...hours,
              days: [6, 7],
              closes_at: "18:00",
              date_from: "2026-10-17",
              date_until: "2026-10-18",
            },
            rates: [{ duration_minutes: 60, price_minor: 50000 }],
          }),
      ],
      [
        "adjacent tariffs",
        (c) => (c.courts[0].tariffs[1].hours.opens_at = "18:00"),
      ],
      ["no tariffs on a draft court", (c) => (c.courts[0].tariffs = [])],
      [
        "empty courts array (draft)",
        (c) => {
          c.courts = [];
          c.plans = [];
        },
      ],
      [
        "50 courts",
        (c) => {
          c.courts = Array.from({ length: 50 }, (_, i) => ({
            ...structuredClone(c.courts[0]),
            id: randomUUID(),
            name: "Court " + (i + 10),
            tariffs: [],
          }));
          c.plans = [];
        },
      ],
    ],
    true,
  );
  sweep(
    [
      [
        "51 courts",
        (c) => {
          c.courts = Array.from({ length: 51 }, (_, i) => ({
            ...structuredClone(c.courts[0]),
            id: randomUUID(),
            name: "Court " + (i + 10),
            tariffs: [],
          }));
          c.plans = [];
        },
      ],
    ],
    false,
  );
});
test("court envelope: kind, schema version, unknown keys, coach contacts, duplicate ids", () => {
  sweep(
    [
      ["wrong kind", set(["kind"], "pool_v1")],
      ["missing kind", (c) => delete c.kind],
      ["schema_version 2", set(["schema_version"], 2)],
      ["schema_version string", set(["schema_version"], "1")],
      ["unknown top key", set(["extra"], 1)],
      ["courts null", set(["courts"], null)],
      ["courts object", set(["courts"], {})],
      ["coach contacts present", set(["coaches"], [{ name: "x" }])],
      ["court/plan share an id", (c) => (c.plans[0].id = c.courts[0].id)],
      ["duplicate court ids", (c) => (c.courts[1].id = c.courts[0].id)],
    ],
    false,
  );
  sweep(
    [
      ["coaches empty", set(["coaches"], [])],
      ["plans omitted", (c) => delete c.plans],
    ],
    true,
  );
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
    assert.equal(
      courtSaveSchema.safeParse(v).success,
      false,
      JSON.stringify(v),
    );
});
test("court plans: allowance, seats, durations, expiry rules, price, ids, enums", () => {
  sweep(
    [
      ...gen("allowance", P0("allowance"), [
        -1,
        10001,
        1.5,
        NaN,
        Infinity,
        "10",
        null,
      ]),
      ["tracked plan with allowance 0", set(P0("allowance"), 0)],
      ...gen("price", P0("price_minor"), [
        -1,
        0.5,
        NaN,
        Infinity,
        "5000",
        100000001,
        1e21,
      ]),
      ...gen("kind", P0("kind"), ["swimming", "", "PLAY", null]),
      ...gen("expiry_mode", P0("expiry_mode"), [
        "never",
        "",
        "after_days",
        null,
      ]),
      ...gen("expiry_days", P0("expiry_days"), [
        0,
        -1,
        3651,
        1.5,
        NaN,
        "30",
        null,
      ]),
      ["months active but days set", set(P0("expiry_mode"), "after_months")],
      [
        "months mode without months",
        (c) => {
          c.plans[0].expiry_mode = "after_months";
          c.plans[0].expiry_days = null;
        },
      ],
      [
        "months 0",
        (c) => {
          c.plans[0].expiry_mode = "after_months";
          c.plans[0].expiry_days = null;
          c.plans[0].expiry_months = 0;
        },
      ],
      [
        "months 121",
        (c) => {
          c.plans[0].expiry_mode = "after_months";
          c.plans[0].expiry_days = null;
          c.plans[0].expiry_months = 121;
        },
      ],
      [
        "years 11",
        (c) => {
          c.plans[0].expiry_mode = "after_years";
          c.plans[0].expiry_days = null;
          c.plans[0].expiry_years = 11;
        },
      ],
      [
        "years 0",
        (c) => {
          c.plans[0].expiry_mode = "after_years";
          c.plans[0].expiry_days = null;
          c.plans[0].expiry_years = 0;
        },
      ],
      ["fixed_date with days set", set(P0("expiry_mode"), "fixed_date")],
      [
        "fixed_date invalid",
        (c) => {
          c.plans[0].expiry_mode = "fixed_date";
          c.plans[0].expiry_days = null;
          c.plans[0].expiry_date = "2026-02-30";
        },
      ],
      ["days mode with a fixed date", set(P0("expiry_date"), "2030-01-01")],
      ...gen("renewal", P0("renewal"), ["monthly", "", null, true]),
      ...gen("coach_id", P0("coach_id"), ["x", "", 5]),
      ["play plan with coach", set(P0("coach_id"), randomUUID())],
      ["play plan with class seats", set(P0("class_seats"), 10)],
      ["play plan with class duration", set(P0("class_duration_minutes"), 60)],
      ["unknown court in plan", set(P0("court_ids"), [randomUUID()])],
      [
        "duplicate court in plan",
        (c) => (c.plans[0].court_ids = [c.courts[0].id, c.courts[0].id]),
      ],
      [
        "51 courts in plan",
        set(
          P0("court_ids"),
          Array.from({ length: 51 }, () => randomUUID()),
        ),
      ],
      ["plan name too short", set(P0("name"), "a")],
      ["plan name too long", set(P0("name"), "p".repeat(101))],
      ["plan on disabled court", (c) => (c.courts[0].enabled = false)],
      [
        "plan hours outside court hours",
        set(P0("availability", "opens_at"), "05:00"),
      ],
      [
        "plan availability opens==closes",
        set(P0("availability", "closes_at"), "06:00"),
      ],
      ["track_attendance string", set(P0("track_attendance"), "no")],
      [
        "51 plans",
        (c) =>
          (c.plans = Array.from({ length: 51 }, () => ({
            ...structuredClone(c.plans[0]),
            id: randomUUID(),
          }))),
      ],
    ],
    false,
  );
  sweep(
    [
      ...gen("allowance", P0("allowance"), [1, 10000]),
      ...gen("price", P0("price_minor"), [0, 1, 100000000, null]),
      ...gen("expiry_days", P0("expiry_days"), [1, 3650]),
      [
        "months",
        (c) => {
          c.plans[0].expiry_mode = "after_months";
          c.plans[0].expiry_days = null;
          c.plans[0].expiry_months = 120;
        },
      ],
      [
        "years",
        (c) => {
          c.plans[0].expiry_mode = "after_years";
          c.plans[0].expiry_days = null;
          c.plans[0].expiry_years = 10;
        },
      ],
      [
        "fixed date",
        (c) => {
          c.plans[0].expiry_mode = "fixed_date";
          c.plans[0].expiry_days = null;
          c.plans[0].expiry_date = "2030-12-31";
        },
      ],
      [
        "fixed date in the past (draft)",
        (c) => {
          c.plans[0].expiry_mode = "fixed_date";
          c.plans[0].expiry_days = null;
          c.plans[0].expiry_date = "2001-01-01";
        },
      ],
      [
        "membership-only plan",
        (c) => {
          c.plans[0].track_attendance = false;
          c.plans[0].allowance = 0;
        },
      ],
      [
        "coaching plan",
        (c) => {
          Object.assign(c.plans[0], {
            kind: "coaching",
            class_duration_minutes: 60,
            class_seats: 20,
            coach_id: randomUUID(),
          });
        },
      ],
      [
        "coach seats 1",
        (c) => {
          Object.assign(c.plans[0], {
            kind: "coaching",
            class_duration_minutes: 30,
            class_seats: 1,
          });
        },
      ],
      [
        "coach seats 500",
        (c) => {
          Object.assign(c.plans[0], {
            kind: "coaching",
            class_duration_minutes: 60,
            class_seats: 500,
          });
        },
      ],
      [
        "disabled plan with no courts",
        (c) => {
          c.plans[0].enabled = false;
          c.plans[0].court_ids = [];
        },
      ],
    ],
    true,
  );
  sweep(
    [
      [
        "coaching seats 0",
        (c) => {
          Object.assign(c.plans[0], {
            kind: "coaching",
            class_duration_minutes: 60,
            class_seats: 0,
          });
        },
      ],
      [
        "coaching seats 501",
        (c) => {
          Object.assign(c.plans[0], {
            kind: "coaching",
            class_duration_minutes: 60,
            class_seats: 501,
          });
        },
      ],
      [
        "coaching seats 2.5",
        (c) => {
          Object.assign(c.plans[0], {
            kind: "coaching",
            class_duration_minutes: 60,
            class_seats: 2.5,
          });
        },
      ],
      [
        "coaching without seats",
        (c) => {
          Object.assign(c.plans[0], {
            kind: "coaching",
            class_duration_minutes: 60,
            class_seats: null,
          });
        },
      ],
      [
        "coaching without duration",
        (c) => {
          Object.assign(c.plans[0], {
            kind: "coaching",
            class_duration_minutes: null,
            class_seats: 5,
          });
        },
      ],
      [
        "coaching duration 29",
        (c) => {
          Object.assign(c.plans[0], {
            kind: "coaching",
            class_duration_minutes: 29,
            class_seats: 5,
          });
        },
      ],
      [
        "coaching duration longer than the plan window",
        (c) => {
          Object.assign(c.plans[0], {
            kind: "coaching",
            class_duration_minutes: 1440,
            class_seats: 5,
          });
        },
      ],
      [
        "membership-only with class seats",
        (c) => {
          Object.assign(c.plans[0], {
            kind: "coaching",
            track_attendance: false,
            allowance: 0,
            class_seats: 5,
            class_duration_minutes: 60,
          });
        },
      ],
    ],
    false,
  );
});
test("court completeness for activation: enabled courts need prices, plans need nonexpired dates", () => {
  const c = base();
  assert.ok(assertCourtComplete(c));
  const bad1 = base();
  bad1.courts.forEach((x: any) => (x.enabled = false));
  bad1.plans = [];
  assert.throws(() => assertCourtComplete(bad1), /Enable at least one court/);
  const bad2 = base();
  bad2.courts[0].tariffs[0].rates[0].price_minor = null;
  assert.throws(() => assertCourtComplete(bad2), /Complete court prices/);
  const bad3 = base();
  bad3.courts[0].tariffs = [];
  assert.throws(() => assertCourtComplete(bad3), /Complete court prices/);
  const bad4 = base();
  Object.assign(bad4.plans[0], {
    expiry_mode: "fixed_date",
    expiry_days: null,
    expiry_date: "2026-01-01",
  });
  assert.throws(() => assertCourtComplete(bad4, "2026-01-02"), /nonexpired/);
  assert.ok(assertCourtComplete(bad4, "2026-01-01")); // the expiry day itself is still valid
  const bad5 = base();
  bad5.plans[0].price_minor = null;
  assert.throws(
    () => assertCourtComplete(bad5),
    /Complete plan courts, prices/,
  );
  const bad6 = base();
  bad6.plans[0].court_ids = [];
  assert.throws(() => assertCourtComplete(bad6), /Complete plan courts/);
  const ok7 = base();
  ok7.plans[0].price_minor = 0; // a free plan is allowed
  assert.ok(assertCourtComplete(ok7));
  const bad8 = base();
  bad8.courts[0].tariffs[1].rates[0].price_minor = null;
  assert.throws(() => assertCourtComplete(bad8), /Complete court prices/);
  assert.throws(() => assertCourtComplete({ kind: "court_v1" }));
  assert.throws(() => assertCourtComplete(null));
});
test("court price quote: invalid dates/times/durations return null and money rounds half up on the 15-minute grid", () => {
  const c = courtConfigurationSchema.parse(base()),
    p = c.courts[0];
  const q = (date: string, time: string, d: number, id = p.id) =>
    courtPriceAtStart(c, id, date, time, d);
  assert.equal(q("2026-10-14", "10:00", 60), 40000);
  assert.equal(q("2026-10-14", "10:00", 75), 50000); // 40000 * 75/60
  assert.equal(q("2026-10-14", "10:00", 90), 60000);
  for (const [date, time, d] of [
    ["2026-02-30", "10:00", 60],
    ["", "10:00", 60],
    ["2026-10-14", "24:00", 60],
    ["2026-10-14", "10:60", 60],
    ["2026-10-14", "", 60],
    ["2026-10-14", "10:00", 0],
    ["2026-10-14", "10:00", -60],
    ["2026-10-14", "10:00", 59],
    ["2026-10-14", "10:00", 61],
    ["2026-10-14", "10:00", 60.5],
    ["2026-10-14", "10:00", NaN],
    ["2026-10-14", "10:00", Infinity],
    ["2026-10-14", "10:00", 1441],
    ["2026-10-14", "10:00", 1e9],
    ["2026-10-14", "05:59", 60],
    ["2026-10-14", "23:30", 60], // runs past closing time
    ["' OR 1=1", "10:00", 60],
  ] as [string, string, number][])
    assert.equal(q(date, time, d), null, `${date} ${time} ${d}`);
  assert.equal(q("2026-10-14", "10:00", 60, randomUUID()), null);
  assert.equal(q("2026-10-14", "10:00", 60, "not-a-uuid"), null);
  // rounding of per-quarter-hour extensions: 1 minor unit at 60 min -> 75 min is 1.25 -> 1; 90 -> 1.5 -> 2
  const r = structuredClone(c);
  r.courts[0].tariffs.forEach((t: any) => (t.rates[0].price_minor = 1));
  assert.equal(courtPriceAtStart(r, p.id, "2026-10-14", "10:00", 75), 1);
  assert.equal(courtPriceAtStart(r, p.id, "2026-10-14", "10:00", 90), 2);
  // a price of exactly 0 is a valid free slot, not "no price"
  const z = structuredClone(c);
  z.courts[0].tariffs.forEach((t: any) => (t.rates[0].price_minor = 0));
  assert.equal(courtPriceAtStart(z, p.id, "2026-10-14", "10:00", 60), 0);
  // a null price means "not priced"
  const n = structuredClone(c);
  n.courts[0].tariffs.forEach((t: any) => (t.rates[0].price_minor = null));
  assert.equal(courtPriceAtStart(n, p.id, "2026-10-14", "10:00", 60), null);
  // a maximum price times a long extension is still exact
  const m = structuredClone(c);
  m.courts[0].durations = [30];
  m.courts[0].default_duration_minutes = 30;
  m.courts[0].tariffs.forEach(
    (t: any) => (t.rates = [{ duration_minutes: 30, price_minor: 100000000 }]),
  );
  assert.equal(
    courtPriceAtStart(m, p.id, "2026-10-14", "06:00", 900),
    3000000000,
  );
});

// ------------------------------------------------------------ service level
async function fixture(type = "badminton") {
  const uid = randomUUID(),
    owner: Actor = { uid, email: `${uid}@example.com`, name: "Owner" };
  await workspace.createOrganization(owner, {
    name: "Court Field QA",
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
test("court configure: version must be a positive integer and match", async () => {
  const { owner, id } = await fixture(),
    c = courtConfigurationSchema.parse(base());
  for (const version of [0, -1, 1.5, "1", null, undefined, NaN, Infinity, true])
    await bad(
      () => service.configure(owner, id, { version, configuration: c }),
      String(version),
    );
  await assert.rejects(
    () => service.configure(owner, id, { version: 2, configuration: c }),
    /Reload before saving/,
  );
  await assert.rejects(
    () => service.configure(owner, id, { version: 99999, configuration: c }),
    /Reload before saving/,
  );
  const r = await service.configure(owner, id, {
    version: 1,
    configuration: c,
  });
  assert.equal(r.version, 2);
  await assert.rejects(
    () => service.configure(owner, id, { version: 1, configuration: c }),
    /Reload before saving/,
  ); // replay of an old version
  assert.equal((await workspace.workspace(owner)).businesses[0].version, 2);
});
test("court configure: body shape, unknown keys and invalid configurations leave version and resources untouched", async () => {
  const { owner, id } = await fixture();
  const good = courtConfigurationSchema.parse(base());
  await service.configure(owner, id, { version: 1, configuration: good });
  const snapshot = async () => {
    const b = (await workspace.workspace(owner)).businesses[0];
    return JSON.stringify({
      v: b.version,
      r: b.resources.map((x: any) => x.id).sort(),
      c: b.configuration,
    });
  };
  const before_ = await snapshot();
  for (const body of [
    null,
    undefined,
    5,
    "x",
    [],
    {},
    { version: 2 },
    { configuration: good },
    { version: 2, configuration: good, extra: 1 },
    { version: 2, configuration: { ...good, kind: "turf_v1" } },
    {
      version: 2,
      configuration: { ...good, courts: [{ ...good.courts[0], name: "" }] },
    },
  ])
    await bad(
      () => service.configure(owner, id, body),
      JSON.stringify(body)?.slice(0, 80),
    );
  assert.equal(await snapshot(), before_);
});
test("court configure: wrong business type, foreign tenant, unknown id and non-owner are rejected", async () => {
  const { owner, id } = await fixture();
  const pool = await fixture("pool");
  const c = courtConfigurationSchema.parse(base());
  await assert.rejects(
    () =>
      service.configure(pool.owner, pool.id, { version: 1, configuration: c }),
    /court business/,
  );
  await assert.rejects(
    () => service.configure(pool.owner, id, { version: 1, configuration: c }),
    /Business not found/,
  ); // cross-tenant
  await assert.rejects(
    () =>
      service.configure(owner, randomUUID(), { version: 1, configuration: c }),
    /Business not found/,
  );
  await assert.rejects(
    () =>
      service.configure({ uid: randomUUID(), email: "x@y.z", name: "x" }, id, {
        version: 1,
        configuration: c,
      }),
    /membership/i,
  );
  const staff: Actor = {
    uid: randomUUID(),
    email: `${randomUUID()}@example.com`,
    name: "Staff",
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
  assert.equal((await workspace.workspace(owner)).businesses[0].version, 1);
});
test("court configure: identifiers owned by another business or tenant cannot be adopted", async () => {
  const a = await fixture(),
    b = await fixture();
  const ca = courtConfigurationSchema.parse(base());
  await service.configure(a.owner, a.id, { version: 1, configuration: ca });
  const stolen = courtConfigurationSchema.parse(base());
  stolen.courts[0].id = ca.courts[0].id; // an id already used by business A
  stolen.plans = [];
  await assert.rejects(
    () =>
      service.configure(b.owner, b.id, { version: 1, configuration: stolen }),
    /another business|identifier/,
  );
  assert.equal((await workspace.workspace(b.owner)).businesses[0].version, 1);
});
test("court configure: unicode and SQL-looking names persist literally", async () => {
  const { owner, id } = await fixture();
  const c = courtConfigurationSchema.parse(base());
  c.courts[0].name = "Court'); DROP TABLE resources;-- 名前 🏸";
  c.courts[1].name = "Ünïcödé Court";
  await service.configure(owner, id, { version: 1, configuration: c });
  const names = (await workspace.workspace(owner)).businesses[0].resources
    .map((r: any) => r.name)
    .sort();
  assert.deepEqual(names, [c.courts[0].name, c.courts[1].name].sort());
});
test(
  "court configure: a NUL byte in a court name is a client error, not a server error",
  { todo: "BUG-4" },
  async () => {
    const { owner, id } = await fixture();
    const c = courtConfigurationSchema.parse(base());
    c.courts[0].name = "Bad\u0000Court";
    await bad(() =>
      service.configure(owner, id, { version: 1, configuration: c }),
    );
  },
);
test("court configure: parallel saves with the same version apply exactly once", async () => {
  const { owner, id } = await fixture();
  const results = await Promise.allSettled(
    [1, 2, 3].map(() =>
      service.configure(owner, id, {
        version: 1,
        configuration: courtConfigurationSchema.parse(base()),
      }),
    ),
  );
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
  assert.equal((await workspace.workspace(owner)).businesses[0].version, 2);
});
test("court configure: an active business rejects incomplete edits atomically and keeps its status", async () => {
  const { owner, id } = await fixture();
  const c = courtConfigurationSchema.parse(base());
  await service.configure(owner, id, { version: 1, configuration: c });
  await workspace.activate(owner, id);
  let b = (await workspace.workspace(owner)).businesses[0];
  assert.equal(b.status, "ready");
  const broken = structuredClone(c);
  broken.courts[0].tariffs[0].rates[0].price_minor = null;
  await assert.rejects(
    () =>
      service.configure(owner, id, {
        version: b.version,
        configuration: broken,
      }),
    /Complete court prices/,
  );
  const past = structuredClone(c);
  Object.assign(past.plans![0], {
    expiry_mode: "fixed_date",
    expiry_days: null,
    expiry_date: "2001-01-01",
  });
  await assert.rejects(
    () =>
      service.configure(owner, id, { version: b.version, configuration: past }),
    /nonexpired/,
  );
  const after_ = (await workspace.workspace(owner)).businesses[0];
  assert.equal(after_.version, b.version);
  assert.equal(after_.status, "ready");
});
