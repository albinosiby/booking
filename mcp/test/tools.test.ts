import { test } from "node:test";
import assert from "node:assert/strict";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { BookingClient, configFromEnv } from "../src/client.js";
import { registerTools } from "../src/tools.js";

const BOOKING = "11111111-1111-4111-8111-111111111111";
const selection = {
  business_id: "22222222-2222-4222-8222-222222222222",
  resource_id: "33333333-3333-4333-8333-333333333333",
  option_id: "football",
  date: "2030-06-04",
  time: "09:00",
  duration_minutes: 60,
  people: 1,
};
const TOKEN = "a".repeat(64);

type Call = { method: string; path: string; auth?: string; body?: any };

/** Fake Supabase Auth + booking-api. `routes` returns [status, body]. */
function fakeApi(
  routes: (call: Call) => [number, unknown] | undefined,
  calls: Call[] = [],
) {
  let issued = 0;
  const http = (async (input: string | URL, init: RequestInit = {}) => {
    const url = new URL(String(input));
    const headers = init.headers as Record<string, string>;
    const call: Call = {
      method: init.method ?? "GET",
      path: url.pathname.replace("/functions/v1/booking-api/v1", "") + url.search,
      auth: headers.authorization,
      body: init.body ? JSON.parse(String(init.body)) : undefined,
    };
    calls.push(call);
    if (url.pathname === "/auth/v1/token")
      return Response.json({
        access_token: `token-${++issued}`,
        refresh_token: "refresh",
        expires_in: 3600,
      });
    const [status, body] = routes(call) ?? [404, { message: "Not found" }];
    if (status === 0) throw new TypeError("fetch failed");
    return Response.json(body, { status });
  }) as typeof fetch;
  return { http, calls };
}

async function connect(http: typeof fetch) {
  const server = new McpServer({ name: "test", version: "0" });
  const config = configFromEnv({ BOOKING_EMAIL: "o@x.test", BOOKING_PASSWORD: "x" });
  registerTools(server, new BookingClient(config, http));
  const [a, b] = InMemoryTransport.createLinkedPair();
  const client = new Client({ name: "t", version: "0" });
  await Promise.all([server.connect(a), client.connect(b)]);
  return client;
}

const text = (r: any) => r.content[0].text as string;

test("lists the booking tools", async () => {
  const client = await connect(fakeApi(() => undefined).http);
  const { tools } = await client.listTools();
  assert.deepEqual(
    tools.map((t) => t.name).sort(),
    [
      "cancel_booking",
      "check_availability",
      "create_booking",
      "find_bookings",
      "get_booking",
      "list_bookable_options",
      "quote_booking",
      "reschedule_booking",
    ],
  );
});

test("requires credentials", () => {
  assert.throws(() => configFromEnv({}), /BOOKING_EMAIL/);
});

test("create_booking signs in, sends a command key and returns details", async () => {
  const { http, calls } = fakeApi((c) =>
    c.method === "POST" && c.path === "/bookings"
      ? [201, { id: BOOKING }]
      : c.path === `/bookings/${BOOKING}`
        ? [200, { id: BOOKING, version: 1, status: "confirmed" }]
        : undefined,
  );
  const client = await connect(http);
  const result = await client.callTool({
    name: "create_booking",
    arguments: {
      selection,
      quote_token: TOKEN,
      customer: { name: "Asha", phone: "+91 98765 43210" },
      payments: [{ method: "upi", amount_minor: 50000 }],
    },
  });
  assert.equal(result.isError, undefined);
  const post = calls.find((c) => c.path === "/bookings")!;
  assert.equal(post.auth, "Bearer token-1");
  assert.match(post.body.command_key, /^[0-9a-f-]{36}$/);
  assert.deepEqual(post.body.customer, {
    id: null,
    name: "Asha",
    phone: "+91 98765 43210",
    email: null,
  });
  assert.equal(post.body.notes, "");
  assert.equal(post.body.payments[0].reference, "");
  assert.ok(Date.parse(post.body.payments[0].received_at));
  assert.equal(JSON.parse(text(result)).booking.status, "confirmed");
});

test("cancel_booking posts a cancelled status with the version", async () => {
  const { http, calls } = fakeApi((c) =>
    c.path === `/bookings/${BOOKING}/status`
      ? [201, { id: BOOKING }]
      : c.path === `/bookings/${BOOKING}`
        ? [200, { id: BOOKING, version: 3, status: "cancelled" }]
        : undefined,
  );
  const client = await connect(http);
  await client.callTool({
    name: "cancel_booking",
    arguments: { booking_id: BOOKING, version: 2, reason: "Rain" },
  });
  const post = calls.find((c) => c.path.endsWith("/status"))!;
  assert.equal(post.body.status, "cancelled");
  assert.equal(post.body.version, 2);
  assert.equal(post.body.reason, "Rain");
});

test("reschedule_booking surfaces stale-version conflicts", async () => {
  const { http } = fakeApi((c) =>
    c.path.endsWith("/reschedule")
      ? [409, { code: "conflict", message: "Booking changed. Reload before rescheduling." }]
      : undefined,
  );
  const client = await connect(http);
  const result = await client.callTool({
    name: "reschedule_booking",
    arguments: {
      booking_id: BOOKING,
      version: 1,
      selection: { ...selection, time: "11:00" },
      quote_token: TOKEN,
      reason: "Customer asked",
    },
  });
  assert.equal(result.isError, true);
  assert.match(text(result), /Reload before rescheduling/);
});

test("recovers an uncertain write by its command key", async () => {
  const { http, calls } = fakeApi((c) =>
    c.path.endsWith("/status")
      ? [0, null]
      : c.path.startsWith("/bookings/commands/")
        ? [200, { id: BOOKING }]
        : c.path === `/bookings/${BOOKING}`
          ? [200, { id: BOOKING, status: "cancelled" }]
          : undefined,
  );
  const client = await connect(http);
  const result = await client.callTool({
    name: "cancel_booking",
    arguments: { booking_id: BOOKING, version: 1, reason: "Rain" },
  });
  assert.equal(result.isError, undefined);
  const key = calls.find((c) => c.path.endsWith("/status"))!.body.command_key;
  assert.ok(calls.some((c) => c.path === `/bookings/commands/${key}`));
});

test("reports the command key when an uncertain write cannot be recovered", async () => {
  const { http } = fakeApi((c) =>
    c.path.endsWith("/status")
      ? [503, { message: "Temporarily unavailable" }]
      : c.path.startsWith("/bookings/commands/")
        ? [200, { id: null }]
        : undefined,
  );
  const client = await connect(http);
  const result = await client.callTool({
    name: "cancel_booking",
    arguments: { booking_id: BOOKING, version: 1, reason: "Rain" },
  });
  assert.equal(result.isError, true);
  assert.match(text(result), /retry with the same command_key [0-9a-f-]{36}/);
});

test("refreshes the session once on 401", async () => {
  let first = true;
  const { http, calls } = fakeApi((c) => {
    if (c.path !== `/bookings/${BOOKING}`) return undefined;
    if (first) {
      first = false;
      return [401, { message: "Sign in to continue." }];
    }
    return [200, { id: BOOKING }];
  });
  const client = await connect(http);
  const result = await client.callTool({
    name: "get_booking",
    arguments: { booking_id: BOOKING },
  });
  assert.equal(result.isError, undefined);
  const gets = calls.filter((c) => c.path === `/bookings/${BOOKING}`);
  assert.deepEqual(
    gets.map((c) => c.auth),
    ["Bearer token-1", "Bearer token-2"],
  );
});

test("find_bookings passes filters and trims results", async () => {
  const { http, calls } = fakeApi((c) =>
    c.path.startsWith("/bookings?")
      ? [
          200,
          {
            items: [{ id: BOOKING, status: "confirmed", price_snapshot: { big: 1 } }],
            next_cursor: null,
          },
        ]
      : undefined,
  );
  const client = await connect(http);
  const result = await client.callTool({
    name: "find_bookings",
    arguments: { q: "Asha", date: "2030-06-04" },
  });
  assert.equal(calls.at(-1)!.path, "/bookings?q=Asha&date=2030-06-04");
  const data = JSON.parse(text(result));
  assert.equal(data.items[0].id, BOOKING);
  assert.equal(data.items[0].price_snapshot, undefined);
});
