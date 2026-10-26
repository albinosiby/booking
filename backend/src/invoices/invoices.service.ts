import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { createHash, randomUUID } from "node:crypto";
import { z } from "zod";
import { Database, Queryable } from "../common/database";
import { Actor } from "../common/auth.guard";
import { WorkspaceService } from "../workspace/workspace.service";
import { BookingService } from "../bookings/booking.service";
import { localStamp } from "../bookings/booking.inventory";
import { renderInvoice } from "./invoices.pdf";
type Row = Record<string, any>;
const settingsSchema = z.object({ enabled: z.boolean() }).strict();
const generateSchema = z.object({ command_key: z.uuid() }).strict();
const COLUMNS =
  "id,booking_id,invoice_number,total_minor,paid_minor,balance_minor,currency,generated_by_name,generated_at";
const image = (data: unknown, type: unknown) =>
  data && type
    ? { data: Buffer.from(data as Buffer), content_type: String(type) }
    : null;
@Injectable()
export class InvoicesService {
  constructor(
    private readonly db: Database,
    private readonly workspace: WorkspaceService,
    private readonly bookings: BookingService,
  ) {}
  private present(r: Row, reused = false) {
    return {
      id: r.id,
      booking_id: r.booking_id,
      invoice_number: r.invoice_number,
      total_minor: Number(r.total_minor),
      paid_minor: Number(r.paid_minor),
      balance_minor: Number(r.balance_minor),
      currency: r.currency,
      generated_by_name: r.generated_by_name,
      generated_at: r.generated_at,
      reused,
    };
  }
  private async enabled(db: Queryable, org: string) {
    const row = (
      await db.query<Row>(
        "SELECT enabled FROM booking_invoice_settings WHERE organization_id=$1",
        [org],
      )
    ).rows[0];
    return row ? row.enabled === true : true; // invoices are ON until the owner turns them off
  }
  async settings(actor: Actor) {
    const m = await this.workspace.member(actor);
    return { enabled: await this.enabled(this.db, m.organization_id) };
  }
  async saveSettings(actor: Actor, input: unknown) {
    const v = settingsSchema.parse(input);
    await this.db.transaction(async (db) => {
      const m = await this.workspace.member(actor, true, db);
      await db.query(
        `INSERT INTO booking_invoice_settings(organization_id,enabled,updated_by) VALUES($1,$2,$3)
         ON CONFLICT(organization_id) DO UPDATE SET enabled=EXCLUDED.enabled,updated_by=EXCLUDED.updated_by,updated_at=now()`,
        [m.organization_id, v.enabled, actor.uid],
      );
      await this.workspace.audit(
        db,
        actor,
        m.organization_id,
        v.enabled ? "invoices.enabled" : "invoices.disabled",
        m.organization_id,
      );
    });
    return this.settings(actor);
  }
  // Everything printed on the invoice, captured at generation time.
  private async build(actor: Actor, bookingId: string) {
    const db = this.db;
    const b: Row = await this.bookings.detail(actor, bookingId);
    const org = (
      await db.query<Row>(
        "SELECT name,contact_phone,currency FROM organizations WHERE id=$1",
        [b.organization_id],
      )
    ).rows[0];
    const loc = (
      await db.query<Row>(
        "SELECT l.* FROM businesses x JOIN locations l ON l.id=x.location_id WHERE x.id=$1",
        [b.business_id],
      )
    ).rows[0];
    const logo = (
      await db.query<Row>(
        "SELECT content_type,data FROM logo_assets WHERE organization_id=$1",
        [b.organization_id],
      )
    ).rows[0];
    const upi = (
      await db.query<Row>(
        "SELECT upi_id,qr_data,qr_content_type FROM website_payment_settings WHERE organization_id=$1",
        [b.organization_id],
      )
    ).rows[0];
    // Space-level route wins over the business-level route for the same method.
    const routes = (
      await db.query<Row>(
        `SELECT DISTINCT ON (method) method,account_id FROM payment_routes
         WHERE organization_id=$1 AND business_id=$2 AND (resource_id=$3 OR resource_id IS NULL) AND method IN ('upi','bank_transfer')
         ORDER BY method,(resource_id IS NULL)`,
        [b.organization_id, b.business_id, b.resource_id],
      )
    ).rows;
    const ids = [...new Set(routes.map((r) => r.account_id))];
    const accounts = (
      await db.query<Row>(
        `SELECT id,name,bank_name,last_four,account_number,is_primary FROM money_accounts
         WHERE organization_id=$1 AND kind='bank' AND active AND (id = ANY($2::uuid[]) OR ($3 AND is_primary))
         ORDER BY is_primary DESC,name`,
        [b.organization_id, ids, ids.length === 0],
      )
    ).rows;
    const snap = b.price_snapshot,
      cancelled = b.status === "cancelled";
    const discount = snap.selection?.discount;
    const snapshot = {
      currency: org.currency,
      generated_local: localStamp(Date.now(), snap.timezone),
      organization: {
        name: org.name,
        phone: org.contact_phone,
        address_lines: [
          loc?.name,
          [loc?.address_line_1, loc?.address_line_2].filter(Boolean).join(", "),
          [loc?.city, loc?.postal_code].filter(Boolean).join(" "),
        ].filter(Boolean),
      },
      customer: {
        name: b.customer_snapshot?.name ?? "",
        phone: b.customer_snapshot?.phone ?? "",
      },
      booking: {
        reference: b.reference,
        status: b.status,
        business_name: snap.business_name,
        space_name: snap.space_name,
        option_name: snap.option_name ?? null,
        people: b.people,
        notes: b.notes,
        local_start: b.local_start,
        local_end: b.local_end,
        timezone: snap.timezone,
      },
      price: {
        subtotal_minor: snap.subtotal_minor ?? b.total_minor,
        discount_minor: snap.discount_minor ?? 0,
        discount_reason: discount?.reason ?? "",
        total_minor: cancelled ? 0 : b.total_minor,
      },
      payments: b.payments.map((p: Row) => ({
        kind: p.kind,
        method: p.method,
        amount_minor: p.amount_minor,
        local_received: p.local_received,
      })),
      paid_minor: b.net_paid_minor,
      balance_minor: b.balance_minor,
      refund_due_minor: b.refund_due_minor,
      bank_accounts: accounts.map((a) => ({
        name: a.name,
        bank_name: a.bank_name,
        last_four: a.last_four,
        account_number: a.account_number ?? null,
      })),
      upi_id: upi?.upi_id ?? "",
    };
    return {
      booking: b,
      snapshot,
      logo: image(logo?.data, logo?.content_type),
      qr: image(upi?.qr_data, upi?.qr_content_type),
    };
  }
  async generate(actor: Actor, bookingId: string, input: unknown) {
    const v = generateSchema.parse(input);
    const org = (await this.workspace.member(actor)).organization_id;
    if (!(await this.enabled(this.db, org)))
      throw new ForbiddenException(
        "Invoices are turned off for this organization.",
      );
    // Booking access checks run their own transaction, so the snapshot is built before ours opens.
    const built = await this.build(actor, bookingId);
    const hash = createHash("sha256")
      .update(JSON.stringify({ ...built.snapshot, generated_local: null }))
      .update(built.logo?.data ?? "")
      .update(built.qr?.data ?? "")
      .digest("hex");
    return this.db.transaction(async (db) => {
      await db.query("SELECT id FROM organizations WHERE id=$1 FOR UPDATE", [
        org,
      ]);
      const m = await this.workspace.member(actor, false, db);
      const again = (
        await db.query<Row>(
          `SELECT ${COLUMNS},booking_id FROM booking_invoices WHERE organization_id=$1 AND command_key=$2`,
          [org, v.command_key],
        )
      ).rows[0];
      if (again) {
        if (again.booking_id !== bookingId)
          throw new ConflictException(
            "This command key was used for another booking.",
          );
        return this.present(again, true);
      }
      // Nothing on the invoice changed since the last one: hand that one back instead of numbering a duplicate.
      const last = (
        await db.query<Row>(
          `SELECT ${COLUMNS},content_hash FROM booking_invoices WHERE organization_id=$1 AND booking_id=$2 ORDER BY generated_at DESC,invoice_number DESC LIMIT 1`,
          [org, bookingId],
        )
      ).rows[0];
      if (last?.content_hash === hash) return this.present(last, true);
      const n = (
        await db.query<Row>(
          `INSERT INTO booking_invoice_counters(organization_id,last_number) VALUES($1,1)
           ON CONFLICT(organization_id) DO UPDATE SET last_number=booking_invoice_counters.last_number+1 RETURNING last_number`,
          [org],
        )
      ).rows[0].last_number;
      const s = built.snapshot,
        id = randomUUID(),
        number = `INV-${String(n).padStart(6, "0")}`;
      const row = (
        await db.query<Row>(
          `INSERT INTO booking_invoices(id,organization_id,booking_id,invoice_number,total_minor,paid_minor,balance_minor,currency,content_hash,snapshot,logo_data,logo_content_type,qr_data,qr_content_type,generated_by,generated_by_name,command_key)
           VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17) RETURNING ${COLUMNS}`,
          [
            id,
            org,
            bookingId,
            number,
            s.price.total_minor,
            s.paid_minor,
            s.balance_minor,
            s.currency,
            hash,
            s,
            built.logo?.data ?? null,
            built.logo?.content_type ?? null,
            built.qr?.data ?? null,
            built.qr?.content_type ?? null,
            actor.uid,
            m.display_name,
            v.command_key,
          ],
        )
      ).rows[0];
      await this.workspace.audit(db, actor, org, "invoice.generated", id);
      return this.present(row);
    });
  }
  async list(actor: Actor, bookingId: string) {
    const org = (await this.workspace.member(actor)).organization_id;
    await this.bookings.detail(actor, bookingId); // same booking/space access rules
    const rows = (
      await this.db.query<Row>(
        `SELECT ${COLUMNS} FROM booking_invoices WHERE organization_id=$1 AND booking_id=$2 ORDER BY generated_at DESC,invoice_number DESC`,
        [org, bookingId],
      )
    ).rows;
    return {
      enabled: await this.enabled(this.db, org),
      invoices: rows.map((r) => this.present(r)),
    };
  }
  async pdf(actor: Actor, id: string) {
    const org = (await this.workspace.member(actor)).organization_id;
    const row = (
      await this.db.query<Row>(
        "SELECT * FROM booking_invoices WHERE id=$1 AND organization_id=$2",
        [id, org],
      )
    ).rows[0];
    if (!row) throw new NotFoundException("Invoice not found.");
    await this.bookings.detail(actor, row.booking_id);
    const bytes = await renderInvoice(
      row,
      image(row.logo_data, row.logo_content_type),
      image(row.qr_data, row.qr_content_type),
    );
    return { bytes, filename: `${row.invoice_number}.pdf` };
  }
}
