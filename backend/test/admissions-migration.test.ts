import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { PGlite } from "@electric-sql/pglite";

test("production migration grants only the private API role and empty-only recovery retains normal bookings", async () => {
  const store = new PGlite();
  await store.waitReady;
  try {
    await store.exec(
      "CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE booking_api; CREATE SCHEMA booking_app; SET search_path=booking_app,pg_catalog; CREATE TABLE schema_migrations(name text PRIMARY KEY,applied_at timestamptz DEFAULT now()); GRANT USAGE ON SCHEMA booking_app TO booking_api;",
    );
    for (const name of readdirSync("migrations")
      .filter((n) => n.endsWith(".sql") && n < "20261020120000_admissions.sql")
      .sort())
      await store.exec(readFileSync("migrations/" + name, "utf8"));
    // Match the existing production role's access to application tables.
    await store.exec(
      "GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA booking_app TO booking_api;",
    );
    await store.exec(
      readFileSync(
        "../supabase/migrations/20261020120000_admissions.sql",
        "utf8",
      ),
    );
    const grants = await store.query<any>(
      "SELECT has_table_privilege('anon','booking_app.admissions','SELECT') AS anon,has_table_privilege('authenticated','booking_app.admission_balances','SELECT') AS authenticated,has_table_privilege('booking_api','booking_app.admission_balances','SELECT') AS api",
    );
    assert.equal(grants.rows[0].anon, false);
    assert.equal(grants.rows[0].authenticated, false);
    assert.equal(grants.rows[0].api, true);
    await store.exec("SET ROLE booking_api;");
    assert.equal(
      (await store.query("SELECT * FROM booking_app.admission_balances")).rows
        .length,
      0,
    );
    await store.exec("RESET ROLE;");
    assert.equal(
      (
        await store.query<any>(
          "SELECT count(*)::int n FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='booking_app' AND c.relname IN ('admissions','admission_payments','admission_history') AND c.relrowsecurity",
        )
      ).rows[0].n,
      3,
    );
    await store.exec(
      readFileSync(
        "../supabase/manual-recovery/rollback-admissions-empty.sql",
        "utf8",
      ),
    );
    assert.equal(
      (
        await store.query<any>(
          "SELECT to_regclass('booking_app.admissions') AS name",
        )
      ).rows[0].name,
      null,
    );
    assert.equal(
      (
        await store.query<any>(
          "SELECT to_regclass('booking_app.bookings') AS name",
        )
      ).rows[0].name,
      "bookings",
    );
  } finally {
    await store.close();
  }
});
