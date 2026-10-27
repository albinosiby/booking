import { z } from "zod";
export const calendarDate = z
  .string()
  .refine(
    (v) =>
      /^\d{4}-\d{2}-\d{2}$/.test(v) &&
      !Number.isNaN(Date.parse(v)) &&
      new Date(v).toISOString().startsWith(v) &&
      Number(v.slice(0, 4)) >= 2000 &&
      Number(v.slice(0, 4)) <= 2100,
    "Use a valid calendar date between 2000 and 2100",
  );
export const clock = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/);
export const selectionSchema = z
  .object({
    business_id: z.uuid(),
    resource_id: z.uuid(),
    option_id: z.string().max(100),
    date: calendarDate,
    time: clock,
    duration_minutes: z.number().int().min(1).max(1440),
    people: z.number().int().min(1).max(10000),
    discount: z
      .object({
        type: z.enum(["amount", "percent"]),
        value: z.number().int().min(0).max(100000000),
        reason: z.string().trim().max(200),
      })
      .strict()
      .refine(
        (d) => d.type !== "percent" || d.value <= 10000,
        "Discount percentage cannot exceed 100%.",
      )
      .optional(),
  })
  .strict();
export type BookingSelection = z.infer<typeof selectionSchema>;
export const paymentSchema = z
  .object({
    method: z.enum(["cash", "upi", "card", "bank_transfer"]),
    amount_minor: z.number().int().min(1).max(100000000),
    reference: z.string().trim().max(200),
    received_at: z.iso.datetime({ offset: true }),
    account_id: z.uuid().optional(),
  })
  .strict();
export const customerSchema = z
  .object({
    id: z.uuid().nullable(),
    name: z.string().trim().min(2).max(100),
    phone: z
      .string()
      .trim()
      .regex(/^\+?[\d ()-]{7,25}$/)
      .refine((v) => {
        const n = v.replace(/\D/g, "").length;
        return n >= 7 && n <= 15;
      }, "Use a phone number with 7–15 digits"),
    email: z.email().max(200).nullable(),
  })
  .strict();
export const createSchema = z
  .object({
    command_key: z.uuid(),
    selection: selectionSchema,
    quote_token: z.string().regex(/^[a-f0-9]{64}$/),
    customer: customerSchema,
    notes: z.string().trim().max(1000),
    payments: z.array(paymentSchema).max(20),
  })
  .strict();
export const rescheduleSchema = z
  .object({
    command_key: z.uuid(),
    version: z.number().int().positive(),
    selection: selectionSchema,
    quote_token: z.string().regex(/^[a-f0-9]{64}$/),
    reason: z.string().trim().min(2).max(500),
  })
  .strict();
export const paymentsSchema = z
  .object({
    command_key: z.uuid(),
    version: z.number().int().positive(),
    payments: z.array(paymentSchema).min(1).max(20),
    kind: z.enum(["collection", "refund"]),
    reason: z.string().trim().max(500),
  })
  .strict();
export const statusSchema = z
  .object({
    command_key: z.uuid(),
    version: z.number().int().positive(),
    status: z.enum(["cancelled", "completed", "no_show", "checked_in"]),
    reason: z.string().trim().min(2).max(500),
  })
  .strict();
export const customerEditSchema = z
  .object({
    command_key: z.uuid(),
    version: z.number().int().positive(),
    customer: customerSchema,
    notes: z.string().trim().max(1000),
  })
  .strict();
export function moneyStatus(total: number, net: number) {
  return {
    net_paid_minor: net,
    balance_minor: Math.max(0, total - net),
    refund_due_minor: Math.max(0, net - total),
    payment_status:
      net > total
        ? "refund_due"
        : net === total
          ? "paid"
          : net === 0
            ? "unpaid"
            : "partial",
  };
}
