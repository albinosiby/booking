import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { CourtService } from "../src/court/court.service";
import { Actor } from "../src/common/auth.guard";
import {
  CourtConfiguration,
  courtConfigurationSchema,
  assertCourtComplete,
  courtPriceAtStart,
} from "../src/court/court.validation";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  workspace = new WorkspaceService(db),
  service = new CourtService(db, workspace);
const hours = {
  days: [1, 2, 3, 4, 5, 6, 7],
  opens_at: "06:00",
  closes_at: "00:00",
  date_from: null,
  date_until: null,
};
function configuration(): CourtConfiguration {
  return courtConfigurationSchema.parse({
    kind: "court_v1",
    schema_version: 1,
    courts: [1, 2, 3].map((n) => ({
      id: randomUUID(),
      name: `Court ${n}`,
      enabled: true,
      environment: n === 1 ? "indoor" : "outdoor",
      surface: "Synthetic",
      operating: structuredClone(hours),
      durations: [60],
      default_duration_minutes: 60,
      buffer_before: 0,
      buffer_after: 0,
      pricing_basis: "start_time",
      tariffs: [
        {
          id: randomUUID(),
          hours: { ...structuredClone(hours), closes_at: "18:00" },
          rates: [{ duration_minutes: 60, price_minor: n * 40000 }],
        },
        {
          id: randomUUID(),
          hours: { ...structuredClone(hours), opens_at: "18:00" },
          rates: [{ duration_minutes: 60, price_minor: n * 60000 }],
        },
      ],
    })),
  });
}
async function fixture(type = "badminton") {
  const uid = randomUUID(),
    owner: Actor = { uid, email: `${uid}@example.com`, name: "Owner" };
  await workspace.createOrganization(owner, {
    name: "Eden",
    contact_phone: "9876543210",
    currency: "INR",
    location: {
      name: "Kochi",
      address_line_1: "Road",
      address_line_2: null,
      city: "Kochi",
      state_code: "KL",
      country_code: "IN",
      postal_code: "682001",
      timezone: "Asia/Kolkata",
    },
  });
  const w = await workspace.workspace(owner);
  const b = await workspace.createBusiness(owner, {
    name: "Courts",
    type,
    location_id: w.locations[0].id,
  });
  return { owner, id: b.id };
}
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());
test("all three court business types persist independent courts and allow consecutive active edits", async () => {
  for (const type of ["badminton", "tennis", "basketball"]) {
    const { owner, id } = await fixture(type),
      c = configuration();
    await service.configure(owner, id, { version: 1, configuration: c });
    await workspace.activate(owner, id);
    let b = (await workspace.workspace(owner)).businesses[0];
    assert.equal(b.status, "ready");
    assert.deepEqual(b.configuration, c);
    assert.equal(b.resources.length, 3);
    assert.ok(b.resources.every((r: any) => r.capacity === 1));
    [c.courts[0].name, c.courts[1].name] = [c.courts[1].name, c.courts[0].name];
    await service.configure(owner, id, {
      version: b.version,
      configuration: c,
    });
    await workspace.activate(owner, id);
    b = (await workspace.workspace(owner)).businesses[0];
    c.courts[2].tariffs[0].rates[0].price_minor = 75000;
    await service.configure(owner, id, {
      version: b.version,
      configuration: c,
    });
    await workspace.activate(owner, id);
    b = (await workspace.workspace(owner)).businesses[0];
    assert.equal(b.status, "ready");
    assert.equal(b.version, 7);
    assert.deepEqual(
      b.resources.map((r: any) => r.id).sort(),
      c.courts.map((p) => p.id).sort(),
    );
  }
});
test("court rates are independent start-time totals with seasonal overrides and midnight boundaries", () => {
  const c = configuration(),
    p = c.courts[0];
  p.tariffs.push({
    id: randomUUID(),
    hours: {
      ...hours,
      days: [6, 7],
      closes_at: "18:00",
      date_from: "2026-10-17",
      date_until: "2026-10-18",
    },
    rates: [{ duration_minutes: 60, price_minor: 50000 }],
  });
  assertCourtComplete(c);
  assert.equal(courtPriceAtStart(c, p.id, "2026-10-16", "17:30", 60), 40000);
  assert.equal(courtPriceAtStart(c, p.id, "2026-10-17", "17:30", 60), 50000);
  assert.equal(courtPriceAtStart(c, p.id, "2026-10-17", "18:00", 60), 60000);
  assert.equal(
    courtPriceAtStart(c, c.courts[1].id, "2026-10-17", "18:00", 60),
    120000,
  );
  assert.equal(courtPriceAtStart(c, p.id, "2026-10-17", "23:00", 60), 60000);
  assert.equal(courtPriceAtStart(c, p.id, "2026-10-17", "23:01", 60), null);
  assert.equal(courtPriceAtStart(c, p.id, "2026-10-17", "24:00", 60), null);
  p.enabled = false;
  assert.equal(courtPriceAtStart(c, p.id, "2026-10-17", "18:00", 60), null);
});
test("invalid overlaps, duplicate names, outside hours and incomplete active edits leave saved data intact", async () => {
  const { owner, id } = await fixture(),
    c = configuration();
  let x = structuredClone(c);
  x.courts[0].tariffs.push({
    ...structuredClone(x.courts[0].tariffs[0]),
    id: randomUUID(),
  });
  assert.equal(courtConfigurationSchema.safeParse(x).success, false);
  x = structuredClone(c);
  x.courts[1].name = "court 1";
  assert.equal(courtConfigurationSchema.safeParse(x).success, false);
  x = structuredClone(c);
  x.courts[0].tariffs[0].hours.opens_at = "05:00";
  assert.equal(courtConfigurationSchema.safeParse(x).success, false);
  await service.configure(owner, id, { version: 1, configuration: c });
  await workspace.activate(owner, id);
  x = structuredClone(c);
  x.courts[0].tariffs = [];
  await assert.rejects(() =>
    service.configure(owner, id, { version: 3, configuration: x }),
  );
  const b = (await workspace.workspace(owner)).businesses[0];
  assert.equal(b.status, "ready");
  assert.equal(b.version, 3);
  assert.deepEqual(b.configuration, c);
});
test("tenant, stale version, business type and foreign resource identifiers are rejected", async () => {
  const first = await fixture(),
    second = await fixture(),
    hall = await fixture("hall"),
    c = configuration();
  await service.configure(first.owner, first.id, {
    version: 1,
    configuration: c,
  });
  await assert.rejects(() =>
    service.configure(first.owner, first.id, {
      version: 1,
      configuration: configuration(),
    }),
  );
  await assert.rejects(() =>
    service.configure(second.owner, first.id, { version: 2, configuration: c }),
  );
  await assert.rejects(() =>
    service.configure(second.owner, second.id, {
      version: 1,
      configuration: c,
    }),
  );
  await assert.rejects(() =>
    service.configure(hall.owner, hall.id, {
      version: 1,
      configuration: configuration(),
    }),
  );
  assert.equal(
    (await workspace.workspace(second.owner)).businesses[0].resources.length,
    0,
  );
});
test("staff projections restrict courts and pending assignments protect resource deletion", async () => {
  const { owner, id } = await fixture(),
    c = configuration();
  await service.configure(owner, id, { version: 1, configuration: c });
  const uid = randomUUID(),
    email = `${uid}@example.com`,
    staff: Actor = { uid, email, name: "Staff" };
  const invitation = await workspace.invite(owner, {
    email,
    display_name: "Staff",
    role: "staff",
    permissions: ["view_bookings"],
    assignments: [{ business_id: id, resource_ids: [c.courts[0].id] }],
  });
  const removed = { ...structuredClone(c), courts: c.courts.slice(1) };
  await assert.rejects(() =>
    service.configure(owner, id, { version: 2, configuration: removed }),
  );
  await workspace.accept(
    staff,
    new URL(invitation.invitation_url).searchParams.get("token")!,
  );
  const visible = (await workspace.workspace(staff)).businesses[0];
  assert.deepEqual(
    visible.configuration.courts.map((p: any) => p.id),
    [c.courts[0].id],
  );
  await assert.rejects(() =>
    service.configure(staff, id, { version: 2, configuration: c }),
  );
  await assert.rejects(() =>
    service.configure(owner, id, { version: 2, configuration: removed }),
  );
  await assert.rejects(() =>
    workspace.addResource(owner, id, { name: "Legacy bypass", capacity: 1 }),
  );
});
