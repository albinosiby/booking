import "reflect-metadata";
import { test, afterEach } from "node:test";
import assert from "node:assert/strict";
import { createHash, createHmac, randomUUID } from "node:crypto";
import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  HttpException,
  NotFoundException,
  ServiceUnavailableException,
  UnauthorizedException,
} from "@nestjs/common";
import { z, ZodError } from "zod";
import { ErrorsFilter } from "../src/common/errors.filter";
import { AuthGuard } from "../src/common/auth.guard";
import {
  coalesceActorChecks,
  supabaseActor,
} from "../src/common/supabase-auth";
import { panelActor, isPanelActor } from "../src/admin/panel-auth";
import { AdminGuard } from "../src/admin/admin.guard";
import { notificationHandler } from "../edge/notifications-handler";

const SECRET = "test-only-panel-signing-secret-0123456789";
process.env.ADMIN_SESSION_SECRET = SECRET;
process.env.NODE_ENV = "test";
const saved = {
  provider: process.env.AUTH_PROVIDER,
  url: process.env.SUPABASE_URL,
  key: process.env.SUPABASE_PUBLISHABLE_KEY,
};
afterEach(() => {
  process.env.ADMIN_SESSION_SECRET = SECRET;
  for (const [k, v] of [
    ["AUTH_PROVIDER", saved.provider],
    ["SUPABASE_URL", saved.url],
    ["SUPABASE_PUBLISHABLE_KEY", saved.key],
  ] as const)
    v === undefined ? delete process.env[k] : (process.env[k] = v);
});

// -------------------------------------------------------------- supabaseActor

const cfg = {
  url: "https://project.supabase.co",
  key: "sb_publishable_abcdefghijklmnop",
};
const users = (rows: unknown[] = []) => {
  const queries: string[] = [];
  return {
    queries,
    db: {
      query: async (sql: string) => (queries.push(sql), { rows }),
    } as never,
  };
};
const reply =
  (status: number, body: unknown, raw = false) =>
  async () =>
    new Response(raw ? (body as string) : JSON.stringify(body), {
      status,
      headers: { "content-type": "application/json" },
    });
const goodUser = {
  id: "u-1",
  email: "Owner@Example.com",
  email_confirmed_at: "2026-01-01T00:00:00Z",
};
const verify = (request: typeof fetch, c = cfg, token = "tok") =>
  supabaseActor(token, users().db, request, c);
const code = (e: unknown) => (e as HttpException)?.getStatus?.();
const fails = async (p: Promise<unknown>) =>
  p.then(
    () => null,
    (e) => e,
  );

test("supabase auth: configuration must be https URL and a publishable key", async () => {
  for (const c of [
    { url: undefined, key: cfg.key },
    { url: "", key: cfg.key },
    { url: "http://project.supabase.co", key: cfg.key },
    { url: "ftp://project.supabase.co", key: cfg.key },
    { url: " https://project.supabase.co", key: cfg.key },
    { url: cfg.url, key: undefined },
    { url: cfg.url, key: "" },
    { url: cfg.url, key: "sb_secret_abcdefghijklmnop" },
    { url: cfg.url, key: "eyJhbGciOiJIUzI1NiJ9.service_role" },
    { url: cfg.url, key: " sb_publishable_abc" },
  ]) {
    let called = false;
    const e = await fails(
      verify(
        (async () => ((called = true), new Response("{}"))) as never,
        c as never,
      ),
    );
    assert.ok(e instanceof ServiceUnavailableException, JSON.stringify(c));
    assert.equal(called, false, "no network call with invalid configuration");
  }
});

test("supabase auth: trailing slash in the project URL is normalised and the token is sent only as a bearer header", async () => {
  let seen: { url: string; init: RequestInit } | undefined;
  const actor = await verify(
    (async (url: string, init: RequestInit) => (
      (seen = { url, init }),
      new Response(JSON.stringify(goodUser))
    )) as never,
    { ...cfg, url: `${cfg.url}/` },
    "abc.def.ghi",
  );
  assert.equal(seen!.url, "https://project.supabase.co/auth/v1/user");
  assert.equal(
    (seen!.init.headers as Record<string, string>).Authorization,
    "Bearer abc.def.ghi",
  );
  assert.equal(actor.email, "owner@example.com", "email is lower-cased");
});

test("supabase auth: provider status codes map to 401 or 503", async () => {
  for (const s of [400, 401, 403, 404, 422])
    assert.equal(
      code(await fails(verify(reply(s, {}) as never))),
      401,
      `status ${s}`,
    );
  for (const s of [429, 500, 502, 503, 504])
    assert.equal(
      code(await fails(verify(reply(s, {}) as never))),
      503,
      `status ${s}`,
    );
});

test("supabase auth: network failure and timeout are retryable, never a credential error", async () => {
  for (const err of [
    new TypeError("fetch failed"),
    new DOMException("timeout", "TimeoutError"),
    new Error("ECONNRESET"),
  ])
    assert.equal(
      code(
        await fails(
          verify((async () => {
            throw err;
          }) as never),
        ),
      ),
      503,
    );
});

test("supabase auth: incomplete or unverified identities are refused", async () => {
  for (const user of [
    {},
    { ...goodUser, id: "" },
    { ...goodUser, id: undefined },
    { ...goodUser, email: "" },
    { ...goodUser, email: undefined },
    { ...goodUser, email_confirmed_at: null },
    { ...goodUser, email_confirmed_at: "" },
    { ...goodUser, email_confirmed_at: undefined },
    { ...goodUser, is_anonymous: true },
  ]) {
    const e = await fails(verify(reply(200, user) as never));
    assert.ok(e instanceof UnauthorizedException, JSON.stringify(user));
  }
});

test(
  "supabase auth: a successful 200 with a non-JSON or null body is a service failure, not an internal error",
  { todo: "BUG-10" },
  async () => {
    for (const body of ["<html>gateway</html>", "", "null", "[]"]) {
      const e = await fails(verify(reply(200, body, true) as never));
      assert.ok(
        e instanceof HttpException,
        `body ${JSON.stringify(body)} gave ${e?.constructor?.name}`,
      );
    }
  },
);

test(
  "supabase auth: client-controlled full_name must not become an empty, huge or control-character display name",
  { todo: "BUG-11" },
  async () => {
    for (const full_name of [
      "",
      "   ",
      "x".repeat(5000),
      "Line\nBreak",
      "nul\u0000byte",
      "\u200b",
    ]) {
      const actor = await verify(
        reply(200, { ...goodUser, user_metadata: { full_name } }) as never,
      );
      assert.ok(
        actor.name.trim().length > 0,
        `blank name for ${JSON.stringify(full_name).slice(0, 20)}`,
      );
      assert.ok(
        actor.name.length <= 120,
        "name length bounded by the organization schema",
      );
      assert.equal(
        /[\u0000-\u001f]/.test(actor.name),
        false,
        "no control characters",
      );
    }
  },
);

test("supabase auth: non-string full_name falls back to the email local part", async () => {
  for (const full_name of [null, 5, {}, [], true, undefined]) {
    const actor = await verify(
      reply(200, { ...goodUser, user_metadata: { full_name } }) as never,
    );
    assert.equal(actor.name, "owner");
  }
  assert.equal(
    (await verify(reply(200, { ...goodUser, user_metadata: null }) as never))
      .name,
    "owner",
  );
});

test("supabase auth: metadata can never choose the actor id or select a legacy identity", async () => {
  const user = {
    ...goodUser,
    id: "real-subject",
    user_metadata: {
      full_name: "x",
      uid: "legacy",
      actor_id: "legacy",
      sub: "legacy",
    },
    app_metadata: { uid: "legacy" },
  };
  const { db } = users();
  assert.equal(
    (await supabaseActor("t", db, reply(200, user) as never, cfg)).uid,
    "real-subject",
  );
});

test("supabase auth: identity lookup failure surfaces rather than silently using the subject", async () => {
  const db = {
    query: async () => {
      throw new Error("db down");
    },
  } as never;
  await assert.rejects(
    () => supabaseActor("t", db, reply(200, goodUser) as never, cfg),
    /db down/,
  );
});

test("supabase auth: identity lookup is parameterised (SQL metacharacters in email/subject stay data)", async () => {
  const seen: unknown[][] = [];
  const db = {
    query: async (_s: string, v: unknown[]) => (seen.push(v), { rows: [] }),
  } as never;
  await supabaseActor(
    "t",
    db,
    reply(200, {
      id: "x'; DROP TABLE memberships;--",
      email: "o'brien@example.com",
      email_confirmed_at: "2026-01-01",
    }) as never,
    cfg,
  );
  assert.deepEqual(seen[0], [
    "x'; DROP TABLE memberships;--",
    "o'brien@example.com",
  ]);
});

test("coalesced actor checks: copies are isolated, failures propagate and are not cached", async () => {
  let calls = 0;
  const check = coalesceActorChecks(async (token) => {
    calls++;
    await new Promise((r) => setTimeout(r, 5));
    if (token === "bad") throw new UnauthorizedException("no");
    return { uid: token, email: `${token}@x.com`, name: token };
  });
  const [a, b] = await Promise.all([check("same"), check("same")]);
  assert.equal(calls, 1);
  a.name = "mutated";
  assert.equal(b.name, "same", "callers get independent copies");
  await assert.rejects(() => check("bad"), UnauthorizedException);
  await assert.rejects(() => check("bad"), UnauthorizedException);
  assert.equal(calls, 3, "a failed verification is retried, never cached");
  assert.equal((await check("same")).uid, "same");
  assert.equal(calls, 4, "successful verification is not retained either");
});

test("coalesced actor checks: more than 128 distinct in-flight tokens still verify every token", async () => {
  const check = coalesceActorChecks(async (token) => {
    await new Promise((r) => setTimeout(r, 2));
    return { uid: token, email: "e@x.com", name: token };
  });
  const tokens = Array.from({ length: 300 }, (_, i) => `t${i}`);
  const out = await Promise.all(tokens.map(check));
  assert.deepEqual(
    out.map((a) => a.uid),
    tokens,
  );
  assert.deepEqual(
    (await Promise.all([check(""), check(" ")])).map((a) => a.uid),
    ["", " "],
  );
});

// -------------------------------------------------------------------- AuthGuard

const context = (headers: Record<string, unknown>) => {
  const request: Record<string, unknown> = { headers };
  return {
    request,
    ctx: { switchToHttp: () => ({ getRequest: () => request }) } as never,
  };
};

test("auth guard: missing, malformed or non-bearer Authorization is 401 before any provider call", async () => {
  process.env.AUTH_PROVIDER = "supabase";
  delete process.env.SUPABASE_URL;
  const guard = new AuthGuard(undefined as never);
  for (const header of [
    undefined,
    null,
    "",
    " ",
    "Bearer",
    "Bearertoken",
    "Basic abc",
    "Token abc",
    "bearer abc",
    ["Bearer abc"],
    5,
    {},
  ]) {
    const { ctx } = context({ authorization: header });
    const e = await fails(Promise.resolve(guard.canActivate(ctx)));
    assert.ok(
      e instanceof UnauthorizedException,
      `header ${JSON.stringify(header)} gave ${e?.constructor?.name}`,
    );
  }
});

test("auth guard: a well-formed bearer with unconfigured Supabase is a 503 configuration error", async () => {
  process.env.AUTH_PROVIDER = "supabase";
  delete process.env.SUPABASE_URL;
  delete process.env.SUPABASE_PUBLISHABLE_KEY;
  const guard = new AuthGuard(users().db);
  for (const header of [
    "Bearer abc",
    "Bearer ",
    "Bearer    ",
    `Bearer ${"x".repeat(10000)}`,
  ]) {
    const { ctx } = context({ authorization: header });
    const e = await fails(Promise.resolve(guard.canActivate(ctx)));
    assert.ok(
      e instanceof ServiceUnavailableException,
      `${header.slice(0, 20)} gave ${e?.constructor?.name}`,
    );
  }
});

// ------------------------------------------------------------------ ErrorsFilter

function run(error: unknown) {
  let out: { status: number; body: any } | undefined;
  const res = {
    status: (s: number) => ({
      json: (b: unknown) => (out = { status: s, body: b }),
    }),
  };
  new ErrorsFilter().catch(error, {
    switchToHttp: () => ({ getResponse: () => res }),
  } as never);
  return out!;
}

test("errors filter: zod errors are 422 with field paths and never include submitted values", () => {
  const e = (() => {
    try {
      z.object({
        name: z.string().min(50),
        n: z.array(z.object({ x: z.number() })),
      }).parse({ name: "secret-short", n: [{ x: "bad" }] });
    } catch (x) {
      return x;
    }
  })();
  const r = run(e);
  assert.equal(r.status, 422);
  assert.equal(r.body.code, "VALIDATION_ERROR");
  assert.match(r.body.message, /name:/);
  assert.match(r.body.message, /n\.0\.x:/);
  assert.equal(r.body.message.includes("secret-short"), false);
  assert.match(r.body.request_id, /^[0-9a-f-]{36}$/);
  assert.equal(run(new ZodError([])).status, 422);
});

test("errors filter: http exception statuses keep their code mapping", () => {
  const cases: Array<[HttpException, number, string]> = [
    [new BadRequestException("bad"), 400, "REQUEST_ERROR"],
    [new UnauthorizedException("no"), 401, "UNAUTHENTICATED"],
    [new ForbiddenException("no"), 403, "FORBIDDEN"],
    [new NotFoundException("no"), 404, "REQUEST_ERROR"],
    [new ConflictException("dup"), 409, "CONFLICT"],
    [new HttpException("big", 413), 413, "REQUEST_ERROR"],
    [new HttpException("slow down", 429), 429, "REQUEST_ERROR"],
    [new ServiceUnavailableException("later"), 503, "REQUEST_ERROR"],
  ];
  for (const [e, status, code] of cases) {
    const r = run(e);
    assert.equal(r.status, status);
    assert.equal(r.body.code, code);
    assert.equal(r.body.message, e.message);
  }
});

test("errors filter: unknown failures are a generic 500 that leaks neither message nor stack", () => {
  const secret = "password=hunter2 at /srv/app/db.ts:12";
  for (const e of [
    new Error(secret),
    new TypeError(secret),
    secret,
    null,
    undefined,
    5,
    {},
    { message: secret },
    Object.assign(new Error(secret), { stack: secret }),
  ]) {
    const r = run(e);
    assert.equal(r.status, 500);
    assert.equal(r.body.code, "INTERNAL_ERROR");
    assert.equal(JSON.stringify(r.body).includes("hunter2"), false);
    assert.equal(JSON.stringify(r.body).includes("/srv/app"), false);
  }
});

test("errors filter: unique-violation becomes a 409 without echoing the constraint", () => {
  const r = run(
    Object.assign(
      new Error(
        'duplicate key value violates unique constraint "businesses_organization_id_name_key"',
      ),
      { code: "23505" },
    ),
  );
  assert.equal(r.status, 409);
  assert.equal(r.body.code, "CONFLICT");
  assert.equal(r.body.message.includes("businesses_"), false);
});

test("errors filter: every response has a distinct request id", () => {
  const ids = new Set(
    Array.from({ length: 50 }, () => run(new Error("x")).body.request_id),
  );
  assert.equal(ids.size, 50);
});

test(
  "errors filter: client-caused database errors (bad uuid, NUL byte, check/length violations) are 4xx, not 500",
  { todo: "BUG-12" },
  () => {
    for (const code of ["22P02", "22021", "22001", "23514", "23502", "22003"]) {
      const r = run(Object.assign(new Error("db"), { code }));
      assert.ok(
        r.status >= 400 && r.status < 500,
        `pg ${code} gave ${r.status}`,
      );
    }
  },
);

// -------------------------------------------------------------------- panel auth

const sign = (
  opts: {
    ts?: number | string;
    nonce?: string;
    method?: string;
    path?: string;
    body?: string;
    secret?: string;
    mac?: string;
  } = {},
) => {
  const ts = String(opts.ts ?? Date.now());
  const nonce = opts.nonce ?? randomUUID();
  const digest = createHash("sha256")
    .update(opts.body ?? "")
    .digest("hex");
  const mac =
    opts.mac ??
    createHmac("sha256", opts.secret ?? SECRET)
      .update(
        [
          "booking-admin-v1",
          ts,
          nonce,
          opts.method ?? "GET",
          opts.path ?? "/v1/admin/me",
          digest,
        ].join("\n"),
      )
      .digest("hex");
  return `${ts}.${nonce}.${mac}`;
};
const panel = (
  proof: string | undefined | null,
  method = "GET",
  path = "/v1/admin/me",
  body?: unknown,
) => panelActor(proof, method, path, body);

test("panel proof: shape boundaries are rejected before any HMAC comparison", () => {
  const good = sign();
  assert.ok(isPanelActor(panel(good)));
  const [ts, nonce, mac] = good.split(".");
  for (const bad of [
    "",
    " ",
    null,
    undefined,
    good + " ",
    ` ${good}`,
    `${good}\n`,
    good.toUpperCase(),
    `${ts.slice(1)}.${nonce}.${mac}`,
    `${ts}0.${nonce}.${mac}`,
    `${"a".repeat(13)}.${nonce}.${mac}`,
    `${ts}.${nonce.slice(1)}.${mac}`,
    `${ts}.${nonce}0.${mac}`,
    `${ts}.${nonce}.${mac.slice(1)}`,
    `${ts}.${nonce}.${mac}0`,
    `${ts}.${nonce}.${mac.toUpperCase()}`,
    `${ts}.${nonce}.${"g".repeat(64)}`,
    `${ts}.${nonce}`,
    `${ts}..${mac}`,
    `${ts}.${nonce}.${mac}.${mac}`,
    "a.b.c",
    "Bearer " + good,
  ])
    assert.throws(
      () => panel(bad as never),
      /invalid or expired/,
      JSON.stringify(bad)?.slice(0, 40),
    );
});

test("panel proof: freshness window is symmetric and exactly 60 seconds", () => {
  const now = Date.now();
  for (const [skew, ok] of [
    [0, true],
    [-30_000, true],
    [-59_000, true],
    [30_000, true],
    [59_000, true],
    [-61_000, false],
    [61_000, false],
    [-3_600_000, false],
    [3_600_000, false],
    [-86_400_000 * 365, false],
    [86_400_000 * 365, false],
  ] as const)
    if (ok) assert.ok(panel(sign({ ts: now + skew })), `skew ${skew}`);
    else
      assert.throws(
        () => panel(sign({ ts: now + skew })),
        /invalid or expired/,
        `skew ${skew}`,
      );
});

test("panel proof: the signature covers method, exact path and query, and body bytes", () => {
  const body = { active: false, note: "é" };
  const proof = sign({
    method: "PUT",
    path: "/v1/admin/users/x/active?limit=5",
    body: JSON.stringify(body),
  });
  assert.ok(panel(proof, "PUT", "/v1/admin/users/x/active?limit=5", body));
  for (const [m, p, b] of [
    ["put", "/v1/admin/users/x/active?limit=5", body],
    ["PUT", "/v1/admin/users/x/active", body],
    ["PUT", "/v1/admin/users/x/active?limit=6", body],
    ["PUT", "/v1/admin/users/x/active?limit=5&", body],
    ["PUT", "/v1/admin/users/y/active?limit=5", body],
    ["PUT", "/V1/admin/users/x/active?limit=5", body],
    ["PUT", "/v1/admin/users/x/active?limit=5", { ...body, active: true }],
    ["PUT", "/v1/admin/users/x/active?limit=5", { ...body, extra: 1 }],
    ["PUT", "/v1/admin/users/x/active?limit=5", { note: "é", active: false }],
    ["PUT", "/v1/admin/users/x/active?limit=5", undefined],
    ["PUT", "/v1/admin/users/x/active?limit=5", null],
  ] as const)
    assert.throws(
      () => panel(proof, m, p, b),
      /invalid or expired/,
      `${m} ${p} ${JSON.stringify(b)}`,
    );
  const empty = sign({ path: "/v1/admin/overview" });
  assert.ok(panel(empty, "GET", "/v1/admin/overview", undefined));
  assert.throws(
    () => panel(empty, "GET", "/v1/admin/overview", {}),
    /invalid or expired/,
    "{} is not an empty body",
  );
});

test("panel proof: signing secret must be configured and at least 32 characters", () => {
  const proof = sign();
  for (const secret of [undefined, "", "x".repeat(31)]) {
    secret === undefined
      ? delete process.env.ADMIN_SESSION_SECRET
      : (process.env.ADMIN_SESSION_SECRET = secret);
    assert.throws(() => panel(proof), /not configured/, String(secret?.length));
  }
  process.env.ADMIN_SESSION_SECRET = "x".repeat(32);
  assert.throws(
    () => panel(proof),
    /invalid or expired/,
    "valid length but a different secret",
  );
  assert.ok(panel(sign({ secret: "x".repeat(32) })));
});

test("panel proof: a proof signed with the wrong secret, a forged mac or a swapped nonce is refused", () => {
  assert.throws(
    () => panel(sign({ secret: "y".repeat(40) })),
    /invalid or expired/,
  );
  assert.throws(
    () => panel(sign({ mac: "0".repeat(64) })),
    /invalid or expired/,
  );
  const [ts, , mac] = sign().split(".");
  assert.throws(
    () => panel(`${ts}.${randomUUID()}.${mac}`),
    /invalid or expired/,
  );
});

test("panel proof: a captured proof cannot be replayed within its validity window", () => {
  const proof = sign({
    method: "PUT",
    path: "/v1/admin/users/x/active",
    body: JSON.stringify({ active: false }),
  });
  panel(proof, "PUT", "/v1/admin/users/x/active", { active: false });
  assert.throws(
    () => panel(proof, "PUT", "/v1/admin/users/x/active", { active: false }),
    /invalid or expired|already used/,
  );
});

test("panel actor identity is a fresh unforgeable object and spoofed copies are not admin", () => {
  const a = panel(sign());
  const b = panel(sign());
  assert.notEqual(a, b);
  assert.ok(isPanelActor(a) && isPanelActor(b));
  for (const fake of [
    { ...a },
    Object.create(a),
    {
      uid: "admin-panel",
      email: "admin-panel@bookingos.internal",
      name: "Platform admin",
    },
    JSON.parse(JSON.stringify(a)),
  ])
    assert.equal(isPanelActor(fake), false);
});

test("admin guard: header must be a single string; arrays, empty and absent headers are refused", () => {
  const run = (header: unknown) => {
    const request = {
      method: "GET",
      originalUrl: "/v1/admin/me",
      headers: { "x-bookingos-admin": header },
      body: undefined,
    };
    return new AdminGuard().canActivate({
      switchToHttp: () => ({ getRequest: () => request }),
    } as never);
  };
  assert.equal(run(sign()), true);
  for (const h of [undefined, "", [sign()], 5, null, {}])
    assert.throws(
      () => run(h),
      /invalid or expired/,
      JSON.stringify(h)?.slice(0, 30),
    );
});

// -------------------------------------------------------- push dispatch endpoint

test("push dispatch endpoint: only POST with an exact >=32 character secret, regardless of case or padding", async () => {
  const secret = "s".repeat(40);
  const saved = [
    process.env.BOOKING_PUSH_DISPATCH_SECRET,
    process.env.BOOKING_PUSH_DISPATCH_ENABLED,
  ];
  let dispatched = 0;
  const handler = notificationHandler({
    dispatch: async () => (dispatched++, { sent: 0 }),
  } as never);
  const call = (method: string, headers: Record<string, string> = {}) =>
    handler(new Request("https://x.test/", { method, headers }));
  try {
    process.env.BOOKING_PUSH_DISPATCH_SECRET = secret;
    process.env.BOOKING_PUSH_DISPATCH_ENABLED = "true";
    for (const method of ["GET", "PUT", "DELETE", "PATCH"])
      assert.equal(
        (await call(method, { "x-booking-push-secret": secret })).status,
        405,
        method,
      );
    for (const header of [
      undefined,
      "",
      " ",
      secret.toUpperCase(),
      secret.slice(1),
      `${secret}x`,
      "s",
      "Bearer " + secret,
    ])
      assert.equal(
        (
          await call(
            "POST",
            header === undefined ? {} : { "x-booking-push-secret": header },
          )
        ).status,
        401,
        JSON.stringify(header)?.slice(0, 20),
      );
    assert.equal(dispatched, 0);
    assert.equal(
      (await call("POST", { "x-booking-push-secret": secret })).status,
      200,
    );
    assert.equal(dispatched, 1);
    for (const weak of [undefined, "", "short", "x".repeat(31)]) {
      weak === undefined
        ? delete process.env.BOOKING_PUSH_DISPATCH_SECRET
        : (process.env.BOOKING_PUSH_DISPATCH_SECRET = weak);
      assert.equal(
        (await call("POST", { "x-booking-push-secret": weak ?? "" })).status,
        401,
        `secret ${weak}`,
      );
    }
    process.env.BOOKING_PUSH_DISPATCH_SECRET = secret;
    for (const flag of [undefined, "", "TRUE", "1", "yes", "false", " true"]) {
      flag === undefined
        ? delete process.env.BOOKING_PUSH_DISPATCH_ENABLED
        : (process.env.BOOKING_PUSH_DISPATCH_ENABLED = flag);
      const r = await call("POST", { "x-booking-push-secret": secret });
      assert.deepEqual(
        [r.status, await r.json()],
        [200, { disabled: true }],
        `flag ${flag}`,
      );
    }
    assert.equal(dispatched, 1, "disabled switch never dispatches");
  } finally {
    saved[0] === undefined
      ? delete process.env.BOOKING_PUSH_DISPATCH_SECRET
      : (process.env.BOOKING_PUSH_DISPATCH_SECRET = saved[0]);
    saved[1] === undefined
      ? delete process.env.BOOKING_PUSH_DISPATCH_ENABLED
      : (process.env.BOOKING_PUSH_DISPATCH_ENABLED = saved[1]);
  }
});

test("push dispatch endpoint: request body and query cannot choose recipients; dispatcher failures are generic 503", async () => {
  process.env.BOOKING_PUSH_DISPATCH_SECRET = "s".repeat(40);
  process.env.BOOKING_PUSH_DISPATCH_ENABLED = "true";
  const seen: unknown[][] = [];
  const handler = notificationHandler({
    dispatch: async (...a: unknown[]) => (seen.push(a), { sent: 0 }),
  } as never);
  const headers = {
    "x-booking-push-secret": "s".repeat(40),
    "content-type": "application/json",
  };
  await handler(
    new Request("https://x.test/?user_id=victim&limit=100000", {
      method: "POST",
      headers,
      body: JSON.stringify({ user_id: "victim", token: "t", limit: 1e9 }),
    }),
  );
  assert.deepEqual(
    seen,
    [[20]],
    "only the fixed batch size reaches the dispatcher",
  );
  const failing = notificationHandler({
    dispatch: async () => {
      throw new Error("FCM key leaked: abc");
    },
  } as never);
  const r = await failing(
    new Request("https://x.test/", { method: "POST", headers }),
  );
  assert.equal(r.status, 503);
  assert.equal((await r.text()).includes("leaked"), false);
  delete process.env.BOOKING_PUSH_DISPATCH_SECRET;
  delete process.env.BOOKING_PUSH_DISPATCH_ENABLED;
});
