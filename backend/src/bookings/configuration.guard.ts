import { ConflictException } from "@nestjs/common";
import { Queryable } from "../common/database";
type Row = Record<string, any>;
export async function protectBookingInventory(
  db: Queryable,
  b: Row,
  next: Row,
) {
  const prior = b.configuration;
  if (!prior) return;
  const resources = (c: Row) =>
    (c.layouts ?? c.courts ?? c.pools ?? c.halls ?? []).map((p: Row) => ({
      id: p.id,
      capacity: p.capacity ?? 1,
    }));
  const ids = resources(next).map((p: Row) => p.id),
    old = resources(prior),
    removed = old.filter((p: Row) => !ids.includes(p.id));
  if (
    removed.length &&
    (
      await db.query(
        "SELECT id FROM bookings WHERE business_id=$1 AND resource_id=ANY($2::uuid[]) LIMIT 1",
        [b.id, removed.map((p: Row) => p.id)],
      )
    ).rows.length
  )
    throw new ConflictException(
      "A space with booking history cannot be deleted. Disable it instead.",
    );
  if (
    !(
      await db.query(
        "SELECT id FROM bookings WHERE business_id=$1 AND status='confirmed' AND ends_at>now() LIMIT 1",
        [b.id],
      )
    ).rows.length
  )
    return;
  if (
    resources(next).some((p: Row) =>
      old.some((o: Row) => o.id === p.id && p.capacity < o.capacity),
    )
  )
    throw new ConflictException(
      "Capacity cannot be reduced while future bookings exist.",
    );
  if (prior.kind === "turf_v1") {
    for (const layout of prior.layouts) {
      const updated = next.layouts.find((l: Row) => l.id === layout.id);
      if (
        updated &&
        (updated.ground_id !== layout.ground_id ||
          JSON.stringify([...updated.section_ids].sort()) !==
            JSON.stringify([...layout.section_ids].sort()))
      )
        throw new ConflictException(
          "Shared-ground footprints cannot change while future bookings exist.",
        );
    }
  }
}
