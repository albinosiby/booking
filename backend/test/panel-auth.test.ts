import "reflect-metadata";
import { test } from "node:test";
import assert from "node:assert/strict";
import { signAdminRequest } from "../../admin-panel/lib/request-signature";
import {
  createSession,
  validSession,
} from "../../admin-panel/lib/session-token";
import { panelActor, isPanelActor } from "../src/admin/panel-auth";
import { AdminGuard } from "../src/admin/admin.guard";
import { createHandler } from "../edge/handler";

process.env.ADMIN_SESSION_SECRET = "test-only-panel-signing-secret-0123456789";

test("panel proof authenticates only its method, path, query and JSON payload", () => {
  const path = "/v1/admin/users?limit=20";
  const body = { active: false };
  const proof = signAdminRequest("PUT", path, JSON.stringify(body));
  const actor = panelActor(proof, "PUT", path, body);
  assert.ok(isPanelActor(actor));
  assert.equal(isPanelActor({ ...actor }), false);
  for (const [method, target, payload] of [
    ["POST", path, body],
    ["PUT", "/v1/admin/users?limit=21", body],
    ["PUT", path, { active: true }],
  ] as const)
    assert.throws(
      () => panelActor(proof, method, target, payload),
      /invalid or expired/,
    );
  assert.throws(
    () => panelActor(undefined, "GET", path, undefined),
    /invalid or expired/,
  );
  assert.throws(
    () => panelActor(proof + ".extra", "PUT", path, body),
    /invalid or expired/,
  );
  const expired = proof.replace(/^\d+/, String(Date.now() - 120000));
  assert.throws(
    () => panelActor(expired, "PUT", path, body),
    /invalid or expired/,
  );
});

test("Express admin guard accepts panel proof without a bearer user token", () => {
  const path = "/v1/admin/overview";
  const request = {
    method: "GET",
    originalUrl: path,
    headers: { "x-bookingos-admin": signAdminRequest("GET", path) },
    actor: undefined,
  };
  const context = { switchToHttp: () => ({ getRequest: () => request }) };
  assert.equal(new AdminGuard().canActivate(context as never), true);
  assert.ok(isPanelActor(request.actor!));
});

test("Edge panel requests bypass Supabase Auth only on admin routes", async () => {
  let authCalls = 0;
  let writes = 0;
  const handler = createHandler(
    {
      admin: {
        me: (actor: any) => ({ verified: isPanelActor(actor) }),
        setUserActive: (actor: any, id: string, body: any) => {
          assert.ok(isPanelActor(actor));
          writes++;
          return { id, ...body };
        },
      },
      workspace: { workspace: () => ({ ok: true }) },
    } as never,
    async () => {
      authCalls++;
      return { uid: "owner", email: "owner@example.com", name: "Owner" };
    },
    async () => {},
  );
  const request = (
    path: string,
    headers: Record<string, string> = {},
    method = "GET",
    body?: unknown,
  ) =>
    handler(
      new Request(`https://example.com/functions/v1/booking-api${path}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
      }),
    );
  const path = "/v1/admin/me";
  assert.equal((await request(path)).status, 401);
  assert.equal(
    (await request(path, { authorization: "Bearer owner-token" })).status,
    401,
  );
  const result = await request(path, {
    "x-bookingos-admin": signAdminRequest("GET", path),
  });
  assert.equal(result.status, 200);
  assert.deepEqual(await result.json(), { verified: true });
  const mutation =
    "/v1/admin/users/00000000-0000-4000-8000-000000000001/active";
  const body = { active: false };
  assert.equal(
    (
      await request(
        mutation,
        {
          "x-bookingos-admin": signAdminRequest(
            "PUT",
            mutation,
            JSON.stringify(body),
          ),
          "content-type": "application/json",
        },
        "PUT",
        body,
      )
    ).status,
    200,
  );
  assert.equal(writes, 1);
  assert.equal(authCalls, 0);
  assert.equal(
    (
      await request("/v1/workspace", {
        "x-bookingos-admin": signAdminRequest("GET", "/v1/workspace"),
      })
    ).status,
    401,
  );
  assert.equal(authCalls, 0);
  assert.equal(
    (await request("/v1/workspace", { authorization: "Bearer owner-token" }))
      .status,
    200,
  );
  assert.equal(authCalls, 1);
});

test("cookie sessions cannot serve as admin API signatures and malformed cookies fail closed", async () => {
  const cookie = await createSession();
  assert.equal(await validSession(cookie), true);
  assert.equal(await validSession(cookie + ".extra"), false);
  assert.equal(await validSession("NaN." + cookie.split(".")[1]), false);
  assert.throws(
    () => panelActor(cookie, "GET", "/v1/admin/me", undefined),
    /invalid or expired/,
  );
  assert.equal(
    await validSession(signAdminRequest("GET", "/v1/admin/me")),
    false,
  );
});

test("missing or short signing configuration fails closed without using the panel password", async () => {
  const secret = process.env.ADMIN_SESSION_SECRET;
  try {
    process.env.ADMIN_SESSION_SECRET = "";
    process.env.ADMIN_PANEL_PASSWORD = "tatos tech";
    assert.throws(() => signAdminRequest("GET", "/v1/admin/me"), /at least 32/);
    assert.throws(
      () => panelActor(undefined, "GET", "/v1/admin/me", undefined),
      /not configured/,
    );
    assert.equal(await validSession("invalid"), false);
    await assert.rejects(createSession(), /at least 32/);
  } finally {
    process.env.ADMIN_SESSION_SECRET = secret;
  }
});
