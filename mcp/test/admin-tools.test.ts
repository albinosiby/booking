import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { ADMIN_INSTRUCTIONS, registerAdminTools } from "../src/admin/tools.js";
import { AdminMcpError } from "../src/admin/client.js";
import type { AdminWorkflow } from "../src/admin/workflow.js";
import { SarvamTokenStore, SARVAM_MCP_URL } from "../src/admin/sarvam-auth.js";

const ORG = "11111111-1111-4111-8111-111111111111";
const OPERATION = "22222222-2222-4222-8222-222222222222";
const TOOL_KEY = "bkv_fixture_protocol_private_key";
const WORKSPACE_KEY = "fixture_workspace_api_secret";
const OAUTH_TOKEN = "fixture_oauth_private_token";
const ADMIN_TOKEN = "fixture_admin_private_token";
type Call = { name: string; args: unknown[] };

async function connect(
  options: {
    request?: (...args: any[]) => Promise<unknown>;
    workflow?: Record<string, (...args: any[]) => Promise<unknown>>;
    authorized?: boolean;
  } = {},
) {
  const directory = await mkdtemp(join(tmpdir(), "bookingos-admin-protocol-"));
  const tokenFile = join(directory, "sarvam-oauth.json");
  const previousTokenFile = process.env.BOOKINGOS_SARVAM_TOKEN_FILE;
  process.env.BOOKINGOS_SARVAM_TOKEN_FILE = tokenFile;
  if (options.authorized)
    await new SarvamTokenStore(tokenFile).save({
      version: 1,
      server: SARVAM_MCP_URL,
      tokens: {
        access_token: OAUTH_TOKEN,
        token_type: "Bearer",
        expires_in: 3600,
        issuer: SARVAM_MCP_URL,
      },
      expiresAt: Date.now() + 3600_000,
    });
  const calls: Call[] = [];
  const request =
    options.request ??
    (async () => ({ job: { job_id: "job-fixture", step: "credential" } }));
  const workflow: Record<string, unknown> = {
    api: {
      config: {
        token: ADMIN_TOKEN,
        workspaceApiKey: WORKSPACE_KEY,
        templateAgentId: "template-fixture",
        templateVersion: 1,
        templateLanguage: "en-IN",
        templateLanguagePath: "language",
        templateLanguageValue: "en-IN",
      },
      request: async (...args: any[]) => {
        calls.push({ name: "api.request", args });
        return request(...args);
      },
    },
  };
  for (const name of ["preflight", "prepare", "start", "resume"])
    workflow[name] = async (...args: unknown[]) => {
      calls.push({ name, args });
      return (
        options.workflow?.[name]?.(...args) ?? {
          job_id: "job-fixture",
          step: "tool_0",
        }
      );
    };
  const server = new McpServer(
    { name: "bookingos-admin", version: "test" },
    { instructions: ADMIN_INSTRUCTIONS },
  );
  registerAdminTools(server, workflow as unknown as AdminWorkflow);
  const [a, b] = InMemoryTransport.createLinkedPair();
  const client = new Client({ name: "test-admin-client", version: "test" });
  await Promise.all([server.connect(a), client.connect(b)]);
  return {
    client,
    calls,
    async close() {
      await client.close();
      await server.close();
      if (previousTokenFile === undefined)
        delete process.env.BOOKINGOS_SARVAM_TOKEN_FILE;
      else process.env.BOOKINGOS_SARVAM_TOKEN_FILE = previousTokenFile;
      await rm(directory, { recursive: true, force: true });
    },
  };
}

function payload(result: any) {
  return JSON.parse(result.content[0].text);
}
function assertNoSecrets(value: unknown) {
  const text = JSON.stringify(value);
  for (const secret of [TOOL_KEY, WORKSPACE_KEY, OAUTH_TOKEN, ADMIN_TOKEN])
    assert.equal(
      text.includes(secret),
      false,
      "Protocol output must not contain a private fixture credential",
    );
}

test("admin MCP discovers only its voice setup tools, separate from owner/staff booking tools", async () => {
  const f = await connect();
  try {
    const { tools } = await f.client.listTools();
    assert.deepEqual(
      tools.map((t) => t.name).sort(),
      [
        "get_setup_status",
        "list_connection_requests",
        "get_connection_request",
        "preflight_connection",
        "prepare_connection",
        "start_connection",
        "get_connection_job",
        "resume_connection",
        "install_tool_credential",
        "verify_connection",
        "activate_connection",
        "pause_connection",
      ].sort(),
    );
    for (const name of [
      "create_booking",
      "reschedule_booking",
      "cancel_booking",
      "request",
      "execute_sql",
      "get_tool_key",
      "rotate_tool_key",
    ])
      assert.equal(
        tools.some((t) => t.name === name),
        false,
      );
    assert.equal(f.client.getServerVersion()?.name, "bookingos-admin");
    assert.equal(f.client.getInstructions(), ADMIN_INSTRUCTIONS);
  } finally {
    await f.close();
  }
});

test("tool annotations accurately distinguish read-only planning from state changes", async () => {
  const f = await connect();
  try {
    const { tools } = await f.client.listTools();
    const reads = [
      "get_setup_status",
      "list_connection_requests",
      "get_connection_request",
      "preflight_connection",
      "prepare_connection",
      "get_connection_job",
    ];
    for (const tool of tools) {
      assert.equal(
        tool.annotations?.readOnlyHint,
        reads.includes(tool.name),
        tool.name,
      );
      assert.equal(tool.annotations?.destructiveHint, false, tool.name);
      assert.equal(tool.annotations?.openWorldHint, true, tool.name);
    }
  } finally {
    await f.close();
  }
});

test("workflow MCP resource preserves new-chat sequence and safety constraints", async () => {
  const f = await connect();
  try {
    const resources = await f.client.listResources();
    assert.equal(resources.resources.length, 1);
    assert.equal(
      resources.resources[0].uri,
      "bookingos-admin://voice/connection-workflow",
    );
    const resource = await f.client.readResource({
      uri: resources.resources[0].uri,
    });
    const text = String(resource.contents[0].text);
    for (const phrase of [
      "preflight_connection",
      "resume_connection until done",
      "PROVIDER_AUTH_REQUIRED",
      "OUTCOME_UNKNOWN",
      "client booking off",
      "separately authorized",
    ])
      assert.equal(text.includes(phrase), true, phrase);
    assertNoSecrets(resource);
  } finally {
    await f.close();
  }
});

test("get_setup_status returns booleans and safe expiry without reading out installed credentials", async () => {
  const f = await connect({ authorized: true });
  try {
    const result = await f.client.callTool({
      name: "get_setup_status",
      arguments: {},
    });
    assert.equal(result.isError, undefined);
    const data = payload(result);
    assert.equal(data.admin_token_configured, true);
    assert.equal(data.template_configured, true);
    assert.equal(data.sarvam_installer.authorized, true);
    assert.equal(data.sarvam_installer.login_required, false);
    assert.equal(typeof data.sarvam_installer.expires_at, "string");
    assertNoSecrets(result);
    assert.equal(f.calls.length, 0);
  } finally {
    await f.close();
  }
});

test("backend metadata and private installation responses are sanitized at the MCP boundary", async () => {
  const secretPayload = {
    job_id: "job-safe",
    secret_id: "reference-safe",
    tool_key: TOOL_KEY,
    api_key: WORKSPACE_KEY,
    authorization: `Bearer ${ADMIN_TOKEN}`,
    nested: [{ access_token: OAUTH_TOKEN, text: `Do not echo ${TOOL_KEY}` }],
  };
  const f = await connect({
    request: async () => secretPayload,
    workflow: { resume: async () => secretPayload },
  });
  try {
    for (const name of [
      "get_connection_request",
      "get_connection_job",
      "resume_connection",
    ]) {
      const result = await f.client.callTool({
        name,
        arguments: { organization_id: ORG },
      });
      assertNoSecrets(result);
      assert.equal(payload(result).secret_id, "reference-safe");
      assert.equal(payload(result).tool_key, undefined);
    }
  } finally {
    await f.close();
  }
});

test("private credential installation accepts only organization identity and never forwards a caller-supplied key", async () => {
  const f = await connect();
  try {
    const listed = (await f.client.listTools()).tools.find(
      (t) => t.name === "install_tool_credential",
    )!;
    assert.deepEqual(Object.keys(listed.inputSchema.properties ?? {}), [
      "organization_id",
    ]);
    const result = await f.client.callTool({
      name: "install_tool_credential",
      arguments: {
        organization_id: ORG,
        tool_key: TOOL_KEY,
        url: "https://example.org",
      },
    });
    assertNoSecrets(result);
    const resumed = f.calls.find((c) => c.name === "resume");
    if (resumed) assert.deepEqual(resumed.args, [ORG]);
    else assert.equal(result.isError, true);
    assert.equal(
      f.calls.some((c) => JSON.stringify(c.args).includes(TOOL_KEY)),
      false,
    );
  } finally {
    await f.close();
  }
});

test("start_connection schema requires a reviewed plan and stable operation key", async () => {
  const f = await connect({
    workflow: { start: async () => ({ job_id: "job-safe", step: "agent" }) },
  });
  try {
    const tool = (await f.client.listTools()).tools.find(
      (t) => t.name === "start_connection",
    )!;
    assert.deepEqual(
      [...(tool.inputSchema.required ?? [])].sort(),
      ["organization_id", "plan_id", "plan", "idempotency_key"].sort(),
    );
    const rejected = await f.client.callTool({
      name: "start_connection",
      arguments: {
        organization_id: ORG,
        plan_id: "plan-safe",
        idempotency_key: OPERATION,
      },
    });
    assert.equal(rejected.isError, true);
    assert.equal(f.calls.length, 0);
    const plan = {
      organization_id: ORG,
      phone_number: "+918071582699",
      language: "en-IN",
    };
    const accepted = await f.client.callTool({
      name: "start_connection",
      arguments: {
        organization_id: ORG,
        plan_id: "plan-safe",
        plan,
        idempotency_key: OPERATION,
        workspace_api_key: WORKSPACE_KEY,
      },
    });
    assert.equal(accepted.isError, undefined);
    assert.deepEqual(f.calls.find((c) => c.name === "start")?.args, [
      ORG,
      { plan_id: "plan-safe", plan, idempotency_key: OPERATION },
    ]);
    assertNoSecrets(accepted);
  } finally {
    await f.close();
  }
});

test("resume_connection can continue saved steps until done instead of stopping at job creation", async () => {
  const states = ["credential", "tool_0", "verify", "activate", "done"];
  const f = await connect({
    workflow: {
      resume: async () => ({
        job_id: "job-safe",
        step: states.shift(),
        client_enabled: false,
      }),
    },
  });
  try {
    const seen: string[] = [];
    while (states.length) {
      const result = await f.client.callTool({
        name: "resume_connection",
        arguments: { organization_id: ORG },
      });
      assert.equal(result.isError, undefined);
      assert.equal(payload(result).client_enabled, false);
      seen.push(payload(result).step);
      assertNoSecrets(result);
    }
    assert.deepEqual(seen, [
      "credential",
      "tool_0",
      "verify",
      "activate",
      "done",
    ]);
    assert.equal(f.calls.filter((c) => c.name === "resume").length, 5);
  } finally {
    await f.close();
  }
});

test("step-specific tools refuse a different saved step without invoking the workflow", async () => {
  const f = await connect({
    request: async () => ({ job: { step: "agent" } }),
  });
  try {
    for (const name of [
      "install_tool_credential",
      "verify_connection",
      "activate_connection",
    ]) {
      const result = await f.client.callTool({
        name,
        arguments: { organization_id: ORG },
      });
      assert.equal(result.isError, true);
      assert.equal(payload(result).code, "REQUEST_REJECTED");
    }
    assert.equal(
      f.calls.some((c) => c.name === "resume"),
      false,
    );
  } finally {
    await f.close();
  }
});

test("unknown provider failures expose a safe error rather than raw private diagnostics", async () => {
  const f = await connect({
    workflow: {
      preflight: async () => {
        throw new Error(
          `${TOOL_KEY} ${WORKSPACE_KEY} ${OAUTH_TOKEN} ${ADMIN_TOKEN}`,
        );
      },
    },
  });
  try {
    const result = await f.client.callTool({
      name: "preflight_connection",
      arguments: { organization_id: ORG },
    });
    assert.equal(result.isError, true);
    assert.equal(payload(result).code, "SETUP_FAILED");
    assertNoSecrets(result);
  } finally {
    await f.close();
  }
});

test("provider auth and known safe domain failures retain actionable typed codes", async () => {
  let mode = "auth";
  const f = await connect({
    workflow: {
      resume: async () => {
        if (mode === "auth")
          throw Object.assign(new Error(`${OAUTH_TOKEN} ${TOOL_KEY}`), {
            code: "PROVIDER_AUTH_REQUIRED",
          });
        throw new AdminMcpError(
          "NUMBER_IN_USE",
          "The selected number is already assigned.",
        );
      },
    },
  });
  try {
    const auth = await f.client.callTool({
      name: "resume_connection",
      arguments: { organization_id: ORG },
    });
    assert.equal(payload(auth).code, "PROVIDER_AUTH_REQUIRED");
    assert.equal(auth.isError, true);
    assertNoSecrets(auth);
    mode = "conflict";
    const conflict = await f.client.callTool({
      name: "resume_connection",
      arguments: { organization_id: ORG },
    });
    assert.equal(payload(conflict).code, "NUMBER_IN_USE");
    assert.equal(conflict.isError, true);
    assertNoSecrets(conflict);
  } finally {
    await f.close();
  }
});
