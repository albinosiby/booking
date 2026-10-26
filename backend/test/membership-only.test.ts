import "reflect-metadata";
import { before, after, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { CourtService } from "../src/court/court.service";
import { PoolService } from "../src/pool/pool.service";
import { AccountsService } from "../src/accounts/accounts.service";
import { AdmissionService } from "../src/admissions/admission.service";
import { addDate, localStamp } from "../src/bookings/booking.inventory";

delete process.env.DATABASE_URL;
delete process.env.DATABASE_MIGRATE;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  workspace = new WorkspaceService(db),
  service = new AdmissionService(db);
const hours = {
  days: [1, 2, 3, 4, 5, 6, 7],
  opens_at: "00:00",
  closes_at: "00:00",
  all_day: true,
  date_from: null,
  date_until: null,
};
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());
async function fixture(type = "badminton") {
  const owner = {
    uid: randomUUID(),
    email: `${randomUUID()}@example.invalid`,
    name: "Membership owner",
  };
  await workspace.createOrganization(owner, {
    name: "Membership test",
    contact_phone: "9876543210",
    currency: "INR",
    location: {
      name: "Venue",
      address_line_1: "Road",
      address_line_2: null,
      city: "Kochi",
      state_code: "KL",
      country_code: "IN",
      postal_code: "682001",
      timezone: "Asia/Kolkata",
    },
  });
  const state = await workspace.workspace(owner);
  const business = await workspace.createBusiness(owner, {
    name: "Membership venue",
    type,
    location_id: state.locations[0].id,
  });
  const resource = randomUUID(),
    plan = randomUUID();
  const planValue = {
    id: plan,
    name: "Monthly membership",
    kind: "coaching",
    allowance: 0,
    track_attendance: false,
    expiry_mode: "after_months",
    expiry_days: null,
    expiry_months: 1,
    expiry_years: null,
    expiry_date: null,
    price_minor: 10000,
    enabled: true,
    availability: hours,
    class_duration_minutes: null,
    class_seats: null,
    coach_id: null,
    renewal: "none",
  };
  let configuration: any;
  if (type === "pool") {
    configuration = JSON.parse(
      readFileSync("examples/pool-configuration.json", "utf8"),
    ).configuration;
    configuration.pools = [
      {
        ...configuration.pools[0],
        id: resource,
        operating: hours,
        tariffs: [
          {
            id: randomUUID(),
            hours,
            rates: [{ duration_minutes: 60, price_minor: 1000 }],
          },
        ],
      },
    ];
    configuration.group_offers = [];
    configuration.plans = [{ ...planValue, pool_ids: [resource] }];
    await new PoolService(db, workspace).configure(owner, business.id, {
      version: 1,
      configuration,
    });
  } else {
    configuration = {
      kind: "court_v1",
      schema_version: 1,
      courts: [
        {
          id: resource,
          name: "Court",
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
              rates: [{ duration_minutes: 60, price_minor: 1000 }],
            },
          ],
        },
      ],
      plans: [{ ...planValue, court_ids: [resource] }],
    };
    await new CourtService(db, workspace).configure(owner, business.id, {
      version: 1,
      configuration,
    });
  }
  await workspace.activate(owner, business.id);
  const today = localStamp(Date.now(), "Asia/Kolkata").slice(0, 10);
  const input = {
    business_id: business.id,
    resource_id: resource,
    plan_id: plan,
    starts_on: today,
    mode: "membership",
    weekdays: [],
    time: "00:00",
    duration_minutes: 60,
    customer: { id: null, name: "Member", phone: "9876543210", email: null },
    payments: [],
    renewed_from: null,
  };
  const preview = await service.preview(owner, input);
  const command = {
    ...input,
    preview_token: preview.preview_token,
    command_key: randomUUID(),
  };
  const created = await service.create(owner, command);
  return {
    owner,
    business,
    resource,
    plan,
    configuration,
    today,
    input,
    preview,
    command,
    id: created.id,
    organization: state.organization!,
  };
}
test("membership-only court and pool plans enroll without allowance, coach, sessions or inventory", async () => {
  for (const type of ["badminton", "pool"]) {
    const venue = await fixture(type);
    const admission = await service.detail(venue.owner, venue.id);
    assert.equal(admission.mode, "membership");
    assert.equal(admission.status, "active");
    assert.equal(admission.allowance, 0);
    assert.equal(admission.remaining, 0);
    assert.equal(admission.can_attend, false);
    assert.deepEqual(admission.sessions, []);
    assert.deepEqual(venue.preview.sessions, []);
    assert.equal(
      (
        await db.query("SELECT 1 FROM bookings WHERE admission_id=$1", [
          venue.id,
        ])
      ).rows.length,
      0,
    );
    await assert.rejects(
      () =>
        service.checkIn(venue.owner, venue.id, {
          command_key: randomUUID(),
          version: admission.version,
        }),
      /Attendance|scheduled/,
    );
    await assert.rejects(
      () =>
        service.preview(venue.owner, {
          ...venue.input,
          mode: "fixed",
          weekdays: [1],
        }),
      /tracking mode/,
    );
    assert.equal((await service.expired(venue.owner, {})).items.length, 0);
  }
});
test("expiry is inclusive in the business timezone and renewals preserve old dues and disappear from Home", async () => {
  const venue = await fixture();
  await db.query(
    "UPDATE admissions SET starts_on=$2,expires_on=$3 WHERE id=$1",
    [venue.id, addDate(venue.today, -30), venue.today],
  );
  assert.equal((await service.expired(venue.owner, {})).items.length, 0);
  await db.query("UPDATE admissions SET expires_on=$2 WHERE id=$1", [
    venue.id,
    addDate(venue.today, -1),
  ]);
  const expired = await service.expired(venue.owner, {});
  assert.equal(expired.items[0].id, venue.id);
  assert.equal(expired.items[0].balance_minor, 10000);
  const previous = await service.detail(venue.owner, venue.id);
  const renewal = {
    ...venue.input,
    customer: previous.customer_snapshot,
    renewed_from: venue.id,
  };
  renewal.customer = {
    id: previous.customer_id,
    name: "Member",
    phone: "9876543210",
    email: null,
  };
  const quote = await service.preview(venue.owner, renewal);
  const created = await service.create(venue.owner, {
    ...renewal,
    preview_token: quote.preview_token,
    command_key: randomUUID(),
  });
  assert.equal((await service.expired(venue.owner, {})).items.length, 0);
  assert.equal(
    (await service.detail(venue.owner, venue.id)).balance_minor,
    10000,
  );
  assert.equal(
    (await service.detail(venue.owner, created.id)).balance_minor,
    10000,
  );
  await assert.rejects(
    () => service.preview(venue.owner, renewal),
    /already been renewed/,
  );
});
test("deletion keeps customer, history and dues, supports idempotent retries and permits later collection", async () => {
  const venue = await fixture();
  const previous = await service.detail(venue.owner, venue.id);
  const command = {
    command_key: randomUUID(),
    version: previous.version,
    reason: "Member no longer attending",
  };
  const result = await service.deleteMembership(venue.owner, venue.id, command);
  assert.deepEqual(
    await service.deleteMembership(venue.owner, venue.id, command),
    result,
  );
  assert.equal((await service.list(venue.owner, {})).items.length, 0);
  const deleted = await service.list(venue.owner, { status: "deleted" });
  assert.equal(deleted.items[0].id, venue.id);
  const detail = await service.detail(venue.owner, venue.id);
  assert.equal(detail.status, "deleted");
  assert.equal(detail.balance_minor, 10000);
  assert.equal(detail.deleted_by, venue.owner.uid);
  assert.equal(
    detail.history.filter((event: any) => event.action === "deleted").length,
    1,
  );
  assert.equal(
    (
      await db.query("SELECT 1 FROM customers WHERE id=$1", [
        detail.customer_id,
      ])
    ).rows.length,
    1,
  );
  const accounts = new AccountsService(db, workspace);
  assert.equal(
    (
      await accounts.overview(venue.owner, {
        from: venue.today,
        until: venue.today,
      })
    ).outstanding_minor,
    10000,
  );
  await service.payments(venue.owner, venue.id, {
    command_key: randomUUID(),
    version: detail.version,
    kind: "collection",
    reason: "Bank verified",
    payments: [
      {
        method: "cash",
        amount_minor: 4000,
        reference: "Cash",
        received_at: new Date().toISOString(),
      },
    ],
  });
  const collected = await service.detail(venue.owner, venue.id);
  assert.equal(collected.balance_minor, 6000);
  assert.equal(collected.status, "deleted");
  assert.equal(collected.payments.length, 1);
  assert.equal(
    (
      await accounts.overview(venue.owner, {
        from: venue.today,
        until: venue.today,
      })
    ).outstanding_minor,
    6000,
  );
});
test("deletion is versioned, tenant-scoped and requires subscription management", async () => {
  const venue = await fixture(),
    other = await fixture();
  const input = {
    command_key: randomUUID(),
    version: 1,
    reason: "Delete membership",
  };
  await assert.rejects(
    () => service.deleteMembership(other.owner, venue.id, input),
    /not found/,
  );
  await assert.rejects(
    () =>
      service.deleteMembership(venue.owner, venue.id, {
        ...input,
        version: 999,
      }),
    /changed/,
  );
  await db.query(
    "UPDATE memberships SET role='staff',permissions='[\"view_bookings\"]'::jsonb WHERE user_id=$1",
    [venue.owner.uid],
  );
  await db.query(
    "INSERT INTO staff_assignments(membership_id,organization_id,business_id,resource_ids) SELECT id,organization_id,$2,'[]'::jsonb FROM memberships WHERE user_id=$1",
    [venue.owner.uid, venue.business.id],
  );
  await assert.rejects(
    () => service.deleteMembership(venue.owner, venue.id, input),
    /permission/,
  );
  await db.query(
    "UPDATE admissions SET starts_on=$2,expires_on=$3 WHERE id=$1",
    [venue.id, addDate(venue.today, -30), addDate(venue.today, -1)],
  );
  const visible = await service.expired(venue.owner, {});
  assert.equal(visible.items.length, 1);
  assert.equal(visible.items[0].balance_minor, 0);
  assert.equal(visible.items[0].net_paid_minor, 0);
});

test("changing a plan to membership-only keeps purchased attendance and deletion releases only future reservations", async () => {
  const venue = await fixture("pool");
  const pools = new PoolService(db, workspace);
  const save = async () => {
    const current = await workspace.business(venue.owner, venue.business.id);
    await pools.configure(venue.owner, venue.business.id, {
      version: current.version,
      configuration: venue.configuration,
    });
    await workspace.activate(venue.owner, venue.business.id);
  };
  const plan = venue.configuration.plans[0];
  plan.kind = "swimming";
  plan.track_attendance = true;
  plan.allowance = 2;
  await save();
  const input = {
    ...venue.input,
    starts_on: addDate(venue.today, 1),
    mode: "fixed",
    weekdays: [1, 2, 3, 4, 5, 6, 7],
    time: "10:00",
  };
  const quote = await service.preview(venue.owner, input);
  const created = await service.create(venue.owner, {
    ...input,
    command_key: randomUUID(),
    preview_token: quote.preview_token,
  });
  plan.track_attendance = false;
  plan.allowance = 0;
  await save();
  const tracked = await service.detail(venue.owner, created.id);
  assert.equal(tracked.mode, "fixed");
  assert.equal(tracked.allowance, 2);
  assert.equal(tracked.plan_snapshot.track_attendance, true);
  assert.equal(tracked.sessions.length, 2);
  assert.ok(
    (
      await db.query(
        "SELECT 1 FROM booking_allocations WHERE booking_id=ANY($1::uuid[])",
        [tracked.sessions.map((s: any) => s.id)],
      )
    ).rows.length > 0,
  );
  await service.deleteMembership(venue.owner, created.id, {
    command_key: randomUUID(),
    version: tracked.version,
    reason: "Member left before classes started",
  });
  const deleted = await service.detail(venue.owner, created.id);
  assert.equal(deleted.status, "deleted");
  assert.equal(deleted.balance_minor, tracked.balance_minor);
  assert.equal(deleted.sessions.length, 2);
  assert.ok(
    deleted.sessions.every((session: any) => session.status === "cancelled"),
  );
  assert.equal(
    (
      await db.query(
        "SELECT 1 FROM booking_allocations WHERE booking_id=ANY($1::uuid[])",
        [tracked.sessions.map((s: any) => s.id)],
      )
    ).rows.length,
    0,
  );
});
