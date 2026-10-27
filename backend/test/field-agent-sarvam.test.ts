import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  HttpException,
  NotFoundException,
  UnauthorizedException,
} from "@nestjs/common";
import { ZodError } from "zod";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import {
  SarvamService,
  voiceActor,
  hashToolKey,
  sealSecret,
} from "../src/sarvam/sarvam.service";
import { AgentCallService } from "../src/agent-calls/agent-calls.service";
import { voiceAccess } from "../src/agent-calls/agent-call-policy";
import { voiceResult } from "../src/sarvam/voice-result";
import type { Actor } from "../src/common/auth.guard";
delete process.env.DATABASE_URL;
Object.assign(process.env, {
  NODE_ENV: "test",
  PGLITE_PATH: "memory://",
  BOOKING_SECRETS_KEY: Buffer.alloc(32, 3).toString("base64"),
});
const db = new Database(),
  workspace = new WorkspaceService(db),
  provider = new SarvamService(db, workspace),
  calls = new AgentCallService(db, workspace, provider);
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());

const actor = (): Actor => ({
  uid: randomUUID(),
  email: `${randomUUID()}@example.com`,
  name: "Owner",
});
const orgBody = {
  name: "Voice Arena",
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
  await workspace.createOrganization(owner, orgBody);
  const m = await workspace.member(owner);
  return { owner, org: m.organization_id as string };
}
async function staffOf(
  t: { org: string },
  permissions: string[] = ["view_bookings"],
) {
  const a = actor();
  await db.query(
    "INSERT INTO memberships(id,organization_id,user_id,email,display_name,role,permissions) VALUES($1,$2,$3,$4,'Staff Person','staff',$5)",
    [randomUUID(), t.org, a.uid, a.email, JSON.stringify(permissions)],
  );
  return a;
}
const newKey = () => "bkv_" + randomBytes(32).toString("base64url");
/** Integration row with credentials, optional tool key and an active approved request. */
async function connected(
  t: { owner: Actor; org: string },
  opts: {
    enabled?: boolean;
    verified?: boolean;
    status?: string;
    services?: string[];
    key?: string;
  } = {},
) {
  await calls
    .request(t.owner, { services: opts.services ?? ["booking", "enquiry"] })
    .catch(() => undefined);
  const s = await db.transaction((tx) => provider.ensureManaged(tx, t.org));
  const key = opts.key ?? newKey();
  await db.query(
    `UPDATE sarvam_integrations SET enabled=$2,api_key_ciphertext=$3,api_key_last4='cret',sarvam_org_id='o1',workspace_id='w1',app_id=$4,phone_number=$8,
     tool_key_hash=$5,tool_key_prefix=$6,verified_at=CASE WHEN $7 THEN now() END WHERE organization_id=$1`,
    [
      t.org,
      opts.enabled ?? true,
      sealSecret("secret"),
      `app_${randomUUID().slice(0, 8)}`,
      hashToolKey(key),
      key.slice(0, 10),
      opts.verified ?? true,
      `+9199${Math.floor(10000000 + Math.random() * 89999999)}`,
    ],
  );
  await db.query(
    "UPDATE agent_call_requests SET status=$2,approved_services=$3 WHERE organization_id=$1",
    [t.org, opts.status ?? "active", opts.services ?? ["booking", "enquiry"]],
  );
  await db.query("UPDATE memberships SET active=$2 WHERE id=$1", [
    s.membership_id,
    opts.enabled ?? true,
  ]);
  return { key, membership: s.membership_id as string };
}
const fails = (p: Promise<unknown>) =>
  p.then(
    () => null,
    (e) => e as Error & { code?: string; getStatus?: () => number },
  );
const day = { start: "2026-10-01T00:00:00Z", end: "2026-10-02T00:00:00Z" };

// ------------------------------------------------------------------- request

test("agent calls request: services and note boundaries", async () => {
  const t = await tenant();
  for (const bad of [
    null,
    undefined,
    "x",
    [],
    {},
    { services: [] },
    { services: ["booking", "booking"] },
    { services: ["voicemail"] },
    { services: ["Booking"] },
    { services: "booking" },
    { services: [null] },
    {
      services: [
        "booking",
        "rescheduling",
        "enquiry",
        "cancellation",
        "booking",
      ],
    },
    { services: ["booking"], note: "x".repeat(2001) },
    { services: ["booking"], note: 5 },
    { services: ["booking"], note: null },
    { services: ["booking"], status: "active" },
    { services: ["booking"], organization_id: randomUUID() },
  ])
    await assert.rejects(
      () => calls.request(t.owner, bad),
      ZodError,
      JSON.stringify(bad)?.slice(0, 60),
    );
  const r = await calls.request(t.owner, {
    services: ["booking", "rescheduling", "enquiry", "cancellation"],
    note: "  ".padEnd(5, " ") + "n".repeat(2000),
  });
  assert.equal(r.status, "requested");
  assert.equal(r.requested_services.length, 4);
});

test("agent calls request: only the owner may request, duplicates conflict and rejected requests can be resubmitted", async () => {
  const t = await tenant();
  const staff = await staffOf(t, [
    "view_bookings",
    "manage_bookings",
    "view_finance",
  ]);
  await assert.rejects(
    () => calls.request(staff, { services: ["booking"] }),
    ForbiddenException,
  );
  await assert.rejects(
    () => calls.request(actor(), { services: ["booking"] }),
    ForbiddenException,
  );
  await calls.request(t.owner, { services: ["booking"], note: "a" });
  await assert.rejects(
    () => calls.request(t.owner, { services: ["enquiry"] }),
    ConflictException,
  );
  await db.query(
    "UPDATE agent_call_requests SET status='rejected' WHERE organization_id=$1",
    [t.org],
  );
  const again = await calls.request(t.owner, {
    services: ["enquiry"],
    note: "again",
  });
  assert.equal(again.status, "requested");
  assert.deepEqual(again.requested_services, ["enquiry"]);
  assert.deepEqual(
    again.approved_services,
    [],
    "re-request clears earlier approvals",
  );
  assert.equal(
    (
      await db.query(
        "SELECT 1 FROM agent_call_requests WHERE organization_id=$1",
        [t.org],
      )
    ).rows.length,
    1,
  );
});

test("agent calls: status, toggles and history are owner-only and tenant-scoped", async () => {
  const a = await tenant(),
    b = await tenant();
  const staff = await staffOf(a, ["view_bookings"]);
  const k = await connected(a);
  for (const call of [
    () => calls.status(staff),
    () => calls.setEnabled(staff, { enabled: false, version: 1 }),
    () => calls.setSpaces(staff, { resource_ids: [], version: 1 }),
    () => calls.calls(staff, day),
    () => calls.transcript(staff, "x"),
    () => calls.recording(staff, "x"),
  ])
    await assert.rejects(call, ForbiddenException);
  const other = await calls.status(b.owner);
  assert.equal(other.status, "none");
  assert.equal(other.phone_number, "");
  assert.equal(
    JSON.stringify(await calls.status(a.owner)).includes(k.key),
    false,
    "status never reveals the tool key",
  );
  assert.equal(
    JSON.stringify(await calls.status(a.owner)).includes("secret"),
    false,
  );
});

// ------------------------------------------------------------ toggles/spaces

test("agent calls toggles: payload boundaries", async () => {
  const t = await tenant();
  await connected(t);
  for (const bad of [
    null,
    {},
    { enabled: true },
    { version: 1 },
    { enabled: "true", version: 1 },
    { enabled: 1, version: 1 },
    { enabled: true, version: 0 },
    { enabled: true, version: -1 },
    { enabled: true, version: 1.5 },
    { enabled: true, version: "1" },
    { enabled: true, version: 1, extra: 1 },
  ])
    await assert.rejects(
      () => calls.setEnabled(t.owner, bad),
      ZodError,
      JSON.stringify(bad),
    );
  for (const bad of [
    null,
    {},
    { resource_ids: [] },
    { version: 1 },
    { resource_ids: ["x"], version: 1 },
    { resource_ids: [null], version: 1 },
    { resource_ids: "a", version: 1 },
    { resource_ids: [], version: 0 },
    { resource_ids: [], version: 1, extra: 1 },
    {
      resource_ids: Array.from({ length: 1001 }, () => randomUUID()),
      version: 1,
    },
  ])
    await assert.rejects(
      () => calls.setSpaces(t.owner, bad),
      ZodError,
      JSON.stringify(bad)?.slice(0, 50),
    );
});

test("agent calls toggles: not-ready, stale versions and foreign spaces are refused without side effects", async () => {
  const a = await tenant(),
    b = await tenant();
  await assert.rejects(
    () => calls.setEnabled(a.owner, { enabled: true, version: 1 }),
    /not ready/,
  );
  await assert.rejects(
    () => calls.setSpaces(a.owner, { resource_ids: [], version: 1 }),
    /not ready/,
  );
  const k = await connected(a, { verified: false });
  await assert.rejects(
    () => calls.setEnabled(a.owner, { enabled: true, version: 99 }),
    /changed|not ready/,
  );
  await assert.rejects(
    () => calls.setSpaces(a.owner, { resource_ids: [], version: 1 }),
    /not ready/,
    "unverified connection",
  );
  const v = await connected(b);
  const biz = await workspace.createBusiness(b.owner, {
    name: "Voice Turf",
    type: "turf",
    location_id: (await workspace.workspace(b.owner)).locations[0].id,
  });
  const res = await workspace.addResource(b.owner, biz.id, { name: "Pitch" });
  const version = (
    await db.query<{ version: number }>(
      "SELECT version FROM sarvam_integrations WHERE organization_id=$1",
      [b.org],
    )
  ).rows[0].version;
  await assert.rejects(
    () => calls.setSpaces(b.owner, { resource_ids: [res.id], version }),
    /ready spaces/,
    "draft business spaces are not offered",
  );
  await assert.rejects(
    () => calls.setSpaces(b.owner, { resource_ids: [randomUUID()], version }),
    /ready spaces/,
  );
  const aVersion = (
    await db.query<{ version: number }>(
      "SELECT version FROM sarvam_integrations WHERE organization_id=$1",
      [a.org],
    )
  ).rows[0].version;
  await assert.rejects(
    () =>
      calls.setSpaces(a.owner, { resource_ids: [res.id], version: aVersion }),
    /not ready|ready spaces/,
    "another tenant's resource",
  );
  assert.ok(k.key && v.key);
});

// ---------------------------------------------------------------- call history

test("call history query: ISO timestamps with offsets, ordered, at most 31 days", async () => {
  const t = await tenant();
  await connected(t);
  const bad = (q: unknown) =>
    assert.rejects(
      () => calls.calls(t.owner, q),
      ZodError,
      JSON.stringify(q)?.slice(0, 80),
    );
  for (const q of [
    null,
    undefined,
    {},
    { start: day.start },
    { end: day.end },
    { ...day, extra: 1 },
    { start: "2026-10-01", end: "2026-10-02" },
    { start: "2026-10-01T00:00:00", end: "2026-10-02T00:00:00" },
    { start: "yesterday", end: "today" },
    { start: "", end: "" },
    { start: 1, end: 2 },
    { start: null, end: null },
    { start: day.end, end: day.start },
    { start: day.start, end: day.start },
    { start: "2026-10-01T00:00:00Z", end: "2026-11-01T00:00:00.001Z" },
    { start: "2026-13-01T00:00:00Z", end: "2026-13-02T00:00:00Z" },
    { start: "2026-10-01T25:00:00Z", end: "2026-10-02T00:00:00Z" },
    { ...day, offset: -1 },
    { ...day, offset: 1.5 },
    { ...day, offset: "abc" },
    { ...day, offset: 100001 },
    { ...day, offset: "1e9" },
    { ...day, offset: NaN },
    { ...day, offset: Infinity },
  ])
    await bad(q);
  for (const q of [
    day,
    { start: "2026-10-01T00:00:00+05:30", end: "2026-10-02T00:00:00+05:30" },
    { start: "2026-10-01T00:00:00Z", end: "2026-11-01T00:00:00Z" },
    { ...day, offset: 0 },
    { ...day, offset: "5" },
    { ...day, offset: 100000 },
    { start: "2026-10-01T00:00:00.123Z", end: "2026-10-01T00:00:00.124Z" },
  ]) {
    const r = await calls.calls(t.owner, q);
    assert.ok(Array.isArray(r.items), JSON.stringify(q));
  }
});

test("call history query: the owner view falls back to saved calls with a warning when the provider fails, and only shows this tenant's logs", async () => {
  const a = await tenant(),
    b = await tenant();
  const ka = await connected(a),
    kb = await connected(b);
  provider.http = (async () => new Response("{}", { status: 500 })) as never;
  try {
    const va = voiceActor(a.org),
      vb = voiceActor(b.org);
    await calls.recordEvent(va, {
      interaction_id: "call-a-1",
      duration_seconds: 5,
      caller_name: "Anita",
    });
    await calls.recordEvent(vb, {
      interaction_id: "call-b-1",
      duration_seconds: 5,
      caller_name: "Bala",
    });
    const r = await calls.calls(a.owner, {
      start: new Date(Date.now() - 3600_000).toISOString(),
      end: new Date(Date.now() + 3600_000).toISOString(),
    });
    assert.match(r.warning, /Showing saved calls/);
    assert.deepEqual(
      r.items.map((i: any) => i.interaction_id),
      ["call-a-1"],
    );
  } finally {
    provider.http = (...x) => fetch(...x);
  }
  assert.ok(ka.key && kb.key);
});

test("transcript and recording ids: type, length and ownership are checked before the provider is called", async () => {
  const a = await tenant(),
    b = await tenant();
  await connected(a);
  await connected(b);
  let providerCalls = 0;
  provider.http = (async () => (
    providerCalls++,
    new Response("{}", { status: 200 })
  )) as never;
  try {
    await calls.recordEvent(voiceActor(b.org), {
      interaction_id: "secret-call",
      duration_seconds: 1,
    });
    for (const bad of [undefined, null, 5, ["x"], {}, "x".repeat(201), true]) {
      await assert.rejects(
        () => calls.transcript(a.owner, bad),
        BadRequestException,
        JSON.stringify(bad)?.slice(0, 20),
      );
      await assert.rejects(
        () => calls.recording(a.owner, bad),
        BadRequestException,
      );
    }
    for (const id of [
      "",
      "unknown",
      "secret-call",
      "../secret-call",
      "secret-call/",
      "x/y",
    ]) {
      const e = await fails(calls.transcript(a.owner, id));
      assert.ok(
        e instanceof NotFoundException,
        `${JSON.stringify(id)} -> ${e?.constructor?.name}`,
      );
      assert.ok(
        (await fails(calls.recording(a.owner, id))) instanceof
          NotFoundException,
      );
    }
    assert.equal(
      providerCalls,
      0,
      "provider is never contacted for unknown or foreign calls",
    );
  } finally {
    provider.http = (...x) => fetch(...x);
  }
});

test(
  "transcript and recording ids that are dot segments must not alter the provider URL path",
  { todo: "BUG-20" },
  async () => {
    const t = await tenant();
    await connected(t);
    const urls: string[] = [];
    provider.http = (async (u: URL) => (
      urls.push(new URL(u).pathname),
      new Response(JSON.stringify({ messages: [] }), { status: 200 })
    )) as never;
    try {
      for (const id of [".", "a/."]) {
        urls.length = 0;
        await provider.transcript(t.owner, id).catch(() => undefined);
        const last = urls.at(-1) ?? "";
        assert.ok(
          last.endsWith(`/transcripts/${id}`),
          `interaction id ${JSON.stringify(id)} requested ${last}`,
        );
      }
    } finally {
      provider.http = (...x) => fetch(...x);
    }
  },
);

// -------------------------------------------------------------- call-event tool

const eventOk = {
  interaction_id: "int-1",
  caller_phone: "+919876543210",
  duration_seconds: 30,
  transcript: "hello",
  summary: "ok",
  caller_name: "Anu",
  disposition: "booked",
};

test("call-event payload: field boundaries", async () => {
  const t = await tenant();
  await connected(t);
  const v = voiceActor(t.org);
  const bad = (patch: Record<string, unknown>) =>
    calls.recordEvent(v, { ...eventOk, ...patch });
  const cases: Array<[string, unknown[]]> = [
    [
      "interaction_id",
      [
        "",
        " ",
        "a b",
        "a\nb",
        "../x",
        "a..b",
        "a/b/c",
        "/a",
        "a/",
        "ü",
        "x".repeat(201),
        null,
        5,
        ["a"],
        "a;b",
        "a%2e",
      ],
    ],
    ["caller_phone", ["x".repeat(41), 5, ["1"], {}]],
    ["duration_seconds", [-1, 7201, "abc", NaN, Infinity, "-1", {}]],
    ["transcript", ["x".repeat(200001), 5, {}]],
    ["summary", ["x".repeat(4001), 5]],
    ["caller_name", ["x".repeat(101), 5]],
    ["disposition", ["x".repeat(201), 5]],
  ];
  for (const [field, values] of cases)
    for (const x of values)
      await assert.rejects(
        () => bad({ [field]: x }),
        ZodError,
        `${field}=${JSON.stringify(x)?.slice(0, 20)}`,
      );
  for (const patch of [
    { extra: 1 },
    { organization_id: randomUUID() },
    { started_at: "2020-01-01T00:00:00Z" },
  ])
    await assert.rejects(() => bad(patch), ZodError);
  for (const input of [null, undefined, "x", 5, []])
    await assert.rejects(() => calls.recordEvent(v, input), ZodError);
  for (const id of [
    "a",
    "a.b-c_d:e",
    "a/b",
    "x".repeat(200),
    "UPPER/lower",
    "1/2",
  ])
    assert.deepEqual(await bad({ interaction_id: id }), { ok: true }, id);
  for (const d of [0, 7200, 0.5, "12", "1e3"])
    assert.deepEqual(
      await bad({ interaction_id: `d-${d}`, duration_seconds: d }),
      { ok: true },
      String(d),
    );
  assert.deepEqual(
    await bad({
      interaction_id: "big",
      transcript: "x".repeat(200000),
      summary: "s".repeat(4000),
      caller_name: "n".repeat(100),
      disposition: "d".repeat(200),
      caller_phone: "1".repeat(40),
    }),
    { ok: true },
  );
  const min = await calls.recordEvent(v, {
    interaction_id: "minimal",
    duration_seconds: 1,
  });
  assert.deepEqual(min, { ok: true });
});

test(
  "call-event payload: wrong-typed durations are rejected rather than coerced",
  { todo: "BUG-21" },
  async () => {
    const t = await tenant();
    await connected(t);
    const v = voiceActor(t.org);
    for (const duration_seconds of [null, "", [], true, " ", [5]]) {
      const e = await fails(
        calls.recordEvent(v, {
          ...eventOk,
          interaction_id: "coerce",
          duration_seconds,
        }),
      );
      assert.ok(
        e instanceof ZodError,
        `duration_seconds=${JSON.stringify(duration_seconds)} was accepted`,
      );
    }
  },
);

test("call-event: only a voice actor of a connected organization may record, and one tenant cannot overwrite another's call", async () => {
  const a = await tenant(),
    b = await tenant();
  await connected(a);
  await connected(b);
  await assert.rejects(
    () => calls.recordEvent(a.owner, eventOk),
    /call service key/,
  );
  await assert.rejects(
    () =>
      calls.recordEvent(
        { uid: "sarvam:" + randomUUID(), email: "v@sarvam.invalid", name: "v" },
        eventOk,
      ),
    NotFoundException,
  );
  await assert.rejects(() =>
    calls.recordEvent(
      { uid: "sarvam:not-a-uuid", email: "v@sarvam.invalid", name: "v" },
      eventOk,
    ),
  );
  await calls.recordEvent(voiceActor(a.org), {
    ...eventOk,
    interaction_id: "shared-id",
    summary: "A summary",
  });
  await calls.recordEvent(voiceActor(b.org), {
    ...eventOk,
    interaction_id: "shared-id",
    summary: "B summary",
  });
  const rows = (
    await db.query<{ organization_id: string; data: any }>(
      "SELECT organization_id,data FROM agent_call_logs WHERE interaction_id='shared-id'",
    )
  ).rows;
  assert.equal(rows.length, 2);
  assert.equal(
    rows.find((r) => r.organization_id === a.org)!.data.summary,
    "A summary",
  );
  assert.equal(
    rows.find((r) => r.organization_id === b.org)!.data.summary,
    "B summary",
  );
  await calls.recordEvent(voiceActor(a.org), {
    ...eventOk,
    interaction_id: "shared-id",
    summary: "A updated",
  });
  assert.equal(
    (
      await db.query<{ data: any }>(
        "SELECT data FROM agent_call_logs WHERE organization_id=$1 AND interaction_id='shared-id'",
        [a.org],
      )
    ).rows[0].data.summary,
    "A updated",
  );
});

// ------------------------------------------------------------- tool key auth

test("tool key: only a well-formed, known, enabled and approved key authenticates", async () => {
  const t = await tenant();
  const { key } = await connected(t);
  for (const bad of [
    null,
    "",
    " ",
    key.slice(0, -1),
    key + "a",
    key.toUpperCase(),
    key.replace("bkv_", "bkx_"),
    ` ${key}`,
    `${key}\n`,
    "bkv_" + "!".repeat(43),
    "bkv_" + "é".repeat(43),
    "' OR 1=1 --",
    "Bearer " + key,
  ])
    await assert.rejects(
      () => provider.authenticateToolKey(bad),
      UnauthorizedException,
      JSON.stringify(bad)?.slice(0, 30),
    );
  await assert.rejects(
    () => provider.authenticateToolKey(newKey()),
    UnauthorizedException,
    "well-formed but unknown",
  );
  const a = await provider.authenticateToolKey(key);
  assert.equal(a.uid, `sarvam:${t.org}`);
  assert.equal(a.email, "voice-agent@sarvam.invalid");
});

test("tool key: disabled, unverified, unapproved or paused integrations are 403 but still allowed to record call events", async () => {
  const cases: Array<[string, Parameters<typeof connected>[1]]> = [
    ["disabled", { enabled: false }],
    ["unverified", { verified: false }],
    ["paused", { status: "paused" }],
    ["requested", { status: "requested" }],
    ["rejected", { status: "rejected" }],
  ];
  for (const [label, opts] of cases) {
    const t = await tenant();
    const { key } = await connected(t, opts);
    const e = await fails(provider.authenticateToolKey(key));
    assert.ok(
      e instanceof HttpException && e.getStatus() === 403,
      `${label} gave ${e?.constructor?.name}`,
    );
    const ev = await provider.authenticateToolKey(key, true);
    assert.equal(
      ev.uid,
      `sarvam:${t.org}`,
      `${label}: call events keep working so history is complete`,
    );
  }
});

test("tool key: a rotated-away key stops working and an approved-services list gates each service", async () => {
  const t = await tenant();
  const { key } = await connected(t, { services: ["enquiry"] });
  const actorFor = await provider.authenticateToolKey(key);
  await assert.rejects(
    () => voiceAccess(db, actorFor, ["booking"]),
    /not enabled for phone calls/,
  );
  assert.deepEqual(await voiceAccess(db, actorFor, ["enquiry"]), ["enquiry"]);
  await assert.rejects(
    () => voiceAccess(db, actorFor, ["booking", "cancellation"]),
    ForbiddenException,
  );
  assert.deepEqual(
    await voiceAccess(db, actorFor, ["booking", "enquiry"]),
    ["enquiry"],
    "any approved service suffices",
  );
  await db.query(
    "UPDATE sarvam_integrations SET tool_key_hash=$2 WHERE organization_id=$1",
    [t.org, hashToolKey(newKey())],
  );
  await assert.rejects(
    () => provider.authenticateToolKey(key),
    UnauthorizedException,
  );
  assert.deepEqual(
    await voiceAccess(db, actor(), ["booking"]),
    [],
    "ordinary users bypass the voice policy",
  );
});

test("voice results: validation and client errors become speakable refusals, server errors propagate", async () => {
  const zod = await fails(
    Promise.resolve().then(() => {
      throw new ZodError([
        { code: "custom", path: ["date"], message: "x" },
        { code: "custom", path: ["space", "id"], message: "y" },
      ]);
    }),
  );
  assert.deepEqual(
    await voiceResult(async () => {
      throw zod;
    }),
    { ok: false, message: "Some details are missing: date, space.id." },
  );
  assert.deepEqual(
    await voiceResult(async () => {
      throw new ForbiddenException("Off");
    }),
    { ok: false, message: "Off" },
  );
  assert.deepEqual(
    await voiceResult(async () => {
      throw new NotFoundException("Gone");
    }),
    { ok: false, message: "Gone" },
  );
  await assert.rejects(
    () =>
      voiceResult(async () => {
        throw new HttpException("Down", 503);
      }),
    HttpException,
  );
  await assert.rejects(
    () =>
      voiceResult(async () => {
        throw new Error("boom");
      }),
    /boom/,
  );
  assert.deepEqual(await voiceResult(async () => ({ ok: true })), { ok: true });
});

// ------------------------------------------------------- owner sarvam settings

test("sarvam settings: payload boundaries", async () => {
  const t = await tenant();
  const ok = {
    version: 0,
    enabled: false,
    business_ids: [] as string[],
    sarvam_org_id: "",
    workspace_id: "",
    app_id: "",
    api_key: null as string | null,
  };
  const bad = (patch: Record<string, unknown>) =>
    provider.save(t.owner, { ...ok, ...patch });
  const cases: Array<[string, unknown[]]> = [
    ["version", [-1, 1.5, "0", null, undefined]],
    ["enabled", ["true", 1, null, undefined]],
    [
      "business_ids",
      [
        "x",
        [null],
        ["x"],
        [randomUUID(), "x"],
        Array.from({ length: 101 }, () => randomUUID()),
        null,
        undefined,
      ],
    ],
    ["sarvam_org_id", [" ", "a b", "a/b", "x".repeat(101), null, 5, undefined]],
    ["workspace_id", ["a b", "ü", "x".repeat(101), undefined]],
    ["app_id", ["a.b", "x".repeat(101), undefined]],
    ["api_key", ["short", "       ", "x".repeat(501), 5, ""]],
  ];
  for (const [field, values] of cases)
    for (const v of values)
      await assert.rejects(
        () => bad({ [field]: v }),
        ZodError,
        `${field}=${JSON.stringify(v)?.slice(0, 20)}`,
      );
  for (const patch of [
    { extra: 1 },
    { organization_id: randomUUID() },
    { tool_key_hash: "a".repeat(64) },
  ])
    await assert.rejects(() => bad(patch), ZodError);
  for (const input of [null, undefined, "x", 5, []])
    await assert.rejects(() => provider.save(t.owner, input), ZodError);
});

test("sarvam settings: owner-only, enabling needs a business and a tool key, and foreign businesses are refused", async () => {
  const a = await tenant(),
    b = await tenant();
  const staff = await staffOf(a, ["view_bookings", "manage_bookings"]);
  const base = {
    version: 0,
    enabled: false,
    business_ids: [] as string[],
    sarvam_org_id: "",
    workspace_id: "",
    app_id: "",
  };
  await assert.rejects(() => provider.save(staff, base), ForbiddenException);
  await assert.rejects(() => provider.save(actor(), base), ForbiddenException);
  await assert.rejects(() => provider.rotateToolKey(staff), ForbiddenException);
  await assert.rejects(() => provider.settings(staff), ForbiddenException);
  await assert.rejects(
    () => provider.save(a.owner, { ...base, enabled: true }),
    /at least one business/,
  );
  const biz = await workspace.createBusiness(a.owner, {
    name: "Voice Court",
    type: "badminton",
    location_id: (await workspace.workspace(a.owner)).locations[0].id,
  });
  await assert.rejects(
    () =>
      provider.save(a.owner, {
        ...base,
        enabled: true,
        business_ids: [biz.id],
      }),
    /tool key/,
  );
  const foreign = await workspace.createBusiness(b.owner, {
    name: "Foreign Court",
    type: "badminton",
    location_id: (await workspace.workspace(b.owner)).locations[0].id,
  });
  await assert.rejects(
    () => provider.save(a.owner, { ...base, business_ids: [foreign.id] }),
    /businesses in your organization/,
  );
  await assert.rejects(
    () => provider.save(a.owner, { ...base, business_ids: [randomUUID()] }),
    /businesses in your organization/,
  );
  await assert.rejects(
    () => provider.save(a.owner, { ...base, version: 7 }),
    ConflictException,
  );
  const saved = await provider.save(a.owner, {
    ...base,
    business_ids: [biz.id, biz.id],
    api_key: "sk-super-secret-1234",
  });
  assert.equal(saved.api_key_last4, "1234");
  assert.equal(JSON.stringify(saved).includes("sk-super-secret"), false);
  assert.equal(
    saved.businesses.filter((x: any) => x.assigned).length,
    1,
    "duplicate business ids collapse",
  );
  const rotated = await provider.rotateToolKey(a.owner);
  assert.match(rotated.tool_key, /^bkv_[A-Za-z0-9_-]{43}$/);
  assert.equal(rotated.tool_key_prefix, rotated.tool_key.slice(0, 10));
  assert.equal(
    (await provider.settings(a.owner)).tool_key_prefix,
    rotated.tool_key.slice(0, 10),
  );
  assert.equal(
    JSON.stringify(await provider.settings(a.owner)).includes(rotated.tool_key),
    false,
    "the full key is shown once",
  );
});
