// Targeted, transactional hosted migration; credentials never leave this process.
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { resolve } from "node:path";
import pg from "pg";
const project = "scwwkaywewecspsrskft",
  local = resolve("../.local"),
  name = "004_business_order.sql";
const password = readFileSync(
  resolve(local, "supabase-db-password.txt"),
  "utf8",
).trim();
const client = new pg.Client({
  host: "aws-0-ap-northeast-1.pooler.supabase.com",
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
  "businesses",
  "bookings",
  "booking_payments",
  "finance_events",
  "finance_lines",
];
async function counts() {
  const result = {};
  for (const table of tables)
    result[table] = Number(
      (await client.query(`SELECT count(*) AS count FROM booking_app.${table}`))
        .rows[0].count,
    );
  return result;
}
try {
  await client.connect();
  await client.query("BEGIN ISOLATION LEVEL REPEATABLE READ");
  await client.query("SET LOCAL search_path=booking_app,pg_catalog");
  await client.query("SET LOCAL lock_timeout='10s'");
  await client.query("SET LOCAL statement_timeout='45s'");
  await client.query(
    "SELECT pg_advisory_xact_lock(hashtext('booking_app.schema_migrations'))",
  );
  const applied = (
    await client.query("SELECT name FROM schema_migrations ORDER BY name")
  ).rows.map((r) => r.name);
  const columns = (
    await client.query(
      "SELECT table_name,column_name FROM information_schema.columns WHERE table_schema='booking_app' AND ((table_name='businesses' AND column_name='display_order') OR (table_name='organizations' AND column_name='business_order_revision'))",
    )
  ).rows;
  const before = await counts();
  console.log(
    JSON.stringify({ project, applied, orderColumns: columns, counts: before }),
  );
  if (!process.argv.includes("--apply") || applied.includes(name)) {
    await client.query("ROLLBACK");
    console.log(
      applied.includes(name)
        ? "Already applied; no changes made."
        : "Preflight complete; no changes made.",
    );
  } else {
    if (columns.length)
      throw new Error(
        "Partial schema detected; review before applying migration.",
      );
    const folder = resolve(
      local,
      "releases",
      `business-order-${new Date().toISOString().replaceAll(":", "-")}`,
    );
    mkdirSync(folder, { recursive: true, mode: 0o700 });
    const businesses = (
      await client.query(
        "SELECT id,organization_id,name,type FROM businesses ORDER BY organization_id,name,id",
      )
    ).rows;
    writeFileSync(
      resolve(folder, "pre-migration.json"),
      JSON.stringify({ project, applied, counts: before, businesses }, null, 2),
      { mode: 0o600 },
    );
    const sql = readFileSync(resolve("migrations", name), "utf8");
    writeFileSync(resolve(folder, name), sql, { mode: 0o600 });
    await client.query(sql);
    await client.query("INSERT INTO schema_migrations(name) VALUES($1)", [
      name,
    ]);
    const after = await counts();
    if (JSON.stringify(before) !== JSON.stringify(after))
      throw new Error("Unexpected row count change.");
    const invalid = (
      await client.query(
        "SELECT organization_id FROM businesses GROUP BY organization_id HAVING count(*)<>count(DISTINCT display_order) OR min(display_order)<>0 OR max(display_order)<>count(*)-1",
      )
    ).rows;
    if (invalid.length) throw new Error("Business order verification failed.");
    const runtimeAccess = (
      await client.query(
        "SELECT has_column_privilege('booking_api','booking_app.businesses','display_order','UPDATE') AS order_update,has_column_privilege('booking_api','booking_app.organizations','business_order_revision','UPDATE') AS revision_update",
      )
    ).rows[0];
    if (!runtimeAccess.order_update || !runtimeAccess.revision_update)
      throw new Error("Runtime grants do not cover the new columns.");
    await client.query("COMMIT");
    writeFileSync(
      resolve(folder, "verification.json"),
      JSON.stringify(
        {
          migration: name,
          counts: after,
          runtimeAccess,
          appliedAt: new Date().toISOString(),
        },
        null,
        2,
      ),
      { mode: 0o600 },
    );
    console.log(
      JSON.stringify({
        status: "applied",
        migration: name,
        counts: after,
        runtimeAccess,
        recoveryFolder: folder,
      }),
    );
  }
} catch (error) {
  await client.query("ROLLBACK").catch(() => {});
  console.error(String(error.message).replaceAll(password, "[REDACTED]"));
  process.exitCode = 1;
} finally {
  await client.end();
}
