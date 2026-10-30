import { ConflictException } from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { Queryable } from "../common/database";

export const businessConfigurationTables = [
  "payment_routes",
  "booking_website_spaces",
  "booking_website_images",
  "booking_website_businesses",
  "staff_assignments",
  "resources",
] as const;

/** Caller holds the organization, website and business locks, in that order. */
export async function deleteUnusedBusiness(
  db: Queryable,
  business: { id: string; organization_id: string },
  actorId: string,
) {
  const args = [business.organization_id, business.id];
  const history = (
    await db.query<{ history: boolean }>(
      `
    SELECT EXISTS(SELECT 1 FROM bookings WHERE organization_id=$1 AND business_id=$2)
      OR EXISTS(SELECT 1 FROM admissions WHERE organization_id=$1 AND business_id=$2)
      OR EXISTS(SELECT 1 FROM finance_events WHERE organization_id=$1 AND business_id=$2)
      OR EXISTS(SELECT 1 FROM booking_notification_events WHERE organization_id=$1 AND business_id=$2)
      OR EXISTS(SELECT 1 FROM booking_slot_blocks WHERE organization_id=$1 AND business_id=$2) AS history`,
      args,
    )
  ).rows[0];
  if (history.history)
    throw new ConflictException(
      "This business has booking, admission, financial or operational history and cannot be permanently deleted. Turn it off instead.",
    );
  const pending = await db.query(
    `SELECT 1 FROM invitations i WHERE organization_id=$1
    AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at>now()
    AND EXISTS(SELECT 1 FROM jsonb_array_elements(i.assignments) a WHERE a->>'business_id'=$2::text) LIMIT 1`,
    args,
  );
  if (pending.rows.length)
    throw new ConflictException(
      "Cancel or update pending invitations for this business before permanently deleting it.",
    );
  const sites = (
    await db.query<{ website_id: string }>(
      `
    SELECT website_id FROM booking_website_businesses WHERE organization_id=$1 AND business_id=$2
    UNION SELECT website_id FROM booking_website_spaces WHERE organization_id=$1 AND business_id=$2
    UNION SELECT website_id FROM booking_website_images WHERE organization_id=$1 AND business_id=$2`,
      args,
    )
  ).rows.map((r) => r.website_id);
  for (const table of businessConfigurationTables) {
    await db.query(
      `DELETE FROM ${table} WHERE organization_id=$1 AND business_id=$2`,
      args,
    );
  }
  await db.query(
    "DELETE FROM businesses WHERE organization_id=$1 AND id=$2",
    args,
  );
  if (sites.length)
    await db.query(
      `UPDATE booking_websites SET version=version+1,updated_at=now(),
    preview_hash=NULL,preview_expires_at=NULL WHERE organization_id=$1 AND id=ANY($2::uuid[])`,
      [business.organization_id, sites],
    );
  await db.query(
    "UPDATE organizations SET business_order_revision=business_order_revision+1 WHERE id=$1",
    [business.organization_id],
  );
  await db.query(
    "INSERT INTO audit_events(id,organization_id,actor_id,action,entity_id) VALUES($1,$2,$3,'business.deleted',$4)",
    [randomUUID(), business.organization_id, actorId, business.id],
  );
  return { id: business.id };
}
