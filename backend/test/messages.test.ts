import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import {
  MessagesService,
  defaultBody,
  templateError,
} from "../src/messages/messages.service";
import type { Actor } from "../src/common/auth.guard";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  workspace = new WorkspaceService(db),
  service = new MessagesService(db, workspace);
const actor = (): Actor => ({
  uid: randomUUID(),
  email: `${randomUUID()}@example.com`,
  name: "Owner",
});
const owner = actor(),
  other = actor(),
  staff = actor();
async function org(a: Actor) {
  await workspace.createOrganization(a, {
    name: "Eden",
    contact_phone: "9876543210",
    currency: "INR",
    location: {
      name: "Main",
      address_line_1: "Road",
      address_line_2: null,
      city: "Kochi",
      state_code: "KL",
      country_code: "IN",
      postal_code: "682001",
      timezone: "Asia/Kolkata",
    },
  });
}
before(async () => {
  await db.onModuleInit();
  await org(owner);
  await org(other);
  const m = await workspace.member(owner);
  await db.query(
    "INSERT INTO memberships(id,organization_id,user_id,email,display_name,role,permissions) VALUES($1,$2,$3,$4,'Staff','staff',$5)",
    [
      randomUUID(),
      m.organization_id,
      staff.uid,
      staff.email,
      JSON.stringify(["view_bookings"]),
    ],
  );
});
after(() => db.onModuleDestroy());
const request = (name: string, body = defaultBody) => ({
  command_key: randomUUID(),
  name,
  body,
  website_url: "",
});
test("predefined template is always available and cannot be deleted", async () => {
  const c = await service.catalog(owner);
  assert.equal(c.templates.length, 1);
  assert.equal(c.templates[0].body, defaultBody);
  assert.equal(c.templates[0].is_primary, true);
  await assert.rejects(() => service.remove(owner, "default"));
  assert.equal((await service.catalog(staff)).can_manage, false);
});
test("template validation rejects unknown, incomplete, nested placeholders and unsafe website schemes", async () => {
  assert.equal(
    templateError("Hello {customer_name} *{booking_total}*"),
    undefined,
  );
  for (const body of [
    "",
    "Hello {unknown}",
    "Hello {customer_name",
    "Hello {{customer_name}}",
    "Hello {}",
    "x".repeat(6001),
  ]) {
    assert.ok(templateError(body));
    await assert.rejects(() => service.create(owner, request("Invalid", body)));
  }
  await assert.rejects(() =>
    service.create(owner, {
      ...request("Website"),
      website_url: "javascript:alert(1)",
    }),
  );
});
test("editing is a saved copy, retries are idempotent, primary is organization-scoped and unique", async () => {
  const req = request(
    "First custom",
    "Hi {customer_name}, pending {balance_due}",
  );
  const a = await service.create(owner, req);
  assert.equal((await service.create(owner, req)).id, a.id);
  await assert.rejects(() =>
    service.create(owner, { ...req, body: "Changed" }),
  );
  const b = await service.create(owner, request("Second custom"));
  await assert.rejects(() => service.create(owner, request("FIRST CUSTOM")));
  await Promise.all([
    service.primary(owner, { id: a.id }),
    service.primary(owner, { id: b.id }),
  ]);
  const rows = (await service.catalog(owner)).templates;
  assert.equal(rows.filter((t) => t.is_primary).length, 1);
  assert.equal(rows.find((t) => t.id === "default")!.body, defaultBody);
  assert.equal((await service.catalog(other)).templates.length, 1);
  await assert.rejects(() => service.primary(other, { id: a.id }));
  await assert.rejects(() => service.remove(other, a.id));
  await assert.rejects(() => service.create(staff, request("Forbidden")));
  await assert.rejects(() => service.primary(staff, { id: a.id }));
  await assert.rejects(() => service.remove(staff, a.id));
  const primary = rows.find((t) => t.is_primary)!;
  await service.remove(owner, String(primary.id));
  assert.equal(
    (await service.catalog(owner)).templates.find((t) => t.id === "default")!
      .is_primary,
    true,
  );
  const remaining = (await service.catalog(owner)).templates.find(
    (t) => t.id !== "default",
  )!;
  await service.primary(owner, { id: remaining.id });
  await service.primary(owner, { id: "default" });
  assert.equal(
    (await service.catalog(owner)).templates.find((t) => t.id === "default")!
      .is_primary,
    true,
  );
});
