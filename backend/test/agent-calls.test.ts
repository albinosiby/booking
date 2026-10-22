import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { SarvamService } from "../src/sarvam/sarvam.service";
import { AdminService } from "../src/admin/admin.service";
import { SupportService } from "../src/support/support.service";
import { AgentCallService } from "../src/agent-calls/agent-calls.service";
import type { Actor } from "../src/common/auth.guard";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
process.env.BOOKING_SECRETS_KEY = Buffer.alloc(32, 7).toString("base64");
const db = new Database(),
  workspace = new WorkspaceService(db),
  provider = new SarvamService(db, workspace),
  admin = new AdminService(db, provider),
  support = new SupportService(db, workspace),
  calls = new AgentCallService(db, workspace, provider);
const actor = (): Actor => ({
  uid: randomUUID(),
  email: `${randomUUID()}@example.com`,
  name: "Owner",
});
const owner = actor(),
  root = actor();
let orgId = "";
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
  orgId = (await workspace.member(owner)).organization_id;
  await db.query(
    "INSERT INTO platform_admins(user_id,email,role) VALUES($1,$2,'super_admin')",
    [root.uid, root.email],
  );
});
after(() => db.onModuleDestroy());

test("support tickets round-trip between app and admin", async () => {
  const made = (await support.create(owner, {
    category: "booking",
    subject: "Cannot book",
    message: "The grid is empty.",
  })) as { ticket: { id: string } };
  assert.equal(((await support.list(owner)) as any).tickets.length, 1);
  await admin.reply(root, made.ticket.id, { body: "Looking now" });
  const thread = (await support.detail(owner, made.ticket.id)) as any;
  assert.deepEqual(
    thread.messages.map((m: any) => m.author),
    ["user", "admin"],
  );
  await admin.setTicketStatus(root, made.ticket.id, { status: "resolved" });
  const after = (await support.addMessage(owner, made.ticket.id, {
    message: "Still broken",
  })) as any;
  assert.equal(after.ticket.status, "open");
  await assert.rejects(support.create(owner, { subject: "x" }));
});

test("agent call service is request, admin setup, then owner control", async () => {
  assert.equal(((await calls.status(owner)) as any).status, "none");
  await assert.rejects(calls.setEnabled(owner, { enabled: true }), /not ready/);
  await calls.request(owner, { note: "Please" });
  await assert.rejects(calls.request(owner, {}), /already requested/);
  const req = ((await admin.agentRequests(root, {})) as any).requests[0];
  await admin.updateAgentRequest(root, req.id, {
    status: "active",
    user_message: "Ready",
  });
  // Active alone is not enough: the provider connection must exist.
  assert.equal(((await calls.status(owner)) as any).ready, false);
  const conn = (await admin.connection(root, orgId)) as any;
  await admin.saveConnection(root, orgId, {
    api_key: "sk_test_12345678",
    sarvam_org_id: "org1",
    workspace_id: "ws1",
    app_id: "app1",
    business_ids: [],
  });
  assert.equal(conn.has_tool_key, false);
  const key = (await admin.rotateToolKey(root, orgId)) as any;
  assert.match(key.tool_key, /^bkv_/);
  const state = (await calls.status(owner)) as any;
  assert.equal(state.ready, true);
  assert.equal(state.enabled, false);
  // No business assigned yet.
  await assert.rejects(
    calls.setEnabled(owner, { enabled: true }),
    /businesses/,
  );
  const result = JSON.stringify(await admin.connection(root, orgId));
  assert.ok(!result.includes("sk_test_12345678"));
});
