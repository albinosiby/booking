import { BadRequestException } from "@nestjs/common";
import { z } from "zod";
import type { Queryable } from "../common/database";

/** Every order must fit the order table's CHECK; plans and custom limits stay inside it. */
export const ORDER_MIN_PAISE = 10000,
  ORDER_MAX_PAISE = 5000000;

export type Billing = {
  rate_paise_per_minute: number | null;
  plans_paise: number[];
  custom_enabled: boolean;
  custom_above_paise: number;
  custom_max_paise: number;
  low_balance_paise: number;
};
export const BILLING_FIELDS = [
  "rate_paise_per_minute",
  "plans_paise",
  "custom_enabled",
  "custom_above_paise",
  "custom_max_paise",
  "low_balance_paise",
] as const;

const rupee = (p: number) => `₹${(p / 100).toLocaleString("en-IN")}`;
const wholeRupees = z
  .number()
  .int()
  .refine((p) => p % 100 === 0, "Use whole rupees.");
const plan = wholeRupees
  .min(ORDER_MIN_PAISE, `Each plan must be at least ${rupee(ORDER_MIN_PAISE)}.`)
  .max(ORDER_MAX_PAISE, `Each plan must be at most ${rupee(ORDER_MAX_PAISE)}.`);
const plans = z
  .array(plan)
  .min(1, "Add at least one recharge plan.")
  .max(6, "Add at most six recharge plans.")
  .refine((v) => new Set(v).size === v.length, "Plans must be different.");
const fields = {
  rate_paise_per_minute: z
    .number()
    .int()
    .min(0, "The rate cannot be negative.")
    .max(100000, "The rate must be at most ₹1,000 per minute."),
  plans_paise: plans,
  custom_enabled: z.boolean(),
  custom_above_paise: wholeRupees
    .min(0)
    .max(ORDER_MAX_PAISE - 10000, "The custom minimum is too high."),
  custom_max_paise: wholeRupees
    .min(ORDER_MIN_PAISE)
    .max(ORDER_MAX_PAISE, `Custom amounts can be at most ${rupee(ORDER_MAX_PAISE)}.`),
  low_balance_paise: z.number().int().min(0).max(ORDER_MAX_PAISE),
};
export const defaultsSchema = z
  .object({
    version: z.number().int().positive(),
    ...fields,
    rate_paise_per_minute: fields.rate_paise_per_minute.min(
      1,
      "Set a rate above ₹0.",
    ),
  })
  .strict();
/** Each field is optional; null clears the client's override. */
export const overridesSchema = z
  .object(
    Object.fromEntries(
      BILLING_FIELDS.map((k) => [k, fields[k].nullable().optional()]),
    ) as { [K in keyof typeof fields]: z.ZodOptional<z.ZodNullable<(typeof fields)[K]>> },
  )
  .strict();

export function checkBilling(b: Billing) {
  if (b.custom_max_paise <= b.custom_above_paise)
    throw new BadRequestException(
      "The custom maximum must be more than the custom minimum.",
    );
  return b;
}

const num = (v: unknown) => (v == null ? null : Number(v));
const list = (v: unknown) => (Array.isArray(v) ? v.map(Number) : null);

export async function billingDefaults(db: Queryable) {
  const r = (
    await db.query<any>("SELECT * FROM call_billing_settings WHERE id")
  ).rows[0];
  return {
    rate_paise_per_minute: num(r.rate_paise_per_minute),
    plans_paise: list(r.plans_paise) ?? [],
    custom_enabled: Boolean(r.custom_enabled),
    custom_above_paise: Number(r.custom_above_paise),
    custom_max_paise: Number(r.custom_max_paise),
    low_balance_paise: Number(r.low_balance_paise),
    version: Number(r.version),
    updated_by: String(r.updated_by ?? ""),
    updated_at: new Date(r.updated_at).toISOString(),
  };
}

export function walletOverrides(w: any): Partial<Billing> {
  if (!w) return {};
  const o: Partial<Billing> = {};
  if (w.rate_paise_per_minute != null)
    o.rate_paise_per_minute = Number(w.rate_paise_per_minute);
  if (w.plans_paise != null) o.plans_paise = list(w.plans_paise)!;
  if (w.custom_enabled != null) o.custom_enabled = Boolean(w.custom_enabled);
  if (w.custom_above_paise != null)
    o.custom_above_paise = Number(w.custom_above_paise);
  if (w.custom_max_paise != null)
    o.custom_max_paise = Number(w.custom_max_paise);
  if (w.low_balance_paise != null)
    o.low_balance_paise = Number(w.low_balance_paise);
  return o;
}

/** The client's prices: its overrides on top of the platform defaults. */
export async function effectiveBilling(
  db: Queryable,
  wallet: any,
): Promise<Billing> {
  const { version, updated_by, updated_at, ...d } = await billingDefaults(db);
  return { ...d, ...walletOverrides(wallet) };
}

/** Lowest custom amount in whole rupees: strictly above the admin's threshold. */
export function customMinPaise(b: Billing) {
  return Math.max(ORDER_MIN_PAISE, b.custom_above_paise + 100);
}

export function validRecharge(b: Billing, amount: number) {
  if (b.plans_paise.includes(amount)) return;
  if (!b.custom_enabled)
    throw new BadRequestException("Choose one of the recharge plans.");
  if (amount % 100 !== 0)
    throw new BadRequestException("Enter the amount in whole rupees.");
  if (amount < customMinPaise(b))
    throw new BadRequestException(
      b.custom_above_paise + 100 > ORDER_MIN_PAISE
        ? `Enter more than ${rupee(b.custom_above_paise)}, or choose a plan.`
        : `Enter at least ${rupee(ORDER_MIN_PAISE)}.`,
    );
  if (amount > b.custom_max_paise)
    throw new BadRequestException(
      `Recharge at most ${rupee(b.custom_max_paise)}.`,
    );
}
