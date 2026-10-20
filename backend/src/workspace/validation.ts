import { z } from "zod";
import { Country, State } from "country-state-city";
const name = z.string().trim().min(2).max(120);
export const businessTypes = [
  "turf",
  "badminton",
  "tennis",
  "basketball",
  "pool",
  "hall",
] as const;
export const permissionNames = [
  "view_bookings",
  "manage_bookings",
  "collect_payments",
  "manage_attendance",
  "record_expenses",
  "view_finance",
] as const;
const time = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/);
export const locationSchema = z
  .object({
    name,
    address_line_1: z.string().trim().min(2).max(200),
    address_line_2: z.string().trim().max(200).nullable(),
    city: name,
    state_code: z.string().max(10).nullable(),
    country_code: z.string().length(2),
    postal_code: z.string().trim().min(1).max(20),
    timezone: z.string().max(80),
  })
  .strict()
  .superRefine((v, c) => {
    if (!Country.getCountryByCode(v.country_code))
      c.addIssue({
        code: "custom",
        path: ["country_code"],
        message: "Select a valid country",
      });
    const states = State.getStatesOfCountry(v.country_code);
    if (states.length && !states.some((s) => s.isoCode === v.state_code))
      c.addIssue({
        code: "custom",
        path: ["state_code"],
        message: "Select a state belonging to the country",
      });
    if (v.country_code === "IN" && !/^[1-9]\d{5}$/.test(v.postal_code))
      c.addIssue({
        code: "custom",
        path: ["postal_code"],
        message: "Enter a valid six-digit Indian pincode",
      });
    try {
      new Intl.DateTimeFormat("en", { timeZone: v.timezone });
    } catch {
      c.addIssue({
        code: "custom",
        path: ["timezone"],
        message: "Select a valid IANA timezone",
      });
    }
  });
export const orgSchema = z
  .object({
    name,
    contact_phone: z.string().trim().min(6).max(30),
    currency: z.enum(["INR", "AED", "GBP", "USD", "EUR"]),
    location: locationSchema,
  })
  .strict();
export const businessSchema = z
  .object({ name, type: z.enum(businessTypes), location_id: z.uuid() })
  .strict();
export const resourceSchema = z
  .object({
    name: z.string().trim().min(1).max(100),
    capacity: z.number().int().min(1).max(10000).default(1),
  })
  .strict();
export const configSchema = z
  .object({
    version: z.number().int().positive(),
    opens_at: time,
    closes_at: time,
    days: z.array(z.number().int().min(1).max(7)).min(1).max(7),
    duration_minutes: z.number().int().min(30).max(1440),
    price_minor: z.number().int().min(0).max(100000000),
    buffer_minutes: z.number().int().min(0).max(240),
    plan_name: z.string().trim().max(120).nullable(),
    validity_days: z.number().int().min(1).max(3650).nullable(),
    entitlement: z.enum(["unlimited", "visits", "attendance_days"]).nullable(),
    visit_limit: z.number().int().positive().max(10000).nullable(),
  })
  .strict()
  .superRefine((v, c) => {
    if (new Set(v.days).size !== v.days.length)
      c.addIssue({
        code: "custom",
        path: ["days"],
        message: "Duplicate weekdays",
      });
    if (v.opens_at === v.closes_at)
      c.addIssue({
        code: "custom",
        path: ["closes_at"],
        message: "Opening and closing times must differ",
      });
  });
export const invitationSchema = z
  .object({
    email: z.email().transform((v) => v.toLowerCase()),
    display_name: name,
    role: z.enum(["staff", "manager"]),
    permissions: z.array(z.enum(permissionNames)).max(6),
    assignments: z
      .array(
        z
          .object({
            business_id: z.uuid(),
            resource_ids: z.array(z.uuid()).max(100),
          })
          .strict(),
      )
      .min(1)
      .max(100),
  })
  .strict();

export const logoSchema = z
  .object({
    content_type: z.enum(["image/png", "image/jpeg", "image/webp"]),
    base64: z.string().min(1).max(2800000),
  })
  .strict();
export const acceptanceSchema = z
  .object({ token: z.string().regex(/^[a-f0-9]{64}$/) })
  .strict();

export const businessOrderSchema = z
  .object({
    business_ids: z.array(z.uuid()).max(1000),
    revision: z.number().int().min(0),
  })
  .strict()
  .refine((v) => new Set(v.business_ids).size === v.business_ids.length, {
    message: "Business IDs must be unique.",
    path: ["business_ids"],
  });
