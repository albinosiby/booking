import { enqueueBookingNotification } from "../notifications/notification-events";
import { bookingAvailability } from "./booking.availability";
import { inventoryAllocations } from "../slot-blocks/inventory-blocks";
import { postBookingPayment, systemAccounts } from "../accounts/ledger";
import {
  Injectable,
  BadRequestException,
  ForbiddenException,
  NotFoundException,
  ConflictException,
} from "@nestjs/common";
import { randomUUID, createHash } from "node:crypto";
import { z } from "zod";
import { Database, Queryable } from "../common/database";
import { WorkspaceService } from "../workspace/workspace.service";
import { Actor } from "../common/auth.guard";
import {
  selectionSchema,
  createSchema,
  rescheduleSchema,
  paymentsSchema,
  statusSchema,
  customerEditSchema,
  moneyStatus,
  calendarDate,
} from "./booking.validation";
import {
  bookingOptions,
  buildQuote,
  checkInventory,
  localStamp,
} from "./booking.inventory";
type Row = Record<string, any>;
@Injectable()
export class BookingService {
  constructor(
    private readonly db: Database,
    private readonly workspace: WorkspaceService,
  ) {}
  private allowed(m: Row, permission: string) {
    return m.role === "owner" || m.permissions.includes(permission);
  }
  private canRead(m: Row) {
    return [
      "view_bookings",
      "manage_bookings",
      "collect_payments",
      "manage_attendance",
    ].some((p) => this.allowed(m, p));
  }
  private async member(actor: Actor, db: Queryable = this.db) {
    const m = (
      await db.query<Row>(
        "SELECT * FROM memberships WHERE user_id=$1 AND active=true FOR SHARE",
        [actor.uid],
      )
    ).rows[0];
    if (!m) throw new ForbiddenException("No active organization membership.");
    return m;
  }
  private async access(
    m: Row,
    businessId: string,
    resourceId?: string,
    db: Queryable = this.db,
    lock = false,
  ) {
    const b = (
      await db.query<Row>(
        `SELECT b.*,l.timezone FROM businesses b JOIN locations l ON l.id=b.location_id WHERE b.id=$1 AND b.organization_id=$2${lock ? " FOR UPDATE OF b" : ""}`,
        [businessId, m.organization_id],
      )
    ).rows[0];
    if (!b) throw new NotFoundException("Business not found.");
    if (m.role !== "owner") {
      const a = (
        await db.query<Row>(
          "SELECT resource_ids FROM staff_assignments WHERE membership_id=$1 AND business_id=$2 FOR SHARE",
          [m.id, businessId],
        )
      ).rows[0];
      if (
        !a ||
        (resourceId &&
          a.resource_ids.length &&
          !a.resource_ids.includes(resourceId))
      )
        throw new ForbiddenException(
          "This business or space is not assigned to you.",
        );
    }
    return b;
  }
  private async scopes(m: Row, db: Queryable = this.db) {
    return m.role === "owner"
      ? null
      : (
          await db.query<Row>(
            "SELECT business_id,resource_ids FROM staff_assignments WHERE membership_id=$1",
            [m.id],
          )
        ).rows;
  }
  private visible(b: Row, scopes: Row[] | null) {
    return (
      scopes === null ||
      scopes.some(
        (a) =>
          a.business_id === b.business_id &&
          (!a.resource_ids.length || a.resource_ids.includes(b.resource_id)),
      )
    );
  }
  async catalog(actor: Actor) {
    const m = await this.member(actor);
    if (!this.canRead(m) && !this.allowed(m, "view_finance"))
      throw new ForbiddenException("Booking or finance access is required.");
    const w = await this.workspace.workspace(actor);
    await systemAccounts(this.db, m.organization_id);
    const paymentAccounts = (
      await this.db.query<Row>(
        "SELECT id,name,kind,is_primary FROM money_accounts WHERE organization_id=$1 AND active=true AND kind<>'clearing' ORDER BY name",
        [m.organization_id],
      )
    ).rows;
    const paymentRoutes = (
      await this.db.query<Row>(
        "SELECT business_id,resource_id,method,account_id FROM payment_routes WHERE organization_id=$1",
        [m.organization_id],
      )
    ).rows.filter((r) => w.businesses.some((b: Row) => b.id === r.business_id));
    const locations = w.locations as Row[];
    return {
      currency: w.organization!.currency,
      payment_accounts: paymentAccounts,
      payment_routes: paymentRoutes,
      can_view: this.canRead(m),
      can_manage: this.allowed(m, "manage_bookings"),
      can_collect: this.allowed(m, "collect_payments"),
      can_refund: m.role === "owner",
      can_finance: this.allowed(m, "view_finance"),
      filter_businesses: w.businesses.map((b: Row) => ({
        id: b.id,
        name: b.name,
        type: b.type,
        timezone: locations.find((l: Row) => l.id === b.location_id)!.timezone,
        today: localStamp(
          Date.now(),
          locations.find((l: Row) => l.id === b.location_id)!.timezone,
        ).slice(0, 10),
        resources: b.resources.map((r: Row) => ({ ...r, options: [] })),
      })),
      businesses: w.businesses
        .filter((b: Row) => b.status === "ready")
        .map((b: Row) => ({
          id: b.id,
          name: b.name,
          type: b.type,
          timezone: locations.find((l: Row) => l.id === b.location_id)!
            .timezone,
          today: localStamp(
            Date.now(),
            locations.find((l: Row) => l.id === b.location_id)!.timezone,
          ).slice(0, 10),
          resources: bookingOptions(b),
        }))
        .filter((b: Row) => b.resources.length),
    };
  }
  private async allocations(
    businessId: string,
    db: Queryable,
    from = new Date().toISOString(),
    until = "2101-01-01T00:00:00Z",
    inventoryKeys?: string[],
  ) {
    return inventoryAllocations(db, businessId, from, until, inventoryKeys);
  }

  async quote(actor: Actor, input: unknown) {
    const v = z
      .object({
        selection: selectionSchema,
        exclude_booking_id: z.uuid().nullable(),
      })
      .strict()
      .parse(input);
    const s = v.selection;
    return this.db.transaction(async (db) => {
      const m = await this.member(actor, db);
      if (!this.allowed(m, "manage_bookings"))
        throw new ForbiddenException(
          "Booking management permission is required.",
        );
      const b = await this.access(m, s.business_id, s.resource_id, db, true);
      if (b.status !== "ready")
        throw new BadRequestException(
          "This business is not ready for booking.",
        );
      if (v.exclude_booking_id) {
        const old = await this.find(m, v.exclude_booking_id, db);
        if (old.business_id !== b.id)
          throw new BadRequestException("Reschedule within the same business.");
      }
      const q = buildQuote(b, s, b.timezone);
      return checkInventory(
        q,
        await this.allocations(b.id, db, q.occupied_from, q.occupied_until),
        v.exclude_booking_id ?? undefined,
      );
    });
  }
  async availability(actor: Actor, input: unknown) {
    const v = z
      .object({
        selection: selectionSchema,
        end_times: z.boolean().optional(),
        exclude_booking_id: z.uuid().nullable(),
      })
      .strict()
      .parse(input);
    return this.db.transaction(async (db) => {
      const m = await this.member(actor, db);
      if (!this.canRead(m))
        throw new ForbiddenException("Booking access is required.");
      const b = await this.access(
        m,
        v.selection.business_id,
        v.selection.resource_id,
        db,
      );
      if (b.status !== "ready")
        throw new BadRequestException("This business is not ready.");
      if (v.exclude_booking_id) {
        const old = await this.find(m, v.exclude_booking_id, db);
        if (old.business_id !== b.id)
          throw new BadRequestException("Reschedule within the same business.");
      }
      return bookingAvailability(
        db,
        b,
        v.selection,
        v.end_times,
        v.exclude_booking_id,
      );
    });
  }
  private async command(
    actor: Actor,
    businessId: string,
    key: string,
    kind: string,
    input: unknown,
    permission: string,
    work: (db: Queryable, m: Row, b: Row) => Promise<Row>,
  ) {
    return this.db.transaction(async (db) => {
      const m = await this.member(actor, db);
      if (!this.allowed(m, permission))
        throw new ForbiddenException(
          "You do not have permission for this action.",
        );
      const hash = createHash("sha256")
        .update(JSON.stringify(input))
        .digest("hex");
      await db.query(
        "INSERT INTO booking_commands(organization_id,command_key,actor_id,kind,request_hash) VALUES($1,$2,$3,$4,$5) ON CONFLICT DO NOTHING",
        [m.organization_id, key, actor.uid, kind, hash],
      );
      const old = (
        await db.query<Row>(
          "SELECT * FROM booking_commands WHERE organization_id=$1 AND command_key=$2 FOR UPDATE",
          [m.organization_id, key],
        )
      ).rows[0];
      const b = await this.access(m, businessId, undefined, db, true);
      if (
        old.actor_id !== actor.uid ||
        old.kind !== kind ||
        old.request_hash !== hash
      )
        throw new ConflictException(
          "This request key belongs to different booking data.",
        );
      if (old.response) {
        await this.find(m, old.response.id, db);
        return old.response;
      }
      const result = await work(db, m, b);
      await db.query(
        "UPDATE booking_commands SET response=$1 WHERE organization_id=$2 AND command_key=$3",
        [JSON.stringify(result), m.organization_id, key],
      );
      return result;
    });
  }
  async commandResult(actor: Actor, key: string) {
    z.uuid().parse(key);
    const m = await this.member(actor);
    if (!this.canRead(m))
      throw new ForbiddenException("Booking access is required.");
    const c = (
      await this.db.query<Row>(
        "SELECT response FROM booking_commands WHERE organization_id=$1 AND command_key=$2 AND actor_id=$3",
        [m.organization_id, key, actor.uid],
      )
    ).rows[0];
    if (!c?.response) return { id: null };
    await this.find(m, c.response.id);
    return c.response;
  }
  private async find(
    m: Row,
    id: string,
    db: Queryable = this.db,
    lock = false,
  ) {
    const b = (
      await db.query<Row>(
        `SELECT * FROM bookings WHERE id=$1 AND organization_id=$2${lock ? " FOR UPDATE" : ""}`,
        [id, m.organization_id],
      )
    ).rows[0];
    if (!b) throw new NotFoundException("Booking not found.");
    await this.access(m, b.business_id, b.resource_id, db);
    return b;
  }
  private async history(
    db: Queryable,
    id: string,
    actor: Actor,
    action: string,
    details: unknown,
  ) {
    const historyId = randomUUID();
    await db.query(
      "INSERT INTO booking_history(id,booking_id,actor_id,action,details) VALUES($1,$2,$3,$4,$5)",
      [historyId, id, actor.uid, action, JSON.stringify(details)],
    );
    if (["created", "cancelled", "rescheduled"].includes(action))
      await enqueueBookingNotification(db, historyId);
  }
  private async allocate(
    db: Queryable,
    id: string,
    q: ReturnType<typeof buildQuote>,
  ) {
    await db.query("DELETE FROM booking_allocations WHERE booking_id=$1", [id]);
    for (const k of q.inventory_keys)
      await db.query(
        "INSERT INTO booking_allocations(booking_id,inventory_key,starts_at,ends_at,quantity) VALUES($1,$2,$3,$4,$5)",
        [id, k, q.occupied_from, q.occupied_until, q.quantity],
      );
  }
  private async customer(db: Queryable, m: Row, v: Row) {
    if (v.id) {
      const c = (
        await db.query<Row>(
          "SELECT id FROM customers WHERE id=$1 AND organization_id=$2",
          [v.id, m.organization_id],
        )
      ).rows[0];
      if (!c)
        throw new BadRequestException("Customer is not in this organization.");
      if (m.role !== "owner") {
        const bs = (
          await db.query<Row>(
            "SELECT business_id,resource_id FROM bookings WHERE customer_id=$1 AND organization_id=$2",
            [v.id, m.organization_id],
          )
        ).rows;
        const scopes = await this.scopes(m, db);
        if (!bs.some((b) => this.visible(b, scopes)))
          throw new ForbiddenException(
            "This customer is outside your assigned booking history.",
          );
      }
      return v.id;
    }
    const id = randomUUID();
    await db.query(
      "INSERT INTO customers(id,organization_id,name,phone,email) VALUES($1,$2,$3,$4,$5)",
      [id, m.organization_id, v.name, v.phone.replace(/[^\d+]/g, ""), v.email],
    );
    return id;
  }
  private async writePayments(
    db: Queryable,
    m: Row,
    actor: Actor,
    id: string,
    payments: Row[],
    kind: string,
    reason = "",
  ) {
    if (payments.length && !this.allowed(m, "collect_payments"))
      throw new ForbiddenException(
        "Payment collection permission is required.",
      );
    for (const p of payments) {
      const t = Date.parse(p.received_at);
      if (
        !Number.isFinite(t) ||
        t > Date.now() + 60000 ||
        t < Date.UTC(2000, 0, 1)
      )
        throw new BadRequestException(
          "Payment date must be between 2000 and now.",
        );
      const paymentId = randomUUID();
      await db.query(
        "INSERT INTO booking_payments(id,organization_id,booking_id,kind,method,amount_minor,reference,reason,received_at,recorded_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)",
        [
          paymentId,
          m.organization_id,
          id,
          kind,
          p.method,
          p.amount_minor,
          p.reference,
          reason,
          p.received_at,
          actor.uid,
        ],
      );
      await postBookingPayment(
        db,
        m.organization_id,
        paymentId,
        actor.uid,
        { ...p, booking_id: id },
        kind,
        reason,
      );
    }
  }
  private async net(db: Queryable, id: string) {
    return Number(
      (
        await db.query<Row>(
          "SELECT COALESCE(sum(CASE WHEN kind='collection' THEN amount_minor ELSE -amount_minor END),0) AS net FROM booking_payments WHERE booking_id=$1",
          [id],
        )
      ).rows[0].net,
    );
  }
  async create(actor: Actor, input: unknown) {
    const v = createSchema.parse(input);
    return this.command(
      actor,
      v.selection.business_id,
      v.command_key,
      "create",
      v,
      "manage_bookings",
      async (db, m, b) => {
        await this.access(m, b.id, v.selection.resource_id, db);
        if (b.status !== "ready")
          throw new BadRequestException("This business is not ready.");
        const q = buildQuote(b, v.selection, b.timezone);
        if (q.quote_token !== v.quote_token)
          throw new ConflictException(
            "Pricing changed. Review the new quote before confirming.",
          );
        checkInventory(
          q,
          await this.allocations(b.id, db, q.occupied_from, q.occupied_until),
        );
        if (v.payments.reduce((n, p) => n + p.amount_minor, 0) > q.total_minor)
          throw new BadRequestException(
            "Payments cannot exceed the booking total.",
          );
        const customerId = await this.customer(db, m, v.customer),
          id = randomUUID(),
          reference = "BK-" + id.replace(/-/g, "").slice(0, 12).toUpperCase();
        await db.query(
          "INSERT INTO bookings(id,organization_id,business_id,resource_id,customer_id,reference,starts_at,ends_at,total_minor,selection,price_snapshot,customer_snapshot,notes,people,created_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)",
          [
            id,
            m.organization_id,
            b.id,
            v.selection.resource_id,
            customerId,
            reference,
            q.starts_at,
            q.ends_at,
            q.total_minor,
            JSON.stringify(v.selection),
            JSON.stringify(q),
            JSON.stringify({ ...v.customer, id: customerId }),
            v.notes,
            v.selection.people,
            actor.uid,
          ],
        );
        await this.allocate(db, id, q);
        await this.writePayments(db, m, actor, id, v.payments, "collection");
        await this.history(db, id, actor, "created", {
          selection: v.selection,
          total_minor: q.total_minor,
        });
        return { id };
      },
    );
  }
  private async identify(actor: Actor, id: string) {
    z.uuid().parse(id);
    const m = await this.member(actor);
    if (!this.canRead(m))
      throw new ForbiddenException("Booking access is required.");
    return this.find(m, id);
  }
  async reschedule(actor: Actor, id: string, input: unknown) {
    const v = rescheduleSchema.parse(input),
      initial = await this.identify(actor, id);
    return this.command(
      actor,
      initial.business_id,
      v.command_key,
      "reschedule",
      { id, ...v },
      "manage_bookings",
      async (db, m, b) => {
        const old = await this.find(m, id, db, true);
        if (old.admission_id)
          throw new BadRequestException(
            "Manage this visit from Admissions & Coaching.",
          );
        if (old.version !== v.version)
          throw new ConflictException(
            "Booking changed. Reload before rescheduling.",
          );
        if (old.status !== "confirmed")
          throw new BadRequestException(
            "Only confirmed bookings can be rescheduled.",
          );
        if (v.selection.business_id !== old.business_id)
          throw new BadRequestException("Choose a space in the same business.");
        await this.access(m, b.id, v.selection.resource_id, db);
        if (b.status !== "ready")
          throw new BadRequestException("This business is not ready.");
        const q = buildQuote(b, v.selection, b.timezone);
        if (q.quote_token !== v.quote_token)
          throw new ConflictException("Pricing changed. Review the new quote.");
        checkInventory(
          q,
          await this.allocations(b.id, db, q.occupied_from, q.occupied_until),
          id,
        );
        await this.allocate(db, id, q);
        await db.query(
          "UPDATE bookings SET resource_id=$1,starts_at=$2,ends_at=$3,total_minor=$4,selection=$5,price_snapshot=$6,people=$7,version=version+1 WHERE id=$8",
          [
            v.selection.resource_id,
            q.starts_at,
            q.ends_at,
            q.total_minor,
            JSON.stringify(v.selection),
            JSON.stringify(q),
            v.selection.people,
            id,
          ],
        );
        await this.history(db, id, actor, "rescheduled", {
          reason: v.reason,
          previous: old.price_snapshot,
          current: q,
        });
        return { id };
      },
    );
  }
  async payments(actor: Actor, id: string, input: unknown) {
    const v = paymentsSchema.parse(input),
      initial = await this.identify(actor, id);
    return this.command(
      actor,
      initial.business_id,
      v.command_key,
      "payments",
      { id, ...v },
      "collect_payments",
      async (db, m) => {
        const b = await this.find(m, id, db, true);
        if (b.admission_id)
          throw new BadRequestException(
            "Manage this visit from Admissions & Coaching.",
          );
        if (b.version !== v.version)
          throw new ConflictException(
            "Booking changed. Reload before recording payment.",
          );
        const net = await this.net(db, id),
          amount = v.payments.reduce((n, p) => n + p.amount_minor, 0),
          total = b.status === "cancelled" ? 0 : b.total_minor;
        if (v.kind === "refund") {
          if (m.role !== "owner")
            throw new ForbiddenException("Only the owner can record refunds.");
          if (v.reason.trim().length < 2 || amount > Math.max(0, net - total))
            throw new BadRequestException(
              "Enter a refund reason and an amount no greater than the refund due.",
            );
        } else if (amount > Math.max(0, total - net))
          throw new BadRequestException(
            "Payments exceed the outstanding balance.",
          );
        await this.writePayments(
          db,
          m,
          actor,
          id,
          v.payments,
          v.kind,
          v.reason,
        );
        await db.query("UPDATE bookings SET version=version+1 WHERE id=$1", [
          id,
        ]);
        await this.history(
          db,
          id,
          actor,
          v.kind === "refund" ? "refund_recorded" : "payment_recorded",
          {
            amount_minor: amount,
            reason: v.reason,
            methods: v.payments.map((p) => p.method),
          },
        );
        return { id };
      },
    );
  }
  async status(actor: Actor, id: string, input: unknown) {
    const v = statusSchema.parse(input),
      initial = await this.identify(actor, id);
    return this.command(
      actor,
      initial.business_id,
      v.command_key,
      "status",
      { id, ...v },
      "manage_bookings",
      async (db, m) => {
        const b = await this.find(m, id, db, true);
        if (b.admission_id)
          throw new BadRequestException(
            "Manage this visit from Admissions & Coaching.",
          );
        if (b.version !== v.version)
          throw new ConflictException(
            "Booking changed. Reload before updating.",
          );
        if (b.status !== "confirmed")
          throw new BadRequestException(
            "This booking already has a final status.",
          );
        const checkedIn =
          (
            await db.query(
              "SELECT 1 FROM booking_history WHERE booking_id=$1 AND action='checked_in' LIMIT 1",
              [id],
            )
          ).rows.length > 0;
        if (v.status === "checked_in" && checkedIn)
          throw new BadRequestException("This customer is already checked in.");
        if (v.status === "no_show" && checkedIn)
          throw new BadRequestException(
            "A checked-in customer cannot be marked no-show.",
          );
        if (v.status === "checked_in") {
          await db.query("UPDATE bookings SET version=version+1 WHERE id=$1", [
            id,
          ]);
          await this.history(db, id, actor, "checked_in", { reason: v.reason });
          return { id };
        }
        if (
          (v.status === "completed" && Date.parse(b.ends_at) > Date.now()) ||
          (v.status === "no_show" && Date.parse(b.starts_at) > Date.now())
        )
          throw new BadRequestException(
            "Wait until the booking end/start before marking this status.",
          );
        await db.query(
          "UPDATE bookings SET status=$1,version=version+1 WHERE id=$2",
          [v.status, id],
        );
        if (v.status === "cancelled")
          await db.query(
            "DELETE FROM booking_allocations WHERE booking_id=$1",
            [id],
          );
        await this.history(db, id, actor, v.status, { reason: v.reason });
        return { id };
      },
    );
  }
  async editCustomer(actor: Actor, id: string, input: unknown) {
    const v = customerEditSchema.parse(input),
      initial = await this.identify(actor, id);
    return this.command(
      actor,
      initial.business_id,
      v.command_key,
      "customer_edit",
      { id, ...v },
      "manage_bookings",
      async (db, m) => {
        const b = await this.find(m, id, db, true);
        if (b.admission_id)
          throw new BadRequestException(
            "Manage this visit from Admissions & Coaching.",
          );
        if (b.version !== v.version)
          throw new ConflictException(
            "Booking changed. Reload before editing.",
          );
        const customerId = await this.customer(db, m, v.customer);
        await db.query(
          "UPDATE bookings SET customer_id=$1,customer_snapshot=$2,notes=$3,version=version+1 WHERE id=$4",
          [
            customerId,
            JSON.stringify({ ...v.customer, id: customerId }),
            v.notes,
            id,
          ],
        );
        await this.history(db, id, actor, "customer_updated", {
          notes_changed: b.notes !== v.notes,
        });
        return { id };
      },
    );
  }
  async detail(actor: Actor, id: string) {
    await this.identify(actor, id);
    return this.db.transaction(async (db) => {
      const m = await this.member(actor, db);
      if (!this.canRead(m))
        throw new ForbiddenException("Booking access is required.");
      const b = await this.find(m, id, db);
      const payments = (
        await db.query<Row>(
          "SELECT p.*,COALESCE(m.display_name,p.recorded_by) AS collector_name FROM booking_payments p LEFT JOIN memberships m ON m.user_id=p.recorded_by WHERE booking_id=$1 ORDER BY recorded_at,id",
          [id],
        )
      ).rows;
      const history = (
        await db.query<Row>(
          "SELECT h.*,CASE WHEN h.actor_id LIKE 'website:%' THEN 'Booking website' ELSE COALESCE(m.display_name,h.actor_id) END AS actor_name FROM booking_history h LEFT JOIN memberships m ON m.user_id=h.actor_id WHERE booking_id=$1 ORDER BY created_at,id",
          [id],
        )
      ).rows;
      return {
        ...this.present(
          b,
          payments.reduce(
            (n, p) =>
              n + (p.kind === "collection" ? p.amount_minor : -p.amount_minor),
            0,
          ),
        ),
        payments: payments.map((p) => ({
          ...p,
          local_received: localStamp(
            Date.parse(p.received_at),
            b.price_snapshot.timezone,
          ),
        })),
        history: history.map((h) => ({
          ...h,
          local_created: localStamp(
            Date.parse(h.created_at),
            b.price_snapshot.timezone,
          ),
          previous_local: h.details.previous?.local_start ?? null,
          current_local: h.details.current?.local_start ?? null,
        })),
      };
    });
  }
  private present(b: Row, net: number) {
    return {
      ...b,
      ...moneyStatus(b.status === "cancelled" ? 0 : b.total_minor, net),
      local_start: localStamp(
        Date.parse(b.starts_at),
        b.price_snapshot.timezone,
      ),
      local_end: localStamp(Date.parse(b.ends_at), b.price_snapshot.timezone),
    };
  }
  async dateCounts(actor: Actor, input: unknown) {
    const v = z
      .object({
        date: calendarDate,
        date_until: calendarDate,
        resource_id: z.uuid().optional(),
        business_id: z.uuid().optional(),
        q: z.string().trim().max(100).optional(),
        status: z
          .enum(["confirmed", "completed", "cancelled", "no_show"])
          .optional(),
      })
      .strict()
      .parse(input);
    const span = (Date.parse(v.date_until) - Date.parse(v.date)) / 86400000;
    if (span < 0 || span > 61)
      throw new BadRequestException("Choose a date range of 1–62 days.");
    const m = await this.member(actor);
    if (!this.canRead(m))
      throw new ForbiddenException("Booking access is required.");
    const values: unknown[] = [m.organization_id, v.date, v.date_until];
    let where = "b.organization_id=$1";
    for (const [column, value] of [
      ["business_id", v.business_id],
      ["resource_id", v.resource_id],
      ["status", v.status],
    ]) {
      if (value) {
        values.push(value);
        where += ` AND b.${column}=$${values.length}`;
      }
    }
    if (v.q) {
      values.push("%" + v.q + "%");
      where += ` AND (b.customer_snapshot->>'name' ILIKE $${values.length} OR b.customer_snapshot->>'phone' ILIKE $${values.length} OR b.reference ILIKE $${values.length})`;
    }
    where += await this.scopeCondition(m, values);
    const start =
      "(b.starts_at AT TIME ZONE (b.price_snapshot->>'timezone'))::date";
    const end =
      "((b.ends_at-interval '1 microsecond') AT TIME ZONE (b.price_snapshot->>'timezone'))::date";
    where += ` AND ${start}<=$3::date AND ${end}>=$2::date`;
    const rows = (
      await this.db.query<Row>(
        `SELECT d.day::date::text AS date,count(b.id)::int AS count FROM generate_series($2::date::timestamp,$3::date::timestamp,interval '1 day') d(day) LEFT JOIN (SELECT b.* FROM bookings b WHERE ${where}) b ON ${start}<=d.day::date AND ${end}>=d.day::date GROUP BY d.day ORDER BY d.day`,
        values,
      )
    ).rows;
    return {
      items: rows.map((r) => ({ date: r.date, count: Number(r.count) })),
    };
  }

  async list(actor: Actor, input: unknown) {
    const v = z
      .object({
        date: calendarDate.optional(),
        date_until: calendarDate.optional(),
        overlap: z.enum(["true", "false"]).optional(),
        resource_id: z.uuid().optional(),
        business_id: z.uuid().optional(),
        q: z.string().trim().max(100).optional(),
        status: z
          .enum(["confirmed", "completed", "cancelled", "no_show"])
          .optional(),
        cursor: z.coerce.number().int().min(0).max(100000).default(0),
      })
      .strict()
      .parse(input);
    const m = await this.member(actor);
    if (!this.canRead(m))
      throw new ForbiddenException("Booking access is required.");
    const scopes = await this.scopes(m);
    const values: unknown[] = [m.organization_id];
    let where = "b.organization_id=$1";
    const add = (sql: string, value: unknown) => {
      values.push(value);
      where += " AND " + sql.replace("?", `$${values.length}`);
    };
    if (v.business_id) add("b.business_id=?", v.business_id);
    if (v.overlap === "true" && v.date) {
      add(
        "(b.starts_at AT TIME ZONE (b.price_snapshot->>'timezone'))::date<=?::date",
        v.date_until ?? v.date,
      );
      add(
        "((b.ends_at-interval '1 microsecond') AT TIME ZONE (b.price_snapshot->>'timezone'))::date>=?::date",
        v.date,
      );
    } else {
      if (v.date)
        add(
          "(b.starts_at AT TIME ZONE (b.price_snapshot->>'timezone'))::date" +
            (v.date_until ? ">=?::date" : "=?::date"),
          v.date,
        );
      if (v.date_until)
        add(
          "(b.starts_at AT TIME ZONE (b.price_snapshot->>'timezone'))::date<=?::date",
          v.date_until,
        );
    }
    if (v.resource_id) add("b.resource_id=?", v.resource_id);
    if (v.status) add("b.status=?", v.status);
    if (v.q) add("(b.customer_snapshot->>'name' ILIKE ?)", "%" + v.q + "%");
    if (v.q) {
      const i = values.length;
      where = where.replace(
        `(b.customer_snapshot->>'name' ILIKE $${i})`,
        `(b.customer_snapshot->>'name' ILIKE $${i} OR b.customer_snapshot->>'phone' ILIKE $${i} OR b.reference ILIKE $${i})`,
      );
    }
    if (scopes !== null) {
      values.push(JSON.stringify(scopes));
      where += ` AND EXISTS(SELECT 1 FROM jsonb_array_elements($${values.length}::jsonb) a WHERE a->>'business_id'=b.business_id::text AND (jsonb_array_length(a->'resource_ids')=0 OR a->'resource_ids' ? b.resource_id::text))`;
    }
    values.push(v.cursor);
    const rows = (
      await this.db.query<Row>(
        `SELECT b.*,COALESCE((SELECT sum(CASE WHEN kind='collection' THEN amount_minor ELSE -amount_minor END) FROM booking_payments WHERE booking_id=b.id),0) AS net FROM bookings b WHERE ${where} ORDER BY b.starts_at DESC,b.id LIMIT 101 OFFSET $${values.length}`,
        values,
      )
    ).rows;
    return {
      items: rows.slice(0, 100).map((b) => this.present(b, Number(b.net))),
      next_cursor: rows.length > 100 ? v.cursor + 100 : null,
    };
  }
  async customers(actor: Actor, search: string) {
    if (search.replace(/[^0-9]/g, "").length < 3 || search.length > 100)
      return { items: [] };
    const m = await this.member(actor);
    if (!this.canRead(m))
      throw new ForbiddenException("Booking access is required.");
    const values: unknown[] = [
      m.organization_id,
      "%" + search.replace(/[^0-9]/g, "") + "%",
    ];
    let where =
      "c.organization_id=$1 AND regexp_replace(c.phone, '[^0-9]', '', 'g') LIKE $2";
    if (m.role !== "owner") {
      const scope = await this.scopeCondition(m, values);
      where += ` AND EXISTS(SELECT 1 FROM bookings b WHERE b.organization_id=c.organization_id AND b.customer_id=c.id ${scope})`;
    }
    const rows = (
      await this.db.query<Row>(
        `SELECT c.* FROM customers c WHERE ${where} ORDER BY c.created_at DESC,c.id DESC LIMIT 40`,
        values,
      )
    ).rows;
    return { items: rows };
  }

  async customerDirectory(actor: Actor, input: unknown) {
    const v = z
      .object({
        q: z
          .string()
          .trim()
          .max(50)
          .regex(/^[+\d\s().-]*$/)
          .default(""),
        after: z.string().max(80).optional(),
      })
      .strict()
      .parse(input);
    const digits = v.q.replace(/[^0-9]/g, "");
    if (v.q && !digits)
      throw new BadRequestException("Enter a phone number to search.");
    const m = await this.member(actor);
    if (!this.canRead(m))
      throw new ForbiddenException("Booking access is required.");
    const values: unknown[] = [m.organization_id];
    let where = "c.organization_id=$1";
    if (m.role !== "owner") {
      const scope = await this.scopeCondition(m, values);
      where += ` AND EXISTS(SELECT 1 FROM bookings b WHERE b.organization_id=c.organization_id AND b.customer_id=c.id ${scope})`;
    }
    const phone = "regexp_replace(c.phone, '[^0-9]', '', 'g')";
    const key = `COALESCE(NULLIF(${phone},''),c.id::text)`;
    if (digits) {
      values.push(digits + "%");
      where += ` AND ${phone} LIKE $${values.length}`;
    }
    let after = "";
    if (v.after) {
      values.push(v.after);
      after = ` HAVING ${key}>$${values.length}`;
    }
    const rows = (
      await this.db.query<Row>(
        `SELECT min(c.id::text)::uuid AS id,min(c.name) AS name,min(c.phone) AS phone,${key} AS phone_key,count(*)::integer AS record_count
       FROM customers c WHERE ${where} GROUP BY ${key}${after} ORDER BY phone_key LIMIT 51`,
        values,
      )
    ).rows;
    return {
      items: rows.slice(0, 50),
      next: rows.length > 50 ? rows[49].phone_key : null,
    };
  }

  async customerHistory(actor: Actor, id: string, input: unknown) {
    z.uuid().parse(id);
    const v = z
      .object({ cursor: z.string().max(300).optional() })
      .strict()
      .parse(input);
    let before: { time: string; id: string } | undefined;
    if (v.cursor) {
      try {
        before = z
          .object({ time: z.iso.datetime({ offset: true }), id: z.uuid() })
          .strict()
          .parse(
            JSON.parse(Buffer.from(v.cursor, "base64url").toString("utf8")),
          );
      } catch {
        throw new BadRequestException("Invalid booking history cursor.");
      }
    }
    const m = await this.member(actor);
    if (!this.canRead(m))
      throw new ForbiddenException("Booking access is required.");
    const anchor = (
      await this.db.query<Row>(
        "SELECT * FROM customers WHERE id=$1 AND organization_id=$2",
        [id, m.organization_id],
      )
    ).rows[0];
    if (!anchor) throw new NotFoundException("Customer not found.");
    const digits = anchor.phone.replace(/[^0-9]/g, "");
    const values: unknown[] = [m.organization_id, digits || id];
    const match = digits
      ? "regexp_replace(c.phone, '[^0-9]', '', 'g')=$2"
      : "c.id=$2::uuid";
    const scope = await this.scopeCondition(m, values);
    const where = `b.organization_id=$1 AND EXISTS(SELECT 1 FROM customers c WHERE c.organization_id=b.organization_id AND c.id=b.customer_id AND ${match})${scope}`;
    // Staff must be able to see the anchor record itself, not merely know its UUID.
    if (
      m.role !== "owner" &&
      !(
        await this.db.query<Row>(
          `SELECT b.id FROM bookings b WHERE b.organization_id=$1 AND b.customer_id=$2 ${scope} LIMIT 1`,
          [m.organization_id, id, ...values.slice(2)],
        )
      ).rows.length
    )
      throw new NotFoundException("Customer not found.");
    const contacts = (
      await this.db.query<Row>(
        `SELECT count(*)::integer AS count FROM customers c WHERE c.organization_id=$1 AND ${match}` +
          (m.role === "owner"
            ? ""
            : ` AND EXISTS(SELECT 1 FROM bookings b WHERE b.organization_id=c.organization_id AND b.customer_id=c.id ${scope})`),
        values,
      )
    ).rows[0].count;
    let pageWhere = where;
    if (before) {
      values.push(before.time, before.id);
      pageWhere += ` AND (b.starts_at,b.id)<($${values.length - 1}::timestamptz,$${values.length}::uuid)`;
    }
    const rows = (
      await this.db.query<Row>(
        `SELECT b.*,COALESCE((SELECT sum(CASE WHEN kind='collection' THEN amount_minor ELSE -amount_minor END) FROM booking_payments WHERE booking_id=b.id),0) AS net
       FROM bookings b WHERE ${pageWhere} ORDER BY b.starts_at DESC,b.id DESC LIMIT 51`,
        values,
      )
    ).rows;
    const currency = (
      await this.db.query<Row>(
        "SELECT currency FROM organizations WHERE id=$1",
        [m.organization_id],
      )
    ).rows[0].currency;
    const last = rows[49];
    return {
      customer: {
        id: anchor.id,
        name: anchor.name,
        phone: anchor.phone,
        record_count: contacts,
      },
      currency,
      items: rows.slice(0, 50).map((b) => this.present(b, Number(b.net))),
      next:
        rows.length > 50
          ? Buffer.from(
              JSON.stringify({
                time: new Date(last.starts_at).toISOString(),
                id: last.id,
              }),
            ).toString("base64url")
          : null,
    };
  }

  private async scopeCondition(m: Row, values: unknown[], alias = "b") {
    const scopes = await this.scopes(m);
    if (scopes === null) return "";
    values.push(JSON.stringify(scopes));
    return ` AND EXISTS(SELECT 1 FROM jsonb_array_elements($${values.length}::jsonb) a WHERE a->>'business_id'=${alias}.business_id::text AND (jsonb_array_length(a->'resource_ids')=0 OR a->'resource_ids' ? ${alias}.resource_id::text))`;
  }
  async dashboard(actor: Actor, businessId?: string) {
    const m = await this.member(actor);
    if (!this.canRead(m) && !this.allowed(m, "view_finance"))
      throw new ForbiddenException("Booking or finance access is required.");
    const values: unknown[] = [m.organization_id];
    let where = "b.organization_id=$1";
    if (businessId) {
      values.push(z.uuid().parse(businessId));
      where += " AND b.business_id=$2";
    }
    where += await this.scopeCondition(m, values);
    const today =
      "(b.starts_at AT TIME ZONE (b.price_snapshot->>'timezone'))::date=(now() AT TIME ZONE (b.price_snapshot->>'timezone'))::date";
    const counts = (
      await this.db.query<Row>(
        `SELECT count(*) FILTER(WHERE ${today} AND b.status<>'cancelled') AS today_count,count(*) FILTER(WHERE ${today} AND b.status='confirmed' AND b.ends_at>now()) AS upcoming_count,COALESCE(sum(b.total_minor) FILTER(WHERE ${today} AND b.status<>'cancelled'),0) AS booking_value_minor,COALESCE(sum(GREATEST(0,b.total_minor-COALESCE(p.net,0))) FILTER(WHERE b.status<>'cancelled'),0) AS outstanding_minor FROM bookings b LEFT JOIN LATERAL(SELECT sum(CASE WHEN kind='collection' THEN amount_minor ELSE -amount_minor END) AS net FROM booking_payments WHERE booking_id=b.id) p ON true WHERE ${where}`,
        values,
      )
    ).rows[0];
    const upcoming = (
      await this.db.query<Row>(
        `SELECT b.*,COALESCE((SELECT sum(CASE WHEN kind='collection' THEN amount_minor ELSE -amount_minor END) FROM booking_payments WHERE booking_id=b.id),0) AS net FROM bookings b WHERE ${where} AND ${today} AND b.status='confirmed' AND b.ends_at>now() ORDER BY b.starts_at,b.id LIMIT 12`,
        values,
      )
    ).rows;
    const financial = this.allowed(m, "view_finance"),
      payments = financial
        ? await this.paymentList(actor, {
            business_id: businessId,
            today: "true",
          })
        : { totals: [] };
    return {
      today_count: Number(counts.today_count),
      upcoming_count: Number(counts.upcoming_count),
      booking_value_minor: financial
        ? Number(counts.booking_value_minor)
        : null,
      outstanding_minor: financial ? Number(counts.outstanding_minor) : null,
      collected_minor: financial
        ? payments.totals
            .filter((p: Row) => p.kind === "collection")
            .reduce((n: number, p: Row) => n + p.total_minor, 0)
        : null,
      refunded_minor: financial
        ? payments.totals
            .filter((p: Row) => p.kind === "refund")
            .reduce((n: number, p: Row) => n + p.total_minor, 0)
        : null,
      upcoming: this.canRead(m)
        ? upcoming.map((b) => this.present(b, Number(b.net)))
        : [],
    };
  }

  async outstanding(actor: Actor, input: unknown) {
    const v = z
      .object({
        business_id: z.uuid().optional(),
        date: calendarDate.optional(),
        cursor: z.coerce.number().int().min(0).max(100000).default(0),
      })
      .strict()
      .parse(input);
    const m = await this.member(actor);
    if (
      !this.allowed(m, "view_finance") &&
      !this.allowed(m, "collect_payments")
    )
      throw new ForbiddenException(
        "Collections or finance permission is required.",
      );
    const values: unknown[] = [m.organization_id];
    let where = "b.organization_id=$1";
    if (v.business_id) {
      values.push(v.business_id);
      where += ` AND b.business_id=$${values.length}`;
    }
    if (v.date) {
      values.push(v.date);
      where += ` AND (b.starts_at AT TIME ZONE (b.price_snapshot->>'timezone'))::date=$${values.length}::date`;
    }
    where += await this.scopeCondition(m, values);
    const base = `SELECT b.id,b.reference,b.status,b.price_snapshot,b.customer_snapshot,b.starts_at,b.ends_at,b.total_minor,GREATEST(0,(CASE WHEN b.status='cancelled' THEN 0 ELSE b.total_minor END)-COALESCE(p.net,0)) AS balance_minor,GREATEST(0,COALESCE(p.net,0)-(CASE WHEN b.status='cancelled' THEN 0 ELSE b.total_minor END)) AS refund_due_minor FROM bookings b LEFT JOIN LATERAL(SELECT sum(CASE WHEN kind='collection' THEN amount_minor ELSE -amount_minor END) AS net FROM booking_payments WHERE booking_id=b.id) p ON true WHERE ${where}`;
    const totals = (
      await this.db.query<Row>(
        `SELECT COALESCE(sum(balance_minor),0) AS balance_total_minor,COALESCE(sum(refund_due_minor),0) AS refund_total_minor FROM (${base}) due`,
        values,
      )
    ).rows[0];
    values.push(v.cursor);
    const rows = (
      await this.db.query<Row>(
        `SELECT * FROM (${base}) due WHERE balance_minor>0 OR refund_due_minor>0 ORDER BY starts_at,id LIMIT 101 OFFSET $${values.length}`,
        values,
      )
    ).rows;
    return {
      items: rows.slice(0, 100).map((b) => ({
        id: b.id,
        reference: b.reference,
        status: b.status,
        customer_name: b.customer_snapshot.name,
        customer_phone: b.customer_snapshot.phone ?? "",
        local_end: localStamp(Date.parse(b.ends_at), b.price_snapshot.timezone),
        total_minor: Number(b.total_minor),
        option_name: b.price_snapshot.option_name ?? null,
        business_name: b.price_snapshot.business_name,
        space_name: b.price_snapshot.space_name,
        local_start: localStamp(
          Date.parse(b.starts_at),
          b.price_snapshot.timezone,
        ),
        balance_minor: Number(b.balance_minor),
        refund_due_minor: Number(b.refund_due_minor),
      })),
      next_cursor: rows.length > 100 ? v.cursor + 100 : null,
      balance_total_minor: Number(totals.balance_total_minor),
      refund_total_minor: Number(totals.refund_total_minor),
    };
  }
  async paymentList(actor: Actor, input: unknown) {
    const v = z
      .object({
        business_id: z.uuid().optional(),
        today: z.enum(["true", "false"]).optional(),
        date: calendarDate.optional(),
        cursor: z.coerce.number().int().min(0).max(100000).default(0),
      })
      .strict()
      .parse(input);
    const m = await this.member(actor);
    if (
      !this.allowed(m, "view_finance") &&
      !this.allowed(m, "collect_payments")
    )
      throw new ForbiddenException(
        "Collections or finance permission is required.",
      );
    const values: unknown[] = [m.organization_id];
    let where = "p.organization_id=$1";
    if (v.business_id) {
      values.push(v.business_id);
      where += ` AND b.business_id=$${values.length}`;
    }
    if (v.date) {
      values.push(v.date);
      where += ` AND (p.received_at AT TIME ZONE (b.price_snapshot->>'timezone'))::date=$${values.length}::date`;
    }
    if (v.today === "true")
      where +=
        " AND (p.received_at AT TIME ZONE (b.price_snapshot->>'timezone'))::date=(now() AT TIME ZONE (b.price_snapshot->>'timezone'))::date";
    where += await this.scopeCondition(m, values);
    const totals = (
      await this.db.query<Row>(
        `SELECT p.kind,p.method,sum(p.amount_minor) AS total_minor FROM booking_payments p JOIN bookings b ON b.id=p.booking_id WHERE ${where} GROUP BY p.kind,p.method`,
        values,
      )
    ).rows.map((p) => ({ ...p, total_minor: Number(p.total_minor) }));
    values.push(v.cursor);
    const rows = (
      await this.db.query<Row>(
        `SELECT p.*,b.business_id,b.resource_id,b.reference AS booking_reference,b.customer_snapshot,b.price_snapshot,COALESCE(m.display_name,p.recorded_by) AS collector_name FROM booking_payments p JOIN bookings b ON b.id=p.booking_id LEFT JOIN memberships m ON m.user_id=p.recorded_by WHERE ${where} ORDER BY p.received_at DESC,p.id LIMIT 101 OFFSET $${values.length}`,
        values,
      )
    ).rows;
    return {
      items: rows.slice(0, 100).map((p) => ({
        ...p,
        local_received: localStamp(
          Date.parse(p.received_at),
          p.price_snapshot.timezone,
        ),
      })),
      next_cursor: rows.length > 100 ? v.cursor + 100 : null,
      totals,
    };
  }
}
