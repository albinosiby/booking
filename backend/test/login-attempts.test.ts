import { test } from "node:test";
import assert from "node:assert/strict";
import { LoginAttempts } from "../../admin-panel/lib/login-attempts";

test("login attempts reserve before async work and recover at the fixed boundary", () => {
  let time = 100;
  const attempts = new LoginAttempts(() => time, 1000, 2);
  assert.equal(attempts.reserve("peer"), true);
  assert.equal(attempts.reserve("peer"), true);
  assert.equal(attempts.reserve("peer"), false);
  time = 1099;
  assert.equal(attempts.reserve("peer"), false);
  time = 1100;
  assert.equal(attempts.reserve("peer"), true);
});

test("successful login resets only its peer budget", () => {
  const attempts = new LoginAttempts(() => 0, 1000, 1);
  assert.equal(attempts.reserve("first"), true);
  assert.equal(attempts.reserve("second"), true);
  attempts.clear("first");
  assert.equal(attempts.reserve("first"), true);
  assert.equal(attempts.reserve("second"), false);
});

test("key floods cannot evict active budgets or grow memory without bounds", () => {
  let time = 0;
  const attempts = new LoginAttempts(() => time, 1000, 1, 2);
  assert.equal(attempts.reserve("first"), true);
  assert.equal(attempts.reserve("second"), true);
  assert.equal(attempts.reserve("third"), false);
  assert.equal(attempts.reserve("first"), false);
  time = 1000;
  assert.equal(attempts.reserve("third"), true);
});
