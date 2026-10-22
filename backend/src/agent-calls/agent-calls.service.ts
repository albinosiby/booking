import {
  BadRequestException,
  ForbiddenException,
  Injectable,
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import type { Database } from "../common/database";
import type { Actor } from "../common/auth.guard";
import type { WorkspaceService } from "../workspace/workspace.service";
import type { SarvamService } from "../sarvam/sarvam.service";

const requestSchema = z
  .object({ note: z.string().trim().max(2000).default("") })
  .strict();
const enabledSchema = z.object({ enabled: z.boolean() }).strict();

/** Owner-facing agent call service. The owner requests it and tracks progress;
 * the platform admin does the provider connection. Provider names and
 * credentials never leave the backend. */
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
      await this.db.query<Record<string, any>>(
        "SELECT status,user_message,created_at,updated_at FROM agent_call_requests WHERE organization_id=$1",
        [m.organization_id],
      )
    ).rows[0];
    const s = (
      await this.db.query<Record<string, any>>(
        "SELECT enabled,api_key_ciphertext,tool_key_hash FROM sarvam_integrations WHERE organization_id=$1",
        [m.organization_id],
      )
    ).rows[0];
    const ready =
      r?.status === "active" && !!s?.api_key_ciphertext && !!s?.tool_key_hash;
    return {
      status: r?.status ?? "none",
      message: r?.user_message ?? "",
      requested_at: r?.created_at ?? null,
      updated_at: r?.updated_at ?? null,
      ready,
      enabled: ready && !!s?.enabled,
    };
  }

  async request(actor: Actor, input: unknown) {
    const v = requestSchema.safeParse(input ?? {});
    if (!v.success) throw new BadRequestException("Note is too long.");
    const m = await this.workspace.member(actor, true);
    const existing = (
      await this.db.query<{ status: string }>(
        "SELECT status FROM agent_call_requests WHERE organization_id=$1",
        [m.organization_id],
      )
    ).rows[0];
    if (existing && existing.status !== "rejected")
      throw new BadRequestException("You have already requested this service.");
    if (existing)
      await this.db.query(
        "UPDATE agent_call_requests SET status='requested',note=$2,user_message='',membership_id=$3,updated_at=now() WHERE organization_id=$1",
        [m.organization_id, v.data.note, m.id],
      );
    else
      await this.db.query(
        "INSERT INTO agent_call_requests(id,organization_id,membership_id,note) VALUES($1,$2,$3,$4)",
        [randomUUID(), m.organization_id, m.id, v.data.note],
      );
    return this.status(actor);
  }

  async setEnabled(actor: Actor, input: unknown) {
    const v = enabledSchema.safeParse(input);
    if (!v.success) throw new BadRequestException("Choose on or off.");
    const m = await this.workspace.member(actor, true);
    const state = await this.status(actor);
    if (!state.ready)
      throw new ForbiddenException("The call service is not ready yet.");
    await this.db.transaction(async (db) => {
      const s = (
        await db.query<{ membership_id: string }>(
          `UPDATE sarvam_integrations SET enabled=$2,version=version+1,updated_at=now()
           WHERE organization_id=$1 RETURNING membership_id`,
          [m.organization_id, v.data.enabled],
        )
      ).rows[0];
      if (v.data.enabled) {
        const spaces = await db.query(
          "SELECT 1 FROM staff_assignments WHERE membership_id=$1 LIMIT 1",
          [s.membership_id],
        );
        if (!spaces.rows[0])
          throw new BadRequestException(
            "No businesses are set up for the call service yet. Contact support.",
          );
      }
      await db.query("UPDATE memberships SET active=$2 WHERE id=$1", [
        s.membership_id,
        v.data.enabled,
      ]);
      await this.workspace.audit(
        db,
        actor,
        m.organization_id,
        v.data.enabled ? "agent_calls.enabled" : "agent_calls.disabled",
        s.membership_id,
      );
    });
    return this.status(actor);
  }

  private async ready(actor: Actor) {
    if (!(await this.status(actor)).ready)
      throw new ForbiddenException("The call service is not ready yet.");
  }
  async calls(actor: Actor, query: unknown) {
    await this.ready(actor);
    return this.provider.calls(actor, query);
  }
  async transcript(actor: Actor, id: unknown) {
    await this.ready(actor);
    return this.provider.transcript(actor, id);
  }
  async recording(actor: Actor, id: unknown) {
    await this.ready(actor);
    return this.provider.recording(actor, id);
  }
}
