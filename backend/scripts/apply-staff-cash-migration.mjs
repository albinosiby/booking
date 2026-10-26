import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import pg from "pg";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const project = "scwwkaywewecspsrskft";
const migration = "20261026100000_staff_cash_settlements.sql";
const source = readFileSync(
  resolve(root, "supabase/migrations", migration),
  "utf8",
);
const apply = process.argv.includes("--apply");
if (
  JSON.parse(
    readFileSync(resolve(root, "supabase/.temp/linked-project.json"), "utf8"),
  ).ref !== project
)
  throw new Error("Unexpected project; refusing connection.");
if (!/^BEGIN;\s/.test(source) || !/COMMIT;\s*$/.test(source))
  throw new Error("Unexpected migration transaction wrapper.");
const body = source.replace(/^BEGIN;\s*/, "").replace(/COMMIT;\s*$/, "");
const db = new pg.Client({
  host: "aws-0-ap-northeast-1.pooler.supabase.com",
  port: 5432,
  user: `postgres.${project}`,
  database: "postgres",
  password: readFileSync(
    resolve(root, ".local/supabase-db-password.txt"),
    "utf8",
  ).trim(),
  ssl: {
    rejectUnauthorized: true,
    ca: readFileSync(resolve(root, ".local/supabase-ca.crt"), "utf8"),
  },
  connectionTimeoutMillis: 15000,
  application_name: "staff-cash-migration",
});
await db.connect();
try {
  const applied = (
    await db.query(
      "SELECT count(*)::int c FROM booking_app.schema_migrations WHERE name=$1",
      [migration],
    )
  ).rows[0].c;
  const exists = (
    await db.query(
      "SELECT to_regclass('booking_app.staff_cash_settlements') t, to_regclass('booking_app.staff_cash_tracking') k",
    )
  ).rows[0];
  const orgs = (
    await db.query("SELECT count(*)::int c FROM booking_app.organizations")
  ).rows[0].c;
  console.log({ applied, exists, orgs, apply });
  if (applied || exists.t || exists.k)
    throw new Error("Migration already applied or tables exist; refusing.");
  if (apply) {
    await db.query("BEGIN");
    try {
      await db.query(body);
      const v = (
        await db.query(
          `SELECT (SELECT count(*)::int FROM booking_app.staff_cash_tracking) tracked,
        (SELECT count(*)::int FROM booking_app.staff_cash_settlements) settled,
        (SELECT count(*)::int FROM booking_app.schema_migrations WHERE name=$1) marker,
        has_table_privilege('booking_api','booking_app.staff_cash_settlements','INSERT') api_insert,
        has_table_privilege('anon','booking_app.staff_cash_settlements','SELECT') anon_read,
        has_table_privilege('authenticated','booking_app.staff_cash_settlements','SELECT') auth_read`,
          [migration],
        )
      ).rows[0];
      console.log(v);
      if (
        v.tracked !== orgs ||
        v.settled !== 0 ||
        v.marker !== 1 ||
        !v.api_insert ||
        v.anon_read ||
        v.auth_read
      )
        throw new Error("Post-migration validation failed; rolling back.");
      await db.query("COMMIT");
      console.log("Migration committed.");
    } catch (e) {
      await db.query("ROLLBACK");
      throw e;
    }
  }
} finally {
  await db.end();
}
