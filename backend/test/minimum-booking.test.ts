import { test } from "node:test";
import assert from "node:assert/strict";
import {
  acceptsMinimumDuration,
  minimumBookingPrice,
} from "../src/common/minimum-booking";
test("minimum duration permits quarter-hour extensions relative to the minimum", () => {
  for (const duration of [60, 75, 90, 105, 180])
    assert.equal(acceptsMinimumDuration(duration, 60), true);
  assert.equal(acceptsMinimumDuration(120, 90), true);
  for (const d of [30, 61, 1441, 90.5])
    assert.equal(acceptsMinimumDuration(d, 60), false);
});
test("proportional prices use the minimum rate and round to minor currency units", () => {
  const rates = [
    { duration_minutes: 60, price_minor: 60000 },
    { duration_minutes: 120, price_minor: 100000 },
  ];
  assert.equal(minimumBookingPrice(rates, 60, 180), 180000);
  assert.equal(minimumBookingPrice(rates, 60, 90), 90000);
  assert.equal(minimumBookingPrice(rates, 60, 75), 75000);
  assert.equal(minimumBookingPrice(rates, 60, 105), 105000);
  assert.equal(
    minimumBookingPrice(
      [{ duration_minutes: 90, price_minor: 10000 }],
      90,
      120,
    ),
    13333,
  );
  assert.equal(
    minimumBookingPrice([{ duration_minutes: 60, price_minor: 0 }], 60, 180),
    0,
  );
  assert.equal(minimumBookingPrice(undefined, 60, 180), null);
});
