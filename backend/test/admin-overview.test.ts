import { test } from "node:test";
import assert from "node:assert/strict";
import { overviewTotals } from "../../admin-panel/lib/overview";

const totals = {
  organizations: 12,
  users: 23,
  active_users: 19,
  businesses: 27,
  bookings: 493,
  customers: 108,
  open_tickets: 0,
  pending_agent_requests: 1,
};

test("admin totals preserve actual API values including genuine zeros", () => {
  assert.deepEqual(overviewTotals(totals), totals);
});

test("missing or invalid live totals cannot become fabricated zero metrics", () => {
  for (const value of [
    null,
    {},
    { ...totals, bookings: undefined },
    { ...totals, users: "23" },
    { ...totals, customers: -1 },
    { ...totals, active_users: NaN },
  ]) {
    assert.throws(() => overviewTotals(value), /Live platform totals/);
  }
});
