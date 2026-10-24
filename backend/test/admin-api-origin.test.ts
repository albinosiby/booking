import { test } from "node:test";
import assert from "node:assert/strict";
import { configuredApiBase } from "../../admin-panel/lib/api-origin";

test("admin requires an explicit API source instead of silently using another project", () => {
  for (const value of [undefined, "", "  "])
    assert.throws(() => configuredApiBase(value), /BOOKING_API_BASE_URL/);
  assert.equal(
    configuredApiBase("https://live.example.com/functions/v1/booking-api/"),
    "https://live.example.com/functions/v1/booking-api",
  );
  assert.equal(
    configuredApiBase("http://127.0.0.1:3199"),
    "http://127.0.0.1:3199",
  );
});

test("admin API source rejects unsafe or ambiguous origins", () => {
  for (const value of [
    "http://remote.example.com",
    "https://user:password@example.com",
    "https://example.com/?token=test",
    "https://example.com/#test",
  ]) {
    assert.throws(() => configuredApiBase(value), /HTTPS/);
  }
});
