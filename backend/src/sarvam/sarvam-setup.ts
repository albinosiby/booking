import {
  BadRequestException,
  ConflictException,
  ServiceUnavailableException,
} from "@nestjs/common";
import { randomBytes, randomUUID, createHash } from "node:crypto";
import { z } from "zod";
import { Database, Queryable } from "../common/database";
import { Actor } from "../common/auth.guard";
import { WorkspaceService } from "../workspace/workspace.service";
import { sealSecret, openSecret, hashToolKey } from "./sarvam-secrets";
import { MCP, SarvamAuthoring } from "./sarvam-authoring";
import {
  BOOKING_PROMPT,
  CONFIG_REVISION,
  TOOLS,
  toolConfig,
  containsConfig,
} from "./sarvam-booking-config";
type Json = Record<string, any>;
const identifier = z
  .string()
  .trim()
  .regex(/^[A-Za-z0-9_-]{1,100}$/);
const connectInput = z
  .object({
    version: z.number().int().nonnegative(),
    sarvam_org_id: identifier,
    workspace_id: identifier,
    app_id: identifier,
    business_ids: z.array(z.uuid()).min(1).max(100),
    api_key: z.string().trim().min(8).max(500).optional(),
  })
  .strict();
const sha = (s: string) => createHash("sha256").update(s).digest("hex");
const message = (e: unknown) =>
  e instanceof BadRequestException || e instanceof ServiceUnavailableException
    ? e.message
    : "Setup could not be completed. Retry to resume.";
const variable = {
  name: "bookingos_spaces",
  type: "string",
  value: "",
  description: "Live bookable spaces loaded at call start",
  is_agent_updatable: false,
  needs_initial_value: true,
  update_post_interaction: false,
};

/** Durable, owner-scoped orchestration. Each step is short and has a DB lease. */
export class SarvamSetup {
  constructor(
    private db: Database,
    private workspace: WorkspaceService,
    private http: typeof fetch,
    private ensure: (db: Queryable, org: string) => Promise<Json>,
  ) {}
  private async row(org: string, db: Queryable = this.db) {
    return (
      await db.query<Json>(
        "SELECT * FROM sarvam_integrations WHERE organization_id=$1",
        [org],
      )
    ).rows[0];
  }
  private async owner(actor: Actor) {
    return (await this.workspace.member(actor, true)).organization_id as string;
  }
  private publicBase() {
    const url = this.workspace.publicAppUrl || process.env.PUBLIC_APP_URL || "";
    if (
      !url.startsWith("https://") ||
      new URL(url).username ||
      new URL(url).password ||
      new URL(url).search ||
      new URL(url).hash
    )
      throw new BadRequestException(
        "Configure the backend's public HTTPS URL before connecting Sarvam.",
      );
    return url.replace(/\/$/, "");
  }
  private async checkpoint(
    org: string,
    token: string,
    state: Json,
    status?: string,
  ) {
    const r = await this.db.query(
      "UPDATE sarvam_integrations SET setup_state=$1,setup_status=COALESCE($2,CASE WHEN setup_status='failed' THEN 'connecting' ELSE setup_status END),setup_error='',version=version+1,updated_at=now() WHERE organization_id=$3 AND setup_lease=$4 RETURNING organization_id",
      [JSON.stringify(state), status ?? null, org, token],
    );
    if (!r.rows.length)
      throw new ConflictException(
        "Setup was superseded. Refresh the connection status.",
      );
  }
  private async lease(org: string) {
    const token = randomUUID();
    const s = (
      await this.db.query<Json>(
        "UPDATE sarvam_integrations SET setup_lease=$1,setup_lease_until=now()+interval '90 seconds' WHERE organization_id=$2 AND (setup_lease_until IS NULL OR setup_lease_until<now()) RETURNING *",
        [token, org],
      )
    ).rows[0];
    if (!s)
      throw new ConflictException(
        "Another connection action is still finishing. Refresh and retry shortly.",
      );
    return { token, s };
  }
  private async release(org: string, token: string) {
    await this.db.query(
      "UPDATE sarvam_integrations SET setup_lease=NULL,setup_lease_until=NULL WHERE organization_id=$1 AND setup_lease=$2",
      [org, token],
    );
  }
  private async credential(org: string, s: Json): Promise<Json> {
    if (!s.authoring_ciphertext)
      throw new BadRequestException(
        "Sarvam authorization expired. Retry setup to authorize.",
      );
    let auth = JSON.parse(openSecret(s.authoring_ciphertext));
    if (auth.expires_at < Date.now() + 30000) {
      if (!auth.refresh_token)
        throw new BadRequestException(
          "Sarvam authorization expired. Connect again.",
        );
      const refreshed = await new SarvamAuthoring(this.http).exchange({
        grant_type: "refresh_token",
        refresh_token: auth.refresh_token,
        client_id: auth.client_id,
      });
      auth = {
        ...auth,
        ...refreshed,
        expires_at: Date.now() + Number(refreshed.expires_in ?? 300) * 1000,
      };
      await this.db.query(
        "UPDATE sarvam_integrations SET authoring_ciphertext=$1 WHERE organization_id=$2 AND authoring_ciphertext=$3",
        [sealSecret(JSON.stringify(auth)), org, s.authoring_ciphertext],
      );
    }
    return auth;
  }
  async connect(actor: Actor, input: unknown) {
    const v = connectInput.parse(input),
      org = await this.owner(actor);
    const base = this.publicBase();
    // Initialize under the organization lock, including the first version:0 save.
    await this.db.transaction(async (db) => {
      await db.query("SELECT id FROM organizations WHERE id=$1 FOR UPDATE", [
        org,
      ]);
      const current = await this.row(org, db);
      if ((current?.version ?? 0) !== v.version)
        throw new ConflictException(
          "Settings changed. Reload before connecting.",
        );
      if (
        current?.setup_lease_until &&
        new Date(current.setup_lease_until).getTime() > Date.now()
      )
        throw new ConflictException(
          "Connection setup is already running. Retry shortly.",
        );
      if (
        current?.setup_status === "cleanup_pending" ||
        current?.setup_state?.resume_status === "cleanup_pending"
      )
        throw new ConflictException(
          "Finish Disconnect cleanup before reconnecting.",
        );
      if (
        current?.app_id &&
        (current.api_key_ciphertext || current.setup_state?.secret_name) &&
        [
          current.app_id !== v.app_id,
          current.workspace_id !== v.workspace_id,
          current.sarvam_org_id !== v.sarvam_org_id,
        ].some(Boolean)
      )
        throw new ConflictException(
          "Disconnect the existing agent before connecting a different agent or workspace.",
        );
      const owned = await db.query(
        "SELECT id FROM businesses WHERE organization_id=$1 AND id=ANY($2::uuid[])",
        [org, v.business_ids],
      );
      if (owned.rows.length !== new Set(v.business_ids).size)
        throw new BadRequestException(
          "Choose businesses in this organization.",
        );
      const s = await this.ensure(db, org);
      if (
        !v.api_key &&
        !s.api_key_ciphertext &&
        !s.setup_state?.pending_api_key_ciphertext
      )
        throw new BadRequestException("Enter the Sarvam workspace API key.");
      const key = v.api_key
        ? sealSecret(v.api_key)
        : (s.setup_state?.pending_api_key_ciphertext ?? s.api_key_ciphertext);
      const state = s.setup_state ?? {};
      const internal =
        state.key_ciphertext ||
        s.tool_key_ciphertext ||
        sealSecret("bkv_" + randomBytes(32).toString("base64url"));
      await db.query(
        "UPDATE sarvam_integrations SET api_key_ciphertext=$1,api_key_last4=$2,sarvam_org_id=$3,workspace_id=$4,app_id=$5,setup_status='connecting',setup_error='',setup_state=$6,version=version+1 WHERE organization_id=$7",
        [
          s.api_key_ciphertext,
          s.api_key_last4,
          v.sarvam_org_id,
          v.workspace_id,
          v.app_id,
          JSON.stringify({
            ...state,
            revision: CONFIG_REVISION,
            pending_api_key_ciphertext: key,
            pending_last4:
              v.api_key?.slice(-4) ?? state.pending_last4 ?? s.api_key_last4,
            resume_step: undefined,
            resume_status: undefined,
            base,
            key_ciphertext: internal,
            step: "verify_credentials",
            business_ids: [...new Set(v.business_ids)],
          }),
          org,
        ],
      );
      await this.workspace.audit(
        db,
        actor,
        org,
        "sarvam.connect_started",
        s.membership_id,
      );
    });
  }
  private async beginAuthorization(org: string, s: Json, token: string) {
    const state = s.setup_state as Json;
    const redirect = `${state.base}/v1/sarvam/oauth/callback`;
    const client =
      state.oauth_client_id ||
      process.env.SARVAM_OAUTH_CLIENT_ID ||
      (await new SarvamAuthoring(this.http).register(redirect)).client_id;
    if (typeof client !== "string")
      throw new ServiceUnavailableException(
        "Sarvam OAuth client registration failed. Configure SARVAM_OAUTH_CLIENT_ID if registration is restricted.",
      );
    const nonce = randomBytes(32).toString("base64url"),
      verifier = randomBytes(32).toString("base64url");
    const url = new URL(`${MCP}/authorize`);
    Object.entries({
      response_type: "code",
      client_id: client,
      redirect_uri: redirect,
      state: nonce,
      code_challenge: createHash("sha256").update(verifier).digest("base64url"),
      code_challenge_method: "S256",
      resource: MCP,
    }).forEach(([k, v]) => url.searchParams.set(k, v));
    const pending = {
      verifier,
      client,
      redirect,
      expires: Date.now() + 10 * 60000,
    };
    await this.db.query(
      "UPDATE sarvam_integrations SET oauth_state_hash=$1,oauth_pending_ciphertext=$2 WHERE organization_id=$3 AND setup_lease=$4",
      [sha(nonce), sealSecret(JSON.stringify(pending)), org, token],
    );
    await this.checkpoint(
      org,
      token,
      {
        ...state,
        oauth_client_id: client,
        step: "authorize",
        authorization_url: url.toString(),
      },
      "authorization_required",
    );
  }
  async callback(input: unknown) {
    const v = z
      .object({
        state: z.string().regex(/^[A-Za-z0-9_-]{43}$/),
        code: z.string().max(4000).optional(),
        error: z.string().max(200).optional(),
        iss: z.literal(MCP).optional(),
      })
      .passthrough()
      .parse(input);
    const s = (
      await this.db.query<Json>(
        "SELECT * FROM sarvam_integrations WHERE oauth_state_hash=$1",
        [sha(v.state)],
      )
    ).rows[0];
    if (
      !s?.oauth_pending_ciphertext ||
      s.setup_status !== "authorization_required"
    )
      throw new BadRequestException(
        "This authorization link expired. Return to BookingOS and Connect again.",
      );
    const pending = JSON.parse(openSecret(s.oauth_pending_ciphertext));
    if (pending.expires < Date.now())
      throw new BadRequestException(
        "This authorization link expired. Connect again.",
      );
    // Single-use state is consumed before exchanging the code. Failed exchanges restart Connect.
    const claimed = await this.db.query(
      "UPDATE sarvam_integrations SET oauth_state_hash=NULL,oauth_pending_ciphertext=NULL WHERE organization_id=$1 AND oauth_state_hash=$2 RETURNING organization_id",
      [s.organization_id, sha(v.state)],
    );
    if (!claimed.rows.length)
      throw new BadRequestException("Authorization has already been used.");
    if (v.error || !v.code) {
      await this.db.query(
        "UPDATE sarvam_integrations SET setup_status='failed',setup_error='Sarvam authorization was declined. Connect again.',version=version+1 WHERE organization_id=$1 AND setup_status='authorization_required'",
        [s.organization_id],
      );
      return;
    }
    try {
      const auth = await new SarvamAuthoring(this.http).exchange({
        grant_type: "authorization_code",
        code: v.code,
        code_verifier: pending.verifier,
        client_id: pending.client,
        redirect_uri: pending.redirect,
      });
      await this.db.query(
        "UPDATE sarvam_integrations SET authoring_ciphertext=$1,setup_status='connecting',setup_state=$2,setup_error='',version=version+1 WHERE organization_id=$3 AND setup_status='authorization_required' AND version=$4",
        [
          sealSecret(
            JSON.stringify({
              ...auth,
              client_id: pending.client,
              expires_at: Date.now() + Number(auth.expires_in ?? 300) * 1000,
            }),
          ),
          JSON.stringify({
            ...s.setup_state,
            authorization_url: undefined,
            step: "capabilities",
          }),
          s.organization_id,
          s.version,
        ],
      );
    } catch (e) {
      await this.db.query(
        "UPDATE sarvam_integrations SET setup_status='failed',setup_error=$1,version=version+1 WHERE organization_id=$2 AND setup_status='authorization_required' AND version=$3",
        [message(e), s.organization_id, s.version],
      );
    }
  }
  async step(actor: Actor) {
    const org = await this.owner(actor),
      { s, token } = await this.lease(org);
    try {
      const state = s.setup_state as Json;
      if (
        !["connecting", "failed", "publishing", "cleanup_pending"].includes(
          s.setup_status,
        )
      )
        return;
      if (state.step === "verify_credentials") {
        const url = `https://apps.sarvam.ai/api/analytics/v1/${s.sarvam_org_id}/${s.workspace_id}/${s.app_id}/interactions?start_datetime=${encodeURIComponent(new Date(Date.now() - 86400000).toISOString())}&end_datetime=${encodeURIComponent(new Date().toISOString())}`;
        const r = await this.http(url, {
          headers: {
            "X-API-Key": openSecret(
              state.pending_api_key_ciphertext ?? s.api_key_ciphertext,
            ),
          },
          redirect: "error",
          signal: AbortSignal.timeout(12000),
        });
        if (!r.ok)
          throw new BadRequestException(
            "Sarvam could not verify the workspace API key and IDs. Check them and Connect again.",
          );
        await r.body?.cancel();
        await this.db.query(
          "UPDATE sarvam_integrations SET api_key_ciphertext=$1,api_key_last4=$2 WHERE organization_id=$3 AND setup_lease=$4",
          [
            state.pending_api_key_ciphertext ?? s.api_key_ciphertext,
            state.pending_last4 ?? s.api_key_last4,
            org,
            token,
          ],
        );
        await this.checkpoint(
          org,
          token,
          {
            ...state,
            pending_api_key_ciphertext: undefined,
            pending_last4: undefined,
            step: "authorize",
          },
          "connecting",
        );
        return;
      }
      if (state.step === "authorize") {
        await this.beginAuthorization(org, s, token);
        return;
      }
      const auth = await this.credential(org, s),
        remote = new SarvamAuthoring(this.http, auth.access_token);
      const call = (name: string, args: Json) =>
        remote.call(state.tool_names?.[name] ?? name, args);
      if (state.step === "capabilities") {
        const capabilities = await remote.capabilities();
        const required = [
          "agents",
          "configure_agent",
          "configure_secret",
          "secrets",
          "configure_app_tool",
          "telephony",
          "configure_deployment",
        ];
        const names: Json = {};
        for (const name of required) {
          const actual = capabilities.find(
            (t) => t.name === name || t.name.endsWith(`__${name}`),
          );
          if (!actual)
            throw new BadRequestException(
              `Sarvam workspace does not provide ${name}. Check plan and authoring permissions.`,
            );
          names[name] = actual.name;
        }
        await this.checkpoint(
          org,
          token,
          { ...state, tool_names: names, step: "scope" },
          "connecting",
        );
        return;
      }
      if (state.step === "scope") {
        const agent = await call("agents", {
          operation: "get",
          id: s.app_id,
          params: { include: ["config", "tools"] },
        });
        const config = agent.config;
        if (
          config?.org_id !== s.sarvam_org_id ||
          config?.workspace_id !== s.workspace_id ||
          config?.app_id !== s.app_id
        )
          throw new BadRequestException(
            "Authorize the same Sarvam organization and workspace as the entered IDs.",
          );
        if (
          (agent.tools ?? []).some(
            (t: Json) =>
              TOOLS.some((spec) => spec[0] === t.name) &&
              (!state.secret_id ||
                t.connector_config?.auth?.value?.secret_id !== state.secret_id),
          )
        )
          throw new BadRequestException(
            "This Sarvam agent is managed by a different BookingOS connection. Use a separate agent or remove the old connection first.",
          );
        const ac = config.llm_config?.agent_config;
        if (
          !ac?.initial_state_name ||
          Object.keys(ac.states ?? {}).length !== 1
        )
          throw new BadRequestException(
            "Automatic booking setup requires a single-state Sarvam agent.",
          );
        const legacy = (agent.tools ?? [])
          .filter(
            (t: Json) =>
              [
                "assets",
                "health",
                "quote_booking",
                "booking",
                "booking_other_number",
                "cancel_booking",
              ].includes(t.name) &&
              t.connector_config?.url?.startsWith(
                "https://bookingos.online/api/v1/",
              ),
          )
          .map((t: Json) => t.name);
        await this.checkpoint(
          org,
          token,
          {
            ...state,
            initial_state: ac.initial_state_name,
            legacy_tools: legacy,
            step: state.resume_step ?? "secret",
            resume_step: undefined,
            resume_status: undefined,
          },
          state.resume_status ?? "connecting",
        );
        return;
      }
      if (state.step === "secret") {
        const name =
          state.secret_name ??
          `bookingos_${org.replace(/-/g, "")}_${randomBytes(6).toString("hex")}`;
        // Save name before remote mutation, so a lost response can be recovered by listing.
        if (!state.secret_name) {
          await this.checkpoint(org, token, { ...state, secret_name: name });
          return;
        }
        const listed = await call("secrets", { operation: "list" });
        const found = listed.items?.find((x: Json) => x.name === name);
        const secret = await call("configure_secret", {
          name,
          value: openSecret(state.key_ciphertext),
        });
        if (found && secret.id !== found.id)
          throw new BadRequestException(
            "Sarvam changed the managed secret identifier. Retry setup.",
          );
        if (!secret.id)
          throw new ServiceUnavailableException(
            "Sarvam did not return a secret identifier.",
          );
        await this.checkpoint(org, token, {
          ...state,
          secret_id: secret.id,
          step: "variables",
        });
        return;
      }
      if (state.step === "variables") {
        await call("configure_agent", {
          agent_id: s.app_id,
          config: {
            llm_config: {
              agent_config: { agent_variables: { bookingos_spaces: variable } },
            },
          },
        });
        await this.checkpoint(org, token, { ...state, step: "disable_legacy" });
        return;
      }
      if (state.step === "disable_legacy") {
        if (state.legacy_tools?.length)
          await call("agents", {
            operation: "set_tools",
            id: s.app_id,
            params: { disable: state.legacy_tools },
          });
        await this.checkpoint(org, token, { ...state, step: "tool_0" });
        return;
      }
      if (/^tool_[0-5]$/.test(state.step)) {
        const index = Number(state.step.slice(5)),
          [name] = TOOLS[index];
        const agent = await call("agents", {
          operation: "get",
          id: s.app_id,
          params: { include: ["tools"] },
        });
        const existing = agent.tools?.find((t: Json) => t.name === name);
        const config = toolConfig(
          index,
          `${state.base}/voice/v1`,
          state.secret_id,
        );
        if (
          existing &&
          (existing.connector_config?.url !== config.url ||
            existing.connector_config?.auth?.value?.secret_id !==
              state.secret_id)
        )
          throw new ConflictException(
            "A BookingOS tool belongs to another connection. Disconnect its owner before continuing.",
          );
        await call("configure_app_tool", {
          agent_id: s.app_id,
          name,
          description: `BookingOS: ${TOOLS[index][1]}`,
          tool_type: index === 0 ? "webhook_on_start" : "webhook",
          connector_config: config,
          ...(existing ? { tool_id: existing.id } : {}),
        });
        await this.checkpoint(org, token, {
          ...state,
          managed_tools: {
            ...state.managed_tools,
            [name]: existing?.id ?? true,
          },
          step: index === 5 ? "enable_tools" : `tool_${index + 1}`,
        });
        return;
      }
      if (state.step === "enable_tools") {
        await call("agents", {
          operation: "set_tools",
          id: s.app_id,
          params: {
            enable: TOOLS.map((t) => t[0]),
            disable: state.legacy_tools ?? [],
          },
        });
        await this.checkpoint(org, token, { ...state, step: "prompt" });
        return;
      }
      if (state.step === "prompt") {
        await call("configure_agent", {
          agent_id: s.app_id,
          prompt: BOOKING_PROMPT,
          config: {
            llm_config: {
              agent_config: {
                states: {
                  [state.initial_state]: {
                    tool_names: TOOLS.slice(1).map((t) => t[0]),
                    agent_variables_in_context: ["bookingos_spaces"],
                  },
                },
              },
            },
          },
        });
        await this.checkpoint(org, token, { ...state, step: "verify" });
        return;
      }
      if (state.step === "verify") {
        const agent = await call("agents", {
          operation: "get",
          id: s.app_id,
          params: { include: ["config", "tools"] },
        });
        const config = agent.config;
        if (
          config?.llm_config?.agent_config?.states?.[state.initial_state]
            ?.instructions !== BOOKING_PROMPT
        )
          throw new BadRequestException(
            "Sarvam did not save the booking instructions. Retry setup.",
          );
        for (let index = 0; index < TOOLS.length; index++) {
          const t = agent.tools?.find((x: Json) => x.name === TOOLS[index][0]);
          const expected = toolConfig(
            index,
            `${state.base}/voice/v1`,
            state.secret_id,
          );
          if (
            !t?.enabled ||
            t.connector_config?.url !== expected.url ||
            !containsConfig(t.connector_config, expected)
          )
            throw new BadRequestException(
              "Sarvam booking tool verification failed. Retry setup.",
            );
        }
        await this.checkpoint(org, token, {
          ...state,
          draft_version: config.app_version,
          step: "deployments",
        });
        return;
      }
      if (state.step === "deployments") {
        const deployments = await call("telephony", {
          operation: "list_deployments",
          id: s.app_id,
          params: { limit: 100 },
        });
        if (deployments.pagination?.more)
          throw new BadRequestException(
            "Too many deployments to publish safely. Contact the administrator.",
          );
        await this.checkpoint(
          org,
          token,
          {
            ...state,
            deployments: (deployments.items ?? [])
              .filter((d: Json) => d.app_id === s.app_id)
              .map((d: Json) => ({
                id: d.deployment_id,
                name: d.name ?? d.deployment_id,
                version: d.app_version,
              })),
            step: "ready",
          },
          "configured",
        );
        return;
      }
      if (state.step === "commit") {
        const version = await call("agents", {
          operation: "get",
          id: s.app_id,
          params: {
            app_version: state.draft_version,
            include: ["config", "tools"],
          },
        });
        if (
          version.config?.llm_config?.agent_config?.states?.[
            state.initial_state
          ]?.instructions !== BOOKING_PROMPT
        )
          throw new BadRequestException(
            "The agent draft changed. Connect again before publishing.",
          );
        for (let i = 0; i < TOOLS.length; i++) {
          const tool = version.tools?.find((t: Json) => t.name === TOOLS[i][0]);
          if (
            !tool?.enabled ||
            !containsConfig(
              tool.connector_config,
              toolConfig(i, `${state.base}/voice/v1`, state.secret_id),
            )
          )
            throw new BadRequestException(
              "Booking tools changed after setup. Connect again before publishing.",
            );
        }
        if (version.config.status !== "committed")
          await call("agents", {
            operation: "commit",
            id: s.app_id,
            params: {
              source_app_version: state.draft_version,
              app_version_description: `BookingOS configuration ${CONFIG_REVISION}`,
            },
          });
        await this.checkpoint(
          org,
          token,
          { ...state, step: "deploy" },
          "publishing",
        );
        return;
      }
      if (state.step === "deploy") {
        const deployment = await call("telephony", {
          operation: "get_deployment",
          id: state.deployment_id,
        });
        if (deployment.app_id !== s.app_id)
          throw new BadRequestException("Deployment belongs to another agent.");
        if (deployment.app_version !== state.draft_version)
          await call("configure_deployment", {
            deployment_id: state.deployment_id,
            app_version: state.draft_version,
          });
        await this.checkpoint(
          org,
          token,
          { ...state, step: "verify_publish" },
          "publishing",
        );
        return;
      }
      if (state.step === "verify_publish") {
        const deployment = await call("telephony", {
          operation: "get_deployment",
          id: state.deployment_id,
        });
        if (
          deployment.app_id !== s.app_id ||
          deployment.app_version !== state.draft_version
        )
          throw new BadRequestException(
            "Sarvam deployment version was not updated. Retry Publish.",
          );
        await this.db.transaction(async (db) => {
          const row = (
            await db.query<Json>(
              "SELECT * FROM sarvam_integrations WHERE organization_id=$1 FOR UPDATE",
              [org],
            )
          ).rows[0];
          if (row.setup_lease !== token)
            throw new ConflictException(
              "Publishing was superseded by another action.",
            );
          await db.query(
            "UPDATE sarvam_integrations SET tool_key_hash=$1,tool_key_ciphertext=$2,pending_tool_key_hash=NULL,setup_status='configured',setup_error='',setup_state=$3,version=version+1 WHERE organization_id=$4",
            [
              hashToolKey(openSecret(state.key_ciphertext)),
              state.key_ciphertext,
              JSON.stringify({
                ...state,
                published_version: state.draft_version,
                step: "ready",
              }),
              org,
            ],
          );
          await db.query(
            "DELETE FROM staff_assignments WHERE membership_id=$1",
            [row.membership_id],
          );
          for (const business of state.business_ids)
            await db.query(
              "INSERT INTO staff_assignments(membership_id,organization_id,business_id,resource_ids) VALUES($1,$2,$3,'[]')",
              [row.membership_id, org, business],
            );
          await this.workspace.audit(
            db,
            actor,
            org,
            "sarvam.published",
            row.membership_id,
          );
        });
        return;
      }
      if (state.step === "cleanup_tools") {
        await call("agents", {
          operation: "set_tools",
          id: s.app_id,
          params: { disable: TOOLS.map((t) => t[0]) },
        });
        await this.checkpoint(
          org,
          token,
          { ...state, step: "cleanup_secret" },
          "cleanup_pending",
        );
        return;
      }
      if (state.step === "cleanup_secret") {
        if (state.secret_name)
          await call("configure_secret", {
            name: state.secret_name,
            value: randomBytes(32).toString("base64url"),
          });
        await this.db.query(
          "UPDATE sarvam_integrations SET authoring_ciphertext=NULL,setup_state=$1,setup_status='disconnected',setup_error='',version=version+1 WHERE organization_id=$2 AND setup_lease=$3",
          [
            JSON.stringify({
              oauth_client_id: state.oauth_client_id,
              secret_name: state.secret_name,
              secret_id: state.secret_id,
              managed_tools: state.managed_tools,
              base: state.base,
              tool_names: state.tool_names,
            }),
            org,
            token,
          ],
        );
        return;
      }
      throw new BadRequestException(
        "Unknown setup step. Connect again to restart safely.",
      );
    } catch (e) {
      if (
        /authorization expired|authorization.*permission|authorize.*same Sarvam/.test(
          message(e),
        )
      ) {
        await this.db.query(
          "UPDATE sarvam_integrations SET setup_state=$1,authoring_ciphertext=NULL WHERE organization_id=$2 AND setup_lease=$3",
          [
            JSON.stringify({
              ...s.setup_state,
              resume_step: s.setup_state.step,
              resume_status: s.setup_status,
              step: "authorize",
            }),
            org,
            token,
          ],
        );
      }
      await this.db.query(
        "UPDATE sarvam_integrations SET setup_error=$1,setup_status=CASE WHEN setup_status IN ('cleanup_pending','publishing') THEN setup_status ELSE 'failed' END,version=version+1 WHERE organization_id=$2 AND setup_lease=$3",
        [message(e), org, token],
      );
      throw e instanceof ConflictException ||
        e instanceof BadRequestException ||
        e instanceof ServiceUnavailableException
        ? e
        : new ServiceUnavailableException(message(e));
    } finally {
      await this.release(org, token);
    }
  }
  async enabled(actor: Actor, input: unknown) {
    const v = z
        .object({
          enabled: z.boolean(),
          version: z.number().int().nonnegative(),
        })
        .strict()
        .parse(input),
      org = await this.owner(actor);
    await this.db.transaction(async (db) => {
      const s = (
        await db.query<Json>(
          "SELECT * FROM sarvam_integrations WHERE organization_id=$1 FOR UPDATE",
          [org],
        )
      ).rows[0];
      if (!s || (v.enabled && s.version !== v.version))
        throw new ConflictException("Settings changed. Refresh and retry.");
      if (
        v.enabled &&
        (!s.tool_key_hash ||
          !["configured", "legacy"].includes(s.setup_status) ||
          (s.setup_status !== "legacy" && !s.setup_state?.published_version))
      )
        throw new BadRequestException(
          "Connect and publish the agent before enabling phone bookings.",
        );
      if (
        v.enabled &&
        !(
          await db.query(
            "SELECT 1 FROM staff_assignments WHERE membership_id=$1",
            [s.membership_id],
          )
        ).rows.length
      )
        throw new BadRequestException(
          "Select at least one business before enabling phone bookings.",
        );
      await db.query(
        "UPDATE sarvam_integrations SET enabled=$1,version=version+1 WHERE organization_id=$2",
        [v.enabled, org],
      );
      await db.query("UPDATE memberships SET active=$1 WHERE id=$2", [
        v.enabled,
        s.membership_id,
      ]);
      await this.workspace.audit(
        db,
        actor,
        org,
        v.enabled ? "sarvam.bookings_enabled" : "sarvam.bookings_disabled",
        s.membership_id,
      );
    });
  }
  async disconnect(actor: Actor) {
    const org = await this.owner(actor);
    await this.db.transaction(async (db) => {
      const s = (
        await db.query<Json>(
          "SELECT * FROM sarvam_integrations WHERE organization_id=$1 FOR UPDATE",
          [org],
        )
      ).rows[0];
      if (!s) return;
      if (
        s.setup_status === "cleanup_pending" ||
        (s.setup_status === "disconnected" &&
          !s.api_key_ciphertext &&
          !s.setup_state?.pending_api_key_ciphertext)
      )
        return;
      const cleanup = !!s.setup_state?.secret_name;
      await db.query(
        "UPDATE sarvam_integrations SET enabled=false,tool_key_hash=NULL,tool_key_ciphertext=NULL,pending_tool_key_hash=NULL,api_key_ciphertext=NULL,api_key_last4='',oauth_state_hash=NULL,oauth_pending_ciphertext=NULL,setup_lease=NULL,setup_status=$1,setup_error='',setup_state=$2,authoring_ciphertext=CASE WHEN $3 THEN authoring_ciphertext ELSE NULL END,version=version+1 WHERE organization_id=$4",
        [
          cleanup ? "cleanup_pending" : "disconnected",
          cleanup
            ? JSON.stringify({
                ...s.setup_state,
                key_ciphertext: undefined,
                pending_api_key_ciphertext: undefined,
                pending_last4: undefined,
                step: "cleanup_tools",
              })
            : "{}",
          cleanup,
          org,
        ],
      );
      await db.query("UPDATE memberships SET active=false WHERE id=$1", [
        s.membership_id,
      ]);
      await this.workspace.audit(
        db,
        actor,
        org,
        "sarvam.disconnected",
        s.membership_id,
      );
    });
  }
  async publish(actor: Actor, input: unknown) {
    const v = z
        .object({
          version: z.number().int().positive(),
          deployment_id: identifier,
        })
        .strict()
        .parse(input),
      org = await this.owner(actor);
    await this.db.transaction(async (db) => {
      const s = (
        await db.query<Json>(
          "SELECT * FROM sarvam_integrations WHERE organization_id=$1 FOR UPDATE",
          [org],
        )
      ).rows[0];
      if (
        !s ||
        s.version !== v.version ||
        s.setup_status !== "configured" ||
        s.setup_state?.step !== "ready"
      )
        throw new ConflictException(
          "Finish Connect and refresh before publishing.",
        );
      if (
        !s.setup_state.deployments?.some((d: Json) => d.id === v.deployment_id)
      )
        throw new BadRequestException("Select a deployment for this agent.");
      await db.query(
        "UPDATE sarvam_integrations SET setup_status='publishing',setup_error='',pending_tool_key_hash=$1,setup_state=$2,version=version+1 WHERE organization_id=$3",
        [
          hashToolKey(openSecret(s.setup_state.key_ciphertext)),
          JSON.stringify({
            ...s.setup_state,
            deployment_id: v.deployment_id,
            step: "commit",
          }),
          org,
        ],
      );
      await this.workspace.audit(
        db,
        actor,
        org,
        "sarvam.publish_requested",
        s.membership_id,
      );
    });
  }
}
