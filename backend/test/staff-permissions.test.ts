import "reflect-metadata";
import { before, after, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";

delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  workspace = new WorkspaceService(db);
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());
const migration = readFileSync(
  "migrations/20261022051321_unified_staff_permissions.sql",
  "utf8",
);
async function fixture() {
  const owner = {
    uid: randomUUID(),
    email: randomUUID() + "@example.com",
    name: "Owner",
  };
  await workspace.createOrganization(owner, {
    name: "Staff permissions",
    contact_phone: "9876543210",
    currency: "INR",
    location: {
      name: "Main",
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
  const business = await workspace.createBusiness(owner, {
    name: "Pool",
    type: "pool",
    location_id: w.locations[0].id,
  });
  return { owner, businessId: business.id, organizationId: w.organization.id };
}
async function invite(
  f: Awaited<ReturnType<typeof fixture>>,
  permissions: string[],
) {
  const actor = {
    uid: randomUUID(),
    email: randomUUID() + "@example.com",
    name: "Staff",
  };
  const invitation = await workspace.invite(f.owner, {
    email: actor.email,
    display_name: actor.name,
    role: "staff",
    permissions,
    assignments: [{ business_id: f.businessId, resource_ids: [] }],
  });
  return {
    actor,
    invitation,
    token: new URL(invitation.invitation_url).searchParams.get("token")!,
  };
}

test("new coach invitations never gain attendance or booking access implicitly", async () => {
  const f = await fixture();
  const staff = await invite(f, ["coach"]);
  await workspace.accept(staff.actor, staff.token);
  assert.deepEqual(
    (await workspace.workspace(staff.actor)).membership.permissions,
    ["coach"],
  );
  const attendant = await invite(f, [
    "mark_attendance",
    "manage_subscriptions",
  ]);
  await workspace.accept(attendant.actor, attendant.token);
  assert.deepEqual(
    (await workspace.workspace(attendant.actor)).membership.permissions,
    ["mark_attendance", "manage_subscriptions"],
  );
});

test("permission migration preserves legacy abilities and pending invitations without duplicate grants", async () => {
  const f = await fixture();
  const staff = await invite(f, ["coach", "manage_bookings"]);
  await workspace.accept(staff.actor, staff.token);
  const pending = await invite(f, ["coach", "manage_attendance"]);
  const cancelled = await invite(f, ["coach"]);
  await workspace.revoke(f.owner, cancelled.invitation.id, true);
  const explicit = await invite(f, ["view_bookings"]);
  await db.transaction(async (tx) => {
    for (const statement of migration.split(";").filter((s) => s.trim())) {
      await tx.query(statement);
    }
  });
  await db.transaction(async (tx) => {
    for (const statement of migration.split(";").filter((s) => s.trim())) {
      await tx.query(statement);
    }
  });
  const permissions = (await workspace.workspace(staff.actor)).membership
    .permissions;
  assert.deepEqual(
    new Set(permissions),
    new Set([
      "coach",
      "manage_bookings",
      "mark_attendance",
      "manage_subscriptions",
    ]),
  );
  assert.equal(permissions.length, 4);
  const rows = (
    await db.query<any>(
      "SELECT id,permissions FROM invitations WHERE id=ANY($1::uuid[])",
      [
        [
          pending.invitation.id,
          cancelled.invitation.id,
          explicit.invitation.id,
        ],
      ],
    )
  ).rows;
  assert.deepEqual(
    rows.find((r) => r.id === pending.invitation.id).permissions,
    ["coach", "manage_attendance", "mark_attendance"],
  );
  assert.deepEqual(
    rows.find((r) => r.id === cancelled.invitation.id).permissions,
    ["coach"],
  );
  assert.deepEqual(
    rows.find((r) => r.id === explicit.invitation.id).permissions,
    ["view_bookings"],
  );
  await workspace.accept(pending.actor, pending.token);
  assert.ok(
    (await workspace.workspace(pending.actor)).membership.permissions.includes(
      "mark_attendance",
    ),
  );
});
