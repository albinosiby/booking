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
import { InvoicesService } from "../src/invoices/invoices.service";
import { BookingService } from "../src/bookings/booking.service";
import { CourtService } from "../src/court/court.service";
import { addDate } from "../src/bookings/booking.inventory";
import { Actor } from "../src/common/auth.guard";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  w = new WorkspaceService(db),
  bookings = new BookingService(db, w),
  invoices = new InvoicesService(db, w, bookings);
const actor = (): Actor => ({
  uid: randomUUID(),
  email: `${randomUUID()}@example.com`,
  name: "Owner",
});
const hours = {
  days: [1, 2, 3, 4, 5, 6, 7],
  opens_at: "06:00",
  closes_at: "00:00",
  date_from: null,
  date_until: null,
};
let day = 0;
const nextDay = () => addDate("2033-01-01", day++);
async function venue() {
  const owner = actor();
  await w.createOrganization(owner, {
    name: "Finance QA",
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
  const ws = await w.workspace(owner),
    b = await w.createBusiness(owner, {
      name: "Badminton",
      type: "badminton",
      location_id: ws.locations[0].id,
    });
  const courts = [1, 2].map((n) => ({
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
        rates: [{ duration_minutes: 60, price_minor: 65000 }],
      },
    ],
  }));
  await new CourtService(db, w).configure(owner, b.id, {
    version: 1,
    configuration: { kind: "court_v1", schema_version: 1, courts },
  });
  await w.activate(owner, b.id);
  const bc = await bookings.catalog(owner);
  return {
    owner,
    business: b.id,
    resources: bc.businesses[0].resources,
    option: bc.businesses[0].resources[0].options[0].id,
  };
}
type V = Awaited<ReturnType<typeof venue>>;
async function staffOf(v: V, permissions: string[]) {
  const staff = actor();
  const inv = await w.invite(v.owner, {
    email: staff.email,
    display_name: "Desk staff",
    role: "staff",
    permissions,
    assignments: [
      { business_id: v.business, resource_ids: [v.resources[0].id] },
    ],
  });
  await w.accept(staff, new URL(inv.invitation_url).searchParams.get("token")!);
  return staff;
}
async function book(
  v: V,
  over: { name?: string; notes?: string; paid?: number; discount?: any } = {},
) {
  const selection: any = {
    business_id: v.business,
    resource_id: v.resources[0].id,
    option_id: v.option,
    date: nextDay(),
    time: "10:00",
    duration_minutes: 60,
    people: 1,
  };
  if (over.discount) selection.discount = over.discount;
  const q = await bookings.quote(v.owner, {
    selection,
    exclude_booking_id: null,
  });
  return bookings.create(v.owner, {
    command_key: randomUUID(),
    selection,
    quote_token: q.quote_token,
    customer: {
      id: null,
      name: over.name ?? "Asha Nair",
      phone: "9876500011",
      email: null,
    },
    notes: over.notes ?? "",
    payments: over.paid
      ? [
          {
            method: "cash",
            amount_minor: over.paid,
            reference: "",
            received_at: new Date().toISOString(),
          },
        ]
      : [],
  });
}
const gen = (who: Actor, id: string, key: unknown = randomUUID()) =>
  invoices.generate(who, id, { command_key: key });
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
const rows = async (booking: string) =>
  Number(
    (
      await db.query<any>(
        "SELECT count(*)::int AS n FROM booking_invoices WHERE booking_id=$1",
        [booking],
      )
    ).rows[0].n,
  );
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());

test("invoice settings: enabled/template types, empty and unknown bodies, owner only", async () => {
  const v = await venue();
  const desk = await staffOf(v, ["view_bookings", "manage_bookings"]);
  for (const body of [
    {},
    { enabled: "true" },
    { enabled: 1 },
    { enabled: null },
    { template: "" },
    { template: null },
    { template: "CLASSIC" },
    { template: "classic " },
    { template: "../../etc/passwd" },
    { template: "__proto__" },
    { template: 5 },
    { template: "😀" },
    { enabled: true, extra: 1 },
    { enabled: true, template: "fancy" },
    null,
    undefined,
    "x",
    [],
    5,
  ])
    await client(
      () => invoices.saveSettings(v.owner, body),
      JSON.stringify(body),
    );
  for (const template of ["classic", "modern", "minimal"])
    assert.equal(
      (await invoices.saveSettings(v.owner, { template })).template,
      template,
    );
  assert.equal(
    (await invoices.saveSettings(v.owner, { enabled: false })).enabled,
    false,
  );
  assert.equal(
    (
      await invoices.saveSettings(v.owner, {
        enabled: false,
        template: "classic",
      })
    ).template,
    "classic",
  );
  assert.ok(
    (await client(() =>
      invoices.saveSettings(desk, { enabled: true }),
    )) instanceof ForbiddenException,
  );
  assert.ok(
    (await client(() =>
      invoices.saveSettings(actor(), { enabled: true }),
    )) instanceof ForbiddenException,
  );
  assert.equal(
    (await invoices.settings(v.owner)).enabled,
    false,
    "denied writes changed nothing",
  );
  assert.ok(
    (await client(() => invoices.settings(actor()))) instanceof
      ForbiddenException,
  );
  // settings of one organisation never leak into another
  const other = await venue();
  assert.equal((await invoices.settings(other.owner)).enabled, true);
});
test("invoice preview: template ids are an exact enum and never reach the filesystem", async () => {
  const v = await venue();
  for (const t of [
    "",
    " ",
    "fancy",
    "Classic",
    "classic ",
    "../classic",
    "classic/../../x",
    "%2e%2e",
    "__proto__",
    "constructor",
    "😀",
    "null",
    "undefined",
  ])
    await client(() => invoices.preview(v.owner, t), t);
  for (const t of [null, undefined, 5, {}, []])
    await client(() => invoices.preview(v.owner, t as any), String(t));
  for (const t of ["classic", "modern", "minimal"]) {
    const r = await invoices.preview(v.owner, t);
    assert.equal(r.bytes.subarray(0, 5).toString(), "%PDF-");
    assert.equal(r.filename, `invoice-${t}-sample.pdf`);
  }
  assert.ok(
    (await client(() => invoices.preview(actor(), "classic"))) instanceof
      ForbiddenException,
  );
});
test("invoice preview renders organisations with unicode, emoji and very long names without failing", async () => {
  const v = await venue();
  for (const name of [
    "Zoë's Sports 李雷 🏸",
    "A".repeat(100),
    "Line\nBreak Arena",
    "<script>alert(1)</script>",
  ]) {
    await db.query(
      "UPDATE organizations SET name=$1 WHERE id=(SELECT organization_id FROM memberships WHERE user_id=$2)",
      [name, v.owner.uid],
    );
    for (const t of ["classic", "modern", "minimal"])
      assert.equal(
        (await invoices.preview(v.owner, t)).bytes.subarray(0, 5).toString(),
        "%PDF-",
        `${name.slice(0, 8)}/${t}`,
      );
  }
});
test("generate: command_key, booking id and unknown fields", async () => {
  const v = await venue();
  const b = await book(v);
  for (const key of ["", " ", null, 5, "abc", "'; --", "0".repeat(36)])
    await client(() => gen(v.owner, b.id, key), String(key));
  await client(
    () => invoices.generate(v.owner, b.id, {}),
    "missing command_key",
  );
  await client(() =>
    invoices.generate(v.owner, b.id, { command_key: randomUUID(), extra: 1 }),
  );
  for (const body of [null, undefined, "x", [], 5])
    await client(() => invoices.generate(v.owner, b.id, body), String(body));
  for (const id of ["", "abc", "'; --", "😀", "default"])
    await client(() => gen(v.owner, id), `booking=${id}`);
  assert.ok(
    (await client(() => gen(v.owner, randomUUID()))) instanceof
      NotFoundException,
  );
  assert.equal(
    await rows(b.id),
    0,
    "no rejected request created an invoice or consumed a number",
  );
  const first = await gen(v.owner, b.id);
  assert.equal(first.invoice_number, "INV-000001");
});
test("generate: duplicate submit, parallel duplicates, unchanged content and changed content", async () => {
  const v = await venue();
  const b = await book(v, { paid: 10000 });
  const key = randomUUID();
  const a = await gen(v.owner, b.id, key);
  const again = await gen(v.owner, b.id, key);
  assert.equal(again.id, a.id);
  assert.equal(again.reused, true);
  // a new key but nothing changed returns the existing invoice rather than numbering a duplicate
  const same = await gen(v.owner, b.id);
  assert.equal(same.id, a.id);
  assert.equal(await rows(b.id), 1);
  // the key belongs to this booking only
  const other = await book(v);
  assert.ok(
    (await client(() => gen(v.owner, other.id, key))) instanceof
      ConflictException,
  );
  // parallel generation with different keys on unchanged content creates exactly one invoice
  const fresh = await book(v);
  const results = await Promise.allSettled(
    [1, 2, 3, 4].map(() => gen(v.owner, fresh.id)),
  );
  assert.ok(results.every((r) => r.status === "fulfilled"));
  assert.equal(await rows(fresh.id), 1);
  assert.equal(new Set(results.map((r: any) => r.value.id)).size, 1);
  // a payment changes the printed content, so a new invoice with the next number is issued
  const cur: any = await bookings.detail(v.owner, b.id);
  await bookings.payments(v.owner, b.id, {
    command_key: randomUUID(),
    version: cur.version,
    kind: "collection",
    reason: "",
    payments: [
      {
        method: "cash",
        amount_minor: 100,
        reference: "",
        received_at: new Date().toISOString(),
      },
    ],
  });
  const next = await gen(v.owner, b.id);
  assert.notEqual(next.id, a.id);
  assert.equal(next.paid_minor, 10100);
  assert.equal(await rows(b.id), 2);
  const numbers = (
    await db.query<any>(
      "SELECT invoice_number FROM booking_invoices WHERE organization_id=(SELECT organization_id FROM memberships WHERE user_id=$1) ORDER BY invoice_number",
      [v.owner.uid],
    )
  ).rows.map((r) => r.invoice_number);
  assert.deepEqual(
    numbers,
    [...new Set(numbers)],
    "invoice numbers are unique",
  );
  // numbers are consecutive per organisation
  numbers.forEach((n, i) =>
    assert.equal(n, `INV-${String(i + 1).padStart(6, "0")}`),
  );
});
test("generate: monetary boundaries - zero total, full discount, fully paid, overpaid by cancellation", async () => {
  const v = await venue();
  const free = await book(v, {
    discount: { type: "percent", value: 10000, reason: "Complimentary" },
  });
  const f = await gen(v.owner, free.id);
  assert.equal(f.total_minor, 0);
  assert.equal(f.balance_minor, 0);
  const paid = await book(v, { paid: 65000 });
  const p = await gen(v.owner, paid.id);
  assert.deepEqual(
    [p.total_minor, p.paid_minor, p.balance_minor],
    [65000, 65000, 0],
  );
  const cancelled = await book(v, { paid: 5000 });
  const c0: any = await bookings.detail(v.owner, cancelled.id);
  await bookings.status(v.owner, cancelled.id, {
    command_key: randomUUID(),
    version: c0.version,
    status: "cancelled",
    reason: "cancelled",
  });
  const c = await gen(v.owner, cancelled.id);
  assert.equal(c.total_minor, 0, "a cancelled booking invoices zero");
  assert.equal(c.paid_minor, 5000);
  assert.ok(c.balance_minor >= 0);
  for (const inv of [f, p, c]) {
    const pdf = await invoices.pdf(v.owner, inv.id);
    assert.equal(pdf.bytes.subarray(0, 5).toString(), "%PDF-");
    assert.equal(pdf.filename, `${inv.invoice_number}.pdf`);
  }
});
test("generate and download: unicode, emoji, markup, newlines and maximum-length customer, notes and discount reason never break the PDF", async () => {
  const v = await venue();
  const samples = [
    { name: "José Müller 李雷", notes: "Café ☕ résumé" },
    { name: "Party 🎉🏸", notes: "Birthday 🎂 for Zoë 😀" },
    { name: "x".repeat(100), notes: "y".repeat(1000) },
    { name: "W".repeat(100), notes: "Wide ".repeat(200) },
    {
      name: "<b>Bold</b> & 'quotes' \"dq\"",
      notes: "%s %d {{x}} ${y} \\n control\u0007",
    },
    { name: "Line\nBreak", notes: "Para1\n\nPara2\r\nPara3\ttab" },
    { name: "العربية שלום", notes: "مرحبا" },
    { name: "ZW​J‍", notes: "‮RTL override" },
    {
      name: "A'; DROP TABLE booking_invoices;--",
      notes: "'); DELETE FROM bookings;--",
    },
  ];
  for (const s of samples) {
    const b = await book(v, {
      ...s,
      discount: {
        type: "amount",
        value: 100,
        reason: "Reason 😀 " + "z".repeat(150),
      },
    });
    let made: any;
    try {
      made = await gen(v.owner, b.id);
    } catch (e) {
      assert.fail(
        `generate failed for ${JSON.stringify(s.name.slice(0, 12))}: ${(e as Error).message}`,
      );
    }
    const pdf = await invoices
      .pdf(v.owner, made.id)
      .catch((e) =>
        assert.fail(
          `pdf failed for ${JSON.stringify(s.name.slice(0, 12))}: ${(e as Error).message}`,
        ),
      );
    assert.equal(pdf.bytes.subarray(0, 5).toString(), "%PDF-");
    assert.ok(pdf.bytes.length > 500);
  }
  assert.ok(
    (await db.query<any>("SELECT count(*)::int AS n FROM bookings")).rows[0]
      .n >= samples.length,
  );
  assert.ok(
    (await db.query<any>("SELECT count(*)::int AS n FROM booking_invoices"))
      .rows[0].n >= samples.length,
  );
});
test("download: id format, unknown id and invoice filename never carry user input", async () => {
  const v = await venue();
  const b = await book(v, { name: "../../evil\r\nSet-Cookie: x=1" });
  const made = await gen(v.owner, b.id);
  // the controller enforces ParseUUIDPipe; the service must at least refuse these
  for (const id of ["", "abc", "'; --", "😀", "../" + made.id])
    await assert.rejects(() => invoices.pdf(v.owner, id), id);
  assert.ok(
    (await client(() => invoices.pdf(v.owner, randomUUID()))) instanceof
      NotFoundException,
  );
  const pdf = await invoices.pdf(v.owner, made.id);
  assert.match(pdf.filename, /^INV-\d{6}\.pdf$/);
});
test("invoices disabled: generate is refused but list and download of earlier invoices still work", async () => {
  const v = await venue();
  const b = await book(v);
  const made = await gen(v.owner, b.id);
  await invoices.saveSettings(v.owner, { enabled: false });
  assert.ok(
    (await client(() => gen(v.owner, b.id))) instanceof ForbiddenException,
  );
  assert.equal((await invoices.list(v.owner, b.id)).enabled, false);
  assert.equal((await invoices.list(v.owner, b.id)).invoices.length, 1);
  assert.equal(
    (await invoices.pdf(v.owner, made.id)).bytes.subarray(0, 5).toString(),
    "%PDF-",
  );
  // replay of an old key while disabled is also refused (generation switch is checked first)
  assert.ok(
    (await client(() => gen(v.owner, b.id, randomUUID()))) instanceof
      ForbiddenException,
  );
});
test("invoice permissions: unassigned/out-of-scope staff, view-only staff and revoked members", async () => {
  const v = await venue();
  const hidden = await (async () => {
    const selection: any = {
      business_id: v.business,
      resource_id: v.resources[1].id,
      option_id: v.option,
      date: nextDay(),
      time: "10:00",
      duration_minutes: 60,
      people: 1,
    };
    const q = await bookings.quote(v.owner, {
      selection,
      exclude_booking_id: null,
    });
    return bookings.create(v.owner, {
      command_key: randomUUID(),
      selection,
      quote_token: q.quote_token,
      customer: {
        id: null,
        name: "Hidden Guest",
        phone: "9876500022",
        email: null,
      },
      notes: "",
      payments: [],
    });
  })();
  const visible = await book(v);
  const scoped = await staffOf(v, ["view_bookings", "manage_bookings"]);
  const hid = await gen(v.owner, hidden.id);
  assert.ok(
    (await client(() => gen(scoped, hidden.id))) instanceof ForbiddenException,
  );
  assert.ok(
    (await client(() => invoices.list(scoped, hidden.id))) instanceof
      ForbiddenException,
  );
  assert.ok(
    (await client(() => invoices.pdf(scoped, hid.id))) instanceof
      ForbiddenException,
  );
  assert.equal(
    (await gen(scoped, visible.id)).invoice_number.startsWith("INV-"),
    true,
  );
  const nobody = actor();
  for (const call of [
    () => gen(nobody, visible.id),
    () => invoices.list(nobody, visible.id),
    () => invoices.pdf(nobody, hid.id),
  ])
    assert.ok((await client(call)) instanceof ForbiddenException);
  const finance = await staffOf(v, ["view_finance"]);
  assert.ok(
    (await client(() => gen(finance, visible.id))) instanceof
      ForbiddenException,
  );
  await db.query("UPDATE memberships SET active=false WHERE user_id=$1", [
    scoped.uid,
  ]);
  assert.ok(
    (await client(() => gen(scoped, visible.id))) instanceof ForbiddenException,
  );
});
test(
  "a staff member who can only view bookings should not be able to issue (number) invoices",
  { todo: "BUG-13" },
  async () => {
    const v = await venue();
    const b = await book(v);
    const reader = await staffOf(v, ["view_bookings"]);
    await assert.rejects(() => gen(reader, b.id));
  },
);
test("cross-tenant invoices: another organisation cannot generate, list or download and sees no numbering", async () => {
  const x = await venue(),
    y = await venue();
  const b = await book(x);
  const made = await gen(x.owner, b.id);
  for (const call of [
    () => gen(y.owner, b.id),
    () => invoices.list(y.owner, b.id),
    () => invoices.pdf(y.owner, made.id),
  ]) {
    const e = await client(call);
    assert.ok(
      e instanceof NotFoundException || e instanceof ForbiddenException,
    );
  }
  const mine = await book(y);
  assert.equal(
    (await gen(y.owner, mine.id)).invoice_number,
    "INV-000001",
    "numbering is per organisation",
  );
  // the same command key in two tenants is independent
  const key = randomUUID();
  const a = await gen(x.owner, (await book(x)).id, key);
  const c = await gen(y.owner, (await book(y)).id, key);
  assert.notEqual(a.id, c.id);
  assert.equal((await invoices.list(y.owner, mine.id)).invoices.length, 1);
});
