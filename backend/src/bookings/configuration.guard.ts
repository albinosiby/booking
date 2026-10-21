import { interval, validSwimmingDuration } from "../admissions/admission.rules";
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
  const hasActiveBlocks =
    (
      await db.query(
        "SELECT id FROM booking_slot_blocks WHERE business_id=$1 AND unblocked_at IS NULL AND ends_at>now() LIMIT 1",
        [b.id],
      )
    ).rows.length > 0;
  if (
    hasActiveBlocks &&
    (removed.length ||
      (prior.kind === "turf_v1" &&
        prior.layouts.some((layout: Row) => {
          const updated = next.layouts.find((l: Row) => l.id === layout.id);
          return (
            updated &&
            (updated.ground_id !== layout.ground_id ||
              JSON.stringify([...updated.section_ids].sort()) !==
                JSON.stringify([...layout.section_ids].sort()))
          );
        })))
  ) {
    throw new ConflictException(
      "Unblock future slots before deleting spaces or changing shared-ground footprints.",
    );
  }
  if (prior.kind === "pool_v1" || prior.kind === "court_v1") {
    const spaces: Row[] = next.pools ?? next.courts;
    if (
      removed.length &&
      (
        await db.query(
          "SELECT id FROM admissions WHERE business_id=$1 AND resource_id=ANY($2::uuid[]) LIMIT 1",
          [b.id, removed.map((p: Row) => p.id)],
        )
      ).rows.length
    )
      throw new ConflictException(
        "A space with admission history cannot be deleted. Disable it after active admissions end.",
      );
    const active = (
      await db.query<Row>(
        "SELECT * FROM admission_balances WHERE business_id=$1 AND status IN ('active','upcoming')",
        [b.id],
      )
    ).rows;
    for (const a of active) {
      const pool = spaces.find((p: Row) => p.id === a.resource_id);
      if (
        !pool?.enabled ||
        (a.plan_snapshot.kind !== "coaching" &&
          !validSwimmingDuration(pool, a.schedule.duration_minutes))
      )
        throw new ConflictException(
          "Keep spaces and purchased visit durations available until active admissions end.",
        );
    }
    const visits = (
      await db.query<Row>(
        "SELECT v.*,a.plan_snapshot,a.timezone FROM bookings v JOIN admissions a ON a.id=v.admission_id WHERE v.business_id=$1 AND v.status<>'cancelled' AND v.ends_at>now() AND NOT a.cancelled",
        [b.id],
      )
    ).rows;
    for (const v of visits) {
      const pool = spaces.find((p: Row) => p.id === v.resource_id);
      if (!pool?.enabled)
        throw new ConflictException(
          "Keep spaces available while admission reservations exist.",
        );
      try {
        interval(
          pool,
          v.plan_snapshot,
          v.selection.date,
          v.selection.time,
          v.selection.duration_minutes,
          v.timezone,
        );
      } catch {
        throw new ConflictException(
          "New opening hours or durations conflict with reserved admission sessions. Reschedule those sessions first.",
        );
      }
    }
  }
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
