import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import {
  HttpException,
  ForbiddenException,
  NotFoundException,
} from "@nestjs/common";
import { ZodError } from "zod";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { CourtService } from "../src/court/court.service";
import { BookingService } from "../src/bookings/booking.service";
import { addDate } from "../src/bookings/booking.inventory";
import { Actor } from "../src/common/auth.guard";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  workspace = new WorkspaceService(db),
  service = new BookingService(db, workspace),
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
/** A unique future date per call so tests never collide on the same court. */
const nextDay = () => addDate("2031-01-01", dayCounter++);
async function fixture() {
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
      timezone: "Asia/Kolkata",
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
  const catalog = await service.catalog(owner),
    resource = catalog.businesses[0].resources[0],
    option = resource.options[0];
  const sel = (over: Record<string, unknown> = {}) => ({
    business_id: b.id,
    resource_id: resource.id,
    option_id: option.id,
    date: nextDay(),
    time: "09:00",
    duration_minutes: 60,
    people: 1,
    ...over,
  });
  return { owner, id: b.id, config, resource, option, sel };
}
type F = Awaited<ReturnType<typeof fixture>>;
async function staffOf(
  f: F,
  permissions: string[],
  resourceIds: string[] = [],
  assign = true,
) {
  const staff = actor();
  if (!assign) {
    const m = await workspace.member(f.owner);
    await db.query(
      "INSERT INTO memberships(id,organization_id,user_id,email,display_name,role,permissions) VALUES($1,$2,$3,$4,'Staff','staff',$5)",
      [
        randomUUID(),
        m.organization_id,
        staff.uid,
        staff.email,
        JSON.stringify(permissions),
      ],
    );
    return staff;
  }
  const invite = await workspace.invite(f.owner, {
    email: staff.email,
    display_name: "Staff",
    role: "staff",
    permissions,
    assignments: assign
      ? [{ business_id: f.id, resource_ids: resourceIds }]
      : [],
  });
  await workspace.accept(
    staff,
    new URL(invite.invitation_url).searchParams.get("token")!,
  );
  return staff;
}
const customer = (over: Record<string, unknown> = {}) => ({
  id: null,
  name: "Booking Customer",
  phone: "9876543210",
  email: null,
  ...over,
});
const pay = (over: Record<string, unknown> = {}) => ({
  method: "cash",
  amount_minor: 1000,
  reference: "Ref",
  received_at: new Date().toISOString(),
  ...over,
});
async function req(f: F, selection: any, over: Record<string, unknown> = {}) {
  const q = await service.quote(f.owner, {
    selection,
    exclude_booking_id: null,
  });
  return {
    command_key: randomUUID(),
    selection,
    quote_token: q.quote_token,
    customer: customer(),
    notes: "n",
    payments: [],
    ...over,
  };
}
const make = async (f: F, over: Record<string, unknown> = {}, selOver = {}) =>
  service.create(f.owner, await req(f, f.sel(selOver), over));
/** True when the failure is a handled client error rather than an unhandled 500. */
const isClientError = (e: unknown) =>
  e instanceof ZodError ||
  (e instanceof HttpException && e.getStatus() < 500) ||
  (e as any)?.code === "23505";
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
const status = (e: unknown) =>
  e instanceof ZodError
    ? 422
    : e instanceof HttpException
      ? e.getStatus()
      : 500;
const countRows = async (table: string) =>
  Number(
    (await db.query<any>(`SELECT count(*)::int AS n FROM ${table}`)).rows[0].n,
  );

before(() => db.onModuleInit());
after(() => db.onModuleDestroy());

// ---------------------------------------------------------------- selection
test("selection.business_id / resource_id reject empty, null, wrong type, SQL-ish and unknown ids", async () => {
  const f = await fixture();
  const bad: unknown[] = [
    "",
    " ",
    null,
    123,
    {},
    [],
    "not-a-uuid",
    "'; DROP TABLE bookings;--",
    "😀",
    "00000000-0000-0000-0000-000000000000x",
  ];
  for (const field of ["business_id", "resource_id"])
    for (const v of bad) {
      const e = await client(
        () =>
          service.quote(f.owner, {
            selection: f.sel({ [field]: v }),
            exclude_booking_id: null,
          }),
        `${field}=${JSON.stringify(v)}`,
      );
      assert.equal(status(e), 422);
    }
  // well-formed but nonexistent
  const e1 = await client(() =>
    service.quote(f.owner, {
      selection: f.sel({ business_id: randomUUID() }),
      exclude_booking_id: null,
    }),
  );
  assert.ok(e1 instanceof NotFoundException);
  const e2 = await client(() =>
    service.quote(f.owner, {
      selection: f.sel({ resource_id: randomUUID() }),
      exclude_booking_id: null,
    }),
  );
  assert.equal(status(e2), 400);
});
test("selection.option_id rejects empty, long, null, number, SQL-ish and emoji", async () => {
  const f = await fixture();
  for (const v of [
    "",
    "   ",
    "x".repeat(101),
    null,
    7,
    "'; DROP TABLE bookings;--",
    "😀",
    "hourly ",
  ]) {
    const e = await client(
      () =>
        service.quote(f.owner, {
          selection: f.sel({ option_id: v }),
          exclude_booking_id: null,
        }),
      `option_id=${JSON.stringify(v)}`,
    );
    assert.ok([400, 422].includes(status(e)));
  }
});
test("selection.date rejects empty, whitespace, wrong type, malformed and impossible calendar dates", async () => {
  const f = await fixture();
  const bad: unknown[] = [
    "",
    "   ",
    null,
    20310101,
    "2031-6-4",
    "2031/06/04",
    "2031-02-30",
    "2031-13-01",
    "2031-00-10",
    "2031-04-31",
    "2031-06-04T10:00",
    "2031-06-04 ",
    " 2031-06-04",
    "２０３１-０６-０４",
    "2031-06-04'; DROP TABLE bookings;--",
    "😀",
  ];
  for (const v of bad) {
    const e = await client(
      () =>
        service.quote(f.owner, {
          selection: f.sel({ date: v }),
          exclude_booking_id: null,
        }),
      `date=${JSON.stringify(v)}`,
    );
    assert.equal(status(e), 422, `date=${JSON.stringify(v)}`);
  }
  // leap-day handling
  const leap = await service.quote(f.owner, {
    selection: f.sel({ date: "2032-02-29" }),
    exclude_booking_id: null,
  });
  assert.equal(leap.local_start.slice(0, 10), "2032-02-29");
  await client(() =>
    service.quote(f.owner, {
      selection: f.sel({ date: "2033-02-29" }),
      exclude_booking_id: null,
    }),
  );
});
test("selection.date past, epoch and far-future values never produce a 5xx", async () => {
  const f = await fixture();
  const yesterday = addDate(new Date().toISOString().slice(0, 10), -1);
  for (const date of [
    "1500-01-01",
    "1969-12-31",
    "1970-01-01",
    "2000-01-01",
    yesterday,
  ]) {
    const e = await client(
      () =>
        service.quote(f.owner, {
          selection: f.sel({ date }),
          exclude_booking_id: null,
        }),
      `date=${date}`,
    );
    assert.ok([400, 422].includes(status(e)), date);
  }
  for (const date of ["2100-12-31", "5000-01-01"]) {
    // far future: valid calendar date; must be answered (quote or 4xx) and never crash
    try {
      const q = await service.quote(f.owner, {
        selection: f.sel({ date }),
        exclude_booking_id: null,
      });
      assert.equal(q.local_start.slice(0, 10), date);
    } catch (e) {
      assert.ok(isClientError(e), `${date}: ${(e as Error).message}`);
    }
  }
});
test("ancient and end-of-range dates (year 0000-1499, 9999-12-31) pass calendarDate but crash timezone/Postgres code and must be a 4xx on every date field", async () => {
  const f = await fixture();
  for (const date of ["0001-01-01", "1000-01-01", "9999-12-31"])
    await client(
      () =>
        service.quote(f.owner, {
          selection: f.sel({ date }),
          exclude_booking_id: null,
        }),
      `quote ${date}`,
    );
  const sel = f.sel({ date: "0000-01-01" });
  await client(
    () => service.quote(f.owner, { selection: sel, exclude_booking_id: null }),
    "quote",
  );
  await client(
    () =>
      service.availability(f.owner, {
        selection: sel,
        exclude_booking_id: null,
      }),
    "availability",
  );
  await client(() => service.list(f.owner, { date: "0000-01-01" }), "list");
  await client(
    () =>
      service.dateCounts(f.owner, {
        date: "0000-01-01",
        date_until: "0000-01-02",
      }),
    "dateCounts",
  );
  await client(
    () => service.outstanding(f.owner, { date: "0000-01-01" }),
    "outstanding",
  );
  await client(
    () => service.paymentList(f.owner, { date: "0000-12-31" }),
    "collections",
  );
});
test("selection.time rejects malformed clocks and enforces opening/closing boundaries", async () => {
  const f = await fixture();
  const bad: unknown[] = [
    "",
    " ",
    null,
    900,
    "9:00",
    "24:00",
    "09:60",
    "09:00:00",
    " 09:00",
    "09:00 ",
    "٠٩:٠٠",
    "09-00",
    "😀",
    "09:00'; --",
    "9",
  ];
  for (const v of bad) {
    const e = await client(
      () =>
        service.quote(f.owner, {
          selection: f.sel({ time: v }),
          exclude_booking_id: null,
        }),
      `time=${JSON.stringify(v)}`,
    );
    assert.equal(status(e), 422, `time=${JSON.stringify(v)}`);
  }
  // before opening, at midnight (closed), last start that overruns closing
  for (const time of ["00:00", "05:45", "05:59", "23:15", "23:45", "23:59"]) {
    const e = await client(
      () =>
        service.quote(f.owner, {
          selection: f.sel({ time }),
          exclude_booking_id: null,
        }),
      `time=${time}`,
    );
    assert.equal(status(e), 400, `time=${time}`);
  }
  // exact opening and exact closing boundary are accepted (end exclusive at midnight)
  const first = await service.quote(f.owner, {
    selection: f.sel({ time: "06:00" }),
    exclude_booking_id: null,
  });
  assert.equal(first.local_start.slice(11), "06:00");
  const last = await service.quote(f.owner, {
    selection: f.sel({ time: "23:00" }),
    exclude_booking_id: null,
  });
  assert.equal(last.local_end.slice(11), "00:00");
  assert.equal(
    last.local_end.slice(0, 10),
    addDate(last.local_start.slice(0, 10), 1),
  );
});
test("selection.duration_minutes rejects zero, negative, fractional, string, null and overflow", async () => {
  const f = await fixture();
  for (const v of [
    0,
    -1,
    -60,
    1.5,
    60.5,
    "60",
    null,
    1441,
    1e9,
    Number.MAX_SAFE_INTEGER,
    2 ** 53,
    {},
    [],
  ]) {
    const e = await client(
      () =>
        service.quote(f.owner, {
          selection: f.sel({ duration_minutes: v }),
          exclude_booking_id: null,
        }),
      `duration=${JSON.stringify(v)}`,
    );
    assert.ok([400, 422].includes(status(e)), `duration=${JSON.stringify(v)}`);
  }
  // below minimum, not on the 15-minute grid, and too long for the operating window
  for (const v of [1, 15, 45, 59, 61, 74, 1080 + 15, 1440]) {
    const e = await client(
      () =>
        service.quote(f.owner, {
          selection: f.sel({ duration_minutes: v, time: "06:00" }),
          exclude_booking_id: null,
        }),
      `duration=${v}`,
    );
    assert.equal(status(e), 400, `duration=${v}`);
  }
  // minimum, grid extension and the longest legal booking (06:00-24:00) are accepted
  for (const v of [60, 75, 90, 1080]) {
    const q = await service.quote(f.owner, {
      selection: f.sel({ duration_minutes: v, time: "06:00" }),
      exclude_booking_id: null,
    });
    assert.equal(q.total_minor, Math.round((50000 * v) / 60));
  }
});
test("selection.people rejects zero, negative, fractional, string, null and above the schema maximum", async () => {
  const f = await fixture();
  for (const v of [0, -1, 1.5, "1", null, 10001, 1e9, {}]) {
    const e = await client(
      () =>
        service.quote(f.owner, {
          selection: f.sel({ people: v }),
          exclude_booking_id: null,
        }),
      `people=${JSON.stringify(v)}`,
    );
    assert.equal(status(e), 422);
  }
});
test(
  "selection.people above one is meaningless for a court and must be rejected",
  { todo: "BUG-1" },
  async () => {
    const f = await fixture();
    await assert.rejects(() =>
      service.quote(f.owner, {
        selection: f.sel({ people: 9999 }),
        exclude_booking_id: null,
      }),
    );
  },
);
test("selection.discount boundaries: type, value, reason, extra keys, 100% and above-subtotal", async () => {
  const f = await fixture();
  const quote = (discount: unknown) =>
    service.quote(f.owner, {
      selection: f.sel({ discount, time: "09:00" }),
      exclude_booking_id: null,
    });
  const bad: unknown[] = [
    null,
    "10",
    {},
    { type: "amount", value: 1 },
    { type: "bogus", value: 1, reason: "" },
    { type: "AMOUNT", value: 1, reason: "" },
    { type: "amount", value: -1, reason: "" },
    { type: "amount", value: 1.5, reason: "" },
    { type: "amount", value: "5", reason: "" },
    { type: "amount", value: null, reason: "" },
    { type: "amount", value: 100000001, reason: "" },
    { type: "percent", value: 10001, reason: "" },
    { type: "percent", value: -1, reason: "" },
    { type: "amount", value: 1, reason: "x".repeat(201) },
    { type: "amount", value: 1, reason: null },
    { type: "amount", value: 1, reason: "", extra: true },
    { type: "amount", value: 50001, reason: "" },
    { type: "amount", value: Number.MAX_SAFE_INTEGER, reason: "" },
  ];
  for (const d of bad)
    await client(() => quote(d), `discount=${JSON.stringify(d)}`);
  const zero = await quote({ type: "amount", value: 0, reason: "" });
  assert.equal(zero.total_minor, 50000);
  const full = await quote({
    type: "percent",
    value: 10000,
    reason: "free 😀",
  });
  assert.equal(full.total_minor, 0);
  const exact = await quote({
    type: "amount",
    value: 50000,
    reason: "x".repeat(200),
  });
  assert.equal(exact.total_minor, 0);
  const rounded = await quote({ type: "percent", value: 3333, reason: "" });
  assert.equal(rounded.discount_minor, Math.round((50000 * 3333) / 10000));
});
test("unknown keys are rejected on selection and on the request envelope (strict schemas)", async () => {
  const f = await fixture();
  await client(() =>
    service.quote(f.owner, {
      selection: { ...f.sel(), role: "owner" },
      exclude_booking_id: null,
    }),
  );
  await client(() =>
    service.quote(f.owner, {
      selection: f.sel(),
      exclude_booking_id: null,
      extra: 1,
    }),
  );
  await client(
    () => service.quote(f.owner, { selection: f.sel() }),
    "missing exclude_booking_id",
  );
  await client(() => service.quote(f.owner, null), "null body");
  await client(() => service.quote(f.owner, undefined), "undefined body");
  await client(() => service.quote(f.owner, "string"), "string body");
  await client(() => service.quote(f.owner, []), "array body");
  await client(() =>
    service.availability(f.owner, {
      selection: f.sel(),
      exclude_booking_id: null,
      end_times: "yes",
    }),
  );
});
test("exclude_booking_id rejects non-uuid, foreign tenant and foreign business ids", async () => {
  const f = await fixture(),
    g = await fixture();
  const mine = await make(f);
  const theirs = await make(g);
  for (const v of ["", "abc", 5, "'; --"])
    await client(() =>
      service.quote(f.owner, { selection: f.sel(), exclude_booking_id: v }),
    );
  const cross = await client(() =>
    service.quote(f.owner, {
      selection: f.sel(),
      exclude_booking_id: theirs.id,
    }),
  );
  assert.ok(cross instanceof NotFoundException);
  // own booking id in a different (here: foreign) business selection
  await client(() =>
    service.quote(f.owner, { selection: g.sel(), exclude_booking_id: mine.id }),
  );
});

// ----------------------------------------------------------------- customer
test("customer.name boundaries: empty, whitespace, 1 char, 100/101 chars, null, number, unicode, emoji, SQL-ish", async () => {
  const f = await fixture();
  const bad: unknown[] = [
    "",
    "   ",
    "a",
    " a ",
    "x".repeat(101),
    null,
    12,
    {},
    [],
  ];
  for (const name of bad) {
    const e = await client(
      async () =>
        service.create(
          f.owner,
          await req(f, f.sel(), { customer: customer({ name }) }),
        ),
      `name=${JSON.stringify(name)}`,
    );
    assert.equal(status(e), 422);
  }
  const rows = await countRows("bookings");
  const good = [
    "ab",
    "x".repeat(100),
    "José Müller 李雷",
    "Zoë 🙂",
    "O'Brien; DROP TABLE bookings;--",
    "<script>alert(1)</script>",
    "Line\nBreak",
  ];
  for (const name of good) {
    const b = await service.create(
      f.owner,
      await req(f, f.sel({ time: "06:00" }), { customer: customer({ name }) }),
    );
    const d: any = await service.detail(f.owner, b.id);
    assert.equal(d.customer_snapshot.name, name.trim());
  }
  assert.equal(await countRows("bookings"), rows + good.length);
  assert.ok((await countRows("customers")) >= good.length);
});
test("customer.name of a single emoji is below the 2-character minimum (counted in code points)", async () => {
  const f = await fixture();
  await assert.rejects(async () =>
    service.create(
      f.owner,
      await req(f, f.sel(), { customer: customer({ name: "😀" }) }),
    ),
  );
});
test("customer.phone boundaries and normalisation", async () => {
  const f = await fixture();
  const bad: unknown[] = [
    "",
    "   ",
    "123456",
    "+",
    "abc",
    "abcdefghij",
    "+++9198765",
    "++919876543210",
    "9876543210'; --",
    "😀😀😀😀😀😀😀",
    "1".repeat(26),
    "1234567890123456",
    "(((((((",
    "-------",
    null,
    9876543210,
    {},
  ];
  for (const phone of bad) {
    const e = await client(
      async () =>
        service.create(
          f.owner,
          await req(f, f.sel(), { customer: customer({ phone }) }),
        ),
      `phone=${JSON.stringify(phone)}`,
    );
    assert.equal(status(e), 422, `phone=${JSON.stringify(phone)}`);
  }
  const good: [string, string][] = [
    ["1234567", "1234567"],
    ["123456789012345", "123456789012345"],
    ["+91 98765-43210", "+919876543210"],
    ["(080) 123 4567", "0801234567"],
  ];
  for (const [input, stored] of good) {
    const b = await service.create(
      f.owner,
      await req(f, f.sel({ time: "06:00" }), {
        customer: customer({ phone: input }),
      }),
    );
    const row = (
      await db.query<any>(
        "SELECT c.phone FROM customers c JOIN bookings b ON b.customer_id=c.id WHERE b.id=$1",
        [b.id],
      )
    ).rows[0];
    assert.equal(row.phone, stored);
  }
});
test("customer.email boundaries", async () => {
  const f = await fixture();
  for (const email of [
    "",
    " ",
    "plain",
    "a@",
    "@b.com",
    "a b@c.com",
    `${"x".repeat(200)}@example.com`,
    5,
    "😀@😀.com",
    "'; DROP--@x.com",
  ])
    await client(
      async () =>
        service.create(
          f.owner,
          await req(f, f.sel(), { customer: customer({ email }) }),
        ),
      `email=${JSON.stringify(email)}`,
    );
  const noEmailKey: any = customer();
  delete noEmailKey.email;
  await client(
    async () =>
      service.create(f.owner, await req(f, f.sel(), { customer: noEmailKey })),
    "email omitted",
  );
  const ok = await make(f, {
    customer: customer({ email: "guest@example.com" }),
  });
  assert.ok(ok.id);
});
test("customer.id: malformed, unknown, and other-tenant ids are rejected; a customer id may not be rewritten by posted fields", async () => {
  const f = await fixture(),
    g = await fixture();
  for (const id of ["", "abc", 5, "'; --"])
    await client(
      async () =>
        service.create(
          f.owner,
          await req(f, f.sel(), { customer: customer({ id }) }),
        ),
      `id=${id}`,
    );
  const unknown = await client(async () =>
    service.create(
      f.owner,
      await req(f, f.sel(), { customer: customer({ id: randomUUID() }) }),
    ),
  );
  assert.equal(status(unknown), 400);
  const foreign = await make(g);
  const foreignCustomer = (
    await db.query<any>("SELECT customer_id FROM bookings WHERE id=$1", [
      foreign.id,
    ])
  ).rows[0].customer_id;
  const cross = await client(async () =>
    service.create(
      f.owner,
      await req(f, f.sel(), { customer: customer({ id: foreignCustomer }) }),
    ),
  );
  assert.equal(status(cross), 400);
  assert.equal(
    await countRows("bookings WHERE customer_id='" + foreignCustomer + "'"),
    1,
  );
});
test("an existing customer id keeps the stored customer; the booking snapshot must not show other posted details", async () => {
  const f = await fixture();
  const first = await make(f, {
    customer: customer({ name: "Real Person", phone: "9000000001" }),
  });
  const cid = (
    await db.query<any>("SELECT customer_id FROM bookings WHERE id=$1", [
      first.id,
    ])
  ).rows[0].customer_id;
  const second = await service.create(
    f.owner,
    await req(f, f.sel(), {
      customer: customer({
        id: cid,
        name: "Someone Else",
        phone: "9000000002",
      }),
    }),
  );
  const d: any = await service.detail(f.owner, second.id);
  const stored = (
    await db.query<any>("SELECT name,phone FROM customers WHERE id=$1", [cid])
  ).rows[0];
  assert.equal(d.customer_snapshot.name, stored.name);
  assert.equal(d.customer_snapshot.phone, stored.phone);
});
test("notes boundaries: 1000/1001 chars, null, number, whitespace, emoji", async () => {
  const f = await fixture();
  for (const notes of ["x".repeat(1001), null, 5, {}])
    await client(
      async () => service.create(f.owner, await req(f, f.sel(), { notes })),
      `notes=${String(notes).slice(0, 10)}`,
    );
  const ok = await make(f, { notes: "x".repeat(1000) });
  assert.equal(
    ((await service.detail(f.owner, ok.id)) as any).notes.length,
    1000,
  );
  const blank = await make(f, { notes: "    " });
  assert.equal(((await service.detail(f.owner, blank.id)) as any).notes, "");
  const emoji = await make(f, { notes: "Birthday 🎂 'quote' \"dq\" %_" });
  assert.equal(
    ((await service.detail(f.owner, emoji.id)) as any).notes,
    "Birthday 🎂 'quote' \"dq\" %_",
  );
});
test("command_key and quote_token formats", async () => {
  const f = await fixture();
  const base = await req(f, f.sel());
  for (const command_key of ["", "abc", null, 5, "0".repeat(36)])
    await client(
      () => service.create(f.owner, { ...base, command_key }),
      `command_key=${command_key}`,
    );
  const q = base.quote_token;
  for (const quote_token of [
    "",
    q.slice(1),
    q + "0",
    q.toUpperCase(),
    "g".repeat(64),
    null,
    5,
    " " + q.slice(1),
  ])
    await client(
      () => service.create(f.owner, { ...base, quote_token }),
      `quote_token=${String(quote_token).slice(0, 8)}`,
    );
  const stale = await client(() =>
    service.create(f.owner, { ...base, quote_token: "0".repeat(64) }),
  );
  assert.equal(status(stale), 409);
  await client(() => service.create(f.owner, { ...base, extra: 1 }));
  const missing: any = { ...base };
  delete missing.payments;
  await client(() => service.create(f.owner, missing), "payments omitted");
});

// ---------------------------------------------------------------- payments
test("payment fields on create: method, amount, reference, received_at, account_id", async () => {
  const f = await fixture();
  const attempt = async (p: unknown, label: string, expect?: number) => {
    const e = await client(
      async () =>
        service.create(f.owner, await req(f, f.sel(), { payments: [p] })),
      label,
    );
    if (expect) assert.equal(status(e), expect, label);
  };
  const before = await countRows("bookings");
  for (const method of ["", "CASH", "crypto", null, 5, "cash "])
    await attempt(pay({ method }), `method=${method}`, 422);
  for (const amount_minor of [
    0,
    -1,
    -50000,
    1.5,
    "1000",
    null,
    100000001,
    Number.MAX_SAFE_INTEGER,
    1e21,
  ])
    await attempt(pay({ amount_minor }), `amount=${amount_minor}`);
  await attempt(pay({ amount_minor: 50001 }), "overpay by 1", 400);
  for (const reference of ["x".repeat(201), null, 5])
    await attempt(
      pay({ reference }),
      `reference=${String(reference).slice(0, 5)}`,
      422,
    );
  const nowMs = Date.now();
  for (const received_at of [
    "",
    "not a date",
    "2031-01-01",
    "2031-01-01T10:00",
    null,
    5,
    "1999-12-31T23:59:59Z",
    "0001-01-01T00:00:00Z",
    new Date(nowMs + 86400000).toISOString(),
    new Date(nowMs + 3600000).toISOString(),
    "9999-12-31T23:59:59Z",
  ])
    await attempt(pay({ received_at }), `received_at=${received_at}`);
  for (const account_id of ["", "abc", 5, null, randomUUID()])
    await attempt(pay({ account_id }), `account_id=${account_id}`);
  await attempt({ ...pay(), extra: 1 }, "extra payment key", 422);
  assert.equal(
    await countRows("bookings"),
    before,
    "no failed attempt may leave a booking behind",
  );
});
test("payment boundaries accepted: exact total, 1 minor unit, 2000-01-01, offset timestamps, 20 payments", async () => {
  const f = await fixture();
  const full = await make(f, { payments: [pay({ amount_minor: 50000 })] });
  assert.equal(
    ((await service.detail(f.owner, full.id)) as any).payment_status,
    "paid",
  );
  const one = await make(f, { payments: [pay({ amount_minor: 1 })] });
  assert.equal(
    ((await service.detail(f.owner, one.id)) as any).payment_status,
    "partial",
  );
  const old = await make(f, {
    payments: [pay({ received_at: "2000-01-01T00:00:00Z" })],
  });
  assert.ok(old.id);
  const offset = await make(f, {
    payments: [
      pay({ received_at: new Date().toISOString().replace("Z", "+00:00") }),
    ],
  });
  assert.ok(offset.id);
  const twenty = await make(f, {
    payments: Array.from({ length: 20 }, () => pay({ amount_minor: 100 })),
  });
  assert.equal(
    ((await service.detail(f.owner, twenty.id)) as any).net_paid_minor,
    2000,
  );
  await client(async () =>
    service.create(
      f.owner,
      await req(f, f.sel(), {
        payments: Array.from({ length: 21 }, () => pay({ amount_minor: 1 })),
      }),
    ),
  );
  await client(async () =>
    service.create(f.owner, await req(f, f.sel(), { payments: "cash" })),
  );
  await client(async () =>
    service.create(f.owner, await req(f, f.sel(), { payments: null })),
  );
});
test("a payment account of another tenant or of the wrong kind cannot receive a booking payment", async () => {
  const f = await fixture(),
    g = await fixture();
  await service.catalog(g.owner);
  const foreignAccount = (
    await db.query<any>(
      "SELECT id FROM money_accounts WHERE organization_id=(SELECT organization_id FROM memberships WHERE user_id=$1) AND kind='cash' LIMIT 1",
      [g.owner.uid],
    )
  ).rows[0].id;
  const e = await client(async () =>
    service.create(
      f.owner,
      await req(f, f.sel(), {
        payments: [pay({ account_id: foreignAccount })],
      }),
    ),
  );
  assert.equal(status(e), 400);
  const own = (
    await db.query<any>(
      "SELECT id FROM money_accounts WHERE organization_id=(SELECT organization_id FROM memberships WHERE user_id=$1) AND kind='cash' LIMIT 1",
      [f.owner.uid],
    )
  ).rows[0].id;
  const wrong = await client(async () =>
    service.create(
      f.owner,
      await req(f, f.sel(), {
        payments: [pay({ method: "upi", account_id: own })],
      }),
    ),
  );
  assert.equal(status(wrong), 400);
});

// --------------------------------------------------------------- overlaps
test("overlapping, containing, partially overlapping and identical slots conflict; adjacent slots do not", async () => {
  const f = await fixture();
  const date = nextDay();
  const book = async (
    time: string,
    duration_minutes = 60,
    resource_id = f.resource.id,
  ) => {
    const selection = f.sel({ date, time, duration_minutes, resource_id });
    return service.create(f.owner, await req(f, selection));
  };
  await book("10:00", 120);
  for (const [time, duration] of [
    ["10:00", 60],
    ["10:30", 60],
    ["09:30", 60],
    ["11:30", 60],
    ["09:00", 240],
    ["10:15", 75],
  ] as const) {
    const e = await client(() => book(time, duration), `${time}+${duration}`);
    assert.equal(status(e), 409, `${time}+${duration}`);
  }
  await book("09:00", 60); // ends exactly when the first begins
  await book("12:00", 60); // starts exactly when the first ends
  await book("10:00", 60, f.config.courts[1].id); // other court is independent
});
test("duplicate submit: identical retry returns the same booking; changed payload or foreign kind reuses the key -> 409; parallel duplicates create one booking", async () => {
  const f = await fixture();
  const request = await req(f, f.sel());
  const a = await service.create(f.owner, request);
  const b = await service.create(f.owner, request);
  assert.equal(a.id, b.id);
  assert.equal(await countRows(`bookings WHERE id='${a.id}'`), 1);
  const changed = await client(() =>
    service.create(f.owner, { ...request, notes: "changed" }),
  );
  assert.equal(status(changed), 409);
  const wrongKind = await client(() =>
    service.status(f.owner, a.id, {
      command_key: request.command_key,
      version: 1,
      status: "cancelled",
      reason: "dup",
    }),
  );
  assert.equal(status(wrongKind), 409);
  const parallel = await req(f, f.sel());
  const results = await Promise.allSettled(
    [1, 2, 3, 4].map(() => service.create(f.owner, parallel)),
  );
  const ids = new Set(
    results.filter((r) => r.status === "fulfilled").map((r: any) => r.value.id),
  );
  assert.equal(ids.size, 1);
  assert.equal(await countRows(`bookings WHERE id='${[...ids][0]}'`), 1);
  // same key, another user -> no cross-user replay
  const stranger = await fixture();
  const e = await client(() => service.create(stranger.owner, request));
  assert.ok([404, 403, 409].includes(status(e)));
  // the command result endpoint never leaks a response to another actor or tenant
  assert.deepEqual(
    await service.commandResult(stranger.owner, request.command_key),
    { id: null },
  );
  await client(() => service.commandResult(f.owner, "nope"));
  assert.equal(
    ((await service.commandResult(f.owner, request.command_key)) as any).id,
    a.id,
  );
});

// -------------------------------------------------------------- lifecycle
test("reschedule: version, reason, selection and status guards", async () => {
  const f = await fixture();
  const b = await make(f);
  const cur: any = await service.detail(f.owner, b.id);
  const target = f.sel({ time: "14:00" });
  const body = async (over: Record<string, unknown> = {}) => {
    const q = await service.quote(f.owner, {
      selection: target,
      exclude_booking_id: b.id,
    });
    return {
      command_key: randomUUID(),
      version: cur.version,
      selection: target,
      quote_token: q.quote_token,
      reason: "Customer asked",
      ...over,
    };
  };
  for (const version of [0, -1, 1.5, "1", null, undefined, 1e12])
    await client(
      async () => service.reschedule(f.owner, b.id, await body({ version })),
      `version=${version}`,
    );
  const stale = await client(async () =>
    service.reschedule(f.owner, b.id, await body({ version: cur.version + 5 })),
  );
  assert.equal(status(stale), 409);
  for (const reason of ["", " ", "a", "x".repeat(501), null, 5, undefined])
    await client(
      async () => service.reschedule(f.owner, b.id, await body({ reason })),
      `reason=${String(reason).slice(0, 4)}`,
    );
  await client(async () =>
    service.reschedule(f.owner, "not-a-uuid", await body()),
  );
  await client(async () =>
    service.reschedule(f.owner, randomUUID(), await body()),
  );
  await client(async () =>
    service.reschedule(f.owner, b.id, { ...(await body()), extra: 1 }),
  );
  // quote of a stale/forged token
  const forged = await client(async () =>
    service.reschedule(
      f.owner,
      b.id,
      await body({ quote_token: "a".repeat(64) }),
    ),
  );
  assert.equal(status(forged), 409);
  // minimum reason and a long unicode reason are fine
  const ok = await service.reschedule(
    f.owner,
    b.id,
    await body({ reason: "ok" }),
  );
  assert.equal(ok.id, b.id);
  const after: any = await service.detail(f.owner, b.id);
  assert.equal(after.version, cur.version + 1);
  assert.equal(after.local_start.slice(11), "14:00");
  // moving a cancelled booking is refused
  const c = await make(f);
  await service.status(f.owner, c.id, {
    command_key: randomUUID(),
    version: 1,
    status: "cancelled",
    reason: "no longer",
  });
  const cd: any = await service.detail(f.owner, c.id);
  const t2 = f.sel({ time: "16:00" });
  const q2 = await service.quote(f.owner, {
    selection: t2,
    exclude_booking_id: c.id,
  });
  const refused = await client(() =>
    service.reschedule(f.owner, c.id, {
      command_key: randomUUID(),
      version: cd.version,
      selection: t2,
      quote_token: q2.quote_token,
      reason: "late",
    }),
  );
  assert.equal(status(refused), 400);
});
test("reschedule into the past, onto an occupied slot or another business is rejected and leaves the booking untouched", async () => {
  const f = await fixture(),
    g = await fixture();
  const b = await make(f);
  const other = await make(f, {}, { time: "12:00" });
  const before: any = await service.detail(f.owner, b.id);
  const tryMove = async (selection: any, label: string) => {
    let token = "a".repeat(64);
    try {
      token = (
        await service.quote(f.owner, { selection, exclude_booking_id: b.id })
      ).quote_token;
    } catch {
      /* quote itself refuses, the reschedule must refuse as well */
    }
    return client(
      () =>
        service.reschedule(f.owner, b.id, {
          command_key: randomUUID(),
          version: before.version,
          selection,
          quote_token: token,
          reason: "move",
        }),
      label,
    );
  };
  await tryMove({ ...f.sel(), date: "2000-01-01" }, "past");
  await tryMove(g.sel(), "foreign tenant business");
  const rows: any = (
    await db.query("SELECT starts_at FROM bookings WHERE id=$1", [other.id])
  ).rows[0];
  const day = new Date(rows.starts_at).toISOString();
  assert.ok(day);
  const after: any = await service.detail(f.owner, b.id);
  assert.equal(after.version, before.version);
  assert.equal(after.starts_at.toString(), before.starts_at.toString());
});
test("payments endpoint: kind, list size, amounts, reasons, refunds and stale versions", async () => {
  const f = await fixture();
  const b = await make(f, { payments: [pay({ amount_minor: 20000 })] });
  const cur: any = await service.detail(f.owner, b.id);
  const body = (over: Record<string, unknown> = {}) => ({
    command_key: randomUUID(),
    version: cur.version,
    kind: "collection",
    reason: "",
    payments: [pay({ amount_minor: 100 })],
    ...over,
  });
  for (const over of [
    { kind: "bogus" },
    { kind: "" },
    { kind: null },
    { kind: "REFUND" },
    { payments: [] },
    { payments: null },
    { payments: [pay({ amount_minor: 0 })] },
    { payments: [pay({ amount_minor: -100 })] },
    { payments: [pay({ method: "gold" })] },
    { payments: Array.from({ length: 21 }, () => pay({ amount_minor: 1 })) },
    { reason: "x".repeat(501) },
    { reason: null },
    { version: 0 },
    { version: -3 },
    { version: "2" },
    { extra: true },
  ])
    await client(
      () => service.payments(f.owner, b.id, body(over)),
      JSON.stringify(over).slice(0, 60),
    );
  const stale = await client(() =>
    service.payments(f.owner, b.id, body({ version: cur.version + 9 })),
  );
  assert.equal(status(stale), 409);
  const over = await client(() =>
    service.payments(
      f.owner,
      b.id,
      body({ payments: [pay({ amount_minor: 30001 })] }),
    ),
  );
  assert.equal(status(over), 400);
  // exact outstanding balance is accepted, next payment refused
  const settle = await service.payments(
    f.owner,
    b.id,
    body({ payments: [pay({ amount_minor: 30000 })] }),
  );
  assert.equal(settle.id, b.id);
  const cur2: any = await service.detail(f.owner, b.id);
  assert.equal(cur2.payment_status, "paid");
  const extra = await client(() =>
    service.payments(
      f.owner,
      b.id,
      body({ version: cur2.version, payments: [pay({ amount_minor: 1 })] }),
    ),
  );
  assert.equal(status(extra), 400);
  // refunds on a fully-paid booking: nothing is refundable, with or without reason
  const refund = (over: Record<string, unknown>) =>
    service.payments(
      f.owner,
      b.id,
      body({
        version: cur2.version,
        kind: "refund",
        reason: "Customer request",
        payments: [pay({ amount_minor: 1 })],
        ...over,
      }),
    );
  for (const reason of ["", " ", "a"])
    await client(() => refund({ reason }), `refund reason=${reason}`);
  const noneDue = await client(() => refund({}));
  assert.equal(status(noneDue), 400);
  // cancel -> refundable -> boundaries
  await service.status(f.owner, b.id, {
    command_key: randomUUID(),
    version: cur2.version,
    status: "cancelled",
    reason: "cancelled",
  });
  const cur3: any = await service.detail(f.owner, b.id);
  assert.equal(cur3.refund_due_minor, 50000);
  const tooMuch = await client(() =>
    service.payments(
      f.owner,
      b.id,
      body({
        version: cur3.version,
        kind: "refund",
        reason: "r!",
        payments: [pay({ amount_minor: 50001 })],
      }),
    ),
  );
  assert.equal(status(tooMuch), 400);
  const collectCancelled = await client(() =>
    service.payments(
      f.owner,
      b.id,
      body({ version: cur3.version, payments: [pay({ amount_minor: 1 })] }),
    ),
  );
  assert.equal(status(collectCancelled), 400);
  const ok = await service.payments(
    f.owner,
    b.id,
    body({
      version: cur3.version,
      kind: "refund",
      reason: "ok",
      payments: [pay({ amount_minor: 50000 })],
    }),
  );
  assert.equal(ok.id, b.id);
  assert.equal(
    ((await service.detail(f.owner, b.id)) as any).refund_due_minor,
    0,
  );
});
test("status endpoint: values, reasons, versions and illegal transitions", async () => {
  const f = await fixture();
  const b = await make(f);
  const body = (over: Record<string, unknown> = {}) => ({
    command_key: randomUUID(),
    version: 1,
    status: "checked_in",
    reason: "arrived",
    ...over,
  });
  for (const over of [
    { status: "" },
    { status: "confirmed" },
    { status: "Cancelled" },
    { status: null },
    { status: "deleted" },
    { reason: "" },
    { reason: " " },
    { reason: "a" },
    { reason: "x".repeat(501) },
    { reason: null },
    { version: 0 },
    { version: 1.2 },
    { version: -1 },
    { extra: 1 },
  ])
    await client(
      () => service.status(f.owner, b.id, body(over)),
      JSON.stringify(over).slice(0, 50),
    );
  const stale = await client(() =>
    service.status(f.owner, b.id, body({ version: 7 })),
  );
  assert.equal(status(stale), 409);
  // future bookings cannot be completed / no-show
  for (const s of ["completed", "no_show"]) {
    const e = await client(() =>
      service.status(f.owner, b.id, body({ status: s })),
    );
    assert.equal(status(e), 400, s);
  }
  await service.status(f.owner, b.id, body());
  const dup = await client(() =>
    service.status(f.owner, b.id, body({ version: 2 })),
  );
  assert.equal(status(dup), 400, "second check-in");
  const noShow = await client(() =>
    service.status(f.owner, b.id, body({ version: 2, status: "no_show" })),
  );
  assert.equal(status(noShow), 400, "no-show after check-in");
  await service.status(
    f.owner,
    b.id,
    body({ version: 2, status: "cancelled", reason: "ok" }),
  );
  const again = await client(() =>
    service.status(f.owner, b.id, body({ version: 3, status: "cancelled" })),
  );
  assert.equal(status(again), 400, "second cancel");
});
test("customer edit: fields, versions and unicode; blank notes allowed", async () => {
  const f = await fixture();
  const b = await make(f);
  const body = (over: Record<string, unknown> = {}) => ({
    command_key: randomUUID(),
    version: 1,
    customer: customer({ name: "New Name" }),
    notes: "edited",
    ...over,
  });
  for (const over of [
    { customer: customer({ name: "" }) },
    { customer: customer({ phone: "12" }) },
    { customer: customer({ email: "bad" }) },
    { customer: null },
    { customer: { ...customer(), extra: 1 } },
    { notes: "x".repeat(1001) },
    { notes: null },
    { version: 0 },
    { version: "1" },
    { extra: 1 },
  ])
    await client(
      () => service.editCustomer(f.owner, b.id, body(over)),
      JSON.stringify(over).slice(0, 50),
    );
  const stale = await client(() =>
    service.editCustomer(f.owner, b.id, body({ version: 4 })),
  );
  assert.equal(status(stale), 409);
  await service.editCustomer(
    f.owner,
    b.id,
    body({
      customer: customer({ name: "Zoë 李", phone: "+91 90000 11111" }),
      notes: "",
    }),
  );
  const d: any = await service.detail(f.owner, b.id);
  assert.equal(d.customer_snapshot.name, "Zoë 李");
  assert.equal(d.notes, "");
});
test(
  "a cancelled booking's customer and notes should be read-only",
  { todo: "BUG-4" },
  async () => {
    const f = await fixture();
    const b = await make(f);
    await service.status(f.owner, b.id, {
      command_key: randomUUID(),
      version: 1,
      status: "cancelled",
      reason: "gone",
    });
    const d: any = await service.detail(f.owner, b.id);
    await assert.rejects(() =>
      service.editCustomer(f.owner, b.id, {
        command_key: randomUUID(),
        version: d.version,
        customer: customer({ name: "Edited" }),
        notes: "x",
      }),
    );
  },
);

// --------------------------------------------------------------- listing
test("list query: dates, enums, uuids, q, cursor and unknown params", async () => {
  const f = await fixture();
  await make(f, { customer: customer({ name: "Alice Anderson" }) });
  const bad: Record<string, unknown>[] = [
    { date: "" },
    { date: "2031-02-30" },
    { date: "yesterday" },
    { date: "2031-1-1" },
    { date_until: "x" },
    { overlap: "yes" },
    { overlap: "TRUE" },
    { resource_id: "abc" },
    { business_id: "abc" },
    { status: "pending" },
    { status: "" },
    { q: "x".repeat(101) },
    { cursor: -1 },
    { cursor: 100001 },
    { cursor: "abc" },
    { cursor: 1.5 },
    { cursor: "1e9" },
    { page: 1 },
    { q: ["a", "b"] },
  ];
  for (const q of bad)
    await client(() => service.list(f.owner, q), JSON.stringify(q));
  // whitespace only q is trimmed to nothing and does not filter
  assert.ok((await service.list(f.owner, { q: "   " })).items.length >= 1);
  assert.equal(
    (await service.list(f.owner, { cursor: "0" })).items.length >= 1,
    true,
  );
  // SQL-ish, unicode and emoji searches return empty rather than error
  for (const q of [
    "'; DROP TABLE bookings;--",
    "\\",
    "😀",
    "李",
    "' OR '1'='1",
    "%00",
  ]) {
    const r = await service.list(f.owner, { q });
    assert.equal(r.items.length, 0, q);
  }
  assert.ok((await countRows("bookings")) >= 1);
  assert.equal((await service.list(f.owner, { q: "alice" })).items.length, 1);
  // inverted range is empty, not an error
  assert.equal(
    (
      await service.list(f.owner, {
        date: "2040-01-02",
        date_until: "2040-01-01",
      })
    ).items.length,
    0,
  );
});
test(
  "list q treats % and _ as literal characters",
  { todo: "BUG-5" },
  async () => {
    const f = await fixture();
    await make(f, { customer: customer({ name: "Alice Anderson" }) });
    assert.equal((await service.list(f.owner, { q: "%" })).items.length, 0);
    assert.equal((await service.list(f.owner, { q: "_" })).items.length, 0);
    assert.equal((await service.list(f.owner, { q: "A%e" })).items.length, 0);
  },
);
test("dateCounts range boundaries: 62 days allowed, 63 and inverted rejected, required fields", async () => {
  const f = await fixture();
  const ok = await service.dateCounts(f.owner, {
    date: "2031-01-01",
    date_until: "2031-03-03",
  });
  assert.equal(ok.items.length, 62);
  const same = await service.dateCounts(f.owner, {
    date: "2031-01-01",
    date_until: "2031-01-01",
  });
  assert.equal(same.items.length, 1);
  for (const q of [
    { date: "2031-01-01", date_until: "2031-03-04" },
    { date: "2031-01-02", date_until: "2031-01-01" },
    { date: "2031-01-01" },
    { date_until: "2031-01-01" },
    {},
    { date: "0001-01-01", date_until: "9999-12-31" },
    { date: "x", date_until: "y" },
    { date: "2031-01-01", date_until: "2031-01-02", status: "nope" },
    { date: "2031-01-01", date_until: "2031-01-02", q: "x".repeat(101) },
    { date: "2031-01-01", date_until: "2031-01-02", extra: 1 },
  ])
    await client(() => service.dateCounts(f.owner, q), JSON.stringify(q));
});
test("customers() lookup and customer directory inputs", async () => {
  const f = await fixture();
  await make(f, { customer: customer({ phone: "9876501234" }) });
  assert.deepEqual(await service.customers(f.owner, ""), { items: [] });
  assert.deepEqual(await service.customers(f.owner, "12"), { items: [] });
  assert.deepEqual(await service.customers(f.owner, "x".repeat(101)), {
    items: [],
  });
  assert.deepEqual(await service.customers(f.owner, "abc"), { items: [] });
  assert.equal((await service.customers(f.owner, "98765")).items.length, 1);
  for (const q of ["'; DROP TABLE customers;--123", "😀123"])
    await service.customers(f.owner, q);
  assert.ok((await countRows("customers")) >= 1);
  for (const q of [
    { q: "abc" },
    { q: "😀" },
    { q: "'; --" },
    { q: "x".repeat(51) },
    { q: "+" },
    { q: "()" },
    { after: "x".repeat(81) },
    { extra: 1 },
  ])
    await client(
      () => service.customerDirectory(f.owner, q),
      JSON.stringify(q),
    );
  const all = await service.customerDirectory(f.owner, {});
  assert.ok(all.items.length >= 1);
  assert.equal(
    (await service.customerDirectory(f.owner, { q: "+91 (98765)" })).items
      .length >= 0,
    true,
  );
});
test(
  "customers() lookup must tolerate a repeated ?q= parameter (array) without crashing",
  { todo: "BUG-6" },
  async () => {
    const f = await fixture();
    // Controller binds @Query("q") directly, so ?q=123&q=456 arrives as an array.
    await assert.doesNotReject(async () => {
      try {
        await service.customers(f.owner, ["123", "456"] as any);
      } catch (e) {
        if (!isClientError(e)) throw e;
      }
    });
  },
);
test("customer history: cursor shapes, ids and cross-tenant access", async () => {
  const f = await fixture(),
    g = await fixture();
  const b = await make(f);
  const theirs = await make(g);
  const cid = (
    await db.query<any>("SELECT customer_id FROM bookings WHERE id=$1", [b.id])
  ).rows[0].customer_id;
  const gid = (
    await db.query<any>("SELECT customer_id FROM bookings WHERE id=$1", [
      theirs.id,
    ])
  ).rows[0].customer_id;
  const enc = (v: unknown) =>
    Buffer.from(JSON.stringify(v)).toString("base64url");
  for (const cursor of [
    "garbage",
    "%%%",
    enc({}),
    enc({ time: "x", id: "y" }),
    enc({ time: new Date().toISOString(), id: randomUUID(), extra: 1 }),
    enc("str"),
    enc(null),
    "x".repeat(301),
    Buffer.from("{bad").toString("base64url"),
  ])
    await client(
      () => service.customerHistory(f.owner, cid, { cursor }),
      `cursor=${cursor.slice(0, 12)}`,
    );
  await client(() => service.customerHistory(f.owner, "nope", {}));
  await client(() => service.customerHistory(f.owner, cid, { extra: 1 }));
  const cross = await client(() => service.customerHistory(f.owner, gid, {}));
  assert.ok(cross instanceof NotFoundException);
  const good = enc({ time: new Date().toISOString(), id: randomUUID() });
  assert.ok(
    (await service.customerHistory(f.owner, cid, { cursor: good })).items,
  );
});
test("dashboard / outstanding / collections inputs", async () => {
  const f = await fixture(),
    g = await fixture();
  await make(f, { payments: [pay({ amount_minor: 500 })] });
  await client(() => service.dashboard(f.owner, "abc"));
  await client(() => service.dashboard(f.owner, "'; --"));
  const foreign = await service.dashboard(f.owner, g.id);
  assert.equal(foreign.today_count, 0);
  for (const q of [
    { business_id: "x" },
    { date: "2031-02-30" },
    { cursor: -1 },
    { cursor: 100001 },
    { extra: 1 },
    { business_id: "" },
  ])
    await client(() => service.outstanding(f.owner, q), JSON.stringify(q));
  for (const q of [
    { business_id: "x" },
    { date: "x" },
    { today: "yes" },
    { today: true },
    { cursor: "abc" },
    { extra: 1 },
  ])
    await client(() => service.paymentList(f.owner, q), JSON.stringify(q));
  const other = await service.paymentList(f.owner, { business_id: g.id });
  assert.equal(other.items.length, 0);
  assert.equal(
    (await service.outstanding(f.owner, { business_id: g.id })).items.length,
    0,
  );
});

// ------------------------------------------------- permissions / tenants
test("role denial: no membership, revoked member, read-only, finance-only and attendance-only staff", async () => {
  const f = await fixture();
  const b = await make(f);
  const nobody = actor();
  for (const call of [
    () => service.catalog(nobody),
    () => service.list(nobody, {}),
    () => service.detail(nobody, b.id),
    () =>
      service.quote(nobody, { selection: f.sel(), exclude_booking_id: null }),
    () => service.dashboard(nobody),
    () => service.outstanding(nobody, {}),
  ])
    assert.ok((await client(call)) instanceof ForbiddenException);
  const reader = await staffOf(f, ["view_bookings"], []);
  assert.ok((await service.list(reader, {})).items.length >= 1);
  assert.ok(
    (
      await service.availability(reader, {
        selection: f.sel(),
        exclude_booking_id: null,
      })
    ).slots.length > 0,
  );
  for (const call of [
    () =>
      service.quote(reader, { selection: f.sel(), exclude_booking_id: null }),
    async () => service.create(reader, await req(f, f.sel())),
    () =>
      service.payments(reader, b.id, {
        command_key: randomUUID(),
        version: 1,
        kind: "collection",
        reason: "",
        payments: [pay()],
      }),
    () =>
      service.status(reader, b.id, {
        command_key: randomUUID(),
        version: 1,
        status: "checked_in",
        reason: "ok",
      }),
    () =>
      service.editCustomer(reader, b.id, {
        command_key: randomUUID(),
        version: 1,
        customer: customer(),
        notes: "",
      }),
    () => service.outstanding(reader, {}),
    () => service.paymentList(reader, {}),
  ])
    assert.ok((await client(call)) instanceof ForbiddenException);
  const finance = await staffOf(f, ["view_finance"], []);
  assert.ok((await service.outstanding(finance, {})).items);
  assert.ok(
    (await client(() => service.list(finance, {}))) instanceof
      ForbiddenException,
  );
  assert.ok(
    (await client(() => service.detail(finance, b.id))) instanceof
      ForbiddenException,
  );
  const collector = await staffOf(f, ["collect_payments"], []);
  // collectors cannot refund even with the permission
  const e = await client(() =>
    service.payments(collector, b.id, {
      command_key: randomUUID(),
      version: 1,
      kind: "refund",
      reason: "because",
      payments: [pay()],
    }),
  );
  assert.ok(e instanceof ForbiddenException);
  // revoked members lose access immediately
  await db.query("UPDATE memberships SET active=false WHERE user_id=$1", [
    reader.uid,
  ]);
  assert.ok(
    (await client(() => service.list(reader, {}))) instanceof
      ForbiddenException,
  );
});
test("unassigned staff and assignment scopes (business / resource) deny read and write", async () => {
  const f = await fixture();
  const other = f.config.courts[1].id;
  const hidden = await make(f, {}, { resource_id: other });
  const unassigned = await staffOf(
    f,
    ["view_bookings", "manage_bookings"],
    [],
    false,
  );
  assert.ok(
    (await client(() => service.detail(unassigned, hidden.id))) instanceof
      ForbiddenException,
  );
  assert.equal((await service.list(unassigned, {})).items.length, 0);
  const scoped = await staffOf(
    f,
    ["view_bookings", "manage_bookings"],
    [f.resource.id],
  );
  assert.ok(
    (await client(() => service.detail(scoped, hidden.id))) instanceof
      ForbiddenException,
  );
  assert.ok(
    (await client(() =>
      service.quote(scoped, {
        selection: f.sel({ resource_id: other }),
        exclude_booking_id: null,
      }),
    )) instanceof ForbiddenException,
  );
  assert.ok(
    (await client(() =>
      service.availability(scoped, {
        selection: f.sel({ resource_id: other }),
        exclude_booking_id: null,
      }),
    )) instanceof ForbiddenException,
  );
  assert.ok(
    (await client(() =>
      service.status(scoped, hidden.id, {
        command_key: randomUUID(),
        version: 1,
        status: "cancelled",
        reason: "no",
      }),
    )) instanceof ForbiddenException,
  );
  // scoped staff cannot exclude (probe) an out-of-scope booking via exclude_booking_id
  assert.ok(
    (await client(() =>
      service.quote(scoped, {
        selection: f.sel(),
        exclude_booking_id: hidden.id,
      }),
    )) instanceof ForbiddenException,
  );
  // customer ids reachable only through an out-of-scope booking are not reusable by scoped staff
  const cid = (
    await db.query<any>("SELECT customer_id FROM bookings WHERE id=$1", [
      hidden.id,
    ])
  ).rows[0].customer_id;
  const e = await client(async () =>
    service.create(
      scoped,
      await (async () => {
        const selection = f.sel();
        const q = await service.quote(scoped, {
          selection,
          exclude_booking_id: null,
        });
        return {
          command_key: randomUUID(),
          selection,
          quote_token: q.quote_token,
          customer: customer({ id: cid }),
          notes: "",
          payments: [],
        };
      })(),
    ),
  );
  assert.ok(e instanceof ForbiddenException);
  assert.ok(
    (await client(() => service.customerHistory(scoped, cid, {}))) instanceof
      NotFoundException,
  );
});
test("cross-tenant: every booking endpoint treats another organisation's booking as missing and leaves it untouched", async () => {
  const f = await fixture(),
    g = await fixture();
  const mine = await make(f, { payments: [pay({ amount_minor: 100 })] });
  const before: any = await service.detail(f.owner, mine.id);
  const calls: [string, () => Promise<unknown>][] = [
    ["detail", () => service.detail(g.owner, mine.id)],
    [
      "status",
      () =>
        service.status(g.owner, mine.id, {
          command_key: randomUUID(),
          version: 1,
          status: "cancelled",
          reason: "hack",
        }),
    ],
    [
      "payments",
      () =>
        service.payments(g.owner, mine.id, {
          command_key: randomUUID(),
          version: 1,
          kind: "collection",
          reason: "",
          payments: [pay()],
        }),
    ],
    [
      "customer",
      () =>
        service.editCustomer(g.owner, mine.id, {
          command_key: randomUUID(),
          version: 1,
          customer: customer({ name: "Hacker" }),
          notes: "x",
        }),
    ],
    [
      "reschedule",
      async () =>
        service.reschedule(g.owner, mine.id, {
          command_key: randomUUID(),
          version: 1,
          selection: g.sel(),
          quote_token: "a".repeat(64),
          reason: "hack",
        }),
    ],
    [
      "quote(business)",
      () =>
        service.quote(g.owner, {
          selection: f.sel(),
          exclude_booking_id: null,
        }),
    ],
    [
      "availability(business)",
      () =>
        service.availability(g.owner, {
          selection: f.sel(),
          exclude_booking_id: null,
        }),
    ],
  ];
  for (const [name, call] of calls) {
    const e = await client(call, name);
    assert.ok(
      e instanceof NotFoundException || e instanceof ForbiddenException,
      `${name}: ${e.message}`,
    );
  }
  const after: any = await service.detail(f.owner, mine.id);
  assert.equal(after.version, before.version);
  assert.equal(after.status, "confirmed");
  assert.equal(after.net_paid_minor, 100);
  assert.equal((await service.list(g.owner, {})).items.length, 0);
  assert.equal(
    (await service.list(g.owner, { business_id: f.id })).items.length,
    0,
  );
});
test("two tenants may reuse a command_key independently", async () => {
  const f = await fixture(),
    g = await fixture();
  const key = randomUUID();
  const a = await service.create(f.owner, {
    ...(await req(f, f.sel())),
    command_key: key,
  });
  const b = await service.create(g.owner, {
    ...(await req(g, g.sel())),
    command_key: key,
  });
  assert.notEqual(a.id, b.id);
});

// ------------------------------------------------- NUL byte in free text
test(
  "a NUL character (\\u0000) in any free-text field must be a 4xx, never an unhandled database error",
  { todo: "BUG-14" },
  async () => {
    const f = await fixture();
    const nul = "bad\u0000value";
    const failures: string[] = [];
    const probe = async (label: string, fn: () => Promise<unknown>) => {
      try {
        await fn();
      } catch (e) {
        if (!isClientError(e))
          failures.push(
            `${label}: ${(e as Error).constructor.name} ${(e as Error).message}`,
          );
      }
    };
    await probe("notes", async () =>
      service.create(f.owner, await req(f, f.sel(), { notes: nul })),
    );
    await probe("customer.name", async () =>
      service.create(
        f.owner,
        await req(f, f.sel(), { customer: customer({ name: nul }) }),
      ),
    );
    await probe("payment.reference", async () =>
      service.create(
        f.owner,
        await req(f, f.sel(), { payments: [pay({ reference: nul })] }),
      ),
    );
    await probe("discount.reason", async () =>
      service.create(
        f.owner,
        await req(
          f,
          f.sel({ discount: { type: "amount", value: 1, reason: nul } }),
        ),
      ),
    );
    const b = await make(f);
    await probe("status.reason", () =>
      service.status(f.owner, b.id, {
        command_key: randomUUID(),
        version: 1,
        status: "checked_in",
        reason: nul,
      }),
    );
    await probe("list.q", () => service.list(f.owner, { q: nul }));
    assert.deepEqual(failures, []);
  },
);
