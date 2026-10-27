// Field-value / boundary tests for the Pool module: pools, depths (decimal precision), swimming prices,
// group packages, swimming/coaching plans, expiry arithmetic, quote helpers and the configure() service.
import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { HttpException } from "@nestjs/common";
import { ZodError } from "zod";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { PoolService } from "../src/pool/pool.service";
import { Actor } from "../src/common/auth.guard";
import {
  poolConfigurationSchema,
  poolSaveSchema,
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
  const pools = [1, 2].map((n) => ({
    id: randomUUID(),
    name: `Pool ${n}`,
    capacity: 20,
    depth_min_ft: 3,
    depth_max_ft: 5,
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
  const planCommon = {
    expiry_months: null,
    expiry_years: null,
    expiry_date: null,
    enabled: true,
    availability: structuredClone(hours),
    renewal: "none",
  };
  return {
    kind: "pool_v1",
    schema_version: 1,
    pools,
    group_offers: [
      {
        id: randomUUID(),
        name: "Party of 10",
        pool_ids: [pools[0].id],
        group_mode: "exact",
        people: 10,
        duration_minutes: 60,
        price_minor: 100000,
        enabled: true,
        availability: structuredClone(hours),
      },
    ],
    plans: [
      {
        ...planCommon,
        id: randomUUID(),
        name: "Monthly swim",
        kind: "swimming",
        pool_ids: [pools[0].id],
        allowance: 12,
        track_attendance: true,
        expiry_mode: "after_start",
        expiry_days: 45,
        price_minor: 300000,
        class_duration_minutes: null,
        class_seats: null,
        coach_id: null,
      },
      {
        ...planCommon,
        id: randomUUID(),
        name: "Beginner coaching",
        kind: "coaching",
        pool_ids: [pools[1].id],
        allowance: 8,
        track_attendance: true,
        expiry_mode: "after_start",
        expiry_days: 60,
        price_minor: 400000,
        class_duration_minutes: 60,
        class_seats: 10,
        coach_id: null,
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
      const r = poolConfigurationSchema.safeParse(c);
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
const P0 = (...r: (string | number)[]) => ["pools", 0, ...r];
const G0 = (...r: (string | number)[]) => ["group_offers", 0, ...r];
const L0 = (...r: (string | number)[]) => ["plans", 0, ...r];
const L1 = (...r: (string | number)[]) => ["plans", 1, ...r];

test("pool identity: name, capacity, flags, envelope", () => {
  sweep(
    [
      ...gen("name", P0("name"), ["", " ", "a", "p".repeat(101), null, 5]),
      ["duplicate names", (c) => (c.pools[1].name = c.pools[0].name)],
      [
        "duplicate names (case)",
        (c) => (c.pools[1].name = c.pools[0].name.toUpperCase()),
      ],
      ["duplicate ids", (c) => (c.pools[1].id = c.pools[0].id)],
      ["pool/plan share an id", (c) => (c.plans[0].id = c.pools[0].id)],
      ["pool/offer share an id", (c) => (c.group_offers[0].id = c.pools[0].id)],
      ...gen("capacity", P0("capacity"), [
        0,
        -1,
        10001,
        1.5,
        NaN,
        Infinity,
        "20",
        null,
        1e9,
      ]),
      ...gen("enabled", P0("enabled"), ["true", 1, null]),
      ...gen("regular_swimming", P0("regular_swimming"), ["true", 0, null]),
      [
        "31 pools",
        (c) =>
          (c.pools = Array.from({ length: 31 }, (_, i) => ({
            ...structuredClone(c.pools[0]),
            id: randomUUID(),
            name: "P" + i + "x",
          }))),
      ],
      ["unknown pool key", set(P0("extra"), 1)],
      ["wrong kind", set(["kind"], "hall_v1")],
      ["schema_version 2", set(["schema_version"], 2)],
      ["unknown top key", set(["extra"], 1)],
      ["coach contacts present", set(["coaches"], [{ name: "x" }])],
      ["group_offers missing", (c) => delete c.group_offers],
      ["plans missing", (c) => delete c.plans],
    ],
    false,
  );
  sweep(
    [
      ...gen("name", P0("name"), [
        "ab",
        "p".repeat(100),
        "Ünï Pool 名前 🏊",
        "Pool'); DROP TABLE resources;--",
      ]),
      ...gen("capacity", P0("capacity"), [20, 10000]),
      [
        "capacity 1 (offers still fit)",
        (c) => {
          c.pools[1].capacity = 11;
        },
      ],
      [
        "no pools (draft)",
        (c) => {
          c.pools = [];
          c.group_offers = [];
          c.plans = [];
        },
      ],
      ["coaches empty", set(["coaches"], [])],
      [
        "disabled pool",
        (c) => {
          c.pools[1].enabled = false;
          c.plans[1].enabled = false;
        },
      ],
    ],
    true,
  );
});
test("pool depths: 0.01 steps are exact (decimal precision), no more than two decimals, min <= max", () => {
  const exact = [
    0,
    0.01,
    0.07,
    0.1,
    0.29,
    0.57,
    1.15,
    2.675 - 0.005,
    3,
    4.35,
    5.25,
    6.1,
    8.2,
    12.34,
    999.99,
    1000,
  ];
  sweep(
    [
      ...gen("min", P0("depth_min_ft"), [
        -1,
        -0.01,
        1000.01,
        1001,
        0.001,
        0.005,
        1.234,
        2.675,
        NaN,
        Infinity,
        -Infinity,
        "3",
        true,
        [],
        {},
      ]),
      ...gen("max", P0("depth_max_ft"), [
        0,
        -1,
        1000.01,
        0.001,
        0.005,
        5.555,
        NaN,
        Infinity,
        "5",
        true,
      ]),
      [
        "min > max",
        (c) => {
          c.pools[0].depth_min_ft = 5.01;
          c.pools[0].depth_max_ft = 5;
        },
      ],
      [
        "min 1000 max 999.99",
        (c) => {
          c.pools[0].depth_min_ft = 1000;
          c.pools[0].depth_max_ft = 999.99;
        },
      ],
    ],
    false,
  );
  sweep(
    [
      ...exact.map(
        (d) =>
          [
            `min=${d}`,
            (c: any) => {
              c.pools[0].depth_min_ft = d;
              c.pools[0].depth_max_ft = 1000;
            },
          ] as Case,
      ),
      ...exact
        .filter((d) => d > 0)
        .map(
          (d) =>
            [
              `max=${d}`,
              (c: any) => {
                c.pools[0].depth_min_ft = 0;
                c.pools[0].depth_max_ft = d;
              },
            ] as Case,
        ),
      [
        "equal depths",
        (c) => {
          c.pools[0].depth_min_ft = 4.35;
          c.pools[0].depth_max_ft = 4.35;
        },
      ],
      [
        "unknown depths (draft)",
        (c) => {
          c.pools[0].depth_min_ft = null;
          c.pools[0].depth_max_ft = null;
        },
      ],
      [
        "only max",
        (c) => {
          c.pools[0].depth_min_ft = null;
        },
      ],
      [
        "only min",
        (c) => {
          c.pools[0].depth_max_ft = null;
        },
      ],
    ],
    true,
  );
});
test("pool durations, buffers and swimming prices", () => {
  const R = P0("tariffs", 0, "rates", 0);
  sweep(
    [
      ...gen(
        "price",
        [...R, "price_minor"],
        [
          -1,
          0.5,
          200.99,
          0.1 + 0.2,
          NaN,
          Infinity,
          "20000",
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
      ...gen("buffer_before", P0("buffer_before"), [
        -1,
        241,
        1.5,
        NaN,
        "0",
        null,
      ]),
      ...gen("buffer_after", P0("buffer_after"), [
        -1,
        241,
        1.5,
        NaN,
        "0",
        null,
      ]),
      ...gen("default_duration", P0("default_duration_minutes"), [
        29,
        1441,
        60.5,
        "60",
        null,
        90,
      ]),
      ["no durations", set(P0("durations"), [])],
      [
        "11 durations",
        set(
          P0("durations"),
          Array.from({ length: 11 }, (_, i) => 30 + i * 30),
        ),
      ],
      ["duplicate durations", set(P0("durations"), [60, 60])],
      ["tariff misses a duration", set(P0("durations"), [60, 90])],
      [
        "tariffs overlap",
        (c) => (c.pools[0].tariffs[1].hours.opens_at = "17:00"),
      ],
      [
        "tariff outside operating hours",
        (c) => (c.pools[0].tariffs[0].hours.opens_at = "05:00"),
      ],
      [
        "duplicate tariff ids",
        (c) => (c.pools[0].tariffs[1].id = c.pools[0].tariffs[0].id),
      ],
      [
        "pool operating date window",
        (c) => {
          c.pools[0].operating.date_from = "2026-01-01";
          c.pools[0].operating.date_until = "2026-12-31";
        },
      ],
      [
        "tariff seasonal Feb 30",
        (c) => {
          c.pools[0].tariffs[0].hours.date_from = "2026-02-30";
          c.pools[0].tariffs[0].hours.date_until = "2026-03-30";
        },
      ],
      [
        "tariff seasonal inverted",
        (c) => {
          c.pools[0].tariffs[0].hours.date_from = "2026-05-01";
          c.pools[0].tariffs[0].hours.date_until = "2026-04-01";
        },
      ],
      [
        "41 tariffs",
        set(
          P0("tariffs"),
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
    ],
    false,
  );
  sweep(
    [
      ...gen("price", [...R, "price_minor"], [0, 1, 100000000, null]),
      ...gen("buffer_before", P0("buffer_before"), [0, 240]),
      ...gen("buffer_after", P0("buffer_after"), [0, 240]),
      [
        "seasonal pricing",
        (c) =>
          c.pools[0].tariffs.push({
            id: randomUUID(),
            hours: {
              ...hours,
              days: [6, 7],
              closes_at: "18:00",
              date_from: "2026-10-17",
              date_until: "2026-10-18",
            },
            rates: [{ duration_minutes: 60, price_minor: 30000 }],
          }),
      ],
      [
        "24h pool",
        (c) => {
          c.pools[0].operating = {
            ...hours,
            all_day: true,
            opens_at: "00:00",
            closes_at: "00:00",
          };
          c.group_offers[0].availability = structuredClone(
            c.pools[0].operating,
          );
          c.plans[0].availability = structuredClone(c.pools[0].operating);
          c.pools[0].tariffs = [
            {
              id: randomUUID(),
              hours: structuredClone(c.pools[0].operating),
              rates: [{ duration_minutes: 60, price_minor: 1 }],
            },
          ];
        },
      ],
      ["no tariffs (draft)", set(P0("tariffs"), [])],
    ],
    true,
  );
});
test("pool operating hours", () => {
  const O = (k: string) => P0("operating", k);
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
        null,
        600,
      ]),
      ...gen("closes_at", O("closes_at"), ["", "24:00", "7", null]),
      ["opens == closes", set(O("closes_at"), "06:00")],
      ["all_day with non-midnight", set(O("all_day"), true)],
    ],
    false,
  );
});
test("pool group offers: mode, people, duration, price, eligible pools", () => {
  sweep(
    [
      ...gen("name", G0("name"), ["", "a", "n".repeat(101), null]),
      ...gen("group_mode", G0("group_mode"), ["min", "", "EXACT", null]),
      ...gen("people", G0("people"), [
        0,
        -1,
        10001,
        1.5,
        NaN,
        Infinity,
        "10",
        null,
      ]),
      ["people exceed the eligible pool capacity", set(G0("people"), 21)],
      ...gen("duration", G0("duration_minutes"), [
        29,
        0,
        1441,
        60.5,
        NaN,
        "60",
        null,
      ]),
      [
        "duration longer than availability",
        (c) => {
          c.group_offers[0].availability.opens_at = "10:00";
          c.group_offers[0].availability.closes_at = "10:30";
        },
      ],
      ...gen("price", G0("price_minor"), [
        -1,
        0.5,
        1000.5,
        NaN,
        Infinity,
        "1000",
        100000001,
        1e21,
      ]),
      ["unknown pool", set(G0("pool_ids"), [randomUUID()])],
      [
        "duplicate pool",
        (c) => (c.group_offers[0].pool_ids = [c.pools[0].id, c.pools[0].id]),
      ],
      [
        "31 pools",
        set(
          G0("pool_ids"),
          Array.from({ length: 31 }, () => randomUUID()),
        ),
      ],
      [
        "pool disabled while offer enabled",
        (c) => {
          c.pools[0].enabled = false;
          c.plans[0].enabled = false;
        },
      ],
      [
        "availability outside the pool",
        set(G0("availability", "opens_at"), "05:00"),
      ],
      [
        "51 offers",
        set(
          ["group_offers"],
          Array.from({ length: 51 }, () => ({
            ...base().group_offers[0],
            pool_ids: [],
          })),
        ),
      ],
      ["offer unknown key", set(G0("extra"), 1)],
    ],
    false,
  );
  sweep(
    [
      ...gen("group_mode", G0("group_mode"), ["exact", "up_to", "at_least"]),
      ...gen("people", G0("people"), [1, 20]),
      ...gen("price", G0("price_minor"), [0, 1, 100000000, null]),
      ["offer without pools (draft)", set(G0("pool_ids"), [])],
      [
        "disabled offer ignores capacity",
        (c) => {
          c.group_offers[0].enabled = false;
          c.group_offers[0].people = 9999;
        },
      ],
      ["no offers", set(["group_offers"], [])],
    ],
    true,
  );
});
test("pool plans: swimming and coaching rules, allowance, expiry combinations", () => {
  sweep(
    [
      ...gen("allowance", L0("allowance"), [
        -1,
        10001,
        1.5,
        NaN,
        Infinity,
        "12",
        null,
      ]),
      ["tracked plan with 0 allowance", set(L0("allowance"), 0)],
      ...gen("price", L0("price_minor"), [
        -1,
        0.5,
        300000.5,
        NaN,
        Infinity,
        "3000",
        100000001,
        1e21,
      ]),
      ...gen("kind", L0("kind"), ["play", "", "SWIMMING", null]),
      ...gen("expiry_mode", L0("expiry_mode"), ["never", "", null]),
      ...gen("expiry_days", L0("expiry_days"), [
        0,
        -1,
        3651,
        1.5,
        NaN,
        "30",
        null,
      ]),
      ["months chosen but days set", set(L0("expiry_mode"), "after_months")],
      [
        "months 0",
        (c) =>
          Object.assign(c.plans[0], {
            expiry_mode: "after_months",
            expiry_days: null,
            expiry_months: 0,
          }),
      ],
      [
        "months 121",
        (c) =>
          Object.assign(c.plans[0], {
            expiry_mode: "after_months",
            expiry_days: null,
            expiry_months: 121,
          }),
      ],
      [
        "months decimal",
        (c) =>
          Object.assign(c.plans[0], {
            expiry_mode: "after_months",
            expiry_days: null,
            expiry_months: 1.5,
          }),
      ],
      [
        "years 0",
        (c) =>
          Object.assign(c.plans[0], {
            expiry_mode: "after_years",
            expiry_days: null,
            expiry_years: 0,
          }),
      ],
      [
        "years 11",
        (c) =>
          Object.assign(c.plans[0], {
            expiry_mode: "after_years",
            expiry_days: null,
            expiry_years: 11,
          }),
      ],
      ["two units at once", set(L0("expiry_months"), 1)],
      ["fixed date with days", set(L0("expiry_mode"), "fixed_date")],
      [
        "fixed date Feb 30",
        (c) =>
          Object.assign(c.plans[0], {
            expiry_mode: "fixed_date",
            expiry_days: null,
            expiry_date: "2026-02-30",
          }),
      ],
      ["days mode with fixed date", set(L0("expiry_date"), "2030-01-01")],
      ...gen("renewal", L0("renewal"), ["monthly", "", null]),
      ...gen("coach_id", L0("coach_id"), ["x", "", 5]),
      ["swimming plan with coach", set(L0("coach_id"), randomUUID())],
      ["swimming plan with class seats", set(L0("class_seats"), 5)],
      [
        "swimming plan with class duration",
        set(L0("class_duration_minutes"), 60),
      ],
      ["coaching without seats", set(L1("class_seats"), null)],
      ["coaching without duration", set(L1("class_duration_minutes"), null)],
      ["coaching seats 0", set(L1("class_seats"), 0)],
      ["coaching seats 10001", set(L1("class_seats"), 10001)],
      ["coaching seats 2.5", set(L1("class_seats"), 2.5)],
      ["coaching seats exceed the pool capacity", set(L1("class_seats"), 21)],
      ["coaching duration 29", set(L1("class_duration_minutes"), 29)],
      ["coaching duration 1441", set(L1("class_duration_minutes"), 1441)],
      [
        "coaching duration longer than the window",
        (c) => {
          c.plans[1].availability.opens_at = "10:00";
          c.plans[1].availability.closes_at = "10:30";
        },
      ],
      ["unknown pool", set(L0("pool_ids"), [randomUUID()])],
      [
        "duplicate pool",
        (c) => (c.plans[0].pool_ids = [c.pools[0].id, c.pools[0].id]),
      ],
      ["plan on disabled pool", (c) => (c.pools[0].enabled = false)],
      ["plan outside pool hours", set(L0("availability", "opens_at"), "05:00")],
      ["plan name too short", set(L0("name"), "a")],
      ["plan name too long", set(L0("name"), "p".repeat(101))],
      [
        "51 plans",
        (c) =>
          (c.plans = Array.from({ length: 51 }, () => ({
            ...structuredClone(c.plans[0]),
            id: randomUUID(),
          }))),
      ],
      ["plan unknown key", set(L0("extra"), 1)],
    ],
    false,
  );
  sweep(
    [
      ...gen("allowance", L0("allowance"), [1, 10000]),
      ...gen("price", L0("price_minor"), [0, 1, 100000000, null]),
      ...gen("expiry_days", L0("expiry_days"), [1, 3650]),
      [
        "months 120",
        (c) =>
          Object.assign(c.plans[0], {
            expiry_mode: "after_months",
            expiry_days: null,
            expiry_months: 120,
          }),
      ],
      [
        "years 10",
        (c) =>
          Object.assign(c.plans[0], {
            expiry_mode: "after_years",
            expiry_days: null,
            expiry_years: 10,
          }),
      ],
      [
        "fixed date (future)",
        (c) =>
          Object.assign(c.plans[0], {
            expiry_mode: "fixed_date",
            expiry_days: null,
            expiry_date: "2031-12-31",
          }),
      ],
      [
        "fixed date (past, draft only)",
        (c) =>
          Object.assign(c.plans[0], {
            expiry_mode: "fixed_date",
            expiry_days: null,
            expiry_date: "2001-01-01",
          }),
      ],
      [
        "fixed date still empty (draft only; activation rejects it)",
        (c) =>
          Object.assign(c.plans[0], {
            expiry_mode: "fixed_date",
            expiry_days: null,
          }),
      ],
      [
        "leap-day fixed date",
        (c) =>
          Object.assign(c.plans[0], {
            expiry_mode: "fixed_date",
            expiry_days: null,
            expiry_date: "2028-02-29",
          }),
      ],
      [
        "membership-only swimming plan",
        (c) =>
          Object.assign(c.plans[0], { track_attendance: false, allowance: 0 }),
      ],
      [
        "membership-only plan with 0 allowance and no pools hours",
        (c) =>
          Object.assign(c.plans[0], {
            track_attendance: false,
            allowance: 0,
            availability: { ...hours, opens_at: "01:00", closes_at: "02:00" },
          }),
      ],
      ["coaching seats 1", set(L1("class_seats"), 1)],
      ["coaching seats == pool capacity", set(L1("class_seats"), 20)],
      ["coaching duration 30", set(L1("class_duration_minutes"), 30)],
      ["coach assigned", set(L1("coach_id"), randomUUID())],
    ],
    true,
  );
});
test("pool completeness for activation", () => {
  assert.ok(assertPoolComplete(base()));
  const none = base();
  none.pools.forEach((p: any) => (p.enabled = false));
  none.group_offers = [];
  none.plans = [];
  assert.throws(() => assertPoolComplete(none), /Enable at least one pool/);
  const nodepth = base();
  nodepth.pools[0].depth_min_ft = null;
  assert.throws(
    () => assertPoolComplete(nodepth),
    /minimum and maximum depths/,
  );
  const nodepth2 = base();
  nodepth2.pools[0].depth_max_ft = null;
  assert.throws(
    () => assertPoolComplete(nodepth2),
    /minimum and maximum depths/,
  );
  const unpriced = base();
  unpriced.pools[0].tariffs[0].rates[0].price_minor = null;
  assert.throws(() => assertPoolComplete(unpriced), /regular swimming prices/);
  const notariffs = base();
  notariffs.pools[0].tariffs = [];
  assert.throws(() => assertPoolComplete(notariffs), /regular swimming prices/);
  const idle = base();
  idle.pools[1].regular_swimming = false;
  idle.plans = [idle.plans[0]];
  idle.group_offers = idle.group_offers.slice();
  assert.throws(
    () => assertPoolComplete(idle),
    /needs swimming prices, a group offer or a plan/,
  );
  const unpricedOffer = base();
  unpricedOffer.group_offers[0].price_minor = null;
  assert.throws(
    () => assertPoolComplete(unpricedOffer),
    /Complete eligible pools, prices/,
  );
  const unpricedPlan = base();
  unpricedPlan.plans[0].price_minor = null;
  assert.throws(
    () => assertPoolComplete(unpricedPlan),
    /Complete eligible pools, prices/,
  );
  const noPools = base();
  noPools.plans[0].pool_ids = [];
  assert.throws(() => assertPoolComplete(noPools), /Complete eligible pools/);
  const expired = base();
  Object.assign(expired.plans[0], {
    expiry_mode: "fixed_date",
    expiry_days: null,
    expiry_date: "2026-01-01",
  });
  assert.throws(() => assertPoolComplete(expired, "2026-01-02"), /nonexpired/);
  assert.ok(assertPoolComplete(expired, "2026-01-01"));
  const noDate = base();
  Object.assign(noDate.plans[0], {
    expiry_mode: "fixed_date",
    expiry_days: null,
  });
  assert.throws(() => assertPoolComplete(noDate), /nonexpired/);
  const free = base();
  free.plans[0].price_minor = 0;
  free.group_offers[0].price_minor = 0;
  assert.ok(assertPoolComplete(free));
  assert.throws(() => assertPoolComplete(null));
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
    assert.equal(poolSaveSchema.safeParse(v).success, false, JSON.stringify(v));
});
test("pool plan expiry: calendar arithmetic clamps month ends and rejects invalid input", () => {
  const plan = (extra: Record<string, any>) =>
    ({
      expiry_mode: "after_start",
      expiry_days: null,
      expiry_months: null,
      expiry_years: null,
      expiry_date: null,
      ...extra,
    }) as any;
  assert.equal(
    poolPlanExpiry(plan({ expiry_days: 1 }), "2026-12-31"),
    "2027-01-01",
  );
  assert.equal(
    poolPlanExpiry(plan({ expiry_days: 3650 }), "2026-01-01"),
    "2035-12-30",
  );
  assert.equal(
    poolPlanExpiry(
      plan({ expiry_mode: "after_months", expiry_months: 1 }),
      "2026-01-31",
    ),
    "2026-02-28",
  );
  assert.equal(
    poolPlanExpiry(
      plan({ expiry_mode: "after_months", expiry_months: 1 }),
      "2028-01-31",
    ),
    "2028-02-29",
  );
  assert.equal(
    poolPlanExpiry(
      plan({ expiry_mode: "after_months", expiry_months: 6 }),
      "2026-08-31",
    ),
    "2027-02-28",
  );
  assert.equal(
    poolPlanExpiry(
      plan({ expiry_mode: "after_months", expiry_months: 12 }),
      "2026-03-31",
    ),
    "2027-03-31",
  );
  assert.equal(
    poolPlanExpiry(
      plan({ expiry_mode: "after_months", expiry_months: 120 }),
      "2026-01-31",
    ),
    "2036-01-31",
  );
  assert.equal(
    poolPlanExpiry(
      plan({ expiry_mode: "after_years", expiry_years: 1 }),
      "2028-02-29",
    ),
    "2029-02-28",
  );
  assert.equal(
    poolPlanExpiry(
      plan({ expiry_mode: "after_years", expiry_years: 4 }),
      "2028-02-29",
    ),
    "2032-02-29",
  );
  assert.equal(
    poolPlanExpiry(
      plan({ expiry_mode: "fixed_date", expiry_date: "2030-05-05" }),
      "2026-01-01",
    ),
    "2030-05-05",
  );
  for (const start of ["2026-02-30", "", "tomorrow", "2026-1-1", "2026-13-01"])
    assert.throws(() => poolPlanExpiry(plan({ expiry_days: 5 }), start), start);
  assert.throws(() =>
    poolPlanExpiry(
      plan({ expiry_mode: "fixed_date", expiry_date: null }),
      "2026-01-01",
    ),
  );
  assert.throws(
    () =>
      poolPlanExpiry(
        plan({ expiry_mode: "after_start", expiry_days: null }),
        "2026-01-01",
      ),
    /Missing validity days/,
  );
  assert.throws(
    () =>
      poolPlanExpiry(
        plan({ expiry_mode: "after_months", expiry_months: null }),
        "2026-01-01",
      ),
    /Missing validity period/,
  );
  assert.throws(
    () =>
      poolPlanExpiry(
        plan({ expiry_mode: "after_years", expiry_years: 0 }),
        "2026-01-01",
      ),
    /Missing validity period/,
  );
});
test("pool quotes: garbage inputs return null; people multiply the per-person price exactly", () => {
  const c = poolConfigurationSchema.parse(base()),
    p = c.pools[0];
  const q = (date: string, time: string, d: number, people = 1, id = p.id) =>
    poolPriceAtStart(c, id, date, time, d, people);
  assert.equal(q("2026-10-14", "10:00", 60), 20000);
  assert.equal(q("2026-10-14", "10:00", 60, 3), 60000);
  assert.equal(q("2026-10-14", "18:00", 60, 20), 500000);
  assert.equal(q("2026-10-14", "10:00", 90, 2), 60000);
  for (const people of [0, -1, 1.5, NaN, Infinity, 21, 1e9])
    assert.equal(q("2026-10-14", "10:00", 60, people), null, String(people));
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
  ] as [string, string, number][])
    assert.equal(q(date, time, d), null, `${date} ${time} ${d}`);
  assert.equal(q("2026-10-14", "10:00", 60, 1, randomUUID()), null);
  const m = structuredClone(c);
  m.pools[0].capacity = 10000;
  m.pools[0].tariffs.forEach((t: any) => (t.rates[0].price_minor = 100000000));
  assert.equal(
    poolPriceAtStart(m, p.id, "2026-10-14", "10:00", 60, 10000),
    1e12,
  );
  const z = structuredClone(c);
  z.pools[0].tariffs.forEach((t: any) => (t.rates[0].price_minor = 0));
  assert.equal(poolPriceAtStart(z, p.id, "2026-10-14", "10:00", 60, 5), 0);
  const n = structuredClone(c);
  n.pools[0].tariffs.forEach((t: any) => (t.rates[0].price_minor = null));
  assert.equal(poolPriceAtStart(n, p.id, "2026-10-14", "10:00", 60, 5), null);
  const r = structuredClone(c);
  r.pools[0].regular_swimming = false;
  assert.equal(poolPriceAtStart(r, p.id, "2026-10-14", "10:00", 60), null);
});
test("pool group price: exact / up_to / at_least boundaries around the head count", () => {
  const raw = base();
  const mode = (m: string) => {
    const x = structuredClone(raw);
    x.group_offers[0].group_mode = m;
    x.group_offers[0].people = 10;
    return poolConfigurationSchema.parse(x);
  };
  const quote = (c: any, people: number, time = "10:00", date = "2026-10-14") =>
    poolGroupPrice(c, c.group_offers[0].id, c.pools[0].id, date, time, people);
  const exact = mode("exact"),
    upTo = mode("up_to"),
    atLeast = mode("at_least");
  assert.deepEqual(
    [9, 10, 11].map((n) => quote(exact, n)),
    [null, 100000, null],
  );
  assert.deepEqual(
    [9, 10, 11].map((n) => quote(upTo, n)),
    [100000, 100000, null],
  );
  assert.deepEqual(
    [9, 10, 11, 20, 21].map((n) => quote(atLeast, n)),
    [null, 100000, 100000, 100000, null],
  );
  for (const people of [0, -1, 1.5, NaN, Infinity])
    for (const c of [exact, upTo, atLeast])
      assert.equal(quote(c, people), null, String(people));
  assert.equal(quote(exact, 10, "24:00"), null);
  assert.equal(quote(exact, 10, "10:00", "2026-02-30"), null);
  assert.equal(quote(exact, 10, "05:00"), null);
  assert.equal(
    poolGroupPrice(
      exact,
      randomUUID(),
      exact.pools[0].id,
      "2026-10-14",
      "10:00",
      10,
    ),
    null,
  );
  assert.equal(
    poolGroupPrice(
      exact,
      exact.group_offers[0].id,
      randomUUID(),
      "2026-10-14",
      "10:00",
      10,
    ),
    null,
  );
  assert.equal(
    poolGroupPrice(
      exact,
      exact.group_offers[0].id,
      exact.pools[1].id,
      "2026-10-14",
      "10:00",
      10,
    ),
    null,
  ); // pool not eligible
  const free = structuredClone(exact);
  free.group_offers[0].price_minor = 0;
  assert.equal(quote(free, 10), 0);
  const unpriced = structuredClone(exact);
  unpriced.group_offers[0].price_minor = null;
  assert.equal(quote(unpriced, 10), null);
});

// ------------------------------------------------------------ service level
async function fixture(type = "pool") {
  const uid = randomUUID(),
    owner: Actor = { uid, email: `${uid}@example.com`, name: "Owner" };
  await workspace.createOrganization(owner, {
    name: "Pool Field QA",
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
    name: "Pools",
    type,
    location_id: w.locations[0].id,
  });
  return { owner, id: b.id };
}
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());
test("pool configure: version rules, replay and stale saves", async () => {
  const { owner, id } = await fixture(),
    c = poolConfigurationSchema.parse(base());
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
test("pool configure: invalid bodies leave resources and version intact", async () => {
  const { owner, id } = await fixture(),
    good = poolConfigurationSchema.parse(base());
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
    { version: 2, configuration: { ...good, kind: "hall_v1" } },
    {
      version: 2,
      configuration: { ...good, pools: [{ ...good.pools[0], capacity: 0 }] },
    },
  ])
    await bad(
      () => service.configure(owner, id, body),
      JSON.stringify(body)?.slice(0, 70),
    );
  assert.equal(await snap(), s0);
});
test("pool configure: wrong business type, foreign tenant, unknown id and non-owner are rejected", async () => {
  const { owner, id } = await fixture(),
    c = poolConfigurationSchema.parse(base());
  const court = await fixture("badminton");
  await assert.rejects(
    () =>
      service.configure(court.owner, court.id, {
        version: 1,
        configuration: c,
      }),
    /pool business/i,
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
test("pool configure: plan coach must be an active coach on the team (unknown, foreign and non-coach ids)", async () => {
  const a = await fixture(),
    b = await fixture();
  const c = poolConfigurationSchema.parse(base());
  c.plans[1].coach_id = randomUUID();
  await assert.rejects(
    () => service.configure(a.owner, a.id, { version: 1, configuration: c }),
    /active coach/,
  );
  const foreign = (await workspace.workspace(b.owner)).membership.id; // another tenant's owner
  c.plans[1].coach_id = foreign;
  await assert.rejects(
    () => service.configure(a.owner, a.id, { version: 1, configuration: c }),
    /active coach/,
  );
  c.plans[1].coach_id = (await workspace.workspace(a.owner)).membership.id; // own owner, but not opted in as a coach
  await assert.rejects(
    () => service.configure(a.owner, a.id, { version: 1, configuration: c }),
    /not marked as a coach/,
  );
  assert.equal((await workspace.workspace(a.owner)).businesses[0].version, 1);
});
test("pool configure: unicode and SQL-looking names persist literally; stolen ids rejected atomically", async () => {
  const a = await fixture(),
    b = await fixture(),
    c = poolConfigurationSchema.parse(base());
  c.pools[0].name = "Pool'); DROP TABLE resources;-- 名前 🏊";
  await service.configure(a.owner, a.id, { version: 1, configuration: c });
  assert.ok(
    (await workspace.workspace(a.owner)).businesses[0].resources.some(
      (r: any) => r.name === c.pools[0].name,
    ),
  );
  const stolen = poolConfigurationSchema.parse(base());
  stolen.pools[0].id = c.pools[0].id;
  stolen.plans = [];
  stolen.group_offers = [];
  await bad(() =>
    service.configure(b.owner, b.id, { version: 1, configuration: stolen }),
  );
  assert.equal((await workspace.workspace(b.owner)).businesses[0].version, 1);
});
test(
  "pool configure: a NUL byte in a pool name is a client error, not a server error",
  { todo: "BUG-4" },
  async () => {
    const { owner, id } = await fixture(),
      c = poolConfigurationSchema.parse(base());
    c.pools[0].name = "Bad\u0000Pool";
    await bad(() =>
      service.configure(owner, id, { version: 1, configuration: c }),
    );
  },
);
test("pool configure: parallel saves at the same version apply exactly once", async () => {
  const { owner, id } = await fixture();
  const r = await Promise.allSettled(
    [1, 2, 3].map(() =>
      service.configure(owner, id, {
        version: 1,
        configuration: poolConfigurationSchema.parse(base()),
      }),
    ),
  );
  assert.equal(r.filter((x) => x.status === "fulfilled").length, 1);
  assert.equal((await workspace.workspace(owner)).businesses[0].version, 2);
});
test("pool configure: an active pool rejects incomplete or expired edits atomically", async () => {
  const { owner, id } = await fixture(),
    c = poolConfigurationSchema.parse(base());
  await service.configure(owner, id, { version: 1, configuration: c });
  await workspace.activate(owner, id);
  const b = (await workspace.workspace(owner)).businesses[0];
  const noDepth = structuredClone(c);
  noDepth.pools[0].depth_min_ft = null;
  await assert.rejects(
    () =>
      service.configure(owner, id, {
        version: b.version,
        configuration: noDepth,
      }),
    /minimum and maximum depths/,
  );
  const past = structuredClone(c);
  Object.assign(past.plans[0], {
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
