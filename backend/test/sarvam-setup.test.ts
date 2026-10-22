import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID, randomBytes } from "node:crypto";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { SarvamService, openSecret } from "../src/sarvam/sarvam.service";
import { MCP } from "../src/sarvam/sarvam-authoring";
import { TOOLS, BOOKING_PROMPT } from "../src/sarvam/sarvam-booking-config";
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
process.env.BOOKING_SECRETS_KEY = randomBytes(32).toString("base64");
delete process.env.DATABASE_URL;
const db = new Database(),
  workspace = new WorkspaceService(db);
workspace.publicAppUrl = "https://booking.example.test";
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());
type Json = Record<string, any>;
class FakeSarvam {
  tools: Json[] = [];
  secrets: Json[] = [];
  writes: string[] = [];
  missingCapability = "";
  failAfterTool = false;
  failAfterSecret = false;
  denyAnalytics = false;
  scope = "org-1";
  config: Json = {
    app_id: "agent-1",
    org_id: "org-1",
    workspace_id: "ws-1",
    app_version: 7,
    status: "draft",
    llm_config: {
      agent_config: {
        initial_state_name: "start",
        states: { start: { instructions: "Old instructions", tool_names: [] } },
        agent_variables: {},
      },
    },
  };
  deployment = {
    app_id: "agent-1",
    deployment_id: "deployment-1",
    name: "Sports",
    app_version: 6,
    status: "active",
  };
  fetch: typeof fetch = async (url, options) => {
    const path = String(url),
      body = options?.body
        ? JSON.parse(
            String(options.body).startsWith("{") ? String(options.body) : "{}",
          )
        : {};
    const json = (value: unknown, status = 200) =>
      new Response(JSON.stringify(value), {
        status,
        headers: { "Content-Type": "application/json" },
      });
    if (path.startsWith("https://apps.sarvam.ai/api/analytics/"))
      return json({ items: [] }, this.denyAnalytics ? 401 : 200);
    if (path === `${MCP}/register`) return json({ client_id: "oauth-client" });
    if (path === `${MCP}/token`) {
      const form = new URLSearchParams(String(options?.body));
      assert.equal(form.get("client_id"), "oauth-client");
      assert.equal(form.get("resource"), MCP);
      return json({
        access_token: "private-oauth-access",
        refresh_token: "private-oauth-refresh",
        token_type: "Bearer",
        expires_in: 3600,
      });
    }
    assert.equal(path, MCP);
    if (body.method === "initialize")
      return json({
        jsonrpc: "2.0",
        id: body.id,
        result: { protocolVersion: "2025-03-26", capabilities: {} },
      });
    if (body.method === "notifications/initialized")
      return new Response(null, { status: 202 });
    if (body.method === "tools/list")
      return json({
        id: body.id,
        result: {
          tools: [
            "agents",
            "configure_agent",
            "configure_secret",
            "secrets",
            "configure_app_tool",
            "telephony",
            "configure_deployment",
          ]
            .filter((n) => n !== this.missingCapability)
            .map((name) => ({ name })),
        },
      });
    assert.equal(body.method, "tools/call");
    const { name, arguments: args } = body.params;
    let result: Json = {};
    if (name === "agents") {
      if (args.operation === "get")
        result = {
          config: { ...this.config, org_id: this.scope },
          tools: this.tools,
        };
      if (args.operation === "set_tools") {
        this.writes.push("set_tools");
        for (const t of this.tools) {
          if (args.params.enable?.includes(t.name)) t.enabled = true;
          if (args.params.disable?.includes(t.name)) t.enabled = false;
        }
      }
      if (args.operation === "commit") {
        this.writes.push("commit");
        this.config.status = "committed";
        result = { id: "agent-1" };
      }
    } else if (name === "secrets")
      result = { items: this.secrets.map((s) => ({ id: s.id, name: s.name })) };
    else if (name === "configure_secret") {
      this.writes.push("secret");
      let secret = this.secrets.find((s) => s.name === args.name);
      if (!secret) {
        secret = { id: randomUUID(), name: args.name };
        this.secrets.push(secret);
      }
      secret.value = args.value;
      result = { id: secret.id };
      if (this.failAfterSecret) {
        this.failAfterSecret = false;
        return json({ message: "private-secret-must-not-leak" }, 503);
      }
    } else if (name === "configure_app_tool") {
      this.writes.push("tool");
      let tool = this.tools.find((t) => t.name === args.name);
      if (!tool) {
        tool = { id: randomUUID(), name: args.name, enabled: false };
        this.tools.push(tool);
      }
      tool.connector_config = args.connector_config;
      if (this.failAfterTool) {
        this.failAfterTool = false;
        return json({}, 503);
      }
    } else if (name === "configure_agent") {
      this.writes.push("agent");
      const incoming = args.config?.llm_config?.agent_config;
      if (incoming?.agent_variables)
        Object.assign(
          this.config.llm_config.agent_config.agent_variables,
          incoming.agent_variables,
        );
      if (incoming?.states)
        for (const [key, value] of Object.entries(incoming.states))
          Object.assign(this.config.llm_config.agent_config.states[key], value);
      if (args.prompt)
        this.config.llm_config.agent_config.states.start.instructions =
          args.prompt;
    } else if (name === "telephony")
      result =
        args.operation === "list_deployments"
          ? { items: [this.deployment] }
          : this.deployment;
    else if (name === "configure_deployment") {
      this.writes.push("deploy");
      this.deployment.app_version = args.app_version;
    } else assert.fail(`Unexpected MCP tool ${name}`);
    return json({
      id: body.id,
      result: { content: [{ type: "text", text: JSON.stringify(result) }] },
    });
  };
}
async function fixture() {
  const uid = randomUUID(),
    owner = { uid, email: `${uid}@example.com`, name: "Owner" };
  await workspace.createOrganization(owner, {
    name: "Sports",
    contact_phone: "9876543210",
    currency: "INR",
    location: {
      name: "Kochi",
      address_line_1: "Main",
      address_line_2: null,
      city: "Kochi",
      state_code: "KL",
      country_code: "IN",
      postal_code: "682001",
      timezone: "Asia/Kolkata",
    },
  });
  const w = await workspace.workspace(owner);
  const business = await workspace.createBusiness(owner, {
    name: "Courts",
    type: "badminton",
    location_id: w.locations[0].id,
  });
  const remote = new FakeSarvam(),
    api = new SarvamService(db, workspace);
  remote.config.app_id = `agent-${uid}`;
  remote.deployment.app_id = `agent-${uid}`;
  api.http = remote.fetch;
  const input = {
    version: 0,
    business_ids: [business.id],
    sarvam_org_id: "org-1",
    workspace_id: "ws-1",
    app_id: `agent-${uid}`,
    api_key: "private-api-key",
  };
  return { owner, business, remote, api, input };
}
async function drive(
  f: Awaited<ReturnType<typeof fixture>>,
  stop = "configured",
) {
  for (let n = 0; n < 30; n++) {
    const s = await f.api.settings(f.owner);
    if (s.setup_status === stop) return s;
    await f.api.setupStep(f.owner);
  }
  assert.fail("Setup did not terminate");
}
async function authorize(f: Awaited<ReturnType<typeof fixture>>) {
  const s = await drive(f, "authorization_required");
  const state = new URL(s.authorization_url).searchParams.get("state");
  await f.api.oauthCallback({ state, code: "test-auth-code", iss: MCP });
  return state;
}
async function configured() {
  const f = await fixture();
  await f.api.connect(f.owner, f.input);
  await authorize(f);
  await drive(f);
  return f;
}
async function publish(f: Awaited<ReturnType<typeof fixture>>) {
  const s = await f.api.settings(f.owner);
  await f.api.publish(f.owner, {
    version: s.version,
    deployment_id: "deployment-1",
  });
  await drive(f);
}

test("first Connect accepts version zero, completes setup without publishing or exposing keys", async () => {
  const f = await configured(),
    settings = await f.api.settings(f.owner);
  assert.equal(settings.connected, true);
  assert.equal(settings.enabled, false);
  assert.equal(settings.draft_version, 7);
  assert.equal(settings.published_version, null);
  assert.equal(f.remote.tools.length, 6);
  assert.equal(f.remote.deployment.app_version, 6);
  assert.ok(!f.remote.writes.includes("commit"));
  assert.ok(!f.remote.writes.includes("deploy"));
  for (const key of [
    "private-api-key",
    "private-oauth-access",
    "private-oauth-refresh",
    "bkv_",
  ])
    assert.ok(!JSON.stringify(settings).includes(key));
  const booking = f.remote.tools.find((t) => t.name === "bookingos_book_slot")!;
  assert.equal(booking.connector_config.auth.name, "X-API-Key");
  assert.deepEqual(
    booking.connector_config.body.find((b: Json) => b.name === "caller_phone")
      .value,
    { variable_name: "user_identifier" },
  );
  await assert.rejects(f.api.rotateToolKey(f.owner), /internally/);
});

test("invalid credentials and insufficient capabilities fail before any remote mutation", async () => {
  const f = await fixture();
  f.remote.denyAnalytics = true;
  await f.api.connect(f.owner, f.input);
  await assert.rejects(f.api.setupStep(f.owner), /verify/);
  assert.deepEqual(f.remote.writes, []);
  const g = await fixture();
  await g.api.connect(g.owner, g.input);
  await authorize(g);
  g.remote.missingCapability = "configure_secret";
  await assert.rejects(g.api.setupStep(g.owner), /configure_secret/);
  assert.deepEqual(g.remote.writes, []);
});

test("OAuth state is single-use and mismatched workspace cannot be configured", async () => {
  const f = await fixture();
  await f.api.connect(f.owner, f.input);
  const state = await authorize(f);
  await assert.rejects(
    f.api.oauthCallback({ state, code: "again" }),
    /expired/,
  );
  f.remote.scope = "another-org";
  await f.api.setupStep(f.owner);
  await assert.rejects(f.api.setupStep(f.owner), /same Sarvam/);
  assert.deepEqual(f.remote.writes, []);
});

test("lost secret and tool responses resume without duplicate resources or raw errors", async () => {
  const f = await fixture();
  await f.api.connect(f.owner, f.input);
  await authorize(f);
  f.remote.failAfterSecret = true;
  await assert.rejects(drive(f), /503/);
  assert.equal(f.remote.secrets.length, 1);
  assert.ok(
    !JSON.stringify(await f.api.settings(f.owner)).includes(
      "private-secret-must-not-leak",
    ),
  );
  f.remote.failAfterTool = true;
  await assert.rejects(drive(f), /503/);
  await drive(f);
  assert.equal(f.remote.secrets.length, 1);
  assert.equal(f.remote.tools.length, 6);
  assert.equal(new Set(f.remote.tools.map((t) => t.name)).size, 6);
});

test("Publish is explicit, updates the chosen deployment, and switch revocation is immediate", async () => {
  const f = await configured();
  await assert.rejects(
    f.api.bookingEnabled(f.owner, {
      version: (await f.api.settings(f.owner)).version,
      enabled: true,
    }),
    /publish/,
  );
  await publish(f);
  const settings = await f.api.settings(f.owner);
  assert.equal(settings.published_version, 7);
  assert.equal(f.remote.deployment.app_version, 7);
  await f.api.bookingEnabled(f.owner, {
    version: settings.version,
    enabled: true,
  });
  const row = (
    await db.query<Json>(
      "SELECT * FROM sarvam_integrations WHERE app_id=$1 AND membership_id IN (SELECT id FROM memberships WHERE user_id=$2)",
      [
        f.input.app_id,
        `sarvam:${(await workspace.member(f.owner, true)).organization_id}`,
      ],
    )
  ).rows[0];
  const key = openSecret(row.tool_key_ciphertext);
  await f.api.authenticateToolKey(key);
  // Disabling is safe even if a concurrent progress update made this version stale.
  await f.api.bookingEnabled(f.owner, { version: 0, enabled: false });
  await assert.rejects(f.api.authenticateToolKey(key), /turned off/);
  await f.api.disconnect(f.owner);
  await assert.rejects(f.api.authenticateToolKey(key), /tool key/);
  assert.equal((await f.api.settings(f.owner)).has_credentials, false);
  await drive(f, "disconnected");
  assert.equal(
    f.remote.tools.every((t) => !t.enabled),
    true,
  );
});

test("Disconnect invalidates pending OAuth and owners cannot edit another tenant", async () => {
  const f = await fixture();
  await f.api.connect(f.owner, f.input);
  const s = await drive(f, "authorization_required");
  const state = new URL(s.authorization_url).searchParams.get("state");
  await f.api.disconnect(f.owner);
  await assert.rejects(f.api.oauthCallback({ state, code: "late" }), /expired/);
  await assert.rejects(
    f.api.connect(
      { uid: randomUUID(), email: "staff@test.test", name: "Staff" },
      f.input,
    ),
  );
  assert.equal((await f.api.settings(f.owner)).setup_status, "disconnected");
});

test("repeated Connect uses optimistic concurrency and reconnect reuses its secret and tools", async () => {
  const f = await configured(),
    settings = await f.api.settings(f.owner);
  await assert.rejects(f.api.connect(f.owner, f.input), /Settings changed/);
  const input = { ...f.input, version: settings.version };
  await f.api.connect(f.owner, input);
  await authorize(f);
  await drive(f);
  assert.equal(f.remote.tools.length, 6);
  assert.equal(f.remote.secrets.length, 1);
  assert.equal(
    f.remote.config.llm_config.agent_config.states.start.instructions,
    BOOKING_PROMPT,
  );
  assert.equal(TOOLS.length, 6);
});

test("a completed Disconnect can reconnect using the same managed resources", async () => {
  const f = await configured();
  await publish(f);
  await f.api.disconnect(f.owner);
  await drive(f, "disconnected");
  const s = await f.api.settings(f.owner);
  await f.api.connect(f.owner, { ...f.input, version: s.version });
  await authorize(f);
  await drive(f);
  assert.equal(f.remote.tools.length, 6);
  assert.equal(f.remote.secrets.length, 1);
  assert.ok(f.remote.tools.every((t) => t.enabled));
  assert.equal((await f.api.settings(f.owner)).enabled, false);
});

test("an invalid reconnect preserves the working analytics credential", async () => {
  const f = await configured();
  const org = (await workspace.member(f.owner, true)).organization_id;
  const original = (
    await db.query<Json>(
      "SELECT api_key_ciphertext FROM sarvam_integrations WHERE organization_id=$1",
      [org],
    )
  ).rows[0].api_key_ciphertext;
  const s = await f.api.settings(f.owner);
  await f.api.connect(f.owner, {
    ...f.input,
    version: s.version,
    api_key: "invalid-new-api-key",
  });
  f.remote.denyAnalytics = true;
  await assert.rejects(f.api.setupStep(f.owner), /verify/);
  const stored = (
    await db.query<Json>(
      "SELECT api_key_ciphertext FROM sarvam_integrations WHERE organization_id=$1",
      [org],
    )
  ).rows[0].api_key_ciphertext;
  assert.equal(stored, original);
  assert.ok(
    !(await f.api.settings(f.owner)).setup_error.includes(
      "invalid-new-api-key",
    ),
  );
});
