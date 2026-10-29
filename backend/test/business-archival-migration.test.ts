import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { PGlite } from "@electric-sql/pglite";

test("hosted archival migration preserves rows and private privileges and enforces archive metadata/name reuse", async () => {
  const db = new PGlite();
  const id = "00000000-0000-4000-8000-000000000001";
  try {
    await db.exec(`CREATE ROLE booking_api; CREATE ROLE anon; CREATE ROLE authenticated;
      CREATE SCHEMA booking_app; GRANT USAGE ON SCHEMA booking_app TO booking_api;
      CREATE TABLE booking_app.schema_migrations(name text PRIMARY KEY);
      CREATE TABLE booking_app.businesses(id uuid PRIMARY KEY,organization_id uuid NOT NULL,name text NOT NULL,
        status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','ready','paused')),configuration jsonb,
        UNIQUE(organization_id,name));
      ALTER TABLE booking_app.businesses ENABLE ROW LEVEL SECURITY;
      CREATE POLICY api_access ON booking_app.businesses TO booking_api USING (true) WITH CHECK (true);
      GRANT SELECT,UPDATE ON booking_app.businesses TO booking_api;
      INSERT INTO booking_app.businesses(id,organization_id,name,status,configuration)
        VALUES('${id}','${id}','Arena','ready','{"saved":true}');`);
    await db.exec(
      readFileSync(
        "../supabase/migrations/20261029082454_business_archival.sql",
        "utf8",
      ),
    );
    const rows = (await db.query<any>("SELECT * FROM booking_app.businesses"))
      .rows;
    assert.equal(rows.length, 1);
    assert.equal(rows[0].status, "ready");
    assert.deepEqual(rows[0].configuration, { saved: true });
    assert.equal(rows[0].archived_at, null);
    assert.equal(rows[0].archived_by, null);
    await assert.rejects(
      () => db.exec("UPDATE booking_app.businesses SET status='archived'"),
      /check constraint/,
    );
    await assert.rejects(
      () => db.exec("UPDATE booking_app.businesses SET archived_at=now()"),
      /check constraint/,
    );
    await assert.rejects(
      () =>
        db.exec(
          `INSERT INTO booking_app.businesses(id,organization_id,name) VALUES('00000000-0000-4000-8000-000000000002','${id}','Arena')`,
        ),
      /unique constraint/,
    );
    await db.exec("SET ROLE booking_api");
    await db.exec(
      "UPDATE booking_app.businesses SET status='archived',archived_at=now(),archived_by='owner'",
    );
    assert.equal(
      (await db.query<any>("SELECT status FROM booking_app.businesses")).rows[0]
        .status,
      "archived",
    );
    await db.exec("RESET ROLE");
    await db.exec(
      `INSERT INTO booking_app.businesses(id,organization_id,name) VALUES('00000000-0000-4000-8000-000000000002','${id}','Arena')`,
    );
    const access = (
      await db.query<any>(`SELECT relrowsecurity,
      has_table_privilege('anon',oid,'SELECT') AS anon_read,
      has_table_privilege('authenticated',oid,'SELECT') AS auth_read
      FROM pg_class WHERE oid='booking_app.businesses'::regclass`)
    ).rows[0];
    assert.equal(access.relrowsecurity, true);
    assert.equal(access.anon_read, false);
    assert.equal(access.auth_read, false);
    assert.equal(
      (await db.query("SELECT * FROM booking_app.schema_migrations")).rows
        .length,
      1,
    );
  } finally {
    await db.close();
  }
});
