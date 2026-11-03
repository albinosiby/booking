import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import type { Actor } from "../common/auth.guard";
import { Database, type Queryable } from "../common/database";
import { PaymentGateway } from "../call-wallet/payment-gateway";
import {
  BILLING_FIELDS,
  billingDefaults,
  checkBilling,
  customMinPaise,
  defaultsSchema,
  effectiveBilling,
  overridesSchema,
  walletOverrides,
} from "../call-wallet/call-billing";
import {
  applyEntry,
  ledgerItem,
  lockWallet,
} from "../call-wallet/call-wallet.service";
import { AdminService } from "./admin.service";

const uuid = z.string().uuid();
const adjustmentSchema = z
  .object({
    request_id: uuid,
    amount_paise: z
      .number()
      .int()
      .refine((v) => v !== 0, "Enter an amount.")
      .refine((v) => v % 100 === 0, "Use whole rupees.")
      .refine((v) => Math.abs(v) <= 5000000, "Enter at most ₹50,000."),
    payment_mode: z
      .enum(["cash", "upi", "bank_transfer", "cheque", "other"])
      .nullable()
      .default(null),
    external_reference: z.string().trim().max(100).default(""),
    note: z.string().trim().max(500).default(""),
  })
  .strict()
  .refine((v) => v.amount_paise < 0 || v.payment_mode, {
    message: "Choose how the client paid.",
  })
  .refine((v) => v.amount_paise > 0 || v.note.length >= 3, {
    message: "Add a note explaining the deduction.",
  });
const ledgerQuery = z
  .object({ offset: z.coerce.number().int().min(0).max(100000).default(0) })
  .strip();

function parse<T>(schema: z.ZodType<T>, value: unknown) {
  const parsed = schema.safeParse(value);
  if (!parsed.success)
    throw new BadRequestException(
      parsed.error.issues[0]?.message ?? "Invalid request.",
    );
  return parsed.data;
}
function orgId(value: string) {
  const parsed = uuid.safeParse(value);
  if (!parsed.success) throw new BadRequestException("Invalid identifier.");
  return parsed.data;
}

/** Platform pricing and manual wallet credits. Reads need any admin;
 * every change needs a super-admin and is written to the audit log. */
@Injectable()
export class AdminCallBillingService {
  gateway = new PaymentGateway();
  constructor(
    private readonly db: Database,
    private readonly admin: AdminService,
  ) {}
  private async audit(
    db: Queryable,
    email: string,
    action: string,
    type: string,
    target: string,
    detail: object,
  ) {
    await db.query(
      "INSERT INTO admin_audit_log(id,admin_email,action,target_type,target_id,detail) VALUES($1,$2,$3,$4,$5,$6)",
      [randomUUID(), email, action, type, target, JSON.stringify(detail)],
    );
  }
  private async organization(id: string) {
    const org = (
      await this.db.query<any>(
        "SELECT id,name,currency FROM organizations WHERE id=$1",
        [orgId(id)],
      )
    ).rows[0];
    if (!org) throw new NotFoundException("Organization not found.");
    return org;
  }

  async defaults(actor: Actor) {
    await this.admin.me(actor);
    return {
      ...(await billingDefaults(this.db)),
      gateway_configured: this.gateway.configured(),
    };
  }

  async saveDefaults(actor: Actor, body: unknown) {
    const admin = await this.admin.superAdmin(actor);
    const { version, ...input } = parse(defaultsSchema, body);
    checkBilling(input);
    await this.db.transaction(async (tx) => {
      const before = await billingDefaults(tx);
      const { rows } = await tx.query(
        `UPDATE call_billing_settings SET rate_paise_per_minute=$2,plans_paise=$3,custom_enabled=$4,
          custom_above_paise=$5,custom_max_paise=$6,low_balance_paise=$7,version=version+1,updated_by=$8,updated_at=now()
         WHERE id AND version=$1 RETURNING version`,
        [
          version,
          input.rate_paise_per_minute,
          input.plans_paise,
          input.custom_enabled,
          input.custom_above_paise,
          input.custom_max_paise,
          input.low_balance_paise,
          admin.email,
        ],
      );
      if (!rows.length)
        throw new ConflictException(
          "Someone else changed the call billing settings. Refresh and try again.",
        );
      const { version: _v, updated_by, updated_at, ...old } = before;
      await this.audit(tx, admin.email, "call_billing.defaults", "settings", "call_billing", {
        before: old,
        after: input,
      });
    });
    return this.defaults(actor);
  }

  async wallet(actor: Actor, id: string, query: unknown) {
    await this.admin.me(actor);
    const org = await this.organization(id);
    const { offset } = parse(ledgerQuery, query ?? {});
    const one = async (sql: string, params: unknown[] = [org.id]) =>
      (await this.db.query<any>(sql, params)).rows;
    const [[w], [totals], orders, ledger, defaults] = await Promise.all([
      one("SELECT * FROM call_wallets WHERE organization_id=$1"),
      one(
        `SELECT
          coalesce(sum(amount_paise) FILTER (WHERE kind='recharge'),0)::bigint AS recharged_paise,
          coalesce(sum(amount_paise) FILTER (WHERE kind='adjustment' AND amount_paise>0),0)::bigint AS added_paise,
          coalesce(-sum(amount_paise) FILTER (WHERE kind='adjustment' AND amount_paise<0),0)::bigint AS deducted_paise,
          coalesce(-sum(amount_paise) FILTER (WHERE kind='call_charge'),0)::bigint AS spent_paise,
          coalesce(sum(call_seconds) FILTER (WHERE kind='call_charge'),0)::bigint AS call_seconds,
          count(*) FILTER (WHERE kind='call_charge')::int AS calls
         FROM call_wallet_ledger WHERE organization_id=$1`,
      ),
      one(
        `SELECT order_id,amount_paise,status,payment_method,cf_payment_id,created_at,paid_at
         FROM call_wallet_orders WHERE organization_id=$1 ORDER BY created_at DESC LIMIT 50`,
      ),
      one(
        `SELECT l.*,o.payment_method FROM call_wallet_ledger l
         LEFT JOIN call_wallet_orders o ON l.kind='recharge' AND o.order_id=l.reference
         WHERE l.organization_id=$1 ORDER BY l.created_at DESC,l.id LIMIT 51 OFFSET $2`,
        [org.id, offset],
      ),
      billingDefaults(this.db),
    ]);
    const effective = await effectiveBilling(this.db, w);
    const rate = effective.rate_paise_per_minute,
      balance = Number(w?.balance_paise ?? 0);
    return {
      organization: org,
      balance_paise: balance,
      minutes_left: rate && balance > 0 ? Math.floor(balance / rate) : 0,
      low_alert_sent: Boolean(w?.low_alert_sent),
      totals: Object.fromEntries(
        Object.entries(totals).map(([k, v]) => [k, Number(v)]),
      ),
      effective: { ...effective, custom_min_paise: customMinPaise(effective) },
      overrides: walletOverrides(w),
      defaults,
      orders: orders.map((o) => ({
        ...o,
        amount_paise: Number(o.amount_paise),
        created_at: new Date(o.created_at).toISOString(),
        paid_at: o.paid_at ? new Date(o.paid_at).toISOString() : null,
      })),
      ledger: ledger.slice(0, 50).map((r) => ({
        ...ledgerItem(r),
        admin_email: r.admin_email ?? "",
      })),
      next_offset: ledger.length > 50 ? offset + 50 : null,
    };
  }

  async saveOverrides(actor: Actor, id: string, body: unknown) {
    const admin = await this.admin.superAdmin(actor);
    const org = await this.organization(id);
    const changes = parse(overridesSchema, body);
    await this.db.transaction(async (tx) => {
      const w = await lockWallet(tx, org.id);
      const before = walletOverrides(w);
      const after = { ...before };
      for (const k of BILLING_FIELDS)
        if (changes[k] === null) delete after[k];
        else if (changes[k] !== undefined) (after as any)[k] = changes[k];
      // The merged prices must be usable before they are saved.
      checkBilling({
        ...(await effectiveBilling(tx, null)),
        ...after,
      });
      const values = BILLING_FIELDS.map((k) => after[k] ?? null);
      await tx.query(
        `UPDATE call_wallets SET rate_paise_per_minute=$2,plans_paise=$3,custom_enabled=$4,custom_above_paise=$5,
          custom_max_paise=$6,low_balance_paise=$7,updated_at=now() WHERE organization_id=$1`,
        [org.id, ...values],
      );
      await this.audit(tx, admin.email, "call_billing.client", "organization", org.id, {
        before,
        after,
      });
    });
    return this.wallet(actor, org.id, {});
  }

  /** Records money the client paid outside Cashfree, or corrects a mistake.
   * The form's request ID makes a repeated submit a no-op. */
  async adjust(actor: Actor, id: string, body: unknown) {
    const admin = await this.admin.superAdmin(actor);
    const org = await this.organization(id);
    const v = parse(adjustmentSchema, body);
    const result = await this.db.transaction(async (tx) => {
      const w = await lockWallet(tx, org.id);
      if (v.amount_paise < 0 && Number(w.balance_paise) + v.amount_paise < 0)
        throw new BadRequestException(
          "A deduction cannot take the balance below ₹0.",
        );
      const entry = await applyEntry(tx, w, await effectiveBilling(tx, w), {
        kind: "adjustment",
        amount: v.amount_paise,
        reference: `admin_${v.request_id}`,
        note: v.note,
        adminEmail: admin.email,
        paymentMode: v.payment_mode,
        externalReference: v.external_reference || null,
      });
      if (entry)
        await this.audit(tx, admin.email, "call_wallet.adjust", "organization", org.id, {
          amount_paise: v.amount_paise,
          balance_after_paise: entry.balance_paise,
          payment_mode: v.payment_mode,
          external_reference: v.external_reference,
          note: v.note,
        });
      return entry;
    });
    return { duplicate: !result, wallet: await this.wallet(actor, org.id, {}) };
  }
}
