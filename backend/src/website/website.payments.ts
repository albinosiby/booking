import { BadRequestException } from "@nestjs/common";
import { z } from "zod";
import type { Queryable } from "../common/database";

export const paymentPercentages = z
  .array(z.number().int().min(1).max(100))
  .max(3)
  .refine(
    (values) => new Set(values).size === values.length,
    "Choose distinct payment percentages.",
  );
export const upiId = z
  .string()
  .trim()
  .max(100)
  .refine(
    (value) => !value || /^[A-Za-z0-9._-]{2,}@[A-Za-z0-9.-]{2,}$/.test(value),
    "Enter a valid UPI ID, such as venue@bank.",
  );
export const paymentSubmissionSchema = z
  .object({
    percentage: z.number().int().min(1).max(100),
    transaction_id: z
      .string()
      .trim()
      .min(6)
      .max(64)
      .regex(/^[A-Za-z0-9._-]+$/)
      .transform((value) => value.toUpperCase()),
  })
  .strict();
export type PaymentSettings = {
  upi_id: string;
  version: number;
  has_qr: boolean;
};
export async function paymentSettings(
  db: Queryable,
  org: string,
  lock = false,
): Promise<PaymentSettings> {
  const row = (
    await db.query<PaymentSettings>(
      `SELECT upi_id,version,qr_data IS NOT NULL AS has_qr FROM website_payment_settings WHERE organization_id=$1${lock ? " FOR SHARE" : ""}`,
      [org],
    )
  ).rows[0];
  return row ?? { upi_id: "", version: 0, has_qr: false };
}
export function paymentPolicy(
  required: boolean,
  percentages: number[],
  total: number,
  currency: string,
  settings: PaymentSettings,
) {
  const available = currency === "INR" && !!settings.upi_id && settings.has_qr;
  if (required && total > 0 && (!available || !percentages.length))
    throw new BadRequestException(
      "Online payment details are unavailable. Please contact the venue before paying.",
    );
  return {
    required: required && total > 0,
    upi_id: available ? settings.upi_id : "",
    has_qr: available,
    version: settings.version,
    options:
      available && total > 0
        ? (required ? percentages : [100]).map((percentage) => ({
            percentage,
            amount_minor: Math.ceil((total * percentage) / 100),
          }))
        : [],
  };
}
