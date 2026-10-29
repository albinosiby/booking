import "reflect-metadata";
import { test } from "node:test";
import assert from "node:assert/strict";
import { UnauthorizedException, ForbiddenException } from "@nestjs/common";
import { createHandler } from "../edge/handler";
import { AdminMcpError } from "../src/admin/admin-mcp.service";
import { signAdminRequest } from "../../admin-panel/lib/request-signature";

const org = "00000000-0000-4000-8000-000000000001";
const base = "/v1/admin-mcp/voice";
function fixture(
  options: { missingAuth?: boolean; missingService?: boolean } = {},
) {
  const serviceCalls: { method: string; args: any[] }[] = [],
    mcpAuthCalls: any[] = [],
    userAuthCalls: string[] = [];
  let failure: Error | undefined;
  const service = new Proxy(
    {},
    {
      get:
        (_, method) =>
        async (...args: any[]) => {
          serviceCalls.push({ method: String(method), args });
          if (failure) throw failure;
          return method === "credential"
            ? {
                job_id: org,
                secret_name: "job-owned-secret",
                tool_key: "test-private-installer-key",
              }
            : { ok: true };
        },
    },
  );
  const actor = {
    uid: "admin-mcp:operator",
    email: "operator@example.com",
    name: "Voice operator",
  };
  const allowed: Record<string, string[]> = {
    "mcp-read": ["voice:read"],
    "mcp-write": ["voice:read", "voice:write"],
    "mcp-installer": ["voice:credentials:install"],
  };
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
    ...(options.missingService ? {} : { adminMcp: service }),
    ...(options.missingAuth
      ? {}
      : {
          adminMcpAuth: {
            authenticate: async (header: string | null, scope: string) => {
              mcpAuthCalls.push({ header, scope });
              const token = /^Bearer (.+)$/.exec(header ?? "")?.[1];
              if (!token || !allowed[token])
                throw new UnauthorizedException(
                  "Admin MCP authorization required.",
                );
              if (!allowed[token].includes(scope))
                throw new ForbiddenException("Admin MCP scope is not allowed.");
              return actor;
            },
          },
        }),
  } as any;
  const handler = createHandler(
    services,
    async (token) => {
      userAuthCalls.push(token);
      if (token !== "owner-session")
        throw new UnauthorizedException("User session required.");
      return { uid: "owner", email: "owner@example.com", name: "Owner" };
    },
    async () => {},
  );
  const request = (
    path: string,
    method = "GET",
    body?: unknown,
    token: string | null = "mcp-read",
    extra: Record<string, string> = {},
  ) =>
    handler(
      new Request(`https://example.test/functions/v1/booking-api${path}`, {
        method,
        headers: {
          ...(token ? { authorization: `Bearer ${token}` } : {}),
          ...(body === undefined ? {} : { "content-type": "application/json" }),
          ...extra,
        },
        body: body === undefined ? undefined : JSON.stringify(body),
      }),
    );
  return {
    request,
    serviceCalls,
    mcpAuthCalls,
    userAuthCalls,
    actor,
    fail: (e: Error) => (failure = e),
  };
}

test("Edge routes narrow MCP reads through dedicated authentication without a user-session fallback", async () => {
  const f = fixture();
  const response = await f.request(
    `${base}/requests?name=Edens&status=requested`,
  );
  assert.equal(response.status, 200);
  assert.equal(f.mcpAuthCalls[0].scope, "voice:read");
  assert.equal(f.userAuthCalls.length, 0);
  assert.equal(f.serviceCalls[0].method, "list");
  assert.equal(f.serviceCalls[0].args[0], f.actor);
  assert.deepEqual(f.serviceCalls[0].args[1], {
    name: "Edens",
    status: "requested",
  });
  for (const token of [null, "owner-session", "unknown"]) {
    const denied = fixture();
    assert.equal(
      (await denied.request(`${base}/requests`, "GET", undefined, token))
        .status,
      401,
    );
    assert.equal(denied.serviceCalls.length, 0);
    assert.equal(denied.userAuthCalls.length, 0);
  }
});

test("Edge enforces write and credential-install scopes before dispatch and preserves exact org/body", async () => {
  const f = fixture(),
    payload = { job_id: org, lease_id: org, operation_key: org };
  assert.equal(
    (await f.request(`${base}/requests/${org}/start`, "POST", {}, "mcp-read"))
      .status,
    403,
  );
  assert.equal(
    (
      await f.request(
        `${base}/jobs/${org}/credential`,
        "POST",
        payload,
        "mcp-write",
      )
    ).status,
    403,
  );
  assert.equal(f.serviceCalls.length, 0);
  const response = await f.request(
    `${base}/jobs/${org}/credential`,
    "POST",
    payload,
    "mcp-installer",
  );
  assert.equal(response.status, 201);
  assert.match(response.headers.get("cache-control") ?? "", /no-store/);
  assert.equal(response.headers.get("x-content-type-options"), "nosniff");
  const result = await response.json();
  assert.equal(result.tool_key, "test-private-installer-key");
  assert.equal(f.serviceCalls[0].method, "credential");
  assert.equal(f.serviceCalls[0].args[1], org);
  assert.deepEqual(f.serviceCalls[0].args[2], payload);
  assert.equal(f.mcpAuthCalls.at(-1).scope, "voice:credentials:install");
  assert.equal(f.userAuthCalls.length, 0);
  assert.equal(
    (
      await f.request(
        `${base}/jobs/${org}/claim`,
        "POST",
        { job_id: org, version: 2 },
        "mcp-write",
      )
    ).status,
    201,
  );
  assert.equal(f.serviceCalls.at(-1)!.method, "claim");
});

test("Edge panel proof, MCP credential and owner sessions cannot substitute for one another", async () => {
  process.env.ADMIN_SESSION_SECRET =
    "test-only-edge-signing-secret-at-least-32-characters";
  const f = fixture(),
    path = `${base}/jobs/${org}/credential`,
    payload = { job_id: org, lease_id: org, operation_key: org };
  assert.equal(
    (
      await f.request(path, "POST", payload, "owner-session", {
        "x-bookingos-admin": signAdminRequest(
          "POST",
          path,
          JSON.stringify(payload),
        ),
      })
    ).status,
    401,
  );
  assert.equal(
    (await f.request("/v1/admin/me", "GET", undefined, "mcp-write")).status,
    401,
  );
  assert.equal(
    (await f.request("/v1/workspace", "GET", undefined, "mcp-write")).status,
    401,
  );
  assert.deepEqual(f.userAuthCalls, ["mcp-write"]);
  assert.equal(f.serviceCalls.length, 0);
});

test("Edge returns custom MCP errors and never falls back for a missing dedicated auth service", async () => {
  const f = fixture();
  f.fail(
    new AdminMcpError("STALE_PLAN", 409, "Read the saved job before retrying."),
  );
  const response = await f.request(
    `${base}/jobs/${org}/claim`,
    "POST",
    { job_id: org, version: 2 },
    "mcp-write",
  );
  assert.equal(response.status, 409);
  const error = await response.json();
  assert.equal(error.code, "STALE_PLAN");
  assert.equal(error.message, "Read the saved job before retrying.");
  assert.ok(error.request_id);
  assert.match(response.headers.get("cache-control") ?? "", /no-store/);
  const missing = fixture({ missingAuth: true });
  assert.equal(
    (
      await missing.request(
        `${base}/requests`,
        "GET",
        undefined,
        "owner-session",
      )
    ).status,
    503,
  );
  assert.equal(missing.userAuthCalls.length, 0);
  assert.equal(missing.serviceCalls.length, 0);
});

test("Edge rejects unknown MCP endpoints and invalid organization identifiers without dispatch", async () => {
  const f = fixture();
  for (const path of [
    `${base}/sql`,
    `${base}/jobs/${org}/rotate`,
    "/v1/admin-mcp/other/requests",
  ]) {
    assert.equal((await f.request(path, "POST", {}, "mcp-write")).status, 404);
  }
  assert.equal(f.mcpAuthCalls.length, 0);
  assert.equal(f.userAuthCalls.length, 0);
  assert.equal(f.serviceCalls.length, 0);
  assert.equal(
    (await f.request(`${base}/requests/invalid`, "GET", undefined, "mcp-read"))
      .status,
    422,
  );
  assert.equal(f.serviceCalls.length, 0);
  const unavailable = fixture({ missingService: true });
  assert.equal((await unavailable.request(`${base}/requests`)).status, 404);
});
