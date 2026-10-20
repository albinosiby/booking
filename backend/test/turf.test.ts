import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { TurfService } from "../src/turf/turf.service";
import {
  turfConfigurationSchema,
  turfLayoutsOverlap,
  assertTurfComplete,
} from "../src/turf/turf.validation";
import { Actor } from "../src/common/auth.guard";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  workspace = new WorkspaceService(db),
  turf = new TurfService(db, workspace);
const actor = (): Actor => {
  const uid = randomUUID();
  return { uid, email: `${uid}@example.com`, name: "Owner" };
};
async function fixture() {
  const owner = actor();
  await workspace.createOrganization(owner, {
    name: "Eden",
    contact_phone: "9876543210",
    currency: "INR",
    location: {
      name: "Kochi",
      address_line_1: "Road 1",
      address_line_2: null,
      city: "Kochi",
      state_code: "KL",
      country_code: "IN",
      postal_code: "682001",
      timezone: "Asia/Kolkata",
    },
  });
  const w = await workspace.workspace(owner);
  const business = await workspace.createBusiness(owner, {
    name: "Turf",
    type: "turf",
    location_id: w.locations[0].id,
  });
  return { owner, id: business.id };
}
function configuration(priced = false) {
  const ground = randomUUID(),
    a = randomUUID(),
    b = randomUUID();
  const layouts = [
    { id: randomUUID(), ground_id: ground, name: "Half A", section_ids: [a] },
    { id: randomUUID(), ground_id: ground, name: "Half B", section_ids: [b] },
    {
      id: randomUUID(),
      ground_id: ground,
      name: "Full Ground",
      section_ids: [a, b],
    },
  ];
  return {
    kind: "turf_v1" as const,
    schema_version: 1 as const,
    sports: ["football", "cricket"] as ("football" | "cricket")[],
    grounds: [
      {
        id: ground,
        name: "Main Ground",
        arrangement: "split" as const,
        sections: [
          { id: a, name: "Section A" },
          { id: b, name: "Section B" },
        ],
      },
    ],
    layouts,
    offerings: layouts.flatMap((l, i) =>
      ["football", "cricket"].map((s) => ({
        id: randomUUID(),
        layout_id: l.id,
        sport: s as "football" | "cricket",
        name: `${s} ${i}`,
        format:
          s === "football"
            ? i === 2
              ? "7s"
              : "5s"
            : i === 2
              ? "Full ground"
              : "Half ground",
        enabled: true,
        rates: [{ duration_minutes: 60, price_minor: priced ? 150000 : null }],
        buffer_before: 0,
        buffer_after: 0,
        hours_override: null as {
          days: number[];
          opens_at: string;
          closes_at: string;
        } | null,
      })),
    ),
    operating: {
      days: [1, 2, 3, 4, 5, 6, 7],
      opens_at: "06:00",
      closes_at: "23:00",
    },
  };
}
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());
test("turf draft persists the graph and activation requires all enabled prices", async () => {
  const { owner, id } = await fixture(),
    config = configuration();
  await turf.configure(owner, id, { version: 1, configuration: config });
  let b = (await workspace.workspace(owner)).businesses[0];
  assert.equal(b.resources.length, 3);
  assert.deepEqual(b.configuration, config);
  await assert.rejects(() => workspace.activate(owner, id));
  config.offerings.forEach((o) => (o.rates[0].price_minor = 120000));
  await turf.configure(owner, id, { version: 2, configuration: config });
  await workspace.activate(owner, id);
  b = (await workspace.workspace(owner)).businesses[0];
  assert.equal(b.status, "ready");
  await assert.rejects(() =>
    workspace.addResource(owner, id, { name: "Ghost", capacity: 1 }),
  );
  await assert.rejects(() =>
    workspace.deleteResource(owner, id, config.layouts[0].id),
  );
});
test("shared footprints separate the halves and block full-ground cross-sport overlap", () => {
  const config = turfConfigurationSchema.parse(configuration(true)),
    [a, b, full] = config.layouts;
  assert.equal(turfLayoutsOverlap(config, a.id, b.id), false);
  assert.equal(turfLayoutsOverlap(config, a.id, full.id), true);
  assert.equal(turfLayoutsOverlap(config, b.id, full.id), true);
  assert.equal(turfLayoutsOverlap(config, a.id, a.id), true);
  const second = configuration(true);
  second.layouts.forEach((l, i) => (l.name = `Other ${i}`));
  const combined = turfConfigurationSchema.parse({
    ...config,
    grounds: [...config.grounds, ...second.grounds],
    layouts: [...config.layouts, ...second.layouts],
    offerings: [...config.offerings, ...second.offerings],
  });
  assert.equal(turfLayoutsOverlap(combined, a.id, second.layouts[0].id), false);
});
test("invalid ground references, duplicate offerings and invalid timing overrides are rejected", () => {
  const v = configuration(true);
  v.layouts[2].section_ids = [v.layouts[0].section_ids[0]];
  assert.throws(() => turfConfigurationSchema.parse(v));
  const wrong = configuration(true);
  wrong.layouts[0].section_ids = [randomUUID()];
  assert.throws(() => turfConfigurationSchema.parse(wrong));
  const duplicate = configuration(true);
  duplicate.offerings[1].sport = "football";
  assert.throws(() => turfConfigurationSchema.parse(duplicate));
  const hours = configuration(true);
  hours.offerings[0].hours_override = {
    days: [1],
    opens_at: "05:00",
    closes_at: "10:00",
  };
  assert.throws(() => turfConfigurationSchema.parse(hours));
  const night = configuration(true);
  night.operating = { days: [1], opens_at: "22:00", closes_at: "06:00" };
  night.offerings[0].hours_override = {
    days: [1],
    opens_at: "23:00",
    closes_at: "02:00",
  };
  assert.doesNotThrow(() => assertTurfComplete(night));
  night.offerings[0].buffer_before = 240;
  assert.doesNotThrow(() => assertTurfComplete(night));
});
test("version and tenant checks prevent partial topology writes or stolen space identifiers", async () => {
  const first = await fixture(),
    second = await fixture(),
    config = configuration(true);
  await turf.configure(first.owner, first.id, {
    version: 1,
    configuration: config,
  });
  await assert.rejects(() =>
    turf.configure(first.owner, first.id, {
      version: 1,
      configuration: configuration(true),
    }),
  );
  await assert.rejects(() =>
    turf.configure(second.owner, first.id, {
      version: 2,
      configuration: config,
    }),
  );
  const other = configuration(true);
  other.layouts[0].id = config.layouts[0].id;
  other.offerings[0].layout_id = other.layouts[0].id;
  other.offerings[1].layout_id = other.layouts[0].id;
  await assert.rejects(() =>
    turf.configure(second.owner, second.id, {
      version: 1,
      configuration: other,
    }),
  );
  assert.equal(
    (await workspace.workspace(second.owner)).businesses[0].resources.length,
    0,
  );
  assert.deepEqual(
    (await workspace.workspace(first.owner)).businesses[0].configuration,
    config,
  );
});
test("space-name swaps are atomic and pending staff invitations protect replaced layouts", async () => {
  const { owner, id } = await fixture(),
    config = configuration(true);
  await turf.configure(owner, id, { version: 1, configuration: config });
  [config.layouts[0].name, config.layouts[1].name] = [
    config.layouts[1].name,
    config.layouts[0].name,
  ];
  await turf.configure(owner, id, { version: 2, configuration: config });
  const invite = await workspace.invite(owner, {
    email: actor().email,
    display_name: "Staff",
    role: "staff",
    permissions: ["view_bookings"],
    assignments: [{ business_id: id, resource_ids: [config.layouts[0].id] }],
  });
  await assert.rejects(() =>
    turf.configure(owner, id, {
      version: 3,
      configuration: configuration(true),
    }),
  );
  assert.equal((await workspace.workspace(owner)).businesses[0].version, 3);
  await workspace.revoke(owner, invite.id, true);
  await turf.configure(owner, id, {
    version: 3,
    configuration: configuration(true),
  });
});
test("restricted staff see only assigned topology and cannot change its configuration", async () => {
  const { owner, id } = await fixture(),
    config = configuration(true);
  await turf.configure(owner, id, { version: 1, configuration: config });
  const staff = actor();
  const invite = await workspace.invite(owner, {
    email: staff.email,
    display_name: "Staff",
    role: "staff",
    permissions: ["view_bookings"],
    assignments: [{ business_id: id, resource_ids: [config.layouts[0].id] }],
  });
  const token = new URL(invite.invitation_url).searchParams.get("token")!;
  await workspace.accept(staff, token);
  const b = (await workspace.workspace(staff)).businesses[0];
  assert.equal(b.resources.length, 1);
  assert.equal(b.configuration.layouts.length, 1);
  assert.equal(b.configuration.offerings.length, 2);
  assert.equal(b.configuration.grounds[0].sections.length, 1);
  await assert.rejects(() =>
    turf.configure(staff, id, { version: 2, configuration: config }),
  );
  await assert.rejects(() =>
    turf.configure(owner, id, {
      version: 2,
      configuration: configuration(true),
    }),
  );
});

import { turfPriceAtStart } from "../src/turf/turf.validation";
function timedConfiguration() {
  const config = configuration(true);
  const bands = [
    { days: [6, 7], starts_at: "09:00", ends_at: "18:00", price: 60000 },
    { days: [6, 7], starts_at: "18:00", ends_at: "21:12", price: 70000 },
    {
      days: [1, 2, 3, 4, 5],
      starts_at: "06:00",
      ends_at: "09:00",
      price: 60000,
    },
    {
      days: [1, 2, 3, 4, 5],
      starts_at: "18:00",
      ends_at: "21:12",
      price: 65000,
    },
  ];
  return {
    ...config,
    offerings: config.offerings.map((offer) => ({
      ...offer,
      pricing_basis: "start_time" as const,
      default_duration_minutes: 60,
      pricing_rules: bands.map((band) => ({
        id: randomUUID(),
        days: band.days,
        starts_at: band.starts_at,
        ends_at: band.ends_at,
        rates: [{ duration_minutes: 60, price_minor: band.price }],
      })),
    })),
  };
}
test("weekday/time rates use booking start, exact minute boundaries and no fallback for gaps", () => {
  const config = turfConfigurationSchema.parse(timedConfiguration()),
    id = config.offerings[0].id;
  assert.equal(turfPriceAtStart(config, id, 6, "09:00", 60), 60000);
  assert.equal(turfPriceAtStart(config, id, 6, "17:30", 60), 60000);
  assert.equal(turfPriceAtStart(config, id, 7, "18:00", 60), 70000);
  assert.equal(turfPriceAtStart(config, id, 1, "18:00", 60), 65000);
  assert.equal(turfPriceAtStart(config, id, 2, "06:00", 60), 60000);
  assert.equal(turfPriceAtStart(config, id, 7, "21:11", 60), 70000);
  assert.equal(turfPriceAtStart(config, id, 7, "21:12", 60), null);
  assert.equal(turfPriceAtStart(config, id, 1, "10:00", 60), null);
  assert.equal(turfPriceAtStart(config, id, 1, "18:00", 90), 97500);
  assert.doesNotThrow(() => assertTurfComplete(config));
});
test("overlapping weekday/time rules and invalid defaults are rejected, incomplete rule prices cannot activate", () => {
  const overlap = timedConfiguration();
  overlap.offerings[0].pricing_rules.push({
    id: randomUUID(),
    days: [7],
    starts_at: "17:00",
    ends_at: "19:00",
    rates: [{ duration_minutes: 60, price_minor: 80000 }],
  });
  assert.throws(() => turfConfigurationSchema.parse(overlap));
  const wrong = timedConfiguration();
  wrong.offerings[0].default_duration_minutes = 90;
  assert.throws(() => turfConfigurationSchema.parse(wrong));
  const incomplete = turfConfigurationSchema.parse(timedConfiguration());
  incomplete.offerings[0].pricing_rules![0].rates[0].price_minor = null;
  assert.throws(() => assertTurfComplete(incomplete));
});
test("time-band tariffs persist and restore without altering physical layouts", async () => {
  const { owner, id } = await fixture();
  const config = timedConfiguration();
  await turf.configure(owner, id, { version: 1, configuration: config });
  const saved = (await workspace.workspace(owner)).businesses[0];
  assert.deepEqual(saved.configuration, config);
  assert.equal(saved.resources.length, 3);
  await workspace.activate(owner, id);
});

test("legacy editors cannot overwrite saved weekday/time pricing", async () => {
  const { owner, id } = await fixture(),
    config = timedConfiguration();
  await turf.configure(owner, id, { version: 1, configuration: config });
  await assert.rejects(() =>
    turf.configure(owner, id, {
      version: 2,
      configuration: configuration(true),
    }),
  );
  assert.deepEqual(
    (await workspace.workspace(owner)).businesses[0].configuration,
    config,
  );
});

test("linked Cricket settings persist and reject divergent or missing Football counterparts", async () => {
  const { owner, id } = await fixture();
  const linked = turfConfigurationSchema.parse({
    ...configuration(true),
    cricket_uses_football: true,
  });
  for (const offer of linked.offerings) {
    offer.default_duration_minutes = 60;
    offer.pricing_basis = "start_time";
    offer.pricing_rules = [
      {
        id: randomUUID(),
        days: [1, 2, 3, 4, 5, 6, 7],
        starts_at: "06:00",
        ends_at: "23:00",
        rates: structuredClone(offer.rates),
      },
    ];
  }
  assert.equal(turfConfigurationSchema.safeParse(linked).success, true);
  await turf.configure(owner, id, { version: 1, configuration: linked });
  const loaded = await workspace.workspace(owner);
  assert.equal(loaded.businesses[0].configuration!.cricket_uses_football, true);
  const divergent = structuredClone(linked);
  divergent.offerings.find((o) => o.sport === "cricket")!.rates[0].price_minor =
    99900;
  assert.equal(turfConfigurationSchema.safeParse(divergent).success, false);
  const missing = structuredClone(linked);
  missing.offerings.find((o) => o.sport === "football")!.enabled = false;
  assert.equal(turfConfigurationSchema.safeParse(missing).success, false);
  divergent.cricket_uses_football = false;
  assert.equal(turfConfigurationSchema.safeParse(divergent).success, true);
});

test("final turf edits preserve active status and reject incomplete active changes atomically", async () => {
  const { owner, id } = await fixture();
  const config = timedConfiguration();
  await turf.configure(owner, id, { version: 1, configuration: config });
  await workspace.activate(owner, id);
  const before = (await workspace.workspace(owner)).businesses[0];
  const changed = structuredClone(config);
  changed.grounds[0].name = "Updated ground";
  await turf.configure(owner, id, {
    version: before.version,
    configuration: changed,
  });
  const saved = (await workspace.workspace(owner)).businesses[0];
  assert.equal(saved.status, "ready");
  const invalid = structuredClone(changed);
  invalid.offerings[0].pricing_rules![0].rates[0].price_minor = null;
  await assert.rejects(() =>
    turf.configure(owner, id, {
      version: saved.version,
      configuration: invalid,
    }),
  );
  const after = (await workspace.workspace(owner)).businesses[0];
  assert.equal(after.status, "ready");
  assert.equal(after.version, saved.version);
  assert.deepEqual(after.configuration, changed);
});
