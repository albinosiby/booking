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
import { Actor } from "../common/auth.guard";
import { WorkspaceService } from "../workspace/workspace.service";
import { systemAccounts } from "./ledger";
import { paymentSettings, upiId } from "../website/website.payments";
import { websiteImage, websiteImageSchema } from "../website/website.images";
import {
  accountSchema,
  entrySchema,
  filterSchema,
  FinanceFilter,
} from "./accounts.validation";
type Row = Record<string, any>;
@Injectable()
export class AccountsService {
  constructor(
    private readonly db: Database,
    private readonly workspace: WorkspaceService,
  ) {}
  private readDb?: Queryable;
  async websitePayments(actor: Actor) {
    const member = await this.workspace.member(actor, true);
    const row = (
      await this.db.query<Row>(
        "SELECT upi_id,version,qr_data,qr_content_type FROM website_payment_settings WHERE organization_id=$1",
        [member.organization_id],
      )
    ).rows[0];
    return {
      upi_id: row?.upi_id ?? "",
      version: row?.version ?? 0,
      has_qr: !!row?.qr_data,
      qr: row?.qr_data
        ? {
            base64: Buffer.from(row.qr_data).toString("base64"),
            content_type: row.qr_content_type,
          }
        : null,
    };
  }
  async saveWebsitePayments(actor: Actor, input: unknown) {
    const value = z
      .object({
        version: z.number().int().nonnegative(),
        upi_id: upiId,
        qr: z
          .object({
            base64: websiteImageSchema.shape.base64,
            content_type: websiteImageSchema.shape.content_type,
          })
          .strict()
          .nullable()
          .optional(),
      })
      .strict()
      .parse(input);
    const data = value.qr
      ? websiteImage({ ...value.qr, version: 1, kind: "logo" })
      : null;
    await this.db.transaction(async (db) => {
      const member = await this.workspace.member(actor, true, db);
      await this.lock(db, member.organization_id);
      const previous = await paymentSettings(db, member.organization_id);
      if (previous.version !== value.version)
        throw new ConflictException(
          "Payment details changed. Reload before saving.",
        );
      const hasQr = value.qr === undefined ? previous.has_qr : !!data;
      if (!value.upi_id || !hasQr) {
        const required = (
          await db.query(
            "SELECT 1 FROM booking_website_spaces WHERE organization_id=$1 AND payment_required LIMIT 1",
            [member.organization_id],
          )
        ).rows.length;
        if (required)
          throw new BadRequestException(
            "Turn off mandatory payment for your website spaces before removing payment details.",
          );
      }
      await db.query(
        `INSERT INTO website_payment_settings(organization_id,upi_id,qr_data,qr_content_type,version)
        VALUES($1,$2,$3,$4,1) ON CONFLICT(organization_id) DO UPDATE SET
        upi_id=EXCLUDED.upi_id,qr_data=CASE WHEN $5 THEN EXCLUDED.qr_data ELSE website_payment_settings.qr_data END,
        qr_content_type=CASE WHEN $5 THEN EXCLUDED.qr_content_type ELSE website_payment_settings.qr_content_type END,
        version=website_payment_settings.version+1,updated_at=now()`,
        [
          member.organization_id,
          value.upi_id,
          data,
          value.qr?.content_type ?? null,
          value.qr !== undefined,
        ],
      );
      await this.audit(
        db,
        member,
        actor,
        "website.payment_details_updated",
        member.organization_id,
      );
    });
    return this.websitePayments(actor);
  }
  private get store(): Queryable {
    return this.readDb ?? this.db;
  }
  private async snapshot<T>(
    work: (reader: AccountsService) => Promise<T>,
  ): Promise<T> {
    if (this.readDb) return work(this);
    return this.db.transaction(async (tx) => {
      await tx.query("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ");
      const reader = new AccountsService(this.db, this.workspace);
      reader.readDb = tx;
      return work(reader);
    });
  }
  private allowed(m: Row, p: string) {
    return m.role === "owner" || m.permissions.includes(p);
  }
  private async member(
    actor: Actor,
    permission = "view_finance",
    db: Queryable = this.store,
  ) {
    const m = await this.workspace.member(actor, false, db);
    if (!this.allowed(m, permission))
      throw new ForbiddenException("Finance access is required.");
    return m;
  }
  private async audit(
    db: Queryable,
    m: Row,
    actor: Actor,
    action: string,
    id: string,
  ) {
    await db.query(
      "INSERT INTO audit_events(id,organization_id,actor_id,action,entity_id) VALUES($1,$2,$3,$4,$5)",
      [randomUUID(), m.organization_id, actor.uid, action, id],
    );
  }
  private async lock(db: Queryable, org: string) {
    await db.query("SELECT id FROM organizations WHERE id=$1 FOR UPDATE", [
      org,
    ]);
  }
  private async scope(
    m: Row,
    business: string | null,
    resource: string | null,
    db: Queryable = this.store,
  ) {
    if (resource && !business)
      throw new BadRequestException("Choose a business for this space.");
    if (!business) {
      if (m.role !== "owner")
        throw new ForbiddenException("Shared entries require owner access.");
      return;
    }
    const b = (
      await db.query<Row>(
        "SELECT id FROM businesses WHERE id=$1 AND organization_id=$2",
        [business, m.organization_id],
      )
    ).rows[0];
    if (!b) throw new NotFoundException("Business not found.");
    if (
      resource &&
      !(
        await db.query(
          "SELECT id FROM resources WHERE id=$1 AND business_id=$2 AND organization_id=$3",
          [resource, business, m.organization_id],
        )
      ).rows.length
    )
      throw new NotFoundException("Space not found.");
    if (m.role !== "owner") {
      const a = (
        await db.query<Row>(
          "SELECT resource_ids FROM staff_assignments WHERE membership_id=$1 AND business_id=$2",
          [m.id, business],
        )
      ).rows[0];
      if (
        !a ||
        (a.resource_ids.length &&
          (!resource || !a.resource_ids.includes(resource)))
      )
        throw new ForbiddenException("Choose an assigned space.");
    }
  }
  private where(m: Row, f: FinanceFilter, values: unknown[], alias = "e") {
    let sql = `${alias}.organization_id=$1`;
    if (m.role !== "owner") {
      values.push(m.id);
      sql += ` AND EXISTS(SELECT 1 FROM staff_assignments a WHERE a.membership_id=$${values.length} AND a.business_id=${alias}.business_id AND (jsonb_array_length(a.resource_ids)=0 OR a.resource_ids ? ${alias}.resource_id::text))`;
    }
    for (const [key, column] of [
      ["business_id", "business_id"],
      ["resource_id", "resource_id"],
    ] as const) {
      if (f[key]) {
        values.push(f[key]);
        sql += ` AND ${alias}.${column}=$${values.length}`;
      }
    }
    return sql;
  }
  private async context(m: Row) {
    return (
      await this.store.query<Row>(
        `SELECT o.name,o.currency,COALESCE((SELECT timezone FROM locations WHERE organization_id=o.id ORDER BY id LIMIT 1),'UTC') AS timezone FROM organizations o WHERE o.id=$1`,
        [m.organization_id],
      )
    ).rows[0];
  }
  private async accounts(m: Row, balances: boolean) {
    const rows = (
      await this.store.query<Row>(
        `SELECT a.*,a.opening_minor+COALESCE((SELECT sum(l.amount_minor) FROM finance_lines l JOIN finance_events e ON e.id=l.event_id WHERE l.account_id=a.id AND e.occurred_at>=a.opening_at AND e.occurred_at<=now()),0) AS balance_minor FROM money_accounts a WHERE organization_id=$1 ORDER BY a.kind,a.is_primary DESC,a.name`,
        [m.organization_id],
      )
    ).rows;
    return rows.map((a) => ({
      ...a,
      account_number: m.role === "owner" ? a.account_number : null,
      opening_minor: balances ? Number(a.opening_minor) : null,
      balance_minor: balances ? Number(a.balance_minor) : null,
    }));
  }
  async catalog(actor: Actor) {
    const m = await this.workspace.member(actor);
    if (
      !["view_finance", "collect_payments", "record_expenses"].some((p) =>
        this.allowed(m, p),
      )
    )
      throw new ForbiddenException(
        "Finance or payment permission is required.",
      );
    await systemAccounts(this.db, m.organization_id);
    // Historical businesses are retained in finance filters and reports.
    const w = await this.workspace.workspace(actor, true),
      context = await this.context(m);
    return {
      ...context,
      today: new Intl.DateTimeFormat("en-CA", {
        timeZone: context.timezone,
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
      }).format(new Date()),
      can_view: this.allowed(m, "view_finance"),
      can_manage: m.role === "owner",
      can_expense: this.allowed(m, "record_expenses"),
      can_income: this.allowed(m, "collect_payments"),
      accounts: await this.accounts(m, m.role === "owner"),
      businesses: w.businesses.map((b: Row) => ({
        id: b.id,
        name: b.status === "archived" ? `${b.name} (removed)` : b.name,
        resources: b.resources,
      })),
      routes: (
        await this.store.query<Row>(
          "SELECT * FROM payment_routes WHERE organization_id=$1",
          [m.organization_id],
        )
      ).rows.filter((r: Row) =>
        w.businesses.some(
          (b: Row) =>
            b.id === r.business_id &&
            (!r.resource_id ||
              b.resources.some((s: Row) => s.id === r.resource_id)),
        ),
      ),
    };
  }
  async createAccount(actor: Actor, input: unknown) {
    const v = accountSchema.parse(input),
      hash = createHash("sha256").update(JSON.stringify(v)).digest("hex");
    if (
      Date.parse(v.opening_at) > Date.now() + 60000 ||
      Date.parse(v.opening_at) < Date.UTC(2000, 0, 1)
    )
      throw new BadRequestException(
        "Choose an opening date between 2000 and now.",
      );
    return this.db.transaction(async (db) => {
      const m = await this.workspace.member(actor, true, db);
      await this.lock(db, m.organization_id);
      // An audit key makes retries safe without treating a second bank as the same account.
      const old = (
        await db.query<Row>(
          "SELECT id,request_hash FROM money_accounts WHERE id=$1 AND organization_id=$2",
          [v.command_key, m.organization_id],
        )
      ).rows[0];
      if (old) {
        if (old.request_hash !== hash)
          throw new ConflictException(
            "This request key belongs to different account data.",
          );
        return { id: old.id };
      }
      const primary =
        v.is_primary ||
        !(
          await db.query(
            "SELECT id FROM money_accounts WHERE organization_id=$1 AND is_primary=true",
            [m.organization_id],
          )
        ).rows.length;
      if (primary)
        await db.query(
          "UPDATE money_accounts SET is_primary=false WHERE organization_id=$1",
          [m.organization_id],
        );
      await db.query(
        `INSERT INTO money_accounts(id,organization_id,name,kind,bank_name,last_four,opening_minor,opening_at,is_primary,request_hash,opening_set,account_number) VALUES($1,$2,$3,'bank',$4,$5,$6,$7,$8,$9,true,$10)`,
        [
          v.command_key,
          m.organization_id,
          v.name,
          v.bank_name,
          v.account_number.slice(-4),
          v.opening_minor,
          v.opening_at,
          primary,
          hash,
          v.account_number,
        ],
      );
      await this.audit(db, m, actor, "bank_account_created", v.command_key);
      return { id: v.command_key };
    });
  }
  async cashOpening(actor: Actor, input: unknown) {
    const v = z
      .object({
        command_key: z.uuid(),
        opening_minor: z.number().int().min(-100000000000).max(100000000000),
        opening_at: z.iso.datetime({ offset: true }),
      })
      .strict()
      .parse(input);
    if (
      Date.parse(v.opening_at) > Date.now() + 60000 ||
      Date.parse(v.opening_at) < Date.UTC(2000, 0, 1)
    )
      throw new BadRequestException("Choose a date between 2000 and now.");
    const hash = createHash("sha256").update(JSON.stringify(v)).digest("hex");
    return this.db.transaction(async (db) => {
      const m = await this.workspace.member(actor, true, db);
      await this.lock(db, m.organization_id);
      await systemAccounts(db, m.organization_id);
      const a = (
        await db.query<Row>(
          "SELECT * FROM money_accounts WHERE organization_id=$1 AND system_key='cash' FOR UPDATE",
          [m.organization_id],
        )
      ).rows[0];
      if (a.opening_set) {
        if (a.request_hash === hash) return { id: a.id };
        throw new ConflictException(
          "Cash opening balance is already set. Record a correction entry with a reason instead.",
        );
      }
      await db.query(
        "UPDATE money_accounts SET opening_minor=$1,opening_at=$2,opening_set=true,request_hash=$3 WHERE id=$4",
        [v.opening_minor, v.opening_at, hash, a.id],
      );
      await this.audit(db, m, actor, "cash_opening_balance", a.id);
      return { id: a.id };
    });
  }
  async updateAccount(actor: Actor, id: string, input: unknown) {
    const v = z
      .object({
        name: z.string().trim().min(2).max(100).optional(),
        is_primary: z.literal(true).optional(),
        archive: z.literal(true).optional(),
      })
      .strict()
      .parse(input);
    return this.db.transaction(async (db) => {
      const m = await this.workspace.member(actor, true, db);
      await this.lock(db, m.organization_id);
      const a = (
        await db.query<Row>(
          "SELECT * FROM money_accounts WHERE id=$1 AND organization_id=$2 FOR UPDATE",
          [id, m.organization_id],
        )
      ).rows[0];
      if (!a || a.kind !== "bank" || !a.active)
        throw new BadRequestException("Choose an active bank account.");
      if (v.archive) {
        if (
          a.is_primary ||
          (
            await db.query(
              "SELECT id FROM payment_routes WHERE account_id=$1",
              [id],
            )
          ).rows.length
        )
          throw new ConflictException(
            "Replace the primary account and payment mappings before archiving.",
          );
        await db.query("UPDATE money_accounts SET active=false WHERE id=$1", [
          id,
        ]);
      } else {
        if (v.is_primary) {
          await db.query(
            "UPDATE money_accounts SET is_primary=false WHERE organization_id=$1",
            [m.organization_id],
          );
          await db.query(
            "UPDATE money_accounts SET is_primary=true WHERE id=$1",
            [id],
          );
        }
        if (v.name)
          await db.query("UPDATE money_accounts SET name=$1 WHERE id=$2", [
            v.name,
            id,
          ]);
      }
      await this.audit(db, m, actor, "bank_account_updated", id);
      return { id };
    });
  }
  async route(actor: Actor, input: unknown) {
    const v = z
      .object({
        business_id: z.uuid(),
        resource_id: z.uuid().nullable(),
        method: z.enum(["upi", "card", "bank_transfer"]),
        account_id: z.uuid().nullable(),
      })
      .strict()
      .parse(input);
    return this.db.transaction(async (db) => {
      const m = await this.workspace.member(actor, true, db);
      await this.lock(db, m.organization_id);
      await this.scope(m, v.business_id, v.resource_id, db);
      if (
        v.account_id &&
        !(
          await db.query(
            `SELECT id FROM money_accounts WHERE id=$1 AND organization_id=$2 AND kind='bank' AND active=true`,
            [v.account_id, m.organization_id],
          )
        ).rows.length
      )
        throw new BadRequestException("Choose an active bank account.");
      await db.query(
        "DELETE FROM payment_routes WHERE organization_id=$1 AND business_id=$2 AND resource_id IS NOT DISTINCT FROM $3::uuid AND method=$4",
        [m.organization_id, v.business_id, v.resource_id, v.method],
      );
      if (v.account_id)
        await db.query(
          "INSERT INTO payment_routes(id,organization_id,business_id,resource_id,method,account_id) VALUES($1,$2,$3,$4,$5,$6)",
          [
            randomUUID(),
            m.organization_id,
            v.business_id,
            v.resource_id,
            v.method,
            v.account_id,
          ],
        );
      await this.audit(db, m, actor, "payment_route_updated", v.business_id);
      return { saved: true };
    });
  }
  async createEntry(actor: Actor, input: unknown) {
    const v = entrySchema.parse(input),
      hash = createHash("sha256").update(JSON.stringify(v)).digest("hex");
    if (
      Date.parse(v.occurred_at) > Date.now() + 60000 ||
      Date.parse(v.occurred_at) < Date.UTC(2000, 0, 1)
    )
      throw new BadRequestException("Choose a date between 2000 and now.");
    return this.db.transaction(async (db) => {
      const m = await this.member(
        actor,
        v.kind === "expense" ? "record_expenses" : "collect_payments",
        db,
      );
      await this.lock(db, m.organization_id);
      const old = (
        await db.query<Row>(
          "SELECT id,request_hash,recorded_by FROM finance_events WHERE organization_id=$1 AND command_key=$2",
          [m.organization_id, v.command_key],
        )
      ).rows[0];
      if (old) {
        if (old.request_hash !== hash || old.recorded_by !== actor.uid)
          throw new ConflictException(
            "This request key belongs to another entry.",
          );
        return { id: old.id };
      }
      if (v.kind === "transfer") {
        if (m.role !== "owner")
          throw new ForbiddenException("Only the owner can transfer money.");
        if (
          v.lines.length !== 1 ||
          !v.to_account_id ||
          v.to_account_id === v.lines[0].account_id ||
          v.business_id ||
          v.resource_id
        )
          throw new BadRequestException(
            "Choose two different accounts for an organization transfer.",
          );
      } else {
        await this.scope(m, v.business_id, v.resource_id, db);
        if (v.to_account_id)
          throw new BadRequestException(
            "A destination account is only used for transfers.",
          );
      }
      const ids = [
        ...v.lines.map((l) => l.account_id),
        ...(v.to_account_id ? [v.to_account_id] : []),
      ];
      const accounts = (
        await db.query<Row>(
          "SELECT * FROM money_accounts WHERE organization_id=$1 AND id=ANY($2::uuid[]) AND active=true FOR UPDATE",
          [m.organization_id, ids],
        )
      ).rows;
      for (const line of v.lines) {
        const a = accounts.find((a) => a.id === line.account_id);
        if (!a)
          throw new BadRequestException(
            "Choose active accounts from your organization.",
          );
        if (
          v.kind !== "transfer" &&
          (a.kind === "clearing" ||
            (line.method === "cash" ? a.kind !== "cash" : a.kind !== "bank") ||
            line.method === "transfer")
        )
          throw new BadRequestException(
            "Payment method must match the selected cash or bank account.",
          );
        if (Date.parse(v.occurred_at) < Date.parse(a.opening_at))
          throw new BadRequestException(
            "The entry predates this account opening balance.",
          );
      }
      if (v.to_account_id) {
        const a = accounts.find((a) => a.id === v.to_account_id);
        if (
          !a ||
          a.kind === "clearing" ||
          Date.parse(v.occurred_at) < Date.parse(a.opening_at)
        )
          throw new BadRequestException(
            "Choose an active destination account and valid date.",
          );
      }
      let expenseCategory = v.category;
      let expenseCategoryId = v.expense_category_id ?? null;
      // Older installed clients still send a category name. Preserve their entries
      // with a stable category ID so the new filtered reports include them.
      if (v.kind === "expense" && !expenseCategoryId) {
        await db.query(
          "INSERT INTO expense_categories(organization_id,name) VALUES($1,$2) ON CONFLICT DO NOTHING",
          [m.organization_id, v.category],
        );
        const category = (
          await db.query<Row>(
            "SELECT id,active FROM expense_categories WHERE organization_id=$1 AND lower(name)=lower($2)",
            [m.organization_id, v.category],
          )
        ).rows[0];
        if (!category?.active)
          throw new BadRequestException("Choose an active expense category.");
        expenseCategoryId = category.id;
      }
      if (v.expense_category_id) {
        if (v.kind !== "expense")
          throw new BadRequestException("Categories apply to expenses only.");
        const category = (
          await db.query<Row>(
            "SELECT name FROM expense_categories WHERE id=$1 AND organization_id=$2 AND active=true",
            [v.expense_category_id, m.organization_id],
          )
        ).rows[0];
        if (!category)
          throw new BadRequestException("Choose an active expense category.");
        expenseCategory = category.name;
      }
      let incomeCategoryId = v.income_category_id ?? null;
      if (v.income_category_id) {
        if (v.kind !== "income")
          throw new BadRequestException(
            "Income categories apply to income only.",
          );
        const category = (
          await db.query<Row>(
            "SELECT name FROM income_categories WHERE id=$1 AND organization_id=$2 AND active=true",
            [v.income_category_id, m.organization_id],
          )
        ).rows[0];
        if (!category)
          throw new BadRequestException("Choose an active income category.");
        expenseCategory = category.name;
      } else if (v.kind === "income") {
        // Older installed clients send a typed category name; keep it as a managed category.
        await db.query(
          "INSERT INTO income_categories(organization_id,name) VALUES($1,$2) ON CONFLICT DO NOTHING",
          [m.organization_id, v.category],
        );
        const category = (
          await db.query<Row>(
            "SELECT id,name,active FROM income_categories WHERE organization_id=$1 AND lower(name)=lower($2)",
            [m.organization_id, v.category],
          )
        ).rows[0];
        if (!category?.active)
          throw new BadRequestException("Choose an active income category.");
        incomeCategoryId = category.id;
        expenseCategory = category.name;
      }
      const id = randomUUID();
      await db.query(
        "INSERT INTO finance_events(id,organization_id,kind,business_id,resource_id,category,reason,reference,occurred_at,recorded_by,command_key,request_hash,expense_category_id,income_category_id) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)",
        [
          id,
          m.organization_id,
          v.kind,
          v.business_id,
          v.resource_id,
          expenseCategory,
          v.reason,
          v.reference,
          v.occurred_at,
          actor.uid,
          v.command_key,
          hash,
          expenseCategoryId,
          incomeCategoryId,
        ],
      );
      const lines = v.lines.map((l) => ({
        ...l,
        amount_minor: l.amount_minor * (v.kind === "income" ? 1 : -1),
        method: v.kind === "transfer" ? "transfer" : l.method,
      }));
      if (v.kind === "transfer")
        lines.push({
          account_id: v.to_account_id!,
          method: "transfer",
          amount_minor: v.lines[0].amount_minor,
        });
      for (const l of lines)
        await db.query(
          "INSERT INTO finance_lines(id,organization_id,event_id,account_id,method,amount_minor) VALUES($1,$2,$3,$4,$5,$6)",
          [
            randomUUID(),
            m.organization_id,
            id,
            l.account_id,
            l.method,
            l.amount_minor,
          ],
        );
      await this.audit(db, m, actor, `finance_${v.kind}`, id);
      return { id };
    });
  }
  async reverse(actor: Actor, id: string, input: unknown) {
    const v = z
      .object({
        command_key: z.uuid(),
        reason: z.string().trim().min(2).max(500),
      })
      .strict()
      .parse(input);
    return this.db.transaction(async (db) => {
      const m = await this.workspace.member(actor, true, db);
      await this.lock(db, m.organization_id);
      const e = (
        await db.query<Row>(
          "SELECT * FROM finance_events WHERE id=$1 AND organization_id=$2",
          [id, m.organization_id],
        )
      ).rows[0];
      if (
        !e ||
        e.admission_payment_id ||
        !["income", "expense", "transfer"].includes(e.kind)
      )
        throw new BadRequestException(
          "Only manual entries can be reversed here. Use the admission or booking refund flow for customer payments.",
        );
      const old = (
        await db.query<Row>(
          "SELECT id,command_key FROM finance_events WHERE reverses_id=$1",
          [id],
        )
      ).rows[0];
      if (old) {
        if (old.command_key === v.command_key) return { id: old.id };
        throw new ConflictException("This entry is already reversed.");
      }
      const rid = randomUUID();
      await db.query(
        `INSERT INTO finance_events(id,organization_id,kind,business_id,resource_id,category,reason,occurred_at,recorded_by,command_key,reverses_id) VALUES($1,$2,'reversal',$3,$4,$5,$6,now(),$7,$8,$9)`,
        [
          rid,
          m.organization_id,
          e.business_id,
          e.resource_id,
          e.category,
          v.reason,
          actor.uid,
          v.command_key,
          id,
        ],
      );
      await db.query(
        "INSERT INTO finance_lines(id,organization_id,event_id,account_id,method,amount_minor) SELECT gen_random_uuid(),organization_id,$1,account_id,method,-amount_minor FROM finance_lines WHERE event_id=$2",
        [rid, id],
      );
      await this.audit(db, m, actor, "finance_reversed", rid);
      return { id: rid };
    });
  }
  private async readContext(actor: Actor, input: unknown) {
    const m = await this.member(actor),
      f = filterSchema.parse(input),
      c = await this.context(m);
    return { m, f, c };
  }
  private periodWhere(m: Row, f: FinanceFilter, c: Row, values: unknown[]) {
    let where = this.where(m, f, values);
    values.push(c.timezone, f.from, f.until);
    // Same local-date range, expressed on occurred_at so the date index applies.
    where += ` AND e.occurred_at >= ($${values.length - 1}::date::timestamp AT TIME ZONE $${values.length - 2}) AND e.occurred_at < (($${values.length}::date+1)::timestamp AT TIME ZONE $${values.length - 2})`;
    if (f.kind) {
      values.push(f.kind);
      where += ` AND e.kind=$${values.length}`;
    }
    if (f.q) {
      values.push(`%${f.q.replace(/[\\%_]/g, "\\$&")}%`);
      where += ` AND (e.reason ILIKE $${values.length} OR e.reference ILIKE $${values.length} OR b.reference ILIKE $${values.length} OR b.customer_snapshot->>'name' ILIKE $${values.length})`;
    }
    if (f.account_id) {
      values.push(f.account_id);
      where += ` AND EXISTS(SELECT 1 FROM finance_lines x WHERE x.event_id=e.id AND x.account_id=$${values.length})`;
    }
    return where;
  }
  async transactions(actor: Actor, input: unknown, all = false) {
    const { m, f, c } = await this.readContext(actor, input),
      values: unknown[] = [m.organization_id],
      where = this.periodWhere(m, f, c, values);
    const timezoneIndex = values.indexOf(c.timezone) + 1;
    const limit = all ? 20001 : 101;
    values.push(all ? 0 : f.cursor);
    const rows = (
      await this.store.query<Row>(
        `SELECT e.*,COALESCE(o.kind,e.kind) AS effective_kind,b.id AS booking_id,ad.id AS admission_id,COALESCE(b.reference,ad.reference) AS booking_reference,COALESCE(b.customer_snapshot->>'name',ad.customer_snapshot->>'name') AS customer_name,COALESCE(b.total_minor,ad.total_minor) AS tariff_minor,bs.name AS business_name,r.name AS space_name,COALESCE(mm.display_name,e.recorded_by) AS staff_name,(e.occurred_at AT TIME ZONE $${timezoneIndex})::text AS local_time,
   (SELECT jsonb_agg(jsonb_build_object('account_id',l.account_id,'account_name',a.name,'method',l.method,'amount_minor',l.amount_minor) ORDER BY l.id) FROM finance_lines l JOIN money_accounts a ON a.id=l.account_id WHERE l.event_id=e.id) AS lines
   FROM finance_events e LEFT JOIN finance_events o ON o.id=e.reverses_id LEFT JOIN booking_payments p ON p.id=e.booking_payment_id LEFT JOIN bookings b ON b.id=p.booking_id LEFT JOIN admission_payments ap ON ap.id=e.admission_payment_id LEFT JOIN admissions ad ON ad.id=ap.admission_id LEFT JOIN businesses bs ON bs.id=e.business_id LEFT JOIN resources r ON r.id=e.resource_id LEFT JOIN memberships mm ON mm.user_id=e.recorded_by
   WHERE ${where} ORDER BY e.occurred_at DESC,e.id DESC LIMIT ${limit} OFFSET $${values.length}`,
        values,
      )
    ).rows;
    // local_time uses the explicit timezone value separately because scope parameters are variable.
    if (all && rows.length > 20000)
      throw new BadRequestException(
        "This report exceeds 20,000 entries. Choose a shorter date range.",
      );
    return {
      items: rows.slice(0, all ? 20000 : 100),
      next_cursor: !all && rows.length > 100 ? f.cursor + 100 : null,
    };
  }
  async overview(actor: Actor, input: unknown) {
    return this.snapshot((reader) => reader.overviewData(actor, input));
  }
  private async overviewData(actor: Actor, input: unknown) {
    const { m, f, c } = await this.readContext(actor, input);
    // Totals for one window (selected, previous or today) of the grouped rows.
    const summarize = (rows: Row[], key: string) => {
      const sum = (kind: string) =>
        rows
          .filter((r) => r.kind === kind)
          .reduce((n, r) => n + Number(r[key]), 0);
      const collection =
          sum("booking_collection") + sum("admission_collection"),
        extra = sum("income"),
        refund = -sum("booking_refund") - sum("admission_refund"),
        expense = -sum("expense");
      return {
        collections_minor: collection,
        extra_income_minor: extra,
        refunds_minor: refund,
        expenses_minor: expense,
        income_minor: collection + extra,
        net_minor: collection + extra - refund - expense,
        income_methods: Object.fromEntries(
          ["cash", "upi", "card", "bank_transfer"].map((method) => [
            method,
            rows
              .filter(
                (r) =>
                  r.method === method &&
                  [
                    "booking_collection",
                    "admission_collection",
                    "income",
                  ].includes(r.kind),
              )
              .reduce((n, r) => n + Number(r[key]), 0),
          ]),
        ),
        methods: Object.fromEntries(
          ["cash", "upi", "card", "bank_transfer"].map((method) => [
            method,
            rows
              .filter(
                (r) =>
                  r.method === method &&
                  ["booking_collection", "admission_collection"].includes(
                    r.kind,
                  ),
              )
              .reduce((n, r) => n + Number(r[key]), 0),
          ]),
        ),
      };
    };
    const day = new Intl.DateTimeFormat("en-CA", {
      timeZone: c.timezone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(new Date());
    const start = Date.parse(f.from),
      end = Date.parse(f.until),
      span = end - start + 86400000;
    let previousFrom = new Date(start - span).toISOString().slice(0, 10),
      previousUntil = new Date(start - 86400000).toISOString().slice(0, 10);
    const fromDate = new Date(start),
      untilDate = new Date(end);
    if (
      fromDate.getUTCDate() === 1 &&
      fromDate.getUTCMonth() === untilDate.getUTCMonth() &&
      fromDate.getUTCFullYear() === untilDate.getUTCFullYear()
    ) {
      previousFrom = new Date(
        Date.UTC(fromDate.getUTCFullYear(), fromDate.getUTCMonth() - 1, 1),
      )
        .toISOString()
        .slice(0, 10);
      const lastPrevious = new Date(
        Date.UTC(fromDate.getUTCFullYear(), fromDate.getUTCMonth(), 0),
      ).getUTCDate();
      const fullMonth =
        untilDate.getUTCDate() ===
        new Date(
          Date.UTC(fromDate.getUTCFullYear(), fromDate.getUTCMonth() + 1, 0),
        ).getUTCDate();
      previousUntil = new Date(
        Date.UTC(
          fromDate.getUTCFullYear(),
          fromDate.getUTCMonth() - 1,
          fullMonth
            ? lastPrevious
            : Math.min(untilDate.getUTCDate(), lastPrevious),
        ),
      )
        .toISOString()
        .slice(0, 10);
    } else if (
      fromDate.getUTCMonth() === 0 &&
      fromDate.getUTCDate() === 1 &&
      fromDate.getUTCFullYear() === untilDate.getUTCFullYear()
    ) {
      previousFrom = `${fromDate.getUTCFullYear() - 1}-01-01`;
      const previousYear = untilDate.getUTCFullYear() - 1,
        lastDay = new Date(
          Date.UTC(previousYear, untilDate.getUTCMonth() + 1, 0),
        ).getUTCDate();
      previousUntil = new Date(
        Date.UTC(
          previousYear,
          untilDate.getUTCMonth(),
          Math.min(untilDate.getUTCDate(), lastDay),
        ),
      )
        .toISOString()
        .slice(0, 10);
    }
    // One scan covering all three windows instead of three queries.
    const windows = [f.from, f.until, previousFrom, previousUntil, day, day];
    const aggregateValues: unknown[] = [m.organization_id],
      aggregateWhere = this.periodWhere(
        m,
        {
          ...f,
          from: [...windows].sort()[0],
          until: [...windows].sort().at(-1)!,
        },
        c,
        aggregateValues,
      );
    const local = `(e.occurred_at AT TIME ZONE $${aggregateValues.indexOf(c.timezone) + 1})::date`;
    const sumIn = (from: string, until: string) => {
      aggregateValues.push(from, until);
      return `COALESCE(sum(l.amount_minor) FILTER (WHERE ${local} BETWEEN $${aggregateValues.length - 1}::date AND $${aggregateValues.length}::date),0)`;
    };
    const columns = `${sumIn(f.from, f.until)} AS selected,${sumIn(previousFrom, previousUntil)} AS previous,${sumIn(day, day)} AS today`;
    const grouped = (
      await this.store.query<Row>(
        `SELECT COALESCE(o.kind,e.kind) AS kind,l.method,${columns} FROM finance_events e JOIN finance_lines l ON l.event_id=e.id LEFT JOIN finance_events o ON o.id=e.reverses_id LEFT JOIN booking_payments p ON p.id=e.booking_payment_id LEFT JOIN bookings b ON b.id=p.booking_id WHERE ${aggregateWhere} GROUP BY COALESCE(o.kind,e.kind),l.method`,
        aggregateValues,
      )
    ).rows;
    const selected = summarize(grouped, "selected"),
      previous = summarize(grouped, "previous"),
      today = summarize(grouped, "today");
    const values: unknown[] = [m.organization_id],
      base = this.where(m, f, values, "b");
    values.push(c.timezone, f.until);
    // Booking and admission dues in one round trip.
    const dues = (
      await this.store.query<Row>(
        `SELECT (SELECT COALESCE(sum(GREATEST(0,b.total_minor-COALESCE((SELECT sum(CASE WHEN p.kind='collection' THEN p.amount_minor ELSE -p.amount_minor END) FROM booking_payments p WHERE p.booking_id=b.id AND (p.received_at AT TIME ZONE $${values.length - 1})::date<=$${values.length}::date),0))),0) FROM bookings b WHERE ${base} AND b.status<>'cancelled' AND (b.created_at AT TIME ZONE $${values.length - 1})::date<=$${values.length}::date) AS bookings,(SELECT COALESCE(sum(GREATEST(0,b.total_minor-COALESCE((SELECT sum(CASE WHEN p.kind='collection' THEN p.amount_minor ELSE -p.amount_minor END) FROM admission_payments p WHERE p.admission_id=b.id AND (p.received_at AT TIME ZONE $${values.length - 1})::date<=$${values.length}::date),0))),0) FROM admissions b WHERE ${base} AND (b.created_at AT TIME ZONE $${values.length - 1})::date<=$${values.length}::date) AS admissions`,
        values,
      )
    ).rows[0];
    const trendValues: unknown[] = [m.organization_id],
      trendWhere = this.periodWhere(m, f, c, trendValues);
    const timezoneIndex = trendValues.indexOf(c.timezone) + 1;
    const trend = (
      await this.store.query<Row>(
        `SELECT to_char(e.occurred_at AT TIME ZONE $${timezoneIndex},'YYYY-MM') AS month,COALESCE(sum(CASE WHEN COALESCE(o.kind,e.kind) IN ('income','booking_collection','admission_collection') THEN l.amount_minor ELSE 0 END),0) AS income_minor,COALESCE(-sum(CASE WHEN COALESCE(o.kind,e.kind)='expense' THEN l.amount_minor ELSE 0 END),0) AS expenses_minor FROM finance_events e JOIN finance_lines l ON l.event_id=e.id LEFT JOIN finance_events o ON o.id=e.reverses_id LEFT JOIN booking_payments p ON p.id=e.booking_payment_id LEFT JOIN bookings b ON b.id=p.booking_id WHERE ${trendWhere} GROUP BY month ORDER BY month`,
        trendValues,
      )
    ).rows;
    // One grouped read supplies every month/space: month taps need no request.
    const analysisYear = f.until.slice(0, 4);
    const analysisValues: unknown[] = [m.organization_id];
    const analysisWhere = this.periodWhere(
      m,
      { ...f, from: `${analysisYear}-01-01`, until: `${analysisYear}-12-31` },
      c,
      analysisValues,
    );
    const analysisTimezone = analysisValues.indexOf(c.timezone) + 1;
    const analysisRows = (
      await this.store.query<Row>(
        `SELECT to_char(e.occurred_at AT TIME ZONE $${analysisTimezone},'YYYY-MM') AS month,
       e.business_id,e.resource_id,bs.name AS business_name,r.name AS space_name,
       COALESCE(sum(CASE WHEN COALESCE(o.kind,e.kind) IN ('income','booking_collection','admission_collection') THEN l.amount_minor ELSE 0 END),0) AS income_minor,
       COALESCE(-sum(CASE WHEN COALESCE(o.kind,e.kind)='expense' THEN l.amount_minor ELSE 0 END),0) AS expenses_minor,
       COALESCE(-sum(CASE WHEN COALESCE(o.kind,e.kind) IN ('booking_refund','admission_refund') THEN l.amount_minor ELSE 0 END),0) AS refunds_minor
       FROM finance_events e JOIN finance_lines l ON l.event_id=e.id
       LEFT JOIN finance_events o ON o.id=e.reverses_id
       LEFT JOIN booking_payments p ON p.id=e.booking_payment_id LEFT JOIN bookings b ON b.id=p.booking_id
       LEFT JOIN businesses bs ON bs.id=e.business_id AND bs.organization_id=e.organization_id
       LEFT JOIN resources r ON r.id=e.resource_id AND r.organization_id=e.organization_id
       WHERE ${analysisWhere} AND COALESCE(o.kind,e.kind) IN ('income','booking_collection','admission_collection','expense','booking_refund','admission_refund')
       GROUP BY month,e.business_id,e.resource_id,bs.name,r.name ORDER BY month,bs.name NULLS LAST,r.name NULLS LAST`,
        analysisValues,
      )
    ).rows;
    const monthlyAnalysis = Array.from({ length: 12 }, (_, index) => {
      const month = `${analysisYear}-${String(index + 1).padStart(2, "0")}`;
      const spaces = analysisRows
        .filter((r) => r.month === month)
        .map((r) => ({
          business_id: r.business_id,
          resource_id: r.resource_id,
          business_name: r.business_name,
          space_name: r.space_name,
          income_minor: Number(r.income_minor),
          expenses_minor: Number(r.expenses_minor),
          refunds_minor: Number(r.refunds_minor),
        }));
      return {
        month,
        income_minor: spaces.reduce((n, r) => n + r.income_minor, 0),
        expenses_minor: spaces.reduce((n, r) => n + r.expenses_minor, 0),
        refunds_minor: spaces.reduce((n, r) => n + r.refunds_minor, 0),
        spaces,
      };
    });
    return {
      ...c,
      from: f.from,
      until: f.until,
      previous_from: previousFrom,
      previous_until: previousUntil,
      selected,
      previous,
      today,
      outstanding_minor: Number(dues.bookings) + Number(dues.admissions),
      monthly_analysis: monthlyAnalysis,
      growth_percent:
        previous.income_minor > 0
          ? ((selected.income_minor - previous.income_minor) * 100) /
            previous.income_minor
          : null,
      accounts: m.role === "owner" ? await this.accounts(m, true) : [],
      trend: trend.map((r) => ({
        ...r,
        income_minor: Number(r.income_minor),
        expenses_minor: Number(r.expenses_minor),
      })),
    };
  }
  async report(actor: Actor, input: unknown) {
    return this.snapshot((reader) => reader.reportData(actor, input));
  }
  private async reportData(actor: Actor, input: unknown) {
    const reportFilter = filterSchema.parse(input);
    if (reportFilter.account_id || reportFilter.kind || reportFilter.q)
      throw new BadRequestException(
        "Reports support date, business and space filters. Clear transaction-only filters before exporting.",
      );
    const { m, f, c } = await this.readContext(actor, input),
      overview = await this.overview(actor, f),
      transactions = await this.transactions(actor, f, true);
    const values: unknown[] = [m.organization_id],
      where = this.where(m, f, values, "b");
    values.push(c.timezone, f.from, f.until);
    const tz = values.length - 2,
      from = values.length - 1,
      until = values.length;
    const bookings = (
      await this.store.query<Row>(
        `SELECT b.id,b.reference,b.customer_snapshot->>'name' AS customer,b.starts_at,b.ends_at,b.status,b.total_minor,b.price_snapshot,bs.name AS business,r.name AS space,
   COALESCE((SELECT sum(CASE WHEN p.kind='collection' THEN p.amount_minor ELSE -p.amount_minor END) FROM booking_payments p WHERE p.booking_id=b.id AND (p.received_at AT TIME ZONE $${tz})::date<=$${until}::date),0) AS received_to_date_minor,
   COALESCE((SELECT jsonb_agg(jsonb_build_object('kind',p.kind,'method',p.method,'amount_minor',p.amount_minor,'received_at',p.received_at)) FROM booking_payments p WHERE p.booking_id=b.id AND (p.received_at AT TIME ZONE $${tz})::date BETWEEN $${from}::date AND $${until}::date),'[]') AS payments
   FROM bookings b JOIN businesses bs ON bs.id=b.business_id JOIN resources r ON r.id=b.resource_id WHERE ${where} AND ((b.starts_at AT TIME ZONE $${tz})::date BETWEEN $${from}::date AND $${until}::date OR EXISTS(SELECT 1 FROM booking_payments p WHERE p.booking_id=b.id AND (p.received_at AT TIME ZONE $${tz})::date BETWEEN $${from}::date AND $${until}::date)) ORDER BY b.starts_at,b.id LIMIT 20001`,
        values,
      )
    ).rows;
    if (bookings.length > 20000)
      throw new BadRequestException(
        "Choose a shorter date range for this report.",
      );
    const accounts =
      m.role === "owner"
        ? (
            await this.store.query<Row>(
              `SELECT a.id,a.name,a.opening_at,CASE WHEN (a.opening_at AT TIME ZONE $2)::date<$3::date THEN a.opening_minor ELSE 0 END+COALESCE(sum(l.amount_minor) FILTER(WHERE e.occurred_at>=a.opening_at AND (e.occurred_at AT TIME ZONE $2)::date<$3::date),0) AS opening_minor,CASE WHEN (a.opening_at AT TIME ZONE $2)::date<=$4::date THEN a.opening_minor ELSE 0 END+COALESCE(sum(l.amount_minor) FILTER(WHERE e.occurred_at>=a.opening_at AND (e.occurred_at AT TIME ZONE $2)::date<=$4::date),0) AS closing_minor FROM money_accounts a LEFT JOIN finance_lines l ON l.account_id=a.id LEFT JOIN finance_events e ON e.id=l.event_id WHERE a.organization_id=$1 GROUP BY a.id`,
              [m.organization_id, c.timezone, f.from, f.until],
            )
          ).rows.map((a) => ({
            ...a,
            opening_minor: Number(a.opening_minor),
            closing_minor: Number(a.closing_minor),
          }))
        : [];
    return {
      ...overview,
      filters: f,
      scope_business: f.business_id
        ? (
            await this.store.query<Row>(
              "SELECT name FROM businesses WHERE id=$1 AND organization_id=$2",
              [f.business_id, m.organization_id],
            )
          ).rows[0]?.name
        : null,
      scope_space: f.resource_id
        ? (
            await this.store.query<Row>(
              "SELECT name FROM resources WHERE id=$1 AND organization_id=$2",
              [f.resource_id, m.organization_id],
            )
          ).rows[0]?.name
        : null,
      transactions: transactions.items,
      bookings: bookings.map((b) => ({
        ...b,
        received_to_date_minor: Number(b.received_to_date_minor),
      })),
      account_statement: accounts,
    };
  }
}
