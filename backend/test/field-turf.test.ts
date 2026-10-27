// Field-value / boundary tests for the Turf module: grounds, layouts, football/cricket offerings,
// time-band pricing rules, hours overrides, pricing helper and the configure() service.
import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { HttpException } from "@nestjs/common";
import { ZodError } from "zod";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { TurfService } from "../src/turf/turf.service";
import { Actor } from "../src/common/auth.guard";
import {
  turfConfigurationSchema,
  turfSaveSchema,
  assertTurfComplete,
  turfPriceAtStart,
} from "../src/turf/turf.validation";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  workspace = new WorkspaceService(db),
  service = new TurfService(db, workspace);
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
function base(): any {
  const ground = randomUUID(),
    a = randomUUID(),
    b = randomUUID();
  const layouts = [
    { id: randomUUID(), ground_id: ground, name: "Half A", section_ids: [a] },
    { id: randomUUID(), ground_id: ground, name: "Half B", section_ids: [b] },
    {
      id: randomUUID(),
      ground_id: ground,
      name: "Full Ground",
      section_ids: [a, b],
    },
  ];
  return {
    kind: "turf_v1",
    schema_version: 1,
    sports: ["football", "cricket"],
    grounds: [
      {
        id: ground,
        name: "Main Ground",
        arrangement: "split",
        sections: [
          { id: a, name: "Section A" },
          { id: b, name: "Section B" },
        ],
      },
    ],
    layouts,
    offerings: layouts.flatMap((l, i) =>
      ["football", "cricket"].map((s) => ({
        id: randomUUID(),
        layout_id: l.id,
        sport: s,
        name: `${s} ${i}`,
        format: s === "football" ? "5s" : "Half ground",
        enabled: true,
        rates: [{ duration_minutes: 60, price_minor: 150000 }],
        buffer_before: 0,
        buffer_after: 0,
        hours_override: null,
      })),
    ),
    operating: {
      days: [1, 2, 3, 4, 5, 6, 7],
      opens_at: "06:00",
      closes_at: "23:00",
    },
  };
}
type Case = [string, (c: any) => void];
function sweep(
  cases: Case[],
  expectValid: boolean,
  schema = turfConfigurationSchema,
) {
  const failures: string[] = [];
  for (const [label, mutate] of cases) {
    const c = base();
    let ok: boolean,
      why = "";
    try {
      mutate(c);
      const r = schema.safeParse(c);
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
const O0 = (...r: (string | number)[]) => ["offerings", 0, ...r];
const rule = (extra: Record<string, any> = {}) => ({
  id: randomUUID(),
  days: [1, 2, 3, 4, 5, 6, 7],
  starts_at: "06:00",
  ends_at: "23:00",
  rates: [{ duration_minutes: 60, price_minor: 100 }],
  ...extra,
});
const withRules = (rules: any[]) => (c: any) =>
  c.offerings.forEach(
    (o: any) =>
      (o.pricing_rules = rules.map((r) => ({
        ...structuredClone(r),
        id: randomUUID(),
      }))),
  );

test("turf sports and shared envelope fields", () => {
  sweep(
    [
      ["duplicate sports", set(["sports"], ["football", "football"])],
      ["unknown sport", set(["sports"], ["hockey"])],
      ["3 sports", set(["sports"], ["football", "cricket", "football"])],
      ["sports null", set(["sports"], null)],
      ["sports string", set(["sports"], "football")],
      ["wrong kind", set(["kind"], "court_v1")],
      ["schema_version 2", set(["schema_version"], 2)],
      ["unknown key", set(["extra"], 1)],
      ["cricket_uses_football string", set(["cricket_uses_football"], "yes")],
      [
        "offering enabled for a sport not selected",
        set(["sports"], ["football"]),
      ],
      [
        "linked cricket with different price",
        (c) => {
          c.cricket_uses_football = true;
          c.offerings[1].rates[0].price_minor = 1;
        },
      ],
      [
        "linked cricket without football sport",
        (c) => {
          c.cricket_uses_football = true;
          c.sports = ["cricket"];
        },
      ],
    ],
    false,
  );
  sweep(
    [
      [
        "one sport",
        (c) => {
          c.sports = ["football"];
          c.offerings.forEach(
            (o: any) => o.sport === "cricket" && (o.enabled = false),
          );
        },
      ],
      [
        "no sports (draft)",
        (c) => {
          c.sports = [];
          c.offerings.forEach((o: any) => (o.enabled = false));
        },
      ],
      [
        "cricket mirrors football",
        (c) => {
          c.cricket_uses_football = true;
        },
      ],
    ],
    true,
  );
});
test("turf grounds, sections and layouts: names, counts and topology", () => {
  sweep(
    [
      ...gen(
        "ground name",
        ["grounds", 0, "name"],
        ["", " ", "a", "g".repeat(101), null, 5],
      ),
      ...gen(
        "section name",
        ["grounds", 0, "sections", 0, "name"],
        ["", "a", "s".repeat(101), null],
      ),
      ...gen(
        "layout name",
        ["layouts", 0, "name"],
        ["", " ", "a", "l".repeat(101), null],
      ),
      [
        "duplicate layout names",
        (c) => (c.layouts[1].name = c.layouts[0].name),
      ],
      [
        "duplicate layout names case-insensitive",
        (c) => (c.layouts[1].name = c.layouts[0].name.toLowerCase()),
      ],
      ...gen("arrangement", ["grounds", 0, "arrangement"], ["quad", "", null]),
      ["no grounds", set(["grounds"], [])],
      [
        "11 grounds",
        (c) =>
          (c.grounds = Array.from({ length: 11 }, () => ({
            ...structuredClone(c.grounds[0]),
            id: randomUUID(),
          }))),
      ],
      ["0 sections", set(["grounds", 0, "sections"], [])],
      [
        "3 sections",
        (c) =>
          c.grounds[0].sections.push({ id: randomUUID(), name: "Section C" }),
      ],
      [
        "duplicate section ids",
        (c) => (c.grounds[0].sections[1].id = c.grounds[0].sections[0].id),
      ],
      ["no layouts", set(["layouts"], [])],
      [
        "31 layouts",
        (c) =>
          (c.layouts = Array.from({ length: 31 }, (_, i) => ({
            ...structuredClone(c.layouts[0]),
            id: randomUUID(),
            name: "L" + i + "x",
          }))),
      ],
      ["layout with no sections", set(["layouts", 0, "section_ids"], [])],
      [
        "layout with 3 sections",
        set(
          ["layouts", 0, "section_ids"],
          [randomUUID(), randomUUID(), randomUUID()],
        ),
      ],
      [
        "layout in unknown ground",
        set(["layouts", 0, "ground_id"], randomUUID()),
      ],
      [
        "layout uses a foreign section",
        set(["layouts", 0, "section_ids"], [randomUUID()]),
      ],
      [
        "layout repeats a section",
        (c) =>
          (c.layouts[2].section_ids = [
            c.grounds[0].sections[0].id,
            c.grounds[0].sections[0].id,
          ]),
      ],
      [
        "split ground without full layout",
        (c) => {
          c.layouts.pop();
          c.offerings = c.offerings.slice(0, 4);
        },
      ],
      [
        "single ground with split topology",
        set(["grounds", 0, "arrangement"], "single"),
      ],
      ["duplicate layout ids", (c) => (c.layouts[1].id = c.layouts[0].id)],
      ["ids are not uuids", set(["layouts", 0, "id"], "l1")],
      ["layout unknown key", set(["layouts", 0, "extra"], 1)],
    ],
    false,
  );
  sweep(
    [
      ...gen(
        "ground name",
        ["grounds", 0, "name"],
        ["ab", "g".repeat(100), "Ünï Ground 名前 ⚽"],
      ),
      ...gen(
        "layout name",
        ["layouts", 0, "name"],
        ["ab", "l".repeat(100), "Half'); DROP TABLE resources;--"],
      ),
      [
        "single ground",
        (c) => {
          const g = randomUUID(),
            s = randomUUID(),
            l = randomUUID();
          c.grounds = [
            {
              id: g,
              name: "Only ground",
              arrangement: "single",
              sections: [{ id: s, name: "Whole" }],
            },
          ];
          c.layouts = [
            { id: l, ground_id: g, name: "Whole", section_ids: [s] },
          ];
          c.offerings = c.offerings
            .slice(0, 2)
            .map((o: any) => ({ ...o, layout_id: l }));
        },
      ],
    ],
    true,
  );
});
test("turf offerings: count, sport, format, names, duplicate pairs", () => {
  sweep(
    [
      ...gen("sport", O0("sport"), ["hockey", "", "FOOTBALL", null]),
      ...gen("format", O0("format"), ["", " ", "x", "f".repeat(41), null, 5]),
      ...gen("offering name", O0("name"), ["", "a", "n".repeat(101), null]),
      ...gen("enabled", O0("enabled"), ["true", 1, null]),
      ["missing offering", (c) => c.offerings.pop()],
      [
        "extra offering",
        (c) =>
          c.offerings.push({
            ...structuredClone(c.offerings[0]),
            id: randomUUID(),
          }),
      ],
      ["duplicate (layout,sport)", (c) => (c.offerings[1].sport = "football")],
      ["offering for unknown layout", set(O0("layout_id"), randomUUID())],
      [
        "duplicate offering ids",
        (c) => (c.offerings[1].id = c.offerings[0].id),
      ],
      [
        "61 offerings",
        (c) =>
          (c.offerings = Array.from({ length: 61 }, () => ({
            ...structuredClone(c.offerings[0]),
            id: randomUUID(),
          }))),
      ],
      ["1 offering", (c) => (c.offerings = [c.offerings[0]])],
      ["offering unknown key", set(O0("extra"), 1)],
    ],
    false,
  );
  sweep(
    [
      ...gen("format", O0("format"), [
        "ab",
        "f".repeat(40),
        "7-a-side ⚽",
        "5s'); --",
      ]),
      ["disabled offering", set(O0("enabled"), false)],
    ],
    true,
  );
});
test("turf rates: duration 30..1440, price integer 0..100,000,000 or null, unique durations", () => {
  const R = O0("rates", 0);
  sweep(
    [
      ...gen(
        "price",
        [...R, "price_minor"],
        [
          -1,
          -0.01,
          0.5,
          1499.99,
          0.1 + 0.2,
          NaN,
          Infinity,
          -Infinity,
          "150000",
          "1e5",
          true,
          100000001,
          Number.MAX_SAFE_INTEGER,
          1e21,
          undefined,
        ],
      ),
      ...gen(
        "duration",
        [...R, "duration_minutes"],
        [0, 29, -60, 1441, 60.5, NaN, Infinity, "60", null, 1e9],
      ),
      ["no rates", set(O0("rates"), [])],
      [
        "11 rates",
        set(
          O0("rates"),
          Array.from({ length: 11 }, (_, i) => ({
            duration_minutes: 30 + i * 30,
            price_minor: 1,
          })),
        ),
      ],
      [
        "duplicate durations",
        (c) =>
          c.offerings[0].rates.push({ duration_minutes: 60, price_minor: 1 }),
      ],
      ["rate unknown key", set([...R, "currency"], "INR")],
      ["default duration not a rate", set(O0("default_duration_minutes"), 90)],
      ...gen("default_duration", O0("default_duration_minutes"), [
        0,
        29,
        1441,
        60.5,
        "60",
        null,
      ]),
      ...gen("buffer_before", O0("buffer_before"), [
        -1,
        241,
        1.5,
        NaN,
        Infinity,
        "0",
        null,
        1e9,
      ]),
      ...gen("buffer_after", O0("buffer_after"), [
        -1,
        241,
        1.5,
        NaN,
        Infinity,
        "0",
        null,
        1e9,
      ]),
    ],
    false,
  );
  sweep(
    [
      ...gen("price", [...R, "price_minor"], [0, 1, 99999999, 100000000, null]),
      ...gen("duration", [...R, "duration_minutes"], [30, 1440]),
      ...gen("buffer_before", O0("buffer_before"), [0, 1, 240]),
      ...gen("buffer_after", O0("buffer_after"), [0, 1, 240]),
      [
        "default duration",
        (c) => {
          c.offerings[0].rates.push({
            duration_minutes: 90,
            price_minor: 200000,
          });
          c.offerings[0].default_duration_minutes = 90;
        },
      ],
      [
        "10 rates",
        set(
          O0("rates"),
          Array.from({ length: 10 }, (_, i) => ({
            duration_minutes: 30 + i * 30,
            price_minor: 1,
          })),
        ),
      ],
    ],
    true,
  );
});
test("turf operating hours and per-offering overrides", () => {
  sweep(
    [
      ...gen(
        "days",
        ["operating", "days"],
        [
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
        ],
      ),
      ...gen(
        "opens_at",
        ["operating", "opens_at"],
        ["", "24:00", "6:00", "06:60", "06:00:00", null, 600],
      ),
      ...gen(
        "closes_at",
        ["operating", "closes_at"],
        ["", "24:00", "23:60", null],
      ),
      ["opens == closes", set(["operating", "closes_at"], "06:00")],
      ["all_day with non-midnight", set(["operating", "all_day"], true)],
      [
        "operating date_from is not supported",
        set(["operating", "date_from"], "2026-01-01"),
      ],
      [
        "override opens before operating",
        set(O0("hours_override"), {
          days: [1],
          opens_at: "05:00",
          closes_at: "10:00",
        }),
      ],
      [
        "override closes after operating",
        set(O0("hours_override"), {
          days: [1],
          opens_at: "10:00",
          closes_at: "23:30",
        }),
      ],
      [
        "override on a closed day",
        (c) => {
          c.operating.days = [1, 2];
          c.offerings[0].hours_override = {
            days: [3],
            opens_at: "10:00",
            closes_at: "12:00",
          };
        },
      ],
      [
        "override opens == closes",
        set(O0("hours_override"), {
          days: [1],
          opens_at: "10:00",
          closes_at: "10:00",
        }),
      ],
      [
        "override duplicate days",
        set(O0("hours_override"), {
          days: [1, 1],
          opens_at: "10:00",
          closes_at: "12:00",
        }),
      ],
      ["override string", set(O0("hours_override"), "none")],
      [
        "override unknown key",
        set(O0("hours_override"), {
          days: [1],
          opens_at: "10:00",
          closes_at: "12:00",
          x: 1,
        }),
      ],
    ],
    false,
  );
  sweep(
    [
      ["days subset", set(["operating", "days"], [6, 7])],
      [
        "24h",
        (c) =>
          (c.operating = {
            days: [1, 2, 3, 4, 5, 6, 7],
            opens_at: "00:00",
            closes_at: "00:00",
            all_day: true,
          }),
      ],
      [
        "overnight",
        (c) =>
          (c.operating = {
            days: [1, 2, 3, 4, 5, 6, 7],
            opens_at: "22:00",
            closes_at: "06:00",
          }),
      ],
      [
        "valid override",
        set(O0("hours_override"), {
          days: [1, 2],
          opens_at: "08:00",
          closes_at: "20:00",
        }),
      ],
      [
        "override equal to operating",
        set(O0("hours_override"), {
          days: [1, 2, 3, 4, 5, 6, 7],
          opens_at: "06:00",
          closes_at: "23:00",
        }),
      ],
    ],
    true,
  );
});
test("turf time-band pricing rules: bounds, overlaps, ids, rates and hours", () => {
  sweep(
    [
      [
        "duplicate rule ids",
        (c) => {
          const r = rule();
          c.offerings[0].pricing_rules = [
            r,
            {
              ...rule({ days: [1], starts_at: "07:00", ends_at: "08:00" }),
              id: r.id,
            },
          ];
        },
      ],
      [
        "band starts==ends (zero length)",
        withRules([rule({ starts_at: "10:00", ends_at: "10:00" })]),
      ],
      ["band all_day with non-midnight", withRules([rule({ all_day: true })])],
      ["band duplicate days", withRules([rule({ days: [1, 1] })])],
      ["band days empty", withRules([rule({ days: [] })])],
      ["band days 8", withRules([rule({ days: [8] })])],
      ["band time 24:00", withRules([rule({ starts_at: "24:00" })])],
      ["band time 6:00", withRules([rule({ starts_at: "6:00" })])],
      [
        "band outside operating hours",
        withRules([rule({ starts_at: "05:00", ends_at: "10:00" })]),
      ],
      [
        "band beyond closing",
        withRules([rule({ starts_at: "10:00", ends_at: "23:30" })]),
      ],
      [
        "band lacks a duration",
        withRules([
          rule({ rates: [{ duration_minutes: 90, price_minor: 1 }] }),
        ]),
      ],
      [
        "band rates repeated",
        withRules([
          rule({
            rates: [
              { duration_minutes: 60, price_minor: 1 },
              { duration_minutes: 60, price_minor: 2 },
            ],
          }),
        ]),
      ],
      [
        "band price negative",
        withRules([
          rule({ rates: [{ duration_minutes: 60, price_minor: -1 }] }),
        ]),
      ],
      [
        "band price decimal",
        withRules([
          rule({ rates: [{ duration_minutes: 60, price_minor: 10.5 }] }),
        ]),
      ],
      [
        "band price NaN",
        withRules([
          rule({ rates: [{ duration_minutes: 60, price_minor: NaN }] }),
        ]),
      ],
      [
        "band price max+1",
        withRules([
          rule({ rates: [{ duration_minutes: 60, price_minor: 100000001 }] }),
        ]),
      ],
      ["band no rates", withRules([rule({ rates: [] })])],
      [
        "bands overlap",
        withRules([
          rule({ starts_at: "06:00", ends_at: "12:00" }),
          rule({ starts_at: "11:59", ends_at: "15:00" }),
        ]),
      ],
      [
        "41 bands",
        (c) =>
          (c.offerings[0].pricing_rules = Array.from({ length: 41 }, (_, i) =>
            rule({ days: [1], starts_at: "06:00", ends_at: "07:00" }),
          )),
      ],
      ["band unknown key", withRules([rule({ extra: 1 })])],
    ],
    false,
  );
  sweep(
    [
      [
        "adjacent bands",
        withRules([
          rule({ starts_at: "06:00", ends_at: "12:00" }),
          rule({ starts_at: "12:00", ends_at: "23:00" }),
        ]),
      ],
      [
        "same hours different days",
        withRules([rule({ days: [1, 2, 3] }), rule({ days: [4, 5, 6, 7] })]),
      ],
      [
        "free band (price 0)",
        withRules([
          rule({ rates: [{ duration_minutes: 60, price_minor: 0 }] }),
        ]),
      ],
      [
        "unpriced band (draft)",
        withRules([
          rule({ rates: [{ duration_minutes: 60, price_minor: null }] }),
        ]),
      ],
      [
        "max price band",
        withRules([
          rule({ rates: [{ duration_minutes: 60, price_minor: 100000000 }] }),
        ]),
      ],
      ["no bands (empty array)", withRules([])],
    ],
    true,
  );
});
test("turf completeness for activation", () => {
  const ok = base();
  assert.ok(assertTurfComplete(ok));
  const unpriced = base();
  unpriced.offerings[0].rates[0].price_minor = null;
  assert.throws(() => assertTurfComplete(unpriced), /enter all enabled prices/);
  const noSports = base();
  noSports.sports = [];
  noSports.offerings.forEach((o: any) => (o.enabled = false));
  assert.throws(() => assertTurfComplete(noSports), /Select sports/);
  const spaceOff = base();
  spaceOff.offerings
    .filter((o: any) => o.layout_id === spaceOff.layouts[0].id)
    .forEach((o: any) => (o.enabled = false));
  assert.throws(
    () => assertTurfComplete(spaceOff),
    /enable an offering for every space/,
  );
  const sportOff = base();
  sportOff.offerings
    .filter((o: any) => o.sport === "cricket")
    .forEach((o: any) => (o.enabled = false));
  assert.throws(() => assertTurfComplete(sportOff), /Select sports/);
  const emptyRules = base();
  emptyRules.offerings[0].pricing_rules = [];
  assert.throws(
    () => assertTurfComplete(emptyRules),
    /Select sports|enter all enabled prices/,
  );
  const tooLong = base();
  tooLong.operating = { days: [1], opens_at: "10:00", closes_at: "10:30" };
  assert.throws(
    () => assertTurfComplete(tooLong),
    /fit the offering operating hours/,
  );
  const free = base();
  free.offerings.forEach((o: any) => (o.rates[0].price_minor = 0));
  assert.ok(assertTurfComplete(free));
  assert.throws(() => assertTurfComplete(null));
  assert.throws(() => assertTurfComplete({}));
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
    assert.equal(turfSaveSchema.safeParse(v).success, false, JSON.stringify(v));
});
test("turf price quote: garbage inputs return null; rounding is exact; zero price is a real price", () => {
  const c = turfConfigurationSchema.parse(base()),
    o = c.offerings[0];
  const q = (day: number, time: string, d: number, id = o.id) =>
    turfPriceAtStart(c, id, day, time, d);
  assert.equal(q(3, "10:00", 60), 150000);
  assert.equal(q(3, "10:00", 75), 187500);
  for (const [day, time, d] of [
    [0, "10:00", 60],
    [8, "10:00", 60],
    [-1, "10:00", 60],
    [1.5, "10:00", 60],
    [NaN, "10:00", 60],
    [Infinity, "10:00", 60],
    [3, "24:00", 60],
    [3, "10:60", 60],
    [3, "", 60],
    [3, "9:00", 60],
    [3, "10:00", 0],
    [3, "10:00", -60],
    [3, "10:00", 59],
    [3, "10:00", 61],
    [3, "10:00", 60.5],
    [3, "10:00", NaN],
    [3, "10:00", Infinity],
    [3, "10:00", 1441],
    [3, "10:00", 1e9],
    [3, "05:59", 60],
    [3, "22:30", 60],
  ] as [number, string, number][])
    assert.equal(q(day, time, d), null, `${day} ${time} ${d}`);
  assert.equal(q(3, "10:00", 60, randomUUID()), null);
  const z = structuredClone(c);
  z.offerings[0].rates[0].price_minor = 0;
  assert.equal(turfPriceAtStart(z, o.id, 3, "10:00", 60), 0);
  const n = structuredClone(c);
  n.offerings[0].rates[0].price_minor = null;
  assert.equal(turfPriceAtStart(n, o.id, 3, "10:00", 60), null);
  const d = structuredClone(c);
  d.offerings[0].enabled = false;
  assert.equal(turfPriceAtStart(d, o.id, 3, "10:00", 60), null);
  const r = structuredClone(c);
  r.offerings[0].rates = [{ duration_minutes: 60, price_minor: 1 }];
  assert.equal(turfPriceAtStart(r, o.id, 3, "10:00", 75), 1);
  assert.equal(turfPriceAtStart(r, o.id, 3, "10:00", 90), 2);
});
test("turf pricing rules: band boundaries use the booking start and gaps return null", () => {
  const raw = base();
  raw.offerings.forEach(
    (x: any) =>
      (x.pricing_rules = [
        rule({
          starts_at: "06:00",
          ends_at: "12:00",
          rates: [{ duration_minutes: 60, price_minor: 10 }],
        }),
        rule({
          starts_at: "12:00",
          ends_at: "18:00",
          rates: [{ duration_minutes: 60, price_minor: 20 }],
        }),
      ]),
  );
  const c = turfConfigurationSchema.parse(raw),
    id = c.offerings[0].id;
  assert.equal(turfPriceAtStart(c, id, 2, "11:59", 60), 10);
  assert.equal(turfPriceAtStart(c, id, 2, "12:00", 60), 20);
  assert.equal(turfPriceAtStart(c, id, 2, "17:59", 60), 20);
  assert.equal(turfPriceAtStart(c, id, 2, "18:00", 60), null); // gap: no silent fallback to the base rate
  assert.equal(turfPriceAtStart(c, id, 2, "18:00", 60), null);
});

// ------------------------------------------------------------ service level
async function fixture(type = "turf") {
  const uid = randomUUID(),
    owner: Actor = { uid, email: `${uid}@example.com`, name: "Owner" };
  await workspace.createOrganization(owner, {
    name: "Turf Field QA",
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
    name: "Turf",
    type,
    location_id: w.locations[0].id,
  });
  return { owner, id: b.id };
}
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());
test("turf configure: version rules, replay and stale saves", async () => {
  const { owner, id } = await fixture(),
    c = turfConfigurationSchema.parse(base());
  for (const version of [0, -1, 1.5, "1", null, undefined, NaN, Infinity, true])
    await bad(
      () => service.configure(owner, id, { version, configuration: c }),
      String(version),
    );
  await assert.rejects(
    () => service.configure(owner, id, { version: 2, configuration: c }),
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
  );
});
test("turf configure: invalid bodies leave topology and version intact", async () => {
  const { owner, id } = await fixture(),
    good = turfConfigurationSchema.parse(base());
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
    { version: 2, configuration: { ...good, kind: "court_v1" } },
    { version: 2, configuration: { ...good, layouts: [] } },
  ])
    await bad(
      () => service.configure(owner, id, body),
      JSON.stringify(body)?.slice(0, 70),
    );
  assert.equal(await snap(), s0);
});
test("turf configure: wrong business type, foreign tenant, unknown id and non-owner are rejected", async () => {
  const { owner, id } = await fixture(),
    c = turfConfigurationSchema.parse(base());
  const court = await fixture("badminton");
  await assert.rejects(
    () =>
      service.configure(court.owner, court.id, {
        version: 1,
        configuration: c,
      }),
    /turf business/i,
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
test("turf configure: unicode and SQL-looking layout names persist literally; NUL byte is a client error", async () => {
  const { owner, id } = await fixture(),
    c = turfConfigurationSchema.parse(base());
  c.layouts[0].name = "Half'); DROP TABLE resources;-- 名前 ⚽";
  c.layouts[1].name = "Ünïcödé Half";
  await service.configure(owner, id, { version: 1, configuration: c });
  const names = (await workspace.workspace(owner)).businesses[0].resources.map(
    (r: any) => r.name,
  );
  assert.ok(
    names.includes(c.layouts[0].name) && names.includes(c.layouts[1].name),
  );
});
test(
  "turf configure: a NUL byte in a layout name is a client error, not a server error",
  { todo: "BUG-4" },
  async () => {
    const { owner, id } = await fixture(),
      c = turfConfigurationSchema.parse(base());
    c.layouts[0].name = "Bad\u0000Half";
    await bad(() =>
      service.configure(owner, id, { version: 1, configuration: c }),
    );
  },
);
test("turf configure: stolen layout identifiers from another tenant are rejected atomically", async () => {
  const a = await fixture(),
    b = await fixture();
  const ca = turfConfigurationSchema.parse(base());
  await service.configure(a.owner, a.id, { version: 1, configuration: ca });
  const stolen = turfConfigurationSchema.parse(base());
  stolen.layouts[0].id = ca.layouts[0].id;
  stolen.offerings.filter((o: any) => o.layout_id !== ca.layouts[0].id).length;
  stolen.offerings
    .slice(0, 2)
    .forEach((o: any) => (o.layout_id = stolen.layouts[0].id));
  await bad(() =>
    service.configure(b.owner, b.id, { version: 1, configuration: stolen }),
  );
  assert.equal((await workspace.workspace(b.owner)).businesses[0].version, 1);
  assert.equal(
    (await workspace.workspace(b.owner)).businesses[0].resources.length,
    0,
  );
});
test("turf configure: parallel saves at the same version apply exactly once", async () => {
  const { owner, id } = await fixture();
  const r = await Promise.allSettled(
    [1, 2, 3].map(() =>
      service.configure(owner, id, {
        version: 1,
        configuration: turfConfigurationSchema.parse(base()),
      }),
    ),
  );
  assert.equal(r.filter((x) => x.status === "fulfilled").length, 1);
  assert.equal((await workspace.workspace(owner)).businesses[0].version, 2);
});
test("turf configure: an active turf rejects an unpriced edit atomically", async () => {
  const { owner, id } = await fixture(),
    c = turfConfigurationSchema.parse(base());
  await service.configure(owner, id, { version: 1, configuration: c });
  await workspace.activate(owner, id);
  const b = (await workspace.workspace(owner)).businesses[0];
  const broken = structuredClone(c);
  broken.offerings[0].rates[0].price_minor = null;
  await assert.rejects(
    () =>
      service.configure(owner, id, {
        version: b.version,
        configuration: broken,
      }),
    /enter all enabled prices/,
  );
  const after_ = (await workspace.workspace(owner)).businesses[0];
  assert.equal(after_.version, b.version);
  assert.equal(after_.status, "ready");
});
