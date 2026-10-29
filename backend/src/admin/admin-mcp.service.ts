import { Injectable } from "@nestjs/common";
import { DomainHttpError } from "../common/domain-error";
import { createHmac, randomBytes, randomUUID } from "node:crypto";
import { z } from "zod";
import type { Actor } from "../common/auth.guard";
import { Database, Queryable } from "../common/database";
import { WorkspaceService } from "../workspace/workspace.service";
import { SarvamService } from "../sarvam/sarvam.service";
import { managedBookingSpecification } from "../sarvam/sarvam-provisioning-remote";
import { hashToolKey, openSecret, sealSecret } from "../sarvam/sarvam-secrets";
import { serviceSelection } from "../agent-calls/agent-call-policy";
import { requireAdminMcpScope, AdminMcpScope } from "./admin-mcp-auth";

type Json = Record<string, any>;
const identifier = z.string().regex(/^[A-Za-z0-9_-]{1,200}$/);
const version = z.number().int().nonnegative();
const planSchema = z
  .object({
    principal_id: z.uuid(),
    organization_id: z.uuid(),
    request_id: z.uuid(),
    request_version: z.number().int().positive(),
    integration_version: version,
    approved_services: serviceSelection,
    phone_number: z.string().regex(/^\+[1-9][0-9]{7,14}$/),
    connection_id: identifier,
    sarvam_org_id: identifier,
    workspace_id: identifier,
    language: z.string().regex(/^[a-z]{2}(?:-[A-Z]{2})?$/),
    expires_at: z.iso.datetime(),
    template_agent_id: identifier,
    template_version: z.number().int().positive(),
    template_language: z.string().regex(/^[a-z]{2}(?:-[A-Z]{2})?$/),
    template_language_path: z
      .string()
      .regex(/^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*){0,12}$/),
    template_language_value: z
      .string()
      .trim()
      .min(1)
      .max(80)
      .regex(/^[A-Za-z0-9_-]+$/),
    initial_state: z
      .string()
      .trim()
      .min(1)
      .max(100)
      .regex(/^[^\u0000-\u001f]+$/),
  })
  .strict();
const resourcesSchema = z
  .object({
    agent_id: identifier.optional(),
    secret_id: identifier.optional(),
    draft_version: z.number().int().positive().optional(),
    agent_version: z.number().int().positive().optional(),
    deployment_id: identifier.optional(),
  })
  .strict();
const receiptSchema = z
  .object({
    tools_verified: z.literal(true).optional(),
    language_verified: z.literal(true).optional(),
    credential_verified: z.literal(true).optional(),
    configuration_hash: z
      .string()
      .regex(/^[a-f0-9]{64}$/)
      .optional(),
  })
  .strict();
const leaseInput = z.object({
  job_id: z.uuid(),
  version: z.number().int().positive(),
  lease_id: z.uuid(),
});
const safeCodes = [
  "PROVIDER_AUTH_REQUIRED",
  "PROVIDER_CAPABILITY_MISSING",
  "OUTCOME_UNKNOWN",
  "VERIFICATION_FAILED",
  "PROVIDER_ERROR",
  "STALE_PLAN",
] as const;
function planDigest(value: unknown) {
  const key = Buffer.from(process.env.BOOKING_SECRETS_KEY ?? "", "base64");
  if (key.length !== 32)
    fail(
      "CONFIGURATION_REQUIRED",
      503,
      "Configure server secret storage before preparing setup.",
    );
  return createHmac("sha256", key)
    .update("bookingos-admin-mcp-plan-v1\n" + JSON.stringify(value))
    .digest("hex");
}
export class AdminMcpError extends DomainHttpError {
  constructor(
    readonly code: string,
    status: number,
    message: string,
  ) {
    super(code, status, message);
  }
}
function fail(code: string, status: number, message: string): never {
  throw new AdminMcpError(code, status, message);
}
function parse<T>(schema: z.ZodType<T>, body: unknown): T {
  const p = schema.safeParse(body);
  if (!p.success) fail("VALIDATION_ERROR", 422, "Invalid admin MCP request.");
  return p.data;
}

/** Durable metadata/checkpoints; provider credentials never enter safe job output. */
@Injectable()
export class AdminMcpService {
  constructor(
    private readonly db: Database,
    private readonly provider: SarvamService,
    private readonly workspace: WorkspaceService,
  ) {}

  private principal(actor: Actor, scope: AdminMcpScope = "voice:write") {
    return requireAdminMcpScope(actor, scope);
  }
  private org(value: string) {
    return parse(z.uuid(), value);
  }
  private async audit(
    db: Queryable,
    actor: Actor,
    action: string,
    org: string,
    detail: Json = {},
  ) {
    const p = this.principal(
      actor,
      action === "credential" ? "voice:credentials:install" : "voice:write",
    );
    await db.query(
      "INSERT INTO admin_audit_log(id,admin_email,action,target_type,target_id,detail) VALUES($1,$2,$3,'organization',$4,$5)",
      [
        randomUUID(),
        actor.email,
        `admin_mcp.${action}`,
        org,
        JSON.stringify({ principal_id: p.id, ...detail }),
      ],
    );
  }
  private async request(db: Queryable, org: string, lock = false) {
    const r = (
      await db.query<Json>(
        `SELECT r.*,o.name AS organization_name FROM agent_call_requests r JOIN organizations o ON o.id=r.organization_id WHERE r.organization_id=$1${lock ? " FOR UPDATE OF r" : ""}`,
        [org],
      )
    ).rows[0];
    if (!r) fail("NOT_FOUND", 404, "Call-service request not found.");
    return r;
  }
  private async integration(db: Queryable, org: string, lock = false) {
    return (
      await db.query<Json>(
        `SELECT * FROM sarvam_integrations WHERE organization_id=$1${lock ? " FOR UPDATE" : ""}`,
        [org],
      )
    ).rows[0];
  }
  private baseUrl() {
    const raw = (
      this.workspace.publicAppUrl ||
      process.env.PUBLIC_APP_URL ||
      ""
    ).replace(/\/$/, "");
    let u: URL;
    try {
      u = new URL(raw);
    } catch {
      fail(
        "CONFIGURATION_REQUIRED",
        503,
        "Configure the public HTTPS API URL.",
      );
    }
    if (
      u.protocol !== "https:" ||
      u.username ||
      u.password ||
      u.search ||
      u.hash
    )
      fail(
        "CONFIGURATION_REQUIRED",
        503,
        "Configure the public HTTPS API URL.",
      );
    return raw + "/voice/v1";
  }
  private spec(plan: Json) {
    return managedBookingSpecification(plan.approved_services, {
      baseUrl: this.baseUrl(),
      secretId: "${BOOKINGOS_SECRET_ID}",
      language: plan.language,
    });
  }
  private safeJob(s: Json | undefined) {
    const state = s?.setup_state;
    if (state?.mode !== "codex_mcp") return null;
    return {
      organization_id: s!.organization_id,
      job_id: state.job_id,
      version: s!.version,
      step: state.step,
      done: state.step === "done",
      status: s!.setup_status,
      plan_id: state.plan_id,
      plan: state.plan,
      resources: state.resources,
      receipt: state.receipts,
      credential_operation: state.credential_operation ?? null,
      agent_name: state.agent_name,
      secret_name: state.secret_name,
      spec: state.spec,
      tool_count: state.spec.tools.length,
      error_code: s!.setup_error || "",
      lease_until: s!.setup_lease_until ?? null,
      client_enabled: !!s!.enabled,
    };
  }
  private state(
    actor: Actor,
    s: Json | undefined,
    jobId: string,
    scope: AdminMcpScope = "voice:write",
  ) {
    const p = this.principal(actor, scope),
      st = s?.setup_state;
    if (st?.mode !== "codex_mcp" || st.job_id !== jobId)
      fail("NOT_FOUND", 404, "Connection job not found.");
    if (st.principal_id !== p.id)
      fail(
        "FORBIDDEN",
        403,
        "This connection job belongs to another automation principal.",
      );
    return st;
  }
  private leased(
    actor: Actor,
    s: Json | undefined,
    input: { job_id: string; version?: number; lease_id: string },
    scope: AdminMcpScope = "voice:write",
  ) {
    const st = this.state(actor, s, input.job_id, scope);
    if (input.version !== undefined && s!.version !== input.version)
      fail(
        "STALE_PLAN",
        409,
        "Connection changed. Read the saved job before retrying.",
      );
    if (
      s!.setup_lease !== input.lease_id ||
      !s!.setup_lease_until ||
      new Date(s!.setup_lease_until).getTime() <= Date.now()
    )
      fail(
        "LEASE_EXPIRED",
        409,
        "The connection step lease expired. Reconcile before retrying.",
      );
    return st;
  }
  private async assertRequest(db: Queryable, org: string, state: Json) {
    const req = await this.request(db, org, true);
    if (
      req.id !== state.plan.request_id ||
      req.version !== state.request_version ||
      req.status !== "setting_up" ||
      JSON.stringify([...req.approved_services].sort()) !==
        JSON.stringify([...state.plan.approved_services].sort()) ||
      state.plan.approved_services.some(
        (x: string) => !req.requested_services.includes(x),
      )
    )
      fail(
        "STALE_PLAN",
        409,
        "The request or approved services changed. Review setup before continuing.",
      );
    return req;
  }
  async list(actor: Actor, query: Record<string, string>) {
    this.principal(actor, "voice:read");
    const name = String(query.name ?? "")
        .trim()
        .slice(0, 100),
      status = query.status || null;
    if (
      status &&
      ![
        "requested",
        "in_review",
        "setting_up",
        "active",
        "paused",
        "rejected",
      ].includes(status)
    )
      fail("VALIDATION_ERROR", 422, "Invalid request status.");
    const limit = Math.min(
      Math.max(Number.parseInt(query.limit ?? "100", 10) || 100, 1),
      100,
    );
    const result = await this.db.query<Json>(
      `SELECT r.id,r.organization_id,o.name AS organization_name,r.status,r.version,r.requested_services,r.approved_services,r.note,r.updated_at FROM agent_call_requests r JOIN organizations o ON o.id=r.organization_id WHERE ($1::text='' OR position(lower($1) in lower(o.name))>0) AND ($2::text IS NULL OR r.status=$2) ORDER BY r.updated_at DESC,r.id LIMIT $3`,
      [name, status, limit + 1],
    );
    return {
      requests: result.rows.slice(0, limit),
      has_more: result.rows.length > limit,
    };
  }
  async get(actor: Actor, organizationId: string) {
    this.principal(actor, "voice:read");
    const org = this.org(organizationId),
      r = await this.request(this.db, org),
      s = await this.integration(this.db, org);
    return {
      organization_id: org,
      organization_name: r.organization_name,
      request: {
        id: r.id,
        status: r.status,
        version: r.version,
        requested_services: r.requested_services,
        approved_services: r.approved_services,
        note: r.note,
      },
      connection: {
        version: s?.version ?? 0,
        enabled: s?.enabled ?? false,
        has_api_key: !!s?.api_key_ciphertext,
        has_tool_key: !!s?.tool_key_hash,
        sarvam_org_id: s?.sarvam_org_id ?? "",
        workspace_id: s?.workspace_id ?? "",
        app_id: s?.app_id ?? "",
        phone_number: s?.phone_number ?? "",
        deployment_id: s?.deployment_id ?? "",
        verified_at: s?.verified_at ?? null,
      },
      job: this.safeJob(s),
    };
  }
  async prepare(actor: Actor, organizationId: string, body: unknown) {
    const principal = this.principal(actor),
      org = this.org(organizationId),
      v = parse(
        planSchema.omit({
          principal_id: true,
          organization_id: true,
          request_id: true,
          expires_at: true,
        }),
        body,
      );
    const r = await this.request(this.db, org),
      s = await this.integration(this.db, org);
    if (
      r.version !== v.request_version ||
      (s?.version ?? 0) !== v.integration_version
    )
      fail(
        "STALE_PLAN",
        409,
        "Request or connection changed. Prepare a new plan.",
      );
    if (
      !["requested", "in_review", "setting_up"].includes(r.status) ||
      s?.app_id ||
      s?.setup_state?.mode === "admin_mcp" ||
      s?.setup_state?.mode === "codex_mcp"
    )
      fail(
        "CONNECTION_EXISTS",
        409,
        "A connection or setup already exists. Read or resume it instead.",
      );
    if (
      s?.setup_lease_until &&
      new Date(s.setup_lease_until).getTime() > Date.now()
    )
      fail("LEASE_BUSY", 409, "Another connection action is still running.");
    if (v.approved_services.some((x) => !r.requested_services.includes(x)))
      fail("FORBIDDEN", 403, "Approve only services requested by the client.");
    if (v.template_language !== v.language)
      fail(
        "PROVIDER_CAPABILITY_MISSING",
        409,
        "The template language must match the requested agent language.",
      );
    if (
      (
        await this.db.query(
          "SELECT 1 FROM sarvam_integrations WHERE organization_id<>$1 AND phone_number=$2",
          [org, v.phone_number],
        )
      ).rows.length
    )
      fail(
        "NUMBER_IN_USE",
        409,
        "This number is assigned to another organization.",
      );
    const plan = planSchema.parse({
      principal_id: principal.id,
      organization_id: org,
      request_id: r.id,
      ...v,
      expires_at: new Date(Date.now() + 15 * 60_000).toISOString(),
    });
    return {
      plan_id: planDigest(plan),
      expires_at: plan.expires_at,
      plan,
      spec: this.spec(plan),
    };
  }
  async start(actor: Actor, organizationId: string, body: unknown) {
    const p = this.principal(actor),
      org = this.org(organizationId),
      v = parse(
        z
          .object({
            plan_id: z.string().regex(/^[a-f0-9]{64}$/),
            plan: planSchema,
            idempotency_key: z.uuid(),
            workspace_api_key: z.string().min(8).max(500).optional(),
          })
          .strict(),
        body,
      );
    if (
      v.plan.organization_id !== org ||
      v.plan.principal_id !== p.id ||
      v.plan_id !== planDigest(v.plan)
    )
      fail(
        "STALE_PLAN",
        409,
        "The setup plan does not match this request or operator.",
      );
    await this.db
      .transaction(async (db) => {
        await db.query("SELECT id FROM organizations WHERE id=$1 FOR UPDATE", [
          org,
        ]);
        const before = await this.integration(db, org, true),
          existing = before?.setup_state;
        if (existing?.mode === "codex_mcp") {
          if (
            existing.idempotency_key === v.idempotency_key &&
            existing.plan_id === v.plan_id &&
            existing.principal_id === p.id
          )
            return;
          fail(
            "CONNECTION_EXISTS",
            409,
            "A connection job already exists. Resume it instead.",
          );
        }
        if (
          new Date(v.plan.expires_at).getTime() <= Date.now() ||
          new Date(v.plan.expires_at).getTime() > Date.now() + 15 * 60_000
        )
          fail("STALE_PLAN", 409, "The setup plan expired. Prepare it again.");
        const r = await this.request(db, org, true);
        if (
          before?.setup_lease_until &&
          new Date(before.setup_lease_until).getTime() > Date.now()
        )
          fail(
            "LEASE_BUSY",
            409,
            "Another connection action is still running.",
          );
        if (
          r.id !== v.plan.request_id ||
          r.version !== v.plan.request_version ||
          (before?.version ?? 0) !== v.plan.integration_version ||
          !["requested", "in_review", "setting_up"].includes(r.status) ||
          before?.app_id ||
          before?.setup_state?.mode === "admin_mcp"
        )
          fail(
            "STALE_PLAN",
            409,
            "Request or connection changed. Prepare a new plan.",
          );
        if (
          v.plan.approved_services.some(
            (x) => !r.requested_services.includes(x),
          )
        )
          fail(
            "FORBIDDEN",
            403,
            "Approve only services requested by the client.",
          );
        if (
          (
            await db.query(
              "SELECT 1 FROM sarvam_integrations WHERE organization_id<>$1 AND phone_number=$2",
              [org, v.plan.phone_number],
            )
          ).rows.length
        )
          fail(
            "NUMBER_IN_USE",
            409,
            "This number is assigned to another organization.",
          );
        const platform = (
          await db.query<Json>(
            "SELECT sarvam_org_id,workspace_id,api_key_ciphertext,api_key_last4 FROM sarvam_admin_connection WHERE id=true FOR SHARE",
          )
        ).rows[0];
        const saved =
          platform?.sarvam_org_id === v.plan.sarvam_org_id &&
          platform?.workspace_id === v.plan.workspace_id
            ? platform
            : undefined;
        const ciphertext = v.workspace_api_key
          ? sealSecret(v.workspace_api_key)
          : saved?.api_key_ciphertext;
        if (!ciphertext)
          fail(
            "PROVIDER_AUTH_REQUIRED",
            409,
            "Configure the private workspace API key before starting setup.",
          );
        const s = await this.provider.ensureManaged(db, org),
          jobId = randomUUID();
        const state = {
          mode: "codex_mcp",
          job_id: jobId,
          principal_id: p.id,
          idempotency_key: v.idempotency_key,
          plan_id: v.plan_id,
          plan: v.plan,
          request_version: r.version + 1,
          step: "agent",
          resources: {},
          receipts: {},
          agent_name: `BookingOS_${org.replace(/-/g, "")}_${jobId.slice(0, 8)}`,
          secret_name: `bookingos_${org.replace(/-/g, "")}_${jobId.slice(0, 8)}`,
          spec: this.spec(v.plan),
        };
        await db.query(
          `UPDATE sarvam_integrations SET enabled=false,sarvam_org_id=$2,workspace_id=$3,phone_number=$4,api_key_ciphertext=$5,api_key_last4=$6,setup_status='connecting',setup_state=$7,setup_error='',setup_lease=NULL,setup_lease_until=NULL,verified_at=NULL,verified_by='',tool_key_hash=NULL,tool_key_prefix='',tool_key_ciphertext=NULL,pending_tool_key_hash=NULL,oauth_state_hash=NULL,oauth_pending_ciphertext=NULL,authoring_ciphertext=NULL,version=version+1,updated_at=now() WHERE organization_id=$1`,
          [
            org,
            v.plan.sarvam_org_id,
            v.plan.workspace_id,
            v.plan.phone_number,
            ciphertext,
            v.workspace_api_key?.slice(-4) ?? saved!.api_key_last4,
            JSON.stringify(state),
          ],
        );
        await db.query("UPDATE memberships SET active=false WHERE id=$1", [
          s.membership_id,
        ]);
        await db.query(
          "UPDATE agent_call_requests SET status='setting_up',approved_services=$2,user_message='We are setting up your call service.',version=version+1,updated_at=now() WHERE organization_id=$1",
          [org, v.plan.approved_services],
        );
        await this.audit(db, actor, "start", org, {
          job_id: jobId,
          plan_id: v.plan_id,
          services: v.plan.approved_services,
        });
      })
      .catch((e) => {
        if (e?.code === "23505")
          fail(
            "NUMBER_IN_USE",
            409,
            "The number or agent was reserved by another request.",
          );
        throw e;
      });
    return this.jobInternal(actor, org);
  }
  private async jobInternal(actor: Actor, org: string) {
    const s = await this.integration(this.db, org);
    return this.safeJob(s);
  }
  async job(actor: Actor, organizationId: string) {
    this.principal(actor, "voice:read");
    return this.jobInternal(actor, this.org(organizationId));
  }
  async claim(actor: Actor, organizationId: string, body: unknown) {
    this.principal(actor);
    const org = this.org(organizationId),
      v = parse(
        z
          .object({ job_id: z.uuid(), version: z.number().int().positive() })
          .strict(),
        body,
      ),
      lease = randomUUID();
    const s = await this.db.transaction(async (db) => {
      const row = await this.integration(db, org, true),
        state = this.state(actor, row, v.job_id);
      if (row!.version !== v.version)
        fail(
          "STALE_PLAN",
          409,
          "Connection changed. Read the saved job before retrying.",
        );
      if (state.step === "done") return row!;
      await this.assertRequest(db, org, state);
      if (
        row!.setup_lease_until &&
        new Date(row!.setup_lease_until).getTime() > Date.now()
      )
        fail("LEASE_BUSY", 409, "Another connection step is running.");
      return (
        await db.query<Json>(
          "UPDATE sarvam_integrations SET setup_lease=$2,setup_lease_until=now()+interval '90 seconds' WHERE organization_id=$1 RETURNING *",
          [org, lease],
        )
      ).rows[0];
    });
    return {
      ...this.safeJob(s),
      ...(s.setup_lease === lease ? { lease_id: lease } : {}),
    };
  }
  private next(step: string, toolCount: number) {
    if (step === "agent") return "credential";
    if (step === "credential") return "tool_0";
    if (/^tool_\d+$/.test(step)) {
      const i = Number(step.slice(5));
      return i + 1 < toolCount ? `tool_${i + 1}` : "configure";
    }
    if (step === "configure") return "commit";
    if (step === "commit") return "deployment";
    if (step === "deployment") return "verify";
    fail(
      "INVALID_STEP",
      409,
      "This step must use its dedicated verification or activation endpoint.",
    );
  }
  async checkpoint(actor: Actor, organizationId: string, body: unknown) {
    this.principal(actor);
    const org = this.org(organizationId),
      v = parse(
        leaseInput
          .extend({
            step: z.string().max(32),
            resources: resourcesSchema.default({}),
            receipt: receiptSchema.optional(),
          })
          .strict(),
        body,
      );
    await this.db.transaction(async (db) => {
      const s = await this.integration(db, org, true),
        st = this.leased(actor, s, v);
      await this.assertRequest(db, org, st);
      if (st.step !== v.step)
        fail(
          "STALE_PLAN",
          409,
          "The saved setup step changed. Reconcile before retrying.",
        );
      const resources = { ...st.resources };
      for (const [k, value] of Object.entries(v.resources)) {
        if (resources[k] !== undefined && resources[k] !== value)
          fail(
            "RESOURCE_MISMATCH",
            409,
            "A provider resource reference cannot be changed during setup.",
          );
        resources[k] = value;
      }
      const required =
        v.step === "agent"
          ? "agent_id"
          : v.step === "credential"
            ? "secret_id"
            : v.step === "commit"
              ? "agent_version"
              : v.step === "deployment"
                ? "deployment_id"
                : null;
      if (required && !resources[required])
        fail(
          "INVALID_STEP",
          422,
          "The provider reference for this step is required.",
        );
      if (
        resources.agent_id &&
        (
          await db.query(
            "SELECT 1 FROM sarvam_integrations WHERE organization_id<>$1 AND sarvam_org_id=$2 AND workspace_id=$3 AND app_id=$4",
            [org, s!.sarvam_org_id, s!.workspace_id, resources.agent_id],
          )
        ).rows.length
      )
        fail(
          "RESOURCE_MISMATCH",
          409,
          "This agent is assigned to another organization.",
        );
      const receipts = { ...st.receipts, ...v.receipt };
      if (
        resources.secret_id &&
        (
          await db.query(
            "SELECT 1 FROM sarvam_integrations WHERE organization_id<>$1 AND sarvam_org_id=$2 AND workspace_id=$3 AND (setup_state->'resources'->>'secret_id'=$4 OR setup_state->>'secret_id'=$4)",
            [org, s!.sarvam_org_id, s!.workspace_id, resources.secret_id],
          )
        ).rows.length
      )
        fail(
          "RESOURCE_MISMATCH",
          409,
          "This secret is assigned to another organization.",
        );
      if (
        v.step === "credential" &&
        (!s!.tool_key_hash || !receipts.credential_verified)
      )
        fail(
          "VERIFICATION_FAILED",
          409,
          "Verify the generated tool credential before recording its secret.",
        );
      const next = {
        ...st,
        step: this.next(st.step, st.spec.tools.length),
        resources,
        receipts,
      };
      await db.query(
        `UPDATE sarvam_integrations SET setup_state=$2,app_id=COALESCE($3,app_id),deployment_id=COALESCE($4,deployment_id),setup_status='connecting',setup_error='',setup_lease=NULL,setup_lease_until=NULL,version=version+1,updated_at=now() WHERE organization_id=$1`,
        [
          org,
          JSON.stringify(next),
          resources.agent_id ?? null,
          resources.deployment_id ?? null,
        ],
      );
      await this.audit(db, actor, "checkpoint", org, {
        job_id: st.job_id,
        step: v.step,
        next_step: next.step,
      });
    });
    return this.jobInternal(actor, org);
  }
  async release(actor: Actor, organizationId: string, body: unknown) {
    this.principal(actor);
    const org = this.org(organizationId),
      v = parse(
        z
          .object({
            job_id: z.uuid(),
            lease_id: z.uuid(),
            error_code: z.enum(safeCodes),
          })
          .strict(),
        body,
      );
    await this.db.transaction(async (db) => {
      const s = await this.integration(db, org, true);
      this.state(actor, s, v.job_id);
      if (s!.setup_lease !== v.lease_id)
        fail(
          "LEASE_EXPIRED",
          409,
          "This step is no longer owned by this operator.",
        );
      await db.query(
        "UPDATE sarvam_integrations SET setup_lease=NULL,setup_lease_until=NULL,setup_status='failed',setup_error=$2,version=version+1,updated_at=now() WHERE organization_id=$1",
        [org, v.error_code],
      );
      await this.audit(db, actor, "step_failed", org, {
        job_id: v.job_id,
        error_code: v.error_code,
      });
    });
    return this.jobInternal(actor, org);
  }
  /** One private delivery per operation. Never expose as an MCP tool response. */
  async credential(actor: Actor, organizationId: string, body: unknown) {
    this.principal(actor, "voice:credentials:install");
    const org = this.org(organizationId),
      v = parse(
        z
          .object({
            job_id: z.uuid(),
            lease_id: z.uuid(),
            operation_key: z.uuid(),
          })
          .strict(),
        body,
      );
    return this.db.transaction(async (db) => {
      const s = await this.integration(db, org, true),
        st = this.leased(actor, s, v, "voice:credentials:install");
      await this.assertRequest(db, org, st);
      if (st.step !== "credential")
        fail(
          "INVALID_STEP",
          409,
          "Tool credential delivery is available only during credential installation.",
        );
      if (
        st.credential_operation &&
        st.credential_operation !== v.operation_key
      )
        fail(
          "OUTCOME_UNKNOWN",
          409,
          "Reuse the saved credential operation key to reconcile installation.",
        );
      let key: string;
      if (s!.tool_key_ciphertext) key = openSecret(s!.tool_key_ciphertext);
      else {
        key = "bkv_" + randomBytes(32).toString("base64url");
        await db.query(
          "UPDATE sarvam_integrations SET tool_key_ciphertext=$2,tool_key_hash=$3,tool_key_prefix=$4,setup_state=$5,enabled=false,verified_at=NULL,verified_by='' WHERE organization_id=$1",
          [
            org,
            sealSecret(key),
            hashToolKey(key),
            key.slice(0, 10),
            JSON.stringify({ ...st, credential_operation: v.operation_key }),
          ],
        );
        await this.audit(db, actor, "credential", org, {
          job_id: st.job_id,
          operation_key: v.operation_key,
        });
      }
      return {
        job_id: st.job_id,
        operation_key: v.operation_key,
        secret_name: st.secret_name,
        tool_key: key,
      };
    });
  }
  async verify(actor: Actor, organizationId: string, body: unknown) {
    this.principal(actor);
    const org = this.org(organizationId),
      v = parse(
        leaseInput
          .extend({
            tools_verified: z.literal(true),
            credential_verified: z.literal(true),
            language_verified: z.literal(true),
            committed_version: z.number().int().positive(),
            secret_id: identifier,
          })
          .strict(),
        body,
      );
    const s = await this.integration(this.db, org),
      st = this.leased(actor, s, v);
    if (
      st.step !== "verify" ||
      st.resources.agent_version !== v.committed_version ||
      st.resources.secret_id !== v.secret_id ||
      !st.receipts.credential_verified ||
      !st.receipts.tools_verified ||
      !st.receipts.language_verified
    )
      fail(
        "VERIFICATION_FAILED",
        409,
        "Provider audit does not match the saved connection resources.",
      );
    const owner = (
      await this.db.query<Json>(
        "SELECT user_id,email,display_name FROM memberships WHERE organization_id=$1 AND role='owner' AND active LIMIT 1",
        [org],
      )
    ).rows[0];
    if (!owner) fail("NOT_FOUND", 404, "Organization owner not found.");
    const [deployment] = await Promise.all([
      this.provider.verifyDeployment(s as any),
      this.provider.test({
        uid: owner.user_id,
        email: owner.email,
        name: owner.display_name,
      }),
    ]);
    if (deployment.app_version !== v.committed_version)
      fail(
        "VERIFICATION_FAILED",
        409,
        "The live deployment is using another agent version.",
      );
    await this.db.transaction(async (db) => {
      const current = await this.integration(db, org, true),
        state = this.leased(actor, current, v);
      await this.assertRequest(db, org, state);
      await db.query(
        "UPDATE sarvam_integrations SET setup_state=$2,verified_at=now(),verified_by=$3,setup_lease=NULL,setup_lease_until=NULL,setup_error='',version=version+1,updated_at=now() WHERE organization_id=$1",
        [
          org,
          JSON.stringify({
            ...state,
            step: "activate",
            receipts: {
              ...state.receipts,
              tools_verified: true,
              language_verified: true,
              credential_verified: true,
            },
          }),
          actor.email,
        ],
      );
      await this.audit(db, actor, "verified", org, {
        job_id: st.job_id,
        agent_version: v.committed_version,
      });
    });
    return this.jobInternal(actor, org);
  }
  async activate(actor: Actor, organizationId: string, body: unknown) {
    this.principal(actor);
    const org = this.org(organizationId),
      v = parse(leaseInput.strict(), body);
    await this.db.transaction(async (db) => {
      const s = await this.integration(db, org, true),
        st = this.leased(actor, s, v);
      await this.assertRequest(db, org, st);
      if (
        st.step !== "activate" ||
        !s!.verified_at ||
        !st.receipts.tools_verified ||
        !st.receipts.language_verified ||
        !st.receipts.credential_verified
      )
        fail(
          "VERIFICATION_FAILED",
          409,
          "Verify every connection check before activation.",
        );
      await db.query(
        "UPDATE sarvam_integrations SET setup_state=$2,setup_status='configured',enabled=false,tool_key_ciphertext=NULL,setup_lease=NULL,setup_lease_until=NULL,setup_error='',version=version+1,updated_at=now() WHERE organization_id=$1",
        [org, JSON.stringify({ ...st, step: "done" })],
      );
      await db.query(
        "UPDATE agent_call_requests SET status='active',user_message='Your call service is connected. Choose spaces and turn it on.',version=version+1,updated_at=now() WHERE organization_id=$1",
        [org],
      );
      await this.audit(db, actor, "connected", org, {
        job_id: st.job_id,
        agent_id: st.resources.agent_id,
        deployment_id: st.resources.deployment_id,
      });
    });
    return this.jobInternal(actor, org);
  }
  async pause(actor: Actor, organizationId: string, body: unknown) {
    this.principal(actor);
    const org = this.org(organizationId),
      v = parse(
        z
          .object({
            request_version: z.number().int().positive(),
            reason: z.string().trim().max(500).optional(),
          })
          .strict(),
        body,
      );
    await this.db.transaction(async (db) => {
      const s = await this.integration(db, org, true),
        r = await this.request(db, org, true);
      if (r.version !== v.request_version)
        fail("STALE_PLAN", 409, "Request changed. Refresh before pausing.");
      await db.query(
        "UPDATE sarvam_integrations SET enabled=false,setup_lease=NULL,setup_lease_until=NULL,version=version+1,updated_at=now() WHERE organization_id=$1",
        [org],
      );
      if (s)
        await db.query("UPDATE memberships SET active=false WHERE id=$1", [
          s.membership_id,
        ]);
      await db.query(
        "UPDATE agent_call_requests SET status='paused',user_message=$2,version=version+1,updated_at=now() WHERE organization_id=$1",
        [org, v.reason ?? "Your call service is paused."],
      );
      await this.audit(db, actor, "paused", org);
    });
    return { organization_id: org, status: "paused", client_enabled: false };
  }
}
