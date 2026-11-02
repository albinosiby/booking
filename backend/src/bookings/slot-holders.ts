import { Queryable } from "../common/database";
import { localStamp } from "./booking.inventory";
type Row = Record<string, any>;

const days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const months = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
];
/** "2026-11-12T17:00..." local stamp → "Thu, 12 Nov 2026 at 5:00 PM". */
export function slotLabel(local: string) {
  const [y, mo, d] = local.slice(0, 10).split("-").map(Number);
  const day = new Date(Date.UTC(y, mo - 1, d)).getUTCDay() || 7;
  const hour = Number(local.slice(11, 13)),
    minute = local.slice(14, 16);
  const clock = `${hour % 12 || 12}:${minute} ${hour < 12 ? "AM" : "PM"}`;
  return `${days[day - 1]}, ${d} ${months[mo - 1]} ${y} at ${clock}`;
}

/**
 * Who occupies the given inventory rows: an ordinary booking, an admission
 * session or a slot block. `source` matches the row's `booking_id`. Customer names appear only when `names` is set;
 * otherwise holders are described by kind and reference alone.
 */
export async function slotHolders(
  db: Queryable,
  organizationId: string,
  rows: Row[],
  names: boolean,
  zone: string,
) {
  const ids = [...new Set(rows.map((r) => String(r.booking_id)))];
  const bookingIds = ids.filter((id) => !id.startsWith("block:"));
  const blockIds = ids
    .filter((id) => id.startsWith("block:"))
    .map((id) => id.slice(6));
  const [bookings, blocks] = await Promise.all([
    bookingIds.length
      ? db.query<Row>(
          `SELECT b.id,b.reference,b.admission_id,b.starts_at,b.ends_at,c.name AS customer_name,
            a.reference AS admission_reference,a.plan_snapshot AS plan_snapshot,a.schedule AS schedule,a.expires_on::text AS expires_on
          FROM bookings b JOIN customers c ON c.id=b.customer_id AND c.organization_id=b.organization_id
          LEFT JOIN admissions a ON a.id=b.admission_id AND a.organization_id=b.organization_id
          WHERE b.organization_id=$1 AND b.id=ANY($2::uuid[])`,
          [organizationId, bookingIds],
        )
      : { rows: [] as Row[] },
    blockIds.length
      ? db.query<Row>(
          "SELECT id,starts_at,ends_at,all_day FROM booking_slot_blocks WHERE organization_id=$1 AND id=ANY($2::uuid[])",
          [organizationId, blockIds],
        )
      : { rows: [] as Row[] },
  ]);
  const iso = (v: unknown) => new Date(v as string).toISOString();
  const local = (v: unknown) => localStamp(Date.parse(iso(v)), zone);
  return [
    ...bookings.rows.map((r) =>
      r.admission_id
        ? {
            source: r.id,
            kind: "admission",
            booking_id: r.id,
            admission_id: r.admission_id,
            reference: r.admission_reference,
            name: r.customer_name,
            plan_name: r.plan_snapshot?.name ?? null,
            weekdays: r.schedule?.weekdays ?? [],
            expires_on: r.expires_on,
            starts_at: iso(r.starts_at),
            ends_at: iso(r.ends_at),
            local_start: local(r.starts_at),
            local_end: local(r.ends_at),
          }
        : {
            source: r.id,
            kind: "booking",
            booking_id: r.id,
            admission_id: null,
            reference: r.reference,
            name: names ? r.customer_name : null,
            plan_name: null,
            weekdays: [],
            expires_on: null,
            starts_at: iso(r.starts_at),
            ends_at: iso(r.ends_at),
            local_start: local(r.starts_at),
            local_end: local(r.ends_at),
          },
    ),
    ...blocks.rows.map((r) => ({
      source: "block:" + r.id,
      kind: "block",
      booking_id: null,
      admission_id: null,
      reference: null,
      name: null,
      plan_name: null,
      weekdays: [],
      expires_on: null,
      starts_at: iso(r.starts_at),
      ends_at: iso(r.ends_at),
      local_start: local(r.starts_at),
      local_end: local(r.ends_at),
    })),
  ].sort((x, y) => Date.parse(x.starts_at) - Date.parse(y.starts_at));
}

/** Short text for a holder inside an error message. */
export function holderText(h: Row) {
  if (h.kind === "block") return "a slot block";
  if (h.kind === "admission")
    return `${h.name} (${h.plan_name ?? "plan"} ${h.reference})`;
  return h.name
    ? `${h.name} (booking ${h.reference})`
    : `booking ${h.reference}`;
}
