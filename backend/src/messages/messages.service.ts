import {
  Injectable,
  BadRequestException,
  ForbiddenException,
  ConflictException,
  NotFoundException,
} from "@nestjs/common";
import { z } from "zod";
import { Database } from "../common/database";
import { Actor } from "../common/auth.guard";
import { WorkspaceService } from "../workspace/workspace.service";
export const fields = [
  "customer_name",
  "booking_reference",
  "venue_name",
  "space_name",
  "booking_date",
  "start_time",
  "end_time",
  "subtotal",
  "discount",
  "booking_total",
  "amount_received",
  "balance_due",
  "organization_name",
  "website",
  "booking_status",
] as const;
export const defaultBody = `Dear {customer_name},
Your booking has been {booking_status}.

*Booking Details*

• Booking ID: *{booking_reference}*
• Venue: *{venue_name}*
• Slot: *{space_name}*
• Date: *{booking_date}*
• Time: *{start_time} - {end_time}*

*Payment Summary*

• Slot Amount: *{booking_total}*
• Pending Amount: *{balance_due}*

Thank you for booking with us!
We look forward to seeing you!

Best regards,
{organization_name}`;
export function templateError(body: string): string | undefined {
  if (!body.trim() || body.length > 6000)
    return "Write a message of 1–6000 characters.";
  const tokens = [...body.matchAll(/\{([^{}]*)\}/g)];
  const unknown = tokens.find(
    (t) => !(fields as readonly string[]).includes(t[1]),
  );
  if (unknown) return `Unknown field: {${unknown[1]}}.`;
  if (/[{}]/.test(body.replace(/\{[^{}]*\}/g, "")))
    return "Complete every field using {field_name}.";
}
const bodySchema = z
  .string()
  .max(6000)
  .superRefine((v, ctx) => {
    const error = templateError(v);
    if (error) ctx.addIssue({ code: "custom", message: error });
  });
const builtin = {
  id: "default",
  name: "Booking confirmation",
  body: defaultBody,
  website_url: "",
  is_builtin: true,
  is_primary: true,
};
@Injectable()
export class MessagesService {
  constructor(
    private readonly db: Database,
    private readonly workspace: WorkspaceService,
  ) {}
  async catalog(actor: Actor) {
    const m = await this.workspace.member(actor);
    if (
      m.role !== "owner" &&
      ![
        "view_bookings",
        "manage_bookings",
        "collect_payments",
        "view_finance",
      ].some((p) => m.permissions.includes(p))
    )
      throw new ForbiddenException("Booking access is required.");
    const rows = (
      await this.db.query(
        "SELECT id,name,body,website_url,is_primary FROM booking_message_templates WHERE organization_id=$1 ORDER BY created_at,id",
        [m.organization_id],
      )
    ).rows;
    return {
      can_manage: m.role === "owner",
      templates: [
        { ...builtin, is_primary: !rows.some((r) => r.is_primary) },
        ...rows.map((r) => ({ ...r, is_builtin: false })),
      ],
    };
  }
  async create(actor: Actor, input: unknown) {
    const v = z
      .object({
        command_key: z.uuid(),
        name: z.string().trim().min(2).max(80),
        body: bodySchema,
        website_url: z
          .string()
          .max(500)
          .default("")
          .refine(
            (v) =>
              !v ||
              (/^https?:\/\//.test(v) &&
                (() => {
                  try {
                    return !!new URL(v).hostname;
                  } catch {
                    return false;
                  }
                })()),
            "Use an http or https website URL.",
          ),
      })
      .strict()
      .parse(input);
    return this.db.transaction(async (db) => {
      const m = await this.workspace.member(actor, true, db);
      await db.query("SELECT id FROM organizations WHERE id=$1 FOR UPDATE", [
        m.organization_id,
      ]);
      const old = (
        await db.query(
          "SELECT id,name,body,website_url FROM booking_message_templates WHERE id=$1 AND organization_id=$2",
          [v.command_key, m.organization_id],
        )
      ).rows[0];
      if (old) {
        if (
          old.name !== v.name ||
          old.body !== v.body ||
          old.website_url !== v.website_url
        )
          throw new ConflictException(
            "This request key belongs to another template.",
          );
        return { id: old.id };
      }
      const rows = (
        await db.query(
          "SELECT name FROM booking_message_templates WHERE organization_id=$1",
          [m.organization_id],
        )
      ).rows;
      if (rows.length >= 50)
        throw new BadRequestException("You can save up to 50 templates.");
      if (
        rows.some((r) => String(r.name).toLowerCase() === v.name.toLowerCase())
      )
        throw new ConflictException("Choose a different template name.");
      await db.query(
        "INSERT INTO booking_message_templates(id,organization_id,name,body,website_url) VALUES($1,$2,$3,$4,$5)",
        [v.command_key, m.organization_id, v.name, v.body, v.website_url],
      );
      await this.workspace.audit(
        db,
        actor,
        m.organization_id,
        "message_template_created",
        v.command_key,
      );
      return { id: v.command_key };
    });
  }
  async primary(actor: Actor, input: unknown) {
    const v = z
      .object({ id: z.union([z.uuid(), z.literal("default")]) })
      .strict()
      .parse(input);
    return this.db.transaction(async (db) => {
      const m = await this.workspace.member(actor, true, db);
      await db.query("SELECT id FROM organizations WHERE id=$1 FOR UPDATE", [
        m.organization_id,
      ]);
      if (
        v.id !== "default" &&
        !(
          await db.query(
            "SELECT id FROM booking_message_templates WHERE id=$1 AND organization_id=$2",
            [v.id, m.organization_id],
          )
        ).rows.length
      )
        throw new NotFoundException("Template unavailable.");
      await db.query(
        "UPDATE booking_message_templates SET is_primary=false WHERE organization_id=$1",
        [m.organization_id],
      );
      if (v.id !== "default")
        await db.query(
          "UPDATE booking_message_templates SET is_primary=true WHERE id=$1 AND organization_id=$2",
          [v.id, m.organization_id],
        );
      await this.workspace.audit(
        db,
        actor,
        m.organization_id,
        "message_template_primary",
        m.organization_id,
      );
      return { id: v.id };
    });
  }
  async remove(actor: Actor, id: string) {
    z.uuid().parse(id);
    return this.db.transaction(async (db) => {
      const m = await this.workspace.member(actor, true, db);
      await db.query("SELECT id FROM organizations WHERE id=$1 FOR UPDATE", [
        m.organization_id,
      ]);
      const result = await db.query(
        "DELETE FROM booking_message_templates WHERE id=$1 AND organization_id=$2 RETURNING id",
        [id, m.organization_id],
      );
      if (!result.rows.length)
        throw new NotFoundException("Template unavailable.");
      await this.workspace.audit(
        db,
        actor,
        m.organization_id,
        "message_template_deleted",
        id,
      );
      return { id };
    });
  }
}
