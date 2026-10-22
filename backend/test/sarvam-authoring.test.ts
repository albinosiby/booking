import { test } from "node:test";
import assert from "node:assert/strict";
import { SarvamAuthoring, MCP } from "../src/sarvam/sarvam-authoring";

test("MCP session headers and fragmented SSE readback are supported", async () => {
  const seen: string[] = [];
  const http: typeof fetch = async (url, init) => {
    assert.equal(String(url), MCP);
    const request = JSON.parse(String(init?.body));
    const headers = new Headers(init?.headers);
    assert.equal(headers.get("authorization"), "Bearer oauth-private");
    seen.push(request.method);
    if (request.method === "initialize")
      return new Response(
        JSON.stringify({
          id: request.id,
          result: { protocolVersion: "2025-03-26" },
        }),
        {
          headers: {
            "Content-Type": "application/json",
            "Mcp-Session-Id": "session-1",
          },
        },
      );
    assert.equal(headers.get("mcp-session-id"), "session-1");
    if (request.method === "notifications/initialized")
      return new Response(null, { status: 202 });
    const event =
      "data: " +
      JSON.stringify({
        id: request.id,
        result: { content: [{ type: "text", text: '{"id":"saved-tool"}' }] },
      }) +
      "\r\n\r\n";
    const encoder = new TextEncoder();
    return new Response(
      new ReadableStream({
        start(controller) {
          controller.enqueue(encoder.encode(event.slice(0, -3)));
          controller.enqueue(encoder.encode(event.slice(-3)));
          controller.close();
        },
      }),
      { headers: { "Content-Type": "text/event-stream" } },
    );
  };
  assert.equal(
    (
      await new SarvamAuthoring(http, "oauth-private").call(
        "configure_secret",
        { name: "test", value: "private-tool-key" },
      )
    ).id,
    "saved-tool",
  );
  assert.deepEqual(seen, [
    "initialize",
    "notifications/initialized",
    "tools/call",
  ]);
});

test("MCP errors and partially applied configurations do not succeed or leak provider text", async () => {
  for (const result of [
    {
      isError: true,
      content: [{ type: "text", text: "credential: private-tool-key" }],
    },
    { structuredContent: { not_applied: [{ path: "private-tool-key" }] } },
  ]) {
    const http: typeof fetch = async (_url, init) => {
      const request = JSON.parse(String(init?.body));
      if (request.method === "notifications/initialized")
        return new Response(null, { status: 202 });
      return new Response(
        JSON.stringify({
          id: request.id,
          result: request.method === "initialize" ? {} : result,
        }),
        { headers: { "Content-Type": "application/json" } },
      );
    };
    await assert.rejects(
      new SarvamAuthoring(http, "token").call("configure_agent", {}),
      (error: Error) => !error.message.includes("private-tool-key"),
    );
  }
});

test("registration reports the exact callback approval requirement without echoing provider details", async () => {
  const redirect = "https://booking.example.test/v1/sarvam/oauth/callback";
  let attempts = 0;
  const http: typeof fetch = async (url, init) => {
    attempts++;
    assert.equal(String(url), `${MCP}/register`);
    const request = JSON.parse(String(init?.body));
    assert.deepEqual(request.redirect_uris, [redirect]);
    assert.deepEqual(request.grant_types, ["authorization_code"]);
    return new Response(
      JSON.stringify({
        error: "invalid_redirect_uri",
        error_description: "untrusted private-token must not leak",
      }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  };
  await assert.rejects(
    new SarvamAuthoring(http).register(redirect),
    (error: Error) => {
      assert.match(error.message, /Sarvam has not approved/);
      assert.ok(error.message.includes(redirect));
      assert.ok(!error.message.includes("private-token"));
      assert.ok(!error.message.includes("permissions"));
      return true;
    },
  );
  assert.equal(attempts, 1);
});

test("other registration rejections do not expose response bodies or suggest a permission fix", async () => {
  const http: typeof fetch = async () =>
    new Response(
      JSON.stringify({
        error: "invalid_client_metadata",
        error_description: "secret-value",
      }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  await assert.rejects(
    new SarvamAuthoring(http).register("https://booking.example.test/callback"),
    (error: Error) => {
      assert.match(error.message, /OAuth client registration/);
      assert.ok(!error.message.includes("secret-value"));
      assert.ok(!error.message.includes("permissions"));
      return true;
    },
  );
});

test("an expired authorization code requests fresh sign-in without leaking the code", async () => {
  const http: typeof fetch = async () =>
    new Response(
      JSON.stringify({
        error: "invalid_grant",
        error_description: "code: private-code",
      }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  await assert.rejects(
    new SarvamAuthoring(http).exchange({ code: "private-code" }),
    (error: Error) => {
      assert.match(error.message, /Press Connect/);
      assert.ok(!error.message.includes("private-code"));
      return true;
    },
  );
});
