import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { Actor } from "../src/common/auth.guard";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  s = new WorkspaceService(db);
const owner: Actor = {
    uid: randomUUID(),
    email: "edit@example.com",
    name: "Owner",
  },
  other: Actor = {
    uid: randomUUID(),
    email: "other@example.com",
    name: "Other",
  },
  staff: Actor = {
    uid: randomUUID(),
    email: "staff@example.com",
    name: "Staff",
  };
const org = {
  name: "Original organization",
  contact_phone: "9876543210",
  currency: "INR",
  location: {
    name: "Arena",
    address_line_1: "Original road",
    address_line_2: null,
    city: "Kochi",
    state_code: "KL",
    country_code: "IN",
    postal_code: "682001",
    timezone: "Asia/Kolkata",
  },
};
before(async () => {
  await db.onModuleInit();
  await s.createOrganization(owner, org);
  await s.createOrganization(other, org);
  const m = await s.member(owner);
  await db.query(
    "INSERT INTO memberships(id,organization_id,user_id,email,display_name,role,permissions) VALUES($1,$2,$3,$4,$5,'staff','[]')",
    [randomUUID(), m.organization_id, staff.uid, staff.email, staff.name],
  );
});
after(() => db.onModuleDestroy());
const body = (d: any) => ({
  revision: d.revision,
  name: d.name,
  contact_phone: d.contact_phone,
  locations: d.locations.map(({ timezone, ...l }: any) => l),
});
test("owner updates name, phone and every address field without changing timezone", async () => {
  const d = await s.organizationDetails(owner),
    v = body(d);
  v.name = "Updated organization";
  v.contact_phone = "+91 98765 43210";
  v.locations[0] = {
    ...v.locations[0],
    name: "New Arena",
    address_line_1: "14 Garden Road",
    address_line_2: "Near park",
    city: "Thrissur",
    postal_code: "680001",
  };
  const saved = await s.updateOrganization(owner, v);
  assert.equal(saved.name, v.name);
  assert.equal(saved.locations[0].address_line_2, "Near park");
  assert.equal(saved.locations[0].timezone, "Asia/Kolkata");
  assert.notEqual(saved.revision, d.revision);
  const w = await s.workspace(owner);
  assert.equal(w.organization.name, v.name);
  assert.equal(w.locations[0].city, "Thrissur");
  assert.equal((await s.updateOrganization(owner, v)).revision, saved.revision);
});
test("stale edits conflict, and invalid address updates roll back all fields", async () => {
  const d = await s.organizationDetails(owner),
    v = body(d);
  await s.updateOrganization(owner, { ...v, name: "Concurrent change" });
  await assert.rejects(
    () => s.updateOrganization(owner, { ...v, name: "Stale change" }),
    /changed elsewhere/,
  );
  const fresh = await s.organizationDetails(owner),
    bad = body(fresh);
  bad.name = "Must not be saved";
  bad.locations[0].postal_code = "123";
  await assert.rejects(() => s.updateOrganization(owner, bad));
  assert.equal((await s.organizationDetails(owner)).name, "Concurrent change");
});
test("staff, cross-organization locations and timezone injection are rejected", async () => {
  await assert.rejects(() => s.organizationDetails(staff));
  const d = await s.organizationDetails(owner),
    foreign = await s.organizationDetails(other);
  await assert.rejects(() => s.updateOrganization(staff, body(d)));
  const v = body(d);
  v.locations[0].id = foreign.locations[0].id;
  await assert.rejects(() => s.updateOrganization(owner, v));
  const altered = body(d);
  altered.locations[0].timezone = "UTC";
  await assert.rejects(() => s.updateOrganization(owner, altered));
  const ownerData = await s.organizationDetails(owner);
  assert.equal(ownerData.locations[0].timezone, "Asia/Kolkata");
});
test("country and state are validated together; blank optional line can be cleared", async () => {
  const d = await s.organizationDetails(owner),
    v = body(d);
  v.locations[0].state_code = "XX";
  await assert.rejects(() => s.updateOrganization(owner, v));
  v.locations[0].state_code = "KL";
  v.locations[0].address_line_2 = null;
  const saved = await s.updateOrganization(owner, v);
  assert.equal(saved.locations[0].address_line_2, null);
});
