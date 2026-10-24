import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import type { Database } from "../common/database";
import type { Actor } from "../common/auth.guard";
import type { WorkspaceService } from "../workspace/workspace.service";

const createSchema = z
  .object({
    category: z
      .enum(["booking", "payments", "team", "website", "agent_calls", "other"])
      .default("other"),
    subject: z.string().trim().min(3).max(160),
    message: z.string().trim().min(5).max(4000),
  })
  .strict();
const messageSchema = z
  .object({ message: z.string().trim().min(1).max(4000) })
  .strict();
const uuid = z.string().uuid();

/** Support tickets raised by organization members. Members only see tickets
 * from their own organization; the admin panel reads them across all. */
@Injectable()
export class SupportService {
  constructor(
    private readonly db: Database,
    private readonly workspace: WorkspaceService,
  ) {}

  async list(actor: Actor) {
    const m = await this.workspace.member(actor);
    const { rows } = await this.db.query(
      `SELECT id,category,subject,status,created_at,updated_at FROM support_tickets
       WHERE organization_id=$1 ORDER BY updated_at DESC LIMIT 100`,
      [m.organization_id],
    );
    return { tickets: rows };
  }

  async create(actor: Actor, input: unknown) {
    const v = createSchema.safeParse(input);
    if (!v.success)
      throw new BadRequestException(v.error.issues[0]?.message ?? "Invalid.");
    const m = await this.workspace.member(actor);
    const open = await this.db.query<{ n: number }>(
      "SELECT count(*)::int AS n FROM support_tickets WHERE organization_id=$1 AND status IN ('open','in_progress')",
      [m.organization_id],
    );
    if (open.rows[0].n >= 20)
      throw new BadRequestException(
        "You have too many open requests. Wait for support to resolve an existing request before opening another.",
      );
    const id = randomUUID();
    await this.db.transaction(async (db) => {
      await db.query(
        "INSERT INTO support_tickets(id,organization_id,membership_id,category,subject) VALUES($1,$2,$3,$4,$5)",
        [id, m.organization_id, m.id, v.data.category, v.data.subject],
      );
      await db.query(
        "INSERT INTO support_messages(id,ticket_id,author,author_name,body) VALUES($1,$2,'user',$3,$4)",
        [randomUUID(), id, m.display_name, v.data.message],
      );
    });
    return this.detail(actor, id);
  }

  async detail(actor: Actor, ticketId: string) {
    const id = uuid.safeParse(ticketId);
    if (!id.success) throw new NotFoundException("Request not found.");
    const m = await this.workspace.member(actor);
    const t = (
      await this.db.query(
        `SELECT id,category,subject,status,created_at,updated_at FROM support_tickets
         WHERE id=$1 AND organization_id=$2`,
        [id.data, m.organization_id],
      )
    ).rows[0];
    if (!t) throw new NotFoundException("Request not found.");
    const messages = (
      await this.db.query(
        "SELECT id,author,author_name,body,created_at FROM support_messages WHERE ticket_id=$1 ORDER BY created_at",
        [id.data],
      )
    ).rows;
    return { ticket: t, messages };
  }

  async addMessage(actor: Actor, ticketId: string, input: unknown) {
    const v = messageSchema.safeParse(input);
    if (!v.success)
      throw new BadRequestException(v.error.issues[0]?.message ?? "Invalid.");
    const current = await this.detail(actor, ticketId);
    const m = await this.workspace.member(actor);
    await this.db.transaction(async (db) => {
      await db.query(
        "INSERT INTO support_messages(id,ticket_id,author,author_name,body) VALUES($1,$2,'user',$3,$4)",
        [
          randomUUID(),
          (current.ticket as { id: string }).id,
          m.display_name,
          v.data.message,
        ],
      );
      // A reply reopens a resolved or closed request.
      await db.query(
        "UPDATE support_tickets SET status='open', updated_at=now() WHERE id=$1",
        [(current.ticket as { id: string }).id],
      );
    });
    return this.detail(actor, ticketId);
  }
}
