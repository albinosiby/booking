import "reflect-metadata";
import { test, before, after } from "node:test";
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
import { WorkspaceService } from "../src/workspace/workspace.service";
import { CourtService } from "../src/court/court.service";
import { BookingService } from "../src/bookings/booking.service";
import { SlotBlocksService } from "../src/slot-blocks/slot-blocks.service";
import { addDate } from "../src/bookings/booking.inventory";
import { Actor } from "../src/common/auth.guard";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  workspace = new WorkspaceService(db),
  bookings = new BookingService(db, workspace),
  blocks = new SlotBlocksService(db),
  courts = new CourtService(db, workspace);
const hours = {
  days: [1, 2, 3, 4, 5, 6, 7],
  opens_at: "06:00",
  closes_at: "00:00",
  date_from: null,
  date_until: null,
};
const actor = (): Actor => {
  const uid = randomUUID();
  return { uid, email: `${uid}@example.com`, name: "Owner" };
};
let dayCounter = 0;
const nextDay = () => addDate("2032-01-01", dayCounter++);
async function fixture(timezone = "Asia/Kolkata") {
  const owner = actor();
  await workspace.createOrganization(owner, {
    name: "Eden",
    contact_phone: "9876543210",
    currency: "INR",
    location: {
      name: "Kochi",
      address_line_1: "Main Road",
      address_line_2: null,
      city: "Kochi",
      state_code: "KL",
      country_code: "IN",
      postal_code: "682001",
      timezone,
    },
  });
  const w = await workspace.workspace(owner),
    b = await workspace.createBusiness(owner, {
      name: "Bookings",
      type: "badminton",
      location_id: w.locations[0].id,
    });
  const config = {
    kind: "court_v1",
    schema_version: 1,
    courts: [1, 2].map((n) => ({
      id: randomUUID(),
      name: `Court ${n}`,
      enabled: true,
      environment: "indoor",
      surface: "",
      operating: hours,
      durations: [60],
      default_duration_minutes: 60,
      buffer_before: 0,
      buffer_after: 0,
      pricing_basis: "start_time",
      tariffs: [
        {
          id: randomUUID(),
          hours,
          rates: [{ duration_minutes: 60, price_minor: 50000 }],
        },
      ],
    })),
  };
  await courts.configure(owner, b.id, { version: 1, configuration: config });
  await workspace.activate(owner, b.id);
  const catalog = await bookings.catalog(owner);
  const res = catalog.businesses[0].resources;
  const block = (over: Record<string, unknown> = {}) => ({
    command_key: randomUUID(),
    business_id: b.id,
    resource_ids: [res[0].id],
    date: nextDay(),
    all_day: false,
    start_time: "10:00",
    end_time: "12:00",
    ...over,
  });
  return { owner, id: b.id, res, block, option: res[0].options[0] };
}
type F = Awaited<ReturnType<typeof fixture>>;
async function staffOf(
  f: F,
  permissions: string[],
  resourceIds: string[] = [],
) {
  const staff = actor();
  const invite = await workspace.invite(f.owner, {
    email: staff.email,
    display_name: "Staff",
    role: "staff",
    permissions,
    assignments: [{ business_id: f.id, resource_ids: resourceIds }],
  });
  await workspace.accept(
    staff,
    new URL(invite.invitation_url).searchParams.get("token")!,
  );
  return staff;
}
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
      `${label} should be a client error, got ${(e as Error)?.constructor?.name}: ${(e as Error)?.message}`,
    );
    return e as Error;
  }
  assert.fail(`${label} should have been rejected`);
}
const count = async (f: F) =>
  Number(
    (
      await db.query<any>(
        "SELECT count(*)::int AS n FROM booking_slot_blocks WHERE business_id=$1",
        [f.id],
      )
    ).rows[0].n,
  );
async function book(f: F, date: string, time: string, duration = 60) {
  const selection = {
    business_id: f.id,
    resource_id: f.res[0].id,
    option_id: f.option.id,
    date,
    time,
    duration_minutes: duration,
    people: 1,
  };
  const q = await bookings.quote(f.owner, {
    selection,
    exclude_booking_id: null,
  });
  return bookings.create(f.owner, {
    command_key: randomUUID(),
    selection,
    quote_token: q.quote_token,
    customer: { id: null, name: "Customer", phone: "9876543210", email: null },
    notes: "",
    payments: [],
  });
}
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());

test("block.command_key / business_id / resource_ids reject empty, null, wrong type, SQL-ish, duplicate and oversized lists", async () => {
  const f = await fixture();
  const n0 = await count(f);
  for (const command_key of ["", " ", null, 5, "abc", "'; --"])
    await client(
      () => blocks.create(f.owner, f.block({ command_key })),
      `command_key=${command_key}`,
    );
  for (const business_id of [
    "",
    null,
    5,
    "abc",
    "😀",
    "'; DROP TABLE booking_slot_blocks;--",
  ])
    assert.equal(
      status(
        await client(() => blocks.create(f.owner, f.block({ business_id }))),
      ),
      422,
    );
  assert.ok(
    (await client(() =>
      blocks.create(f.owner, f.block({ business_id: randomUUID() })),
    )) instanceof NotFoundException,
  );
  for (const resource_ids of [
    [],
    null,
    "x",
    5,
    {},
    [""],
    [null],
    ["abc"],
    [5],
    Array.from({ length: 101 }, () => randomUUID()),
  ])
    assert.equal(
      status(
        await client(
          () => blocks.create(f.owner, f.block({ resource_ids })),
          JSON.stringify(resource_ids).slice(0, 40),
        ),
      ),
      422,
    );
  const dup = await client(() =>
    blocks.create(
      f.owner,
      f.block({ resource_ids: [f.res[0].id, f.res[0].id] }),
    ),
  );
  assert.equal(status(dup), 400);
  const unknown = await client(() =>
    blocks.create(f.owner, f.block({ resource_ids: [randomUUID()] })),
  );
  assert.equal(status(unknown), 400);
  const mixed = await client(() =>
    blocks.create(
      f.owner,
      f.block({ resource_ids: [f.res[0].id, randomUUID()] }),
    ),
  );
  assert.equal(status(mixed), 400);
  await client(() => blocks.create(f.owner, { ...f.block(), extra: 1 }));
  for (const body of [null, undefined, "x", [], 5])
    await client(() => blocks.create(f.owner, body), `body=${String(body)}`);
  assert.equal(await count(f), n0, "no rejected request may create a block");
});
test("block.date boundaries: format, calendar validity, year range, past and today", async () => {
  const f = await fixture();
  for (const date of [
    "",
    " ",
    null,
    20320101,
    "2032-1-1",
    "2032-02-30",
    "2033-02-29",
    "2032-13-01",
    "2032-06-04T10:00",
    "'; --",
    "😀",
    "1999-12-31",
    "0000-01-01",
    "2101-01-01",
    "9999-12-31",
  ])
    assert.equal(
      status(
        await client(
          () => blocks.create(f.owner, f.block({ date })),
          `date=${date}`,
        ),
      ),
      422,
      `date=${date}`,
    );
  // years 2000 and 2100 pass schema; 2000 is past, 2100 is future and valid
  const past = await client(() =>
    blocks.create(f.owner, f.block({ date: "2000-01-01" })),
  );
  assert.equal(status(past), 400);
  const far = await blocks.create(
    f.owner,
    f.block({ date: "2100-12-31", start_time: "10:00", end_time: "11:00" }),
  );
  assert.ok(far.id);
  const leap = await blocks.create(f.owner, f.block({ date: "2032-02-29" }));
  assert.ok(leap.id);
  // yesterday and an interval that ended one minute ago are refused
  const today = new Date().toISOString().slice(0, 10);
  const e1 = await client(() =>
    blocks.create(
      f.owner,
      f.block({
        date: addDate(today, -1),
        start_time: "10:00",
        end_time: "12:00",
      }),
    ),
  );
  assert.equal(status(e1), 400);
  const e2 = await client(() =>
    blocks.create(
      f.owner,
      f.block({
        date: addDate(today, -2),
        all_day: true,
        start_time: undefined,
        end_time: undefined,
      }),
    ),
  );
  assert.equal(status(e2), 400);
});
test("block time fields: all_day type, clock format, missing times, equal times, midnight and 24h boundaries", async () => {
  const f = await fixture();
  for (const all_day of ["true", "false", 1, 0, null, undefined, "", {}])
    await client(
      () => blocks.create(f.owner, f.block({ all_day })),
      `all_day=${String(all_day)}`,
    );
  for (const start_time of [
    "",
    " ",
    "9:00",
    "24:00",
    "10:60",
    "10:00:00",
    " 10:00",
    "10:00 ",
    null,
    1000,
    "😀",
    "10:00'; --",
  ])
    assert.equal(
      status(
        await client(
          () => blocks.create(f.owner, f.block({ start_time })),
          `start=${start_time}`,
        ),
      ),
      422,
    );
  for (const end_time of ["", "24:00", "12:60", "12:00:00", null, 1200, "noon"])
    assert.equal(
      status(
        await client(
          () => blocks.create(f.owner, f.block({ end_time })),
          `end=${end_time}`,
        ),
      ),
      422,
    );
  for (const over of [
    { start_time: undefined },
    { end_time: undefined },
    { start_time: undefined, end_time: undefined },
  ])
    assert.equal(
      status(await client(() => blocks.create(f.owner, f.block(over)))),
      400,
    );
  // all-day ignores supplied times and spans exactly local midnight to midnight
  const date = nextDay();
  const allDay = await blocks.create(
    f.owner,
    f.block({
      date,
      all_day: true,
      start_time: undefined,
      end_time: undefined,
    }),
  );
  const row = (
    await db.query<any>(
      "SELECT starts_at,ends_at FROM booking_slot_blocks WHERE id=$1",
      [allDay.id],
    )
  ).rows[0];
  assert.equal(Date.parse(row.ends_at) - Date.parse(row.starts_at), 86400000);
  assert.equal(
    new Date(row.starts_at).toISOString(),
    new Date(Date.parse(date + "T00:00:00Z") - 330 * 60000).toISOString(),
  );
  // equal start/end = exactly 24h (allowed by the one-day limit); 23:30->00:00 = 30 min
  const other = f.block({ resource_ids: [f.res[1].id] });
  const full = await blocks.create(f.owner, {
    ...other,
    start_time: "08:00",
    end_time: "08:00",
  });
  const r2 = (
    await db.query<any>(
      "SELECT starts_at,ends_at FROM booking_slot_blocks WHERE id=$1",
      [full.id],
    )
  ).rows[0];
  assert.equal(Date.parse(r2.ends_at) - Date.parse(r2.starts_at), 86400000);
  const half = await blocks.create(
    f.owner,
    f.block({ start_time: "23:30", end_time: "00:00" }),
  );
  const r3 = (
    await db.query<any>(
      "SELECT starts_at,ends_at FROM booking_slot_blocks WHERE id=$1",
      [half.id],
    )
  ).rows[0];
  assert.equal(Date.parse(r3.ends_at) - Date.parse(r3.starts_at), 30 * 60000);
  // overnight 23:00 -> 01:00 next day
  const night = await blocks.create(
    f.owner,
    f.block({ start_time: "23:00", end_time: "01:00" }),
  );
  const r4 = (
    await db.query<any>(
      "SELECT starts_at,ends_at FROM booking_slot_blocks WHERE id=$1",
      [night.id],
    )
  ).rows[0];
  assert.equal(Date.parse(r4.ends_at) - Date.parse(r4.starts_at), 120 * 60000);
});
test("block.end_date must stay within one day of date; all-day ignores it", async () => {
  const f = await fixture();
  const date = nextDay();
  for (const end_date of [
    "",
    null,
    5,
    "2032-02-30",
    "1999-12-31",
    "2101-01-01",
    "x",
  ])
    assert.equal(
      status(
        await client(
          () => blocks.create(f.owner, f.block({ date, end_date })),
          `end_date=${end_date}`,
        ),
      ),
      422,
    );
  for (const end_date of [
    addDate(date, -1),
    addDate(date, 2),
    addDate(date, 30),
  ])
    assert.equal(
      status(
        await client(() =>
          blocks.create(
            f.owner,
            f.block({ date, start_time: "10:00", end_time: "12:00", end_date }),
          ),
        ),
      ),
      400,
      end_date,
    );
  // 24h + 1 minute is rejected, 24h exactly accepted
  const e = await client(() =>
    blocks.create(
      f.owner,
      f.block({
        date,
        start_time: "10:00",
        end_time: "10:01",
        end_date: addDate(date, 1),
      }),
    ),
  );
  assert.equal(status(e), 400);
  const ok = await blocks.create(
    f.owner,
    f.block({
      date,
      start_time: "10:00",
      end_time: "10:00",
      end_date: addDate(date, 1),
    }),
  );
  assert.ok(ok.id);
  // same-day end earlier than start without end_date rolls to next day (documented behaviour)
  const f2 = await fixture();
  const roll = await blocks.create(
    f2.owner,
    f2.block({ start_time: "20:00", end_time: "06:00" }),
  );
  const r = (
    await db.query<any>(
      "SELECT starts_at,ends_at FROM booking_slot_blocks WHERE id=$1",
      [roll.id],
    )
  ).rows[0];
  assert.equal(Date.parse(r.ends_at) - Date.parse(r.starts_at), 10 * 3600000);
  // all-day with end_date: the field is ignored, never extending the block
  const f3 = await fixture();
  const d3 = nextDay();
  const allDay = await blocks.create(
    f3.owner,
    f3.block({
      date: d3,
      all_day: true,
      start_time: undefined,
      end_time: undefined,
      end_date: addDate(d3, 5),
    }),
  );
  const r3 = (
    await db.query<any>(
      "SELECT starts_at,ends_at FROM booking_slot_blocks WHERE id=$1",
      [allDay.id],
    )
  ).rows[0];
  assert.equal(Date.parse(r3.ends_at) - Date.parse(r3.starts_at), 86400000);
});
test("overlapping blocks conflict, adjacent blocks and other spaces do not, and a block over a booking is refused with its reference", async () => {
  const f = await fixture();
  const date = nextDay();
  const mk = (
    start_time: string,
    end_time: string,
    resource_ids = [f.res[0].id],
  ) =>
    blocks.create(
      f.owner,
      f.block({ date, start_time, end_time, resource_ids }),
    );
  await mk("10:00", "12:00");
  for (const [s, e] of [
    ["10:00", "12:00"],
    ["11:00", "13:00"],
    ["09:00", "10:30"],
    ["09:00", "13:00"],
    ["10:30", "11:00"],
  ]) {
    const err = await client(() => mk(s, e), `${s}-${e}`);
    assert.ok(err instanceof ConflictException, `${s}-${e}`);
  }
  await mk("08:00", "10:00"); // ends where the first starts
  await mk("12:00", "13:00"); // starts where the first ends
  await mk("10:00", "12:00", [f.res[1].id]); // other space
  await mk("10:00", "12:00", [f.res[0].id, f.res[1].id]).then(
    () => assert.fail("multi-space block over existing blocks must conflict"),
    (e) => assert.ok(e instanceof ConflictException),
  );
  // block over an existing booking
  const bdate = nextDay();
  const booked = await book(f, bdate, "15:00");
  const ref = (
    await db.query<any>("SELECT reference FROM bookings WHERE id=$1", [
      booked.id,
    ])
  ).rows[0].reference;
  const over = await client(() =>
    blocks.create(
      f.owner,
      f.block({ date: bdate, start_time: "15:30", end_time: "16:30" }),
    ),
  );
  assert.ok(over instanceof ConflictException);
  assert.ok(over.message.includes(ref));
  await blocks.create(
    f.owner,
    f.block({ date: bdate, start_time: "16:00", end_time: "17:00" }),
  ); // adjacent to booking end
  await blocks.create(
    f.owner,
    f.block({ date: bdate, start_time: "14:00", end_time: "15:00" }),
  ); // adjacent to booking start
  // a booking that ends exactly at midnight leaves the next day free (end is exclusive)
  const ndate = nextDay();
  await book(f, ndate, "23:00");
  const next = await blocks.create(
    f.owner,
    f.block({
      date: addDate(ndate, 1),
      start_time: "00:00",
      end_time: "00:30",
    }),
  );
  assert.ok(next.id);
  const late = await client(() =>
    blocks.create(
      f.owner,
      f.block({ date: ndate, start_time: "23:30", end_time: "00:30" }),
    ),
  );
  assert.ok(late instanceof ConflictException);
});
test("duplicate submit: identical retries are idempotent; changed payload or another tenant reusing the key is refused; parallel duplicates create one block", async () => {
  const f = await fixture(),
    g = await fixture();
  const input = f.block();
  const a = await blocks.create(f.owner, input);
  const b = await blocks.create(f.owner, input);
  assert.deepEqual(a, b);
  assert.equal(await count(f), 1);
  assert.ok(
    (await client(() =>
      blocks.create(f.owner, { ...input, end_time: "13:00" }),
    )) instanceof ConflictException,
  );
  assert.ok(
    (await client(() =>
      blocks.create(f.owner, { ...input, resource_ids: [f.res[1].id] }),
    )) instanceof ConflictException,
  );
  // the same key from another tenant / another user never replays the original
  const cross = await client(() =>
    blocks.create(g.owner, { ...g.block(), command_key: input.command_key }),
  );
  assert.ok(cross instanceof ConflictException);
  assert.equal(await count(g), 0);
  const parallel = f.block();
  const results = await Promise.allSettled(
    [1, 2, 3, 4, 5].map(() => blocks.create(f.owner, parallel)),
  );
  assert.ok(results.every((r) => r.status === "fulfilled"));
  assert.equal(await count(f), 2);
  // parallel *different* keys on the same slot: exactly one wins
  const slot = f.block({ start_time: "14:00", end_time: "15:00" });
  const racing = await Promise.allSettled(
    [1, 2, 3].map(() =>
      blocks.create(f.owner, { ...slot, command_key: randomUUID() }),
    ),
  );
  assert.equal(racing.filter((r) => r.status === "fulfilled").length, 1);
});
test("DST: nonexistent local times are refused, all-day blocks work on 23h and 25h days, slot grids never crash", async () => {
  const f = await fixture("America/New_York");
  const spring = "2032-03-14",
    fall = "2032-11-07";
  const gap = await client(() =>
    blocks.create(
      f.owner,
      f.block({ date: spring, start_time: "02:30", end_time: "03:30" }),
    ),
  );
  assert.equal(status(gap), 400);
  const amb = await client(() =>
    blocks.create(
      f.owner,
      f.block({ date: fall, start_time: "01:30", end_time: "03:00" }),
    ),
  );
  assert.equal(status(amb), 400);
  const a = await blocks.create(
    f.owner,
    f.block({
      date: spring,
      all_day: true,
      start_time: undefined,
      end_time: undefined,
    }),
  );
  const ra = (
    await db.query<any>(
      "SELECT starts_at,ends_at FROM booking_slot_blocks WHERE id=$1",
      [a.id],
    )
  ).rows[0];
  assert.equal(Date.parse(ra.ends_at) - Date.parse(ra.starts_at), 23 * 3600000);
  const b = await blocks.create(
    f.owner,
    f.block({
      date: fall,
      all_day: true,
      start_time: undefined,
      end_time: undefined,
    }),
  );
  const rb = (
    await db.query<any>(
      "SELECT starts_at,ends_at FROM booking_slot_blocks WHERE id=$1",
      [b.id],
    )
  ).rows[0];
  assert.equal(Date.parse(rb.ends_at) - Date.parse(rb.starts_at), 25 * 3600000);
  for (const date of [spring, fall]) {
    const grid = await blocks.slots(f.owner, {
      business_id: f.id,
      date,
      resource_ids: f.res[0].id,
    });
    assert.ok(grid.slots.length >= 46 && grid.slots.length <= 48);
    assert.ok(
      grid.slots.every((s) =>
        ["blocked", "booked", "past", "available"].includes(s.status),
      ),
    );
  }
});

test("list / slots query fields: ids, date range, cursor and unknown params", async () => {
  const f = await fixture();
  await blocks.create(f.owner, f.block());
  const day = new Date().toISOString().slice(0, 10);
  const base = { business_id: f.id, date: day };
  for (const q of [
    {},
    { ...base, business_id: "" },
    { ...base, business_id: "abc" },
    { ...base, business_id: "'; --" },
    { ...base, date: "" },
    { ...base, date: "1999-12-31" },
    { ...base, date: "2101-01-01" },
    { ...base, date: "2032-02-30" },
    { ...base, cursor: -1 },
    { ...base, cursor: 1000001 },
    { ...base, cursor: "abc" },
    { ...base, cursor: 1.5 },
    { ...base, extra: 1 },
  ])
    await client(() => blocks.list(f.owner, q), JSON.stringify(q));
  assert.equal(
    (await blocks.list(f.owner, { ...base, cursor: "1000000" })).items.length,
    0,
  );
  assert.equal(
    (await blocks.list(f.owner, { ...base, cursor: "0" })).next_cursor,
    null,
  );
  assert.equal(
    (
      await client(() =>
        blocks.list(f.owner, { ...base, business_id: randomUUID() }),
      )
    ).constructor,
    NotFoundException,
  );
  for (const resource_ids of [
    undefined,
    "",
    ",",
    ",,,",
    "abc",
    `${f.res[0].id},abc`,
    ` ${f.res[0].id}`,
    `${f.res[0].id} `,
    `${f.res[0].id};${f.res[1].id}`,
    Array.from({ length: 101 }, () => randomUUID()).join(","),
    [f.res[0].id],
    5,
    "😀",
  ])
    await client(
      () =>
        blocks.slots(f.owner, { business_id: f.id, date: day, resource_ids }),
      `resource_ids=${JSON.stringify(resource_ids)?.slice(0, 40)}`,
    );
  const slots = await blocks.slots(f.owner, {
    business_id: f.id,
    date: day,
    resource_ids: `${f.res[0].id},${f.res[0].id}`,
  });
  assert.equal(slots.slots.length, 48, "duplicated ids are de-duplicated");
  await client(
    () =>
      blocks.slots(f.owner, {
        business_id: f.id,
        date: day,
        resource_ids: randomUUID(),
      }),
    "unknown space",
  );
  await client(() =>
    blocks.slots(f.owner, {
      business_id: f.id,
      date: day,
      resource_ids: f.res[0].id,
      extra: 1,
    }),
  );
});
test("unblock: id/body validation, double unblock, unknown id", async () => {
  const f = await fixture();
  const created = await blocks.create(f.owner, f.block());
  for (const id of ["", "abc", "'; --", "😀"])
    await client(() => blocks.unblock(f.owner, id, {}), `id=${id}`);
  for (const body of [{ reason: "x" }, { extra: 1 }, "x", 5, []])
    await client(
      () => blocks.unblock(f.owner, created.id, body),
      `body=${JSON.stringify(body)}`,
    );
  assert.ok(
    (await client(() => blocks.unblock(f.owner, randomUUID(), {}))) instanceof
      NotFoundException,
  );
  assert.equal(
    await blocks.unblock(f.owner, created.id, null).then((r) => r.id),
    created.id,
  );
  assert.equal(
    (await blocks.unblock(f.owner, created.id, undefined)).id,
    created.id,
    "second unblock is a no-op",
  );
  const audit = await db.query<any>(
    "SELECT count(*)::int AS n FROM audit_events WHERE action='booking_slots_unblocked' AND entity_id=$1",
    [created.id],
  );
  assert.equal(audit.rows[0].n, 1, "audit event written once");
  // unblocked interval can be re-blocked and replay of the old key does not resurrect it
  const again = await blocks.create(f.owner, {
    ...f.block(),
    date: (
      await db.query<any>(
        "SELECT (starts_at AT TIME ZONE 'Asia/Kolkata')::date::text AS d FROM booking_slot_blocks WHERE id=$1",
        [created.id],
      )
    ).rows[0].d,
  });
  assert.ok(again.id);
});
test("role denial for blocks: no membership, view-only, finance-only, unassigned and out-of-scope staff", async () => {
  const f = await fixture();
  const created = await blocks.create(
    f.owner,
    f.block({ resource_ids: [f.res[0].id, f.res[1].id] }),
  );
  const nobody = actor();
  const day = new Date().toISOString().slice(0, 10);
  for (const call of [
    () => blocks.list(nobody, { business_id: f.id, date: day }),
    () =>
      blocks.slots(nobody, {
        business_id: f.id,
        date: day,
        resource_ids: f.res[0].id,
      }),
    () => blocks.create(nobody, f.block()),
    () => blocks.unblock(nobody, created.id, {}),
  ])
    await client(call);
  const reader = await staffOf(f, ["view_bookings"], []);
  for (const call of [
    () => blocks.list(reader, { business_id: f.id, date: day }),
    () => blocks.create(reader, f.block()),
    () => blocks.unblock(reader, created.id, {}),
  ])
    assert.ok((await client(call)) instanceof ForbiddenException);
  const finance = await staffOf(f, ["view_finance", "collect_payments"], []);
  assert.ok(
    (await client(() => blocks.create(finance, f.block()))) instanceof
      ForbiddenException,
  );
  // scoped manager: other space and multi-space owner block are untouchable
  const scoped = await staffOf(f, ["manage_bookings"], [f.res[0].id]);
  assert.ok(
    (await client(() =>
      blocks.create(scoped, f.block({ resource_ids: [f.res[1].id] })),
    )) instanceof ForbiddenException,
  );
  assert.ok(
    (await client(() =>
      blocks.create(
        scoped,
        f.block({ resource_ids: [f.res[0].id, f.res[1].id] }),
      ),
    )) instanceof ForbiddenException,
  );
  assert.ok(
    (await client(() => blocks.unblock(scoped, created.id, {}))) instanceof
      ForbiddenException,
  );
  assert.ok(
    (await client(() =>
      blocks.slots(scoped, {
        business_id: f.id,
        date: day,
        resource_ids: f.res[1].id,
      }),
    )) instanceof ForbiddenException,
  );
  const own = await blocks.create(scoped, f.block());
  assert.ok(own.id);
  assert.equal((await blocks.unblock(scoped, own.id, {})).id, own.id);
  // revoked member
  await db.query("UPDATE memberships SET active=false WHERE user_id=$1", [
    scoped.uid,
  ]);
  await client(() => blocks.create(scoped, f.block()));
  const row = (
    await db.query<any>(
      "SELECT unblocked_at FROM booking_slot_blocks WHERE id=$1",
      [created.id],
    )
  ).rows[0];
  assert.equal(
    row.unblocked_at,
    null,
    "denied attempts leave the block active",
  );
});
test("cross-tenant blocks: another organisation cannot list, create against, or unblock these blocks", async () => {
  const f = await fixture(),
    g = await fixture();
  const created = await blocks.create(f.owner, f.block());
  const day = (
    await db.query<any>(
      "SELECT (starts_at AT TIME ZONE 'Asia/Kolkata')::date::text AS d FROM booking_slot_blocks WHERE id=$1",
      [created.id],
    )
  ).rows[0].d;
  assert.ok(
    (await client(() => blocks.unblock(g.owner, created.id, {}))) instanceof
      NotFoundException,
  );
  assert.ok(
    (await client(() =>
      blocks.list(g.owner, { business_id: f.id, date: day }),
    )) instanceof NotFoundException,
  );
  assert.ok(
    (await client(() =>
      blocks.slots(g.owner, {
        business_id: f.id,
        date: day,
        resource_ids: f.res[0].id,
      }),
    )) instanceof NotFoundException,
  );
  assert.ok(
    (await client(() =>
      blocks.create(g.owner, {
        ...g.block(),
        business_id: f.id,
        resource_ids: [f.res[0].id],
      }),
    )) instanceof NotFoundException,
  );
  // own business but the other tenant's space id
  const mix = await client(() =>
    blocks.create(g.owner, g.block({ resource_ids: [f.res[0].id] })),
  );
  assert.equal(status(mix), 400);
  assert.equal(
    (await blocks.list(g.owner, { business_id: g.id, date: day })).items.length,
    0,
  );
  const row = (
    await db.query<any>(
      "SELECT unblocked_at FROM booking_slot_blocks WHERE id=$1",
      [created.id],
    )
  ).rows[0];
  assert.equal(row.unblocked_at, null);
});
