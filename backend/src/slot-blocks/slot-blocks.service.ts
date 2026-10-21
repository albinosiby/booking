import {
  Injectable,
  BadRequestException,
  ForbiddenException,
  NotFoundException,
  ConflictException,
} from "@nestjs/common";
import { createHash, randomUUID } from "node:crypto";
import { z } from "zod";
import { Actor } from "../common/auth.guard";
import { Database, Queryable } from "../common/database";
import { calendarDate, clock } from "../bookings/booking.validation";
import { localStamp, zonedTime } from "../bookings/booking.inventory";
import {
  activeBookingAllocations,
  slotBlockAllocations,
} from "./inventory-blocks";
type Row = Record<string, any>;
const blockDate = calendarDate.refine(
  (value) => value >= "2000-01-01" && value <= "2100-12-31",
  "Choose a date between 2000 and 2100.",
);
const createSchema = z
  .object({
    command_key: z.uuid(),
    business_id: z.uuid(),
    resource_ids: z.array(z.uuid()).min(1).max(100),
    date: blockDate,
    all_day: z.boolean(),
    start_time: clock.optional(),
    end_time: clock.optional(),
    end_date: blockDate.optional(),
  })
  .strict();
const listSchema = z
  .object({
    business_id: z.uuid(),
    date: blockDate,
    cursor: z.coerce.number().int().min(0).max(1000000).default(0),
  })
  .strict();
const slotsSchema = z
  .object({
    business_id: z.uuid(),
    date: blockDate,
    resource_ids: z
      .string()
      .transform((v) => v.split(",").filter(Boolean))
      .pipe(z.array(z.uuid()).min(1).max(100)),
  })
  .strict();
const SLOT_MINUTES = 30;
const nextDate = (date: string) =>
  new Date(Date.parse(date + "T00:00:00Z") + 86400000)
    .toISOString()
    .slice(0, 10);
@Injectable()
export class SlotBlocksService {
  constructor(private readonly db: Database) {}
  private async access(
    actor: Actor,
    businessId: string,
    db: Queryable,
    lock = false,
  ) {
    const m = (
      await db.query<Row>(
        "SELECT * FROM memberships WHERE user_id=$1 AND active=true FOR SHARE",
        [actor.uid],
      )
    ).rows[0];
    if (
      !m ||
      (m.role !== "owner" && !m.permissions.includes("manage_bookings"))
    )
      throw new ForbiddenException(
        "Booking management permission is required.",
      );
    const b = (
      await db.query<Row>(
        `SELECT b.*,l.timezone FROM businesses b JOIN locations l ON l.id=b.location_id WHERE b.id=$1 AND b.organization_id=$2${lock ? " FOR UPDATE OF b" : ""}`,
        [businessId, m.organization_id],
      )
    ).rows[0];
    if (!b) throw new NotFoundException("Business not found.");
    let scope: Set<string> | null = null;
    if (m.role !== "owner") {
      const assignment = (
        await db.query<Row>(
          "SELECT resource_ids FROM staff_assignments WHERE membership_id=$1 AND business_id=$2 FOR SHARE",
          [m.id, b.id],
        )
      ).rows[0];
      if (!assignment)
        throw new ForbiddenException("This business is not assigned to you.");
      if (assignment.resource_ids.length)
        scope = new Set(assignment.resource_ids);
    }
    return { m, b, scope };
  }
  private keys(b: Row, ids: string[]) {
    const keys = new Set<string>();
    for (const id of ids) {
      if (b.configuration?.kind === "turf_v1") {
        const layout = b.configuration.layouts.find((r: Row) => r.id === id);
        if (!layout)
          throw new BadRequestException("Choose a configured ground.");
        for (const section of layout.section_ids)
          keys.add(b.id + ":" + section);
      } else keys.add(b.id + ":" + id);
    }
    if (!keys.size || keys.size > 512)
      throw new BadRequestException("Choose fewer spaces.");
    return [...keys];
  }
  async list(actor: Actor, input: unknown) {
    const v = listSchema.parse(input);
    return this.db.transaction(async (db) => {
      const { m, b, scope } = await this.access(actor, v.business_id, db);
      const from = new Date(
          zonedTime(v.date, "00:00", b.timezone),
        ).toISOString(),
        until = new Date(
          zonedTime(nextDate(v.date), "00:00", b.timezone),
        ).toISOString();
      const values: unknown[] = [m.organization_id, b.id, from, until];
      let condition = "";
      if (scope) {
        values.push(this.keys(b, [...scope]));
        condition = ` AND s.inventory_keys && $${values.length}::text[]`;
      }
      values.push(v.cursor);
      const rows = (
        await db.query<Row>(
          `SELECT s.*,COALESCE((SELECT display_name FROM memberships WHERE user_id=s.created_by AND organization_id=s.organization_id ORDER BY active DESC LIMIT 1),s.created_by) AS creator
        FROM booking_slot_blocks s WHERE s.organization_id=$1 AND s.business_id=$2 AND s.unblocked_at IS NULL AND s.ends_at>$3 AND s.starts_at<$4${condition} ORDER BY s.starts_at,s.id LIMIT 101 OFFSET $${values.length}`,
          values,
        )
      ).rows;
      return {
        items: rows.slice(0, 100).map((r) => ({
          id: r.id,
          business_id: r.business_id,
          resource_ids: r.resource_ids.filter(
            (id: string) => !scope || scope.has(id),
          ),
          spaces: r.resource_names
            .filter((x: Row) => !scope || scope.has(x.id))
            .map((x: Row) => x.name),
          shared_ground:
            scope !== null &&
            !r.resource_ids.some((id: string) => scope.has(id)),
          all_day: r.all_day,
          local_start: localStamp(Date.parse(r.starts_at), r.timezone),
          local_end: localStamp(Date.parse(r.ends_at), r.timezone),
          timezone: r.timezone,
          created_by: r.creator,
          created_at: localStamp(Date.parse(r.created_at), r.timezone),
          can_unblock:
            !scope || r.resource_ids.every((id: string) => scope.has(id)),
        })),
        next_cursor: rows.length > 100 ? v.cursor + 100 : null,
      };
    });
  }
  /** Local-day grid of the selected spaces, so a block can be picked like a booking. */
  async slots(actor: Actor, input: unknown) {
    const v = slotsSchema.parse(input),
      ids = [...new Set(v.resource_ids)].sort();
    return this.db.transaction(async (db) => {
      const { m, b, scope } = await this.access(actor, v.business_id, db);
      if (scope && ids.some((id) => !scope.has(id)))
        throw new ForbiddenException("Choose only your assigned spaces.");
      const found = (
        await db.query<Row>(
          "SELECT id FROM resources WHERE organization_id=$1 AND business_id=$2 AND id=ANY($3::uuid[])",
          [m.organization_id, b.id, ids],
        )
      ).rows;
      if (found.length !== ids.length)
        throw new BadRequestException("Choose spaces in this business.");
      const keys = this.keys(b, ids);
      const cells: { time: string; from: number }[] = [];
      for (let minute = 0; minute < 1440; minute += SLOT_MINUTES) {
        const time = `${String(Math.floor(minute / 60)).padStart(2, "0")}:${String(minute % 60).padStart(2, "0")}`;
        try {
          cells.push({ time, from: zonedTime(v.date, time, b.timezone) });
        } catch {
          // Skipped or repeated local time on a daylight-saving change.
        }
      }
      const dayEnd = zonedTime(nextDate(v.date), "00:00", b.timezone);
      const from = new Date(zonedTime(v.date, "00:00", b.timezone)),
        until = new Date(dayEnd);
      const [bookings, blocks] = await Promise.all([
        activeBookingAllocations(
          db,
          b.id,
          from.toISOString(),
          until.toISOString(),
          keys,
        ),
        slotBlockAllocations(
          db,
          b.id,
          from.toISOString(),
          until.toISOString(),
          keys,
        ),
      ]);
      const overlaps = (rows: Row[], start: number, end: number) =>
        rows.some(
          (r) => Date.parse(r.starts_at) < end && Date.parse(r.ends_at) > start,
        );
      const now = Date.now();
      return {
        date: v.date,
        timezone: b.timezone,
        step_minutes: SLOT_MINUTES,
        slots: cells.map((cell, i) => {
          const end = cells[i + 1]?.from ?? dayEnd;
          return {
            time: cell.time,
            status: overlaps(blocks, cell.from, end)
              ? "blocked"
              : overlaps(bookings, cell.from, end)
                ? "booked"
                : end <= now
                  ? "past"
                  : "available",
          };
        }),
      };
    });
  }
  async create(actor: Actor, input: unknown) {
    const v = createSchema.parse(input),
      ids = [...new Set(v.resource_ids)].sort();
    if (ids.length !== v.resource_ids.length)
      throw new BadRequestException("Choose each space only once.");
    return this.db.transaction(async (db) => {
      const { m, b, scope } = await this.access(actor, v.business_id, db, true);
      if (b.status !== "ready")
        throw new BadRequestException(
          "Configure and activate this business first.",
        );
      if (scope && ids.some((id) => !scope.has(id)))
        throw new ForbiddenException("Choose only your assigned spaces.");
      const resources = (
        await db.query<Row>(
          "SELECT id,name FROM resources WHERE organization_id=$1 AND business_id=$2 AND id=ANY($3::uuid[]) ORDER BY id",
          [m.organization_id, b.id, ids],
        )
      ).rows;
      if (resources.length !== ids.length)
        throw new BadRequestException("Choose spaces in this business.");
      const keys = this.keys(b, ids);
      const startTime = v.all_day ? "00:00" : v.start_time,
        endTime = v.all_day ? "00:00" : v.end_time;
      if (!startTime || !endTime)
        throw new BadRequestException("Choose a start and finish time.");
      const endDate = v.all_day
        ? nextDate(v.date)
        : (v.end_date ?? (endTime <= startTime ? nextDate(v.date) : v.date));
      const wallDuration =
        Date.parse(endDate + "T" + endTime + ":00Z") -
        Date.parse(v.date + "T" + startTime + ":00Z");
      if (wallDuration <= 0 || wallDuration > 86400000)
        throw new BadRequestException("A block must last at most one day.");
      const from = new Date(
          zonedTime(v.date, startTime, b.timezone),
        ).toISOString(),
        until = new Date(zonedTime(endDate, endTime, b.timezone)).toISOString();
      const hash = createHash("sha256")
        .update(
          JSON.stringify({
            business: b.id,
            ids,
            from,
            until,
            all_day: v.all_day,
          }),
        )
        .digest("hex");
      const old = (
        await db.query<Row>("SELECT * FROM booking_slot_blocks WHERE id=$1", [
          v.command_key,
        ])
      ).rows[0];
      if (old) {
        if (
          old.organization_id !== m.organization_id ||
          old.created_by !== actor.uid ||
          old.request_hash !== hash
        )
          throw new ConflictException(
            "This request key belongs to another operation.",
          );
        return { id: old.id };
      }
      if (Date.parse(until) <= Date.now())
        throw new BadRequestException("Choose a current or future interval.");
      const occupied = await activeBookingAllocations(
        db,
        b.id,
        from,
        until,
        keys,
      );
      if (occupied.length) {
        const distinct = [
          ...new Map(occupied.map((r) => [r.booking_id, r])).values(),
        ];
        const visible = distinct
          .filter((r) => !scope || scope.has(r.resource_id))
          .slice(0, 5);
        const details = visible
          .map(
            (r) =>
              `${r.reference} (${localStamp(Date.parse(r.starts_at), b.timezone).replace("T", " ")})`,
          )
          .join("; ");
        throw new ConflictException(
          `${distinct.length} existing booking(s) overlap.${details ? " " + details + "." : ""} Reschedule or cancel overlapping bookings before blocking. Contact the owner for reservations outside your access.`,
        );
      }
      if ((await slotBlockAllocations(db, b.id, from, until, keys)).length)
        throw new ConflictException(
          "These slots are already blocked. Refresh to view the existing block.",
        );
      await db.query(
        `INSERT INTO booking_slot_blocks(id,organization_id,business_id,resource_ids,resource_names,inventory_keys,starts_at,ends_at,all_day,timezone,request_hash,created_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,
        [
          v.command_key,
          m.organization_id,
          b.id,
          JSON.stringify(ids),
          JSON.stringify(resources),
          keys,
          from,
          until,
          v.all_day,
          b.timezone,
          hash,
          actor.uid,
        ],
      );
      await db.query(
        "INSERT INTO audit_events(id,organization_id,actor_id,action,entity_id) VALUES($1,$2,$3,$4,$5)",
        [
          randomUUID(),
          m.organization_id,
          actor.uid,
          "booking_slots_blocked",
          v.command_key,
        ],
      );
      return { id: v.command_key };
    });
  }
  async unblock(actor: Actor, id: string, input: unknown) {
    z.uuid().parse(id);
    z.object({})
      .strict()
      .parse(input ?? {});
    const initial = (
      await this.db.query<Row>(
        "SELECT s.business_id FROM booking_slot_blocks s JOIN memberships m ON m.organization_id=s.organization_id WHERE s.id=$1 AND m.user_id=$2 AND m.active=true",
        [id, actor.uid],
      )
    ).rows[0];
    if (!initial) throw new NotFoundException("Block not found.");
    return this.db.transaction(async (db) => {
      const { m, scope } = await this.access(
        actor,
        initial.business_id,
        db,
        true,
      );
      const row = (
        await db.query<Row>(
          "SELECT * FROM booking_slot_blocks WHERE id=$1 AND organization_id=$2 FOR UPDATE",
          [id, m.organization_id],
        )
      ).rows[0];
      if (!row) throw new NotFoundException("Block not found.");
      if (scope && row.resource_ids.some((r: string) => !scope.has(r)))
        throw new ForbiddenException(
          "Only the owner or staff assigned all selected spaces can unblock this interval.",
        );
      if (!row.unblocked_at) {
        await db.query(
          "UPDATE booking_slot_blocks SET unblocked_at=now(),unblocked_by=$1 WHERE id=$2",
          [actor.uid, id],
        );
        await db.query(
          "INSERT INTO audit_events(id,organization_id,actor_id,action,entity_id) VALUES($1,$2,$3,$4,$5)",
          [
            randomUUID(),
            m.organization_id,
            actor.uid,
            "booking_slots_unblocked",
            id,
          ],
        );
      }
      return { id };
    });
  }
}
