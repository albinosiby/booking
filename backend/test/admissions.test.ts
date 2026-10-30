import { SlotBlocksService } from "../src/slot-blocks/slot-blocks.service";
import { AccountsService } from "../src/accounts/accounts.service";
import "reflect-metadata";
import { before, after, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { PoolService } from "../src/pool/pool.service";
import { BookingService } from "../src/bookings/booking.service";
import { AdmissionService } from "../src/admissions/admission.service";
import { expiryFrom, fixedDates } from "../src/admissions/admission.rules";
import { localStamp } from "../src/bookings/booking.inventory";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  workspace = new WorkspaceService(db),
  service = new AdmissionService(db),
  bookings = new BookingService(db, workspace);
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());
async function fixture(mode = "flexible", kind = "swimming") {
  const owner = {
    uid: randomUUID(),
    email: randomUUID() + "@example.com",
    name: "Owner",
  };
  await workspace.createOrganization(owner, {
    name: "Admissions test",
    contact_phone: "9876543210",
    currency: "INR",
    location: {
      name: "Pool",
      address_line_1: "Main road",
      address_line_2: null,
      city: "Kochi",
      state_code: "KL",
      country_code: "IN",
      postal_code: "682001",
      timezone: "UTC",
    },
  });
  const w = await workspace.workspace(owner);
  const b = await workspace.createBusiness(owner, {
    name: "Swimming",
    type: "pool",
    location_id: w.locations[0].id,
  });
  const c = JSON.parse(
    readFileSync("examples/pool-configuration.json", "utf8"),
  ).configuration;
  const today = localStamp(Date.now(), "UTC").slice(0, 10);
  // IDs must be independent across fixtures.
  const ids = new Map<string, string>();
  const replace = (v: any): any =>
    typeof v === "string" && /^[a-f0-9-]{36}$/.test(v)
      ? ids.has(v)
        ? ids.get(v)
        : (ids.set(v, randomUUID()), ids.get(v))
      : Array.isArray(v)
        ? v.map(replace)
        : v && typeof v === "object"
          ? Object.fromEntries(
              Object.entries(v).map(([k, x]) => [k, replace(x)]),
            )
          : v;
  const config = replace(c);
  for (const p of config.pools) {
    p.capacity = 2;
    p.operating = {
      ...p.operating,
      all_day: true,
      opens_at: "00:00",
      closes_at: "00:00",
    };
    p.tariffs = [
      {
        id: randomUUID(),
        hours: p.operating,
        rates: [{ duration_minutes: 60, price_minor: 1000 }],
      },
    ];
  }
  config.group_offers = [];
  for (const p of config.plans) {
    p.allowance = 2;
    if (p.kind === "coaching") p.class_seats = 2;
    p.expiry_mode = "after_start";
    p.expiry_days = 45;
    p.expiry_date = null;
    p.availability = { ...config.pools[0].operating };
  }
  await new PoolService(db, workspace).configure(owner, b.id, {
    version: 1,
    configuration: config,
  });
  await workspace.activate(owner, b.id);
  const plan = config.plans.find((p: any) => p.kind === kind);
  const start = mode === "fixed" ? "2030-06-04" : today;
  const input = {
    business_id: b.id,
    resource_id: config.pools[0].id,
    plan_id: plan.id,
    starts_on: start,
    mode,
    weekdays: mode === "fixed" ? [1, 2, 3, 4, 5, 6, 7] : [],
    time: "09:00",
    duration_minutes: 60,
    customer: { id: null, name: "Swimmer", phone: "9876543210", email: null },
    payments: [],
    renewed_from: null,
  };
  const q = await service.preview(owner, input);
  const command = {
    ...input,
    preview_token: q.preview_token,
    command_key: randomUUID(),
  };
  const created = await service.create(owner, command);
  return { owner, config, input, q, command, id: created.id, today };
}
async function checkin(f: any) {
  const a = await service.detail(f.owner, f.id);
  return service.checkIn(f.owner, f.id, {
    command_key: randomUUID(),
    version: a.version,
  });
}
for (const kind of ["swimming", "coaching"]) {
  test(`${kind}: agreed fee is saved and fully collecting 2300 leaves no configured-price balance`, async () => {
    const f = await fixture("flexible", kind);
    const input = {
      ...f.input,
      plan_amount_minor: 230000,
      payments: [
        {
          method: "cash",
          amount_minor: 230000,
          reference: "",
          received_at: new Date().toISOString(),
        },
      ],
    };
    const q = await service.preview(f.owner, input);
    assert.equal(q.total_minor, 230000);
    assert.equal(q.plan.price_minor, 230000);
    assert.equal(q.plan.configured_price_minor, f.q.total_minor);
    const request = {
      ...input,
      command_key: randomUUID(),
      preview_token: q.preview_token,
    };
    const created = await service.create(f.owner, request);
    assert.deepEqual(await service.create(f.owner, request), created);
    const a = await service.detail(f.owner, created.id);
    assert.equal(a.total_minor, 230000);
    assert.equal(a.net_paid_minor, 230000);
    assert.equal(a.balance_minor, 0);
    assert.equal(a.plan_snapshot.configured_price_minor, f.q.total_minor);
    const audit = a.history.find((h: any) => h.action === "created");
    assert.equal(audit.details.agreed_amount_minor, 230000);
    assert.equal(audit.details.configured_amount_minor, f.q.total_minor);
    const ledger = (
      await db.query<any>(
        `SELECT l.amount_minor FROM finance_lines l JOIN finance_events e ON e.id=l.event_id
      JOIN admission_payments p ON p.id=e.admission_payment_id WHERE p.admission_id=$1 AND l.amount_minor>0`,
        [created.id],
      )
    ).rows;
    assert.deepEqual(
      ledger.map((r: any) => Number(r.amount_minor)),
      [230000],
    );
    assert.equal(
      (await service.preview(f.owner, f.input)).total_minor,
      f.q.total_minor,
    );
  });
}

test("agreed fee supports partial, unpaid and zero-fee admissions and rejects overcollection", async () => {
  const f = await fixture();
  for (const [fee, paid] of [
    [230000, 100000],
    [230000, 0],
    [0, 0],
  ]) {
    const input = {
      ...f.input,
      plan_amount_minor: fee,
      payments: paid
        ? [
            {
              method: "cash",
              amount_minor: paid,
              reference: "",
              received_at: new Date().toISOString(),
            },
          ]
        : [],
    };
    const q = await service.preview(f.owner, input);
    const created = await service.create(f.owner, {
      ...input,
      command_key: randomUUID(),
      preview_token: q.preview_token,
    });
    let a = await service.detail(f.owner, created.id);
    assert.equal(a.balance_minor, fee - paid);
    if (paid) {
      await assert.rejects(
        () =>
          service.payments(f.owner, created.id, {
            command_key: randomUUID(),
            version: a.version,
            kind: "collection",
            reason: "",
            payments: [
              {
                method: "cash",
                amount_minor: fee - paid + 1,
                reference: "",
                received_at: new Date().toISOString(),
              },
            ],
          }),
        /balance|amount|exceed/i,
      );
      await service.payments(f.owner, created.id, {
        command_key: randomUUID(),
        version: a.version,
        kind: "collection",
        reason: "",
        payments: [
          {
            method: "cash",
            amount_minor: fee - paid,
            reference: "",
            received_at: new Date().toISOString(),
          },
        ],
      });
      a = await service.detail(f.owner, created.id);
      assert.equal(a.net_paid_minor, fee);
      assert.equal(a.balance_minor, 0);
    }
  }
});

test("agreed fee validates minor units, binds preview and command keys, and requires collection permission", async () => {
  const f = await fixture();
  for (const value of [-1, 0.5, "230000", null, 100000001])
    await assert.rejects(() =>
      service.preview(f.owner, { ...f.input, plan_amount_minor: value }),
    );
  const input = { ...f.input, plan_amount_minor: 230000 };
  const q = await service.preview(f.owner, input);
  await assert.rejects(
    () =>
      service.create(f.owner, {
        ...input,
        plan_amount_minor: 220000,
        command_key: randomUUID(),
        preview_token: q.preview_token,
      }),
    /changed/i,
  );
  const b = (await workspace.workspace(f.owner)).businesses[0];
  const staff = {
      uid: randomUUID(),
      email: randomUUID() + "@example.com",
      name: "Staff",
    },
    membership = randomUUID();
  await db.query(
    "INSERT INTO memberships(id,organization_id,user_id,email,display_name,role,permissions) VALUES($1,$2,$3,$4,$5,'staff',$6)",
    [
      membership,
      b.organization_id,
      staff.uid,
      staff.email,
      staff.name,
      JSON.stringify(["manage_subscriptions"]),
    ],
  );
  await db.query(
    "INSERT INTO staff_assignments(membership_id,organization_id,business_id) VALUES($1,$2,$3)",
    [membership, b.organization_id, b.id],
  );
  await assert.rejects(
    () => service.preview(staff, input),
    /collection permission/i,
  );
  await assert.rejects(
    () =>
      service.create(staff, {
        ...input,
        command_key: randomUUID(),
        preview_token: q.preview_token,
      }),
    /collection permission/i,
  );
  assert.equal(
    (await service.preview(staff, f.input)).total_minor,
    f.q.total_minor,
  );
  await db.query("UPDATE memberships SET permissions=$1 WHERE id=$2", [
    JSON.stringify(["manage_subscriptions", "collect_payments"]),
    membership,
  ]);
  const authorized = await service.preview(staff, input);
  const request = {
    ...input,
    command_key: randomUUID(),
    preview_token: authorized.preview_token,
  };
  await service.create(staff, request);
  await assert.rejects(
    () => service.create(staff, { ...request, plan_amount_minor: 220000 }),
    /different data/i,
  );
});
test("calendar expiry and insufficient fixed schedules", () => {
  assert.equal(
    expiryFrom({ expiry_mode: "after_months", expiry_months: 1 }, "2028-01-31"),
    "2028-02-29",
  );
  assert.equal(
    expiryFrom({ expiry_mode: "after_years", expiry_years: 1 }, "2028-02-29"),
    "2029-02-28",
  );
  assert.throws(
    () => fixedDates("2030-01-01", "2030-01-02", [1], 25),
    /Only 0/,
  );
});
test("flexible attendance is idempotent, counts once per date, uses shared inventory and posts admission payments", async () => {
  const f = await fixture();
  assert.deepEqual(await service.create(f.owner, f.command), { id: f.id });
  const result = await checkin(f);
  await checkin(f);
  let a = await service.detail(f.owner, f.id);
  assert.equal(a.used, 1);
  assert.equal(a.remaining, 1);
  assert.equal(a.sessions.length, 1);
  const list = await bookings.list(f.owner, { date: f.today });
  assert.equal(list.items[0].admission_id, f.id);
  const selection = {
    business_id: f.input.business_id,
    resource_id: f.input.resource_id,
    option_id: "regular",
    date: f.today,
    time: localStamp(Date.now() + 60000, "UTC").slice(11, 16),
    duration_minutes: 60,
    people: 2,
  };
  await assert.rejects(
    () => bookings.quote(f.owner, { selection, exclude_booking_id: null }),
    /capacity/,
  );
  await assert.rejects(
    () =>
      bookings.status(f.owner, result.visit_id, {
        command_key: randomUUID(),
        version: 1,
        status: "cancelled",
        reason: "Bypass",
      }),
    /Admissions/,
  );
  await service.payments(f.owner, f.id, {
    command_key: randomUUID(),
    version: a.version,
    kind: "collection",
    reason: "",
    payments: [
      {
        method: "cash",
        amount_minor: 1000,
        reference: "",
        received_at: new Date().toISOString(),
      },
    ],
  });
  a = await service.detail(f.owner, f.id);
  assert.equal(a.net_paid_minor, 1000);
  assert.equal(
    (
      await db.query<any>(
        "SELECT count(*)::int n FROM finance_events e JOIN admission_payments p ON p.id=e.admission_payment_id WHERE p.admission_id=$1",
        [f.id],
      )
    ).rows[0].n,
    1,
  );
  const s = a.sessions[0];
  await service.attendance(f.owner, f.id, s.id, {
    command_key: randomUUID(),
    version: s.version,
    attendance: "unmarked",
    reason: "Wrong customer",
  });
  a = await service.detail(f.owner, f.id);
  assert.equal(a.used, 0);
  assert.equal(a.status, "active");
});
test("fixed sessions reserve capacity and count when ended regardless of presence; cancellation preserves history", async () => {
  const f = await fixture("fixed");
  let a = await service.detail(f.owner, f.id);
  assert.equal(a.sessions.length, 2);
  assert.equal(a.used, 0);
  const rows = await bookings.list(f.owner, { date: "2030-06-04" });
  assert.equal(rows.items.length, 1);
  await db.query(
    "UPDATE bookings SET starts_at=now()-interval '2 hours',ends_at=now()-interval '1 hour' WHERE id=$1",
    [a.sessions[0].id],
  );
  a = await service.detail(f.owner, f.id);
  assert.equal(a.used, 1);
  assert.equal(a.sessions[0].admission_attendance, "unmarked");
  await service.cancel(f.owner, f.id, {
    command_key: randomUUID(),
    version: a.version,
    reason: "Customer cancelled",
  });
  a = await service.detail(f.owner, f.id);
  assert.equal(a.status, "cancelled");
  assert.equal(
    a.sessions.filter((s: any) => s.status === "cancelled").length,
    1,
  );
  assert.equal(a.used, 1);
});
test("renew and collect is atomic, preserves previous dues and cannot duplicate the new payment", async () => {
  const f = await fixture();
  await db.query(
    "UPDATE admissions SET starts_on=current_date-10,expires_on=current_date-1 WHERE id=$1",
    [f.id],
  );
  const old = await service.detail(f.owner, f.id);
  const payment = {
    method: "cash",
    amount_minor: f.q.total_minor,
    reference: "Renewal fee",
    received_at: new Date().toISOString(),
  };
  const renewal = {
    ...f.input,
    customer: { ...f.input.customer, id: old.customer_id },
    renewed_from: f.id,
    payments: [payment],
  };
  const excess = {
    ...renewal,
    payments: [{ ...payment, amount_minor: payment.amount_minor + 1 }],
  };
  const invalid = await service.preview(f.owner, excess);
  await assert.rejects(
    () =>
      service.create(f.owner, {
        ...excess,
        preview_token: invalid.preview_token,
        command_key: randomUUID(),
      }),
    /exceeds/,
  );
  assert.equal(
    (
      await db.query<any>(
        "SELECT count(*)::int n FROM admissions WHERE renewed_from=$1",
        [f.id],
      )
    ).rows[0].n,
    0,
  );
  const quote = await service.preview(f.owner, renewal);
  const command = {
    ...renewal,
    preview_token: quote.preview_token,
    command_key: randomUUID(),
  };
  const created = await service.create(f.owner, command);
  assert.deepEqual(await service.create(f.owner, command), created);
  const current = await service.detail(f.owner, created.id);
  assert.equal(current.renewed_from, f.id);
  assert.equal(current.net_paid_minor, quote.total_minor);
  assert.equal(current.balance_minor, 0);
  assert.equal(current.payments.length, 1);
  assert.equal(
    (await service.detail(f.owner, f.id)).balance_minor,
    old.balance_minor,
  );
  assert.equal(
    (
      await db.query<any>(
        "SELECT count(*)::int n FROM finance_events e JOIN admission_payments p ON p.id=e.admission_payment_id WHERE p.admission_id=$1",
        [created.id],
      )
    ).rows[0].n,
    1,
  );
});

test("expired plans block check-in and renew as a separate admission with fresh balance", async () => {
  const f = await fixture();
  await db.query(
    "UPDATE admissions SET starts_on=current_date-10,expires_on=current_date-1 WHERE id=$1",
    [f.id],
  );
  let a = await service.detail(f.owner, f.id);
  assert.equal(a.status, "expired");
  assert.equal(a.remaining, 2);
  await assert.rejects(() => checkin(f), /expired/);
  const input = {
    ...f.input,
    customer: { ...f.input.customer, id: a.customer_id },
    renewed_from: f.id,
  };
  const q = await service.preview(f.owner, input);
  const result = await service.create(f.owner, {
    ...input,
    preview_token: q.preview_token,
    command_key: randomUUID(),
  });
  assert.notEqual(result.id, f.id);
  a = await service.detail(f.owner, result.id);
  assert.equal(a.used, 0);
  assert.equal(a.renewed_from, f.id);
  await assert.rejects(
    () => service.preview(f.owner, input),
    /already been renewed/,
  );
});
test("coaching enforces class size and coach conflicts; unauthorized organizations cannot inspect admissions", async () => {
  const f = await fixture("fixed", "coaching");
  const outsider = {
    uid: randomUUID(),
    email: "other@example.com",
    name: "Other",
  };
  await assert.rejects(() => service.detail(outsider, f.id), /access/);
  const a = await service.detail(f.owner, f.id);
  assert.equal(a.plan_snapshot.kind, "coaching");
  await assert.rejects(
    () =>
      service.attendance(f.owner, f.id, a.sessions[0].id, {
        command_key: randomUUID(),
        version: 1,
        attendance: "present",
        reason: "",
      }),
    /before the session/,
  );
});
test("fixed completion counts all allotted days without attendance", async () => {
  const f = await fixture("fixed");
  await db.query(
    "UPDATE bookings SET starts_at=now()-interval '2 hours',ends_at=now()-interval '1 hour' WHERE admission_id=$1",
    [f.id],
  );
  const a = await service.detail(f.owner, f.id);
  assert.equal(a.status, "completed");
  assert.equal(a.used, 2);
  assert.equal(a.remaining, 0);
  const input = {
    ...f.input,
    customer: { ...f.input.customer, id: a.customer_id },
    renewed_from: f.id,
  };
  const q = await service.preview(f.owner, input);
  const created = await service.create(f.owner, {
    ...input,
    preview_token: q.preview_token,
    command_key: randomUUID(),
  });
  assert.equal((await service.detail(f.owner, created.id)).used, 0);
  assert.equal((await service.detail(f.owner, f.id)).used, 2);
});
test("session cancellation and owner makeup credits preserve history and capacity", async () => {
  const f = await fixture("fixed");
  let a = await service.detail(f.owner, f.id);
  let v = a.sessions[0];
  await service.sessionChange(f.owner, f.id, v.id, {
    command_key: randomUUID(),
    version: v.version,
    action: "cancel",
    reason: "Pool closed",
  });
  assert.equal(
    (
      await db.query("SELECT 1 FROM booking_allocations WHERE booking_id=$1", [
        v.id,
      ])
    ).rows.length,
    0,
  );
  a = await service.detail(f.owner, f.id);
  v = a.sessions.find((s: any) => s.id === v.id);
  await service.sessionChange(f.owner, f.id, v.id, {
    command_key: randomUUID(),
    version: v.version,
    action: "reschedule",
    reason: "Replacement date",
    date: "2030-06-07",
    time: "09:00",
  });
  a = await service.detail(f.owner, f.id);
  v = a.sessions.find((s: any) => s.id === v.id);
  assert.equal(v.status, "confirmed");
  await db.query(
    "UPDATE bookings SET starts_at=now()-interval '2 hours',ends_at=now()-interval '1 hour' WHERE id=$1",
    [v.id],
  );
  assert.equal((await service.detail(f.owner, f.id)).used, 1);
  await service.sessionChange(f.owner, f.id, v.id, {
    command_key: randomUUID(),
    version: v.version,
    action: "waive",
    reason: "Centre cancelled",
  });
  a = await service.detail(f.owner, f.id);
  assert.equal(a.used, 0);
  v = a.sessions.find((s: any) => s.id === v.id);
  const command = {
    command_key: randomUUID(),
    version: v.version,
    action: "reschedule",
    reason: "Makeup lesson",
    date: "2030-06-09",
    time: "09:00",
  };
  await service.sessionChange(f.owner, f.id, v.id, command);
  a = await service.detail(f.owner, f.id);
  assert.equal(a.sessions.length, 3);
  assert.equal(
    a.sessions.find((s: any) => s.id === v.id).admission_waived,
    true,
  );
  await assert.rejects(
    () =>
      service.sessionChange(f.owner, f.id, v.id, {
        ...command,
        command_key: randomUUID(),
      }),
    /already exists/,
  );
});
test("staff attendance permissions and pool assignments are enforced on lists, detail and corrections", async () => {
  const f = await fixture("fixed");
  let a = await service.detail(f.owner, f.id);
  const org = (
    await db.query<any>(
      "SELECT organization_id FROM memberships WHERE user_id=$1",
      [f.owner.uid],
    )
  ).rows[0].organization_id;
  const staff = {
      uid: randomUUID(),
      email: "staff@example.com",
      name: "Staff",
    },
    mid = randomUUID();
  await db.query(
    "INSERT INTO memberships(id,organization_id,user_id,email,display_name,role,permissions) VALUES($1,$2,$3,$4,$5,'staff',$6)",
    [
      mid,
      org,
      staff.uid,
      staff.email,
      staff.name,
      JSON.stringify(["manage_attendance"]),
    ],
  );
  await db.query(
    "INSERT INTO staff_assignments(membership_id,organization_id,business_id,resource_ids) VALUES($1,$2,$3,$4)",
    [mid, org, f.input.business_id, JSON.stringify([f.input.resource_id])],
  );
  assert.equal((await service.list(staff, {})).items.length, 1);
  assert.equal(
    (
      await service.list(staff, {
        business_id: f.input.business_id,
        resource_id: f.input.resource_id,
        plan_id: f.input.plan_id,
      })
    ).items.length,
    1,
  );
  assert.equal(
    (
      await service.list(staff, {
        business_id: f.input.business_id,
        resource_id: f.config.pools[1].id,
        plan_id: f.input.plan_id,
      })
    ).items.length,
    0,
  );
  assert.equal((await service.catalog(staff)).businesses[0].pools.length, 1);
  await assert.rejects(() => service.preview(staff, f.input), /permission/);
  let visit = a.sessions[0];
  await db.query(
    "UPDATE bookings SET starts_at=now()-interval '15 minutes',ends_at=now()+interval '45 minutes' WHERE id=$1",
    [visit.id],
  );
  await service.attendance(staff, f.id, visit.id, {
    command_key: randomUUID(),
    version: visit.version,
    attendance: "present",
    reason: "",
  });
  a = await service.detail(f.owner, f.id);
  visit = a.sessions.find((s: any) => s.id === visit.id);
  await assert.rejects(
    () =>
      service.attendance(staff, f.id, visit.id, {
        command_key: randomUUID(),
        version: visit.version,
        attendance: "absent",
        reason: "Correction",
      }),
    /owner/,
  );
  await db.query(
    "UPDATE staff_assignments SET resource_ids=$1 WHERE membership_id=$2",
    [JSON.stringify([f.config.pools[1].id]), mid],
  );
  assert.equal((await service.list(staff, {})).items.length, 0);
  await assert.rejects(() => service.detail(staff, f.id), /not assigned/);
});
test("plan snapshots stay immutable; refunds are reported as admission refunds", async () => {
  const f = await fixture();
  let a = await service.detail(f.owner, f.id);
  const payments = [
    {
      method: "cash",
      amount_minor: 1000,
      reference: "",
      received_at: new Date().toISOString(),
    },
  ];
  await service.payments(f.owner, f.id, {
    command_key: randomUUID(),
    version: a.version,
    kind: "collection",
    reason: "",
    payments,
  });
  a = await service.detail(f.owner, f.id);
  await service.payments(f.owner, f.id, {
    command_key: randomUUID(),
    version: a.version,
    kind: "refund",
    reason: "Customer request",
    payments,
  });
  a = await service.detail(f.owner, f.id);
  assert.equal(a.net_paid_minor, 0);
  const r = (
    await db.query<any>(
      "SELECT e.kind,l.amount_minor FROM finance_events e JOIN finance_lines l ON l.event_id=e.id JOIN admission_payments p ON p.id=e.admission_payment_id WHERE p.admission_id=$1 AND p.kind='refund'",
      [f.id],
    )
  ).rows[0];
  assert.equal(r.kind, "admission_refund");
  const accounts = new AccountsService(db, workspace);
  const overview = await accounts.overview(f.owner, {
    from: f.today,
    until: f.today,
  });
  assert.equal(overview.selected.collections_minor, 1000);
  assert.equal(overview.selected.refunds_minor, 1000);
  assert.equal(Math.abs(overview.selected.expenses_minor), 0);
  assert.equal(overview.outstanding_minor, 300000);
  const transactions = await accounts.transactions(f.owner, {
    from: f.today,
    until: f.today,
  });
  assert.equal(transactions.items.length, 2);
  assert.ok(
    transactions.items.every(
      (item: any) =>
        item.admission_id === f.id && item.customer_name === "Swimmer",
    ),
  );

  assert.equal(Number(r.amount_minor), -1000);
  const q = await service.preview(f.owner, f.input);
  const config = f.config;
  config.plans[0].price_minor = 400000;
  config.plans[0].allowance = 3;
  await db.query(
    "UPDATE businesses SET configuration=$1,version=version+1 WHERE id=$2",
    [JSON.stringify(config), f.input.business_id],
  );
  assert.equal((await service.detail(f.owner, f.id)).allowance, 2);
  await assert.rejects(
    () =>
      service.create(f.owner, {
        ...f.input,
        preview_token: q.preview_token,
        command_key: randomUUID(),
      }),
    /changed/,
  );
});
test("coaching capacity and overlapping coach assignments are checked before confirmation", async () => {
  const f = await fixture("fixed", "coaching");
  let q = await service.preview(f.owner, f.input);
  await service.create(f.owner, {
    ...f.input,
    preview_token: q.preview_token,
    command_key: randomUUID(),
  });
  await assert.rejects(
    () => service.preview(f.owner, f.input),
    /capacity|full/,
  );
  const g = await fixture("fixed", "coaching");
  const c = g.config;
  c.pools[0].capacity = 20;
  const plan = c.plans.find((p: any) => p.kind === "coaching");
  plan.coach_id = randomUUID();
  const second = { ...plan, id: randomUUID(), name: "Second class" };
  c.plans.push(second);
  await db.query("UPDATE businesses SET configuration=$1 WHERE id=$2", [
    JSON.stringify(c),
    g.input.business_id,
  ]);
  q = await service.preview(g.owner, g.input);
  await service.create(g.owner, {
    ...g.input,
    preview_token: q.preview_token,
    command_key: randomUUID(),
  });
  await assert.rejects(
    () =>
      service.preview(g.owner, {
        ...g.input,
        plan_id: second.id,
        time: "09:30",
      }),
    /coach/,
  );
});
test("concurrent flexible check-ins consume one final day and correction reopens within validity", async () => {
  const f = await fixture();
  await db.query("UPDATE admissions SET allowance=1 WHERE id=$1", [f.id]);
  const a = await service.detail(f.owner, f.id),
    now = localStamp(Date.now(), "UTC");
  const input = {
    version: a.version,
    date: now.slice(0, 10),
    time: now.slice(11, 16),
    duration_minutes: 60,
  };
  const results = await Promise.allSettled([
    service.checkIn(f.owner, f.id, { ...input, command_key: randomUUID() }),
    service.checkIn(f.owner, f.id, { ...input, command_key: randomUUID() }),
  ]);
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
  let current = await service.detail(f.owner, f.id);
  assert.equal(current.used, 1);
  assert.equal(current.status, "completed");
  const v = current.sessions[0];
  await service.attendance(f.owner, f.id, v.id, {
    version: v.version,
    command_key: randomUUID(),
    attendance: "unmarked",
    reason: "Accidental attendance",
  });
  current = await service.detail(f.owner, f.id);
  assert.equal(current.status, "active");
  assert.equal(current.remaining, 1);
  await db.query(
    "UPDATE admissions SET starts_on=current_date-10,expires_on=current_date-1 WHERE id=$1",
    [f.id],
  );
  assert.equal((await service.detail(f.owner, f.id)).status, "expired");
});
test("pool settings cannot remove a pool with active or historical admissions", async () => {
  const f = await fixture();
  const business = (
    await db.query<any>("SELECT * FROM businesses WHERE id=$1", [
      f.input.business_id,
    ])
  ).rows[0];
  const config = structuredClone(f.config);
  config.plans = [];
  config.pools[0].enabled = false;
  await assert.rejects(
    () =>
      new PoolService(db, workspace).configure(f.owner, business.id, {
        version: business.version,
        configuration: config,
      }),
    /active admissions/,
  );
  const changed = structuredClone(f.config);
  changed.pools = changed.pools.filter(
    (p: any) => p.id !== f.input.resource_id,
  );
  changed.plans = [];
  await assert.rejects(
    () =>
      new PoolService(db, workspace).configure(f.owner, business.id, {
        version: business.version,
        configuration: changed,
      }),
    /admission history/,
  );
});
test("cancelling an admission releases future sessions but keeps a swimmer currently in the pool allocated", async () => {
  const f = await fixture();
  await checkin(f);
  const a = await service.detail(f.owner, f.id);
  await service.cancel(f.owner, f.id, {
    command_key: randomUUID(),
    version: a.version,
    reason: "Stop future visits",
  });
  const now = localStamp(Date.now() + 60000, "UTC");
  const selection = {
    business_id: f.input.business_id,
    resource_id: f.input.resource_id,
    option_id: "regular",
    date: now.slice(0, 10),
    time: now.slice(11, 16),
    duration_minutes: 60,
    people: 2,
  };
  await assert.rejects(
    () => bookings.quote(f.owner, { selection, exclude_booking_id: null }),
    /capacity/,
  );
});

test("pool blocks also reject plan attendance despite spare pool capacity", async () => {
  const f = await fixture(),
    now = localStamp(Date.now(), "UTC");
  await new SlotBlocksService(db).create(f.owner, {
    command_key: randomUUID(),
    business_id: f.input.business_id,
    resource_ids: [f.input.resource_id],
    date: now.slice(0, 10),
    all_day: true,
  });
  await assert.rejects(() => checkin(f), /blocked/);
});
test("swimming plans accept 30-minute extensions above the pool minimum in flexible and fixed modes", async () => {
  for (const mode of ["flexible", "fixed"]) {
    const f = await fixture(mode);
    for (const duration_minutes of [60, 90, 120])
      await service.preview(f.owner, { ...f.input, duration_minutes });
    for (const duration_minutes of [30, 61, 75, 105, 1441])
      await assert.rejects(() =>
        service.preview(f.owner, { ...f.input, duration_minutes }),
      );
    const input = { ...f.input, duration_minutes: 90 },
      preview = await service.preview(f.owner, input);
    const saved = await service.create(f.owner, {
      ...input,
      preview_token: preview.preview_token,
      command_key: randomUUID(),
    });
    const detail = await service.detail(f.owner, saved.id);
    assert.equal(detail.schedule.duration_minutes, 90);
  }
});

test("plan rosters filter before pagination and keep previous plans reachable", async () => {
  const f = await fixture();
  const filters = {
    business_id: f.input.business_id,
    resource_id: f.input.resource_id,
    plan_id: f.input.plan_id,
    kind: "swimming",
  };
  assert.equal((await service.list(f.owner, filters)).items.length, 1);
  assert.equal(
    (
      await service.list(f.owner, {
        ...filters,
        resource_id: f.config.pools[1].id,
      })
    ).items.length,
    0,
  );
  assert.equal(
    (await service.list(f.owner, { ...filters, plan_id: randomUUID() })).items
      .length,
    0,
  );
  assert.equal(
    (await service.list(f.owner, { ...filters, kind: "coaching" })).items
      .length,
    0,
  );
  const another = await fixture();
  assert.equal((await service.list(another.owner, filters)).items.length, 0);
  await assert.rejects(() =>
    service.list(f.owner, { ...filters, resource_id: "invalid" }),
  );
  await assert.rejects(() =>
    service.list(f.owner, { ...filters, plan_id: "invalid" }),
  );
  await db.query(
    `INSERT INTO admissions(id,organization_id,business_id,resource_id,customer_id,
    reference,plan_id,plan_snapshot,customer_snapshot,timezone,mode,starts_on,expires_on,
    allowance,total_minor,schedule,created_by)
    SELECT gen_random_uuid(),a.organization_id,a.business_id,a.resource_id,a.customer_id,
    a.reference||'-roster-'||g.n,a.plan_id,a.plan_snapshot,a.customer_snapshot,a.timezone,
    a.mode,a.starts_on,a.expires_on,a.allowance,a.total_minor,a.schedule,a.created_by
    FROM admissions a CROSS JOIN generate_series(1,55) g(n) WHERE a.id=$1`,
    [f.id],
  );
  const page = await service.list(f.owner, filters);
  assert.equal(page.items.length, 50);
  assert.equal(page.next_cursor, 50);
  const next = await service.list(f.owner, {
    ...filters,
    cursor: page.next_cursor,
  });
  assert.equal(next.items.length, 6);
  assert.equal(next.next_cursor, null);
  assert.equal(
    new Set([...page.items, ...next.items].map((a: any) => a.id)).size,
    56,
  );
  assert.equal(
    (await service.list(f.owner, { ...filters, previous_plans: "true" })).items
      .length,
    0,
  );
  const current = (
    await db.query<any>("SELECT configuration FROM businesses WHERE id=$1", [
      f.input.business_id,
    ])
  ).rows[0].configuration;
  current.plans.find((p: any) => p.id === f.input.plan_id).enabled = false;
  await db.query("UPDATE businesses SET configuration=$1 WHERE id=$2", [
    JSON.stringify(current),
    f.input.business_id,
  ]);
  assert.equal(
    (await service.list(f.owner, { ...filters, previous_plans: "true" })).items
      .length,
    50,
  );
  assert.equal(
    (await service.list(another.owner, { ...filters, previous_plans: "true" }))
      .items.length,
    0,
  );
});

test("automatic flexible check-in uses business-local server time and duration, and replay keeps the original visit", async (t) => {
  const f = await fixture();
  await db.query(
    "UPDATE locations SET timezone='Asia/Kolkata' WHERE id=(SELECT location_id FROM businesses WHERE id=$1)",
    [f.input.business_id],
  );
  await db.query(
    `UPDATE admissions SET timezone='Asia/Kolkata',
    starts_on=(now() AT TIME ZONE 'Asia/Kolkata')::date,
    expires_on=(now() AT TIME ZONE 'Asia/Kolkata')::date+45,
    schedule=jsonb_set(schedule,'{duration_minutes}','90') WHERE id=$1`,
    [f.id],
  );
  const detail = await service.detail(f.owner, f.id);
  const request = { command_key: randomUUID(), version: detail.version };
  const before = Date.now();
  const result = await service.checkIn(f.owner, f.id, request);
  const after = Date.now();
  const saved = await service.detail(f.owner, f.id);
  const visit = saved.sessions[0];
  const start = Date.parse(visit.starts_at);
  assert.ok(start >= Math.floor(before / 60000) * 60000);
  assert.ok(start <= Math.floor(after / 60000) * 60000);
  assert.equal(Date.parse(visit.ends_at) - start, 90 * 60000);
  const booking = (
    await db.query<any>("SELECT selection FROM bookings WHERE id=$1", [
      visit.id,
    ])
  ).rows[0];
  assert.equal(
    booking.selection.date,
    localStamp(start, "Asia/Kolkata").slice(0, 10),
  );
  assert.equal(
    booking.selection.time,
    localStamp(start, "Asia/Kolkata").slice(11, 16),
  );
  assert.equal(saved.used, 1);
  t.mock.method(Date, "now", () => after + 5 * 60000);
  assert.deepEqual(await service.checkIn(f.owner, f.id, request), result);
  assert.equal((await service.detail(f.owner, f.id)).sessions.length, 1);
  t.mock.restoreAll();
  await assert.rejects(() =>
    service.checkIn(f.owner, f.id, {
      command_key: randomUUID(),
      version: saved.version,
      time: "09:00",
    }),
  );
});

test("automatic coaching joins the scheduled class interval and preserves attendance and class capacity", async () => {
  const f = await fixture("fixed", "coaching");
  const now = Date.now(),
    today = localStamp(now, "UTC").slice(0, 10);
  const minutesToday =
    new Date(now).getUTCHours() * 60 + new Date(now).getUTCMinutes();
  const start =
    Math.floor(now / 60000) * 60000 - Math.min(15, minutesToday) * 60000;
  const end = start + 60 * 60000;
  await db.query(
    "UPDATE admissions SET starts_on=$1,expires_on=$1::date+45 WHERE id=$2",
    [today, f.id],
  );
  const initial = await service.detail(f.owner, f.id);
  const scheduled = initial.sessions[0];
  await db.query("UPDATE bookings SET starts_at=$1,ends_at=$2 WHERE id=$3", [
    new Date(start).toISOString(),
    new Date(end).toISOString(),
    scheduled.id,
  ]);
  await service.attendance(f.owner, f.id, scheduled.id, {
    command_key: randomUUID(),
    version: scheduled.version,
    attendance: "present",
    reason: "",
  });
  const source = await service.detail(f.owner, f.id);
  assert.equal(source.sessions.length, 2);
  const sourceVisit = source.sessions.find((v: any) => v.id === scheduled.id);
  assert.equal(Date.parse(sourceVisit.starts_at), start);
  async function flexibleStudent(phone: string) {
    const input = {
      ...f.input,
      mode: "flexible",
      weekdays: [],
      starts_on: today,
      customer: { id: null, name: "Flexible student", phone, email: null },
    };
    const preview = await service.preview(f.owner, input);
    return service.create(f.owner, {
      ...input,
      preview_token: preview.preview_token,
      command_key: randomUUID(),
    });
  }
  const second = await flexibleStudent("9000000011");
  const a = await service.detail(f.owner, second.id);
  const request = { command_key: randomUUID(), version: a.version };
  const result = await service.checkIn(f.owner, second.id, request);
  assert.deepEqual(await service.checkIn(f.owner, second.id, request), result);
  const joined = await service.detail(f.owner, second.id);
  assert.equal(joined.sessions.length, 1);
  assert.equal(Date.parse(joined.sessions[0].starts_at), start);
  assert.equal(Date.parse(joined.sessions[0].ends_at), end);
  assert.equal(joined.sessions[0].admission_attendance, "present");
  assert.equal(joined.used, 1);
  const third = await flexibleStudent("9000000012");
  const b = await service.detail(f.owner, third.id);
  await assert.rejects(
    () =>
      service.checkIn(f.owner, third.id, {
        command_key: randomUUID(),
        version: b.version,
      }),
    /class is full|capacity/,
  );
});

test("automatic coaching without a running class fails without creating a visit", async () => {
  const f = await fixture("flexible", "coaching");
  const a = await service.detail(f.owner, f.id);
  await assert.rejects(
    () =>
      service.checkIn(f.owner, f.id, {
        command_key: randomUUID(),
        version: a.version,
      }),
    /No coaching class is running/,
  );
  const after = await service.detail(f.owner, f.id);
  assert.equal(after.sessions.length, 0);
  assert.equal(after.used, 0);
});

test("a flexible-only pool class starts atomically and later students share its interval", async (t) => {
  const f = await fixture("flexible", "coaching");
  const at = Date.parse(f.today + "T12:00:30Z");
  t.mock.method(Date, "now", () => at);
  const a = await service.detail(f.owner, f.id);
  const request = {
    command_key: randomUUID(),
    version: a.version,
    start_class: true,
  };
  const started = await service.checkIn(f.owner, f.id, request);
  assert.equal(started.class_started, true);
  assert.equal(started.local_start, f.today + "T12:00");
  assert.equal(started.marked_at, new Date(at).toISOString());
  assert.deepEqual(await service.checkIn(f.owner, f.id, request), started);
  const input = {
    ...f.input,
    customer: {
      id: null,
      name: "Second flexible",
      phone: "9000000061",
      email: null,
    },
  };
  const quote = await service.preview(f.owner, input);
  const other = await service.create(f.owner, {
    ...input,
    preview_token: quote.preview_token,
    command_key: randomUUID(),
  });
  const detail = await service.detail(f.owner, other.id);
  const joined = await service.checkIn(f.owner, other.id, {
    command_key: randomUUID(),
    version: detail.version,
    start_class: true,
  });
  assert.equal(joined.class_started, false);
  assert.equal(joined.local_start, started.local_start);
  assert.equal(joined.local_end, started.local_end);
  const after = await service.detail(f.owner, f.id);
  assert.equal(after.used, 1);
  assert.equal(after.sessions.length, 1);
  t.mock.restoreAll();
});

test("business off stops new admissions while existing flexible attendance remains available", async () => {
  const f = await fixture();
  const before = (await workspace.workspace(f.owner)).businesses.find(
    (b: any) => b.id === f.input.business_id,
  );
  await workspace.setBookingEnabled(f.owner, before.id, {
    enabled: false,
    version: before.version,
  });
  assert.equal((await service.catalog(f.owner)).businesses.length, 0);
  await assert.rejects(service.preview(f.owner, f.input), /not ready/i);
  await assert.rejects(
    service.create(f.owner, { ...f.command, command_key: randomUUID() }),
    /not ready/i,
  );
  await checkin(f);
  assert.equal((await service.detail(f.owner, f.id)).used, 1);
});
