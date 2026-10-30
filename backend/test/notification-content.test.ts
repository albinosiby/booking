import { test } from "node:test";
import assert from "node:assert/strict";
import {
  bookingNotificationBody,
  staffCashNotificationBody,
} from "../src/notifications/notification-content";

test("notification dates follow the venue timezone and include the end date across midnight", () => {
  assert.equal(
    bookingNotificationBody("BK-TURF", {
      customer_name: "Arun",
      space_name: "Turf 1",
      starts_at: "2026-10-24T17:30:00Z",
      ends_at: "2026-10-24T19:30:00Z",
      timezone: "Asia/Kolkata",
    }),
    "Name: Arun\nSpace: Turf 1\nTime: 24 Oct 2026, 11:00 PM IST – 25 Oct 2026, 1:00 AM IST\nBK-TURF",
  );
  const west = bookingNotificationBody("BK-US", {
    starts_at: "2026-10-24T02:00:00Z",
    timezone: "America/Los_Angeles",
  });
  assert.match(west, /23 Oct 2026, 7:00 PM/);
});

test("invalid legacy dates and timezones cannot block delivery or imply server-local time", () => {
  for (const details of [
    {},
    { starts_at: "invalid", timezone: "Asia/Kolkata" },
    { starts_at: "2026-10-24T12:30:00Z", timezone: "invalid" },
    { starts_at: "2026-10-24T12:30:00Z" },
  ])
    assert.match(
      bookingNotificationBody("BK-TEST", details),
      /Time: Time unavailable/,
    );
  assert.equal(
    bookingNotificationBody("BK-OLD"),
    "Booking BK-OLD. Open Booking OS for details.",
  );
});

test("notification labels preserve Unicode names, remove injected lines and bound payload size", () => {
  const body = bookingNotificationBody("BK-TEST", {
    customer_name: "  അരുൺ\n\u202e  Kumar ",
    space_name: "⚽".repeat(2000),
  });
  assert.match(body, /^Name: അരുൺ Kumar\nSpace: /u);
  assert.equal(body.split("\n").length, 4);
  assert.equal(
    Array.from(body.split("\n")[1].slice("Space: ".length)).length,
    80,
  );
  assert.ok(Buffer.byteLength(body, "utf8") < 1000);
});

test("cash confirmation names the exact amount and remaining balance for each participant", () => {
  const details = {
    amount_minor: 150000,
    balance_after_minor: 25000,
    currency: "INR",
    staff_name: "Asha\nStaff",
    collector_name: "Albino",
  };
  assert.equal(
    staffCashNotificationBody(details, true),
    "Albino collected ₹1,500.00 from you.\nRemaining to hand over: ₹250.00.",
  );
  assert.equal(
    staffCashNotificationBody(details, false),
    "You collected ₹1,500.00 from Asha Staff.\nRemaining to hand over: ₹250.00.",
  );
  assert.throws(() =>
    staffCashNotificationBody({ ...details, amount_minor: NaN }, true),
  );
  assert.throws(() =>
    staffCashNotificationBody({ ...details, balance_after_minor: -1 }, true),
  );
});
