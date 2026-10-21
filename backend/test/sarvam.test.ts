import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { CourtService } from "../src/court/court.service";
import { BookingService } from "../src/bookings/booking.service";
import {
  SarvamService,
  sealSecret,
  openSecret,
} from "../src/sarvam/sarvam.service";
import {
  VoiceService,
  parseTime,
  parseDate,
} from "../src/sarvam/voice.service";
import { voiceResult } from "../src/sarvam/voice-result";
import { Actor } from "../src/common/auth.guard";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
process.env.BOOKING_SECRETS_KEY = randomBytes(32).toString("base64");
const db = new Database(),
  workspace = new WorkspaceService(db),
  bookings = new BookingService(db, workspace),
  courts = new CourtService(db, workspace),
  sarvam = new SarvamService(db, workspace),
  voice = new VoiceService(db, bookings);
const DATE = "2030-06-04";
const hours = {
  days: [1, 2, 3, 4, 5, 6, 7],
  opens_at: "06:00",
  closes_at: "22:00",
  date_from: null,
  date_until: null,
};
const actor = (): Actor => {
  const uid = randomUUID();
  return { uid, email: `${uid}@example.com`, name: "Owner" };
};
async function organization() {
  const owner = actor();
  await workspace.createOrganization(owner, {
    name: "Eden",
    contact_phone: "9876543210",
    currency: "INR",
    location: {
      name: "Kochi",
      address_line_1: "Main Road",
      address_line_2: null,
      city: "Kochi",
      state_code: "KL",
      country_code: "IN",
      postal_code: "682001",
      timezone: "Asia/Kolkata",
    },
  });
  const w = await workspace.workspace(owner);
  const business = async (name: string) => {
    const b = await workspace.createBusiness(owner, {
      name,
      type: "badminton",
      location_id: w.locations[0].id,
    });
    await courts.configure(owner, b.id, {
      version: 1,
      configuration: {
        kind: "court_v1",
        schema_version: 1,
        courts: [1, 2].map((n) => ({
          id: randomUUID(),
          name: `Court ${n}`,
          enabled: true,
          environment: "indoor",
          surface: "",
          operating: hours,
          durations: [60],
          default_duration_minutes: 60,
          buffer_before: 0,
          buffer_after: 0,
          pricing_basis: "start_time",
          tariffs: [
            {
              id: randomUUID(),
              hours,
              rates: [{ duration_minutes: 60, price_minor: 50000 }],
            },
          ],
        })),
      },
    });
    await workspace.activate(owner, b.id);
    return b;
  };
  return {
    owner,
    booked: await business("Shuttle Arena"),
    hidden: await business("Other Arena"),
  };
}
/** Owner connects Sarvam and lets the agent book only `booked`. */
async function connect() {
  const o = await organization();
  const { tool_key } = await sarvam.rotateToolKey(o.owner);
  const settings = await sarvam.save(o.owner, {
    version: (await sarvam.settings(o.owner)).version,
    enabled: true,
    business_ids: [o.booked.id],
    sarvam_org_id: "org-1",
    workspace_id: "ws-1",
    app_id: "Edens-Sport-1",
    api_key: "sk_test_secret_1234",
  });
  return {
    ...o,
    tool_key,
    settings,
    agent: await sarvam.authenticateToolKey(tool_key),
  };
}
const call = {
  caller_phone: "+91 98470 12345",
  interaction_id: "20300603/a71c352f-11:03:08-e6013eb8",
};

before(async () => {
  await db.onModuleInit?.();
});
after(async () => {
  await db.onModuleDestroy?.();
});

test("parses spoken times and dates", () => {
  assert.equal(parseTime("7 pm"), "19:00");
  assert.equal(parseTime("7.30PM"), "19:30");
  assert.equal(parseTime("12 am"), "00:00");
  assert.equal(parseTime("18:00"), "18:00");
  assert.throws(() => parseTime("evening"));
  assert.equal(parseDate("tomorrow", "2030-12-31"), "2031-01-01");
  assert.equal(parseDate("2030-06-04", "2030-06-01"), "2030-06-04");
});

test("seals the Sarvam API key", () => {
  const sealed = sealSecret("sk_live_abc");
  assert.ok(!sealed.includes("sk_live_abc"));
  assert.equal(openSecret(sealed), "sk_live_abc");
});

test("settings are owner-only, hide the key and keep the agent out of Team", async () => {
  const o = await connect();
  assert.equal(o.settings.connected, true);
  assert.equal(o.settings.api_key_last4, "1234");
  assert.equal(JSON.stringify(o.settings).includes("sk_test_secret"), false);
  assert.match(o.settings.tool_base_url, /\/voice\/v1$/);
  assert.deepEqual(
    o.settings.businesses.filter((b: any) => b.assigned).map((b: any) => b.id),
    [o.booked.id],
  );
  const stored = (
    await db.query<any>(
      "SELECT api_key_ciphertext,tool_key_hash FROM sarvam_integrations",
    )
  ).rows;
  assert.ok(stored.every((r) => !r.api_key_ciphertext.includes("sk_test")));
  assert.ok(stored.every((r) => !r.tool_key_hash.startsWith("bkv_")));
  const team = await workspace.team(o.owner);
  assert.equal(
    team.members.some((m: any) => m.user_id.startsWith("sarvam:")),
    false,
  );
  // Stale version is rejected.
  await assert.rejects(
    sarvam.save(o.owner, {
      version: 1,
      enabled: true,
      business_ids: [o.booked.id],
      sarvam_org_id: "",
      workspace_id: "",
      app_id: "",
    }),
    /changed elsewhere/,
  );
});

test("rejects unknown, rotated and disabled tool keys", async () => {
  const o = await connect();
  await assert.rejects(sarvam.authenticateToolKey(null), /tool key/);
  await assert.rejects(
    sarvam.authenticateToolKey("bkv_" + "x".repeat(43)),
    /tool key/,
  );
  await sarvam.rotateToolKey(o.owner);
  await assert.rejects(sarvam.authenticateToolKey(o.tool_key), /tool key/);
  const { tool_key } = await sarvam.rotateToolKey(o.owner);
  const current = await sarvam.settings(o.owner);
  await sarvam.save(o.owner, {
    version: current.version,
    enabled: false,
    business_ids: [o.booked.id],
    sarvam_org_id: "",
    workspace_id: "",
    app_id: "",
  });
  await assert.rejects(sarvam.authenticateToolKey(tool_key), /turned off/);
  // The membership is inactive too, so old actors cannot keep booking.
  await assert.rejects(voice.catalog(o.agent), /membership/);
});

test("books, lists, reschedules and cancels a caller's booking", async () => {
  const o = await connect();
  const catalog = await voice.catalog(o.agent);
  assert.deepEqual(
    catalog.businesses.map((b: any) => b.name),
    ["Shuttle Arena"],
  );

  const ambiguous = await voiceResult(() =>
    voice.availability(o.agent, { space: "Court", date: DATE }),
  );
  assert.deepEqual(ambiguous, {
    ok: false,
    message: "Which one: Court 1 (Shuttle Arena), Court 2 (Shuttle Arena)?",
  });
  const slots = await voice.availability(o.agent, {
    space: "court 1",
    date: DATE,
    preferred_time: "7 pm",
  });
  assert.match(slots.message, /^7 PM is available\./);
  assert.equal(slots.slots.find((s) => s.time === "19:00")?.total, "₹500");

  const request = {
    ...call,
    space: "Court 1",
    date: DATE,
    time: "7 pm",
    customer_name: "Ebin Thomas",
    expected_total: 500,
  };
  const booked = await voice.book(o.agent, request);
  assert.equal(booked.ok, true);
  assert.match(booked.message, /^Booked\. Your booking reference is B K - /);
  assert.equal(booked.start_time, "19:00");
  assert.equal(booked.balance_due, "₹500");
  // A Sarvam retry of the same call returns the same booking.
  assert.equal(
    (await voice.book(o.agent, request)).reference,
    booked.reference,
  );
  const detail = (await bookings.list(o.owner, { q: booked.reference }))
    .items[0];
  assert.equal(detail.created_by, o.agent.uid);
  assert.equal(detail.customer_snapshot.phone, "+919847012345");

  const taken = await voiceResult(() =>
    voice.book(o.agent, {
      ...request,
      interaction_id: "other-call",
      customer_name: "Asha",
    }),
  );
  assert.equal((taken as any).ok, false);

  const mine = await voice.mine(o.agent, { caller_phone: "09847012345" });
  assert.deepEqual(
    mine.bookings.map((b) => b.reference),
    [booked.reference],
  );
  const strangers = await voice.mine(o.agent, {
    caller_phone: "+91 90000 00000",
  });
  assert.equal(strangers.bookings.length, 0);

  const notYours = await voiceResult(() =>
    voice.cancel(o.agent, {
      reference: booked.reference,
      caller_phone: "+91 90000 00000",
    }),
  );
  assert.equal((notYours as any).ok, false);
  const noPhone = await voiceResult(() =>
    voice.cancel(o.agent, { reference: booked.reference, caller_phone: "" }),
  );
  assert.match((noPhone as any).message, /phone number used to book/);

  const moved = await voice.reschedule(o.agent, {
    ...call,
    reference: booked.reference.toLowerCase(),
    date: DATE,
    time: "20:00",
  });
  assert.equal(moved.start_time, "20:00");
  assert.match(moved.message, /^Done\. Booking/);

  // Retrying the same reschedule after it committed replays its result.
  assert.equal(
    (
      await voice.reschedule(o.agent, {
        ...call,
        reference: booked.reference.toLowerCase(),
        date: DATE,
        time: "20:00",
      })
    ).start_time,
    "20:00",
  );
  const cancel = { ...call, reference: booked.reference, reason: "Rain" };
  const cancelled = await voice.cancel(o.agent, cancel);
  assert.equal(cancelled.status, "cancelled");
  assert.equal((await voice.cancel(o.agent, cancel)).status, "cancelled");
  const after = await bookings.detail(o.owner, detail.id);
  assert.equal(after.status, "cancelled");
  assert.match(after.history.at(-1).details.reason, /Sarvam voice agent: Rain/);
});

test("voice agent cannot reach unassigned businesses", async () => {
  const o = await connect();
  const result = await voiceResult(() =>
    voice.availability(o.agent, {
      business: "Other Arena",
      space: "Court 1",
      date: DATE,
    }),
  );
  assert.equal((result as any).ok, false);
  assert.match((result as any).message, /could not find that space/);
});

test("proxies Sarvam call logs with the stored key", async () => {
  const o = await connect();
  const seen: { url: string; key: string }[] = [];
  sarvam.http = (async (input: string | URL, init?: RequestInit) => {
    const url = String(input);
    seen.push({
      url,
      key: (init?.headers as Record<string, string>)["X-API-Key"],
    });
    if (url.includes("/interactions"))
      return Response.json({
        items: [
          {
            interaction_id: call.interaction_id,
            start_datetime: "2030-06-03 05:33:08",
            duration_in_seconds: 137.5,
            language_name: "Malayalam",
            channel_direction: "inbound",
            user_contact: "+919847012345",
            num_messages: 21,
            agent_variables: {
              call_summary: "Booked court",
              user_name: "Ebin",
            },
          },
        ],
        total: 1,
        limit: 20,
        offset: 0,
      });
    if (url.includes("/transcripts/"))
      return Response.json({
        messages: [
          {
            turn_id: 1,
            role: "assistant",
            content: "Hi",
            language_name: "English",
          },
        ],
      });
    return new Response(new Uint8Array([82, 73, 70, 70]), {
      headers: { "content-type": "audio/wav" },
    });
  }) as typeof fetch;
  const calls = await sarvam.calls(o.owner, {
    start: "2030-06-03T00:00:00Z",
    end: "2030-06-04T00:00:00Z",
  });
  assert.equal(calls.items[0].summary, "Booked court");
  assert.equal(calls.items[0].contact, "+919847012345");
  assert.ok(
    seen[0].url.startsWith(
      "https://apps.sarvam.ai/api/analytics/v1/org-1/ws-1/Edens-Sport-1/interactions?",
    ),
  );
  assert.equal(seen[0].key, "sk_test_secret_1234");
  const transcript = await sarvam.transcript(o.owner, call.interaction_id);
  assert.deepEqual(transcript.messages[0], {
    turn: 1,
    role: "agent",
    text: "Hi",
    language: "English",
  });
  assert.ok(seen[1].url.endsWith(`/transcripts/${call.interaction_id}`));
  assert.equal(
    (await sarvam.recording(o.owner, call.interaction_id)).data.length,
    4,
  );
  await assert.rejects(sarvam.transcript(o.owner, "../../other"));
  await assert.rejects(
    sarvam.calls(o.owner, {
      start: "2030-01-01T00:00:00Z",
      end: "2030-06-01T00:00:00Z",
    }),
    /31 days/,
  );
  sarvam.http = async () => new Response("{}", { status: 401 });
  await assert.rejects(sarvam.test(o.owner), /rejected the API key/);
});
