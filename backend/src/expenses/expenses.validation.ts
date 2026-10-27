import { z } from "zod";
import { calendarDate } from "../bookings/booking.validation";
import { invoiceTypes } from "./invoice-storage";
export const expensesFilter = z
  .object({
    from: calendarDate,
    until: calendarDate,
    category_id: z.uuid().optional(),
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
export type ExpensesFilter = z.infer<typeof expensesFilter>;
export const categoryInput = z
  .object({
    name: z.string().trim().min(2).max(80),
    active: z.boolean().optional(),
  })
  .strict();
export const attachmentInput = z
  .object({
    id: z.uuid(),
    name: z.string().trim().min(1).max(180),
    content_type: z.enum(invoiceTypes),
    size_bytes: z
      .number()
      .int()
      .positive()
      .max(15 * 1024 * 1024),
  })
  .strict();
