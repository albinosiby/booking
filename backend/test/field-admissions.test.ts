import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { BadRequestException } from "@nestjs/common";
import {
  enrollmentSchema,
  createAdmissionSchema,
  expiryFrom,
  fixedDates,
  interval,
  validSwimmingDuration,
  planSpaceIds,
  admissionSpaces,
  coachName,
} from "../src/admissions/admission.rules";

const base = () => ({
  business_id: randomUUID(),
  resource_id: randomUUID(),
  plan_id: randomUUID(),
  starts_on: "2033-01-03",
  mode: "fixed" as const,
  weekdays: [1, 3],
  time: "07:00",
  duration_minutes: 60,
  customer: { id: null, name: "Asha Nair", phone: "9876543210", email: null },
  payments: [] as unknown[],
});
const ok = (o: Record<string, unknown> = {}) =>
  enrollmentSchema.safeParse({ ...base(), ...o }).success;

test("enrolment fields: ids, dates, mode, weekdays, time and duration", () => {
  assert.ok(ok());
  for (const [k, v] of [
    ["business_id", ""],
    ["business_id", "abc"],
    ["business_id", null],
    ["business_id", "'; --"],
    ["resource_id", ""],
    ["resource_id", 5],
    ["plan_id", "x"],
    ["plan_id", undefined],
    ["starts_on", ""],
    ["starts_on", " "],
    ["starts_on", "2033-02-30"],
    ["starts_on", "2033-1-3"],
    ["starts_on", null],
    ["starts_on", "😀"],
    ["mode", ""],
    ["mode", "Fixed"],
    ["mode", "monthly"],
    ["mode", null],
    ["weekdays", [0]],
    ["weekdays", [8]],
    ["weekdays", [-1]],
    ["weekdays", [1.5]],
    ["weekdays", ["1"]],
    ["weekdays", [1, 2, 3, 4, 5, 6, 7, 1]],
    ["weekdays", "1"],
    ["weekdays", null],
    ["time", ""],
    ["time", "24:00"],
    ["time", "7:00"],
    ["time", "07:00:00"],
    ["time", null],
    ["duration_minutes", 0],
    ["duration_minutes", 29],
    ["duration_minutes", 1441],
    ["duration_minutes", -30],
    ["duration_minutes", 30.5],
    ["duration_minutes", "60"],
    ["duration_minutes", null],
    ["payments", "x"],
    ["payments", null],
    ["payments", Array.from({ length: 21 }, () => ({}))],
    ["customer", null],
    ["customer", { id: null, name: "", phone: "9876543210", email: null }],
    ["customer", { id: null, name: "Asha", phone: "12", email: null }],
    ["renewed_from", "abc"],
    ["renewed_from", 5],
  ] as [string, unknown][])
    assert.equal(ok({ [k]: v }), false, `${k}=${JSON.stringify(v)}`);
  for (const [k, v] of [
    ["weekdays", []],
    ["weekdays", [1, 2, 3, 4, 5, 6, 7]],
    ["duration_minutes", 30],
    ["duration_minutes", 1440],
    ["mode", "flexible"],
    ["mode", "membership"],
    ["renewed_from", null],
    ["renewed_from", randomUUID()],
    ["starts_on", "2032-02-29"],
  ] as [string, unknown][])
    assert.equal(ok({ [k]: v }), true, `${k}=${JSON.stringify(v)}`);
  assert.equal(ok({ extra: 1 }), false);
  assert.equal(
    ok({ weekdays: [1, 1] }),
    true,
    "duplicate weekdays pass the schema; fixedDates rejects them",
  );
  const create = (o: Record<string, unknown>) =>
    createAdmissionSchema.safeParse({
      ...base(),
      command_key: randomUUID(),
      preview_token: "a".repeat(64),
      ...o,
    }).success;
  assert.ok(create({}));
  for (const [k, v] of [
    ["command_key", ""],
    ["command_key", "abc"],
    ["command_key", null],
    ["preview_token", ""],
    ["preview_token", "a".repeat(63)],
    ["preview_token", "A".repeat(64)],
    ["preview_token", "g".repeat(64)],
    ["preview_token", null],
  ] as [string, unknown][])
    assert.equal(create({ [k]: v }), false, `${k}=${JSON.stringify(v)}`);
});
test("expiryFrom: month ends, leap days, year spans and every mode", () => {
  assert.equal(
    expiryFrom(
      { expiry_mode: "fixed_date", expiry_date: "2033-12-31" },
      "2033-01-01",
    ),
    "2033-12-31",
  );
  assert.equal(
    expiryFrom({ expiry_mode: "after_start", expiry_days: 0 }, "2033-01-31"),
    "2033-01-31",
  );
  assert.equal(
    expiryFrom({ expiry_mode: "after_start", expiry_days: 30 }, "2033-01-31"),
    "2033-03-02",
  );
  assert.equal(
    expiryFrom({ expiry_mode: "after_start", expiry_days: 366 }, "2032-02-29"),
    "2033-03-01",
  );
  assert.equal(
    expiryFrom({ expiry_mode: "after_months", expiry_months: 1 }, "2033-01-31"),
    "2033-02-28",
  );
  assert.equal(
    expiryFrom({ expiry_mode: "after_months", expiry_months: 1 }, "2032-01-31"),
    "2032-02-29",
  );
  assert.equal(
    expiryFrom(
      { expiry_mode: "after_months", expiry_months: 12 },
      "2032-02-29",
    ),
    "2033-02-28",
  );
  assert.equal(
    expiryFrom(
      { expiry_mode: "after_months", expiry_months: 13 },
      "2033-12-31",
    ),
    "2035-01-31",
  );
  assert.equal(
    expiryFrom({ expiry_mode: "after_years", expiry_years: 1 }, "2032-02-29"),
    "2033-02-28",
  );
  assert.equal(
    expiryFrom({ expiry_mode: "after_years", expiry_years: 4 }, "2032-02-29"),
    "2036-02-29",
  );
  assert.equal(
    expiryFrom({ expiry_mode: "after_months", expiry_months: 0 }, "2033-05-17"),
    "2033-05-17",
  );
  assert.equal(
    expiryFrom(
      { expiry_mode: "after_months", expiry_months: 1200 },
      "2033-05-17",
    ),
    "2133-05-17",
  );
});
test("expiryFrom never returns a made-up date for an unknown mode or missing duration", () => {
  assert.throws(() => expiryFrom({ expiry_mode: "forever" }, "2033-01-01"));
  assert.throws(() =>
    expiryFrom({ expiry_mode: "after_months" }, "2033-01-01"),
  );
});
test("fixedDates: empty and duplicate weekdays, zero/negative allowance, expiry boundary", () => {
  assert.throws(
    () => fixedDates("2033-01-03", "2033-12-31", [], 5),
    BadRequestException,
  );
  assert.throws(
    () => fixedDates("2033-01-03", "2033-12-31", [1, 1], 5),
    BadRequestException,
  );
  assert.deepEqual(fixedDates("2033-01-03", "2033-12-31", [1], 3), [
    "2033-01-03",
    "2033-01-10",
    "2033-01-17",
  ]);
  assert.deepEqual(
    fixedDates("2033-01-03", "2033-01-17", [1], 3),
    ["2033-01-03", "2033-01-10", "2033-01-17"],
    "expiry day is inclusive",
  );
  assert.throws(
    () => fixedDates("2033-01-03", "2033-01-16", [1], 3),
    /Only 2 of 3/,
  );
  assert.throws(
    () => fixedDates("2033-01-04", "2033-01-03", [1, 2], 1),
    /Only 0 of 1/,
    "expiry before start",
  );
  assert.deepEqual(
    fixedDates("2033-01-03", "2033-12-31", [1], 0),
    [],
    "zero allowance selects nothing",
  );
  assert.throws(
    () => fixedDates("2033-01-03", "2033-12-31", [1], -1),
    BadRequestException,
    "a negative allowance must be refused",
  );
  assert.equal(
    fixedDates("2033-01-01", "2033-12-31", [1, 2, 3, 4, 5, 6, 7], 365).length,
    365,
  );
  assert.equal(fixedDates("2032-12-31", "2033-12-31", [7], 1)[0], "2033-01-02");
});
test("validSwimmingDuration: minimum, 30 minute steps and 24 hour ceiling", () => {
  const pool = { default_duration_minutes: 60 };
  for (const d of [60, 90, 120, 1440])
    assert.equal(validSwimmingDuration(pool, d), true, String(d));
  for (const d of [
    0,
    30,
    59,
    61,
    75,
    1441,
    1470,
    -60,
    Number.NaN,
    Infinity,
    90.5,
    "60" as any,
    null as any,
  ])
    assert.equal(validSwimmingDuration(pool, d), false, String(d));
  assert.equal(validSwimmingDuration({ durations: [45] }, 75), true);
  assert.equal(validSwimmingDuration({}, 60), true, "defaults to 60 minutes");
  assert.equal(
    validSwimmingDuration({ default_duration_minutes: 0 }, 30),
    true,
    "a zero minimum is accepted as-is",
  );
});
test("interval: operating hours, plan availability, midnight, overnight, 24-hour spaces and DST", () => {
  const hours = (o: Record<string, unknown> = {}) => ({
    days: [1, 2, 3, 4, 5, 6, 7],
    opens_at: "06:00",
    closes_at: "22:00",
    date_from: null,
    date_until: null,
    ...o,
  });
  const pool = { operating: hours(), default_duration_minutes: 60 };
  const swim = { kind: "swimming", availability: hours() };
  const date = "2033-01-04";
  const at = (
    time: string,
    d = 60,
    p: any = pool,
    plan: any = swim,
    day = date,
    zone = "Asia/Kolkata",
  ) => interval(p, plan, day, time, d, zone);
  assert.equal(at("06:00").local_start, `${date}T06:00`);
  assert.equal(
    at("21:00").local_end,
    `${date}T22:00`,
    "ending exactly at closing is allowed",
  );
  for (const t of ["05:59", "21:01", "22:00", "23:00", "00:00"])
    assert.throws(() => at(t), BadRequestException, t);
  assert.throws(
    () => at("06:00", 1020),
    BadRequestException,
    "17h exceeds 16h window",
  );
  assert.equal(at("06:00", 960).local_end, `${date}T22:00`);
  assert.throws(() => at("06:00", 0), BadRequestException, "zero duration");
  assert.throws(
    () => at("06:00", -60),
    BadRequestException,
    "negative duration",
  );
  assert.throws(() => at("06:00", 1440 + 30), BadRequestException);
  // plan narrower than the pool wins
  assert.throws(
    () =>
      at("06:00", 60, pool, {
        kind: "swimming",
        availability: hours({ opens_at: "08:00" }),
      }),
    BadRequestException,
  );
  assert.throws(
    () =>
      at("10:00", 60, pool, {
        kind: "swimming",
        availability: hours({ days: [1] }),
      }),
    BadRequestException,
    "Tuesday is not a plan day",
  );
  assert.throws(
    () =>
      at("10:00", 60, {
        ...pool,
        operating: hours({ date_from: "2033-02-01", date_until: "2033-02-28" }),
      }),
    BadRequestException,
    "outside season",
  );
  // coaching uses the configured class duration only
  const coach = {
    kind: "coaching",
    class_duration_minutes: 45,
    availability: hours(),
  };
  assert.equal(at("10:00", 45, pool, coach).local_end, `${date}T10:45`);
  for (const d of [30, 44, 46, 60])
    assert.throws(
      () => at("10:00", d, pool, coach),
      BadRequestException,
      String(d),
    );
  // overnight and all-day spaces
  const night = {
    operating: hours({ opens_at: "20:00", closes_at: "02:00" }),
    default_duration_minutes: 60,
  };
  const nightPlan = {
    kind: "swimming",
    availability: hours({ opens_at: "20:00", closes_at: "02:00" }),
  };
  assert.equal(
    interval(night, nightPlan, date, "23:30", 60, "Asia/Kolkata").local_end,
    "2033-01-05T00:30",
  );
  assert.equal(
    interval(night, nightPlan, date, "01:00", 60, "Asia/Kolkata").local_end,
    `${date}T02:00`,
    "after midnight belongs to the previous operating day",
  );
  assert.throws(
    () => interval(night, nightPlan, date, "01:30", 60, "Asia/Kolkata"),
    BadRequestException,
    "ends after 02:00",
  );
  const allDay = {
    operating: hours({
      all_day: true,
      opens_at: "00:00",
      closes_at: "00:00",
      days: [2, 3],
    }),
    default_duration_minutes: 60,
  };
  const allPlan = {
    kind: "swimming",
    availability: hours({
      all_day: true,
      opens_at: "00:00",
      closes_at: "00:00",
      days: [2, 3],
    }),
  };
  assert.equal(
    interval(allDay, allPlan, date, "23:00", 60, "Asia/Kolkata").local_end,
    "2033-01-05T00:00",
  );
  assert.equal(
    interval(allDay, allPlan, date, "23:00", 120, "Asia/Kolkata").local_end,
    "2033-01-05T01:00",
    "Wednesday is open too",
  );
  assert.throws(
    () => interval(allDay, allPlan, "2033-01-05", "23:00", 120, "Asia/Kolkata"),
    BadRequestException,
    "spills into closed Thursday",
  );
  // DST
  assert.throws(
    () => interval(pool, swim, "2033-03-13", "02:30", 60, "America/New_York"),
    /missing or ambiguous/,
  );
  assert.throws(
    () => interval(pool, swim, "2033-11-06", "01:30", 60, "America/New_York"),
    /missing or ambiguous/,
  );
  assert.ok(
    interval(pool, swim, "2033-03-13", "07:00", 60, "America/New_York")
      .starts_at,
  );
});
test("small helpers: planSpaceIds, admissionSpaces, coachName", () => {
  assert.deepEqual(planSpaceIds({ pool_ids: ["a"] }), ["a"]);
  assert.deepEqual(planSpaceIds({ court_ids: ["b"] }), ["b"]);
  assert.deepEqual(planSpaceIds({}), []);
  assert.deepEqual(admissionSpaces(null), []);
  assert.deepEqual(admissionSpaces(undefined), []);
  assert.deepEqual(admissionSpaces({ kind: "hall_v1", halls: [1] }), []);
  assert.deepEqual(admissionSpaces({ kind: "pool_v1", pools: [1] }), [1]);
  assert.equal(coachName(new Map(), null), "Unassigned");
  assert.equal(coachName(new Map(), "x"), "Unassigned");
  assert.equal(coachName(new Map([["x", "Coach 😀"]]), "x"), "Coach 😀");
});
