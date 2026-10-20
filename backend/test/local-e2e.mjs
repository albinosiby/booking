import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
const auth = "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1",
  api = "http://localhost:3000/v1";
async function account() {
  const r = await fetch(`${auth}/accounts:signUp?key=demo-key`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      email: `qa-${randomUUID()}@example.com`,
      password: randomUUID() + "Aa1!",
      returnSecureToken: true,
    }),
  });
  assert.equal(r.status, 200);
  return r.json();
}
async function req(user, path, method = "GET", body) {
  const r = await fetch(api + path, {
    method,
    headers: {
      "Content-Type": "application/json",
      ...(user ? { Authorization: `Bearer ${user.idToken}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: r.status, data: await r.json() };
}
const owner = await account(),
  staff = await account();
assert.equal((await req(null, "/workspace")).status, 401);
assert.equal((await req({ idToken: "invalid" }, "/workspace")).status, 401);
assert.equal(
  (
    await req(owner, "/organizations", "POST", {
      name: "QA first-module organization",
      contact_phone: "9876543210",
      currency: "INR",
      location: {
        name: "QA property",
        address_line_1: "Test Road",
        address_line_2: null,
        city: "Kochi",
        country_code: "IN",
        state_code: "KL",
        postal_code: "682001",
        timezone: "Asia/Kolkata",
      },
    })
  ).status,
  201,
);
const initial = (await req(owner, "/workspace")).data;
const business = await req(owner, "/businesses", "POST", {
  name: "QA Turf",
  type: "turf",
  location_id: initial.locations[0].id,
});
assert.equal(business.status, 201);
const id = business.data.id;
assert.equal(
  (await req(owner, `/businesses/${id}/activate`, "POST")).status,
  400,
);
const resource = await req(owner, `/businesses/${id}/resources`, "POST", {
  name: "QA Turf 1",
  capacity: 1,
});
assert.equal(resource.status, 201);
const workspace = (await req(owner, "/workspace")).data;
const config = {
  version: workspace.businesses[0].version,
  opens_at: "06:00",
  closes_at: "23:00",
  days: [1, 2, 3, 4, 5, 6, 7],
  duration_minutes: 60,
  price_minor: 150000,
  buffer_minutes: 0,
  plan_name: null,
  validity_days: null,
  entitlement: null,
  visit_limit: null,
};
assert.equal(
  (await req(owner, `/businesses/${id}/configuration`, "PATCH", config)).status,
  200,
);
assert.equal(
  (await req(owner, `/businesses/${id}/activate`, "POST")).status,
  201,
);
assert.equal(
  (await req(owner, "/workspace")).data.businesses[0].status,
  "ready",
);
const i = await req(owner, "/invitations", "POST", {
  email: staff.email,
  display_name: "QA staff",
  role: "staff",
  permissions: ["view_bookings"],
  assignments: [{ business_id: id, resource_ids: [resource.data.id] }],
});
assert.equal(i.status, 201);
const token = new URL(i.data.invitation_url).searchParams.get("token");
assert.equal(
  (await req(owner, "/invitations/accept", "POST", { token })).status,
  403,
);
assert.equal(
  (await req(staff, "/invitations/accept", "POST", { token })).status,
  201,
);
const w = (await req(staff, "/workspace")).data;
assert.equal(w.businesses.length, 1);
assert.equal(w.businesses[0].resources[0].id, resource.data.id);
assert.equal((await req(staff, "/team")).status, 403);
assert.equal(
  (await req(staff, `/businesses/${id}/configuration`, "PATCH", config)).status,
  403,
);
assert.equal(
  (await req(owner, `/team/${w.membership.id}`, "DELETE")).status,
  200,
);
assert.equal((await req(staff, "/team")).status, 403);
assert.equal((await req(staff, "/workspace")).status, 403);
console.log(
  "Local HTTP E2E passed: Firebase auth, organization, resources, activation, staff acceptance, scope and revocation.",
);
