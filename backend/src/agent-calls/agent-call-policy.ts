import { ForbiddenException } from "@nestjs/common";
import { z } from "zod";
import type { Queryable } from "../common/database";
import type { Actor } from "../common/auth.guard";

export const callServices = [
  "booking",
  "rescheduling",
  "enquiry",
  "cancellation",
] as const;
export type CallService = (typeof callServices)[number];
export const serviceSelection = z
  .array(z.enum(callServices))
  .min(1, "Choose at least one service.")
  .max(4)
  .refine((v) => new Set(v).size === v.length, "Choose each service once.");

/** Also called inside booking write transactions, before the membership lock.
 * All control mutations lock the same integration first, so revocation cannot
 * race past a booking's authorization check. Ordinary app users are unaffected. */
export async function voiceAccess(
  db: Queryable,
  actor: Actor,
  services?: readonly CallService[],
) {
  if (!actor.uid.startsWith("sarvam:")) return [] as CallService[];
  const s = (
    await db.query<any>(
      `SELECT s.enabled,s.verified_at,r.status,r.approved_services
     FROM sarvam_integrations s JOIN agent_call_requests r USING(organization_id)
     WHERE s.organization_id=$1 FOR SHARE OF s,r`,
      [actor.uid.slice(7)],
    )
  ).rows[0];
  if (!s?.enabled || !s.verified_at || s.status !== "active")
    throw new ForbiddenException(
      "The call service is turned off or not ready. Please contact the venue.",
    );
  const approved = s.approved_services as CallService[];
  if (
    !approved.length ||
    (services && !services.some((x) => approved.includes(x)))
  )
    throw new ForbiddenException(
      "This service is not enabled for phone calls. Please contact the venue.",
    );
  return approved;
}
