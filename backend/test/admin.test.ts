import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { AdminService } from "../src/admin/admin.service";
import type { Actor } from "../src/common/auth.guard";
import { panelActor } from "../src/admin/panel-auth";
import { signAdminRequest } from "../../admin-panel/lib/request-signature";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  workspace = new WorkspaceService(db),
  service = new AdminService(db, undefined as never);
const actor = (): Actor => ({
  uid: randomUUID(),
  email: `${randomUUID()}@example.com`,
  name: "Person",
});
const owner = actor(),
  admin = actor();
before(async () => {
  await db.onModuleInit();
  await workspace.createOrganization(owner, {
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
  } as never);
  await db.query(
    "INSERT INTO platform_admins(user_id,email,role) VALUES($1,$2,'super_admin')",
    [admin.uid, admin.email],
  );
});
after(() => db.onModuleDestroy());

test("non-admins are refused every admin route", async () => {
  await assert.rejects(service.overview(owner), /Admin access required/);
  await assert.rejects(service.users(owner, {}), /Admin access required/);
});

test("signed password-panel requests need no Supabase user or platform membership", async () => {
  process.env.ADMIN_SESSION_SECRET =
    "test-only-panel-signing-secret-0123456789";
  const path = "/v1/admin/me";
  const actor = panelActor(
    signAdminRequest("GET", path),
    "GET",
    path,
    undefined,
  );
  assert.deepEqual(await service.me(actor), {
    email: "admin-panel@bookingos.internal",
    role: "super_admin",
  });
  const overview = (await service.overview(actor)) as { organizations: number };
  assert.equal(overview.organizations, 1);
  assert.equal(
    (
      await db.query("SELECT 1 FROM platform_admins WHERE user_id=$1", [
        actor.uid,
      ])
    ).rows.length,
    0,
  );
  await assert.rejects(service.overview({ ...actor }), /Admin access required/);
});

test("admin sees organizations, tickets and agent requests", async () => {
  const orgs = (await service.organizations(admin, { q: "eden" })) as {
    organizations: { id: string }[];
  };
  assert.equal(orgs.organizations.length, 1);
  const detail = (await service.organization(
    admin,
    orgs.organizations[0].id,
  )) as { members: { id: string; role: string }[] };
  const member = detail.members[0];
  const oid = orgs.organizations[0].id;
  const ticket = randomUUID(),
    request = randomUUID();
  await db.query(
    "INSERT INTO support_tickets(id,organization_id,membership_id,subject) VALUES($1,$2,$3,'Cannot book')",
    [ticket, oid, member.id],
  );
  await db.query(
    "INSERT INTO agent_call_requests(id,organization_id,membership_id) VALUES($1,$2,$3)",
    [request, oid, member.id],
  );
  const replied = (await service.reply(admin, ticket, { body: "Looking" })) as {
    ticket: { status: string };
    messages: unknown[];
  };
  assert.equal(replied.ticket.status, "in_progress");
  assert.equal(replied.messages.length, 1);
  await service.updateAgentRequest(admin, request, {
    status: "in_review",
    version: 1,
    user_message: "Reviewing",
  });
  const list = (await service.agentRequests(admin, {
    status: "in_review",
  })) as {
    requests: unknown[];
  };
  assert.equal(list.requests.length, 1);
  await assert.rejects(
    service.setUserActive(admin, member.id, { active: false }),
    /owner cannot be deactivated/,
  );
  const audit = (await service.auditLog(admin, {})) as { events: unknown[] };
  assert.equal(audit.events.length, 2);
});

test("support records without a deleted team identity remain available to admins", async () => {
  const organization = (await workspace.workspace(owner)).organization;
  const ticketId = randomUUID();
  await db.query(
    "INSERT INTO support_tickets(id,organization_id,membership_id,subject) VALUES($1,$2,NULL,'Former member question')",
    [ticketId, organization.id],
  );
  const listed = await service.tickets(admin, {});
  assert.ok(listed.tickets.some((t: any) => t.id === ticketId));
  const detail = await service.ticket(admin, ticketId);
  assert.equal((detail.ticket as any).user_name, "Removed team member");
});
