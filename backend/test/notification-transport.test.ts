import { test } from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync, verify, randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { PGlite } from "@electric-sql/pglite";
import {
  FcmSender,
  PushFailure,
  type PushMessage,
} from "../src/notifications/fcm-sender";

const message: PushMessage = {
  token: "device-token-fixture",
  eventId: randomUUID(),
  bookingId: randomUUID(),
  userId: "owner",
  kind: "created",
  reference: "BK-TEST",
  details: {
    customer_name: "Arun",
    space_name: "Turf 1",
    starts_at: "2026-10-24T12:30:00Z",
    ends_at: "2026-10-24T13:30:00Z",
    timezone: "Asia/Kolkata",
  },
};
const keys = generateKeyPairSync("rsa", { modulusLength: 2048 });
async function withCredentials(work: () => Promise<void>) {
  const previous = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  process.env.FIREBASE_SERVICE_ACCOUNT_JSON = JSON.stringify({
    project_id: "notification-fixture",
    client_email: "sender@notification-fixture.iam.gserviceaccount.com",
    private_key: keys.privateKey.export({ format: "pem", type: "pkcs8" }),
  });
  try {
    await work();
  } finally {
    if (previous === undefined)
      delete process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
    else process.env.FIREBASE_SERVICE_ACCOUNT_JSON = previous;
  }
}
test("FCM v1 signs OAuth assertion, caches access and targets only the supplied installation", async () =>
  withCredentials(async () => {
    let oauth = 0,
      sends = 0;
    const sender = new FcmSender((async (url, options) => {
      if (String(url).includes("oauth2.googleapis.com")) {
        oauth++;
        const assertion = (options!.body as URLSearchParams).get("assertion")!;
        const [header, payload, signature] = assertion.split(".");
        assert.equal(
          verify(
            "RSA-SHA256",
            Buffer.from(`${header}.${payload}`),
            keys.publicKey,
            Buffer.from(signature, "base64url"),
          ),
          true,
        );
        const claims = JSON.parse(Buffer.from(payload, "base64url").toString());
        assert.equal(
          claims.scope,
          "https://www.googleapis.com/auth/firebase.messaging",
        );
        assert.equal(claims.aud, "https://oauth2.googleapis.com/token");
        return Response.json({
          access_token: "short-lived-token",
          expires_in: 3600,
        });
      }
      sends++;
      assert.equal(
        String(url),
        "https://fcm.googleapis.com/v1/projects/notification-fixture/messages:send",
      );
      assert.equal(
        (options!.headers as Record<string, string>).authorization,
        "Bearer short-lived-token",
      );
      const body = JSON.parse(options!.body as string).message;
      assert.equal(body.token, message.token);
      assert.equal(body.data.recipient_user_id, "owner");
      assert.equal(body.data.booking_id, message.bookingId);
      assert.equal(body.data.event_id, message.eventId);
      const titles: Record<string, string> = {
        created: "Order placed",
        cancelled: "Order cancelled",
        rescheduled: "Order rescheduled",
      };
      assert.equal(body.notification.title, titles[body.data.event_type]);
      assert.equal(
        body.notification.body,
        "Name: Arun\nSpace: Turf 1\nTime: 24 Oct 2026, 6:00 PM IST – 7:00 PM IST\nBK-TEST",
      );
      assert.deepEqual(Object.keys(body.data).sort(), [
        "booking_id",
        "event_id",
        "event_type",
        "recipient_user_id",
      ]);
      assert.equal(
        body.android.notification.channel_id,
        "booking_orders_bell_v2",
      );
      assert.equal(body.android.notification.sound, "new_booking_bell");
      assert.equal(body.android.notification.default_sound, undefined);
      assert.equal(body.apns.payload.aps.sound, "default");
      assert.equal(body.topic, undefined);
      assert.equal(body.condition, undefined);
      return Response.json({ name: "projects/fixture/messages/1" });
    }) as typeof fetch);
    await sender.send(message);
    await sender.send(message);
    await sender.send({ ...message, kind: "cancelled" });
    await sender.send({ ...message, kind: "rescheduled" });
    assert.equal(oauth, 1);
    assert.equal(sends, 4);
  }));
test("FCM only invalidates explicit UNREGISTERED errors and honors provider retry delays", async () =>
  withCredentials(async () => {
    let status = 404,
      code = "UNREGISTERED";
    const sender = new FcmSender((async (url) => {
      if (String(url).includes("oauth2.googleapis.com"))
        return Response.json({ access_token: "token", expires_in: 3600 });
      return Response.json(
        {
          error: {
            details: [
              {
                "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
                errorCode: code,
              },
            ],
          },
        },
        { status, headers: { "retry-after": "120" } },
      );
    }) as typeof fetch);
    await assert.rejects(
      () => sender.send(message),
      (error: unknown) =>
        error instanceof PushFailure && error.unregistered && !error.retryable,
    );
    status = 400;
    code = "INVALID_ARGUMENT";
    await assert.rejects(
      () => sender.send(message),
      (error: unknown) =>
        error instanceof PushFailure && !error.unregistered && !error.retryable,
    );
    status = 429;
    code = "QUOTA_EXCEEDED";
    await assert.rejects(
      () => sender.send(message),
      (error: unknown) =>
        error instanceof PushFailure &&
        !error.unregistered &&
        error.retryable &&
        error.retryAfterSeconds === 120,
    );
  }));
test("hosted migration creates only private RLS tables and grants the restricted runtime role", async () => {
  const sql = new PGlite();
  await sql.waitReady;
  try {
    await sql.exec(`CREATE SCHEMA booking_app;
      CREATE ROLE booking_api; CREATE ROLE anon; CREATE ROLE authenticated;
      GRANT USAGE ON SCHEMA booking_app TO booking_api,anon,authenticated;
      SET search_path=booking_app,pg_catalog;
      CREATE TABLE schema_migrations(name text PRIMARY KEY);
      CREATE TABLE organizations(id uuid PRIMARY KEY);
      CREATE TABLE businesses(id uuid,organization_id uuid,PRIMARY KEY(id,organization_id));
      CREATE TABLE resources(id uuid,business_id uuid,organization_id uuid,PRIMARY KEY(id,business_id,organization_id));
      CREATE TABLE bookings(id uuid PRIMARY KEY);
      CREATE TABLE booking_history(id uuid PRIMARY KEY);`);
    await sql.exec(
      readFileSync(
        "../supabase/migrations/20261023071831_firebase_booking_notifications.sql",
        "utf8",
      ),
    );
    const tables = await sql.query<{
      relname: string;
      relrowsecurity: boolean;
    }>(
      `SELECT relname,relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='booking_app' AND relname IN ('notification_devices','booking_notification_events','notification_deliveries')`,
    );
    assert.equal(tables.rows.length, 3);
    assert.ok(tables.rows.every((t) => t.relrowsecurity));
    assert.equal(
      (await sql.query("SELECT * FROM booking_app.schema_migrations")).rows
        .length,
      1,
    );
    await sql.exec("SET ROLE booking_api");
    await sql.query(
      "INSERT INTO booking_app.notification_devices(id,user_id,proof_hash,token,platform) VALUES($1,'owner',$2,$3,'android')",
      [randomUUID(), "a".repeat(64), "device-token-fixture-long"],
    );
    assert.equal(
      (await sql.query("SELECT id FROM booking_app.notification_devices")).rows
        .length,
      1,
    );
    await assert.rejects(
      () => sql.query("DELETE FROM booking_app.notification_devices"),
      /permission denied/,
    );
    await sql.exec("RESET ROLE;SET ROLE anon");
    await assert.rejects(
      () => sql.query("SELECT * FROM booking_app.notification_devices"),
      /permission denied/,
    );
    await sql.exec("RESET ROLE;SET ROLE authenticated");
    await assert.rejects(
      () => sql.query("SELECT * FROM booking_app.notification_devices"),
      /permission denied/,
    );
    await sql.exec("RESET ROLE");
  } finally {
    await sql.close();
  }
});
