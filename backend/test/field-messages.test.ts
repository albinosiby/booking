import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import {
  HttpException,
  ForbiddenException,
  NotFoundException,
  ConflictException,
} from "@nestjs/common";
import { ZodError } from "zod";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import {
  MessagesService,
  defaultBody,
  fields,
  templateError,
} from "../src/messages/messages.service";
import type { Actor } from "../src/common/auth.guard";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  workspace = new WorkspaceService(db),
  service = new MessagesService(db, workspace);
const actor = (): Actor => ({
  uid: randomUUID(),
  email: `${randomUUID()}@example.com`,
  name: "Owner",
});
async function org(a: Actor) {
  await workspace.createOrganization(a, {
    name: "Eden",
    contact_phone: "9876543210",
    currency: "INR",
    location: {
      name: "Main",
      address_line_1: "Road",
      address_line_2: null,
      city: "Kochi",
      state_code: "KL",
      country_code: "IN",
      postal_code: "682001",
      timezone: "Asia/Kolkata",
    },
  });
}
async function team(permissions: string[]) {
  const o = actor();
  await org(o);
  const m = await workspace.member(o);
  const staff = actor();
  await db.query(
    "INSERT INTO memberships(id,organization_id,user_id,email,display_name,role,permissions) VALUES($1,$2,$3,$4,'Staff','staff',$5)",
    [
      randomUUID(),
      m.organization_id,
      staff.uid,
      staff.email,
      JSON.stringify(permissions),
    ],
  );
  return { owner: o, staff };
}
const isClientError = (e: unknown) =>
  e instanceof ZodError ||
  (e instanceof HttpException && e.getStatus() < 500) ||
  (e as any)?.code === "23505";
const status = (e: unknown) =>
  e instanceof ZodError
    ? 422
    : e instanceof HttpException
      ? e.getStatus()
      : (e as any)?.code === "23505"
        ? 409
        : 500;
async function client(fn: () => Promise<unknown>, label = "") {
  try {
    await fn();
  } catch (e) {
    assert.ok(
      isClientError(e),
      `${label}: expected a client error, got ${(e as Error)?.constructor?.name}: ${(e as Error)?.message}`,
    );
    return e as Error;
  }
  assert.fail(`${label}: should have been rejected`);
}
const req = (
  name = `T-${randomUUID().slice(0, 8)}`,
  body = defaultBody,
  website_url = "",
) => ({
  command_key: randomUUID(),
  name,
  body,
  website_url,
});
const stored = async (id: string) =>
  (
    await db.query<any>("SELECT * FROM booking_message_templates WHERE id=$1", [
      id,
    ])
  ).rows[0];
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());

test("template.command_key and unknown fields are validated", async () => {
  const { owner } = await team(["view_bookings"]);
  for (const command_key of ["", " ", null, 5, "abc", "'; --", undefined])
    assert.equal(
      status(
        await client(
          () => service.create(owner, { ...req(), command_key }),
          String(command_key),
        ),
      ),
      422,
    );
  assert.equal(
    status(await client(() => service.create(owner, { ...req(), extra: 1 }))),
    422,
  );
  assert.equal(
    status(
      await client(() => service.create(owner, { ...req(), is_primary: true })),
    ),
    422,
  );
  for (const body of [null, undefined, "x", 5, []])
    await client(() => service.create(owner, body), String(body));
});
test("template.name: empty, whitespace, 1 char, 80/81 chars, null, number, unicode, emoji, SQL-ish, case-insensitive duplicates", async () => {
  const { owner } = await team([]);
  for (const name of [
    "",
    " ",
    "\t\n",
    "a",
    " a ",
    "x".repeat(81),
    null,
    5,
    {},
    [],
  ])
    assert.equal(
      status(
        await client(
          () => service.create(owner, req(name as any)),
          `name=${JSON.stringify(name)}`,
        ),
      ),
      422,
    );
  const before = (await service.catalog(owner)).templates.length;
  const good = [
    "ab",
    "x".repeat(80),
    "  padded  ",
    "Réservation 李雷",
    "🎉 Party",
    "'; DROP TABLE booking_message_templates;--",
    "<b>bold</b>",
    "100% {x}",
    "a_b%c",
  ];
  for (const name of good) {
    const r = await service.create(owner, req(name));
    assert.equal((await stored(r.id)).name, name.trim());
  }
  assert.equal(
    (await service.catalog(owner)).templates.length,
    before + good.length,
  );
  assert.ok(
    (await client(() => service.create(owner, req("PADDED")))) instanceof
      ConflictException,
  );
  assert.ok(
    (await client(() =>
      service.create(owner, req("réservation 李雷")),
    )) instanceof ConflictException,
  );
  assert.ok(
    (await client(() =>
      service.create(owner, req("RÉSERVATION 李雷")),
    )) instanceof ConflictException,
  );
  // the table survived the SQL-ish name
  assert.ok(
    (
      await db.query<any>(
        "SELECT count(*)::int AS n FROM booking_message_templates",
      )
    ).rows[0].n >= good.length,
  );
});
test(
  "a custom template named like the built-in one is ambiguous and should be refused",
  { todo: "BUG-10" },
  async () => {
    const { owner } = await team([]);
    await assert.rejects(() =>
      service.create(owner, req("Booking confirmation")),
    );
  },
);
test("template.body: empty, whitespace, 6000/6001 chars, placeholders, unbalanced braces, unicode and emoji", async () => {
  const { owner } = await team([]);
  const valid = [
    "a",
    "{customer_name}",
    "{customer_name}{customer_name}",
    "*{booking_total}* _x_ ~y~",
    "😀 {venue_name} 李",
    "x".repeat(6000),
    "x".repeat(5975) + "{customer_name}".slice(0, 0),
    ...fields.map((f) => `{${f}}`),
  ];
  for (const body of valid) {
    assert.equal(templateError(body), undefined, body.slice(0, 20));
    assert.ok((await service.create(owner, req(undefined, body))).id);
  }
  const invalid: unknown[] = [
    "",
    " ",
    "\n\t ",
    null,
    5,
    {},
    [],
    "x".repeat(6001),
    "{unknown}",
    "{Customer_Name}",
    "{ customer_name }",
    "{customer_name ",
    "customer_name}",
    "}{",
    "{",
    "}",
    "{}",
    "{{customer_name}}",
    "{customer_name}}",
    "{{customer_name}",
    "{customer_name}{",
    "{customer_name{venue_name}}",
    "{__proto__}",
    "{constructor}",
    "{toString}",
    "{customer_name\n}",
    "😀".repeat(3001) + "x".repeat(0),
  ];
  for (const body of invalid)
    assert.ok(
      [422, 400].includes(
        status(
          await client(
            () => service.create(owner, req(undefined, body as any)),
            JSON.stringify(body)?.slice(0, 30),
          ),
        ),
      ),
      JSON.stringify(body)?.slice(0, 30),
    );
  // every error path reports a message
  for (const body of ["{unknown}", "{", "", "x".repeat(6001)])
    assert.ok(templateError(body));
  assert.equal(templateError("   "), "Write a message of 1–6000 characters.");
});
test("template.body of exactly 6000 UTF-16 units made of emoji is judged by one consistent length rule", async () => {
  const { owner } = await team([]);
  // 3000 emoji = 3000 code points but 6000 UTF-16 units
  const body = "😀".repeat(3000);
  assert.equal(templateError(body), undefined);
  assert.ok((await service.create(owner, req(undefined, body))).id);
  // 3001 emoji: 3001 code points (zod max ok) but 6002 units -> rejected by templateError
  await client(() => service.create(owner, req(undefined, "😀".repeat(3001))));
});
test("template.website_url: empty, null, wrong type, 500/501 chars, schemes, credentials, whitespace, case", async () => {
  const { owner } = await team([]);
  const ok = [
    "",
    "https://example.com",
    "http://example.com",
    "https://a",
    "http://localhost:3000/path?x=1#y",
    "https://例え.jp",
    "https://example.com/" + "a".repeat(470),
  ];
  for (const url of ok) {
    const r = await service.create(owner, req(undefined, defaultBody, url));
    assert.equal((await stored(r.id)).website_url, url);
  }
  const bad: unknown[] = [
    null,
    5,
    {},
    [],
    " ",
    " https://a.com",
    "ftp://a.com",
    "javascript:alert(1)",
    "data:text/html,<script>",
    "file:///etc/passwd",
    "//a.com",
    "a.com",
    "http://",
    "https://",
    "https:// space.com",
    "https://exa mple.com",
    "http:/a.com",
    "mailto:a@b.com",
    "https://" + "a".repeat(495) + ".com",
    "x".repeat(501),
    "'; DROP TABLE x;--",
    "😀",
  ];
  for (const url of bad)
    await client(
      () => service.create(owner, req(undefined, defaultBody, url as any)),
      `url=${String(url).slice(0, 30)}`,
    );
  // omitted key defaults to ""
  const omitted: any = req();
  delete omitted.website_url;
  assert.equal(
    (await stored((await service.create(owner, omitted)).id)).website_url,
    "",
  );
});
test(
  "website_url is trimmed or rejected when it carries trailing whitespace or newlines",
  { todo: "BUG-12" },
  async () => {
    const { owner } = await team([]);
    for (const url of ["https://a.com ", "https://a.com\n", "https://a.com\t"])
      await assert.rejects(
        () => service.create(owner, req(undefined, defaultBody, url)),
        url,
      );
  },
);
test(
  "website_url must not accept embedded credentials (the social links already refuse them)",
  { todo: "BUG-11" },
  async () => {
    const { owner } = await team([]);
    // The social links on the website reject user:pass@; the message template link accepts them,
    // so a pasted https://user:pass@host link is sent to customers verbatim.
    await assert.rejects(() =>
      service.create(
        owner,
        req(undefined, defaultBody, "https://user:secret@example.com"),
      ),
    );
  },
);
test("duplicate submit: same key + same payload is idempotent, changed payload conflicts, parallel duplicates create one template, limit of 50", async () => {
  const { owner } = await team([]);
  const r = req("Idem");
  const a = await service.create(owner, r);
  const b = await service.create(owner, r);
  assert.equal(a.id, b.id);
  for (const change of [
    { name: "Idem2" },
    { body: "Changed" },
    { website_url: "https://x.com" },
  ])
    assert.ok(
      (await client(() =>
        service.create(owner, { ...r, ...change }),
      )) instanceof ConflictException,
    );
  const p = req("Parallel");
  const results = await Promise.allSettled(
    [1, 2, 3, 4].map(() => service.create(owner, p)),
  );
  assert.ok(results.every((x) => x.status === "fulfilled"));
  assert.equal(
    (
      await db.query<any>(
        "SELECT count(*)::int AS n FROM booking_message_templates WHERE id=$1",
        [p.command_key],
      )
    ).rows[0].n,
    1,
  );
  // same name, different keys in parallel: exactly one wins
  const same = await Promise.allSettled(
    [1, 2, 3].map(() => service.create(owner, req("Racing"))),
  );
  assert.equal(same.filter((x) => x.status === "fulfilled").length, 1);
  // 50 template cap (Idem + Parallel + Racing already exist = 3)
  const have = (await service.catalog(owner)).templates.length - 1;
  for (let i = have; i < 50; i++) await service.create(owner, req(`Bulk ${i}`));
  const over = await client(() => service.create(owner, req("Bulk overflow")));
  assert.equal(status(over), 400);
  // retrying the very first request still works at the cap
  assert.equal((await service.create(owner, r)).id, a.id);
});
test("a template key already used by another organisation returns a handled conflict and leaks nothing", async () => {
  const x = await team([]),
    y = await team([]);
  const r = req("Mine");
  const created = await service.create(x.owner, r);
  const e = await client(() => service.create(y.owner, { ...r }));
  assert.equal(status(e), 409);
  assert.ok(!/Mine/.test(e.message ?? ""));
  assert.equal((await service.catalog(y.owner)).templates.length, 1);
  assert.equal((await stored(created.id)).name, "Mine");
});
test("primary: id format, default/unknown, case, cross-tenant and role denial", async () => {
  const x = await team(["view_bookings"]),
    y = await team([]);
  const mine = await service.create(x.owner, req("P1"));
  const theirs = await service.create(y.owner, req("P2"));
  for (const id of [
    "",
    " ",
    null,
    5,
    undefined,
    "abc",
    "DEFAULT",
    "Default",
    "default ",
    "'; --",
    "😀",
    {},
    [],
  ])
    assert.equal(
      status(
        await client(
          () => service.primary(x.owner, { id }),
          `id=${JSON.stringify(id)}`,
        ),
      ),
      422,
    );
  await client(() => service.primary(x.owner, { id: mine.id, extra: 1 }));
  await client(() => service.primary(x.owner, null));
  assert.ok(
    (await client(() =>
      service.primary(x.owner, { id: randomUUID() }),
    )) instanceof NotFoundException,
  );
  assert.ok(
    (await client(() => service.primary(x.owner, { id: theirs.id }))) instanceof
      NotFoundException,
  );
  assert.ok(
    (await client(() => service.primary(x.staff, { id: mine.id }))) instanceof
      ForbiddenException,
  );
  await service.primary(x.owner, { id: mine.id });
  await service.primary(x.owner, { id: mine.id }); // idempotent
  assert.equal(
    (await service.catalog(x.owner)).templates.filter((t) => t.is_primary)
      .length,
    1,
  );
  await service.primary(x.owner, { id: "default" });
  assert.equal(
    (await service.catalog(x.owner)).templates.find((t) => t.id === "default")!
      .is_primary,
    true,
  );
  assert.equal(
    (await service.catalog(y.owner)).templates.filter((t) => t.is_primary)
      .length,
    1,
  );
});
test("remove: id format, built-in, cross-tenant and role denial", async () => {
  const x = await team(["view_bookings"]),
    y = await team([]);
  const mine = await service.create(x.owner, req("R1"));
  for (const id of [
    "",
    " ",
    "default",
    "DEFAULT",
    "abc",
    "'; --",
    "😀",
    "%",
    "*",
    mine.id.toUpperCase() + "x",
  ])
    await client(() => service.remove(x.owner, id), `id=${id}`);
  assert.ok(
    (await client(() => service.remove(x.owner, randomUUID()))) instanceof
      NotFoundException,
  );
  assert.ok(
    (await client(() => service.remove(y.owner, mine.id))) instanceof
      NotFoundException,
  );
  assert.ok(
    (await client(() => service.remove(x.staff, mine.id))) instanceof
      ForbiddenException,
  );
  assert.ok(
    await stored(mine.id),
    "template still exists after denied removals",
  );
  await service.remove(x.owner, mine.id);
  assert.equal(await stored(mine.id), undefined);
  assert.ok(
    (await client(() => service.remove(x.owner, mine.id))) instanceof
      NotFoundException,
    "second delete",
  );
  // removing a key frees it for reuse by name
  assert.ok((await service.create(x.owner, req("R1"))).id);
});
test("catalog: role matrix and tenant isolation", async () => {
  const none = await team([]);
  for (const permission of [
    "view_bookings",
    "manage_bookings",
    "collect_payments",
    "view_finance",
  ]) {
    const t = await team([permission]);
    const c = await service.catalog(t.staff);
    assert.equal(c.can_manage, false, permission);
    assert.equal(c.templates.length, 1);
  }
  for (const permission of ["manage_attendance", "view_expenses", "bogus"]) {
    const t = await team([permission]);
    assert.ok(
      (await client(() => service.catalog(t.staff), permission)) instanceof
        ForbiddenException,
      permission,
    );
  }
  assert.ok(
    (await client(() => service.catalog(none.staff))) instanceof
      ForbiddenException,
  );
  assert.ok(
    (await client(() => service.catalog(actor()))) instanceof
      ForbiddenException,
  );
  const a = await team([]),
    b = await team([]);
  await service.create(a.owner, req("Only A"));
  assert.equal((await service.catalog(b.owner)).templates.length, 1);
  assert.equal((await service.catalog(a.owner)).can_manage, true);
  // a revoked member loses access
  await db.query("UPDATE memberships SET active=false WHERE user_id=$1", [
    none.staff.uid,
  ]);
  assert.ok(
    (await client(() => service.catalog(none.staff))) instanceof
      ForbiddenException,
  );
});

test(
  "a NUL character (\\u0000) in a template name, body or URL must be a 4xx, never an unhandled database error",
  { todo: "BUG-14" },
  async () => {
    const { owner } = await team([]);
    const nul = "bad\u0000value";
    const failures: string[] = [];
    const probe = async (label: string, fn: () => Promise<unknown>) => {
      try {
        await fn();
      } catch (e) {
        if (!isClientError(e))
          failures.push(
            `${label}: ${(e as Error).constructor.name} ${(e as Error).message}`,
          );
      }
    };
    await probe("name", () => service.create(owner, req(nul)));
    await probe("body", () =>
      service.create(owner, req(undefined, `Hello {customer_name} ${nul}`)),
    );
    await probe("website_url", () =>
      service.create(
        owner,
        req(undefined, defaultBody, `https://example.com/${nul}`),
      ),
    );
    assert.deepEqual(failures, []);
  },
);
