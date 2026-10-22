import "reflect-metadata";
import { before, after, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { seedWebsite } from "../scripts/website-fixtures";
import {
  websiteImage,
  websiteImageSchema,
} from "../src/website/website.images";

delete process.env.DATABASE_URL;
delete process.env.DATABASE_MIGRATE;
process.env.BOOKING_WEBSITE_URL = "http://localhost:3000";
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database();
const png =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jXioAAAAASUVORK5CYII=";
const photo = { kind: "hero", content_type: "image/png", base64: png } as const;
let f: Awaited<ReturnType<typeof seedWebsite>>;
before(async () => {
  await db.onModuleInit();
  f = await seedWebsite(db, "photo-site", false);
});
after(() => db.onModuleDestroy());
const settings = () => f.website.settings(f.owner);
test("hero replacement uses owner access, versioning and publication-aware serving", async () => {
  const old = await settings();
  const first = await f.website.uploadImage(f.owner, {
    ...photo,
    version: old.version,
  });
  const id = first.images[0].id;
  assert.equal(first.version, old.version + 1);
  assert.equal((await f.website.catalog(f.slug)).hero_image, id);
  assert.equal((await f.website.image(f.slug, id)).content_type, "image/png");
  assert.deepEqual(
    Buffer.from((await f.website.ownerImage(f.owner, id)).data),
    Buffer.from(png, "base64"),
  );
  await assert.rejects(
    () => f.website.uploadImage(f.owner, { ...photo, version: old.version }),
    /Reload/,
  );
  const replaced = await f.website.uploadImage(f.owner, {
    ...photo,
    version: first.version,
  });
  assert.notEqual(replaced.images[0].id, id);
  await assert.rejects(() => f.website.image(f.slug, id), /not found/);
  const hidden = await f.website.publication(f.owner, "unpublished", {
    version: replaced.version,
  });
  await assert.rejects(
    () => f.website.image(f.slug, replaced.images[0].id),
    /not available/,
  );
  const preview = new URL(
    (await f.website.preview(f.owner)).url,
  ).searchParams.get("preview")!;
  assert.equal(
    (await f.website.image(f.slug, replaced.images[0].id, preview))
      .content_type,
    "image/png",
  );
  const removed = await f.website.removeImage(f.owner, replaced.images[0].id, {
    version: hidden.version,
  });
  await assert.rejects(
    () => f.website.catalog(f.slug, preview),
    /not available/,
  );
  await f.website.publication(f.owner, "published", {
    version: removed.version,
  });
});
test("space photos stay within their organisation, enabled business and normal resource", async () => {
  const other = await seedWebsite(db, "other-photo-site", false);
  let own = await settings();
  const business = own.businesses[0],
    resource = business.resources[0];
  const input = {
    ...photo,
    kind: "space",
    business_id: business.id,
    resource_id: resource.id,
  };
  own = await f.website.uploadImage(f.owner, {
    ...input,
    version: own.version,
  });
  const id = own.images.find((i: any) => i.kind === "space")!.id;
  const catalog = await f.website.catalog(f.slug);
  assert.deepEqual(catalog.businesses[0].resources[0].images, [id]);
  await assert.rejects(
    () => other.website.ownerImage(other.owner, id),
    /not found/,
  );
  await assert.rejects(() => other.website.image(other.slug, id), /not found/);
  const otherSettings = await other.website.settings(other.owner);
  await assert.rejects(
    () =>
      other.website.uploadImage(other.owner, {
        ...input,
        version: otherSettings.version,
      }),
    /organisation/,
  );
  await assert.rejects(
    () =>
      f.website.uploadImage(f.owner, {
        ...input,
        resource_id: randomUUID(),
        version: own.version,
      }),
    /normal booking space/,
  );
  await db.query(
    "DELETE FROM booking_website_businesses WHERE business_id=$1",
    [business.id],
  );
  assert.equal((await f.website.catalog(f.slug)).businesses.length, 0);
  await assert.rejects(() => f.website.image(f.slug, id), /not found/);
  await db.query(
    "INSERT INTO booking_website_businesses(website_id,organization_id,business_id,display_order) VALUES($1,$2,$3,0)",
    [own.id, f.orgId, business.id],
  );
  await db.query("UPDATE memberships SET role='staff' WHERE user_id=$1", [
    other.owner.uid,
  ]);
  await assert.rejects(
    () =>
      other.website.uploadImage(other.owner, {
        ...photo,
        version: own.version,
      }),
    /Only the owner/,
  );
  await assert.rejects(
    () => other.website.removeImage(other.owner, id, { version: own.version }),
    /Only the owner/,
  );
});
test("gallery limit and deletion preserve order and reject concurrent stale writes", async () => {
  let own = await settings();
  const business = own.businesses[0],
    resource = business.resources[0];
  const input = {
    ...photo,
    kind: "space",
    business_id: business.id,
    resource_id: resource.id,
  };
  for (let n = 0; n < 3; n++)
    own = await f.website.uploadImage(f.owner, {
      ...input,
      version: own.version,
    });
  const gallery = own.images.filter((i: any) => i.kind === "space");
  assert.deepEqual(
    gallery.map((i: any) => i.position),
    [0, 1, 2, 3],
  );
  await assert.rejects(
    () => f.website.uploadImage(f.owner, { ...input, version: own.version }),
    /up to 4/,
  );
  const current = own.version;
  const outcomes = await Promise.allSettled([
    f.website.removeImage(f.owner, gallery[1].id, { version: current }),
    f.website.removeImage(f.owner, gallery[2].id, { version: current }),
  ]);
  assert.equal(outcomes.filter((r) => r.status === "fulfilled").length, 1);
  own = await settings();
  own = await f.website.uploadImage(f.owner, {
    ...input,
    version: own.version,
  });
  assert.equal(own.images.filter((i: any) => i.kind === "space").length, 4);
  assert.deepEqual(
    (await f.website.catalog(f.slug)).businesses[0].resources[0].images,
    own.images.filter((i: any) => i.kind === "space").map((i: any) => i.id),
  );
});
test("image input rejects active content, mismatched file types, oversized pixels and malformed JPEGs", () => {
  assert.throws(() =>
    websiteImageSchema.parse({
      ...photo,
      version: 1,
      content_type: "image/svg+xml",
    }),
  );
  assert.throws(() =>
    websiteImageSchema.parse({ ...photo, version: 1, base64: "<html>" }),
  );
  assert.throws(
    () => websiteImage({ ...photo, version: 1, content_type: "image/jpeg" }),
    /valid/,
  );
  assert.throws(
    () =>
      websiteImage({
        ...photo,
        version: 1,
        base64: Buffer.alloc(1024 * 1024 + 1).toString("base64"),
      }),
    /up to 1 MB/,
  );
  const huge = Buffer.from(png, "base64");
  huge.writeUInt32BE(100000, 16);
  assert.throws(
    () =>
      websiteImage({ ...photo, version: 1, base64: huge.toString("base64") }),
    /megapixels/,
  );
  assert.throws(
    () =>
      websiteImage({
        ...photo,
        version: 1,
        content_type: "image/jpeg",
        base64: Buffer.alloc(32, 255).toString("base64"),
      }),
    /valid/,
  );
});
