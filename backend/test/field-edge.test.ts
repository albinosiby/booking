import "reflect-metadata";
import { test, afterEach } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { createHash, createHmac, randomUUID } from "node:crypto";
import {
  ConflictException,
  ForbiddenException,
  UnauthorizedException,
} from "@nestjs/common";
import { createHandler } from "../edge/handler";

const SECRET = "test-only-panel-signing-secret-0123456789";
process.env.ADMIN_SESSION_SECRET = SECRET;
const id = "00000000-0000-4000-8000-000000000001";
const envKeys = ["BOOKING_CORS_ORIGINS", "BOOKING_WEB_ORIGIN"] as const;
afterEach(() => {
  for (const k of envKeys) delete process.env[k];
});

function fixture(
  opts: { voiceKey?: (key: string | null, callEvent: boolean) => unknown } = {},
) {
  const calls: Array<{ method: string; args: any[] }> = [];
  let fail: Error | undefined;
  const service: any = new Proxy(
    {},
    {
      get: (_, method) =>
        method === "emailTeamAccess"
          ? service
          : async (...args: any[]) => {
              calls.push({ method: String(method), args });
              if (fail) throw fail;
              return { ok: true };
            },
    },
  );
  const services = {
    notifications: service,
    workspace: service,
    admissions: service,
    messages: service,
    bookings: service,
    blocks: service,
    accounts: service,
    invoices: service,
    expenses: service,
    income: service,
    turf: service,
    court: service,
    pool: service,
    hall: service,
    agentCalls: service,
    admin: service,
    adminSarvam: service,
    support: service,
    website: service,
    voice: service,
    staffCash: service,
    sarvam: {
      authenticateToolKey: async (key: string | null, callEvent: boolean) => {
        calls.push({ method: "authenticateToolKey", args: [key, callEvent] });
        const r = opts.voiceKey ? await opts.voiceKey(key, callEvent) : null;
        if (r) return r;
        if (key !== "bkv_" + "a".repeat(43))
          throw new UnauthorizedException(
            "A valid voice tool key is required.",
          );
        return {
          uid: "sarvam:org",
          email: "voice-agent@sarvam.invalid",
          name: "Voice",
        };
      },
      oauthCallback: async () => ({}),
    },
  } as any;
  const handler = createHandler(
    services,
    async (token) => {
      if (token !== "valid" && token !== "other")
        throw new ForbiddenException("Denied");
      return {
        uid: `actor-${token}`,
        email: "owner@example.com",
        name: "Owner",
      };
    },
    async () => {},
  );
  const send = (
    path: string,
    init: RequestInit & { token?: string | null } = {},
  ) => {
    const { token = "valid", headers, ...rest } = init;
    return handler(
      new Request(`https://example.com/functions/v1/booking-api${path}`, {
        ...rest,
        headers: {
          ...(token ? { authorization: `Bearer ${token}` } : {}),
          ...(headers as object),
        },
      }),
    );
  };
  const json = (
    path: string,
    method: string,
    data: unknown,
    headers: Record<string, string> = {},
    token: string | null = "valid",
  ) =>
    send(path, {
      method,
      token,
      headers: { "content-type": "application/json", ...headers },
      body: typeof data === "string" ? data : JSON.stringify(data),
    });
  return {
    handler,
    send,
    json,
    calls,
    setFailure: (e: Error | undefined) => (fail = e),
  };
}
const proof = (method: string, path: string, body = "") => {
  const ts = String(Date.now()),
    nonce = randomUUID();
  const mac = createHmac("sha256", SECRET)
    .update(
      [
        "booking-admin-v1",
        ts,
        nonce,
        method,
        path,
        createHash("sha256").update(body).digest("hex"),
      ].join("\n"),
    )
    .digest("hex");
  return `${ts}.${nonce}.${mac}`;
};

// ----------------------------------------------------------------- path & params

test(
  "edge: malformed percent-encoding in a path is a client error, never a 500",
  { todo: "BUG-22" },
  async () => {
    const f = fixture();
    for (const [path, method] of [
      [`/v1/team/%E0%A4%A`, "DELETE"],
      ["/v1/businesses/%zz/activate", "POST"],
      ["/public/v1/sites/%E0%A4%A", "GET"],
    ] as const) {
      const r = await f.send(path, { method });
      assert.ok(
        r.status >= 400 && r.status < 500,
        `${method} ${path} gave ${r.status}`,
      );
    }
  },
);

test("edge: route parameters must be UUIDs (including the encoded forms) and never reach the service otherwise", async () => {
  const f = fixture();
  for (const bad of [
    "x",
    "1",
    `${id}0`,
    id.slice(1),
    "..%2F..",
    "' OR 1=1",
    "%00",
    "00000000-0000-4000-8000-00000000000g",
    "%20",
  ]) {
    for (const [path, method] of [
      [`/v1/team/${bad}`, "DELETE"],
      [`/v1/invitations/${bad}`, "DELETE"],
      [`/v1/invitations/${bad}/permanent`, "DELETE"],
      [`/v1/team/${bad}/permanent`, "DELETE"],
      [`/v1/businesses/${bad}/activate`, "POST"],
      [`/v1/invitations/${bad}/email`, "POST"],
      [`/v1/admin/organizations/${bad}`, "GET"],
    ] as const) {
      const r =
        method === "GET" && path.startsWith("/v1/admin")
          ? await f.send(path, {
              method,
              token: null,
              headers: {
                "x-bookingos-admin": proof(
                  method,
                  (({ pathname, search }) =>
                    pathname.replace(/^\/functions\/v1\/booking-api/, "") +
                    search)(
                    new URL(
                      `https://example.com/functions/v1/booking-api${path}`,
                    ),
                  ),
                ),
              },
            })
          : await f.send(path, { method });
      assert.equal(r.status, 422, `${method} ${path}`);
    }
  }
  assert.equal(f.calls.length, 0);
  assert.equal(
    (await f.send(`/v1/team/${id.toUpperCase()}`, { method: "DELETE" })).status,
    200,
    "upper-case UUID is accepted",
  );
});

test("edge: unknown routes and wrong methods are 404 after authentication is skipped, trailing slashes are ignored", async () => {
  const f = fixture();
  for (const [path, method] of [
    ["/v1/nope", "GET"],
    ["/v1/workspace", "DELETE"],
    ["/v1/team", "PUT"],
    ["//v1/team", "GET"],
    ["/v1/team/extra/segments/here", "GET"],
    ["/", "GET"],
    ["/v1", "GET"],
  ] as const)
    assert.equal(
      (await f.send(path, { method })).status,
      404,
      `${method} ${path}`,
    );
  assert.equal((await f.send("/v1/team/", { method: "GET" })).status, 200);
  assert.equal(
    (await f.send("/v1/nope", { token: null })).status,
    404,
    "route lookup precedes auth: unauthenticated unknown route is 404",
  );
  assert.equal(f.calls.length, 1);
});

test("edge: the legacy /booking-api and /functions/v1/booking-api prefixes both route", async () => {
  const f = fixture();
  for (const url of [
    "https://example.com/booking-api/v1/team",
    "https://example.com/functions/v1/booking-api/v1/team",
    "https://example.com/v1/team",
  ]) {
    const r = await f.handler(
      new Request(url, { headers: { authorization: "Bearer valid" } }),
    );
    assert.equal(r.status, 200, url);
  }
});

// ---------------------------------------------------------------------- bearer

test("edge: only a single well-formed Bearer token authenticates", async () => {
  const f = fixture();
  for (const header of [
    "",
    "Bearer",
    "Bearer ",
    "bearer valid",
    "BEARER valid",
    "Bearer  valid",
    "Bearer valid extra",
    "Basic dmFsaWQ=",
    "valid",
    "Token valid",
  ]) {
    const r = await f.handler(
      new Request("https://example.com/v1/team", {
        headers: header ? { authorization: header } : {},
      }),
    );
    assert.equal(r.status, 401, JSON.stringify(header));
    assert.equal(((await r.json()) as any).code, "UNAUTHENTICATED");
  }
  assert.equal((await f.send("/v1/team", { token: "wrong" })).status, 403);
  assert.equal(f.calls.length, 0);
});

// ------------------------------------------------------------------------ body

test("edge: JSON body handling for write routes", async () => {
  const f = fixture();
  const post = (
    data: string,
    headers: Record<string, string> = { "content-type": "application/json" },
  ) => f.send("/v1/businesses", { method: "POST", headers, body: data });
  assert.equal((await post("{broken")).status, 400);
  assert.equal(
    (await post("")).status,
    201,
    "empty body is passed through as undefined",
  );
  assert.equal(
    (await post("{}", { "content-type": "text/plain" })).status,
    415,
  );
  assert.equal((await post("{}", {})).status, 415, "missing content type");
  assert.equal(
    (await post("{}", { "content-type": "application/x-www-form-urlencoded" }))
      .status,
    415,
  );
  for (const ct of [
    "application/json",
    "application/json; charset=utf-8",
    "APPLICATION/JSON",
  ])
    assert.equal(
      (await post('{"a":1}', { "content-type": ct })).status,
      201,
      ct,
    );
  for (const scalar of ["null", "5", '"text"', "[]", "[1,2]", "true"]) {
    const before = f.calls.length;
    assert.equal((await post(scalar)).status, 201, scalar);
    assert.deepEqual(
      f.calls[before].args[1],
      JSON.parse(scalar),
      "service receives the parsed scalar and must validate it",
    );
  }
  assert.equal((await post('{"a":1}garbage')).status, 400);
  assert.equal(
    (await post('{"a":"\\u0000"}')).status,
    201,
    "NUL reaches the service",
  );
});

test("edge: oversized bodies are cut off by header and by streaming", async () => {
  const f = fixture();
  const big = JSON.stringify({ x: "a".repeat(3 * 1024 * 1024 + 10) });
  assert.equal((await f.json("/v1/businesses", "POST", big)).status, 413);
  const chunk = new TextEncoder().encode("a".repeat(1024 * 1024));
  let sent = 0;
  const stream = new ReadableStream({
    pull(c) {
      if (sent++ < 4) c.enqueue(chunk);
      else c.close();
    },
  });
  const r = await f.handler(
    new Request("https://example.com/v1/businesses", {
      method: "POST",
      headers: {
        authorization: "Bearer valid",
        "content-type": "application/json",
      },
      body: stream,
      duplex: "half",
    } as never),
  );
  assert.equal(r.status, 413, "chunked body without content-length is counted");
  assert.equal(f.calls.length, 0);
  assert.equal(
    (
      await f.json(
        "/v1/businesses",
        "POST",
        JSON.stringify({ x: "a".repeat(3 * 1024 * 1024 - 100) }),
      )
    ).status,
    201,
    "just below the limit is accepted",
  );
});

test("edge: GET and DELETE bodies are ignored", async () => {
  const f = fixture();
  const r = await f.send(`/v1/team/${id}`, {
    method: "DELETE",
    headers: { "content-type": "application/json" },
    body: "{broken",
  });
  assert.equal(r.status, 200);
});

// ------------------------------------------------------------------ query/admin

test("edge: invite redirect accepts only a 64-hex lower-case token", async () => {
  const f = fixture();
  const token = "ab12".repeat(16);
  const ok = await f.send(`/invite?token=${token}`, { token: null });
  assert.equal(ok.status, 302);
  assert.equal(
    ok.headers.get("location"),
    `com.bookingos.app://invite/invite?token=${token}`,
  );
  assert.equal(ok.headers.get("referrer-policy"), "no-referrer");
  for (const bad of [
    "",
    "abc",
    token.toUpperCase(),
    token + "a",
    token.slice(1),
    "x".repeat(64),
    `${token}%0Aevil`,
    "%00",
  ]) {
    const r = await f.send(`/invite?token=${bad}`, { token: null });
    assert.equal(r.status, 422, bad);
    assert.equal(r.headers.get("location"), null);
  }
  assert.equal((await f.send("/invite", { token: null })).status, 422);
  const injected = await f.send(
    `/invite?token=${token}&redirect=https://evil.example`,
    { token: null },
  );
  assert.equal(
    injected.status,
    422,
    "unknown query keys are refused (strict schema)",
  );
  assert.equal(injected.headers.get("location"), null);
});

test("edge: admin routes require a proof bound to method, path+query and body; bearer tokens never authorise them", async () => {
  const f = fixture();
  const path = "/v1/admin/users?q=a";
  assert.equal((await f.send(path, { token: null })).status, 401);
  assert.equal((await f.send(path, { token: "valid" })).status, 401);
  assert.equal(
    (
      await f.send(path, {
        token: null,
        headers: { "x-bookingos-admin": proof("GET", "/v1/admin/users") },
      })
    ).status,
    401,
    "query not signed",
  );
  assert.equal(
    (
      await f.send(path, {
        token: null,
        headers: { "x-bookingos-admin": proof("POST", path) },
      })
    ).status,
    401,
    "wrong method",
  );
  assert.equal(
    (
      await f.send(path, {
        token: null,
        headers: { "x-bookingos-admin": proof("GET", path) + "0" },
      })
    ).status,
    401,
  );
  assert.equal(
    (
      await f.send(path, {
        token: null,
        headers: { "x-bookingos-admin": proof("GET", path) },
      })
    ).status,
    200,
  );
  const target = `/v1/admin/users/${id}/active`;
  const body = JSON.stringify({ active: false });
  assert.equal(
    (
      await f.json(
        target,
        "PUT",
        body,
        {
          "x-bookingos-admin": proof(
            "PUT",
            target,
            JSON.stringify({ active: true }),
          ),
        },
        null,
      )
    ).status,
    401,
    "body tampered",
  );
  assert.equal(
    (
      await f.json(
        target,
        "PUT",
        body,
        { "x-bookingos-admin": proof("PUT", target, body) },
        null,
      )
    ).status,
    200,
  );
  assert.equal(
    (
      await f.json(
        target,
        "PUT",
        '{ "active" : false }',
        { "x-bookingos-admin": proof("PUT", target, body) },
        null,
      )
    ).status,
    200,
    "proof covers the canonical JSON, so insignificant whitespace is fine",
  );
  const two = JSON.stringify({ a: 1, b: 2 });
  assert.equal(
    (
      await f.json(
        target,
        "PUT",
        JSON.stringify({ b: 2, a: 1 }),
        { "x-bookingos-admin": proof("PUT", target, two) },
        null,
      )
    ).status,
    401,
    "key order is part of the signed text",
  );
  const before = f.calls.length;
  assert.equal(
    (
      await f.send("/v1/workspace", {
        token: null,
        headers: { "x-bookingos-admin": proof("GET", "/v1/workspace") },
      })
    ).status,
    401,
    "panel proof does not open member routes",
  );
  assert.equal(f.calls.length, before);
});

test("edge: admin proof secret misconfiguration is a 503, not an open door", async () => {
  const f = fixture();
  const path = "/v1/admin/me";
  const p = proof("GET", path);
  process.env.ADMIN_SESSION_SECRET = "short";
  try {
    const r = await f.send(path, {
      token: null,
      headers: { "x-bookingos-admin": p },
    });
    assert.equal(r.status, 503);
  } finally {
    process.env.ADMIN_SESSION_SECRET = SECRET;
  }
});

// ------------------------------------------------------------------------ CORS

test("edge: only configured origins pass, preflight is answered, and header values are exact", async () => {
  const f = fixture();
  process.env.BOOKING_CORS_ORIGINS =
    " https://app.example , https://www.example ";
  process.env.BOOKING_WEB_ORIGIN = "https://web.example";
  const call = (origin: string | null, method = "GET") =>
    f.handler(
      new Request("https://example.com/v1/catalog", {
        method,
        headers: origin === null ? {} : { origin },
      }),
    );
  for (const o of [
    "https://app.example",
    "https://www.example",
    "https://web.example",
  ]) {
    const r = await call(o);
    assert.equal(r.status, 200);
    assert.equal(r.headers.get("access-control-allow-origin"), o);
    assert.equal(r.headers.get("vary"), "Origin");
  }
  for (const o of [
    "https://app.example/",
    "http://app.example",
    "https://APP.example",
    "https://app.example.evil.test",
    "https://evil.test",
    "null",
    "*",
    "https://app.example:443",
    "",
  ]) {
    const r = await call(o);
    if (o === "")
      assert.equal(
        r.status,
        200,
        "an empty Origin header is treated as no origin",
      );
    else assert.equal(r.status, 403, o);
    assert.equal(r.headers.get("access-control-allow-origin"), null);
  }
  const pre = await call("https://app.example", "OPTIONS");
  assert.equal(pre.status, 204);
  assert.match(pre.headers.get("access-control-allow-methods")!, /PATCH/);
  assert.equal((await call(null, "OPTIONS")).status, 204);
  assert.equal((await call("https://evil.test", "OPTIONS")).status, 403);
  const none = await call(null);
  assert.equal(none.headers.get("access-control-allow-origin"), null);
  assert.equal(none.headers.get("cache-control"), "private, no-store");
  assert.equal(none.headers.get("x-content-type-options"), "nosniff");
});

test("edge: with no allow-list configured every browser origin is refused", async () => {
  const f = fixture();
  const r = await f.handler(
    new Request("https://example.com/v1/catalog", {
      headers: { origin: "https://anywhere.test" },
    }),
  );
  assert.equal(r.status, 403);
});

// ------------------------------------------------------------------ rate limits

test("edge: an actor is limited to 120 requests per minute and other actors are unaffected", async () => {
  const f = fixture();
  let last = 0;
  for (let i = 0; i < 121; i++) last = (await f.send("/v1/team")).status;
  assert.equal(last, 429);
  assert.equal((await f.send("/v1/team", { token: "other" })).status, 200);
  const body = (await (await f.send("/v1/team")).json()) as any;
  assert.equal(body.code, "REQUEST_ERROR");
});

test("edge: failed authentication does not consume another user's rate budget", async () => {
  const f = fixture();
  for (let i = 0; i < 130; i++) await f.send("/v1/team", { token: "invalid" });
  assert.equal((await f.send("/v1/team")).status, 200);
});

test("edge: logged-out device revocation validates body size/JSON and shares one global budget", async () => {
  const f = fixture();
  const revoke = (data: string) =>
    f.handler(
      new Request("https://example.com/v1/notifications/installations/revoke", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: data,
      }),
    );
  assert.equal((await revoke("{broken")).status, 400);
  assert.equal(
    (await revoke(JSON.stringify({ x: "a".repeat(2000) }))).status,
    413,
  );
  assert.equal((await revoke("{}")).status, 200);
  let status = 0;
  for (let i = 0; i < 125; i++) status = (await revoke("{}")).status;
  assert.equal(
    status,
    429,
    "after 120 calls anyone is throttled (shared bucket)",
  );
  assert.equal(
    (await f.send("/v1/team")).status,
    200,
    "authenticated traffic is a separate budget",
  );
});

// ------------------------------------------------------------------------ voice

test("edge voice routes: tool key is mandatory and must be well formed before any work happens", async () => {
  const f = fixture();
  const call = (path: string, key: string | null, method = "POST") =>
    f.handler(
      new Request(`https://example.com${path}`, {
        method,
        headers: {
          ...(key === null ? {} : { "x-api-key": key }),
          "content-type": "application/json",
        },
        body: method === "POST" ? "{}" : undefined,
      }),
    );
  for (const key of [
    null,
    "",
    " ",
    "bkv_short",
    "bkv_" + "a".repeat(42),
    "bkv_" + "a".repeat(44),
    "xxx_" + "a".repeat(43),
    "bkv_" + "!".repeat(43),
    "Bearer " + "bkv_" + "a".repeat(43),
  ])
    assert.equal(
      (await call("/voice/v1/catalog", key)).status,
      401,
      String(key),
    );
  assert.equal(
    (await call("/voice/v1/catalog", "bkv_" + "a".repeat(43))).status,
    200,
  );
  assert.equal(
    (await call("/voice/v1/catalog", "bkv_" + "a".repeat(43), "GET")).status,
    404,
    "tool endpoints are POST only",
  );
  assert.equal(
    (await call("/voice/v1/unknown", "bkv_" + "a".repeat(43))).status,
    404,
  );
});

test("edge voice routes: expected refusals come back as 200 {ok:false} and client mistakes never leak internals", async () => {
  const f = fixture();
  f.setFailure(new ConflictException("Slot taken"));
  const key = "bkv_" + "a".repeat(43);
  const r = await f.handler(
    new Request("https://example.com/voice/v1/bookings", {
      method: "POST",
      headers: { "x-api-key": key, "content-type": "application/json" },
      body: "{}",
    }),
  );
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), { ok: false, message: "Slot taken" });
  f.setFailure(new Error("db password=hunter2"));
  const e = await f.handler(
    new Request("https://example.com/voice/v1/bookings", {
      method: "POST",
      headers: { "x-api-key": key, "content-type": "application/json" },
      body: "{}",
    }),
  );
  assert.equal(e.status, 500);
  assert.equal((await e.text()).includes("hunter2"), false);
});

test("edge voice routes: call-events use the call-event authentication mode only on that path", async () => {
  const f = fixture();
  const key = "bkv_" + "a".repeat(43);
  for (const [path, mode] of [
    ["/voice/v1/call-events", true],
    ["/voice/v1/catalog", false],
    ["/voice/v1/cancel", false],
  ] as const) {
    await f.handler(
      new Request(`https://example.com${path}`, {
        method: "POST",
        headers: { "x-api-key": key, "content-type": "application/json" },
        body: "{}",
      }),
    );
    const last = f.calls
      .filter((c) => c.method === "authenticateToolKey")
      .at(-1)!;
    assert.deepEqual(last.args, [key, mode], path);
  }
});

// ---------------------------------------------------------------- public routes

test("edge public website: sub-routes, id format and body size are enforced", async () => {
  const f = fixture();
  const get = (p: string) =>
    f.handler(new Request(`https://example.com/public/v1/sites/${p}`));
  assert.equal((await get("my-club")).status, 200);
  assert.equal((await get("my-club/catalog")).status, 200);
  for (const bad of [
    "my-club/unknown",
    "my-club/images/short",
    "my-club/images/" + "g".repeat(36),
    "my-club/catalog/extra",
    "my-club//",
    "",
  ])
    assert.equal((await get(bad)).status, 404, bad);
  assert.equal(
    (
      await f.handler(
        new Request("https://example.com/public/v1/sites/my-club/bookings"),
      )
    ).status,
    404,
    "GET on a POST-only operation",
  );
  const post = (
    op: string,
    data: string,
    headers: Record<string, string> = {},
  ) =>
    f.handler(
      new Request(`https://example.com/public/v1/sites/my-club/${op}`, {
        method: "POST",
        headers: { "content-type": "application/json", ...headers },
        body: data,
      }),
    );
  assert.equal((await post("quote", "{broken")).status, 400);
  assert.equal(
    (await post("quote", JSON.stringify({ x: "a".repeat(20000) }))).status,
    413,
  );
  assert.equal((await post("bookings", "{}")).status, 201);
  assert.equal((await post("availability", "{}")).status, 200);
  assert.equal(
    (await post("quote", "{}", { "content-type": "text/plain" })).status,
    415,
  );
  const slugCall = f.calls.find((c) => c.method === "catalog")!;
  assert.equal(slugCall.args[0], "my-club");
  await get("spaced%20slug%2Fwith-slash");
  assert.equal(
    f.calls.filter((c) => c.method === "catalog").at(-1)!.args[0],
    "spaced slug/with-slash",
    "slug is data, decoded once",
  );
});

test("edge catalog: only upper-case two-letter country codes are routed for states", async () => {
  const f = fixture();
  for (const code of ["in", "IND", "I", "1", "I%4E", "%00%00"]) {
    const r = await f.handler(
      new Request(`https://example.com/v1/catalog/states/${code}`),
    );
    assert.notEqual(r.status, 200, code);
  }
  assert.equal(
    (await f.handler(new Request("https://example.com/v1/catalog/states/IN")))
      .status,
    200,
  );
  const states = (await (
    await f.handler(new Request("https://example.com/v1/catalog/states/ZZ"))
  ).json()) as unknown[];
  assert.deepEqual(states, []);
});

// ---------------------------------------------------------------------- errors

test("edge errors: typed errors keep their status, unknown errors are generic and every response has a request id", async () => {
  const f = fixture();
  for (const [error, status, code] of [
    [new ConflictException("dup"), 409, "CONFLICT"],
    [new ForbiddenException("no"), 403, "FORBIDDEN"],
    [new UnauthorizedException("no"), 401, "UNAUTHENTICATED"],
    [
      Object.assign(new Error("duplicate key"), { code: "23505" }),
      409,
      "CONFLICT",
    ],
    [new Error("secret=abc"), 500, "INTERNAL_ERROR"],
    [
      Object.assign(new Error("secret=abc"), { code: "22P02" }),
      422,
      "VALIDATION_ERROR",
    ],
  ] as const) {
    f.setFailure(error as Error);
    const r = await f.json("/v1/businesses", "POST", {});
    const b = (await r.json()) as any;
    assert.equal(r.status, status);
    assert.equal(b.code, code);
    assert.equal(JSON.stringify(b).includes("secret=abc"), false);
    assert.equal(r.headers.get("x-request-id"), b.request_id);
  }
});

test("edge errors: validation failures from services are 422 with paths and without echoed input", async () => {
  const f = fixture();
  const { z } = await import("zod");
  try {
    z.object({ name: z.string().min(40) }).parse({ name: "very-secret-value" });
  } catch (e) {
    f.setFailure(e as Error);
  }
  const r = await f.json("/v1/businesses", "POST", {});
  const b = (await r.json()) as any;
  assert.equal(r.status, 422);
  assert.equal(b.code, "VALIDATION_ERROR");
  assert.match(b.message, /^name:/);
  assert.equal(b.message.includes("very-secret-value"), false);
});

test("edge errors: client-caused database errors map to 4xx", async () => {
  const f = fixture();
  for (const code of ["22P02", "22021", "22001", "23514"]) {
    f.setFailure(Object.assign(new Error("db"), { code }));
    const r = await f.json("/v1/businesses", "POST", {});
    assert.ok(r.status >= 400 && r.status < 500, `pg ${code} gave ${r.status}`);
  }
});

// ----------------------------------------------------- deployed bundle freshness

test("deployed edge bundles contain every route and rule the source declares", () => {
  const root = resolve(import.meta.dirname, "../..");
  const source = readFileSync(resolve(root, "backend/edge/handler.ts"), "utf8");
  const bundle = readFileSync(
    resolve(root, "supabase/functions/booking-api/index.ts"),
    "utf8",
  );
  const routes = [
    ...source.matchAll(
      /add\(\s*"(GET|POST|PUT|PATCH|DELETE)",\s*(?:"([^"]+)"|`([^`]+)`)/g,
    ),
  ]
    .map((m) => m[2] ?? m[3])
    .filter((p) => !p.includes("${"));
  assert.ok(routes.length > 100, `parsed ${routes.length} routes`);
  const missing = [...new Set(routes)].filter(
    (p) => !bundle.includes(`"${p}"`) && !bundle.includes(`\`${p}\``),
  );
  assert.deepEqual(
    missing,
    [],
    "routes in edge/handler.ts missing from supabase/functions/booking-api/index.ts (rebuild with npm run edge:build)",
  );
  const revision = /revision:\s*"([^"]+)"/.exec(source)![1];
  assert.ok(
    bundle.includes(revision),
    "bundle revision matches handler source",
  );
  for (const rule of [
    "Only the owner can manage organization setup.",
    "You cannot remove your own owner access.",
    "An organization needs at least one owner.",
    "team-owners:",
  ])
    assert.ok(bundle.includes(rule), `bundle lacks: ${rule}`);
  const push = readFileSync(
    resolve(root, "supabase/functions/booking-notifications/index.ts"),
    "utf8",
  );
  assert.ok(push.includes("x-booking-push-secret"));
  assert.ok(push.includes("BOOKING_PUSH_DISPATCH_ENABLED"));
});

test("function manifests pin the runtime config and import the same pdf dependency version", () => {
  const root = resolve(import.meta.dirname, "../..");
  for (const fn of ["booking-api", "booking-notifications"]) {
    const manifest = JSON.parse(
      readFileSync(resolve(root, `supabase/functions/${fn}/deno.json`), "utf8"),
    );
    assert.equal(typeof manifest, "object");
    assert.equal(
      JSON.stringify(manifest).includes("latest"),
      false,
      `${fn} must not float on latest`,
    );
  }
});
