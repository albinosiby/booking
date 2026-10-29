import test from "node:test";
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import {
  mkdtemp,
  readFile,
  stat,
  writeFile,
  access,
  rm,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";

const run = promisify(execFile);
test("bootstrap stores token privately, emits hash-only registration and refuses overwrites", async () => {
  const dir = await mkdtemp(join(tmpdir(), "bookingos-admin-bootstrap-"));
  try {
    const env = join(dir, "private.env"),
      sql = join(dir, "credential.sql");
    const args = [
      "--import",
      "tsx",
      "src/admin-bootstrap.ts",
      "--operator-email",
      "operator@example.test",
      "--config-file",
      env,
      "--sql-file",
      sql,
    ];
    const output = await run(process.execPath, args, { cwd: process.cwd() });
    const privateText = await readFile(env, "utf8"),
      registration = await readFile(sql, "utf8");
    const token = /BOOKINGOS_ADMIN_MCP_TOKEN=(bkam_[\w-]+)/.exec(
      privateText,
    )?.[1];
    assert.ok(token);
    assert.ok(
      registration.includes(createHash("sha256").update(token).digest("hex")),
    );
    assert.ok(!registration.includes(token));
    assert.ok(!output.stdout.includes(token));
    assert.equal(output.stderr, "");
    assert.equal((await stat(env)).mode & 0o777, 0o600);
    assert.equal((await stat(sql)).mode & 0o777, 0o600);
    await assert.rejects(run(process.execPath, args, { cwd: process.cwd() }));
    assert.equal(await readFile(env, "utf8"), privateText);
    assert.equal(await readFile(sql, "utf8"), registration);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
test("bootstrap rolls back only its new env when the SQL destination already exists", async () => {
  const dir = await mkdtemp(join(tmpdir(), "bookingos-admin-bootstrap-"));
  try {
    const env = join(dir, "private.env"),
      sql = join(dir, "credential.sql");
    await writeFile(sql, "existing SQL", { mode: 0o600 });
    await assert.rejects(
      run(
        process.execPath,
        [
          "--import",
          "tsx",
          "src/admin-bootstrap.ts",
          "--operator-email",
          "operator@example.test",
          "--config-file",
          env,
          "--sql-file",
          sql,
        ],
        { cwd: process.cwd() },
      ),
    );
    await assert.rejects(access(env));
    assert.equal(await readFile(sql, "utf8"), "existing SQL");
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
