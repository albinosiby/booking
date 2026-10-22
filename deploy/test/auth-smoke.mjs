import assert from "node:assert/strict";

// This test signs into a disposable LOCAL container only, backed by mock-api.mjs.
const origin = new URL(process.argv[2] || "http://127.0.0.1:8080").origin;
assert.ok(["127.0.0.1", "localhost"].includes(new URL(origin).hostname), "auth smoke is restricted to a local fixture");
const password = process.env.SMOKE_ADMIN_PANEL_PASSWORD;
assert.ok(password, "set the disposable container's SMOKE_ADMIN_PANEL_PASSWORD");
const options = { redirect: "manual", signal: AbortSignal.timeout(15_000) };
const decode = (value) => value.replaceAll("&quot;", '"').replaceAll("&#x27;", "'").replaceAll("&amp;", "&");
function formFields(html) {
  const form = new FormData();
  for (const input of html.matchAll(/<input\b[^>]*>/g)) {
    const attributes = Object.fromEntries([...input[0].matchAll(/([\w$:-]+)="([^"]*)"/g)].map((match) => [match[1], decode(match[2])]));
    if (attributes.type === "hidden" && attributes.name) form.append(attributes.name, attributes.value || "");
  }
  assert.ok([...form.keys()].some((name) => name.startsWith("$ACTION")), "server-action form fields must be rendered");
  return form;
}

const login = await fetch(`${origin}/admin/login`, options);
const loginHtml = await login.text();
assert.doesNotMatch(loginHtml, /name="(?:username|email)"/);
const wrong = formFields(loginHtml);
wrong.set("password", "incorrect-fixture-password");
const rejected = await fetch(`${origin}/admin/login`, {
  ...options, method: "POST", body: wrong, headers: { Origin: origin },
});
assert.equal(rejected.status, 200);
assert.match(await rejected.text(), /Incorrect password/);
assert.ok(!rejected.headers.getSetCookie().some((value) => value.startsWith("admin_session=")));
const form = formFields(loginHtml);
form.set("password", password);
const signedIn = await fetch(`${origin}/admin/login`, {
  ...options, method: "POST", body: form, headers: { Origin: origin },
});
assert.equal(signedIn.status, 303);
assert.equal(new URL(signedIn.headers.get("location"), origin).pathname, "/admin");
const cookie = signedIn.headers.getSetCookie().find((value) => value.startsWith("admin_session="));
assert.ok(cookie);
assert.match(cookie, /Path=\/admin(?:;|$)/);
assert.match(cookie, /HttpOnly/i);
assert.match(cookie, /Secure/i);
const session = cookie.split(";")[0];
const overview = await fetch(`${origin}/admin`, { ...options, headers: { Cookie: session } });
assert.equal(overview.status, 200);
const html = await overview.text();
assert.match(html, /Platform-wide totals/);
assert.match(html, /href="\/admin\/organizations"/);
const logout = await fetch(`${origin}/admin`, {
  ...options, method: "POST", body: formFields(html), headers: { Origin: origin, Cookie: session },
});
assert.equal(logout.status, 303);
assert.equal(new URL(logout.headers.get("location"), origin).pathname, "/admin/login");
const cleared = logout.headers.getSetCookie().find((value) => value.startsWith("admin_session="));
assert.match(cleared || "", /Path=\/admin(?:;|$)/);
assert.match(cleared || "", /Max-Age=0/i);
console.info("Passed: fixture-only admin login, scoped cookie, navigation and logout without client JavaScript.");
