import "reflect-metadata";
import { before, after, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { addDate } from "../src/bookings/booking.inventory";
import { seedWebsite } from "../scripts/website-fixtures";

delete process.env.DATABASE_URL;
delete process.env.DATABASE_MIGRATE;
delete process.env.BOOKING_WEBSITE_URL;
process.env.BOOKING_WEBSITE_DOMAIN = "bookingos.online";
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database();
const png =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jXioAAAAASUVORK5CYII=";
let f: Awaited<ReturnType<typeof seedWebsite>>;
before(async () => {
  await db.onModuleInit();
  f = await seedWebsite(db, "design-site");
});
after(() => db.onModuleDestroy());
const settings = () => f.website.settings(f.owner);
const form = (s: any, extra: Record<string, unknown> = {}) => ({
  version: s.version,
  slug: s.slug,
  title: s.title,
  description: s.description,
  contact_phone: s.contact_phone,
  instructions: s.instructions,
  cancellation_policy: s.cancellation_policy,
  publish_logo: s.publish_logo,
  notice_minutes: s.notice_minutes,
  advance_days: s.advance_days,
  business_ids: s.businesses
    .filter((b: any) => b.enabled)
    .map((b: any) => b.id),
  ...extra,
});

test("each website is addressed by its own subdomain", async () => {
  const s = await settings();
  assert.equal(s.url, "https://design-site.bookingos.online");
  assert.equal(s.domain, "bookingos.online");
  const preview = new URL((await f.website.preview(f.owner)).url);
  assert.equal(preview.host, "design-site.bookingos.online");
  assert.match(preview.searchParams.get("preview")!, /^[a-f0-9]{64}$/);
});

test("addresses must be free, unreserved DNS labels", async () => {
  // A new organisation gets a private draft whose address can still change.
  const owner = {
    uid: randomUUID(),
    email: "draft@example.com",
    name: "Draft",
  };
  await f.workspace.createOrganization(owner, {
    name: "Draft Venue",
    contact_phone: "+919876543211",
    currency: "INR",
    location: {
      name: "Main",
      address_line_1: "Road",
      address_line_2: null,
      city: "Kochi",
      state_code: "KL",
      country_code: "IN",
      postal_code: "682001",
      timezone: "Asia/Kolkata",
    },
  });
  const s = await f.website.settings(owner);
  assert.equal(s.status, "draft");
  assert.ok(s.slug.length <= 63);
  await assert.rejects(
    () => f.website.save(owner, form(s, { slug: "design-site" })),
    /already taken/,
  );
  await assert.rejects(
    () => f.website.save(owner, form(s, { slug: "www" })),
    /reserved/,
  );
  await assert.rejects(
    () => f.website.save(owner, form(s, { slug: "a".repeat(64) })),
    /63/,
  );
  const saved = await f.website.save(owner, form(s, { slug: "draft-venue" }));
  assert.equal(saved.url, "https://draft-venue.bookingos.online");
});

test("hero heading, social links and card descriptions are public; omitted fields are kept", async () => {
  let s = await settings();
  const turf = s.businesses.find((b: any) => b.type === "turf")!;
  s = await f.website.save(
    f.owner,
    form(s, {
      hero_heading: "Play under the lights",
      social_links: {
        instagram: "https://instagram.com/eden",
        youtube: "",
      },
      card_descriptions: { [turf.id]: "Floodlit 7-a-side turf." },
    }),
  );
  await assert.rejects(
    () =>
      f.website.save(
        f.owner,
        form(s, { social_links: { facebook: "javascript:alert(1)" } }),
      ),
    /https/,
  );
  // An older app that does not send the new fields keeps the saved design.
  s = await f.website.save(f.owner, form(s));
  const site = await f.website.catalog(f.slug);
  assert.equal(site.hero_heading, "Play under the lights");
  assert.deepEqual(site.social_links, {
    instagram: "https://instagram.com/eden",
  });
  assert.equal(
    site.businesses.find((b: any) => b.id === turf.id)!.description,
    "Floodlit 7-a-side turf.",
  );
});

test("hidden spaces disappear and per-space rules override the site defaults", async () => {
  let s = await settings();
  const court = s.businesses.find((b: any) => b.type === "badminton")!;
  const [first, second] = court.resources;
  assert.ok(first && second, "fixture needs two courts");
  s = await f.website.save(
    f.owner,
    form(s, {
      spaces: [
        {
          business_id: court.id,
          resource_id: first.id,
          visible: false,
          notice_minutes: null,
          advance_days: null,
          rules: "",
        },
        {
          business_id: court.id,
          resource_id: second.id,
          visible: true,
          notice_minutes: 120,
          advance_days: 3,
          rules: "Non-marking shoes only.",
        },
      ],
    }),
  );
  const projected = s.businesses.find((b: any) => b.id === court.id)!;
  assert.equal(projected.resources[0].visible, false);
  assert.equal(projected.resources[1].advance_days, 3);
  const site = await f.website.catalog(f.slug);
  const business = site.businesses.find((b: any) => b.id === court.id)!;
  assert.ok(!business.resources.some((r: any) => r.id === first.id));
  const shown = business.resources.find((r: any) => r.id === second.id)!;
  assert.equal(shown.notice_minutes, 120);
  assert.equal(shown.advance_days, 3);
  assert.equal(shown.rules, "Non-marking shoes only.");
  const selection = (resource: any, days: number) => ({
    business_id: court.id,
    resource_id: resource.id,
    option_id: resource.options?.[0]?.id ?? shown.options[0].id,
    date: addDate(business.today, days),
    time: "10:00",
    duration_minutes: shown.options[0].default_duration,
    people: 1,
  });
  await assert.rejects(
    () => f.website.quote(f.slug, { selection: selection(first, 1) }),
    /Only normal bookings/,
  );
  await assert.rejects(
    () => f.website.quote(f.slug, { selection: selection(shown, 5) }),
    /booking window/,
  );
  const quote = await f.website.quote(f.slug, {
    selection: selection(shown, 2),
  });
  assert.ok(quote.quote_token);
  await assert.rejects(
    () =>
      f.website.save(
        f.owner,
        form(s, {
          spaces: [
            {
              business_id: court.id,
              resource_id: "not-a-space",
              visible: true,
              notice_minutes: null,
              advance_days: null,
              rules: "",
            },
          ],
        }),
      ),
    /normal booking spaces/,
  );
});

test("website logo and service card photos replace their single slot", async () => {
  let s = await settings();
  const pool = s.businesses.find((b: any) => b.type === "pool")!;
  s = await f.website.uploadImage(f.owner, {
    version: s.version,
    kind: "logo",
    content_type: "image/png",
    base64: png,
  });
  const logo = s.images.find((i: any) => i.kind === "logo")!;
  s = await f.website.uploadImage(f.owner, {
    version: s.version,
    kind: "logo",
    content_type: "image/png",
    base64: png,
  });
  assert.equal(s.images.filter((i: any) => i.kind === "logo").length, 1);
  assert.notEqual(s.images.find((i: any) => i.kind === "logo")!.id, logo.id);
  const site = await f.website.catalog(f.slug);
  assert.equal(site.has_logo, true);
  assert.equal((await f.website.logo(f.slug)).content_type, "image/png");
  s = await f.website.uploadImage(f.owner, {
    version: s.version,
    kind: "card",
    business_id: pool.id,
    content_type: "image/png",
    base64: png,
  });
  const card = s.images.find((i: any) => i.kind === "card")!;
  assert.equal(card.business_id, pool.id);
  const catalog = await f.website.catalog(f.slug);
  assert.equal(
    catalog.businesses.find((b: any) => b.id === pool.id)!.card_image,
    card.id,
  );
  assert.equal(
    (await f.website.image(f.slug, card.id)).content_type,
    "image/png",
  );
  assert.throws(
    () =>
      // A card photo belongs to a business, not to a single space.
      require("../src/website/website.images").websiteImageSchema.parse({
        version: 1,
        kind: "card",
        content_type: "image/png",
        base64: png,
      }),
    /business/,
  );
});
