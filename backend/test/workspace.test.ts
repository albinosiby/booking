import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { locationSchema } from "../src/workspace/validation";
import { Actor } from "../src/common/auth.guard";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  service = new WorkspaceService(db);
const actor = (): Actor => {
  const id = randomUUID();
  return { uid: id, email: `${id}@example.com`, name: "Test owner" };
};
const org = {
  name: "Eden Test",
  contact_phone: "9876543210",
  currency: "INR",
  location: {
    name: "Main property",
    address_line_1: "Road 1",
    address_line_2: null,
    city: "Kochi",
    state_code: "KL",
    country_code: "IN",
    postal_code: "682001",
    timezone: "Asia/Kolkata",
  },
};
const rules = {
  version: 1,
  opens_at: "06:00",
  closes_at: "23:00",
  days: [1, 2, 3, 4, 5, 6, 7],
  duration_minutes: 60,
  price_minor: 150000,
  buffer_minutes: 0,
  plan_name: null,
  validity_days: null,
  entitlement: null,
  visit_limit: null,
};
async function fixture(type = "turf") {
  const owner = actor();
  await service.createOrganization(owner, org);
  const w = await service.workspace(owner);
  const b = await service.createBusiness(owner, {
    name: "Eden facility",
    type,
    location_id: w.locations[0].id,
  });
  return { owner, id: b.id };
}
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());
test("structured addresses reject wrong state and invalid pincode", () => {
  assert.throws(() =>
    locationSchema.parse({ ...org.location, state_code: "CA" }),
  );
  assert.throws(() =>
    locationSchema.parse({ ...org.location, postal_code: "00123" }),
  );
  assert.throws(() =>
    locationSchema.parse({ ...org.location, timezone: "not-a-zone" }),
  );
});
test("organization creation is atomic and cannot run twice for an account", async () => {
  const a = actor();
  await service.createOrganization(a, org);
  await assert.rejects(() => service.createOrganization(a, org));
  const w = await service.workspace(a);
  assert.equal(w.locations[0].address_line_1, "Road 1");
  assert.equal(w.locations[0].postal_code, "682001");
  assert.equal(w.organization.logo_storage_key, null);
  assert.equal(w.membership.role, "owner");
});
test("activation requires both resource and configuration", async () => {
  const { owner, id } = await fixture();
  await assert.rejects(() => service.activate(owner, id));
  await service.addResource(owner, id, { name: "Turf 1", capacity: 1 });
  await assert.rejects(() => service.activate(owner, id));
  const version = (await service.workspace(owner)).businesses[0].version;
  await service.configure(owner, id, { ...rules, version });
  await service.activate(owner, id);
  assert.equal((await service.workspace(owner)).businesses[0].status, "ready");
});
test("a stale configuration cannot overwrite another device", async () => {
  const { owner, id } = await fixture();
  await service.configure(owner, id, rules);
  await assert.rejects(() => service.configure(owner, id, rules));
  assert.equal((await service.workspace(owner)).businesses[0].version, 2);
});
test("pool plans require explicit entitlement and visit limits", async () => {
  const { owner, id } = await fixture("pool");
  await assert.rejects(() => service.configure(owner, id, rules));
  const pool = {
    ...rules,
    plan_name: "Monthly plan",
    validity_days: 30,
    entitlement: "visits",
    visit_limit: null,
  };
  await assert.rejects(() => service.configure(owner, id, pool));
  await service.configure(owner, id, { ...pool, visit_limit: 25 });
  const w = await service.workspace(owner);
  assert.equal(w.businesses[0].configuration.visit_limit, 25);
});
test("cross-organization resources and locations are rejected", async () => {
  const a = await fixture(),
    b = await fixture();
  await assert.rejects(() =>
    service.addResource(b.owner, a.id, { name: "Not allowed" }),
  );
  const location = (await service.workspace(a.owner)).locations[0].id;
  await assert.rejects(() =>
    service.createBusiness(b.owner, {
      name: "Wrong location",
      type: "turf",
      location_id: location,
    }),
  );
});
test("invitation email, business and resource boundaries are enforced", async () => {
  const a = await fixture(),
    other = await fixture();
  const one = await service.addResource(a.owner, a.id, { name: "Court A" }),
    two = await service.addResource(a.owner, a.id, { name: "Court B" });
  const staff = actor();
  const body = {
    email: staff.email,
    display_name: "Pool staff",
    role: "staff",
    permissions: ["view_bookings"],
    assignments: [{ business_id: a.id, resource_ids: [one.id] }],
  };
  await assert.rejects(() =>
    service.invite(a.owner, {
      ...body,
      assignments: [{ business_id: other.id, resource_ids: [] }],
    }),
  );
  const invite = await service.invite(a.owner, body);
  const token = new URL(invite.invitation_url).searchParams.get("token")!;
  await assert.rejects(() => service.accept(actor(), token));
  await service.accept(staff, token);
  await assert.rejects(() => service.accept(staff, token));
  const w = await service.workspace(staff);
  assert.equal(w.businesses.length, 1);
  assert.equal(w.businesses[0].resources.length, 1);
  assert.equal(w.businesses[0].resources[0].id, one.id);
  assert.notEqual(w.businesses[0].resources[0].id, two.id);
  await assert.rejects(() => service.configure(staff, a.id, rules));
  await assert.rejects(() => service.team(staff));
  await assert.rejects(() => service.deleteResource(a.owner, a.id, one.id));
  const membership = w.membership;
  await service.revoke(a.owner, membership.id, false);
  await assert.rejects(() => service.member(staff));
  await assert.rejects(() => service.workspace(staff));
});
test("cancelled invitation cannot grant access", async () => {
  const { owner, id } = await fixture();
  const staff = actor();
  const i = await service.invite(owner, {
    email: staff.email,
    display_name: "Test staff",
    role: "staff",
    permissions: [],
    assignments: [{ business_id: id, resource_ids: [] }],
  });
  await service.revoke(owner, i.id, true);
  await assert.rejects(() =>
    service.accept(staff, new URL(i.invitation_url).searchParams.get("token")!),
  );
});
test("logo rejects non-string payloads and content disguised as an image", async () => {
  const { owner } = await fixture();
  await assert.rejects(() =>
    service.uploadLogo(owner, {
      content_type: "image/png",
      base64: { length: 999999999 },
    }),
  );
  await assert.rejects(() =>
    service.uploadLogo(owner, {
      content_type: "image/png",
      base64: Buffer.from("not an image").toString("base64"),
    }),
  );
});

test("expired invitation cannot be accepted", async () => {
  const { owner, id } = await fixture();
  const staff = actor();
  const invite = await service.invite(owner, {
    email: staff.email,
    display_name: "Expired staff",
    role: "staff",
    permissions: [],
    assignments: [{ business_id: id, resource_ids: [] }],
  });
  await db.query(
    "UPDATE invitations SET expires_at=now()-interval '1 day' WHERE id=$1",
    [invite.id],
  );
  await assert.rejects(() =>
    service.accept(
      staff,
      new URL(invite.invitation_url).searchParams.get("token")!,
    ),
  );
});

test("business order persists across catalogs, rejects stale/invalid lists and appends new businesses", async () => {
  const { owner, id } = await fixture("pool");
  const workspace = await service.workspace(owner);
  const turf = await service.createBusiness(owner, {
    name: "ZZ Turf",
    type: "turf",
    location_id: workspace.locations[0].id,
  });
  const other = await fixture();
  const revision = (await service.workspace(owner)).organization!
    .business_order_revision;
  const ids = [turf.id, id];
  for (const invalid of [[id], [id, id], [id, other.id]]) {
    await assert.rejects(() =>
      service.reorderBusinesses(owner, { business_ids: invalid, revision }),
    );
  }
  const result = await service.reorderBusinesses(owner, {
    business_ids: ids,
    revision,
  });
  assert.equal(result.revision, revision + 1);
  assert.deepEqual(
    (await service.workspace(owner)).businesses.map((b) => b.id),
    ids,
  );
  await assert.rejects(() =>
    service.reorderBusinesses(owner, { business_ids: [id, turf.id], revision }),
  );
  const { BookingService } = await import("../src/bookings/booking.service");
  const { AccountsService } = await import("../src/accounts/accounts.service");
  assert.deepEqual(
    (
      await new BookingService(db, service).catalog(owner)
    ).filter_businesses.map((b: any) => b.id),
    ids,
  );
  assert.deepEqual(
    (await new AccountsService(db, service).catalog(owner)).businesses.map(
      (b: any) => b.id,
    ),
    ids,
  );
  const added = await service.createBusiness(owner, {
    name: "AA Court",
    type: "badminton",
    location_id: workspace.locations[0].id,
  });
  assert.deepEqual(
    (await service.workspace(owner)).businesses.map((b) => b.id),
    [...ids, added.id],
  );
  await assert.rejects(() =>
    service.reorderBusinesses(owner, {
      business_ids: ids,
      revision: result.revision,
    }),
  );
});

test("staff inherit the owner's order for their subset and cannot reorder", async () => {
  const { owner, id } = await fixture();
  const workspace = await service.workspace(owner);
  const pool = await service.createBusiness(owner, {
    name: "Swimming",
    type: "pool",
    location_id: workspace.locations[0].id,
  });
  const revision = (await service.workspace(owner)).organization!
    .business_order_revision;
  await service.reorderBusinesses(owner, {
    business_ids: [pool.id, id],
    revision,
  });
  const staff = actor();
  const invite = await service.invite(owner, {
    email: staff.email,
    display_name: "Staff",
    role: "staff",
    permissions: ["view_bookings"],
    assignments: [
      { business_id: id, resource_ids: [] },
      { business_id: pool.id, resource_ids: [] },
    ],
  });
  await service.accept(
    staff,
    new URL(invite.invitation_url).searchParams.get("token")!,
  );
  assert.deepEqual(
    (await service.workspace(staff)).businesses.map((b) => b.id),
    [pool.id, id],
  );
  await assert.rejects(() =>
    service.reorderBusinesses(staff, {
      business_ids: [id, pool.id],
      revision: revision + 1,
    }),
  );
  const other = await fixture();
  await assert.rejects(() =>
    service.reorderBusinesses(other.owner, {
      business_ids: [pool.id, id],
      revision: 1,
    }),
  );
});

test("concurrent business order saves commit one complete order across fresh service catalogs", async () => {
  const { owner, id } = await fixture("pool");
  const initial = await service.workspace(owner);
  const turf = await service.createBusiness(owner, {
    name: "Turf",
    type: "turf",
    location_id: initial.locations[0].id,
  });
  const hall = await service.createBusiness(owner, {
    name: "Hall",
    type: "hall",
    location_id: initial.locations[0].id,
  });
  const revision = (await service.workspace(owner)).organization!
    .business_order_revision;
  const orders = [
    [turf.id, id, hall.id],
    [hall.id, turf.id, id],
  ];
  const results = await Promise.allSettled(
    orders.map((business_ids) =>
      service.reorderBusinesses(owner, { business_ids, revision }),
    ),
  );
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
  assert.equal(results.filter((r) => r.status === "rejected").length, 1);
  const winner = orders[results.findIndex((r) => r.status === "fulfilled")];
  const fresh = new WorkspaceService(db);
  assert.deepEqual(
    (await fresh.workspace(owner)).businesses.map((b) => b.id),
    winner,
  );
  assert.equal(
    (await fresh.workspace(owner)).organization!.business_order_revision,
    revision + 1,
  );
  const { BookingService } = await import("../src/bookings/booking.service");
  const { AccountsService } = await import("../src/accounts/accounts.service");
  const staff = actor();
  const invite = await service.invite(owner, {
    email: staff.email,
    display_name: "Scoped staff",
    role: "staff",
    permissions: ["view_bookings", "view_finance"],
    assignments: [
      { business_id: id, resource_ids: [] },
      { business_id: hall.id, resource_ids: [] },
    ],
  });
  await service.accept(
    staff,
    new URL(invite.invitation_url).searchParams.get("token")!,
  );
  for (const viewer of [owner, staff]) {
    const expected =
      viewer === owner ? winner : winner.filter((b) => b !== turf.id);
    assert.deepEqual(
      (await fresh.workspace(viewer)).businesses.map((b) => b.id),
      expected,
    );
    assert.deepEqual(
      (
        await new BookingService(db, fresh).catalog(viewer)
      ).filter_businesses.map((b: any) => b.id),
      expected,
    );
    assert.deepEqual(
      (await new AccountsService(db, fresh).catalog(viewer)).businesses.map(
        (b: any) => b.id,
      ),
      expected,
    );
  }
});

test("workspace batches resource reads across businesses while preserving the public resource shape", async () => {
  const f = await fixture();
  const workspace = await service.workspace(f.owner);
  await db.query(
    "INSERT INTO resources(id,organization_id,business_id,name,capacity) VALUES($1,$2,$3,$4,$5)",
    [randomUUID(), workspace.organization.id, f.id, "Main turf", 1],
  );
  for (let n = 0; n < 5; n++)
    await service.createBusiness(f.owner, {
      name: `Court ${n}`,
      type: "badminton",
      location_id: workspace.locations[0].id,
    });
  const statements: string[] = [];
  const measured = {
    query: async <T = Record<string, unknown>>(
      sql: string,
      values?: unknown[],
    ) => {
      statements.push(sql);
      return db.query<T>(sql, values);
    },
  };
  const reader = new WorkspaceService(measured as Database);
  const result = await reader.workspace(f.owner);
  assert.equal(result.businesses.length, 6);
  assert.equal(
    result.businesses.flatMap((business) => business.resources).length,
    1,
  );
  assert.equal(
    statements.filter((sql) => sql.includes("FROM resources")).length,
    1,
  );
  assert.equal(statements.length, 2);
  for (const business of result.businesses)
    for (const resource of business.resources)
      assert.deepEqual(Object.keys(resource).sort(), [
        "capacity",
        "id",
        "name",
      ]);
});

test("removing a manager clears grants and coaching while preserving their history", async () => {
  const { owner, id } = await fixture("pool");
  const resource = await service.addResource(owner, id, {
    name: "Pool A",
    capacity: 20,
  });
  const manager = actor();
  const invitation = await service.invite(owner, {
    email: manager.email,
    display_name: "Coach manager",
    role: "manager",
    permissions: ["coach", "mark_attendance", "view_bookings"],
    assignments: [{ business_id: id, resource_ids: [resource.id] }],
  });
  await service.accept(
    manager,
    new URL(invitation.invitation_url).searchParams.get("token")!,
  );
  const snapshot = await service.workspace(manager);
  const memberId = snapshot.membership.id,
    orgId = snapshot.organization.id;
  await db.query("UPDATE businesses SET configuration=$1 WHERE id=$2", [
    JSON.stringify({
      kind: "pool_v1",
      plans: [
        {
          id: randomUUID(),
          name: "Coaching",
          kind: "coaching",
          coach_id: memberId,
          pool_ids: [resource.id],
        },
      ],
    }),
    id,
  ]);
  const pendingId = randomUUID();
  await db.query(
    "INSERT INTO invitations(id,organization_id,email,display_name,role,permissions,assignments,token_hash,expires_at) VALUES($1,$2,$3,'Coach manager','manager','[]','[]',$4,now()+interval '7 days')",
    [pendingId, orgId, manager.email, randomUUID()],
  );
  const customerId = randomUUID(),
    bookingId = randomUUID(),
    paymentId = randomUUID(),
    historyId = randomUUID();
  await db.query(
    "INSERT INTO customers(id,organization_id,name,phone) VALUES($1,$2,'Student','9876543210')",
    [customerId, orgId],
  );
  await db.query(
    "INSERT INTO bookings(id,organization_id,business_id,resource_id,customer_id,reference,starts_at,ends_at,total_minor,selection,price_snapshot,customer_snapshot,people,created_by) VALUES($1,$2,$3,$4,$5,$6,'2030-06-04T06:00Z','2030-06-04T07:00Z',50000,'{}','{}','{}',1,$7)",
    [bookingId, orgId, id, resource.id, customerId, randomUUID(), manager.uid],
  );
  await db.query(
    "INSERT INTO booking_payments(id,organization_id,booking_id,kind,method,amount_minor,received_at,recorded_by) VALUES($1,$2,$3,'collection','cash',10000,now(),$4)",
    [paymentId, orgId, bookingId, manager.uid],
  );
  await db.query(
    "INSERT INTO booking_history(id,booking_id,actor_id,action,details) VALUES($1,$2,$3,'attendance','{\"attendance\":\"present\"}')",
    [historyId, bookingId, manager.uid],
  );
  await assert.rejects(() => service.revoke(manager, memberId, false));
  const other = await fixture();
  await assert.rejects(() => service.revoke(other.owner, memberId, false));
  const ownerMembership = (await service.workspace(owner)).membership.id;
  await assert.rejects(() => service.revoke(owner, ownerMembership, false));
  const result = await service.revoke(owner, memberId, false);
  assert.equal(result.released, 1);
  // A stale edit form must not recreate assignments after removal.
  await assert.rejects(() =>
    service.updateMember(owner, memberId, {
      display_name: "Coach manager",
      email: manager.email,
      role: "manager",
      permissions: ["coach", "mark_attendance"],
      assignments: [{ business_id: id, resource_ids: [resource.id] }],
    }),
  );
  await assert.rejects(() => service.workspace(manager));
  assert.equal(
    (
      await db.query("SELECT * FROM staff_assignments WHERE membership_id=$1", [
        memberId,
      ])
    ).rows.length,
    0,
  );
  assert.equal(
    (
      await db.query<any>("SELECT active FROM memberships WHERE id=$1", [
        memberId,
      ])
    ).rows[0].active,
    false,
  );
  assert.ok(
    (
      await db.query<any>("SELECT revoked_at FROM invitations WHERE id=$1", [
        pendingId,
      ])
    ).rows[0].revoked_at,
  );
  assert.equal(
    (
      await db.query<any>("SELECT configuration FROM businesses WHERE id=$1", [
        id,
      ])
    ).rows[0].configuration.plans[0].coach_id,
    null,
  );
  assert.equal(
    (
      await db.query<any>("SELECT created_by FROM bookings WHERE id=$1", [
        bookingId,
      ])
    ).rows[0].created_by,
    manager.uid,
  );
  assert.equal(
    (
      await db.query<any>(
        "SELECT recorded_by,amount_minor FROM booking_payments WHERE id=$1",
        [paymentId],
      )
    ).rows[0].amount_minor,
    10000,
  );
  assert.equal(
    (
      await db.query<any>(
        "SELECT actor_id,details FROM booking_history WHERE id=$1",
        [historyId],
      )
    ).rows[0].details.attendance,
    "present",
  );
  assert.equal(
    (
      await db.query(
        "SELECT id FROM audit_events WHERE action='staff.revoked' AND entity_id=$1",
        [memberId],
      )
    ).rows.length,
    1,
  );
  // Keep real admission attendance and support history through permanent deletion.
  const admissionId = randomUUID(),
    ticketId = randomUUID();
  await db.query(
    "INSERT INTO admissions(id,organization_id,business_id,resource_id,customer_id,reference,plan_id,plan_snapshot,customer_snapshot,timezone,mode,starts_on,expires_on,allowance,total_minor,schedule,created_by) VALUES($1,$2,$3,$4,$5,$6,$7,'{}','{}','UTC','fixed','2030-06-04','2030-07-04',25,50000,'{}',$8)",
    [
      admissionId,
      orgId,
      id,
      resource.id,
      customerId,
      randomUUID(),
      randomUUID(),
      manager.uid,
    ],
  );
  await db.query(
    "UPDATE bookings SET admission_id=$1,admission_attendance='present' WHERE id=$2",
    [admissionId, bookingId],
  );
  await db.query(
    "INSERT INTO support_tickets(id,organization_id,membership_id,subject) VALUES($1,$2,$3,'Attendance question')",
    [ticketId, orgId, memberId],
  );
  await db.query(
    "INSERT INTO support_messages(id,ticket_id,author,author_name,body) VALUES($1,$2,'user','Coach manager','Please check my class.')",
    [randomUUID(), ticketId],
  );
  // A later explicit grant must be cancelled before the old identity is purged.
  await db.query("UPDATE invitations SET revoked_at=NULL WHERE id=$1", [
    pendingId,
  ]);
  await assert.rejects(() => service.deleteTeamRecord(owner, memberId, false));
  await db.query("UPDATE invitations SET revoked_at=now() WHERE id=$1", [
    pendingId,
  ]);
  await assert.rejects(() =>
    service.deleteTeamRecord(manager, memberId, false),
  );
  await assert.rejects(() =>
    service.deleteTeamRecord(other.owner, memberId, false),
  );
  await assert.rejects(() =>
    service.deleteTeamRecord(owner, ownerMembership, false),
  );
  const acceptedId = (
    await db.query<any>(
      "SELECT id FROM invitations WHERE organization_id=$1 AND email=$2 AND accepted_at IS NOT NULL",
      [orgId, manager.email],
    )
  ).rows[0].id;
  await assert.rejects(() => service.deleteTeamRecord(owner, acceptedId, true));
  await service.deleteTeamRecord(owner, memberId, false);
  assert.equal(
    (await db.query("SELECT id FROM memberships WHERE id=$1", [memberId])).rows
      .length,
    0,
  );
  assert.equal(
    (
      await db.query(
        "SELECT id FROM invitations WHERE organization_id=$1 AND email=$2",
        [orgId, manager.email],
      )
    ).rows.length,
    0,
  );
  assert.equal(
    (
      await db.query<any>(
        "SELECT created_by,admission_attendance FROM bookings WHERE id=$1",
        [bookingId],
      )
    ).rows[0].admission_attendance,
    "present",
  );
  assert.equal(
    (
      await db.query<any>("SELECT created_by FROM admissions WHERE id=$1", [
        admissionId,
      ])
    ).rows[0].created_by,
    manager.uid,
  );
  assert.equal(
    (
      await db.query<any>(
        "SELECT recorded_by FROM booking_payments WHERE id=$1",
        [paymentId],
      )
    ).rows[0].recorded_by,
    manager.uid,
  );
  assert.equal(
    (
      await db.query<any>("SELECT actor_id FROM booking_history WHERE id=$1", [
        historyId,
      ])
    ).rows[0].actor_id,
    manager.uid,
  );
  const ticket = (
    await db.query<any>(
      "SELECT organization_id,membership_id FROM support_tickets WHERE id=$1",
      [ticketId],
    )
  ).rows[0];
  assert.equal(ticket.organization_id, orgId);
  assert.equal(ticket.membership_id, null);
  assert.equal(
    (
      await db.query("SELECT id FROM support_messages WHERE ticket_id=$1", [
        ticketId,
      ])
    ).rows.length,
    1,
  );
  assert.equal((await service.workspace(manager)).membership, null);
});

test("only cancelled invitations can be permanently deleted by their organization owner", async () => {
  const f = await fixture(),
    other = await fixture(),
    person = actor();
  const invitation = await service.invite(f.owner, {
    email: person.email,
    display_name: "Pending person",
    role: "staff",
    permissions: [],
    assignments: [{ business_id: f.id, resource_ids: [] }],
  });
  await assert.rejects(() =>
    service.deleteTeamRecord(f.owner, invitation.id, true),
  );
  await service.revoke(f.owner, invitation.id, true);
  await assert.rejects(() =>
    service.deleteTeamRecord(other.owner, invitation.id, true),
  );
  await service.deleteTeamRecord(f.owner, invitation.id, true);
  assert.equal(
    (await db.query("SELECT id FROM invitations WHERE id=$1", [invitation.id]))
      .rows.length,
    0,
  );
  const active = (await service.workspace(f.owner)).membership;
  await assert.rejects(() =>
    service.deleteTeamRecord(f.owner, active.id, false),
  );
});

test("permanent deletion rolls back all cleanup when another protected record references the member", async () => {
  const f = await fixture(),
    staff = actor();
  const grant = await service.invite(f.owner, {
    email: staff.email,
    display_name: "Former staff",
    role: "staff",
    permissions: [],
    assignments: [{ business_id: f.id, resource_ids: [] }],
  });
  await service.accept(
    staff,
    new URL(grant.invitation_url).searchParams.get("token")!,
  );
  const snapshot = await service.workspace(staff),
    memberId = snapshot.membership.id;
  await service.revoke(f.owner, memberId, false);
  // Unrelated service records are never cascaded away by team deletion.
  await db.query(
    "INSERT INTO agent_call_requests(id,organization_id,membership_id) VALUES($1,$2,$3)",
    [randomUUID(), snapshot.organization.id, memberId],
  );
  await assert.rejects(
    () => service.deleteTeamRecord(f.owner, memberId, false),
    /Other protected records/,
  );
  assert.equal(
    (await db.query("SELECT id FROM memberships WHERE id=$1", [memberId])).rows
      .length,
    1,
  );
  assert.equal(
    (await db.query("SELECT id FROM invitations WHERE id=$1", [grant.id])).rows
      .length,
    1,
  );
  assert.equal(
    (
      await db.query(
        "SELECT id FROM audit_events WHERE entity_id=$1 AND action='staff.permanently_deleted'",
        [memberId],
      )
    ).rows.length,
    0,
  );
  await assert.rejects(() =>
    service.deleteTeamRecord(f.owner, "not-a-uuid", false),
  );
});
