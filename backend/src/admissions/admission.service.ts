import {
  inventoryAllocations,
  inventoryIsBlocked,
  SlotBlockedException,
} from "../slot-blocks/inventory-blocks";
import {
  Injectable,
  BadRequestException,
  ForbiddenException,
  NotFoundException,
  ConflictException,
} from "@nestjs/common";
import { createHash, randomUUID } from "node:crypto";
import { z } from "zod";
import { Database, Queryable } from "../common/database";
import { Actor } from "../common/auth.guard";
import {
  addDate,
  localStamp,
  checkInventory,
  inventoryRemaining,
  zonedTime,
} from "../bookings/booking.inventory";
import { holderText, slotHolders, slotLabel } from "../bookings/slot-holders";
import { coachingConfiguration, isCoach } from "../workspace/coach.access";
import {
  calendarDate,
  clock,
  paymentSchema,
  moneyStatus,
} from "../bookings/booking.validation";
import { destination } from "../accounts/ledger";
import {
  admissionSpaces,
  admissionTypes,
  CoachNames,
  coachName,
  currentCoachId,
  currentCoachName,
  planSpaceIds,
  validSwimmingDuration,
  enrollmentSchema,
  createAdmissionSchema,
  expiryFrom,
  fixedDates,
  interval,
  isSubscription,
  reminderDays,
  slotChartSchema,
  subscriptionPlan,
  dueBy,
} from "./admission.rules";
type Row = Record<string, any>;
class CoachClashException extends ConflictException {
  constructor() {
    super("The coach has another overlapping class.");
  }
}
/** Shows who coaches the admission's plan now, not who did when it was sold. */
function withCurrentCoach(a: Row, config: Row | undefined, names: CoachNames) {
  if (a.plan_snapshot?.kind !== "coaching") return a;
  return {
    ...a,
    plan_snapshot: {
      ...a.plan_snapshot,
      coach_name: currentCoachName(config, a.plan_id, a.plan_snapshot, names),
    },
  };
}
const reasonSchema = z.string().trim().min(2).max(500);
// pg returns DATE columns as Date objects (local midnight; PGlite uses UTC midnight): compare as YYYY-MM-DD.
const ymd = (v: unknown): string => {
  if (!(v instanceof Date)) return String(v);
  const utcMidnight =
    v.getUTCHours() === 0 && v.getUTCMinutes() === 0 && v.getUTCSeconds() === 0;
  return utcMidnight
    ? v.toISOString().slice(0, 10)
    : `${v.getFullYear()}-${String(v.getMonth() + 1).padStart(2, "0")}-${String(v.getDate()).padStart(2, "0")}`;
};
/**
 * Monthly fee position of a subscription: what is due by today, what is
 * still owed of it, and the next fee. Plans are due in full at once.
 */
function feeStatus(a: Row) {
  const today = localStamp(Date.now(), a.timezone).slice(0, 10);
  const net = Number(a.net ?? 0);
  if (!isSubscription(a.plan_snapshot))
    return {
      due_now_minor: a.total_minor,
      owed_now_minor: Math.max(0, a.total_minor - net),
      next_due_on: null,
      next_due_minor: null,
    };
  const due = dueBy(a.plan_snapshot, today);
  const next = (a.plan_snapshot.subscription.instalments as Row[]).find(
    (i) => i.due_on > today,
  );
  return {
    due_now_minor: due,
    owed_now_minor: Math.max(0, due - net),
    next_due_on: next?.due_on ?? null,
    next_due_minor: next?.amount_minor ?? null,
  };
}
@Injectable()
export class AdmissionService {
  constructor(private readonly db: Database) {}
  private allowed(m: Row, p: string) {
    return (
      m.role === "owner" ||
      m.permissions.includes(p) ||
      (p === "mark_attendance" && m.permissions.includes("manage_attendance"))
    );
  }
  private canMarkAttendance(
    m: Row,
    admission: Row,
    configuration: Row | undefined,
  ) {
    if (admission.mode === "membership" || admission.deleted_at) return false;
    if (!this.allowed(m, "mark_attendance")) return false;
    if (m.role === "owner" || !isCoach(m)) return true;
    return (
      currentCoachId(
        configuration,
        admission.plan_id,
        admission.plan_snapshot,
      ) === m.id
    );
  }
  private async member(
    actor: Actor,
    db: Queryable = this.db,
    allowCoachClasses = false,
  ) {
    const m = (
      await db.query<Row>(
        "SELECT * FROM memberships WHERE user_id=$1 AND active=true FOR SHARE",
        [actor.uid],
      )
    ).rows[0];
    if (
      !m ||
      (![
        "view_bookings",
        "manage_bookings",
        "manage_attendance",
        "mark_attendance",
        "manage_subscriptions",
        "collect_payments",
      ].some((p) => this.allowed(m, p)) &&
        !(allowCoachClasses && isCoach(m)))
    )
      throw new ForbiddenException("Admission access is required.");
    return m;
  }
  private async business(
    m: Row,
    id: string,
    resource: string | undefined,
    db: Queryable,
    lock = false,
  ) {
    const b = (
      await db.query<Row>(
        `SELECT b.*,l.timezone FROM businesses b JOIN locations l ON l.id=b.location_id WHERE b.id=$1 AND b.organization_id=$2${lock ? " FOR UPDATE OF b" : ""}`,
        [id, m.organization_id],
      )
    ).rows[0];
    if (!b || !admissionTypes.includes(b.type))
      throw new NotFoundException("Pool or court business not found.");
    if (m.role !== "owner") {
      const a = (
        await db.query<Row>(
          "SELECT resource_ids FROM staff_assignments WHERE membership_id=$1 AND business_id=$2 FOR SHARE",
          [m.id, id],
        )
      ).rows[0];
      if (
        !a ||
        (resource &&
          a.resource_ids.length &&
          !a.resource_ids.includes(resource))
      )
        throw new ForbiddenException("This space is not assigned to you.");
      b.scope = a.resource_ids;
    }
    return b;
  }
  private async find(m: Row, id: string, db: Queryable = this.db) {
    z.uuid().parse(id);
    const a = (
      await db.query<Row>(
        "SELECT * FROM admission_balances WHERE id=$1 AND organization_id=$2",
        [id, m.organization_id],
      )
    ).rows[0];
    if (!a) throw new NotFoundException("Admission not found.");
    await this.business(m, a.business_id, a.resource_id, db);
    return a;
  }
  private async command(
    actor: Actor,
    businessId: string,
    resource: string,
    key: string,
    kind: string,
    input: unknown,
    permission: string | ((m: Row) => boolean),
    work: (db: Queryable, m: Row, b: Row) => Promise<Row>,
  ) {
    return this.db.transaction(async (db) => {
      const m = await this.member(actor, db);
      if (
        typeof permission === "string"
          ? !this.allowed(m, permission)
          : !permission(m)
      )
        throw new ForbiddenException(
          "You do not have permission for this action.",
        );
      const b = await this.business(m, businessId, resource, db, true);
      const hash = createHash("sha256")
        .update(JSON.stringify(input))
        .digest("hex");
      await db.query(
        "INSERT INTO booking_commands(organization_id,command_key,actor_id,kind,request_hash) VALUES($1,$2,$3,$4,$5) ON CONFLICT DO NOTHING",
        [m.organization_id, key, actor.uid, kind, hash],
      );
      const c = (
        await db.query<Row>(
          "SELECT * FROM booking_commands WHERE organization_id=$1 AND command_key=$2 FOR UPDATE",
          [m.organization_id, key],
        )
      ).rows[0];
      if (
        c.actor_id !== actor.uid ||
        c.kind !== kind ||
        c.request_hash !== hash
      )
        throw new ConflictException(
          "This request key belongs to different data.",
        );
      if (c.response) return c.response;
      const result = await work(db, m, b);
      await db.query(
        "UPDATE booking_commands SET response=$1 WHERE organization_id=$2 AND command_key=$3",
        [JSON.stringify(result), m.organization_id, key],
      );
      return result;
    });
  }
  private async audit(
    db: Queryable,
    m: Row,
    actor: Actor,
    id: string,
    action: string,
    details: unknown,
  ) {
    await db.query(
      "INSERT INTO admission_history(id,organization_id,admission_id,actor_id,action,details) VALUES($1,$2,$3,$4,$5,$6)",
      [
        randomUUID(),
        m.organization_id,
        id,
        actor.uid,
        action,
        JSON.stringify(details),
      ],
    );
  }
  async customers(actor: Actor, query: string) {
    const q = z.string().trim().max(100).parse(query);
    const m = await this.member(actor);
    if (q.length < 3) return { items: [] };
    const rows = (
      await this.db.query<Row>(
        `SELECT c.* FROM customers c WHERE c.organization_id=$1 AND (c.name ILIKE $2 OR regexp_replace(c.phone,'[^0-9]','','g') LIKE $3) AND ($4::boolean OR EXISTS(SELECT 1 FROM (SELECT business_id,resource_id FROM bookings WHERE customer_id=c.id AND organization_id=c.organization_id UNION SELECT business_id,resource_id FROM admissions WHERE customer_id=c.id AND organization_id=c.organization_id) h JOIN staff_assignments s ON s.business_id=h.business_id WHERE s.membership_id=$5 AND (jsonb_array_length(s.resource_ids)=0 OR s.resource_ids @> jsonb_build_array(h.resource_id::text)))) ORDER BY c.name,c.id LIMIT 20`,
        [
          m.organization_id,
          "%" + q + "%",
          q.replace(/[^0-9]/g, "").length >= 3
            ? "%" + q.replace(/[^0-9]/g, "") + "%"
            : "__never__",
          m.role === "owner",
          m.id,
        ],
      )
    ).rows;
    return { items: rows };
  }
  /** Team member names, which name plan coaches. */
  private async coachNames(db: Queryable, organizationId: string) {
    const rows = (
      await db.query<Row>(
        "SELECT id,display_name FROM memberships WHERE organization_id=$1",
        [organizationId],
      )
    ).rows;
    return new Map<string, string>(rows.map((r) => [r.id, r.display_name]));
  }
  async catalog(actor: Actor) {
    const m = await this.member(actor);
    const names = await this.coachNames(this.db, m.organization_id);
    const rows = (
      await this.db.query<Row>(
        "SELECT id FROM businesses WHERE organization_id=$1 AND type=ANY($2::text[]) ORDER BY display_order,id",
        [m.organization_id, admissionTypes],
      )
    ).rows;
    const businesses: Row[] = [];
    for (const row of rows) {
      let b: Row;
      try {
        b = await this.business(m, row.id, undefined, this.db);
      } catch (e) {
        if (e instanceof ForbiddenException) continue;
        throw e;
      }
      const c = b.configuration;
      if (b.status !== "ready" || !["pool_v1", "court_v1"].includes(c?.kind))
        continue;
      const pools = admissionSpaces(c).filter(
        (p: Row) => p.enabled && (!b.scope?.length || b.scope.includes(p.id)),
      );
      // Active/upcoming enrollments per plan, limited to the member's spaces.
      const counts = (
        await this.db.query<Row>(
          "SELECT plan_id,count(*)::integer n FROM admission_balances WHERE business_id=$1 AND status IN ('active','upcoming') AND ($2::text[] IS NULL OR resource_id::text=ANY($2::text[])) GROUP BY plan_id",
          [b.id, b.scope?.length ? b.scope : null],
        )
      ).rows;
      businesses.push({
        id: b.id,
        name: b.name,
        type: b.type,
        space_kind: c.kind === "court_v1" ? "court" : "pool",
        subscriptions: c.subscriptions_enabled === true,
        timezone: b.timezone,
        today: localStamp(Date.now(), b.timezone).slice(0, 10),
        pools: pools.map((p: Row) => ({
          id: p.id,
          name: p.name,
          durations: p.durations,
          default_duration_minutes: p.default_duration_minutes,
          operating: p.operating,
        })),
        plans: (c.plans ?? [])
          .filter(
            (p: Row) =>
              p.enabled &&
              planSpaceIds(p).some((id: string) =>
                pools.some((r: Row) => r.id === id),
              ),
          )
          .map((p: Row) => ({
            ...p,
            pool_ids: planSpaceIds(p).filter((id: string) =>
              pools.some((r: Row) => r.id === id),
            ),
            coach_name: coachName(names, p.coach_id ?? null),
            active_count: counts.find((r) => r.plan_id === p.id)?.n ?? 0,
          })),
      });
    }
    const currency = (
      await this.db.query<Row>(
        "SELECT currency FROM organizations WHERE id=$1",
        [m.organization_id],
      )
    ).rows[0].currency;
    return {
      businesses,
      currency,
      can_manage: this.allowed(m, "manage_subscriptions"),
      can_attend: this.allowed(m, "mark_attendance"),
      can_collect: this.allowed(m, "collect_payments"),
      is_owner: m.role === "owner",
    };
  }
  private async allocations(
    db: Queryable,
    business: string,
    from: string,
    until: string,
  ) {
    return inventoryAllocations(db, business, from, until);
  }

  private check(
    b: Row,
    pool: Row,
    plan: Row,
    s: Row,
    allocations: Row[],
    exclude?: string,
  ) {
    const quote = {
      inventory_keys: [b.id + ":" + pool.id],
      occupied_from: s.starts_at,
      occupied_until: s.ends_at,
      capacity: pool.capacity ?? 1,
      quantity: 1,
    };
    const court = b.configuration?.kind === "court_v1";
    if (!court || plan.kind !== "coaching")
      checkInventory(quote, allocations, exclude);
    if (plan.kind !== "coaching") return;
    const overlaps = allocations.filter(
      (r) =>
        r.booking_id !== exclude &&
        r.plan_snapshot?.kind === "coaching" &&
        Date.parse(r.starts_at) < Date.parse(s.ends_at) &&
        Date.parse(r.ends_at) > Date.parse(s.starts_at),
    );
    const same = overlaps.filter(
      (r) =>
        r.plan_id === plan.id &&
        r.inventory_key === b.id + ":" + pool.id &&
        Date.parse(r.starts_at) === Date.parse(s.starts_at) &&
        Date.parse(r.ends_at) === Date.parse(s.ends_at),
    );
    if (same.length >= plan.class_seats)
      throw new ConflictException("This coaching class is full.");
    // A court batch occupies the whole court once; later students join it.
    if (court && same.length) {
      if (inventoryIsBlocked(quote, allocations))
        throw new SlotBlockedException();
    } else if (court) checkInventory(quote, allocations, exclude);
    const coach = currentCoachId(b.configuration, plan.id, plan);
    if (
      coach &&
      overlaps.some(
        (r) =>
          currentCoachId(b.configuration, r.plan_id, r.plan_snapshot) ===
            coach && !same.includes(r),
      )
    )
      throw new CoachClashException();
  }
  /** Rows of this space's inventory that overlap a session. */
  private holding(b: Row, pool: Row, s: Row, occupied: Row[]) {
    const key = b.id + ":" + pool.id;
    return occupied.filter(
      (r) =>
        r.inventory_key === key &&
        Date.parse(r.starts_at) < Date.parse(s.ends_at) &&
        Date.parse(r.ends_at) > Date.parse(s.starts_at),
    );
  }
  /**
   * Restates a session conflict with its date and, when the space itself is
   * full, who holds it. The original reason is kept as the last sentence.
   */
  private async clash(
    db: Queryable,
    m: Row,
    b: Row,
    pool: Row,
    s: Row,
    occupied: Row[],
    e: ConflictException,
  ) {
    const when = slotLabel(s.local_start);
    const plain = new ConflictException(`${when}: ${e.message}`);
    if (e instanceof SlotBlockedException || e instanceof CoachClashException)
      return plain;
    const holders = (
      await slotHolders(
        db,
        m.organization_id,
        this.holding(b, pool, s, occupied),
        this.allowed(m, "view_bookings") || this.allowed(m, "manage_bookings"),
        b.timezone,
      )
    ).filter((h) => h.kind !== "block");
    if (!holders.length) return plain;
    const names = holders.slice(0, 3).map(holderText).join(", ");
    const more = holders.length > 3 ? ` and ${holders.length - 3} more` : "";
    return new ConflictException(
      `${when} is held by ${names}${more}. ${e.message}`,
    );
  }
  /** The caller's coaching classes on one local date, each with its students. */
  async classes(actor: Actor, input: unknown) {
    const v = z.object({ date: calendarDate }).strict().parse(input);
    const m = await this.member(actor, this.db, true);
    if (!isCoach(m))
      throw new ForbiddenException("Only coaches have coaching classes.");
    const businesses = (
      await this.db.query<Row>(
        "SELECT b.*,l.timezone FROM businesses b JOIN locations l ON l.id=b.location_id WHERE b.organization_id=$1 ORDER BY b.display_order,b.id",
        [m.organization_id],
      )
    ).rows;
    const assignments =
      m.role === "owner"
        ? []
        : (
            await this.db.query<Row>(
              "SELECT business_id,resource_ids FROM staff_assignments WHERE membership_id=$1",
              [m.id],
            )
          ).rows;
    const now = Date.now();
    const classes: Row[] = [];
    const flexible_students: Row[] = [];
    for (const b of businesses) {
      if (!coachingConfiguration(b.configuration)) continue;
      const assignment = assignments.find((a) => a.business_id === b.id);
      if (m.role !== "owner" && !assignment) continue;
      const plans: Row[] = (b.configuration.plans ?? []).filter(
        (p: Row) => p.kind === "coaching" && p.coach_id === m.id,
      );
      if (!plans.length) continue;
      const from = new Date(zonedTime(v.date, "00:00", b.timezone)),
        until = new Date(zonedTime(addDate(v.date, 1), "00:00", b.timezone));
      const rows = (
        await this.db.query<Row>(
          "SELECT s.id visit_id,s.version,s.starts_at,s.ends_at,s.resource_id,s.admission_attendance,a.id admission_id,a.reference,a.mode,a.customer_snapshot,a.plan_id FROM bookings s JOIN admission_balances a ON a.id=s.admission_id WHERE s.business_id=$1 AND s.status<>'cancelled' AND NOT a.cancelled AND a.deleted_at IS NULL AND a.plan_id::text=ANY($2::text[]) AND s.starts_at>=$3 AND s.starts_at<$4 ORDER BY s.starts_at,s.resource_id,a.customer_snapshot->>'name',s.id",
          [b.id, plans.map((p) => p.id), from, until],
        )
      ).rows;
      const spaces = admissionSpaces(b.configuration);
      // One class per plan, space and time; students of a batch share it.
      const byKey = new Map<string, Row>();
      for (const r of rows) {
        if (
          m.role !== "owner" &&
          assignment!.resource_ids.length &&
          !assignment!.resource_ids.includes(r.resource_id)
        )
          continue;
        const starts = Date.parse(new Date(r.starts_at).toISOString()),
          ends = Date.parse(new Date(r.ends_at).toISOString());
        const key = [b.id, r.plan_id, r.resource_id, starts, ends].join("|");
        let c = byKey.get(key);
        if (!c) {
          c = {
            key,
            business_id: b.id,
            business_name: b.name,
            plan_id: r.plan_id,
            plan_name: plans.find((p) => p.id === r.plan_id)?.name ?? "Class",
            space_name:
              spaces.find((p: Row) => p.id === r.resource_id)?.name ?? "Space",
            starts_at: new Date(starts).toISOString(),
            ends_at: new Date(ends).toISOString(),
            local_start: localStamp(starts, b.timezone),
            local_end: localStamp(ends, b.timezone),
            students: [],
          };
          byKey.set(key, c);
          classes.push(c);
        }
        c.students.push({
          admission_id: r.admission_id,
          reference: r.reference,
          visit_id: r.visit_id,
          version: r.version,
          name: r.customer_snapshot?.name ?? "Student",
          phone: r.customer_snapshot?.phone ?? null,
          attendance: r.admission_attendance,
          // Mirrors attendance(): first marks of fixed sessions, from the
          // start until 24 hours after the end; owners correct the rest.
          markable:
            this.allowed(m, "mark_attendance") &&
            r.mode === "fixed" &&
            r.admission_attendance === "unmarked" &&
            starts <= now &&
            ends >= now - 86400000,
        });
      }
      if (v.date === localStamp(now, b.timezone).slice(0, 10)) {
        flexible_students.push(
          ...(await this.flexibleRoster(
            m,
            b,
            plans,
            assignment,
            v.date,
            from,
            until,
            now,
          )),
        );
      }
    }
    classes.sort(
      (x, y) =>
        Date.parse(x.starts_at) - Date.parse(y.starts_at) ||
        x.key.localeCompare(y.key),
    );
    return { date: v.date, classes, flexible_students };
  }

  /** Enrolments do not reserve visits: expose them before the first check-in. */
  private async flexibleRoster(
    m: Row,
    b: Row,
    plans: Row[],
    assignment: Row | undefined,
    date: string,
    from: Date,
    until: Date,
    now: number,
  ) {
    const admissions = (
      await this.db.query<Row>(
        "SELECT * FROM admission_balances WHERE organization_id=$1 AND business_id=$2 AND mode='flexible' AND plan_snapshot->>'kind'='coaching' AND NOT cancelled AND deleted_at IS NULL AND plan_id::text=ANY($3::text[]) AND starts_on<=$4 AND expires_on>=$4 ORDER BY customer_snapshot->>'name',id",
        [m.organization_id, b.id, plans.map((p) => p.id), date],
      )
    ).rows.filter(
      (a) =>
        m.role === "owner" ||
        !assignment!.resource_ids.length ||
        assignment!.resource_ids.includes(a.resource_id),
    );
    if (!admissions.length) return [];
    const present = (
      await this.db.query<Row>(
        "SELECT s.admission_id,s.starts_at,s.ends_at,COALESCE((SELECT COALESCE(h.details->>'marked_at',h.created_at::text) FROM admission_history h WHERE h.admission_id=s.admission_id AND h.details->>'visit_id'=s.id::text AND h.action IN ('checked_in','attendance') ORDER BY h.created_at DESC,h.id DESC LIMIT 1),s.created_at::text) marked_at FROM bookings s WHERE s.business_id=$1 AND s.admission_id=ANY($2::uuid[]) AND s.status<>'cancelled' AND s.admission_attendance='present' AND ((s.starts_at>=$3 AND s.starts_at<$4) OR (s.starts_at<=$5 AND s.ends_at>$5)) ORDER BY s.created_at DESC,s.id",
        [b.id, admissions.map((a) => a.id), from, until, new Date(now)],
      )
    ).rows;
    // One inventory snapshot per business, covering every possible class duration.
    const occupied = await this.allocations(
      this.db,
      b.id,
      new Date(Math.floor(now / 60000) * 60000).toISOString(),
      new Date(now + 1440 * 60000).toISOString(),
    );
    const result: Row[] = [];
    for (const a of admissions) {
      const visit = present.find((p) => p.admission_id === a.id);
      if (a.remaining <= 0 && !visit) continue;
      const plan = plans.find((p) => p.id === a.plan_id)!;
      const space = admissionSpaces(b.configuration).find(
        (p) => p.id === a.resource_id,
      );
      let action = "unavailable",
        reason: string | null = null;
      let session: Row | undefined;
      if (visit) action = "present";
      else if (!this.allowed(m, "mark_attendance"))
        reason = "Attendance permission is required.";
      else if (
        !["ready", "paused"].includes(b.status) ||
        !space?.enabled ||
        !plan.enabled ||
        !planSpaceIds(plan).includes(a.resource_id)
      )
        reason = "This plan or space is unavailable.";
      else {
        try {
          session = await this.runningCoachingVisit(
            this.db,
            a,
            b,
            space!,
            now,
            true,
            occupied,
          );
          this.check(b, space!, a.plan_snapshot, session, occupied);
          if (
            localStamp(Date.parse(session.ends_at) - 1, a.timezone).slice(
              0,
              10,
            ) > ymd(a.expires_on)
          )
            throw new BadRequestException(
              "The class must end within admission validity.",
            );
          action = session.class_started ? "start" : "join";
        } catch (e) {
          if (!(
            e instanceof BadRequestException || e instanceof ConflictException
          ))
            throw e;
          reason = e.message;
        }
      }
      result.push({
        admission_id: a.id,
        version: a.version,
        name: a.customer_snapshot?.name ?? "Student",
        reference: a.reference,
        business_name: b.name,
        plan_name: plan.name,
        space_name: space?.name ?? "Space",
        today: date,
        remaining: a.remaining,
        duration_minutes: a.plan_snapshot.class_duration_minutes,
        action,
        reason,
        local_marked_at: visit
          ? localStamp(Date.parse(visit.marked_at), b.timezone)
          : null,
        local_start: visit
          ? localStamp(Date.parse(visit.starts_at), b.timezone)
          : (session?.local_start ?? null),
        local_end: visit
          ? localStamp(Date.parse(visit.ends_at), b.timezone)
          : (session?.local_end ?? null),
      });
    }
    return result;
  }
  /**
   * Upcoming classes that would overlap for a coach who coaches exactly
   * `plan_ids` after a staff coaching-plan save. Only clashes involving a plan
   * the coach would newly take over are reported.
   */
  async coachConflicts(actor: Actor, input: unknown) {
    const v = z
      .object({
        business_id: z.uuid(),
        coach_id: z.string().min(1).max(100),
        plan_ids: z.array(z.string().min(1).max(100)).max(50),
      })
      .strict()
      .parse(input);
    const m = await this.member(actor);
    if (m.role !== "owner")
      throw new ForbiddenException("Only the owner can manage coaches.");
    const b = await this.business(m, v.business_id, undefined, this.db);
    const plans: Row[] = b.configuration?.plans ?? [];
    const wanted = new Set(v.plan_ids);
    const gained = new Set(
      plans
        .filter((p) => wanted.has(p.id) && p.coach_id !== v.coach_id)
        .map((p) => p.id),
    );
    if (!gained.size) return { items: [] };
    const coachOf = (planId: string, snapshot: Row) => {
      if (!plans.some((p) => p.id === planId))
        return currentCoachId(undefined, planId, snapshot);
      if (wanted.has(planId)) return v.coach_id;
      const current = currentCoachId(b.configuration, planId);
      return current === v.coach_id ? null : current;
    };
    const now = new Date().toISOString();
    // Admissions may start far ahead, so every future class counts.
    const until = "9999-12-31T23:59:59Z";
    // One class per plan, space and time; students of a batch share it.
    const classes = new Map<string, Row>();
    for (const r of await this.allocations(this.db, b.id, now, until)) {
      if (
        !r.plan_id ||
        r.plan_snapshot?.kind !== "coaching" ||
        Date.parse(r.starts_at) <= Date.now() ||
        coachOf(r.plan_id, r.plan_snapshot) !== v.coach_id
      )
        continue;
      const key = [r.plan_id, r.inventory_key, r.starts_at, r.ends_at].join(
        "|",
      );
      const c = classes.get(key) ?? { ...r, bookings: new Set<string>() };
      c.bookings.add(r.booking_id);
      classes.set(key, c);
    }
    const list = [...classes.values()].sort(
      (x, y) => Date.parse(x.starts_at) - Date.parse(y.starts_at),
    );
    const name = (r: Row) =>
      plans.find((p) => p.id === r.plan_id)?.name ??
      r.plan_snapshot?.name ??
      "Coaching plan";
    const items: Row[] = [];
    for (let i = 0; i < list.length && items.length < 20; i++)
      for (let j = i + 1; j < list.length && items.length < 20; j++) {
        const x = list[i],
          y = list[j];
        if (Date.parse(y.starts_at) >= Date.parse(x.ends_at)) break;
        if (
          (!gained.has(x.plan_id) && !gained.has(y.plan_id)) ||
          [...x.bookings].some((id) => y.bookings.has(id))
        )
          continue;
        items.push({
          plan_id: x.plan_id,
          plan_name: name(x),
          other_plan_id: y.plan_id,
          other_plan_name: name(y),
          starts_at: x.starts_at,
          ends_at: x.ends_at,
          other_starts_at: y.starts_at,
          other_ends_at: y.ends_at,
          label: localStamp(Date.parse(y.starts_at), b.timezone)
            .slice(0, 16)
            .replace("T", " "),
        });
      }
    return { items };
  }
  private async previewIn(
    db: Queryable,
    m: Row,
    b: Row,
    v: z.infer<typeof enrollmentSchema>,
  ) {
    if (b.status !== "ready")
      throw new BadRequestException("This business is not ready.");
    if ((v.plan_id === undefined) === (v.subscription === undefined))
      throw new BadRequestException("Choose a plan or enter a subscription.");
    const c = b.configuration,
      pool = admissionSpaces(c).find(
        (p: Row) => p.id === v.resource_id && p.enabled,
      ),
      plan: Row | undefined = v.subscription
        ? subscriptionPlan(c, v.starts_on, v.subscription)
        : c?.plans?.find(
            (p: Row) =>
              p.id === v.plan_id &&
              p.enabled &&
              planSpaceIds(p).includes(v.resource_id),
          );
    if (!pool || !plan || plan.price_minor === null)
      throw new BadRequestException(
        "Choose an enabled space and plan with a price.",
      );
    const subscription = isSubscription(plan);
    if (subscription && v.plan_amount_minor !== undefined)
      throw new BadRequestException(
        "Set a subscription's amount as its monthly fee.",
      );
    if (
      v.plan_amount_minor !== undefined &&
      !this.allowed(m, "collect_payments")
    )
      throw new ForbiddenException(
        "Payment collection permission is required to change the plan amount.",
      );
    if ((plan.track_attendance !== false) !== (v.mode !== "membership"))
      throw new BadRequestException(
        "Use the tracking mode configured for this plan. Reload the plan before enrolling.",
      );
    if (subscription && (v.mode !== "fixed" || !v.weekdays.length))
      throw new BadRequestException(
        "A subscription reserves a weekly time slot. Choose its weekdays and time.",
      );
    if (v.mode === "membership" && v.weekdays.length)
      throw new BadRequestException(
        "Membership-only plans do not have scheduled weekdays.",
      );
    const today = localStamp(Date.now(), b.timezone).slice(0, 10);
    const expires = expiryFrom(plan, v.starts_on);
    if (v.starts_on < today || !expires || expires < v.starts_on)
      throw new BadRequestException(
        "Choose an activation date from today within plan validity.",
      );
    if (v.mode === "flexible" && v.weekdays.length)
      throw new BadRequestException(
        "Flexible plans do not have fixed weekdays.",
      );
    if (v.mode === "fixed" && !subscription && plan.allowance > 1000)
      throw new BadRequestException(
        "A fixed admission supports at most 1,000 reserved sessions. Use flexible attendance for larger plans.",
      );
    if (v.renewed_from) {
      const old = await this.find(m, v.renewed_from, db);
      // An active term opens for renewal in its reminder window; the next
      // term then starts after it so the two never overlap.
      const early =
        old.status === "active" &&
        !old.cancelled &&
        today >= addDate(ymd(old.expires_on), -reminderDays(c));
      if (!["completed", "expired"].includes(old.status) && !early)
        throw new BadRequestException(
          "Renew a completed or expired admission, or an active one in its renewal reminder window.",
        );
      if (early && v.starts_on <= ymd(old.expires_on))
        throw new BadRequestException(
          `Start the renewal after the current term ends on ${ymd(old.expires_on)}.`,
        );
      if (old.business_id !== b.id || v.customer.id !== old.customer_id)
        throw new BadRequestException(
          "Renewal must keep the same business and customer.",
        );
      if (
        (
          await db.query("SELECT id FROM admissions WHERE renewed_from=$1", [
            old.id,
          ])
        ).rows.length
      )
        throw new ConflictException("This admission has already been renewed.");
    }
    const sessions =
      v.mode === "fixed"
        ? fixedDates(
            v.starts_on,
            expires,
            v.weekdays,
            subscription ? 1000 : plan.allowance,
          ).map((date) =>
            interval(pool, plan, date, v.time, v.duration_minutes, b.timezone),
          )
        : [];
    if (
      sessions.some(
        (s) =>
          localStamp(Date.parse(s.ends_at) - 1, b.timezone).slice(0, 10) >
          expires,
      )
    )
      throw new BadRequestException(
        "Sessions must end within admission validity.",
      );
    if (sessions.some((s) => Date.parse(s.starts_at) < Date.now()))
      throw new BadRequestException(
        "The first reserved session must be in the future.",
      );
    // Validate flexible duration without making a reservation; opening hours are checked at check-in.
    if (
      v.mode === "flexible" &&
      (plan.kind === "coaching"
        ? v.duration_minutes !== plan.class_duration_minutes
        : !validSwimmingDuration(pool, v.duration_minutes))
    )
      throw new BadRequestException("Choose the configured visit duration.");
    for (let i = 1; i < sessions.length; i++)
      if (
        Date.parse(sessions[i].starts_at) < Date.parse(sessions[i - 1].ends_at)
      )
        throw new BadRequestException(
          "The weekly schedule contains overlapping sessions.",
        );
    if (sessions.length) {
      const occupied = await this.allocations(
        db,
        b.id,
        sessions[0].starts_at,
        sessions.at(-1)!.ends_at,
      );
      for (const s of sessions)
        try {
          this.check(b, pool, plan, s, occupied);
        } catch (e) {
          if (!(e instanceof ConflictException)) throw e;
          throw await this.clash(db, m, b, pool, s, occupied, e);
        }
    }
    if (subscription && sessions.length > 1000)
      throw new BadRequestException(
        "A subscription supports at most 1,000 reserved sessions. Choose fewer months or weekdays.",
      );
    const configured = plan.price_minor;
    const agreedAmount = v.plan_amount_minor ?? configured;
    const snapshot = {
      ...plan,
      configured_price_minor: configured,
      price_minor: agreedAmount,
      allowance:
        v.mode === "membership"
          ? 0
          : subscription
            ? sessions.length
            : plan.allowance,
      track_attendance: v.mode !== "membership",
      coach_name: coachName(
        await this.coachNames(db, b.organization_id),
        plan.coach_id ?? null,
      ),
    };
    const preview = {
      plan: snapshot,
      pool_name: pool.name,
      business_name: b.name,
      timezone: b.timezone,
      expires_on: expires,
      total_minor: agreedAmount,
      sessions,
    };
    return {
      ...preview,
      preview_token: createHash("sha256")
        .update(JSON.stringify({ preview, version: b.version, input: v }))
        .digest("hex"),
    };
  }
  async preview(actor: Actor, input: unknown) {
    const v = enrollmentSchema.parse(input);
    return this.db.transaction(async (db) => {
      const m = await this.member(actor, db);
      if (!this.allowed(m, "manage_subscriptions"))
        throw new ForbiddenException(
          "Subscription management permission is required.",
        );
      const b = await this.business(m, v.business_id, v.resource_id, db, true);
      return this.previewIn(db, m, b, v);
    });
  }
  /**
   * Start times for a fixed weekly schedule. Each time is checked against
   * every session date of the term, as preview does, and names who holds
   * the dates that clash.
   */
  async slotChart(actor: Actor, input: unknown) {
    const v = slotChartSchema.parse(input);
    const m = await this.member(actor);
    if (!this.allowed(m, "manage_subscriptions"))
      throw new ForbiddenException(
        "Subscription management permission is required.",
      );
    const b = await this.business(m, v.business_id, v.resource_id, this.db);
    if (b.status !== "ready")
      throw new BadRequestException("This business is not ready.");
    if ((v.plan_id === undefined) === (v.subscription === undefined))
      throw new BadRequestException("Choose a plan or enter a subscription.");
    const c = b.configuration,
      pool = admissionSpaces(c).find(
        (p: Row) => p.id === v.resource_id && p.enabled,
      ),
      plan: Row | undefined = v.subscription
        ? subscriptionPlan(c, v.starts_on, {
            ...v.subscription,
            monthly_minor: 0,
          })
        : c?.plans?.find(
            (p: Row) =>
              p.id === v.plan_id &&
              p.enabled &&
              planSpaceIds(p).includes(v.resource_id),
          );
    if (!pool || !plan)
      throw new BadRequestException("Choose an enabled space and plan.");
    if (plan.track_attendance === false)
      throw new BadRequestException(
        "Membership-only plans do not have scheduled weekdays.",
      );
    const subscription = isSubscription(plan);
    if (!subscription && plan.allowance > 1000)
      throw new BadRequestException(
        "A fixed admission supports at most 1,000 reserved sessions. Use flexible attendance for larger plans.",
      );
    const today = localStamp(Date.now(), b.timezone).slice(0, 10);
    const expires = expiryFrom(plan, v.starts_on);
    if (v.starts_on < today || !expires || expires < v.starts_on)
      throw new BadRequestException(
        "Choose an activation date from today within plan validity.",
      );
    const dates = fixedDates(
      v.starts_on,
      expires,
      v.weekdays,
      subscription ? 1000 : plan.allowance,
    );
    const minute = (t: string) =>
      Number(t.slice(0, 2)) * 60 + Number(t.slice(3, 5));
    const pad = (n: number) => String(n).padStart(2, "0");
    // Offer half-hour steps from each opening time that applies.
    const anchors = [
      pool.operating,
      ...(plan.follow_court_hours ? [] : [plan.availability]),
    ]
      .filter((h: Row | undefined) => h && !h.all_day)
      .map((h: Row) => minute(h.opens_at));
    const starts = new Set<number>();
    for (const a of anchors.length ? anchors : [0])
      for (let n = 0; n < 48; n++) starts.add((a + n * 30) % 1440);
    const times = [...starts]
      .sort((x, y) => x - y)
      .map((t) => `${pad(Math.floor(t / 60))}:${pad(t % 60)}`);
    const day = 86400000,
      lo = Math.floor(Date.parse(dates[0] + "T00:00:00Z") / day) - 2,
      hi = Math.floor(Date.parse(dates.at(-1)! + "T00:00:00Z") / day) + 3;
    const occupied = await this.allocations(
      this.db,
      b.id,
      new Date(lo * day).toISOString(),
      new Date((hi + 1) * day).toISOString(),
    );
    // Index by UTC day so each session only scans its neighbours.
    const buckets = new Map<number, Row[]>();
    for (const r of occupied) {
      const from = Math.floor(Date.parse(r.starts_at) / day),
        to = Math.floor((Date.parse(r.ends_at) - 1) / day);
      for (let d = Math.max(from, lo); d <= Math.min(to, hi); d++) {
        const list = buckets.get(d) ?? [];
        list.push(r);
        buckets.set(d, list);
      }
    }
    const near = (s: Row) => {
      const found = new Set<Row>();
      const last = Math.floor((Date.parse(s.ends_at) - 1) / day);
      for (let d = Math.floor(Date.parse(s.starts_at) / day); d <= last; d++)
        for (const r of buckets.get(d) ?? []) found.add(r);
      return [...found];
    };
    const key = b.id + ":" + pool.id,
      court = c?.kind === "court_v1",
      coaching = plan.kind === "coaching";
    const capacity = coaching ? plan.class_seats : (pool.capacity ?? 1);
    const left = (s: Row, rows: Row[]) => {
      let remaining = capacity;
      if (!court || !coaching)
        remaining = inventoryRemaining(
          {
            inventory_keys: [key],
            occupied_from: s.starts_at,
            occupied_until: s.ends_at,
            capacity: pool.capacity ?? 1,
            quantity: 1,
          },
          rows,
        );
      if (coaching)
        remaining = Math.min(
          remaining,
          plan.class_seats -
            rows.filter(
              (r) =>
                r.plan_id === plan.id &&
                r.inventory_key === key &&
                Date.parse(r.starts_at) === Date.parse(s.starts_at) &&
                Date.parse(r.ends_at) === Date.parse(s.ends_at),
            ).length,
        );
      return Math.max(0, remaining);
    };
    const now = Date.now();
    const slots: Row[] = [];
    for (const time of times) {
      let sessions: Row[];
      try {
        sessions = dates.map((date) =>
          interval(pool, plan, date, time, v.duration_minutes, b.timezone),
        );
      } catch (e) {
        // Preview would reject this time on some date, so it is not offered.
        if (e instanceof BadRequestException) continue;
        throw e;
      }
      if (
        sessions.some(
          (s, i) =>
            localStamp(Date.parse(s.ends_at) - 1, b.timezone).slice(0, 10) >
              expires ||
            (i > 0 &&
              Date.parse(s.starts_at) < Date.parse(sessions[i - 1].ends_at)),
        )
      )
        continue;
      const base = {
        time,
        end_time: sessions[0].local_end.slice(11, 16),
        session_count: sessions.length,
        capacity,
      };
      if (Date.parse(sessions[0].starts_at) < now) {
        slots.push({
          ...base,
          status: "past",
          remaining_capacity: 0,
          clash_count: 0,
          clashes: [],
        });
        continue;
      }
      let remaining = capacity;
      const clashes: Row[] = [];
      for (const s of sessions) {
        const rows = near(s);
        try {
          this.check(b, pool, plan, s, rows);
          remaining = Math.min(remaining, left(s, rows));
        } catch (e) {
          if (!(e instanceof ConflictException)) throw e;
          clashes.push({
            s,
            reason: e.message,
            rows: this.holding(b, pool, s, rows),
          });
        }
      }
      slots.push({
        ...base,
        status: clashes.length ? "taken" : "available",
        remaining_capacity: clashes.length ? 0 : remaining,
        clash_count: clashes.length,
        clashes: clashes.slice(0, 3),
      });
    }
    const holders = await slotHolders(
      this.db,
      m.organization_id,
      slots.flatMap((s) => s.clashes.flatMap((x: Row) => x.rows)),
      this.allowed(m, "view_bookings") || this.allowed(m, "manage_bookings"),
      b.timezone,
    );
    return {
      timezone: b.timezone,
      expires_on: expires,
      dates,
      slots: slots.map((slot) => ({
        ...slot,
        clashes: slot.clashes.map((x: Row) => {
          const ids = new Set(x.rows.map((r: Row) => String(r.booking_id)));
          const held = holders.filter((h) => ids.has(h.source));
          return {
            date: x.s.date,
            label: slotLabel(x.s.local_start),
            starts_at: x.s.starts_at,
            ends_at: x.s.ends_at,
            reason: x.reason,
            holder_count: held.length,
            holders: held.slice(0, 5),
          };
        }),
      })),
    };
  }
  private async payment(
    db: Queryable,
    m: Row,
    actor: Actor,
    a: Row,
    payments: Row[],
    kind: string,
    reason = "",
  ) {
    if (payments.length && !this.allowed(m, "collect_payments"))
      throw new ForbiddenException(
        "Payment collection permission is required.",
      );
    if (kind === "refund" && m.role !== "owner")
      throw new ForbiddenException("Only the owner can record refunds.");
    const net = Number(
      (
        await db.query<Row>(
          "SELECT COALESCE(sum(CASE WHEN kind='collection' THEN amount_minor ELSE -amount_minor END),0) net FROM admission_payments WHERE admission_id=$1",
          [a.id],
        )
      ).rows[0].net,
    );
    const amount = payments.reduce((n, p) => n + p.amount_minor, 0);
    if (kind === "collection" ? net + amount > a.total_minor : amount > net)
      throw new BadRequestException(
        "Payment exceeds the outstanding balance or refundable amount.",
      );
    for (const p of payments) {
      const t = Date.parse(p.received_at);
      if (t > Date.now() + 60000 || t < Date.UTC(2000, 0, 1))
        throw new BadRequestException(
          "Choose a payment date between 2000 and now.",
        );
      const account = await destination(
          db,
          m.organization_id,
          a.business_id,
          a.resource_id,
          p.method,
          p.account_id,
        ),
        pid = randomUUID(),
        eid = randomUUID();
      await db.query(
        "INSERT INTO admission_payments(id,organization_id,admission_id,kind,method,amount_minor,reference,reason,received_at,recorded_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)",
        [
          pid,
          m.organization_id,
          a.id,
          kind,
          p.method,
          p.amount_minor,
          p.reference,
          reason,
          p.received_at,
          actor.uid,
        ],
      );
      await db.query(
        "INSERT INTO finance_events(id,organization_id,kind,business_id,resource_id,admission_payment_id,category,reason,reference,occurred_at,recorded_by) VALUES($1,$2,$3,$4,$5,$6,'Admissions',$7,$8,$9,$10)",
        [
          eid,
          m.organization_id,
          kind === "collection" ? "admission_collection" : "admission_refund",
          a.business_id,
          a.resource_id,
          pid,
          reason || `Admission ${a.reference}`,
          p.reference,
          p.received_at,
          actor.uid,
        ],
      );
      await db.query(
        "INSERT INTO finance_lines(id,organization_id,event_id,account_id,method,amount_minor) VALUES($1,$2,$3,$4,$5,$6)",
        [
          randomUUID(),
          m.organization_id,
          eid,
          account,
          p.method,
          (kind === "collection" ? 1 : -1) * p.amount_minor,
        ],
      );
    }
  }
  private async visits(
    db: Queryable,
    m: Row,
    actor: Actor,
    a: Row,
    b: Row,
    sessions: Row[],
    present = false,
  ) {
    if (!sessions.length) return [];
    const pool = admissionSpaces(b.configuration).find(
        (p: Row) => p.id === a.resource_id,
      ),
      plan = a.plan_snapshot;
    const rows = sessions.map((s) => {
      const id = randomUUID();
      return {
        id,
        organization_id: m.organization_id,
        business_id: b.id,
        resource_id: a.resource_id,
        customer_id: a.customer_id,
        reference: "VS-" + id.replace(/-/g, "").slice(0, 12).toUpperCase(),
        starts_at: s.starts_at,
        ends_at: s.ends_at,
        selection: {
          business_id: b.id,
          resource_id: a.resource_id,
          option_id: plan.id,
          date: s.date,
          time: s.time,
          duration_minutes:
            (Date.parse(s.ends_at) - Date.parse(s.starts_at)) / 60000,
          people: 1,
        },
        price_snapshot: {
          ...s,
          timezone: a.timezone,
          business_name: b.name,
          space_name: pool?.name ?? "Space",
          option_name: plan.name,
          total_minor: 0,
          subtotal_minor: 0,
          cleanup_minutes: 0,
          preparation_minutes: 0,
          admission_reference: a.reference,
        },
        customer_snapshot: a.customer_snapshot,
        created_by: actor.uid,
        admission_id: a.id,
        attendance: present ? "present" : "unmarked",
      };
    });
    await db.query(
      `INSERT INTO bookings(id,organization_id,business_id,resource_id,customer_id,reference,starts_at,ends_at,total_minor,selection,price_snapshot,customer_snapshot,people,created_by,admission_id,admission_attendance)
   SELECT v.id,v.organization_id,v.business_id,v.resource_id,v.customer_id,v.reference,v.starts_at,v.ends_at,0,v.selection,v.price_snapshot,v.customer_snapshot,1,v.created_by,v.admission_id,v.attendance
   FROM jsonb_to_recordset($1::jsonb) AS v(id uuid,organization_id uuid,business_id uuid,resource_id uuid,customer_id uuid,reference text,starts_at timestamptz,ends_at timestamptz,selection jsonb,price_snapshot jsonb,customer_snapshot jsonb,created_by text,admission_id uuid,attendance text)`,
      [JSON.stringify(rows)],
    );
    await db.query(
      `INSERT INTO booking_allocations(booking_id,inventory_key,starts_at,ends_at,quantity)
   SELECT v.id,$2,v.starts_at,v.ends_at,1 FROM jsonb_to_recordset($1::jsonb) AS v(id uuid,starts_at timestamptz,ends_at timestamptz)`,
      [JSON.stringify(rows), b.id + ":" + a.resource_id],
    );
    return rows.map((r) => r.id);
  }

  async create(actor: Actor, input: unknown) {
    const parsed = createAdmissionSchema.parse(input),
      { command_key, preview_token, ...v } = parsed;
    return this.command(
      actor,
      v.business_id,
      v.resource_id,
      command_key,
      "admission_create",
      parsed,
      "manage_subscriptions",
      async (db, m, b) => {
        const q = await this.previewIn(db, m, b, v);
        if (q.preview_token !== preview_token)
          throw new ConflictException(
            "The plan, amount or schedule changed. Review again before confirming.",
          );
        let customerId = v.customer.id;
        if (customerId) {
          if (
            !(
              await db.query(
                "SELECT id FROM customers WHERE id=$1 AND organization_id=$2",
                [customerId, m.organization_id],
              )
            ).rows.length
          )
            throw new BadRequestException(
              "Customer not found in this organization.",
            );
          if (
            m.role !== "owner" &&
            !(
              await db.query(
                "SELECT 1 FROM (SELECT business_id,resource_id FROM bookings WHERE customer_id=$1 AND organization_id=$2 UNION SELECT business_id,resource_id FROM admissions WHERE customer_id=$1 AND organization_id=$2) h JOIN staff_assignments s ON s.business_id=h.business_id WHERE s.membership_id=$3 AND (jsonb_array_length(s.resource_ids)=0 OR s.resource_ids @> jsonb_build_array(h.resource_id::text)) LIMIT 1",
                [customerId, m.organization_id, m.id],
              )
            ).rows.length
          )
            throw new ForbiddenException(
              "This customer is outside your assigned history.",
            );
        } else {
          customerId = randomUUID();
          await db.query(
            "INSERT INTO customers(id,organization_id,name,phone,email) VALUES($1,$2,$3,$4,$5)",
            [
              customerId,
              m.organization_id,
              v.customer.name,
              v.customer.phone.replace(/[^\d+]/g, ""),
              v.customer.email,
            ],
          );
        }
        const id = randomUUID(),
          reference = "AD-" + id.replace(/-/g, "").slice(0, 12).toUpperCase();
        const a = {
          id,
          business_id: b.id,
          resource_id: v.resource_id,
          customer_id: customerId,
          reference,
          timezone: b.timezone,
          total_minor: q.total_minor,
          plan_snapshot: q.plan,
          customer_snapshot: { ...v.customer, id: customerId },
        };
        await db.query(
          "INSERT INTO admissions(id,organization_id,business_id,resource_id,customer_id,reference,plan_id,plan_snapshot,customer_snapshot,timezone,mode,starts_on,expires_on,allowance,total_minor,schedule,renewed_from,created_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18)",
          [
            id,
            m.organization_id,
            b.id,
            v.resource_id,
            customerId,
            reference,
            (q.plan as Row).id,
            JSON.stringify(q.plan),
            JSON.stringify(a.customer_snapshot),
            b.timezone,
            v.mode,
            v.starts_on,
            q.expires_on,
            v.mode === "membership" ? 0 : q.plan.allowance,
            q.total_minor,
            JSON.stringify({
              weekdays: v.weekdays,
              time: v.time,
              duration_minutes: v.duration_minutes,
            }),
            v.renewed_from,
            actor.uid,
          ],
        );
        await this.visits(db, m, actor, a, b, q.sessions);
        await this.payment(db, m, actor, a, v.payments, "collection");
        await this.audit(
          db,
          m,
          actor,
          id,
          v.renewed_from ? "renewed" : "created",
          {
            renewed_from: v.renewed_from,
            mode: v.mode,
            allowance: q.plan.allowance,
            expires_on: q.expires_on,
            configured_amount_minor: q.plan.configured_price_minor,
            agreed_amount_minor: q.total_minor,
          },
        );
        return { id };
      },
    );
  }
  async list(actor: Actor, input: unknown) {
    const v = z
      .object({
        q: z.string().trim().max(100).optional(),
        kind: z.enum(["swimming", "play", "coaching"]).optional(),
        status: z
          .enum([
            "active",
            "upcoming",
            "completed",
            "expired",
            "cancelled",
            "deleted",
          ])
          .optional(),
        business_id: z.uuid().optional(),
        resource_id: z.uuid().optional(),
        plan_id: z.uuid().optional(),
        previous_plans: z.enum(["true", "false"]).optional(),
        needs_renewal: z.enum(["true", "false"]).optional(),
        reminder: z.enum(["due_soon", "unpaid"]).optional(),
        subscription: z.enum(["true", "false"]).optional(),
        cursor: z.coerce.number().int().min(0).max(100000).default(0),
      })
      .strict()
      .parse(input);
    const m = await this.member(actor);
    const values: unknown[] = [m.organization_id];
    const net =
      "COALESCE((SELECT sum(CASE WHEN p.kind='collection' THEN p.amount_minor ELSE -p.amount_minor END) FROM admission_payments p WHERE p.admission_id=a.id),0)::integer";
    let where = "a.organization_id=$1";
    if (v.status !== "deleted") where += " AND a.deleted_at IS NULL";
    if (v.needs_renewal === "true")
      where +=
        " AND (now() AT TIME ZONE a.timezone)::date>a.expires_on AND NOT a.cancelled AND NOT EXISTS(SELECT 1 FROM admissions renewed WHERE renewed.renewed_from=a.id)";
    const today = "(now() AT TIME ZONE a.timezone)::date",
      window =
        "COALESCE((b.configuration->>'renewal_reminder_days')::integer,3)",
      fees =
        "jsonb_array_elements(a.plan_snapshot->'subscription'->'instalments')";
    // Due soon: a subscription's next monthly fee, or a term ending, inside
    // the business's reminder window.
    if (v.reminder === "due_soon")
      where += ` AND NOT a.cancelled AND a.status IN ('active','upcoming','completed') AND (EXISTS(SELECT 1 FROM ${fees} i WHERE (i->>'due_on')::date>${today} AND (i->>'due_on')::date<=${today}+${window}) OR (${today}<=a.expires_on AND ${today}>=a.expires_on-${window} AND NOT EXISTS(SELECT 1 FROM admissions renewed WHERE renewed.renewed_from=a.id)))`;
    // Collect now: subscription months already started but not fully paid,
    // and ended plan terms still owed after renewal or cancellation.
    if (v.reminder === "unpaid")
      where += ` AND ((a.plan_snapshot ? 'subscription' AND COALESCE((SELECT sum((i->>'amount_minor')::integer) FROM ${fees} i WHERE (i->>'due_on')::date<=${today}),0)>${net}) OR (NOT a.plan_snapshot ? 'subscription' AND ${today}>a.expires_on AND (a.cancelled OR EXISTS(SELECT 1 FROM admissions renewed WHERE renewed.renewed_from=a.id)) AND a.total_minor>${net}))`;
    if (v.subscription === "true")
      where += " AND a.plan_snapshot ? 'subscription'";
    if (v.subscription === "false")
      where += " AND NOT a.plan_snapshot ? 'subscription'";
    const add = (sql: string, value: unknown) => {
      values.push(value);
      where += " AND " + sql.replaceAll("?", `$${values.length}`);
    };
    if (v.q)
      add(
        "(a.customer_snapshot->>'name' ILIKE ? OR a.customer_snapshot->>'phone' ILIKE ? OR a.reference ILIKE ?)",
        "%" + v.q + "%",
      );
    if (v.kind) add("a.plan_snapshot->>'kind'=?", v.kind);
    if (v.status) add("a.status=?", v.status);
    if (v.business_id) add("a.business_id=?", v.business_id);
    if (v.resource_id) add("a.resource_id=?", v.resource_id);
    if (v.plan_id) add("a.plan_id=?", v.plan_id);
    if (v.previous_plans === "true")
      where +=
        " AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(b.configuration->'plans','[]'::jsonb)) p WHERE p->>'id'=a.plan_id::text AND p->>'kind'=a.plan_snapshot->>'kind' AND p->>'enabled'='true' AND COALESCE(p->'pool_ids',p->'court_ids','[]'::jsonb) @> jsonb_build_array(a.resource_id::text))";
    if (m.role !== "owner")
      add(
        "EXISTS(SELECT 1 FROM staff_assignments s WHERE s.membership_id=? AND s.business_id=a.business_id AND (jsonb_array_length(s.resource_ids)=0 OR s.resource_ids @> jsonb_build_array(a.resource_id::text)))",
        m.id,
      );
    values.push(v.cursor);
    const rows = (
      await this.db.query<Row>(
        `SELECT a.*,b.name business_name,b.configuration business_configuration,r.name space_name,${net} net FROM admission_balances a JOIN businesses b ON b.id=a.business_id JOIN resources r ON r.id=a.resource_id WHERE ${where} ORDER BY ${v.needs_renewal === "true" || v.reminder ? "a.expires_on,a.id" : "a.created_at DESC,a.id"} LIMIT 51 OFFSET $${values.length}`,
        values,
      )
    ).rows;
    const names = await this.coachNames(this.db, m.organization_id);
    return {
      items: rows.slice(0, 50).map(({ business_configuration, ...a }) => ({
        ...withCurrentCoach(a, business_configuration, names),
        ...moneyStatus(a.total_minor, a.net),
        ...feeStatus(a),
        renewal_open: this.renewalOpen(a, business_configuration),
      })),
      next_cursor: rows.length > 50 ? v.cursor + 50 : null,
    };
  }
  /**
   * Whether a term can be renewed now: once completed or expired, or while
   * active inside its business's renewal reminder window. Renewed terms and
   * existing renewals are checked by the caller.
   */
  private renewalOpen(a: Row, configuration: Row | undefined) {
    if (a.deleted_at || a.cancelled) return false;
    if (["completed", "expired"].includes(a.status)) return true;
    if (a.status !== "active") return false;
    const today = localStamp(Date.now(), a.timezone).slice(0, 10);
    return today >= addDate(ymd(a.expires_on), -reminderDays(configuration));
  }
  /**
   * Home payment reminders. `due_soon` lists running terms whose next month
   * is due, with that month's price; `unpaid` lists ended terms still owed
   * money after renewal or cancellation.
   */
  async paymentReminders(actor: Actor, input: unknown) {
    const v = z
      .object({
        group: z.enum(["due_soon", "unpaid"]),
        cursor: z.coerce.number().int().min(0).max(100000).default(0),
      })
      .strict()
      .parse(input);
    const member = await this.member(actor);
    const amounts =
      this.allowed(member, "view_finance") ||
      this.allowed(member, "collect_payments");
    if (v.group === "unpaid" && !amounts)
      return { items: [], next_cursor: null };
    const page = await this.list(actor, {
      reminder: v.group,
      cursor: v.cursor,
    });
    return {
      ...page,
      items: page.items.map((a: Row) =>
        amounts
          ? a
          : {
              ...a,
              net: 0,
              net_paid_minor: 0,
              balance_minor: 0,
              refund_due_minor: 0,
              due_now_minor: 0,
              owed_now_minor: 0,
              next_due_minor: null,
              payment_status: "hidden",
            },
      ),
    };
  }
  async expired(actor: Actor, input: unknown) {
    const query = z
      .object({ cursor: z.coerce.number().int().min(0).max(100000).default(0) })
      .strict()
      .parse(input);
    const member = await this.member(actor);
    const page = await this.list(actor, {
      needs_renewal: "true",
      cursor: query.cursor,
    });
    if (
      this.allowed(member, "view_finance") ||
      this.allowed(member, "collect_payments")
    )
      return page;
    return {
      ...page,
      items: page.items.map((admission) => ({
        ...admission,
        net: 0,
        net_paid_minor: 0,
        balance_minor: 0,
        refund_due_minor: 0,
        payment_status: "hidden",
      })),
    };
  }
  async deleteMembership(actor: Actor, id: string, input: unknown) {
    const value = z
      .object({
        command_key: z.uuid(),
        version: z.number().int().positive(),
        reason: reasonSchema,
      })
      .strict()
      .parse(input);
    const original = await this.find(await this.member(actor), id);
    return this.command(
      actor,
      original.business_id,
      original.resource_id,
      value.command_key,
      "admission_delete",
      { id, ...value },
      "manage_subscriptions",
      async (db, member) => {
        const admission = await this.find(member, id, db);
        if (admission.version !== value.version)
          throw new ConflictException(
            "Membership changed. Refresh before deleting.",
          );
        if (admission.deleted_at)
          throw new BadRequestException("This membership was already deleted.");
        if (
          (
            await db.query(
              "SELECT id FROM bookings WHERE admission_id=$1 AND status<>'cancelled' AND starts_at<=now() AND ends_at>now() LIMIT 1",
              [id],
            )
          ).rows.length
        )
          throw new ConflictException(
            "A session is running. Delete the membership after it ends.",
          );
        await db.query(
          "UPDATE admissions SET deleted_at=now(),deleted_by=$2,deletion_reason=$3,version=version+1 WHERE id=$1",
          [id, actor.uid, value.reason],
        );
        await db.query(
          "DELETE FROM booking_allocations WHERE booking_id IN (SELECT id FROM bookings WHERE admission_id=$1 AND starts_at>now())",
          [id],
        );
        const cancelled = await db.query<{ id: string }>(
          "UPDATE bookings SET status='cancelled',version=version+1 WHERE admission_id=$1 AND starts_at>now() AND status<>'cancelled' RETURNING id",
          [id],
        );
        await this.audit(db, member, actor, id, "deleted", {
          reason: value.reason,
          previous_status: admission.status,
          total_minor: admission.total_minor,
          cancelled_session_ids: cancelled.rows.map((session) => session.id),
        });
        return { id };
      },
    );
  }
  async detail(actor: Actor, id: string) {
    const m = await this.member(actor),
      a = await this.find(m, id);
    const sessions = (
      await this.db.query<Row>(
        "SELECT id,starts_at,ends_at,status,admission_attendance,admission_waived,version,price_snapshot,(SELECT r.id FROM bookings r WHERE r.admission_replacement_for=bookings.id) AS replacement_id FROM bookings WHERE admission_id=$1 ORDER BY starts_at,id",
        [id],
      )
    ).rows;
    const payments = (
      await this.db.query<Row>(
        "SELECT * FROM admission_payments WHERE admission_id=$1 ORDER BY recorded_at,id",
        [id],
      )
    ).rows;
    const history = (
      await this.db.query<Row>(
        "SELECT history.action,history.details,history.actor_id,history.created_at,COALESCE(member.display_name,history.actor_id) AS actor_name FROM admission_history history LEFT JOIN memberships member ON member.user_id=history.actor_id AND member.organization_id=history.organization_id WHERE history.admission_id=$1 ORDER BY history.created_at,history.id",
        [id],
      )
    ).rows;
    const renewal = (
      await this.db.query<Row>(
        "SELECT id FROM admissions WHERE renewed_from=$1",
        [id],
      )
    ).rows[0];
    const business = await this.business(
      m,
      a.business_id,
      a.resource_id,
      this.db,
    );
    const net = payments.reduce(
      (n, p) =>
        n + (p.kind === "collection" ? p.amount_minor : -p.amount_minor),
      0,
    );
    return {
      ...withCurrentCoach(
        a,
        business.configuration,
        await this.coachNames(this.db, m.organization_id),
      ),
      can_attend: this.canMarkAttendance(m, a, business.configuration),
      business_name: business.name,
      space_name:
        admissionSpaces(business.configuration).find(
          (p: Row) => p.id === a.resource_id,
        )?.name ?? "Space",
      today: localStamp(Date.now(), a.timezone).slice(0, 10),
      local_now: localStamp(Date.now(), a.timezone),
      ...moneyStatus(a.total_minor, net),
      ...feeStatus({ ...a, net }),
      renewal_id: renewal?.id ?? null,
      renewal_open: this.renewalOpen(a, business.configuration),
      sessions: sessions.map((s) => ({
        ...s,
        local_start: localStamp(Date.parse(s.starts_at), a.timezone),
        local_end: localStamp(Date.parse(s.ends_at), a.timezone),
      })),
      payments,
      history,
    };
  }
  /** Join the exact running class interval, preserving its reserved capacity. */
  private async runningCoachingVisit(
    db: Queryable,
    a: Row,
    b: Row,
    pool: Row,
    now: number,
    startIfMissing = false,
    allocations?: Row[],
  ) {
    const occupied =
      allocations ??
      (await this.allocations(
        db,
        b.id,
        new Date(now).toISOString(),
        new Date(now + 1).toISOString(),
      ));
    const classes = new Map<string, Row>();
    for (const row of occupied) {
      const start = Date.parse(row.starts_at),
        end = Date.parse(row.ends_at);
      if (
        row.plan_id !== a.plan_id ||
        row.plan_snapshot?.kind !== "coaching" ||
        row.inventory_key !== `${b.id}:${a.resource_id}` ||
        start > now ||
        end <= now ||
        end - start !== a.plan_snapshot.class_duration_minutes * 60000
      )
        continue;
      classes.set(`${start}:${end}`, row);
    }
    if (!classes.size && startIfMissing) {
      const local = localStamp(now, a.timezone);
      return {
        ...interval(
          pool,
          a.plan_snapshot,
          local.slice(0, 10),
          local.slice(11, 16),
          a.plan_snapshot.class_duration_minutes,
          a.timezone,
        ),
        class_started: true,
      };
    }
    if (!classes.size)
      throw new BadRequestException(
        "No coaching class is running now for this plan and space. Mark attendance from a scheduled class.",
      );
    if (classes.size > 1)
      throw new ConflictException(
        "More than one coaching class is running. Open the student's scheduled class to mark attendance.",
      );
    const row = [...classes.values()][0];
    const start = localStamp(Date.parse(row.starts_at), a.timezone);
    const session = interval(
      pool,
      a.plan_snapshot,
      start.slice(0, 10),
      start.slice(11, 16),
      a.plan_snapshot.class_duration_minutes,
      a.timezone,
    );
    return {
      ...session,
      starts_at: new Date(row.starts_at).toISOString(),
      ends_at: new Date(row.ends_at).toISOString(),
      class_started: false,
    };
  }

  async checkIn(actor: Actor, id: string, input: unknown) {
    // New clients omit the clock; older clients may still send a complete visit.
    const automatic = z
      .object({
        command_key: z.uuid(),
        version: z.number().int().positive(),
        start_class: z.boolean().optional(),
      })
      .strict();
    const explicit = z
      .object({
        command_key: z.uuid(),
        version: z.number().int().positive(),
        date: calendarDate,
        time: clock,
        duration_minutes: z.number().int().min(30).max(1440),
      })
      .strict();
    const v = z.union([automatic, explicit]).parse(input);
    const original = await this.find(await this.member(actor), id);
    return this.command(
      actor,
      original.business_id,
      original.resource_id,
      v.command_key,
      "admission_checkin",
      { id, ...v },
      "mark_attendance",
      async (db, m, b) => {
        const a = await this.find(m, id, db);
        if (!this.canMarkAttendance(m, a, b.configuration))
          throw new ForbiddenException(
            "Attendance is limited to your assigned coaching plans.",
          );
        if (a.version !== v.version)
          throw new ConflictException("Admission changed. Refresh and retry.");
        if (a.mode !== "flexible")
          throw new BadRequestException(
            "Mark attendance on a scheduled session.",
          );
        const now = Date.now();
        const local = localStamp(now, a.timezone),
          today = local.slice(0, 10);
        if (
          !["active", "completed"].includes(a.status) ||
          today > ymd(a.expires_on)
        )
          throw new BadRequestException(
            "The plan is not active, has expired, or has no remaining days.",
          );
        const pool = admissionSpaces(b.configuration).find(
          (p: Row) => p.id === a.resource_id && p.enabled,
        );
        if (!pool || !["ready", "paused"].includes(b.status))
          throw new BadRequestException("This space is unavailable.");
        if ("start_class" in v && v.start_class) {
          const plan = b.configuration.plans?.find(
            (p: Row) => p.id === a.plan_id,
          );
          if (
            a.plan_snapshot.kind !== "coaching" ||
            !plan?.enabled ||
            !planSpaceIds(plan).includes(a.resource_id)
          )
            throw new BadRequestException("This coaching plan is unavailable.");
          if (
            m.role !== "owner" &&
            (!isCoach(m) ||
              currentCoachId(b.configuration, a.plan_id, a.plan_snapshot) !==
                m.id)
          )
            throw new ForbiddenException(
              "Only the assigned coach can start this class.",
            );
        }
        const s =
          "time" in v
            ? interval(
                pool,
                a.plan_snapshot,
                v.date,
                v.time,
                v.duration_minutes,
                a.timezone,
              )
            : a.plan_snapshot.kind === "coaching"
              ? await this.runningCoachingVisit(
                  db,
                  a,
                  b,
                  pool,
                  now,
                  "start_class" in v && v.start_class === true,
                )
              : interval(
                  pool,
                  a.plan_snapshot,
                  today,
                  local.slice(11, 16),
                  a.schedule.duration_minutes,
                  a.timezone,
                );
        const attendanceDate = s.date;
        const sameDay = (
          await db.query<Row>(
            "SELECT id FROM bookings WHERE admission_id=$1 AND status<>'cancelled' AND admission_attendance='present' AND (starts_at AT TIME ZONE $2)::date=$3::date ORDER BY starts_at DESC LIMIT 1",
            [id, a.timezone, attendanceDate],
          )
        ).rows[0];
        if (
          ("date" in v && v.date !== today) ||
          attendanceDate < ymd(a.starts_on) ||
          attendanceDate > ymd(a.expires_on) ||
          (a.status === "completed" && !sameDay)
        )
          throw new BadRequestException(
            "The plan is not active, has expired, or has no remaining days.",
          );
        if (
          localStamp(Date.parse(s.ends_at) - 1, a.timezone).slice(0, 10) >
          ymd(a.expires_on)
        )
          throw new BadRequestException(
            "The visit must end within admission validity.",
          );
        if (Date.parse(s.starts_at) > now || Date.parse(s.ends_at) <= now)
          throw new BadRequestException(
            "Choose a visit containing the current time.",
          );
        const occupied = await this.allocations(
          db,
          b.id,
          s.starts_at,
          s.ends_at,
        );
        const duplicate = occupied.find((r) => r.booking_id === sameDay?.id);
        if (duplicate)
          return {
            id,
            visit_id: duplicate.booking_id,
            class_started: false,
            local_start: localStamp(
              Date.parse(duplicate.starts_at),
              a.timezone,
            ),
            local_end: localStamp(Date.parse(duplicate.ends_at), a.timezone),
          };
        this.check(b, pool, a.plan_snapshot, s, occupied);
        const [visitId] = await this.visits(db, m, actor, a, b, [s], true);
        await db.query("UPDATE admissions SET version=version+1 WHERE id=$1", [
          id,
        ]);
        await this.audit(db, m, actor, id, "checked_in", {
          visit_id: visitId,
          local_date: attendanceDate,
          deducted: !sameDay,
          marked_at: new Date(now).toISOString(),
          class_started: "class_started" in s && s.class_started === true,
        });
        return {
          id,
          visit_id: visitId,
          class_started: "class_started" in s && s.class_started === true,
          marked_at: new Date(now).toISOString(),
          local_marked_at: local,
          local_start: s.local_start,
          local_end: s.local_end,
        };
      },
    );
  }
  async attendance(actor: Actor, id: string, visitId: string, input: unknown) {
    z.uuid().parse(visitId);
    const v = z
      .object({
        command_key: z.uuid(),
        version: z.number().int().positive(),
        attendance: z.enum(["unmarked", "present", "absent"]),
        reason: z.string().trim().max(500),
      })
      .strict()
      .parse(input);
    const member = await this.member(actor),
      original = await this.find(member, id);
    return this.command(
      actor,
      original.business_id,
      original.resource_id,
      v.command_key,
      "admission_attendance",
      { id, visitId, ...v },
      "mark_attendance",
      async (db, m, b) => {
        const a = await this.find(m, id, db);
        if (!this.canMarkAttendance(m, a, b.configuration))
          throw new ForbiddenException(
            "Attendance is limited to your assigned coaching plans.",
          );
        const s = (
          await db.query<Row>(
            "SELECT * FROM bookings WHERE id=$1 AND admission_id=$2 FOR UPDATE",
            [visitId, id],
          )
        ).rows[0];
        if (!s || s.status === "cancelled" || a.cancelled)
          throw new BadRequestException(
            "This session is cancelled or unavailable.",
          );
        if (s.version !== v.version)
          throw new ConflictException("Attendance changed. Refresh and retry.");
        if (Date.parse(s.starts_at) > Date.now())
          throw new BadRequestException(
            "Attendance cannot be marked before the session starts.",
          );
        const correction =
          s.admission_attendance !== "unmarked" ||
          a.mode === "flexible" ||
          Date.parse(s.ends_at) < Date.now() - 86400000;
        if (correction && (m.role !== "owner" || v.reason.length < 2))
          throw new ForbiddenException(
            "An owner must provide a reason for attendance corrections.",
          );
        if (
          a.mode === "flexible" &&
          v.attendance === "present" &&
          s.admission_attendance !== "present"
        ) {
          const occupied = (
            await db.query<Row>(
              "SELECT id FROM bookings WHERE admission_id=$1 AND status<>'cancelled' AND admission_attendance='present' AND (starts_at AT TIME ZONE $2)::date=( $3::timestamptz AT TIME ZONE $2)::date LIMIT 1",
              [id, a.timezone, s.starts_at],
            )
          ).rows.length;
          if (!occupied && a.remaining === 0)
            throw new BadRequestException(
              "No allowance remains for this correction.",
            );
        }
        await db.query(
          "UPDATE bookings SET admission_attendance=$1,version=version+1 WHERE id=$2",
          [v.attendance, visitId],
        );
        await db.query("UPDATE admissions SET version=version+1 WHERE id=$1", [
          id,
        ]);
        await this.audit(db, m, actor, id, "attendance", {
          visit_id: visitId,
          previous: s.admission_attendance,
          current: v.attendance,
          reason: v.reason,
          marked_at: new Date(Date.now()).toISOString(),
        });
        return { id };
      },
    );
  }
  async sessionChange(
    actor: Actor,
    id: string,
    visitId: string,
    input: unknown,
  ) {
    z.uuid().parse(visitId);
    const v = z
      .object({
        command_key: z.uuid(),
        version: z.number().int().positive(),
        action: z.enum(["cancel", "waive", "reschedule"]),
        reason: reasonSchema,
        date: calendarDate.optional(),
        time: clock.optional(),
      })
      .strict()
      .parse(input);
    const original = await this.find(await this.member(actor), id);
    return this.command(
      actor,
      original.business_id,
      original.resource_id,
      v.command_key,
      "admission_session",
      { id, visitId, ...v },
      "manage_subscriptions",
      async (db, m, b) => {
        const a = await this.find(m, id, db),
          session = (
            await db.query<Row>(
              "SELECT * FROM bookings WHERE id=$1 AND admission_id=$2 FOR UPDATE",
              [visitId, id],
            )
          ).rows[0];
        if (!session || a.mode !== "fixed" || a.cancelled || a.deleted_at)
          throw new BadRequestException(
            "Choose a fixed session on an available admission.",
          );
        if (session.version !== v.version)
          throw new ConflictException("Session changed. Refresh and retry.");
        const past = Date.parse(session.starts_at) <= Date.now();
        if (v.action === "waive") {
          if (
            m.role !== "owner" ||
            Date.parse(session.ends_at) > Date.now() ||
            session.status === "cancelled"
          )
            throw new ForbiddenException(
              "Only the owner can restore credit for an ended session.",
            );
          await db.query(
            "UPDATE bookings SET admission_waived=true,version=version+1 WHERE id=$1",
            [visitId],
          );
        } else if (v.action === "cancel") {
          if (past)
            throw new BadRequestException(
              "An ended or running session requires an owner credit correction.",
            );
          await db.query(
            "UPDATE bookings SET status='cancelled',version=version+1 WHERE id=$1",
            [visitId],
          );
          await db.query(
            "DELETE FROM booking_allocations WHERE booking_id=$1",
            [visitId],
          );
        } else {
          if (
            (past && !session.admission_waived) ||
            !v.date ||
            !v.time ||
            v.date < ymd(a.starts_on) ||
            v.date > ymd(a.expires_on)
          )
            throw new BadRequestException(
              "Choose a future session within admission validity.",
            );
          if (past && session.admission_waived) {
            if (
              (
                await db.query(
                  "SELECT id FROM bookings WHERE admission_replacement_for=$1",
                  [visitId],
                )
              ).rows.length
            )
              throw new ConflictException(
                "A replacement for this credit already exists. Reschedule that replacement instead.",
              );
          }
          const pool = admissionSpaces(b.configuration).find(
            (p: Row) => p.id === a.resource_id && p.enabled,
          );
          if (!pool || b.status !== "ready")
            throw new BadRequestException("This space is unavailable.");
          const duration = session.selection.duration_minutes;
          const next = interval(
            pool,
            a.plan_snapshot,
            v.date,
            v.time,
            duration,
            a.timezone,
          );
          if (
            Date.parse(next.starts_at) <= Date.now() ||
            localStamp(Date.parse(next.ends_at) - 1, a.timezone).slice(0, 10) >
              ymd(a.expires_on)
          )
            throw new BadRequestException(
              "Choose a future session ending within admission validity.",
            );
          this.check(
            b,
            pool,
            a.plan_snapshot,
            next,
            await this.allocations(db, b.id, next.starts_at, next.ends_at),
            visitId,
          );
          const duplicate = (
            await db.query<Row>(
              "SELECT id FROM bookings WHERE admission_id=$1 AND id<>$2 AND status<>'cancelled' AND starts_at<$4 AND ends_at>$3",
              [id, visitId, next.starts_at, next.ends_at],
            )
          ).rows[0];
          if (duplicate)
            throw new ConflictException(
              "This customer already has an overlapping session.",
            );
          if (past && session.admission_waived) {
            const [replacement] = await this.visits(db, m, actor, a, b, [next]);
            await db.query(
              "UPDATE bookings SET admission_replacement_for=$1 WHERE id=$2",
              [visitId, replacement],
            );
          } else {
            await db.query(
              "UPDATE bookings SET status='confirmed',starts_at=$1,ends_at=$2,selection=$3,price_snapshot=$4,admission_attendance='unmarked',version=version+1 WHERE id=$5",
              [
                next.starts_at,
                next.ends_at,
                JSON.stringify({
                  ...session.selection,
                  date: v.date,
                  time: v.time,
                }),
                JSON.stringify({ ...session.price_snapshot, ...next }),
                visitId,
              ],
            );
            await db.query(
              "DELETE FROM booking_allocations WHERE booking_id=$1",
              [visitId],
            );
            await db.query(
              "INSERT INTO booking_allocations(booking_id,inventory_key,starts_at,ends_at,quantity) VALUES($1,$2,$3,$4,1)",
              [
                visitId,
                b.id + ":" + a.resource_id,
                next.starts_at,
                next.ends_at,
              ],
            );
          }
        }
        await db.query("UPDATE admissions SET version=version+1 WHERE id=$1", [
          id,
        ]);
        await this.audit(db, m, actor, id, "session_" + v.action, {
          visit_id: visitId,
          reason: v.reason,
          previous_start: session.starts_at,
          date: v.date,
          time: v.time,
        });
        return { id };
      },
    );
  }
  async payments(actor: Actor, id: string, input: unknown) {
    const v = z
      .object({
        command_key: z.uuid(),
        version: z.number().int().positive(),
        kind: z.enum(["collection", "refund"]),
        reason: z.string().trim().max(500),
        payments: z.array(paymentSchema).min(1).max(20),
      })
      .strict()
      .parse(input);
    const original = await this.find(await this.member(actor), id);
    return this.command(
      actor,
      original.business_id,
      original.resource_id,
      v.command_key,
      "admission_payment",
      { id, ...v },
      "collect_payments",
      async (db, m) => {
        const a = await this.find(m, id, db);
        if (a.version !== v.version)
          throw new ConflictException("Admission changed. Refresh and retry.");
        if (v.kind === "refund" && v.reason.length < 2)
          throw new BadRequestException("Provide a refund reason.");
        await this.payment(db, m, actor, a, v.payments, v.kind, v.reason);
        await db.query("UPDATE admissions SET version=version+1 WHERE id=$1", [
          id,
        ]);
        await this.audit(db, m, actor, id, v.kind, {
          amount_minor: v.payments.reduce((n, p) => n + p.amount_minor, 0),
          reason: v.reason,
        });
        return { id };
      },
    );
  }
  /**
   * Moves every remaining session of a subscription to new weekdays, time
   * and hours from [from_date]; sessions before it stay as they are.
   */
  async reschedule(actor: Actor, id: string, input: unknown) {
    const v = z
      .object({
        command_key: z.uuid(),
        version: z.number().int().positive(),
        from_date: calendarDate,
        weekdays: z.array(z.number().int().min(1).max(7)).min(1).max(7),
        time: clock,
        duration_minutes: z.number().int().min(30).max(1440),
        reason: reasonSchema,
      })
      .strict()
      .parse(input);
    const original = await this.find(await this.member(actor), id);
    return this.command(
      actor,
      original.business_id,
      original.resource_id,
      v.command_key,
      "admission_schedule",
      { id, ...v },
      "manage_subscriptions",
      async (db, m, b) => {
        const a = await this.find(m, id, db);
        if (a.version !== v.version)
          throw new ConflictException("Admission changed. Refresh and retry.");
        if (
          !isSubscription(a.plan_snapshot) ||
          a.mode !== "fixed" ||
          a.cancelled ||
          a.deleted_at ||
          !["active", "upcoming"].includes(a.status)
        )
          throw new BadRequestException(
            "Only an active or upcoming subscription can be rescheduled.",
          );
        const today = localStamp(Date.now(), a.timezone).slice(0, 10),
          expires = ymd(a.expires_on);
        if (
          v.from_date < today ||
          v.from_date < ymd(a.starts_on) ||
          v.from_date > expires
        )
          throw new BadRequestException(
            "Choose a date from today within the subscription.",
          );
        const pool = admissionSpaces(b.configuration).find(
          (p: Row) => p.id === a.resource_id && p.enabled,
        );
        if (!pool || b.status !== "ready")
          throw new BadRequestException("This space is unavailable.");
        const from = new Date(
          Math.max(zonedTime(v.from_date, "00:00", a.timezone), Date.now()),
        ).toISOString();
        const moving = (
          await db.query<Row>(
            "SELECT id FROM bookings WHERE admission_id=$1 AND status<>'cancelled' AND starts_at>=$2 FOR UPDATE",
            [id, from],
          )
        ).rows.map((r) => r.id);
        await db.query(
          "UPDATE bookings SET status='cancelled',version=version+1 WHERE id=ANY($1::uuid[])",
          [moving],
        );
        await db.query(
          "DELETE FROM booking_allocations WHERE booking_id=ANY($1::uuid[])",
          [moving],
        );
        const sessions = fixedDates(v.from_date, expires, v.weekdays, 1000)
          .map((date) =>
            interval(
              pool,
              a.plan_snapshot,
              date,
              v.time,
              v.duration_minutes,
              a.timezone,
            ),
          )
          .filter((s) => Date.parse(s.starts_at) > Date.now());
        if (
          sessions.some(
            (s) =>
              localStamp(Date.parse(s.ends_at) - 1, a.timezone).slice(0, 10) >
              expires,
          )
        )
          throw new BadRequestException(
            "Sessions must end within the subscription.",
          );
        for (let i = 1; i < sessions.length; i++)
          if (
            Date.parse(sessions[i].starts_at) <
            Date.parse(sessions[i - 1].ends_at)
          )
            throw new BadRequestException(
              "The weekly schedule contains overlapping sessions.",
            );
        if (sessions.length) {
          const occupied = await this.allocations(
            db,
            b.id,
            sessions[0].starts_at,
            sessions.at(-1)!.ends_at,
          );
          for (const s of sessions)
            try {
              this.check(b, pool, a.plan_snapshot, s, occupied);
            } catch (e) {
              if (!(e instanceof ConflictException)) throw e;
              throw await this.clash(db, m, b, pool, s, occupied, e);
            }
        }
        await this.visits(db, m, actor, a, b, sessions);
        const kept = Number(
          (
            await db.query<Row>(
              "SELECT count(*)::integer n FROM bookings WHERE admission_id=$1 AND status<>'cancelled'",
              [id],
            )
          ).rows[0].n,
        );
        if (kept < 1)
          throw new BadRequestException(
            "No sessions remain with this schedule. Choose other weekdays or an earlier date.",
          );
        await db.query(
          "UPDATE admissions SET schedule=$2,allowance=$3,version=version+1 WHERE id=$1",
          [
            id,
            JSON.stringify({
              weekdays: v.weekdays,
              time: v.time,
              duration_minutes: v.duration_minutes,
            }),
            kept,
          ],
        );
        await this.audit(db, m, actor, id, "rescheduled", {
          from_date: v.from_date,
          weekdays: v.weekdays,
          time: v.time,
          duration_minutes: v.duration_minutes,
          moved: moving.length,
          sessions: sessions.length,
          reason: v.reason,
        });
        return { id };
      },
    );
  }
  async cancel(actor: Actor, id: string, input: unknown) {
    const v = z
      .object({
        command_key: z.uuid(),
        version: z.number().int().positive(),
        reason: reasonSchema,
      })
      .strict()
      .parse(input);
    const original = await this.find(await this.member(actor), id);
    return this.command(
      actor,
      original.business_id,
      original.resource_id,
      v.command_key,
      "admission_cancel",
      { id, ...v },
      "manage_subscriptions",
      async (db, m) => {
        const a = await this.find(m, id, db);
        if (a.version !== v.version)
          throw new ConflictException("Admission changed. Refresh and retry.");
        if (!["active", "upcoming"].includes(a.status))
          throw new BadRequestException(
            "Only an active or upcoming admission can be cancelled.",
          );
        if (isSubscription(a.plan_snapshot)) {
          // Stopping keeps only the monthly fees that have already started.
          const today = localStamp(Date.now(), a.timezone).slice(0, 10);
          const kept = (
            a.plan_snapshot.subscription.instalments as Row[]
          ).filter((i) => i.due_on <= today);
          const snapshot = {
            ...a.plan_snapshot,
            subscription: {
              ...a.plan_snapshot.subscription,
              instalments: kept,
              stopped_on: today,
            },
          };
          await db.query(
            "UPDATE admissions SET plan_snapshot=$2,total_minor=$3 WHERE id=$1",
            [
              id,
              JSON.stringify(snapshot),
              kept.reduce((n, i) => n + i.amount_minor, 0),
            ],
          );
        }
        await db.query(
          "UPDATE admissions SET cancelled=true,version=version+1 WHERE id=$1",
          [id],
        );
        await db.query(
          "UPDATE bookings SET status='cancelled',version=version+1 WHERE admission_id=$1 AND starts_at>now()",
          [id],
        );
        await this.audit(db, m, actor, id, "cancelled", { reason: v.reason });
        return { id };
      },
    );
  }
}
