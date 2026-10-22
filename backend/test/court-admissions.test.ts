import "reflect-metadata";
import { before, after, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { CourtService } from "../src/court/court.service";
import { BookingService } from "../src/bookings/booking.service";
import { AdmissionService } from "../src/admissions/admission.service";
import { courtConfigurationSchema } from "../src/court/court.validation";
import { localStamp } from "../src/bookings/booking.inventory";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  workspace = new WorkspaceService(db),
  courts = new CourtService(db, workspace),
  service = new AdmissionService(db),
  bookings = new BookingService(db, workspace);
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
function plan(name: string, courtIds: string[], coachId: string | null) {
  return {
    id: randomUUID(),
    name,
    kind: "coaching",
    court_ids: courtIds,
    allowance: 2,
    expiry_mode: "after_start",
    expiry_days: 45,
    expiry_date: null,
    price_minor: 300000,
    enabled: true,
    availability: hours,
    class_duration_minutes: 60,
    class_seats: 2,
    coach_id: coachId,
    renewal: "none",
  };
}
function configuration(coachId: string | null = null) {
  const ids = [randomUUID(), randomUUID()];
  return {
    kind: "court_v1",
    schema_version: 1,
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
    plans: [
      plan("Beginner batch", ids, coachId),
      plan("Advanced batch", ids, coachId),
      {
        ...plan("Play pass", ids, null),
        kind: "play",
        class_duration_minutes: null,
        class_seats: null,
      },
    ],
  };
}
async function fixture() {
  const owner = {
    uid: randomUUID(),
    email: randomUUID() + "@example.com",
    name: "Owner",
  };
  await workspace.createOrganization(owner, {
    name: "Court academy",
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
  // The owner coaches both batches unless a test reassigns them.
  await workspace.ownerCoach(owner, { coach: true });
  const w = await workspace.workspace(owner);
  const b = await workspace.createBusiness(owner, {
    name: "Badminton academy",
    type: "badminton",
    location_id: w.locations[0].id,
  });
  const config = configuration(w.membership.id);
  await courts.configure(owner, b.id, { version: 1, configuration: config });
  await workspace.activate(owner, b.id);
  return { owner, config, businessId: b.id };
}
async function enroll(
  f: Awaited<ReturnType<typeof fixture>>,
  overrides: Record<string, unknown> = {},
  phone = "9000000001",
) {
  const input = {
    business_id: f.businessId,
    resource_id: f.config.courts[0].id,
    plan_id: f.config.plans[0].id,
    starts_on: "2030-06-04",
    mode: "fixed",
    weekdays: [2, 4],
    time: "17:00",
    duration_minutes: 60,
    customer: { id: null, name: "Student " + phone, phone, email: null },
    payments: [],
    renewed_from: null,
    ...overrides,
  };
  const q = await service.preview(f.owner, input);
  return service.create(f.owner, {
    ...input,
    preview_token: q.preview_token,
    command_key: randomUUID(),
  });
}
test("court configuration accepts optional coaching plans and validates coach coverage", () => {
  const config = configuration();
  assert.equal(
    courtConfigurationSchema.safeParse({ ...config, plans: undefined }).success,
    true,
  );
  assert.match(
    JSON.stringify(
      courtConfigurationSchema.safeParse({
        ...config,
        coaches: [{ id: randomUUID(), name: "Asha", phone: "9876500001" }],
      }).error,
    ),
    /staff coaches/,
  );
  const foreign = structuredClone(config);
  foreign.plans[0].court_ids = [randomUUID()];
  assert.equal(courtConfigurationSchema.safeParse(foreign).success, false);
  const outside = structuredClone(config);
  outside.courts[0].operating = {
    ...hours,
    all_day: false,
    opens_at: "06:00",
    closes_at: "22:00",
  };
  outside.courts[0].tariffs[0].hours = outside.courts[0].operating;
  assert.match(
    JSON.stringify(courtConfigurationSchema.safeParse(outside).error),
    /within court hours/,
  );
});
test("catalog lists court businesses with their coaching plans", async () => {
  const f = await fixture();
  const catalog = await service.catalog(f.owner);
  const b = catalog.businesses.find((b: any) => b.id === f.businessId);
  assert.equal(b.space_kind, "court");
  assert.equal(b.type, "badminton");
  assert.equal(b.pools.length, 2);
  assert.equal(b.plans.length, 3);
  assert.deepEqual(
    b.plans[0].pool_ids,
    f.config.courts.map((c: any) => c.id),
  );
  assert.equal(b.plans[0].coach_name, "Owner");
});
test("a coaching batch reserves its court once and later students join up to the seat limit", async () => {
  const f = await fixture();
  const first = await enroll(f);
  const selection = {
    business_id: f.businessId,
    resource_id: f.config.courts[0].id,
    option_id: "hourly",
    date: "2030-06-04",
    time: "17:00",
    duration_minutes: 60,
    people: 1,
  };
  await assert.rejects(
    () => bookings.quote(f.owner, { selection, exclude_booking_id: null }),
    /no longer available/,
  );
  await bookings.quote(f.owner, {
    selection: { ...selection, resource_id: f.config.courts[1].id },
    exclude_booking_id: null,
  });
  const second = await enroll(f, {}, "9000000002");
  assert.notEqual(second.id, first.id);
  await assert.rejects(() => enroll(f, {}, "9000000003"), /class is full/);
  // Another batch cannot share the reserved court, and its coach is busy.
  await assert.rejects(
    () => enroll(f, { plan_id: f.config.plans[1].id }, "9000000004"),
    /no longer available/,
  );
  await assert.rejects(
    () =>
      enroll(
        f,
        {
          plan_id: f.config.plans[1].id,
          resource_id: f.config.courts[1].id,
        },
        "9000000005",
      ),
    /coach has another overlapping class/,
  );
  // Cancelling one student keeps the court reserved for the remaining batch.
  const a = await service.detail(f.owner, first.id);
  await service.cancel(f.owner, first.id, {
    command_key: randomUUID(),
    version: a.version,
    reason: "Customer cancelled",
  });
  await assert.rejects(
    () => bookings.quote(f.owner, { selection, exclude_booking_id: null }),
    /no longer available/,
  );
  const detail = await service.detail(f.owner, second.id);
  assert.equal(detail.space_name, "Court 1");
  const catalog = await service.catalog(f.owner);
  const plans = catalog.businesses.find(
    (b: any) => b.id === f.businessId,
  ).plans;
  assert.equal(
    plans.find((p: any) => p.id === f.config.plans[0].id).active_count,
    1,
  );
  assert.equal(detail.sessions.length, 2);
});
test("flexible court coaching checks in on a free court", async () => {
  const f = await fixture();
  const today = localStamp(Date.now(), "UTC").slice(0, 10);
  const created = await enroll(f, {
    mode: "flexible",
    weekdays: [],
    starts_on: today,
  });
  const a = await service.detail(f.owner, created.id),
    now = localStamp(Date.now(), "UTC");
  await service.checkIn(f.owner, created.id, {
    command_key: randomUUID(),
    version: a.version,
    date: today,
    time: now.slice(11, 16),
    duration_minutes: 60,
  });
  const detail = await service.detail(f.owner, created.id);
  assert.equal(detail.used, 1);
  assert.equal(detail.sessions[0].admission_attendance, "present");
});
test("courts with admission history cannot be deleted", async () => {
  const f = await fixture();
  await enroll(f);
  const w = await workspace.workspace(f.owner);
  const b = w.businesses.find((b: any) => b.id === f.businessId);
  const next = structuredClone(f.config);
  next.courts = next.courts.slice(1);
  next.plans = next.plans.map((p: any) => ({
    ...p,
    court_ids: [next.courts[0].id],
  }));
  await assert.rejects(
    () =>
      courts.configure(f.owner, f.businessId, {
        version: b.version,
        configuration: next,
      }),
    /admission history|booking history/,
  );
});
test("court play plans reserve the whole court per visit and reject coaching fields", async () => {
  const bad = structuredClone(configuration());
  bad.plans[2].class_seats = 4;
  assert.match(
    JSON.stringify(courtConfigurationSchema.safeParse(bad).error),
    /only to coaching plans/,
  );
  const f = await fixture();
  const play = { plan_id: f.config.plans[2].id, time: "08:00" };
  const first = await enroll(f, play);
  const detail = await service.detail(f.owner, first.id);
  assert.equal(detail.plan_snapshot.kind, "play");
  assert.equal(detail.sessions.length, 2);
  // A second player cannot share the court; the other court is still free.
  await assert.rejects(
    () => enroll(f, play, "9000000002"),
    /no longer available/,
  );
  await enroll(
    f,
    { ...play, resource_id: f.config.courts[1].id },
    "9000000003",
  );
  // Play visits accept longer durations in 30-minute steps from the minimum.
  await enroll(
    f,
    { ...play, time: "10:00", duration_minutes: 90 },
    "9000000004",
  );
  await assert.rejects(
    () =>
      enroll(f, { ...play, time: "12:00", duration_minutes: 45 }, "9000000005"),
    /visit duration|minimum visit duration/,
  );
  const list = await service.list(f.owner, { kind: "play" });
  assert.equal(list.items.length, 3);
});
async function coach(
  f: Awaited<ReturnType<typeof fixture>>,
  permissions: string[] = ["coach"],
) {
  const staff = {
    uid: randomUUID(),
    email: randomUUID() + "@example.com",
    name: "Ravi",
  };
  const invite = await workspace.invite(f.owner, {
    email: staff.email,
    display_name: "Coach Ravi",
    role: "staff",
    permissions,
    assignments: [{ business_id: f.businessId, resource_ids: [] }],
  });
  await workspace.accept(
    staff,
    new URL(invite.invitation_url).searchParams.get("token")!,
  );
  const member = (await workspace.team(f.owner)).members.find(
    (m: any) => m.user_id === staff.uid,
  );
  return { staff, id: member.id as string };
}
async function assign(
  f: Awaited<ReturnType<typeof fixture>>,
  coaches: Record<string, string | null>,
) {
  const b = (await workspace.workspace(f.owner)).businesses.find(
    (b: any) => b.id === f.businessId,
  );
  await workspace.planCoaches(f.owner, f.businessId, {
    version: b.version,
    coaches,
  });
}
test("reassigned coaches are checked against the classes they now teach", async () => {
  const f = await fixture();
  const ravi = await coach(f);
  await assign(f, { [f.config.plans[1].id]: ravi.id });
  // Different coaches may teach at the same time on different courts.
  const beginner = await enroll(f);
  await enroll(
    f,
    { plan_id: f.config.plans[1].id, resource_id: f.config.courts[1].id },
    "9000000002",
  );
  const conflicts = await service.coachConflicts(f.owner, {
    business_id: f.businessId,
    coach_id: ravi.id,
    plan_ids: [f.config.plans[0].id, f.config.plans[1].id],
  });
  assert.ok(conflicts.items.length > 0);
  assert.deepEqual(
    new Set(
      conflicts.items.flatMap((c: any) => [c.plan_name, c.other_plan_name]),
    ),
    new Set(["Beginner batch", "Advanced batch"]),
  );
  // Keeping the current plans reports nothing new.
  assert.equal(
    (
      await service.coachConflicts(f.owner, {
        business_id: f.businessId,
        coach_id: ravi.id,
        plan_ids: [f.config.plans[1].id],
      })
    ).items.length,
    0,
  );
  await assign(f, { [f.config.plans[0].id]: ravi.id });
  // The beginner classes now belong to Ravi, not to the coach in the snapshot.
  assert.equal(
    (await service.detail(f.owner, beginner.id)).plan_snapshot.coach_name,
    "Coach Ravi",
  );
  await assert.rejects(
    () =>
      enroll(
        f,
        { plan_id: f.config.plans[1].id, resource_id: f.config.courts[1].id },
        "9000000003",
      ),
    /coach has another overlapping class/,
  );
});
test("coaches see their own classes and may mark attendance only for them", async () => {
  const f = await fixture();
  const ravi = await coach(f);
  const helper = await coach(f, ["view_bookings"]);
  await assign(f, { [f.config.plans[1].id]: ravi.id });
  const mine = await enroll(f, {
    plan_id: f.config.plans[1].id,
    resource_id: f.config.courts[1].id,
  });
  await enroll(
    f,
    { plan_id: f.config.plans[1].id, resource_id: f.config.courts[1].id },
    "9000000002",
  );
  const other = await enroll(f, {}, "9000000003");
  const day = await service.classes(ravi.staff, { date: "2030-06-04" });
  assert.equal(day.classes.length, 1);
  assert.equal(day.classes[0].plan_name, "Advanced batch");
  assert.equal(day.classes[0].space_name, "Court 2");
  assert.equal(day.classes[0].local_start, "2030-06-04T17:00");
  assert.equal(day.classes[0].students.length, 2);
  assert.equal(day.classes[0].students[0].markable, false);
  assert.equal(
    (await service.classes(f.owner, { date: "2030-06-04" })).classes[0]
      .plan_name,
    "Beginner batch",
  );
  await assert.rejects(
    () => service.classes(helper.staff, { date: "2030-06-04" }),
    /Only coaches/,
  );
  const mark = async (actor: any, admission: string) => {
    const a = await service.detail(f.owner, admission);
    return service.attendance(actor, admission, a.sessions[0].id, {
      command_key: randomUUID(),
      version: a.sessions[0].version,
      attendance: "present",
      reason: "",
    });
  };
  // Coach status by itself cannot mark attendance.
  await assert.rejects(() => mark(ravi.staff, mine.id), /permission|access/);
  await assert.rejects(() => service.detail(ravi.staff, mine.id), /access/);
  await assert.rejects(() => service.list(ravi.staff, {}), /access/);
  await db.query("UPDATE memberships SET permissions=$1 WHERE id=$2", [
    JSON.stringify(["coach", "mark_attendance"]),
    ravi.id,
  ]);
  assert.equal((await service.detail(ravi.staff, mine.id)).can_attend, true);
  assert.equal((await service.detail(ravi.staff, other.id)).can_attend, false);
  // An explicit attendance grant permits his class, but never another coach's.
  await assert.rejects(() => mark(ravi.staff, mine.id), /before the session/);
  await assert.rejects(
    () => mark(ravi.staff, other.id),
    /assigned coaching plans/,
  );
  await assert.rejects(() => mark(helper.staff, mine.id), /permission/);
  const detail = await service.detail(f.owner, mine.id);
  await db.query(
    "UPDATE bookings SET starts_at=now()-interval '10 minutes', ends_at=now()+interval '50 minutes' WHERE id=$1",
    [detail.sessions[0].id],
  );
  const today = localStamp(Date.now(), "UTC").slice(0, 10);
  assert.equal(
    (await service.classes(ravi.staff, { date: today })).classes[0].students[0]
      .markable,
    true,
  );
  await db.query("UPDATE memberships SET permissions=$1 WHERE id=$2", [
    JSON.stringify(["coach"]),
    ravi.id,
  ]);
  assert.equal(
    (await service.classes(ravi.staff, { date: today })).classes[0].students[0]
      .markable,
    false,
  );
  await assert.rejects(() => mark(ravi.staff, mine.id), /permission|access/);
  await db.query("UPDATE memberships SET permissions=$1 WHERE id=$2", [
    JSON.stringify(["coach", "mark_attendance"]),
    ravi.id,
  ]);
  await mark(ravi.staff, mine.id);
  assert.equal(
    (await service.detail(f.owner, mine.id)).sessions[0].admission_attendance,
    "present",
  );
  await db.query(
    "UPDATE staff_assignments SET resource_ids=$1 WHERE membership_id=$2",
    [JSON.stringify([f.config.courts[0].id]), ravi.id],
  );
  assert.equal(
    (await service.classes(ravi.staff, { date: today })).classes.length,
    0,
  );
  await assert.rejects(
    () => service.detail(ravi.staff, mine.id),
    /not assigned/,
  );
});

test("subscription management, booking creation and attendance are independent staff grants", async () => {
  const f = await fixture();
  const bookingStaff = await coach(f, ["view_bookings", "manage_bookings"]);
  const subscriptionStaff = await coach(f, ["manage_subscriptions"]);
  const attendanceStaff = await coach(f, ["mark_attendance"]);
  assert.equal((await service.catalog(bookingStaff.staff)).can_manage, false);
  assert.equal(
    (await service.catalog(subscriptionStaff.staff)).can_manage,
    true,
  );
  assert.equal(
    (await service.catalog(subscriptionStaff.staff)).can_attend,
    false,
  );
  assert.equal((await service.catalog(attendanceStaff.staff)).can_attend, true);
  assert.equal(
    (await service.catalog(attendanceStaff.staff)).can_manage,
    false,
  );
  const admission = await enroll(f);
  assert.equal(
    (await service.detail(attendanceStaff.staff, admission.id)).can_attend,
    true,
  );
  const command = {
    business_id: f.businessId,
    resource_id: f.config.courts[0].id,
    plan_id: f.config.plans[0].id,
    starts_on: "2030-06-06",
    mode: "fixed",
    weekdays: [1, 2, 3, 4, 5, 6, 7],
    time: "17:00",
    duration_minutes: 60,
    customer: {
      id: null,
      name: "New student",
      phone: "9000000008",
      email: null,
    },
    payments: [],
    renewed_from: null,
  };
  await assert.rejects(
    () => service.preview(bookingStaff.staff, command),
    /Subscription management permission/,
  );
  await assert.rejects(
    () => service.preview(attendanceStaff.staff, command),
    /Subscription management permission/,
  );
  const quote = await service.preview(subscriptionStaff.staff, command);
  const created = await service.create(subscriptionStaff.staff, {
    ...command,
    preview_token: quote.preview_token,
    command_key: randomUUID(),
  });
  assert.ok(created.id);
  await assert.rejects(
    () => bookings.catalog(subscriptionStaff.staff),
    /access|permission/i,
  );
});
