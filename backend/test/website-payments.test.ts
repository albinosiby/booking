import "reflect-metadata";
import { before, after, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { AccountsService } from "../src/accounts/accounts.service";
import { addDate } from "../src/bookings/booking.inventory";
import { seedWebsite } from "../scripts/website-fixtures";
import { paymentPolicy } from "../src/website/website.payments";

delete process.env.DATABASE_URL;
delete process.env.DATABASE_MIGRATE;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
process.env.BOOKING_WEBSITE_URL = "http://localhost:3000";
const db = new Database();
const png =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jXioAAAAASUVORK5CYII=";
let venue: Awaited<ReturnType<typeof seedWebsite>>;
let accounts: AccountsService;
before(async () => {
  await db.onModuleInit();
  venue = await seedWebsite(db, "upi-payments-test");
  accounts = new AccountsService(db, venue.workspace);
});
after(() => db.onModuleDestroy());
async function choice(time = "10:00") {
  const site = await venue.website.catalog(venue.slug),
    business = site.businesses.find((entry) => entry.type === "badminton")!,
    resource = business.resources[0],
    option = resource.options[0];
  return {
    business,
    resource,
    selection: {
      business_id: business.id,
      resource_id: resource.id,
      option_id: option.id,
      date: addDate(business.today, 2),
      time,
      duration_minutes: option.default_duration,
      people: 1,
    },
  };
}
async function policy(required: boolean, percentages: number[]) {
  const settings = await venue.website.settings(venue.owner),
    selected = await choice();
  return venue.website.save(venue.owner, {
    version: settings.version,
    slug: settings.slug,
    title: settings.title,
    description: settings.description,
    contact_phone: settings.contact_phone,
    instructions: settings.instructions,
    cancellation_policy: settings.cancellation_policy,
    publish_logo: settings.publish_logo,
    notice_minutes: settings.notice_minutes,
    advance_days: settings.advance_days,
    business_ids: settings.businesses
      .filter((entry) => entry.enabled)
      .map((entry) => entry.id),
    spaces: [
      {
        business_id: selected.business.id,
        resource_id: selected.resource.id,
        visible: true,
        notice_minutes: null,
        advance_days: null,
        rules: "",
        payment_required: required,
        payment_percentages: percentages,
      },
    ],
  });
}
test("mandatory collection needs payment details and valid distinct percentages", async () => {
  await assert.rejects(() => policy(true, [50, 100]), /UPI ID and QR/);
  await assert.rejects(() => policy(true, [50, 50]), /distinct/);
  const saved = await accounts.saveWebsitePayments(venue.owner, {
    version: 0,
    upi_id: "venue@bank",
    qr: { content_type: "image/png", base64: png },
  });
  assert.equal(saved.has_qr, true);
  assert.equal(
    (await venue.website.paymentQr(venue.slug)).content_type,
    "image/png",
  );
  await assert.rejects(
    () =>
      accounts.saveWebsitePayments(venue.owner, {
        version: 0,
        upi_id: "other@bank",
      }),
    /changed/,
  );
  await policy(true, [25, 50, 100]);
  await assert.rejects(
    () =>
      accounts.saveWebsitePayments(venue.owner, {
        version: saved.version,
        upi_id: "",
        qr: null,
      }),
    /Turn off/,
  );
});
test("older website clients cannot erase a mandatory payment policy by omitting its fields", async () => {
  const settings = await venue.website.settings(venue.owner);
  const saved = await venue.website.save(venue.owner, {
    version: settings.version,
    slug: settings.slug,
    title: settings.title,
    description: settings.description,
    contact_phone: settings.contact_phone,
    instructions: settings.instructions,
    cancellation_policy: settings.cancellation_policy,
    publish_logo: settings.publish_logo,
    notice_minutes: settings.notice_minutes,
    advance_days: settings.advance_days,
    business_ids: settings.businesses
      .filter((entry) => entry.enabled)
      .map((entry) => entry.id),
    spaces: [],
  });
  const selected = await choice();
  const resource = saved.businesses
    .find((entry) => entry.id === selected.business.id)!
    .resources.find((entry: any) => entry.id === selected.resource.id);
  assert.equal(resource.payment_required, true);
  assert.deepEqual(resource.payment_percentages, [25, 50, 100]);
});
test("public quote calculates amounts and booking requires an allowed choice and transaction ID", async () => {
  const { selection } = await choice(),
    quote = await venue.website.quote(venue.slug, { selection });
  assert.equal(quote.payment.required, true);
  assert.deepEqual(
    quote.payment.options.map((entry) => entry.percentage),
    [25, 50, 100],
  );
  assert.equal(
    quote.payment.options[0].amount_minor,
    Math.ceil(quote.total_minor / 4),
  );
  const command = {
    command_key: randomUUID(),
    selection,
    quote_token: quote.quote_token,
    customer: { name: "UPI Customer", phone: "9123456780" },
  };
  await assert.rejects(
    () => venue.website.book(venue.slug, command),
    /transaction ID/,
  );
  await assert.rejects(
    () =>
      venue.website.book(venue.slug, {
        ...command,
        payment: { percentage: 10, transaction_id: "123456789012" },
      }),
    /payment options/,
  );
  await assert.rejects(() =>
    venue.website.book(venue.slug, {
      ...command,
      payment: { percentage: 50, transaction_id: "123" },
    }),
  );
  const paidCommand = {
    ...command,
    payment: { percentage: 50, transaction_id: "upi-test-123456" },
  };
  const result = await venue.website.book(venue.slug, paidCommand);
  assert.equal(result.payment_status, "unpaid");
  assert.equal(
    result.website_payment_submission?.status,
    "pending_verification",
  );
  assert.equal(
    result.website_payment_submission?.transaction_id,
    "UPI-TEST-123456",
  );
  assert.deepEqual(await venue.website.book(venue.slug, paidCommand), result);
  const booking = (
    await db.query<any>(
      "SELECT id,website_payment_submission FROM bookings WHERE reference=$1",
      [result.reference],
    )
  ).rows[0];
  assert.equal(
    booking.website_payment_submission.amount_minor,
    Math.ceil(quote.total_minor / 2),
  );
  assert.equal(
    (
      await db.query("SELECT 1 FROM booking_payments WHERE booking_id=$1", [
        booking.id,
      ])
    ).rows.length,
    0,
  );
});
test("duplicate references are rejected and payment detail changes invalidate old quotes", async () => {
  const { selection } = await choice("12:00"),
    quote = await venue.website.quote(venue.slug, { selection });
  const command = {
    command_key: randomUUID(),
    selection,
    quote_token: quote.quote_token,
    customer: { name: "Second UPI Customer", phone: "9123456781" },
    payment: { percentage: 100, transaction_id: "upi-test-123456" },
  };
  await assert.rejects(
    () => venue.website.book(venue.slug, command),
    /already submitted/,
  );
  const settings = await accounts.websitePayments(venue.owner);
  await accounts.saveWebsitePayments(venue.owner, {
    version: settings.version,
    upi_id: "newvenue@bank",
  });
  await assert.rejects(
    () =>
      venue.website.paymentQr(venue.slug, undefined, String(settings.version)),
    /changed/,
  );
  await assert.rejects(
    () =>
      venue.website.book(venue.slug, {
        ...command,
        payment: { percentage: 100, transaction_id: "987654321012" },
      }),
    /Pricing changed/,
  );
});
test("optional checkout retains pay-at-venue and owner-only settings do not leak across organizations", async () => {
  await policy(false, []);
  const { selection } = await choice("14:00"),
    quote = await venue.website.quote(venue.slug, { selection });
  assert.equal(quote.payment.required, false);
  const result = await venue.website.book(venue.slug, {
    command_key: randomUUID(),
    selection,
    quote_token: quote.quote_token,
    customer: { name: "Venue Customer", phone: "9123456782" },
  });
  assert.equal(result.website_payment_submission, null);
  const second = await seedWebsite(db, "second-upi-test");
  assert.equal((await accounts.websitePayments(second.owner)).upi_id, "");
  await assert.rejects(
    () => second.website.paymentQr(second.slug),
    /not found/,
  );
  await db.query("UPDATE memberships SET role='staff' WHERE user_id=$1", [
    second.owner.uid,
  ]);
  await assert.rejects(
    () => accounts.websitePayments(second.owner),
    /Only the owner/,
  );
  await assert.rejects(
    () =>
      accounts.saveWebsitePayments(second.owner, {
        version: 0,
        upi_id: "staff@bank",
      }),
    /Only the owner/,
  );
});
test("rounding and free/non-INR bookings do not silently demand an unsupported transfer", () => {
  const settings = { version: 1, upi_id: "venue@bank", has_qr: true };
  assert.equal(
    paymentPolicy(true, [50], 101, "INR", settings).options[0].amount_minor,
    51,
  );
  assert.equal(paymentPolicy(true, [50], 0, "INR", settings).required, false);
  assert.throws(
    () => paymentPolicy(true, [50], 100, "USD", settings),
    /unavailable/,
  );
});
