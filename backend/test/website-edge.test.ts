import { test } from "node:test";
import assert from "node:assert/strict";
import { createHandler } from "../edge/handler";
function fixture() {
  const calls: { method: string; args: unknown[] }[] = [],
    website = new Proxy(
      {},
      {
        get:
          (_, method) =>
          async (...args: unknown[]) => {
            calls.push({ method: String(method), args });
            if (["image", "ownerImage"].includes(String(method)))
              return {
                data: Buffer.from([1, 2, 3]),
                content_type: "image/png",
              };
            return { ok: true };
          },
      },
    );
  let authentications = 0;
  const handler = createHandler(
    { website } as never,
    async () => {
      authentications++;
      return { uid: "owner", email: "owner@example.com", name: "Owner" };
    },
    async () => {},
  );
  const request = (
    path: string,
    method = "GET",
    body?: unknown,
    token?: string,
  ) =>
    handler(
      new Request(`https://example.com/functions/v1/booking-api${path}`, {
        method,
        headers: {
          ...(token ? { authorization: `Bearer ${token}` } : {}),
          ...(body === undefined ? {} : { "Content-Type": "application/json" }),
        },
        body: body === undefined ? undefined : JSON.stringify(body),
      }),
    );
  return { request, calls, authentications: () => authentications };
}
test("public website routes dispatch without granting access to authenticated booking routes", async () => {
  const f = fixture();
  assert.equal((await f.request("/public/v1/sites/eden-sports")).status, 200);
  assert.equal(f.calls[0].method, "catalog");
  assert.equal(f.calls[0].args[0], "eden-sports");
  for (const operation of ["availability", "quote", "bookings"]) {
    const response = await f.request(
      `/public/v1/sites/eden-sports/${operation}`,
      "POST",
      { selection: {} },
    );
    assert.equal(response.status, operation === "bookings" ? 201 : 200);
  }
  assert.equal(f.authentications(), 0);
  assert.equal((await f.request("/v1/bookings")).status, 401);
  assert.equal((await f.request("/v1/booking-website")).status, 401);
});
test("owner website routes authenticate, and preview capability is limited to the public service", async () => {
  const f = fixture(),
    token = "a".repeat(64);
  await f.request(`/public/v1/sites/eden-sports?preview=${token}`);
  assert.equal(f.calls.at(-1)?.args[1], token);
  await f.request(
    "/v1/booking-website/publish",
    "POST",
    { version: 2 },
    "valid",
  );
  assert.equal(f.authentications(), 1);
  assert.equal(f.calls.at(-1)?.method, "publication");
  assert.equal(f.calls.at(-1)?.args[1], "published");
  assert.equal(
    (await f.request("/public/v1/sites/eden-sports/customer-directory")).status,
    404,
  );
  assert.equal(
    (await f.request("/public/v1/sites/eden-sports/bookings", "GET")).status,
    404,
  );
  assert.equal(
    (
      await f.request("/public/v1/sites/eden-sports/bookings", "POST", {
        data: "x".repeat(16385),
      })
    ).status,
    413,
  );
});

test("website photos have separate authenticated mutation and public read routes", async () => {
  const f = fixture(),
    id = "12345678-1234-4123-8123-123456789abc";
  const response = await f.request(`/public/v1/sites/eden-sports/images/${id}`);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("Content-Type"), "image/png");
  assert.match(response.headers.get("Cache-Control")!, /no-store/);
  assert.equal(f.calls.at(-1)?.method, "image");
  assert.equal(f.authentications(), 0);
  assert.equal(
    (await f.request("/v1/booking-website/images", "POST", {})).status,
    401,
  );
  await f.request("/v1/booking-website/images", "POST", {}, "valid");
  assert.equal(f.calls.at(-1)?.method, "uploadImage");
  await f.request(
    `/v1/booking-website/images/${id}/remove`,
    "POST",
    { version: 2 },
    "valid",
  );
  assert.equal(f.calls.at(-1)?.method, "removeImage");
  assert.equal(
    (await f.request(`/public/v1/sites/eden-sports/images/${id}`, "POST", {}))
      .status,
    404,
  );
});
