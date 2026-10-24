import fs from "node:fs";
import path from "node:path";
import { parseEnv } from "node:util";
import { createHash } from "node:crypto";
import pg from "pg";
import { PGlite } from "@electric-sql/pglite";

const root = path.resolve(import.meta.dirname, "../..");
const manifest = JSON.parse(
  fs.readFileSync(
    path.join(root, "docs/audits/2026-10-24-live-qa-preview.json"),
    "utf8",
  ),
);
const metadata =
  process.argv[2] === "apply"
    ? JSON.parse(
        fs.readFileSync(path.join(process.argv[3], "backup.json"), "utf8"),
      ).metadata
    : JSON.parse(fs.readFileSync("/tmp/booking-qa-schema.json", "utf8"));
const settings = parseEnv(
  fs.readFileSync(path.join(root, ".local/supabase-server.env"), "utf8"),
);
const approved = new Set(
  manifest.candidateOrganizations.map((record) => record.id),
);
const quote = (name) => '"' + name.replaceAll('"', '""') + '"';
const tablePath = (name) => `booking_app.${quote(name)}`;
const columns = (value) =>
  Array.isArray(value) ? value : value.slice(1, -1).split(",");
const digest = (rows) =>
  createHash("sha256")
    .update(JSON.stringify(rows.map((row) => row.json).sort()))
    .digest("hex");
const requireCondition = (condition, message) => {
  if (!condition) throw new Error(message);
};
requireCondition(
  approved.size === 51 && manifest.project === "scwwkaywewecspsrskft",
  "Approval manifest mismatch",
);
requireCondition(
  new URL(settings.SUPABASE_URL).hostname === `${manifest.project}.supabase.co`,
  "Wrong live project",
);
requireCondition(
  metadata.constraints.every(
    (constraint) =>
      constraint.child_schema === "booking_app" &&
      constraint.parent_schema === "booking_app",
  ),
  "External dependency requires review",
);
requireCondition(
  metadata.tables.every((table) =>
    table.columns.every((column) => !column.generated && !column.identity),
  ),
  "Generated columns require review",
);
requireCondition(
  metadata.triggers?.length === 0,
  "User triggers require review before cleanup",
);

const administrator = process.argv.includes("--administrator");
const connectionOptions = administrator
  ? {
      host: "aws-0-ap-northeast-1.pooler.supabase.com",
      port: 5432,
      user: `postgres.${manifest.project}`,
      database: "postgres",
      password: fs
        .readFileSync(
          path.join(root, ".local/supabase-db-password.txt"),
          "utf8",
        )
        .trim(),
    }
  : { connectionString: settings.DATABASE_URL };
const pool = new pg.Pool({
  ...connectionOptions,
  max: 1,
  connectionTimeoutMillis: 10000,
  query_timeout: 30000,
  ssl: {
    rejectUnauthorized: true,
    ca: fs.readFileSync(settings.DATABASE_CA_FILE, "utf8"),
  },
});

async function snapshot(database) {
  const result = {};
  for (const table of metadata.tables) {
    const response = await database.query(
      `SELECT row_to_json(record)::text AS json FROM ${tablePath(table.name)} record`,
    );
    result[table.name] = response.rows.map((record) => ({
      json: record.json,
      value: JSON.parse(record.json),
    }));
  }
  return result;
}

function plan(data) {
  const candidates = data.organizations.filter((record) =>
    approved.has(record.value.id),
  );
  requireCondition(candidates.length === 51, "Candidate count changed");
  for (const record of candidates) {
    const original = manifest.candidateOrganizations.find(
      (candidate) => candidate.id === record.value.id,
    );
    requireCondition(
      record.value.name === original.name,
      "Candidate organization renamed",
    );
    const members = data.memberships.filter(
      (member) => member.value.organization_id === record.value.id,
    );
    requireCondition(
      members.some((member) => member.value.role === "owner"),
      "Candidate owner missing",
    );
    requireCondition(
      members.every((member) =>
        member.value.email.toLowerCase().endsWith("@example.com"),
      ),
      "Non-QA membership detected",
    );
  }
  const selected = Object.fromEntries(
    metadata.tables.map((table) => [table.name, new Set()]),
  );
  for (const table of metadata.tables) {
    data[table.name].forEach((record, index) => {
      if (
        table.name === "organizations"
          ? approved.has(record.value.id)
          : approved.has(record.value.organization_id)
      )
        selected[table.name].add(index);
    });
  }
  let changed = true;
  while (changed) {
    changed = false;
    for (const constraint of metadata.constraints) {
      const parentColumns = columns(constraint.parent_columns),
        childColumns = columns(constraint.child_columns);
      const parentKeys = new Set(
        [...selected[constraint.parent]].map((index) =>
          JSON.stringify(
            parentColumns.map(
              (column) => data[constraint.parent][index].value[column],
            ),
          ),
        ),
      );
      data[constraint.child].forEach((record, index) => {
        if (selected[constraint.child].has(index)) return;
        const values = childColumns.map((column) => record.value[column]);
        if (
          values.some((value) => value === null || value === undefined) ||
          !parentKeys.has(JSON.stringify(values))
        )
          return;
        requireCondition(
          !record.value.organization_id ||
            approved.has(record.value.organization_id),
          "Cross-organization dependency detected",
        );
        selected[constraint.child].add(index);
        changed = true;
      });
    }
  }
  const counts = Object.fromEntries(
    Object.entries(selected).map(([table, indexes]) => [table, indexes.size]),
  );
  for (const [table, count] of Object.entries({
    organizations: 51,
    memberships: 55,
    businesses: 50,
    bookings: 13,
    customers: 13,
  }))
    requireCondition(
      counts[table] === count,
      `Approved ${table} count changed`,
    );
  requireCondition(
    selected.platform_admins.size === 0 &&
      selected.notification_devices.size === 0 &&
      selected.schema_migrations.size === 0,
    "Global identity/schema scope exceeded",
  );
  const protectedOrganizations = data.organizations.filter(
    (record) => !approved.has(record.value.id),
  );
  requireCondition(
    protectedOrganizations.some((record) => record.value.name === "JK Group") &&
      protectedOrganizations.some(
        (record) => record.value.name === "RK Groups",
      ),
    "Protected organizations missing",
  );
  const visiting = new Set(),
    visited = new Set(),
    order = [];
  function visit(table) {
    if (visited.has(table)) return;
    requireCondition(
      !visiting.has(table),
      "Cross-table dependency cycle requires review",
    );
    visiting.add(table);
    for (const constraint of metadata.constraints.filter(
      (item) => item.parent === table && item.child !== table,
    ))
      visit(constraint.child);
    visiting.delete(table);
    visited.add(table);
    order.push(table);
  }
  for (const table of metadata.tables) visit(table.name);
  return { selected, counts, order };
}

function selectedRows(data, planValue, table) {
  return [...planValue.selected[table]].map((index) => data[table][index]);
}
function deletion(table, rows) {
  const keys = metadata.keys.find((key) => key.table_name === table)?.columns;
  requireCondition(keys?.length, `Primary key missing for ${table}`);
  const matches = keys
    .map((column) => `target.${quote(column)} = saved.${quote(column)}`)
    .join(" AND ");
  return {
    sql: `DELETE FROM ${tablePath(table)} target WHERE EXISTS (SELECT 1 FROM json_populate_recordset(NULL::${tablePath(table)},$1::json) saved WHERE ${matches})`,
    values: ["[" + rows.map((row) => row.json).join(",") + "]"],
  };
}
async function remove(database, data, planValue) {
  for (const table of planValue.order) {
    const rows = selectedRows(data, planValue, table);
    if (!rows.length) continue;
    const query = deletion(table, rows);
    const result = await database.query(
      query.sql + " RETURNING 1",
      query.values,
    );
    requireCondition(
      result.rows.length === rows.length,
      `Delete count mismatch for ${table}`,
    );
  }
}
function verifyRemaining(before, after, planValue) {
  for (const table of metadata.tables) {
    const preserved = before[table.name].filter(
      (record, index) => !planValue.selected[table.name].has(index),
    );
    requireCondition(
      digest(preserved) === digest(after[table.name]),
      `Protected data mismatch in ${table.name}`,
    );
  }
}
async function insert(database, table, rows) {
  if (!rows.length) return;
  const names = metadata.tables
    .find((record) => record.name === table)
    .columns.map((column) => quote(column.name))
    .join(",");
  await database.query(
    `INSERT INTO ${tablePath(table)} (${names}) SELECT ${names} FROM json_populate_recordset(NULL::${tablePath(table)},$1::json)`,
    ["[" + rows.map((row) => row.json).join(",") + "]"],
  );
}
async function rehearse(data, planValue, saved) {
  const local = new PGlite();
  try {
    await local.exec(
      "CREATE SCHEMA booking_app; SET search_path=booking_app,pg_catalog; SET TIME ZONE 'UTC'",
    );
    for (const table of metadata.tables)
      await local.exec(
        `CREATE TABLE ${tablePath(table.name)} (${table.columns.map((column) => `${quote(column.name)} ${column.type}`).join(",")})`,
      );
    for (const table of metadata.tables)
      await insert(local, table.name, data[table.name]);
    for (const definition of metadata.definitions.filter(
      (record) => record.type !== "f",
    ))
      await local.exec(
        `ALTER TABLE ${tablePath(definition.table_name)} ADD CONSTRAINT ${quote(definition.name)} ${definition.definition}`,
      );
    for (const index of metadata.indexes) await local.exec(index.definition);
    for (const definition of metadata.definitions.filter(
      (record) => record.type === "f",
    ))
      await local.exec(
        `ALTER TABLE ${tablePath(definition.table_name)} ADD CONSTRAINT ${quote(definition.name)} ${definition.definition}`,
      );
    const imported = await snapshot(local);
    for (const table of metadata.tables)
      requireCondition(
        digest(imported[table.name]) === saved.originalHashes[table.name],
        `Snapshot import mismatch in ${table.name}`,
      );
    await remove(local, data, planValue);
    verifyRemaining(data, await snapshot(local), planValue);
    for (const table of [...planValue.order].reverse())
      await insert(local, table, saved.rows[table] ?? []);
    const restored = await snapshot(local);
    for (const table of metadata.tables)
      requireCondition(
        digest(data[table.name]) === digest(restored[table.name]),
        `Backup restore mismatch in ${table.name}`,
      );
    return "delete and backup restore passed with primary/unique/foreign-key constraints";
  } finally {
    await local.close();
  }
}

const mode = process.argv[2];
requireCondition(
  ["prepare", "apply"].includes(mode),
  "Specify prepare or apply",
);
const connection = await pool.connect();
try {
  await connection.query(
    mode === "apply"
      ? "BEGIN ISOLATION LEVEL REPEATABLE READ"
      : "BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY",
  );
  await connection.query(
    "SET LOCAL statement_timeout='30s'; SET LOCAL lock_timeout='5s'; SET LOCAL TIME ZONE 'UTC'",
  );
  const liveTables = await connection.query(
    "SELECT c.relname AS name FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace WHERE ns.nspname='booking_app' AND c.relkind='r' ORDER BY c.relname",
  );
  requireCondition(
    JSON.stringify(liveTables.rows.map((table) => table.name)) ===
      JSON.stringify(metadata.tables.map((table) => table.name)),
    "Table inventory changed",
  );
  const liveTriggers = await connection.query(
    "SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace ns ON ns.oid=c.relnamespace WHERE ns.nspname='booking_app' AND NOT t.tgisinternal",
  );
  requireCondition(
    liveTriggers.rows.length === 0,
    "Live user triggers require review",
  );
  const liveDefinitions = await connection.query(
    "SELECT c.relname AS table_name,con.conname AS name,con.contype AS type,pg_get_constraintdef(con.oid) AS definition FROM pg_constraint con JOIN pg_class c ON c.oid=con.conrelid JOIN pg_namespace ns ON ns.oid=c.relnamespace WHERE ns.nspname='booking_app' AND con.contype IN ('p','u','f') ORDER BY con.contype,c.relname,con.conname",
  );
  requireCondition(
    JSON.stringify(liveDefinitions.rows) ===
      JSON.stringify(metadata.definitions),
    "Constraint inventory changed",
  );
  if (mode === "apply")
    await connection.query(
      "SELECT id FROM booking_app.organizations WHERE id=ANY($1::uuid[]) FOR UPDATE",
      [[...approved]],
    );
  const data = await snapshot(connection),
    planValue = plan(data);
  if (mode === "prepare") {
    const directory = fs.mkdtempSync(
      path.join(root, ".local/backups/approved-qa-cleanup-"),
    );
    fs.chmodSync(directory, 0o700);
    const backup = {
      project: manifest.project,
      createdAt: new Date().toISOString(),
      metadata,
      counts: planValue.counts,
      order: planValue.order,
      originalHashes: Object.fromEntries(
        Object.entries(data).map(([table, rows]) => [table, digest(rows)]),
      ),
      rows: Object.fromEntries(
        metadata.tables.map((table) => [
          table.name,
          selectedRows(data, planValue, table.name),
        ]),
      ),
    };
    const file = path.join(directory, "backup.json");
    fs.writeFileSync(file, JSON.stringify(backup), { mode: 0o600, flag: "wx" });
    const saved = JSON.parse(fs.readFileSync(file, "utf8"));
    const rehearsal = await rehearse(data, planValue, saved);
    fs.writeFileSync(
      path.join(directory, "verification.json"),
      JSON.stringify({
        rehearsal,
        backupSha256: createHash("sha256")
          .update(fs.readFileSync(file))
          .digest("hex"),
        counts: planValue.counts,
      }),
      { mode: 0o600 },
    );
    await connection.query("COMMIT");
    console.log(
      JSON.stringify({
        status: "prepared",
        directory,
        rehearsal,
        counts: planValue.counts,
      }),
    );
  } else {
    const directory = path.resolve(process.argv[3] ?? "");
    requireCondition(
      directory.startsWith(
        path.join(root, ".local/backups/approved-qa-cleanup-"),
      ),
      "Invalid backup directory",
    );
    const backupFile = fs.readFileSync(path.join(directory, "backup.json"));
    const backup = JSON.parse(backupFile),
      verification = JSON.parse(
        fs.readFileSync(path.join(directory, "verification.json"), "utf8"),
      );
    requireCondition(
      createHash("sha256").update(backupFile).digest("hex") ===
        verification.backupSha256,
      "Backup checksum mismatch",
    );
    for (const table of metadata.tables)
      requireCondition(
        digest(selectedRows(data, planValue, table.name)) ===
          digest(backup.rows[table.name]),
        `QA scope drift in ${table.name}`,
      );
    await remove(connection, data, planValue);
    const remaining = await snapshot(connection);
    verifyRemaining(data, remaining, planValue);
    await connection.query("COMMIT");
    const report = {
      status: "committed",
      project: manifest.project,
      completedAt: new Date().toISOString(),
      counts: planValue.counts,
      remaining: {
        organizations: remaining.organizations.length,
        memberships: remaining.memberships.length,
        businesses: remaining.businesses.length,
        bookings: remaining.bookings.length,
        customers: remaining.customers.length,
      },
      preservedOrganizationNames: remaining.organizations.map(
        (record) => record.value.name,
      ),
      protectedRows: "unchanged across every application table",
      backupDirectory: directory,
    };
    fs.writeFileSync(
      path.join(directory, "completion.json"),
      JSON.stringify(report, null, 2),
      { mode: 0o600 },
    );
    console.log(JSON.stringify(report));
  }
} catch (error) {
  await connection.query("ROLLBACK").catch(() => {});
  console.error(
    JSON.stringify({
      status: "rolled_back_or_read_only",
      message: error.message,
    }),
  );
  process.exitCode = 1;
} finally {
  connection.release();
  await pool.end();
}
