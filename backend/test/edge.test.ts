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
    notifications: service,
    workspace: service,
    admissions: service,
    messages: service,
    bookings: service,
    blocks: service,
    accounts: service,
    expenses: service,
    income: service,
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
test("Edge routes income endpoints with the actor, query and category ID", async () => {
  const f = fixture();
  assert.equal(
    (await f.request("/v1/income/overview?from=2030-01-01&until=2030-01-31"))
      .status,
    200,
  );
  assert.equal(f.calls.at(-1).method, "overview");
  assert.equal(f.calls.at(-1).args[1].from, "2030-01-01");
  await f.request(`/v1/income/categories/${id}`, "PATCH", { name: "Events" });
  assert.equal(f.calls.at(-1).method, "category");
  assert.equal(f.calls.at(-1).args[2], id);
  assert.equal(
    (await f.request("/v1/income", "GET", undefined, null)).status,
    401,
  );
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
for (const transitioning of [false, true]) {
  test(`hosted web CORS preserves existing origins and authentication (transition=${transitioning})`, async () => {
    const previousOrigins = process.env.BOOKING_CORS_ORIGINS;
    const previousWeb = process.env.BOOKING_WEB_ORIGIN;
    const web = "https://booking-production-8e79.up.railway.app";
    const custom = "https://bookingos.online";
    process.env.BOOKING_CORS_ORIGINS =
      " https://existing.example , http://localhost:8080 ";
    process.env.BOOKING_WEB_ORIGIN = transitioning
      ? ` ${custom}, ${web}, `
      : web;
    try {
      const f = fixture();
      const send = (origin: string, method = "OPTIONS", token?: string) =>
        f.handler(
          new Request("https://example.com/booking-api/v1/workspace", {
            method,
            headers: {
              origin,
              "access-control-request-method": "GET",
              "access-control-request-headers":
                "apikey,authorization,content-type",
              ...(token ? { authorization: `Bearer ${token}` } : {}),
            },
          }),
        );
      for (const origin of [
        web,
        ...(transitioning ? [custom] : []),
        "https://existing.example",
        "http://localhost:8080",
      ]) {
        const response = await send(origin);
        assert.equal(response.status, 204);
        assert.equal(
          response.headers.get("access-control-allow-origin"),
          origin,
        );
        assert.match(
          response.headers.get("access-control-allow-headers") ?? "",
          /authorization/,
        );
        assert.match(
          response.headers.get("access-control-allow-headers") ?? "",
          /apikey/,
        );
        assert.equal(response.headers.get("vary"), "Origin");
      }
      assert.equal(f.calls.length, 0);
      const unsigned = await send(web, "GET");
      assert.equal(unsigned.status, 401);
      assert.equal(unsigned.headers.get("access-control-allow-origin"), web);
      assert.equal((await send(web, "GET", "valid")).status, 200);
      if (transitioning) {
        assert.equal((await send(custom, "GET")).status, 401);
        assert.equal((await send(custom, "GET", "valid")).status, 200);
      }
      for (const origin of [
        web + ".untrusted.example",
        custom + ".untrusted.example",
        "https://untrusted.example",
      ]) {
        const rejected = await send(origin);
        assert.equal(rejected.status, 403);
        assert.equal(rejected.headers.get("access-control-allow-origin"), null);
      }
    } finally {
      if (previousOrigins === undefined)
        delete process.env.BOOKING_CORS_ORIGINS;
      else process.env.BOOKING_CORS_ORIGINS = previousOrigins;
      if (previousWeb === undefined) delete process.env.BOOKING_WEB_ORIGIN;
      else process.env.BOOKING_WEB_ORIGIN = previousWeb;
    }
  });
}

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
    revision: "2026-10-22-sarvam-automatic-setup",
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

test("Edge accepts streamed empty activation bodies but requires JSON for non-empty bodies", async () => {
  const f = fixture();
  for (const content of ["", new Uint8Array(0)]) {
    const response = await f.handler(
      new Request(
        `https://example.com/booking-api/v1/businesses/${id}/activate`,
        {
          method: "POST",
          headers: { authorization: "Bearer valid" },
          body: content,
        },
      ),
    );
    assert.equal(response.status, 201);
    assert.equal(f.calls.at(-1).method, "activate");
  }
  const count = f.calls.length;
  for (const content of ["not-json", "{}"]) {
    const response = await f.handler(
      new Request(
        `https://example.com/booking-api/v1/businesses/${id}/activate`,
        {
          method: "POST",
          headers: {
            authorization: "Bearer valid",
            "content-type": "text/plain",
          },
          body: content,
        },
      ),
    );
    assert.equal(response.status, 415);
  }
  assert.equal(f.calls.length, count);
  assert.equal(
    (await f.request(`/v1/businesses/${id}/activate`, "POST", {})).status,
    201,
  );
});

test("Edge authenticates admission, renewal, attendance and payment routes", async () => {
  const f = fixture();
  for (const path of [
    "/v1/admissions",
    "/v1/admissions/catalog",
    `/v1/admissions/${id}`,
  ])
    assert.equal((await f.request(path, "GET", undefined, null)).status, 401);
  await f.request("/v1/admissions/preview", "POST", { mode: "fixed" });
  assert.equal(f.calls.at(-1).method, "preview");
  await f.request(`/v1/admissions/${id}/sessions/${id}/attendance`, "POST", {
    attendance: "present",
  });
  assert.equal(f.calls.at(-1).method, "attendance");
  assert.equal(f.calls.at(-1).args[2], id);
  await f.request(`/v1/admissions/${id}/sessions/${id}/change`, "POST", {
    action: "reschedule",
  });
  assert.equal(f.calls.at(-1).method, "sessionChange");
  await f.request(`/v1/admissions/${id}/payments`, "POST", {
    kind: "collection",
  });
  assert.equal(f.calls.at(-1).method, "payments");
});
test("Edge authenticates and dispatches block list, create and unblock routes", async () => {
  const f = fixture();
  assert.equal(
    (await f.request("/v1/booking-blocks", "GET", undefined, null)).status,
    401,
  );
  assert.equal(
    (await f.request(`/v1/booking-blocks?business_id=${id}&date=2030-06-04`))
      .status,
    200,
  );
  assert.equal(f.calls.at(-1).method, "list");
  assert.equal(
    (
      await f.request(
        `/v1/booking-blocks/slots?business_id=${id}&date=2030-06-04&resource_ids=${id}`,
      )
    ).status,
    200,
  );
  assert.equal(f.calls.at(-1).method, "slots");
  assert.equal(
    (await f.request("/v1/booking-blocks", "POST", { business_id: id })).status,
    201,
  );
  assert.equal(f.calls.at(-1).method, "create");
  assert.equal(
    (await f.request(`/v1/booking-blocks/${id}/unblock`, "POST", {})).status,
    201,
  );
  assert.equal(f.calls.at(-1).method, "unblock");
});
test("Edge exposes non-sensitive server timing for performance diagnosis", async () => {
  const f = fixture();
  const result = await f.request("/v1/workspace");
  assert.match(
    result.headers.get("server-timing") ?? "",
    /^app;dur=\d+\.\d+, auth;dur=\d+\.\d+$/,
  );
});

test("Edge routes Sarvam voice tools by tool key and speaks refusals", async () => {
  const { BadRequestException, UnauthorizedException } =
    await import("@nestjs/common");
  const voiceCalls: any[] = [];
  const handler = createHandler(
    {
      sarvam: {
        authenticateToolKey: async (key: string | null) => {
          if (key !== "bkv_good")
            throw new UnauthorizedException(
              "A valid voice tool key is required.",
            );
          return { uid: "sarvam:org", email: "v@x", name: "Voice" };
        },
      },
      voice: {
        book: async (actor: any, body: any) => {
          voiceCalls.push({ actor, body });
          if (body.time === "taken")
            throw new BadRequestException("That slot is taken.");
          return { ok: true, reference: "BK-1" };
        },
      },
    } as any,
    async () => {
      throw new Error("user auth must not run for voice tools");
    },
    async () => {},
  );
  const call = (key: string | null, data: unknown) =>
    handler(
      new Request(
        "https://example.com/functions/v1/booking-api/voice/v1/bookings",
        {
          method: "POST",
          headers: {
            "content-type": "application/json",
            ...(key ? { "x-api-key": key } : {}),
          },
          body: JSON.stringify(data),
        },
      ),
    );
  assert.equal((await call(null, {})).status, 401);
  assert.equal((await call("bkv_bad", {})).status, 401);
  assert.equal(voiceCalls.length, 0);
  const ok = await call("bkv_good", { time: "19:00" });
  assert.equal(ok.status, 200);
  assert.deepEqual(await ok.json(), { ok: true, reference: "BK-1" });
  assert.equal(voiceCalls[0].actor.uid, "sarvam:org");
  const refused = await call("bkv_good", { time: "taken" });
  assert.equal(refused.status, 200);
  assert.deepEqual(await refused.json(), {
    ok: false,
    message: "That slot is taken.",
  });
});

test("Edge device registration verifies user auth; cleanup uses only installation proof", async () => {
  const f = fixture();
  assert.equal(
    (await f.request("/v1/notifications/devices", "POST", {}, null)).status,
    401,
  );
  assert.equal(f.calls.length, 0);
  assert.equal(
    (await f.request("/v1/notifications/devices", "POST", { token: "device" }))
      .status,
    201,
  );
  assert.equal(f.calls.at(-1).method, "register");
  assert.equal(f.calls.at(-1).args[0].uid, "actor");
  assert.equal(
    (
      await f.request(
        "/v1/notifications/installations/revoke",
        "POST",
        { installation_id: id, installation_secret: "a".repeat(64) },
        null,
      )
    ).status,
    200,
  );
  assert.equal(f.calls.at(-1).method, "revokeInstallation");
});
