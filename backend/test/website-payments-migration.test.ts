import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { PGlite } from "@electric-sql/pglite";

test("production payment migration enforces grants, RLS and submission constraints in isolation", async () => {
  const db = new PGlite();
  try {
    await db.exec(`CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE booking_api;
      CREATE SCHEMA booking_app;
      GRANT USAGE ON SCHEMA booking_app TO booking_api,anon,authenticated;
      CREATE TABLE booking_app.organizations(id uuid PRIMARY KEY);
      CREATE TABLE booking_app.booking_website_spaces(organization_id uuid NOT NULL);
      CREATE TABLE booking_app.bookings(id uuid PRIMARY KEY, organization_id uuid NOT NULL);
      CREATE TABLE booking_app.schema_migrations(name text PRIMARY KEY);`);
    await db.exec(
      readFileSync(
        "../supabase/migrations/20261024135923_website_upi_payments.sql",
        "utf8",
      ),
    );
    const rows = await db.query<{ relrowsecurity: boolean }>(
      "SELECT relrowsecurity FROM pg_class WHERE oid='booking_app.website_payment_settings'::regclass",
    );
    assert.equal(rows.rows[0].relrowsecurity, true);
    const org = "00000000-0000-4000-8000-000000000001";
    await db.query("INSERT INTO booking_app.organizations VALUES($1)", [org]);
    await db.exec("SET ROLE booking_api");
    await db.query(
      "INSERT INTO booking_app.website_payment_settings(organization_id,upi_id) VALUES($1,'fixture@invalid')",
      [org],
    );
    assert.equal(
      (
        await db.query(
          "SELECT upi_id FROM booking_app.website_payment_settings",
        )
      ).rows.length,
      1,
    );
    await assert.rejects(
      () => db.exec("DELETE FROM booking_app.website_payment_settings"),
      /permission denied/,
    );
    await db.exec("RESET ROLE; SET ROLE anon");
    await assert.rejects(
      () => db.exec("SELECT * FROM booking_app.website_payment_settings"),
      /permission denied/,
    );
    await db.exec("RESET ROLE; SET ROLE authenticated");
    await assert.rejects(
      () => db.exec("SELECT * FROM booking_app.website_payment_settings"),
      /permission denied/,
    );
    await db.exec("RESET ROLE");
    await assert.rejects(
      () =>
        db.query(
          "UPDATE booking_app.website_payment_settings SET qr_data=$1,qr_content_type=NULL",
          [Buffer.alloc(24)],
        ),
      /check constraint/,
    );
    await assert.rejects(
      () =>
        db.query(
          "INSERT INTO booking_app.bookings(id,organization_id,website_payment_submission) VALUES($1,$2,'{}')",
          [org, org],
        ),
      /check constraint/,
    );
    await assert.rejects(
      () =>
        db.query(
          "INSERT INTO booking_app.booking_website_spaces(organization_id,payment_required,payment_percentages) VALUES($1,true,ARRAY[NULL]::int[])",
          [org],
        ),
      /check constraint/,
    );
  } finally {
    await db.close();
  }
});
