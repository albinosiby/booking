import type { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { AdminMcpError, type Json } from "./client.js";

type Tool = { name: string; inputSchema: Json };
export type ProviderTransport = Pick<Client, "listTools" | "callTool">;

export function contains(actual: any, expected: any): boolean {
  if (Array.isArray(expected))
    return (
      Array.isArray(actual) &&
      actual.length === expected.length &&
      expected.every((v, i) => contains(actual[i], v))
    );
  if (expected && typeof expected === "object")
    return (
      !!actual &&
      typeof actual === "object" &&
      Object.entries(expected).every(([k, v]) => contains(actual[k], v))
    );
  return actual === expected;
}

/** Typed operations only. No arbitrary URL, provider tool, or raw credential result is exposed. */
export class SarvamProvider {
  private tools: Tool[] = [];
  constructor(private client: ProviderTransport) {}
  private tool(name: string) {
    const tool = this.tools.find(
      (t) => t.name === name || t.name.endsWith(`__${name}`),
    );
    if (!tool)
      throw new AdminMcpError(
        "PROVIDER_CAPABILITY_MISSING",
        `Sarvam does not advertise ${name}. Setup stopped before allocating resources.`,
      );
    return tool;
  }
  private args(tool: Tool, fields: Json) {
    const schema = tool.inputSchema;
    if (!schema?.properties)
      throw new AdminMcpError(
        "PROVIDER_CAPABILITY_MISSING",
        "Sarvam did not advertise a supported input schema.",
      );
    const result: Json = {};
    for (const [key, value] of Object.entries(fields)) {
      const prop = schema.properties[key];
      if (!prop || value === undefined) continue;
      if (prop.enum && !prop.enum.includes(value))
        throw new AdminMcpError(
          "PROVIDER_CAPABILITY_MISSING",
          `Sarvam does not support the required ${key} operation.`,
        );
      result[key] = value;
    }
    for (const required of schema.required ?? [])
      if (!(required in result))
        throw new AdminMcpError(
          "PROVIDER_CAPABILITY_MISSING",
          "Sarvam requires an unsupported field; review the current workspace schema.",
        );
    return result;
  }
  private async invoke(name: string, fields: Json) {
    const tool = this.tool(name);
    let result: any;
    try {
      result = await this.client.callTool(
        { name: tool.name, arguments: this.args(tool, fields) },
        undefined,
        { timeout: 15000 },
      );
    } catch (e) {
      if (e instanceof AdminMcpError) throw e;
      if ((e as { code?: string })?.code === "PROVIDER_AUTH_REQUIRED")
        throw new AdminMcpError(
          "PROVIDER_AUTH_REQUIRED",
          "Renew the separate Sarvam installer authorization, then resume this job.",
        );
      throw new AdminMcpError(
        "OUTCOME_UNKNOWN",
        "Sarvam did not confirm this operation. Resume the same job to reconcile its saved name and references.",
      );
    }
    if (result.isError)
      throw new AdminMcpError(
        "PROVIDER_REJECTED",
        "Sarvam refused this operation. Inspect the current supported capabilities and job before retrying.",
      );
    let data: Json;
    try {
      data =
        result.structuredContent ??
        JSON.parse(
          result.content?.find((c: Json) => c.type === "text")?.text ?? "null",
        );
    } catch {
      throw new AdminMcpError(
        "OUTCOME_UNKNOWN",
        "Sarvam returned an unreadable operation result. Reconcile before retrying.",
      );
    }
    if (!data || data.validation?.length || data.not_applied?.length)
      throw new AdminMcpError(
        "PROVIDER_REJECTED",
        "Sarvam did not confirm every required field.",
      );
    return data;
  }
  async inspect() {
    let cursor: string | undefined;
    this.tools = [];
    for (let page = 0; page < 20; page++) {
      const result = await this.client.listTools(cursor ? { cursor } : {}, {
        timeout: 15000,
      });
      this.tools.push(...(result.tools as Tool[]));
      cursor = result.nextCursor;
      if (!cursor) break;
    }
    if (cursor)
      throw new AdminMcpError(
        "PROVIDER_CAPABILITY_MISSING",
        "Sarvam capability inventory is incomplete.",
      );
    const credentialPolicy = this.tools
      .filter((t) =>
        /(?:^|__)(configure_app_tool|create_api_tool|create_http_tool|configure_secret)$/.test(
          t.name,
        ),
      )
      .map((t) => (t as Tool & { description?: string }).description ?? "")
      .join("\n");
    if (
      /auth on a tool is refused|stored credential to no URL|user then selects the credential/i.test(
        credentialPolicy,
      )
    )
      throw new AdminMcpError(
        "PROVIDER_CREDENTIAL_ATTACHMENT_UNAVAILABLE",
        "This Sarvam MCP explicitly refuses authenticated API-tool configuration. Browser-free setup requires a supported Sarvam credential-attachment API; no resources were allocated.",
      );
    for (const name of [
      "agents",
      "telephony",
      "configure_agent",
      "secrets",
      "configure_secret",
      "configure_deployment",
    ])
      this.tool(name);
    const http = this.tools.find((t) =>
      /(?:^|__)(create_http_tool|configure_app_tool)$/.test(t.name),
    );
    if (!http)
      throw new AdminMcpError(
        "PROVIDER_CAPABILITY_MISSING",
        "This Sarvam workspace does not expose HTTP tool authoring.",
      );
    const secret = this.tool("configure_secret");
    if (
      !secret.inputSchema.properties?.value ||
      !secret.inputSchema.properties?.name
    )
      throw new AdminMcpError(
        "PROVIDER_CAPABILITY_MISSING",
        "This Sarvam workspace has no supported private secret installation contract.",
      );
    this.args(secret, { name: "capability_check_only", value: "not_sent" });
    const agent = this.tool("configure_agent").inputSchema.properties ?? {};
    for (const field of [
      "name",
      "clone_from",
      "clone_version",
      "config",
      "prompt",
    ])
      if (!agent[field])
        throw new AdminMcpError(
          "PROVIDER_CAPABILITY_MISSING",
          "Sarvam cannot clone a pinned template and configure the complete managed agent.",
        );
    if (!agent.agent_id && !agent.app_id)
      throw new AdminMcpError(
        "PROVIDER_CAPABILITY_MISSING",
        "Sarvam does not expose scoped agent updates.",
      );
    const deployment =
      this.tool("configure_deployment").inputSchema.properties ?? {};
    for (const field of [
      "app_id",
      "app_version",
      "connection_configs",
      "channel_direction",
    ])
      if (!deployment[field])
        throw new AdminMcpError(
          "PROVIDER_CAPABILITY_MISSING",
          "Sarvam cannot bind this deployment to an exact agent version and number.",
        );
    const hp = http.inputSchema.properties ?? {};
    if (
      (!hp.agent_id && !hp.app_id) ||
      !hp.name ||
      (!hp.connector_config &&
        !hp.config &&
        ["url", "auth", "body", "lifecycle"].some((k) => !hp[k]))
    )
      throw new AdminMcpError(
        "PROVIDER_CAPABILITY_MISSING",
        "Sarvam cannot express scoped authenticated lifecycle tools.",
      );
    this.args(this.tool("configure_agent"), {
      name: "preflight_only",
      clone_from: "template",
      clone_version: 1,
    });
    this.args(this.tool("configure_agent"), {
      agent_id: "preflight_only",
      app_id: "preflight_only",
      config: {},
      prompt: "Preflight only",
      operation: "update",
    });
    this.args(this.tool("configure_deployment"), {
      name: "preflight_only",
      app_id: "preflight_only",
      app_version: 1,
      connection_configs: [],
      channel_direction: "inbound",
      operation: "create",
    });
    for (const lifecycle of ["on_start", "run", "on_end"]) {
      const config = {
        url: "https://example.invalid/catalog",
        method: "POST",
        auth: {
          type: "api_key",
          name: "X-API-Key",
          location: "header",
          value: { secret_id: "preflight_only" },
        },
        body: [],
        lifecycle,
      };
      this.args(http, {
        agent_id: "preflight_only",
        app_id: "preflight_only",
        name: "preflight_only",
        description: "Capability check only",
        tool_type:
          lifecycle === "on_start"
            ? "webhook_on_start"
            : lifecycle === "on_end"
              ? "webhook_on_end"
              : "webhook",
        ...(hp.connector_config
          ? { connector_config: config }
          : hp.config
            ? { config }
            : config),
      });
    }
    for (const [domain, operations] of Object.entries({
      agents: ["list", "get", "commit"],
      telephony: [
        "list_connections",
        "list_endpoints",
        "list_deployments",
        "get_deployment",
      ],
      secrets: ["list"],
    })) {
      const allowed = this.tool(domain).inputSchema.properties?.operation?.enum;
      if (
        !Array.isArray(allowed) ||
        operations.some((op) => !allowed.includes(op))
      )
        throw new AdminMcpError(
          "PROVIDER_CAPABILITY_MISSING",
          `Sarvam ${domain} does not expose all required read/recovery operations.`,
        );
    }
    return { supported: true, private_credential_install: true };
  }
  domain(
    name: "agents" | "telephony" | "secrets",
    operation: string,
    id?: string,
    params?: Json,
  ) {
    return this.invoke(name, { operation, id, params, fetch_all: true });
  }
  async agent(id: string, version?: number): Promise<Json> {
    const a = await this.domain("agents", "get", id, {
      include: ["config", "tools", "tool_specs"],
      ...(version ? { app_version: version } : {}),
    });
    if (!a.config || typeof a.config !== "object")
      throw new AdminMcpError(
        "VERIFICATION_FAILED",
        "Sarvam did not return the agent configuration.",
      );
    const config = { ...a.config };
    for (const key of [
      "org_id",
      "workspace_id",
      "app_id",
      "app_version",
      "status",
    ])
      config[key] ??= a[key] ?? a.details?.[key];
    if (version !== undefined && config.app_version !== version)
      throw new AdminMcpError(
        "VERIFICATION_FAILED",
        "Sarvam did not return the exact requested agent version.",
      );
    return { ...a, config };
  }
  async inventory() {
    const connections = await this.domain("telephony", "list_connections");
    const deployments = await this.domain("telephony", "list_deployments");
    if (connections.pagination?.more || deployments.pagination?.more)
      throw new AdminMcpError(
        "PROVIDER_CAPABILITY_MISSING",
        "Sarvam phone inventory is incomplete.",
      );
    const numbers: Json[] = [];
    for (const c of connections.items ?? []) {
      const id = c.connection_id ?? c.id;
      if (typeof id !== "string")
        throw new AdminMcpError(
          "VERIFICATION_FAILED",
          "Sarvam returned an invalid connection.",
        );
      const endpoints = await this.domain("telephony", "list_endpoints", id);
      if (endpoints.pagination?.more)
        throw new AdminMcpError(
          "PROVIDER_CAPABILITY_MISSING",
          "Sarvam phone inventory is incomplete.",
        );
      for (const item of endpoints.items ?? []) {
        const phone =
          typeof item === "string" ? item : (item.phone_number ?? item.number);
        if (
          /^\+[1-9][0-9]{7,14}$/.test(phone ?? "") &&
          !["archived", "inactive"].includes(item.status) &&
          !item.is_archived &&
          !item.is_deleted
        )
          numbers.push({
            connection_id: id,
            phone_number: phone,
            label: c.name ?? id,
          });
      }
    }
    return { numbers, deployments: deployments.items ?? [] };
  }
  async template(
    id: string,
    version: number,
    scope: string[],
    languageRule?: { path: string; value: string },
  ) {
    const a = await this.agent(id, version);
    this.assertScope(a.config, scope, id);
    const config = a.config.llm_config?.agent_config;
    const initial = config?.initial_state_name;
    if (
      a.config.status !== "committed" ||
      a.config.app_version !== version ||
      typeof initial !== "string" ||
      !config.states?.[initial]
    )
      throw new AdminMcpError(
        "VERIFICATION_FAILED",
        "Use a pinned committed template with a valid initial state.",
      );
    if (
      (a.tools ?? []).length ||
      Object.keys(config.states).length !== 1 ||
      (config.states[initial].tool_names ?? []).length
    )
      throw new AdminMcpError(
        "TEMPLATE_REQUIRED",
        "Select a dedicated committed single-state template with no tools or client credentials. Existing client agents cannot be used as the admin template.",
      );
    if (languageRule) this.assertNativeLanguage(a.config, languageRule);
    return { agent: a, initial };
  }
  assertNativeLanguage(config: Json, rule: { path: string; value: string }) {
    if (
      !/^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*$/.test(
        rule.path,
      ) ||
      rule.path
        .split(".")
        .some((k) => ["__proto__", "prototype", "constructor"].includes(k))
    )
      throw new AdminMcpError(
        "TEMPLATE_REQUIRED",
        "The template native language field path is invalid.",
      );
    const actual = rule.path
      .split(".")
      .reduce((value: any, key) => value?.[key], config);
    if (actual !== rule.value)
      throw new AdminMcpError(
        "TEMPLATE_LANGUAGE_MISMATCH",
        "The actual agent native language setting differs from the reviewed template manifest.",
      );
  }
  assertScope(config: Json, scope: string[], id: string) {
    if (
      config.org_id !== scope[0] ||
      config.workspace_id !== scope[1] ||
      config.app_id !== id
    )
      throw new AdminMcpError(
        "WORKSPACE_MISMATCH",
        "Sarvam authorization is connected to a different organization or workspace.",
      );
  }
  async findAgent(name: string) {
    const all = await this.domain("agents", "list");
    if (all.pagination?.more)
      throw new AdminMcpError(
        "PROVIDER_CAPABILITY_MISSING",
        "Agent inventory is incomplete.",
      );
    const matches = (all.items ?? []).filter(
      (a: Json) => (a.app_name ?? a.name) === name,
    );
    if (matches.length > 1)
      throw new AdminMcpError(
        "VERIFICATION_FAILED",
        "More than one agent matches the job name. Reconcile the job before continuing.",
      );
    return matches[0]?.app_id ?? matches[0]?.id;
  }
  async createAgent(name: string, template: string, version: number) {
    const result = await this.invoke("configure_agent", {
      name,
      clone_from: template,
      clone_version: version,
    });
    const id = result.id ?? result.app_id ?? result.details?.app_id;
    if (!id || typeof id !== "string")
      throw new AdminMcpError(
        "OUTCOME_UNKNOWN",
        "Sarvam did not confirm the new agent ID. Resume the same saved job name.",
      );
    return id;
  }
  configureAgent(id: string, config: Json, prompt?: string) {
    return this.invoke("configure_agent", {
      agent_id: id,
      app_id: id,
      config,
      prompt,
      operation: "update",
    });
  }
  async installSecret(name: string, value: string, allowCreate = true) {
    const all = await this.domain("secrets", "list");
    if (all.pagination?.more)
      throw new AdminMcpError(
        "PROVIDER_CAPABILITY_MISSING",
        "Secret reference inventory is incomplete.",
      );
    const matches = (all.items ?? all.secrets ?? []).filter(
      (s: Json) => s.name === name,
    );
    if (matches.length > 1)
      throw new AdminMcpError(
        "VERIFICATION_FAILED",
        "Duplicate job secret names require reconciliation.",
      );
    if (matches.length) {
      const id = matches[0].secret_id ?? matches[0].id;
      if (typeof id !== "string")
        throw new AdminMcpError(
          "VERIFICATION_FAILED",
          "Sarvam returned an invalid secret reference.",
        );
      const props = this.tool("configure_secret").inputSchema.properties ?? {};
      if (
        !props.operation?.enum?.includes("update") ||
        (!props.secret_id && !props.id)
      )
        throw new AdminMcpError(
          "CREDENTIAL_RECOVERY_REQUIRED",
          "A secret with this job name exists, but Sarvam cannot prove or update its stored value. No deployment was made. Reconcile this private credential before resuming.",
        );
      await this.invoke("configure_secret", {
        operation: "update",
        secret_id: id,
        id,
        name,
        value,
      });
      return id;
    }
    if (!allowCreate)
      throw new AdminMcpError(
        "OUTCOME_UNKNOWN",
        "The prior secret operation is still unconfirmed. Wait for read-back or reconcile it; a second secret was not created.",
      );
    const result = await this.invoke("configure_secret", { name, value });
    const id = result.id ?? result.secret_id;
    if (!id || typeof id !== "string")
      throw new AdminMcpError(
        "OUTCOME_UNKNOWN",
        "Sarvam did not confirm the secret reference. Resume the same job to reconcile by its unique name.",
      );
    return id;
  }
  async addTool(app: string, spec: Json, secret: string, allowCreate = true) {
    const config = this.toolConfig(spec, secret);
    const a = await this.agent(app);
    const existing = (a.tools ?? []).filter((t: Json) => t.name === spec.name);
    if (existing.length > 1)
      throw new AdminMcpError(
        "VERIFICATION_FAILED",
        "Duplicate managed tools require reconciliation.",
      );
    if (existing.length) {
      if (!contains(existing[0].connector_config ?? existing[0].config, config))
        throw new AdminMcpError(
          "VERIFICATION_FAILED",
          "A saved managed tool differs from the job specification. Review before resuming.",
        );
      return;
    }
    if (!allowCreate)
      throw new AdminMcpError(
        "OUTCOME_UNKNOWN",
        "The prior tool operation is still unconfirmed. A duplicate tool was not created.",
      );
    const tool = this.tools.find((t) =>
      /(?:^|__)(create_http_tool|configure_app_tool)$/.test(t.name),
    )!;
    const properties = tool.inputSchema.properties ?? {};
    const fields: Json = {
      agent_id: app,
      app_id: app,
      name: spec.name,
      description: `BookingOS ${spec.name}`,
      tool_type:
        config.lifecycle === "on_start"
          ? "webhook_on_start"
          : config.lifecycle === "on_end"
            ? "webhook_on_end"
            : "webhook",
    };
    if (properties.connector_config) fields.connector_config = config;
    else if (properties.config) fields.config = config;
    else {
      for (const key of ["url", "auth", "body", "lifecycle"])
        if (!properties[key])
          throw new AdminMcpError(
            "PROVIDER_CAPABILITY_MISSING",
            "Sarvam cannot express authenticated lifecycle HTTP tools.",
          );
      Object.assign(fields, config);
    }
    await this.invoke(tool.name, fields);
  }
  private toolConfig(spec: Json, secret: string) {
    const config = structuredClone(spec.config);
    if (
      typeof secret !== "string" ||
      !secret ||
      config.auth?.type !== "api_key" ||
      config.auth?.name !== "X-API-Key" ||
      config.auth?.location !== "header" ||
      config.auth?.value?.secret_id !== "${BOOKINGOS_SECRET_ID}"
    )
      throw new AdminMcpError(
        "VERIFICATION_FAILED",
        "The managed tool does not contain the expected isolated secret reference.",
      );
    config.auth.value.secret_id = secret;
    return config;
  }
  async configurePrompt(app: string, initial: string, spec: Json) {
    if (
      this.tool("agents").inputSchema.properties?.operation?.enum?.includes(
        "set_tools",
      )
    )
      await this.domain("agents", "set_tools", app, {
        enable: spec.tools.map((t: Json) => t.name),
      });
    await this.configureAgent(
      app,
      {
        llm_config: {
          agent_config: {
            agent_variables: spec.variables,
            states: {
              [initial]: {
                tool_names: spec.tools
                  .filter((t: Json) => t.config.lifecycle === "run")
                  .map((t: Json) => t.name),
                agent_variables_in_context: ["bookingos_spaces"],
              },
            },
          },
        },
      },
      spec.prompt,
    );
  }
  async verifyTools(
    app: string,
    scope: string[],
    initial: string,
    spec: Json,
    secret: string,
    version?: number,
    languageRule?: { path: string; value: string },
  ) {
    const a = await this.agent(app, version);
    this.assertScope(a.config, scope, app);
    if (languageRule) this.assertNativeLanguage(a.config, languageRule);
    const state = a.config.llm_config?.agent_config?.states?.[initial];
    const expectedNames = spec.tools
      .filter((t: Json) => t.config.lifecycle === "run")
      .map((t: Json) => t.name);
    if (
      state?.instructions !== spec.prompt ||
      !contains(state.tool_names, expectedNames) ||
      (a.tools ?? []).length !== spec.tools.length
    )
      throw new AdminMcpError(
        "VERIFICATION_FAILED",
        "Agent instructions or tool scope do not match the approved request.",
      );
    for (const t of spec.tools) {
      const found = a.tools.find((x: Json) => x.name === t.name);
      const expected = this.toolConfig(t, secret);
      if (
        !found?.enabled ||
        !contains(found.connector_config ?? found.config, expected)
      )
        throw new AdminMcpError(
          "VERIFICATION_FAILED",
          "A managed tool auth, input or response mapping failed verification.",
        );
    }
    if (!Number.isInteger(a.config.app_version))
      throw new AdminMcpError(
        "VERIFICATION_FAILED",
        "Agent version was not returned.",
      );
    return a.config;
  }
  async commit(app: string, version: number, allowCommit = true) {
    const before = await this.agent(app, version);
    if (before.config.status !== "committed" && !allowCommit)
      throw new AdminMcpError(
        "OUTCOME_UNKNOWN",
        "The prior version commit is still unconfirmed. It was not repeated.",
      );
    if (before.config.status !== "committed")
      await this.domain("agents", "commit", app, {
        source_app_version: version,
        app_version_description:
          "BookingOS approved service setup; isolated key and trusted caller context verified.",
      });
    const after = await this.agent(app, version);
    if (after.config.status !== "committed")
      throw new AdminMcpError(
        "VERIFICATION_FAILED",
        "The exact agent version is not confirmed committed.",
      );
    return version;
  }
  matchesDeployment(
    d: Json,
    app: string,
    version: number,
    connection: string,
    phone: string,
  ) {
    return (
      d.app_id === app &&
      d.app_version === version &&
      d.channel_direction === "inbound" &&
      (d.connection_configs ?? []).length === 1 &&
      d.connection_configs[0].connection_id === connection &&
      contains(d.connection_configs[0].phone_numbers, [phone])
    );
  }
  async deploy(
    app: string,
    version: number,
    connection: string,
    phone: string,
    name: string,
    allowCreate = true,
  ) {
    const inventory = await this.inventory();
    const matches = inventory.deployments.filter((d: Json) =>
      this.matchesDeployment(d, app, version, connection, phone),
    );
    if (matches.length > 1)
      throw new AdminMcpError(
        "VERIFICATION_FAILED",
        "Duplicate matching deployments require reconciliation.",
      );
    if (matches.length) return matches[0];
    if (!allowCreate)
      throw new AdminMcpError(
        "OUTCOME_UNKNOWN",
        "The prior deployment is still unconfirmed. No second deployment was created.",
      );
    if (
      inventory.deployments.some((d: Json) =>
        (d.connection_configs ?? []).some((c: Json) =>
          c.phone_numbers?.includes(phone),
        ),
      )
    )
      throw new AdminMcpError(
        "NUMBER_IN_USE",
        "The number is assigned to another deployment. No transfer or deletion was performed.",
      );
    const result = await this.invoke("configure_deployment", {
      name,
      app_id: app,
      app_version: version,
      connection_configs: [
        { connection_id: connection, phone_numbers: [phone] },
      ],
      channel_direction: "inbound",
      operation: "create",
    });
    const id =
      result.id ?? result.deployment_id ?? result.details?.deployment_id;
    if (!id || typeof id !== "string")
      throw new AdminMcpError(
        "OUTCOME_UNKNOWN",
        "The deployment outcome is unknown. Resume the existing job to reconcile its number.",
      );
    return this.domain("telephony", "get_deployment", id);
  }
}
