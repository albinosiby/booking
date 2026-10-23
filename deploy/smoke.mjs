import assert from "node:assert/strict";
import { get as httpGet } from "node:http";
import { get as httpsGet } from "node:https";

// Read-only deployment verification. Never submits logins, bookings or payments.
const origin = new URL(process.argv[2] || "http://127.0.0.1:8080").origin;
const domain = process.argv[4];
async function get(path, options = {}) {
  // Node's fetch ignores Host overrides; the HTTP client lets local tests send
  // real tenant Host headers through the same gateway as production traffic.
  return new Promise((resolve, reject) => {
    const url = new URL(path, origin);
    const request = (url.protocol === "https:" ? httpsGet : httpGet)(url, {
      signal: AbortSignal.timeout(15_000), ...options,
    }, async (response) => {
      try {
        const chunks = [];
        for await (const chunk of response) chunks.push(chunk);
        const headers = new Headers();
        for (const [name, value] of Object.entries(response.headers))
          for (const item of Array.isArray(value) ? value : [value])
            if (item !== undefined) headers.append(name, item);
        resolve({ response: { status: response.statusCode, headers }, text: Buffer.concat(chunks).toString() });
      } catch (error) { reject(error); }
    });
    request.on("error", reject);
  });
}

const health = await get("/_health");
assert.equal(health.response.status, 200, "all frontend processes must be healthy");
assert.equal(JSON.parse(health.text).status, "ok");
const landing = await get("/");
assert.equal(landing.response.status, 200);
assert.match(landing.text, /Run your/);
assert.match(landing.text, /href="\/app\/sign-in"/);
assert.match(landing.text, /href="\/app\/register"/);
assert.equal(landing.response.headers.get("x-content-type-options"), "nosniff");

const landingAssets = new Set([...landing.text.matchAll(/(?:src|href|poster)="(\/_landing\/[^"?#]+)/g)].map((match) => match[1]));
assert.ok(landingAssets.size > 3, "landing assets must use their separate namespace");
for (const asset of landingAssets)
  assert.equal((await get(asset)).response.status, 200, asset);

for (const path of ["/app/", "/app/sign-in", "/app/register", "/app/profile/booking-website"]) {
  const { response, text } = await get(path);
  assert.equal(response.status, 200, path);
  assert.match(text, /<base href="\/app\/">/, path);
  assert.match(response.headers.get("cache-control") || "", /no-cache/, path);
}
assert.equal((await get("/app/flutter_bootstrap.js")).response.status, 200);
for (const path of ["/app/missing-file.js", "/app/assets/missing-file", "/_landing/missing-file.png", "/.env", "/app/main.dart.js.map"])
  assert.equal((await get(path)).response.status, 404, path);

for (const [path, destination] of [["/app", "/app/"], ["/sign-in?from=home", "/app/sign-in?from=home"], ["/register", "/app/register"]]) {
  const { response } = await get(path);
  assert.ok([307, 308].includes(response.status), path);
  assert.equal(new URL(response.headers.get("location"), origin).pathname + new URL(response.headers.get("location"), origin).search, destination);
}

const login = await get("/admin/login");
assert.equal(login.response.status, 200);
assert.match(login.text, /name="password"/, "admin login must render its password form");
const adminAssets = new Set([...login.text.matchAll(/(?:src|href)="(\/admin\/_next\/[^"?#]+)/g)].map((match) => match[1]));
assert.ok(adminAssets.size > 0, "admin assets must stay under /admin/_next");
for (const asset of adminAssets)
  assert.equal((await get(asset)).response.status, 200, asset);
for (const path of ["/admin", "/admin/organizations", "/admin/support"]) {
  const { response } = await get(path, { headers: { "X-Forwarded-Host": "attacker.invalid" } });
  assert.ok([307, 308].includes(response.status), path);
  const target = new URL(response.headers.get("location"), origin);
  assert.equal(target.pathname, "/admin/login", path);
  assert.equal(target.host, new URL(origin).host, "gateway must overwrite untrusted forwarded hosts");
}
assert.equal((await get("/admin/healthz")).response.status, 200);
// Optional existing published slug (or the isolated container fixture slug).
if (process.argv[3]) {
  const slug = encodeURIComponent(process.argv[3]);
  const site = await get(`/${slug}`);
  assert.equal(site.response.status, 200);
  assert.match(site.text, /site-brand/);
  assert.doesNotMatch(site.text, /Run your/);
  if (process.argv[3] === "railway-smoke") {
    assert.match(site.text, /Railway fixture venue/);
    const booking = await get(`/${slug}/book/fixture-court`);
    assert.equal(booking.response.status, 200);
    assert.match(booking.text, /Fixture badminton court/);
    const catalog = await get(`/api/sites/${slug}`);
    assert.equal(catalog.response.status, 200);
    assert.equal(JSON.parse(catalog.text).slug, "railway-smoke");
    // A forwarded host or internal tenant header must not change path routing.
    const spoofed = await get(`/${slug}`, { headers: { "X-Forwarded-Host": "other.bookingos.online", "X-Booking-Site-Host": "other" } });
    assert.equal(spoofed.response.status, 200);
    assert.match(spoofed.text, /Railway fixture venue/);
  }
  if (domain) {
    const tenantHost = `${process.argv[3]}.${domain}`;
    const tenantHeaders = { Host: tenantHost, "X-Forwarded-Proto": "https", "X-Forwarded-Host": "attacker.invalid", "X-Booking-Site-Host": "other" };
    const home = await get("/", { headers: tenantHeaders });
    assert.equal(home.response.status, 200, "tenant root must open the booking homepage");
    assert.ok(!/localhost|127\.0\.0\.1/.test(home.response.headers.get("x-middleware-rewrite") || ""), "internal host must not leak into the rewrite response");
    assert.match(home.text, /site-brand/);
    assert.doesNotMatch(home.text, /Run your/);
    assert.doesNotMatch(home.text, new RegExp(`href="/${slug}/book/`), "tenant links must not repeat the slug");
    const assets = new Set([...home.text.matchAll(/(?:src|href)="(\/_next\/[^"?#]+)/g)].map((match) => match[1]));
    assert.ok(assets.size > 0, "tenant must include booking frontend assets");
    for (const asset of assets)
      assert.equal((await get(asset, { headers: tenantHeaders })).response.status, 200, asset);
    if (process.argv[3] === "railway-smoke") {
      assert.match(home.text, /Railway fixture venue/);
      assert.match(home.text, /href="\/book\/fixture-court"/);
      const booking = await get("/book/fixture-court", { headers: tenantHeaders });
      assert.equal(booking.response.status, 200);
      assert.match(booking.text, /Fixture badminton court/);
      const navigation = await get("/book/fixture-court?_rsc", { headers: { ...tenantHeaders, RSC: "1" } });
      assert.equal(navigation.response.status, 200, "client navigation must survive the HTTPS rewrite");
      assert.match(navigation.response.headers.get("content-type") || "", /text\/x-component/);
      assert.match(navigation.text, /Fixture badminton court/);
      const catalog = await get(`/api/sites/${slug}`, { headers: tenantHeaders });
      assert.equal(catalog.response.status, 200);
      assert.equal(JSON.parse(catalog.text).slug, "railway-smoke");
    }
    const legacy = await get(`/${slug}?from=legacy`, { headers: tenantHeaders });
    assert.equal(legacy.response.status, 308);
    const clean = new URL(legacy.response.headers.get("location"), `http://${tenantHost}`);
    assert.equal(clean.host, tenantHost);
    assert.equal(clean.protocol, "https:");
    assert.equal(clean.pathname + clean.search, "/?from=legacy");
    const httpHome = await get("/", { headers: { ...tenantHeaders, "X-Forwarded-Proto": "http" } });
    assert.equal(httpHome.response.status, 200, "HTTP and forwarded HTTPS must both support tenant homepages");
    const apexLegacy = await get(`/${slug}/book/example?from=legacy`, { headers: { Host: domain } });
    assert.equal(apexLegacy.response.status, 308);
    assert.equal(apexLegacy.response.headers.get("location"), `https://${tenantHost}/book/example?from=legacy`);
    for (const host of [domain, `www.${domain}`, `not.${domain}.evil.test`]) {
      const main = await get("/", { headers: { Host: host, "X-Forwarded-Host": tenantHost } });
      assert.equal(main.response.status, 200);
      assert.match(main.text, /Run your/, host);
    }
    const owner = await get("/app/profile/booking-website", { headers: tenantHeaders });
    assert.equal(owner.response.status, 200);
    assert.match(owner.text, /<base href="\/app\/">/);
    const admin = await get("/admin", { headers: tenantHeaders });
    assert.ok([307, 308].includes(admin.response.status));
    assert.equal(new URL(admin.response.headers.get("location"), origin).pathname, "/admin/login");
  }
}
console.info("Passed: readiness, landing assets, Flutter deep links/404s, login redirects, admin protection and admin assets" + (domain ? ", custom-domain homepages, clean booking links and host isolation." : "."));
