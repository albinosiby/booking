import { test } from "node:test";
import assert from "node:assert/strict";
import {
  bookingTimeCells,
  chooseTimeCell,
  preloadedEnds,
} from "../lib/booking-time-grid.ts";

const date = "2030-06-04";
const available = (time) => ({
  time,
  available: true,
  status: "available",
  total_minor: 50000,
});
const slots = [
  available("09:00"),
  available("09:15"),
  available("09:30"),
  available("09:45"),
  { ...available("10:00"), available: false, status: "booked" },
  available("10:15"),
  available("11:00"),
];
const ends = [
  { ...available("10:00"), duration_minutes: 60 },
  { ...available("10:15"), duration_minutes: 75 },
];
const cells = (range, extra = {}) =>
  bookingTimeCells({
    date,
    slots,
    endSlots: [],
    minimum: 60,
    ...range,
    ...extra,
  });
const at = (all, time) => all.find((c) => c.key === `${date}T${time}`);

test("one grid retains every original start and marks a booked start as a valid finish", () => {
  const before = cells({ start: "", duration: 0 });
  const waiting = cells({ start: "09:00", duration: 0 }, { endSlots: ends });
  assert.deepEqual(
    waiting.map((c) => c.key),
    before.map((c) => c.key),
  );
  assert.equal(at(waiting, "09:00").start, true);
  assert.equal(at(waiting, "09:00").enabled, true);
  assert.equal(at(waiting, "09:15").enabled, false);
  assert.equal(at(waiting, "09:15").label, "Min. 1 hr");
  assert.equal(at(waiting, "10:00").enabled, true);
  assert.deepEqual(
    chooseTimeCell(
      { start: "09:00", duration: 0 },
      at(waiting, "10:00"),
      60,
      60,
    ),
    { start: "09:00", duration: 60 },
  );
});
test("both boundaries and the intervening range stay highlighted; either boundary can be cleared", () => {
  const range = { start: "09:00", duration: 60 },
    selected = cells(range, { endSlots: ends });
  assert.equal(at(selected, "09:00").start, true);
  assert.equal(at(selected, "10:00").end, true);
  assert.equal(selected.filter((c) => c.inRange).length, 3);
  const clearedEnd = chooseTimeCell(range, at(selected, "10:00"), 60, 60);
  assert.deepEqual(clearedEnd, { start: "09:00", duration: 0 });
  const waiting = cells(clearedEnd, { endSlots: ends });
  assert.equal(at(waiting, "09:00").start, true);
  assert.deepEqual(chooseTimeCell(clearedEnd, at(waiting, "09:00"), 60, 60), {
    start: "",
    duration: 0,
  });
});
test("a completed range can be replaced by choosing another available start", () => {
  const range = { start: "09:00", duration: 60 },
    selected = cells(range, { endSlots: ends });
  assert.deepEqual(chooseTimeCell(range, at(selected, "11:00"), 60, 60), {
    start: "11:00",
    duration: 0,
  });
  assert.deepEqual(chooseTimeCell(range, at(selected, "09:30"), 60, 60), {
    start: "09:30",
    duration: 0,
  });
});
test("midnight remains a separate next-day end boundary instead of replacing today's start", () => {
  const all = bookingTimeCells({
    date,
    start: "23:00",
    duration: 60,
    minimum: 60,
    slots: [available("00:00"), available("23:00")],
    endSlots: [
      { ...available("00:00"), date: "2030-06-05", duration_minutes: 60 },
    ],
  });
  assert.equal(all.filter((c) => c.slot.time === "00:00").length, 2);
  assert.equal(all.find((c) => c.key === "2030-06-05T00:00").end, true);
  assert.equal(at(all, "00:00").end, false);
});
test("end-only closing boundaries, blocked times and loading respect separate start/end validity", () => {
  const base = [
    ...slots,
    { ...available("12:00"), available: false, status: "end_only" },
  ];
  const initial = cells({ start: "", duration: 0 }, { slots: base });
  assert.equal(at(initial, "12:00").enabled, false);
  assert.equal(at(initial, "12:00").label, "End only");
  const waiting = cells(
    { start: "11:00", duration: 0 },
    {
      slots: base,
      endSlots: [{ ...available("12:00"), duration_minutes: 60 }],
    },
  );
  assert.equal(at(waiting, "12:00").enabled, true);
  const loading = cells(
    { start: "09:00", duration: 0 },
    { endSlots: ends, loading: true },
  );
  assert.equal(at(loading, "09:00").enabled, true);
  assert.equal(at(loading, "10:00").enabled, false);
  assert.equal(at(loading, "10:00").label, "Checking…");
  assert.deepEqual(
    chooseTimeCell(
      { start: "09:00", duration: 0 },
      at(loading, "09:00"),
      60,
      60,
    ),
    { start: "", duration: 0 },
  );
  assert.ok(
    cells(
      { start: "09:00", duration: 60 },
      { endSlots: ends, locked: true },
    ).every((c) => !c.enabled),
  );
});
test("prevalidated end options preserve their dates and absent options can use API fallback", () => {
  assert.equal(preloadedEnds(available("09:00")), undefined);
  assert.deepEqual(
    preloadedEnds({
      ...available("23:00"),
      end_options: [[60, "2030-06-05T00:00"]],
    }),
    [
      {
        time: "00:00",
        date: "2030-06-05",
        duration_minutes: 60,
        available: true,
        status: "available",
        total_minor: 0,
      },
    ],
  );
});
test("fixed sessions retain their single-click booking behaviour", () => {
  const fixed = cells({ start: "", duration: 0 }, { minimum: null });
  assert.deepEqual(
    chooseTimeCell({ start: "", duration: 0 }, at(fixed, "09:00"), null, 180),
    { start: "09:00", duration: 180 },
  );
  assert.equal(at(fixed, "10:00").label, "Unavailable");
});

test("a free hour remains bookable when later starts would overlap the next booking", () => {
  const unavailable = (time) => ({
    ...available(time), available: false, status: "booked",
  });
  const gapSlots = [
    { ...available("19:00"), end_options: [[60, `${date}T20:00`]] },
    ...["19:15", "19:30", "19:45", "20:00", "20:15", "20:30", "20:45"].map(unavailable),
    available("21:00"),
  ];
  const initial = cells({ start: "", duration: 0 }, { slots: gapSlots });
  assert.equal(at(initial, "19:00").enabled, true);
  assert.equal(at(initial, "19:00").label, "Available");
  for (const time of ["19:15", "19:30", "19:45"]) {
    assert.equal(at(initial, time).label, "Available · cannot start");
    assert.equal(at(initial, time).enabled, false);
  }
  assert.equal(at(initial, "20:00").label, "Unavailable for 1 hr");
  assert.equal(at(initial, "20:00").enabled, false);
  const range = chooseTimeCell({ start: "", duration: 0 }, at(initial, "19:00"), 60, 60);
  const waiting = cells(range, { slots: gapSlots, endSlots: preloadedEnds(gapSlots[0]) });
  assert.equal(at(waiting, "20:00").enabled, true);
  assert.deepEqual(chooseTimeCell(range, at(waiting, "20:00"), 60, 60), {
    start: "19:00", duration: 60,
  });
});

test("interval availability works without an earlier selectable start", () => {
  const grid = cells({ start: "", duration: 0 }, {
    slots: [
      { ...available("19:15"), available: false, status: "booked", interval_available: true },
      { ...available("19:30"), available: false, status: "blocked", interval_available: true },
      { ...available("20:00"), available: false, status: "booked", interval_available: false },
    ],
  });
  for (const time of ["19:15", "19:30"]) {
    assert.equal(at(grid, time).label, "Available · cannot start");
    assert.equal(at(grid, time).enabled, false);
  }
  assert.equal(at(grid, "20:00").label, "Unavailable for 1 hr");
});

test("end conflicts describe the range and pool capacity labels stay unchanged", () => {
  const waiting = cells({ start: "09:00", duration: 0 }, {
    endSlots: [{ ...available("11:00"), available: false, status: "booked", duration_minutes: 120 }],
  });
  assert.equal(at(waiting, "11:00").label, "Overlaps a booking");
  assert.equal(at(waiting, "11:00").enabled, false);
  const pool = cells({ start: "", duration: 0 }, {
    pool: true,
    slots: [{ ...available("09:00"), remaining_capacity: 3 }, slots[4]],
  });
  assert.equal(at(pool, "09:00").label, "3 places");
  assert.equal(at(pool, "10:00").label, "Unavailable");
});

test("the selected end uses the API's local boundary across clock changes", () => {
  const all = bookingTimeCells({
    date: "2030-03-10",
    start: "01:30",
    duration: 60,
    minimum: 60,
    slots: [available("01:30"), available("03:30")],
    endSlots: [
      { ...available("03:30"), date: "2030-03-10", duration_minutes: 60 },
    ],
  });
  assert.equal(all.find((c) => c.slot.time === "03:30").end, true);
});
