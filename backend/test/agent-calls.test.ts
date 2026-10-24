import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { SarvamService } from "../src/sarvam/sarvam.service";
import { AdminService } from "../src/admin/admin.service";
import { CourtService } from "../src/court/court.service";
import { BookingService } from "../src/bookings/booking.service";
import { VoiceService } from "../src/sarvam/voice.service";
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

test("managed service verifies deployment, enforces services/spaces and preserves history when paused", async () => {
  const booking = new BookingService(db, workspace),
    voice = new VoiceService(db, booking),
    courts = new CourtService(db, workspace);
  const w = await workspace.workspace(owner);
  const business = await workspace.createBusiness(owner, {
    name: "Arena",
    type: "badminton",
    location_id: w.locations[0].id,
  });
  const ids = [randomUUID(), randomUUID()];
  const hours = {
    days: [1, 2, 3, 4, 5, 6, 7],
    opens_at: "06:00",
    closes_at: "22:00",
    date_from: null,
    date_until: null,
  };
  await courts.configure(owner, business.id, {
    version: 1,
    configuration: {
      kind: "court_v1",
      schema_version: 1,
      courts: ids.map((id, i) => ({
        id,
        name: `Court ${i + 1}`,
        enabled: true,
        environment: "indoor",
        surface: "",
        operating: hours,
        durations: [60],
        default_duration_minutes: 60,
        buffer_before: 0,
        buffer_after: 0,
        pricing_basis: "start_time",
        tariffs: [
          {
            id: randomUUID(),
            hours,
            rates: [{ duration_minutes: 60, price_minor: 50000 }],
          },
        ],
      })),
    },
  });
  await workspace.activate(owner, business.id);
  assert.equal((await calls.status(owner)).status, "none");
  await assert.rejects(
    calls.request(owner, { services: [] }),
    /Choose at least one/,
  );
  await assert.rejects(calls.request(owner, { services: ["refund"] }));
  await calls.request(owner, {
    note: "Please",
    services: ["booking", "enquiry"],
  });
  await assert.rejects(
    calls.request(owner, { services: ["booking"] }),
    /already requested/,
  );
  const request = async () =>
    (await admin.agentRequests(root, {})).requests.find(
      (r: any) => r.organization_id === orgId,
    ) as any;
  let r = await request();
  await assert.rejects(
    admin.updateAgentRequest(root, r.id, {
      version: r.version,
      status: "active",
    }),
    /Verify/,
  );
  const supportActor = actor();
  await db.query(
    "INSERT INTO platform_admins(user_id,email,role) VALUES($1,$2,'support')",
    [supportActor.uid, supportActor.email],
  );
  await assert.rejects(admin.connection(supportActor, orgId), /Super-admin/);
  await assert.rejects(admin.saveConnection(owner, orgId, {}), /Admin access/);
  const input = {
    version: 0,
    api_key: "sk_test_12345678",
    sarvam_org_id: "org1",
    workspace_id: "ws1",
    app_id: "app1",
    deployment_id: "deployment1",
    phone_number: "+919876543210",
    approved_services: ["booking", "enquiry"],
  };
  await assert.rejects(
    admin.saveConnection(root, orgId, {
      ...input,
      approved_services: ["cancellation"],
    }),
    /requested/,
  );
  await admin.saveConnection(root, orgId, input);
  const { tool_key } = await admin.rotateToolKey(root, orgId);
  let validDeployment = false;
  provider.http = async (url) =>
    String(url).includes("/deployments/")
      ? Response.json({
          deployment_id: "deployment1",
          app_id: "app1",
          status: "active",
          channel_direction: "inbound",
          connection_configs: [
            {
              phone_numbers: [
                validDeployment ? "+919876543210" : "+919111111111",
              ],
            },
          ],
        })
      : Response.json({ items: [], total: 0 });
  let connection = await admin.connection(root, orgId);
  await assert.rejects(
    admin.verifyConnection(root, orgId, {
      version: connection.version,
      tools_confirmed: true,
    }),
    /match/,
  );
  validDeployment = true;
  await admin.verifyConnection(root, orgId, {
    version: connection.version,
    tools_confirmed: true,
  });
  r = await request();
  await admin.updateAgentRequest(root, r.id, {
    version: r.version,
    status: "active",
    user_message: "Ready",
  });
  let state = await calls.status(owner);
  assert.equal(state.ready, true);
  assert.equal(state.enabled, false);
  assert.equal(state.phone_number, input.phone_number);
  assert.deepEqual(state.approved_services, ["booking", "enquiry"]);
  assert.ok(state.spaces.every((s) => !s.enabled));
  await assert.rejects(
    calls.setEnabled(owner, { enabled: true, version: state.version }),
    /ready space/,
  );
  await assert.rejects(
    calls.setSpaces(owner, {
      resource_ids: [randomUUID()],
      version: state.version,
    }),
    /your organization/,
  );
  state = await calls.setSpaces(owner, {
    resource_ids: [ids[0]],
    version: state.version,
  });
  await assert.rejects(
    calls.setSpaces(owner, { resource_ids: [], version: state.version - 1 }),
    /changed/,
  );
  state = await calls.setEnabled(owner, {
    enabled: true,
    version: state.version,
  });
  const agent = await provider.authenticateToolKey(tool_key);
  const catalog = await voice.catalog(agent);
  assert.deepEqual(
    catalog.businesses[0].spaces.map((s: any) => s.name),
    ["Court 1"],
  );
  await assert.rejects(voice.cancel(agent, {}), /not enabled/);
  await assert.rejects(voice.reschedule(agent, {}), /not enabled/);
  await assert.rejects(
    voice.mine(agent, { caller_phone: "+919999999999" }),
    /not enabled/,
  );
  await assert.rejects(
    voice.availability(agent, { space: "Court 2", date: "2030-06-04" }),
    /could not find/,
  );
  const booked = await voice.book(agent, {
    space: "Court 1",
    date: "2030-06-04",
    time: "10:00",
    customer_name: "Caller",
    caller_phone: "+919999999999",
    interaction_id: "test-call",
    expected_total: 500,
  });
  assert.equal(booked.ok, true);
  // A cached catalog cannot keep a removed space bookable.
  state = await calls.setSpaces(owner, {
    resource_ids: [ids[1]],
    version: state.version,
  });
  await assert.rejects(
    voice.book(agent, {
      space: "Court 1",
      date: "2030-06-04",
      time: "11:00",
      customer_name: "Caller",
      caller_phone: "+919999999999",
      interaction_id: "test-call-2",
    }),
    /could not find/,
  );
  await calls.recordEvent(agent, {
    interaction_id: "test-call",
    caller_phone: "+919999999999",
    duration_seconds: 60,
    transcript: "Agent: Hello. Caller: Book a court.",
    summary: "Booked Court 1",
    disposition: "booked",
  });
  const saved = await calls.calls(owner, {
    start: new Date(Date.now() - 86400000).toISOString(),
    end: new Date(Date.now() + 1000).toISOString(),
  });
  assert.equal(saved.items[0].summary, "Booked Court 1");
  assert.match(saved.warning, /catches up/);
  provider.http = async () => {
    throw Error("provider unavailable");
  };
  r = await request();
  await admin.updateAgentRequest(root, r.id, {
    version: r.version,
    status: "paused",
    user_message: "Temporarily on hold",
  });
  assert.equal((await calls.status(owner)).enabled, false);
  await assert.rejects(provider.authenticateToolKey(tool_key), /turned off/);
  await assert.rejects(voice.catalog(agent), /turned off/);
  // Call completion can still be recorded with the valid key after pausing.
  assert.equal(
    (await provider.authenticateToolKey(tool_key, true)).uid,
    agent.uid,
  );
  const history = await calls.calls(owner, {
    start: new Date(Date.now() - 86400000).toISOString(),
    end: new Date(Date.now() + 1000).toISOString(),
  });
  assert.equal(history.items[0].summary, "Booked Court 1");
  assert.match(history.warning, /saved calls/);
  assert.match((await calls.transcript(owner, "test-call")).text, /Hello/);
  // A reused interaction ID on a replacement agent cannot overwrite archived transcripts.
  await db.query(
    "UPDATE sarvam_integrations SET app_id='replacement-app' WHERE organization_id=$1",
    [orgId],
  );
  await calls.recordEvent(agent, {
    interaction_id: "test-call",
    duration_seconds: 10,
    transcript: "Unrelated replacement call",
  });
  assert.match((await calls.transcript(owner, "test-call")).text, /Hello/);
  await db.query(
    "UPDATE sarvam_integrations SET app_id=$2 WHERE organization_id=$1",
    [orgId, input.app_id],
  );
  assert.equal((await calls.status(owner)).call_logs_available, true);
  const other = actor();
  await workspace.createOrganization(other, {
    name: "Other",
    contact_phone: "9876543211",
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
  await assert.rejects(calls.transcript(other, "test-call"), /not found/);
  const otherOrg = (await workspace.member(other, true)).organization_id;
  await calls.request(other, { services: ["booking"] });
  await assert.rejects(
    admin.saveConnection(root, otherOrg, {
      ...input,
      approved_services: ["booking"],
    }),
    /already assigned/,
  );
  // Client can always turn actions off, even with stale settings.
  await calls.setEnabled(owner, { enabled: false, version: 1 });
  assert.ok(!JSON.stringify(await calls.status(owner)).includes("sarvam"));
  assert.ok(
    !JSON.stringify(await admin.connection(root, orgId)).includes(
      "sk_test_12345678",
    ),
  );
});

test("enquiries-only connections cannot write through the underlying booking service", async () => {
  const r = (await admin.agentRequests(root, {})).requests.find(
    (r: any) => r.organization_id === orgId,
  ) as any;
  const c = await admin.connection(root, orgId);
  await admin.saveConnection(root, orgId, {
    version: c.version,
    sarvam_org_id: c.sarvam_org_id,
    workspace_id: c.workspace_id,
    app_id: c.app_id,
    deployment_id: c.deployment_id,
    phone_number: c.phone_number,
    approved_services: ["enquiry"],
  });
  provider.http = async (url) =>
    String(url).includes("/deployments/")
      ? Response.json({
          deployment_id: c.deployment_id,
          app_id: c.app_id,
          status: "active",
          channel_direction: "inbound",
          connection_configs: [{ phone_numbers: [c.phone_number] }],
        })
      : Response.json({ items: [], total: 0 });
  await admin.verifyConnection(root, orgId, {
    version: (await admin.connection(root, orgId)).version,
    tools_confirmed: true,
  });
  const current = (await admin.agentRequests(root, {})).requests.find(
    (x: any) => x.id === r.id,
  ) as any;
  await admin.updateAgentRequest(root, r.id, {
    version: current.version,
    status: "active",
  });
  let state = await calls.status(owner);
  state = await calls.setEnabled(owner, {
    enabled: true,
    version: state.version,
  });
  const agent = {
    uid: `sarvam:${orgId}`,
    email: "voice@invalid",
    name: "Voice",
  };
  const bookings = new BookingService(db, workspace),
    voice = new VoiceService(db, bookings);
  await assert.rejects(voice.book(agent, {}), /not enabled/);
  const catalog = await bookings.catalog(owner),
    b = catalog.businesses[0],
    resource = b.resources[0],
    option = resource.options[0];
  const selection = {
    business_id: b.id,
    resource_id: resource.id,
    option_id: option.id,
    date: "2030-06-04",
    time: "15:00",
    duration_minutes: 60,
    people: 1,
  };
  const quote = await bookings.quote(owner, {
    selection,
    exclude_booking_id: null,
  });
  await assert.rejects(
    bookings.create(agent, {
      selection,
      quote_token: quote.quote_token,
      command_key: randomUUID(),
      customer: {
        id: null,
        name: "Caller",
        phone: "+919999999999",
        email: null,
      },
      payments: [],
      notes: "",
    }),
    /not enabled/,
  );
  state = await calls.setSpaces(owner, {
    version: state.version,
    resource_ids: [],
  });
  assert.equal(state.enabled, false);
  assert.equal(
    (
      await db.query(
        "SELECT 1 FROM staff_assignments a JOIN sarvam_integrations s ON s.membership_id=a.membership_id WHERE s.organization_id=$1",
        [orgId],
      )
    ).rows.length,
    0,
  );
});
