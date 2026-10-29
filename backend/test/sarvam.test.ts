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
    app_id: `Eden-${o.owner.uid}`,
    api_key: "sk_test_secret_1234",
  });
  const member = await workspace.member(o.owner, true);
  await db.query(
    "INSERT INTO agent_call_requests(id,organization_id,membership_id,status,approved_services) VALUES($1,$2,$3,'active',ARRAY['booking','rescheduling','enquiry','cancellation'])",
    [randomUUID(), member.organization_id, member.id],
  );
  await db.query(
    "UPDATE sarvam_integrations SET verified_at=now() WHERE organization_id=$1",
    [member.organization_id],
  );
  await db.query(
    "UPDATE staff_assignments a SET resource_ids=(SELECT jsonb_agg(r.id::text) FROM resources r WHERE r.business_id=a.business_id) WHERE a.membership_id=(SELECT membership_id FROM sarvam_integrations WHERE organization_id=$1)",
    [member.organization_id],
  );
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

function gate() {
  let release!: () => void;
  const pending = new Promise<void>((resolve) => (release = resolve));
  return { pending, release };
}

function pausedQuote() {
  const service = new BookingService(db, workspace);
  const quote = service.quote.bind(service);
  const entered = gate(),
    resume = gate();
  service.quote = async (...args) => {
    entered.release();
    await resume.pending;
    return quote(...args);
  };
  return { voice: new VoiceService(db, service), entered, resume };
}

/** Pause one voice read while the booking service keeps using the real DB. */
function pausedVoiceQuery(
  prefix: string,
  service = new BookingService(db, workspace),
) {
  const entered = gate(),
    resume = gate();
  const scoped = {
    async query<T = Record<string, unknown>>(sql: string, values?: unknown[]) {
      if (sql.startsWith(prefix)) {
        entered.release();
        await resume.pending;
      }
      return db.query<T>(sql, values);
    },
  } as unknown as Database;
  return { voice: new VoiceService(scoped, service), entered, resume };
}

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
  assert.equal(o.settings.connected, false);
  assert.equal(o.settings.setup_status, "legacy");
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
  await assert.rejects(voice.catalog(o.agent), /turned off/);
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
  assert.match(after.history.at(-1).details.reason, /call service: Rain/);
});

test("overlapping call requests recover the booking after its slot is reserved", async () => {
  const o = await connect();
  const request = {
    ...call,
    space: "Court 1",
    date: DATE,
    time: "19:00",
    customer_name: "Retry Caller",
    expected_total: 500,
  };
  const first = pausedQuote(),
    second = pausedQuote();
  const firstResult = first.voice.book(o.agent, request);
  await first.entered.pending;
  const secondResult = second.voice.book(o.agent, request);
  await second.entered.pending;
  first.resume.release();
  const winner = await firstResult;
  second.resume.release();
  const recovered = await secondResult;
  assert.equal(recovered.ok, true);
  assert.equal(recovered.reference, winner.reference);
  const rows = (await bookings.list(o.owner, {})).items;
  assert.equal(rows.length, 1);
  const detail = await bookings.detail(o.owner, rows[0].id);
  assert.equal(
    detail.history.filter((h: any) => h.action === "created").length,
    1,
  );
  assert.equal(
    (
      await db.query(
        "SELECT count(*)::int AS count FROM booking_commands WHERE actor_id=$1",
        [o.agent.uid],
      )
    ).rows[0].count,
    1,
  );
});

test(
  "overlapping bookings recover when the winner creates the reusable customer",
  { timeout: 15000 },
  async () => {
    const o = await connect();
    const request = {
      ...call,
      space: "Court 1",
      date: DATE,
      time: "19:00",
      customer_name: "Customer Race",
      expected_total: 500,
    };
    const first = pausedQuote();
    const service = new BookingService(db, workspace);
    const create = service.create.bind(service);
    let secondCustomerId: unknown,
      createFailure = "";
    service.create = async (...args) => {
      secondCustomerId = (args[1] as any).customer.id;
      try {
        return await create(...args);
      } catch (error) {
        createFailure = (error as Error).message;
        throw error;
      }
    };
    const second = pausedVoiceQuery("SELECT b.customer_id", service);
    const firstResult = first.voice.book(o.agent, request);
    await first.entered.pending;
    const secondResult = second.voice.book(o.agent, request);
    // Both initial command checks and the second quote saw a free slot.
    await second.entered.pending;
    first.resume.release();
    const winner = await firstResult;
    const row = (await bookings.list(o.owner, {})).items[0];
    second.resume.release();
    const recovered = await secondResult;
    assert.equal(secondCustomerId, row.customer_id);
    assert.match(
      createFailure,
      /request key belongs to different booking data/,
    );
    assert.equal(recovered.reference, winner.reference);
    assert.equal((await bookings.list(o.owner, {})).items.length, 1);
    const detail = await bookings.detail(o.owner, row.id);
    assert.equal(
      detail.history.filter((h: any) => h.action === "created").length,
      1,
    );
  },
);

test(
  "overlapping reschedules recover after the first move changes the version",
  { timeout: 15000 },
  async () => {
    const o = await connect();
    const booked = await voice.book(o.agent, {
      ...call,
      space: "Court 1",
      date: DATE,
      time: "19:00",
      customer_name: "Moving Caller",
      expected_total: 500,
    });
    const request = {
      ...call,
      reference: booked.reference,
      date: DATE,
      time: "20:00",
    };
    const first = pausedQuote();
    const service = new BookingService(db, workspace);
    const reschedule = service.reschedule.bind(service);
    let secondVersion: unknown,
      moveFailure = "";
    service.reschedule = async (...args) => {
      secondVersion = (args[2] as any).version;
      try {
        return await reschedule(...args);
      } catch (error) {
        moveFailure = (error as Error).message;
        throw error;
      }
    };
    const second = pausedVoiceQuery(
      "SELECT b.id FROM bookings b JOIN memberships",
      service,
    );
    const firstResult = first.voice.reschedule(o.agent, request);
    await first.entered.pending;
    const secondResult = second.voice.reschedule(o.agent, request);
    await second.entered.pending;
    first.resume.release();
    const winner = await firstResult;
    // The second ownership lookup and quote run after the winner commits.
    second.resume.release();
    const recovered = await secondResult;
    assert.equal(secondVersion, 2);
    assert.match(moveFailure, /request key belongs to different booking data/);
    assert.equal(recovered.reference, winner.reference);
    assert.equal(recovered.start_time, "20:00");
    const row = (await bookings.list(o.owner, {})).items[0];
    const detail = await bookings.detail(o.owner, row.id);
    assert.equal(detail.version, 2);
    assert.equal(
      detail.history.filter((h: any) => h.action === "rescheduled").length,
      1,
    );
  },
);

test(
  "overlapping cancellations recover after the booking leaves the upcoming list",
  { timeout: 15000 },
  async () => {
    const o = await connect();
    const booked = await voice.book(o.agent, {
      ...call,
      space: "Court 1",
      date: DATE,
      time: "19:00",
      customer_name: "Cancelling Caller",
      expected_total: 500,
    });
    const request = { ...call, reference: booked.reference, reason: "Rain" };
    const service = new BookingService(db, workspace);
    const status = service.status.bind(service);
    const statusEntered = gate(),
      statusResume = gate();
    service.status = async (...args) => {
      statusEntered.release();
      await statusResume.pending;
      return status(...args);
    };
    const first = new VoiceService(db, service);
    const second = pausedVoiceQuery(
      "SELECT b.id FROM bookings b JOIN memberships",
    );
    const firstResult = first.cancel(o.agent, request);
    await statusEntered.pending;
    const secondResult = second.voice.cancel(o.agent, request);
    await second.entered.pending;
    statusResume.release();
    const winner = await firstResult;
    second.resume.release();
    const recovered = await secondResult;
    assert.equal(recovered.reference, winner.reference);
    assert.equal(recovered.status, "cancelled");
    const row = (await bookings.list(o.owner, {})).items[0];
    const detail = await bookings.detail(o.owner, row.id);
    assert.equal(
      detail.history.filter((h: any) => h.action === "cancelled").length,
      1,
    );
  },
);

test(
  "recovery does not bypass a call service permission revoked during the request",
  { timeout: 15000 },
  async () => {
    const o = await connect();
    const request = {
      ...call,
      space: "Court 1",
      date: DATE,
      time: "19:00",
      customer_name: "Revoked Caller",
      expected_total: 500,
    };
    const first = pausedQuote(),
      second = pausedQuote();
    const firstResult = first.voice.book(o.agent, request);
    await first.entered.pending;
    const secondResult = second.voice.book(o.agent, request);
    await second.entered.pending;
    first.resume.release();
    await firstResult;
    await db.query(
      "UPDATE agent_call_requests SET approved_services=ARRAY['rescheduling'] WHERE organization_id=$1",
      [o.agent.uid.slice(7)],
    );
    const denied = assert.rejects(
      secondResult,
      /service is not enabled for phone calls/,
    );
    second.resume.release();
    await denied;
    const rows = (await bookings.list(o.owner, {})).items;
    assert.equal(rows.length, 1);
    assert.equal(rows[0].status, "confirmed");
  },
);

test("a different call, caller or missing interaction cannot recover an occupied booking", async () => {
  const o = await connect();
  const request = {
    ...call,
    space: "Court 1",
    date: DATE,
    time: "19:00",
    customer_name: "Original Caller",
    expected_total: 500,
  };
  const booked = await voice.book(o.agent, request);
  for (const changed of [
    { interaction_id: "another-interaction" },
    { caller_phone: "+91 90000 00000" },
    { interaction_id: "" },
  ]) {
    await assert.rejects(
      voice.book(o.agent, { ...request, ...changed }),
      /no longer available/,
    );
  }
  const rows = (await bookings.list(o.owner, {})).items;
  assert.equal(rows.length, 1);
  assert.equal(rows[0].reference, booked.reference);
});

test("replaying an original booking describes its current space and cancellation state", async () => {
  const o = await connect();
  const request = {
    ...call,
    space: "Court 1",
    date: DATE,
    time: "19:00",
    customer_name: "Current State Caller",
    expected_total: 500,
  };
  const booked = await voice.book(o.agent, request);
  const move = {
    ...call,
    reference: booked.reference,
    date: DATE,
    time: "20:00",
    space: "Court 2",
  };
  await voice.reschedule(o.agent, move);
  const replayed = await voice.book(o.agent, request);
  assert.equal(replayed.reference, booked.reference);
  assert.equal(replayed.start_time, "20:00");
  assert.match(replayed.message, /Court 2/);
  assert.doesNotMatch(replayed.message, /Court 1/);
  await voice.cancel(o.agent, {
    ...call,
    reference: booked.reference,
    reason: "Rain",
  });
  const afterCancellation = await voice.book(o.agent, request);
  assert.equal(afterCancellation.ok, false);
  assert.equal(afterCancellation.status, "cancelled");
  assert.match(afterCancellation.message, /currently cancelled/);
  assert.doesNotMatch(afterCancellation.message, /^Booked\./);
  const replayedMove = await voice.reschedule(o.agent, move);
  assert.equal(replayedMove.ok, false);
  assert.equal(replayedMove.status, "cancelled");
  const rows = (await bookings.list(o.owner, {})).items;
  assert.equal(rows.length, 1);
  const detail = await bookings.detail(o.owner, rows[0].id);
  assert.equal(
    detail.history.filter((h: any) => h.action === "created").length,
    1,
  );
});

test("a missing response after commit recovers the completed booking", async () => {
  const o = await connect();
  const service = new BookingService(db, workspace);
  const create = service.create.bind(service);
  service.create = async (...args) => {
    await create(...args);
    throw new Error("Response connection closed after commit");
  };
  const retrying = new VoiceService(db, service);
  const result = await retrying.book(o.agent, {
    ...call,
    space: "Court 1",
    date: DATE,
    time: "19:00",
    customer_name: "Recovered Response Caller",
    expected_total: 500,
  });
  assert.equal(result.ok, true);
  const rows = (await bookings.list(o.owner, {})).items;
  assert.equal(rows.length, 1);
  assert.equal(result.reference, rows[0].reference);
});

test("phone tools cannot list, reschedule or cancel bookings created by staff", async () => {
  const o = await connect();
  const created = await voice.book(o.agent, {
    ...call,
    space: "Court 1",
    date: DATE,
    time: "19:00",
    customer_name: "Phone Customer",
    expected_total: 500,
  });
  const original = (await bookings.list(o.owner, { q: created.reference }))
    .items[0];
  // Model the same customer and booking data entered by staff instead of by call.
  await db.query("UPDATE bookings SET created_by=$2 WHERE id=$1", [
    original.id,
    o.owner.uid,
  ]);
  const before = await bookings.detail(o.owner, original.id);
  assert.equal(
    (await voice.mine(o.agent, { caller_phone: call.caller_phone })).bookings
      .length,
    0,
  );
  await assert.rejects(
    voice.reschedule(o.agent, {
      ...call,
      reference: created.reference,
      date: DATE,
      time: "20:00",
    }),
    /Only bookings originally made by call/,
  );
  await assert.rejects(
    voice.cancel(o.agent, {
      ...call,
      reference: created.reference,
    }),
    /Only bookings originally made by call/,
  );
  // The underlying write transaction also enforces provenance for direct calls.
  const selection = { ...before.selection, date: DATE, time: "20:00" };
  const quote = await bookings.quote(o.owner, {
    selection,
    exclude_booking_id: before.id,
  });
  await assert.rejects(
    bookings.reschedule(o.agent, before.id, {
      command_key: randomUUID(),
      version: before.version,
      selection,
      quote_token: quote.quote_token,
      reason: "Move by phone",
    }),
    /Only bookings originally made by call/,
  );
  await assert.rejects(
    bookings.status(o.agent, before.id, {
      command_key: randomUUID(),
      version: before.version,
      status: "cancelled",
      reason: "Cancel by phone",
    }),
    /Only bookings originally made by call/,
  );
  const after = await bookings.detail(o.owner, before.id);
  assert.equal(after.version, before.version);
  assert.equal(after.status, "confirmed");
  assert.deepEqual(after.starts_at, before.starts_at);
  // Staff retain their existing ability to manage these bookings.
  await bookings.status(o.owner, before.id, {
    command_key: randomUUID(),
    version: before.version,
    status: "cancelled",
    reason: "Customer requested cancellation",
  });
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
      `https://apps.sarvam.ai/api/analytics/v1/org-1/ws-1/Eden-${o.owner.uid}/interactions?`,
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
  await assert.rejects(sarvam.test(o.owner), /connection needs attention/);
});
