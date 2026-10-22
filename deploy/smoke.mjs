import assert from "node:assert/strict";

// Read-only deployment verification. Never submits logins, bookings or payments.
const origin = new URL(process.argv[2] || "http://127.0.0.1:8080").origin;
async function get(path, options = {}) {
  const response = await fetch(`${origin}${path}`, {
    redirect: "manual", signal: AbortSignal.timeout(15_000), ...options,
  });
  return { response, text: await response.text() };
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
assert.match(login.text, /Booking Admin/);
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
}
console.info("Passed: readiness, landing assets, Flutter deep links/404s, login redirects, admin protection and admin assets.");
