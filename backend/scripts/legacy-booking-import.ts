import { createHash } from "node:crypto";
import type { Queryable } from "../src/common/database";
import { localStamp, zonedTime } from "../src/bookings/booking.inventory";

type Row = Record<string, any>;
export type LegacyExport = {
  source_project: string;
  source_business_id: string;
  exported_at: string;
  data: Record<string, Row[]>;
};
export type ImportDestination = {
  organization_id: string;
  data: Record<string, Row[]>;
};
export type SpaceMapping = Record<
  string,
  {
    business_id: string;
    resource_id: string;
    option_id: string;
    cricket_option_id?: string;
    inventory: Record<string, string>;
  }
>;
export type BookingImportPlan = {
  source_project: string;
  source_business_id: string;
  organization_id: string;
  source_hash: string;
  command_key: string;
  request_hash: string;
  configuration_hash: string;
  business_ids: string[];
  rows: Record<string, Row[]>;
  source_booking_ids: string[];
  renamed_references: {
    source_id: string;
    original: string;
    imported: string;
  }[];
  customer_map: Record<string, string>;
  bank_map: Record<string, string>;
  expected: {
    bookings: number;
    payments: number;
    gross_minor: number;
    discount_minor: number;
    total_minor: number;
    collected_minor: number;
    active_balance_minor: number;
    by_method: Record<string, number>;
  };
};

function requireValue(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}
function canonical(value: any): any {
  if (value instanceof Date) return value.toISOString();
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === "object")
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [key, canonical(value[key])]),
    );
  return value;
}
export const hash = (value: unknown) =>
  createHash("sha256")
    .update(JSON.stringify(canonical(value)))
    .digest("hex");

/** Stable IDs make the source export reproducible without adding a migration table. */
export function legacyId(
  org: string,
  project: string,
  table: string,
  id: unknown,
) {
  const bytes = createHash("sha256")
    .update(
      JSON.stringify(["legacy-bookings-v1", org, project, table, String(id)]),
    )
    .digest()
    .subarray(0, 16);
  bytes[6] = (bytes[6]! & 0x0f) | 0x80;
  bytes[8] = (bytes[8]! & 0x3f) | 0x80;
  const s = bytes.toString("hex");
  return `${s.slice(0, 8)}-${s.slice(8, 12)}-${s.slice(12, 16)}-${s.slice(16, 20)}-${s.slice(20)}`;
}

const digits = (s: string) => (s ?? "").replace(/\D/g, "");
const normalized = (s: string) => (s ?? "").trim().toLowerCase();
const ordered = (rows: Row[]) =>
  [...rows].sort((a, b) => String(a.id).localeCompare(String(b.id)));
const configurationHash = (rows: Row[]) =>
  hash(
    ordered(rows).map((b) => ({
      id: b.id,
      organization_id: b.organization_id,
      location_id: b.location_id,
      name: b.name,
      type: b.type,
      status: b.status,
      configuration: b.configuration,
      version: b.version,
      display_order: b.display_order,
    })),
  );
const amount = (value: unknown) => {
  requireValue(
    Number.isSafeInteger(value) && Number(value) >= 0,
    "Invalid source rupee amount",
  );
  const minor = Number(value) * 100;
  requireValue(
    Number.isSafeInteger(minor) && minor <= 100000000,
    "Source amount exceeds the supported range",
  );
  return minor;
};

/** Source slot timestamps are local wall time; source default-now audit timestamps are UTC. */
export function sourceTime(value: string, zone?: string) {
  requireValue(typeof value === "string", "Missing source timestamp");
  if (/(?:Z|[+-]\d\d:\d\d)$/.test(value)) {
    requireValue(
      Number.isFinite(Date.parse(value)),
      "Invalid source timestamp",
    );
    return value;
  }
  const m = /^(\d{4}-\d\d-\d\d)T(\d\d:\d\d):(\d\d)(?:\.(\d{1,6}))?$/.exec(
    value,
  );
  requireValue(m && Number(m[3]) < 60, "Invalid naive source timestamp");
  if (!zone) {
    requireValue(
      Number.isFinite(Date.parse(value + "Z")),
      "Invalid UTC source timestamp",
    );
    return value + "Z";
  }
  const time = zonedTime(m[1]!, m[2]!, zone) + Number(m[3]) * 1000;
  const result = new Date(time).toISOString().slice(0, 19);
  return result + (m[4] ? "." + m[4] : "") + "Z";
}

function uniqueRows(rows: Row[], label: string) {
  requireValue(
    new Set(rows.map((r) => String(r.id))).size === rows.length,
    `Duplicate source ${label} IDs`,
  );
}

export function buildBookingImport(
  source: LegacyExport,
  destination: ImportDestination,
  mappings: SpaceMapping,
  importedAt: string,
): BookingImportPlan {
  const org = destination.organization_id;
  const d = destination.data;
  const s = source.data;
  requireValue(
    d.organizations?.length === 1 && d.organizations[0].id === org,
    "Destination organization mismatch",
  );
  requireValue(
    d.organizations[0].currency === "INR",
    "This importer only converts INR rupees to paise",
  );
  requireValue(
    s.businesses?.length === 1 &&
      s.businesses[0].id === source.source_business_id,
    "Source business mismatch",
  );
  const bookings = ordered(s.bookings ?? []);
  const sourceBookingIds = new Set(bookings.map((b) => b.id));
  const payments = ordered(s.booking_payments ?? []);
  uniqueRows(bookings, "booking");
  uniqueRows(payments, "payment");
  uniqueRows(s.customers ?? [], "customer");
  requireValue(bookings.length > 0, "No source bookings");
  requireValue(
    bookings.every((b) => b.business_id === source.source_business_id),
    "Foreign business in source bookings",
  );
  requireValue(
    payments.every((p) => sourceBookingIds.has(p.booking_id)),
    "Unscoped source payment",
  );
  const id = (table: string, key: unknown) =>
    legacyId(org, source.source_project, table, key);
  const sourceHash = hash({
    project: source.source_project,
    business: source.source_business_id,
    bookings,
    payments,
    customers: ordered(s.customers),
    lines: ordered(s.booking_lines),
    options: ordered(s.asset_booking_options),
    assets: ordered(s.assets),
    banks: ordered(s.bank_accounts),
  });
  const commandKey = id("import", source.source_business_id);
  const requestHash = hash({
    version: 1,
    source_hash: sourceHash,
    organization_id: org,
    mappings,
  });
  const rows: Record<string, Row[]> = Object.fromEntries(
    [
      "customers",
      "money_accounts",
      "bookings",
      "booking_allocations",
      "booking_payments",
      "finance_events",
      "finance_lines",
      "booking_history",
      "audit_events",
    ].map((t) => [t, []]),
  );
  const customerMap: Record<string, string> = {};
  for (const customerId of [
    ...new Set(bookings.map((b) => b.customer_id)),
  ].sort()) {
    const c = s.customers.find((c) => c.id === customerId);
    requireValue(
      c && c.business_id === source.source_business_id,
      "Missing or unscoped booking customer",
    );
    const deterministic = id("customers", customerId);
    const existingId = d.customers.find((r) => r.id === deterministic);
    const matches = existingId
      ? [existingId]
      : d.customers.filter(
          (r) =>
            digits(c.phone) &&
            digits(c.phone) === digits(r.phone) &&
            normalized(c.name) === normalized(r.name) &&
            normalized(c.email) === normalized(r.email),
        );
    requireValue(
      matches.length <= 1,
      "Ambiguous existing customer; explicit mapping is needed",
    );
    customerMap[customerId] = matches[0]?.id ?? deterministic;
    if (!matches.length)
      rows.customers!.push({
        id: deterministic,
        organization_id: org,
        name: c.name,
        phone: c.phone,
        email: c.email ?? null,
      });
  }
  const cash = d.money_accounts.filter(
    (a) =>
      a.organization_id === org && a.system_key === "cash" && a.kind === "cash",
  );
  const clearing = d.money_accounts.filter(
    (a) =>
      a.organization_id === org &&
      a.system_key === "unassigned" &&
      a.kind === "clearing",
  );
  requireValue(
    cash.length === 1 && clearing.length === 1,
    "Destination system accounts are missing or ambiguous",
  );
  const bankMap: Record<string, string> = {};
  const neededBanks = [
    ...new Set(
      payments
        .filter(
          (p) => !["cash", "discount"].includes(p.method) && p.bank_account_id,
        )
        .map((p) => p.bank_account_id),
    ),
  ].sort();
  for (const bankId of neededBanks) {
    const bank = s.bank_accounts.find((a) => a.id === bankId);
    requireValue(
      bank && bank.business_id === source.source_business_id,
      "Missing or unscoped source bank account",
    );
    const number = bank.account_number;
    requireValue(
      typeof number === "string" &&
        /^\d{6,34}$/.test(number) &&
        number.endsWith(bank.last4),
      "Invalid source bank account details",
    );
    const deterministic = id("bank_accounts", bankId);
    const exact = d.money_accounts.filter(
      (a) =>
        a.id === deterministic ||
        (a.kind === "bank" &&
          a.account_number === number &&
          normalized(a.bank_name) === normalized(bank.bank_name)),
    );
    requireValue(exact.length <= 1, "Ambiguous destination bank account");
    bankMap[bankId] = exact[0]?.id ?? deterministic;
    if (!exact.length)
      rows.money_accounts!.push({
        id: deterministic,
        organization_id: org,
        name: (bank.label || bank.bank_name || "Imported bank").slice(0, 100),
        kind: "bank",
        bank_name: bank.bank_name,
        last_four: bank.last4,
        account_number: number,
        request_hash: hash({ project: source.source_project, bank }),
        is_primary: false,
        active: true,
      });
  }
  const references = new Set(d.bookings.map((b) => b.reference));
  const renamed: BookingImportPlan["renamed_references"] = [];
  const businessIds = new Set<string>();
  const expected = {
    bookings: bookings.length,
    payments: 0,
    gross_minor: 0,
    discount_minor: 0,
    total_minor: 0,
    collected_minor: 0,
    active_balance_minor: 0,
    by_method: {} as Record<string, number>,
  };
  const importActor = "legacy-import:" + source.source_project;
  const collector = (uid: string | null) => {
    const user = s.app_users?.find((u) => u.id === uid);
    // Historical attribution only: never grant memberships or impersonate a destination user.
    return user
      ? `Legacy import · ${user.name}`
      : "Legacy import (collector not recorded)";
  };
  for (const b of bookings) {
    const mapping = mappings[b.booking_option_id];
    requireValue(mapping, "Missing destination space mapping");
    const business = d.businesses.find(
      (r) => r.id === mapping.business_id && r.organization_id === org,
    );
    const resource = d.resources.find(
      (r) =>
        r.id === mapping.resource_id &&
        r.business_id === mapping.business_id &&
        r.organization_id === org,
    );
    const location =
      business &&
      d.locations.find(
        (r) => r.id === business.location_id && r.organization_id === org,
      );
    const asset = s.assets.find(
      (a) => a.id === b.asset_id && a.business_id === source.source_business_id,
    );
    const option = s.asset_booking_options.find(
      (o) => o.id === b.booking_option_id && o.asset_id === b.asset_id,
    );
    const service =
      asset &&
      s.location_services.find((ls) => ls.id === asset.location_service_id);
    const sourceLocation =
      service && s.locations.find((l) => l.id === service.location_id);
    requireValue(
      business && resource && location && asset && option && sourceLocation,
      "Invalid booking resource topology",
    );
    requireValue(
      location.timezone === sourceLocation.timezone,
      "Source and destination timezones differ",
    );
    businessIds.add(business.id);
    const lines = s.booking_lines.filter((l) => l.booking_id === b.id);
    requireValue(lines.length > 0, "A booking has no source price lines");
    const discounts = payments.filter(
      (p) => p.booking_id === b.id && p.method === "discount",
    );
    const gross = lines.reduce((n, l) => n + amount(l.amount), 0);
    const discount = discounts.reduce((n, p) => n + amount(p.amount), 0);
    requireValue(
      gross <= 100000000 && discount <= gross,
      "Invalid historical booking total/discount",
    );
    const total = gross - discount;
    const sourcePayments = payments.filter(
      (p) => p.booking_id === b.id && p.method !== "discount",
    );
    const paid = sourcePayments.reduce((n, p) => n + amount(p.amount), 0);
    requireValue(
      paid <= total,
      "Source booking is overpaid; review before import",
    );
    const start = sourceTime(b.starts_at, location.timezone);
    const end = sourceTime(b.ends_at, location.timezone);
    const duration = (Date.parse(end) - Date.parse(start)) / 60000;
    requireValue(
      Number.isInteger(duration) && duration > 0 && duration <= 1440,
      "Unsupported booking duration",
    );
    requireValue(
      ["confirmed", "completed", "cancelled", "no_show"].includes(b.status),
      "Unsupported source booking status",
    );
    requireValue(
      b.status !== "cancelled" || paid === 0,
      "Cancelled source booking has money attached; review refunds first",
    );
    const people = b.party_size ?? 1;
    requireValue(
      Number.isInteger(people) && people >= 1 && people <= 10000,
      "Invalid historical party size",
    );
    const config = business.configuration;
    const cricket = lines.some((l) => /\bcricket\b/i.test(l.label));
    const optionId =
      cricket && mapping.cricket_option_id
        ? mapping.cricket_option_id
        : mapping.option_id;
    let capacity = 1;
    let targetInventory: string[];
    if (config.kind === "turf_v1") {
      const layout = config.layouts.find((l: Row) => l.id === resource.id);
      requireValue(
        layout &&
          config.offerings.some(
            (o: Row) => o.id === optionId && o.layout_id === resource.id,
          ),
        "Turf offering mapping changed",
      );
      targetInventory = layout.section_ids.map(
        (key: string) => business.id + ":" + key,
      );
    } else {
      const spaces = config.kind === "pool_v1" ? config.pools : config.courts;
      requireValue(
        ["pool_v1", "court_v1"].includes(config.kind) &&
          spaces.some((r: Row) => r.id === resource.id),
        "Unsupported destination booking type",
      );
      requireValue(
        optionId === (config.kind === "pool_v1" ? "regular" : "hourly"),
        "Invalid pool/court option mapping",
      );
      capacity =
        config.kind === "pool_v1"
          ? spaces.find((r: Row) => r.id === resource.id).capacity
          : 1;
      targetInventory = [business.id + ":" + resource.id];
    }
    const mappedInventory = option.resource_keys.map(
      (key: string) => mapping.inventory[key],
    );
    requireValue(
      mappedInventory.every(Boolean) &&
        JSON.stringify([...mappedInventory].sort()) ===
          JSON.stringify([...targetInventory].sort()),
      "Source/target inventory topology mismatch",
    );
    const bookingId = id("bookings", b.id);
    requireValue(
      !d.bookings.some(
        (e) =>
          e.price_snapshot?.legacy_import?.source_booking_id === b.id &&
          e.price_snapshot?.legacy_import?.source_project ===
            source.source_project &&
          e.id !== bookingId,
      ),
      "Source booking was previously imported with another ID",
    );
    let reference = b.ref;
    if (references.has(reference)) {
      reference =
        String(b.ref).slice(0, 24) +
        "-LEG-" +
        bookingId.replace(/-/g, "").slice(0, 8);
      requireValue(
        !references.has(reference),
        "Unable to allocate unique historical reference",
      );
      renamed.push({ source_id: b.id, original: b.ref, imported: reference });
    }
    references.add(reference);
    const selection: Row = {
      business_id: business.id,
      resource_id: resource.id,
      option_id: optionId,
      date: b.starts_at.slice(0, 10),
      time: b.starts_at.slice(11, 16),
      duration_minutes: duration,
      people,
    };
    if (discount)
      selection.discount = {
        type: "amount",
        value: discount,
        reason: discounts
          .map((p) => p.note || "Imported discount")
          .join("; ")
          .slice(0, 200),
      };
    const c = s.customers.find((c) => c.id === b.customer_id)!;
    const customer = {
      id: customerMap[b.customer_id],
      name: c.name,
      phone: c.phone,
      email: c.email ?? null,
    };
    const provenance = {
      version: 1,
      source_project: source.source_project,
      source_business_id: source.source_business_id,
      source_booking_id: b.id,
      source_reference: b.ref,
      source_hash: sourceHash,
      original_payment_status: b.payment_status,
      original_source: b.source,
      original_checked_in: b.checked_in,
      source_discounts: discounts.map((p) => ({
        id: p.id,
        amount_rupees: p.amount,
        note: p.note,
        created_at: p.created_at,
      })),
    };
    const price: Row = {
      business_id: business.id,
      resource_id: resource.id,
      business_name: business.name,
      space_name: resource.name,
      option_name: option.name,
      timezone: location.timezone,
      selection,
      starts_at: start,
      ends_at: end,
      local_start: localStamp(Date.parse(start), location.timezone),
      local_end: localStamp(Date.parse(end), location.timezone),
      occupied_from: start,
      occupied_until: end,
      preparation_minutes: 0,
      cleanup_minutes: asset.buffer_minutes ?? 0,
      subtotal_minor: gross,
      discount_minor: discount,
      total_minor: total,
      business_version: business.version,
      inventory_keys: targetInventory,
      quantity: config.kind === "pool_v1" ? people : 1,
      capacity,
      legacy_import: provenance,
    };
    price.quote_token = hash(price);
    rows.bookings!.push({
      id: bookingId,
      organization_id: org,
      business_id: business.id,
      resource_id: resource.id,
      customer_id: customer.id,
      reference,
      status: b.status,
      starts_at: start,
      ends_at: end,
      total_minor: total,
      selection,
      price_snapshot: price,
      customer_snapshot: customer,
      notes: b.notes ?? "",
      people,
      version: 1,
      created_by: importActor,
      created_at: sourceTime(b.created_at),
    });
    if (b.status !== "cancelled")
      for (const key of targetInventory)
        rows.booking_allocations!.push({
          booking_id: bookingId,
          inventory_key: key,
          starts_at: start,
          ends_at: end,
          quantity: price.quantity,
        });
    rows.booking_history!.push({
      id: id("history-import", b.id),
      booking_id: bookingId,
      actor_id: importActor,
      action: "legacy_imported",
      details: {
        ...provenance,
        source_price_lines: lines,
        imported_at: importedAt,
      },
      created_at: importedAt,
    });
    if (b.checked_in)
      rows.booking_history!.push({
        id: id("history-checkin", b.id),
        booking_id: bookingId,
        actor_id: importActor,
        action: "checked_in",
        details: {
          source: "legacy_import",
          original_event_time_unknown: true,
          imported_at: importedAt,
        },
        created_at: importedAt,
      });
    for (const p of sourcePayments) {
      requireValue(
        ["cash", "upi", "card", "netbanking"].includes(p.method),
        "Unsupported historical payment method",
      );
      const method = p.method === "netbanking" ? "bank_transfer" : p.method;
      const minor = amount(p.amount);
      requireValue(minor > 0, "Zero historical payment");
      const paymentId = id("booking_payments", p.id);
      const eventId = id("finance_events", p.id);
      const received = sourceTime(p.created_at);
      const accountId =
        method === "cash"
          ? cash[0].id
          : p.bank_account_id
            ? bankMap[p.bank_account_id]
            : clearing[0].id;
      requireValue(accountId, "Missing payment destination mapping");
      const actor = collector(p.collected_by_user_id);
      rows.booking_payments!.push({
        id: paymentId,
        organization_id: org,
        booking_id: bookingId,
        kind: "collection",
        method,
        amount_minor: minor,
        reference: p.note ?? "",
        reason: "Imported historical booking payment",
        received_at: received,
        recorded_by: actor,
        recorded_at: received,
      });
      rows.finance_events!.push({
        id: eventId,
        organization_id: org,
        kind: "booking_collection",
        business_id: business.id,
        resource_id: resource.id,
        booking_payment_id: paymentId,
        category: "",
        reason: "Booking " + reference,
        reference: p.note ?? "",
        occurred_at: received,
        recorded_at: received,
        recorded_by: actor,
        command_key: id("finance_commands", p.id),
        request_hash: hash({
          source_project: source.source_project,
          payment: p,
        }),
      });
      rows.finance_lines!.push({
        id: id("finance_lines", p.id),
        organization_id: org,
        event_id: eventId,
        account_id: accountId,
        method,
        amount_minor: minor,
      });
      expected.payments++;
      expected.collected_minor += minor;
      expected.by_method[method] = (expected.by_method[method] ?? 0) + minor;
    }
    expected.gross_minor += gross;
    expected.discount_minor += discount;
    expected.total_minor += total;
    if (b.status !== "cancelled") expected.active_balance_minor += total - paid;
  }
  for (const correction of s.booking_collection_corrections ?? []) {
    requireValue(
      sourceBookingIds.has(correction.booking_id),
      "Unscoped collection correction",
    );
    rows.booking_history!.push({
      id: id("collection-corrections", correction.id),
      booking_id: id("bookings", correction.booking_id),
      actor_id: collector(correction.corrected_by),
      action: "legacy_collection_corrected",
      details: {
        source: "legacy_import",
        source_correction_id: correction.id,
        reason: correction.reason,
        previous_total_rupees: correction.previous_total,
        corrected_total_rupees: correction.corrected_total,
        previous_payments: correction.previous_payments,
        corrected_payments: correction.corrected_payments,
      },
      created_at: sourceTime(correction.corrected_at),
    });
  }
  rows.audit_events!.push({
    id: id("audit", source.source_business_id),
    organization_id: org,
    actor_id: importActor,
    action: "bookings.legacy_imported",
    entity_id: org,
    created_at: importedAt,
  });
  const businessList = [...businessIds].sort();
  return {
    source_project: source.source_project,
    source_business_id: source.source_business_id,
    organization_id: org,
    source_hash: sourceHash,
    command_key: commandKey,
    request_hash: requestHash,
    configuration_hash: configurationHash(
      d.businesses.filter((b) => businessIds.has(b.id)),
    ),
    business_ids: businessList,
    rows,
    source_booking_ids: bookings.map((b) => b.id),
    renamed_references: renamed,
    customer_map: customerMap,
    bank_map: bankMap,
    expected,
  };
}

const INSERT_ORDER = [
  "customers",
  "money_accounts",
  "bookings",
  "booking_allocations",
  "booking_payments",
  "finance_events",
  "finance_lines",
  "booking_history",
  "audit_events",
];
async function insertRows(db: Queryable, table: string, rows: Row[]) {
  requireValue(INSERT_ORDER.includes(table), "Unapproved import table");
  if (!rows.length) return;
  const columns = Object.keys(rows[0]!);
  requireValue(
    rows.every(
      (r) => JSON.stringify(Object.keys(r)) === JSON.stringify(columns),
    ),
    "Inconsistent import columns",
  );
  requireValue(
    columns.every((c) => /^[a-z_]+$/.test(c)),
    "Invalid column name",
  );
  const names = columns.map((c) => '"' + c + '"').join(",");
  for (let offset = 0; offset < rows.length; offset += 200)
    await db.query(
      `INSERT INTO "${table}"(${names}) SELECT ${names} FROM jsonb_populate_recordset(NULL::"${table}",$1::jsonb)`,
      [JSON.stringify(rows.slice(offset, offset + 200))],
    );
}

export async function verifyBookingImport(
  db: Queryable,
  plan: BookingImportPlan,
) {
  const ids = plan.rows.bookings!.map((b) => b.id);
  const r = (
    await db.query<Row>(
      `SELECT count(*)::int AS bookings,coalesce(sum(b.total_minor),0)::text AS total_minor,
    coalesce(sum((b.price_snapshot->>'subtotal_minor')::bigint),0)::text AS gross_minor,
    coalesce(sum((b.price_snapshot->>'discount_minor')::bigint),0)::text AS discount_minor,
    coalesce(sum(CASE WHEN b.status='cancelled' THEN 0 ELSE b.total_minor-coalesce(p.paid,0) END),0)::text AS active_balance_minor,
    coalesce(sum(p.paid),0)::text AS collected_minor,coalesce(sum(p.n),0)::int AS payments
    FROM bookings b LEFT JOIN LATERAL(SELECT sum(amount_minor) AS paid,count(*) AS n FROM booking_payments WHERE booking_id=b.id AND kind='collection') p ON true
    WHERE b.organization_id=$1 AND b.id=ANY($2::uuid[])`,
      [plan.organization_id, ids],
    )
  ).rows[0]!;
  for (const key of [
    "bookings",
    "payments",
    "total_minor",
    "gross_minor",
    "discount_minor",
    "active_balance_minor",
    "collected_minor",
  ] as const)
    requireValue(
      Number(r[key]) === plan.expected[key],
      `Imported ${key} does not reconcile`,
    );
  const methods = (
    await db.query<Row>(
      "SELECT p.method,sum(p.amount_minor)::text AS amount FROM booking_payments p WHERE p.organization_id=$1 AND p.booking_id=ANY($2::uuid[]) GROUP BY p.method",
      [plan.organization_id, ids],
    )
  ).rows;
  requireValue(
    methods.length === Object.keys(plan.expected.by_method).length &&
      methods.every(
        (m) => Number(m.amount) === plan.expected.by_method[m.method],
      ),
    "Payment methods do not reconcile",
  );
  const ledger = (
    await db.query<Row>(
      `SELECT count(*)::int AS payments,count(e.id)::int AS events,count(l.id)::int AS lines,
    coalesce(sum(l.amount_minor),0)::text AS ledger_minor,
    count(*) FILTER(WHERE e.organization_id<>p.organization_id OR l.organization_id<>p.organization_id OR l.amount_minor<>p.amount_minor OR l.method<>p.method OR e.kind<>'booking_collection')::int AS mismatches
    FROM booking_payments p LEFT JOIN finance_events e ON e.booking_payment_id=p.id LEFT JOIN finance_lines l ON l.event_id=e.id
    WHERE p.organization_id=$1 AND p.id=ANY($2::uuid[])`,
      [plan.organization_id, plan.rows.booking_payments!.map((p) => p.id)],
    )
  ).rows[0]!;
  requireValue(
    ledger.payments === plan.expected.payments &&
      ledger.events === plan.expected.payments &&
      ledger.lines === plan.expected.payments &&
      Number(ledger.ledger_minor) === plan.expected.collected_minor &&
      ledger.mismatches === 0,
    "Booking payments and finance ledger do not reconcile",
  );
  return {
    ...plan.expected,
    ledger_verified: true,
    rows_by_table: Object.fromEntries(
      Object.entries(plan.rows).map(([t, rows]) => [t, rows.length]),
    ),
  };
}

/** Caller supplies one transaction; this routine never updates, deletes, migrates, or notifies. */
export async function applyBookingImport(
  db: Queryable,
  plan: BookingImportPlan,
) {
  requireValue(
    (
      await db.query("SELECT id FROM organizations WHERE id=$1 FOR UPDATE", [
        plan.organization_id,
      ])
    ).rows.length === 1,
    "Destination organization missing",
  );
  const command = (
    await db.query<Row>(
      "SELECT * FROM booking_commands WHERE organization_id=$1 AND command_key=$2",
      [plan.organization_id, plan.command_key],
    )
  ).rows[0];
  if (command) {
    requireValue(
      command.kind === "legacy_bookings_import_v1" &&
        command.request_hash === plan.request_hash,
      "A different export was already imported; refusing to overwrite it",
    );
    return { already_imported: true, ...(await verifyBookingImport(db, plan)) };
  }
  const businesses = (
    await db.query<Row>(
      "SELECT * FROM businesses WHERE organization_id=$1 AND id=ANY($2::uuid[]) ORDER BY id FOR UPDATE",
      [plan.organization_id, plan.business_ids],
    )
  ).rows;
  requireValue(
    configurationHash(businesses) === plan.configuration_hash,
    "Destination businesses changed after preflight",
  );
  const existing = (
    await db.query<Row>(
      "SELECT id,reference FROM bookings WHERE organization_id=$1 AND (id=ANY($2::uuid[]) OR reference=ANY($3::text[]))",
      [
        plan.organization_id,
        plan.rows.bookings!.map((b) => b.id),
        plan.rows.bookings!.map((b) => b.reference),
      ],
    )
  ).rows;
  requireValue(
    existing.length === 0,
    "Existing booking ID/reference collision; refusing to replace data",
  );
  for (const table of INSERT_ORDER)
    await insertRows(db, table, plan.rows[table]!);
  const result = await verifyBookingImport(db, plan);
  await db.query(
    "INSERT INTO booking_commands(organization_id,command_key,actor_id,kind,request_hash,response) VALUES($1,$2,$3,'legacy_bookings_import_v1',$4,$5::jsonb)",
    [
      plan.organization_id,
      plan.command_key,
      "legacy-import:" + plan.source_project,
      plan.request_hash,
      JSON.stringify(result),
    ],
  );
  return { already_imported: false, ...result };
}
