import "reflect-metadata";
import { before, after, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { BookingService } from "../src/bookings/booking.service";
import { addDate } from "../src/bookings/booking.inventory";
import { seedWebsite } from "../scripts/website-fixtures";
delete process.env.DATABASE_URL;
delete process.env.DATABASE_MIGRATE;
process.env.BOOKING_WEBSITE_URL = "http://localhost:3000";
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database();
let f: Awaited<ReturnType<typeof seedWebsite>>;
before(async () => {
  await db.onModuleInit();
  f = await seedWebsite(db, "eden-public-test");
});
after(() => db.onModuleDestroy());
async function choice(type = "badminton", time = "10:00") {
  const site = await f.website.catalog(f.slug),
    business = site.businesses.find((b) => b.type === type)!,
    resource = business.resources[0],
    option = resource.options[0];
  return {
    business,
    resource,
    option,
    selection: {
      business_id: business.id,
      resource_id: resource.id,
      option_id: option.id,
      date: addDate(business.today, 2),
      time,
      duration_minutes: option.default_duration,
      people: 1,
    },
  };
}
test("public catalog projects only normal options and no private configuration or finance", async () => {
  const site = await f.website.catalog(f.slug);
  assert.equal(site.businesses.length, 6);
  const hall = site.businesses.find((b) => b.type === "hall")!;
  for (const resource of hall.resources) {
    for (const option of resource.options.filter(
      (o: any) => o.kind !== "hourly",
    )) {
      assert.ok(
        option.tariffs.some((t: any) => t.price_minor !== null),
        "Fixed hall tariffs must project package prices",
      );
    }
  }
  assert.ok(
    site.businesses.every((b) =>
      b.resources.every((r: any) =>
        r.options.every((o: any) =>
          ["hourly", "session", "full_day"].includes(o.kind),
        ),
      ),
    ),
  );
  const text = JSON.stringify(site);
  for (const privateKey of [
    '"configuration"',
    '"group_offers"',
    '"plans"',
    '"payment_accounts"',
    '"preview_hash"',
    '"memberships"',
  ])
    assert.ok(!text.includes(privateKey), privateKey);
});
test("onboarding creates a private draft; only owner can configure it", async () => {
  const other = await seedWebsite(
      db,
      `draft-${randomUUID().slice(0, 8)}`,
      false,
    ),
    settings = await other.website.settings(other.owner);
  await other.website.publication(other.owner, "unpublished", {
    version: settings.version,
  });
  await assert.rejects(
    () => other.website.catalog(other.slug),
    /not available/,
  );
  await db.query("UPDATE memberships SET role='staff' WHERE user_id=$1", [
    other.owner.uid,
  ]);
  await assert.rejects(
    () => other.website.settings(other.owner),
    /Only the owner/,
  );
});
test("guest booking uses existing inventory and creates no payment entries", async () => {
  const { selection } = await choice(),
    quote = await f.website.quote(f.slug, { selection }),
    command = {
      command_key: randomUUID(),
      selection,
      quote_token: quote.quote_token,
      customer: { name: "Guest customer", phone: "+919123456781" },
    };
  const result = await f.website.book(f.slug, command);
  assert.equal(result.payment_status, "unpaid");
  assert.ok(result.reference.startsWith("BK-"));
  assert.deepEqual(await f.website.book(f.slug, command), result);
  const row = (
    await db.query<any>("SELECT * FROM bookings WHERE reference=$1", [
      result.reference,
    ])
  ).rows[0];
  assert.equal(row.booking_source, "website");
  const notifications = (
    await db.query(
      "SELECT kind FROM booking_notification_events WHERE booking_id=$1",
      [row.id],
    )
  ).rows;
  assert.deepEqual(notifications, [{ kind: "created" }]);
  const detail = await new BookingService(db, f.workspace).detail(
    f.owner,
    row.id,
  );
  assert.equal(detail.history[0].actor_name, "Booking website");
  assert.equal(
    (
      await db.query("SELECT * FROM booking_payments WHERE booking_id=$1", [
        row.id,
      ])
    ).rows.length,
    0,
  );
  await assert.rejects(
    () =>
      new BookingService(db, f.workspace).quote(f.owner, {
        selection,
        exclude_booking_id: null,
      }),
    /available|capacity|booked/i,
  );
  await assert.rejects(
    () =>
      f.website.book(f.slug, {
        ...command,
        customer: { ...command.customer, name: "Changed customer" },
      }),
    /different booking data/,
  );
});
test("group offers, discounts, customer IDs, payments and cross-tenant businesses are rejected", async () => {
  const { selection } = await choice("pool");
  const raw = (
    await db.query<any>("SELECT configuration FROM businesses WHERE id=$1", [
      selection.business_id,
    ])
  ).rows[0].configuration;
  const group = raw.group_offers.find((o: any) => o.enabled);
  if (group)
    await assert.rejects(
      () =>
        f.website.quote(f.slug, {
          selection: { ...selection, option_id: group.id },
        }),
      /Only normal/,
    );
  await assert.rejects(() =>
    f.website.quote(f.slug, {
      selection: {
        ...selection,
        discount: { type: "amount", value: 100, reason: "x" },
      },
    }),
  );
  const quote = await f.website.quote(f.slug, { selection });
  const command = {
    command_key: randomUUID(),
    selection,
    quote_token: quote.quote_token,
    customer: { name: "Guest", phone: "9123456782" },
  };
  await assert.rejects(() =>
    f.website.book(f.slug, { ...command, payments: [] }),
  );
  await assert.rejects(() =>
    f.website.book(f.slug, {
      ...command,
      customer: { ...command.customer, id: randomUUID() },
    }),
  );
  const other = await seedWebsite(
    db,
    `other-${randomUUID().slice(0, 8)}`,
    false,
  );
  await assert.rejects(
    () => f.website.quote(other.slug, { selection }),
    /not available/,
  );
});
test("start/end availability uses shared rules and hides stale results only through confirmation checks", async () => {
  const { selection } = await choice("badminton", "14:00");
  const starts = await f.website.availability(f.slug, { selection });
  assert.ok(starts.slots.some((s) => s.time === "14:00" && s.available));
  const ends = await f.website.availability(f.slug, {
    selection,
    end_times: true,
  });
  assert.ok(
    ends.slots.some(
      (s) => s.time === "15:30" && s.duration_minutes === 90 && s.available,
    ),
  );
  await assert.rejects(() =>
    f.website.quote(f.slug, {
      selection: { ...selection, duration_minutes: 30 },
    }),
  );
  await assert.rejects(
    () =>
      f.website.quote(f.slug, {
        selection: { ...selection, date: addDate(selection.date, 365) },
      }),
    /booking window/,
  );
});
test("pool capacity and shared turf footprints remain authoritative", async () => {
  const { selection, resource } = await choice("pool", "15:00");
  const first = { ...selection, people: resource.capacity };
  const q = await f.website.quote(f.slug, { selection: first });
  await f.website.book(f.slug, {
    command_key: randomUUID(),
    selection: first,
    quote_token: q.quote_token,
    customer: { name: "Pool customer", phone: "9123456783" },
  });
  await assert.rejects(
    () => f.website.quote(f.slug, { selection }),
    /capacity|available/i,
  );
  const turf = await choice("turf", "16:00"),
    full = turf.business.resources.find((r: any) => r.section_ids.length > 1)!,
    half = turf.business.resources.find(
      (r: any) => r.ground_id === full.ground_id && r.section_ids.length === 1,
    )!;
  const fullSelection = {
    ...turf.selection,
    resource_id: full.id,
    option_id: full.options[0].id,
  };
  const fullQuote = await f.website.quote(f.slug, { selection: fullSelection });
  await f.website.book(f.slug, {
    command_key: randomUUID(),
    selection: fullSelection,
    quote_token: fullQuote.quote_token,
    customer: { name: "Turf customer", phone: "9123456784" },
  });
  await assert.rejects(
    () =>
      f.website.quote(f.slug, {
        selection: {
          ...fullSelection,
          resource_id: half.id,
          option_id: half.options[0].id,
        },
      }),
    /available|booked/i,
  );
});
test("preview is read-only, stale settings conflict and pausing blocks new writes", async () => {
  let settings = await f.website.settings(f.owner);
  const token = new URL(
    (await f.website.preview(f.owner)).url,
  ).searchParams.get("preview")!;
  assert.equal((await f.website.catalog(f.slug, token)).is_preview, true);
  const { selection } = await choice("badminton", "20:00"),
    q = await f.website.quote(f.slug, { selection });
  const command = {
    command_key: randomUUID(),
    selection,
    quote_token: q.quote_token,
    customer: { name: "Preview customer", phone: "9123456785" },
  };
  await assert.rejects(
    () => f.website.book(f.slug, command, token),
    /read-only/,
  );
  await assert.rejects(
    () =>
      f.website.publication(f.owner, "paused", {
        version: settings.version - 1,
      }),
    /changed/,
  );
  await f.website.publication(f.owner, "paused", { version: settings.version });
  await assert.rejects(() => f.website.book(f.slug, command), /paused/);
  settings = await f.website.settings(f.owner);
  await f.website.publication(f.owner, "published", {
    version: settings.version,
  });
  await assert.rejects(() => f.website.catalog(f.slug, token), /not available/);
});
test("concurrent public confirmations reserve an exclusive court only once", async () => {
  const { selection, business } = await choice("badminton", "12:00");
  const resource = business.resources[1],
    selected = {
      ...selection,
      resource_id: resource.id,
      option_id: resource.options[0].id,
    };
  const quote = await f.website.quote(f.slug, { selection: selected });
  const commands = [1, 2].map((n) => ({
    command_key: randomUUID(),
    selection: selected,
    quote_token: quote.quote_token,
    customer: { name: `Concurrent ${n}`, phone: `912345679${n}` },
  }));
  const result = await Promise.allSettled(
    commands.map((c) => f.website.book(f.slug, c)),
  );
  assert.equal(result.filter((r) => r.status === "fulfilled").length, 1);
  assert.equal(result.filter((r) => r.status === "rejected").length, 1);
});

test("successful confirmation retries remain safe after unpublishing", async () => {
  const { selection } = await choice("badminton", "21:00"),
    quote = await f.website.quote(f.slug, { selection });
  const command = {
    command_key: randomUUID(),
    selection,
    quote_token: quote.quote_token,
    customer: { name: "Retry customer", phone: "9123456788" },
  };
  const result = await f.website.book(f.slug, command);
  const settings = await f.website.settings(f.owner);
  await f.website.publication(f.owner, "unpublished", {
    version: settings.version,
  });
  assert.deepEqual(await f.website.book(f.slug, command), result);
  await assert.rejects(() => f.website.catalog(f.slug), /not available/);
  const fresh = await f.website.settings(f.owner);
  await f.website.publication(f.owner, "published", { version: fresh.version });
});

test("distributed limits are stored in the database and apply across service instances", async () => {
  const site = (
    await db.query<any>("SELECT id FROM booking_websites WHERE slug=$1", [
      f.slug,
    ])
  ).rows[0];
  const window = Math.floor(Date.now() / 60000);
  await db.query(
    "INSERT INTO booking_website_limits(website_id,bucket,used,expires_at) VALUES($1,$2,1200,now()+interval '1 minute') ON CONFLICT(website_id,bucket) DO UPDATE SET used=1200",
    [site.id, `read:${window}`],
  );
  await assert.rejects(() => f.website.catalog(f.slug), /Too many/);
});
