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
type Row = Record<string, any>;
const settleSchema = z
  .object({
    command_key: z.uuid(),
    direction: z.enum(["collect", "give"]),
    amount_minor: z.number().int().positive().max(100000000),
    expected_balance_minor: z.number().int(),
    note: z.string().trim().max(300).default(""),
  })
  .strict();
const dateSchema = z
  .object({
    date: z.iso.date().optional(),
    cursor: z.coerce.number().int().min(0).max(1000000).default(0),
    settlement_cursor: z.coerce.number().int().min(0).max(1000000).default(0),
  })
  .strict()
  .default({ cursor: 0, settlement_cursor: 0 });
// Cash held = cash-account ledger lines attributed to the staff member (a reversal counts for whoever
// recorded the original entry) minus cash already collected plus cash already given back.
const HOLDING_SQL = `SELECT m.id AS membership_id,
 COALESCE((SELECT sum(l.amount_minor) FROM finance_lines l
  JOIN money_accounts a ON a.id=l.account_id AND a.kind='cash'
  JOIN finance_events e ON e.id=l.event_id
  LEFT JOIN finance_events o ON o.id=e.reverses_id
  WHERE e.organization_id=m.organization_id AND e.kind<>'transfer'
   AND COALESCE(o.recorded_by,e.recorded_by)=m.user_id
   AND COALESCE(o.occurred_at,e.occurred_at)>=COALESCE((SELECT started_at FROM staff_cash_tracking WHERE organization_id=m.organization_id),'2000-01-01')),0)
 - COALESCE((SELECT sum(amount_minor) FROM staff_cash_settlements s WHERE s.membership_id=m.id AND s.direction='collect'),0)
 + COALESCE((SELECT sum(amount_minor) FROM staff_cash_settlements s WHERE s.membership_id=m.id AND s.direction='give'),0) AS holding_minor
 FROM memberships m WHERE m.organization_id=$1`;
@Injectable()
export class StaffCashService {
  constructor(
    private readonly db: Database,
    private readonly workspace: WorkspaceService,
  ) {}
  private async holdings(db: Queryable, org: string, only?: string) {
    const rows = (
      await db.query<Row>(
        only ? `${HOLDING_SQL} AND m.id=$2` : HOLDING_SQL,
        only ? [org, only] : [org],
      )
    ).rows;
    return new Map(rows.map((r) => [r.membership_id, Number(r.holding_minor)]));
  }
  private settlementRow(r: Row) {
    return {
      id: r.id,
      membership_id: r.membership_id,
      staff_name: r.staff_name,
      direction: r.direction,
      amount_minor: Number(r.amount_minor),
      balance_after_minor: Number(r.balance_after_minor),
      note: r.note,
      settled_at: r.settled_at,
    };
  }
  async me(actor: Actor, input: unknown) {
    const v = dateSchema.parse(input);
    const m = await this.workspace.member(actor);
    if (m.role === "owner")
      throw new ForbiddenException("Owners use the staff cash overview.");
    if (
      !["collect_payments", "view_finance"].some((p) =>
        m.permissions.includes(p),
      )
    )
      throw new ForbiddenException(
        "Payment collection or finance access is required.",
      );
    const tz = (
      await this.db.query<Row>(
        "SELECT COALESCE((SELECT timezone FROM locations WHERE organization_id=$1 ORDER BY id LIMIT 1),'UTC') AS tz",
        [m.organization_id],
      )
    ).rows[0].tz;
    const today = (
      await this.db.query<Row>(
        "SELECT (now() AT TIME ZONE $1)::date::text AS d",
        [tz],
      )
    ).rows[0].d;
    const date = v.date ?? today;
    const holding =
      (await this.holdings(this.db, m.organization_id, m.id)).get(m.id) ?? 0;
    const range = `e.occurred_at >= ($3::date::timestamp AT TIME ZONE $2) AND e.occurred_at < (($3::date+1)::timestamp AT TIME ZONE $2)`;
    // Totals: only the member's own entries (reversals credit the original recorder).
    const lines = (
      await this.db.query<Row>(
        `SELECT l.method,a.kind AS account_kind,COALESCE(o.kind,e.kind) AS event_kind,sum(l.amount_minor) AS total
         FROM finance_lines l JOIN money_accounts a ON a.id=l.account_id
         JOIN finance_events e ON e.id=l.event_id LEFT JOIN finance_events o ON o.id=e.reverses_id
         WHERE e.organization_id=$1 AND e.kind<>'transfer' AND COALESCE(o.recorded_by,e.recorded_by)=$4 AND ${range}
         GROUP BY l.method,a.kind,COALESCE(o.kind,e.kind)`,
        [m.organization_id, tz, date, m.user_id],
      )
    ).rows;
    const by_method = { cash: 0, upi: 0, card: 0, bank_transfer: 0 } as Record<
      string,
      number
    >;
    let collected = 0,
      refunded = 0,
      expenses = 0,
      bank = 0;
    for (const r of lines) {
      const t = Number(r.total);
      if (r.event_kind === "expense") expenses += -t;
      else if (["booking_refund", "admission_refund"].includes(r.event_kind))
        refunded += -t;
      else {
        collected += t;
        by_method[r.method] = (by_method[r.method] ?? 0) + t;
        if (r.account_kind !== "cash") bank += t;
      }
    }
    // Personal activity only, including owner reversals attributed to this member.
    const transactions = (
      await this.db.query<Row>(
        `SELECT e.id,e.kind,e.reason,
         COALESCE(b.reference,ad.reference,e.reference) AS reference,
         COALESCE(b.customer_snapshot->>'name',ad.customer_snapshot->>'name','') AS customer_name,
         r.name AS space_name,bs.name AS business_name,
         COALESCE(mm.display_name,e.recorded_by) AS staff_name,(e.recorded_by=$4) AS mine,
         (e.occurred_at AT TIME ZONE $2)::text AS local_time,
         (SELECT jsonb_agg(jsonb_build_object('method',l.method,'amount_minor',l.amount_minor,'is_cash',a.kind='cash') ORDER BY l.id)
           FROM finance_lines l JOIN money_accounts a ON a.id=l.account_id WHERE l.event_id=e.id) AS lines
         FROM finance_events e LEFT JOIN finance_events o ON o.id=e.reverses_id
         LEFT JOIN booking_payments bp ON bp.id=COALESCE(e.booking_payment_id,o.booking_payment_id)
         LEFT JOIN bookings b ON b.id=bp.booking_id
         LEFT JOIN admission_payments ap ON ap.id=COALESCE(e.admission_payment_id,o.admission_payment_id)
         LEFT JOIN admissions ad ON ad.id=ap.admission_id
         LEFT JOIN resources r ON r.id=e.resource_id LEFT JOIN businesses bs ON bs.id=e.business_id
         LEFT JOIN memberships mm ON mm.user_id=e.recorded_by AND mm.organization_id=e.organization_id
         WHERE e.organization_id=$1 AND COALESCE(o.kind,e.kind)<>'transfer' AND ${range}
          AND COALESCE(o.recorded_by,e.recorded_by)=$4
         ORDER BY e.occurred_at DESC,e.id DESC LIMIT 51 OFFSET $5`,
        [m.organization_id, tz, date, m.user_id, v.cursor],
      )
    ).rows;
    const settlements = (
      await this.db.query<Row>(
        `SELECT s.*,$2::text AS staff_name FROM staff_cash_settlements s WHERE s.membership_id=$1
         AND s.organization_id=$3 ORDER BY s.settled_at DESC,s.id DESC LIMIT 51 OFFSET $4`,
        [m.id, m.display_name, m.organization_id, v.settlement_cursor],
      )
    ).rows;
    const handovers = (
      await this.db.query<Row>(
        `SELECT COALESCE(sum(amount_minor) FILTER (WHERE direction='collect'),0) AS given,
         COALESCE(sum(amount_minor) FILTER (WHERE direction='give'),0) AS received
         FROM staff_cash_settlements WHERE organization_id=$1 AND membership_id=$2`,
        [m.organization_id, m.id],
      )
    ).rows[0];
    return {
      date,
      today,
      handed_over_minor: Number(handovers.given),
      received_from_owner_minor: Number(handovers.received),
      next_cursor: transactions.length > 50 ? v.cursor + 50 : null,
      next_settlement_cursor:
        settlements.length > 50 ? v.settlement_cursor + 50 : null,
      collected_minor: collected,
      refunded_minor: refunded,
      expenses_minor: expenses,
      by_method,
      bank_minor: bank,
      cash_holding_minor: holding,
      transactions: transactions.slice(0, 50).map((t) => ({
        ...t,
        lines: (t.lines ?? []).map((l: Row) => ({ ...l })),
      })),
      settlements: settlements.slice(0, 50).map((s) => this.settlementRow(s)),
    };
  }
  async overview(actor: Actor) {
    const m = await this.workspace.member(actor, true);
    const holdings = await this.holdings(this.db, m.organization_id);
    const staff = (
      await this.db.query<Row>(
        `SELECT m.id,m.display_name,m.role,
         (SELECT max(settled_at) FROM staff_cash_settlements s WHERE s.membership_id=m.id) AS last_settled_at,
         COALESCE((SELECT jsonb_agg(DISTINCT r.name) FROM staff_assignments a JOIN resources r ON r.business_id=a.business_id
           AND (jsonb_array_length(a.resource_ids)=0 OR a.resource_ids ? r.id::text) WHERE a.membership_id=m.id),'[]'::jsonb) AS spaces
         FROM memberships m WHERE m.organization_id=$1 AND m.role<>'owner' AND m.active=true ORDER BY m.display_name,m.id`,
        [m.organization_id],
      )
    ).rows;
    return {
      staff: staff.map((s) => ({
        membership_id: s.id,
        name: s.display_name,
        spaces: s.spaces,
        last_settled_at: s.last_settled_at,
        holding_minor: holdings.get(s.id) ?? 0,
      })),
    };
  }
  async settle(actor: Actor, membershipId: string, input: unknown) {
    const v = settleSchema.parse(input),
      hash = createHash("sha256")
        .update(JSON.stringify({ membershipId, ...v }))
        .digest("hex");
    return this.db.transaction(async (db) => {
      const owner = await this.workspace.member(actor, true, db);
      await db.query("SELECT id FROM organizations WHERE id=$1 FOR UPDATE", [
        owner.organization_id,
      ]);
      const old = (
        await db.query<Row>(
          "SELECT id,request_hash,balance_after_minor FROM staff_cash_settlements WHERE organization_id=$1 AND command_key=$2",
          [owner.organization_id, v.command_key],
        )
      ).rows[0];
      if (old) {
        if (old.request_hash !== hash)
          throw new ConflictException(
            "This request key belongs to another settlement.",
          );
        return {
          id: old.id,
          balance_after_minor: Number(old.balance_after_minor),
        };
      }
      const staff = (
        await db.query<Row>(
          "SELECT id FROM memberships WHERE id=$1 AND organization_id=$2 AND role<>'owner'",
          [membershipId, owner.organization_id],
        )
      ).rows[0];
      if (!staff) throw new NotFoundException("Staff member not found.");
      const balance =
        (await this.holdings(db, owner.organization_id, staff.id)).get(
          staff.id,
        ) ?? 0;
      if (balance !== v.expected_balance_minor)
        throw new ConflictException(
          "The staff cash balance changed. Review the new amount and try again.",
        );
      if (balance === 0)
        throw new BadRequestException("This staff member holds no cash.");
      if (v.direction !== (balance > 0 ? "collect" : "give"))
        throw new BadRequestException(
          balance > 0
            ? "Staff owes cash. Collect it from them."
            : "Owner owes cash. Give it to the staff member.",
        );
      if (v.amount_minor > Math.abs(balance))
        throw new BadRequestException("Amount is more than the balance.");
      const after =
        balance +
        (v.direction === "collect" ? -v.amount_minor : v.amount_minor);
      const id = randomUUID();
      await db.query(
        `INSERT INTO staff_cash_settlements(id,organization_id,membership_id,direction,amount_minor,balance_before_minor,balance_after_minor,settled_by,note,command_key,request_hash)
         VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
        [
          id,
          owner.organization_id,
          staff.id,
          v.direction,
          v.amount_minor,
          balance,
          after,
          actor.uid,
          v.note,
          v.command_key,
          hash,
        ],
      );
      await this.workspace.audit(
        db,
        actor,
        owner.organization_id,
        `staff_cash_${v.direction}`,
        id,
      );
      return { id, balance_after_minor: after };
    });
  }
  // Settlements shown in the owner's transaction history, newest first.
  async history(actor: Actor, input: unknown) {
    const m = await this.workspace.member(actor, true);
    const v = z
      .object({ from: z.iso.date(), until: z.iso.date() })
      .strict()
      .parse(input);
    const rows = (
      await this.db.query<Row>(
        `SELECT s.*,m.display_name AS staff_name FROM staff_cash_settlements s JOIN memberships m ON m.id=s.membership_id
         WHERE s.organization_id=$1 AND s.settled_at >= ($2::date::timestamp AT TIME ZONE COALESCE((SELECT timezone FROM locations WHERE organization_id=$1 ORDER BY id LIMIT 1),'UTC'))
          AND s.settled_at < (($3::date+1)::timestamp AT TIME ZONE COALESCE((SELECT timezone FROM locations WHERE organization_id=$1 ORDER BY id LIMIT 1),'UTC'))
         ORDER BY s.settled_at DESC,s.id LIMIT 500`,
        [m.organization_id, v.from, v.until],
      )
    ).rows;
    return { items: rows.map((r) => this.settlementRow(r)) };
  }
}
