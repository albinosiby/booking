// Additive expense migration; credentials are read in memory and never printed or copied.
import { readFileSync, readdirSync } from "node:fs";
import pg from "pg";
const local = "../.local",
  project = "scwwkaywewecspsrskft";
const db = new pg.Client({
  host: "aws-0-ap-northeast-1.pooler.supabase.com",
  port: 5432,
  user: `postgres.${project}`,
  database: "postgres",
  password: readFileSync(`${local}/supabase-db-password.txt`, "utf8").trim(),
  ssl: {
    rejectUnauthorized: true,
    ca: readFileSync(`${local}/supabase-ca.crt`, "utf8"),
  },
  connectionTimeoutMillis: 15000,
});
try {
  await db.connect();
  const migration = readdirSync("../supabase/migrations").find((n) =>
    n.endsWith("_expenses.sql"),
  );
  const before = await db.query(
    "SELECT count(*)::int AS count FROM booking_app.finance_events",
  );
  const applied = await db.query(
    "SELECT 1 FROM booking_app.schema_migrations WHERE name=$1",
    [migration],
  );
  if (process.argv.includes("--apply") && !applied.rowCount) {
    await db.query("BEGIN");
    try {
      await db.query(
        readFileSync(`../supabase/migrations/${migration}`, "utf8"),
      );
      await db.query(
        "INSERT INTO booking_app.schema_migrations(name) VALUES($1)",
        [migration],
      );
      await db.query("COMMIT");
    } catch (e) {
      await db.query("ROLLBACK");
      throw e;
    }
  }
  const state = await db.query(
    "SELECT tablename,rowsecurity FROM pg_tables WHERE schemaname='booking_app' AND tablename IN ('expense_categories','expense_attachments')",
  );
  const bucket = await db.query(
    "SELECT id,public,file_size_limit,allowed_mime_types FROM storage.buckets WHERE id='expense-invoices'",
  );
  const after = await db.query(
    "SELECT count(*)::int AS count FROM booking_app.finance_events",
  );
  if (before.rows[0].count !== after.rows[0].count)
    throw new Error("Ledger count changed unexpectedly");
  console.log(
    JSON.stringify({
      existing_ledger_rows: after.rows[0].count,
      migration_applied: !!applied.rowCount || process.argv.includes("--apply"),
      tables: state.rows,
      bucket: bucket.rows,
    }),
  );
} catch (e) {
  console.error(
    "Expense migration failed:",
    e.code ?? e.name,
    e.message?.replace(/postgres(?:ql)?:\/\/\S+/g, "[connection redacted]"),
  );
  process.exitCode = 1;
} finally {
  await db.end();
}
