import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { PGlite } from "@electric-sql/pglite";

test("production membership migration preserves old modes, supports zero-allowance memberships and retains private view access", async () => {
  const database = new PGlite();
  try {
    await database.exec(`CREATE ROLE booking_api; CREATE ROLE anon; CREATE ROLE authenticated;
      CREATE SCHEMA booking_app; GRANT USAGE ON SCHEMA booking_app TO booking_api;
      CREATE TABLE booking_app.schema_migrations(name text PRIMARY KEY);
      CREATE TABLE booking_app.admissions(id uuid PRIMARY KEY,organization_id uuid,mode text NOT NULL CHECK(mode IN ('fixed','flexible')),
       allowance int NOT NULL CHECK(allowance BETWEEN 1 AND 10000),cancelled boolean DEFAULT false,timezone text DEFAULT 'UTC',starts_on date DEFAULT CURRENT_DATE,expires_on date DEFAULT CURRENT_DATE);
      CREATE TABLE booking_app.bookings(admission_id uuid,ends_at timestamptz,starts_at timestamptz,admission_waived boolean,admission_attendance text,status text);
      CREATE VIEW booking_app.admission_balances WITH(security_invoker=true) AS SELECT * FROM booking_app.admissions;
      GRANT SELECT ON booking_app.admissions,booking_app.bookings TO booking_api;
      INSERT INTO booking_app.admissions(id,mode,allowance) VALUES('00000000-0000-4000-8000-000000000001','flexible',10);`);
    await database.exec(
      readFileSync(
        "../supabase/migrations/20261026042821_membership_only_plans.sql",
        "utf8",
      ),
    );
    const previous = (
      await database.query<any>(
        "SELECT mode,allowance,deleted_at FROM booking_app.admissions",
      )
    ).rows[0];
    assert.equal(previous.mode, "flexible");
    assert.equal(previous.allowance, 10);
    assert.equal(previous.deleted_at, null);
    await database.exec(
      "INSERT INTO booking_app.admissions(id,mode,allowance) VALUES('00000000-0000-4000-8000-000000000002','membership',0)",
    );
    await database.exec("SET ROLE booking_api");
    const membership = (
      await database.query<any>(
        "SELECT * FROM booking_app.admission_balances WHERE mode='membership'",
      )
    ).rows[0];
    assert.equal(membership.status, "active");
    assert.equal(membership.used, 0);
    assert.equal(membership.remaining, 0);
    await database.exec("RESET ROLE");
    await assert.rejects(
      () =>
        database.exec(
          "INSERT INTO booking_app.admissions(id,mode,allowance) VALUES('00000000-0000-4000-8000-000000000003','fixed',0)",
        ),
      /check constraint/,
    );
    await assert.rejects(
      () =>
        database.exec(
          "UPDATE booking_app.admissions SET deleted_at=now() WHERE mode='membership'",
        ),
      /check constraint/,
    );
    const metadata = (
      await database.query<any>(
        "SELECT reloptions,has_table_privilege('anon',oid,'SELECT') AS anon_read,has_table_privilege('authenticated',oid,'SELECT') AS authenticated_read FROM pg_class WHERE oid='booking_app.admission_balances'::regclass",
      )
    ).rows[0];
    assert.ok(metadata.reloptions.includes("security_invoker=true"));
    assert.equal(metadata.anon_read, false);
    assert.equal(metadata.authenticated_read, false);
  } finally {
    await database.close();
  }
});
