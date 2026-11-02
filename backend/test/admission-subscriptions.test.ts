import "reflect-metadata";
import { before, after, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { CourtService } from "../src/court/court.service";
import { AdmissionService } from "../src/admissions/admission.service";
import { courtConfigurationSchema } from "../src/court/court.validation";
import {
  instalments,
  subscriptionExpiry,
  subscriptionPlan,
} from "../src/admissions/admission.rules";
import { NotificationDispatcher } from "../src/notifications/notification-dispatcher";
import { addDate, localStamp } from "../src/bookings/booking.inventory";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  workspace = new WorkspaceService(db),
  courts = new CourtService(db, workspace),
  service = new AdmissionService(db);
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());
const hours = {
  days: [1, 2, 3, 4, 5, 6, 7],
  opens_at: "00:00",
  closes_at: "00:00",
  all_day: true,
  date_from: null,
  date_until: null,
};
function configuration(subscriptions = true) {
  const ids = [randomUUID()];
  return {
    kind: "court_v1",
    schema_version: 1,
    renewal_reminder_days: 3,
    subscriptions_enabled: subscriptions,
    courts: ids.map((id, n) => ({
      id,
      name: `Court ${n + 1}`,
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
    plans: [],
  };
}
async function fixture(subscriptions = true) {
  const owner = {
    uid: randomUUID(),
    email: randomUUID() + "@example.com",
    name: "Owner",
  };
  await workspace.createOrganization(owner, {
    name: "Court club",
    contact_phone: "9876543210",
    currency: "INR",
    location: {
      name: "Arena",
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
    name: "Badminton club",
    type: "badminton",
    location_id: w.locations[0].id,
  });
  const config = configuration(subscriptions);
  await courts.configure(owner, b.id, { version: 1, configuration: config });
  await workspace.activate(owner, b.id);
  return { owner, config, businessId: b.id };
}
type Fixture = Awaited<ReturnType<typeof fixture>>;
function input(f: Fixture, overrides: Record<string, unknown> = {}) {
  return {
    business_id: f.businessId,
    resource_id: f.config.courts[0].id,
    subscription: { monthly_minor: 150000, months: 3, ends_on: null },
    starts_on: "2030-06-01",
    mode: "fixed",
    weekdays: [1, 2, 3, 4, 5, 6, 7],
    time: "17:00",
    duration_minutes: 60,
    customer: { id: null, name: "Rahul", phone: "9000000001", email: null },
    payments: [],
    renewed_from: null,
    ...overrides,
  };
}
async function enroll(f: Fixture, overrides: Record<string, unknown> = {}) {
  const v = input(f, overrides);
  const q = await service.preview(f.owner, v);
  const created = await service.create(f.owner, {
    ...v,
    preview_token: q.preview_token,
    command_key: randomUUID(),
  });
  return { q, id: created.id as string, input: v };
}
async function collect(f: Fixture, id: string, amount: number) {
  const a = await service.detail(f.owner, id);
  await service.payments(f.owner, id, {
    command_key: randomUUID(),
    version: a.version,
    kind: "collection",
    reason: "",
    payments: [
      {
        method: "cash",
        amount_minor: amount,
        reference: "",
        received_at: new Date().toISOString(),
      },
    ],
  });
}
const today = () => localStamp(Date.now(), "UTC").slice(0, 10);
/** Moves a subscription's monthly fees so they fall around today. */
async function feesAround(id: string, offsets: number[]) {
  const a = (
    await db.query<any>("SELECT plan_snapshot FROM admissions WHERE id=$1", [
      id,
    ])
  ).rows[0];
  const fees = offsets.map((d) => ({
    due_on: addDate(today(), d),
    amount_minor: 150000,
  }));
  a.plan_snapshot.subscription.instalments = fees;
  await db.query(
    "UPDATE admissions SET plan_snapshot=$2,starts_on=$3,expires_on=$4 WHERE id=$1",
    [
      id,
      JSON.stringify(a.plan_snapshot),
      fees[0].due_on,
      addDate(fees.at(-1)!.due_on, 30),
    ],
  );
}

test("monthly fees fall due each month from activation; custom periods are one fee", () => {
  assert.deepEqual(
    instalments("2030-01-31", {
      monthly_minor: 100,
      months: 3,
      ends_on: null,
    }).map((i) => i.due_on),
    ["2030-01-31", "2030-02-28", "2030-03-31"],
  );
  assert.equal(
    subscriptionExpiry("2030-06-01", { months: 3, ends_on: null }),
    "2030-09-01",
  );
  assert.equal(
    subscriptionExpiry("2030-06-01", { months: null, ends_on: "2030-06-20" }),
    "2030-06-20",
  );
  assert.throws(
    () =>
      subscriptionExpiry("2030-06-01", { months: 1, ends_on: "2030-06-20" }),
    /months or a custom end date/,
  );
  const on = { kind: "court_v1", subscriptions_enabled: true };
  assert.throws(
    () =>
      subscriptionPlan({ kind: "court_v1" }, "2030-06-01", {
        monthly_minor: 90000,
        months: 1,
        ends_on: null,
      }),
    /Subscriptions are off for this space/,
  );
  const custom = subscriptionPlan(on, "2030-06-01", {
    monthly_minor: 90000,
    months: null,
    ends_on: "2030-06-20",
  });
  assert.equal(custom.kind, "play");
  assert.equal(custom.price_minor, 90000);
  assert.deepEqual(custom.subscription.instalments, [
    { due_on: "2030-06-01", amount_minor: 90000 },
  ]);
  assert.throws(
    () =>
      subscriptionPlan(on, "2030-06-01", {
        monthly_minor: 99999999,
        months: 2,
        ends_on: null,
      }),
    /maximum amount/,
  );
  // Court plans no longer carry hourly subscription pricing.
  const config = configuration();
  assert.equal(
    courtConfigurationSchema.safeParse({
      ...config,
      plans: [{ pricing: "subscription" }],
    }).success,
    false,
  );
});

test("Subscription stays hidden and refused until Configure turns it on", async () => {
  const f = await fixture(false);
  const off = (await service.catalog(f.owner)).businesses.find(
    (b: any) => b.id === f.businessId,
  );
  assert.equal(off.subscriptions, false);
  await assert.rejects(
    () => service.preview(f.owner, input(f)),
    /Subscriptions are off for this space/,
  );
  const current = await workspace.workspace(f.owner);
  const business = current.businesses.find((b: any) => b.id === f.businessId);
  await courts.configure(f.owner, f.businessId, {
    version: business.version,
    configuration: { ...f.config, subscriptions_enabled: true },
  });
  await workspace.activate(f.owner, f.businessId);
  const on = (await service.catalog(f.owner)).businesses.find(
    (b: any) => b.id === f.businessId,
  );
  assert.equal(on.subscriptions, true);
  assert.equal((await service.preview(f.owner, input(f))).total_minor, 450000);
});

test("a subscription reserves its weekly slot for every month at the agreed monthly fee", async () => {
  const f = await fixture();
  const sub = await enroll(f, { weekdays: [6, 7] });
  assert.equal(sub.q.total_minor, 450000);
  assert.equal(sub.q.expires_on, "2030-09-01");
  const a = await service.detail(f.owner, sub.id);
  assert.equal(a.plan_snapshot.name, "Subscription");
  assert.equal(a.plan_snapshot.subscription.monthly_minor, 150000);
  assert.equal(a.plan_snapshot.subscription.instalments.length, 3);
  // 2030-06-01 to 2030-09-01 (inclusive): 28 weekend days, all reserved.
  assert.equal(a.allowance, 28);
  assert.equal(a.sessions.length, 28);
  assert.equal(a.due_now_minor, 0);
  assert.equal(a.next_due_on, "2030-06-01");
  assert.equal(
    (await service.list(f.owner, { subscription: "true" })).items.length,
    1,
  );
  assert.equal(
    (await service.list(f.owner, { subscription: "false" })).items.length,
    0,
  );
  // The held slot is taken for the next person.
  await assert.rejects(
    () =>
      service.preview(
        f.owner,
        input(f, {
          weekdays: [6],
          customer: {
            id: null,
            name: "Asha",
            phone: "9000000002",
            email: null,
          },
        }),
      ),
    /held by Rahul/,
  );
  const chart = await service.slotChart(f.owner, {
    business_id: f.businessId,
    resource_id: f.config.courts[0].id,
    subscription: { months: 1, ends_on: null },
    starts_on: "2030-06-01",
    weekdays: [6],
    duration_minutes: 60,
  });
  assert.equal(
    chart.slots.find((t: any) => t.time === "17:00")!.status,
    "taken",
  );
  // A plan or a subscription, never both or neither; the fee is the amount.
  await assert.rejects(
    () => service.preview(f.owner, input(f, { plan_id: randomUUID() })),
    /plan or enter a subscription/,
  );
  await assert.rejects(
    () => service.preview(f.owner, input(f, { subscription: undefined })),
    /plan or enter a subscription/,
  );
  await assert.rejects(
    () =>
      service.preview(
        f.owner,
        input(f, { plan_amount_minor: 1, time: "06:00" }),
      ),
    /monthly fee/,
  );
  await assert.rejects(
    () =>
      service.preview(
        f.owner,
        input(f, { mode: "flexible", weekdays: [], time: "06:00" }),
      ),
    /weekly time slot/,
  );
});

test("Home lists started months to collect and the next month due soon", async () => {
  const f = await fixture();
  const sub = await enroll(f, { weekdays: [6, 7] });
  await feesAround(sub.id, [-30, 0, 2]);
  const reminders = (group: string) =>
    service.paymentReminders(f.owner, { group });
  const unpaid = await reminders("unpaid");
  assert.equal(unpaid.items.length, 1);
  assert.equal(unpaid.items[0].due_now_minor, 300000);
  assert.equal(unpaid.items[0].owed_now_minor, 300000);
  assert.equal(unpaid.items[0].balance_minor, 450000);
  const soon = await reminders("due_soon");
  assert.equal(soon.items.length, 1);
  assert.equal(soon.items[0].next_due_on, addDate(today(), 2));
  assert.equal(soon.items[0].next_due_minor, 150000);
  await collect(f, sub.id, 100000);
  assert.equal((await reminders("unpaid")).items[0].owed_now_minor, 200000);
  await collect(f, sub.id, 200000);
  assert.equal((await reminders("unpaid")).items.length, 0);
  // Paying ahead is allowed up to the whole subscription.
  await collect(f, sub.id, 150000);
  await assert.rejects(() => collect(f, sub.id, 1), /outstanding balance/);
});

test("stopping a subscription releases future sessions and drops months not started", async () => {
  const f = await fixture();
  const sub = await enroll(f, { weekdays: [6, 7] });
  await feesAround(sub.id, [-30, 0, 30]);
  const a = await service.detail(f.owner, sub.id);
  await service.cancel(f.owner, sub.id, {
    command_key: randomUUID(),
    version: a.version,
    reason: "Moving away",
  });
  const stopped = await service.detail(f.owner, sub.id);
  assert.equal(stopped.total_minor, 300000);
  assert.equal(stopped.plan_snapshot.subscription.instalments.length, 2);
  assert.equal(stopped.plan_snapshot.subscription.stopped_on, today());
  assert.equal(
    stopped.sessions.filter(
      (s: any) =>
        s.status !== "cancelled" && Date.parse(s.starts_at) > Date.now(),
    ).length,
    0,
  );
  // Started months stay owed after stopping.
  assert.equal(
    (await service.paymentReminders(f.owner, { group: "unpaid" })).items[0]
      .owed_now_minor,
    300000,
  );
});

test("rescheduling moves remaining sessions to new days and time, checked for clashes", async () => {
  const f = await fixture();
  const other = await enroll(f, {
    weekdays: [1],
    time: "19:00",
    customer: { id: null, name: "Asha", phone: "9000000002", email: null },
  });
  assert.ok(other.id);
  const sub = await enroll(f, { weekdays: [6, 7] });
  const a = await service.detail(f.owner, sub.id);
  const move = (time: string, version: number) =>
    service.reschedule(f.owner, sub.id, {
      command_key: randomUUID(),
      version,
      from_date: "2030-07-01",
      weekdays: [1],
      time,
      duration_minutes: 120,
      reason: "New timing",
    });
  await assert.rejects(() => move("18:00", a.version), /held by Asha/);
  await move("06:00", a.version);
  const moved = await service.detail(f.owner, sub.id);
  const live = moved.sessions.filter((s: any) => s.status !== "cancelled");
  // June keeps its 9 weekend sessions; July 1 to Sep 1 has 10 Mondays.
  assert.equal(live.length, 19);
  assert.equal(moved.allowance, 19);
  assert.deepEqual(moved.schedule, {
    weekdays: [1],
    time: "06:00",
    duration_minutes: 120,
  });
  assert.ok(
    live
      .filter((s: any) => s.local_start >= "2030-07-01")
      .every((s: any) => s.local_start.endsWith("T06:00")),
  );
  await assert.rejects(() => move("08:00", a.version), /changed/);
});

test("the push sender queues one fee alert per subscription month on its due day", async () => {
  const f = await fixture();
  const sub = await enroll(f, { weekdays: [6, 7] });
  await feesAround(sub.id, [-30, 0, 30]);
  const sent: unknown[] = [];
  const dispatcher = new NotificationDispatcher(db, {
    send: async (m: unknown) => {
      sent.push(m);
    },
  } as any);
  await dispatcher.dispatch();
  await dispatcher.dispatch();
  const events = (
    await db.query<any>(
      "SELECT kind,due_on::text due_on,fee_details FROM booking_notification_events WHERE admission_id=$1",
      [sub.id],
    )
  ).rows;
  assert.equal(events.length, 1);
  assert.equal(events[0].kind, "subscription_fee_due");
  assert.equal(events[0].due_on, today());
  assert.equal(events[0].fee_details.amount_minor, 150000);
  assert.equal(events[0].fee_details.customer_name, "Rahul");
  assert.equal(events[0].fee_details.currency, "INR");
});
