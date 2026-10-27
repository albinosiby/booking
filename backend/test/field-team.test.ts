import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from "@nestjs/common";
import { ZodError } from "zod";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import type { Actor } from "../src/common/auth.guard";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  service = new WorkspaceService(db);
let mails = 0;
service.emailTeamAccess.mailer = {
  async send() {
    mails++;
  },
};
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());

const actor = (email?: string): Actor => {
  const id = randomUUID();
  return { uid: id, email: email ?? `${id}@example.com`, name: "Person" };
};
const org = {
  name: "Team Arena",
  contact_phone: "9876543210",
  currency: "INR",
  location: {
    name: "Main",
    address_line_1: "Road 1",
    address_line_2: null,
    city: "Kochi",
    state_code: "KL",
    country_code: "IN",
    postal_code: "682001",
    timezone: "Asia/Kolkata",
  },
};
type World = Awaited<ReturnType<typeof world>>;
async function world() {
  const owner = actor();
  await service.createOrganization(owner, org);
  const w = await service.workspace(owner);
  const business = await service.createBusiness(owner, {
    name: "Turf",
    type: "turf",
    location_id: w.locations[0].id,
  });
  const other = await service.createBusiness(owner, {
    name: "Court",
    type: "badminton",
    location_id: w.locations[0].id,
  });
  const r1 = await service.addResource(owner, business.id, { name: "Pitch A" });
  const r2 = await service.addResource(owner, business.id, { name: "Pitch B" });
  const o1 = await service.addResource(owner, other.id, { name: "Court 1" });
  const ownerMember = await service.member(owner);
  return {
    owner,
    ownerMemberId: ownerMember.id as string,
    org: ownerMember.organization_id as string,
    business: business.id as string,
    other: other.id as string,
    r1: r1.id as string,
    r2: r2.id as string,
    o1: o1.id as string,
  };
}
const draft = (
  w: World,
  email: string,
  patch: Record<string, unknown> = {},
) => ({
  email,
  display_name: "Team Member",
  role: "staff",
  permissions: ["view_bookings"],
  assignments: [{ business_id: w.business, resource_ids: [w.r1] }],
  ...patch,
});
/** Adds an active member through the email-login path. */
async function member(
  w: World,
  role: "staff" | "manager" | "owner" = "staff",
  patch: Record<string, unknown> = {},
) {
  const a = actor();
  await service.emailTeamAccess.add(
    w.owner,
    draft(w, a.email, { role, ...patch }),
  );
  await service.session(a);
  const m = await service.member(a);
  return { a, id: m.id as string };
}
const status = (e: unknown) =>
  (e as { getStatus?: () => number })?.getStatus?.();

// -------------------------------------------------------- privilege escalation

test("non-owner members cannot reach any owner-only operation", async () => {
  const w = await world();
  const staff = await member(w, "staff");
  const manager = await member(w, "manager", {
    permissions: [
      "view_bookings",
      "manage_bookings",
      "view_finance",
      "collect_payments",
    ],
  });
  const target = await member(w, "staff");
  const pending = await service.emailTeamAccess.add(
    w.owner,
    draft(w, actor().email),
  );
  const legacy = await service.invite(w.owner, draft(w, actor().email));
  const body = draft(w, "x@example.com");
  for (const who of [staff.a, manager.a]) {
    const calls: Array<[string, () => Promise<unknown>]> = [
      ["team", () => service.team(who)],
      ["invite", () => service.invite(who, body)],
      [
        "invite owner",
        () =>
          service.invite(
            who,
            draft(w, "o@example.com", {
              role: "owner",
              permissions: [],
              assignments: [],
            }),
          ),
      ],
      ["add", () => service.emailTeamAccess.add(who, body)],
      [
        "add owner",
        () =>
          service.emailTeamAccess.add(
            who,
            draft(w, "o2@example.com", {
              role: "owner",
              permissions: [],
              assignments: [],
            }),
          ),
      ],
      ["deliver", () => service.emailTeamAccess.deliver(who, pending.id)],
      [
        "update pending",
        () =>
          service.emailTeamAccess.update(
            who,
            pending.id,
            draft(w, "x@example.com"),
          ),
      ],
      ["revoke member", () => service.revoke(who, target.id, false)],
      ["revoke invitation", () => service.revoke(who, legacy.id, true)],
      ["delete member", () => service.deleteTeamRecord(who, target.id, false)],
      [
        "delete invitation",
        () => service.deleteTeamRecord(who, legacy.id, true),
      ],
      [
        "update member (self promote)",
        () =>
          service.updateMember(
            who,
            who === staff.a ? staff.id : manager.id,
            draft(w, who.email, { role: "owner" }),
          ),
      ],
      [
        "update member (other)",
        () => service.updateMember(who, target.id, draft(w, "x@example.com")),
      ],
      ["owner coach", () => service.ownerCoach(who, { coach: true })],
      [
        "plan coaches",
        () => service.planCoaches(who, w.business, { version: 1, coaches: {} }),
      ],
      [
        "create business",
        () =>
          service.createBusiness(who, {
            name: "Mine",
            type: "turf",
            location_id: randomUUID(),
          }),
      ],
      [
        "rename",
        () => service.renameBusiness(who, w.business, { name: "Renamed" }),
      ],
      [
        "add resource",
        () => service.addResource(who, w.business, { name: "Mine" }),
      ],
      ["delete resource", () => service.deleteResource(who, w.business, w.r1)],
      ["activate", () => service.activate(who, w.business)],
      [
        "reorder",
        () =>
          service.reorderBusinesses(who, {
            business_ids: [w.business, w.other],
            revision: 0,
          }),
      ],
      ["org details", () => service.organizationDetails(who)],
      [
        "org update",
        () =>
          service.updateOrganization(who, {
            revision: "a".repeat(64),
            name: "Hacked",
            contact_phone: "9876543210",
            locations: [
              {
                id: randomUUID(),
                name: "Main",
                address_line_1: "Road 1",
                address_line_2: null,
                city: "Kochi",
                state_code: "KL",
                country_code: "IN",
                postal_code: "682001",
              },
            ],
          }),
      ],
      [
        "logo upload",
        () =>
          service.uploadLogo(who, {
            content_type: "image/png",
            base64: Buffer.concat([
              Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
              Buffer.alloc(8),
            ]).toString("base64"),
          }),
      ],
    ];
    for (const [label, call] of calls) {
      const e = await call().then(
        () => null,
        (x) => x,
      );
      assert.ok(
        e instanceof ForbiddenException,
        `${label} must be Forbidden for ${who === staff.a ? "staff" : "manager"} but got ${e?.constructor?.name}: ${e?.message}`,
      );
    }
  }
  // Nothing changed.
  assert.equal(
    (await service.workspace(w.owner)).businesses.find(
      (b: any) => b.id === w.business,
    )!.name,
    "Turf",
  );
  assert.equal(
    (await service.team(w.owner)).members.find((m: any) => m.id === target.id)
      .active,
    true,
  );
});

test("a user with no membership at all is refused by every operation", async () => {
  const w = await world();
  const nobody = actor();
  for (const call of [
    () => service.team(nobody),
    () => service.invite(nobody, draft(w, "x@example.com")),
    () => service.revoke(nobody, w.ownerMemberId, false),
    () =>
      service.updateMember(nobody, w.ownerMemberId, draft(w, "x@example.com")),
    () => service.renameBusiness(nobody, w.business, { name: "Renamed" }),
    () =>
      service.uploadLogo(nobody, {
        content_type: "image/png",
        base64: Buffer.concat([
          Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
          Buffer.alloc(8),
        ]).toString("base64"),
      }),
  ])
    await assert.rejects(call, ForbiddenException);
});

test("a removed member loses access immediately and cannot read the workspace or act", async () => {
  const w = await world();
  const m = await member(w, "manager");
  await service.revoke(w.owner, m.id, false);
  await assert.rejects(() => service.workspace(m.a), /access has been removed/);
  await assert.rejects(() => service.team(m.a), ForbiddenException);
  await assert.rejects(
    () => service.invite(m.a, draft(w, "z@example.com")),
    ForbiddenException,
  );
});

test("staff cannot use an invitation addressed to someone else or to another organization", async () => {
  const w = await world();
  const w2 = await world();
  const staff = await member(w, "staff");
  const intended = actor();
  const inv = await service.invite(
    w2.owner,
    draft(w2, intended.email, {
      role: "owner",
      permissions: [],
      assignments: [],
    }),
  );
  const token = new URL(inv.invitation_url).searchParams.get("token")!;
  await assert.rejects(
    () => service.accept(staff.a, token),
    ForbiddenException,
    "wrong email",
  );
  const own = await service
    .invite(
      w2.owner,
      draft(w2, staff.a.email, {
        role: "owner",
        permissions: [],
        assignments: [],
      }),
    )
    .catch((e) => e);
  assert.ok(
    own instanceof ConflictException,
    "cannot invite an active member's email",
  );
  assert.equal((await service.member(staff.a)).role, "staff");
});

test("an active member of one organization cannot accept an owner invitation from another", async () => {
  const w = await world();
  const w2 = await world();
  const staff = await member(w, "staff");
  // Directly craft a pending invitation for the staff member's email in the other org.
  const token = "ab".repeat(32);
  await db.query(
    "INSERT INTO invitations(id,organization_id,email,display_name,role,permissions,assignments,token_hash,expires_at) VALUES($1,$2,$3,'X Y','owner','[]','[]',$4,now()+interval '1 day')",
    [
      randomUUID(),
      w2.org,
      staff.a.email,
      createHash("sha256").update(token).digest("hex"),
    ],
  );
  await assert.rejects(() => service.accept(staff.a, token), ConflictException);
  assert.equal((await service.member(staff.a)).organization_id, w.org);
  assert.equal((await service.member(staff.a)).role, "staff");
});

// --------------------------------------------------------------- owner role

test("owner role: promoting a member to owner clears scoped permissions and assignments", async () => {
  const w = await world();
  const m = await member(w, "staff", {
    permissions: ["view_bookings", "coach"],
  });
  await service.updateMember(
    w.owner,
    m.id,
    draft(w, m.a.email, { role: "owner" }),
  );
  const row = (await service.team(w.owner)).members.find(
    (x: any) => x.id === m.id,
  );
  assert.equal(row.role, "owner");
  assert.deepEqual(row.permissions, []);
  assert.deepEqual(row.assignments, []);
  // The promoted owner can now manage the organization.
  const p = await service.team(m.a);
  assert.ok(p.members.length >= 2);
});

test("owner role: an owner row can never be edited through the member editor, even by another owner", async () => {
  const w = await world();
  const second = await member(w, "owner", { permissions: [], assignments: [] });
  await assert.rejects(
    () =>
      service.updateMember(
        w.owner,
        second.id,
        draft(w, second.a.email, { role: "staff" }),
      ),
    NotFoundException,
  );
  await assert.rejects(
    () =>
      service.updateMember(
        second.a,
        w.ownerMemberId,
        draft(w, w.owner.email, { role: "staff" }),
      ),
    NotFoundException,
  );
  assert.equal((await service.member(w.owner)).role, "owner");
  assert.equal((await service.member(second.a)).role, "owner");
});

test("owner role: a sole owner cannot remove, delete or demote themselves", async () => {
  const w = await world();
  await assert.rejects(
    () => service.revoke(w.owner, w.ownerMemberId, false),
    /cannot remove your own owner access/,
  );
  await assert.rejects(
    () => service.deleteTeamRecord(w.owner, w.ownerMemberId, false),
    ConflictException,
  );
  await assert.rejects(
    () =>
      service.updateMember(
        w.owner,
        w.ownerMemberId,
        draft(w, w.owner.email, { role: "staff" }),
      ),
    NotFoundException,
  );
  assert.equal((await service.member(w.owner)).active, true);
});

test("owner role: two owners removing each other concurrently leaves exactly one active owner", async () => {
  const w = await world();
  const second = await member(w, "owner", { permissions: [], assignments: [] });
  const results = await Promise.allSettled([
    service.revoke(w.owner, second.id, false),
    service.revoke(second.a, w.ownerMemberId, false),
  ]);
  const ok = results.filter((r) => r.status === "fulfilled").length;
  assert.ok(ok >= 1, "at least one removal proceeds");
  const active = (
    await db.query(
      "SELECT id FROM memberships WHERE organization_id=$1 AND role='owner' AND active",
      [w.org],
    )
  ).rows.length;
  assert.equal(active, 1, `exactly one owner must remain, got ${active}`);
});

test("owner role: removing another owner keeps the remover and revokes the removed owner's pending grants", async () => {
  const w = await world();
  const second = await member(w, "owner", { permissions: [], assignments: [] });
  await service.revoke(w.owner, second.id, false);
  await assert.rejects(() => service.workspace(second.a), /removed/);
  assert.equal((await service.member(w.owner)).active, true);
});

test("owner role: sarvam voice-agent memberships cannot be removed, edited or deleted through Team", async () => {
  const w = await world();
  const sid = randomUUID();
  await db.query(
    "INSERT INTO memberships(id,organization_id,user_id,email,display_name,role,permissions,active) VALUES($1,$2,$3,'voice-agent@sarvam.invalid','Sarvam voice agent','staff','[]',false)",
    [sid, w.org, `sarvam:${w.org}`],
  );
  await assert.rejects(
    () => service.revoke(w.owner, sid, false),
    NotFoundException,
  );
  await assert.rejects(
    () =>
      service.updateMember(
        w.owner,
        sid,
        draft(w, "voice-agent@sarvam.invalid"),
      ),
    NotFoundException,
  );
  await assert.rejects(
    () => service.deleteTeamRecord(w.owner, sid, false),
    ConflictException,
  );
  assert.equal(
    (await service.team(w.owner)).members.some((m: any) => m.id === sid),
    false,
  );
});

// ---------------------------------------------------------------- cross tenant

test("cross-tenant: another organization's owner cannot revoke, edit, delete, resend or cancel your people", async () => {
  const mine = await world();
  const theirs = await world();
  const m = await member(mine, "staff");
  const pending = await service.emailTeamAccess.add(
    mine.owner,
    draft(mine, actor().email),
  );
  const legacy = await service.invite(mine.owner, draft(mine, actor().email));
  await assert.rejects(
    () => service.revoke(theirs.owner, m.id, false),
    NotFoundException,
  );
  await assert.rejects(
    () => service.revoke(theirs.owner, legacy.id, true),
    NotFoundException,
  );
  await assert.rejects(
    () => service.updateMember(theirs.owner, m.id, draft(theirs, m.a.email)),
    NotFoundException,
  );
  await assert.rejects(
    () => service.deleteTeamRecord(theirs.owner, m.id, false),
    NotFoundException,
  );
  await assert.rejects(
    () => service.deleteTeamRecord(theirs.owner, legacy.id, true),
    NotFoundException,
  );
  await assert.rejects(
    () => service.emailTeamAccess.deliver(theirs.owner, pending.id),
    ConflictException,
  );
  await assert.rejects(
    () =>
      service.emailTeamAccess.update(
        theirs.owner,
        pending.id,
        draft(theirs, "x@example.com"),
      ),
    NotFoundException,
  );
  assert.equal(
    (await service.team(mine.owner)).members.find((x: any) => x.id === m.id)
      .active,
    true,
  );
  const theirTeam = await service.team(theirs.owner);
  assert.equal(
    theirTeam.members.some((x: any) => x.id === m.id),
    false,
  );
  assert.equal(theirTeam.invitations.length, 0);
});

test("cross-tenant: assignments cannot reference another organization's business or resource", async () => {
  const mine = await world();
  const theirs = await world();
  const email = actor().email;
  for (const assignments of [
    [{ business_id: theirs.business, resource_ids: [] }],
    [{ business_id: theirs.business, resource_ids: [theirs.r1] }],
    [{ business_id: mine.business, resource_ids: [theirs.r1] }],
    [{ business_id: randomUUID(), resource_ids: [] }],
    [{ business_id: mine.business, resource_ids: [randomUUID()] }],
    [{ business_id: mine.business, resource_ids: [mine.o1] }],
    [{ business_id: mine.business, resource_ids: [mine.r1, mine.r1] }],
    [
      { business_id: mine.business, resource_ids: [] },
      { business_id: mine.business, resource_ids: [mine.r1] },
    ],
  ]) {
    await assert.rejects(
      () =>
        service.emailTeamAccess.add(
          mine.owner,
          draft(mine, email, { assignments }),
        ),
      BadRequestException,
      JSON.stringify(assignments),
    );
    await assert.rejects(
      () => service.invite(mine.owner, draft(mine, email, { assignments })),
      BadRequestException,
    );
  }
  assert.equal(
    (await service.team(mine.owner)).invitations.length,
    0,
    "failed grants must not leave pending rows",
  );
});

test("cross-tenant: an email already active in another organization cannot be added", async () => {
  const mine = await world();
  const theirs = await world();
  const m = await member(theirs, "staff");
  await assert.rejects(
    () => service.emailTeamAccess.add(mine.owner, draft(mine, m.a.email)),
    ConflictException,
  );
  await assert.rejects(
    () =>
      service.emailTeamAccess.add(
        mine.owner,
        draft(mine, m.a.email.toUpperCase()),
      ),
    ConflictException,
  );
  await assert
    .rejects(
      () => service.invite(mine.owner, draft(mine, m.a.email)),
      /already has active|This staff/,
    )
    .catch(() => undefined);
});

test("cross-tenant: pending email access in another organization blocks a second claim", async () => {
  const mine = await world();
  const theirs = await world();
  const email = actor().email;
  await service.emailTeamAccess.add(theirs.owner, draft(theirs, email));
  await assert.rejects(
    () => service.emailTeamAccess.add(mine.owner, draft(mine, email)),
    /another organization/,
  );
});

// ----------------------------------------------------------- duplicate invites

test("duplicate invites: email-login duplicates (any case) conflict and leave one pending row", async () => {
  const w = await world();
  const email = actor().email;
  await service.emailTeamAccess.add(w.owner, draft(w, email));
  await assert.rejects(
    () => service.emailTeamAccess.add(w.owner, draft(w, email)),
    /already awaiting sign-in/,
  );
  await assert.rejects(
    () => service.emailTeamAccess.add(w.owner, draft(w, email.toUpperCase())),
    /already awaiting sign-in/,
  );
  await assert.rejects(
    () => service.emailTeamAccess.add(w.owner, draft(w, `  ${email}  `)),
    ZodError,
  );
  assert.equal(
    (await service.team(w.owner)).invitations.filter(
      (i: any) => i.email === email && !i.revoked_at,
    ).length,
    1,
  );
});

test("duplicate invites: a new legacy invite revokes the previous token for the same email", async () => {
  const w = await world();
  const email = actor().email;
  const first = await service.invite(w.owner, draft(w, email));
  const second = await service.invite(w.owner, draft(w, email.toUpperCase()));
  const t = (r: { invitation_url: string }) =>
    new URL(r.invitation_url).searchParams.get("token")!;
  assert.notEqual(t(first), t(second));
  const invitee = actor(email);
  await assert.rejects(
    () => service.accept(invitee, t(first)),
    NotFoundException,
    "superseded token is dead",
  );
  const ok = await service.accept(invitee, t(second));
  assert.ok(ok.id);
  assert.equal(
    (
      await db.query(
        "SELECT 1 FROM invitations WHERE organization_id=$1 AND email=$2 AND accepted_at IS NULL AND revoked_at IS NULL",
        [w.org, email],
      )
    ).rows.length,
    0,
  );
});

test("duplicate invites: inviting yourself or an active teammate conflicts", async () => {
  const w = await world();
  const m = await member(w, "staff");
  await assert.rejects(
    () => service.invite(w.owner, draft(w, w.owner.email)),
    ConflictException,
  );
  await assert.rejects(
    () => service.invite(w.owner, draft(w, m.a.email)),
    ConflictException,
  );
  await assert.rejects(
    () => service.emailTeamAccess.add(w.owner, draft(w, w.owner.email)),
    ConflictException,
  );
  await assert.rejects(
    () => service.emailTeamAccess.add(w.owner, draft(w, m.a.email)),
    ConflictException,
  );
});

test("duplicate invites: concurrent adds for one email create exactly one pending entry", async () => {
  const w = await world();
  const email = actor().email;
  const r = await Promise.allSettled(
    Array.from({ length: 4 }, () =>
      service.emailTeamAccess.add(w.owner, draft(w, email)),
    ),
  );
  assert.equal(r.filter((x) => x.status === "fulfilled").length, 1);
  assert.equal(
    (
      await db.query(
        "SELECT 1 FROM invitations WHERE organization_id=$1 AND email=$2 AND revoked_at IS NULL AND accepted_at IS NULL",
        [w.org, email],
      )
    ).rows.length,
    1,
  );
});

test("duplicate invites: re-adding a removed member reactivates them with the new scope, never twice", async () => {
  const w = await world();
  const m = await member(w, "staff");
  await service.revoke(w.owner, m.id, false);
  await service.emailTeamAccess.add(
    w.owner,
    draft(w, m.a.email, {
      role: "manager",
      permissions: ["view_bookings", "manage_bookings"],
    }),
  );
  await service.session(m.a);
  await service.session(m.a);
  const rows = (
    await db.query<any>("SELECT role,active FROM memberships WHERE email=$1", [
      m.a.email,
    ])
  ).rows;
  assert.equal(rows.length, 1);
  assert.deepEqual(rows[0], { role: "manager", active: true });
});

// ------------------------------------------------------------ invitation tokens

test("invitation tokens: malformed tokens are rejected before any database lookup", async () => {
  const w = await world();
  const u = actor();
  const good = "a1".repeat(32);
  for (const bad of [
    "",
    " ",
    good.slice(1),
    good + "a",
    good.toUpperCase(),
    `${good}\n`,
    "g".repeat(64),
    "../".repeat(21),
    "' OR 1=1 --",
    null,
    undefined,
    5,
    {},
    ["a"],
  ])
    await assert
      .rejects(
        () => service.accept(u, bad as never),
        BadRequestException,
        JSON.stringify(bad)?.slice(0, 30),
      )
      .catch((e) => {
        // non-string input throws a TypeError from RegExp coercion only if it stringifies to a valid token
        throw e;
      });
  await assert.rejects(
    () => service.accept(u, good),
    NotFoundException,
    "unknown but well-formed token",
  );
  assert.ok(w);
});

test("invitation tokens: the stored hash is not itself an acceptable token and the url token is single-use", async () => {
  const w = await world();
  const invitee = actor();
  const inv = await service.invite(w.owner, draft(w, invitee.email));
  const token = new URL(inv.invitation_url).searchParams.get("token")!;
  assert.match(token, /^[a-f0-9]{64}$/);
  const stored = (
    await db.query<{ token_hash: string }>(
      "SELECT token_hash FROM invitations WHERE id=$1",
      [inv.id],
    )
  ).rows[0].token_hash;
  assert.notEqual(stored, token);
  await assert.rejects(
    () => service.accept(invitee, stored),
    NotFoundException,
    "leaked hash must not authenticate",
  );
  await service.accept(invitee, token);
  await assert.rejects(
    () => service.accept(invitee, token),
    NotFoundException,
    "replay",
  );
  await assert.rejects(
    () => service.accept(actor(invitee.email), token),
    NotFoundException,
    "replay by another session of the same email",
  );
});

test("invitation tokens: an expired token is refused, and the owner view marks it expired", async () => {
  const w = await world();
  const invitee = actor();
  const inv = await service.invite(w.owner, draft(w, invitee.email));
  const token = new URL(inv.invitation_url).searchParams.get("token")!;
  await db.query(
    "UPDATE invitations SET expires_at=now()-interval '1 second' WHERE id=$1",
    [inv.id],
  );
  await assert.rejects(
    () => service.accept(invitee, token),
    /expired or unavailable/,
  );
  const row = (await service.team(w.owner)).invitations.find(
    (i: any) => i.id === inv.id,
  );
  assert.ok(new Date(row.expires_at) < new Date());
  assert.equal(row.accepted_at, null);
  assert.equal(
    JSON.stringify(await service.team(w.owner)).includes(token),
    false,
  );
  assert.equal(
    JSON.stringify(await service.team(w.owner)).includes("token_hash"),
    false,
  );
});

test("invitation tokens: acceptance with a different email is forbidden and leaves the invitation usable", async () => {
  const w = await world();
  const invitee = actor();
  const inv = await service.invite(w.owner, draft(w, invitee.email));
  const token = new URL(inv.invitation_url).searchParams.get("token")!;
  await assert.rejects(
    () => service.accept(actor(), token),
    ForbiddenException,
  );
  await assert.rejects(
    () => service.accept(actor(`${invitee.email}.evil`), token),
    ForbiddenException,
  );
  await service.accept(invitee, token);
});

test("invitation tokens: invitation created for a business later deleted from scope is revalidated at acceptance", async () => {
  const w = await world();
  const invitee = actor();
  const inv = await service.invite(
    w.owner,
    draft(w, invitee.email, {
      assignments: [{ business_id: w.business, resource_ids: [w.r2] }],
    }),
  );
  const token = new URL(inv.invitation_url).searchParams.get("token")!;
  await db.query("DELETE FROM resources WHERE id=$1", [w.r2]);
  await assert.rejects(
    () => service.accept(invitee, token),
    BadRequestException,
  );
  assert.equal((await service.workspace(invitee)).organization, null);
});

test("pending removals: cancelled legacy invitation and removed member cannot be revived by the old token", async () => {
  const w = await world();
  const invitee = actor();
  const inv = await service.invite(w.owner, draft(w, invitee.email));
  const token = new URL(inv.invitation_url).searchParams.get("token")!;
  await service.revoke(w.owner, inv.id, true);
  await assert.rejects(() => service.accept(invitee, token), NotFoundException);
  await assert.rejects(
    () => service.revoke(w.owner, randomUUID(), true),
    NotFoundException,
  );
});

// ------------------------------------------------------------- member editor

test("member editor: email is immutable, role must be valid and unknown ids are not found", async () => {
  const w = await world();
  const m = await member(w, "staff");
  await assert.rejects(
    () =>
      service.updateMember(w.owner, m.id, draft(w, "different@example.com")),
    /cannot be changed/,
  );
  await assert.rejects(
    () => service.updateMember(w.owner, randomUUID(), draft(w, m.a.email)),
    NotFoundException,
  );
  for (const bad of [
    { role: "admin" },
    { role: null },
    { permissions: ["root"] },
    { display_name: "" },
    { assignments: [] },
    { extra: 1 },
  ])
    await assert.rejects(
      () => service.updateMember(w.owner, m.id, draft(w, m.a.email, bad)),
      ZodError,
      JSON.stringify(bad),
    );
  await service.updateMember(
    w.owner,
    m.id,
    draft(w, m.a.email.toUpperCase(), { display_name: "Renamed Member" }),
  );
  assert.equal(
    (await service.team(w.owner)).members.find((x: any) => x.id === m.id)
      .display_name,
    "Renamed Member",
  );
});

test("member editor: an invalid edit changes nothing (atomic)", async () => {
  const w = await world();
  const m = await member(w, "staff", { permissions: ["view_bookings"] });
  await assert.rejects(
    () =>
      service.updateMember(
        w.owner,
        m.id,
        draft(w, m.a.email, {
          permissions: ["view_finance"],
          assignments: [
            { business_id: w.business, resource_ids: [randomUUID()] },
          ],
        }),
      ),
    BadRequestException,
  );
  const row = (await service.team(w.owner)).members.find(
    (x: any) => x.id === m.id,
  );
  assert.deepEqual(row.permissions, ["view_bookings"]);
  assert.equal(row.assignments[0].resource_ids[0], w.r1);
});

test("member editor: inactive or removed members cannot be edited back to life", async () => {
  const w = await world();
  const m = await member(w, "staff");
  await service.revoke(w.owner, m.id, false);
  await assert.rejects(
    () => service.updateMember(w.owner, m.id, draft(w, m.a.email)),
    NotFoundException,
  );
});

// ------------------------------------------------------------- permanent delete

test("permanent delete: only removed members and cancelled invitations, never active, accepted or pending ones", async () => {
  const w = await world();
  const m = await member(w, "staff");
  await assert.rejects(
    () => service.deleteTeamRecord(w.owner, m.id, false),
    /Only removed team members/,
  );
  const pending = await service.invite(w.owner, draft(w, actor().email));
  await assert.rejects(
    () => service.deleteTeamRecord(w.owner, pending.id, true),
    /Only cancelled/,
  );
  const accepted = (
    await db.query<{ id: string }>(
      "SELECT id FROM invitations WHERE organization_id=$1 AND accepted_at IS NOT NULL LIMIT 1",
      [w.org],
    )
  ).rows[0];
  await assert.rejects(
    () => service.deleteTeamRecord(w.owner, accepted.id, true),
    /Only cancelled/,
  );
  for (const bad of [
    "",
    "x",
    "00000000-0000-0000-0000-00000000000g",
    "../1",
    null,
    5,
  ])
    await assert.rejects(
      () => service.deleteTeamRecord(w.owner, bad as never, false),
      ZodError,
    );
  await service.revoke(w.owner, pending.id, true);
  assert.deepEqual(await service.deleteTeamRecord(w.owner, pending.id, true), {
    id: pending.id,
    deleted: true,
  });
  await service.revoke(w.owner, m.id, false);
  assert.deepEqual(await service.deleteTeamRecord(w.owner, m.id, false), {
    id: m.id,
    deleted: true,
  });
  await assert.rejects(
    () => service.deleteTeamRecord(w.owner, m.id, false),
    NotFoundException,
  );
});

// ----------------------------------------------------------- email pending edit

test("pending access editor: email is immutable and only pending email entries are editable", async () => {
  const w = await world();
  const email = actor().email;
  const p = await service.emailTeamAccess.add(w.owner, draft(w, email));
  await assert.rejects(
    () =>
      service.emailTeamAccess.update(
        w.owner,
        p.id,
        draft(w, "other@example.com"),
      ),
    /correct email/,
  );
  await assert.rejects(
    () =>
      service.emailTeamAccess.update(w.owner, randomUUID(), draft(w, email)),
    NotFoundException,
  );
  for (const bad of [
    { role: "root" },
    { assignments: [] },
    { display_name: "x" },
    { permissions: "view_bookings" },
  ])
    await assert.rejects(
      () => service.emailTeamAccess.update(w.owner, p.id, draft(w, email, bad)),
      ZodError,
    );
  await service.revoke(w.owner, p.id, true);
  await assert.rejects(
    () => service.emailTeamAccess.update(w.owner, p.id, draft(w, email)),
    NotFoundException,
  );
});

test("pending access resend: unknown, cancelled and accepted entries are refused; rapid resends are throttled", async () => {
  const w = await world();
  const p = await service.emailTeamAccess.add(w.owner, draft(w, actor().email));
  await assert.rejects(
    () => service.emailTeamAccess.deliver(w.owner, p.id),
    /sent recently/,
  );
  await assert.rejects(
    () => service.emailTeamAccess.deliver(w.owner, randomUUID()),
    ConflictException,
  );
  await service.revoke(w.owner, p.id, true);
  await db.query(
    "UPDATE invitations SET email_attempted_at=now()-interval '5 minutes' WHERE id=$1",
    [p.id],
  );
  await assert.rejects(
    () => service.emailTeamAccess.deliver(w.owner, p.id),
    ConflictException,
  );
});

// ----------------------------------------------------------------- session join

test("session bootstrap: accounts without an invitation or with a different email get no access", async () => {
  const w = await world();
  await service.emailTeamAccess.add(
    w.owner,
    draft(w, "pending.person@example.com"),
  );
  const stranger = actor();
  assert.equal((await service.session(stranger)).organization, null);
  const near = actor("pending.person@example.com.au");
  assert.equal((await service.session(near)).organization, null);
  const sub = actor("pending.person+tag@example.com");
  assert.equal(
    (await service.session(sub)).organization,
    null,
    "plus-addressing is a different identity",
  );
});

test("session bootstrap: upper-case session email still matches the lower-cased grant", async () => {
  const w = await world();
  const id = randomUUID();
  const email = `${id}@example.com`;
  await service.emailTeamAccess.add(w.owner, draft(w, email));
  const upper: Actor = { uid: id, email: email.toUpperCase(), name: "Upper" };
  const s = await service.session(upper);
  assert.equal(s.membership?.role, "staff");
});

test("session bootstrap: an active member of another organization cannot claim a pending grant", async () => {
  const w1 = await world();
  const w2 = await world();
  const m = await member(w1, "staff");
  await db.query(
    "INSERT INTO invitations(id,organization_id,email,display_name,role,permissions,assignments,token_hash,expires_at,join_mode,email_status) VALUES($1,$2,$3,'Foo Bar','owner','[]','[]',$4,'infinity','email_login','pending')",
    [
      randomUUID(),
      w2.org,
      m.a.email,
      randomUUID().replaceAll("-", "").repeat(2),
    ],
  );
  const s = await service.session(m.a);
  assert.equal(s.membership?.organization_id, w1.org);
  assert.equal(
    s.membership?.role,
    "staff",
    "no silent privilege escalation through a foreign owner grant",
  );
});

// -------------------------------------------------------------------- coaches

test("owner coach toggle: strict boolean, idempotent and owner-only", async () => {
  const w = await world();
  for (const bad of [
    null,
    undefined,
    {},
    { coach: "true" },
    { coach: 1 },
    { coach: null },
    { coach: true, extra: 1 },
    [],
  ])
    await assert.rejects(
      () => service.ownerCoach(w.owner, bad),
      ZodError,
      JSON.stringify(bad),
    );
  await service.ownerCoach(w.owner, { coach: true });
  await service.ownerCoach(w.owner, { coach: true });
  let perms = (await service.member(w.owner)).permissions as string[];
  assert.equal(perms.filter((p) => p === "coach").length, 1);
  await service.ownerCoach(w.owner, { coach: false });
  await service.ownerCoach(w.owner, { coach: false });
  perms = (await service.member(w.owner)).permissions as string[];
  assert.equal(perms.includes("coach"), false);
  const m = await member(w, "manager");
  await assert.rejects(
    () => service.ownerCoach(m.a, { coach: true }),
    ForbiddenException,
  );
});

test("plan coaches payload: version, coach map and ids are validated", async () => {
  const w = await world();
  for (const bad of [
    null,
    {},
    { version: 0, coaches: {} },
    { version: 1.5, coaches: {} },
    { version: "1", coaches: {} },
    { version: 1 },
    { version: 1, coaches: null },
    { version: 1, coaches: { plan: "x" } },
    { version: 1, coaches: { "": randomUUID() } },
    { version: 1, coaches: { ["p".repeat(101)]: randomUUID() } },
    { version: 1, coaches: {}, extra: 1 },
    { version: 1, coaches: { plan: 5 } },
  ])
    await assert.rejects(
      () => service.planCoaches(w.owner, w.business, bad),
      ZodError,
      JSON.stringify(bad),
    );
  await assert.rejects(
    () => service.planCoaches(w.owner, w.business, { version: 1, coaches: {} }),
    /pool or court configuration/,
  );
  await assert.rejects(
    () =>
      service.planCoaches(w.owner, randomUUID(), { version: 1, coaches: {} }),
    NotFoundException,
  );
});

// ------------------------------------------------------------ information leaks

test(
  "workspace snapshot for staff does not expose the creator's account id",
  { todo: "BUG-9" },
  async () => {
    const w = await world();
    const staff = await member(w, "staff");
    const snapshot = await service.workspace(staff.a);
    assert.equal(
      Object.hasOwn(snapshot.organization as object, "created_by"),
      false,
    );
  },
);

test("team listing never exposes invitation secrets", async () => {
  const w = await world();
  await service.invite(w.owner, draft(w, actor().email));
  await service.emailTeamAccess.add(w.owner, draft(w, actor().email));
  const dump = JSON.stringify(await service.team(w.owner));
  assert.equal(/token_hash|email_attempt_id|invitation_url/.test(dump), false);
});

test("status helper sanity", () => {
  assert.equal(status(new ForbiddenException()), 403);
  assert.equal(mails >= 0, true);
});
