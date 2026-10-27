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
import { addDate } from "../src/bookings/booking.inventory";
import { seedWebsite } from "../scripts/website-fixtures";

delete process.env.DATABASE_URL;
delete process.env.DATABASE_MIGRATE;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
process.env.BOOKING_WEBSITE_URL = "http://localhost:3000";
const db = new Database();
type Site = Awaited<ReturnType<typeof seedWebsite>>;
const png =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jXioAAAAASUVORK5CYII=";
let seq = 0;
const slugOf = () => `pub-${Date.now().toString(36)}-${seq++}`;
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
const countBookings = async (f: Site) =>
  Number(
    (
      await db.query<any>(
        "SELECT count(*)::int AS n FROM bookings WHERE organization_id=$1",
        [f.orgId],
      )
    ).rows[0].n,
  );
let phoneSeq = 0;
const phone = () => `9${String(100000000 + phoneSeq++).padStart(9, "0")}`;
async function pick(f: Site, type = "badminton", resourceIndex = 0) {
  const cat = await f.website.catalog(f.slug);
  const business = cat.businesses.find((b: any) => b.type === type)!,
    resource = business.resources[resourceIndex],
    option = resource.options[0];
  let n = 0;
  const base = {
    business_id: business.id,
    resource_id: resource.id,
    option_id: option.id,
    duration_minutes: option.default_duration,
    people: 1,
  };
  /** Unique future slot on every call. */
  const next = (over: Record<string, unknown> = {}) => {
    const i = n++;
    return {
      ...base,
      date: addDate(business.today, 1 + (i % 25)),
      time: `${String(6 + Math.floor(i / 25)).padStart(2, "0")}:00`,
      ...over,
    };
  };
  return { cat, business, resource, option, base, next, today: business.today };
}
const request = async (
  f: Site,
  selection: any,
  over: Record<string, unknown> = {},
) => {
  const q = await f.website.quote(f.slug, { selection });
  return {
    command_key: randomUUID(),
    selection,
    quote_token: q.quote_token,
    customer: { name: "Guest Person", phone: phone() },
    ...over,
  };
};
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());

test("public selection fields: ids, option, date, time, duration, people on quote and availability", async () => {
  const f = await seedWebsite(db, slugOf(), false);
  const p = await pick(f);
  const sel = (over: Record<string, unknown> = {}) => p.next(over);
  const calls = [
    (s: any) => f.website.quote(f.slug, { selection: s }),
    (s: any) => f.website.availability(f.slug, { selection: s }),
    (s: any) =>
      f.website.availability(f.slug, { selection: s, end_times: true }),
  ];
  const bad: [string, unknown[]][] = [
    [
      "business_id",
      ["", " ", null, 5, "abc", "'; DROP TABLE businesses;--", "😀"],
    ],
    ["resource_id", ["", " ", null, 5, "abc", "'; --"]],
    ["option_id", ["", null, 5, "x".repeat(101), "😀", "'; --"]],
    [
      "date",
      [
        "",
        " ",
        null,
        20321201,
        "2032-1-1",
        "2032-02-30",
        "2033-02-29",
        "2032-13-01",
        "'; --",
        "😀",
        "2032-01-01T10:00",
      ],
    ],
    [
      "time",
      [
        "",
        " ",
        null,
        900,
        "9:00",
        "24:00",
        "09:60",
        "09:00:00",
        "٠٩:٠٠",
        "😀",
        "'; --",
      ],
    ],
    [
      "duration_minutes",
      [0, -1, 1.5, "60", null, 1441, 1e9, Number.MAX_SAFE_INTEGER, {}],
    ],
    ["people", [0, -1, 1.5, "1", null, 10001, 1e9, {}]],
  ];
  for (const [field, values] of bad)
    for (const v of values)
      for (const call of calls)
        await client(
          () => call(sel({ [field]: v })),
          `${field}=${JSON.stringify(v)}`,
        );
  // codes: schema failures are 422; unknown but well-formed ids are 404/400
  assert.equal(
    status(
      await client(() =>
        f.website.quote(f.slug, { selection: sel({ date: "2032-02-30" }) }),
      ),
    ),
    422,
  );
  assert.ok(
    (await client(() =>
      f.website.quote(f.slug, {
        selection: sel({ business_id: randomUUID() }),
      }),
    )) instanceof NotFoundException,
  );
  assert.equal(
    status(
      await client(() =>
        f.website.quote(f.slug, {
          selection: sel({ resource_id: randomUUID() }),
        }),
      ),
    ),
    400,
  );
  assert.equal(
    status(
      await client(() =>
        f.website.quote(f.slug, { selection: sel({ option_id: "nope" }) }),
      ),
    ),
    400,
  );
  // discount and unknown keys are not accepted from guests
  for (const extra of [
    { discount: { type: "percent", value: 10000, reason: "free" } },
    { discount: null },
    { admin: true },
    { notes: "x" },
  ])
    for (const call of calls)
      assert.equal(
        status(
          await client(
            () => call({ ...sel(), ...extra }),
            JSON.stringify(extra),
          ),
        ),
        422,
      );
  for (const body of [
    {},
    { selection: sel(), extra: 1 },
    { selection: null },
    null,
    undefined,
    "x",
    [],
    5,
  ]) {
    await client(
      () => f.website.quote(f.slug, body),
      `quote ${JSON.stringify(body)?.slice(0, 40)}`,
    );
    await client(
      () => f.website.availability(f.slug, body),
      `availability ${JSON.stringify(body)?.slice(0, 40)}`,
    );
  }
  for (const end_times of ["true", 1, null, "yes"])
    await client(
      () => f.website.availability(f.slug, { selection: sel(), end_times }),
      `end_times=${end_times}`,
    );
  // courts take exactly one "person"
  for (const people of [2, 5, 9999])
    assert.equal(
      status(
        await client(
          () => f.website.quote(f.slug, { selection: sel({ people }) }),
          `people=${people}`,
        ),
      ),
      400,
    );
  // duration grid
  for (const duration_minutes of [1, 15, 45, 59, 61, 74, 1440])
    await client(
      () =>
        f.website.quote(f.slug, {
          selection: sel({ duration_minutes, time: "06:00" }),
        }),
      `duration=${duration_minutes}`,
    );
  for (const duration_minutes of [60, 75, 120])
    assert.ok(
      (await f.website.quote(f.slug, { selection: sel({ duration_minutes }) }))
        .quote_token,
    );
  // end-of-day boundary: ending exactly at midnight is fine, one quarter later is not
  assert.ok(
    (
      await f.website.quote(f.slug, { selection: sel({ time: "23:00" }) })
    ).local_end.endsWith("00:00"),
  );
  await client(() =>
    f.website.quote(f.slug, { selection: sel({ time: "23:15" }) }),
  );
  await client(() =>
    f.website.quote(f.slug, { selection: sel({ time: "05:45" }) }),
  );
});
test("booking window: yesterday, today, last permitted day, one day beyond, and notice period", async () => {
  const f = await seedWebsite(db, slugOf(), false);
  const p = await pick(f);
  const s0: any = await f.website.settings(f.owner);
  const day = (n: number, time = "23:00") =>
    p.next({ date: addDate(p.today, n), time });
  assert.equal(
    status(await client(() => f.website.quote(f.slug, { selection: day(-1) }))),
    400,
  );
  assert.equal(
    status(
      await client(() => f.website.quote(f.slug, { selection: day(-365) })),
    ),
    400,
  );
  assert.equal(
    status(
      await client(() =>
        f.website.quote(f.slug, { selection: day(s0.advance_days + 1) }),
      ),
    ),
    400,
  );
  assert.equal(
    status(
      await client(() => f.website.quote(f.slug, { selection: day(10000) })),
    ),
    400,
  );
  assert.ok(
    (await f.website.quote(f.slug, { selection: day(s0.advance_days) }))
      .quote_token,
    "last permitted day",
  );
  assert.ok((await f.website.quote(f.slug, { selection: day(1) })).quote_token);
  // availability reports the same window instead of leaking slots outside it
  await client(() =>
    f.website.availability(f.slug, { selection: day(s0.advance_days + 1) }),
  );
  await client(() => f.website.availability(f.slug, { selection: day(-1) }));
  // advance_days = 1 and notice = 10080 minutes (one week)
  await f.website.save(f.owner, {
    version: s0.version,
    slug: s0.slug,
    title: s0.title,
    description: s0.description,
    contact_phone: s0.contact_phone,
    instructions: s0.instructions,
    cancellation_policy: s0.cancellation_policy,
    publish_logo: false,
    notice_minutes: 0,
    advance_days: 1,
    business_ids: s0.businesses
      .filter((b: any) => b.enabled)
      .map((b: any) => b.id),
  });
  assert.ok((await f.website.quote(f.slug, { selection: day(1) })).quote_token);
  assert.equal(
    status(await client(() => f.website.quote(f.slug, { selection: day(2) }))),
    400,
  );
  const s1: any = await f.website.settings(f.owner);
  await f.website.save(f.owner, {
    version: s1.version,
    slug: s1.slug,
    title: s1.title,
    description: s1.description,
    contact_phone: s1.contact_phone,
    instructions: s1.instructions,
    cancellation_policy: s1.cancellation_policy,
    publish_logo: false,
    notice_minutes: 10080,
    advance_days: 30,
    business_ids: s1.businesses
      .filter((b: any) => b.enabled)
      .map((b: any) => b.id),
  });
  assert.equal(
    status(await client(() => f.website.quote(f.slug, { selection: day(3) }))),
    400,
    "inside the notice period",
  );
  assert.ok(
    (await f.website.quote(f.slug, { selection: day(9) })).quote_token,
    "beyond the notice period",
  );
  const avail = await f.website.availability(f.slug, {
    selection: day(3, "10:00"),
  });
  assert.ok(
    avail.slots.every((s: any) => !s.available),
    "no slot inside the notice period is offered",
  );
  const later = await f.website.availability(f.slug, {
    selection: day(12, "10:00"),
  });
  assert.ok(later.slots.some((s: any) => s.available));
});
test("pool participants: zero, over capacity and price overflow never produce a 5xx", async () => {
  const f = await seedWebsite(db, slugOf(), true);
  const p = await pick(f, "pool");
  for (const people of [0, -1, 1.5, "2", null, 10001])
    await client(
      () => f.website.quote(f.slug, { selection: p.next({ people }) }),
      `people=${people}`,
    );
  assert.ok(
    (await f.website.quote(f.slug, { selection: p.next({ people: 1 }) }))
      .quote_token,
  );
  assert.ok(
    (await f.website.quote(f.slug, { selection: p.next({ people: 2 }) }))
      .total_minor > 0,
  );
  for (const people of [500, 9999, 10000]) {
    try {
      await f.website.quote(f.slug, { selection: p.next({ people }) });
    } catch (e) {
      assert.ok(isClientError(e), `people=${people}: ${(e as Error).message}`);
    }
  }
  // non-pool businesses ignore nothing: people must be exactly 1
  const turf = await pick(f, "turf");
  assert.equal(
    status(
      await client(() =>
        f.website.quote(f.slug, { selection: turf.next({ people: 2 }) }),
      ),
    ),
    400,
  );
});
test("hidden spaces and businesses removed from the site are not bookable even with valid ids", async () => {
  const f = await seedWebsite(db, slugOf(), false);
  const p = await pick(f);
  const s: any = await f.website.settings(f.owner);
  const hiddenSite = await f.website.save(f.owner, {
    version: s.version,
    slug: s.slug,
    title: s.title,
    description: s.description,
    contact_phone: s.contact_phone,
    instructions: s.instructions,
    cancellation_policy: s.cancellation_policy,
    publish_logo: false,
    notice_minutes: 0,
    advance_days: 30,
    business_ids: s.businesses
      .filter((b: any) => b.enabled)
      .map((b: any) => b.id),
    spaces: [
      {
        business_id: p.business.id,
        resource_id: p.resource.id,
        visible: false,
        notice_minutes: null,
        advance_days: null,
        rules: "",
      },
    ],
  });
  assert.equal(
    status(
      await client(() => f.website.quote(f.slug, { selection: p.next() })),
    ),
    400,
  );
  assert.equal(
    status(
      await client(() =>
        f.website.availability(f.slug, { selection: p.next() }),
      ),
    ),
    400,
  );
  const req = {
    command_key: randomUUID(),
    selection: p.next(),
    quote_token: "a".repeat(64),
    customer: { name: "Guest Person", phone: phone() },
  };
  assert.equal(status(await client(() => f.website.book(f.slug, req))), 400);
  assert.equal(await countBookings(f), 0);
  await db.query("DELETE FROM booking_website_businesses WHERE website_id=$1", [
    hiddenSite.id,
  ]);
  assert.ok(
    (await client(() =>
      f.website.quote(f.slug, {
        selection: p.next({
          resource_id: p.business.resources?.[1]?.id ?? p.resource.id,
        }),
      }),
    )) instanceof NotFoundException,
  );
});

test("guest customer fields: name, phone, forbidden keys, unicode and injection strings", async () => {
  const f = await seedWebsite(db, slugOf(), false);
  const p = await pick(f);
  const attempt = async (customer: unknown, label: string) => {
    const r: any = await request(f, p.next());
    return client(() => f.website.book(f.slug, { ...r, customer }), label);
  };
  for (const name of [
    "",
    " ",
    "\n",
    "a",
    " a ",
    "x".repeat(101),
    null,
    5,
    {},
    [],
  ])
    assert.equal(
      status(
        await attempt(
          { name, phone: "9876543210" },
          `name=${JSON.stringify(name)}`,
        ),
      ),
      422,
    );
  for (const ph of [
    "",
    " ",
    "123456",
    "abc",
    "+",
    "++919876543210",
    "1".repeat(26),
    "1234567890123456",
    null,
    9876543210,
    "(((((((",
    "-------",
    "😀😀😀😀😀😀😀",
    "98765'; --",
  ])
    assert.equal(
      status(
        await attempt(
          { name: "Guest Person", phone: ph },
          `phone=${JSON.stringify(ph)}`,
        ),
      ),
      422,
    );
  for (const extra of [
    { email: "a@b.com" },
    { id: randomUUID() },
    { id: null },
    { notes: "x" },
    { role: "owner" },
  ])
    assert.equal(
      status(
        await attempt(
          { name: "Guest Person", phone: "9876543210", ...extra },
          JSON.stringify(extra),
        ),
      ),
      422,
    );
  assert.equal(status(await attempt(null, "null customer")), 422);
  assert.equal(status(await attempt(undefined, "missing customer")), 422);
  assert.equal(await countBookings(f), 0);
  const good = [
    ["ab", "1234567"],
    ["x".repeat(100), "123456789012345"],
    ["José Müller 李雷", "+91 98765-43210"],
    ["Zoë 🙂 Party", "(080) 123 4567"],
    ["O'Brien; DROP TABLE bookings;--", "9000000001"],
    ["<script>alert(1)</script>", "9000000002"],
    ["Line\nBreak", "9000000003"],
    ["  Padded Name  ", "9000000004"],
  ];
  for (const [name, ph] of good) {
    const r: any = await request(f, p.next(), {
      customer: { name, phone: ph },
    });
    const out = await f.website.book(f.slug, r);
    assert.equal(out.status, "confirmed");
    const row = (
      await db.query<any>(
        "SELECT c.name,c.phone,b.customer_snapshot,b.booking_source FROM bookings b JOIN customers c ON c.id=b.customer_id WHERE b.reference=$1",
        [out.reference],
      )
    ).rows[0];
    assert.equal(row.name, name.trim());
    assert.equal(row.phone, ph.replace(/[^\d+]/g, ""));
    assert.equal(row.customer_snapshot.email, null);
    assert.equal(row.booking_source, "website");
  }
  assert.ok(
    (await db.query<any>("SELECT count(*)::int AS n FROM bookings")).rows[0]
      .n >= good.length,
    "tables survived the injection strings",
  );
});
test("book(): command_key, quote_token, unknown keys and envelope shapes", async () => {
  const f = await seedWebsite(db, slugOf(), false);
  const p = await pick(f);
  const r: any = await request(f, p.next());
  for (const command_key of ["", " ", null, 5, "abc", "'; --", undefined])
    await client(
      () => f.website.book(f.slug, { ...r, command_key }),
      String(command_key),
    );
  const t = r.quote_token as string;
  for (const quote_token of [
    "",
    t.slice(1),
    t + "0",
    t.toUpperCase(),
    "g".repeat(64),
    null,
    5,
    undefined,
  ])
    await client(
      () => f.website.book(f.slug, { ...r, quote_token }),
      String(quote_token).slice(0, 8),
    );
  assert.equal(
    status(
      await client(() =>
        f.website.book(f.slug, { ...r, quote_token: "0".repeat(64) }),
      ),
    ),
    409,
  );
  for (const body of [
    { ...r, extra: 1 },
    { ...r, status: "paid" },
    { ...r, payment: null },
    { ...r, payment: { percentage: 50 } },
    null,
    undefined,
    "x",
    [],
    5,
    {},
  ])
    await client(
      () => f.website.book(f.slug, body),
      JSON.stringify(body)?.slice(0, 40),
    );
  assert.equal(
    await countBookings(f),
    0,
    "nothing was booked by any rejected request",
  );
});
test("overlap and adjacency on the public site; duplicate submit and parallel duplicates", async () => {
  const f = await seedWebsite(db, slugOf(), false);
  const p = await pick(f);
  const date = addDate(p.today, 3);
  const one = (time: string, duration_minutes = 60, resource = 0) => ({
    ...p.next(),
    date,
    time,
    duration_minutes,
    ...(resource
      ? {
          resource_id: p.cat.businesses[0].resources[resource].id,
          option_id: p.cat.businesses[0].resources[resource].options[0].id,
        }
      : {}),
  });
  const book = async (selection: any) =>
    f.website.book(f.slug, await request(f, selection));
  await book(one("10:00", 120));
  for (const [time, d] of [
    ["10:00", 60],
    ["10:30", 60],
    ["09:30", 60],
    ["11:30", 60],
    ["09:00", 240],
    ["10:15", 75],
  ] as const) {
    const e = await client(
      async () => book(one(time, d)),
      `${time}+${d}`,
    ).catch((x) => x);
    assert.ok(e instanceof Error, `${time}+${d}`);
  }
  // the quote itself may already refuse; the book step must refuse with a conflict for a quote taken earlier
  const early = await request(f, one("14:00", 60));
  await book(one("14:00", 60));
  assert.equal(status(await client(() => f.website.book(f.slug, early))), 409);
  await book(one("09:00", 60)); // adjacent before
  await book(one("12:00", 60)); // adjacent after
  await book(one("10:00", 60, 1)); // other court
  // duplicate submit
  const r: any = await request(f, p.next());
  const a = await f.website.book(f.slug, r);
  const b = await f.website.book(f.slug, r);
  assert.deepEqual(a, b);
  assert.equal(
    Number(
      (
        await db.query<any>(
          "SELECT count(*)::int AS n FROM bookings WHERE reference=$1",
          [a.reference],
        )
      ).rows[0].n,
    ),
    1,
  );
  assert.equal(
    status(
      await client(() =>
        f.website.book(f.slug, {
          ...r,
          customer: { name: "Other Name", phone: r.customer.phone },
        }),
      ),
    ),
    409,
    "same key, changed customer",
  );
  assert.equal(
    status(
      await client(() =>
        f.website.book(f.slug, {
          ...r,
          customer: { name: r.customer.name, phone: phone() },
        }),
      ),
    ),
    409,
    "same key, changed phone",
  );
  // parallel duplicates of one request
  const par: any = await request(f, p.next());
  const res = await Promise.allSettled(
    [1, 2, 3, 4].map(() => f.website.book(f.slug, par)),
  );
  assert.ok(res.every((x) => x.status === "fulfilled"));
  assert.equal(new Set(res.map((x: any) => x.value.reference)).size, 1);
  // parallel different guests for one slot: exactly one succeeds
  const sel = p.next();
  const q = await f.website.quote(f.slug, { selection: sel });
  const race = await Promise.allSettled(
    [1, 2, 3].map(() =>
      f.website.book(f.slug, {
        command_key: randomUUID(),
        selection: sel,
        quote_token: q.quote_token,
        customer: { name: "Racer", phone: phone() },
      }),
    ),
  );
  assert.equal(race.filter((x) => x.status === "fulfilled").length, 1);
});
test("site state: paused and preview refuse writes; draft sites must look identical to missing sites", async () => {
  const f = await seedWebsite(db, slugOf(), false);
  const p = await pick(f);
  const s: any = await f.website.settings(f.owner);
  const r: any = await request(f, p.next());
  const token = new URL(
    (await f.website.preview(f.owner)).url,
  ).searchParams.get("preview")!;
  assert.ok(
    (await client(() => f.website.book(f.slug, r, token))) instanceof
      ForbiddenException,
  );
  assert.ok(
    (await client(() => f.website.book(f.slug, r, "0".repeat(64)))) instanceof
      ForbiddenException,
    "any preview value turns the call read-only",
  );
  const paused: any = await f.website.publication(f.owner, "paused", {
    version: s.version,
  });
  assert.ok(
    (await client(() => f.website.book(f.slug, r))) instanceof
      ConflictException,
  );
  assert.ok(
    (await f.website.catalog(f.slug)).businesses.length > 0,
    "paused sites remain visible",
  );
  await f.website.quote(f.slug, { selection: p.next() });
  const off: any = await f.website.publication(f.owner, "unpublished", {
    version: paused.version,
  });
  assert.ok(off);
  assert.ok(
    (await client(() => f.website.book("never-existed-site", r))) instanceof
      NotFoundException,
  );
  await client(() => f.website.catalog(f.slug), "unpublished catalog");
});
test(
  "an unpublished or draft address must answer a booking attempt with 404, exactly like an unknown address",
  { todo: "BUG-16" },
  async () => {
    const f = await seedWebsite(db, slugOf(), false);
    const p = await pick(f);
    const r: any = await request(f, p.next());
    const s: any = await f.website.settings(f.owner);
    await f.website.publication(f.owner, "unpublished", { version: s.version });
    const unknown = await client(() => f.website.book("never-existed-site", r));
    const draft = await client(() => f.website.book(f.slug, r));
    assert.equal(status(draft), status(unknown));
  },
);
test("transaction ids and payment choices: required, optional, unsupported and duplicate submissions", async () => {
  const f = await seedWebsite(db, slugOf(), false),
    g = await seedWebsite(db, slugOf(), false);
  const accounts = new AccountsService(db, f.workspace);
  const p = await pick(f);
  const s = async () => (await f.website.settings(f.owner)) as any;
  const policy = async (required: boolean, percentages: number[]) => {
    const cur = await s();
    await f.website.save(f.owner, {
      version: cur.version,
      slug: cur.slug,
      title: cur.title,
      description: cur.description,
      contact_phone: cur.contact_phone,
      instructions: cur.instructions,
      cancellation_policy: cur.cancellation_policy,
      publish_logo: false,
      notice_minutes: 0,
      advance_days: 30,
      business_ids: cur.businesses
        .filter((b: any) => b.enabled)
        .map((b: any) => b.id),
      spaces: [
        {
          business_id: p.business.id,
          resource_id: p.resource.id,
          visible: true,
          notice_minutes: null,
          advance_days: null,
          rules: "",
          payment_required: required,
          payment_percentages: percentages,
        },
      ],
    });
  };
  const withPay = async (
    payment: unknown,
    over: Record<string, unknown> = {},
  ) => {
    const r: any = await request(f, p.next());
    return f.website.book(f.slug, { ...r, payment, ...over });
  };
  // optional checkout without UPI configured: no payment options exist
  assert.equal(
    status(
      await client(() =>
        withPay({ percentage: 100, transaction_id: "TXN-AAAA-0001" }),
      ),
    ),
    400,
  );
  await accounts.saveWebsitePayments(f.owner, {
    version: 0,
    upi_id: "venue@bank",
    qr: { content_type: "image/png", base64: png },
  });
  // optional checkout: only 100% is offered
  assert.equal(
    status(
      await client(() =>
        withPay({ percentage: 50, transaction_id: "TXN-AAAA-0002" }),
      ),
    ),
    400,
  );
  const ok100: any = await withPay({
    percentage: 100,
    transaction_id: "txn-aaaa-0003",
  });
  assert.equal(
    ok100.website_payment_submission.transaction_id,
    "TXN-AAAA-0003",
  );
  assert.equal(ok100.website_payment_submission.status, "pending_verification");
  assert.equal(
    ok100.website_payment_submission.amount_minor,
    ok100.total_minor,
  );
  // mandatory checkout
  await policy(true, [25, 50, 100]);
  const missing = await client(async () => {
    const r: any = await request(f, p.next());
    return f.website.book(f.slug, r);
  });
  assert.equal(status(missing), 400);
  for (const payment of [
    { percentage: 0, transaction_id: "TXN-AAAA-0004" },
    { percentage: 101, transaction_id: "TXN-AAAA-0004" },
    { percentage: 33, transaction_id: "TXN-AAAA-0004" },
    { percentage: 1.5, transaction_id: "TXN-AAAA-0004" },
    { percentage: "50", transaction_id: "TXN-AAAA-0004" },
    { percentage: null, transaction_id: "TXN-AAAA-0004" },
    { percentage: 50, transaction_id: "12345" },
    { percentage: 50, transaction_id: "x".repeat(65) },
    { percentage: 50, transaction_id: "AB CD EF" },
    { percentage: 50, transaction_id: "ABC#123" },
    { percentage: 50, transaction_id: "ÀÉÎÕÜ123" },
    { percentage: 50, transaction_id: "😀😀😀😀😀😀" },
    { percentage: 50, transaction_id: "ABC123'; DROP TABLE bookings;--" },
    { percentage: 50, transaction_id: null },
    { percentage: 50, transaction_id: 123456 },
    { percentage: 50 },
    { transaction_id: "TXN-AAAA-0004" },
    {},
    null,
    "x",
    [],
    { percentage: 50, transaction_id: "TXN-AAAA-0004", extra: 1 },
    { percentage: 50, transaction_id: "TXN-AAAA-0004", amount_minor: 1 },
  ])
    await client(() => withPay(payment), JSON.stringify(payment).slice(0, 70));
  assert.equal(
    await countBookings(f),
    1,
    "only the valid optional booking exists",
  );
  // the amount is derived on the server, never taken from the guest
  const ok25: any = await withPay({
    percentage: 25,
    transaction_id: "  txn-bbbb-0005  ",
  });
  assert.equal(
    ok25.website_payment_submission.amount_minor,
    Math.ceil((ok25.total_minor * 25) / 100),
  );
  assert.equal(ok25.website_payment_submission.transaction_id, "TXN-BBBB-0005");
  // duplicate transaction id: case-insensitive, same organisation only
  for (const id of ["txn-bbbb-0005", "TXN-BBBB-0005", "Txn-Bbbb-0005"])
    assert.equal(
      status(
        await client(() => withPay({ percentage: 50, transaction_id: id }), id),
      ),
      409,
    );
  const gp = await pick(g);
  await accounts.saveWebsitePayments(g.owner, {
    version: 0,
    upi_id: "other@bank",
    qr: { content_type: "image/png", base64: png },
  });
  const gr: any = await request(g, gp.next());
  const cross: any = await g.website.book(g.slug, {
    ...gr,
    payment: { percentage: 100, transaction_id: "TXN-BBBB-0005" },
  });
  assert.equal(
    cross.website_payment_submission.transaction_id,
    "TXN-BBBB-0005",
    "another organisation may reuse the reference",
  );
  // the quote token is bound to the payment policy
  const stale: any = await request(f, p.next());
  await policy(true, [100]);
  assert.equal(
    status(
      await client(() =>
        f.website.book(f.slug, {
          ...stale,
          payment: { percentage: 100, transaction_id: "TXN-CCCC-0006" },
        }),
      ),
    ),
    409,
  );
  // no booking_payments are ever created from a guest submission
  assert.equal(
    Number(
      (
        await db.query<any>(
          "SELECT count(*)::int AS n FROM booking_payments WHERE organization_id=$1",
          [f.orgId],
        )
      ).rows[0].n,
    ),
    0,
  );
});
test("per-phone and per-site limits: rejected attempts do not consume them, accepted ones do", async () => {
  const f = await seedWebsite(db, slugOf(), false);
  const p = await pick(f);
  const same = "9555000111";
  const slot = p.next();
  const first: any = await request(f, slot, {
    customer: { name: "Limit One", phone: same },
  });
  await f.website.book(f.slug, first);
  // conflicts on a taken slot must not burn the phone allowance
  for (let n = 0; n < 5; n++) {
    const r: any = {
      ...first,
      command_key: randomUUID(),
      customer: { name: "Limit Retry", phone: same },
    };
    assert.equal(status(await client(() => f.website.book(f.slug, r))), 409);
  }
  for (let n = 0; n < 2; n++)
    await f.website.book(
      f.slug,
      await request(f, p.next(), {
        customer: { name: `Limit ${n}`, phone: same },
      }),
    );
  const fourth: any = await request(f, p.next(), {
    customer: { name: "Limit Four", phone: same },
  });
  assert.equal(
    status(await client(() => f.website.book(f.slug, fourth))),
    429,
    "fourth booking for one phone within the hour",
  );
  assert.equal(await countBookings(f), 3);
  // replaying an accepted booking is not rate limited
  assert.ok((await f.website.book(f.slug, first)).reference);
  // another phone is unaffected
  assert.ok(
    (
      await f.website.book(
        f.slug,
        await request(f, p.next(), {
          customer: { name: "Other Guest", phone: phone() },
        }),
      )
    ).reference,
  );
  // site-wide hourly confirmation cap
  const siteRow = (
    await db.query<any>("SELECT id FROM booking_websites WHERE slug=$1", [
      f.slug,
    ])
  ).rows[0];
  const window = Math.floor(Date.now() / 3600000);
  await db.query(
    "INSERT INTO booking_website_limits(website_id,bucket,used,expires_at) VALUES($1,$2,30,now()+interval '1 hour') ON CONFLICT(website_id,bucket) DO UPDATE SET used=30",
    [siteRow.id, `confirm:${window}`],
  );
  assert.equal(
    status(
      await client(async () =>
        f.website.book(
          f.slug,
          await request(f, p.next(), {
            customer: { name: "Capped Guest", phone: phone() },
          }),
        ),
      ),
    ),
    429,
  );
  assert.ok(
    (await f.website.quote(f.slug, { selection: p.next() })).quote_token,
    "reads and quotes are unaffected by the confirmation cap",
  );
});
test("the per-phone limit applies to the same number written with a country code, spaces or a trunk zero", async () => {
  const f = await seedWebsite(db, slugOf(), false);
  const p = await pick(f);
  const variants = [
    "9555000222",
    "+919555000222",
    "09555000222",
    "95550 00222",
    "+91 95550-00222",
    "(95550) 00222",
  ];
  let accepted = 0;
  for (const v of variants) {
    try {
      await f.website.book(
        f.slug,
        await request(f, p.next(), {
          customer: { name: "Same Person", phone: v },
        }),
      );
      accepted++;
    } catch (e) {
      assert.equal(status(e), 429);
    }
  }
  assert.ok(
    accepted <= 3,
    `${accepted} bookings were accepted for one phone number`,
  );
});
test("cross-tenant: another site's ids, spaces and quotes cannot be used", async () => {
  const f = await seedWebsite(db, slugOf(), false),
    g = await seedWebsite(db, slugOf(), false);
  const pf = await pick(f),
    pg = await pick(g);
  assert.ok(
    (await client(() =>
      f.website.quote(f.slug, { selection: pg.next() }),
    )) instanceof NotFoundException,
  );
  assert.ok(
    (await client(() =>
      f.website.availability(f.slug, { selection: pg.next() }),
    )) instanceof NotFoundException,
  );
  assert.equal(
    status(
      await client(() =>
        f.website.quote(f.slug, {
          selection: pf.next({ resource_id: pg.resource.id }),
        }),
      ),
    ),
    400,
  );
  const gReq: any = await request(g, pg.next());
  assert.ok(
    (await client(() => f.website.book(f.slug, gReq))) instanceof
      NotFoundException,
  );
  // a quote from the right business but another site's slug path cannot be confirmed there
  const own: any = await request(f, pf.next());
  assert.ok(
    (await client(() => g.website.book(g.slug, own))) instanceof
      NotFoundException,
  );
  assert.equal(await countBookings(f), 0);
  assert.equal(await countBookings(g), 0);
  // the same command key is independent per organisation
  const key = randomUUID();
  const a = await f.website.book(f.slug, {
    ...(await request(f, pf.next())),
    command_key: key,
  });
  const b = await g.website.book(g.slug, {
    ...(await request(g, pg.next())),
    command_key: key,
  });
  assert.notEqual(a.reference, b.reference);
  // unknown query-string flags never widen access
  for (const preview of ["true", "1", "admin", "../", "%00", "x".repeat(500)])
    assert.ok(
      (await client(
        () => f.website.catalog(f.slug, preview),
        `preview=${preview.slice(0, 10)}`,
      )) instanceof NotFoundException,
      "an invalid preview value never grants preview rights",
    );
});

test(
  "a NUL character (\\u0000) in the guest name must be a 4xx on the unauthenticated booking endpoint",
  { todo: "BUG-14" },
  async () => {
    const f = await seedWebsite(db, slugOf(), false);
    const p = await pick(f);
    const r: any = await request(f, p.next());
    await client(
      () =>
        f.website.book(f.slug, {
          ...r,
          customer: { name: "Guest\u0000Person", phone: phone() },
        }),
      "guest name with NUL",
    );
  },
);
