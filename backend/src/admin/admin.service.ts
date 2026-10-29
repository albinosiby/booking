import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { randomUUID, randomBytes } from "node:crypto";
import { z } from "zod";
import type { Actor } from "../common/auth.guard";
import type { Database } from "../common/database";
import type { SarvamService } from "../sarvam/sarvam.service";
import { serviceSelection } from "../agent-calls/agent-call-policy";
import { sealSecret, hashToolKey } from "../sarvam/sarvam-secrets";
import { BOOKING_PROMPT, TOOLS } from "../sarvam/sarvam-booking-config";
import { isPanelActor } from "./panel-auth";

const uuid = z.string().uuid();
const ticketStatus = z.enum(["open", "in_progress", "resolved", "closed"]);
const requestStatus = z.enum([
  "requested",
  "in_review",
  "setting_up",
  "active",
  "paused",
  "rejected",
]);
const connectionSchema = z.object({
  api_key: z.string().trim().min(8).max(500).optional(),
  sarvam_org_id: z
    .string()
    .trim()
    .regex(/^[A-Za-z0-9_-]{1,100}$/, "Invalid organization ID."),
  workspace_id: z
    .string()
    .trim()
    .regex(/^[A-Za-z0-9_-]{1,100}$/, "Invalid workspace ID."),
  app_id: z
    .string()
    .trim()
    .regex(/^[A-Za-z0-9_-]{1,100}$/, "Invalid app ID."),
  version: z.number().int().nonnegative(),
  phone_number: z
    .string()
    .trim()
    .regex(
      /^\+[1-9][0-9]{7,14}$/,
      "Enter the booking number with country code, for example +919876543210.",
    ),
  deployment_id: z
    .string()
    .trim()
    .regex(/^[A-Za-z0-9_-]{1,200}$/, "Enter the deployment ID."),
  approved_services: serviceSelection,
});
const replySchema = z.object({ body: z.string().trim().min(1).max(4000) });
const statusSchema = z.object({ status: ticketStatus });
const activeSchema = z.object({ active: z.boolean() });
const requestUpdateSchema = z.object({
  version: z.number().int().positive(),
  status: requestStatus,
  admin_note: z.string().trim().max(2000).optional(),
  user_message: z.string().trim().max(500).optional(),
});

function id(value: string) {
  const parsed = uuid.safeParse(value);
  if (!parsed.success) throw new BadRequestException("Invalid identifier.");
  return parsed.data;
}
function parse<T>(schema: z.ZodType<T>, value: unknown) {
  const parsed = schema.safeParse(value);
  if (!parsed.success)
    throw new BadRequestException(
      parsed.error.issues[0]?.message ?? "Invalid request.",
    );
  return parsed.data;
}
function search(value: unknown) {
  return `%${String(value ?? "")
    .trim()
    .slice(0, 80)
    .replace(/[\\%_]/g, "\\$&")}%`;
}
function page(value: unknown) {
  const n = Number(value);
  return Number.isInteger(n) && n > 0 ? Math.min(n, 500) : 100;
}

/** Platform administration accepts a verified panel request or an explicitly
 * authorized legacy platform actor. Organization secrets are never returned. */
@Injectable()
export class AdminService {
  constructor(
    private readonly db: Database,
    private readonly provider: SarvamService,
  ) {}

  private async admin(actor: Actor) {
    if (isPanelActor(actor)) return { role: "super_admin", email: actor.email };
    const { rows } = await this.db.query<{ role: string; email: string }>(
      "SELECT role,email FROM platform_admins WHERE active AND (user_id=$1 OR email=$2)",
      [actor.uid, actor.email.toLowerCase()],
    );
    if (!rows[0]) throw new ForbiddenException("Admin access required.");
    return rows[0];
  }
  async superAdmin(actor: Actor) {
    const admin = await this.admin(actor);
    if (admin.role !== "super_admin")
      throw new ForbiddenException("Super-admin access required.");
    return admin;
  }
  private async audit(
    admin: { email: string },
    action: string,
    type: string,
    target: string,
    detail: object = {},
  ) {
    await this.db.query(
      "INSERT INTO admin_audit_log(id,admin_email,action,target_type,target_id,detail) VALUES($1,$2,$3,$4,$5,$6)",
      [randomUUID(), admin.email, action, type, target, JSON.stringify(detail)],
    );
  }

  async me(actor: Actor) {
    const a = await this.admin(actor);
    return { email: a.email, role: a.role };
  }

  async overview(actor: Actor) {
    await this.admin(actor);
    const { rows } = await this.db.query(
      `SELECT
        (SELECT count(*)::int FROM organizations) AS organizations,
        (SELECT count(*)::int FROM memberships) AS users,
        (SELECT count(*)::int FROM memberships WHERE active) AS active_users,
        (SELECT count(*)::int FROM businesses) AS businesses,
        (SELECT count(*)::int FROM bookings) AS bookings,
        (SELECT count(*)::int FROM customers) AS customers,
        (SELECT count(*)::int FROM support_tickets WHERE status IN ('open','in_progress')) AS open_tickets,
        (SELECT count(*)::int FROM agent_call_requests WHERE status IN ('requested','in_review','setting_up')) AS pending_agent_requests`,
    );
    return rows[0];
  }

  async organizations(actor: Actor, query: Record<string, string>) {
    await this.admin(actor);
    const { rows } = await this.db.query(
      `SELECT o.id,o.name,o.contact_phone,o.currency,o.created_at,
        (SELECT count(*)::int FROM memberships m WHERE m.organization_id=o.id) AS users,
        (SELECT count(*)::int FROM businesses b WHERE b.organization_id=o.id) AS businesses,
        (SELECT count(*)::int FROM bookings k WHERE k.organization_id=o.id) AS bookings,
        (SELECT email FROM memberships m WHERE m.organization_id=o.id AND m.role='owner' LIMIT 1) AS owner_email,
        (SELECT status FROM agent_call_requests r WHERE r.organization_id=o.id) AS agent_status
       FROM organizations o
       WHERE o.name ILIKE $1 ESCAPE '\\'
          OR EXISTS(SELECT 1 FROM memberships m WHERE m.organization_id=o.id AND m.email ILIKE $1 ESCAPE '\\')
       ORDER BY o.created_at DESC LIMIT $2`,
      [search(query.q), page(query.limit)],
    );
    return { organizations: rows };
  }

  async organization(actor: Actor, orgId: string) {
    await this.admin(actor);
    const oid = id(orgId);
    const one = async (sql: string) => (await this.db.query(sql, [oid])).rows;
    const [org] = await one("SELECT * FROM organizations WHERE id=$1");
    if (!org) throw new NotFoundException("Organization not found.");
    const [
      locations,
      businesses,
      members,
      invitations,
      stats,
      website,
      agent,
      tickets,
    ] = await Promise.all([
      one("SELECT * FROM locations WHERE organization_id=$1 ORDER BY name"),
      one(
        `SELECT b.id,b.name,b.type,b.status,b.version,
            (SELECT count(*)::int FROM resources r WHERE r.business_id=b.id) AS resources
           FROM businesses b WHERE b.organization_id=$1 ORDER BY b.name`,
      ),
      one(
        "SELECT id,email,display_name,role,permissions,active FROM memberships WHERE organization_id=$1 ORDER BY role,email",
      ),
      one(
        `SELECT id,email,display_name,role,expires_at,created_at,accepted_at,revoked_at
           FROM invitations WHERE organization_id=$1 ORDER BY created_at DESC LIMIT 50`,
      ),
      one(
        `SELECT
            (SELECT count(*)::int FROM bookings WHERE organization_id=$1) AS bookings,
            (SELECT count(*)::int FROM bookings WHERE organization_id=$1 AND status='cancelled') AS cancelled,
            (SELECT coalesce(sum(total_minor),0)::bigint FROM bookings WHERE organization_id=$1 AND status IN ('confirmed','completed')) AS booked_minor,
            (SELECT count(*)::int FROM customers WHERE organization_id=$1) AS customers,
            (SELECT max(created_at) FROM bookings WHERE organization_id=$1) AS last_booking_at`,
      ),
      one(
        "SELECT slug,title,status FROM booking_websites WHERE organization_id=$1",
      ),
      one(
        "SELECT id,status,note,admin_note,user_message,created_at,updated_at FROM agent_call_requests WHERE organization_id=$1",
      ),
      one(
        "SELECT id,subject,category,status,created_at,updated_at FROM support_tickets WHERE organization_id=$1 ORDER BY updated_at DESC LIMIT 20",
      ),
    ]);
    return {
      organization: org,
      locations,
      businesses,
      members,
      invitations,
      stats: stats[0],
      website: website[0] ?? null,
      agent_request: agent[0] ?? null,
      tickets,
    };
  }

  async users(actor: Actor, query: Record<string, string>) {
    await this.admin(actor);
    const { rows } = await this.db.query(
      `SELECT m.id,m.email,m.display_name,m.role,m.active,m.organization_id,o.name AS organization_name
       FROM memberships m JOIN organizations o ON o.id=m.organization_id
       WHERE m.email ILIKE $1 ESCAPE '\\' OR m.display_name ILIKE $1 ESCAPE '\\' OR o.name ILIKE $1 ESCAPE '\\'
       ORDER BY o.name,m.role,m.email LIMIT $2`,
      [search(query.q), page(query.limit)],
    );
    return { users: rows };
  }

  async setUserActive(actor: Actor, membershipId: string, body: unknown) {
    const admin = await this.admin(actor);
    const mid = id(membershipId);
    const { active } = parse(activeSchema, body);
    const { rows } = await this.db.query<{ role: string; email: string }>(
      "SELECT role,email FROM memberships WHERE id=$1",
      [mid],
    );
    if (!rows[0]) throw new NotFoundException("User not found.");
    if (rows[0].role === "owner" && !active)
      throw new BadRequestException(
        "An organization owner cannot be deactivated here.",
      );
    await this.db.query("UPDATE memberships SET active=$2 WHERE id=$1", [
      mid,
      active,
    ]);
    await this.audit(
      admin,
      active ? "user.activate" : "user.deactivate",
      "membership",
      mid,
      {
        email: rows[0].email,
      },
    );
    return { id: mid, active };
  }

  async tickets(actor: Actor, query: Record<string, string>) {
    await this.admin(actor);
    const status = ticketStatus.safeParse(query.status);
    const { rows } = await this.db.query(
      `SELECT t.id,t.subject,t.category,t.status,t.created_at,t.updated_at,t.organization_id,
        o.name AS organization_name,COALESCE(m.email,'') AS user_email,COALESCE(m.display_name,'Removed team member') AS user_name
       FROM support_tickets t
       JOIN organizations o ON o.id=t.organization_id
       LEFT JOIN memberships m ON m.id=t.membership_id AND m.organization_id=t.organization_id
       WHERE ($1::text IS NULL OR t.status=$1)
       ORDER BY t.updated_at DESC LIMIT $2`,
      [status.success ? status.data : null, page(query.limit)],
    );
    return { tickets: rows };
  }

  async ticket(actor: Actor, ticketId: string) {
    await this.admin(actor);
    const tid = id(ticketId);
    const { rows } = await this.db.query(
      `SELECT t.id,t.subject,t.category,t.status,t.created_at,t.updated_at,t.organization_id,
        o.name AS organization_name,COALESCE(m.email,'') AS user_email,COALESCE(m.display_name,'Removed team member') AS user_name
       FROM support_tickets t
       JOIN organizations o ON o.id=t.organization_id
       LEFT JOIN memberships m ON m.id=t.membership_id AND m.organization_id=t.organization_id WHERE t.id=$1`,
      [tid],
    );
    if (!rows[0]) throw new NotFoundException("Ticket not found.");
    const messages = await this.db.query(
      "SELECT id,author,author_name,body,created_at FROM support_messages WHERE ticket_id=$1 ORDER BY created_at",
      [tid],
    );
    return { ticket: rows[0], messages: messages.rows };
  }

  async reply(actor: Actor, ticketId: string, body: unknown) {
    const admin = await this.admin(actor);
    const tid = id(ticketId);
    const { body: text } = parse(replySchema, body);
    const found = await this.db.query(
      "SELECT 1 FROM support_tickets WHERE id=$1",
      [tid],
    );
    if (!found.rows[0]) throw new NotFoundException("Ticket not found.");
    await this.db.query(
      "INSERT INTO support_messages(id,ticket_id,author,author_name,body) VALUES($1,$2,'admin',$3,$4)",
      [randomUUID(), tid, actor.name, text],
    );
    await this.db.query(
      "UPDATE support_tickets SET updated_at=now(), status=CASE WHEN status='open' THEN 'in_progress' ELSE status END WHERE id=$1",
      [tid],
    );
    await this.audit(admin, "ticket.reply", "ticket", tid);
    return this.ticket(actor, tid);
  }

  async setTicketStatus(actor: Actor, ticketId: string, body: unknown) {
    const admin = await this.admin(actor);
    const tid = id(ticketId);
    const { status } = parse(statusSchema, body);
    const { rows } = await this.db.query(
      "UPDATE support_tickets SET status=$2, updated_at=now() WHERE id=$1 RETURNING id",
      [tid, status],
    );
    if (!rows[0]) throw new NotFoundException("Ticket not found.");
    await this.audit(admin, "ticket.status", "ticket", tid, { status });
    return { id: tid, status };
  }

  async agentRequests(actor: Actor, query: Record<string, string>) {
    await this.admin(actor);
    const status = requestStatus.safeParse(query.status);
    const { rows } = await this.db.query(
      `SELECT r.id,r.status,r.note,r.admin_note,r.user_message,r.created_at,r.updated_at,r.version,r.requested_services,r.approved_services,
        r.organization_id,o.name AS organization_name,coalesce(m.email,'') AS user_email,coalesce(m.display_name,'Removed team member') AS user_name
       FROM agent_call_requests r
       JOIN organizations o ON o.id=r.organization_id
       LEFT JOIN memberships m ON m.id=r.membership_id AND m.organization_id=r.organization_id
       WHERE ($1::text IS NULL OR r.status=$1)
       ORDER BY r.updated_at DESC LIMIT $2`,
      [status.success ? status.data : null, page(query.limit)],
    );
    return { requests: rows };
  }

  async updateAgentRequest(actor: Actor, requestId: string, body: unknown) {
    const admin = await this.superAdmin(actor);
    const rid = id(requestId),
      input = parse(requestUpdateSchema, body);
    const before = (
      await this.db.query<any>(
        "SELECT organization_id FROM agent_call_requests WHERE id=$1",
        [rid],
      )
    ).rows[0];
    if (!before) throw new NotFoundException("Request not found.");
    await this.db.transaction(async (db) => {
      const connection = (
        await db.query<any>(
          "SELECT * FROM sarvam_integrations WHERE organization_id=$1 FOR UPDATE",
          [before.organization_id],
        )
      ).rows[0];
      const request = (
        await db.query<any>(
          "SELECT * FROM agent_call_requests WHERE id=$1 FOR UPDATE",
          [rid],
        )
      ).rows[0];
      if (request.version !== input.version)
        throw new ConflictException("Request changed. Refresh and try again.");
      if (
        input.status === "active" &&
        (!connection?.verified_at ||
          !connection.phone_number ||
          !connection.api_key_ciphertext ||
          !connection.tool_key_hash ||
          !request.approved_services.length)
      )
        throw new BadRequestException(
          "Verify the connection, assigned number and approved services before activating.",
        );
      await db.query(
        `UPDATE agent_call_requests SET status=$2,admin_note=coalesce($3,admin_note),user_message=coalesce($4,user_message),updated_at=now(),version=version+1 WHERE id=$1`,
        [
          rid,
          input.status,
          input.admin_note ?? null,
          input.user_message ?? null,
        ],
      );
      // Activation never turns the client switch on; suspension always turns it off.
      if (connection && input.status !== "active") {
        await db.query(
          "UPDATE sarvam_integrations SET enabled=false,version=version+1,updated_at=now() WHERE organization_id=$1",
          [before.organization_id],
        );
        await db.query("UPDATE memberships SET active=false WHERE id=$1", [
          connection.membership_id,
        ]);
      }
      await db.query(
        "INSERT INTO admin_audit_log(id,admin_email,action,target_type,target_id,detail) VALUES($1,$2,'agent_request.update','agent_request',$3,$4)",
        [
          randomUUID(),
          admin.email,
          rid,
          JSON.stringify({ status: input.status }),
        ],
      );
    });
    return { id: rid, status: input.status };
  }

  async auditLog(actor: Actor, query: Record<string, string>) {
    await this.admin(actor);
    const { rows } = await this.db.query(
      "SELECT id,admin_email,action,target_type,target_id,detail,created_at FROM admin_audit_log ORDER BY created_at DESC LIMIT $1",
      [page(query.limit)],
    );
    return { events: rows };
  }

  /** The organization owner, whose identity the provider setup code expects. */
  private async ownerActor(orgId: string): Promise<Actor> {
    const { rows } = await this.db.query<{
      user_id: string;
      email: string;
      display_name: string;
    }>(
      "SELECT user_id,email,display_name FROM memberships WHERE organization_id=$1 AND role='owner' AND active LIMIT 1",
      [id(orgId)],
    );
    if (!rows[0]) throw new NotFoundException("Organization owner not found.");
    return {
      uid: rows[0].user_id,
      email: rows[0].email,
      name: rows[0].display_name,
    };
  }
  private async connectionState(orgId: string) {
    const owner = await this.ownerActor(orgId);
    const settings = await this.provider.settings(owner);
    const request = (
      await this.db.query<any>(
        "SELECT id,status,note,admin_note,user_message,requested_services,approved_services,version FROM agent_call_requests WHERE organization_id=$1",
        [orgId],
      )
    ).rows[0];
    if (!request) throw new NotFoundException("Request not found.");
    const s = (
      await this.db.query<any>(
        "SELECT phone_number,deployment_id,verified_at,verified_by FROM sarvam_integrations WHERE organization_id=$1",
        [orgId],
      )
    ).rows[0];
    return {
      version: settings.version,
      enabled: settings.enabled,
      has_api_key: settings.has_credentials,
      api_key_last4: settings.api_key_last4,
      sarvam_org_id: settings.sarvam_org_id,
      workspace_id: settings.workspace_id,
      app_id: settings.app_id,
      has_tool_key: !!settings.tool_key_prefix,
      tool_key_prefix: settings.tool_key_prefix,
      tool_base_url: settings.tool_base_url,
      phone_number: s?.phone_number ?? "",
      deployment_id: s?.deployment_id ?? "",
      verified_at: s?.verified_at ?? null,
      verified_by: s?.verified_by ?? "",
      request,
      instructions: BOOKING_PROMPT,
      tools: TOOLS.map(([name, path, fields]) => ({ name, path, fields })),
    };
  }
  async connection(actor: Actor, orgId: string) {
    await this.superAdmin(actor);
    return this.connectionState(id(orgId));
  }
  async saveConnection(actor: Actor, orgId: string, body: unknown) {
    const admin = await this.superAdmin(actor),
      org = id(orgId),
      input = parse(connectionSchema, body);
    await this.db.transaction(async (db) => {
      const s = await this.provider.ensureManaged(db, org);
      // ensureManaged serializes first creation; explicitly lock existing configuration too.
      const current = (
        await db.query<any>(
          "SELECT * FROM sarvam_integrations WHERE organization_id=$1 FOR UPDATE",
          [org],
        )
      ).rows[0];
      const request = (
        await db.query<any>(
          "SELECT * FROM agent_call_requests WHERE organization_id=$1 FOR UPDATE",
          [org],
        )
      ).rows[0];
      if (!request) throw new NotFoundException("Request not found.");
      if (
        input.version === 0
          ? current.version !== 1
          : current.version !== input.version
      )
        throw new ConflictException(
          "Connection changed. Refresh and try again.",
        );
      if (
        input.approved_services.some(
          (x) => !request.requested_services.includes(x),
        )
      )
        throw new BadRequestException(
          "Approve only services requested by the client.",
        );
      if (!current.api_key_ciphertext && !input.api_key)
        throw new BadRequestException("Enter the Sarvam API key.");
      const duplicate = (
        await db.query(
          "SELECT 1 FROM sarvam_integrations WHERE organization_id<>$1 AND (phone_number=$2 OR (sarvam_org_id=$3 AND workspace_id=$4 AND app_id=$5))",
          [
            org,
            input.phone_number,
            input.sarvam_org_id,
            input.workspace_id,
            input.app_id,
          ],
        )
      ).rows.length;
      if (duplicate)
        throw new ConflictException(
          "This phone number or agent is already assigned to another organization.",
        );
      if (["admin_mcp", "codex_mcp"].includes(current.setup_state?.mode))
        throw new ConflictException(
          "This connection is managed automatically. Use its provisioning controls instead of manual configuration.",
        );
      if (
        current.setup_lease_until &&
        new Date(current.setup_lease_until).getTime() > Date.now()
      )
        throw new ConflictException(
          "Provider setup is running. Retry when it finishes.",
        );
      if (
        current.sarvam_org_id !== input.sarvam_org_id ||
        current.workspace_id !== input.workspace_id ||
        current.app_id !== input.app_id
      ) {
        await db.query(
          "UPDATE sarvam_integrations SET tool_key_hash=NULL,tool_key_prefix='' WHERE organization_id=$1",
          [org],
        );
      }
      await db.query(
        `UPDATE sarvam_integrations SET enabled=false,api_key_ciphertext=$2,api_key_last4=$3,sarvam_org_id=$4,workspace_id=$5,app_id=$6,
        phone_number=$7,deployment_id=$8,verified_at=NULL,verified_by='',version=version+1,updated_at=now(),setup_status='legacy',
        oauth_state_hash=NULL,oauth_pending_ciphertext=NULL,authoring_ciphertext=NULL,pending_tool_key_hash=NULL,tool_key_ciphertext=NULL,setup_state='{}',setup_error='' WHERE organization_id=$1`,
        [
          org,
          input.api_key
            ? sealSecret(input.api_key)
            : current.api_key_ciphertext,
          input.api_key ? input.api_key.slice(-4) : current.api_key_last4,
          input.sarvam_org_id,
          input.workspace_id,
          input.app_id,
          input.phone_number,
          input.deployment_id,
        ],
      );
      await db.query("UPDATE memberships SET active=false WHERE id=$1", [
        s.membership_id,
      ]);
      await db.query(
        "UPDATE agent_call_requests SET approved_services=$2,status=CASE WHEN status IN ('requested','in_review','active') THEN 'setting_up' ELSE status END,version=version+1,updated_at=now() WHERE organization_id=$1",
        [org, input.approved_services],
      );
      await db.query(
        "INSERT INTO admin_audit_log(id,admin_email,action,target_type,target_id,detail) VALUES($1,$2,'agent_connection.save','organization',$3,$4)",
        [
          randomUUID(),
          admin.email,
          org,
          JSON.stringify({ services: input.approved_services }),
        ],
      );
    });
    return this.connectionState(org);
  }
  async verifyConnection(actor: Actor, orgId: string, body: unknown) {
    const admin = await this.superAdmin(actor),
      org = id(orgId);
    const input = parse(
      z
        .object({
          version: z.number().int().positive(),
          tools_confirmed: z.literal(true),
        })
        .strict(),
      body,
    );
    const s = (
      await this.db.query<any>(
        "SELECT * FROM sarvam_integrations WHERE organization_id=$1",
        [org],
      )
    ).rows[0];
    if (!s || s.version !== input.version)
      throw new ConflictException("Connection changed. Refresh and try again.");
    await this.provider.verifyDeployment(s);
    await this.provider.test(await this.ownerActor(org));
    await this.db.transaction(async (db) => {
      const result = await db.query(
        "UPDATE sarvam_integrations SET verified_at=now(),verified_by=$3,version=version+1,updated_at=now() WHERE organization_id=$1 AND version=$2 RETURNING organization_id",
        [org, input.version, admin.email],
      );
      if (!result.rows.length)
        throw new ConflictException(
          "Connection changed during verification. Verify again.",
        );
      await db.query(
        "INSERT INTO admin_audit_log(id,admin_email,action,target_type,target_id) VALUES($1,$2,'agent_connection.verified','organization',$3)",
        [randomUUID(), admin.email, org],
      );
    });
    return this.connectionState(org);
  }
  async rotateToolKey(actor: Actor, orgId: string) {
    const admin = await this.superAdmin(actor),
      org = id(orgId);
    const key = "bkv_" + randomBytes(32).toString("base64url");
    await this.db.transaction(async (db) => {
      const s = (
        await db.query<any>(
          "SELECT * FROM sarvam_integrations WHERE organization_id=$1 FOR UPDATE",
          [org],
        )
      ).rows[0];
      if (!s) throw new BadRequestException("Save the connection first.");
      if (["admin_mcp", "codex_mcp"].includes(s.setup_state?.mode))
        throw new ConflictException(
          "This key is managed automatically. Manual rotation would disconnect the agent.",
        );
      if (
        s.setup_lease_until &&
        new Date(s.setup_lease_until).getTime() > Date.now()
      )
        throw new ConflictException(
          "Provider setup is running. Retry when it finishes.",
        );
      await db.query(
        "UPDATE sarvam_integrations SET tool_key_hash=$2,tool_key_prefix=$3,enabled=false,verified_at=NULL,verified_by='',version=version+1,updated_at=now() WHERE organization_id=$1",
        [org, hashToolKey(key), key.slice(0, 10)],
      );
      await db.query("UPDATE memberships SET active=false WHERE id=$1", [
        s.membership_id,
      ]);
      await db.query(
        "UPDATE agent_call_requests SET status=CASE WHEN status='active' THEN 'setting_up' ELSE status END,version=version+1,updated_at=now() WHERE organization_id=$1",
        [org],
      );
      await db.query(
        "INSERT INTO admin_audit_log(id,admin_email,action,target_type,target_id) VALUES($1,$2,'agent_connection.tool_key','organization',$3)",
        [randomUUID(), admin.email, org],
      );
    });
    return { tool_key: key, tool_key_prefix: key.slice(0, 10) };
  }
}
