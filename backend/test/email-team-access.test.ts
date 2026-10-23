import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import type { Actor } from "../src/common/auth.guard";
import {
  teamAccessMessage,
  teamLoginUrls,
  type TeamAccessNotice,
} from "../src/workspace/team-access-mailer";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  service = new WorkspaceService(db);
const messages: TeamAccessNotice[] = [];
let mailFails = false;
service.emailTeamAccess.mailer = {
  async send(notice) {
    messages.push(notice);
    if (mailFails)
      throw new Error("private SMTP credentials must never escape");
  },
};
const actor = (): Actor => {
  const uid = randomUUID();
  return { uid, email: `${uid}@example.com`, name: "Test owner" };
};
async function fixture() {
  const owner = actor();
  await service.createOrganization(owner, {
    name: "Falcon Arena",
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
  });
  const w = await service.workspace(owner);
  const business = await service.createBusiness(owner, {
    name: "Falcon Turf",
    type: "turf",
    location_id: w.locations[0].id,
  });
  const resource = await service.addResource(owner, business.id, {
    name: "Court A",
    capacity: 1,
  });
  const staff = actor();
  const draft = {
    email: staff.email.toUpperCase(),
    display_name: "Team Member",
    role: "staff",
    permissions: ["view_bookings"],
    assignments: [{ business_id: business.id, resource_ids: [resource.id] }],
  };
  return { owner, staff, draft, business, resource };
}
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());

test("email access sends named scope and activates only on matching verified session bootstrap", async () => {
  const f = await fixture();
  const result = await service.emailTeamAccess.add(f.owner, f.draft);
  assert.equal(result.delivery, "sent");
  assert.equal("invitation_url" in result, false);
  assert.equal(messages.at(-1)!.organization, "Falcon Arena");
  assert.deepEqual(messages.at(-1)!.assignments, [
    { business: "Falcon Turf", resources: ["Court A"] },
  ]);
  assert.equal((await service.workspace(f.staff)).organization, null);
  assert.equal((await service.session(actor())).organization, null);
  const w = await service.session(f.staff);
  assert.equal(w.membership.role, "staff");
  assert.deepEqual(w.membership.permissions, ["view_bookings"]);
  assert.deepEqual(
    w.businesses.map((b) => b.id),
    [f.business.id],
  );
  assert.deepEqual(
    w.businesses[0].resources.map((r: any) => r.id),
    [f.resource.id],
  );
  assert.equal((await service.session(f.staff)).membership.id, w.membership.id);
  assert.ok(
    (
      await db.query<any>("SELECT accepted_at FROM invitations WHERE id=$1", [
        result.id,
      ])
    ).rows[0].accepted_at,
  );
  await assert.rejects(() => service.team(f.staff), /Only the owner/);
  await assert.rejects(
    () => service.emailTeamAccess.add(f.staff, f.draft),
    /Only the owner/,
  );
  await assert.rejects(
    () => service.emailTeamAccess.add(f.owner, f.draft),
    /already has active/,
  );
});

test("SMTP failure preserves access and exposes retryable status without SMTP errors", async () => {
  const f = await fixture();
  mailFails = true;
  const result = await service.emailTeamAccess.add(f.owner, f.draft);
  mailFails = false;
  assert.equal(result.delivery, "failed");
  assert.equal(
    (await service.team(f.owner)).invitations[0].email_status,
    "failed",
  );
  assert.equal(JSON.stringify(result).includes("credentials"), false);
  await assert.rejects(
    () => service.emailTeamAccess.deliver(f.owner, result.id),
    /Wait 30 seconds/,
  );
  await db.query(
    "UPDATE invitations SET email_attempted_at=now()-interval '1 minute' WHERE id=$1",
    [result.id],
  );
  assert.equal(
    (await service.emailTeamAccess.deliver(f.owner, result.id)).delivery,
    "sent",
  );
  assert.equal((await service.session(f.staff)).membership.role, "staff");
});

test("pending edits change emailed and activated scope; foreign owners cannot edit or resend", async () => {
  const f = await fixture(),
    other = await fixture();
  const added = await service.emailTeamAccess.add(f.owner, f.draft);
  await assert.rejects(
    () => service.emailTeamAccess.update(other.owner, added.id, f.draft),
    /unavailable/,
  );
  await assert.rejects(() =>
    service.emailTeamAccess.deliver(other.owner, added.id),
  );
  await assert.rejects(
    () =>
      service.emailTeamAccess.update(f.owner, added.id, {
        ...f.draft,
        email: actor().email,
      }),
    /correct email/,
  );
  const updated = {
    ...f.draft,
    role: "manager",
    permissions: ["manage_bookings"],
    assignments: [{ business_id: f.business.id, resource_ids: [] }],
  };
  await service.emailTeamAccess.update(f.owner, added.id, updated);
  assert.equal(messages.at(-1)!.role, "manager");
  assert.deepEqual(messages.at(-1)!.permissions, ["manage_bookings"]);
  const w = await service.session(f.staff);
  assert.equal(w.membership.role, "manager");
  await service.updateMember(f.owner, w.membership.id, {
    ...updated,
    permissions: [],
  });
  assert.deepEqual((await service.session(f.staff)).membership.permissions, []);
});

test("cancelled entries and removed members never regain access without a fresh owner grant", async () => {
  const f = await fixture();
  const added = await service.emailTeamAccess.add(f.owner, f.draft);
  await service.revoke(f.owner, added.id, true);
  assert.equal((await service.session(f.staff)).organization, null);
  await assert.rejects(() =>
    service.emailTeamAccess.deliver(f.owner, added.id),
  );
  await service.emailTeamAccess.add(f.owner, f.draft);
  const w = await service.session(f.staff);
  await service.revoke(f.owner, w.membership.id, false);
  await assert.rejects(() => service.session(f.staff), /removed/);
  await service.emailTeamAccess.add(f.owner, { ...f.draft, permissions: [] });
  const restored = await service.session(f.staff);
  assert.equal(restored.membership.id, w.membership.id);
  assert.deepEqual(restored.membership.permissions, []);
});

test("email grants reject foreign resources, duplicates and ambiguous organizations; concurrent sign-in is idempotent", async () => {
  const f = await fixture(),
    other = await fixture();
  await assert.rejects(
    () =>
      service.emailTeamAccess.add(f.owner, {
        ...f.draft,
        assignments: [{ business_id: other.business.id, resource_ids: [] }],
      }),
    /outside/,
  );
  await assert.rejects(
    () =>
      service.emailTeamAccess.add(f.owner, {
        ...f.draft,
        assignments: [
          { business_id: f.business.id, resource_ids: [other.resource.id] },
        ],
      }),
    /Invalid resource/,
  );
  await service.emailTeamAccess.add(f.owner, f.draft);
  await assert.rejects(
    () => service.emailTeamAccess.add(f.owner, f.draft),
    /already awaiting/,
  );
  await assert.rejects(
    () =>
      service.emailTeamAccess.add(other.owner, {
        ...f.draft,
        assignments: [{ business_id: other.business.id, resource_ids: [] }],
      }),
    /another organization/,
  );
  const [a, b] = await Promise.all([
    service.session(f.staff),
    service.session(f.staff),
  ]);
  assert.equal(a.membership.id, b.membership.id);
  assert.equal(
    (
      await db.query("SELECT id FROM memberships WHERE user_id=$1", [
        f.staff.uid,
      ])
    ).rows.length,
    1,
  );
});

test("legacy invitations still require explicit token acceptance", async () => {
  const f = await fixture();
  const invitation = await service.invite(f.owner, f.draft);
  assert.equal((await service.session(f.staff)).organization, null);
  await service.accept(
    f.staff,
    new URL(invitation.invitation_url).searchParams.get("token")!,
  );
  assert.equal((await service.session(f.staff)).membership.role, "staff");
});

test("email markup escapes names and includes app/web login links without access tokens", () => {
  const mail = teamAccessMessage({
    email: "staff@example.com",
    name: '<img src=x onerror="alert(1)">',
    organization: "Falcon & friends",
    role: "staff",
    permissions: ["coach", "mark_attendance"],
    assignments: [{ business: "Court <A>", resources: [] }],
  });
  assert.match(mail.html, /&lt;img/);
  assert.equal(mail.html.includes("<img src=x"), false);
  assert.match(mail.text, /Mark attendance/);
  assert.match(mail.text, /https:\/\/bookingos.online\/app\/sign-in/);
  assert.match(mail.text, /bookingservice.tatos.tech:\/\/login\/sign-in/);
  assert.equal(mail.text.includes("?token="), false);
  assert.throws(() =>
    teamLoginUrls({
      TEAM_LOGIN_WEB_URL: "https://example.com/sign-in?next=evil",
    }),
  );
  assert.throws(() =>
    teamLoginUrls({ TEAM_LOGIN_WEB_URL: "javascript:alert(1)" }),
  );
});

test("Nodemailer uses authenticated TLS, safe message options and closes transport on acceptance or rejection", async () => {
  const { NodemailerTeamAccessMailer } =
    await import("../src/workspace/team-access-mailer");
  const notice = {
    email: "staff@example.com",
    name: "Staff",
    organization: "Falcon",
    role: "staff",
    permissions: [],
    assignments: [],
  };
  let closed = 0,
    accepted = true;
  const mailer = new NodemailerTeamAccessMailer(
    async (options) => {
      assert.equal(options.port, 465);
      assert.equal(options.secure, true);
      assert.equal(options.tls?.rejectUnauthorized, true);
      assert.equal(options.disableFileAccess, true);
      assert.equal(options.disableUrlAccess, true);
      assert.equal(options.debug, false);
      return {
        async sendMail(message) {
          assert.deepEqual(message.to, {
            name: "Staff",
            address: "staff@example.com",
          });
          assert.match(
            String(message.text),
            /https:\/\/bookingos.online\/app\/sign-in/,
          );
          return {
            accepted: accepted ? ["staff@example.com"] : [],
            rejected: accepted ? [] : ["staff@example.com"],
          };
        },
        close() {
          closed++;
        },
      };
    },
    {
      SMTP_HOST: "smtp.example.com",
      SMTP_PORT: "465",
      SMTP_USER: "test-user",
      SMTP_PASSWORD: "test-only-password",
      SMTP_FROM: "team@example.com",
    },
  );
  await mailer.send(notice);
  accepted = false;
  await assert.rejects(() => mailer.send(notice), /not accepted/);
  assert.equal(closed, 2);
  const missing = new NodemailerTeamAccessMailer(async () => {
    throw new Error("must not connect");
  }, {});
  await assert.rejects(() => missing.send(notice), /SMTP_HOST/);
});

test("a removed member cannot receive an unusable grant to a different organization", async () => {
  const f = await fixture(),
    other = await fixture();
  await service.emailTeamAccess.add(f.owner, f.draft);
  const member = (await service.session(f.staff)).membership;
  await service.revoke(f.owner, member.id, false);
  await assert.rejects(
    () =>
      service.emailTeamAccess.add(other.owner, {
        ...f.draft,
        assignments: [{ business_id: other.business.id, resource_ids: [] }],
      }),
    /another organization/,
  );
});
