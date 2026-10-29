import { BadRequestException, ConflictException } from "@nestjs/common";
import type { CallService } from "../agent-calls/agent-call-policy";
import {
  TOOLS,
  toolConfig,
  containsConfig,
  bookingToolIndexes,
  bookingPromptForServices,
  defaultBookingServices,
} from "./sarvam-booking-config";
type Json = Record<string, any>;
/** Both the backend OAuth adapter and private local MCP clients can implement it. */
export interface SarvamProvisioningClient {
  capabilities(): Promise<Json[]>;
  call(name: string, args: Json): Promise<Json>;
}
export const COMPLETION_TOOL = "bookingos_call_completed";
export const managedToolNames = [...TOOLS.map((t) => t[0]), COMPLETION_TOOL];
export function selectedManagedToolNames(
  services: readonly CallService[] = defaultBookingServices,
) {
  return [
    ...bookingToolIndexes(services).map((index) => TOOLS[index][0]),
    COMPLETION_TOOL,
  ];
}
export function managedToolConfig(
  index: number,
  base: string,
  secret: string,
): Json {
  if (index < TOOLS.length) return toolConfig(index, base, secret);
  return {
    ...toolConfig(0, base, secret),
    url: `${base}/call-events`,
    lifecycle: "on_end",
    body: [
      ["interaction_id", "interaction_id"],
      ["caller_phone", "user_identifier"],
      ["duration_seconds", "call_duration_seconds"],
      ["transcript", "interaction_transcript"],
    ].map(([name, variable_name]) => ({
      name,
      type: "system_variable",
      value: { variable_name },
    })),
    save_to_variables: [],
  };
}
export function managedToolConfigForName(
  name: string,
  base: string,
  secret: string,
): Json {
  const index = managedToolNames.indexOf(name);
  if (index < 0)
    throw new BadRequestException("Unknown managed BookingOS tool.");
  return managedToolConfig(index, base, secret);
}

/** Safe setup metadata; secretId may be a placeholder, never a credential value. */
export function managedBookingSpecification(
  services: readonly CallService[],
  options: { baseUrl: string; secretId: string; language?: string },
) {
  const url = new URL(options.baseUrl);
  if (
    url.protocol !== "https:" ||
    url.username ||
    url.password ||
    url.search ||
    url.hash
  )
    throw new BadRequestException(
      "Use the configured public HTTPS voice API URL.",
    );
  const base = options.baseUrl.replace(/\/$/, "");
  return {
    services: [...services],
    language: options.language ?? null,
    prompt: bookingPromptForServices(services, options.language),
    tools: selectedManagedToolNames(services).map((name) => ({
      name,
      config: managedToolConfigForName(name, base, options.secretId),
    })),
    variables: {
      bookingos_spaces: {
        name: "bookingos_spaces",
        type: "string",
        value:
          "The call service is unavailable until its live catalog has loaded. Direct callers to venue staff.",
        description: "Live spaces loaded at call start",
        is_agent_updatable: false,
        needs_initial_value: true,
        update_post_interaction: false,
      },
    },
  };
}
/** Only known fields/operations from the authenticated workspace's advertised schemas
 * are used. Unsupported contracts stop provisioning and never silently downgrade. */
export class SarvamProvisioningRemote {
  private tools: Json[] = [];
  readonly toolNames: string[];
  readonly toolIndexes: number[];
  readonly prompt: string;
  constructor(
    private remote: SarvamProvisioningClient,
    options: { services?: readonly CallService[]; language?: string } = {},
  ) {
    this.toolIndexes = [...bookingToolIndexes(options.services), TOOLS.length];
    this.toolNames = selectedManagedToolNames(options.services);
    this.prompt = bookingPromptForServices(options.services, options.language);
  }
  async inspect() {
    this.tools = await this.remote.capabilities();
    for (const name of [
      "agents",
      "telephony",
      "configure_agent",
      "secrets",
      "configure_secret",
      "configure_deployment",
    ])
      this.tool(name);
    if (!this.find("create_http_tool") && !this.find("configure_app_tool"))
      throw new BadRequestException(
        "This workspace does not expose HTTP-tool authoring. Enable the supported HTTP-tool plan in Sarvam.",
      );
    const p = this.tool("configure_agent").inputSchema?.properties ?? {};
    if (
      !p.clone_from ||
      !p.clone_version ||
      !p.name ||
      !p.config ||
      !p.prompt ||
      (!p.agent_id && !p.app_id)
    )
      throw new BadRequestException(
        "This workspace does not expose native cloning and managed prompt authoring.",
      );
    this.args(this.tool("configure_agent"), {
      name: "BookingOS",
      clone_from: "template",
      clone_version: 1,
    });
    this.args(this.tool("configure_secret"), {
      name: "bookingos_preflight",
      value: "preflight",
    });
    const secretFields = this.tool("configure_secret").inputSchema?.properties;
    if (!secretFields?.name || !secretFields.value)
      throw new BadRequestException(
        "Sarvam does not advertise supported private secret authoring.",
      );
    for (const operation of ["list", "get", "commit"])
      this.domainArgs("agents", operation, "bookingos_preflight");
    for (const operation of [
      "list_connections",
      "list_endpoints",
      "list_deployments",
      "get_deployment",
    ])
      this.domainArgs("telephony", operation, "bookingos_preflight");
    for (const index of this.toolIndexes)
      this.toolArguments(
        index,
        "bookingos_preflight",
        "https://booking.example.test/voice/v1",
        "secret_reference",
      );
    const deploymentFields =
      this.tool("configure_deployment").inputSchema?.properties ?? {};
    if (
      ["app_id", "app_version", "connection_configs", "channel_direction"].some(
        (key) => !deploymentFields[key],
      )
    )
      throw new BadRequestException(
        "Sarvam does not advertise version-bound inbound deployment authoring.",
      );
    this.args(this.tool("configure_deployment"), {
      name: "BookingOS",
      app_id: "bookingos_preflight",
      app_version: 1,
      connection_configs: [],
      channel_direction: "inbound",
      operation: "create",
    });
  }
  private find(name: string) {
    return this.tools.find(
      (t) => t.name === name || t.name.endsWith(`__${name}`),
    );
  }
  private tool(name: string) {
    const t = this.find(name);
    if (!t)
      throw new BadRequestException(
        `Sarvam workspace is missing ${name}. Check its plan and permissions.`,
      );
    return t;
  }
  private args(t: Json, candidates: Json) {
    const schema = t.inputSchema;
    if (!schema?.properties)
      throw new BadRequestException(
        `Sarvam ${t.name} does not advertise a supported input schema.`,
      );
    const result: Json = {};
    for (const [key, value] of Object.entries(candidates)) {
      const spec = schema.properties[key];
      if (spec && value !== undefined) {
        if (spec.enum && !spec.enum.includes(value))
          throw new BadRequestException(
            `Sarvam ${t.name} does not support the required ${key} operation.`,
          );
        result[key] = value;
      }
    }
    for (const key of schema.required ?? [])
      if (!(key in result))
        throw new BadRequestException(
          `Sarvam ${t.name} requires an unsupported field (${key}). Review this workspace's MCP contract before provisioning.`,
        );
    return result;
  }
  private async invoke(name: string, args: Json) {
    const t = this.tool(name);
    return this.remote.call(t.name, this.args(t, args));
  }
  async domain(
    name: "agents" | "telephony" | "secrets",
    operation: string,
    id?: string,
    params?: Json,
  ) {
    const { tool, args } = this.domainArgs(name, operation, id, params);
    return this.remote.call(tool.name, args);
  }
  private domainArgs(
    name: "agents" | "telephony" | "secrets",
    operation: string,
    id?: string,
    params?: Json,
  ) {
    const operations = this.tool(name).inputSchema?.properties?.operation?.enum;
    if (
      name === "telephony" &&
      operation === "list_numbers" &&
      operations &&
      !operations.includes(operation) &&
      operations.includes("list_phone_numbers")
    )
      operation = "list_phone_numbers";
    const tool = this.tool(name);
    const supported = tool.inputSchema?.properties?.operation?.enum;
    if (!Array.isArray(supported) || !supported.includes(operation))
      throw new BadRequestException(
        `Sarvam ${name} does not advertise the required ${operation} operation.`,
      );
    return {
      tool,
      args: this.args(tool, { operation, id, params, fetch_all: true }),
    };
  }
  async agent(id: string, version?: number): Promise<Json> {
    const result = await this.domain("agents", "get", id, {
      include: ["config", "tools", "tool_specs"],
      ...(version === undefined ? {} : { app_version: version }),
    });
    if (!result.config || typeof result.config !== "object")
      throw new BadRequestException(
        "Sarvam did not return the requested agent configuration.",
      );
    const config = { ...result.config };
    // Authoring versions expose record metadata either beside the config or
    // within the full record. Keep the editable config independent of it.
    for (const key of [
      "org_id",
      "workspace_id",
      "app_id",
      "app_version",
      "status",
    ])
      if (config[key] === undefined)
        config[key] = result[key] ?? result.details?.[key];
    if (version !== undefined && config.app_version !== version)
      throw new BadRequestException(
        "Sarvam did not return the exact requested agent version.",
      );
    return { ...result, config };
  }
  async listAgents() {
    return this.domain("agents", "list");
  }
  async inventory() {
    const [connections, deployments] = await Promise.all([
      this.domain("telephony", "list_connections"),
      this.domain("telephony", "list_deployments"),
    ]);
    if (connections.pagination?.more || deployments.pagination?.more)
      throw new BadRequestException(
        "Incomplete telephony inventory. Narrow the workspace before provisioning.",
      );
    const numbers: Json[] = [];
    for (const connection of connections.items ?? []) {
      const id = connection.connection_id ?? connection.id;
      if (typeof id !== "string")
        throw new BadRequestException(
          "Sarvam returned an invalid telephony connection.",
        );
      const listed = await this.domain("telephony", "list_endpoints", id);
      if (listed.pagination?.more)
        throw new BadRequestException(
          "Incomplete phone inventory. Retry with a smaller workspace.",
        );
      for (const item of listed.items ?? []) {
        const number =
          typeof item === "string" ? item : (item.phone_number ?? item.number);
        if (
          typeof number === "string" &&
          /^\+[1-9][0-9]{7,14}$/.test(number) &&
          !["archived", "inactive"].includes(item.status) &&
          !item.is_archived &&
          !item.is_deleted
        )
          numbers.push({
            connection_id: id,
            phone_number: number,
            label: connection.name ?? id,
          });
      }
    }
    return { numbers, deployments: deployments.items ?? [] };
  }
  async createAgent(name: string, template: string, version: number) {
    const result = await this.invoke("configure_agent", {
      name,
      clone_from: template,
      clone_version: version,
    });
    const id = result.id ?? result.details?.app_id;
    if (typeof id !== "string" || !id)
      throw new BadRequestException(
        "Sarvam did not return the cloned agent ID. Resume to recover it by its saved name.",
      );
    return id;
  }
  async configureAgent(app: string, config: Json, prompt?: string) {
    const p = this.tool("configure_agent").inputSchema?.properties ?? {};
    return this.invoke("configure_agent", {
      ...(p.agent_id ? { agent_id: app } : { app_id: app }),
      config,
      prompt,
      operation: "update",
    });
  }
  async secret(name: string, value: string) {
    const result = await this.invoke("configure_secret", { name, value });
    const id = result.id ?? result.secret_id;
    if (typeof id !== "string" || !id)
      throw new BadRequestException(
        "Sarvam did not return the managed secret ID.",
      );
    return id;
  }
  async toolAt(index: number, app: string, base: string, secret: string) {
    if (!this.toolIndexes.includes(index))
      throw new BadRequestException(
        "This tool is outside the approved call services.",
      );
    const agent = await this.agent(app);
    const name = managedToolNames[index],
      config = managedToolConfig(index, base, secret);
    const existing = agent.tools?.find((t: Json) => t.name === name);
    if (existing) {
      if (!containsConfig(existing.connector_config ?? existing.config, config))
        throw new ConflictException(
          "A managed tool differs from the saved setup. Review it in Sarvam before resuming.",
        );
      return;
    }
    const { tool, args } = this.toolArguments(index, app, base, secret);
    await this.remote.call(tool.name, args);
  }
  private toolArguments(
    index: number,
    app: string,
    base: string,
    secret: string,
  ) {
    const name = managedToolNames[index],
      config = managedToolConfig(index, base, secret);
    const tool =
      this.find("create_http_tool") ?? this.tool("configure_app_tool");
    const p = tool.inputSchema?.properties ?? {};
    if (!p.name || (!p.agent_id && !p.app_id))
      throw new BadRequestException(
        "Sarvam does not advertise agent-scoped HTTP-tool authoring.",
      );
    const args: Json = {
      agent_id: app,
      app_id: app,
      name,
      description: `BookingOS: ${name}`,
      tool_type:
        index === 0
          ? "webhook_on_start"
          : index === 6
            ? "webhook_on_end"
            : "webhook",
    };
    // Current and legacy schemas expose the HTTP connector either nested or flat.
    if (p.connector_config) args.connector_config = config;
    else if (p.config) args.config = config;
    else {
      if (!p.url || !p.auth || !p.body || !p.lifecycle)
        throw new BadRequestException(
          "The HTTP-tool schema cannot express authenticated lifecycle tools. Review the workspace MCP contract.",
        );
      Object.assign(args, config);
    }
    return { tool, args: this.args(tool, args) };
  }
  async enable(app: string) {
    const spec = this.tool("agents").inputSchema?.properties?.operation;
    if (spec?.enum?.includes("set_tools"))
      await this.domain("agents", "set_tools", app, {
        enable: this.toolNames,
      });
  }
  async verify(
    app: string,
    scope: string[],
    initial: string,
    base: string,
    secret: string,
    version?: number,
  ) {
    const agent = await this.agent(app, version),
      c = agent.config;
    if (
      c?.org_id !== scope[0] ||
      c?.workspace_id !== scope[1] ||
      c?.app_id !== app
    )
      throw new BadRequestException(
        "MCP is connected to a different Sarvam workspace. Reconnect using the configured workspace.",
      );
    const state = c.llm_config?.agent_config?.states?.[initial];
    if (
      state?.instructions !== this.prompt ||
      !containsConfig(
        state.tool_names,
        this.toolIndexes
          .filter((index) => index > 0 && index < TOOLS.length)
          .map((index) => TOOLS[index][0]),
      )
    )
      throw new BadRequestException(
        "Sarvam did not save the managed instructions and tools.",
      );
    if (
      (agent.tools ?? []).some(
        (tool: Json) => !this.toolNames.includes(tool.name),
      )
    )
      throw new BadRequestException(
        "The agent contains a tool outside the approved call services.",
      );
    for (const i of this.toolIndexes) {
      const t = agent.tools?.find((t: Json) => t.name === managedToolNames[i]);
      if (
        !t ||
        t.enabled !== true ||
        !containsConfig(
          t.connector_config ?? t.config,
          managedToolConfig(i, base, secret),
        )
      )
        throw new BadRequestException(
          `Managed tool verification failed for ${managedToolNames[i]}.`,
        );
    }
    if (!Number.isInteger(c.app_version))
      throw new BadRequestException("Sarvam did not return the agent version.");
    return c;
  }
  async commit(app: string, version: number) {
    const current = await this.agent(app, version);
    if (current.config?.status === "committed") return version;
    const result = await this.domain("agents", "commit", app, {
      source_app_version: version,
      app_version_description: "BookingOS managed agent",
    });
    const committed =
      result.app_version ??
      result.details?.app_version ??
      result.config?.app_version ??
      version;
    if (!Number.isInteger(committed))
      throw new BadRequestException(
        "Sarvam did not return a committed agent version.",
      );
    const check = await this.agent(app, committed);
    if (check.config?.status !== "committed")
      throw new BadRequestException(
        "Agent commit was not confirmed. Review the saved version before resuming.",
      );
    return committed;
  }
  async deploy(
    app: string,
    version: number,
    connection: string,
    phone: string,
  ) {
    const result = await this.invoke("configure_deployment", {
      name: `BookingOS ${app.slice(-12)}`,
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
    if (typeof id !== "string" || !id)
      throw new BadRequestException(
        "Sarvam did not return the deployment ID. Resume to reconcile the saved number.",
      );
    return this.domain("telephony", "get_deployment", id);
  }
}
