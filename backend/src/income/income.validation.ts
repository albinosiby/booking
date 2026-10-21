import { z } from "zod";
import { calendarDate } from "../bookings/booking.validation";
export const incomeSources = ["bookings", "admissions"] as const;
export const incomeFilter = z
  .object({
    from: calendarDate,
    until: calendarDate,
    // "bookings", "admissions" or an income category ID.
    source: z.union([z.enum(incomeSources), z.uuid()]).optional(),
    business_id: z.uuid().optional(),
    resource_id: z.uuid().optional(),
    account_id: z.uuid().optional(),
    q: z.string().trim().max(100).optional(),
    cursor: z.coerce.number().int().min(0).max(1000000).default(0),
  })
  .strict()
  .refine(
    (v) =>
      v.from <= v.until &&
      Date.parse(v.until) - Date.parse(v.from) <= 366 * 86400000,
    "Choose a period of up to one year.",
  );
export type IncomeFilter = z.infer<typeof incomeFilter>;
