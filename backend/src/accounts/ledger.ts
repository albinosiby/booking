import { randomUUID } from "node:crypto";
import { BadRequestException } from "@nestjs/common";
import { Queryable } from "../common/database";
type Row = Record<string, any>;
export async function systemAccounts(db: Queryable, org: string) {
  for (const [key, name, kind] of [
    ["cash", "Cash in hand", "cash"],
    ["unassigned", "Unassigned bank receipts", "clearing"],
  ]) {
    await db.query(
      "INSERT INTO money_accounts(id,organization_id,name,kind,system_key) VALUES($1,$2,$3,$4,$5) ON CONFLICT(organization_id,system_key) DO NOTHING",
      [randomUUID(), org, name, kind, key],
    );
  }
}
export async function destination(
  db: Queryable,
  org: string,
  business: string,
  resource: string,
  method: string,
  explicit?: string,
) {
  await systemAccounts(db, org);
  if (explicit) {
    const a = (
      await db.query<Row>(
        "SELECT * FROM money_accounts WHERE id=$1 AND organization_id=$2 AND active=true FOR SHARE",
        [explicit, org],
      )
    ).rows[0];
    if (!a || (method === "cash" ? a.kind !== "cash" : a.kind !== "bank"))
      throw new BadRequestException(
        "Choose an active account matching the payment method.",
      );
    return a.id;
  }
  if (method !== "cash") {
    const route = (
      await db.query<Row>(
        `SELECT a.id FROM payment_routes r JOIN money_accounts a ON a.id=r.account_id WHERE r.organization_id=$1 AND r.business_id=$2 AND (r.resource_id=$3 OR r.resource_id IS NULL) AND r.method=$4 AND a.active=true ORDER BY r.resource_id NULLS LAST LIMIT 1 FOR SHARE OF a`,
        [org, business, resource, method],
      )
    ).rows[0];
    if (route) return route.id;
    const primary = (
      await db.query<Row>(
        "SELECT id FROM money_accounts WHERE organization_id=$1 AND is_primary=true AND active=true FOR SHARE",
        [org],
      )
    ).rows[0];
    if (primary) return primary.id;
  }
  return (
    await db.query<Row>(
      "SELECT id FROM money_accounts WHERE organization_id=$1 AND system_key=$2",
      [org, method === "cash" ? "cash" : "unassigned"],
    )
  ).rows[0].id;
}
export async function postBookingPayment(
  db: Queryable,
  org: string,
  paymentId: string,
  actor: string,
  p: Row,
  kind: string,
  reason: string,
) {
  const b = (
    await db.query<Row>(
      "SELECT * FROM bookings WHERE id=$1 AND organization_id=$2",
      [p.booking_id, org],
    )
  ).rows[0];
  const account = await destination(
    db,
    org,
    b.business_id,
    b.resource_id,
    p.method,
    p.account_id,
  );
  const id = randomUUID();
  await db.query(
    "INSERT INTO finance_events(id,organization_id,kind,business_id,resource_id,booking_payment_id,reason,reference,occurred_at,recorded_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)",
    [
      id,
      org,
      kind === "collection" ? "booking_collection" : "booking_refund",
      b.business_id,
      b.resource_id,
      paymentId,
      reason || `Booking ${b.reference}`,
      p.reference,
      p.received_at,
      actor,
    ],
  );
  await db.query(
    "INSERT INTO finance_lines(id,organization_id,event_id,account_id,method,amount_minor) VALUES($1,$2,$3,$4,$5,$6)",
    [
      randomUUID(),
      org,
      id,
      account,
      p.method,
      (kind === "collection" ? 1 : -1) * p.amount_minor,
    ],
  );
}
