import {
  Injectable,
  BadRequestException,
  ConflictException,
  HttpException,
  NotFoundException,
  ServiceUnavailableException,
  UnauthorizedException,
} from "@nestjs/common";
import { z } from "zod";
import { randomBytes, randomUUID } from "node:crypto";
import { Database, Queryable } from "../common/database";
import { Actor } from "../common/auth.guard";
import { WorkspaceService } from "../workspace/workspace.service";
import { sealSecret, openSecret, hashToolKey } from "./sarvam-secrets";
export { sealSecret, openSecret, hashToolKey } from "./sarvam-secrets";
import { SarvamSetup } from "./sarvam-setup";
type Row = Record<string, any>;

/** Voice-agent memberships use this user_id prefix and never appear in Team. */
export const VOICE_PREFIX = "sarvam:";
export const voiceActor = (organizationId: string): Actor => ({
  uid: VOICE_PREFIX + organizationId,
  email: "voice-agent@sarvam.invalid",
  name: "Sarvam voice agent",
});
const SARVAM_ORIGIN = "https://apps.sarvam.ai";
const id = z
  .string()
  .trim()
  .regex(/^[A-Za-z0-9_-]{1,100}$/, "Use the ID shown in Sarvam.");
const interactionId = z
  .string()
  .regex(/^[A-Za-z0-9:_.-]+(\/[A-Za-z0-9:_.-]+)?$/)
  .max(200)
  .refine((v) => !v.includes(".."), "Invalid interaction ID.");
const settingsSchema = z
  .object({
    version: z.number().int().nonnegative(),
    enabled: z.boolean(),
    business_ids: z.array(z.uuid()).max(100),
    sarvam_org_id: id.or(z.literal("")),
    workspace_id: id.or(z.literal("")),
    app_id: id.or(z.literal("")),
    // Omitted keeps the stored key; null removes it.
    api_key: z.string().trim().min(8).max(500).nullable().optional(),
  })
  .strict();
const callsSchema = z
  .object({
    start: z.iso.datetime({ offset: true }),
    end: z.iso.datetime({ offset: true }),
    offset: z.coerce.number().int().min(0).max(100000).default(0),
  })
  .strict()
  .refine(
    (v) => Date.parse(v.end) > Date.parse(v.start),
    "End must be after start.",
  )
  .refine(
    (v) => Date.parse(v.end) - Date.parse(v.start) <= 31 * 86400000,
    "Choose at most 31 days.",
  );

@Injectable()
export class SarvamService {
  /** Replaced in tests; Sarvam is only contacted over HTTPS at SARVAM_ORIGIN. */
  http: typeof fetch = (...a) => fetch(...a);
  constructor(
    private readonly db: Database,
    private readonly workspace: WorkspaceService,
  ) {}
  private get setup() {
    return new SarvamSetup(
      this.db,
      this.workspace,
      (...a) => this.http(...a),
      (db, org) => this.ensure(db, org),
    );
  }
  async connect(actor: Actor, input: unknown) {
    await this.setup.connect(actor, input);
    return this.settings(actor);
  }
  async setupStep(actor: Actor) {
    await this.setup.step(actor);
    return this.settings(actor);
  }
  async disconnect(actor: Actor) {
    await this.setup.disconnect(actor);
    return this.settings(actor);
  }
  async bookingEnabled(actor: Actor, input: unknown) {
    await this.setup.enabled(actor, input);
    return this.settings(actor);
  }
  async publish(actor: Actor, input: unknown) {
    await this.setup.publish(actor, input);
    return this.settings(actor);
  }
  oauthCallback(input: unknown) {
    return this.setup.callback(input);
  }
  private toolBaseUrl() {
    return `${this.workspace.publicAppUrl || process.env.PUBLIC_APP_URL || "http://localhost:3000"}/voice/v1`;
  }
  private async row(organizationId: string, db: Queryable = this.db) {
    return (
      await db.query<Row>(
        "SELECT * FROM sarvam_integrations WHERE organization_id=$1",
        [organizationId],
      )
    ).rows[0];
  }
  /** Creates the inactive voice membership and settings row on first use. */
  private async ensure(db: Queryable, organizationId: string) {
    await db.query("SELECT id FROM organizations WHERE id=$1 FOR UPDATE", [
      organizationId,
    ]);
    const existing = await this.row(organizationId, db);
    if (existing) return existing;
    const membershipId = randomUUID(),
      a = voiceActor(organizationId);
    await db.query(
      "INSERT INTO memberships(id,organization_id,user_id,email,display_name,role,permissions,active) VALUES($1,$2,$3,$4,$5,'staff',$6,false)",
      [
        membershipId,
        organizationId,
        a.uid,
        a.email,
        a.name,
        JSON.stringify(["view_bookings", "manage_bookings"]),
      ],
    );
    await db.query(
      "INSERT INTO sarvam_integrations(organization_id,membership_id) VALUES($1,$2)",
      [organizationId, membershipId],
    );
    return (await this.row(organizationId, db))!;
  }
  async settings(actor: Actor) {
    const m = await this.workspace.member(actor, true);
    const s = await this.row(m.organization_id);
    const businesses = (
      await this.db.query<Row>(
        "SELECT id,name,type,status FROM businesses WHERE organization_id=$1 ORDER BY name",
        [m.organization_id],
      )
    ).rows;
    const assigned = s
      ? (
          await this.db.query<Row>(
            "SELECT business_id FROM staff_assignments WHERE membership_id=$1",
            [s.membership_id],
          )
        ).rows.map((r) => r.business_id)
      : [];
    return {
      version: s?.version ?? 0,
      enabled: s?.enabled ?? false,
      connected: !!s?.api_key_ciphertext && s?.setup_status === "configured",
      has_credentials:
        !!s?.api_key_ciphertext || !!s?.setup_state?.pending_api_key_ciphertext,
      call_logs_available: !!s?.api_key_ciphertext,
      setup_status: s?.setup_status ?? "disconnected",
      setup_step: s?.setup_state?.step ?? "",
      setup_error: s?.setup_error ?? "",
      authorization_url:
        s?.setup_status === "authorization_required"
          ? (s?.setup_state?.authorization_url ?? "")
          : "",
      draft_version: s?.setup_state?.draft_version ?? null,
      published_version: s?.setup_state?.published_version ?? null,
      deployments: s?.setup_state?.deployments ?? [],
      api_key_last4: s?.api_key_last4 ?? "",
      sarvam_org_id: s?.sarvam_org_id ?? "",
      workspace_id: s?.workspace_id ?? "",
      app_id: s?.app_id ?? "",
      tool_key_prefix: s?.tool_key_prefix ?? "",
      tool_base_url: this.toolBaseUrl(),
      businesses: businesses.map((b) => ({
        ...b,
        assigned: (s?.setup_state?.business_ids ?? assigned).includes(b.id),
      })),
    };
  }
  async save(actor: Actor, input: unknown) {
    const v = settingsSchema.parse(input);
    const member = await this.workspace.member(actor, true);
    const existing = await this.row(member.organization_id);
    if (existing?.setup_status && existing.setup_status !== "legacy")
      throw new ConflictException(
        "Use Connect or the phone booking switch to update this integration.",
      );
    if (v.enabled && !v.business_ids.length)
      throw new BadRequestException(
        "Choose at least one business the voice agent can book.",
      );
    await this.db.transaction(async (db) => {
      const m = await this.workspace.member(actor, true, db);
      await db.query("SELECT id FROM organizations WHERE id=$1 FOR UPDATE", [
        m.organization_id,
      ]);
      const current = (await this.row(m.organization_id, db))?.version ?? 0;
      const s = await this.ensure(db, m.organization_id);
      if (current !== v.version)
        throw new ConflictException(
          "Sarvam settings changed elsewhere. Reload and try again.",
        );
      if (v.enabled && !s.tool_key_hash)
        throw new BadRequestException(
          "Generate a voice tool key before turning the agent on.",
        );
      const owned = (
        await db.query<Row>(
          "SELECT id FROM businesses WHERE organization_id=$1 AND id = ANY($2::uuid[])",
          [m.organization_id, v.business_ids],
        )
      ).rows;
      if (owned.length !== new Set(v.business_ids).size)
        throw new BadRequestException(
          "Choose businesses in your organization.",
        );
      const key =
        v.api_key === undefined
          ? { sealed: s.api_key_ciphertext, last4: s.api_key_last4 }
          : v.api_key === null
            ? { sealed: null, last4: "" }
            : { sealed: sealSecret(v.api_key), last4: v.api_key.slice(-4) };
      await db.query(
        "UPDATE sarvam_integrations SET enabled=$1,api_key_ciphertext=$2,api_key_last4=$3,sarvam_org_id=$4,workspace_id=$5,app_id=$6,version=version+1,updated_at=now() WHERE organization_id=$7",
        [
          v.enabled,
          key.sealed,
          key.last4,
          v.sarvam_org_id,
          v.workspace_id,
          v.app_id,
          m.organization_id,
        ],
      );
      await db.query("UPDATE memberships SET active=$1 WHERE id=$2", [
        v.enabled,
        s.membership_id,
      ]);
      await db.query("DELETE FROM staff_assignments WHERE membership_id=$1", [
        s.membership_id,
      ]);
      for (const businessId of new Set(v.business_ids))
        await db.query(
          "INSERT INTO staff_assignments(membership_id,organization_id,business_id,resource_ids) VALUES($1,$2,$3,'[]')",
          [s.membership_id, m.organization_id, businessId],
        );
      await this.workspace.audit(
        db,
        actor,
        m.organization_id,
        "sarvam.settings_updated",
        s.membership_id,
      );
    });
    return this.settings(actor);
  }
  /** Issues a new tool key (shown once) and invalidates the previous one. */
  async rotateToolKey(actor: Actor) {
    return this.db.transaction(async (db) => {
      const m = await this.workspace.member(actor, true, db);
      const s = await this.ensure(db, m.organization_id);
      if (s.setup_status && s.setup_status !== "legacy")
        throw new ConflictException(
          "Tool keys are managed internally by Connect.",
        );
      const key = "bkv_" + randomBytes(32).toString("base64url");
      await db.query(
        "UPDATE sarvam_integrations SET tool_key_hash=$1,tool_key_prefix=$2,version=version+1,updated_at=now() WHERE organization_id=$3",
        [hashToolKey(key), key.slice(0, 10), m.organization_id],
      );
      await this.workspace.audit(
        db,
        actor,
        m.organization_id,
        "sarvam.tool_key_rotated",
        s.membership_id,
      );
      return { tool_key: key, tool_key_prefix: key.slice(0, 10) };
    });
  }
  /** Resolves an X-API-Key from Sarvam to the organization's voice actor. */
  async authenticateToolKey(key: string | null) {
    if (!key || !/^bkv_[A-Za-z0-9_-]{43}$/.test(key))
      throw new UnauthorizedException("A valid voice tool key is required.");
    const s = (
      await this.db.query<Row>(
        "SELECT organization_id,enabled FROM sarvam_integrations WHERE tool_key_hash=$1 OR (setup_status='publishing' AND pending_tool_key_hash=$1)",
        [hashToolKey(key)],
      )
    ).rows[0];
    if (!s)
      throw new UnauthorizedException("A valid voice tool key is required.");
    if (!s.enabled)
      throw new HttpException("The voice agent is turned off.", 403);
    return voiceActor(s.organization_id);
  }
  private async analytics(actor: Actor) {
    const m = await this.workspace.member(actor, true);
    const s = await this.row(m.organization_id);
    if (
      !s?.api_key_ciphertext ||
      !s.sarvam_org_id ||
      !s.workspace_id ||
      !s.app_id
    )
      throw new BadRequestException(
        "The call service is not connected yet. Contact support.",
      );
    const base = `${SARVAM_ORIGIN}/api/analytics/v1/${s.sarvam_org_id}/${s.workspace_id}/${s.app_id}`;
    const key = openSecret(s.api_key_ciphertext);
    return async (path: string, query: Record<string, string> = {}) => {
      const url = new URL(base + path);
      for (const [k, v] of Object.entries(query)) url.searchParams.set(k, v);
      let res: Response;
      try {
        res = await this.http(url, {
          headers: { "X-API-Key": key },
          signal: AbortSignal.timeout(20000),
        });
      } catch {
        throw new ServiceUnavailableException(
          "The call service did not respond. Try again.",
        );
      }
      if (res.status === 401 || res.status === 403)
        throw new BadRequestException(
          "The call service connection needs attention. Contact support.",
        );
      if (res.status === 404)
        throw new NotFoundException(
          "The call service could not find this call. Contact support if it persists.",
        );
      if (!res.ok)
        throw new ServiceUnavailableException(
          `The call service returned an error (${res.status}). Try again.`,
        );
      return res;
    };
  }
  async test(actor: Actor) {
    const get = await this.analytics(actor);
    const end = new Date(),
      start = new Date(end.getTime() - 86400000);
    const data = (await (
      await get("/interactions", {
        start_datetime: start.toISOString(),
        end_datetime: end.toISOString(),
      })
    ).json()) as Row;
    return {
      ok: true,
      calls_last_24h: Number(data.total ?? data.items?.length ?? 0),
    };
  }
  async calls(actor: Actor, input: unknown) {
    const v = callsSchema.parse(input);
    const get = await this.analytics(actor);
    const data = (await (
      await get("/interactions", {
        start_datetime: new Date(v.start).toISOString(),
        end_datetime: new Date(v.end).toISOString(),
        ...(v.offset ? { offset: String(v.offset) } : {}),
      })
    ).json()) as Row;
    const items: Row[] = Array.isArray(data.items) ? data.items : [];
    const text = (x: unknown) => (typeof x === "string" ? x : "");
    return {
      total: Number(data.total ?? items.length),
      offset: Number(data.offset ?? v.offset),
      limit: Number(data.limit ?? items.length),
      items: items.map((c) => {
        const vars = (c.agent_variables ?? {}) as Row;
        return {
          interaction_id: text(c.interaction_id),
          // Sarvam omits a timezone suffix; observed values are UTC.
          started_at: text(c.start_datetime),
          duration_seconds: Number(c.duration_in_seconds ?? 0),
          language: text(c.language_name),
          direction: text(c.channel_direction),
          contact: text(c.user_contact),
          contact_masked: text(c.user_contact_masked),
          ended_by: text(c.ended_by),
          messages: Number(c.num_messages ?? 0),
          caller_name: text(vars.user_name),
          summary: text(vars.call_summary),
          enquiry_type: text(vars.enquiry_type),
          disposition: text(vars.call_disposition),
          requested_facility: text(vars.requested_facility),
          preferred_datetime: text(vars.preferred_datetime),
        };
      }),
    };
  }
  async transcript(actor: Actor, id: unknown) {
    const interaction = interactionId.parse(id);
    const get = await this.analytics(actor);
    const data = (await (
      await get(`/transcripts/${interaction}`)
    ).json()) as Row;
    return {
      interaction_id: interaction,
      messages: (Array.isArray(data.messages) ? data.messages : []).map(
        (m: Row) => ({
          turn: Number(m.turn_id ?? 0),
          role: m.role === "assistant" ? "agent" : "caller",
          text: typeof m.content === "string" ? m.content : "",
          language: typeof m.language_name === "string" ? m.language_name : "",
        }),
      ),
    };
  }
  async recording(actor: Actor, id: unknown) {
    const interaction = interactionId.parse(id);
    const get = await this.analytics(actor);
    const res = await get(`/recordings/${interaction}`);
    if (!res.headers.get("content-type")?.startsWith("audio/"))
      throw new ServiceUnavailableException(
        "The call service did not return audio.",
      );
    const bytes = new Uint8Array(await res.arrayBuffer());
    if (bytes.length > 25 * 1024 * 1024)
      throw new BadRequestException(
        "This recording is too large to play here.",
      );
    return { content_type: "audio/wav", data: bytes };
  }
}
