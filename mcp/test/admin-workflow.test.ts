import { test } from "node:test";
import assert from "node:assert/strict";
import {
  AdminClient,
  AdminMcpError,
  safeOutput,
  type Json,
} from "../src/admin/client.js";
import { AdminWorkflow, type SessionFactory } from "../src/admin/workflow.js";
import type { SarvamProvider } from "../src/admin/provider.js";

const ORG = "00000000-0000-4000-8000-000000000001";
const API = "https://booking.example/api/v1/admin-mcp/voice";
const CATALOG = "https://booking.example/api/voice/v1/catalog";
const KEY = "bkv_fixture_client_secret";
const PLAN = {
  organization_id: ORG,
  language: "en-IN",
  sarvam_org_id: "sarvam-org",
  workspace_id: "sarvam-workspace",
  connection_id: "conn-fixture",
  phone_number: "+918071582699",
  template_agent_id: "template-fixture",
  template_version: 1,
  template_language: "en-IN",
  template_language_path: "language",
  template_language_value: "en-IN",
  initial_state: "start",
};
const json = (value: unknown, status = 200) =>
  new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json" },
  });
const clone = <T>(value: T): T => structuredClone(value);

function job(step = "credential"): Json {
  return {
    organization_id: ORG,
    job_id: "job-fixture",
    step,
    version: 2,
    plan: clone(PLAN),
    agent_name: "BookingOS fixture unique job",
    resources: step === "agent" ? {} : { agent_id: "agent-fixture" },
    receipt: {},
    spec: {
      tools: [
        {
          name: "bookingos_list_spaces",
          config: { lifecycle: "on_start", url: CATALOG },
        },
      ],
    },
  };
}

function setup(
  options: {
    step?: string;
    provider?: Json;
    state?: Json;
    api?: (
      path: string,
      method: string,
      body: Json | undefined,
    ) => Response | Promise<Response> | undefined;
    catalog?: typeof fetch;
  } = {},
) {
  const calls: { method: string; path: string; body?: Json }[] = [];
  const providerCalls: { name: string; args: unknown[] }[] = [];
  let state = options.state ?? job(options.step);
  let closed = 0;
  let claims = 0;
  const defaults: Json = {
    inspect: async () => ({ supported: true }),
    agent: async (id: string) => ({
      config: {
        org_id: PLAN.sarvam_org_id,
        workspace_id: PLAN.workspace_id,
        app_id: id,
        app_version: 1,
      },
    }),
    template: async () => ({ initial: "start" }),
    inventory: async () => ({
      numbers: [
        { connection_id: PLAN.connection_id, phone_number: PLAN.phone_number },
      ],
      deployments: [],
    }),
    assertScope: () => undefined,
    findAgent: async () => undefined,
    createAgent: async () => "agent-fixture",
    installSecret: async () => "secret-reference-only",
    addTool: async () => undefined,
    configurePrompt: async () => undefined,
    verifyTools: async () => ({ app_version: 2 }),
    commit: async () => 2,
    matchesDeployment: () => true,
    deploy: async () => ({
      deployment_id: "deployment-fixture",
      status: "active",
    }),
    domain: async () => ({
      deployment_id: "deployment-fixture",
      status: "active",
    }),
    ...options.provider,
  };
  const provider: Json = Object.fromEntries(
    Object.entries(defaults).map(([name, fn]) => [
      name,
      (...args: unknown[]) => {
        providerCalls.push({ name, args });
        return fn(...args);
      },
    ]),
  );
  const sessions: SessionFactory = async () => ({
    provider: provider as SarvamProvider,
    close: async () => {
      closed++;
    },
  });
  const api = new AdminClient(
    {
      apiUrl: API,
      token: "fixture-admin-token",
      workspaceApiKey: "fixture-workspace-key",
      templateAgentId: "template-fixture",
      templateVersion: 1,
      templateLanguage: "en-IN",
      templateLanguagePath: "language",
      templateLanguageValue: "en-IN",
    },
    async (input, init) => {
      const url = new URL(String(input));
      const path = url.pathname.replace("/api/v1/admin-mcp/voice", "");
      const method = init?.method ?? "GET";
      const body = init?.body ? JSON.parse(String(init.body)) : undefined;
      calls.push({ method, path, body });
      const handled = await options.api?.(path, method, body);
      if (handled) return handled;
      if (path === `/requests/${ORG}` && method === "GET")
        return json({
          organization_id: ORG,
          connection: {},
          request: { version: 1 },
        });
      if (path === `/jobs/${ORG}` && method === "GET")
        return json({ job: clone(state) });
      if (path.endsWith("/claim")) {
        state = {
          ...state,
          lease_id: `lease-${++claims}`,
          version: state.version + 1,
        };
        return json({ job: clone(state) });
      }
      if (path.endsWith("/credential"))
        return json({
          tool_key: KEY,
          secret_name: "bookingos_fixture_job_secret",
        });
      if (path.endsWith("/checkpoint")) {
        state = {
          ...state,
          resources: { ...state.resources, ...body.resources },
          receipt: { ...state.receipt, ...body.receipt },
          version: state.version + 1,
          step:
            state.step === "credential"
              ? "tool_0"
              : state.step === "agent"
                ? "credential"
                : state.step,
          lease_id: undefined,
        };
        return json({ job: clone(state) });
      }
      if (path.endsWith("/release")) {
        state = { ...state, lease_id: undefined };
        return json({ released: true });
      }
      if (path.endsWith("/start")) return json({ job: clone(state) });
      if (path.endsWith("/prepare")) return json({ plan: clone(PLAN) });
      if (path.endsWith("/verify"))
        return json({ job: { ...clone(state), step: "activate" } });
      if (path.endsWith("/activate"))
        return json({ job: { ...clone(state), step: "done" } });
      throw new Error("Unexpected fixture backend route");
    },
  );
  const catalog =
    options.catalog ??
    (async () =>
      json(
        { code: "FORBIDDEN", message: "The voice agent is turned off." },
        403,
      ));
  const workflow = new AdminWorkflow(api, sessions, catalog);
  return {
    workflow,
    api,
    calls,
    providerCalls,
    get state() {
      return state;
    },
    get closed() {
      return closed;
    },
  };
}

test("AdminClient rejects broad routes before transmitting its admin token", async () => {
  let requests = 0;
  const client = new AdminClient(
    { apiUrl: API, token: "fixture-admin-token" },
    async () => {
      requests++;
      return json({});
    },
  );
  for (const path of [
    "/users",
    "/requests/../users",
    "/requests?q=anything",
    "https://example.org",
    "/jobs/fixture#token",
  ])
    await assert.rejects(
      client.request("POST", path),
      (error: unknown) =>
        error instanceof AdminMcpError && error.code === "FORBIDDEN",
    );
  assert.equal(requests, 0);
});

test("AdminClient does not echo response bodies or retry uncertain writes", async () => {
  let requests = 0;
  const client = new AdminClient(
    { apiUrl: API, token: "fixture-admin-token" },
    async () => {
      requests++;
      return json(
        {
          message: `${KEY} Bearer fixture-admin-token`,
          api_key: "fixture-workspace-key",
        },
        503,
      );
    },
  );
  await assert.rejects(
    client.request("POST", `/jobs/${ORG}/checkpoint`, {
      secret_id: "safe-reference",
    }),
    (error: unknown) => {
      assert.equal(error instanceof AdminMcpError, true);
      assert.equal((error as AdminMcpError).code, "OUTCOME_UNKNOWN");
      assert.equal(String(error).includes(KEY), false);
      assert.equal(String(error).includes("fixture-admin-token"), false);
      assert.equal(String(error).includes("fixture-workspace-key"), false);
      return true;
    },
  );
  assert.equal(requests, 1);
});

test("AdminClient preserves an allowlisted conflict code while redacting its backend message", async () => {
  const client = new AdminClient(
    { apiUrl: API, token: "fixture-admin-token" },
    async () =>
      json(
        {
          code: "NUMBER_IN_USE",
          message: `${KEY} fixture-workspace-key Bearer fixture-admin-token`,
          private_diagnostic: "fixture-private-provider-response",
        },
        409,
      ),
  );
  await assert.rejects(
    client.request("POST", `/requests/${ORG}/start`, { plan: clone(PLAN) }),
    (error: unknown) => {
      assert.equal(error instanceof AdminMcpError, true);
      assert.equal((error as AdminMcpError).code, "NUMBER_IN_USE");
      assert.equal((error as AdminMcpError).status, 409);
      for (const secret of [
        KEY,
        "fixture-workspace-key",
        "fixture-admin-token",
        "fixture-private-provider-response",
      ])
        assert.equal(String(error).includes(secret), false);
      return true;
    },
  );
});

for (const operation of [
  { step: "tool_0", endpoint: "checkpoint" },
  { step: "verify", endpoint: "verify" },
  { step: "activate", endpoint: "activate" },
]) {
  test(`an asynchronous ${operation.endpoint} rejection releases the claimed lease`, async () => {
    const state = job(operation.step);
    state.resources = {
      agent_id: "agent-fixture",
      secret_id: "secret-reference-only",
      agent_version: 2,
      deployment_id: "deployment-fixture",
    };
    state.receipt = { credential_verified: true };
    const f = setup({
      state,
      api: async (path) => {
        if (path.endsWith(`/${operation.endpoint}`)) {
          await Promise.resolve();
          return json({ code: "VERIFICATION_FAILED", message: KEY }, 409);
        }
      },
    });
    await assert.rejects(
      f.workflow.resume(ORG),
      (error: unknown) =>
        error instanceof AdminMcpError && error.code === "VERIFICATION_FAILED",
    );
    assert.equal(f.calls.filter((c) => c.path.endsWith("/claim")).length, 1);
    const releases = f.calls.filter((c) => c.path.endsWith("/release"));
    assert.equal(releases.length, 1);
    assert.equal(releases[0].body?.error_code, "VERIFICATION_FAILED");
    assert.equal(f.state.lease_id, undefined);
    assert.equal(f.state.step, operation.step);
    assert.equal(f.closed, 1);
    assert.equal(JSON.stringify(releases).includes(KEY), false);
  });
}

test("safeOutput recursively removes credentials while retaining provider references", () => {
  const output = safeOutput({
    job_id: "safe",
    secret_id: "secret-reference-only",
    tool_key: KEY,
    workspace_api_key: "fixture-workspace-key",
    nested: [
      {
        access_token: "token-fixture",
        password: "password-fixture",
        message: `${KEY} Bearer fixture-admin-token`,
      },
    ],
  });
  const text = JSON.stringify(output);
  for (const secret of [
    KEY,
    "fixture-workspace-key",
    "token-fixture",
    "password-fixture",
    "fixture-admin-token",
  ])
    assert.equal(text.includes(secret), false);
  assert.equal(text.includes("secret-reference-only"), true);
});

test("unsupported provider capability preflight performs no backend writes or allocations", async () => {
  const f = setup({
    provider: {
      inspect: async () => {
        throw new AdminMcpError(
          "PROVIDER_CAPABILITY_MISSING",
          "Missing secure secret installer.",
        );
      },
    },
  });
  await assert.rejects(
    f.workflow.start(ORG, { plan: clone(PLAN), operation_key: "same-key" }),
    (error: unknown) =>
      error instanceof AdminMcpError &&
      error.code === "PROVIDER_CAPABILITY_MISSING",
  );
  assert.deepEqual(
    f.calls.map((c) => c.method),
    ["GET"],
  );
  assert.equal(
    f.providerCalls.some((c) =>
      ["createAgent", "installSecret", "deploy"].includes(c.name),
    ),
    false,
  );
  assert.equal(f.closed, 1);
});

test("credential install sends the key only to the private installer and exact catalog, never checkpoints/results", async () => {
  const catalogCalls: { url: string; key: string | null }[] = [];
  const f = setup({
    catalog: async (input, init) => {
      catalogCalls.push({
        url: String(input),
        key: new Headers(init?.headers).get("X-API-Key"),
      });
      assert.equal(init?.redirect, "error");
      assert.equal(init?.body, "{}");
      return json(
        { code: "FORBIDDEN", message: "The voice agent is turned off." },
        403,
      );
    },
  });
  const result = await f.workflow.resume(ORG);
  assert.deepEqual(catalogCalls, [{ url: CATALOG, key: KEY }]);
  assert.deepEqual(
    f.providerCalls.find((c) => c.name === "installSecret")?.args,
    ["bookingos_fixture_job_secret", KEY, true],
  );
  const checkpoint = f.calls.find((c) => c.path.endsWith("/checkpoint"));
  assert.equal(checkpoint?.body?.resources.secret_id, "secret-reference-only");
  assert.equal(checkpoint?.body?.receipt.credential_verified, true);
  assert.equal(JSON.stringify(checkpoint).includes(KEY), false);
  assert.equal(JSON.stringify(safeOutput(result)).includes(KEY), false);
  assert.equal(f.closed, 1);
});

test("credential test refuses an external destination before forwarding the client key", async () => {
  const state = job();
  state.spec.tools[0].config.url = "https://example.org/voice/v1/catalog";
  let forwarded = 0;
  const f = setup({
    state,
    catalog: async () => {
      forwarded++;
      return json({});
    },
  });
  await assert.rejects(
    f.workflow.resume(ORG),
    (error: unknown) =>
      error instanceof AdminMcpError && error.code === "VERIFICATION_FAILED",
  );
  assert.equal(forwarded, 0);
  assert.equal(f.calls.filter((c) => c.path.endsWith("/release")).length, 1);
  assert.equal(
    f.calls.some((c) => c.path.endsWith("/checkpoint")),
    false,
  );
  assert.equal(f.closed, 1);
});

test("credential test refuses an arbitrary same-origin path before forwarding the client key", async () => {
  const state = job();
  state.spec.tools[0].config.url =
    "https://booking.example/evil/voice/v1/catalog";
  let forwarded = 0;
  const f = setup({
    state,
    catalog: async () => {
      forwarded++;
      return json(
        { code: "FORBIDDEN", message: "The voice agent is turned off." },
        403,
      );
    },
  });
  await assert.rejects(
    f.workflow.resume(ORG),
    (error: unknown) =>
      error instanceof AdminMcpError && error.code === "VERIFICATION_FAILED",
  );
  assert.equal(forwarded, 0);
  assert.equal(f.calls.filter((c) => c.path.endsWith("/release")).length, 1);
});

test("a template failure after claiming a lease releases the job and closes the session", async () => {
  const f = setup({
    provider: {
      template: async () => {
        throw new AdminMcpError("TEMPLATE_REQUIRED", "Template changed.");
      },
    },
  });
  await assert.rejects(
    f.workflow.resume(ORG),
    (error: unknown) =>
      error instanceof AdminMcpError && error.code === "TEMPLATE_REQUIRED",
  );
  assert.equal(f.calls.filter((c) => c.path.endsWith("/claim")).length, 1);
  assert.equal(f.calls.filter((c) => c.path.endsWith("/release")).length, 1);
  assert.equal(f.state.lease_id, undefined);
  assert.equal(f.closed, 1);
});

test("a failed private install releases the lease without checkpointing success or leaking its inputs", async () => {
  const f = setup({
    provider: {
      installSecret: async () => {
        throw new AdminMcpError(
          "OUTCOME_UNKNOWN",
          "Provider did not confirm the secret reference.",
        );
      },
    },
  });
  await assert.rejects(
    f.workflow.resume(ORG),
    (error: unknown) =>
      error instanceof AdminMcpError && error.code === "OUTCOME_UNKNOWN",
  );
  const release = f.calls.find((c) => c.path.endsWith("/release"));
  assert.equal(release?.body?.error_code, "OUTCOME_UNKNOWN");
  assert.equal(JSON.stringify(release).includes(KEY), false);
  assert.equal(
    f.calls.some((c) => c.path.endsWith("/checkpoint")),
    false,
  );
  assert.equal(f.closed, 1);
});

test("an uncertain agent creation is recovered by saved job name without a duplicate create", async () => {
  let created: string | undefined;
  const f = setup({
    step: "agent",
    provider: {
      findAgent: async () => created,
      createAgent: async () => {
        created = "agent-recovered";
        throw new AdminMcpError("OUTCOME_UNKNOWN", "Provider reply was lost.");
      },
    },
  });
  await assert.rejects(
    f.workflow.resume(ORG),
    (error: unknown) =>
      error instanceof AdminMcpError && error.code === "OUTCOME_UNKNOWN",
  );
  assert.equal(f.state.step, "agent");
  const result = await f.workflow.resume(ORG);
  assert.equal(
    f.providerCalls.filter((c) => c.name === "createAgent").length,
    1,
  );
  assert.equal(f.providerCalls.filter((c) => c.name === "findAgent").length, 2);
  assert.equal(f.state.resources.agent_id, "agent-recovered");
  assert.equal(JSON.stringify(result).includes("agent-recovered"), true);
  assert.equal(f.closed, 2);
});

test("start rechecks a newly occupied phone before writing backend setup state", async () => {
  const f = setup({
    provider: {
      inventory: async () => ({
        numbers: [
          {
            connection_id: PLAN.connection_id,
            phone_number: PLAN.phone_number,
          },
        ],
        deployments: [
          {
            connection_configs: [
              {
                connection_id: PLAN.connection_id,
                phone_numbers: [PLAN.phone_number],
              },
            ],
          },
        ],
      }),
    },
  });
  await assert.rejects(
    f.workflow.start(ORG, { plan: clone(PLAN), operation_key: "same-key" }),
    (error: unknown) =>
      error instanceof AdminMcpError && error.code === "NUMBER_IN_USE",
  );
  assert.equal(
    f.calls.some((c) => c.method !== "GET"),
    false,
  );
});

test("final verification uses the persisted credential receipt without requesting or returning a raw key", async () => {
  const state = job("verify");
  state.receipt = { credential_verified: true };
  state.resources = {
    agent_id: "agent-fixture",
    secret_id: "secret-reference-only",
    agent_version: 2,
    deployment_id: "deployment-fixture",
  };
  const f = setup({ state });
  await f.workflow.resume(ORG);
  const verify = f.calls.find((c) => c.path.endsWith("/verify"));
  assert.equal(verify?.body?.credential_verified, true);
  assert.equal(verify?.body?.committed_version, 2);
  assert.equal(
    f.calls.some((c) => c.path.endsWith("/credential")),
    false,
  );
  assert.equal(JSON.stringify(verify).includes(KEY), false);
});

test("a completed job returns without a new provider session or setup write", async () => {
  const f = setup({ step: "done" });
  const result = await f.workflow.resume(ORG);
  assert.equal(result.step, "done");
  assert.equal(f.providerCalls.length, 0);
  assert.equal(f.closed, 0);
  assert.deepEqual(
    f.calls.map((c) => c.method),
    ["GET"],
  );
});
