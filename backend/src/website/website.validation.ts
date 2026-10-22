import { z } from "zod";
import { randomUUID } from "node:crypto";
import { Queryable } from "../common/database";
import {
  customerSchema,
  selectionSchema,
} from "../bookings/booking.validation";

const reserved = new Set([
  "api",
  "admin",
  "public",
  "profile",
  "login",
  "sign-in",
  "register",
  "preview",
  "demo",
  "health",
  "_next",
  "favicon",
  "robots",
  "sitemap",
  "www",
  "app",
  "mail",
  "email",
  "smtp",
  "status",
  "support",
  "help",
  "docs",
  "blog",
  "static",
  "assets",
  "cdn",
  "dashboard",
  "book",
  "booking",
  "bookingos",
]);
export const websiteSlug = z
  .string()
  .trim()
  .min(3)
  .max(80)
  .regex(
    /^[a-z0-9]+(?:-[a-z0-9]+)*$/,
    "Use lowercase letters, numbers and single hyphens",
  )
  .refine((v) => !reserved.has(v), "This address is reserved");
/** A new or changed address must also be a valid DNS label for `<slug>.<domain>`. */
export const websiteSubdomain = websiteSlug.refine(
  (v) => v.length <= 63,
  "Use up to 63 characters",
);
export const socialNetworks = [
  "instagram",
  "facebook",
  "x",
  "youtube",
  "linkedin",
  "whatsapp",
] as const;
const socialUrl = z
  .string()
  .trim()
  .max(300)
  .refine((v) => {
    if (!v) return true;
    try {
      const u = new URL(v);
      return u.protocol === "https:" && !u.username && !u.password;
    } catch {
      return false;
    }
  }, "Use a full https:// link");
export const websiteSpaceSchema = z
  .object({
    business_id: z.uuid(),
    resource_id: z.string().min(1).max(100),
    visible: z.boolean(),
    notice_minutes: z.number().int().min(0).max(10080).nullable(),
    advance_days: z.number().int().min(1).max(365).nullable(),
    rules: z.string().trim().max(1000),
  })
  .strict();
export const websiteSettingsSchema = z
  .object({
    version: z.number().int().positive(),
    slug: websiteSlug,
    title: z.string().trim().min(2).max(120),
    description: z.string().trim().max(1200),
    contact_phone: customerSchema.shape.phone,
    instructions: z.string().trim().max(2000),
    cancellation_policy: z.string().trim().max(2000),
    publish_logo: z.boolean(),
    notice_minutes: z.number().int().min(0).max(10080),
    advance_days: z.number().int().min(1).max(365),
    // Optional so older app versions can still save; omitted values are kept.
    hero_heading: z.string().trim().max(120).optional(),
    social_links: z.partialRecord(z.enum(socialNetworks), socialUrl).optional(),
    card_descriptions: z
      .record(z.uuid(), z.string().trim().max(300))
      .optional(),
    spaces: z
      .array(websiteSpaceSchema)
      .max(500)
      .refine(
        (v) =>
          new Set(v.map((s) => `${s.business_id}/${s.resource_id}`)).size ===
          v.length,
        "Duplicate spaces",
      )
      .optional(),
    business_ids: z
      .array(z.uuid())
      .max(100)
      .refine((v) => new Set(v).size === v.length, "Duplicate businesses"),
  })
  .strict();
export const publicSelection = selectionSchema
  .omit({ discount: true })
  .strict();
export const publicAvailabilitySchema = z
  .object({ selection: publicSelection, end_times: z.boolean().optional() })
  .strict();
export const publicQuoteSchema = z
  .object({ selection: publicSelection })
  .strict();
export const publicCreateSchema = z
  .object({
    command_key: z.uuid(),
    selection: publicSelection,
    quote_token: z.string().regex(/^[a-f0-9]{64}$/),
    customer: customerSchema.pick({ name: true, phone: true }).strict(),
  })
  .strict();

/** Drafts are private. Safe for onboarding and for existing organisations. */
export async function ensureWebsiteDraft(
  db: Queryable,
  org: { id: string; name: string; contact_phone: string },
) {
  const base =
    org.name
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "")
      .slice(0, 30) || "organisation";
  for (const suffix of [org.id.slice(0, 8), org.id.replace(/-/g, "")]) {
    await db.query(
      `INSERT INTO booking_websites(id,organization_id,slug,title,contact_phone)
      VALUES($1,$2,$3,$4,$5) ON CONFLICT DO NOTHING`,
      [randomUUID(), org.id, `${base}-${suffix}`, org.name, org.contact_phone],
    );
    const row = (
      await db.query<Record<string, any>>(
        "SELECT * FROM booking_websites WHERE organization_id=$1",
        [org.id],
      )
    ).rows[0];
    if (row) return row;
  }
  throw new Error("Could not allocate a booking website address");
}
