import "reflect-metadata";
import { before, after, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { supabaseActor } from "../src/common/supabase-auth";
import {
  UnauthorizedException,
  ServiceUnavailableException,
} from "@nestjs/common";
delete process.env.DATABASE_URL;
process.env.PGLITE_PATH = "memory://";
process.env.NODE_ENV = "test";
process.env.SUPABASE_URL = "https://project.supabase.co";
process.env.SUPABASE_PUBLISHABLE_KEY = "sb_publishable_test";
const db = new Database();
before(async () => {
  await db.onModuleInit();
  await db.query(
    "CREATE TABLE migrated_identities(email text PRIMARY KEY,actor_id text UNIQUE NOT NULL,supabase_subject uuid UNIQUE)",
  );
});
after(() => db.onModuleDestroy());
const user = (extra = {}) => ({
  id: randomUUID(),
  email: "new@example.com",
  email_confirmed_at: "2026-01-01",
  user_metadata: { full_name: "Name", role: "owner" },
  ...extra,
});
function response(body: unknown, status = 200): typeof fetch {
  return async (_url, options) => {
    assert.equal(
      (options?.headers as Record<string, string>).apikey,
      "sb_publishable_test",
    );
    assert.ok(
      (options?.headers as Record<string, string>).Authorization.startsWith(
        "Bearer ",
      ),
    );
    return new Response(JSON.stringify(body), { status });
  };
}
test("Supabase rejects invalid, anonymous and unverified users", async () => {
  for (const body of [
    user({ email_confirmed_at: null }),
    user({ is_anonymous: true }),
    user({ email: null }),
  ])
    await assert.rejects(
      () => supabaseActor("token", db, response(body)),
      UnauthorizedException,
    );
  await assert.rejects(
    () => supabaseActor("invalid", db, response({}, 401)),
    UnauthorizedException,
  );
});
test("provider outage is a retryable service failure, not incorrect credentials", async () => {
  await assert.rejects(
    () => supabaseActor("token", db, response({}, 503)),
    ServiceUnavailableException,
  );
  await assert.rejects(
    () =>
      supabaseActor("token", db, async () => {
        throw new Error("network");
      }),
    ServiceUnavailableException,
  );
});
test("verified new users use their subject; metadata cannot select a legacy actor", async () => {
  const u = user({
    user_metadata: { full_name: "Name", actor_id: "old-owner", role: "owner" },
  });
  const actor = await supabaseActor("token", db, response(u));
  assert.equal(actor.uid, u.id);
  assert.deepEqual(Object.keys(actor).sort(), ["email", "name", "uid"]);
});
test("only a verified matching migration claim binds the original actor once", async () => {
  const subject = randomUUID();
  await db.query("INSERT INTO migrated_identities VALUES($1,$2,NULL)", [
    "owner@example.com",
    "original-owner",
  ]);
  const u = user({ id: subject, email: "OWNER@example.com" });
  assert.equal(
    (await supabaseActor("token", db, response(u))).uid,
    "original-owner",
  );
  assert.equal(
    (await supabaseActor("token", db, response(u))).uid,
    "original-owner",
  );
  await assert.rejects(
    () => supabaseActor("token", db, response({ ...u, id: randomUUID() })),
    UnauthorizedException,
  );
  assert.equal(
    (
      await supabaseActor(
        "token",
        db,
        response({ ...u, email: "changed@example.com" }),
      )
    ).uid,
    "original-owner",
  );
});

test("Edge authentication accepts injected configuration without changing environment variables", async () => {
  const beforeUrl = process.env.SUPABASE_URL;
  const u = user();
  const result = await supabaseActor(
    "token",
    db,
    async (url, options) => {
      assert.equal(url, "https://edge-project.supabase.co/auth/v1/user");
      assert.equal(
        (options?.headers as Record<string, string>).apikey,
        "sb_publishable_edge",
      );
      return new Response(JSON.stringify(u));
    },
    { url: "https://edge-project.supabase.co", key: "sb_publishable_edge" },
  );
  assert.equal(result.uid, u.id);
  assert.equal(process.env.SUPABASE_URL, beforeUrl);
});

test("linked and new users authenticate with one read and no recurring identity writes", async () => {
  const subject = randomUUID(),
    email = "read-only@example.com";
  await db.query("INSERT INTO migrated_identities VALUES($1,$2,$3)", [
    email,
    "read-only-owner",
    subject,
  ]);
  const statements: string[] = [];
  const measured = {
    query: async <T = Record<string, unknown>>(
      sql: string,
      values?: unknown[],
    ) => {
      statements.push(sql);
      return db.query<T>(sql, values);
    },
  };
  for (let n = 0; n < 3; n++) {
    assert.equal(
      (
        await supabaseActor(
          "token",
          measured,
          response(user({ id: subject, email })),
        )
      ).uid,
      "read-only-owner",
    );
  }
  assert.equal(statements.length, 3);
  assert.ok(statements.every((sql) => sql.startsWith("SELECT")));
  statements.length = 0;
  const fresh = user({ email: "read-only-new@example.com" });
  assert.equal(
    (await supabaseActor("token", measured, response(fresh))).uid,
    fresh.id,
  );
  assert.equal(statements.length, 1);
  assert.ok(statements[0].startsWith("SELECT"));
});
