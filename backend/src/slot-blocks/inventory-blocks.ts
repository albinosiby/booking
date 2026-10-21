import { ConflictException } from "@nestjs/common";
import { Queryable } from "../common/database";
type Row = Record<string, any>;
export class SlotBlockedException extends ConflictException {
  constructor() {
    super("This space is blocked for this interval. Choose another slot.");
  }
}
export function inventoryIsBlocked(
  q: {
    inventory_keys: string[];
    occupied_from: string;
    occupied_until: string;
  },
  rows: Row[],
) {
  return rows.some(
    (r) =>
      r.blocked &&
      q.inventory_keys.includes(r.inventory_key) &&
      Date.parse(r.starts_at) < Date.parse(q.occupied_until) &&
      Date.parse(r.ends_at) > Date.parse(q.occupied_from),
  );
}
export async function activeBookingAllocations(
  db: Queryable,
  business: string,
  from: string,
  until: string,
  keys?: string[],
) {
  return (
    await db.query<Row>(
      `SELECT b.id AS booking_id,b.reference,b.resource_id,x.inventory_key,x.quantity,b.starts_at,b.ends_at,a.plan_id,a.plan_snapshot
    FROM bookings b JOIN booking_allocations x ON x.booking_id=b.id LEFT JOIN admission_balances a ON a.id=b.admission_id
    WHERE b.business_id=$1 AND b.status<>'cancelled' AND b.ends_at>$2 AND b.starts_at<$3
    AND (a.id IS NULL OR b.starts_at<=now() OR (NOT a.cancelled AND a.status IN ('active','upcoming') AND (b.starts_at AT TIME ZONE a.timezone)::date<=a.expires_on))${keys ? " AND x.inventory_key=ANY($4::text[])" : ""}`,
      keys ? [business, from, until, keys] : [business, from, until],
    )
  ).rows;
}
export async function slotBlockAllocations(
  db: Queryable,
  business: string,
  from: string,
  until: string,
  keys?: string[],
) {
  return (
    await db.query<Row>(
      `SELECT 'block:'||s.id::text AS booking_id,k.inventory_key,0 AS quantity,true AS blocked,s.starts_at,s.ends_at
    FROM booking_slot_blocks s CROSS JOIN LATERAL unnest(s.inventory_keys) k(inventory_key)
    WHERE s.business_id=$1 AND s.unblocked_at IS NULL AND s.ends_at>$2 AND s.starts_at<$3${keys ? " AND k.inventory_key=ANY($4::text[])" : ""}`,
      keys ? [business, from, until, keys] : [business, from, until],
    )
  ).rows;
}
export async function inventoryAllocations(
  db: Queryable,
  business: string,
  from: string,
  until: string,
  keys?: string[],
) {
  const [bookings, blocks] = await Promise.all([
    activeBookingAllocations(db, business, from, until, keys),
    slotBlockAllocations(db, business, from, until, keys),
  ]);
  return [...bookings, ...blocks];
}
