import { test } from "node:test";
import assert from "node:assert/strict";
import { ForbiddenException, ConflictException } from "@nestjs/common";
import { createHandler } from "../edge/handler";
const id = "00000000-0000-4000-8000-000000000001";
function fixture() {
  const calls: any[] = [];
  let fail: Error | undefined;
  const service = new Proxy(
    {},
    {
      get:
        (_, method) =>
        async (...args: any[]) => {
          calls.push({ method, args });
          if (fail) throw fail;
          return { ok: true };
        },
    },
  );
  const services = {
    workspace: service,
    messages: service,
    bookings: service,
    accounts: service,
    expenses: service,
    turf: service,
    court: service,
    pool: service,
    hall: service,
  } as any;
  const handler = createHandler(
    services,
    async (token) => {
      if (token !== "valid") throw new ForbiddenException("Denied");
      return { uid: "actor", email: "owner@example.com", name: "Owner" };
    },
    async () => {},
  );
  const request = (
    path: string,
    method = "GET",
    data?: unknown,
    token: string | null = "valid",
  ) =>
    handler(
      new Request(`https://example.com/functions/v1/booking-api${path}`, {
        method,
        headers: {
          ...(token ? { authorization: `Bearer ${token}` } : {}),
          ...(data !== undefined ? { "content-type": "application/json" } : {}),
        },
        body: data === undefined ? undefined : JSON.stringify(data),
      }),
    );
  return { handler, request, calls, setFailure: (e: Error) => (fail = e) };
}
test("Edge protects booking, accounts, configuration and organization routes before dispatch", async () => {
  const f = fixture();
  for (const path of ["/v1/workspace", "/v1/bookings", "/v1/accounts/catalog"])
    assert.equal((await f.request(path, "GET", undefined, null)).status, 401);
  assert.equal(
    (
      await f.request(
        `/v1/businesses/${id}/court-configuration`,
        "PATCH",
        {},
        "invalid",
      )
    ).status,
    403,
  );
  assert.equal(f.calls.length, 0);
});
test("Edge preserves route parameters, actor and configuration payloads for all business types", async () => {
  const f = fixture();
  for (const kind of ["turf", "court", "pool", "hall"]) {
    const response = await f.request(
      `/v1/businesses/${id}/${kind}-configuration`,
      "PATCH",
      { version: 3, configuration: { kind } },
    );
    assert.equal(response.status, 200);
    assert.equal(f.calls.at(-1).method, "configure");
    assert.equal(f.calls.at(-1).args[0].uid, "actor");
    assert.equal(f.calls.at(-1).args[1], id);
  }
});
test("Edge accepts bodyless activate and rejects malformed JSON and invalid UUID before mutation", async () => {
  const f = fixture();
  assert.equal(
    (await f.request(`/v1/businesses/${id}/activate`, "POST")).status,
    201,
  );
  assert.equal(
    (await f.request("/v1/businesses/invalid/activate", "POST")).status,
    422,
  );
  const bad = await f.handler(
    new Request("https://example.com/booking-api/v1/bookings", {
      method: "POST",
      headers: {
        authorization: "Bearer valid",
        "content-type": "application/json",
      },
      body: "{broken",
    }),
  );
  assert.equal(bad.status, 400);
  assert.equal(f.calls.length, 1);
});
test("Edge forwards split payments and rescheduling without changing command keys", async () => {
  const f = fixture(),
    body = {
      command_key: id,
      payments: [
        { method: "cash", amount_minor: 15000 },
        { method: "upi", amount_minor: 50000 },
      ],
    };
  assert.equal((await f.request("/v1/bookings", "POST", body)).status, 201);
  assert.deepEqual(f.calls[0].args[1], body);
  assert.equal(
    (
      await f.request(`/v1/bookings/${id}/reschedule`, "POST", {
        command_key: id,
        reason: "Requested",
      })
    ).status,
    201,
  );
  assert.equal(f.calls[1].method, "reschedule");
  assert.equal(f.calls[1].args[1], id);
});
test("Edge keeps safe typed errors and no-store headers", async () => {
  const f = fixture();
  f.setFailure(new ConflictException("Space already booked."));
  const response = await f.request("/v1/bookings", "POST", {}),
    body = await response.json();
  assert.equal(response.status, 409);
  assert.equal(body.code, "CONFLICT");
  assert.equal(body.message, "Space already booked.");
  assert.equal(response.headers.get("cache-control"), "private, no-store");
  assert.ok(body.request_id);
});
test("Edge public catalog works while unexpected origins and oversized bodies are rejected", async () => {
  const f = fixture();
  assert.equal(
    (await f.request("/v1/catalog", "GET", undefined, null)).status,
    200,
  );
  const rejected = await f.handler(
    new Request("https://example.com/booking-api/v1/workspace", {
      headers: {
        origin: "https://untrusted.example",
        authorization: "Bearer valid",
      },
    }),
  );
  assert.equal(rejected.status, 403);
  const large = await f.handler(
    new Request("https://example.com/booking-api/v1/bookings", {
      method: "POST",
      headers: {
        authorization: "Bearer valid",
        "content-type": "application/json",
        "content-length": "4000000",
      },
      body: "{}",
    }),
  );
  assert.equal(large.status, 413);
});
test("Edge preserves exact invitation-token validation", async () => {
  const f = fixture();
  assert.equal(
    (
      await f.request("/v1/invitations/accept", "POST", {
        token: "x".repeat(64),
      })
    ).status,
    422,
  );
  assert.equal(f.calls.length, 0);
  assert.equal(
    (
      await f.request("/v1/invitations/accept", "POST", {
        token: "a".repeat(64),
      })
    ).status,
    201,
  );
});

test("hosted invitation links redirect only a validated token into the mobile app", async () => {
  const f = fixture(),
    token = "a".repeat(64);
  const response = await f.request(
    `/invite?token=${token}`,
    "GET",
    undefined,
    null,
  );
  assert.equal(response.status, 302);
  assert.equal(
    response.headers.get("location"),
    `com.bookingos.app://invite/invite?token=${token}`,
  );
  assert.equal(response.headers.get("referrer-policy"), "no-referrer");
  assert.equal(
    (await f.request("/invite?token=invalid", "GET", undefined, null)).status,
    422,
  );
  assert.equal(f.calls.length, 0);
});

test("business reorder is routed through PUT in the Edge API", async () => {
  const f = fixture();
  const payload = { business_ids: [id], revision: 3 };
  const response = await f.request("/v1/businesses/order", "PUT", payload);
  assert.equal(response.status, 200);
  assert.equal(f.calls[0].method, "reorderBusinesses");
  assert.deepEqual(f.calls[0].args[1], payload);
});

test("Edge authenticates and dispatches customer directory and history routes", async () => {
  const f = fixture();
  assert.equal(
    (await f.request("/v1/bookings/customer-directory", "GET", undefined, null))
      .status,
    401,
  );
  assert.equal(
    (await f.request("/v1/bookings/customer-directory?q=98765")).status,
    200,
  );
  assert.equal(f.calls.at(-1).method, "customerDirectory");
  assert.equal(f.calls.at(-1).args[1].q, "98765");
  assert.equal(
    (await f.request(`/v1/bookings/customer-directory/${id}?cursor=next`))
      .status,
    200,
  );
  assert.equal(f.calls.at(-1).method, "customerHistory");
  assert.equal(f.calls.at(-1).args[1], id);
  assert.equal(f.calls.at(-1).args[2].cursor, "next");
  assert.equal(
    (await f.request("/v1/bookings/customer-directory/invalid")).status,
    422,
  );
});

test("public health exposes a revision for deployment verification without account data", async () => {
  const response = await fixture().request("/health", "GET", undefined, null);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    status: "ok",
    runtime: "supabase-edge",
    revision: "2026-10-20-customer-lookup-performance",
  });
});

test("Edge authenticates and dispatches message-template operations", async () => {
  const f = fixture();
  assert.equal(
    (await f.request("/v1/message-templates", "GET", undefined, null)).status,
    401,
  );
  assert.equal((await f.request("/v1/message-templates")).status, 200);
  assert.equal(f.calls.at(-1).method, "catalog");
  const body = {
    command_key: id,
    name: "Custom",
    body: "Hi {customer_name}",
    website_url: "",
  };
  assert.equal(
    (await f.request("/v1/message-templates", "POST", body)).status,
    201,
  );
  assert.equal(f.calls.at(-1).method, "create");
  assert.deepEqual(f.calls.at(-1).args[1], body);
  assert.equal(
    (await f.request("/v1/message-templates/primary", "PUT", { id: "default" }))
      .status,
    200,
  );
  assert.equal(f.calls.at(-1).method, "primary");
  assert.equal(
    (await f.request(`/v1/message-templates/${id}`, "DELETE")).status,
    200,
  );
  assert.equal(f.calls.at(-1).method, "remove");
  assert.equal(f.calls.at(-1).args[1], id);
});
