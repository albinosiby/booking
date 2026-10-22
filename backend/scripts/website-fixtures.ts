import { readFileSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { WebsiteService } from "../src/website/website.service";
import { TurfService } from "../src/turf/turf.service";
import { CourtService } from "../src/court/court.service";
import { PoolService } from "../src/pool/pool.service";
import { HallService } from "../src/hall/hall.service";
import { Actor } from "../src/common/auth.guard";

/** Test/preview data only. Callers must supply an isolated in-memory Database. */
export async function seedWebsite(
  db: Database,
  slug = `venue-${randomUUID().slice(0, 8)}`,
  allTypes = true,
) {
  if (process.env.PGLITE_PATH !== "memory://" || process.env.DATABASE_URL)
    throw new Error("Website fixtures require an isolated in-memory database");
  const workspace = new WorkspaceService(db),
    website = new WebsiteService(db, workspace),
    uid = randomUUID();
  const owner: Actor = {
    uid,
    email: `${uid}@example.com`,
    name: "Preview owner",
  };
  await workspace.createOrganization(owner, {
    name: "Eden Sports Arena",
    contact_phone: "+919876543210",
    currency: "INR",
    location: {
      name: "Main location",
      address_line_1: "Sports Avenue",
      address_line_2: null,
      city: "Kochi",
      state_code: "KL",
      country_code: "IN",
      postal_code: "682001",
      timezone: "Asia/Kolkata",
    },
  });
  const initial = await workspace.workspace(owner),
    ids: string[] = [];
  for (const type of allTypes
    ? ["turf", "badminton", "pool", "tennis", "basketball", "hall"]
    : ["badminton"]) {
    const kind = ["badminton", "tennis", "basketball"].includes(type)
      ? "court"
      : type;
    const mapping = new Map<string, string>();
    const copy = (v: any): any => {
      if (typeof v === "string" && /^[a-f0-9-]{36}$/.test(v)) {
        if (!mapping.has(v)) mapping.set(v, randomUUID());
        return mapping.get(v);
      }
      if (Array.isArray(v)) return v.map(copy);
      if (v && typeof v === "object")
        return Object.fromEntries(
          Object.entries(v).map(([k, x]) => [k, copy(x)]),
        );
      return v;
    };
    const config = copy(
      JSON.parse(readFileSync(`examples/${kind}-configuration.json`, "utf8"))
        .configuration,
    );
    if (type === "turf")
      for (const offering of config.offerings) {
        const layout = config.layouts.find(
            (l: any) => l.id === offering.layout_id,
          ),
          price = layout.section_ids.length > 1 ? 160000 : 90000;
        for (const rate of offering.rates) rate.price_minor = price;
        offering.pricing_rules = [
          {
            id: randomUUID(),
            days: [1, 2, 3, 4, 5, 6, 7],
            starts_at: "06:00",
            ends_at: config.operating.closes_at,
            rates: offering.rates.map((r: any) => ({
              ...r,
              price_minor: price,
            })),
          },
        ];
      }
    const name = (
      {
        turf: "Turf",
        badminton: "Badminton",
        pool: "Swimming pool",
        tennis: "Tennis",
        basketball: "Basketball",
        hall: "Party hall",
      } as Record<string, string>
    )[type];
    const business = await workspace.createBusiness(owner, {
      name,
      type,
      location_id: initial.locations[0].id,
    });
    ids.push(business.id);
    const service =
      kind === "court"
        ? new CourtService(db, workspace)
        : kind === "turf"
          ? new TurfService(db, workspace)
          : kind === "pool"
            ? new PoolService(db, workspace)
            : new HallService(db, workspace);
    await service.configure(owner, business.id, {
      version: 1,
      configuration: config,
    });
    await workspace.activate(owner, business.id);
  }
  const draft = await website.settings(owner);
  const saved = await website.save(owner, {
    version: draft.version,
    slug,
    title: "Eden Sports Arena",
    description:
      "Your space. Your sport. Your time. Book directly with Eden Sports Arena.",
    contact_phone: "+919876543210",
    instructions:
      "Please arrive 10 minutes before your booking. Bring your booking reference and pay at the venue.",
    cancellation_policy:
      "Contact the venue for cancellations or changes to your reservation.",
    publish_logo: false,
    notice_minutes: 0,
    advance_days: 30,
    business_ids: ids,
  });
  await website.publication(owner, "published", { version: saved.version });
  return {
    workspace,
    website,
    owner,
    ids,
    slug,
    orgId: initial.organization!.id,
  };
}
