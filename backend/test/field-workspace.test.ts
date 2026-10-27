import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { ZodError } from "zod";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import {
  acceptanceSchema,
  businessOrderSchema,
  businessSchema,
  configSchema,
  invitationSchema,
  locationSchema,
  logoSchema,
  orgSchema,
  resourceSchema,
} from "../src/workspace/validation";
import { organizationEditSchema } from "../src/workspace/organization-edit";
import type { Actor } from "../src/common/auth.guard";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  service = new WorkspaceService(db);
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());

const uuid = "00000000-0000-4000-8000-000000000001";
const location = {
  name: "Main property",
  address_line_1: "Road 1",
  address_line_2: null,
  city: "Kochi",
  state_code: "KL",
  country_code: "IN",
  postal_code: "682001",
  timezone: "Asia/Kolkata",
};
const org = {
  name: "Field Arena",
  contact_phone: "9876543210",
  currency: "INR",
  location,
};
const rules = {
  version: 1,
  opens_at: "06:00",
  closes_at: "23:00",
  days: [1, 2, 3, 4, 5, 6, 7],
  duration_minutes: 60,
  price_minor: 150000,
  buffer_minutes: 0,
  plan_name: null,
  validity_days: null,
  entitlement: null,
  visit_limit: null,
};
const actor = (): Actor => {
  const id = randomUUID();
  return { uid: id, email: `${id}@example.com`, name: "Owner" };
};
async function owner() {
  const a = actor();
  await service.createOrganization(a, org);
  const w = await service.workspace(a);
  return { a, location_id: w.locations[0].id as string };
}
const accepts = (
  schema: { safeParse(v: unknown): { success: boolean } },
  v: unknown,
  label = "",
) =>
  assert.equal(
    schema.safeParse(v).success,
    true,
    `should accept ${label || JSON.stringify(v)}`,
  );
const rejects = (
  schema: { safeParse(v: unknown): { success: boolean } },
  v: unknown,
  label = "",
) =>
  assert.equal(
    schema.safeParse(v).success,
    false,
    `should reject ${label || JSON.stringify(v)}`,
  );
const long = (n: number, c = "a") => c.repeat(n);

// ---------------------------------------------------------------- location

test("location: required text fields reject empty, whitespace, null, wrong type and overlong values", () => {
  for (const field of [
    "name",
    "address_line_1",
    "city",
    "postal_code",
    "country_code",
    "timezone",
  ])
    for (const bad of ["", "   ", null, 0, 12, true, [], {}, undefined])
      rejects(
        locationSchema,
        { ...location, [field]: bad },
        `${field}=${JSON.stringify(bad)}`,
      );
  rejects(locationSchema, { ...location, name: long(121) });
  accepts(locationSchema, { ...location, name: long(120) });
  rejects(locationSchema, { ...location, address_line_1: long(201) });
  accepts(locationSchema, { ...location, address_line_1: long(200) });
  rejects(locationSchema, { ...location, city: long(121) });
  rejects(locationSchema, { ...location, address_line_2: long(201) });
  rejects(locationSchema, { ...location, postal_code: long(21) });
  rejects(locationSchema, { ...location, address_line_2: 5 });
  rejects(
    locationSchema,
    { ...location, address_line_2: undefined },
    "missing nullable key",
  );
  rejects(locationSchema, { ...location, extra: 1 }, "unknown key");
});

test("location: unicode text, emoji and surrounding whitespace are preserved or trimmed", () => {
  const parsed = locationSchema.parse({
    ...location,
    name: "  കൊച്ചി ശാഖ  ",
    city: "München",
    address_line_1: "४ Road 🏟",
  });
  assert.equal(parsed.name, "കൊച്ചി ശാഖ");
  assert.equal(parsed.city, "München");
});

test("location: country/state/pincode/timezone interplay", () => {
  for (const country_code of ["in", "IND", "I", "ZZ", "00", " IN"])
    rejects(locationSchema, { ...location, country_code }, country_code);
  for (const state_code of ["kl", "XX", "", null, "KL ", "KERALA-LONG-CODE"])
    rejects(locationSchema, { ...location, state_code }, String(state_code));
  for (const postal_code of [
    "68200",
    "6820011",
    "082001",
    "68200a",
    "६८२००१",
    "682 001",
    "00000",
  ])
    rejects(locationSchema, { ...location, postal_code }, postal_code);
  accepts(
    locationSchema,
    { ...location, postal_code: "  682001  " },
    "padded pincode is trimmed",
  );
  accepts(locationSchema, {
    ...location,
    country_code: "US",
    state_code: "CA",
    postal_code: "90210",
  });
  for (const timezone of [
    "",
    " Asia/Kolkata",
    "Asia/Nowhere",
    "Etc/GMT+14",
    "Asia/Kolkata\n",
    "x".repeat(81),
  ])
    rejects(
      locationSchema,
      { ...location, timezone },
      JSON.stringify(timezone),
    );
});

test("location: timezone must be a canonical IANA zone, not a UTC offset", () => {
  // Postgres reads '+05:30' as a POSIX zone (UTC-5:30), the opposite sign, and the
  // timezone is snapshotted into bookings used by AT TIME ZONE queries.
  rejects(locationSchema, { ...location, timezone: "+05:30" }, "offset zone");
  rejects(
    locationSchema,
    { ...location, timezone: "asia/kolkata" },
    "non-canonical case",
  );
});

test("location: Postgres reads an accepted offset timezone with the inverted sign", async () => {
  const r = (
    await db.query<{ a: string; b: string }>(
      "SELECT (timestamptz '2026-01-01 00:00:00+00' AT TIME ZONE '+05:30')::text a,(timestamptz '2026-01-01 00:00:00+00' AT TIME ZONE 'Asia/Kolkata')::text b",
    )
  ).rows[0];
  assert.notEqual(r.a, r.b, "documents why BUG-1 matters");
});

test(
  "location: countries without states accept an arbitrary state code",
  { todo: "BUG-6" },
  () => {
    rejects(
      locationSchema,
      { ...location, country_code: "AQ", state_code: "ZZ", postal_code: "x" },
      "state code for a country with no states",
    );
  },
);

// --------------------------------------------------------------- organization

test("organization: name boundaries, types and unicode", () => {
  for (const bad of [
    "",
    " ",
    "a",
    " a ",
    null,
    7,
    [],
    {},
    undefined,
    long(121),
  ])
    rejects(
      orgSchema,
      { ...org, name: bad },
      JSON.stringify(bad)?.slice(0, 20),
    );
  accepts(orgSchema, { ...org, name: "ab" });
  accepts(orgSchema, { ...org, name: long(120) });
  accepts(orgSchema, { ...org, name: "കൊച്ചി Arena 🏟" });
  assert.equal(orgSchema.parse({ ...org, name: "  Eden  " }).name, "Eden");
});

test(
  "organization: invisible-only names are rejected",
  { todo: "BUG-3" },
  () => {
    rejects(orgSchema, { ...org, name: "​​" }, "two zero-width spaces");
    rejects(orgSchema, { ...org, name: "‍⁠" }, "joiner/word-joiner only");
  },
);

test("organization: currency is a closed upper-case enum", () => {
  for (const bad of ["inr", "JPY", "", " INR", null, 1, ["INR"], undefined])
    rejects(orgSchema, { ...org, currency: bad }, JSON.stringify(bad));
  for (const ok of ["INR", "AED", "GBP", "USD", "EUR"])
    accepts(orgSchema, { ...org, currency: ok });
});

test("organization: unknown keys and wrong top-level types are refused", () => {
  rejects(orgSchema, { ...org, organization_id: uuid }, "tenant injection");
  rejects(orgSchema, { ...org, location: null });
  rejects(orgSchema, null);
  rejects(orgSchema, "string");
  rejects(orgSchema, []);
});

test("organization: contact phone length boundaries", () => {
  for (const bad of ["", "     ", "12345", null, 9876543210, [], long(31, "1")])
    rejects(orgSchema, { ...org, contact_phone: bad }, JSON.stringify(bad));
  accepts(orgSchema, { ...org, contact_phone: "123456" });
  accepts(orgSchema, { ...org, contact_phone: long(30, "1") });
  accepts(orgSchema, { ...org, contact_phone: "+91 98765 43210" });
});

test(
  "organization: contact phone must be a phone number (parity with the edit schema)",
  { todo: "BUG-2" },
  () => {
    for (const bad of [
      "abcdefgh",
      "<script>",
      "hello world",
      "------",
      "((((((",
    ])
      rejects(orgSchema, { ...org, contact_phone: bad }, bad);
  },
);

test(
  "organization: a phone accepted at creation can later be edited unchanged",
  { todo: "BUG-2" },
  async () => {
    const a = actor();
    await service.createOrganization(a, {
      ...org,
      contact_phone: "call me maybe",
    });
    const details = await service.organizationDetails(a);
    await assert.doesNotReject(() =>
      service.updateOrganization(a, {
        revision: details.revision,
        name: details.name,
        contact_phone: details.contact_phone,
        locations: details.locations.map(({ timezone: _t, ...l }) => l),
      }),
    );
  },
);

test(
  "organization: NUL characters are a client error, not an internal error",
  { todo: "BUG-4" },
  async () => {
    const err = await service
      .createOrganization(actor(), { ...org, name: "ab\u0000c" })
      .then(
        () => null,
        (e) => e,
      );
    assert.ok(err, "must reject");
    assert.ok(
      err instanceof ZodError || (err.getStatus && err.getStatus() < 500),
      `expected a 4xx/ZodError but got ${err?.constructor?.name} code=${err?.code}`,
    );
  },
);

test("organization: a second organization for the same account is a conflict", async () => {
  const a = actor();
  await service.createOrganization(a, org);
  await assert.rejects(
    () => service.createOrganization(a, org),
    /already belongs/,
  );
});

test("organization: failed validation leaves no partial rows", async () => {
  const a = actor();
  await assert.rejects(() =>
    service.createOrganization(a, {
      ...org,
      location: { ...location, postal_code: "bad" },
    }),
  );
  assert.equal(
    (await db.query("SELECT 1 FROM organizations WHERE created_by=$1", [a.uid]))
      .rows.length,
    0,
  );
  assert.equal((await service.workspace(a)).organization, null);
});

// ------------------------------------------------------------ organization edit

const edit = {
  revision: "a".repeat(64),
  name: "Edited Arena",
  contact_phone: "9876543210",
  locations: [{ id: uuid, ...(({ timezone: _t, ...l }) => l)(location) }],
};

test("organization edit: revision must be 64 lower-case hex characters", () => {
  for (const bad of [
    "",
    "A".repeat(64),
    "a".repeat(63),
    "a".repeat(65),
    "g".repeat(64),
    null,
    1,
    " ".repeat(64),
    `${"a".repeat(63)}\n`,
  ])
    rejects(
      organizationEditSchema,
      { ...edit, revision: bad },
      JSON.stringify(bad),
    );
  accepts(organizationEditSchema, edit);
});

test("organization edit: phone format, digit count and characters", () => {
  for (const bad of [
    "12345",
    "++919876543210",
    "98765abc43",
    "+1234567890123456",
    "(((((",
    "-- -- --",
    "٩٨٧٦٥٤٣٢١٠",
    "9876543210 ext 5",
    "+",
    " ",
    "",
    null,
    9876543210,
  ])
    rejects(
      organizationEditSchema,
      { ...edit, contact_phone: bad },
      JSON.stringify(bad),
    );
  for (const ok of [
    "+91 (98765) 432-10",
    "123456",
    "+123456789012345",
    "  9876543210  ",
  ])
    accepts(organizationEditSchema, { ...edit, contact_phone: ok }, ok);
  assert.equal(
    organizationEditSchema.parse({ ...edit, contact_phone: "  9876543210 " })
      .contact_phone,
    "9876543210",
  );
});

test("organization edit: location list shape, duplicates and strict keys", () => {
  const l = edit.locations[0];
  rejects(organizationEditSchema, { ...edit, locations: [] }, "empty");
  rejects(
    organizationEditSchema,
    { ...edit, locations: [l, l] },
    "duplicate id",
  );
  rejects(
    organizationEditSchema,
    {
      ...edit,
      locations: Array.from({ length: 101 }, () => ({
        ...l,
        id: randomUUID(),
      })),
    },
    "101",
  );
  accepts(
    organizationEditSchema,
    {
      ...edit,
      locations: Array.from({ length: 100 }, () => ({
        ...l,
        id: randomUUID(),
      })),
    },
    "100",
  );
  rejects(
    organizationEditSchema,
    { ...edit, locations: [{ ...l, timezone: "UTC" }] },
    "timezone injection",
  );
  rejects(organizationEditSchema, {
    ...edit,
    locations: [{ ...l, organization_id: uuid }],
  });
  rejects(organizationEditSchema, {
    ...edit,
    locations: [{ ...l, id: "not-a-uuid" }],
  });
  rejects(organizationEditSchema, { ...edit, locations: null });
  rejects(organizationEditSchema, { ...edit, name: " a " });
  rejects(organizationEditSchema, { ...edit, name: long(121) });
  rejects(
    organizationEditSchema,
    { ...edit, currency: "USD" },
    "currency is not editable",
  );
});

test("organization edit: a non-owner cannot edit and unknown-organization ids are conflicts", async () => {
  const { a } = await owner();
  const d = await service.organizationDetails(a);
  await assert.rejects(
    () => service.organizationDetails(actor()),
    /No active organization/,
  );
  const stranger = {
    revision: d.revision,
    name: d.name,
    contact_phone: d.contact_phone,
    locations: [
      { ...(({ timezone: _t, ...l }) => l)(d.locations[0]), id: randomUUID() },
    ],
  };
  await assert.rejects(
    () => service.updateOrganization(a, stranger),
    /locations changed/,
  );
});

// ------------------------------------------------------------------- business

test("business: name, type and location_id validation", () => {
  const ok = { name: "Turf A", type: "turf", location_id: uuid };
  accepts(businessSchema, ok);
  for (const bad of ["", " ", "a", null, 5, long(121), [], undefined])
    rejects(
      businessSchema,
      { ...ok, name: bad },
      JSON.stringify(bad)?.slice(0, 20),
    );
  for (const bad of [
    "Turf",
    "cricket",
    "",
    null,
    1,
    ["turf"],
    " turf",
    undefined,
  ])
    rejects(businessSchema, { ...ok, type: bad }, JSON.stringify(bad));
  for (const bad of ["", "abc", null, 5, uuid.slice(1), uuid + "0", undefined])
    rejects(businessSchema, { ...ok, location_id: bad }, JSON.stringify(bad));
  rejects(businessSchema, { ...ok, organization_id: uuid }, "tenant injection");
  rejects(businessSchema, { ...ok, status: "ready" }, "status injection");
  for (const type of [
    "turf",
    "badminton",
    "tennis",
    "basketball",
    "pool",
    "hall",
  ])
    accepts(businessSchema, { ...ok, type });
});

test("business: duplicate names conflict (unique per organization) and other tenants may reuse them", async () => {
  const a = await owner(),
    b = await owner();
  await service.createBusiness(a.a, {
    name: "Centre Court",
    type: "tennis",
    location_id: a.location_id,
  });
  const err = await service
    .createBusiness(a.a, {
      name: "Centre Court",
      type: "tennis",
      location_id: a.location_id,
    })
    .then(
      () => null,
      (e) => e,
    );
  assert.equal(err?.code, "23505");
  await service.createBusiness(b.a, {
    name: "Centre Court",
    type: "tennis",
    location_id: b.location_id,
  });
});

test(
  "business: names that differ only by case or surrounding space are treated as the same business",
  { todo: "BUG-8" },
  async () => {
    const a = await owner();
    await service.createBusiness(a.a, {
      name: "Arena One",
      type: "turf",
      location_id: a.location_id,
    });
    await assert.rejects(
      () =>
        service.createBusiness(a.a, {
          name: "arena one",
          type: "turf",
          location_id: a.location_id,
        }),
      "case-insensitive duplicate should conflict",
    );
  },
);

test("business: location from another tenant or unknown id is rejected before insert", async () => {
  const a = await owner(),
    b = await owner();
  await assert.rejects(
    () =>
      service.createBusiness(a.a, {
        name: "Stolen Site",
        type: "turf",
        location_id: b.location_id,
      }),
    /Select an organization location/,
  );
  await assert.rejects(
    () =>
      service.createBusiness(a.a, {
        name: "Ghost Site",
        type: "turf",
        location_id: randomUUID(),
      }),
    /Select an organization location/,
  );
  assert.equal(
    (
      await db.query(
        "SELECT 1 FROM businesses WHERE name IN ('Stolen Site','Ghost Site')",
      )
    ).rows.length,
    0,
  );
});

test("business: rename validates type, bounds and trims; NUL is a client error", async () => {
  const a = await owner();
  const b = await service.createBusiness(a.a, {
    name: "Rename Me",
    type: "turf",
    location_id: a.location_id,
  });
  for (const bad of [
    null,
    undefined,
    {},
    { name: null },
    { name: 5 },
    { name: ["ab"] },
    { name: "" },
    { name: " " },
    { name: "a" },
    { name: " a " },
    { name: long(121) },
  ])
    await assert.rejects(
      () => service.renameBusiness(a.a, b.id, bad),
      /between 2 and 120/,
      JSON.stringify(bad),
    );
  await service.renameBusiness(a.a, b.id, { name: "  Renamed ✓  " });
  assert.equal((await service.workspace(a.a)).businesses[0].name, "Renamed ✓");
  await service.renameBusiness(a.a, b.id, { name: long(120) });
  await assert.rejects(
    () => service.renameBusiness(a.a, randomUUID(), { name: "Nobody" }),
    /not found/i,
  );
});

test(
  "business: rename NUL character and invisible-only name",
  { todo: "BUG-4" },
  async () => {
    const a = await owner();
    const b = await service.createBusiness(a.a, {
      name: "Nul Probe",
      type: "turf",
      location_id: a.location_id,
    });
    const err = await service
      .renameBusiness(a.a, b.id, { name: "ab\u0000c" })
      .then(
        () => null,
        (e) => e,
      );
    assert.ok(
      err?.getStatus && err.getStatus() < 500,
      `got ${err?.constructor?.name} ${err?.code}`,
    );
  },
);

test(
  "business: invisible-only rename is rejected",
  { todo: "BUG-3" },
  async () => {
    const a = await owner();
    const b = await service.createBusiness(a.a, {
      name: "Zero Width",
      type: "turf",
      location_id: a.location_id,
    });
    await assert.rejects(() =>
      service.renameBusiness(a.a, b.id, { name: "​​" }),
    );
  },
);

test("business: cross-tenant rename, activate and configure behave as not found", async () => {
  const a = await owner(),
    b = await owner();
  const biz = await service.createBusiness(a.a, {
    name: "Mine Only",
    type: "turf",
    location_id: a.location_id,
  });
  await assert.rejects(
    () => service.renameBusiness(b.a, biz.id, { name: "Hijacked" }),
    /not found/i,
  );
  await assert.rejects(() => service.activate(b.a, biz.id), /not found/i);
  await assert.rejects(
    () => service.configure(b.a, biz.id, rules),
    /not found/i,
  );
  await assert.rejects(
    () => service.addResource(b.a, biz.id, { name: "X" }),
    /not found/i,
  );
  await assert.rejects(
    () => service.deleteResource(b.a, biz.id, randomUUID()),
    /not found/i,
  );
  assert.equal((await service.workspace(a.a)).businesses[0].name, "Mine Only");
});

test("business order: payload shape boundaries", () => {
  const ok = { business_ids: [uuid], revision: 0 };
  accepts(businessOrderSchema, ok);
  accepts(businessOrderSchema, { business_ids: [], revision: 0 });
  for (const bad of [-1, 1.5, "1", null, NaN, Infinity, undefined])
    rejects(businessOrderSchema, { ...ok, revision: bad }, String(bad));
  rejects(
    businessOrderSchema,
    { ...ok, business_ids: [uuid, uuid] },
    "duplicates",
  );
  rejects(businessOrderSchema, { ...ok, business_ids: ["x"] });
  rejects(businessOrderSchema, { ...ok, business_ids: null });
  rejects(businessOrderSchema, {
    ...ok,
    business_ids: Array.from({ length: 1001 }, () => randomUUID()),
  });
  rejects(businessOrderSchema, { ...ok, organization_id: uuid });
});

test("business order: a list containing another tenant's business is rejected", async () => {
  const a = await owner(),
    b = await owner();
  const mine = await service.createBusiness(a.a, {
    name: "Order Mine",
    type: "turf",
    location_id: a.location_id,
  });
  const theirs = await service.createBusiness(b.a, {
    name: "Order Theirs",
    type: "turf",
    location_id: b.location_id,
  });
  const revision = (
    await db.query<{ r: number }>(
      "SELECT business_order_revision r FROM organizations WHERE created_by=$1",
      [a.a.uid],
    )
  ).rows[0].r;
  await assert.rejects(
    () =>
      service.reorderBusinesses(a.a, {
        business_ids: [mine.id, theirs.id],
        revision,
      }),
    /exactly once/,
  );
  await assert.rejects(
    () =>
      service.reorderBusinesses(a.a, { business_ids: [theirs.id], revision }),
    /exactly once/,
  );
});

// ------------------------------------------------------------------- resources

test("resource: name and capacity boundaries", () => {
  accepts(resourceSchema, { name: "Court 1" });
  assert.equal(resourceSchema.parse({ name: "Court 1" }).capacity, 1);
  accepts(resourceSchema, { name: "x" });
  accepts(resourceSchema, { name: long(100) });
  accepts(resourceSchema, { name: "കോർട്ട് ൧ 🎾" });
  for (const bad of ["", "   ", null, 5, [], long(101), undefined])
    rejects(resourceSchema, { name: bad }, JSON.stringify(bad)?.slice(0, 20));
  for (const bad of [0, -1, 10001, 1.5, "5", null, NaN, Infinity, true, []])
    rejects(resourceSchema, { name: "Court", capacity: bad }, String(bad));
  accepts(resourceSchema, { name: "Court", capacity: 10000 });
  rejects(
    resourceSchema,
    { name: "Court", business_id: uuid },
    "tenant injection",
  );
});

test("resource: duplicate names within a business conflict, across businesses they do not", async () => {
  const a = await owner();
  const b1 = await service.createBusiness(a.a, {
    name: "Res One",
    type: "badminton",
    location_id: a.location_id,
  });
  const b2 = await service.createBusiness(a.a, {
    name: "Res Two",
    type: "badminton",
    location_id: a.location_id,
  });
  await service.addResource(a.a, b1.id, { name: "Court A" });
  const err = await service.addResource(a.a, b1.id, { name: "Court A" }).then(
    () => null,
    (e) => e,
  );
  assert.equal(err?.code, "23505");
  await service.addResource(a.a, b2.id, { name: "Court A" });
});

test("resource: deleting an unknown resource, another business's resource or a non-uuid id fails safely", async () => {
  const a = await owner();
  const b1 = await service.createBusiness(a.a, {
    name: "Del One",
    type: "badminton",
    location_id: a.location_id,
  });
  const b2 = await service.createBusiness(a.a, {
    name: "Del Two",
    type: "badminton",
    location_id: a.location_id,
  });
  const r2 = await service.addResource(a.a, b2.id, { name: "Court Z" });
  await assert.rejects(
    () => service.deleteResource(a.a, b1.id, randomUUID()),
    /Resource not found/,
  );
  await assert.rejects(
    () => service.deleteResource(a.a, b1.id, r2.id),
    /Resource not found/,
  );
  assert.equal(
    (await service.workspace(a.a)).businesses.find((b: any) => b.id === b2.id)!
      .resources.length,
    1,
  );
});

// --------------------------------------------------------------- configuration

test("configuration: time fields accept only HH:MM 00:00-23:59", () => {
  for (const field of ["opens_at", "closes_at"])
    for (const bad of [
      "24:00",
      "6:00",
      "06:60",
      "06:00:00",
      " 06:00",
      "06:00\n",
      "06-00",
      "",
      null,
      600,
      "ab:cd",
      "٠٦:٠٠",
    ])
      rejects(
        configSchema,
        { ...rules, [field]: bad },
        `${field}=${JSON.stringify(bad)}`,
      );
  accepts(configSchema, { ...rules, opens_at: "00:00", closes_at: "23:59" });
  rejects(configSchema, { ...rules, closes_at: "06:00" }, "equal times");
});

test("configuration: numeric boundaries", () => {
  const num = (field: string, bad: unknown[], good: unknown[]) => {
    for (const b of bad)
      rejects(configSchema, { ...rules, [field]: b }, `${field}=${String(b)}`);
    for (const g of good)
      accepts(configSchema, { ...rules, [field]: g }, `${field}=${String(g)}`);
  };
  num(
    "duration_minutes",
    [29, 1441, 60.5, "60", null, NaN, -60, 0],
    [30, 1440],
  );
  num(
    "price_minor",
    [-1, 100000001, 1.5, "100", null, NaN, Infinity],
    [0, 100000000],
  );
  num("buffer_minutes", [-1, 241, 1.5, "0", null], [0, 240]);
  num("version", [0, -1, 1.5, "1", null, undefined], [1, 5]);
  num(
    "days",
    [[], [0], [8], [1, 1], [1.5], ["1"], null, [1, 2, 3, 4, 5, 6, 7, 7]],
    [[1], [7], [1, 7], [1, 2, 3, 4, 5, 6, 7]],
  );
  num("plan_name", [5, long(121), []], [null, "x", long(120)]);
  num("validity_days", [0, 3651, 1.5, "30"], [null, 1, 3650]);
  num(
    "entitlement",
    ["", "unlimited ", "UNLIMITED", "weekly", 1],
    [null, "unlimited", "visits", "attendance_days"],
  );
  num("visit_limit", [0, -1, 10001, 1.5, "5"], [null, 1, 10000]);
});

test("configuration: missing keys and unknown keys are refused", () => {
  for (const key of Object.keys(rules)) {
    const { [key as keyof typeof rules]: _omit, ...partial } = rules;
    rejects(configSchema, partial, `missing ${key}`);
  }
  rejects(configSchema, { ...rules, kind: "turf_v1" }, "kind injection");
  rejects(configSchema, { ...rules, status: "ready" });
  rejects(configSchema, null);
});

test("configuration: subscription fields are pool-only and pools need them", async () => {
  const a = await owner();
  const turf = await service.createBusiness(a.a, {
    name: "Cfg Turf",
    type: "turf",
    location_id: a.location_id,
  });
  for (const patch of [
    { plan_name: "Gold" },
    { validity_days: 30 },
    { entitlement: "unlimited" },
    { visit_limit: 5 },
  ])
    await assert.rejects(
      () => service.configure(a.a, turf.id, { ...rules, ...patch }),
      /swimming pools only/,
    );
  const pool = await service.createBusiness(a.a, {
    name: "Cfg Pool",
    type: "pool",
    location_id: a.location_id,
  });
  for (const patch of [
    {},
    { plan_name: "Gold" },
    { plan_name: "   ", validity_days: 30, entitlement: "unlimited" },
    { plan_name: "Gold", validity_days: 30 },
    { plan_name: "Gold", entitlement: "unlimited" },
    { plan_name: "Gold", validity_days: 30, entitlement: "visits" },
    { plan_name: "Gold", validity_days: 30, entitlement: "attendance_days" },
  ])
    await assert.rejects(
      () => service.configure(a.a, pool.id, { ...rules, ...patch }),
      /Pool plans require|Enter the visit/,
      JSON.stringify(patch),
    );
  await service.configure(a.a, pool.id, {
    ...rules,
    plan_name: "Gold",
    validity_days: 30,
    entitlement: "unlimited",
  });
});

test("configuration: stale or future version numbers conflict", async () => {
  const a = await owner();
  const b = await service.createBusiness(a.a, {
    name: "Ver Turf",
    type: "turf",
    location_id: a.location_id,
  });
  await assert.rejects(() =>
    service.configure(a.a, b.id, { ...rules, version: 0 }),
  );
  await assert.rejects(
    () => service.configure(a.a, b.id, { ...rules, version: 2 }),
    /another device/,
  );
  await assert.rejects(() =>
    service.configure(a.a, b.id, { ...rules, version: 1.5 }),
  );
  await service.configure(a.a, b.id, rules);
});

test("activation: a business without configuration or resources cannot go live, and a broken stored configuration is refused", async () => {
  const a = await owner();
  const b = await service.createBusiness(a.a, {
    name: "Act Turf",
    type: "turf",
    location_id: a.location_id,
  });
  await assert.rejects(() => service.activate(a.a, b.id), /operating rules/);
  await service.configure(a.a, b.id, rules);
  await assert.rejects(
    () => service.activate(a.a, b.id),
    /at least one resource/,
  );
  await service.addResource(a.a, b.id, { name: "Pitch" });
  await db.query(
    "UPDATE businesses SET configuration=jsonb_set(configuration,'{opens_at}','\"99:99\"') WHERE id=$1",
    [b.id],
  );
  await assert.rejects(() => service.activate(a.a, b.id), ZodError);
  assert.equal((await service.workspace(a.a)).businesses[0].status, "draft");
});

// ------------------------------------------------------------------ invitation

const invite = {
  email: "new.person@example.com",
  display_name: "New Person",
  role: "staff",
  permissions: ["view_bookings"],
  assignments: [{ business_id: uuid, resource_ids: [] as string[] }],
};

test("invitation: email format edge cases", () => {
  for (const bad of [
    "",
    " ",
    " a@b.com",
    "a@b.com ",
    "a@b",
    "a b@c.com",
    "a@@b.com",
    "a@b..com",
    ".a@b.com",
    "a..b@c.com",
    "a@b.c",
    "ü@b.com",
    "a@bü.com",
    "a@b.com\n",
    '"a b"@c.com',
    "a@[1.2.3.4]",
    "a@b.com,c@d.com",
    "a@b.com;c@d.com",
    "mailto:a@b.com",
    "<a@b.com>",
    "Name <a@b.com>",
    null,
    5,
    ["a@b.com"],
    {},
    undefined,
  ])
    rejects(invitationSchema, { ...invite, email: bad }, JSON.stringify(bad));
  assert.equal(
    invitationSchema.parse({ ...invite, email: "Mixed.Case+Tag@Example.COM" })
      .email,
    "mixed.case+tag@example.com",
  );
});

test(
  "invitation: email longer than RFC 5321 limits is rejected",
  { todo: "BUG-5" },
  () => {
    rejects(
      invitationSchema,
      { ...invite, email: `${long(65)}@example.com` },
      "65-char local part",
    );
    rejects(
      invitationSchema,
      { ...invite, email: `a@${long(250)}.com` },
      "254+ chars",
    );
    rejects(
      invitationSchema,
      { ...invite, email: `${long(5000)}@example.com` },
      "5000 chars",
    );
  },
);

test("invitation: display name, role, permissions and assignments", () => {
  for (const bad of ["", " ", "A", null, 5, long(121), [], undefined])
    rejects(
      invitationSchema,
      { ...invite, display_name: bad },
      JSON.stringify(bad)?.slice(0, 20),
    );
  for (const bad of [
    "Staff",
    "admin",
    "OWNER",
    "",
    null,
    1,
    ["staff"],
    "super_admin",
    "platform_admin",
    "sarvam",
  ])
    rejects(invitationSchema, { ...invite, role: bad }, JSON.stringify(bad));
  for (const bad of [
    "admin",
    "view_bookings ",
    "VIEW_BOOKINGS",
    "",
    null,
    "manage_team",
    "owner",
  ])
    rejects(
      invitationSchema,
      { ...invite, permissions: [bad] },
      JSON.stringify(bad),
    );
  rejects(invitationSchema, { ...invite, permissions: "view_bookings" });
  rejects(invitationSchema, { ...invite, permissions: null });
  rejects(
    invitationSchema,
    { ...invite, permissions: Array(10).fill("view_bookings") },
    "more than the permission count",
  );
  rejects(
    invitationSchema,
    { ...invite, assignments: [] },
    "staff needs a business",
  );
  rejects(invitationSchema, {
    ...invite,
    assignments: [{ business_id: uuid }],
  });
  rejects(invitationSchema, {
    ...invite,
    assignments: [{ business_id: "x", resource_ids: [] }],
  });
  rejects(invitationSchema, {
    ...invite,
    assignments: [{ business_id: uuid, resource_ids: ["x"] }],
  });
  rejects(invitationSchema, {
    ...invite,
    assignments: [
      {
        business_id: uuid,
        resource_ids: Array.from({ length: 101 }, () => randomUUID()),
      },
    ],
  });
  rejects(invitationSchema, {
    ...invite,
    assignments: Array.from({ length: 101 }, () => ({
      business_id: randomUUID(),
      resource_ids: [],
    })),
  });
  rejects(invitationSchema, {
    ...invite,
    assignments: [{ business_id: uuid, resource_ids: [], extra: 1 }],
  });
  rejects(
    invitationSchema,
    { ...invite, organization_id: uuid },
    "tenant injection",
  );
  rejects(invitationSchema, { ...invite, active: true });
  for (const role of ["staff", "manager"])
    accepts(invitationSchema, { ...invite, role });
});

test("invitation: an owner invitation drops permissions and assignments", () => {
  const parsed = invitationSchema.parse({
    ...invite,
    role: "owner",
    permissions: ["view_finance"],
    assignments: [{ business_id: uuid, resource_ids: [] }],
  });
  assert.deepEqual(parsed.permissions, []);
  assert.deepEqual(parsed.assignments, []);
  accepts(invitationSchema, { ...invite, role: "owner", assignments: [] });
});

test(
  "invitation: duplicate permissions are normalised",
  { todo: "BUG-7" },
  () => {
    const p = invitationSchema.parse({
      ...invite,
      permissions: ["view_bookings", "view_bookings"],
    });
    assert.deepEqual(p.permissions, ["view_bookings"]);
  },
);

test(
  "invitation: control characters in the display name are refused or flattened",
  { todo: "BUG-7" },
  () => {
    const r = invitationSchema.safeParse({
      ...invite,
      display_name: "Alice\r\nBcc: x@evil.test",
    });
    assert.ok(!r.success || !/[\r\n]/.test(r.data.display_name));
  },
);

test(
  "invitation: invisible-only display name is rejected",
  { todo: "BUG-3" },
  () => {
    rejects(invitationSchema, { ...invite, display_name: "​​" });
  },
);

test("acceptance token: exactly 64 lower-case hex characters", () => {
  const ok = "a1".repeat(32);
  accepts(acceptanceSchema, { token: ok });
  for (const bad of [
    "",
    ok.toUpperCase(),
    ok.slice(1),
    ok + "a",
    ` ${ok}`,
    `${ok}\n`,
    "g".repeat(64),
    null,
    5,
    [ok],
    undefined,
    "٠".repeat(64),
  ])
    rejects(
      acceptanceSchema,
      { token: bad },
      JSON.stringify(bad)?.slice(0, 30),
    );
  rejects(acceptanceSchema, { token: ok, extra: 1 });
  rejects(acceptanceSchema, null);
  rejects(acceptanceSchema, ok);
});

test("logo schema: content type and size limits", () => {
  for (const bad of [
    "image/svg+xml",
    "image/gif",
    "image/PNG",
    "text/html",
    "",
    null,
    "image/png; charset=x",
    "application/octet-stream",
  ])
    rejects(logoSchema, { content_type: bad, base64: "aGVsbG8=" }, String(bad));
  rejects(logoSchema, { content_type: "image/png", base64: "" });
  rejects(logoSchema, { content_type: "image/png", base64: null });
  rejects(logoSchema, { content_type: "image/png", base64: 5 });
  rejects(logoSchema, { content_type: "image/png", base64: long(2800001) });
  accepts(logoSchema, { content_type: "image/png", base64: long(2800000) });
  rejects(logoSchema, { content_type: "image/png", base64: "aa", extra: 1 });
});

// ----------------------------------------------------------------------- logo

const png = (n: number) =>
  Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    Buffer.alloc(Math.max(0, n - 8), 1),
  ]);
const jpeg = (n: number) =>
  Buffer.concat([
    Buffer.from([255, 216, 255]),
    Buffer.alloc(Math.max(0, n - 3), 1),
  ]);
const webp = (n: number) => {
  const b = Buffer.alloc(n, 1);
  b.write("RIFF", 0);
  b.write("WEBP", 8);
  return b;
};

test("logo upload: signature must match the declared type and size limits are exact", async () => {
  const a = await owner();
  const up = (content_type: string, data: Buffer | string) =>
    service.uploadLogo(a.a, {
      content_type,
      base64: typeof data === "string" ? data : data.toString("base64"),
    });
  await assert.rejects(
    () => up("image/png", jpeg(100)),
    /valid PNG, JPEG or WebP/,
  );
  await assert.rejects(
    () => up("image/jpeg", png(100)),
    /valid PNG, JPEG or WebP/,
  );
  await assert.rejects(
    () => up("image/webp", png(100)),
    /valid PNG, JPEG or WebP/,
  );
  await assert.rejects(
    () => up("image/png", png(11)),
    /valid PNG/,
    "shorter than 12 bytes",
  );
  await assert.rejects(
    () =>
      up("image/png", `data:image/png;base64,${png(100).toString("base64")}`),
    /valid PNG/,
    "data URI",
  );
  await assert.rejects(() => up("image/png", "!!!!"), /valid PNG/);
  await assert.rejects(
    () =>
      up("image/png", Buffer.from("<svg onload=alert(1)>").toString("base64")),
    /valid PNG/,
  );
  await assert.rejects(
    () => up("image/png", png(2097153)),
    /valid PNG, JPEG or WebP image up to 2 MB/,
  );
  await up("image/png", png(12));
  await up("image/jpeg", jpeg(100));
  await up("image/webp", webp(100));
  await up("image/png", png(2097152));
  const stored = await service.logo(a.a);
  assert.equal(stored.content_type, "image/png");
  assert.equal(stored.data.length, 2097152);
});

test("logo upload: payload that is not an object is a validation error", async () => {
  const a = await owner();
  for (const bad of [
    null,
    undefined,
    "x",
    5,
    [],
    { content_type: "image/png" },
    { base64: "aa" },
  ])
    await assert.rejects(
      () => service.uploadLogo(a.a, bad as never),
      ZodError,
      JSON.stringify(bad),
    );
});

test("logo: tenants never see each other's logo and members without logo get not found", async () => {
  const a = await owner(),
    b = await owner();
  await assert.rejects(() => service.logo(a.a), /No logo uploaded/);
  await service.uploadLogo(a.a, {
    content_type: "image/jpeg",
    base64: jpeg(64).toString("base64"),
  });
  await assert.rejects(() => service.logo(b.a), /No logo uploaded/);
  await assert.rejects(() => service.logo(actor()), /No active organization/);
  assert.equal((await service.logo(a.a)).content_type, "image/jpeg");
});

// ------------------------------------------------------------------- catalog

import { CatalogController } from "../src/workspace/workspace.controller";
import {
  coachProblem,
  isCoach,
  planSpaces,
  coachingConfiguration,
} from "../src/workspace/coach.access";

test("catalog: every advertised country, state and timezone is accepted by the address schema", () => {
  const catalog = new CatalogController().catalog();
  assert.ok(catalog.countries.length > 200);
  assert.deepEqual([...catalog.timezones], [...catalog.timezones].sort());
  assert.ok(
    catalog.timezones.includes("Asia/Kolkata") &&
      catalog.timezones.includes("UTC"),
  );
  assert.equal(new Set(catalog.timezones).size, catalog.timezones.length);
  for (const tz of catalog.timezones)
    assert.equal(
      locationSchema.safeParse({ ...location, timezone: tz }).success,
      true,
      tz,
    );
  const states = new CatalogController().states("IN");
  assert.ok(states.some((s) => s.code === "KL"));
  for (const country of catalog.countries.slice(0, 40)) {
    const first = new CatalogController().states(country.code)[0];
    const input = {
      ...location,
      country_code: country.code,
      state_code: first?.code ?? null,
      postal_code: country.code === "IN" ? "682001" : "12345",
    };
    assert.equal(
      locationSchema.safeParse(input).success,
      true,
      `${country.code} ${country.name}`,
    );
  }
});

test("catalog: state lookups for unknown, lower-case or hostile country codes return an empty list", () => {
  const c = new CatalogController();
  for (const code of [
    "",
    "in",
    "ZZ",
    "IND",
    "../etc",
    "<script>",
    "%00",
    "constructor",
    "__proto__",
    "' OR 1=1",
  ])
    assert.deepEqual(c.states(code), [], code);
});

// ------------------------------------------------------------------ coaching

const mem = (patch: Record<string, unknown> = {}) => ({
  id: "m1",
  role: "staff",
  permissions: ["coach"],
  active: true,
  display_name: "Coach One",
  ...patch,
});
const coaches = (members: any[], assignments: any[] = []) => ({
  members,
  assignments,
});

test("coaching: flags, activity and role decide who can coach", () => {
  assert.equal(isCoach(mem()), true);
  assert.equal(isCoach(mem({ permissions: [] })), false);
  assert.equal(isCoach(mem({ permissions: undefined })), false);
  assert.equal(isCoach(mem({ active: false })), false);
  assert.equal(
    isCoach(mem({ active: undefined })),
    true,
    "legacy rows without the column count as active",
  );
  assert.equal(
    isCoach(mem({ permissions: ["Coach"] })),
    false,
    "permission names are case-sensitive",
  );
  assert.equal(isCoach(mem({ permissions: ["view_bookings", "coach"] })), true);
  assert.deepEqual(planSpaces({ pool_ids: ["a"] }), ["a"]);
  assert.deepEqual(planSpaces({ court_ids: ["b"] }), ["b"]);
  assert.deepEqual(planSpaces({}), []);
  assert.equal(coachingConfiguration(undefined), false);
  assert.equal(coachingConfiguration({ kind: "turf_v1" }), false);
  assert.equal(coachingConfiguration({ kind: "pool_v1" }), true);
  assert.equal(coachingConfiguration({ kind: "court_v1" }), true);
});

test("coaching: assignment scope must cover every space of the plan unless the coach is an owner or unrestricted", () => {
  const b = "biz1";
  const a = (resource_ids: string[], business_id = b) => ({
    membership_id: "m1",
    business_id,
    resource_ids,
  });
  assert.equal(
    coachProblem(coaches([]), b, "m1", []),
    "Choose an active coach from your team.",
  );
  assert.equal(
    coachProblem(coaches([mem({ active: false })]), b, "m1", []),
    "Choose an active coach from your team.",
  );
  assert.match(
    coachProblem(coaches([mem({ permissions: [] })]), b, "m1", [])!,
    /not marked as a coach/,
  );
  assert.equal(
    coachProblem(coaches([mem({ role: "owner" })]), b, "m1", ["s1", "s2"]),
    null,
    "owners cover everything",
  );
  assert.match(
    coachProblem(coaches([mem()]), b, "m1", ["s1"])!,
    /not assigned to this business/,
  );
  assert.match(
    coachProblem(coaches([mem()], [a([], "other")]), b, "m1", ["s1"])!,
    /not assigned to this business/,
  );
  assert.equal(
    coachProblem(coaches([mem()], [a([])]), b, "m1", ["s1", "s2"]),
    null,
    "empty resource list means every space",
  );
  assert.equal(
    coachProblem(coaches([mem()], [a(["s1", "s2"])]), b, "m1", ["s1"]),
    null,
  );
  assert.match(
    coachProblem(coaches([mem()], [a(["s1"])]), b, "m1", ["s1", "s2"])!,
    /every space of this plan/,
  );
  assert.equal(
    coachProblem(coaches([mem()], [a(["s1"])]), b, "m1", []),
    null,
    "a plan with no spaces needs no coverage",
  );
  assert.match(
    coachProblem(coaches([mem()], [a(["s1"])]), b, "unknown", ["s1"])!,
    /active coach/,
  );
  assert.match(
    coachProblem(
      coaches([mem()], [{ ...a(["s1"]), membership_id: "someone-else" }]),
      b,
      "m1",
      ["s1"],
    )!,
    /not assigned/,
  );
});
