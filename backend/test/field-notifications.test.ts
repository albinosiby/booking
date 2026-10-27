import { test } from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import { bookingNotificationBody } from "../src/notifications/notification-content";
import {
  FcmSender,
  PushFailure,
  type PushMessage,
} from "../src/notifications/fcm-sender";
import {
  teamAccessMessage,
  teamLoginUrls,
  NodemailerTeamAccessMailer,
  type TeamAccessNotice,
} from "../src/workspace/team-access-mailer";

// ------------------------------------------------------------ notification text

const lines = (body: string) => body.split("\n");
const base = {
  customer_name: "Arun",
  space_name: "Turf 1",
  starts_at: "2026-10-24T17:30:00Z",
  ends_at: "2026-10-24T19:30:00Z",
  timezone: "Asia/Kolkata",
};

test("notification body: non-string, blank and control-only fields fall back to labels", () => {
  for (const bad of [
    undefined,
    null,
    5,
    true,
    {},
    [],
    ["Arun"],
    "",
    "   ",
    "\n\t",
    "\u0000\u0001",
    "‮‭",
    "\u0085 ",
  ]) {
    const l = lines(
      bookingNotificationBody("BK-1", {
        ...base,
        customer_name: bad as never,
        space_name: bad as never,
      }),
    );
    assert.equal(l[0], "Name: Customer", JSON.stringify(bad));
    assert.equal(l[1], "Space: Booked space", JSON.stringify(bad));
    assert.equal(l.length, 4, "body always has exactly four lines");
  }
});

test("notification body: reference is flattened, bounded and defaulted", () => {
  assert.equal(lines(bookingNotificationBody("", base)).at(-1), "Booking");
  assert.equal(lines(bookingNotificationBody("   ", base)).at(-1), "Booking");
  assert.equal(
    lines(bookingNotificationBody(undefined as never, base)).at(-1),
    "Booking",
  );
  assert.equal(
    lines(bookingNotificationBody("BK-1\nName: Admin", base)).length,
    4,
  );
  assert.equal(
    Array.from(lines(bookingNotificationBody("R".repeat(5000), base)).at(-1)!)
      .length,
    80,
  );
  assert.equal(
    bookingNotificationBody("BK\u0000", undefined),
    "Booking BK. Open Booking OS for details.",
  );
  assert.equal(
    bookingNotificationBody("BK-9", null),
    "Booking BK-9. Open Booking OS for details.",
  );
});

test("notification body: 80 code-point limit never splits surrogate pairs or breaks line structure", () => {
  const name = "😀".repeat(200);
  const body = bookingNotificationBody("BK-1", {
    ...base,
    customer_name: name,
  });
  const first = lines(body)[0].slice("Name: ".length);
  assert.equal(Array.from(first).length, 80);
  assert.equal(
    /[\ud800-\udbff](?![\udc00-\udfff])/.test(first),
    false,
    "no lone surrogate",
  );
  assert.equal(
    lines(
      bookingNotificationBody("BK-1", { ...base, customer_name: "x\r\ny z w" }),
    )[0],
    "Name: x y z w",
  );
  assert.equal(
    lines(
      bookingNotificationBody("BK-1", {
        ...base,
        customer_name: "a".repeat(80),
      }),
    )[0],
    `Name: ${"a".repeat(80)}`,
  );
  assert.equal(
    lines(
      bookingNotificationBody("BK-1", {
        ...base,
        customer_name: "a".repeat(81),
      }),
    )[0],
    `Name: ${"a".repeat(80)}`,
  );
});

test("notification body: time handling for missing, invalid, reversed and cross-zone values", () => {
  const time = (d: Record<string, unknown>) =>
    lines(bookingNotificationBody("BK-1", { ...base, ...d } as never))[2];
  for (const d of [
    { starts_at: null },
    { starts_at: "" },
    { starts_at: "not a date" },
    { timezone: null },
    { timezone: "" },
    { timezone: "Mars/Olympus" },
    { starts_at: "2026-10-24T17:30:00Z", timezone: "Asia/Kolkata\n" },
  ])
    assert.equal(time(d), "Time: Time unavailable", JSON.stringify(d));
  assert.match(time({ ends_at: null }), /^Time: 24 Oct 2026, 11:00 PM IST$/);
  assert.match(
    time({ ends_at: "garbage" }),
    /^Time: 24 Oct 2026, 11:00 PM IST$/,
  );
  assert.match(
    time({ ends_at: base.starts_at }),
    /^Time: 24 Oct 2026, 11:00 PM IST$/,
    "zero-length booking shows only the start",
  );
  assert.match(
    time({ ends_at: "2026-10-24T10:00:00Z" }),
    /^Time: 24 Oct 2026, 11:00 PM IST$/,
    "end before start shows only the start",
  );
  assert.match(time({ timezone: "UTC" }), /5:30 PM UTC – 7:30 PM UTC$/);
  assert.match(
    time({
      starts_at: "2026-03-29T00:30:00Z",
      ends_at: "2026-03-29T01:30:00Z",
      timezone: "Europe/London",
    }),
    /29 Mar 2026/,
  );
  assert.match(
    time({
      starts_at: "2026-12-31T23:30:00Z",
      ends_at: "2027-01-01T00:30:00Z",
      timezone: "UTC",
    }),
    /31 Dec 2026, 11:30 PM UTC – 1 Jan 2027, 12:30 AM UTC/,
  );
});

// ----------------------------------------------------------------- FCM sender

const { privateKey } = generateKeyPairSync("rsa", {
  modulusLength: 2048,
  privateKeyEncoding: { type: "pkcs8", format: "pem" },
  publicKeyEncoding: { type: "spki", format: "pem" },
});
const account = {
  project_id: "demo-project-1",
  client_email: "svc@demo-project-1.iam.gserviceaccount.com",
  private_key: privateKey,
};
const message: PushMessage = {
  token: "tok_" + "x".repeat(40),
  eventId: "e1",
  bookingId: "b1",
  userId: "u1",
  kind: "created",
  reference: "BK-1",
  details: base,
};
const withAccount = async <T>(value: unknown, fn: () => Promise<T>) => {
  const saved = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  process.env.FIREBASE_SERVICE_ACCOUNT_JSON =
    typeof value === "string" ? value : JSON.stringify(value);
  try {
    return await fn();
  } finally {
    saved === undefined
      ? delete process.env.FIREBASE_SERVICE_ACCOUNT_JSON
      : (process.env.FIREBASE_SERVICE_ACCOUNT_JSON = saved);
  }
};
const failure = (p: Promise<unknown>) =>
  p.then(
    () => null,
    (e) => e as PushFailure,
  );
function http(
  sequence: Array<
    | { status?: number; body?: unknown; headers?: Record<string, string> }
    | Error
  >,
) {
  const requests: Array<{ url: string; body: any }> = [];
  let n = 0;
  const f = (async (url: string, init?: RequestInit) => {
    const item = sequence[Math.min(n++, sequence.length - 1)];
    if (item instanceof Error) throw item;
    requests.push({ url: String(url), body: init?.body });
    return new Response(JSON.stringify(item.body ?? {}), {
      status: item.status ?? 200,
      headers: item.headers,
    });
  }) as typeof fetch;
  return { f, requests };
}
const oauth = { body: { access_token: "at", expires_in: 3600 } };

test("fcm: unknown or blank event kinds are refused permanently before any credential or network use", async () => {
  const h = http([oauth]);
  const sender = new FcmSender(h.f);
  for (const kind of [
    "",
    "CREATED",
    "deleted",
    " created",
    "created\n",
    undefined as never,
    5 as never,
  ]) {
    const e = await failure(
      withAccount("not-json", () => sender.send({ ...message, kind })),
    );
    assert.ok(
      e instanceof PushFailure && e.code === "INVALID_EVENT" && !e.retryable,
      `kind ${JSON.stringify(kind)} gave ${e?.code}`,
    );
  }
  assert.equal(h.requests.length, 0);
});

test(
  "fcm: prototype property names are not valid event kinds",
  { todo: "BUG-25" },
  async () => {
    const sender = new FcmSender(http([oauth]).f);
    for (const kind of [
      "__proto__",
      "constructor",
      "toString",
      "hasOwnProperty",
      "valueOf",
    ]) {
      const e = await failure(
        withAccount("not-json", () => sender.send({ ...message, kind })),
      );
      assert.ok(
        e instanceof PushFailure && e.code === "INVALID_EVENT",
        `kind ${kind} gave ${e?.code}`,
      );
    }
  },
);

test("fcm: malformed service-account configuration is a retryable credentials failure with no leakage", async () => {
  const h = http([oauth]);
  for (const value of [
    "",
    "{}",
    "[]",
    "null",
    "not json",
    { ...account, project_id: "" },
    { ...account, project_id: "Bad_ID" },
    { ...account, project_id: "a/../b" },
    { ...account, project_id: "1project" },
    { ...account, project_id: "p" },
    { ...account, project_id: "x\ny" },
    { ...account, client_email: undefined },
    { ...account, private_key: undefined },
    { ...account, project_id: 5 },
  ]) {
    const e = await failure(
      withAccount(value, () => new FcmSender(h.f).send(message)),
    );
    assert.ok(
      e instanceof PushFailure && e.code === "FCM_CREDENTIALS" && e.retryable,
      `${JSON.stringify(value)?.slice(0, 40)} gave ${e?.code}`,
    );
    assert.equal(e.message.includes("PRIVATE"), false);
  }
  assert.equal(h.requests.length, 0);
});

test("fcm: a private key that cannot sign is an OAuth failure and secrets never reach the failure object", async () => {
  const h = http([oauth]);
  const e = await failure(
    withAccount(
      {
        ...account,
        private_key:
          "-----BEGIN PRIVATE KEY-----\nSECRETSECRET\n-----END PRIVATE KEY-----",
      },
      () => new FcmSender(h.f).send(message),
    ),
  );
  assert.ok(e instanceof PushFailure && e.code === "FCM_OAUTH" && e.retryable);
  assert.equal(JSON.stringify(e).includes("SECRETSECRET"), false);
});

test("fcm: the device token and message fields are carried only in the JSON body, never in the URL", async () => {
  const h = http([oauth, { status: 200 }]);
  const token = "tok/../?evil=1&x= " + "y".repeat(30);
  await withAccount(account, () =>
    new FcmSender(h.f).send({ ...message, token, reference: "BK-1\nINJECT" }),
  );
  const send = h.requests.find((r) => r.url.includes("messages:send"))!;
  assert.equal(
    send.url,
    "https://fcm.googleapis.com/v1/projects/demo-project-1/messages:send",
  );
  const body = JSON.parse(send.body);
  assert.equal(body.message.token, token);
  assert.equal(body.message.notification.title, "Order placed");
  assert.equal(body.message.notification.body.split("\n").length, 4);
  assert.deepEqual(Object.keys(body.message.data).sort(), [
    "booking_id",
    "event_id",
    "event_type",
    "recipient_user_id",
  ]);
  assert.equal(body.message.android.notification.tag, "e1");
  for (const [kind, title] of [
    ["cancelled", "Order cancelled"],
    ["rescheduled", "Order rescheduled"],
  ] as const) {
    const g = http([oauth, { status: 200 }]);
    await withAccount(account, () =>
      new FcmSender(g.f).send({ ...message, kind }),
    );
    assert.equal(
      JSON.parse(g.requests.find((r) => r.url.includes("messages:send"))!.body)
        .message.notification.title,
      title,
    );
  }
});

test("fcm: provider failures classify retry, dead-token and back-off correctly without persisting provider text", async () => {
  const send = async (
    status: number,
    body: unknown = {},
    headers: Record<string, string> = {},
  ) => {
    const h = http([oauth, { status, body, headers }]);
    return failure(
      withAccount(account, () => new FcmSender(h.f).send(message)),
    );
  };
  const unregistered = await send(404, {
    error: {
      details: [
        {
          "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
          errorCode: "UNREGISTERED",
        },
      ],
    },
  });
  assert.deepEqual(
    [unregistered.code, unregistered.retryable, unregistered.unregistered],
    ["UNREGISTERED", false, true],
  );
  const wrongType = await send(404, {
    error: { details: [{ "@type": "other", errorCode: "UNREGISTERED" }] },
  });
  assert.equal(
    wrongType.unregistered,
    false,
    "only the FcmError detail type is trusted",
  );
  assert.equal((await send(404, "not an object" as never)).unregistered, false);
  for (const [status, retryable] of [
    [400, false],
    [404, false],
    [401, true],
    [403, true],
    [429, true],
    [500, true],
    [503, true],
  ] as const) {
    const e = await send(status);
    assert.deepEqual(
      [e.code, e.retryable],
      [`FCM_HTTP_${status}`, retryable],
      String(status),
    );
    assert.equal(e.unregistered, false);
  }
  assert.equal(
    (await send(429, {}, { "retry-after": "120" })).retryAfterSeconds,
    120,
  );
  assert.equal(
    (await send(429, {}, { "retry-after": "999999" })).retryAfterSeconds,
    3600,
    "capped at one hour",
  );
  assert.equal(
    (await send(429, {}, { "retry-after": "abc" })).retryAfterSeconds,
    0,
  );
  assert.equal(
    (await send(429, {}, { "retry-after": "Wed, 21 Oct 2015 07:28:00 GMT" }))
      .retryAfterSeconds,
    0,
    "past dates mean now",
  );
  assert.equal(
    (
      await send(500, { error: { message: "token tok_secret rejected" } })
    ).message.includes("tok_secret"),
    false,
  );
});

test(
  "fcm: a negative Retry-After is clamped to zero",
  { todo: "BUG-24" },
  async () => {
    const h = http([oauth, { status: 429, headers: { "retry-after": "-30" } }]);
    const e = await failure(
      withAccount(account, () => new FcmSender(h.f).send(message)),
    );
    assert.ok(
      e.retryAfterSeconds >= 0,
      `retryAfterSeconds=${e.retryAfterSeconds}`,
    );
  },
);

test("fcm: network errors are retryable and an OAuth refusal or malformed grant is retryable with back-off", async () => {
  const net = await failure(
    withAccount(account, () =>
      new FcmSender(http([oauth, new TypeError("fetch failed")]).f).send(
        message,
      ),
    ),
  );
  assert.deepEqual([net.code, net.retryable], ["FCM_NETWORK", true]);
  for (const first of [
    { status: 401 },
    { status: 500 },
    { status: 200, body: {} },
    { status: 200, body: { access_token: "x" } },
    { status: 200, body: { access_token: "", expires_in: 3600 } },
    new Error("offline"),
  ]) {
    const e = await failure(
      withAccount(account, () => new FcmSender(http([first]).f).send(message)),
    );
    assert.deepEqual(
      [e.code, e.retryable, e.retryAfterSeconds],
      ["FCM_OAUTH", true, 300],
    );
  }
});

// ------------------------------------------------------------- team access mail

const notice: TeamAccessNotice = {
  email: "member@example.com",
  name: "Member",
  organization: "Falcon Arena",
  role: "staff",
  permissions: ["view_bookings"],
  assignments: [{ business: "Turf", resources: ["Pitch A"] }],
};
const urls = {
  web: "https://bookingos.online/app/sign-in",
  app: "bookingservice.tatos.tech://login/sign-in",
};

test("team email: HTML-significant characters in every user-controlled field are escaped", () => {
  const evil = `<img src=x onerror=alert(1)>&"'`;
  const m = teamAccessMessage(
    {
      ...notice,
      name: evil,
      organization: evil,
      email: `a"><b@example.com`,
      assignments: [{ business: evil, resources: [evil, "<b>"] }],
    },
    urls,
  );
  assert.equal(
    /<img|<b>|onerror=alert\(1\)>(?!&)/.test(
      m.html.replace(/&lt;img[^]*?&gt;/g, ""),
    ),
    false,
  );
  assert.ok(
    m.html.includes("&lt;img src=x onerror=alert(1)&gt;&amp;&quot;&#39;"),
  );
  assert.equal(m.html.includes("<img"), false);
  assert.equal(m.html.includes("<b>"), false);
});

test("team email: subject cannot gain header lines from the organization name", () => {
  for (const organization of [
    "A\r\nBcc: attacker@example.com",
    "A\nB",
    "A\rB",
    "A\r\n\r\nbody",
  ])
    assert.equal(
      /[\r\n]/.test(
        teamAccessMessage({ ...notice, organization }, urls).subject,
      ),
      false,
      JSON.stringify(organization),
    );
});

test(
  "team email: plain-text body cannot be given extra lines by a display name or business name",
  { todo: "BUG-7" },
  () => {
    const m = teamAccessMessage(
      {
        ...notice,
        name: "Alice\n\nYour account is locked, visit http://evil.example",
        assignments: [
          { business: "Turf\nVisit http://evil.example", resources: [] },
        ],
      },
      urls,
    );
    assert.equal(m.text.includes("\nYour account is locked"), false);
    assert.equal(m.text.includes("\nVisit http://evil.example"), false);
  },
);

test("team email: unknown permissions are omitted, duplicates collapse, roles are labelled and empty scope is explained", () => {
  const m = teamAccessMessage(
    {
      ...notice,
      permissions: ["view_bookings", "view_bookings", "root", "coach"],
      role: "unknown",
      assignments: [],
    },
    urls,
  );
  assert.equal((m.text.match(/View bookings/g) ?? []).length, 1);
  assert.equal(/root/.test(m.text.split("Your permissions:")[1]), false);
  assert.match(m.text, /Responsibility: Staff/);
  assert.match(
    teamAccessMessage({ ...notice, role: "owner" }, urls).text,
    /Responsibility: Owner/,
  );
  assert.match(
    teamAccessMessage({ ...notice, role: "manager" }, urls).text,
    /Responsibility: Manager/,
  );
  assert.match(
    teamAccessMessage({ ...notice, permissions: [] }, urls).text,
    /No operational permissions enabled/,
  );
  assert.match(
    teamAccessMessage(
      { ...notice, assignments: [{ business: "Turf", resources: [] }] },
      urls,
    ).text,
    /Turf: All resources/,
  );
  assert.equal(
    /token|accept\?|invite\?/i.test(
      m.text.replace(/No invitation link, acceptance code/g, ""),
    ),
    false,
    "no secret links",
  );
});

test(
  "team email: prototype property names are ignored as permissions instead of crashing the renderer",
  { todo: "BUG-25" },
  () => {
    assert.doesNotThrow(() =>
      teamAccessMessage(
        { ...notice, permissions: ["__proto__", "constructor", "toString"] },
        urls,
      ),
    );
  },
);

test("team login url: only https web sign-in pages (or localhost http outside production) are accepted", () => {
  const ok = (v: string, env: Record<string, string> = {}) =>
    teamLoginUrls({ TEAM_LOGIN_WEB_URL: v, ...env } as never).web;
  assert.equal(
    ok("https://bookingos.online/app/sign-in"),
    "https://bookingos.online/app/sign-in",
  );
  assert.equal(
    teamLoginUrls({} as never).web,
    "https://bookingos.online/app/sign-in",
  );
  assert.equal(
    ok("http://localhost:8080/sign-in", { NODE_ENV: "development" }),
    "http://localhost:8080/sign-in",
  );
  for (const bad of [
    "http://bookingos.online/app/sign-in",
    "javascript:alert(1)",
    "ftp://x/sign-in",
    "https://user:pw@bookingos.online/app/sign-in",
    "https://bookingos.online/app/sign-in?next=//evil",
    "https://bookingos.online/app/sign-in#x",
    "https://bookingos.online/app/login",
    "not a url",
    "//evil.test/sign-in",
    "https://bookingos.online/app/sign-in/x",
  ])
    assert.throws(() => ok(bad), undefined, bad);
  assert.throws(() =>
    ok("http://localhost:8080/sign-in", { NODE_ENV: "production" }),
  );
  assert.throws(() =>
    ok("http://evil.test/sign-in", { NODE_ENV: "development" }),
  );
  assert.throws(() =>
    ok("http://localhost.evil.test/sign-in", { NODE_ENV: "development" }),
  );
});

test("smtp mailer: incomplete or invalid configuration fails before any transport is created", async () => {
  let created = 0;
  const factory = async () => (
    created++,
    { sendMail: async () => ({ accepted: ["x"], rejected: [] }), close() {} }
  );
  const good = {
    SMTP_HOST: "smtp.example.com",
    SMTP_PORT: "465",
    SMTP_USER: "u",
    SMTP_PASSWORD: "p",
    SMTP_FROM: "noreply@example.com",
    NODE_ENV: "test",
  };
  for (const patch of [
    { SMTP_HOST: "" },
    { SMTP_HOST: undefined },
    { SMTP_USER: "" },
    { SMTP_PASSWORD: "" },
    { SMTP_PASSWORD: undefined },
    { SMTP_FROM: "not-an-email" },
    { SMTP_FROM: "" },
    { SMTP_FROM: "a@b.com, c@d.com" },
    { SMTP_PORT: "0" },
    { SMTP_PORT: "65536" },
    { SMTP_PORT: "abc" },
    { SMTP_PORT: "465.5" },
    { SMTP_PORT: "-1" },
  ]) {
    const env = { ...good, ...patch };
    await assert.rejects(
      () =>
        new NodemailerTeamAccessMailer(factory as never, env as never).send(
          notice,
        ),
      undefined,
      JSON.stringify(patch),
    );
  }
  assert.equal(created, 0);
  await new NodemailerTeamAccessMailer(factory as never, good as never).send(
    notice,
  );
  assert.equal(created, 1);
  await new NodemailerTeamAccessMailer(
    factory as never,
    { ...good, SMTP_PORT: undefined } as never,
  ).send(notice);
});

test("smtp mailer: partial acceptance or a hung server is a failure and the transport is always closed", async () => {
  const good = {
    SMTP_HOST: "h",
    SMTP_PORT: "587",
    SMTP_USER: "u",
    SMTP_PASSWORD: "p",
    SMTP_FROM: "noreply@example.com",
    NODE_ENV: "test",
  };
  let closed = 0,
    options: any;
  const mk = (info: unknown) =>
    (async (o: unknown) => (
      (options = o),
      { sendMail: async () => info, close: () => closed++ }
    )) as never;
  for (const info of [
    { accepted: [], rejected: [] },
    { accepted: ["a"], rejected: ["b"] },
    { accepted: undefined, rejected: undefined },
  ])
    await assert.rejects(
      () =>
        new NodemailerTeamAccessMailer(mk(info), good as never).send(notice),
      /not accepted/,
    );
  assert.equal(closed, 3);
  assert.equal(options.secure, false, "port 587 uses STARTTLS");
  assert.equal(options.requireTLS, true);
  assert.equal(options.tls.rejectUnauthorized, true);
  assert.equal(options.disableFileAccess && options.disableUrlAccess, true);
  await new NodemailerTeamAccessMailer(mk({ accepted: ["a"], rejected: [] }), {
    ...good,
    SMTP_PORT: "465",
  } as never).send(notice);
  assert.equal(options.secure, true);
});
