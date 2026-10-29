import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { SarvamService } from "../src/sarvam/sarvam.service";
import { AdminService } from "../src/admin/admin.service";
import { AdminSarvamService } from "../src/admin/admin-sarvam.service";
import { AgentCallService } from "../src/agent-calls/agent-calls.service";
import { MCP } from "../src/sarvam/sarvam-authoring";
import { openSecret } from "../src/sarvam/sarvam-secrets";
type Json = Record<string, any>;
delete process.env.DATABASE_URL;
Object.assign(process.env, {
  NODE_ENV: "test",
  PGLITE_PATH: "memory://",
  BOOKING_SECRETS_KEY: Buffer.alloc(32, 9).toString("base64"),
  SARVAM_ADMIN_REDIRECT_URI:
    "https://booking.example.test/admin/agent-requests/mcp/callback",
});
const db = new Database(),
  workspace = new WorkspaceService(db),
  provider = new SarvamService(db, workspace),
  admin = new AdminService(db, provider),
  service = new AdminSarvamService(db, admin, provider, workspace),
  calls = new AgentCallService(db, workspace, provider);
workspace.publicAppUrl = "https://api.example.test/functions/v1/booking-api";
const actor = () => ({
  uid: randomUUID(),
  email: `${randomUUID()}@example.com`,
  name: "Owner",
});
const root = actor(),
  support = actor(),
  owner = actor(),
  second = actor();
let org = "",
  org2 = "";
const agents: Json = {
  template: {
    config: {
      org_id: "org1",
      workspace_id: "ws1",
      app_id: "template",
      app_version: 1,
      status: "draft",
      llm_config: {
        agent_config: {
          initial_state_name: "main",
          states: { main: { instructions: "Template", tool_names: [] } },
        },
      },
    },
    tools: [],
  },
};
const committedVersions: Record<string, Record<number, Json>> = {};
const deployments: Json[] = [],
  secrets = new Map<string, string>();
let writes = 0,
  agentCreates = 0,
  deployCreates = 0,
  loseCommit = false,
  loseCreation = false,
  loseDeployment = false,
  expired = false,
  unsupported = false;
const schema = (keys: string[], required: string[] = [], ops?: string[]) => ({
  type: "object",
  properties: Object.fromEntries(
    keys.map((k) => [
      k,
      k === "operation" && ops ? { type: "string", enum: ops } : {},
    ]),
  ),
  required,
});
const specs = [
  {
    name: "agents",
    inputSchema: schema(
      ["operation", "id", "params", "fetch_all"],
      ["operation"],
      ["list", "get", "commit", "set_tools"],
    ),
  },
  {
    name: "telephony",
    inputSchema: schema(
      ["operation", "id", "params", "fetch_all"],
      ["operation"],
      [
        "list_connections",
        "list_endpoints",
        "list_deployments",
        "get_deployment",
      ],
    ),
  },
  {
    name: "secrets",
    inputSchema: schema(["operation"], ["operation"], ["list"]),
  },
  {
    name: "configure_agent",
    inputSchema: schema([
      "agent_id",
      "name",
      "clone_from",
      "clone_version",
      "config",
      "prompt",
    ]),
  },
  {
    name: "configure_secret",
    inputSchema: schema(["name", "value"], ["name", "value"]),
  },
  {
    name: "configure_app_tool",
    inputSchema: schema(
      ["agent_id", "name", "description", "tool_type", "connector_config"],
      ["agent_id", "name", "connector_config"],
    ),
  },
  {
    name: "configure_deployment",
    inputSchema: schema(
      [
        "name",
        "app_id",
        "app_version",
        "connection_configs",
        "channel_direction",
        "operation",
      ],
      ["app_id", "app_version", "connection_configs"],
      ["create"],
    ),
  },
];
function merge(a: Json, b: Json) {
  for (const [k, v] of Object.entries(b)) {
    if (v && typeof v === "object" && !Array.isArray(v))
      merge((a[k] ??= {}), v);
    else a[k] = v;
  }
}
provider.http = async (url, init) => {
  const target = String(url);
  if (target === `${MCP}/register`)
    return Response.json({ client_id: "bookingos-client" });
  if (target === `${MCP}/token`) {
    assert.ok(String(init?.body).includes("code_verifier="));
    return Response.json({
      access_token: "private-oauth-token",
      token_type: "Bearer",
      expires_in: 86400,
    });
  }
  if (target !== MCP) {
    if (target.includes("/deployments/")) {
      const d = deployments.find(
        (d) => d.deployment_id === target.split("/").at(-1),
      );
      return d ? Response.json(d) : Response.json({}, { status: 404 });
    }
    return Response.json({ items: [], total: 0 });
  }
  if (expired) return Response.json({}, { status: 401 });
  const req = JSON.parse(String(init?.body));
  if (req.method === "notifications/initialized")
    return new Response(null, { status: 202 });
  if (req.method === "initialize")
    return Response.json({
      id: req.id,
      result: { protocolVersion: "2025-03-26" },
    });
  if (req.method === "tools/list")
    return Response.json({
      id: req.id,
      result: {
        tools: unsupported
          ? specs.filter((s) => s.name !== "configure_app_tool")
          : specs,
      },
    });
  assert.equal(
    new Headers(init?.headers).get("authorization"),
    "Bearer private-oauth-token",
  );
  const { name, arguments: a } = req.params;
  let value: Json = {};
  if (name === "agents") {
    if (a.operation === "list")
      value = {
        items: Object.keys(agents).map((app_id) => ({
          app_id,
          app_name: agents[app_id].app_name ?? app_id,
        })),
      };
    else if (a.operation === "get") {
      const source =
        committedVersions[a.id]?.[a.params?.app_version] ?? agents[a.id];
      const { org_id, workspace_id, app_id, app_version, status, ...config } =
        source.config;
      value = {
        ...source,
        org_id,
        workspace_id,
        app_id,
        app_version,
        status,
        config,
      };
    } else if (a.operation === "commit") {
      const agent = agents[a.id],
        v = agent.config.app_version;
      agent.config.status = "committed";
      (committedVersions[a.id] ??= {})[v] = structuredClone(agent);
      agent.config = {
        ...structuredClone(agent.config),
        app_version: v + 1,
        status: "draft",
      };
      value = { details: { app_version: v } };
      if (loseCommit) {
        loseCommit = false;
        throw Error("lost commit response");
      }
    } else if (a.operation === "set_tools")
      for (const t of agents[a.id].tools)
        t.enabled = a.params.enable.includes(t.name);
  } else if (name === "telephony")
    if (a.operation === "get_deployment")
      value = deployments.find((d) => d.deployment_id === a.id)!;
    else
      value = {
        items:
          a.operation === "list_connections"
            ? [{ connection_id: "conn1", name: "Main line" }]
            : a.operation === "list_endpoints"
              ? [
                  { phone_number: "+919999999991", status: "active" },
                  { phone_number: "+919999999992", status: "active" },
                ]
              : deployments,
      };
  else if (name === "configure_agent") {
    writes++;
    if (!a.agent_id) {
      assert.ok(a.clone_from && a.name);
      agentCreates++;
      const app = randomUUID();
      agents[app] = {
        ...structuredClone(agents[a.clone_from]),
        app_name: a.name,
      };
      Object.assign(agents[app].config, {
        app_id: app,
        app_version: 1,
        status: "draft",
      });
      value = { id: app, details: { app_id: app } };
      if (loseCreation) {
        loseCreation = false;
        throw Error("lost creation response");
      }
    } else {
      for (const state of Object.values(
        a.config?.llm_config?.agent_config?.states ?? {},
      ))
        assert.ok(
          !("instructions" in (state as Json)),
          "Prompt text must use the prompt parameter",
        );
      merge(agents[a.agent_id].config, a.config ?? {});
      if (a.prompt) {
        for (const match of a.prompt.matchAll(/tool:(bookingos_[a-z_]+)/g))
          assert.ok(
            agents[a.agent_id].tools.some((t: Json) => t.name === match[1]),
            "Tools must exist before the prompt references them",
          );
        const initial =
          agents[a.agent_id].config.llm_config.agent_config.initial_state_name;
        agents[a.agent_id].config.llm_config.agent_config.states[
          initial
        ].instructions = a.prompt;
      }
    }
  } else if (name === "configure_secret") {
    writes++;
    secrets.set(a.name, a.value);
    value = { id: a.name };
  } else if (name === "configure_app_tool") {
    writes++;
    if (a.connector_config.lifecycle === "on_end") {
      const supported = new Set([
        "interaction_id",
        "user_identifier",
        "call_duration_seconds",
        "interaction_transcript",
      ]);
      for (const field of a.connector_config.body)
        if (field.type === "system_variable")
          assert.ok(
            supported.has(field.value.variable_name),
            "Unsupported Sarvam call-end context variable",
          );
    }
    assert.ok(!agents[a.agent_id].tools.some((t: Json) => t.name === a.name));
    agents[a.agent_id].tools.push({
      id: randomUUID(),
      name: a.name,
      connector_config: structuredClone(a.connector_config),
      enabled: true,
    });
  } else if (name === "configure_deployment") {
    writes++;
    deployCreates++;
    value = {
      deployment_id: randomUUID(),
      app_id: a.app_id,
      app_version: a.app_version,
      channel_direction: "inbound",
      status: "active",
      connection_configs: a.connection_configs,
    };
    deployments.push(value);
    value = { id: value.deployment_id, details: value };
    if (loseDeployment) {
      loseDeployment = false;
      throw Error("lost deployment response");
    }
  } else if (name !== "secrets") throw Error(`Unexpected MCP tool ${name}`);
  return Response.json({
    id: req.id,
    result: { structuredContent: value ?? {} },
  });
};
async function organization(who: ReturnType<typeof actor>) {
  await workspace.createOrganization(who, {
    name: "Venue",
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
  const org = (await workspace.member(who, true)).organization_id;
  await calls.request(who, { services: ["booking", "enquiry"] });
  return org;
}
async function settings() {
  return service.status(root);
}
async function reconnect() {
  const { authorization_url } = await service.connect(root);
  const u = new URL(authorization_url);
  assert.equal(
    u.searchParams.get("redirect_uri"),
    process.env.SARVAM_ADMIN_REDIRECT_URI,
  );
  assert.equal(u.searchParams.get("code_challenge_method"), "S256");
  const state = u.searchParams.get("state")!;
  await assert.rejects(
    service.callback(root, {
      state: "invalid_state_that_does_not_match",
      code: "one-time-code",
    }),
    /invalid/,
  );
  await service.callback(root, { state, code: "one-time-code" });
  return state;
}
async function version(id: string) {
  return (
    await db.query<Json>(
      "SELECT version FROM agent_call_requests WHERE organization_id=$1",
      [id],
    )
  ).rows[0].version;
}
const approve = async (
  id: string,
  phone = "+919999999991",
  services = ["booking"],
) =>
  service.approve(root, id, {
    version: await version(id),
    approved_services: services,
    phone_number: phone,
    connection_id: "conn1",
  });
before(async () => {
  await db.onModuleInit();
  org = await organization(owner);
  org2 = await organization(second);
  for (const [who, role] of [
    [root, "super_admin"],
    [support, "support"],
  ] as const)
    await db.query(
      "INSERT INTO platform_admins(user_id,email,role) VALUES($1,$2,$3)",
      [who.uid, who.email, role],
    );
});
after(() => db.onModuleDestroy());
test("only super admins can view, authorize, approve or resume", async () => {
  for (const who of [owner, support]) {
    await assert.rejects(service.status(who), /Admin|Super-admin/);
    await assert.rejects(service.connect(who), /Admin|Super-admin/);
    await assert.rejects(service.approve(who, org, {}), /Admin|Super-admin/);
    await assert.rejects(service.resume(who, org), /Admin|Super-admin/);
  }
  assert.equal(writes, 0);
});
test("OAuth uses PKCE, consumes state once and hides encrypted credentials", async () => {
  await service.save(root, {
    version: (await settings()).version,
    sarvam_org_id: "org1",
    workspace_id: "ws1",
    api_key: "private-workspace-api-key",
    template_app_id: "template",
  });
  const state = await reconnect();
  await assert.rejects(
    service.callback(root, { state, code: "reused" }),
    /already used/,
  );
  const s = await settings();
  assert.equal(s.connected, true);
  assert.ok(!JSON.stringify(s).includes("private-"));
  const row = (await db.query<Json>("SELECT * FROM sarvam_admin_connection"))
    .rows[0];
  assert.equal(openSecret(row.authoring_ciphertext), "private-oauth-token");
  assert.ok(!row.authoring_ciphertext.includes("private-oauth-token"));
  const i = await service.inventory(root);
  assert.equal(i.numbers.length, 2);
  assert.equal(i.templates[0].id, "template");
});
test("approval checks services, capabilities and number ownership before reserving a client agent", async () => {
  await assert.rejects(approve(org, undefined, ["cancellation"]), /requested/);
  await assert.rejects(approve(org, "+919999999999"), /available/);
  unsupported = true;
  await assert.rejects(approve(org), /HTTP-tool/);
  unsupported = false;
  assert.equal(writes, 0);
  const job = await approve(org);
  assert.equal(job.step, "create");
  await assert.rejects(approve(org2), /reserved/);
  assert.equal((await service.inventory(root)).numbers[0].assigned, true);
  await assert.rejects(admin.rotateToolKey(root, org), /automatically/);
});
test("an approval change stops setup before creating provider resources", async () => {
  const before = writes;
  await db.query(
    "UPDATE agent_call_requests SET approved_services=$2 WHERE organization_id=$1",
    [org, ["booking", "enquiry"]],
  );
  await assert.rejects(service.resume(root, org), /Approved services changed/);
  assert.equal(writes, before);
  assert.equal((await service.job(root, org)).step, "create");
  await db.query(
    "UPDATE agent_call_requests SET approved_services=$2 WHERE organization_id=$1",
    [org, ["booking"]],
  );
});
test("lost create response and expired OAuth resume without a second agent", async () => {
  loseCreation = true;
  await assert.rejects(service.resume(root, org), /did not respond/);
  assert.equal(agentCreates, 1);
  await service.resume(root, org);
  assert.equal(agentCreates, 1);
  await db.query(
    "UPDATE sarvam_admin_connection SET expires_at=now()-interval '1 second'",
  );
  assert.equal((await settings()).needs_reconnect, true);
  await assert.rejects(service.resume(root, org), /Reconnect/);
  assert.equal((await service.job(root, org)).step, "variables");
  await reconnect();
  await service.resume(root, org);
  assert.equal((await service.job(root, org)).step, "secret");
  await service.resume(root, org);
  assert.equal((await service.job(root, org)).step, "tool_0");
  expired = true;
  await assert.rejects(service.resume(root, org), /Reconnect/);
  expired = false;
  assert.equal((await settings()).connected, false);
  await reconnect();
});
test("all tenant tools are verified and a lost deployment response does not duplicate the number assignment", async () => {
  for (
    let i = 0;
    i < 15 && (await service.job(root, org)).step !== "commit";
    i++
  )
    await service.resume(root, org);
  loseCommit = true;
  await assert.rejects(service.resume(root, org), /did not respond/);
  await service.resume(root, org);

  for (
    let i = 0;
    i < 15 && (await service.job(root, org)).step !== "deploy";
    i++
  )
    await service.resume(root, org);
  assert.equal((await service.job(root, org)).step, "deploy");
  loseDeployment = true;
  await assert.rejects(service.resume(root, org), /did not respond/);
  assert.equal(deployCreates, 1);
  await service.resume(root, org);
  assert.equal(deployCreates, 1);
  const done = await service.resume(root, org);
  assert.equal(done.done, true);
  const s = await calls.status(owner);
  assert.equal(s.status, "active");
  assert.equal(s.enabled, false);
  assert.deepEqual(s.approved_services, ["booking"]);
  assert.equal(s.phone_number, "+919999999991");
  const remote = agents[done.app_id];
  assert.deepEqual(
    remote.tools.map((tool: Json) => tool.name).sort(),
    [
      "bookingos_list_spaces",
      "bookingos_check_availability",
      "bookingos_book_slot",
      "bookingos_call_completed",
    ].sort(),
  );
  assert.doesNotMatch(
    remote.config.llm_config.agent_config.states.main.instructions,
    /tool:bookingos_(cancel_booking|reschedule_booking|my_bookings)/,
  );
  assert.equal(
    remote.tools.find((t: Json) => t.name === "bookingos_call_completed")
      .connector_config.lifecycle,
    "on_end",
  );
  assert.equal(
    remote.tools
      .find((t: Json) => t.name === "bookingos_book_slot")
      .connector_config.body.find((b: Json) => b.name === "caller_phone").type,
    "system_variable",
  );
  assert.ok(!JSON.stringify(done).includes("private-"));
  assert.ok(!JSON.stringify(s).includes("sarvam"));
  assert.equal((await service.resume(root, org)).done, true);
});
test("reconnect preserves connected clients and cannot switch the platform workspace", async () => {
  const prior = await calls.status(owner);
  await reconnect();
  assert.deepEqual(await calls.status(owner), prior);
  await assert.rejects(
    service.save(root, {
      version: (await settings()).version,
      sarvam_org_id: "another",
      workspace_id: "other",
    }),
    /managed agents/,
  );
});

test("a second organization gets its own agent and secret; suspension and tool tampering prevent activation", async () => {
  const first = await service.job(root, org);
  const secondJob = await approve(org2, "+919999999992", ["enquiry"]);
  assert.notEqual(secondJob.app_id, first.app_id);
  let request = (
    await db.query<Json>(
      "SELECT id,version FROM agent_call_requests WHERE organization_id=$1",
      [org2],
    )
  ).rows[0];
  await admin.updateAgentRequest(root, request.id, {
    version: request.version,
    status: "paused",
  });
  await assert.rejects(service.resume(root, org2), /on hold/);
  assert.equal((await service.job(root, org2)).step, "create");
  request = (
    await db.query<Json>(
      "SELECT id,version FROM agent_call_requests WHERE organization_id=$1",
      [org2],
    )
  ).rows[0];
  await admin.updateAgentRequest(root, request.id, {
    version: request.version,
    status: "setting_up",
  });
  for (
    let i = 0;
    i < 15 && (await service.job(root, org2)).step !== "verify_tools";
    i++
  )
    await service.resume(root, org2);
  const actualSecond = await service.job(root, org2);
  const tool = agents[actualSecond.app_id].tools.find(
    (t: Json) => t.name === "bookingos_check_availability",
  );
  const reference = tool.connector_config.auth.value.secret_id;
  assert.deepEqual(
    agents[actualSecond.app_id].tools
      .map((candidate: Json) => candidate.name)
      .sort(),
    [
      "bookingos_list_spaces",
      "bookingos_check_availability",
      "bookingos_call_completed",
    ].sort(),
  );
  assert.doesNotMatch(
    agents[actualSecond.app_id].config.llm_config.agent_config.states.main
      .instructions,
    /tool:bookingos_(book_slot|cancel_booking|reschedule_booking|my_bookings)/,
  );
  tool.connector_config.auth.value.secret_id = "foreign-secret";
  await assert.rejects(service.resume(root, org2), /tool verification/);
  assert.equal((await calls.status(second)).enabled, false);
  assert.equal((await calls.status(second)).status, "setting_up");
  tool.connector_config.auth.value.secret_id = reference;
  for (let i = 0; i < 8 && !(await service.job(root, org2)).done; i++)
    await service.resume(root, org2);
  assert.equal((await service.job(root, org2)).done, true);
  const keys = (
    await db.query<Json>(
      "SELECT tool_key_ciphertext FROM sarvam_integrations WHERE organization_id=ANY($1::uuid[])",
      [[org, org2]],
    )
  ).rows.map((r) => openSecret(r.tool_key_ciphertext));
  assert.equal(new Set(keys).size, 2);
  await service.save(root, {
    version: (await settings()).version,
    sarvam_org_id: "org1",
    workspace_id: "ws1",
    api_key: "rotated-workspace-api-key",
  });
  const rows = (
    await db.query<Json>(
      "SELECT api_key_ciphertext,tool_key_ciphertext FROM sarvam_integrations WHERE organization_id=ANY($1::uuid[])",
      [[org, org2]],
    )
  ).rows;
  assert.ok(
    rows.every(
      (r) => openSecret(r.api_key_ciphertext) === "rotated-workspace-api-key",
    ),
  );
  assert.deepEqual(
    rows.map((r) => openSecret(r.tool_key_ciphertext)),
    keys,
  );
});
