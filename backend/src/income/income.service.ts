import {
  Injectable,
  BadRequestException,
  ForbiddenException,
  NotFoundException,
  ConflictException,
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { Database, Queryable } from "../common/database";
import { Actor } from "../common/auth.guard";
import { WorkspaceService } from "../workspace/workspace.service";
import { AccountsService } from "../accounts/accounts.service";
import { entrySchema } from "../accounts/accounts.validation";
import { categoryInput } from "../expenses/expenses.validation";
import { incomeFilter } from "./income.validation";
type Row = Record<string, any>;
const defaults = [
  ["sponsorship", "Sponsorship"],
  ["events", "Events"],
  ["rentals", "Rentals"],
  ["coaching", "Coaching fees"],
  ["food", "Food & beverages"],
  ["merchandise", "Merchandise"],
  ["other", "Other"],
];
// Income uses the same rule as the Accounts overview: collections plus extra
// income, with refunds reported separately. Reversals keep their original kind.
const base = "COALESCE(o.kind,e.kind)";
const kinds = `${base} IN ('income','booking_collection','admission_collection','booking_refund','admission_refund')`;
const refund = `${base} IN ('booking_refund','admission_refund')`;
@Injectable()
export class IncomeService {
  constructor(
    private readonly db: Database,
    private readonly workspace: WorkspaceService,
    private readonly accounts: AccountsService,
  ) {}
  private async member(actor: Actor, db: Queryable = this.db) {
    const m = await this.workspace.member(actor, false, db);
    if (m.role !== "owner" && !m.permissions.includes("view_finance"))
      throw new ForbiddenException("Finance access is required.");
    return m;
  }
  private scope(m: Row, values: unknown[], alias = "e") {
    let sql = `${alias}.organization_id=$1`;
    if (m.role !== "owner") {
      values.push(m.id);
      sql += ` AND EXISTS(SELECT 1 FROM staff_assignments a WHERE a.membership_id=$${values.length} AND a.business_id=${alias}.business_id AND (jsonb_array_length(a.resource_ids)=0 OR a.resource_ids ? ${alias}.resource_id::text))`;
    }
    return sql;
  }
  async catalog(actor: Actor) {
    const m = await this.workspace.member(actor);
    if (
      m.role !== "owner" &&
      !m.permissions.some((p: string) =>
        ["view_finance", "collect_payments"].includes(p),
      )
    )
      throw new ForbiddenException("Income access is required.");
    await this.db.query(
      "INSERT INTO income_categories(organization_id,default_key,name) SELECT $1,v->>0,v->>1 FROM jsonb_array_elements($2::jsonb) v ON CONFLICT DO NOTHING",
      [m.organization_id, JSON.stringify(defaults)],
    );
    return {
      categories: (
        await this.db.query(
          "SELECT id,name,active FROM income_categories WHERE organization_id=$1 ORDER BY name",
          [m.organization_id],
        )
      ).rows,
    };
  }
  async category(actor: Actor, input: unknown, id?: string) {
    const m = await this.workspace.member(actor, true),
      v = categoryInput.parse(input);
    const categoryId = id ?? randomUUID();
    try {
      if (id) {
        if (
          !(
            await this.db.query(
              "UPDATE income_categories SET name=$1,active=$2 WHERE organization_id=$3 AND id=$4 RETURNING id",
              [v.name, v.active, m.organization_id, id],
            )
          ).rows.length
        )
          throw new NotFoundException("Category not found.");
      } else
        await this.db.query(
          "INSERT INTO income_categories(id,organization_id,name) VALUES($1,$2,$3)",
          [categoryId, m.organization_id, v.name],
        );
    } catch (e) {
      if ((e as any).code === "23505")
        throw new ConflictException(
          "A category with this name already exists.",
        );
      throw e;
    }
    return { id: categoryId };
  }
  async create(actor: Actor, input: unknown) {
    const v = entrySchema.parse(input);
    if (v.kind !== "income" || !v.income_category_id)
      throw new BadRequestException("Choose an income category.");
    return this.accounts.createEntry(actor, v);
  }
  private async context(actor: Actor, input: unknown, db: Queryable = this.db) {
    const m = await this.member(actor, db),
      f = incomeFilter.parse(input);
    const c = (
      await db.query<Row>(
        "SELECT o.name,o.currency,l.timezone FROM organizations o JOIN locations l ON l.organization_id=o.id WHERE o.id=$1 ORDER BY l.id LIMIT 1",
        [m.organization_id],
      )
    ).rows[0];
    const values: unknown[] = [m.organization_id];
    let where = this.scope(m, values);
    where += ` AND ${kinds}`;
    values.push(c.timezone, f.from, f.until);
    where += ` AND e.occurred_at >= ($${values.length - 1}::date::timestamp AT TIME ZONE $${values.length - 2}) AND e.occurred_at < (($${values.length}::date+1)::timestamp AT TIME ZONE $${values.length - 2})`;
    if (f.source === "bookings")
      where += ` AND ${base} IN ('booking_collection','booking_refund')`;
    else if (f.source === "admissions")
      where += ` AND ${base} IN ('admission_collection','admission_refund')`;
    else if (f.source) {
      values.push(f.source);
      where += ` AND ${base}='income' AND COALESCE(e.income_category_id,o.income_category_id)=$${values.length}`;
    }
    for (const key of ["business_id", "resource_id"] as const) {
      if (f[key]) {
        values.push(f[key]);
        where += ` AND e.${key}=$${values.length}`;
      }
    }
    if (f.account_id) {
      values.push(f.account_id);
      where += ` AND EXISTS(SELECT 1 FROM finance_lines fl WHERE fl.event_id=e.id AND fl.account_id=$${values.length})`;
    }
    if (f.q) {
      values.push(`%${f.q.replace(/[\\%_]/g, "\\$&")}%`);
      where += ` AND (e.reason ILIKE $${values.length} OR e.reference ILIKE $${values.length} OR COALESCE(b.reference,ad.reference) ILIKE $${values.length} OR COALESCE(b.customer_snapshot->>'name',ad.customer_snapshot->>'name') ILIKE $${values.length})`;
    }
    return { m, f, c, values, where };
  }
  private cte(where: string, tzIndex: number) {
    return `WITH income_rows AS (
 SELECT e.*,${base} AS base_kind,${refund} AS is_refund,
 CASE WHEN ${base} IN ('booking_collection','booking_refund') THEN 'bookings' WHEN ${base} IN ('admission_collection','admission_refund') THEN 'admissions' ELSE COALESCE(e.income_category_id,o.income_category_id)::text END AS source_id,
 CASE WHEN ${base} IN ('booking_collection','booking_refund') THEN 'Bookings' WHEN ${base} IN ('admission_collection','admission_refund') THEN 'Admissions' ELSE COALESCE(c.name,NULLIF(e.category,''),NULLIF(o.category,''),'Other') END AS source_name,
 (e.occurred_at AT TIME ZONE $${tzIndex})::date::text AS local_date,(e.occurred_at AT TIME ZONE $${tzIndex})::text AS local_time,
 (SELECT SUM(amount_minor) FROM finance_lines fl WHERE fl.event_id=e.id) AS amount_minor,
 b.id AS booking_id,ad.id AS admission_id,COALESCE(b.reference,ad.reference) AS booking_reference,
 COALESCE(b.customer_snapshot->>'name',ad.customer_snapshot->>'name') AS customer_name,COALESCE(b.total_minor,ad.total_minor) AS tariff_minor,
 bs.name AS business_name,r.name AS space_name,COALESCE(m.display_name,e.recorded_by) AS staff_name
 FROM finance_events e LEFT JOIN finance_events o ON o.id=e.reverses_id
 LEFT JOIN income_categories c ON c.id=COALESCE(e.income_category_id,o.income_category_id)
 LEFT JOIN booking_payments p ON p.id=COALESCE(e.booking_payment_id,o.booking_payment_id) LEFT JOIN bookings b ON b.id=p.booking_id
 LEFT JOIN admission_payments ap ON ap.id=COALESCE(e.admission_payment_id,o.admission_payment_id) LEFT JOIN admissions ad ON ad.id=ap.admission_id
 LEFT JOIN businesses bs ON bs.id=e.business_id LEFT JOIN resources r ON r.id=e.resource_id LEFT JOIN memberships m ON m.user_id=e.recorded_by AND m.organization_id=e.organization_id
 WHERE ${where})`;
  }
  async overview(actor: Actor, input: unknown) {
    const { f, c, values, where } = await this.context(actor, input),
      cte = this.cte(where, values.indexOf(c.timezone) + 1);
    // One statement (one consistent snapshot, one round trip) computes the
    // totals, the daily bars and the source breakdown from a single scan.
    const t = (
      await this.db.query<Row>(
        `${cte},
 days AS (SELECT local_date AS day,SUM(amount_minor) AS total_minor FROM income_rows WHERE NOT is_refund GROUP BY local_date),
 sources AS (SELECT source_id,source_name,SUM(amount_minor) AS total_minor FROM income_rows WHERE NOT is_refund GROUP BY source_id,source_name)
 SELECT COALESCE(SUM(amount_minor) FILTER (WHERE NOT is_refund),0) AS total_minor,COALESCE(-SUM(amount_minor) FILTER (WHERE is_refund),0) AS refunds_minor,COUNT(*)::int AS count,
 (SELECT COALESCE(jsonb_agg(d ORDER BY d.day),'[]') FROM days d) AS days,
 (SELECT COALESCE(jsonb_agg(x ORDER BY x.total_minor DESC),'[]') FROM sources x) AS sources
 FROM income_rows`,
        values,
      )
    ).rows[0];
    return {
      name: c.name,
      currency: c.currency,
      timezone: c.timezone,
      from: f.from,
      until: f.until,
      total_minor: Number(t.total_minor),
      refunds_minor: Number(t.refunds_minor),
      net_minor: Number(t.total_minor) - Number(t.refunds_minor),
      count: t.count,
      days: t.days,
      sources: t.sources,
    };
  }
  async list(actor: Actor, input: unknown, all = false) {
    const { f, c, values, where } = await this.context(actor, input),
      cte = this.cte(where, values.indexOf(c.timezone) + 1);
    values.push(all ? 0 : f.cursor);
    const rows = (
      await this.db.query<Row>(
        `${cte} SELECT x.*,
  (SELECT jsonb_agg(jsonb_build_object('account_id',l.account_id,'account_name',a.name,'method',l.method,'amount_minor',l.amount_minor) ORDER BY l.id) FROM finance_lines l JOIN money_accounts a ON a.id=l.account_id WHERE l.event_id=x.id) AS lines
  FROM income_rows x ORDER BY x.occurred_at DESC,x.id DESC LIMIT ${all ? 20001 : 51} OFFSET $${values.length}`,
        values,
      )
    ).rows;
    if (all && rows.length > 20000)
      throw new BadRequestException(
        "Report exceeds 20,000 entries. Choose a shorter period.",
      );
    return {
      items: rows.slice(0, all ? 20000 : 50),
      next_cursor: !all && rows.length > 50 ? f.cursor + 50 : null,
    };
  }
  async report(actor: Actor, input: unknown) {
    const overview = await this.overview(actor, input);
    const { items } = await this.list(actor, input, true);
    // Derive report aggregates from the exact exported rows, even if new entries arrive meanwhile.
    const sources = new Map<string, { name: string; total_minor: number }>();
    let total = 0,
      refunds = 0;
    for (const r of items) {
      const n = Number(r.amount_minor);
      if (r.is_refund) {
        refunds -= n;
        continue;
      }
      total += n;
      const key = r.source_id ?? r.source_name;
      const s = sources.get(key) ?? { name: r.source_name, total_minor: 0 };
      s.total_minor += n;
      sources.set(key, s);
    }
    const f = incomeFilter.parse(input);
    const org = (await this.workspace.member(actor)).organization_id;
    const find = async (table: string, id?: string) =>
      id
        ? ((
            await this.db.query<Row>(
              `SELECT name FROM ${table} WHERE id=$1 AND organization_id=$2`,
              [id, org],
            )
          ).rows[0]?.name ?? "Selected")
        : null;
    return {
      ...overview,
      total_minor: total,
      refunds_minor: refunds,
      net_minor: total - refunds,
      count: items.length,
      sources: [...sources.values()].sort(
        (a, b) => b.total_minor - a.total_minor,
      ),
      items,
      source_filter:
        f.source === "bookings"
          ? "Bookings"
          : f.source === "admissions"
            ? "Admissions"
            : await find("income_categories", f.source),
      business_filter: await find("businesses", f.business_id),
      space_filter: await find("resources", f.resource_id),
      account_filter: await find("money_accounts", f.account_id),
      search_filter: f.q ?? "",
    };
  }
}
