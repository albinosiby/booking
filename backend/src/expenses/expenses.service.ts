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
import {
  expensesFilter,
  ExpensesFilter,
  categoryInput,
  attachmentInput,
} from "./expenses.validation";
import {
  InvoiceStorage,
  SupabaseInvoiceStorage,
  InvoiceValidationError,
} from "./invoice-storage";
type Row = Record<string, any>;
const defaults = [
  ["maintenance", "Maintenance"],
  ["food", "Food"],
  ["cleaning", "Cleaning & supplies"],
  ["utilities", "Utilities"],
  ["staff", "Staff & wages"],
  ["equipment", "Equipment & purchases"],
  ["rent", "Rent & lease"],
  ["marketing", "Marketing"],
  ["transport", "Transport"],
  ["other", "Other"],
];
@Injectable()
export class ExpensesService {
  storage: InvoiceStorage = new SupabaseInvoiceStorage();
  constructor(
    private readonly db: Database,
    private readonly workspace: WorkspaceService,
    private readonly accounts: AccountsService,
  ) {}
  private async member(actor: Actor, write = false, db: Queryable = this.db) {
    const m = await this.workspace.member(actor, false, db);
    if (
      m.role !== "owner" &&
      !m.permissions.includes(write ? "record_expenses" : "view_finance")
    )
      throw new ForbiddenException("Expense access is required.");
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
  private async event(
    actor: Actor,
    id: string,
    write = false,
    db: Queryable = this.db,
  ) {
    const m = await this.member(actor, write, db),
      values: unknown[] = [m.organization_id];
    const where = this.scope(m, values);
    values.push(id);
    const e = (
      await db.query<Row>(
        `SELECT e.* FROM finance_events e WHERE ${where} AND e.id=$${values.length} AND e.kind='expense'`,
        values,
      )
    ).rows[0];
    if (!e) throw new NotFoundException("Expense not found.");
    if (write && m.role !== "owner" && e.recorded_by !== actor.uid)
      throw new ForbiddenException(
        "Only the owner or recording staff can attach an invoice.",
      );
    return { m, e };
  }
  async catalog(actor: Actor) {
    const m = await this.workspace.member(actor);
    if (
      m.role !== "owner" &&
      !m.permissions.some((p: string) =>
        ["view_finance", "record_expenses"].includes(p),
      )
    )
      throw new ForbiddenException("Expense access is required.");
    await this.db.query(
      "INSERT INTO expense_categories(organization_id,default_key,name) SELECT $1,v->>0,v->>1 FROM jsonb_array_elements($2::jsonb) v ON CONFLICT DO NOTHING",
      [m.organization_id, JSON.stringify(defaults)],
    );
    return {
      categories: (
        await this.db.query(
          "SELECT id,name,active FROM expense_categories WHERE organization_id=$1 ORDER BY name",
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
              "UPDATE expense_categories SET name=$1,active=$2 WHERE organization_id=$3 AND id=$4 RETURNING id",
              [v.name, v.active, m.organization_id, id],
            )
          ).rows.length
        )
          throw new NotFoundException("Category not found.");
      } else
        await this.db.query(
          "INSERT INTO expense_categories(id,organization_id,name) VALUES($1,$2,$3)",
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
    if (v.kind !== "expense" || !v.expense_category_id)
      throw new BadRequestException("Choose an expense category.");
    return this.accounts.createEntry(actor, v);
  }
  private async context(actor: Actor, input: unknown, db: Queryable = this.db) {
    const m = await this.member(actor, false, db),
      f = expensesFilter.parse(input);
    const c = (
      await db.query<Row>(
        "SELECT o.name,o.currency,l.timezone FROM organizations o JOIN locations l ON l.organization_id=o.id WHERE o.id=$1 ORDER BY l.id LIMIT 1",
        [m.organization_id],
      )
    ).rows[0];
    const values: unknown[] = [m.organization_id];
    let where = this.scope(m, values);
    where += ` AND (e.kind='expense' OR (e.kind='reversal' AND o.kind='expense'))`;
    values.push(c.timezone, f.from, f.until);
    where += ` AND e.occurred_at >= ($${values.length - 1}::date::timestamp AT TIME ZONE $${values.length - 2}) AND e.occurred_at < (($${values.length}::date+1)::timestamp AT TIME ZONE $${values.length - 2})`;
    for (const [key, column] of [
      ["category_id", "COALESCE(e.expense_category_id,o.expense_category_id)"],
      ["business_id", "e.business_id"],
      ["resource_id", "e.resource_id"],
    ] as const) {
      if (f[key]) {
        values.push(f[key]);
        where += ` AND ${column}=$${values.length}`;
      }
    }
    if (f.account_id) {
      values.push(f.account_id);
      where += ` AND EXISTS(SELECT 1 FROM finance_lines fl WHERE fl.event_id=e.id AND fl.account_id=$${values.length})`;
    }
    if (f.q) {
      values.push(`%${f.q.replace(/[\\%_]/g, "\\$&")}%`);
      where += ` AND (e.reason ILIKE $${values.length} OR e.reference ILIKE $${values.length})`;
    }
    return { m, f, c, values, where };
  }
  private cte(where: string, tzIndex: number) {
    return `WITH expense_rows AS (
 SELECT e.*,COALESCE(e.expense_category_id,o.expense_category_id) AS category_id,COALESCE(c.name,NULLIF(e.category,''),NULLIF(o.category,''),'Other') AS category_name,
 (e.occurred_at AT TIME ZONE $${tzIndex})::date::text AS local_date,
 (SELECT -SUM(amount_minor) FROM finance_lines fl WHERE fl.event_id=e.id) AS amount_minor,
 b.name AS business_name,r.name AS space_name,COALESCE(m.display_name,e.recorded_by) AS staff_name
 FROM finance_events e LEFT JOIN finance_events o ON o.id=e.reverses_id LEFT JOIN expense_categories c ON c.id=COALESCE(e.expense_category_id,o.expense_category_id)
 LEFT JOIN businesses b ON b.id=e.business_id LEFT JOIN resources r ON r.id=e.resource_id LEFT JOIN memberships m ON m.user_id=e.recorded_by AND m.organization_id=e.organization_id
 WHERE ${where})`;
  }
  async overview(actor: Actor, input: unknown) {
    return this.db.transaction(async (db) => {
      await db.query("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ");
      const { f, c, values, where } = await this.context(actor, input, db),
        cte = this.cte(where, values.indexOf(c.timezone) + 1);
      const [total, days, categories] = await Promise.all([
        db.query(
          ` ${cte} SELECT COALESCE(SUM(amount_minor),0) AS total_minor,COUNT(*)::int AS count FROM expense_rows`,
          values,
        ),
        db.query(
          ` ${cte} SELECT local_date AS day,SUM(amount_minor) AS total_minor FROM expense_rows GROUP BY local_date ORDER BY local_date`,
          values,
        ),
        db.query(
          ` ${cte} SELECT category_id,category_name,SUM(amount_minor) AS total_minor FROM expense_rows GROUP BY category_id,category_name ORDER BY SUM(amount_minor) DESC`,
          values,
        ),
      ]);
      return {
        name: c.name,
        currency: c.currency,
        timezone: c.timezone,
        from: f.from,
        until: f.until,
        ...total.rows[0],
        days: days.rows,
        categories: categories.rows,
      };
    });
  }
  async list(actor: Actor, input: unknown, all = false) {
    const { f, c, values, where } = await this.context(actor, input),
      cte = this.cte(where, values.indexOf(c.timezone) + 1);
    values.push(all ? 0 : f.cursor);
    const rows = (
      await this.db.query<Row>(
        `${cte} SELECT x.*,
  (SELECT COUNT(*)::int FROM expense_attachments a WHERE a.event_id=COALESCE(x.reverses_id,x.id) AND a.status='ready') AS attachments_count,
  (SELECT jsonb_agg(jsonb_build_object('account_id',l.account_id,'account_name',a.name,'method',l.method,'amount_minor',l.amount_minor) ORDER BY l.id) FROM finance_lines l JOIN money_accounts a ON a.id=l.account_id WHERE l.event_id=x.id) AS lines
  FROM expense_rows x ORDER BY x.occurred_at DESC,x.id DESC LIMIT ${all ? 20001 : 51} OFFSET $${values.length}`,
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
  async detail(actor: Actor, id: string) {
    const { e, m } = await this.event(actor, id);
    const c = (
      await this.db.query<Row>(
        "SELECT name FROM expense_categories WHERE id=$1",
        [e.expense_category_id],
      )
    ).rows[0];
    const lines = (
      await this.db.query(
        "SELECT l.*,a.name AS account_name FROM finance_lines l JOIN money_accounts a ON a.id=l.account_id WHERE l.event_id=$1",
        [id],
      )
    ).rows;
    const attachments = (
      await this.db.query(
        "SELECT id,name,content_type,size_bytes,status FROM expense_attachments WHERE event_id=$1 ORDER BY created_at",
        [id],
      )
    ).rows;
    const reversals = (
      await this.db.query(
        "SELECT id,reason,occurred_at,recorded_by FROM finance_events WHERE reverses_id=$1",
        [id],
      )
    ).rows;
    return {
      ...e,
      category_name: c?.name ?? e.category,
      can_attach:
        m.role === "owner" ||
        (m.permissions.includes("record_expenses") &&
          e.recorded_by === actor.uid),
      amount_minor: lines.reduce(
        (n: number, l: any) => n - Number(l.amount_minor),
        0,
      ),
      lines,
      attachments,
      reversals,
    };
  }
  async report(actor: Actor, input: unknown) {
    const overview = await this.overview(actor, input);
    const { items } = await this.list(actor, input, true);
    // Derive report aggregates from the exact exported rows, even if new entries arrive meanwhile.
    const categories = new Map<string, { name: string; total_minor: number }>();
    let total = 0;
    for (const r of items) {
      const n = Number(r.amount_minor);
      total += n;
      const key = r.category_id ?? r.category_name;
      const c = categories.get(key) ?? {
        name: r.category_name,
        total_minor: 0,
      };
      c.total_minor += n;
      categories.set(key, c);
    }
    const f = expensesFilter.parse(input);
    const find = async (table: string, id?: string) =>
      id
        ? ((
            await this.db.query<Row>(
              `SELECT name FROM ${table} WHERE id=$1 AND organization_id=$2`,
              [id, (await this.workspace.member(actor)).organization_id],
            )
          ).rows[0]?.name ?? "Selected")
        : null;
    return {
      ...overview,
      total_minor: total,
      count: items.length,
      categories: [...categories.values()],
      items,
      category_filter: await find("expense_categories", f.category_id),
      business_filter: await find("businesses", f.business_id),
      space_filter: await find("resources", f.resource_id),
      account_filter: await find("money_accounts", f.account_id),
      search_filter: f.q ?? "",
    };
  }
  async prepare(actor: Actor, eventId: string, input: unknown) {
    const v = attachmentInput.parse(input);
    const result = await this.db.transaction(async (db) => {
      const { m, e } = await this.event(actor, eventId, true, db);
      await db.query("SELECT id FROM finance_events WHERE id=$1 FOR UPDATE", [
        eventId,
      ]);
      const old = (
        await db.query<Row>("SELECT * FROM expense_attachments WHERE id=$1", [
          v.id,
        ])
      ).rows[0];
      if (old) {
        if (
          old.event_id !== e.id ||
          old.organization_id !== m.organization_id ||
          old.name !== v.name ||
          old.content_type !== v.content_type ||
          old.size_bytes !== v.size_bytes
        )
          throw new ConflictException(
            "Invoice identifier belongs to a different upload.",
          );
        return old;
      }
      if (
        (
          await db.query(
            "SELECT id FROM expense_attachments WHERE event_id=$1",
            [eventId],
          )
        ).rows.length >= 10
      )
        throw new BadRequestException(
          "An expense can have up to 10 invoice files.",
        );
      const path = `${m.organization_id}/${eventId}/${v.id}`;
      await db.query(
        "INSERT INTO expense_attachments(id,organization_id,event_id,name,content_type,size_bytes,object_path,uploaded_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8)",
        [
          v.id,
          m.organization_id,
          eventId,
          v.name,
          v.content_type,
          v.size_bytes,
          path,
          actor.uid,
        ],
      );
      return { ...v, object_path: path, status: "pending" };
    });
    if (result.status === "ready") return { id: v.id, ready: true };
    // A lost completion response or upload response can be retried safely.
    try {
      await this.storage.verify(
        result.object_path,
        v.content_type,
        v.size_bytes,
      );
      await this.complete(actor, eventId, v.id);
      return { id: v.id, ready: true };
    } catch {}
    return {
      id: v.id,
      ready: false,
      upload_url: await this.storage.upload(result.object_path),
    };
  }
  async complete(actor: Actor, eventId: string, id: string) {
    await this.event(actor, eventId, true);
    const a = (
      await this.db.query<Row>(
        "SELECT * FROM expense_attachments WHERE id=$1 AND event_id=$2",
        [id, eventId],
      )
    ).rows[0];
    if (!a) throw new NotFoundException("Invoice not found.");
    if (a.status !== "ready") {
      try {
        await this.storage.verify(a.object_path, a.content_type, a.size_bytes);
      } catch (error) {
        if (error instanceof InvoiceValidationError)
          await this.storage.remove([a.object_path]);
        throw error;
      }
      const saved = await this.db.query(
        "UPDATE expense_attachments SET status='ready' WHERE id=$1 RETURNING id",
        [id],
      );
      if (!saved.rows.length)
        throw new NotFoundException(
          "Invoice upload was removed. Add the file again.",
        );
    }
    return { id };
  }
  async attachment(actor: Actor, eventId: string, id: string) {
    await this.event(actor, eventId);
    const a = (
      await this.db.query<Row>(
        "SELECT * FROM expense_attachments WHERE id=$1 AND event_id=$2 AND status='ready'",
        [id, eventId],
      )
    ).rows[0];
    if (!a) throw new NotFoundException("Invoice not found.");
    return { url: await this.storage.download(a.object_path) };
  }
  async removePending(actor: Actor, eventId: string, id: string) {
    return this.db.transaction(async (db) => {
      await this.event(actor, eventId, true, db);
      const a = (
        await db.query<Row>(
          "SELECT * FROM expense_attachments WHERE id=$1 AND event_id=$2 AND status='pending' FOR UPDATE",
          [id, eventId],
        )
      ).rows[0];
      if (!a) throw new NotFoundException("Pending invoice not found.");
      await this.storage.remove([a.object_path]);
      await db.query(
        "DELETE FROM expense_attachments WHERE id=$1 AND status='pending'",
        [id],
      );
      return {};
    });
  }
}
