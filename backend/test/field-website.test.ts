import "reflect-metadata";
import { before, after, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import {
  HttpException,
  ForbiddenException,
  NotFoundException,
  ConflictException,
} from "@nestjs/common";
import { ZodError } from "zod";
import { Database } from "../src/common/database";
import { AccountsService } from "../src/accounts/accounts.service";
import { seedWebsite } from "../scripts/website-fixtures";
import {
  websiteSlug,
  websiteSubdomain,
  websiteSettingsSchema,
  websiteSpaceSchema,
} from "../src/website/website.validation";
import {
  websiteImage,
  websiteImageSchema,
} from "../src/website/website.images";
import {
  upiId,
  paymentPercentages,
  paymentSubmissionSchema,
  paymentPolicy,
} from "../src/website/website.payments";

delete process.env.DATABASE_URL;
delete process.env.DATABASE_MIGRATE;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
process.env.BOOKING_WEBSITE_URL = "http://localhost:3000";
const db = new Database();
type Site = Awaited<ReturnType<typeof seedWebsite>>;
let seq = 0;
const slugOf = () => `field-${Date.now().toString(36)}-${seq++}`;
const png =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jXioAAAAASUVORK5CYII=";
const isClientError = (e: unknown) =>
  e instanceof ZodError ||
  (e instanceof HttpException && e.getStatus() < 500) ||
  (e as any)?.code === "23505";
const status = (e: unknown) =>
  e instanceof ZodError
    ? 422
    : e instanceof HttpException
      ? e.getStatus()
      : 500;
async function client(fn: () => Promise<unknown>, label = "") {
  try {
    await fn();
  } catch (e) {
    assert.ok(
      isClientError(e),
      `${label}: expected a client error, got ${(e as Error)?.constructor?.name}: ${(e as Error)?.message}`,
    );
    return e as Error;
  }
  assert.fail(`${label}: should have been rejected`);
}
const site = (allTypes = false) => seedWebsite(db, slugOf(), allTypes);
/** A full, valid save payload derived from the current settings. */
const form = (s: any, over: Record<string, unknown> = {}) => ({
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
  ...over,
});
const save = async (f: Site, over: Record<string, unknown> = {}) =>
  f.website.save(f.owner, form(await f.website.settings(f.owner), over));
const rejectSave = async (
  f: Site,
  over: Record<string, unknown>,
  label: string,
) => client(() => save(f, over), label);
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());

// ------------------------------------------------------------------ slug
test("slug: schema accepts only 3-80 char lowercase words with single hyphens and refuses reserved words", () => {
  for (const v of [
    "abc",
    "a1b",
    "my-site",
    "a-b-c-d",
    "x".repeat(80),
    "123",
    "site-2032",
    "  padded-slug  ",
    "abc\n",
  ])
    assert.ok(websiteSlug.safeParse(v).success, v);
  for (const v of [
    "",
    " ",
    "a",
    "ab",
    "x".repeat(81),
    "ABC",
    "Abc-def",
    "a--b",
    "-ab",
    "ab-",
    "a b",
    "a_b",
    "a.b",
    "a/b",
    "../x",
    "é-site",
    "café",
    "李雷李",
    "😀😀😀",
    "abc'; DROP TABLE booking_websites;--",
    "a\u0000b",
    "admin",
    "api",
    "www",
    "bookingos",
    "book",
    "_next",
    "ADMIN",
    null,
    undefined,
    5,
    {},
    [],
  ])
    assert.equal(websiteSlug.safeParse(v).success, false, JSON.stringify(v));
  // subdomain form must also be a DNS label (<=63)
  assert.ok(websiteSubdomain.safeParse("x".repeat(63)).success);
  assert.equal(websiteSubdomain.safeParse("x".repeat(64)).success, false);
  assert.equal(websiteSubdomain.safeParse("x".repeat(80)).success, false);
});
test("slug on save: bad values are 422, taken is 409, unchanged legacy slugs and overlong DNS labels behave", async () => {
  const f = await site(),
    other = await site();
  for (const slug of [
    "",
    "ab",
    "ADMIN",
    "a--b",
    "x".repeat(81),
    "x".repeat(64),
    "x".repeat(70),
    "😀😀😀",
    "a b c",
    "'; --",
    null,
    5,
  ])
    assert.equal(
      status(await rejectSave(f, { slug }, `slug=${slug}`)),
      422,
      `slug=${slug}`,
    );
  const taken = (await other.website.settings(other.owner)).slug;
  assert.ok(
    (await rejectSave(f, { slug: taken }, "taken")) instanceof
      ConflictException,
  );
  const s = await f.website.settings(f.owner);
  const renamed = `renamed-${seq++}`;
  const out = await f.website.save(f.owner, form(s, { slug: renamed }));
  assert.equal(out.slug, renamed);
  assert.equal(out.version, s.version + 1);
  assert.ok((await f.website.catalog(renamed)).slug === renamed);
  assert.ok(
    (await client(() => f.website.catalog(s.slug))) instanceof
      NotFoundException,
  );
  // the freed address can be claimed by someone else
  const out2 = await other.website.save(
    other.owner,
    form(await other.website.settings(other.owner), { slug: s.slug }),
  );
  assert.equal(out2.slug, s.slug);
  // case/whitespace: padded input is trimmed, never stored raw
  const trimmed = `  Trim-${seq++}`.toLowerCase();
  const out3 = await f.website.save(
    f.owner,
    form(await f.website.settings(f.owner), { slug: trimmed }),
  );
  assert.equal(out3.slug, trimmed.trim());
});
test("public routes validate the slug before touching the database", async () => {
  const f = await site();
  for (const slug of [
    "",
    " ",
    "ADMIN",
    "a b",
    "'; DROP TABLE booking_websites;--",
    "😀😀😀",
    "x".repeat(200),
    "../../etc",
    "%00",
    "a\u0000b",
  ])
    for (const call of [
      () => f.website.catalog(slug),
      () => f.website.logo(slug),
      () => f.website.paymentQr(slug),
      () => f.website.availability(slug, {}),
      () => f.website.quote(slug, {}),
      () => f.website.book(slug, {}),
    ])
      await client(call, `slug=${JSON.stringify(slug)}`);
  assert.ok(
    (await client(() =>
      f.website.catalog("does-not-exist-anywhere"),
    )) instanceof NotFoundException,
  );
});

// --------------------------------------------------------------- text fields
test("title / description / instructions / cancellation_policy / hero_heading boundaries", async () => {
  const f = await site();
  const cases: [string, number, number][] = [
    ["title", 2, 120],
    ["description", 0, 1200],
    ["instructions", 0, 2000],
    ["cancellation_policy", 0, 2000],
    ["hero_heading", 0, 120],
  ];
  for (const [field, min, max] of cases) {
    for (const v of [null, 5, {}, [], max + 1 >= 0 ? "x".repeat(max + 1) : ""])
      await rejectSave(f, { [field]: v }, `${field}=${String(v).slice(0, 8)}`);
    if (min > 0)
      for (const v of ["", " ", "\n\t", "a", " a "])
        await rejectSave(f, { [field]: v }, `${field}=${JSON.stringify(v)}`);
    for (const v of ["x".repeat(max), "ab", "  trimmed  "]) {
      const out: any = await save(f, { [field]: v });
      assert.equal(out[field], v.trim(), field);
    }
    for (const v of [
      "李雷 café 🎉",
      "<script>alert(1)</script>",
      "'; DROP TABLE booking_websites;--",
      "line1\nline2",
      "100% _wild_ \\ back",
    ]) {
      const out: any = await save(f, { [field]: v });
      assert.equal(out[field], v, `${field} round-trip`);
    }
    if (min === 0)
      assert.equal(
        ((await save(f, { [field]: "   " })) as any)[field],
        "",
        `${field} whitespace-only becomes empty`,
      );
  }
  // the public catalog returns the stored text verbatim for the client to escape
  const cat = await f.website.catalog((await f.website.settings(f.owner)).slug);
  assert.equal(typeof cat.title, "string");
});
test("contact_phone follows the customer phone rules", async () => {
  const f = await site();
  for (const v of [
    "",
    " ",
    "123456",
    "abc",
    "++9198765",
    "1".repeat(26),
    "1234567890123456",
    null,
    5,
    "😀😀😀😀😀😀😀",
    "98765'; --",
  ])
    await rejectSave(f, { contact_phone: v }, `phone=${v}`);
  for (const v of [
    "1234567",
    "+91 98765-43210",
    "(080) 2345 6789",
    "123456789012345",
  ])
    assert.equal(
      ((await save(f, { contact_phone: v })) as any).contact_phone,
      v,
    );
});
test("notice_minutes / advance_days / publish_logo / version are strict integers and booleans", async () => {
  const f = await site();
  for (const v of [-1, 10081, 1.5, "5", null, Number.NaN, Infinity, 1e9, {}])
    await rejectSave(f, { notice_minutes: v }, `notice=${v}`);
  for (const v of [0, 1, 10080])
    assert.equal(
      ((await save(f, { notice_minutes: v })) as any).notice_minutes,
      v,
    );
  for (const v of [0, 366, -1, 1.5, "30", null, Number.NaN, 1e9])
    await rejectSave(f, { advance_days: v }, `advance=${v}`);
  for (const v of [1, 365])
    assert.equal(((await save(f, { advance_days: v })) as any).advance_days, v);
  for (const v of ["true", 1, 0, null, "", {}])
    await rejectSave(f, { publish_logo: v }, `logo=${v}`);
  for (const v of [true, false])
    assert.equal(((await save(f, { publish_logo: v })) as any).publish_logo, v);
  const s = await f.website.settings(f.owner);
  for (const v of [0, -1, 1.5, "1", null, undefined, Number.NaN])
    await client(
      () => f.website.save(f.owner, form(s, { version: v })),
      `version=${v}`,
    );
  assert.ok(
    (await client(() =>
      f.website.save(f.owner, form(s, { version: s.version + 1 })),
    )) instanceof ConflictException,
  );
  assert.ok(
    (await client(() =>
      f.website.save(f.owner, form(s, { version: s.version - 1 })),
    )) instanceof ConflictException,
  );
  // two saves with the same stale version: exactly one wins
  const fresh = await f.website.settings(f.owner);
  const race = await Promise.allSettled(
    [1, 2, 3].map((n) =>
      f.website.save(f.owner, form(fresh, { title: `Racer ${n}` })),
    ),
  );
  assert.equal(race.filter((r) => r.status === "fulfilled").length, 1);
  await client(() =>
    f.website.save(f.owner, { ...form(fresh), extra: 1 } as any),
  );
  for (const body of [null, undefined, "x", [], 5])
    await client(() => f.website.save(f.owner, body), String(body));
});
test("social_links: only https links on known networks, no credentials, empty clears, omitted keeps", async () => {
  const f = await site();
  const bad: Record<string, unknown>[] = [
    { instagram: "http://instagram.com/x" },
    { instagram: "javascript:alert(1)" },
    { instagram: "ftp://x.com" },
    { instagram: "//instagram.com/x" },
    { instagram: "instagram.com/x" },
    { instagram: "https://user:pass@instagram.com/x" },
    { instagram: "https://user@instagram.com/x" },
    { instagram: "https://" + "a".repeat(300) + ".com" },
    { instagram: "data:text/html,<script>" },
    { instagram: "file:///etc/passwd" },
    { instagram: 5 },
    { instagram: null },
    { tiktok: "https://tiktok.com/x" },
    { constructor: "https://x.com" },
  ];
  for (const social_links of bad)
    await rejectSave(
      f,
      { social_links },
      JSON.stringify(social_links).slice(0, 50),
    );
  for (const social_links of [null, "x", [], 5])
    await rejectSave(f, { social_links }, String(social_links));
  const ok: any = await save(f, {
    social_links: {
      instagram: "https://instagram.com/ok",
      x: "https://x.com/ok",
      whatsapp: "https://wa.me/919876543210",
    },
  });
  assert.equal(ok.social_links.instagram, "https://instagram.com/ok");
  const cleared: any = await save(f, { social_links: { instagram: "" } });
  assert.equal(cleared.social_links.instagram, undefined);
  assert.equal(
    cleared.social_links.x,
    undefined,
    "a replaced map removes unlisted networks",
  );
  const kept: any = await save(f, {
    social_links: { x: "https://x.com/kept" },
  });
  const omitted: any = await f.website.save(f.owner, form(kept));
  assert.equal(
    omitted.social_links.x,
    "https://x.com/kept",
    "omitted social_links keeps the saved ones",
  );
  const padded: any = await save(f, {
    social_links: { facebook: "  https://facebook.com/pad  " },
  });
  assert.equal(padded.social_links.facebook, "https://facebook.com/pad");
});
test("card_descriptions: keys must be uuids, values up to 300 chars", async () => {
  const f = await site();
  const s: any = await f.website.settings(f.owner);
  const id = s.businesses[0].id;
  for (const card_descriptions of [
    { abc: "x" },
    { "": "x" },
    { [id]: "x".repeat(301) },
    { [id]: null },
    { [id]: 5 },
    null,
    "x",
    [],
    { [randomUUID()]: "x", bad: "y" },
  ])
    await rejectSave(
      f,
      { card_descriptions },
      JSON.stringify(card_descriptions)?.slice(0, 50),
    );
  const ok: any = await save(f, {
    card_descriptions: { [id]: "x".repeat(300) },
  });
  assert.equal(
    ok.businesses.find((b: any) => b.id === id).card_description.length,
    300,
  );
  const emoji: any = await save(f, {
    card_descriptions: { [id]: "Court 🏸 Zoë 李" },
  });
  assert.equal(
    emoji.businesses.find((b: any) => b.id === id).card_description,
    "Court 🏸 Zoë 李",
  );
  // descriptions for businesses that are not listed are ignored, never stored for a foreign id
  const stranger = randomUUID();
  await save(f, { card_descriptions: { [stranger]: "ghost" } });
  assert.equal(
    (
      await db.query<any>(
        "SELECT count(*)::int AS n FROM booking_website_businesses WHERE business_id=$1",
        [stranger],
      )
    ).rows[0].n,
    0,
  );
});
test("business_ids: uuids, no duplicates, max 100, own organisation only, published sites keep a bookable business", async () => {
  const f = await site(),
    g = await site();
  const own: any = await f.website.settings(f.owner);
  const foreign = ((await g.website.settings(g.owner)) as any).businesses[0].id;
  for (const business_ids of [
    null,
    "x",
    [""],
    ["abc"],
    [5],
    [own.businesses[0].id, own.businesses[0].id],
    Array.from({ length: 101 }, () => randomUUID()),
  ])
    await rejectSave(
      f,
      { business_ids },
      JSON.stringify(business_ids)?.slice(0, 50),
    );
  assert.equal(
    status(
      await rejectSave(f, { business_ids: [foreign] }, "foreign business"),
    ),
    400,
  );
  assert.equal(
    status(
      await rejectSave(
        f,
        { business_ids: [own.businesses[0].id, foreign] },
        "mixed",
      ),
    ),
    400,
  );
  assert.equal(
    status(
      await rejectSave(f, { business_ids: [randomUUID()] }, "unknown business"),
    ),
    400,
  );
  assert.equal(
    status(await rejectSave(f, { business_ids: [] }, "published with nothing")),
    400,
  );
  assert.equal(
    (
      await db.query<any>(
        "SELECT count(*)::int AS n FROM booking_website_businesses WHERE business_id=$1",
        [foreign],
      )
    ).rows[0].n,
    1,
    "foreign business still belongs to its own site only",
  );
  assert.equal(
    (await g.website.catalog(((await g.website.settings(g.owner)) as any).slug))
      .businesses.length,
    1,
  );
});
test("spaces: ids, duplicates, ranges, rules length, payment fields and foreign spaces", async () => {
  const f = await site(),
    g = await site();
  const s: any = await f.website.settings(f.owner);
  const b = s.businesses[0],
    r = b.resources[0];
  const space = (over: Record<string, unknown> = {}) => ({
    business_id: b.id,
    resource_id: r.id,
    visible: true,
    notice_minutes: null,
    advance_days: null,
    rules: "",
    ...over,
  });
  for (const sp of [
    space({ business_id: "x" }),
    space({ business_id: null }),
    space({ resource_id: "" }),
    space({ resource_id: "x".repeat(101) }),
    space({ resource_id: null }),
    space({ visible: "yes" }),
    space({ visible: null }),
    space({ notice_minutes: -1 }),
    space({ notice_minutes: 10081 }),
    space({ notice_minutes: 1.5 }),
    space({ notice_minutes: "5" }),
    space({ advance_days: 0 }),
    space({ advance_days: 366 }),
    space({ advance_days: -1 }),
    space({ advance_days: 1.5 }),
    space({ rules: "x".repeat(1001) }),
    space({ rules: null }),
    space({ payment_required: "yes" }),
    space({ payment_percentages: [0] }),
    space({ payment_percentages: [101] }),
    space({ payment_percentages: [1.5] }),
    space({ payment_percentages: [-5] }),
    space({ payment_percentages: [10, 20, 30, 40] }),
    space({ payment_percentages: [50, 50] }),
    space({ payment_percentages: ["50"] }),
    { ...space(), extra: 1 },
  ])
    await rejectSave(f, { spaces: [sp] }, JSON.stringify(sp).slice(0, 80));
  await rejectSave(f, { spaces: [space(), space()] }, "duplicate space");
  await rejectSave(
    f,
    {
      spaces: Array.from({ length: 501 }, () =>
        space({ resource_id: randomUUID() }),
      ),
    },
    "501 spaces",
  );
  await rejectSave(f, { spaces: "x" }, "string spaces");
  await rejectSave(f, { spaces: null }, "null spaces");
  assert.equal(
    status(
      await rejectSave(
        f,
        { spaces: [space({ resource_id: randomUUID() })] },
        "unknown space",
      ),
    ),
    400,
  );
  assert.equal(
    status(
      await rejectSave(
        f,
        { spaces: [space({ resource_id: "not-a-space" })] },
        "non-uuid unknown space",
      ),
    ),
    400,
  );
  const foreign: any = (await g.website.settings(g.owner)) as any;
  assert.equal(
    status(
      await rejectSave(
        f,
        {
          spaces: [
            space({
              business_id: foreign.businesses[0].id,
              resource_id: foreign.businesses[0].resources[0].id,
            }),
          ],
        },
        "foreign space",
      ),
    ),
    400,
  );
  assert.equal(
    status(
      await rejectSave(
        f,
        {
          spaces: [
            space({ payment_required: true, payment_percentages: [50] }),
          ],
        },
        "payment without UPI",
      ),
    ),
    400,
  );
  assert.equal(
    status(
      await rejectSave(
        f,
        {
          spaces: [space({ payment_required: true, payment_percentages: [] })],
        },
        "payment without percentages",
      ),
    ),
    400,
  );
  // boundaries accepted
  const ok: any = await save(f, {
    spaces: [
      space({ notice_minutes: 0, advance_days: 1, rules: "x".repeat(1000) }),
    ],
  });
  const saved = ok.businesses
    .find((x: any) => x.id === b.id)
    .resources.find((x: any) => x.id === r.id);
  assert.deepEqual(
    [saved.notice_minutes, saved.advance_days, saved.rules.length],
    [0, 1, 1000],
  );
  const max: any = await save(f, {
    spaces: [space({ notice_minutes: 10080, advance_days: 365 })],
  });
  assert.equal(
    max.businesses.find((x: any) => x.id === b.id).resources[0].advance_days,
    365,
  );
  const empty: any = await save(f, { spaces: [] });
  assert.equal(
    empty.businesses.find((x: any) => x.id === b.id).resources[0].visible,
    true,
    "empty list resets overrides",
  );
});
test("owner-only access: staff, revoked and unknown members cannot read or change the website", async () => {
  const f = await site();
  const m = (
    await db.query<any>(
      "SELECT organization_id FROM memberships WHERE user_id=$1",
      [f.owner.uid],
    )
  ).rows[0];
  const staff = {
    uid: randomUUID(),
    email: `${randomUUID()}@example.com`,
    name: "Staff",
  };
  await db.query(
    "INSERT INTO memberships(id,organization_id,user_id,email,display_name,role,permissions) VALUES($1,$2,$3,$4,'Staff','staff',$5)",
    [
      randomUUID(),
      m.organization_id,
      staff.uid,
      staff.email,
      JSON.stringify(["view_bookings", "manage_bookings", "view_finance"]),
    ],
  );
  const s: any = await f.website.settings(f.owner);
  for (const call of [
    () => f.website.settings(staff),
    () => f.website.save(staff, form(s)),
    () => f.website.publication(staff, "unpublished", { version: s.version }),
    () => f.website.preview(staff),
    () =>
      f.website.uploadImage(staff, {
        version: s.version,
        kind: "hero",
        content_type: "image/png",
        base64: png,
      }),
    () => f.website.removeImage(staff, randomUUID(), { version: s.version }),
    () => f.website.ownerImage(staff, randomUUID()),
  ])
    assert.ok((await client(call)) instanceof ForbiddenException);
  assert.equal((await f.website.link(staff)).can_manage, false);
  const stranger = { uid: randomUUID(), email: "s@example.com", name: "S" };
  for (const call of [
    () => f.website.link(stranger),
    () => f.website.settings(stranger),
  ])
    assert.ok((await client(call)) instanceof ForbiddenException);
  assert.equal(
    ((await f.website.settings(f.owner)) as any).version,
    s.version,
    "denied calls changed nothing",
  );
});

// -------------------------------------------------------------- publication
test("publication transitions: version, body shape, preconditions and idempotent repeats", async () => {
  const f = await site(false);
  const s: any = await f.website.settings(f.owner);
  for (const body of [
    {},
    { version: 0 },
    { version: -1 },
    { version: 1.5 },
    { version: "1" },
    { version: null },
    { version: s.version, extra: 1 },
    null,
    undefined,
    "x",
    [],
  ])
    for (const status of ["published", "paused", "unpublished"] as const)
      await client(
        () => f.website.publication(f.owner, status, body),
        `${status} ${JSON.stringify(body)}`,
      );
  assert.ok(
    (await client(() =>
      f.website.publication(f.owner, "paused", { version: s.version + 3 }),
    )) instanceof ConflictException,
  );
  const paused: any = await f.website.publication(f.owner, "paused", {
    version: s.version,
  });
  assert.equal(paused.status, "paused");
  const again: any = await f.website.publication(f.owner, "paused", {
    version: paused.version,
  });
  assert.equal(again.status, "paused");
  assert.equal(
    again.version,
    paused.version + 1,
    "every transition bumps the version",
  );
  const off: any = await f.website.publication(f.owner, "unpublished", {
    version: again.version,
  });
  // publish needs at least one active business with normal options
  const emptySite = await site(false);
  const es: any = await emptySite.website.settings(emptySite.owner);
  const stripped: any = await emptySite.website.publication(
    emptySite.owner,
    "unpublished",
    { version: es.version },
  );
  await db.query("DELETE FROM booking_website_businesses WHERE website_id=$1", [
    stripped.id,
  ]);
  assert.equal(
    status(
      await client(() =>
        emptySite.website.publication(emptySite.owner, "published", {
          version: stripped.version,
        }),
      ),
    ),
    400,
  );
  const pub: any = await f.website.publication(f.owner, "published", {
    version: off.version,
  });
  assert.equal(pub.status, "published");
  assert.ok(pub.first_published_at);
  const firstAt = pub.first_published_at;
  const p2: any = await f.website.publication(f.owner, "unpublished", {
    version: pub.version,
  });
  const p3: any = await f.website.publication(f.owner, "published", {
    version: p2.version,
  });
  assert.equal(
    new Date(p3.first_published_at).getTime(),
    new Date(firstAt).getTime(),
    "first_published_at is never overwritten",
  );
  // parallel publish with the same version: one winner
  const cur: any = await f.website.settings(f.owner);
  const race = await Promise.allSettled(
    [1, 2, 3].map(() =>
      f.website.publication(f.owner, "paused", { version: cur.version }),
    ),
  );
  assert.equal(race.filter((r) => r.status === "fulfilled").length, 1);
});
test("preview tokens: format, expiry, ownership and the public query parameter", async () => {
  const f = await site(),
    g = await site();
  const slug = ((await f.website.settings(f.owner)) as any).slug;
  const gslug = ((await g.website.settings(g.owner)) as any).slug;
  const token = new URL(
    (await f.website.preview(f.owner)).url,
  ).searchParams.get("preview")!;
  assert.match(token, /^[a-f0-9]{64}$/);
  assert.equal((await f.website.catalog(slug, token)).is_preview, true);
  for (const bad of [
    " ",
    "x",
    token.slice(1),
    token + "0",
    token.toUpperCase(),
    "g".repeat(64),
    "0".repeat(64),
    "'; --",
    "😀",
    `${token},${token}`,
  ]) {
    const e = await client(
      () => f.website.catalog(slug, bad),
      `preview=${bad}`,
    );
    assert.ok(
      e instanceof NotFoundException || status(e) === 404,
      `preview=${bad}`,
    );
  }
  assert.ok(
    (await client(() => g.website.catalog(gslug, token))) instanceof
      NotFoundException,
    "token of another site",
  );
  // expiry
  await db.query(
    "UPDATE booking_websites SET preview_expires_at=now()-interval '1 second' WHERE slug=$1",
    [slug],
  );
  await client(() => f.website.catalog(slug, token), "expired preview");
  const token2 = new URL(
    (await f.website.preview(f.owner)).url,
  ).searchParams.get("preview")!;
  assert.notEqual(token2, token, "each preview issues a fresh token");
  await client(
    () => f.website.catalog(slug, token),
    "old token after re-issue",
  );
  assert.equal((await f.website.catalog(slug, token2)).is_preview, true);
  // saving settings revokes outstanding preview links
  await save(f, { title: "Edited after preview" });
  await client(() => f.website.catalog(slug, token2), "preview after save");
  // an unpublished (draft) site is only visible through a valid preview token
  const s: any = await f.website.settings(f.owner);
  await f.website.publication(f.owner, "unpublished", { version: s.version });
  await client(() => f.website.catalog(slug), "unpublished without token");
  const t3 = new URL((await f.website.preview(f.owner)).url).searchParams.get(
    "preview",
  )!;
  assert.equal((await f.website.catalog(slug, t3)).is_preview, true);
});

// ------------------------------------------------------------------ images
const withDims = (w: number, h: number) => {
  const b = Buffer.from(png, "base64");
  b.writeUInt32BE(w, 16);
  b.writeUInt32BE(h, 20);
  return b.toString("base64");
};
const jpeg = (w: number, h: number) => {
  const b = Buffer.alloc(40, 0);
  Buffer.from([0xff, 0xd8, 0xff, 0xc0, 0x00, 0x11, 0x08]).copy(b, 0);
  b.writeUInt16BE(h, 7);
  b.writeUInt16BE(w, 9);
  Buffer.from([
    0x03, 0x01, 0x11, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
  ]).copy(b, 11);
  return b.toString("base64");
};
const webpX = (w: number, h: number) => {
  const b = Buffer.alloc(40, 0);
  b.write("RIFF", 0, "ascii");
  b.writeUInt32LE(32, 4);
  b.write("WEBPVP8X", 8, "ascii");
  b.writeUInt32LE(10, 16);
  b.writeUIntLE(w - 1, 24, 3);
  b.writeUIntLE(h - 1, 27, 3);
  return b.toString("base64");
};
test("image schema: kind/business/resource combinations, content types, version and base64 syntax", () => {
  const base = {
    version: 1,
    kind: "hero",
    content_type: "image/png",
    base64: png,
  } as any;
  const ok = (v: any) => websiteImageSchema.safeParse(v).success;
  assert.ok(ok(base));
  assert.ok(ok({ ...base, kind: "logo" }));
  assert.ok(ok({ ...base, kind: "card", business_id: randomUUID() }));
  assert.ok(
    ok({ ...base, kind: "space", business_id: randomUUID(), resource_id: "x" }),
  );
  for (const over of [
    { kind: "" },
    { kind: "banner" },
    { kind: "HERO" },
    { kind: null },
    { business_id: randomUUID() },
    { resource_id: "x" },
    { kind: "card" },
    { kind: "card", business_id: randomUUID(), resource_id: "x" },
    { kind: "space" },
    { kind: "space", business_id: randomUUID() },
    { kind: "space", resource_id: "x" },
    { kind: "space", business_id: "abc", resource_id: "x" },
    { kind: "space", business_id: randomUUID(), resource_id: "" },
    { kind: "space", business_id: randomUUID(), resource_id: "x".repeat(101) },
    { content_type: "image/gif" },
    { content_type: "image/svg+xml" },
    { content_type: "IMAGE/PNG" },
    { content_type: "image/png; charset=x" },
    { content_type: "text/html" },
    { content_type: "" },
    { content_type: null },
    { content_type: "image/jpg" },
    { version: 0 },
    { version: -1 },
    { version: 1.5 },
    { version: "1" },
    { version: null },
    { base64: "" },
    { base64: " " + png },
    { base64: png + "\n" },
    { base64: png.slice(0, -1) },
    { base64: png + "=" },
    { base64: "AAA" },
    { base64: "AA=A" },
    { base64: "@@@@" },
    { base64: "data:image/png;base64," + png },
    { base64: "<svg onload=alert(1)>" },
    { base64: null },
    { base64: 5 },
    { base64: "A".repeat(1398105) },
    { extra: 1 },
  ])
    assert.equal(
      ok({ ...base, ...over }),
      false,
      JSON.stringify(over).slice(0, 80),
    );
  assert.ok(
    ok({ ...base, base64: "A".repeat(1398104) }),
    "schema limit is inclusive",
  );
  assert.equal(ok({ ...base, base64: "A".repeat(1398104 + 1) }), false);
});
test("image bytes: dimensions, magic numbers, mismatched types and megapixel limits", () => {
  const img = (content_type: any, base64: string) =>
    ({ version: 1, kind: "hero", content_type, base64 }) as any;
  assert.ok(websiteImage(img("image/png", png)).length >= 24);
  assert.ok(websiteImage(img("image/png", withDims(8192, 1))));
  assert.ok(websiteImage(img("image/png", withDims(1, 8192))));
  assert.ok(
    websiteImage(img("image/png", withDims(6000, 4000))),
    "24,000,000 px is allowed",
  );
  for (const [w, h] of [
    [0, 1],
    [1, 0],
    [0, 0],
    [8193, 1],
    [1, 8193],
    [6000, 4001],
    [8192, 8192],
    [4294967295, 1],
    [1, 4294967295],
    [65536, 65536],
  ])
    assert.throws(
      () => websiteImage(img("image/png", withDims(w, h))),
      /megapixels|valid/,
      `${w}x${h}`,
    );
  // magic number must match the declared type
  assert.throws(() => websiteImage(img("image/jpeg", png)), /valid/);
  assert.throws(() => websiteImage(img("image/webp", png)), /valid/);
  assert.throws(() => websiteImage(img("image/png", jpeg(10, 10))), /valid/);
  assert.throws(
    () =>
      websiteImage(img("image/png", Buffer.alloc(64, 0).toString("base64"))),
    /valid/,
  );
  assert.throws(
    () =>
      websiteImage(
        img(
          "image/png",
          Buffer.from(
            "<svg xmlns='http://www.w3.org/2000/svg' onload='alert(1)'></svg>",
          ).toString("base64"),
        ),
      ),
    /valid/,
  );
  assert.throws(
    () =>
      websiteImage(
        img(
          "image/png",
          Buffer.from(
            "<html><script>alert(1)</script></html>" + " ".repeat(40),
          ).toString("base64"),
        ),
      ),
    /valid/,
  );
  assert.throws(
    () =>
      websiteImage(img("image/png", Buffer.alloc(10, 1).toString("base64"))),
    /1 MB|valid/,
    "shorter than the 24 byte floor",
  );
  assert.throws(
    () =>
      websiteImage(
        img(
          "image/png",
          Buffer.from("iVBORw0KGgo=", "base64").toString("base64"),
        ),
      ),
    /1 MB|valid/,
  );
  // JPEG
  assert.ok(websiteImage(img("image/jpeg", jpeg(100, 100))));
  assert.ok(websiteImage(img("image/jpeg", jpeg(8192, 1))));
  for (const [w, h] of [
    [0, 10],
    [10, 0],
    [8193, 1],
    [6000, 4001],
    [65535, 65535],
  ])
    assert.throws(
      () => websiteImage(img("image/jpeg", jpeg(w, h))),
      /megapixels|valid/,
      `jpeg ${w}x${h}`,
    );
  assert.throws(
    () =>
      websiteImage(
        img("image/jpeg", Buffer.alloc(40, 0xff).toString("base64")),
      ),
    /valid/,
    "all 0xFF bytes must not hang or pass",
  );
  assert.throws(
    () =>
      websiteImage(
        img(
          "image/jpeg",
          Buffer.concat([
            Buffer.from([0xff, 0xd8]),
            Buffer.alloc(60, 0),
          ]).toString("base64"),
        ),
      ),
    /valid/,
  );
  // WebP
  assert.ok(websiteImage(img("image/webp", webpX(100, 100))));
  assert.throws(
    () => websiteImage(img("image/webp", webpX(8193, 1))),
    /megapixels|valid/,
  );
  assert.throws(
    () => websiteImage(img("image/webp", webpX(6000, 4001))),
    /megapixels|valid/,
  );
  assert.throws(
    () =>
      websiteImage(img("image/webp", Buffer.alloc(40, 0).toString("base64"))),
    /valid/,
  );
  // decoded size ceiling: exactly 1 MiB passes the size check, one byte more fails
  const exact = Buffer.alloc(1024 * 1024, 0);
  Buffer.from(png, "base64").copy(exact, 0);
  exact.writeUInt32BE(10, 16);
  exact.writeUInt32BE(10, 20);
  assert.equal(
    websiteImage(img("image/png", exact.toString("base64"))).length,
    1024 * 1024,
  );
  assert.throws(
    () =>
      websiteImage(
        img(
          "image/png",
          Buffer.concat([exact, Buffer.from([0])]).toString("base64"),
        ),
      ),
    /1 MB/,
  );
});
test(
  "a PNG whose body is not an image is accepted as long as the header is plausible",
  { todo: "BUG-17" },
  () => {
    // Only the signature and IHDR are inspected; there is no check for IDAT/IEND or trailing data,
    // so HTML/script payloads can be stored behind a valid PNG header and served from the public domain.
    const poly = Buffer.concat([
      Buffer.from(png, "base64").subarray(0, 33),
      Buffer.from("<script>alert(document.domain)</script>"),
    ]);
    assert.throws(() =>
      websiteImage({
        version: 1,
        kind: "hero",
        content_type: "image/png",
        base64: poly.toString("base64"),
      } as any),
    );
  },
);
test("image upload and removal: slots, limits, versions, foreign spaces and ids", async () => {
  const f = await site(false),
    g = await site(false);
  const s0: any = await f.website.settings(f.owner);
  const b = s0.businesses[0],
    r = b.resources[0];
  const up = async (over: Record<string, unknown> = {}) => {
    const cur: any = await f.website.settings(f.owner);
    return f.website.uploadImage(f.owner, {
      version: cur.version,
      kind: "hero",
      content_type: "image/png",
      base64: png,
      ...over,
    });
  };
  // stale version
  assert.ok(
    (await client(() =>
      f.website.uploadImage(f.owner, {
        version: s0.version + 5,
        kind: "hero",
        content_type: "image/png",
        base64: png,
      }),
    )) instanceof ConflictException,
  );
  // wrong space / foreign business
  const foreign: any = (await g.website.settings(g.owner)) as any;
  assert.equal(
    status(
      await client(() =>
        up({
          kind: "space",
          business_id: foreign.businesses[0].id,
          resource_id: foreign.businesses[0].resources[0].id,
        }),
      ),
    ),
    400,
  );
  assert.equal(
    status(
      await client(() =>
        up({ kind: "card", business_id: foreign.businesses[0].id }),
      ),
    ),
    400,
  );
  assert.equal(
    status(
      await client(() =>
        up({ kind: "space", business_id: b.id, resource_id: randomUUID() }),
      ),
    ),
    400,
  );
  assert.equal(
    status(await client(() => up({ kind: "card", business_id: randomUUID() }))),
    400,
  );
  // hero/logo/card single slot replace; space slot cap of 4
  const first: any = await up();
  const second: any = await up();
  assert.equal(second.images.filter((i: any) => i.kind === "hero").length, 1);
  assert.notEqual(
    second.images.find((i: any) => i.kind === "hero").id,
    first.images.find((i: any) => i.kind === "hero").id,
  );
  for (let n = 0; n < 4; n++)
    await up({ kind: "space", business_id: b.id, resource_id: r.id });
  assert.ok(
    /up to 4/.test(
      (
        await client(() =>
          up({ kind: "space", business_id: b.id, resource_id: r.id }),
        )
      ).message,
    ),
  );
  const other = b.resources[1];
  if (other)
    assert.ok(
      await up({ kind: "space", business_id: b.id, resource_id: other.id }),
      "another space has its own 4 slots",
    );
  // site-wide cap of 40 photos
  const h: Site = await site(false);
  const hs: any = await h.website.settings(h.owner);
  const hb = hs.businesses[0];
  for (let n = 0; n < 40; n++) {
    const res = hb.resources[n % hb.resources.length];
    const cur: any = await h.website.settings(h.owner);
    const same = cur.images.filter(
      (i: any) => i.kind === "space" && i.resource_id === res.id,
    ).length;
    if (same >= 4) break;
    await h.website.uploadImage(h.owner, {
      version: cur.version,
      kind: "space",
      business_id: hb.id,
      resource_id: res.id,
      content_type: "image/png",
      base64: png,
    });
  }
  const total = ((await h.website.settings(h.owner)) as any).images.length;
  assert.ok(total <= 40);
  // removal
  const cur: any = await f.website.settings(f.owner);
  const target = cur.images[0];
  for (const id of ["", "abc", "'; --", "😀", "../" + target.id])
    await client(
      () => f.website.removeImage(f.owner, id, { version: cur.version }),
      id,
    );
  for (const body of [
    {},
    { version: 0 },
    { version: "1" },
    { version: cur.version, extra: 1 },
    null,
    undefined,
  ])
    await client(
      () => f.website.removeImage(f.owner, target.id, body),
      JSON.stringify(body),
    );
  assert.ok(
    (await client(() =>
      f.website.removeImage(f.owner, target.id, { version: cur.version + 9 }),
    )) instanceof ConflictException,
  );
  assert.ok(
    (await client(() =>
      f.website.removeImage(f.owner, randomUUID(), { version: cur.version }),
    )) instanceof NotFoundException,
  );
  // another organisation can neither remove nor read this image
  const gs: any = await g.website.settings(g.owner);
  assert.ok(
    (await client(() =>
      g.website.removeImage(g.owner, target.id, { version: gs.version }),
    )) instanceof NotFoundException,
  );
  assert.ok(
    (await client(() => g.website.ownerImage(g.owner, target.id))) instanceof
      NotFoundException,
  );
  const removed: any = await f.website.removeImage(f.owner, target.id, {
    version: cur.version,
  });
  assert.equal(
    removed.images.some((i: any) => i.id === target.id),
    false,
  );
  assert.ok(
    (await client(() =>
      f.website.removeImage(f.owner, target.id, { version: removed.version }),
    )) instanceof NotFoundException,
    "second removal",
  );
  // owner image id validation
  for (const id of ["", "abc", "'; --"])
    await client(() => f.website.ownerImage(f.owner, id), id);
});
test("public photo, logo and payment QR endpoints: ids, preview, hidden businesses and version parameter", async () => {
  const f = await site(false);
  const s: any = await f.website.settings(f.owner);
  const slug = s.slug,
    b = s.businesses[0],
    r = b.resources[0];
  const withHero: any = await f.website.uploadImage(f.owner, {
    version: s.version,
    kind: "hero",
    content_type: "image/png",
    base64: png,
  });
  const withSpace: any = await f.website.uploadImage(f.owner, {
    version: withHero.version,
    kind: "space",
    business_id: b.id,
    resource_id: r.id,
    content_type: "image/png",
    base64: png,
  });
  const hero = withSpace.images.find((i: any) => i.kind === "hero"),
    spacePhoto = withSpace.images.find((i: any) => i.kind === "space");
  assert.equal(
    (await f.website.image(slug, hero.id)).content_type,
    "image/png",
  );
  for (const id of ["", "abc", "'; --", "😀", "../" + hero.id])
    await client(() => f.website.image(slug, id), id);
  assert.ok(
    (await client(() => f.website.image(slug, randomUUID()))) instanceof
      NotFoundException,
  );
  // a hidden space's photos disappear
  const hidden: any = await save(f, {
    spaces: [
      {
        business_id: b.id,
        resource_id: r.id,
        visible: false,
        notice_minutes: null,
        advance_days: null,
        rules: "",
      },
    ],
  });
  assert.ok(hidden);
  assert.ok(
    (await client(() => f.website.image(slug, spacePhoto.id))) instanceof
      NotFoundException,
  );
  // another site never serves this site's photo
  const g = await site(false);
  const gslug2 = ((await g.website.settings(g.owner)) as any).slug;
  assert.ok(
    (await client(() => g.website.image(gslug2, hero.id))) instanceof
      NotFoundException,
  );
  // logo: nothing uploaded and not published => 404
  assert.ok(
    (await client(() => f.website.logo(slug))) instanceof NotFoundException,
  );
  // payment QR: none configured; non-numeric and stale versions
  assert.ok(
    (await client(() => f.website.paymentQr(slug))) instanceof
      NotFoundException,
  );
  const accounts = new AccountsService(db, f.workspace);
  const saved = await accounts.saveWebsitePayments(f.owner, {
    version: 0,
    upi_id: "venue@bank",
    qr: { content_type: "image/png", base64: png },
  });
  assert.equal(
    (await f.website.paymentQr(slug, undefined, String(saved.version)))
      .content_type,
    "image/png",
  );
  assert.equal((await f.website.paymentQr(slug)).content_type, "image/png");
  for (const v of [
    "",
    "abc",
    "0",
    "-1",
    "1.0",
    "01",
    String(saved.version + 1),
    "'; --",
  ])
    assert.ok(
      (await client(
        () => f.website.paymentQr(slug, undefined, v),
        `v=${v}`,
      )) instanceof ConflictException,
      `v=${v}`,
    );
});

// ------------------------------------------------------ payment settings
test("UPI id grammar and payment percentage lists", () => {
  for (const v of [
    "",
    " ",
    "ab@bk",
    "venue@bank",
    "a.b-c_d@okaxis",
    "shop.1@ok.bank",
    "  venue@bank  ",
    "x".repeat(60) + "@" + "y".repeat(39),
  ])
    assert.ok(upiId.safeParse(v).success, JSON.stringify(v));
  for (const v of [
    "a@bank",
    "ab@b",
    "ab@@bank",
    "@bank",
    "venue@",
    "venue bank@x",
    "venue@ba nk",
    "venue",
    "venue@bank@x",
    "ve#@bank",
    "名前@bank",
    "😀😀@bank",
    "venue@銀行",
    "x".repeat(101),
    "a'b@bank",
    "ab@bank; DROP",
    null,
    5,
    {},
  ])
    assert.equal(upiId.safeParse(v).success, false, JSON.stringify(v));
  for (const v of [[], [1], [100], [25, 50, 100]])
    assert.ok(paymentPercentages.safeParse(v).success, JSON.stringify(v));
  for (const v of [
    [0],
    [101],
    [-1],
    [1.5],
    ["50"],
    [null],
    [50, 50],
    [10, 20, 30, 40],
    "50",
    null,
    {},
    [Number.NaN],
    [Infinity],
  ])
    assert.equal(
      paymentPercentages.safeParse(v).success,
      false,
      JSON.stringify(v),
    );
});
test("website UPI settings: id, QR image, version and organisation-only access", async () => {
  const f = await site(false),
    g = await site(false);
  const accounts = new AccountsService(db, f.workspace);
  for (const body of [
    {},
    { version: -1, upi_id: "" },
    { version: 0.5, upi_id: "" },
    { version: "0", upi_id: "" },
    { version: null, upi_id: "" },
    { version: 0, upi_id: "bad" },
    { version: 0, upi_id: null },
    {
      version: 0,
      upi_id: "venue@bank",
      qr: { content_type: "image/gif", base64: png },
    },
    {
      version: 0,
      upi_id: "venue@bank",
      qr: { content_type: "image/png", base64: "!!!" },
    },
    {
      version: 0,
      upi_id: "venue@bank",
      qr: { content_type: "image/png", base64: png, extra: 1 },
    },
    { version: 0, upi_id: "venue@bank", extra: 1 },
    { version: 0, upi_id: "venue@bank", qr: "x" },
    null,
  ])
    await client(
      () => accounts.saveWebsitePayments(f.owner, body),
      JSON.stringify(body)?.slice(0, 60),
    );
  const huge = withDims(9000, 9000);
  assert.equal(
    status(
      await client(() =>
        accounts.saveWebsitePayments(f.owner, {
          version: 0,
          upi_id: "venue@bank",
          qr: { content_type: "image/png", base64: huge },
        }),
      ),
    ),
    400,
  );
  assert.ok(
    (await client(() =>
      accounts.saveWebsitePayments(f.owner, {
        version: 3,
        upi_id: "venue@bank",
      }),
    )) instanceof ConflictException,
  );
  const saved = await accounts.saveWebsitePayments(f.owner, {
    version: 0,
    upi_id: "  Venue.One@Bank  ",
    qr: { content_type: "image/png", base64: png },
  });
  assert.equal(saved.upi_id, "Venue.One@Bank");
  assert.equal(saved.version, 1);
  // omitted qr keeps the stored QR; null removes it
  const kept = await accounts.saveWebsitePayments(f.owner, {
    version: 1,
    upi_id: "venue@bank",
  });
  assert.equal(kept.has_qr, true);
  const removed = await accounts.saveWebsitePayments(f.owner, {
    version: 2,
    upi_id: "venue@bank",
    qr: null,
  });
  assert.equal(removed.has_qr, false);
  // another organisation is unaffected and cannot read these settings
  const other = await accounts.websitePayments(g.owner);
  assert.deepEqual([other.upi_id, other.version, other.has_qr], ["", 0, false]);
  // concurrent saves with the same version: one winner
  const race = await Promise.allSettled(
    [1, 2, 3].map((n) =>
      accounts.saveWebsitePayments(f.owner, {
        version: 3,
        upi_id: `racer${n}@bank`,
      }),
    ),
  );
  assert.equal(race.filter((r) => r.status === "fulfilled").length, 1);
});
test("paymentPolicy and paymentSubmissionSchema numeric boundaries", () => {
  const ok = { upi_id: "v@bank", version: 1, has_qr: true };
  const p = paymentPolicy(true, [100], 1, "INR", ok);
  assert.equal(p.options[0].amount_minor, 1);
  assert.equal(
    paymentPolicy(true, [33], 100, "INR", ok).options[0].amount_minor,
    33,
  );
  assert.equal(
    paymentPolicy(true, [33], 101, "INR", ok).options[0].amount_minor,
    Math.ceil(101 * 0.33),
    "partial amounts round up",
  );
  assert.equal(
    paymentPolicy(true, [1], 1, "INR", ok).options[0].amount_minor,
    1,
    "never rounds down to zero",
  );
  assert.equal(
    paymentPolicy(true, [100], 0, "INR", ok).required,
    false,
    "free bookings need no payment",
  );
  assert.equal(
    paymentPolicy(false, [], 500, "INR", ok).options[0].percentage,
    100,
  );
  assert.equal(paymentPolicy(false, [], 500, "USD", ok).options.length, 0);
  assert.throws(() => paymentPolicy(true, [100], 500, "USD", ok));
  assert.throws(() => paymentPolicy(true, [], 500, "INR", ok));
  assert.throws(() =>
    paymentPolicy(true, [100], 500, "INR", { ...ok, has_qr: false }),
  );
  assert.throws(() =>
    paymentPolicy(true, [100], 500, "INR", { ...ok, upi_id: "" }),
  );
  const sub = (o: any) =>
    paymentSubmissionSchema.safeParse({
      percentage: 50,
      transaction_id: "ABC123",
      ...o,
    });
  for (const o of [
    { percentage: 0 },
    { percentage: 101 },
    { percentage: 1.5 },
    { percentage: "50" },
    { percentage: null },
    { transaction_id: "12345" },
    { transaction_id: "x".repeat(65) },
    { transaction_id: "" },
    { transaction_id: "      " },
    { transaction_id: "AB CD12" },
    { transaction_id: "AB#CD12" },
    { transaction_id: "ÀBCD12" },
    { transaction_id: "😀😀😀😀😀😀" },
    { transaction_id: "ABC123; DROP" },
    { transaction_id: null },
    { transaction_id: 123456 },
    { extra: 1 },
  ])
    assert.equal(sub(o).success, false, JSON.stringify(o));
  assert.equal(
    sub({ transaction_id: "  abc.123_x-y  " }).data?.transaction_id,
    "ABC.123_X-Y",
  );
  assert.ok(sub({ transaction_id: "x".repeat(64) }).success);
  assert.ok(sub({ transaction_id: "x".repeat(6) }).success);
  assert.ok(sub({ percentage: 1 }).success && sub({ percentage: 100 }).success);
});
test("websiteSettingsSchema and websiteSpaceSchema reject prototype-pollution style keys and unknown fields", () => {
  const base = {
    version: 1,
    slug: "abc-def",
    title: "Title",
    description: "",
    contact_phone: "9876543210",
    instructions: "",
    cancellation_policy: "",
    publish_logo: false,
    notice_minutes: 0,
    advance_days: 1,
    business_ids: [],
  };
  assert.ok(websiteSettingsSchema.safeParse(base).success);
  for (const extra of [
    { __proto__x: 1 },
    { constructor: 1 },
    { admin: true },
    { organization_id: randomUUID() },
    { status: "published" },
    { version2: 1 },
  ])
    assert.equal(
      websiteSettingsSchema.safeParse({ ...base, ...extra }).success,
      false,
      JSON.stringify(extra),
    );
  const parsed = websiteSettingsSchema.safeParse(
    JSON.parse(
      '{"version":1,"slug":"abc-def","title":"Title","description":"","contact_phone":"9876543210","instructions":"","cancellation_policy":"","publish_logo":false,"notice_minutes":0,"advance_days":1,"business_ids":[],"__proto__":{"admin":true}}',
    ),
  );
  assert.ok(!parsed.success || (parsed.data as any).admin === undefined);
  assert.equal(
    websiteSpaceSchema.safeParse({
      business_id: randomUUID(),
      resource_id: "r",
      visible: true,
      notice_minutes: null,
      advance_days: null,
      rules: "",
      organization_id: "x",
    }).success,
    false,
  );
});

test(
  "a NUL character (\\u0000) in any website text field must be a 4xx, never an unhandled database error",
  { todo: "BUG-14" },
  async () => {
    const f = await site();
    const nul = "bad\u0000value";
    const failures: string[] = [];
    for (const field of [
      "title",
      "description",
      "instructions",
      "cancellation_policy",
      "hero_heading",
    ]) {
      try {
        await save(f, { [field]: nul });
      } catch (e) {
        if (!isClientError(e))
          failures.push(
            `${field}: ${(e as Error).constructor.name} ${(e as Error).message}`,
          );
      }
    }
    const s: any = await f.website.settings(f.owner);
    try {
      await f.website.save(
        f.owner,
        form(s, {
          spaces: [
            {
              business_id: s.businesses[0].id,
              resource_id: s.businesses[0].resources[0].id,
              visible: true,
              notice_minutes: null,
              advance_days: null,
              rules: nul,
            },
          ],
        }),
      );
    } catch (e) {
      if (!isClientError(e))
        failures.push(
          `rules: ${(e as Error).constructor.name} ${(e as Error).message}`,
        );
    }
    assert.deepEqual(failures, []);
  },
);
