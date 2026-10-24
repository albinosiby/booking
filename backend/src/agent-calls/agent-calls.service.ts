import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import type { Database } from "../common/database";
import type { Actor } from "../common/auth.guard";
import type { WorkspaceService } from "../workspace/workspace.service";
import type { SarvamService } from "../sarvam/sarvam.service";
import { serviceSelection } from "./agent-call-policy";

const requestSchema = z
  .object({
    note: z.string().trim().max(2000).default(""),
    services: serviceSelection,
  })
  .strict();
const enabledSchema = z
  .object({ enabled: z.boolean(), version: z.number().int().positive() })
  .strict();
const spacesSchema = z
  .object({
    resource_ids: z.array(z.string().uuid()).max(1000),
    version: z.number().int().positive(),
  })
  .strict();
const historySchema = z
  .object({
    start: z.iso.datetime({ offset: true }),
    end: z.iso.datetime({ offset: true }),
    offset: z.coerce.number().int().min(0).max(100000).default(0),
  })
  .strict()
  .refine(
    (v) =>
      Date.parse(v.end) > Date.parse(v.start) &&
      Date.parse(v.end) - Date.parse(v.start) <= 31 * 86400000,
    "Choose a date range of at most 31 days.",
  );

@Injectable()
export class AgentCallService {
  constructor(
    private readonly db: Database,
    private readonly workspace: WorkspaceService,
    private readonly provider: SarvamService,
  ) {}
  async status(actor: Actor) {
    const m = await this.workspace.member(actor, true);
    const r = (
      await this.db.query<any>(
        "SELECT status,user_message,requested_services,approved_services,version,created_at,updated_at FROM agent_call_requests WHERE organization_id=$1",
        [m.organization_id],
      )
    ).rows[0];
    const s = (
      await this.db.query<any>(
        "SELECT enabled,api_key_ciphertext,tool_key_hash,phone_number,verified_at,membership_id,version FROM sarvam_integrations WHERE organization_id=$1",
        [m.organization_id],
      )
    ).rows[0];
    const ready =
      r?.status === "active" &&
      !!s?.verified_at &&
      !!s?.phone_number &&
      !!s?.api_key_ciphertext &&
      !!s?.tool_key_hash &&
      !!r?.approved_services.length;
    const spaces = (
      await this.db.query<any>(
        `SELECT b.id AS business_id,b.name AS business_name,b.status AS business_status,r.id,r.name,
    COALESCE(a.resource_ids ? r.id::text,false) AS enabled
    FROM businesses b JOIN resources r ON r.business_id=b.id AND r.organization_id=b.organization_id
    LEFT JOIN staff_assignments a ON a.business_id=b.id AND a.membership_id=$2
    WHERE b.organization_id=$1 ORDER BY b.name,r.name,r.id`,
        [m.organization_id, s?.membership_id ?? null],
      )
    ).rows;
    const hasHistory = !!(
      await this.db.query(
        "SELECT 1 FROM agent_call_logs WHERE organization_id=$1 LIMIT 1",
        [m.organization_id],
      )
    ).rows.length;
    return {
      status: r?.status ?? "none",
      message: r?.user_message ?? "",
      requested_at: r?.created_at ?? null,
      updated_at: r?.updated_at ?? null,
      requested_services: r?.requested_services ?? [],
      approved_services: r?.approved_services ?? [],
      phone_number: s?.phone_number ?? "",
      version: s?.version ?? 0,
      ready,
      enabled: ready && !!s?.enabled,
      spaces,
      call_logs_available: hasHistory || !!s?.api_key_ciphertext,
    };
  }
  async request(actor: Actor, input: unknown) {
    const v = requestSchema.parse(input);
    await this.db.transaction(async (db) => {
      const m = await this.workspace.member(actor, true, db);
      await db.query("SELECT id FROM organizations WHERE id=$1 FOR UPDATE", [
        m.organization_id,
      ]);
      const existing = (
        await db.query<any>(
          "SELECT id,status FROM agent_call_requests WHERE organization_id=$1 FOR UPDATE",
          [m.organization_id],
        )
      ).rows[0];
      if (existing && existing.status !== "rejected")
        throw new ConflictException("You have already requested this service.");
      if (existing)
        await db.query(
          "UPDATE agent_call_requests SET status='requested',note=$2,requested_services=$3,approved_services='{}',user_message='',membership_id=$4,created_at=now(),updated_at=now(),version=version+1 WHERE organization_id=$1",
          [m.organization_id, v.note, v.services, m.id],
        );
      else
        await db.query(
          "INSERT INTO agent_call_requests(id,organization_id,membership_id,note,requested_services) VALUES($1,$2,$3,$4,$5)",
          [randomUUID(), m.organization_id, m.id, v.note, v.services],
        );
      await this.workspace.audit(
        db,
        actor,
        m.organization_id,
        "agent_calls.requested",
        m.id,
      );
    });
    return this.status(actor);
  }
  async setEnabled(actor: Actor, input: unknown) {
    const v = enabledSchema.parse(input);
    await this.db.transaction(async (db) => {
      const m = await this.workspace.member(actor, true, db);
      const s = (
        await db.query<any>(
          "SELECT * FROM sarvam_integrations WHERE organization_id=$1 FOR UPDATE",
          [m.organization_id],
        )
      ).rows[0];
      if (!s)
        throw new ForbiddenException("The call service is not ready yet.");
      const r = (
        await db.query<any>(
          "SELECT status,approved_services FROM agent_call_requests WHERE organization_id=$1 FOR SHARE",
          [m.organization_id],
        )
      ).rows[0];
      // Turning off is always allowed, even when another admin update won the race.
      if (v.enabled) {
        if (s.version !== v.version)
          throw new ConflictException(
            "Call settings changed. Refresh and try again.",
          );
        if (
          r?.status !== "active" ||
          !s.verified_at ||
          !s.phone_number ||
          !s.api_key_ciphertext ||
          !s.tool_key_hash ||
          !r.approved_services.length
        )
          throw new ForbiddenException("The call service is not ready yet.");
        const spaces = await db.query(
          `SELECT 1 FROM staff_assignments a JOIN resources r ON r.business_id=a.business_id AND a.resource_ids ? r.id::text
      JOIN businesses b ON b.id=r.business_id WHERE a.membership_id=$1 AND b.status='ready' LIMIT 1`,
          [s.membership_id],
        );
        if (!spaces.rows.length)
          throw new BadRequestException(
            "Choose at least one ready space for the call service.",
          );
      }
      await db.query(
        "UPDATE sarvam_integrations SET enabled=$2,version=version+1,updated_at=now() WHERE organization_id=$1",
        [m.organization_id, v.enabled],
      );
      await db.query("UPDATE memberships SET active=$2 WHERE id=$1", [
        s.membership_id,
        v.enabled,
      ]);
      await this.workspace.audit(
        db,
        actor,
        m.organization_id,
        v.enabled ? "agent_calls.enabled" : "agent_calls.disabled",
        s.membership_id,
      );
    });
    return this.status(actor);
  }
  async setSpaces(actor: Actor, input: unknown) {
    const v = spacesSchema.parse(input);
    const ids = [...new Set(v.resource_ids)];
    await this.db.transaction(async (db) => {
      const m = await this.workspace.member(actor, true, db);
      const s = (
        await db.query<any>(
          "SELECT * FROM sarvam_integrations WHERE organization_id=$1 FOR UPDATE",
          [m.organization_id],
        )
      ).rows[0];
      const r = (
        await db.query<any>(
          "SELECT status FROM agent_call_requests WHERE organization_id=$1 FOR SHARE",
          [m.organization_id],
        )
      ).rows[0];
      if (!s?.verified_at || r?.status !== "active")
        throw new ForbiddenException("The call service is not ready yet.");
      if (s.version !== v.version)
        throw new ConflictException(
          "Call settings changed. Refresh and try again.",
        );
      const resources = (
        await db.query<any>(
          `SELECT r.id,r.business_id FROM resources r JOIN businesses b ON b.id=r.business_id
      WHERE r.organization_id=$1 AND r.id=ANY($2::uuid[]) AND b.status='ready'`,
          [m.organization_id, ids],
        )
      ).rows;
      if (resources.length !== ids.length)
        throw new BadRequestException(
          "Choose ready spaces in your organization.",
        );
      // Explicit IDs only. An empty assignment has legacy "all spaces" semantics.
      await db.query("DELETE FROM staff_assignments WHERE membership_id=$1", [
        s.membership_id,
      ]);
      for (const business of new Set(resources.map((r) => r.business_id)))
        await db.query(
          "INSERT INTO staff_assignments(membership_id,organization_id,business_id,resource_ids) VALUES($1,$2,$3,$4)",
          [
            s.membership_id,
            m.organization_id,
            business,
            JSON.stringify(
              resources
                .filter((r) => r.business_id === business)
                .map((r) => r.id),
            ),
          ],
        );
      const enabled = s.enabled && ids.length > 0;
      await db.query(
        "UPDATE sarvam_integrations SET enabled=$2,version=version+1,updated_at=now() WHERE organization_id=$1",
        [m.organization_id, enabled],
      );
      await db.query("UPDATE memberships SET active=$2 WHERE id=$1", [
        s.membership_id,
        enabled,
      ]);
      await this.workspace.audit(
        db,
        actor,
        m.organization_id,
        "agent_calls.spaces_updated",
        s.membership_id,
      );
    });
    return this.status(actor);
  }
  async calls(actor: Actor, input: unknown) {
    const q = historySchema.parse(input);
    const m = await this.workspace.member(actor, true);
    try {
      const { provider_scope, ...result } = await this.provider.calls(actor, q);
      for (const item of result.items)
        await this.storeCall(m.organization_id, provider_scope, item);
      if (result.total === 0) {
        const saved = await this.savedCalls(m.organization_id, q);
        if (saved.total > 0)
          return {
            ...saved,
            warning: "Showing saved calls while live call history catches up.",
          };
      }
      return {
        ...result,
        next_offset:
          result.items.length && q.offset + result.items.length < result.total
            ? q.offset + result.items.length
            : null,
        warning: "",
      };
    } catch {
      return {
        ...(await this.savedCalls(m.organization_id, q)),
        warning:
          "Live call history is unavailable. Showing saved calls; recent calls may be missing.",
      };
    }
  }
  private async savedCalls(org: string, q: z.infer<typeof historySchema>) {
    const items = (
      await this.db.query<any>(
        "SELECT data FROM agent_call_logs WHERE organization_id=$1 AND started_at >= $2 AND started_at < $3 ORDER BY started_at DESC,interaction_id LIMIT 50 OFFSET $4",
        [org, q.start, q.end, q.offset],
      )
    ).rows.map((r) => r.data);
    const total = Number(
      (
        await this.db.query<any>(
          "SELECT count(*) AS total FROM agent_call_logs WHERE organization_id=$1 AND started_at >= $2 AND started_at < $3",
          [org, q.start, q.end],
        )
      ).rows[0].total,
    );
    return {
      items,
      total,
      offset: q.offset,
      limit: 50,
      next_offset:
        q.offset + items.length < total ? q.offset + items.length : null,
    };
  }
  /** An authenticated on-end tool records history even after the client turns actions off. */
  async recordEvent(actor: Actor, input: unknown) {
    const event = z
      .object({
        interaction_id: z
          .string()
          .regex(/^[A-Za-z0-9:_.-]+(\/[A-Za-z0-9:_.-]+)?$/)
          .max(200)
          .refine((v) => !v.includes("..")),
        caller_phone: z.string().max(40).default(""),
        duration_seconds: z.coerce.number().min(0).max(7200),
        transcript: z.string().max(200000).default(""),
        summary: z.string().max(4000).default(""),
        caller_name: z.string().max(100).default(""),
        disposition: z.string().max(200).default(""),
      })
      .strict()
      .parse(input);
    if (!actor.uid.startsWith("sarvam:"))
      throw new ForbiddenException("A call service key is required.");
    const org = actor.uid.slice(7);
    const s = (
      await this.db.query<any>(
        "SELECT sarvam_org_id,workspace_id,app_id FROM sarvam_integrations WHERE organization_id=$1",
        [org],
      )
    ).rows[0];
    if (!s) throw new NotFoundException("Connection not found.");
    const scope = JSON.stringify([s.sarvam_org_id, s.workspace_id, s.app_id]);
    const existing = (
      await this.db.query<any>(
        "SELECT data FROM agent_call_logs WHERE organization_id=$1 AND interaction_id=$2",
        [org, event.interaction_id],
      )
    ).rows[0];
    await this.storeCall(org, scope, {
      interaction_id: event.interaction_id,
      started_at:
        existing?.data.started_at ??
        new Date(Date.now() - event.duration_seconds * 1000).toISOString(),
      duration_seconds: event.duration_seconds,
      contact: event.caller_phone,
      caller_name: event.caller_name,
      summary: event.summary,
      disposition: event.disposition,
      direction: "inbound",
    });
    // Raw call transcripts remain a separate, accurately labelled text field.
    if (event.transcript)
      await this.db.query(
        "UPDATE agent_call_logs SET transcript=$3 WHERE organization_id=$1 AND interaction_id=$2 AND provider_scope=$4",
        [
          org,
          event.interaction_id,
          JSON.stringify({
            interaction_id: event.interaction_id,
            messages: [],
            text: event.transcript,
          }),
          scope,
        ],
      );
    return { ok: true };
  }
  private async storeCall(
    org: string,
    app: string,
    item: Record<string, unknown>,
  ) {
    if (
      typeof item.interaction_id !== "string" ||
      !item.interaction_id ||
      item.interaction_id.length > 200
    )
      return;
    const raw = String(item.started_at ?? "");
    const stamp =
      raw && !/(Z|[+-]\d\d:?\d\d)$/.test(raw)
        ? raw.replace(" ", "T") + "Z"
        : raw;
    const started = Number.isFinite(Date.parse(stamp))
      ? new Date(stamp).toISOString()
      : null;
    await this.db.query(
      `INSERT INTO agent_call_logs(organization_id,interaction_id,provider_scope,started_at,data) VALUES($1,$2,$3,$4,$5)
   ON CONFLICT(organization_id,interaction_id) DO UPDATE SET data=EXCLUDED.data,started_at=COALESCE(EXCLUDED.started_at,agent_call_logs.started_at),updated_at=now()
   WHERE agent_call_logs.provider_scope=EXCLUDED.provider_scope`,
      [org, item.interaction_id, app, started, JSON.stringify(item)],
    );
  }
  private async knownCall(actor: Actor, id: unknown) {
    if (typeof id !== "string" || id.length > 200)
      throw new BadRequestException("Invalid call.");
    const m = await this.workspace.member(actor, true);
    const row = (
      await this.db.query<any>(
        `SELECT l.*,s.sarvam_org_id,s.workspace_id,s.app_id FROM agent_call_logs l LEFT JOIN sarvam_integrations s USING(organization_id)
   WHERE l.organization_id=$1 AND l.interaction_id=$2`,
        [m.organization_id, id],
      )
    ).rows[0];
    if (!row)
      throw new NotFoundException(
        "Call not found. Refresh call history first.",
      );
    return row;
  }
  async transcript(actor: Actor, id: unknown) {
    const row = await this.knownCall(actor, id);
    try {
      if (
        row.provider_scope !==
        JSON.stringify([row.sarvam_org_id, row.workspace_id, row.app_id])
      )
        throw new NotFoundException();
      const result = await this.provider.transcript(
        actor,
        id,
        row.provider_scope,
      );
      if (!result.messages.length && row.transcript) return row.transcript;
      await this.db.query(
        "UPDATE agent_call_logs SET transcript=$3 WHERE organization_id=$1 AND interaction_id=$2 AND provider_scope=$4",
        [row.organization_id, id, JSON.stringify(result), row.provider_scope],
      );
      return result;
    } catch (error) {
      if (row.transcript) return row.transcript;
      throw error;
    }
  }
  async recording(actor: Actor, id: unknown) {
    const row = await this.knownCall(actor, id);
    if (
      row.provider_scope !==
      JSON.stringify([row.sarvam_org_id, row.workspace_id, row.app_id])
    )
      throw new NotFoundException("This recording is no longer available.");
    return this.provider.recording(actor, id, row.provider_scope);
  }
}
