import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import pg from "pg";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const project = "scwwkaywewecspsrskft";
const migration = "20261026055830_booking_end_of_day_checkins.sql";
const jobName = "booking-end-of-day-checkins";
const source = readFileSync(
  resolve(root, "supabase/migrations", migration),
  "utf8",
);
const hash = (value) => createHash("sha256").update(value).digest("hex");
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
const password = readFileSync(
  resolve(root, ".local/supabase-db-password.txt"),
  "utf8",
).trim();
if (!password) throw new Error("Existing database credential is empty.");
const db = new pg.Client({
  host: "aws-0-ap-northeast-1.pooler.supabase.com",
  port: 5432,
  user: `postgres.${project}`,
  database: "postgres",
  password,
  ssl: {
    rejectUnauthorized: true,
    ca: readFileSync(resolve(root, ".local/supabase-ca.crt"), "utf8"),
  },
  connectionTimeoutMillis: 15000,
  application_name: "booking-eod-migration",
});
const tables = [
  "bookings",
  "booking_history",
  "booking_payments",
  "booking_allocations",
  "customers",
  "finance_events",
  "finance_lines",
  "admissions",
  "admission_payments",
  "admission_history",
];
let transaction = false;
let committed = false;
let folder;
async function snapshot() {
  const result = {};
  for (const table of tables)
    result[table] = (
      await db.query(
        `SELECT to_jsonb(t) AS row FROM booking_app.${table} t ORDER BY to_jsonb(t)::text`,
      )
    ).rows.map((entry) => entry.row);
  return result;
}
async function runtimeAccess() {
  return (
    await db.query(
      "SELECT name,has_table_privilege('booking_api','booking_app.'||name,'SELECT') AS read,has_table_privilege('booking_api','booking_app.'||name,'INSERT') AS insert,has_table_privilege('booking_api','booking_app.'||name,'UPDATE') AS update FROM (VALUES ('bookings'),('booking_history'),('booking_payments'),('finance_events'),('finance_lines')) objects(name) ORDER BY name",
    )
  ).rows;
}
async function verify() {
  const setting = (
    await db.query(
      "SELECT enabled,enabled_at FROM booking_app.booking_checkin_automation",
    )
  ).rows;
  if (setting.length !== 1 || !setting[0].enabled)
    throw new Error("Expected one enabled automation setting.");
  const job = (
    await db.query(
      "SELECT jobid,jobname,schedule,active,username,database,command FROM cron.job WHERE jobname=$1",
      [jobName],
    )
  ).rows;
  const expectedCommand = source.match(/\$job\$([\s\S]*?)\$job\$/)?.[1];
  if (
    job.length !== 1 ||
    !job[0].active ||
    job[0].schedule !== "* * * * *" ||
    job[0].username !== "postgres" ||
    job[0].database !== "postgres" ||
    job[0].command !== expectedCommand
  )
    throw new Error("Scheduled job failed validation.");
  const functionState = (
    await db.query(
      "SELECT prosecdef,proconfig FROM pg_proc WHERE oid='booking_app.booking_end_of_day_checkins(timestamptz,integer)'::regprocedure",
    )
  ).rows[0];
  if (
    functionState.prosecdef ||
    !functionState.proconfig?.includes("search_path=booking_app, pg_catalog")
  )
    throw new Error("Private function configuration failed validation.");
  const access = (
    await db.query(
      "SELECT role_name,has_function_privilege(role_name,'booking_app.booking_end_of_day_checkins(timestamptz,integer)','EXECUTE') AS can_run,has_table_privilege(role_name,'booking_app.booking_checkin_automation','SELECT') AS can_read,has_table_privilege(role_name,'booking_app.booking_checkin_automation','UPDATE') AS can_update FROM (VALUES ('anon'),('authenticated'),('booking_api')) roles(role_name)",
    )
  ).rows;
  if (access.some((role) => role.can_run || role.can_read || role.can_update))
    throw new Error("Automation is exposed to client/API roles.");
  const security = (
    await db.query(
      "SELECT relrowsecurity FROM pg_class WHERE oid='booking_app.booking_checkin_automation'::regclass",
    )
  ).rows[0];
  if (!security.relrowsecurity)
    throw new Error("Automation setting RLS is disabled.");
  const indexes = (
    await db.query(
      "SELECT c.relname,i.indisvalid,i.indisready FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid WHERE c.oid IN (to_regclass('booking_app.booking_single_checkin_idx'),to_regclass('booking_app.booking_end_of_day_candidates_idx')) ORDER BY c.relname",
    )
  ).rows;
  if (
    indexes.length !== 2 ||
    indexes.some((index) => !index.indisvalid || !index.indisready)
  )
    throw new Error("Automation indexes failed validation.");
  const markers = (
    await db.query(
      "SELECT count(*)::int count FROM booking_app.schema_migrations WHERE name=$1",
      [migration],
    )
  ).rows[0].count;
  const duplicates = (
    await db.query(
      "SELECT count(*)::int count FROM (SELECT booking_id FROM booking_app.booking_history WHERE action='checked_in' GROUP BY booking_id HAVING count(*)>1) duplicates",
    )
  ).rows[0].count;
  if (markers !== 1 || duplicates !== 0)
    throw new Error(
      "Migration marker or check-in uniqueness failed validation.",
    );
  return {
    setting: setting[0],
    job: { ...job[0], command: undefined },
    function: functionState,
    client_access: access,
    indexes,
    migration_markers: markers,
    duplicate_checkins: duplicates,
  };
}
try {
  await db.connect();
  if (!db.connection.stream.encrypted || !db.connection.stream.authorized)
    throw new Error("Certificate-verified TLS required.");
  await db.query(
    apply
      ? "BEGIN ISOLATION LEVEL REPEATABLE READ"
      : "BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY",
  );
  transaction = true;
  await db.query("SET LOCAL search_path=booking_app,pg_catalog");
  await db.query("SET LOCAL lock_timeout='10s'");
  await db.query("SET LOCAL statement_timeout='45s'");
  if (apply)
    await db.query(
      "SELECT pg_advisory_xact_lock(hashtext('booking_app.schema_migrations'))",
    );
  const applied =
    (
      await db.query(
        "SELECT 1 FROM booking_app.schema_migrations WHERE name=$1",
        [migration],
      )
    ).rowCount > 0;
  if (applied) {
    const verification = await verify();
    await db.query("ROLLBACK");
    transaction = false;
    console.log(
      JSON.stringify({
        status: "already_applied",
        project,
        migration,
        verification,
      }),
    );
  } else {
    const existing = (
      await db.query(
        "SELECT to_regclass('booking_app.booking_checkin_automation') AS settings,to_regprocedure('booking_app.booking_end_of_day_checkins(timestamptz,integer)') AS function,(SELECT count(*)::int FROM cron.job WHERE jobname=$1) AS jobs",
        [jobName],
      )
    ).rows[0];
    if (existing.settings || existing.function || existing.jobs)
      throw new Error(
        "Partial or conflicting automation exists; refusing changes.",
      );
    if (apply)
      await db.query(
        "LOCK TABLE booking_app.bookings,booking_app.booking_history IN SHARE MODE",
      );
    const before = await snapshot();
    const permissions = await runtimeAccess();
    const counts = Object.fromEntries(
      Object.entries(before).map(([table, rows]) => [table, rows.length]),
    );
    if (!apply) {
      await db.query("ROLLBACK");
      transaction = false;
      console.log(
        JSON.stringify({
          status: "preflight_passed",
          project,
          migration,
          migration_sha256: hash(source),
          counts,
        }),
      );
    } else {
      folder = resolve(
        root,
        ".local/releases",
        `booking-eod-${new Date().toISOString().replaceAll(":", "-")}`,
      );
      mkdirSync(folder, { recursive: true, mode: 0o700 });
      const save = (name, value) =>
        writeFileSync(resolve(folder, name), value, {
          mode: 0o600,
          flag: "wx",
        });
      const schema = (
        await db.query(
          "SELECT c.relname,c.relrowsecurity,c.relacl,pg_get_userbyid(c.relowner) AS owner FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='booking_app' AND c.relname=ANY($1::text[]) ORDER BY c.relname",
          [tables],
        )
      ).rows;
      const indexes = (
        await db.query(
          "SELECT tablename,indexname,indexdef FROM pg_indexes WHERE schemaname='booking_app' AND tablename IN ('bookings','booking_history') ORDER BY tablename,indexname",
        )
      ).rows;
      const constraints = (
        await db.query(
          "SELECT conrelid::regclass::text AS table_name,conname,pg_get_constraintdef(oid) AS definition FROM pg_constraint WHERE conrelid IN ('booking_app.bookings'::regclass,'booking_app.booking_history'::regclass) ORDER BY conrelid,conname",
        )
      ).rows;
      save(migration, source);
      save("pre-migration-data.json", JSON.stringify(before, null, 2));
      save(
        "pre-migration-schema.json",
        JSON.stringify({ schema, indexes, constraints, permissions }, null, 2),
      );
      save(
        "manifest.json",
        JSON.stringify(
          {
            project,
            migration,
            migration_sha256: hash(source),
            data_sha256: hash(JSON.stringify(before)),
            counts,
            captured_at: new Date().toISOString(),
          },
          null,
          2,
        ),
      );
      save(
        "recovery.txt",
        "Private logical snapshot of affected booking/admission/customer/payment/finance records and schema metadata; not a full project/Auth backup. Before COMMIT a failure rolls back everything. After activation, preserve audit/payment records; pause this specific job and automation setting only after authorization. Never delete check-in history or restore stale records over newer payments. See docs/booking-end-of-day-checkins.md.\n",
      );
      await db.query(body);
      const verification = await verify();
      const smoke = (
        await db.query(
          "SELECT booking_app.booking_end_of_day_checkins() AS processed",
        )
      ).rows[0].processed;
      if (smoke !== 0)
        throw new Error(
          "Activation must not backfill earlier days; rolling back.",
        );
      if (
        hash(JSON.stringify(before)) !== hash(JSON.stringify(await snapshot()))
      )
        throw new Error(
          "Existing booking, payment or history records changed; rolling back.",
        );
      if (JSON.stringify(permissions) !== JSON.stringify(await runtimeAccess()))
        throw new Error("Existing runtime privileges changed; rolling back.");
      save(
        "validated-before-commit.json",
        JSON.stringify(
          {
            verification,
            activation_smoke_processed: smoke,
            existing_records_unchanged: true,
          },
          null,
          2,
        ),
      );
      await db.query("COMMIT");
      transaction = false;
      committed = true;
      const confirmed = await verify();
      save(
        "verification.json",
        JSON.stringify(
          {
            status: "applied",
            project,
            migration,
            applied_at: new Date().toISOString(),
            existing_records_unchanged: true,
            verification: confirmed,
          },
          null,
          2,
        ),
      );
      console.log(
        JSON.stringify({
          status: "applied",
          project,
          migration,
          counts,
          existing_records_unchanged: true,
          activation_smoke_processed: smoke,
          verification: confirmed,
          backup_folder: folder,
        }),
      );
    }
  }
} catch (error) {
  if (transaction) await db.query("ROLLBACK").catch(() => {});
  console.error(
    JSON.stringify({
      status: committed ? "committed_recheck_required" : "not_applied",
      project,
      migration,
      error: String(error.message)
        .replaceAll(password, "[REDACTED]")
        .replace(/postgres(?:ql)?:\/\/\S+/g, "[connection redacted]"),
      backup_folder: folder,
    }),
  );
  process.exitCode = 1;
} finally {
  await db.end();
}
