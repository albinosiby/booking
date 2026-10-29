import {
  Injectable,
  BadRequestException,
  ConflictException,
  NotFoundException,
} from "@nestjs/common";
import { randomBytes, randomUUID, createHash } from "node:crypto";
import { z } from "zod";
import { Database, Queryable } from "../common/database";
import { Actor } from "../common/auth.guard";
import { AdminService } from "./admin.service";
import { SarvamService } from "../sarvam/sarvam.service";
import {
  SarvamAuthoring,
  MCP,
  SarvamAuthorizationExpired,
} from "../sarvam/sarvam-authoring";
import { SarvamProvisioningRemote } from "../sarvam/sarvam-provisioning-remote";
import { sealSecret, openSecret, hashToolKey } from "../sarvam/sarvam-secrets";
import {
  serviceSelection,
  type CallService,
} from "../agent-calls/agent-call-policy";
import { TOOLS } from "../sarvam/sarvam-booking-config";
import { WorkspaceService } from "../workspace/workspace.service";
type Json = Record<string, any>;
const identifier = z
  .string()
  .trim()
  .regex(/^[A-Za-z0-9_-]{1,100}$/);
const hash = (s: string) => createHash("sha256").update(s).digest("hex");
const settingsSchema = z
  .object({
    version: z.number().int().positive(),
    sarvam_org_id: identifier,
    workspace_id: identifier,
    template_app_id: identifier.optional(),
    api_key: z.string().trim().min(8).max(500).optional(),
  })
  .strict();
@Injectable()
export class AdminSarvamService {
  constructor(
    private db: Database,
    private admin: AdminService,
    private provider: SarvamService,
    private workspace: WorkspaceService,
  ) {}
  private async row(db: Queryable = this.db) {
    return (
      await db.query<Json>(
        "SELECT * FROM sarvam_admin_connection WHERE id=true",
      )
    ).rows[0];
  }
  private redirectUri() {
    const raw = process.env.SARVAM_ADMIN_REDIRECT_URI;
    if (!raw)
      throw new BadRequestException(
        "Set SARVAM_ADMIN_REDIRECT_URI to the admin panel’s /admin/agent-requests/mcp/callback HTTPS URL.",
      );
    const u = new URL(raw);
    if (
      u.protocol !== "https:" ||
      u.username ||
      u.password ||
      u.search ||
      u.hash ||
      !u.pathname.endsWith("/admin/agent-requests/mcp/callback")
    )
      throw new BadRequestException("Invalid SARVAM_ADMIN_REDIRECT_URI.");
    return u.toString();
  }
  async status(actor: Actor) {
    await this.admin.superAdmin(actor);
    const s = await this.row();
    if (!s)
      throw new BadRequestException(
        "Apply the admin Sarvam provisioning migration first.",
      );
    return {
      version: s.version,
      sarvam_org_id: s.sarvam_org_id,
      workspace_id: s.workspace_id,
      template_app_id: s.template_app_id,
      has_api_key: !!s.api_key_ciphertext,
      api_key_last4: s.api_key_last4,
      connected:
        !!s.authoring_ciphertext &&
        new Date(s.expires_at).getTime() > Date.now() + 30000,
      expires_at: s.expires_at,
      redirect_uri: process.env.SARVAM_ADMIN_REDIRECT_URI ?? "",
      needs_reconnect:
        !!s.expires_at &&
        (!s.authoring_ciphertext ||
          new Date(s.expires_at).getTime() <= Date.now() + 30000),
    };
  }
  private async audit(
    db: Queryable,
    actor: Actor,
    action: string,
    target: string,
    detail: Json = {},
  ) {
    await db.query(
      "INSERT INTO admin_audit_log(id,admin_email,action,target_type,target_id,detail) VALUES($1,$2,$3,'sarvam',$4,$5)",
      [randomUUID(), actor.email, action, target, JSON.stringify(detail)],
    );
  }
  async save(actor: Actor, input: unknown) {
    await this.admin.superAdmin(actor);
    const v = settingsSchema.parse(input);
    await this.db.transaction(async (db) => {
      const s = (
        await db.query<Json>(
          "SELECT * FROM sarvam_admin_connection WHERE id=true FOR UPDATE",
        )
      ).rows[0];
      if (s.version !== v.version)
        throw new ConflictException(
          "Sarvam settings changed. Refresh before saving.",
        );
      const scopeChanged =
        s.sarvam_org_id !== v.sarvam_org_id ||
        s.workspace_id !== v.workspace_id;
      if (
        scopeChanged &&
        (
          await db.query(
            "SELECT 1 FROM sarvam_integrations WHERE setup_state->>'mode'='admin_mcp' LIMIT 1",
          )
        ).rows.length
      )
        throw new ConflictException(
          "This workspace is used by managed agents. Keep its IDs unchanged; reconnect to the same workspace.",
        );
      await db.query(
        `UPDATE sarvam_admin_connection SET sarvam_org_id=$1,workspace_id=$2,template_app_id=COALESCE($3,template_app_id),api_key_ciphertext=COALESCE($4,api_key_ciphertext),api_key_last4=COALESCE($5,api_key_last4),
        authoring_ciphertext=CASE WHEN $6 THEN NULL ELSE authoring_ciphertext END,expires_at=CASE WHEN $6 THEN NULL ELSE expires_at END,oauth_state_hash=NULL,oauth_pending_ciphertext=NULL,version=version+1,updated_at=now() WHERE id=true`,
        [
          v.sarvam_org_id,
          v.workspace_id,
          v.template_app_id ?? null,
          v.api_key ? sealSecret(v.api_key) : null,
          v.api_key?.slice(-4) ?? null,
          scopeChanged,
        ],
      );
      if (v.api_key && !scopeChanged) {
        await db.query(
          `UPDATE sarvam_integrations SET api_key_ciphertext=$1,api_key_last4=$2,version=version+1,updated_at=now()
          WHERE setup_state->>'mode'='admin_mcp' AND sarvam_org_id=$3 AND workspace_id=$4`,
          [
            sealSecret(v.api_key),
            v.api_key.slice(-4),
            v.sarvam_org_id,
            v.workspace_id,
          ],
        );
      }
      await this.audit(db, actor, "sarvam.settings_saved", "platform");
    });
    return this.status(actor);
  }
  async connect(actor: Actor) {
    await this.admin.superAdmin(actor);
    const s = await this.row(),
      redirect = this.redirectUri();
    if (!s?.sarvam_org_id || !s.workspace_id || !s.api_key_ciphertext)
      throw new BadRequestException(
        "Save the Sarvam workspace IDs and API key first.",
      );
    const client =
      process.env.SARVAM_OAUTH_CLIENT_ID ||
      s.oauth_client_id ||
      (await new SarvamAuthoring(this.provider.http).register(redirect))
        .client_id;
    if (typeof client !== "string" || !client)
      throw new BadRequestException(
        "Sarvam did not register the admin callback.",
      );
    const state = randomBytes(32).toString("base64url"),
      verifier = randomBytes(32).toString("base64url");
    const pending = {
      verifier,
      client,
      redirect,
      expires: Date.now() + 10 * 60 * 1000,
    };
    const saved = await this.db.query(
      "UPDATE sarvam_admin_connection SET oauth_state_hash=$1,oauth_pending_ciphertext=$2,oauth_client_id=$4,version=version+1,updated_at=now() WHERE id=true AND version=$3 RETURNING id",
      [hash(state), sealSecret(JSON.stringify(pending)), s.version, client],
    );
    if (!saved.rows.length)
      throw new ConflictException("Sarvam settings changed. Retry Connect.");
    const u = new URL(`${MCP}/authorize`);
    u.search = new URLSearchParams({
      client_id: client,
      redirect_uri: redirect,
      response_type: "code",
      state,
      code_challenge: hashChallenge(verifier),
      code_challenge_method: "S256",
      resource: MCP,
    }).toString();
    await this.audit(
      this.db,
      actor,
      "sarvam.authorization_started",
      "platform",
    );
    return { authorization_url: u.toString() };
  }
  async callback(actor: Actor, input: unknown) {
    await this.admin.superAdmin(actor);
    const q = z
      .object({
        state: z.string().min(20).max(200),
        code: z.string().min(1).max(4000).optional(),
        error: z.string().max(200).optional(),
        iss: z.literal(MCP).optional(),
      })
      .strict()
      .parse(input);
    const s = await this.row();
    if (s?.oauth_state_hash !== hash(q.state) || !s.oauth_pending_ciphertext)
      throw new BadRequestException(
        "Authorization is invalid or already used. Reconnect Sarvam.",
      );
    const pending = JSON.parse(openSecret(s.oauth_pending_ciphertext));
    if (pending.expires < Date.now())
      throw new BadRequestException("Sign-in expired. Reconnect Sarvam.");
    const claimed = await this.db.query(
      "UPDATE sarvam_admin_connection SET oauth_state_hash=NULL,oauth_pending_ciphertext=NULL,version=version+1 WHERE id=true AND oauth_state_hash=$1 AND version=$2 RETURNING version",
      [hash(q.state), s.version],
    );
    if (!claimed.rows.length)
      throw new ConflictException("Authorization already processed.");
    if (q.error || !q.code)
      throw new BadRequestException(
        "Sarvam sign-in was declined. Reconnect when ready.",
      );
    const credential = await new SarvamAuthoring(this.provider.http).exchange({
      grant_type: "authorization_code",
      code: q.code,
      client_id: pending.client,
      redirect_uri: pending.redirect,
      code_verifier: pending.verifier,
    });
    const ttl = Math.min(Number(credential.expires_in ?? 86400), 86400);
    if (!Number.isFinite(ttl) || ttl < 60)
      throw new BadRequestException(
        "Sarvam returned an invalid authorization lifetime.",
      );
    const result = await this.db.query(
      "UPDATE sarvam_admin_connection SET authoring_ciphertext=$1,expires_at=$2,version=version+1,updated_at=now() WHERE id=true AND version=$3 RETURNING id",
      [
        sealSecret(credential.access_token),
        new Date(Date.now() + ttl * 1000).toISOString(),
        claimed.rows[0].version,
      ],
    );
    if (!result.rows.length)
      throw new ConflictException(
        "Settings changed during sign-in. Reconnect again.",
      );
    await this.audit(this.db, actor, "sarvam.authorized", "platform");
    return this.status(actor);
  }
  private async remote(s: Json, services?: readonly CallService[]) {
    if (
      !s?.authoring_ciphertext ||
      new Date(s.expires_at).getTime() <= Date.now() + 30000
    )
      throw new SarvamAuthorizationExpired();
    const r = new SarvamProvisioningRemote(
      new SarvamAuthoring(
        this.provider.http,
        openSecret(s.authoring_ciphertext),
      ),
      { services },
    );
    try {
      await r.inspect();
    } catch (e) {
      await this.expired(e, s);
      throw e;
    }
    return r;
  }
  private async expired(error: unknown, s: Json) {
    if (error instanceof SarvamAuthorizationExpired)
      await this.db.query(
        "UPDATE sarvam_admin_connection SET authoring_ciphertext=NULL,version=version+1 WHERE id=true AND authoring_ciphertext=$1",
        [s.authoring_ciphertext],
      );
  }
  async inventory(actor: Actor) {
    await this.admin.superAdmin(actor);
    const s = await this.row();
    try {
      const remote = await this.remote(s),
        inventory = await remote.inventory(),
        agents = await remote.listAgents();
      if (agents.pagination?.more)
        throw new BadRequestException(
          "Incomplete agent list. Narrow the workspace before selecting a template.",
        );
      const reserved = (
        await this.db.query<Json>(
          "SELECT organization_id,phone_number FROM sarvam_integrations WHERE phone_number<>''",
        )
      ).rows;
      return {
        templates: (agents.items ?? []).map((a: Json) => ({
          id: a.app_id ?? a.id,
          name: a.app_name ?? a.name ?? a.app_id ?? a.id,
        })),
        numbers: inventory.numbers.map((n) => ({
          ...n,
          assigned:
            reserved.some((r) => r.phone_number === n.phone_number) ||
            inventory.deployments.some((d: Json) =>
              (d.connection_configs ?? []).some((c: Json) =>
                c.phone_numbers?.includes(n.phone_number),
              ),
            ),
        })),
      };
    } catch (e) {
      await this.expired(e, s);
      throw e;
    }
  }
  async job(actor: Actor, orgId: string) {
    await this.admin.superAdmin(actor);
    const org = z.uuid().parse(orgId);
    const s = (
      await this.db.query<Json>(
        "SELECT setup_state,setup_error,setup_status,app_id,phone_number,deployment_id FROM sarvam_integrations WHERE organization_id=$1",
        [org],
      )
    ).rows[0];
    return {
      automatic: s?.setup_state?.mode === "admin_mcp",
      step: s?.setup_state?.step ?? "",
      error: s?.setup_error ?? "",
      done: s?.setup_state?.step === "done",
      app_id: s?.app_id ?? "",
      phone_number: s?.phone_number ?? "",
      deployment_id: s?.deployment_id ?? "",
    };
  }
  async approve(actor: Actor, orgId: string, input: unknown) {
    await this.admin.superAdmin(actor);
    const org = z.uuid().parse(orgId);
    const v = z
      .object({
        version: z.number().int().positive(),
        approved_services: serviceSelection,
        phone_number: z.string().regex(/^\+[1-9][0-9]{7,14}$/),
        connection_id: identifier,
      })
      .strict()
      .parse(input);
    const platform = await this.row(),
      remote = await this.remote(platform);
    if (!platform.template_app_id)
      throw new BadRequestException(
        "Select the platform booking template first.",
      );
    const template = await remote.agent(platform.template_app_id);
    const c = template.config,
      ac = c?.llm_config?.agent_config;
    if (
      c?.org_id !== platform.sarvam_org_id ||
      c?.workspace_id !== platform.workspace_id
    )
      throw new BadRequestException(
        "Reconnect MCP to the configured organization and workspace.",
      );
    if (
      !ac?.initial_state_name ||
      Object.keys(ac.states ?? {}).length !== 1 ||
      !Array.isArray(template.tools) ||
      template.tools.length
    )
      throw new BadRequestException(
        "Use a single-state template with no tools. Its voice/language settings will be copied; BookingOS adds the managed tools.",
      );
    const inv = await remote.inventory();
    if (
      !inv.numbers.some(
        (n) =>
          n.phone_number === v.phone_number &&
          n.connection_id === v.connection_id,
      )
    )
      throw new BadRequestException(
        "Select a number available in this Sarvam workspace.",
      );
    if (
      inv.deployments.some((d: Json) =>
        (d.connection_configs ?? []).some((x: Json) =>
          x.phone_numbers?.includes(v.phone_number),
        ),
      )
    )
      throw new ConflictException(
        "This number already belongs to a Sarvam deployment. Select a free number.",
      );
    if (!Number.isInteger(c.app_version))
      throw new BadRequestException(
        "Sarvam did not return a template version.",
      );
    const key = "bkv_" + randomBytes(32).toString("base64url");
    await this.db
      .transaction(async (db) => {
        const activePlatform = (
          await db.query<Json>(
            "SELECT version FROM sarvam_admin_connection WHERE id=true FOR SHARE",
          )
        ).rows[0];
        if (activePlatform.version !== platform.version)
          throw new ConflictException(
            "Platform connection changed. Refresh before approving.",
          );
        await this.provider.ensureManaged(db, org);
        const s = (
          await db.query<Json>(
            "SELECT * FROM sarvam_integrations WHERE organization_id=$1 FOR UPDATE",
            [org],
          )
        ).rows[0];
        const r = (
          await db.query<Json>(
            "SELECT * FROM agent_call_requests WHERE organization_id=$1 FOR UPDATE",
            [org],
          )
        ).rows[0];
        if (!r) throw new NotFoundException("Request not found.");
        if (r.version !== v.version)
          throw new ConflictException(
            "Request changed. Refresh before approving.",
          );
        if (
          !["requested", "in_review", "setting_up"].includes(r.status) ||
          s.app_id ||
          s.setup_state?.mode === "admin_mcp"
        )
          throw new ConflictException(
            "A connection or setup already exists. Resume it instead of approving again.",
          );
        if (v.approved_services.some((x) => !r.requested_services.includes(x)))
          throw new BadRequestException(
            "Approve only services requested by the client.",
          );
        if (
          (
            await db.query(
              "SELECT 1 FROM sarvam_integrations WHERE organization_id<>$1 AND phone_number=$2",
              [org, v.phone_number],
            )
          ).rows.length
        )
          throw new ConflictException(
            "This number is reserved by another organization.",
          );
        const state = {
          mode: "admin_mcp",
          step: "create",
          template_id: platform.template_app_id,
          template_version: c.app_version,
          agent_name: `BookingOS ${org.replace(/-/g, "")}_${randomBytes(4).toString("hex")}`,
          initial: ac.initial_state_name,
          connection_id: v.connection_id,
          secret_name: `bookingos_${org.replace(/-/g, "")}`,
          base: this.toolBase(),
          scope: [platform.sarvam_org_id, platform.workspace_id],
          services: v.approved_services,
        };
        await db.query(
          `UPDATE sarvam_integrations SET app_id=$2,sarvam_org_id=$3,workspace_id=$4,phone_number=$5,api_key_ciphertext=$6,api_key_last4=$7,tool_key_ciphertext=$8,tool_key_hash=$9,tool_key_prefix=$10,enabled=false,verified_at=NULL,verified_by='',setup_status='connecting',setup_state=$11,setup_error='',version=version+1 WHERE organization_id=$1`,
          [
            org,
            `bookingos_${org.replace(/-/g, "")}`,
            platform.sarvam_org_id,
            platform.workspace_id,
            v.phone_number,
            platform.api_key_ciphertext,
            platform.api_key_last4,
            sealSecret(key),
            hashToolKey(key),
            key.slice(0, 10),
            JSON.stringify(state),
          ],
        );
        await db.query("UPDATE memberships SET active=false WHERE id=$1", [
          s.membership_id,
        ]);
        await db.query(
          "UPDATE agent_call_requests SET approved_services=$2,status='setting_up',user_message='We are setting up your call service.',version=version+1,updated_at=now() WHERE organization_id=$1",
          [org, v.approved_services],
        );
        await this.audit(db, actor, "sarvam.agent_approved", org, {
          services: v.approved_services,
          phone_number: v.phone_number,
        });
      })
      .catch((error: unknown) => {
        if ((error as { code?: string })?.code === "23505")
          throw new ConflictException(
            "The number or agent was reserved by another request. Refresh and choose an available number.",
          );
        throw error;
      });
    return this.job(actor, org);
  }
  private toolBase() {
    const base =
      this.workspace.publicAppUrl || process.env.PUBLIC_APP_URL || "";
    const u = new URL(base);
    if (
      u.protocol !== "https:" ||
      u.username ||
      u.password ||
      u.search ||
      u.hash
    )
      throw new BadRequestException(
        "Configure the public HTTPS API URL first.",
      );
    return base.replace(/\/$/, "") + "/voice/v1";
  }
  async resume(actor: Actor, orgId: string) {
    await this.admin.superAdmin(actor);
    const org = z.uuid().parse(orgId),
      lease = randomUUID();
    const s = (
      await this.db.query<Json>(
        `UPDATE sarvam_integrations SET setup_lease=$2,setup_lease_until=now()+interval '90 seconds' WHERE organization_id=$1 AND setup_state->>'mode'='admin_mcp' AND setup_state->>'step'<>'done' AND (setup_lease_until IS NULL OR setup_lease_until<now()) RETURNING *`,
        [org, lease],
      )
    ).rows[0];
    if (!s) {
      const job = await this.job(actor, org);
      if (job.done) return job;
      throw new ConflictException(
        "Setup is already running, or no automatic setup exists. Refresh shortly.",
      );
    }
    let platform: Json | undefined;
    try {
      const r = (
        await this.db.query<Json>(
          "SELECT status,approved_services FROM agent_call_requests WHERE organization_id=$1",
          [org],
        )
      ).rows[0];
      if (r?.status !== "setting_up")
        throw new ConflictException(
          "Setup is on hold. Set the request to Setting up before resuming.",
        );
      const state = s.setup_state,
        services = serviceSelection.parse(
          state.services ?? r.approved_services,
        );
      if (
        JSON.stringify([...services].sort()) !==
        JSON.stringify([...(r.approved_services ?? [])].sort())
      )
        throw new ConflictException(
          "Approved services changed. Review setup before resuming.",
        );
      platform = await this.row();
      const remote = await this.remote(platform, services);
      if (
        state.scope[0] !== platform.sarvam_org_id ||
        state.scope[1] !== platform.workspace_id
      )
        throw new ConflictException(
          "This setup belongs to another Sarvam workspace.",
        );
      const next = { ...state, services };
      if (state.step === "create") {
        const listed = await remote.listAgents();
        if (listed.pagination?.more)
          throw new BadRequestException(
            "Agent list is incomplete; setup cannot safely recover a previous creation.",
          );
        const matches = (listed.items ?? []).filter(
          (a: Json) => (a.app_name ?? a.name) === state.agent_name,
        );
        if (matches.length > 1)
          throw new ConflictException(
            "More than one agent has this setup's unique name. Review Sarvam before resuming.",
          );
        const app = matches.length
          ? (matches[0].app_id ?? matches[0].id)
          : await remote.createAgent(
              state.agent_name,
              state.template_id,
              state.template_version,
            );
        if (typeof app !== "string" || !app)
          throw new BadRequestException(
            "Sarvam did not return the client agent ID.",
          );
        const claimed = (
          await this.db.query(
            "SELECT 1 FROM sarvam_integrations WHERE organization_id<>$1 AND sarvam_org_id=$2 AND workspace_id=$3 AND app_id=$4",
            [org, ...state.scope, app],
          )
        ).rows.length;
        if (claimed)
          throw new ConflictException(
            "This agent is assigned to another client.",
          );
        const created = await remote.agent(app);
        if (
          created.config?.org_id !== state.scope[0] ||
          created.config?.workspace_id !== state.scope[1] ||
          created.config?.llm_config?.agent_config?.initial_state_name !==
            state.initial
        )
          throw new BadRequestException(
            "Created agent does not match the configured workspace and template.",
          );
        next.app_id = app;
        next.step = "variables";
      } else if (state.step === "variables") {
        await remote.configureAgent(
          s.app_id,
          {
            llm_config: {
              agent_config: {
                agent_variables: {
                  bookingos_spaces: {
                    name: "bookingos_spaces",
                    value:
                      "The call service is unavailable until its live catalog has loaded. Direct callers to venue staff.",
                    description: "Live spaces loaded at call start",
                    is_agent_updatable: false,
                    needs_initial_value: true,
                    update_post_interaction: false,
                  },
                },
                states: {
                  [state.initial]: {
                    tool_names: [],
                    agent_variables_in_context: ["bookingos_spaces"],
                  },
                },
              },
            },
          },
          "The venue's call service is being configured. Direct callers to venue staff until setup is complete.",
        );
        next.step = "secret";
      } else if (state.step === "secret") {
        next.secret_id = await remote.secret(
          state.secret_name,
          openSecret(s.tool_key_ciphertext),
        );
        next.step = `tool_${remote.toolIndexes[0]}`;
      } else if (/^tool_[0-6]$/.test(state.step)) {
        const index = Number(state.step.slice(5));
        if (remote.toolIndexes.includes(index))
          await remote.toolAt(index, s.app_id, state.base, state.secret_id);
        const following = remote.toolIndexes.find(
          (candidate) => candidate > index,
        );
        next.step = following === undefined ? "prompt" : `tool_${following}`;
      } else if (state.step === "prompt") {
        await remote.enable(s.app_id);
        await remote.configureAgent(
          s.app_id,
          {
            llm_config: {
              agent_config: {
                states: {
                  [state.initial]: {
                    tool_names: remote.toolNames.filter((name) =>
                      TOOLS.slice(1).some((tool) => tool[0] === name),
                    ),
                    agent_variables_in_context: ["bookingos_spaces"],
                  },
                },
              },
            },
          },
          remote.prompt,
        );
        next.step = "verify_tools";
      } else if (state.step === "verify_tools") {
        const c = await remote.verify(
          s.app_id,
          state.scope,
          state.initial,
          state.base,
          state.secret_id,
        );
        next.draft_version = c.app_version;
        next.step = "commit";
      } else if (state.step === "commit") {
        const c = await remote.verify(
          s.app_id,
          state.scope,
          state.initial,
          state.base,
          state.secret_id,
          state.draft_version,
        );
        const latest =
          c.status === "committed" ? c : (await remote.agent(s.app_id)).config;
        if (latest.app_version !== state.draft_version)
          throw new ConflictException(
            "Agent draft changed. Review it before resuming setup.",
          );
        next.draft_version = await remote.commit(s.app_id, state.draft_version);
        next.step = "deploy";
      } else if (state.step === "deploy") {
        const inventory = await remote.inventory();
        const same = (d: Json) =>
          d.app_id === s.app_id &&
          d.app_version === state.draft_version &&
          (d.connection_configs ?? []).some(
            (c: Json) =>
              c.connection_id === state.connection_id &&
              c.phone_numbers?.includes(s.phone_number),
          );
        let deployment = inventory.deployments.find(same);
        if (!deployment) {
          if (
            inventory.deployments.some((d: Json) =>
              (d.connection_configs ?? []).some((c: Json) =>
                c.phone_numbers?.includes(s.phone_number),
              ),
            )
          )
            throw new ConflictException(
              "The selected number is now used by another deployment. Review Sarvam before retrying.",
            );
          deployment = await remote.deploy(
            s.app_id,
            state.draft_version,
            state.connection_id,
            s.phone_number,
          );
        }
        if (!same(deployment) || typeof deployment.deployment_id !== "string")
          throw new BadRequestException(
            "Sarvam returned a deployment that does not match this client and number.",
          );
        next.deployment_id = deployment.deployment_id;
        next.step = "verify_deployment";
      } else if (state.step === "verify_deployment") {
        const owner = (
          await this.db.query<Json>(
            "SELECT user_id,email,display_name FROM memberships WHERE organization_id=$1 AND role='owner' AND active LIMIT 1",
            [org],
          )
        ).rows[0];
        if (!owner)
          throw new NotFoundException("Organization owner not found.");
        await Promise.all([
          this.provider.verifyDeployment({
            ...s,
            deployment_id: state.deployment_id,
          }),
          this.provider.test({
            uid: owner.user_id,
            email: owner.email,
            name: owner.display_name,
          }),
        ]);
        next.step = "done";
      } else
        throw new BadRequestException("Unknown setup step. Contact support.");
      await this.db.transaction(async (db) => {
        const current = (
          await db.query<Json>(
            "SELECT * FROM sarvam_integrations WHERE organization_id=$1 FOR UPDATE",
            [org],
          )
        ).rows[0];
        if (current.setup_lease !== lease)
          throw new ConflictException(
            "Setup was superseded. Refresh before resuming.",
          );
        const req = (
          await db.query<Json>(
            "SELECT status,approved_services,requested_services FROM agent_call_requests WHERE organization_id=$1 FOR UPDATE",
            [org],
          )
        ).rows[0];
        if (req.status !== "setting_up")
          throw new ConflictException("Setup was placed on hold.");
        if (
          !req.approved_services.length ||
          JSON.stringify([...req.approved_services].sort()) !==
            JSON.stringify([...services].sort()) ||
          req.approved_services.some(
            (x: string) => !req.requested_services.includes(x),
          )
        )
          throw new ConflictException(
            "The requested services changed. Review the approval before continuing.",
          );
        await db.query(
          `UPDATE sarvam_integrations SET setup_state=$3,setup_error='',setup_status=$4,deployment_id=COALESCE($5,deployment_id),verified_at=CASE WHEN $6 THEN now() ELSE verified_at END,verified_by=CASE WHEN $6 THEN $7 ELSE verified_by END,app_id=COALESCE($8,app_id),version=version+1,updated_at=now() WHERE organization_id=$1 AND setup_lease=$2`,
          [
            org,
            lease,
            JSON.stringify(next),
            next.step === "done" ? "configured" : "connecting",
            next.deployment_id ?? null,
            next.step === "done",
            actor.email,
            next.app_id ?? null,
          ],
        );
        if (next.step === "done") {
          await db.query(
            "UPDATE agent_call_requests SET status='active',user_message='Your call service is connected. Choose spaces and turn it on.',version=version+1,updated_at=now() WHERE organization_id=$1",
            [org],
          );
          await this.audit(db, actor, "sarvam.agent_connected", org, {
            app_id: s.app_id,
            deployment_id: next.deployment_id,
          });
        }
      });
      return this.job(actor, org);
    } catch (e) {
      if (platform) await this.expired(e, platform);
      const message =
        e instanceof BadRequestException || e instanceof ConflictException
          ? e.message
          : "Setup did not finish. Reconnect if needed, then resume; completed steps are saved.";
      await this.db.query(
        "UPDATE sarvam_integrations SET setup_error=$3,setup_status='failed' WHERE organization_id=$1 AND setup_lease=$2",
        [org, lease, message.slice(0, 500)],
      );
      throw e;
    } finally {
      await this.db.query(
        "UPDATE sarvam_integrations SET setup_lease=NULL,setup_lease_until=NULL WHERE organization_id=$1 AND setup_lease=$2",
        [org, lease],
      );
    }
  }
}
function hashChallenge(verifier: string) {
  return createHash("sha256").update(verifier).digest("base64url");
}
