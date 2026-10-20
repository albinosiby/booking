import { z } from "zod";
import { createHash } from "node:crypto";
import { locationSchema } from "./validation";
export const organizationEditSchema = z
  .object({
    revision: z.string().regex(/^[a-f0-9]{64}$/),
    name: z.string().trim().min(2).max(120),
    contact_phone: z
      .string()
      .trim()
      .min(6)
      .max(30)
      .refine(
        (v) =>
          /^\+?[\d ()-]+$/.test(v) &&
          v.replace(/\D/g, "").length >= 6 &&
          v.replace(/\D/g, "").length <= 15,
        "Enter a valid phone number",
      ),
    locations: z
      .array(
        z
          .object({
            id: z.uuid(),
            name: z.string().trim().min(2).max(120),
            address_line_1: z.string().trim().min(2).max(200),
            address_line_2: z.string().trim().max(200).nullable(),
            city: z.string().trim().min(2).max(120),
            state_code: z.string().max(10).nullable(),
            country_code: z.string().length(2),
            postal_code: z.string().trim().min(1).max(20),
          })
          .strict(),
      )
      .min(1)
      .max(100),
  })
  .strict()
  .superRefine((v, c) => {
    if (new Set(v.locations.map((l) => l.id)).size !== v.locations.length)
      c.addIssue({
        code: "custom",
        path: ["locations"],
        message: "Duplicate location",
      });
  });
type Row = Record<string, any>;
export function organizationSnapshot(org: Row, locations: Row[]) {
  return {
    id: org.id,
    name: org.name,
    contact_phone: org.contact_phone,
    currency: org.currency,
    locations: [...locations]
      .sort((a, b) => a.id.localeCompare(b.id))
      .map((l) => ({
        id: l.id,
        name: l.name,
        address_line_1: l.address_line_1,
        address_line_2: l.address_line_2,
        city: l.city,
        state_code: l.state_code,
        country_code: l.country_code,
        postal_code: l.postal_code,
        timezone: l.timezone,
      })),
  };
}
export function organizationRevision(
  snapshot: ReturnType<typeof organizationSnapshot>,
) {
  return createHash("sha256").update(JSON.stringify(snapshot)).digest("hex");
}
export function validateOrganizationLocations(
  input: z.infer<typeof organizationEditSchema>,
  current: Row[],
) {
  for (let i = 0; i < input.locations.length; i++) {
    const { id, ...fields } = input.locations[i],
      existing = current.find((l) => l.id === id);
    if (!existing) continue; // Membership of the complete location set is checked before validation.
    const result = locationSchema.safeParse({
      ...fields,
      timezone: existing.timezone,
    });
    if (!result.success)
      throw new z.ZodError(
        result.error.issues.map((issue) => ({
          ...issue,
          path: ["locations", i, ...issue.path],
        })),
      );
  }
}
