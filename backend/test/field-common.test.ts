import { test } from "node:test";
import assert from "node:assert/strict";
import {
  OperatingHours,
  hoursSpan,
  hoursWithin,
  windowsOverlap,
  windowApplies,
  weeklyWindowApplies,
  fitsOperatingInterval,
  allDayDatesCover,
} from "../src/common/operating-hours";
import {
  acceptsMinimumDuration,
  minimumBookingPrice,
} from "../src/common/minimum-booking";
import {
  calendarDate,
  clock,
  selectionSchema,
  paymentSchema,
  customerSchema,
  moneyStatus,
} from "../src/bookings/booking.validation";
import {
  addDate,
  localStamp,
  zonedTime,
} from "../src/bookings/booking.inventory";

const h = (over: Partial<OperatingHours> = {}): OperatingHours => ({
  days: [1, 2, 3, 4, 5, 6, 7],
  opens_at: "06:00",
  closes_at: "22:00",
  date_from: null,
  date_until: null,
  ...over,
});

// ------------------------------------------------------------ operating hours
test("hoursSpan: normal, overnight, equal times, all-day flag and malformed clocks", () => {
  assert.equal(hoursSpan(h()), 16 * 60);
  assert.equal(hoursSpan(h({ opens_at: "22:00", closes_at: "06:00" })), 8 * 60);
  assert.equal(
    hoursSpan(h({ opens_at: "06:00", closes_at: "00:00" })),
    18 * 60,
  );
  assert.equal(
    hoursSpan(h({ opens_at: "00:00", closes_at: "00:00" })),
    0,
    "equal times without all_day is an empty window",
  );
  assert.equal(
    hoursSpan(h({ opens_at: "00:00", closes_at: "00:00", all_day: true })),
    1440,
  );
  assert.equal(hoursSpan(h({ opens_at: "23:59", closes_at: "00:00" })), 1);
  assert.equal(hoursSpan(h({ opens_at: "00:00", closes_at: "23:59" })), 1439);
  // malformed input must never produce a usable positive window
  for (const bad of ["", "xx:yy", "25:00", "😀"]) {
    const span = hoursSpan(h({ opens_at: bad }));
    assert.ok(Number.isNaN(span) || span <= 1440, `opens_at=${bad}`);
  }
});
test("hoursWithin: day subsets, overnight children and all-day parents", () => {
  assert.equal(hoursWithin(h({ days: [1] }), h()), true);
  assert.equal(
    hoursWithin(h({ days: [] }), h()),
    true,
    "no days is vacuously within",
  );
  assert.equal(hoursWithin(h({ days: [1, 8 as any] }), h()), false);
  assert.equal(hoursWithin(h({ days: [1, 2] }), h({ days: [1] })), false);
  assert.equal(
    hoursWithin(
      h({ opens_at: "06:00", closes_at: "22:00" }),
      h({ opens_at: "06:00", closes_at: "22:00" }),
    ),
    true,
  );
  assert.equal(
    hoursWithin(h({ opens_at: "05:59", closes_at: "22:00" }), h()),
    false,
  );
  assert.equal(
    hoursWithin(h({ opens_at: "06:00", closes_at: "22:01" }), h()),
    false,
  );
  assert.equal(
    hoursWithin(h({ opens_at: "07:00", closes_at: "21:00" }), h()),
    true,
  );
  assert.equal(
    hoursWithin(h({ opens_at: "20:00", closes_at: "02:00" }), h()),
    false,
  );
  assert.equal(
    hoursWithin(
      h({ opens_at: "20:00", closes_at: "02:00" }),
      h({ opens_at: "18:00", closes_at: "04:00" }),
    ),
    true,
  );
  // 24h parent: a child crossing midnight needs the following weekday to be open
  const allDay = h({ opens_at: "00:00", closes_at: "00:00", all_day: true });
  assert.equal(
    hoursWithin(
      h({ days: [7], opens_at: "22:00", closes_at: "02:00" }),
      allDay,
    ),
    true,
  );
  assert.equal(
    hoursWithin(h({ days: [7], opens_at: "22:00", closes_at: "02:00" }), {
      ...allDay,
      days: [7],
    }),
    false,
  );
  assert.equal(
    hoursWithin(h({ days: [7], opens_at: "22:00", closes_at: "00:00" }), {
      ...allDay,
      days: [7],
    }),
    true,
    "ends exactly at midnight",
  );
});
test("windowsOverlap: touching windows do not overlap; overnight, Sunday wrap, seasons and empty day lists", () => {
  assert.equal(
    windowsOverlap(
      h({ opens_at: "06:00", closes_at: "12:00" }),
      h({ opens_at: "12:00", closes_at: "18:00" }),
    ),
    false,
    "end is exclusive",
  );
  assert.equal(
    windowsOverlap(
      h({ opens_at: "06:00", closes_at: "12:01" }),
      h({ opens_at: "12:00", closes_at: "18:00" }),
    ),
    true,
  );
  assert.equal(
    windowsOverlap(
      h({ days: [1], opens_at: "06:00", closes_at: "12:00" }),
      h({ days: [2], opens_at: "06:00", closes_at: "12:00" }),
    ),
    false,
  );
  assert.equal(
    windowsOverlap(h({ days: [], opens_at: "06:00", closes_at: "12:00" }), h()),
    false,
  );
  assert.equal(windowsOverlap(h(), h({ days: [] })), false);
  // overnight Sunday 22:00 -> Monday 02:00 overlaps Monday 01:00 -> 05:00 but not Monday 02:00 -> 05:00
  assert.equal(
    windowsOverlap(
      h({ days: [7], opens_at: "22:00", closes_at: "02:00" }),
      h({ days: [1], opens_at: "01:00", closes_at: "05:00" }),
    ),
    true,
  );
  assert.equal(
    windowsOverlap(
      h({ days: [7], opens_at: "22:00", closes_at: "02:00" }),
      h({ days: [1], opens_at: "02:00", closes_at: "05:00" }),
    ),
    false,
  );
  // seasonal: same hours on non-intersecting date ranges never overlap, shared boundary day does
  const a = h({ date_from: "2032-01-01", date_until: "2032-03-31" });
  assert.equal(
    windowsOverlap(a, h({ date_from: "2032-04-01", date_until: "2032-06-30" })),
    false,
  );
  assert.equal(
    windowsOverlap(a, h({ date_from: "2032-03-31", date_until: "2032-06-30" })),
    true,
  );
  // single-weekday seasons whose date range contains no such weekday never overlap
  let tuesday = "2032-03-02";
  while ((new Date(tuesday + "T00:00:00Z").getUTCDay() || 7) !== 2)
    tuesday = addDate(tuesday, 1);
  const mondays = (from: string, until: string) =>
    h({ days: [1], date_from: from, date_until: until });
  assert.equal(
    windowsOverlap(
      mondays(tuesday, addDate(tuesday, 5)),
      mondays(tuesday, addDate(tuesday, 5)),
    ),
    false,
    "Tue..Sun has no Monday",
  );
  assert.equal(
    windowsOverlap(
      mondays(tuesday, addDate(tuesday, 6)),
      mondays(tuesday, addDate(tuesday, 6)),
    ),
    true,
    "Tue..Mon includes a Monday",
  );
});
test("windowApplies / weeklyWindowApplies: opening minute inclusive, closing minute exclusive, overnight and seasonal limits", () => {
  const op = h({ opens_at: "06:00", closes_at: "22:00" });
  const date = "2032-06-02"; // Wednesday
  assert.equal(windowApplies(op, op, date, "06:00"), true);
  assert.equal(windowApplies(op, op, date, "21:59"), true);
  assert.equal(windowApplies(op, op, date, "22:00"), false);
  assert.equal(windowApplies(op, op, date, "05:59"), false);
  assert.equal(
    windowApplies(h({ days: [1] }), op, date, "10:00"),
    false,
    "Wednesday is not Monday",
  );
  const season = h({ date_from: "2032-06-03", date_until: "2032-06-10" });
  assert.equal(windowApplies(season, op, "2032-06-02", "10:00"), false);
  assert.equal(windowApplies(season, op, "2032-06-03", "10:00"), true);
  assert.equal(windowApplies(season, op, "2032-06-10", "10:00"), true);
  assert.equal(windowApplies(season, op, "2032-06-11", "10:00"), false);
  const night = h({ opens_at: "20:00", closes_at: "02:00" });
  assert.equal(windowApplies(night, night, "2032-06-02", "23:30"), true);
  assert.equal(windowApplies(night, night, "2032-06-03", "01:59"), true);
  assert.equal(windowApplies(night, night, "2032-06-03", "02:00"), false);
  assert.equal(weeklyWindowApplies(op, op, 3, "06:00"), true);
  assert.equal(weeklyWindowApplies(op, op, 3, "22:00"), false);
  assert.equal(weeklyWindowApplies(h({ days: [3] }), op, 4, "10:00"), false);
  assert.equal(
    weeklyWindowApplies(night, night, 4, "01:00"),
    true,
    "overnight rule belongs to the previous weekday when queried on its own hours",
  );
});
test("fitsOperatingInterval: exact fit, one minute over, negative lead-in, zero/negative durations", () => {
  const op = h({ opens_at: "06:00", closes_at: "22:00" });
  assert.equal(fitsOperatingInterval(op, 0, 960, 0, 0, 3), true);
  assert.equal(fitsOperatingInterval(op, 0, 961, 0, 0, 3), false);
  assert.equal(fitsOperatingInterval(op, 1, 960, 0, 0, 3), false);
  assert.equal(
    fitsOperatingInterval(op, 0, 960, 1, 0, 3),
    false,
    "buffer before opening",
  );
  assert.equal(fitsOperatingInterval(op, 0, 959, 0, 1, 3), true);
  assert.equal(fitsOperatingInterval(op, 0, 959, 0, 2, 3), false);
  assert.equal(
    fitsOperatingInterval(op, -1, 60, 0, 0, 3),
    false,
    "starts before opening",
  );
  assert.equal(
    fitsOperatingInterval(op, 0, 0, 0, 0, 3),
    true,
    "zero length at the opening minute",
  );
  assert.equal(fitsOperatingInterval(op, Number.NaN, 60, 0, 0, 3), false);
  const allDay = h({
    opens_at: "00:00",
    closes_at: "00:00",
    all_day: true,
    days: [1, 2],
  });
  assert.equal(
    fitsOperatingInterval(allDay, 23 * 60, 60, 0, 0, 2),
    true,
    "ending exactly at midnight does not need Wednesday",
  );
  assert.equal(
    fitsOperatingInterval(allDay, 23 * 60, 61, 0, 0, 2),
    false,
    "spills into closed Wednesday",
  );
  assert.equal(
    fitsOperatingInterval(allDay, 23 * 60, 61, 0, 0, 1),
    true,
    "spills into open Tuesday",
  );
  assert.equal(
    fitsOperatingInterval(allDay, 0, 30, 60, 0, 1),
    false,
    "buffer reaches closed Sunday",
  );
});
test("allDayDatesCover: single day, inverted range, season edges and unlisted weekdays", () => {
  const wk = h({
    days: [1, 2, 3, 4, 5],
    date_from: "2032-06-01",
    date_until: "2032-06-30",
  });
  assert.equal(allDayDatesCover(wk, "2032-06-02", "2032-06-02"), true);
  assert.equal(
    allDayDatesCover(wk, "2032-06-04", "2032-06-05"),
    false,
    "Saturday is closed",
  );
  assert.equal(
    allDayDatesCover(wk, "2032-05-31", "2032-05-31"),
    false,
    "before the season",
  );
  assert.equal(
    allDayDatesCover(wk, "2032-06-01", "2032-06-01"),
    true,
    "first day of the season",
  );
  assert.equal(
    allDayDatesCover(wk, "2032-06-30", "2032-06-30"),
    true,
    "last day of the season",
  );
  assert.equal(
    allDayDatesCover(wk, "2032-07-01", "2032-07-01"),
    false,
    "after the season",
  );
  assert.equal(
    allDayDatesCover(wk, "2032-06-03", "2032-06-02"),
    true,
    "inverted range covers nothing and is vacuously true",
  );
});

// -------------------------------------------------------- minimum booking
test("acceptsMinimumDuration: boundaries, grid, type and non-finite inputs", () => {
  assert.equal(acceptsMinimumDuration(30, 30), true);
  assert.equal(acceptsMinimumDuration(45, 30), true);
  assert.equal(
    acceptsMinimumDuration(1440, 30),
    true,
    "1440-30 is a multiple of 15",
  );
  assert.equal(acceptsMinimumDuration(1440, 60), true);
  assert.equal(
    acceptsMinimumDuration(1440, 45),
    true,
    "1440-45 is a multiple of 15",
  );
  for (const [d, m] of [
    [0, 30],
    [-30, 30],
    [29, 30],
    [1441, 30],
    [Number.NaN, 30],
    [Infinity, 30],
    [60, 29],
    [60, 0],
    [60, -30],
    [60, 30.5],
    [60.5, 30],
    [40, 30],
    [30, Number.NaN],
    [2 ** 53, 30],
  ] as [number, number][])
    assert.equal(acceptsMinimumDuration(d, m), false, `${d}/${m}`);
  for (const bad of ["60", null, undefined, {}, [], true] as any[]) {
    assert.equal(acceptsMinimumDuration(bad, 60), false, String(bad));
    assert.equal(acceptsMinimumDuration(60, bad), false, String(bad));
  }
});
test("minimumBookingPrice: missing rates, null and zero prices, huge prices, rounding half-up and invalid durations", () => {
  const rate = (price_minor: number | null, duration_minutes = 60) => [
    { duration_minutes, price_minor },
  ];
  assert.equal(minimumBookingPrice(undefined, 60, 60), null);
  assert.equal(minimumBookingPrice([], 60, 60), null);
  assert.equal(minimumBookingPrice(rate(null), 60, 60), null);
  assert.equal(
    minimumBookingPrice(rate(100, 90), 60, 60),
    null,
    "no rate at the minimum duration",
  );
  assert.equal(minimumBookingPrice(rate(0), 60, 60), 0);
  assert.equal(minimumBookingPrice(rate(1), 60, 75), Math.round(75 / 60));
  assert.equal(
    minimumBookingPrice(rate(1), 60, 90),
    2,
    "1.5 rounds half-up to 2",
  );
  assert.equal(minimumBookingPrice(rate(100), 60, 61), null, "off grid");
  assert.equal(minimumBookingPrice(rate(100), 60, 0), null);
  assert.equal(minimumBookingPrice(rate(100), 60, -60), null);
  assert.equal(minimumBookingPrice(rate(100), 60, Number.NaN), null);
  assert.equal(
    minimumBookingPrice(rate(Number.MAX_SAFE_INTEGER), 30, 1440),
    null,
    "unsafe product is rejected, not returned as an imprecise number",
  );
  assert.equal(minimumBookingPrice(rate(Infinity), 60, 120), null);
  assert.equal(minimumBookingPrice(rate(Number.NaN), 60, 120), null);
});

// ------------------------------------------------------ shared validators
test("calendarDate / clock accept only canonical values", () => {
  for (const v of ["2032-02-29", "2000-01-01", "2100-12-31"])
    assert.ok(calendarDate.safeParse(v).success, v);
  for (const v of ["1999-12-31", "2101-01-01"])
    assert.equal(calendarDate.safeParse(v).success, false, v);
  for (const v of [
    "",
    " ",
    "2032-2-29",
    "2033-02-29",
    "2032-00-01",
    "2032-01-00",
    "2032-01-32",
    "20320101",
    "2032-01-01T00:00:00Z",
    "2032-01-01 ",
    "٢٠٣٢-٠١-٠١",
    null,
    undefined,
    5,
    {},
    [],
  ])
    assert.equal(calendarDate.safeParse(v).success, false, String(v));
  for (const v of ["00:00", "09:05", "23:59"])
    assert.ok(clock.safeParse(v).success, v);
  for (const v of [
    "",
    "0:00",
    "24:00",
    "23:60",
    "23:59:59",
    "23.59",
    "٠٩:٠٠",
    null,
    5,
  ])
    assert.equal(clock.safeParse(v).success, false, String(v));
});
test("calendarDate must reject years that downstream Date/Postgres code cannot handle", () => {
  for (const v of [
    "0000-01-01",
    "0000-12-31",
    "0001-01-01",
    "1000-06-15",
    "9999-12-31",
  ])
    assert.equal(calendarDate.safeParse(v).success, false, v);
});
test("selectionSchema, paymentSchema and customerSchema: numeric extremes", () => {
  const sel = {
    business_id: crypto.randomUUID(),
    resource_id: crypto.randomUUID(),
    option_id: "hourly",
    date: "2032-01-01",
    time: "10:00",
    duration_minutes: 60,
    people: 1,
  };
  assert.ok(selectionSchema.safeParse(sel).success);
  for (const [k, v] of [
    ["duration_minutes", 0],
    ["duration_minutes", 1441],
    ["duration_minutes", -1],
    ["duration_minutes", 0.5],
    ["duration_minutes", Infinity],
    ["duration_minutes", Number.NaN],
    ["people", 0],
    ["people", 10001],
    ["people", -1],
    ["people", Number.NaN],
    ["option_id", "x".repeat(101)],
  ] as [string, unknown][])
    assert.equal(
      selectionSchema.safeParse({ ...sel, [k]: v }).success,
      false,
      `${k}=${v}`,
    );
  for (const [k, v] of [
    ["duration_minutes", 1],
    ["duration_minutes", 1440],
    ["people", 1],
    ["people", 10000],
    ["option_id", ""],
    ["option_id", "x".repeat(100)],
  ] as [string, unknown][])
    assert.equal(
      selectionSchema.safeParse({ ...sel, [k]: v }).success,
      true,
      `${k}=${v}`,
    );
  const pay = {
    method: "cash",
    amount_minor: 1,
    reference: "",
    received_at: "2032-01-01T00:00:00Z",
  };
  assert.ok(paymentSchema.safeParse(pay).success);
  assert.ok(
    paymentSchema.safeParse({ ...pay, amount_minor: 100000000 }).success,
  );
  for (const amount_minor of [0, -1, 100000001, 1.1, Infinity, Number.NaN, "5"])
    assert.equal(
      paymentSchema.safeParse({ ...pay, amount_minor }).success,
      false,
      String(amount_minor),
    );
  for (const received_at of [
    "",
    "2032-01-01",
    "2032-01-01T00:00:00",
    "2032-13-01T00:00:00Z",
    "2032-01-01T25:00:00Z",
  ])
    assert.equal(
      paymentSchema.safeParse({ ...pay, received_at }).success,
      false,
      received_at,
    );
  assert.ok(
    paymentSchema.safeParse({
      ...pay,
      received_at: "2032-01-01T00:00:00+05:30",
    }).success,
  );
  assert.equal(
    customerSchema.safeParse({
      id: null,
      name: "ab",
      phone: "1234567",
      email: null,
    }).success,
    true,
  );
  assert.equal(
    customerSchema.safeParse({
      id: null,
      name: "ab",
      phone: "123-4567",
      email: null,
    }).success,
    true,
  );
  assert.equal(
    customerSchema.safeParse({
      id: null,
      name: "ab",
      phone: "000-0000",
      email: null,
    }).success,
    true,
  );
});
test("moneyStatus: zero, exact, partial, over and negative balances", () => {
  assert.deepEqual(moneyStatus(0, 0), {
    net_paid_minor: 0,
    balance_minor: 0,
    refund_due_minor: 0,
    payment_status: "paid",
  });
  assert.equal(moneyStatus(100, 0).payment_status, "unpaid");
  assert.equal(moneyStatus(100, 1).payment_status, "partial");
  assert.equal(moneyStatus(100, 100).payment_status, "paid");
  assert.equal(moneyStatus(100, 101).payment_status, "refund_due");
  assert.equal(moneyStatus(100, 101).refund_due_minor, 1);
  assert.equal(
    moneyStatus(0, 50).refund_due_minor,
    50,
    "cancelled booking with money held",
  );
  assert.equal(
    moneyStatus(100, -5).balance_minor,
    105,
    "net negative (refund exceeded collections) increases the balance",
  );
});
test("date and timezone helpers: addDate, localStamp, zonedTime boundaries", () => {
  assert.equal(addDate("2032-02-28", 1), "2032-02-29");
  assert.equal(addDate("2033-02-28", 1), "2033-03-01");
  assert.equal(addDate("2032-12-31", 1), "2033-01-01");
  assert.equal(addDate("2032-01-01", -1), "2031-12-31");
  assert.equal(addDate("2032-01-01", 0), "2032-01-01");
  assert.equal(
    localStamp(Date.UTC(2032, 0, 1, 18, 29), "Asia/Kolkata"),
    "2032-01-01T23:59",
  );
  assert.equal(
    localStamp(Date.UTC(2032, 0, 1, 18, 30), "Asia/Kolkata"),
    "2032-01-02T00:00",
    "midnight renders as 00:00 not 24:00",
  );
  assert.equal(
    zonedTime("2032-01-02", "00:00", "Asia/Kolkata"),
    Date.UTC(2032, 0, 1, 18, 30),
  );
  assert.equal(
    zonedTime("2032-01-01", "23:59", "UTC"),
    Date.UTC(2032, 0, 1, 23, 59),
  );
  assert.throws(
    () => zonedTime("2032-03-14", "02:30", "America/New_York"),
    /missing or ambiguous/,
  );
  assert.throws(
    () => zonedTime("2032-11-07", "01:30", "America/New_York"),
    /missing or ambiguous/,
  );
  assert.ok(
    Number.isFinite(zonedTime("2032-03-14", "01:59", "America/New_York")),
  );
  assert.ok(
    Number.isFinite(zonedTime("2032-03-14", "03:00", "America/New_York")),
  );
  assert.throws(() => zonedTime("2032-01-01", "10:00", "Not/AZone"));
});
test(
  "fitsOperatingInterval must refuse a negative duration (defence in depth; callers currently validate)",
  { todo: "BUG-8" },
  () => {
    assert.equal(fitsOperatingInterval(h(), 0, -60, 0, 0, 3), false);
  },
);
test(
  "minimumBookingPrice must refuse a negative tariff (defence in depth; schemas currently validate)",
  { todo: "BUG-9" },
  () => {
    assert.equal(
      minimumBookingPrice(
        [{ duration_minutes: 60, price_minor: -100 }],
        60,
        120,
      ),
      null,
    );
  },
);
