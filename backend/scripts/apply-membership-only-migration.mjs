import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import pg from "pg";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const project = "scwwkaywewecspsrskft";
const migration = "20261026042821_membership_only_plans.sql";
const source = readFileSync(
  resolve(root, "supabase/migrations", migration),
  "utf8",
);
const digest = (value) => createHash("sha256").update(value).digest("hex");
const apply = process.argv.includes("--apply");
const linked = JSON.parse(
  readFileSync(resolve(root, "supabase/.temp/linked-project.json"), "utf8"),
);
if (linked.ref !== project)
  throw new Error("Unexpected linked project; refusing migration.");
if (!/^BEGIN;\s/.test(source) || !/COMMIT;\s*$/.test(source))
  throw new Error("Unexpected migration transaction wrapper.");
const body = source.replace(/^BEGIN;\s*/, "").replace(/COMMIT;\s*$/, "");
const password = readFileSync(
  resolve(root, ".local/supabase-db-password.txt"),
  "utf8",
).trim();
if (!password) throw new Error("Existing database credential is empty.");
const client = new pg.Client({
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
  application_name: "booking-membership-migration",
});
const tables = [
  "admissions",
  "admission_payments",
  "admission_history",
  "customers",
  "bookings",
  "booking_allocations",
  "booking_payments",
  "finance_events",
  "finance_lines",
];
const addedColumns = ["deleted_at", "deleted_by", "deletion_reason"];
let transaction = false;
let committed = false;
let backupFolder;

async function snapshot() {
  const result = {};
  for (const table of tables) {
    const expression =
      table === "admissions"
        ? "to_jsonb(t)-ARRAY['deleted_at','deleted_by','deletion_reason']"
        : "to_jsonb(t)";
    result[table] = (
      await client.query(
        `SELECT ${expression} AS row FROM booking_app.${table} t ORDER BY (${expression})::text`,
      )
    ).rows.map((entry) => entry.row);
  }
  return result;
}

async function definitions() {
  return {
    columns: (
      await client.query(
        "SELECT column_name,data_type,is_nullable,column_default FROM information_schema.columns WHERE table_schema='booking_app' AND table_name='admissions' ORDER BY ordinal_position",
      )
    ).rows,
    constraints: (
      await client.query(
        "SELECT conname,pg_get_constraintdef(oid) AS definition FROM pg_constraint WHERE conrelid='booking_app.admissions'::regclass ORDER BY conname",
      )
    ).rows,
    indexes: (
      await client.query(
        "SELECT indexname,indexdef FROM pg_indexes WHERE schemaname='booking_app' AND tablename='admissions' ORDER BY indexname",
      )
    ).rows,
    view: (
      await client.query(
        "SELECT pg_get_viewdef(oid,true) AS definition,reloptions,relacl,pg_get_userbyid(relowner) AS owner FROM pg_class WHERE oid='booking_app.admission_balances'::regclass",
      )
    ).rows[0],
    privacy: (
      await client.query(
        "SELECT relname,relrowsecurity,relforcerowsecurity FROM pg_class WHERE oid IN ('booking_app.admissions'::regclass,'booking_app.admission_payments'::regclass,'booking_app.admission_history'::regclass) ORDER BY relname",
      )
    ).rows,
  };
}

async function validate() {
  const columns = (
    await client.query(
      "SELECT column_name,data_type FROM information_schema.columns WHERE table_schema='booking_app' AND table_name='admissions' AND column_name=ANY($1::text[]) ORDER BY column_name",
      [addedColumns],
    )
  ).rows;
  if (
    columns.length !== 3 ||
    !columns.some(
      (column) =>
        column.column_name === "deleted_at" &&
        column.data_type === "timestamp with time zone",
    )
  )
    throw new Error("Membership deletion columns failed validation.");
  const constraints = (
    await client.query(
      "SELECT conname,pg_get_constraintdef(oid) AS definition FROM pg_constraint WHERE conrelid='booking_app.admissions'::regclass AND conname IN ('admissions_mode_check','admissions_allowance_check','admissions_deletion_metadata_check') ORDER BY conname",
    )
  ).rows;
  if (
    constraints.length !== 3 ||
    !constraints
      .find((entry) => entry.conname === "admissions_mode_check")
      ?.definition.includes("membership") ||
    !constraints
      .find((entry) => entry.conname === "admissions_allowance_check")
      ?.definition.includes("membership")
  )
    throw new Error("Membership constraints failed validation.");
  const access = (
    await client.query(
      "SELECT reloptions,has_table_privilege('booking_api',oid,'SELECT') AS api_read,has_table_privilege('anon',oid,'SELECT') AS anonymous_read,has_table_privilege('authenticated',oid,'SELECT') AS authenticated_read FROM pg_class WHERE oid='booking_app.admission_balances'::regclass",
    )
  ).rows[0];
  if (
    !access?.reloptions?.includes("security_invoker=true") ||
    !access.api_read ||
    access.anonymous_read ||
    access.authenticated_read
  )
    throw new Error("Private view access failed validation.");
  const runtime = (
    await client.query(
      "SELECT bool_and(has_column_privilege('booking_api','booking_app.admissions',column_name,'SELECT') AND has_column_privilege('booking_api','booking_app.admissions',column_name,'UPDATE')) AS can_access FROM information_schema.columns WHERE table_schema='booking_app' AND table_name='admissions' AND column_name=ANY($1::text[])",
      [addedColumns],
    )
  ).rows[0];
  if (!runtime.can_access)
    throw new Error("Runtime privileges do not cover new metadata.");
  const index = (
    await client.query(
      "SELECT i.indisvalid,i.indisready FROM pg_index i WHERE i.indexrelid=to_regclass('booking_app.admissions_expiry_attention_idx')",
    )
  ).rows[0];
  if (!index?.indisvalid || !index.indisready)
    throw new Error("Expiry index failed validation.");
  const invalid = (
    await client.query(
      "SELECT count(*)::int AS count FROM booking_app.admission_balances WHERE (mode='membership' AND (allowance<>0 OR used<>0 OR remaining<>0)) OR (deleted_at IS NOT NULL AND status<>'deleted')",
    )
  ).rows[0].count;
  if (invalid !== 0) throw new Error("Membership balances failed validation.");
  const markers = (
    await client.query(
      "SELECT count(*)::int AS count FROM booking_app.schema_migrations WHERE name=$1",
      [migration],
    )
  ).rows[0].count;
  if (markers !== 1) throw new Error("Migration marker failed validation.");
  return {
    columns,
    constraints,
    access,
    runtime,
    index,
    invalid_balances: invalid,
    migration_markers: markers,
  };
}

try {
  await client.connect();
  if (
    !client.connection.stream.encrypted ||
    !client.connection.stream.authorized
  )
    throw new Error("Certificate-verified TLS required.");
  await client.query(
    apply
      ? "BEGIN ISOLATION LEVEL REPEATABLE READ"
      : "BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY",
  );
  transaction = true;
  await client.query("SET LOCAL search_path=booking_app,pg_catalog");
  await client.query("SET LOCAL lock_timeout='10s'");
  await client.query("SET LOCAL statement_timeout='45s'");
  if (apply)
    await client.query(
      "SELECT pg_advisory_xact_lock(hashtext('booking_app.schema_migrations'))",
    );
  const objects = (
    await client.query(
      "SELECT to_regclass('booking_app.admissions') AS admissions,to_regclass('booking_app.admission_balances') AS balances,to_regclass('booking_app.schema_migrations') AS migrations",
    )
  ).rows[0];
  if (!objects.admissions || !objects.balances || !objects.migrations)
    throw new Error("Prerequisite admissions schema is missing.");
  const applied =
    (
      await client.query(
        "SELECT 1 FROM booking_app.schema_migrations WHERE name=$1",
        [migration],
      )
    ).rowCount > 0;
  if (applied) {
    const verification = await validate();
    await client.query("ROLLBACK");
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
    const beforeSchema = await definitions();
    if (
      beforeSchema.columns.some((column) =>
        addedColumns.includes(column.column_name),
      ) ||
      beforeSchema.constraints.some((constraint) =>
        constraint.definition.includes("'membership'"),
      )
    )
      throw new Error(
        "Partial membership schema detected; refusing automatic changes.",
      );
    const dependents = (
      await client.query(
        "SELECT DISTINCT c.oid FROM pg_depend d JOIN pg_rewrite r ON r.oid=d.objid JOIN pg_class c ON c.oid=r.ev_class WHERE d.refobjid='booking_app.admission_balances'::regclass AND c.oid<>d.refobjid",
      )
    ).rows;
    if (dependents.length)
      throw new Error(
        "Dependent views require review before replacing admission_balances.",
      );
    if (apply)
      await client.query(
        "LOCK TABLE booking_app.admissions IN ACCESS EXCLUSIVE MODE",
      );
    const beforeData = await snapshot();
    const counts = Object.fromEntries(
      Object.entries(beforeData).map(([table, rows]) => [table, rows.length]),
    );
    if (!apply) {
      await client.query("ROLLBACK");
      transaction = false;
      console.log(
        JSON.stringify({
          status: "preflight_passed",
          project,
          migration,
          migration_sha256: digest(source),
          counts,
          schema_change_required: true,
        }),
      );
    } else {
      backupFolder = resolve(
        root,
        ".local/releases",
        `membership-only-${new Date().toISOString().replaceAll(":", "-")}`,
      );
      mkdirSync(backupFolder, { recursive: true, mode: 0o700 });
      const save = (name, value) =>
        writeFileSync(resolve(backupFolder, name), value, {
          mode: 0o600,
          flag: "wx",
        });
      save(migration, source);
      save("pre-migration-schema.json", JSON.stringify(beforeSchema, null, 2));
      save("pre-migration-data.json", JSON.stringify(beforeData, null, 2));
      save(
        "manifest.json",
        JSON.stringify(
          {
            project,
            migration,
            migration_sha256: digest(source),
            data_sha256: digest(JSON.stringify(beforeData)),
            counts,
            captured_at: new Date().toISOString(),
          },
          null,
          2,
        ),
      );
      save(
        "recovery.txt",
        "This is a private, consistent logical snapshot of the affected admissions, customer, booking and finance tables plus pre-migration definitions and grants. It is not a full project or Auth backup. A failure before COMMIT rolls back the migration. After COMMIT, preserve membership/deletion data, stop affected writes and use a reviewed forward fix. Do not restore snapshot rows over newer bookings or payments. No automatic rollback or restoration is authorized by this runner.\n",
      );
      await client.query(body);
      const verification = await validate();
      const afterData = await snapshot();
      if (
        digest(JSON.stringify(beforeData)) !== digest(JSON.stringify(afterData))
      )
        throw new Error("Existing records changed unexpectedly; rolling back.");
      const afterSchema = await definitions();
      if (
        JSON.stringify(beforeSchema.privacy) !==
        JSON.stringify(afterSchema.privacy)
      )
        throw new Error("Existing row security changed unexpectedly.");
      save(
        "validated-before-commit.json",
        JSON.stringify(
          { verification, counts, existing_records_unchanged: true },
          null,
          2,
        ),
      );
      await client.query("COMMIT");
      transaction = false;
      committed = true;
      const confirmed = await validate();
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
          verification: confirmed,
          backup_folder: backupFolder,
        }),
      );
    }
  }
} catch (error) {
  if (transaction) await client.query("ROLLBACK").catch(() => {});
  console.error(
    JSON.stringify({
      status: committed ? "committed_recheck_required" : "not_applied",
      project,
      migration,
      error: String(error.message)
        .replaceAll(password, "[REDACTED]")
        .replace(/postgres(?:ql)?:\/\/\S+/g, "[connection redacted]"),
      backup_folder: backupFolder,
    }),
  );
  process.exitCode = 1;
} finally {
  await client.end();
}
