import { test } from "node:test";
import assert from "node:assert/strict";
import { managedBookingSpecification } from "../../backend/src/sarvam/sarvam-provisioning-remote.ts";
import { AdminClient, AdminMcpError, type Json } from "../src/admin/client.js";
import {
  SarvamProvider,
  type ProviderTransport,
} from "../src/admin/provider.js";
import { AdminWorkflow } from "../src/admin/workflow.js";

const ORG = "11111111-1111-4111-8111-111111111111";
const PHONE = "+918071582699";
const SCOPE = ["provider-org", "provider-workspace"];
const KEY = "bkv_private_credential_for_fixture";
const SECRET_PLACEHOLDER = "${BOOKINGOS_SECRET_ID}";
const API_ROOT = "https://api.example.test/functions/v1/booking-api";
const LANGUAGE_RULE = { path: "language", value: "English" };

function merge(target: Json, patch: Json) {
  for (const [key, value] of Object.entries(patch)) {
    if (value && typeof value === "object" && !Array.isArray(value))
      merge((target[key] ??= {}), value);
    else target[key] = structuredClone(value);
  }
}

function fixture() {
  const schema = (fields: string[], operations?: string[]) => ({
    type: "object",
    properties: Object.fromEntries(
      fields.map((field) => [
        field,
        field === "operation" ? { type: "string", enum: operations } : {},
      ]),
    ),
    required: [],
  });
  const capabilities: Json[] = [
    {
      name: "agents",
      inputSchema: schema(
        ["operation", "id", "params", "fetch_all"],
        ["list", "get", "commit", "set_tools"],
      ),
    },
    {
      name: "telephony",
      inputSchema: schema(
        ["operation", "id", "params", "fetch_all"],
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
      inputSchema: schema(["operation", "fetch_all"], ["list"]),
    },
    {
      name: "configure_agent",
      inputSchema: schema(
        [
          "agent_id",
          "name",
          "clone_from",
          "clone_version",
          "config",
          "prompt",
          "operation",
        ],
        ["create", "update"],
      ),
    },
    {
      name: "configure_secret",
      inputSchema: schema(
        ["name", "value", "operation", "secret_id"],
        ["create", "update"],
      ),
    },
    {
      name: "create_http_tool",
      inputSchema: schema([
        "agent_id",
        "name",
        "description",
        "tool_type",
        "connector_config",
      ]),
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
        ["create"],
      ),
    },
  ];
  const agents = new Map<string, Json>([
    [
      "template",
      {
        app_name: "Reviewed empty English template",
        config: {
          org_id: SCOPE[0],
          workspace_id: SCOPE[1],
          app_id: "template",
          app_version: 1,
          status: "committed",
          language: "English",
          llm_config: {
            agent_config: {
              initial_state_name: "main",
              states: { main: { instructions: "Template", tool_names: [] } },
              agent_variables: {},
            },
          },
        },
        tools: [],
      },
    ],
  ]);
  const versions = new Map<string, Json>();
  const secrets = new Map<string, { id: string; value: string }>();
  const deployments: Json[] = [];
  const calls: { name: string; args: Json }[] = [];
  const lost = new Set<string>();
  let wrongVersion = false;
  const transport = {
    async listTools() {
      return { tools: structuredClone(capabilities) };
    },
    async callTool(request: { name: string; arguments: Json }) {
      const { name, arguments: a } = request;
      calls.push({ name, args: structuredClone(a) });
      let value: Json = {};
      let operation = name;
      if (name === "agents") {
        operation += `:${a.operation}`;
        if (a.operation === "list")
          value = {
            items: [...agents].map(([app_id, agent]) => ({
              app_id,
              app_name: agent.app_name,
            })),
          };
        else if (a.operation === "get") {
          value = structuredClone(
            versions.get(`${a.id}:${a.params?.app_version}`) ??
              agents.get(a.id)!,
          );
          if (wrongVersion) value.config.app_version += 1;
        } else if (a.operation === "set_tools") {
          for (const tool of agents.get(a.id)!.tools)
            tool.enabled = a.params.enable.includes(tool.name);
        } else if (a.operation === "commit") {
          const source = agents.get(a.id)!;
          assert.equal(source.config.app_version, a.params.source_app_version);
          source.config.status = "committed";
          versions.set(
            `${a.id}:${source.config.app_version}`,
            structuredClone(source),
          );
          source.config.status = "draft";
          source.config.app_version += 1;
        }
      } else if (name === "telephony") {
        if (a.operation === "list_connections")
          value = {
            items: [{ connection_id: "connection", name: "Main line" }],
          };
        else if (a.operation === "list_endpoints")
          value = { items: [{ phone_number: PHONE, status: "active" }] };
        else if (a.operation === "list_deployments")
          value = { items: deployments };
        else if (a.operation === "get_deployment")
          value = deployments.find(
            (deployment) => deployment.deployment_id === a.id,
          )!;
      } else if (name === "secrets") {
        value = {
          items: [...secrets].map(([name, secret]) => ({
            name,
            id: secret.id,
          })),
        };
      } else if (name === "configure_agent") {
        if (a.clone_from) {
          operation += ":create";
          const id = `agent-${agents.size}`;
          const agent = structuredClone(agents.get(a.clone_from)!);
          agent.app_name = a.name;
          Object.assign(agent.config, {
            app_id: id,
            app_version: 1,
            status: "draft",
          });
          agents.set(id, agent);
          value = { id };
        } else {
          operation += ":update";
          const agent = agents.get(a.agent_id)!;
          merge(agent.config, a.config ?? {});
          if (a.prompt)
            agent.config.llm_config.agent_config.states.main.instructions =
              a.prompt;
        }
      } else if (name === "configure_secret") {
        const existing = secrets.get(a.name);
        if (existing) {
          assert.equal(a.operation, "update");
          assert.equal(a.secret_id, existing.id);
          existing.value = a.value;
          value = { id: existing.id };
        } else {
          const secret = { id: `secret-${secrets.size + 1}`, value: a.value };
          secrets.set(a.name, secret);
          value = { id: secret.id };
        }
      } else if (name === "create_http_tool") {
        const agent = agents.get(a.agent_id)!;
        assert.ok(
          !agent.tools.some((tool: Json) => tool.name === a.name),
          "Must reconcile a saved tool before recreating it",
        );
        agent.tools.push({
          name: a.name,
          enabled: true,
          connector_config: a.connector_config,
        });
        value = { id: `tool-${agent.tools.length}` };
      } else if (name === "configure_deployment") {
        const deployment = {
          deployment_id: `deployment-${deployments.length + 1}`,
          app_id: a.app_id,
          app_version: a.app_version,
          channel_direction: a.channel_direction,
          connection_configs: a.connection_configs,
          status: "active",
        };
        deployments.push(deployment);
        value = { deployment_id: deployment.deployment_id };
      } else assert.fail(`Unexpected provider tool ${name}`);
      if (lost.delete(operation))
        throw new Error(
          `Lost reply; untrusted private provider details ${KEY}`,
        );
      return { structuredContent: structuredClone(value) };
    },
  } as unknown as ProviderTransport;
  return {
    capabilities,
    agents,
    versions,
    secrets,
    deployments,
    calls,
    lost,
    transport,
    provider: new SarvamProvider(transport),
    wrongVersion() {
      wrongVersion = true;
    },
  };
}

function code(expected: string) {
  return (error: unknown) =>
    error instanceof AdminMcpError &&
    error.code === expected &&
    !error.message.includes(KEY);
}
const specification = () =>
  managedBookingSpecification(["booking", "rescheduling"], {
    baseUrl: `${API_ROOT}/voice/v1`,
    secretId: SECRET_PLACEHOLDER,
    language: "en-IN",
  });

test("provider's explicit credential-attachment restriction stops before any remote mutation", async () => {
  const f = fixture();
  f.capabilities.find((tool) => tool.name === "create_http_tool")!.description =
    "auth on a tool is refused; user then selects the credential in the console";
  delete f.capabilities.find((tool) => tool.name === "configure_agent")!
    .inputSchema.properties.prompt;
  await assert.rejects(
    f.provider.inspect(),
    code("PROVIDER_CREDENTIAL_ATTACHMENT_UNAVAILABLE"),
  );
  assert.equal(f.calls.length, 0);
});

test("provider capability gate refuses missing secret, pinned clone, authenticated tool or deployment support before writes", async () => {
  for (const missing of [
    "secret-tool",
    "secret-value",
    "clone-version",
    "http-auth",
    "deployment-version",
    "commit",
    "unknown-required-http-field",
  ]) {
    const f = fixture();
    const capability = (name: string) =>
      f.capabilities.find((tool) => tool.name === name)!;
    if (missing === "secret-tool")
      f.capabilities.splice(
        f.capabilities.findIndex((tool) => tool.name === "configure_secret"),
        1,
      );
    if (missing === "secret-value")
      delete capability("configure_secret").inputSchema.properties.value;
    if (missing === "clone-version")
      delete capability("configure_agent").inputSchema.properties.clone_version;
    if (missing === "http-auth")
      capability("create_http_tool").inputSchema.properties = {
        agent_id: {},
        name: {},
        url: {},
        body: {},
        lifecycle: {},
      };
    if (missing === "deployment-version")
      delete capability("configure_deployment").inputSchema.properties
        .app_version;
    if (missing === "commit")
      capability("agents").inputSchema.properties.operation.enum = [
        "list",
        "get",
      ];
    if (missing === "unknown-required-http-field")
      capability("create_http_tool").inputSchema.required = [
        "unsupported_required_field",
      ];
    await assert.rejects(
      f.provider.inspect(),
      code("PROVIDER_CAPABILITY_MISSING"),
      missing,
    );
    assert.equal(f.calls.length, 0, missing);
    assert.equal(f.agents.size, 1);
    assert.equal(f.secrets.size, 0);
  }
});

test("template verification binds workspace, immutable version, empty scope and native language manifest", async () => {
  const f = fixture();
  await f.provider.inspect();
  assert.equal(
    (await f.provider.template("template", 1, SCOPE, LANGUAGE_RULE)).initial,
    "main",
  );
  await assert.rejects(
    f.provider.template(
      "template",
      1,
      ["different-org", SCOPE[1]],
      LANGUAGE_RULE,
    ),
    code("WORKSPACE_MISMATCH"),
  );
  await assert.rejects(
    f.provider.template("template", 1, SCOPE, {
      path: "language",
      value: "Hindi",
    }),
    code("TEMPLATE_LANGUAGE_MISMATCH"),
  );
  await assert.rejects(
    f.provider.template("template", 1, SCOPE, {
      path: "__proto__.language",
      value: "English",
    }),
    code("TEMPLATE_REQUIRED"),
  );
  f.agents
    .get("template")!
    .tools.push({ name: "foreign-tool", enabled: false });
  await assert.rejects(
    f.provider.template("template", 1, SCOPE, LANGUAGE_RULE),
    code("TEMPLATE_REQUIRED"),
  );
  f.agents.get("template")!.tools = [];
  f.wrongVersion();
  await assert.rejects(
    f.provider.agent("template", 1),
    code("VERIFICATION_FAILED"),
  );
});

test("uncertain agent creation reconciles the unique job name without a duplicate", async () => {
  const f = fixture();
  await f.provider.inspect();
  f.lost.add("configure_agent:create");
  await assert.rejects(
    f.provider.createAgent("BookingOS unique job", "template", 1),
    code("OUTCOME_UNKNOWN"),
  );
  const id = await f.provider.findAgent("BookingOS unique job");
  assert.equal(id, "agent-1");
  assert.equal(f.agents.size, 2);
  assert.equal(
    f.calls.filter((call) => call.name === "configure_agent").length,
    1,
  );
  f.agents.set("duplicate", { app_name: "BookingOS unique job" });
  await assert.rejects(
    f.provider.findAgent("BookingOS unique job"),
    code("VERIFICATION_FAILED"),
  );
});

test("uncertain secret creation safely rewrites the same job-owned reference when update is advertised", async () => {
  const f = fixture();
  await f.provider.inspect();
  f.lost.add("configure_secret");
  await assert.rejects(
    f.provider.installSecret("job-secret", KEY),
    code("OUTCOME_UNKNOWN"),
  );
  const secret = f.secrets.get("job-secret")!;
  secret.value = "stale-value";
  const id = await f.provider.installSecret("job-secret", KEY);
  assert.equal(id, secret.id);
  assert.equal(f.secrets.size, 1);
  assert.equal(secret.value, KEY);
  const update = f.calls
    .filter((call) => call.name === "configure_secret")
    .at(-1)!;
  assert.equal(update.args.operation, "update");
  assert.equal(update.args.secret_id, id);
});

test("an existing secret is never accepted on its name alone without supported private update", async () => {
  const f = fixture();
  const secret = f.capabilities.find(
    (tool) => tool.name === "configure_secret",
  )!;
  delete secret.inputSchema.properties.operation;
  delete secret.inputSchema.properties.secret_id;
  f.secrets.set("job-secret", { id: "secret-1", value: "other-client-key" });
  await f.provider.inspect();
  await assert.rejects(
    f.provider.installSecret("job-secret", KEY),
    code("CREDENTIAL_RECOVERY_REQUIRED"),
  );
  assert.equal(f.secrets.get("job-secret")!.value, "other-client-key");
  assert.ok(!f.calls.some((call) => call.name === "configure_secret"));
  assert.equal(f.deployments.length, 0);
});

test("provider configuration consumes the backend six-tool specification without changing variable or trusted-context shape", async () => {
  const f = fixture();
  const spec = specification();
  await f.provider.inspect();
  const app = await f.provider.createAgent("Client", "template", 1);
  for (const tool of spec.tools)
    await f.provider.addTool(app, tool, "secret-1");
  await f.provider.configurePrompt(app, "main", spec);
  const verified = await f.provider.verifyTools(
    app,
    SCOPE,
    "main",
    spec,
    "secret-1",
  );
  assert.equal(verified.app_version, 1);
  const agent = f.agents.get(app)!;
  agent.config.language = "Hindi";
  await assert.rejects(
    f.provider.verifyTools(
      app,
      SCOPE,
      "main",
      spec,
      "secret-1",
      undefined,
      LANGUAGE_RULE,
    ),
    code("TEMPLATE_LANGUAGE_MISMATCH"),
  );
  agent.config.language = "English";
  assert.equal(agent.tools.length, 6);
  assert.deepEqual(
    agent.config.llm_config.agent_config.agent_variables,
    spec.variables,
  );
  assert.deepEqual(
    agent.config.llm_config.agent_config.states.main.agent_variables_in_context,
    ["bookingos_spaces"],
  );
  for (const tool of agent.tools)
    assert.equal(tool.connector_config.auth.value.secret_id, "secret-1");
  assert.ok(!JSON.stringify(agent).includes(SECRET_PLACEHOLDER));
  assert.ok(
    !agent.tools.some((tool: Json) => tool.name === "bookingos_cancel_booking"),
  );
  const before = f.calls.filter(
    (call) => call.name === "create_http_tool",
  ).length;
  await f.provider.addTool(app, spec.tools[0], "secret-1");
  assert.equal(
    f.calls.filter((call) => call.name === "create_http_tool").length,
    before,
  );
  agent.tools[0].connector_config.auth.value.secret_id = "foreign-secret";
  await assert.rejects(
    f.provider.verifyTools(app, SCOPE, "main", spec, "secret-1"),
    code("VERIFICATION_FAILED"),
  );
  agent.tools[0].connector_config.auth.value.secret_id = "secret-1";
  agent.tools.push({ name: "bookingos_cancel_booking", enabled: false });
  await assert.rejects(
    f.provider.verifyTools(app, SCOPE, "main", spec, "secret-1"),
    code("VERIFICATION_FAILED"),
  );
});

test("provider rejection bodies never become operator errors containing private credentials", async () => {
  const f = fixture();
  const provider = new SarvamProvider({
    ...f.transport,
    async callTool() {
      return {
        isError: true,
        content: [{ type: "text", text: `Rejected secret ${KEY}` }],
      };
    },
  } as unknown as ProviderTransport);
  await provider.inspect();
  await assert.rejects(
    provider.createAgent("Client", "template", 1),
    code("PROVIDER_REJECTED"),
  );
});

test("uncertain commit and deployment replies reconcile the exact version without duplicate deployment or transfer", async () => {
  const f = fixture();
  await f.provider.inspect();
  const app = await f.provider.createAgent("Client", "template", 1);
  f.lost.add("agents:commit");
  await assert.rejects(f.provider.commit(app, 1), code("OUTCOME_UNKNOWN"));
  assert.equal(await f.provider.commit(app, 1), 1);
  assert.equal(
    f.calls.filter(
      (call) => call.name === "agents" && call.args.operation === "commit",
    ).length,
    1,
  );
  f.lost.add("configure_deployment");
  await assert.rejects(
    f.provider.deploy(app, 1, "connection", PHONE, "Client inbound"),
    code("OUTCOME_UNKNOWN"),
  );
  const recovered = await f.provider.deploy(
    app,
    1,
    "connection",
    PHONE,
    "Client inbound",
  );
  assert.equal(recovered.deployment_id, "deployment-1");
  assert.equal(f.deployments.length, 1);
  assert.equal(
    f.calls.filter((call) => call.name === "configure_deployment").length,
    1,
  );
  await assert.rejects(
    f.provider.deploy(
      "other-client",
      1,
      "connection",
      PHONE,
      "Must not transfer",
    ),
    code("NUMBER_IN_USE"),
  );
  assert.equal(f.deployments[0].app_id, app);
  assert.ok(
    !f.calls.some((call) =>
      /delete|pause|resume/.test(call.args.operation ?? ""),
    ),
  );
});

function workflowFixture() {
  const f = fixture();
  const spec = specification();
  const plan = {
    organization_id: ORG,
    sarvam_org_id: SCOPE[0],
    workspace_id: SCOPE[1],
    connection_id: "connection",
    phone_number: PHONE,
    language: "en-IN",
    template_agent_id: "template",
    template_version: 1,
    template_language: "en-IN",
    template_language_path: LANGUAGE_RULE.path,
    template_language_value: LANGUAGE_RULE.value,
    initial_state: "main",
  };
  const steps = [
    "agent",
    "credential",
    ...spec.tools.map((_, index) => `tool_${index}`),
    "configure",
    "commit",
    "deployment",
    "verify",
    "activate",
    "done",
  ];
  const job: Json = {
    job_id: "job-unique",
    organization_id: ORG,
    version: 1,
    step: steps[0],
    agent_name: "BookingOS job-unique",
    plan,
    spec,
    resources: {},
    receipt: {},
    client_enabled: false,
  };
  const apiCalls: { method: string; path: string; body?: Json }[] = [];
  let closed = 0;
  const api = {
    config: {
      apiUrl: `${API_ROOT}/v1/admin-mcp/voice`,
      token: "private-admin-token",
      templateAgentId: "template",
      templateVersion: 1,
      templateLanguage: "en-IN",
      templateLanguagePath: "language",
      templateLanguageValue: "English",
    },
    async request(method: string, path: string, body?: Json) {
      apiCalls.push({ method, path, body: body && structuredClone(body) });
      if (path === `/requests/${ORG}`)
        return {
          connection: {},
          request: { requested_services: ["booking", "rescheduling"] },
        };
      if (path === `/jobs/${ORG}`) return structuredClone(job);
      if (path.endsWith("/claim")) {
        job.lease_id = "lease";
        job.version += 1;
        return structuredClone(job);
      }
      if (path.endsWith("/credential"))
        return { tool_key: KEY, secret_name: "job-secret" };
      if (path.endsWith("/checkpoint")) {
        Object.assign(job.resources, body!.resources);
        Object.assign(job.receipt, body!.receipt);
        job.step = steps[steps.indexOf(job.step) + 1];
        job.version += 1;
        delete job.lease_id;
        return structuredClone(job);
      }
      if (path.endsWith("/verify")) {
        assert.equal(body!.tools_verified, true);
        assert.equal(body!.credential_verified, true);
        assert.equal(body!.language_verified, true);
        assert.equal(body!.committed_version, 1);
        job.step = "activate";
        delete job.lease_id;
        return structuredClone(job);
      }
      if (path.endsWith("/activate")) {
        job.step = "done";
        job.status = "active";
        delete job.lease_id;
        return structuredClone(job);
      }
      if (path.endsWith("/release")) {
        delete job.lease_id;
        return structuredClone(job);
      }
      if (path.endsWith("/prepare")) return { plan: body };
      if (path.endsWith("/start")) return structuredClone(job);
      assert.fail(`Unexpected BookingOS request ${method} ${path}`);
    },
  } as unknown as AdminClient;
  const catalogCalls: { url: string; init?: RequestInit }[] = [];
  const catalog: typeof fetch = async (input, init) => {
    catalogCalls.push({ url: String(input), init });
    assert.equal(new Headers(init?.headers).get("X-API-Key"), KEY);
    return Response.json(
      { code: "FORBIDDEN", message: "The voice agent is turned off." },
      { status: 403 },
    );
  };
  const workflow = new AdminWorkflow(
    api,
    async () => ({
      provider: new SarvamProvider(f.transport),
      async close() {
        closed += 1;
      },
    }),
    catalog,
  );
  return {
    ...f,
    api,
    apiCalls,
    job,
    plan,
    workflow,
    catalogCalls,
    closed: () => closed,
  };
}

test("one leased setup sequence keeps secrets private, freezes scope and leaves the client switch off", async () => {
  const f = workflowFixture();
  const outputs: unknown[] = [];
  for (let step = 0; step < 20 && f.job.step !== "done"; step++)
    outputs.push(await f.workflow.resume(ORG));
  assert.equal(f.job.step, "done");
  assert.equal(f.job.client_enabled, false);
  assert.equal(f.agents.size, 2);
  assert.equal(f.secrets.size, 1);
  assert.equal(f.deployments.length, 1);
  assert.equal(f.catalogCalls.length, 1);
  assert.equal(f.catalogCalls[0].url, `${API_ROOT}/voice/v1/catalog`);
  assert.equal(f.catalogCalls[0].init?.redirect, "error");
  assert.ok(!JSON.stringify(outputs).includes(KEY));
  assert.ok(
    !f.calls.some((call) =>
      /delete|pause|resume|place_test_call|verify_phone_number/.test(
        call.args.operation ?? call.name,
      ),
    ),
  );
  const sessions = f.closed();
  await f.workflow.resume(ORG);
  assert.equal(
    f.closed(),
    sessions,
    "A completed setup must not open another provider session",
  );
});

test("a conflicting number stops prepare and start without transferring it or reserving a new setup", async () => {
  const f = workflowFixture();
  f.deployments.push({
    deployment_id: "another-client",
    app_id: "rk-groups",
    app_version: 2,
    channel_direction: "inbound",
    status: "paused",
    connection_configs: [
      { connection_id: "connection", phone_numbers: [PHONE] },
    ],
  });
  const fields = { ...f.plan };
  await assert.rejects(f.workflow.prepare(ORG, fields), code("NUMBER_IN_USE"));
  await assert.rejects(
    f.workflow.start(ORG, { plan: f.plan }),
    code("NUMBER_IN_USE"),
  );
  assert.ok(!f.apiCalls.some((call) => /\/(prepare|start)$/.test(call.path)));
  assert.equal(f.deployments[0].app_id, "rk-groups");
  assert.ok(
    !f.calls.some(
      (call) =>
        call.name.startsWith("configure_") ||
        /delete|pause|resume/.test(call.args.operation ?? ""),
    ),
  );
});

test("workspace or language mismatches release a claimed job and never configure another client", async () => {
  for (const mismatch of ["workspace", "language"]) {
    const f = workflowFixture();
    if (mismatch === "workspace") f.job.plan.workspace_id = "other-workspace";
    else f.agents.get("template")!.config.language = "Hindi";
    await assert.rejects(
      f.workflow.resume(ORG),
      code(
        mismatch === "workspace"
          ? "WORKSPACE_MISMATCH"
          : "TEMPLATE_LANGUAGE_MISMATCH",
      ),
    );
    assert.ok(f.apiCalls.some((call) => call.path.endsWith("/release")));
    assert.equal(f.job.lease_id, undefined);
    assert.ok(!f.calls.some((call) => call.name.startsWith("configure_")));
    assert.equal(f.closed(), 1);
  }
});

test("a tampered credential-probe destination cannot forward the new tool key", async () => {
  const f = workflowFixture();
  await f.workflow.resume(ORG);
  f.job.spec.tools[0].config.url =
    "https://api.example.test/unrelated/voice/v1/catalog";
  await assert.rejects(f.workflow.resume(ORG), code("VERIFICATION_FAILED"));
  assert.equal(f.catalogCalls.length, 0);
  assert.equal(f.job.step, "credential");
  assert.equal(f.job.lease_id, undefined);
  assert.equal(f.deployments.length, 0);
});

test("an unknown remote outcome with no read-back never retries creation or commit", async () => {
  const f = fixture();
  await f.provider.inspect();
  const app = await f.provider.createAgent("Client", "template", 1);
  const spec = specification();
  const before = f.calls.length;
  await assert.rejects(
    f.provider.installSecret("not-visible-yet", KEY, false),
    code("OUTCOME_UNKNOWN"),
  );
  await assert.rejects(
    f.provider.addTool(app, spec.tools[0], "secret-1", false),
    code("OUTCOME_UNKNOWN"),
  );
  await assert.rejects(
    f.provider.commit(app, 1, false),
    code("OUTCOME_UNKNOWN"),
  );
  await assert.rejects(
    f.provider.deploy(app, 1, "connection", PHONE, "Not visible yet", false),
    code("OUTCOME_UNKNOWN"),
  );
  const retries = f.calls
    .slice(before)
    .filter(
      (call) =>
        call.name.startsWith("configure_") ||
        call.name === "create_http_tool" ||
        (call.name === "agents" && call.args.operation === "commit"),
    );
  assert.deepEqual(retries, []);
  assert.equal(f.secrets.size, 0);
  assert.equal(f.agents.get(app)!.tools.length, 0);
  assert.equal(f.agents.get(app)!.config.status, "draft");
  assert.equal(f.deployments.length, 0);
});

test("saved OUTCOME_UNKNOWN jobs wait for authoritative read-back instead of assuming immediate inventory consistency", async () => {
  for (const uncertainStep of [
    "agent",
    "credential",
    "tool_0",
    "commit",
    "deployment",
  ]) {
    const f = workflowFixture();
    for (let count = 0; count < 20 && f.job.step !== uncertainStep; count++)
      await f.workflow.resume(ORG);
    assert.equal(f.job.step, uncertainStep);
    f.job.error_code = "OUTCOME_UNKNOWN";
    const before = f.calls.length;
    const resourcesBefore = {
      agents: f.agents.size,
      secrets: f.secrets.size,
      deployments: f.deployments.length,
      tools: [...f.agents.values()].reduce(
        (total, agent) => total + (agent.tools?.length ?? 0),
        0,
      ),
    };
    await assert.rejects(
      f.workflow.resume(ORG),
      code("OUTCOME_UNKNOWN"),
      uncertainStep,
    );
    assert.equal(f.job.step, uncertainStep);
    assert.equal(f.job.lease_id, undefined);
    assert.deepEqual(
      f.calls
        .slice(before)
        .filter(
          (call) =>
            call.name.startsWith("configure_") ||
            call.name === "create_http_tool" ||
            (call.name === "agents" && call.args.operation === "commit"),
        ),
      [],
      uncertainStep,
    );
    assert.deepEqual(
      {
        agents: f.agents.size,
        secrets: f.secrets.size,
        deployments: f.deployments.length,
        tools: [...f.agents.values()].reduce(
          (total, agent) => total + (agent.tools?.length ?? 0),
          0,
        ),
      },
      resourcesBefore,
      uncertainStep,
    );
    assert.equal(f.apiCalls.at(-1)?.body?.error_code, "OUTCOME_UNKNOWN");
  }
});
