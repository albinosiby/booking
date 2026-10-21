import { z } from "zod";
import { calendarDate } from "../bookings/booking.validation";
export const amount = z.number().int().positive().max(100000000);
export const filterSchema = z
  .object({
    from: calendarDate,
    until: calendarDate,
    business_id: z.uuid().optional(),
    resource_id: z.uuid().optional(),
    account_id: z.uuid().optional(),
    kind: z
      .enum([
        "booking_collection",
        "booking_refund",
        "admission_collection",
        "admission_refund",
        "income",
        "expense",
        "transfer",
        "reversal",
      ])
      .optional(),
    q: z.string().trim().max(100).optional(),
    cursor: z.coerce.number().int().min(0).max(1000000).default(0),
  })
  .strict()
  .refine(
    (v) =>
      v.from <= v.until &&
      Date.parse(v.until) - Date.parse(v.from) <= 3660 * 86400000,
    "Choose a date range up to ten years",
  );
export type FinanceFilter = z.infer<typeof filterSchema>;
export const accountSchema = z
  .object({
    command_key: z.uuid(),
    name: z.string().trim().min(2).max(100),
    bank_name: z.string().trim().max(100),
    account_number: z
      .string()
      .trim()
      .regex(
        /^[0-9]{6,34}$/,
        "Enter the full account number using 6–34 digits.",
      ),
    last_four: z
      .string()
      .regex(/^\d{0,4}$/)
      .optional(),
    opening_minor: z.number().int().min(-100000000000).max(100000000000),
    opening_at: z.iso.datetime({ offset: true }),
    is_primary: z.boolean(),
  })
  .strict();
export const entrySchema = z
  .object({
    command_key: z.uuid(),
    kind: z.enum(["income", "expense", "transfer"]),
    business_id: z.uuid().nullable(),
    resource_id: z.uuid().nullable(),
    category: z.string().trim().min(2).max(80),
    reason: z.string().trim().min(2).max(500),
    reference: z.string().trim().max(200),
    occurred_at: z.iso.datetime({ offset: true }),
    lines: z
      .array(
        z
          .object({
            account_id: z.uuid(),
            method: z.enum([
              "cash",
              "upi",
              "card",
              "bank_transfer",
              "transfer",
            ]),
            amount_minor: amount,
          })
          .strict(),
      )
      .min(1)
      .max(20),
    to_account_id: z.uuid().optional(),
    expense_category_id: z.uuid().optional(),
    income_category_id: z.uuid().optional(),
  })
  .strict();
