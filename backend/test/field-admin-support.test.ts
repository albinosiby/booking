import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { createHash, createHmac, randomUUID } from "node:crypto";
import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from "@nestjs/common";
import { ZodError } from "zod";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { SarvamService } from "../src/sarvam/sarvam.service";
import { AdminService } from "../src/admin/admin.service";
import { AdminSarvamService } from "../src/admin/admin-sarvam.service";
import { SupportService } from "../src/support/support.service";
import { AgentCallService } from "../src/agent-calls/agent-calls.service";
import { NotificationService } from "../src/notifications/notification.service";
import { BookingService } from "../src/bookings/booking.service";
import { AdmissionService } from "../src/admissions/admission.service";
import { panelActor } from "../src/admin/panel-auth";
import type { Actor } from "../src/common/auth.guard";
delete process.env.DATABASE_URL;
Object.assign(process.env, {
  NODE_ENV: "test",
  PGLITE_PATH: "memory://",
  BOOKING_SECRETS_KEY: Buffer.alloc(32, 5).toString("base64"),
  ADMIN_SESSION_SECRET: "test-only-panel-signing-secret-0123456789",
});
const db = new Database(),
  workspace = new WorkspaceService(db),
  provider = new SarvamService(db, workspace),
  admin = new AdminService(db, provider),
  adminSarvam = new AdminSarvamService(db, admin, provider, workspace),
  support = new SupportService(db, workspace),
  calls = new AgentCallService(db, workspace, provider),
  devices = new NotificationService(db),
  bookings = new BookingService(db, workspace),
  admissions = new AdmissionService(db);
after(() => db.onModuleDestroy());

const actor = (): Actor => ({
  uid: randomUUID(),
  email: `${randomUUID()}@example.com`,
  name: "Person",
});
const org = {
  name: "Admin Arena",
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
async function tenant() {
  const owner = actor();
  await workspace.createOrganization(owner, org);
  const m = await workspace.member(owner);
  return {
    owner,
    org: m.organization_id as string,
    membership: m.id as string,
  };
}
async function staffOf(
  t: { org: string },
  permissions: string[] = ["view_bookings"],
  role = "staff",
) {
  const a = actor();
  const id = randomUUID();
  await db.query(
    "INSERT INTO memberships(id,organization_id,user_id,email,display_name,role,permissions) VALUES($1,$2,$3,$4,'Staff Person',$5,$6)",
    [id, t.org, a.uid, a.email, role, JSON.stringify(permissions)],
  );
  return { a, id };
}
const panel = (): Actor => {
  const ts = String(Date.now()),
    nonce = randomUUID();
  const digest = createHash("sha256").update("").digest("hex");
  const mac = createHmac("sha256", process.env.ADMIN_SESSION_SECRET!)
    .update(["booking-admin-v1", ts, nonce, "GET", "/x", digest].join("\n"))
    .digest("hex");
  return panelActor(`${ts}.${nonce}.${mac}`, "GET", "/x", undefined);
};
const root = panel();
const supportAdmin = actor();
const inactiveAdmin = actor();
before(async () => {
  await db.onModuleInit();
  await db.query(
    "INSERT INTO platform_admins(user_id,email,role) VALUES($1,$2,'support')",
    [supportAdmin.uid, supportAdmin.email],
  );
  await db.query(
    "INSERT INTO platform_admins(user_id,email,role,active) VALUES($1,$2,'super_admin',false)",
    [inactiveAdmin.uid, inactiveAdmin.email],
  );
});
const goodUuid = "00000000-0000-4000-8000-0000000000aa";
const fails = (p: Promise<unknown>) =>
  p.then(
    () => null,
    (e) => e as Error & { code?: string; getStatus?: () => number },
  );

// ------------------------------------------------------------- admin authority

test("admin: ordinary users, inactive admins and unknown actors are refused on every read and write", async () => {
  const t = await tenant();
  const calls: Array<(a: Actor) => Promise<unknown>> = [
    (a) => admin.me(a),
    (a) => admin.overview(a),
    (a) => admin.organizations(a, {}),
    (a) => admin.organization(a, goodUuid),
    (a) => admin.users(a, {}),
    (a) => admin.setUserActive(a, goodUuid, { active: true }),
    (a) => admin.tickets(a, {}),
    (a) => admin.ticket(a, goodUuid),
    (a) => admin.reply(a, goodUuid, { body: "hello" }),
    (a) => admin.setTicketStatus(a, goodUuid, { status: "closed" }),
    (a) => admin.agentRequests(a, {}),
    (a) => admin.auditLog(a, {}),
    (a) =>
      admin.updateAgentRequest(a, goodUuid, { version: 1, status: "active" }),
    (a) => admin.connection(a, goodUuid),
    (a) => admin.saveConnection(a, goodUuid, {}),
    (a) => admin.verifyConnection(a, goodUuid, {}),
    (a) => admin.rotateToolKey(a, goodUuid),
  ];
  for (const who of [
    t.owner,
    inactiveAdmin,
    actor(),
    {
      uid: "admin-panel",
      email: "admin-panel@bookingos.internal",
      name: "Platform admin",
    },
  ])
    for (const call of calls) {
      const e = await fails(call(who));
      assert.ok(
        e instanceof ForbiddenException,
        `${call.toString().slice(0, 60)} gave ${e?.constructor?.name}`,
      );
    }
});

test("admin: a support-role admin can read but never change provider connections or request status", async () => {
  assert.equal((await admin.me(supportAdmin)).role, "support");
  assert.ok((await admin.overview(supportAdmin)).organizations >= 0);
  for (const call of [
    () =>
      admin.updateAgentRequest(supportAdmin, goodUuid, {
        version: 1,
        status: "active",
      }),
    () => admin.connection(supportAdmin, goodUuid),
    () => admin.saveConnection(supportAdmin, goodUuid, {}),
    () => admin.verifyConnection(supportAdmin, goodUuid, {}),
    () => admin.rotateToolKey(supportAdmin, goodUuid),
    () => adminSarvam.save(supportAdmin, {}),
    () => adminSarvam.connect(supportAdmin),
    () => adminSarvam.callback(supportAdmin, {}),
    () => adminSarvam.inventory(supportAdmin),
    () => adminSarvam.approve(supportAdmin, goodUuid, {}),
  ])
    await assert.rejects(call, /Super-admin access required/);
});

test("admin: identifiers in paths must be UUIDs", async () => {
  for (const bad of [
    "",
    "x",
    "1",
    goodUuid.slice(1),
    `${goodUuid}0`,
    "' OR 1=1 --",
    "../../etc",
    "%00",
    "00000000-0000-4000-8000-00000000000g",
    "{}",
    " ",
  ]) {
    for (const call of [
      () => admin.organization(root, bad),
      () => admin.ticket(root, bad),
      () => admin.reply(root, bad, { body: "hello" }),
      () => admin.setTicketStatus(root, bad, { status: "open" }),
      () => admin.setUserActive(root, bad, { active: true }),
      () =>
        admin.updateAgentRequest(root, bad, { version: 1, status: "paused" }),
      () => admin.connection(root, bad),
      () => admin.rotateToolKey(root, bad),
      () =>
        admin.verifyConnection(root, bad, {
          version: 1,
          tools_confirmed: true,
        }),
    ]) {
      const e = await fails(call());
      assert.ok(
        e instanceof BadRequestException &&
          /Invalid identifier/.test(e.message),
        `${JSON.stringify(bad)}: ${e?.constructor?.name} ${e?.message}`,
      );
    }
  }
});

test("admin: unknown organizations, tickets and users are 404, not empty successes", async () => {
  await assert.rejects(
    () => admin.organization(root, goodUuid),
    NotFoundException,
  );
  await assert.rejects(() => admin.ticket(root, goodUuid), NotFoundException);
  await assert.rejects(
    () => admin.reply(root, goodUuid, { body: "hello" }),
    NotFoundException,
  );
  await assert.rejects(
    () => admin.setTicketStatus(root, goodUuid, { status: "closed" }),
    NotFoundException,
  );
  await assert.rejects(
    () => admin.setUserActive(root, goodUuid, { active: false }),
    NotFoundException,
  );
  await assert.rejects(
    () =>
      admin.updateAgentRequest(root, goodUuid, {
        version: 1,
        status: "paused",
      }),
    NotFoundException,
  );
  await assert.rejects(
    () => admin.connection(root, goodUuid),
    NotFoundException,
  );
});

// ------------------------------------------------------------ admin list inputs

test("admin lists: limit parsing is lenient but bounded", async () => {
  await tenant();
  await tenant();
  const n = async (limit: unknown) =>
    (await admin.organizations(root, { limit } as never)).organizations.length;
  assert.equal(await n("1"), 1);
  assert.equal(await n(" 1 "), 1);
  for (const bad of [
    "0",
    "-5",
    "abc",
    "2.5",
    "",
    "NaN",
    "Infinity",
    undefined,
    null,
    "0x2",
    "1e1000",
  ])
    assert.ok(
      (await n(bad)) >= 2,
      `limit=${bad} falls back to the default page`,
    );
  assert.ok((await n("999999")) <= 500);
});

test("admin search: wildcard and escape characters match literally", async () => {
  const a = await tenant(),
    b = await tenant();
  await db.query("UPDATE organizations SET name='Fun 100% Club' WHERE id=$1", [
    a.org,
  ]);
  await db.query("UPDATE organizations SET name='Fun 100 Club' WHERE id=$1", [
    b.org,
  ]);
  const names = async (q: string) =>
    (await admin.organizations(root, { q })).organizations.map(
      (o: any) => o.name,
    );
  assert.deepEqual(await names("100%"), ["Fun 100% Club"]);
  assert.equal((await names("%")).includes("Fun 100 Club"), false);
  assert.equal(
    (await names("Fun 100_")).length,
    0,
    "underscore is not a wildcard",
  );
  assert.equal((await names("\\")).length, 0);
  assert.equal((await names("' OR 1=1 --")).length, 0);
  assert.ok((await names("")).length >= 2);
  assert.ok((await names("   ")).length >= 2);
  assert.ok((await names("fun 100")).length >= 2, "case-insensitive");
  assert.ok(
    (await names("Fun 100 Club".padEnd(500, " "))).includes("Fun 100 Club"),
    "whitespace padding is trimmed before the 80-char cut",
  );
  const users = (await admin.users(root, { q: a.owner.email.slice(0, 8) }))
    .users;
  assert.ok(Array.isArray(users));
});

test(
  "admin search: NUL characters in the query are a client error",
  { todo: "BUG-4" },
  async () => {
    const e = await fails(admin.users(root, { q: "ab\u0000c" }));
    assert.ok(
      e === null || e.getStatus?.() !== undefined,
      `got ${e?.constructor?.name} ${e?.code}`,
    );
  },
);

test(
  "admin tickets/requests: an unrecognised status filter is rejected rather than silently ignored",
  { todo: "BUG-15" },
  async () => {
    const e = await fails(admin.tickets(root, { status: "bogus" }));
    assert.ok(e instanceof BadRequestException);
    const e2 = await fails(admin.agentRequests(root, { status: "bogus" }));
    assert.ok(e2 instanceof BadRequestException);
  },
);

// --------------------------------------------------------------- admin writes

test("admin: activating or deactivating users validates the body strictly", async () => {
  const t = await tenant();
  const s = await staffOf(t);
  for (const bad of [
    null,
    undefined,
    {},
    { active: "true" },
    { active: 1 },
    { active: null },
    { active: [] },
    "true",
    [],
  ])
    await assert.rejects(
      () => admin.setUserActive(root, s.id, bad),
      BadRequestException,
      JSON.stringify(bad),
    );
  assert.deepEqual(await admin.setUserActive(root, s.id, { active: false }), {
    id: s.id,
    active: false,
  });
  assert.deepEqual(await admin.setUserActive(root, s.id, { active: true }), {
    id: s.id,
    active: true,
  });
  await assert.rejects(
    () => admin.setUserActive(root, t.membership, { active: false }),
    /owner cannot be deactivated/,
  );
  assert.equal((await workspace.member(t.owner)).active, true);
});

test(
  "admin: the managed voice-agent membership cannot be switched on from the generic user toggle",
  { todo: "BUG-14" },
  async () => {
    const t = await tenant();
    const sid = randomUUID();
    await db.query(
      "INSERT INTO memberships(id,organization_id,user_id,email,display_name,role,permissions,active) VALUES($1,$2,$3,'voice-agent@sarvam.invalid','Sarvam voice agent','staff','[]',false)",
      [sid, t.org, `sarvam:${t.org}`],
    );
    await assert.rejects(() =>
      admin.setUserActive(supportAdmin, sid, { active: true }),
    );
    assert.equal(
      (
        await db.query<{ active: boolean }>(
          "SELECT active FROM memberships WHERE id=$1",
          [sid],
        )
      ).rows[0].active,
      false,
    );
  },
);

test("admin: ticket replies and status changes validate their bodies", async () => {
  const t = await tenant();
  const made = (
    await support.create(t.owner, {
      subject: "Help please",
      message: "Something broke",
    })
  ).ticket as { id: string };
  for (const bad of [
    null,
    undefined,
    {},
    { body: "" },
    { body: "   " },
    { body: 5 },
    { body: null },
    { body: ["x"] },
    { body: "x".repeat(4001) },
    "hello",
  ])
    await assert.rejects(
      () => admin.reply(root, made.id, bad),
      BadRequestException,
      JSON.stringify(bad)?.slice(0, 30),
    );
  await admin.reply(root, made.id, { body: "x".repeat(4000) });
  await admin.reply(root, made.id, { body: "  മറുപടി 🙂  " });
  const detail = await admin.ticket(root, made.id);
  assert.equal(detail.messages.at(-1).body, "മറുപടി 🙂");
  for (const bad of [
    null,
    {},
    { status: "" },
    { status: "Open" },
    { status: "done" },
    { status: null },
    { status: ["open"] },
    { status: "open " },
  ])
    await assert.rejects(
      () => admin.setTicketStatus(root, made.id, bad),
      BadRequestException,
      JSON.stringify(bad),
    );
  for (const status of ["open", "in_progress", "resolved", "closed"])
    assert.equal(
      (await admin.setTicketStatus(root, made.id, { status })).status,
      status,
    );
});

test("admin: every write is recorded in the audit log with the acting admin", async () => {
  const t = await tenant();
  const s = await staffOf(t);
  const before = (await admin.auditLog(root, {})).events.length;
  await admin.setUserActive(root, s.id, { active: false });
  const events = (await admin.auditLog(root, { limit: "5" })).events;
  assert.ok((await admin.auditLog(root, {})).events.length > before);
  assert.equal(events[0].action, "user.deactivate");
  assert.equal(events[0].admin_email, "admin-panel@bookingos.internal");
});

// --------------------------------------------------------- agent request admin

async function request(
  t: Awaited<ReturnType<typeof tenant>>,
  services = ["booking", "enquiry"],
) {
  await calls.request(t.owner, { services, note: "please" });
  return (
    await db.query<{ id: string; version: number }>(
      "SELECT id,version FROM agent_call_requests WHERE organization_id=$1",
      [t.org],
    )
  ).rows[0];
}

test("agent request admin: update payload boundaries", async () => {
  const t = await tenant();
  const r = await request(t);
  for (const bad of [
    null,
    {},
    { status: "paused" },
    { version: 0, status: "paused" },
    { version: -1, status: "paused" },
    { version: 1.5, status: "paused" },
    { version: "1", status: "paused" },
    { version: 1, status: "Paused" },
    { version: 1, status: "approved" },
    { version: 1, status: null },
    { version: 1, status: "paused", admin_note: "x".repeat(2001) },
    { version: 1, status: "paused", user_message: "x".repeat(501) },
    { version: 1, status: "paused", admin_note: 5 },
  ])
    await assert.rejects(
      () => admin.updateAgentRequest(root, r.id, bad),
      BadRequestException,
      JSON.stringify(bad)?.slice(0, 50),
    );
  await assert.rejects(
    () =>
      admin.updateAgentRequest(root, r.id, {
        version: r.version + 5,
        status: "paused",
      }),
    ConflictException,
  );
  await assert.rejects(
    () =>
      admin.updateAgentRequest(root, r.id, {
        version: r.version,
        status: "active",
      }),
    /Verify the connection/,
  );
  assert.equal(
    (
      await admin.updateAgentRequest(root, r.id, {
        version: r.version,
        status: "in_review",
        admin_note: "x".repeat(2000),
        user_message: "y".repeat(500),
      })
    ).status,
    "in_review",
  );
});

test("agent request admin: connection payload boundaries are validated before the database is touched", async () => {
  const t = await tenant();
  const r = await request(t);
  const ok = {
    api_key: "sk_test_12345678",
    sarvam_org_id: "org_1",
    workspace_id: "ws-1",
    app_id: "app_1",
    version: 0,
    phone_number: "+919876543210",
    deployment_id: "dep_1",
    approved_services: ["booking"],
  };
  const bad = (patch: Record<string, unknown>) =>
    admin.saveConnection(root, t.org, { ...ok, ...patch });
  const cases: Array<[string, unknown[]]> = [
    ["api_key", ["short", " 1234567 ", "x".repeat(501), 5, null]],
    [
      "sarvam_org_id",
      ["", " ", "a b", "a/b", "../x", "ü", "x".repeat(101), null, 5, "a\nb"],
    ],
    ["workspace_id", ["", "a b", "a;b", "x".repeat(101), undefined]],
    ["app_id", ["", "a.b", "a@b", "x".repeat(101), undefined]],
    ["version", [-1, 1.5, "1", null, undefined, NaN]],
    [
      "phone_number",
      [
        "",
        "9876543210",
        "+0123456789",
        "+91 98765 43210",
        "+91-9876543210",
        "++919876543210",
        "+1234567",
        "+1234567890123456",
        "+٩١٩٨٧٦٥٤٣٢١٠",
        "tel:+919876543210",
        " 919876543210",
        null,
        919876543210,
      ],
    ],
    ["deployment_id", ["", "a b", "x".repeat(201), "a/b", undefined]],
    [
      "approved_services",
      [
        [],
        ["booking", "booking"],
        ["voicemail"],
        ["booking", "rescheduling", "enquiry", "cancellation", "booking"],
        "booking",
        null,
        [null],
        undefined,
      ],
    ],
  ];
  for (const [field, values] of cases)
    for (const v of values) {
      const e = await fails(bad({ [field]: v }));
      assert.ok(
        e instanceof BadRequestException,
        `${field}=${JSON.stringify(v)} gave ${e?.constructor?.name}`,
      );
    }
  for (const phone of ["+12345678", "+123456789012345", "+919876543210"]) {
    const e = await fails(
      bad({ phone_number: phone, approved_services: ["cancellation"] }),
    );
    assert.ok(
      e instanceof BadRequestException &&
        /requested by the client/.test(e.message),
      "valid phone reaches the service rule",
    );
  }
  assert.ok(r.id);
});

test("agent request admin: services not requested by the client cannot be approved, and a valid save never exposes the API key", async () => {
  const t = await tenant();
  await request(t, ["booking"]);
  const ok = {
    api_key: "sk_test_secret_value_12345",
    sarvam_org_id: `org_${randomUUID().slice(0, 8)}`,
    workspace_id: "ws1",
    app_id: `app_${randomUUID().slice(0, 8)}`,
    version: 0,
    phone_number: `+9198${Math.floor(10000000 + Math.random() * 89999999)}`,
    deployment_id: "dep1",
    approved_services: ["booking"],
  };
  await assert.rejects(
    () =>
      admin.saveConnection(root, t.org, {
        ...ok,
        approved_services: ["booking", "cancellation"],
      }),
    /only services requested/,
  );
  const saved = await admin.saveConnection(root, t.org, ok);
  const dump = JSON.stringify(saved);
  assert.equal(dump.includes("sk_test_secret_value_12345"), false);
  assert.equal((saved as any).api_key_last4, "2345");
  assert.equal((saved as any).has_api_key, true);
});

test(
  "agent request admin: saving a connection for a non-existent organization is a 404",
  { todo: "BUG-16" },
  async () => {
    const e = await fails(
      admin.saveConnection(root, randomUUID(), {
        api_key: "sk_test_12345678",
        sarvam_org_id: "o",
        workspace_id: "w",
        app_id: "a",
        version: 0,
        phone_number: "+919876543210",
        deployment_id: "d",
        approved_services: ["booking"],
      }),
    );
    assert.ok(
      e instanceof NotFoundException || e instanceof BadRequestException,
      `got ${e?.constructor?.name} code=${e?.code}`,
    );
  },
);

test("agent request admin: the same phone number or agent cannot be assigned to two organizations", async () => {
  const a = await tenant(),
    b = await tenant();
  await request(a);
  await request(b);
  const shared = {
    sarvam_org_id: `o${randomUUID().slice(0, 6)}`,
    workspace_id: "w1",
    app_id: `a${randomUUID().slice(0, 6)}`,
    phone_number: `+9197${Math.floor(10000000 + Math.random() * 89999999)}`,
    deployment_id: "d1",
    approved_services: ["booking"],
  };
  await admin.saveConnection(root, a.org, {
    ...shared,
    api_key: "sk_test_12345678",
    version: 0,
  });
  await assert.rejects(
    () =>
      admin.saveConnection(root, b.org, {
        ...shared,
        api_key: "sk_test_12345678",
        version: 0,
      }),
    ConflictException,
  );
  await assert.rejects(
    () =>
      admin.saveConnection(root, b.org, {
        ...shared,
        app_id: "other_app",
        api_key: "sk_test_12345678",
        version: 0,
      }),
    ConflictException,
    "phone alone is unique",
  );
  await assert.rejects(
    () =>
      admin.saveConnection(root, b.org, {
        ...shared,
        phone_number: "+919700000001",
        api_key: "sk_test_12345678",
        version: 0,
      }),
    ConflictException,
    "agent triple alone is unique",
  );
});

test("agent request admin: verify body requires the explicit confirmation literal and a positive version", async () => {
  const t = await tenant();
  await request(t);
  for (const bad of [
    null,
    {},
    { version: 1 },
    { tools_confirmed: true },
    { version: 1, tools_confirmed: false },
    { version: 1, tools_confirmed: "true" },
    { version: 0, tools_confirmed: true },
    { version: 1.5, tools_confirmed: true },
    { version: 1, tools_confirmed: true, extra: 1 },
  ])
    await assert.rejects(
      () => admin.verifyConnection(root, t.org, bad),
      BadRequestException,
      JSON.stringify(bad),
    );
});

test("admin sarvam: settings, callback and approval payloads are strict", async () => {
  const ok = { version: 1, sarvam_org_id: "org1", workspace_id: "ws1" };
  for (const bad of [
    null,
    {},
    { ...ok, version: 0 },
    { ...ok, version: 1.5 },
    { ...ok, sarvam_org_id: "" },
    { ...ok, sarvam_org_id: "a b" },
    { ...ok, workspace_id: "x".repeat(101) },
    { ...ok, template_app_id: "a/b" },
    { ...ok, api_key: "short" },
    { ...ok, api_key: "x".repeat(501) },
    { ...ok, extra: 1 },
  ])
    await assert.rejects(
      () => adminSarvam.save(root, bad),
      ZodError,
      JSON.stringify(bad)?.slice(0, 50),
    );
  for (const bad of [
    null,
    {},
    { state: "short" },
    { state: "x".repeat(201) },
    { state: "x".repeat(30), code: "" },
    { state: "x".repeat(30), code: "c".repeat(4001) },
    { state: "x".repeat(30), error: "e".repeat(201) },
    { state: "x".repeat(30), iss: "https://evil.example" },
    { state: "x".repeat(30), extra: 1 },
  ])
    await assert.rejects(
      () => adminSarvam.callback(root, bad),
      ZodError,
      JSON.stringify(bad)?.slice(0, 50),
    );
  const approve = {
    version: 1,
    approved_services: ["booking"],
    phone_number: "+919876543210",
    connection_id: "c1",
  };
  for (const bad of [
    null,
    {},
    { ...approve, version: 0 },
    { ...approve, approved_services: [] },
    { ...approve, approved_services: ["x"] },
    { ...approve, phone_number: "9876543210" },
    { ...approve, connection_id: "a b" },
    { ...approve, extra: 1 },
  ])
    await assert.rejects(
      () => adminSarvam.approve(root, goodUuid, bad),
      ZodError,
      JSON.stringify(bad)?.slice(0, 50),
    );
  for (const bad of ["x", "", "../x", " "])
    await assert.rejects(
      () => adminSarvam.approve(root, bad, approve),
      ZodError,
    );
});

// --------------------------------------------------------------------- support

test("support: create validates category, subject and message boundaries", async () => {
  const t = await tenant();
  const ok = { category: "booking", subject: "Hello", message: "Message body" };
  const bad = (patch: Record<string, unknown>) =>
    support.create(t.owner, { ...ok, ...patch });
  for (const [field, values] of [
    ["category", ["", "Booking", "billing", null, 5, ["booking"], "other "]],
    ["subject", ["", "  ", "ab", " ab ", null, 5, ["x"], "x".repeat(161)]],
    ["message", ["", "    ", "abcd", " abcd ", null, 5, "x".repeat(4001)]],
  ] as const)
    for (const v of values)
      assert.ok(
        (await fails(bad({ [field]: v }))) instanceof BadRequestException,
        `${field}=${JSON.stringify(v)}`,
      );
  for (const input of [
    null,
    undefined,
    "x",
    5,
    [],
    { ...ok, organization_id: randomUUID() },
    { ...ok, status: "resolved" },
    { ...ok, membership_id: randomUUID() },
  ])
    assert.ok(
      (await fails(support.create(t.owner, input))) instanceof
        BadRequestException,
      JSON.stringify(input)?.slice(0, 40),
    );
  const defaults = await support.create(t.owner, {
    subject: "abc",
    message: "abcde",
  });
  assert.equal((defaults.ticket as any).category, "other");
  const edge = await support.create(t.owner, {
    subject: "x".repeat(160),
    message: "m".repeat(4000),
  });
  assert.equal((edge.ticket as any).subject.length, 160);
  const uni = await support.create(t.owner, {
    subject: "  പ്രശ്നം 🙂  ",
    message: "  കൊച്ചി ഇമോജി 🏟  ",
  });
  assert.equal((uni.ticket as any).subject, "പ്രശ്നം 🙂");
  assert.equal((uni.messages as any[])[0].body, "കൊച്ചി ഇമോജി 🏟");
});

test(
  "support: invisible-only subjects and NUL characters are refused cleanly",
  { todo: "BUG-3" },
  async () => {
    const t = await tenant();
    assert.ok(
      (await fails(
        support.create(t.owner, {
          subject: "​​​",
          message: "visible body text",
        }),
      )) instanceof BadRequestException,
    );
  },
);

test(
  "support: NUL character in a ticket is a client error",
  { todo: "BUG-4" },
  async () => {
    const t = await tenant();
    const e = await fails(
      support.create(t.owner, {
        subject: "abc\u0000",
        message: "visible body text",
      }),
    );
    assert.ok(
      e?.getStatus && e.getStatus() < 500,
      `got ${e?.constructor?.name} ${e?.code}`,
    );
  },
);

test("support: users without an active membership cannot create, list or read", async () => {
  const t = await tenant();
  const made = (
    await support.create(t.owner, {
      subject: "Mine only",
      message: "Private text",
    })
  ).ticket as { id: string };
  const stranger = actor();
  const removed = await staffOf(t);
  await db.query("UPDATE memberships SET active=false WHERE id=$1", [
    removed.id,
  ]);
  for (const who of [stranger, removed.a]) {
    await assert.rejects(
      () =>
        support.create(who, { subject: "Mine only", message: "Private text" }),
      ForbiddenException,
    );
    await assert.rejects(() => support.list(who), ForbiddenException);
    await assert.rejects(
      () => support.detail(who, made.id),
      ForbiddenException,
    );
    await assert.rejects(
      () => support.addMessage(who, made.id, { message: "hello" }),
      ForbiddenException,
    );
  }
});

test("support: tickets are isolated per organization and ids are validated", async () => {
  const a = await tenant(),
    b = await tenant();
  const made = (
    await support.create(a.owner, {
      subject: "A secret",
      message: "Only A should see this",
    })
  ).ticket as { id: string };
  await assert.rejects(
    () => support.detail(b.owner, made.id),
    NotFoundException,
  );
  await assert.rejects(
    () => support.addMessage(b.owner, made.id, { message: "intrude" }),
    NotFoundException,
  );
  assert.equal((await support.list(b.owner)).tickets.length, 0);
  assert.equal(
    (
      await db.query("SELECT 1 FROM support_messages WHERE ticket_id=$1", [
        made.id,
      ])
    ).rows.length,
    1,
  );
  for (const bad of [
    "",
    "x",
    "1",
    `${made.id}x`,
    "' OR 1=1 --",
    "00000000-0000-0000-0000-000000000000",
    made.id.toUpperCase().slice(0, 35),
  ])
    await assert.rejects(
      () => support.detail(a.owner, bad),
      NotFoundException,
      bad,
    );
  // A teammate of the same organization shares the organization's tickets.
  const mate = await staffOf(a, []);
  assert.equal((await support.detail(mate.a, made.id)).ticket.id, made.id);
});

test("support: replies validate length, reopen resolved tickets and cannot be forged as admin", async () => {
  const t = await tenant();
  const made = (
    await support.create(t.owner, {
      subject: "Reply test",
      message: "First message",
    })
  ).ticket as { id: string };
  for (const bad of [
    null,
    undefined,
    {},
    { message: "" },
    { message: "   " },
    { message: 5 },
    { message: "x".repeat(4001) },
    { message: "ok", author: "admin" },
    { message: "ok", ticket_id: randomUUID() },
    "hello",
  ])
    assert.ok(
      (await fails(support.addMessage(t.owner, made.id, bad))) instanceof
        BadRequestException,
      JSON.stringify(bad)?.slice(0, 40),
    );
  await admin.setTicketStatus(root, made.id, { status: "closed" });
  const r = await support.addMessage(t.owner, made.id, {
    message: "x".repeat(4000),
  });
  assert.equal((r.ticket as any).status, "open");
  assert.equal((r.messages as any[]).at(-1).author, "user");
  await support.addMessage(t.owner, made.id, { message: "a" });
});

test("support: more than 20 open requests are refused, resolved ones do not count", async () => {
  const t = await tenant();
  const ids: string[] = [];
  for (let i = 0; i < 20; i++)
    ids.push(
      (
        (
          await support.create(t.owner, {
            subject: `Open ${i}`,
            message: "Message body",
          })
        ).ticket as any
      ).id,
    );
  await assert.rejects(
    () =>
      support.create(t.owner, {
        subject: "Twenty-first",
        message: "Message body",
      }),
    /too many open requests/,
  );
  await admin.setTicketStatus(root, ids[0], { status: "resolved" });
  await support.create(t.owner, {
    subject: "After resolve",
    message: "Message body",
  });
  await assert.rejects(
    () =>
      support.create(t.owner, {
        subject: "Over again",
        message: "Message body",
      }),
    /too many open requests/,
  );
  assert.ok((await support.list(t.owner)).tickets.length <= 100);
});

// ---------------------------------------------------------- device registration

const device = (patch: Record<string, unknown> = {}) => ({
  installation_id: randomUUID(),
  installation_secret: (randomUUID() + randomUUID()).replaceAll("-", ""),
  token: `${randomUUID()}${randomUUID()}`,
  platform: "android",
  ...patch,
});

test("device registration: field boundaries", async () => {
  const a = actor();
  for (const [field, values] of [
    [
      "installation_id",
      [
        "",
        "x",
        "not-a-uuid",
        `${randomUUID()}0`,
        null,
        5,
        undefined,
        randomUUID().slice(1),
      ],
    ],
    [
      "installation_secret",
      [
        "",
        "a".repeat(63),
        "a".repeat(65),
        "A".repeat(64),
        "g".repeat(64),
        ` ${"a".repeat(63)}`,
        `${"a".repeat(64)}\n`,
        null,
        5,
        undefined,
      ],
    ],
    [
      "token",
      [
        "",
        "x".repeat(19),
        20,
        null,
        undefined,
        ["x".repeat(20)],
        "x".repeat(4097),
      ],
    ],
    [
      "platform",
      ["", "web", "Android", "IOS", "android ", null, 1, undefined, "windows"],
    ],
  ] as const)
    for (const v of values)
      await assert.rejects(
        () => devices.register(a, device({ [field]: v })),
        ZodError,
        `${field}=${JSON.stringify(v)?.slice(0, 20)}`,
      );
  for (const bad of [
    null,
    undefined,
    "x",
    5,
    [],
    { ...device(), user_id: "other" },
    { ...device(), enabled: false },
  ])
    await assert.rejects(() => devices.register(a, bad), ZodError);
  await devices.register(a, device({ token: "x".repeat(20) }));
  await devices.register(
    a,
    device({ token: "t".repeat(4096), platform: "ios" }),
  );
  await devices.register(a, device({ token: "ü".repeat(40) }));
});

test(
  "device registration: a token made only of whitespace is not a push token",
  { todo: "BUG-17" },
  async () => {
    await assert.rejects(
      () => devices.register(actor(), device({ token: " ".repeat(30) })),
      ZodError,
    );
  },
);

test("device registration: voice-agent sessions cannot register devices", async () => {
  await assert.rejects(
    () =>
      devices.register(
        {
          uid: `sarvam:${randomUUID()}`,
          email: "voice-agent@sarvam.invalid",
          name: "v",
        },
        device(),
      ),
    ForbiddenException,
  );
});

test("device registration: proof is required to re-bind a known installation and tokens cannot be shared", async () => {
  const a = actor(),
    b = actor();
  const d = device();
  await devices.register(a, d);
  await assert.rejects(
    () => devices.register(b, { ...d, installation_secret: "0".repeat(64) }),
    ForbiddenException,
  );
  await assert.rejects(
    () =>
      devices.register(b, {
        ...d,
        installation_secret: d.installation_secret.toUpperCase(),
      }),
    ZodError,
  );
  await assert.rejects(
    () => devices.register(b, device({ token: d.token })),
    ConflictException,
  );
  const row = (
    await db.query<{ user_id: string }>(
      "SELECT user_id FROM notification_devices WHERE id=$1",
      [d.installation_id],
    )
  ).rows[0];
  assert.equal(row.user_id, a.uid);
});

test("device unregister: wrong secret, wrong user and bad ids never disable or reveal a device", async () => {
  const a = actor(),
    b = actor();
  const d = device();
  await devices.register(a, d);
  const enabled = async () =>
    (
      await db.query<{ enabled: boolean }>(
        "SELECT enabled FROM notification_devices WHERE id=$1",
        [d.installation_id],
      )
    ).rows[0].enabled;
  for (const bad of ["0".repeat(64), "a".repeat(63)]) {
    const r = await fails(
      devices.unregister(a, d.installation_id, { installation_secret: bad }),
    );
    assert.ok(r === null || r instanceof ZodError);
  }
  assert.deepEqual(
    await devices.unregister(b, d.installation_id, {
      installation_secret: d.installation_secret,
    }),
    { unregistered: true },
    "same response, no oracle",
  );
  assert.equal(
    await enabled(),
    true,
    "another user cannot disable the device even with the secret",
  );
  assert.deepEqual(
    await devices.unregister(a, randomUUID(), {
      installation_secret: d.installation_secret,
    }),
    { unregistered: true },
  );
  for (const id of ["", "x", "1", `${d.installation_id}x`])
    await assert.rejects(
      () =>
        devices.unregister(a, id, {
          installation_secret: d.installation_secret,
        }),
      ZodError,
    );
  for (const bad of [
    null,
    {},
    { installation_secret: 5 },
    { installation_secret: d.installation_secret, user_id: "x" },
  ])
    await assert.rejects(
      () => devices.unregister(a, d.installation_id, bad),
      ZodError,
    );
  await devices.unregister(a, d.installation_id, {
    installation_secret: d.installation_secret,
  });
  assert.equal(await enabled(), false);
});

test("installation revoke: needs the id and secret, ignores extra fields' influence and is idempotent", async () => {
  const a = actor();
  const d = device();
  await devices.register(a, d);
  for (const bad of [
    null,
    {},
    { installation_secret: d.installation_secret },
    { installation_id: d.installation_id },
    { installation_id: "x", installation_secret: d.installation_secret },
    {
      installation_id: d.installation_id,
      installation_secret: d.installation_secret,
      user_id: a.uid,
    },
  ])
    await assert.rejects(
      () => devices.revokeInstallation(bad),
      ZodError,
      JSON.stringify(bad)?.slice(0, 40),
    );
  assert.equal(
    (
      await db.query<{ enabled: boolean }>(
        "SELECT enabled FROM notification_devices WHERE id=$1",
        [d.installation_id],
      )
    ).rows[0].enabled,
    true,
  );
  await devices.revokeInstallation({
    installation_id: d.installation_id,
    installation_secret: "9".repeat(64),
  });
  assert.equal(
    (
      await db.query<{ enabled: boolean }>(
        "SELECT enabled FROM notification_devices WHERE id=$1",
        [d.installation_id],
      )
    ).rows[0].enabled,
    true,
  );
  await devices.revokeInstallation({
    installation_id: d.installation_id,
    installation_secret: d.installation_secret,
  });
  await devices.revokeInstallation({
    installation_id: d.installation_id,
    installation_secret: d.installation_secret,
  });
  assert.equal(
    (
      await db.query<{ enabled: boolean }>(
        "SELECT enabled FROM notification_devices WHERE id=$1",
        [d.installation_id],
      )
    ).rows[0].enabled,
    false,
  );
});

// ----------------------------------------------------- customer directory/search

test("customer directory: query boundaries and phone-only search", async () => {
  const t = await tenant();
  await db.query(
    "INSERT INTO customers(id,organization_id,name,phone) VALUES($1,$2,'Alice Smith','+91 98765 43210'),($3,$2,'Bob Jones','9123456789')",
    [randomUUID(), t.org, randomUUID()],
  );
  for (const bad of [
    "abc",
    "98765a",
    "<script>",
    "'; DROP TABLE customers;--",
    "98%",
    "9_",
    "x".repeat(51),
    "9".repeat(51),
    "٩٨٧٦٥",
  ])
    await assert.rejects(
      () => bookings.customerDirectory(t.owner, { q: bad }),
      ZodError,
      bad,
    );
  for (const bad of ["()", "+", "---", "( )"])
    await assert.rejects(
      () => bookings.customerDirectory(t.owner, { q: bad }),
      BadRequestException,
      bad,
    );
  for (const bad of [
    null,
    "98765",
    5,
    [],
    { q: 5 },
    { q: ["1"] },
    { q: "9", after: 5 },
    { q: "9", after: "x".repeat(81) },
    { q: "9", extra: 1 },
    { q: null },
  ])
    await assert.rejects(
      () => bookings.customerDirectory(t.owner, bad),
      ZodError,
      JSON.stringify(bad)?.slice(0, 30),
    );
  assert.equal(
    (await bookings.customerDirectory(t.owner, { q: "" })).items.length,
    2,
  );
  assert.equal(
    (await bookings.customerDirectory(t.owner, { q: "   " })).items.length,
    2,
  );
  assert.equal((await bookings.customerDirectory(t.owner, {})).items.length, 2);
  assert.equal(
    (await bookings.customerDirectory(t.owner, { q: "+91 (98765)" })).items
      .length,
    1,
  );
  assert.equal(
    (await bookings.customerDirectory(t.owner, { q: "9" })).items.length,
    2,
  );
  assert.equal(
    (await bookings.customerDirectory(t.owner, { q: "0000" })).items.length,
    0,
  );
  assert.equal(
    (await bookings.customerDirectory(t.owner, { q: "9".repeat(50) })).items
      .length,
    0,
  );
});

test("customer directory: other tenants' customers never appear and staff need a booking permission", async () => {
  const a = await tenant(),
    b = await tenant();
  await db.query(
    "INSERT INTO customers(id,organization_id,name,phone) VALUES($1,$2,'Tenant A','9000000001'),($3,$4,'Tenant B','9000000002')",
    [randomUUID(), a.org, randomUUID(), b.org],
  );
  const mine = (
    await bookings.customerDirectory(a.owner, { q: "9000" })
  ).items.map((i: any) => i.name);
  assert.deepEqual(mine, ["Tenant A"]);
  const noPerm = await staffOf(a, ["record_expenses"]);
  await assert.rejects(
    () => bookings.customerDirectory(noPerm.a, {}),
    ForbiddenException,
  );
  await assert.rejects(
    () => bookings.customerDirectory(actor(), {}),
    ForbiddenException,
  );
  const reader = await staffOf(a, ["view_bookings"]);
  assert.deepEqual(
    (await bookings.customerDirectory(reader.a, {})).items,
    [],
    "staff only see customers with bookings in their scope",
  );
  assert.deepEqual((await bookings.customers(reader.a, "9000")).items, []);
  assert.equal((await bookings.customers(a.owner, "9000")).items.length, 1);
  assert.deepEqual(
    (await bookings.customers(a.owner, "90")).items,
    [],
    "fewer than three digits returns nothing",
  );
  assert.deepEqual(
    (await bookings.customers(a.owner, "9".repeat(101))).items,
    [],
  );
});

test(
  "customer search: repeated query parameters must not crash the lookup",
  { todo: "BUG-18" },
  async () => {
    const t = await tenant();
    const e = await fails(bookings.customers(t.owner, ["900", "000"] as never));
    assert.ok(
      e === null || e.getStatus?.() !== undefined,
      `got ${e?.constructor?.name}: ${e?.message}`,
    );
  },
);

test(
  "customer search by name: wildcard characters in the query are literal",
  { todo: "BUG-19" },
  async () => {
    const t = await tenant();
    await db.query(
      "INSERT INTO customers(id,organization_id,name,phone) VALUES($1,$2,'Alice Smith','9111111111'),($3,$2,'Bob Jones','9222222222')",
      [randomUUID(), t.org, randomUUID()],
    );
    assert.equal(
      (await admissions.customers(t.owner, "Alice")).items.length,
      1,
    );
    assert.equal(
      (await admissions.customers(t.owner, "%%%")).items.length,
      0,
      "percent signs must not match every customer",
    );
    assert.equal(
      (await admissions.customers(t.owner, "___")).items.length,
      0,
      "underscores must not match every customer",
    );
  },
);

test("customer search by name: short, padded, long and non-string queries", async () => {
  const t = await tenant();
  await db.query(
    "INSERT INTO customers(id,organization_id,name,phone) VALUES($1,$2,'Alice Smith','9111111111')",
    [randomUUID(), t.org],
  );
  assert.deepEqual((await admissions.customers(t.owner, "al")).items, []);
  assert.deepEqual((await admissions.customers(t.owner, "  al  ")).items, []);
  assert.equal(
    (await admissions.customers(t.owner, "  alice  ")).items.length,
    1,
  );
  assert.equal((await admissions.customers(t.owner, "ALICE")).items.length, 1);
  assert.equal((await admissions.customers(t.owner, "91111")).items.length, 1);
  assert.deepEqual(
    (await admissions.customers(t.owner, "' OR 1=1 --")).items,
    [],
  );
  assert.ok(
    (await fails(admissions.customers(t.owner, "x".repeat(101)))) instanceof
      ZodError,
  );
  for (const bad of [null, undefined, 5, ["alice"], {}])
    assert.ok(
      (await fails(admissions.customers(t.owner, bad as never))) instanceof
        ZodError,
    );
  await assert.rejects(
    () => admissions.customers(actor(), "alice"),
    ForbiddenException,
  );
});
