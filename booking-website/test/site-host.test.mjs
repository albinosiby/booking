import { test } from "node:test";
import assert from "node:assert/strict";
import {
  appOrigin,
  appRedirect,
  legacySitePath,
  resolveSiteHost,
  siteDomain,
  siteOrigin,
} from "../lib/site-host.ts";

const domain = siteDomain("bookingos.online");
test("organisation subdomains resolve to their website slug", () => {
  assert.deepEqual(resolveSiteHost("eden-sports.bookingos.online", domain), {
    kind: "site",
    slug: "eden-sports",
  });
  assert.deepEqual(
    resolveSiteHost("Eden-Sports.BookingOS.online:443", domain),
    { kind: "site", slug: "eden-sports" },
  );
  assert.deepEqual(resolveSiteHost("eden.localhost:3000", "localhost"), {
    kind: "site",
    slug: "eden",
  });
});
test("main domain, reserved names and foreign hosts are not websites", () => {
  assert.equal(resolveSiteHost("bookingos.online", domain).kind, "root");
  assert.equal(resolveSiteHost("www.bookingos.online", domain).kind, "root");
  for (const host of [
    "api.bookingos.online",
    "a.b.bookingos.online",
    "-bad.bookingos.online",
    "ab.bookingos.online",
    "evilbookingos.online",
    "eden.bookingos.online.evil.com",
    "127.0.0.1:3000",
    "",
    null,
  ])
    assert.equal(resolveSiteHost(host, domain).kind, "other", String(host));
});
test("old path links move to the subdomain", () => {
  assert.deepEqual(legacySitePath("/eden-sports/book/1"), {
    slug: "eden-sports",
    path: "/book/1",
  });
  assert.deepEqual(legacySitePath("/eden-sports"), {
    slug: "eden-sports",
    path: "/",
  });
  assert.equal(legacySitePath("/api/sites/x"), null);
  assert.equal(legacySitePath("/"), null);
  assert.equal(siteOrigin("eden", domain), "https://eden.bookingos.online");
  assert.equal(siteOrigin("eden", "localhost"), "http://eden.localhost");
  assert.equal(
    siteOrigin("eden", "localhost", "localhost:3010"),
    "http://eden.localhost:3010",
  );
});
test("login and register open the owner app", () => {
  assert.equal(
    appRedirect("/login", domain, ""),
    "https://app.bookingos.online/sign-in",
  );
  assert.equal(
    appRedirect("/login/", domain, ""),
    "https://app.bookingos.online/sign-in",
  );
  assert.equal(
    appRedirect("/register", domain, ""),
    "https://app.bookingos.online/register",
  );
  assert.equal(appRedirect("/eden-sports", domain, ""), null);
  assert.equal(legacySitePath("/login"), null);
  assert.equal(
    appOrigin(domain, "https://my-app.up.railway.app/x"),
    "https://my-app.up.railway.app",
  );
  assert.equal(appOrigin("localhost", ""), "http://localhost:8080");
});

test("owner app redirects retain a configured /app mount", () => {
  for (const base of ["/app", "/app/", "https://bookingos.online/app/"]) {
    assert.equal(
      appRedirect("/login", domain, base),
      "https://bookingos.online/app/sign-in",
    );
    assert.equal(
      appRedirect("/register", domain, base),
      "https://bookingos.online/app/register",
    );
  }
  assert.equal(appOrigin(domain, "/app"), "https://bookingos.online");
  assert.equal(
    appRedirect("/sign-in", "localhost", "/app"),
    "http://localhost:8080/app/sign-in",
  );
});
