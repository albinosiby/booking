import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import {
  AdminMcpAuthService,
  hashAdminMcpToken,
  requireAdminMcpScope,
  voiceScopeForRequest,
} from "../src/admin/admin-mcp-auth";
delete process.env.DATABASE_URL;
Object.assign(process.env, { NODE_ENV: "test", PGLITE_PATH: "memory://" });
const db = new Database(),
  auth = new AdminMcpAuthService(db);
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());
async function principal(scopes: string[] = ["voice:read"]) {
  const token = "bkam_" + randomBytes(32).toString("base64url"),
    id = randomUUID();
  await db.query(
    "INSERT INTO admin_mcp_credentials(id,name,operator_email,issued_by,token_hash,token_prefix,scopes,expires_at) VALUES($1,'Voice operator','operator@example.com','test',$2,$3,$4,now()+interval '1 day')",
    [id, hashAdminMcpToken(token), token.slice(0, 10), scopes],
  );
  return { id, token };
}
test("admin MCP authenticates only hashed active scoped tokens and brands the actor", async () => {
  const p = await principal();
  const actor = await auth.authenticate(`Bearer ${p.token}`, "voice:read");
  assert.equal(actor.uid, `admin-mcp:${p.id}`);
  assert.equal(actor.email, "operator@example.com");
  assert.equal(requireAdminMcpScope(actor, "voice:read").id, p.id);
  assert.throws(
    () => requireAdminMcpScope({ ...actor }, "voice:read"),
    /authorization is required/,
  );
  assert.throws(
    () => requireAdminMcpScope(actor, "voice:write"),
    /scope is not allowed/,
  );
  await assert.rejects(
    auth.authenticate(`Bearer ${p.token}`, "voice:write"),
    /scope is not allowed/,
  );
  const row = (
    await db.query<any>("SELECT * FROM admin_mcp_credentials WHERE id=$1", [
      p.id,
    ])
  ).rows[0];
  assert.ok(row.last_used_at);
  assert.ok(!JSON.stringify(row).includes(p.token));
});
test("revocation and expiry are checked again on every request", async () => {
  const p = await principal();
  await auth.authenticate(`Bearer ${p.token}`, "voice:read");
  await db.query(
    "UPDATE admin_mcp_credentials SET revoked_at=now() WHERE id=$1",
    [p.id],
  );
  await assert.rejects(
    auth.authenticate(`Bearer ${p.token}`, "voice:read"),
    /invalid or expired/,
  );
  const expired = await principal();
  await db.query(
    "UPDATE admin_mcp_credentials SET created_at=now()-interval '2 days',expires_at=now()-interval '1 day' WHERE id=$1",
    [expired.id],
  );
  await assert.rejects(
    auth.authenticate(`Bearer ${expired.token}`, "voice:read"),
    /invalid or expired/,
  );
  await assert.rejects(
    auth.authenticate("Bearer bkam_bad", "voice:read"),
    /authorization is required/,
  );
  await assert.rejects(
    auth.authenticate(`Bearer bkam_${"A".repeat(43)}`, "voice:read"),
    /invalid or expired/,
  );
});
test("credential scope and namespace are separate from broad admin and booking routes", () => {
  const org = randomUUID(),
    base = "/v1/admin-mcp/voice";
  assert.equal(voiceScopeForRequest("GET", `${base}/requests`), "voice:read");
  assert.equal(
    voiceScopeForRequest("GET", `${base}/requests/${org}`),
    "voice:read",
  );
  assert.equal(
    voiceScopeForRequest("POST", `${base}/jobs/${org}/credential`),
    "voice:credentials:install",
  );
  assert.equal(
    voiceScopeForRequest("POST", `${base}/jobs/${org}/claim`),
    "voice:write",
  );
  for (const path of [
    "/v1/admin/me",
    "/v1/admin/agent-requests",
    "/v1/bookings",
    `${base}/jobs/${org}/rotate`,
    `${base}/http`,
  ])
    assert.equal(voiceScopeForRequest("POST", path), undefined);
});
