#!/usr/bin/env node
import { createHash, randomBytes, randomUUID } from "node:crypto";
import { mkdir, open, unlink } from "node:fs/promises";
import { dirname, resolve } from "node:path";

function option(name: string) {
  const at = process.argv.indexOf(name);
  return at < 0 ? undefined : process.argv[at + 1];
}
const quote = (value: string) => `'${value.replaceAll("'", "''")}'`;
const created: string[] = [];
const handles: Awaited<ReturnType<typeof open>>[] = [];
try {
  const email = (option("--operator-email") ?? "").toLowerCase().trim();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 320)
    throw new Error("email");
  const days = Number(option("--days") ?? 90);
  if (!Number.isInteger(days) || days < 1 || days > 365)
    throw new Error("days");
  const envPath = resolve(option("--config-file") ?? "../.local/admin-mcp.env");
  const sqlPath = resolve(
    option("--sql-file") ?? "../.local/admin-mcp-credential.sql",
  );
  if (envPath === sqlPath) throw new Error("paths");
  await mkdir(dirname(envPath), { recursive: true, mode: 0o700 });
  await mkdir(dirname(sqlPath), { recursive: true, mode: 0o700 });
  const token = `bkam_${randomBytes(32).toString("base64url")}`;
  const id = randomUUID();
  const expires = new Date(Date.now() + days * 86400000).toISOString();
  const hash = createHash("sha256").update(token).digest("hex");
  const env = `# Private BookingOS admin MCP configuration. Keep mode 0600. Never paste this file into chat.\nBOOKINGOS_ADMIN_MCP_TOKEN=${token}\nBOOKINGOS_ADMIN_API_URL=https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/v1/admin-mcp/voice\n# Optional if the matching platform workspace key is already saved on the backend.\nBOOKINGOS_SARVAM_WORKSPACE_API_KEY=\n# Use a dedicated committed single-state template with no tools or client credentials.\nBOOKINGOS_SARVAM_TEMPLATE_AGENT_ID=\nBOOKINGOS_SARVAM_TEMPLATE_VERSION=\nBOOKINGOS_SARVAM_TEMPLATE_LANGUAGE=en-IN\n# Exact native config field from the authenticated Sarvam agent schema, and its reviewed value.\nBOOKINGOS_SARVAM_TEMPLATE_LANGUAGE_PATH=\nBOOKINGOS_SARVAM_TEMPLATE_LANGUAGE_VALUE=\n`;
  // Never overwrite a working credential. The SQL contains its hash, never its value.
  const sql = `-- Apply only after the admin voice MCP credential migration. No raw token is in this file.\nBEGIN;\nSET LOCAL search_path=booking_app,pg_catalog;\nINSERT INTO admin_mcp_credentials(id,name,operator_email,issued_by,token_hash,token_prefix,scopes,expires_at) VALUES (${quote(id)},'Codex voice setup',${quote(email)},${quote(email)},${quote(hash)},${quote(token.slice(0, 12))},ARRAY['voice:read','voice:write','voice:credentials:install'],${quote(expires)});\nCOMMIT;\n-- Revoke this principal when needed:\n-- UPDATE booking_app.admin_mcp_credentials SET revoked_at=now() WHERE id=${quote(id)};\n`;
  const envHandle = await open(envPath, "wx", 0o600);
  handles.push(envHandle);
  created.push(envPath);
  const sqlHandle = await open(sqlPath, "wx", 0o600);
  handles.push(sqlHandle);
  created.push(sqlPath);
  await envHandle.writeFile(env);
  await sqlHandle.writeFile(sql);
  await Promise.all(handles.map((handle) => handle.close()));
  handles.length = 0;
  process.stdout.write(
    `Created a private admin configuration and hash-only registration SQL.\nEnvironment file: ${envPath}\nSQL file: ${sqlPath}\nPrincipal ID: ${id}\nExpires: ${expires}\nApply the migration and review/apply the SQL yourself. No live database changes were made.\n`,
  );
} catch {
  await Promise.all(
    handles.map((handle) => handle.close().catch(() => undefined)),
  );
  await Promise.all(created.map((path) => unlink(path).catch(() => undefined)));
  process.stderr.write(
    "Bootstrap did not finish. Supply --operator-email, use new private output paths, and check directory permissions. Existing files are never overwritten. Do not paste credential files into chat.\n",
  );
  process.exitCode = 1;
}
