import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { NotificationService } from "../src/notifications/notification.service";
import { NotificationDispatcher } from "../src/notifications/notification-dispatcher";
import { enqueueBookingNotification } from "../src/notifications/notification-events";
import { PushFailure, type PushMessage } from "../src/notifications/fcm-sender";
import { notificationHandler } from "../edge/notifications-handler";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  devices = new NotificationService(db),
  workspace = new WorkspaceService(db);
before(() => db.onModuleInit());
after(() => db.onModuleDestroy());
const actor = () => ({
  uid: randomUUID(),
  email: `${randomUUID()}@example.com`,
  name: "Owner",
});
const device = () => ({
  installation_id: randomUUID(),
  installation_secret:
    randomUUID().replaceAll("-", "") + randomUUID().replaceAll("-", ""),
  token: randomUUID() + randomUUID(),
  platform: "android",
});
async function fixture() {
  const owner = actor();
  await workspace.createOrganization(owner, {
    name: "Notifications",
    contact_phone: "9876543210",
    currency: "INR",
    location: {
      name: "Kochi",
      address_line_1: "Main Road",
      address_line_2: null,
      city: "Kochi",
      state_code: "KL",
      country_code: "IN",
      postal_code: "682001",
      timezone: "Asia/Kolkata",
    },
  });
  const w = await workspace.workspace(owner),
    org = w.organization!.id;
  const business = await workspace.createBusiness(owner, {
    name: "Court",
    type: "badminton",
    location_id: w.locations[0].id,
  });
  const resource = randomUUID(),
    otherResource = randomUUID(),
    customer = randomUUID(),
    booking = randomUUID();
  for (const id of [resource, otherResource])
    await db.query(
      "INSERT INTO resources(id,organization_id,business_id,name) VALUES($1,$2,$3,$4)",
      [id, org, business.id, id],
    );
  await db.query(
    "INSERT INTO customers(id,organization_id,name,phone) VALUES($1,$2,'Customer','9876543210')",
    [customer, org],
  );
  await db.query(
    `INSERT INTO bookings(id,organization_id,business_id,resource_id,customer_id,reference,starts_at,ends_at,total_minor,selection,price_snapshot,customer_snapshot,people,created_by)
    VALUES($1,$2,$3,$4,$5,'BK-TEST',now(),now()+interval '1 hour',0,'{}','{}','{}',1,$6)`,
    [booking, org, business.id, resource, customer, owner.uid],
  );
  return {
    owner,
    org,
    business: business.id,
    resource,
    otherResource,
    booking,
  };
}
async function event(f: Awaited<ReturnType<typeof fixture>>, kind = "created") {
  const id = randomUUID();
  await db.transaction(async (tx) => {
    await tx.query(
      "INSERT INTO booking_history(id,booking_id,actor_id,action,details) VALUES($1,$2,$3,$4,'{}')",
      [id, f.booking, f.owner.uid, kind],
    );
    await enqueueBookingNotification(tx, id);
  });
  return id;
}
async function staff(
  f: Awaited<ReturnType<typeof fixture>>,
  permissions: string[],
  resource?: string,
  active = true,
) {
  const user = actor(),
    id = randomUUID();
  await db.query(
    "INSERT INTO memberships(id,organization_id,user_id,email,display_name,role,permissions,active) VALUES($1,$2,$3,$4,'Staff','staff',$5,$6)",
    [id, f.org, user.uid, user.email, JSON.stringify(permissions), active],
  );
  if (resource)
    await db.query(
      "INSERT INTO staff_assignments(membership_id,organization_id,business_id,resource_ids) VALUES($1,$2,$3,$4)",
      [id, f.org, f.business, JSON.stringify([resource])],
    );
  await devices.register(user, device());
  return user;
}
test("device proof, rotation, rebinding and logged-out cleanup protect account ownership", async () => {
  const a = actor(),
    b = actor(),
    d = device();
  await devices.register(a, d);
  await devices.register(a, d);
  await assert.rejects(() =>
    devices.register(b, { ...d, installation_secret: "0".repeat(64) }),
  );
  await assert.rejects(() =>
    devices.register(b, { ...device(), token: d.token }),
  );
  await devices.register(a, { ...d, token: randomUUID() + randomUUID() });
  await devices.unregister(b, d.installation_id, {
    installation_secret: d.installation_secret,
  });
  assert.equal(
    (
      await db.query("SELECT enabled FROM notification_devices WHERE id=$1", [
        d.installation_id,
      ])
    ).rows[0].enabled,
    true,
  );
  await devices.register(b, d);
  assert.equal(
    (
      await db.query("SELECT user_id FROM notification_devices WHERE id=$1", [
        d.installation_id,
      ])
    ).rows[0].user_id,
    b.uid,
  );
  await devices.revokeInstallation({
    installation_id: d.installation_id,
    installation_secret: "0".repeat(64),
  });
  assert.equal(
    (
      await db.query("SELECT enabled FROM notification_devices WHERE id=$1", [
        d.installation_id,
      ])
    ).rows[0].enabled,
    true,
  );
  await devices.revokeInstallation({
    installation_id: d.installation_id,
    installation_secret: d.installation_secret,
  });
  assert.equal(
    (
      await db.query("SELECT enabled FROM notification_devices WHERE id=$1", [
        d.installation_id,
      ])
    ).rows[0].enabled,
    false,
  );
});
test("all three events target only owner and currently authorized resource staff across devices", async () => {
  const f = await fixture(),
    other = await fixture(),
    sent: PushMessage[] = [];
  await devices.register(f.owner, device());
  await devices.register(f.owner, device());
  const allowed = await staff(f, ["manage_bookings"], f.resource);
  await staff(f, ["view_bookings"], f.resource);
  await staff(f, ["manage_bookings"], f.otherResource);
  await staff(f, ["manage_bookings"]);
  await staff(f, ["manage_bookings"], f.resource, false);
  await devices.register(other.owner, device());
  const dispatcher = new NotificationDispatcher(db, {
    send: async (m) => {
      sent.push(m);
    },
  });
  const ids = [];
  for (const kind of ["created", "cancelled", "rescheduled"])
    ids.push(await event(f, kind));
  for (const id of ids) await enqueueBookingNotification(db, id);
  await event(f, "checked_in");
  await dispatcher.dispatch(40);
  const ours = sent.filter((m) => ids.includes(m.eventId));
  assert.equal(ours.length, 9);
  assert.deepEqual(
    new Set(ours.map((m) => m.userId)),
    new Set([f.owner.uid, allowed.uid]),
  );
  await dispatcher.dispatch(40);
  assert.equal(sent.length, 9);
});
test("rollback enqueues nothing and pending deliveries recheck permission, logout and expiry", async () => {
  const f = await fixture(),
    sent: PushMessage[] = [];
  await devices.register(f.owner, device());
  const staffUser = await staff(f, ["manage_bookings"], f.resource);
  const rolled = randomUUID();
  await assert.rejects(() =>
    db.transaction(async (tx) => {
      await tx.query(
        "INSERT INTO booking_history(id,booking_id,actor_id,action,details) VALUES($1,$2,$3,'created','{}')",
        [rolled, f.booking, f.owner.uid],
      );
      await enqueueBookingNotification(tx, rolled);
      throw new Error("rollback");
    }),
  );
  assert.equal(
    (
      await db.query("SELECT id FROM booking_notification_events WHERE id=$1", [
        rolled,
      ])
    ).rows.length,
    0,
  );
  const id = await event(f);
  const first = new NotificationDispatcher(db, {
    send: async () => {
      throw new PushFailure("FCM_NETWORK", true);
    },
  });
  await first.dispatch(40);
  await db.query("UPDATE memberships SET permissions='[]' WHERE user_id=$1", [
    staffUser.uid,
  ]);
  await db.query(
    "UPDATE notification_deliveries SET next_attempt_at=now() WHERE event_id=$1",
    [id],
  );
  const result = await new NotificationDispatcher(db, {
    send: async (m) => {
      sent.push(m);
    },
  }).dispatch(40);
  assert.equal(result.skipped, 1);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].userId, f.owner.uid);
  const expired = await event(f);
  await db.query(
    "UPDATE booking_notification_events SET created_at=now()-interval '25 hours' WHERE id=$1",
    [expired],
  );
  await new NotificationDispatcher(db, {
    send: async (m) => {
      sent.push(m);
    },
  }).dispatch(40);
  assert.equal(sent.length, 1);
});
test("unregistered response cannot disable a newly refreshed token; generic failures preserve tokens", async () => {
  const f = await fixture(),
    d = device();
  await devices.register(f.owner, d);
  const id = await event(f);
  await new NotificationDispatcher(db, {
    send: async () => {
      await devices.register(f.owner, {
        ...d,
        token: randomUUID() + randomUUID(),
      });
      throw new PushFailure("UNREGISTERED", false, true);
    },
  }).dispatch(40);
  assert.equal(
    (
      await db.query("SELECT enabled FROM notification_devices WHERE id=$1", [
        d.installation_id,
      ])
    ).rows[0].enabled,
    true,
  );
  assert.equal(
    (
      await db.query(
        "SELECT state FROM notification_deliveries WHERE event_id=$1",
        [id],
      )
    ).rows[0].state,
    "dead",
  );
});
test("dispatch endpoint requires internal secret and cannot accept client-selected recipients", async () => {
  const previous = process.env.BOOKING_PUSH_DISPATCH_SECRET,
    enabled = process.env.BOOKING_PUSH_DISPATCH_ENABLED;
  process.env.BOOKING_PUSH_DISPATCH_SECRET = "a".repeat(64);
  process.env.BOOKING_PUSH_DISPATCH_ENABLED = "true";
  let calls = 0;
  const handler = notificationHandler({
    dispatch: async (limit: number) => {
      assert.equal(limit, 20);
      calls++;
      return { sent: 1 };
    },
  } as never);
  try {
    assert.equal(
      (await handler(new Request("https://example.com", { method: "POST" })))
        .status,
      401,
    );
    assert.equal(calls, 0);
    assert.equal(
      (
        await handler(
          new Request("https://example.com", {
            method: "POST",
            headers: { "x-booking-push-secret": "a".repeat(64) },
            body: '{"tokens":["other-device"]}',
          }),
        )
      ).status,
      200,
    );
    assert.equal(calls, 1);
  } finally {
    if (previous === undefined) delete process.env.BOOKING_PUSH_DISPATCH_SECRET;
    else process.env.BOOKING_PUSH_DISPATCH_SECRET = previous;
    if (enabled === undefined) delete process.env.BOOKING_PUSH_DISPATCH_ENABLED;
    else process.env.BOOKING_PUSH_DISPATCH_ENABLED = enabled;
  }
});

test("concurrent dispatch skips live leases; expired leases recover and attempts stop at eight", async () => {
  const f = await fixture(),
    d = device();
  await devices.register(f.owner, d);
  const id = await event(f);
  let started!: () => void, release!: () => void;
  const sending = new Promise<void>((resolve) => {
    started = resolve;
  });
  const held = new Promise<void>((resolve) => {
    release = resolve;
  });
  const first = new NotificationDispatcher(db, {
    send: async () => {
      started();
      await held;
    },
  }).dispatch(40);
  await sending;
  const second = await new NotificationDispatcher(db, {
    send: async () => {
      assert.fail("Live lease sent twice");
    },
  }).dispatch(40);
  assert.equal(second.claimed, 0);
  release();
  await first;
  const recovering = await event(f, "rescheduled");
  const failing = new NotificationDispatcher(db, {
    send: async () => {
      throw new PushFailure("FCM_NETWORK", true);
    },
  });
  await failing.dispatch(40);
  await db.query(
    "UPDATE notification_deliveries SET state='processing',lease_until=now()-interval '1 second',lease_id=$2,attempts=7 WHERE event_id=$1",
    [recovering, randomUUID()],
  );
  const exhausted = await failing.dispatch(40);
  assert.equal(exhausted.dead, 1);
  assert.equal(
    (
      await db.query(
        "SELECT state,attempts FROM notification_deliveries WHERE event_id=$1",
        [recovering],
      )
    ).rows[0].attempts,
    8,
  );
  assert.equal((await failing.dispatch(40)).claimed, 0);
  assert.equal(
    (
      await db.query("SELECT enabled FROM notification_devices WHERE id=$1", [
        d.installation_id,
      ])
    ).rows[0].enabled,
    true,
  );
});
