import assert from "node:assert/strict";
import { test } from "node:test";
import { routingConfiguration } from "../routing.mjs";
import { resolveSiteHost } from "../../booking-website/lib/site-host.ts";

test("gateway and booking server agree which hosts serve a tenant homepage", () => {
  const { domain, mode, tenantHostRule } = routingConfiguration({});
  assert.equal(domain, "bookingos.online");
  assert.equal(mode, "auto");
  const pattern = new RegExp(/^"~(.+)" 1;$/.exec(tenantHostRule)[1]);
  for (const host of [
    "rk-sports.bookingos.online",
    "railway-smoke.bookingos.online",
    "abc.bookingos.online",
    `${"a".repeat(63)}.bookingos.online`,
    `${"a".repeat(64)}.bookingos.online`,
    "bookingos.online",
    "www.bookingos.online",
    "app.bookingos.online",
    "api.bookingos.online",
    "admin.bookingos.online",
    "book.bookingos.online",
    "login.bookingos.online",
    "sign-in.bookingos.online",
    "register.bookingos.online",
    "ab.bookingos.online",
    "bad--name.bookingos.online",
    "-bad.bookingos.online",
    "bad-.bookingos.online",
    "a.b.bookingos.online",
    "rk-sports.bookingos.online.evil.test",
    "evilbookingos.online",
    "booking-production-8e79.up.railway.app",
  ])
    assert.equal(
      pattern.test(host),
      resolveSiteHost(host, domain).kind === "site",
      host,
    );
});

test("routing normalizes custom domains and supports explicit path rollback", () => {
  const custom = routingConfiguration({
    BOOKING_SITE_DOMAIN: " Sports.Example. ",
    BOOKING_ROUTING_MODE: "subdomain",
  });
  assert.equal(custom.domain, "sports.example");
  assert.match(custom.tenantHostRule, /sports\\\.example/);
  assert.equal(
    routingConfiguration({ BOOKING_ROUTING_MODE: "path" }).tenantHostRule,
    "",
  );
  assert.match(
    routingConfiguration({ BOOKING_SITE_DOMAIN: "localhost" }).tenantHostRule,
    /localhost/,
  );
});

test("invalid domain and mode settings fail before Nginx configuration is generated", () => {
  for (const domain of [
    "https://bookingos.online",
    "bookingos.online/app",
    "*.bookingos.online",
    "bookingos.online:443",
    "a..test",
    "-bad.test",
    "bad_.test",
    "test; return 200",
    'test"',
    "test\nmalicious",
    `${"a".repeat(64)}.test`,
  ])
    assert.throws(
      () => routingConfiguration({ BOOKING_SITE_DOMAIN: domain }),
      /BOOKING_SITE_DOMAIN/,
    );
  assert.throws(
    () => routingConfiguration({ BOOKING_ROUTING_MODE: "invalid" }),
    /BOOKING_ROUTING_MODE/,
  );
});
