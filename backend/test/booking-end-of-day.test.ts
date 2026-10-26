import { before, beforeEach, after, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { PGlite } from "@electric-sql/pglite";

const name = "20261026055830_booking_end_of_day_checkins.sql";
const store = new PGlite();
const activation = "2026-10-26T06:00:00Z";
const midnight = "2026-10-26T18:30:00Z";
async function foundation(db: PGlite) {
  await db.exec(`CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE booking_api;
    CREATE TABLE locations(id uuid PRIMARY KEY,timezone text NOT NULL);
    CREATE TABLE businesses(id uuid PRIMARY KEY,location_id uuid REFERENCES locations(id));
    CREATE TABLE bookings(id uuid PRIMARY KEY,business_id uuid REFERENCES businesses(id),status text DEFAULT 'confirmed',admission_id uuid,
      starts_at timestamptz,ends_at timestamptz,total_minor int DEFAULT 10000,version int DEFAULT 1,price_snapshot jsonb DEFAULT '{}');
    CREATE TABLE booking_history(id uuid PRIMARY KEY,booking_id uuid REFERENCES bookings(id),actor_id text,action text,details jsonb,created_at timestamptz DEFAULT now());
    CREATE TABLE booking_payments(id uuid PRIMARY KEY,booking_id uuid REFERENCES bookings(id),amount_minor int);
    CREATE TABLE finance_events(id uuid PRIMARY KEY,amount_minor int);
    GRANT SELECT,INSERT,UPDATE ON bookings,booking_history TO booking_api;`);
}
before(async () => {
  await foundation(store);
  await store.exec(readFileSync(`migrations/${name}`, "utf8"));
});
beforeEach(async () => {
  await store.exec(
    "DELETE FROM booking_history; DELETE FROM booking_payments; DELETE FROM bookings; DELETE FROM businesses; DELETE FROM locations; DELETE FROM finance_events;",
  );
  await store.query(
    "UPDATE booking_checkin_automation SET enabled=true,enabled_at=$1",
    [activation],
  );
});
after(() => store.close());
async function booking(
  options: {
    timezone?: string;
    end?: string;
    status?: string;
    admission?: boolean;
    checked?: boolean;
    snapshotTimezone?: string;
  } = {},
) {
  const id = randomUUID(),
    business = randomUUID(),
    location = randomUUID();
  await store.query("INSERT INTO locations VALUES($1,$2)", [
    location,
    options.timezone ?? "Asia/Kolkata",
  ]);
  await store.query("INSERT INTO businesses VALUES($1,$2)", [
    business,
    location,
  ]);
  await store.query(
    "INSERT INTO bookings(id,business_id,status,admission_id,starts_at,ends_at,price_snapshot) VALUES($1,$2,$3,$4,$5,$6,$7)",
    [
      id,
      business,
      options.status ?? "confirmed",
      options.admission ? randomUUID() : null,
      "2026-10-25T00:00:00Z",
      options.end ?? "2026-10-26T16:00:00Z",
      JSON.stringify(
        options.snapshotTimezone ? { timezone: options.snapshotTimezone } : {},
      ),
    ],
  );
  if (options.checked)
    await store.query(
      "INSERT INTO booking_history VALUES($1,$2,'owner','checked_in','{}',$3)",
      [randomUUID(), id, "2026-10-26T15:00:00Z"],
    );
  return id;
}
async function run(time = midnight, limit = 500) {
  return (
    await store.query<{ count: number }>(
      "SELECT booking_end_of_day_checkins($1,$2) AS count",
      [time, limit],
    )
  ).rows[0].count;
}
test("midnight fallback preserves booking status, money, times and ledger and runs once", async () => {
  const id = await booking();
  await store.query("INSERT INTO booking_payments VALUES($1,$2,4000)", [
    randomUUID(),
    id,
  ]);
  await store.query("INSERT INTO finance_events VALUES($1,4000)", [
    randomUUID(),
  ]);
  const previous = (
    await store.query("SELECT * FROM bookings WHERE id=$1", [id])
  ).rows[0];
  assert.equal(await run("2026-10-26T18:29:59Z"), 0);
  assert.equal(await run(), 1);
  assert.equal(await run(), 0);
  assert.deepEqual(
    (await store.query("SELECT * FROM bookings WHERE id=$1", [id])).rows[0],
    { ...previous, version: 2 },
  );
  assert.equal(
    (
      await store.query<{ balance: number }>(
        "SELECT total_minor-(SELECT sum(amount_minor)::int FROM booking_payments WHERE booking_id=$1) AS balance FROM bookings WHERE id=$1",
        [id],
      )
    ).rows[0].balance,
    6000,
  );
  assert.equal(
    (await store.query("SELECT amount_minor FROM finance_events")).rows[0]
      .amount_minor,
    4000,
  );
  const history = (
    await store.query("SELECT * FROM booking_history WHERE booking_id=$1", [id])
  ).rows;
  assert.equal(history.length, 1);
  assert.equal(history[0].actor_id, "system:booking_end_of_day");
  assert.equal(history[0].details.source, "automatic_end_of_day");
  assert.equal(history[0].details.booking_date, "2026-10-26");
});
test("cancelled, no-show, completed, manual arrivals and admission visits are skipped", async () => {
  await booking({ status: "cancelled" });
  await booking({ status: "no_show" });
  await booking({ status: "completed" });
  await booking({ checked: true });
  await booking({ admission: true });
  assert.equal(await run(), 0);
  assert.equal(
    (await store.query("SELECT count(*)::int count FROM booking_history"))
      .rows[0].count,
    1,
  );
});
test("activation day is included without backfilling earlier days or future bookings", async () => {
  await booking({ end: "2026-10-25T16:00:00Z" });
  await booking({ end: "2026-10-25T18:30:00Z" });
  await booking({ end: "2026-10-28T16:00:00Z" });
  await booking({ end: "2026-10-26T04:00:00Z" });
  assert.equal(await run(), 1);
});
test("overnight bookings wait for their end day and midnight-ending bookings belong to the prior day", async () => {
  const overnight = await booking({ end: "2026-10-26T20:00:00Z" });
  const boundary = await booking({ end: midnight });
  assert.equal(await run(), 1);
  assert.equal(
    (await store.query("SELECT booking_id FROM booking_history")).rows[0]
      .booking_id,
    boundary,
  );
  assert.equal(await run("2026-10-27T18:30:00Z"), 1);
  assert.equal(
    (
      await store.query(
        "SELECT count(*)::int count FROM booking_history WHERE booking_id=$1",
        [overnight],
      )
    ).rows[0].count,
    1,
  );
});
test("each booking uses its saved business timezone, with location fallback and daylight saving", async () => {
  await booking();
  await booking({ timezone: "America/New_York", end: "2026-10-26T17:00:00Z" });
  await booking({ timezone: "UTC", snapshotTimezone: "Asia/Kolkata" });
  assert.equal(await run(), 2);
  assert.equal(await run("2026-10-27T04:00:00Z"), 1);
  await store.query(
    "UPDATE booking_checkin_automation SET enabled_at='2026-10-31T06:00:00Z'",
  );
  await booking({ timezone: "America/New_York", end: "2026-11-01T07:00:00Z" });
  assert.equal(await run("2026-11-02T04:59:59Z"), 0);
  assert.equal(await run("2026-11-02T05:00:00Z"), 1);
});
test("bounded batches catch up safely, while pause and invalid inputs prevent writes", async () => {
  await booking();
  await booking();
  await booking();
  assert.equal(await run(midnight, 2), 2);
  assert.equal(await run(midnight, 2), 1);
  assert.equal(await run(midnight, 2), 0);
  await booking();
  await store.exec("UPDATE booking_checkin_automation SET enabled=false");
  assert.equal(await run(), 0);
  await assert.rejects(() => run(midnight, 0), /batch limit/);
  await assert.rejects(() => run("infinity"), /finite run time/);
});
test("automatic writes are private, API booking access remains, and duplicate arrivals are prohibited", async () => {
  for (const role of ["anon", "authenticated", "booking_api"]) {
    const access = (
      await store.query(
        "SELECT has_function_privilege($1,'booking_end_of_day_checkins(timestamptz,integer)','EXECUTE') AS execute,has_table_privilege($1,'booking_checkin_automation','SELECT') AS read",
        [role],
      )
    ).rows[0];
    assert.equal(access.execute, false);
    assert.equal(access.read, false);
  }
  assert.equal(
    (
      await store.query(
        "SELECT has_table_privilege('booking_api','bookings','UPDATE') AS access",
      )
    ).rows[0].access,
    true,
  );
  const id = await booking({ checked: true });
  await assert.rejects(
    () =>
      store.query(
        "INSERT INTO booking_history VALUES($1,$2,'owner','checked_in','{}',now())",
        [randomUUID(), id],
      ),
    /unique constraint/,
  );
});
test("production migration schedules one bounded private job and retains a verifiable marker", async () => {
  const db = new PGlite();
  try {
    await db.exec(
      "CREATE SCHEMA booking_app; SET search_path=booking_app,pg_catalog;",
    );
    await foundation(db);
    await db.exec(`CREATE TABLE admissions(id uuid PRIMARY KEY); CREATE TABLE schema_migrations(name text PRIMARY KEY);
      CREATE SCHEMA cron; CREATE TABLE cron.job(jobid bigint GENERATED ALWAYS AS IDENTITY,jobname text UNIQUE,schedule text,command text);
      CREATE FUNCTION cron.schedule(text,text,text) RETURNS bigint LANGUAGE sql AS 'INSERT INTO cron.job(jobname,schedule,command) VALUES($1,$2,$3) RETURNING jobid';`);
    const sql = readFileSync(`../supabase/migrations/${name}`, "utf8");
    const extensionGuard =
      "IF NOT EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_cron') THEN";
    assert.equal(sql.split(extensionGuard).length, 2);
    await db.exec(sql.replace(extensionGuard, "IF false THEN"));
    const job = (await db.query("SELECT * FROM cron.job")).rows[0];
    assert.equal(job.jobname, "booking-end-of-day-checkins");
    assert.equal(job.schedule, "* * * * *");
    assert.match(String(job.command), /statement_timeout='45s'/);
    assert.equal(
      (await db.query("SELECT name FROM booking_app.schema_migrations")).rows[0]
        .name,
      name,
    );
    assert.equal(
      (
        await db.query(
          "SELECT prosecdef FROM pg_proc WHERE oid='booking_app.booking_end_of_day_checkins(timestamptz,integer)'::regprocedure",
        )
      ).rows[0].prosecdef,
      false,
    );
    assert.equal(
      (
        await db.query(
          "SELECT has_function_privilege('anon','booking_app.booking_end_of_day_checkins(timestamptz,integer)','EXECUTE') AS access",
        )
      ).rows[0].access,
      false,
    );
    assert.equal(
      (
        await db.query(
          "SELECT relrowsecurity FROM pg_class WHERE oid='booking_app.booking_checkin_automation'::regclass",
        )
      ).rows[0].relrowsecurity,
      true,
    );
    await db.exec("SET search_path=public,pg_catalog");
    assert.equal(
      (
        await db.query(
          "SELECT booking_app.booking_end_of_day_checkins() AS count",
        )
      ).rows[0].count,
      0,
    );
  } finally {
    await db.close();
  }
});
