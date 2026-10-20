// Run from backend only, with the local API stopped. Never logs credentials.
import {
  readFileSync,
  writeFileSync,
  mkdirSync,
  readdirSync,
  cpSync,
} from "node:fs";
import { resolve } from "node:path";
import { randomBytes, createHash } from "node:crypto";
import { PGlite } from "@electric-sql/pglite";
import pg from "pg";
const project = "scwwkaywewecspsrskft";
const local = resolve("../.local");
const password = readFileSync(
  resolve(local, "supabase-db-password.txt"),
  "utf8",
).trim();
if (!password)
  throw new Error("Save the database password in the private local file.");
const host = "aws-0-ap-northeast-1.pooler.supabase.com";
const client = new pg.Client({
  host,
  port: 5432,
  user: `postgres.${project}`,
  database: "postgres",
  password,
  ssl: {
    rejectUnauthorized: true,
    ca: readFileSync(resolve(local, "supabase-ca.crt"), "utf8"),
  },
  connectionTimeoutMillis: 15000,
});
const tables = [
  "organizations",
  "locations",
  "memberships",
  "businesses",
  "resources",
  "staff_assignments",
  "invitations",
  "logo_assets",
  "audit_events",
  "customers",
  "bookings",
  "booking_allocations",
  "booking_payments",
  "booking_history",
  "booking_commands",
  "money_accounts",
  "payment_routes",
  "finance_events",
  "finance_lines",
];
const quote = (name) => `"${name.replaceAll('"', '""')}"`;
let source;
let transaction = false;
try {
  await client.connect();
  if (
    !client.connection.stream.encrypted ||
    !client.connection.stream.authorized
  )
    throw new Error("Certificate-verified client TLS is required.");
  const existing = await client.query(
    "select 1 from pg_tables where schemaname='booking_app'",
  );
  if (existing.rowCount)
    throw new Error(
      "booking_app already contains tables; refusing to overwrite them.",
    );
  const stamp = new Date().toISOString().replaceAll(":", "-");
  const backup = resolve(local, `supabase-backup-${stamp}`);
  mkdirSync(backup, { recursive: true, mode: 0o700 });
  cpSync(resolve(local, "postgres"), resolve(backup, "postgres"), {
    recursive: true,
  });
  source = new PGlite(resolve(local, "postgres"));
  await source.waitReady;
  const snapshot = {};
  const types = {};
  for (const table of tables) {
    types[table] = (
      await source.query(
        "select column_name,udt_name from information_schema.columns where table_schema='public' and table_name=$1 order by ordinal_position",
        [table],
      )
    ).rows;
    snapshot[table] = (
      await source.query(`select * from ${quote(table)}`)
    ).rows;
  }
  writeFileSync(
    resolve(backup, "snapshot.json"),
    JSON.stringify(snapshot, (_key, value) =>
      typeof value === "bigint" ? value.toString() : value,
    ),
    { mode: 0o600 },
  );
  await source.close();
  source = undefined;
  const identities = snapshot.memberships.filter((row) => row.active);
  if (
    new Set(identities.map((row) => row.email.toLowerCase())).size !==
    identities.length
  )
    throw new Error(
      "Ambiguous migrated identity emails; resolve before migration.",
    );
  await client.query("BEGIN");
  transaction = true;
  await client.query("CREATE SCHEMA booking_app");
  await client.query("SET LOCAL search_path=booking_app,pg_catalog");
  await client.query(
    "REVOKE ALL ON SCHEMA booking_app FROM PUBLIC,anon,authenticated",
  );
  await client.query(
    "CREATE TABLE schema_migrations(name text PRIMARY KEY,applied_at timestamptz NOT NULL DEFAULT now())",
  );
  for (const name of readdirSync("migrations")
    .filter((n) => n.endsWith(".sql"))
    .sort()) {
    await client.query(readFileSync(resolve("migrations", name), "utf8"));
    await client.query("INSERT INTO schema_migrations(name) VALUES($1)", [
      name,
    ]);
  }
  for (const table of tables) {
    let rows = snapshot[table];
    if (table === "finance_events") {
      const ordered = [],
        pending = new Map(rows.map((row) => [row.id, row]));
      while (pending.size) {
        const before = pending.size;
        for (const [id, row] of pending)
          if (!row.reverses_id || !pending.has(row.reverses_id)) {
            ordered.push(row);
            pending.delete(id);
          }
        if (pending.size === before)
          throw new Error("Invalid finance reversal dependency.");
      }
      rows = ordered;
    }
    const columns = types[table];
    for (let offset = 0; offset < rows.length; offset += 100) {
      const batch = rows.slice(offset, offset + 100),
        values = [];
      const placeholders = batch.map(
        (row) =>
          "(" +
          columns
            .map((c) => {
              const value = row[c.column_name];
              values.push(
                value == null
                  ? null
                  : c.udt_name === "jsonb"
                    ? JSON.stringify(value)
                    : c.udt_name === "bytea"
                      ? Buffer.from(value)
                      : value,
              );
              return "$" + values.length;
            })
            .join(",") +
          ")",
      );
      await client.query(
        `INSERT INTO ${quote(table)} (${columns.map((c) => quote(c.column_name)).join(",")}) VALUES ${placeholders.join(",")}`,
        values,
      );
    }
    const count = Number(
      (await client.query(`SELECT count(*) AS n FROM ${quote(table)}`)).rows[0]
        .n,
    );
    if (count !== rows.length) throw new Error(`Count mismatch for ${table}`);
  }
  await client.query(`CREATE TABLE migrated_identities (
    email text PRIMARY KEY CHECK(email=lower(email)),
    actor_id text NOT NULL UNIQUE REFERENCES memberships(user_id),
    supabase_subject uuid UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
  )`);
  for (const row of identities)
    await client.query(
      "INSERT INTO migrated_identities(email,actor_id) VALUES($1,$2)",
      [row.email.toLowerCase(), row.user_id],
    );
  const rolePassword = randomBytes(36).toString("base64url");
  await client.query(
    `CREATE ROLE booking_api LOGIN PASSWORD '${rolePassword}' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOINHERIT`,
  );
  await client.query("GRANT USAGE ON SCHEMA booking_app TO booking_api");
  await client.query(
    "GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA booking_app TO booking_api",
  );
  await client.query(
    "REVOKE ALL ON ALL TABLES IN SCHEMA booking_app FROM PUBLIC,anon,authenticated",
  );
  for (const table of [...tables, "schema_migrations", "migrated_identities"]) {
    await client.query(`ALTER TABLE ${quote(table)} ENABLE ROW LEVEL SECURITY`);
    await client.query(
      `CREATE POLICY api_server_access ON ${quote(table)} TO booking_api USING(true) WITH CHECK(true)`,
    );
  }
  await client.query(
    "REVOKE INSERT,UPDATE,DELETE ON schema_migrations FROM booking_api",
  );
  await client.query(
    "REVOKE INSERT,DELETE ON migrated_identities FROM booking_api",
  );
  await client.query("REVOKE UPDATE ON migrated_identities FROM booking_api");
  await client.query(
    "GRANT UPDATE(supabase_subject) ON migrated_identities TO booking_api",
  );
  const totals = (
    await client.query(
      "SELECT coalesce(sum(amount_minor),0)::text as amount FROM finance_lines",
    )
  ).rows[0].amount;
  const localTotal = snapshot.finance_lines
    .reduce((sum, row) => sum + BigInt(row.amount_minor), 0n)
    .toString();
  if (totals !== localTotal) throw new Error("Ledger total mismatch");
  // Verify entire migrated rows, including JSON configuration and payment details.
  function normalize(value) {
    if (value instanceof Date) return value.toISOString();
    if (Buffer.isBuffer(value) || value instanceof Uint8Array)
      return Buffer.from(value).toString("base64");
    if (Array.isArray(value)) return value.map(normalize);
    if (value && typeof value === "object")
      return Object.fromEntries(
        Object.keys(value)
          .sort()
          .map((k) => [k, normalize(value[k])]),
      );
    return typeof value === "bigint" ? value.toString() : value;
  }
  const digest = (rows) =>
    createHash("sha256")
      .update(
        JSON.stringify(
          rows
            .map(normalize)
            .map((row) => JSON.stringify(row))
            .sort(),
        ),
      )
      .digest("hex");
  for (const table of tables) {
    const comparable = (rows) =>
      rows.map((row) =>
        Object.fromEntries(
          types[table].map((column) => {
            const value = row[column.column_name];
            return [
              column.column_name,
              column.udt_name === "int8" && value != null
                ? String(value)
                : value,
            ];
          }),
        ),
      );
    if (
      digest(
        comparable((await client.query(`SELECT * FROM ${quote(table)}`)).rows),
      ) !== digest(comparable(snapshot[table]))
    )
      throw new Error(`Content verification failed for ${table}`);
  }
  const config =
    [
      `AUTH_PROVIDER=supabase`,
      `SUPABASE_URL=https://${project}.supabase.co`,
      "SUPABASE_PUBLISHABLE_KEY=sb_publishable_d6iVFApYyh41BlF9GkTsgw_h0d-chZN",
      `DATABASE_URL=postgresql://booking_api.${project}:${rolePassword}@${host}:5432/postgres`,
      "DATABASE_SCHEMA=booking_app",
      "DATABASE_SSL=true",
      `DATABASE_CA_FILE=${resolve(local, "supabase-ca.crt")}`,
      "DATABASE_MIGRATE=false",
      "PORT=3000",
      "APP_BIND_HOST=127.0.0.1",
      "PUBLIC_APP_URL=http://localhost:8080",
      `BOOKING_QUOTE_SECRET=${randomBytes(48).toString("base64url")}`,
    ].join("\n") + "\n";
  // Keep the candidate separate until runtime verification passes.
  writeFileSync(resolve(local, "supabase-server.env"), config, { mode: 0o600 });
  await client.query("COMMIT");
  transaction = false;
  const report = {
    project,
    created_at: new Date().toISOString(),
    backup,
    counts: Object.fromEntries(tables.map((t) => [t, snapshot[t].length])),
    ledger_total_minor: totals,
    identity_claims: identities.length,
    tls_verified: true,
  };
  writeFileSync(
    resolve(local, "supabase-migration-verification.json"),
    JSON.stringify(report, null, 2),
    { mode: 0o600 },
  );
  console.log(
    JSON.stringify({
      success: true,
      backup,
      counts: report.counts,
      tls_verified: true,
    }),
  );
} catch (error) {
  if (transaction) await client.query("ROLLBACK").catch(() => {});
  // Do not leak SQL parameters, customer data or credentials on failure.
  console.error(
    "Migration failed:",
    error.code || error.name,
    String(error.message).replaceAll(password, "[redacted]"),
  );
  process.exitCode = 1;
} finally {
  await source?.close();
  await client.end();
}
