import {
  Injectable,
  BadRequestException,
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from "@nestjs/common";
import { z } from "zod";
import { createHash, randomUUID } from "node:crypto";
import { Database } from "../common/database";
import { Actor } from "../common/auth.guard";
import { BookingService } from "../bookings/booking.service";
import { voiceAccess } from "../agent-calls/agent-call-policy";
type Row = Record<string, any>;

/**
 * Phone-call booking tools for the Sarvam voice agent. Every write goes through
 * BookingService as the organization's restricted voice membership, so prices,
 * inventory, slot blocks, business scope and idempotency follow the app rules.
 * Responses carry a short `message` the agent can read to the caller.
 */
const text = (max: number) => z.string().trim().max(max);
const phone = text(40).optional().default("");
const interaction = text(200).optional().default("");
const place = {
  business: text(120).optional().default(""),
  space: text(120).optional().default(""),
  activity: text(120).optional().default(""),
};
const when = {
  date: text(20).describe("YYYY-MM-DD, today or tomorrow"),
  duration_minutes: z.coerce.number().int().min(15).max(1440).optional(),
  people: z.coerce.number().int().min(1).max(10000).optional().default(1),
};
const availabilitySchema = z
  .object({
    ...place,
    ...when,
    preferred_time: text(20).optional().default(""),
  })
  .strip();
const bookSchema = z
  .object({
    ...place,
    ...when,
    time: text(20),
    customer_name: text(100),
    caller_phone: phone,
    contact_phone: phone,
    expected_total: z.coerce.number().min(0).optional(),
    interaction_id: interaction,
  })
  .strip();
const mineSchema = z.object({ caller_phone: phone }).strip();
const rescheduleSchema = z
  .object({
    reference: text(40),
    caller_phone: phone,
    date: text(20),
    time: text(20),
    duration_minutes: z.coerce.number().int().min(15).max(1440).optional(),
    space: text(120).optional().default(""),
    interaction_id: interaction,
  })
  .strip();
const cancelSchema = z
  .object({
    reference: text(40),
    caller_phone: phone,
    reason: text(300).optional().default(""),
    interaction_id: interaction,
  })
  .strip();

const fold = (v: string) =>
  v
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
const digits = (v: string) => v.replace(/\D/g, "");
/** Last ten digits identify Indian numbers with or without +91/0 prefixes. */
const phoneKey = (v: string) => digits(v).slice(-10);

/** Parses 24h or spoken 12h times such as 19:00, 7 pm, 7.30pm. */
export function parseTime(raw: string) {
  const m = /^(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?$/i.exec(
    raw.trim(),
  );
  if (!m)
    throw new BadRequestException(`I could not understand the time "${raw}".`);
  let hour = Number(m[1]);
  const minute = Number(m[2] ?? 0),
    half = m[3]?.toLowerCase()[0];
  if (half && (hour < 1 || hour > 12))
    throw new BadRequestException(`I could not understand the time "${raw}".`);
  if (half === "p" && hour < 12) hour += 12;
  if (half === "a" && hour === 12) hour = 0;
  if (hour > 23 || minute > 59)
    throw new BadRequestException(`I could not understand the time "${raw}".`);
  return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
}
export function parseDate(raw: string, today: string) {
  const v = raw.trim().toLowerCase();
  const shift = (days: number) =>
    new Date(Date.parse(today + "T00:00:00Z") + days * 86400000)
      .toISOString()
      .slice(0, 10);
  if (v === "today") return today;
  if (v === "tomorrow") return shift(1);
  if (v === "day after tomorrow") return shift(2);
  if (/^\d{4}-\d{2}-\d{2}$/.test(v) && !Number.isNaN(Date.parse(v))) return v;
  throw new BadRequestException(
    `I could not understand the date "${raw}". Use a date like ${today}.`,
  );
}
export const spokenTime = (hhmm: string) => {
  const h = Number(hhmm.slice(0, 2)),
    m = hhmm.slice(3, 5);
  return `${h % 12 || 12}${m === "00" ? "" : ":" + m} ${h < 12 ? "AM" : "PM"}`;
};
const spokenDate = (date: string) =>
  new Date(date + "T12:00:00Z").toLocaleDateString("en-IN", {
    weekday: "long",
    day: "numeric",
    month: "long",
    timeZone: "UTC",
  });
const money = (minor: number, currency: string) =>
  new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency,
    maximumFractionDigits: minor % 100 ? 2 : 0,
  }).format(minor / 100);
/** Same call + same request → same command key, so Sarvam retries never double-book. */
function commandKey(org: string, call: string, kind: string, payload: unknown) {
  if (!call) return randomUUID();
  const h = createHash("sha256")
    .update(JSON.stringify([org, call, kind, payload]))
    .digest("hex");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-4${h.slice(13, 16)}-${((parseInt(h[16], 16) & 3) | 8).toString(16)}${h.slice(17, 20)}-${h.slice(20, 32)}`;
}

@Injectable()
export class VoiceService {
  constructor(
    private readonly db: Database,
    private readonly bookings: BookingService,
  ) {}
  private detail(actor: Actor, id: string): Promise<Row> {
    return this.bookings.detail(actor, id);
  }
  private org(actor: Actor) {
    return actor.uid.slice(actor.uid.indexOf(":") + 1);
  }
  async catalog(actor: Actor) {
    const services = await voiceAccess(this.db, actor);
    const c = await this.bookings.catalog(actor);
    const businesses = c.businesses.map((b: Row) => ({
      name: b.name,
      type: b.type,
      today: b.today,
      spaces: b.resources.map((r: Row) => ({
        name: r.name,
        activities: r.options.map((o: Row) => ({
          name: o.name,
          default_duration_minutes: o.default_duration ?? o.durations?.[0],
          fixed_start: o.fixed_time,
        })),
      })),
    }));
    const message = businesses.length
      ? businesses
          .map(
            (b: Row) =>
              `${b.name}: ` +
              b.spaces
                .map(
                  (s: Row) =>
                    `${s.name} (${s.activities.map((a: Row) => a.name).join(", ")})`,
                )
                .join("; "),
          )
          .join(". ") + `. Today is ${businesses[0].today}.`
      : "No spaces are available for phone booking right now.";
    return {
      ok: true,
      message: `Available services: ${services.join(", ")}. ${message}`,
      services,
      businesses,
    };
  }
  /** Resolves spoken business/space/activity names to catalog IDs. */
  private async resolve(
    actor: Actor,
    input: { business: string; space: string; activity: string },
  ) {
    const c = await this.bookings.catalog(actor);
    const matches = (name: string, want: string) =>
      !want || fold(name) === fold(want) || fold(name).includes(fold(want));
    const candidates: Row[] = [];
    for (const b of c.businesses)
      if (matches(b.name, input.business))
        for (const r of b.resources)
          if (matches(r.name, input.space)) {
            const options = r.options.filter((o: Row) =>
              matches(o.name, input.activity),
            );
            if (options.length) candidates.push({ b, r, options });
          }
    // Prefer exact space names, so "Court 1" does not also match "Court 10".
    const exact = candidates.filter(
      (x) => fold(x.r.name) === fold(input.space),
    );
    const found = exact.length === 1 ? exact : candidates;
    if (!found.length)
      throw new NotFoundException(
        "I could not find that space. Available: " +
          c.businesses
            .flatMap((b: Row) => b.resources.map((r: Row) => r.name))
            .join(", ") +
          ".",
      );
    if (found.length > 1)
      throw new BadRequestException(
        "Which one: " +
          found.map((x) => `${x.r.name} (${x.b.name})`).join(", ") +
          "?",
      );
    const { b, r, options } = found[0];
    const exactOption = options.filter(
      (o: Row) => fold(o.name) === fold(input.activity),
    );
    const pick = exactOption.length === 1 ? exactOption : options;
    if (pick.length > 1)
      throw new BadRequestException(
        `Which activity at ${r.name}: ${pick.map((o: Row) => o.name).join(", ")}?`,
      );
    return {
      business: b,
      resource: r,
      option: pick[0],
      currency: c.currency as string,
    };
  }
  private selection(
    found: Awaited<ReturnType<VoiceService["resolve"]>>,
    date: string,
    time: string,
    duration: number | undefined,
    people: number,
  ) {
    const o = found.option;
    const minutes = duration ?? o.default_duration ?? o.durations?.[0];
    if (
      o.minimum_duration
        ? minutes < o.minimum_duration
        : !o.durations.includes(minutes)
    )
      throw new BadRequestException(
        o.minimum_duration
          ? `The minimum duration is ${o.minimum_duration} minutes.`
          : `Choose a duration of ${o.durations.join(" or ")} minutes.`,
      );
    return {
      business_id: found.business.id,
      resource_id: found.resource.id,
      option_id: o.id,
      date: parseDate(date, found.business.today),
      time: o.fixed_time ?? time,
      duration_minutes: minutes,
      people,
    };
  }
  async availability(actor: Actor, input: unknown) {
    await voiceAccess(this.db, actor, ["enquiry", "booking", "rescheduling"]);
    const v = availabilitySchema.parse(input);
    const found = await this.resolve(actor, v);
    const selection = this.selection(
      found,
      v.date,
      "00:00",
      v.duration_minutes,
      v.people,
    );
    const { slots } = await this.bookings.availability(actor, {
      selection,
      exclude_booking_id: null,
    });
    const open = slots.filter((s: Row) => s.available);
    const preferred = v.preferred_time ? parseTime(v.preferred_time) : "";
    const minute = (t: string) =>
      Number(t.slice(0, 2)) * 60 + Number(t.slice(3));
    const ranked = preferred
      ? [...open].sort(
          (a, b) =>
            Math.abs(minute(a.time) - minute(preferred)) -
            Math.abs(minute(b.time) - minute(preferred)),
        )
      : [
          ...open.filter((s: Row) => s.time.endsWith(":00")),
          ...open.filter((s: Row) => !s.time.endsWith(":00")),
        ];
    const offered = ranked
      .slice(0, 8)
      .sort((a: Row, b: Row) => minute(a.time) - minute(b.time))
      .map((s: Row) => ({
        time: s.time,
        spoken_time: spokenTime(s.time),
        total: money(s.total_minor, found.currency),
        total_minor: s.total_minor,
      }));
    const day = spokenDate(selection.date);
    const exact = preferred && open.some((s: Row) => s.time === preferred);
    const message = !offered.length
      ? `${found.resource.name} has no free slots on ${day} for ${selection.duration_minutes} minutes.`
      : (preferred
          ? exact
            ? `${spokenTime(preferred)} is available. `
            : `${spokenTime(preferred)} is not available. `
          : "") +
        `Free times at ${found.resource.name} on ${day} for ${selection.duration_minutes} minutes: ` +
        offered.map((s) => `${s.spoken_time} (${s.total})`).join(", ") +
        ".";
    return {
      ok: true,
      message,
      date: selection.date,
      space: found.resource.name,
      activity: found.option.name,
      duration_minutes: selection.duration_minutes,
      slots: offered,
    };
  }
  async book(actor: Actor, input: unknown) {
    await voiceAccess(this.db, actor, ["booking"]);
    const v = bookSchema.parse(input);
    const phoneNumber = v.contact_phone || v.caller_phone;
    if (digits(phoneNumber).length < 7)
      throw new BadRequestException(
        "I need the caller's phone number to book.",
      );
    if (v.customer_name.length < 2)
      throw new BadRequestException("I need the caller's name to book.");
    const found = await this.resolve(actor, v);
    const { interaction_id, expected_total, ...request } = v;
    const key = commandKey(this.org(actor), interaction_id, "book", request);
    const previous = await this.replay(actor, key, interaction_id);
    if (previous) return this.booked(previous, found);
    const selection = this.selection(
      found,
      v.date,
      parseTime(v.time),
      v.duration_minutes,
      v.people,
    );
    const quote = await this.bookings.quote(actor, {
      selection,
      exclude_booking_id: null,
    });
    if (
      v.expected_total !== undefined &&
      Math.round(v.expected_total * 100) !== quote.total_minor
    )
      throw new ConflictException(
        `The price is now ${money(quote.total_minor, found.currency)}. Please confirm with the caller before booking.`,
      );
    const customer = {
      id: await this.existingCustomer(actor, phoneNumber),
      name: v.customer_name,
      phone: phoneNumber.replace(/[^\d+]/g, ""),
      email: null,
    };
    const { id } = await this.bookings.create(actor, {
      command_key: key,
      selection,
      quote_token: quote.quote_token,
      customer,
      notes: `Booked through the call service${v.interaction_id ? ` (call ${v.interaction_id})` : ""}.`,
      payments: [],
    });
    return this.booked(await this.detail(actor, id), found);
  }
  /**
   * A Sarvam retry of the same call and request returns the first result
   * instead of re-checking a slot the first attempt already took.
   */
  private async replay(actor: Actor, key: string, call: string) {
    if (!call) return null;
    const { id } = (await this.bookings.commandResult(actor, key)) as Row;
    return id ? this.detail(actor, id) : null;
  }
  private booked(
    booking: Row,
    found: Awaited<ReturnType<VoiceService["resolve"]>>,
  ) {
    return {
      ok: true,
      message: `Booked. Your booking reference is ${booking.reference.split("").join(" ")}. ${found.resource.name}, ${this.span(booking)}. Total ${money(booking.total_minor, found.currency)}, payable at the venue.`,
      ...this.summary(booking, found.currency),
    };
  }
  /** Reuses the newest customer with this phone in the agent's own businesses. */
  private async existingCustomer(actor: Actor, phoneNumber: string) {
    const key = phoneKey(phoneNumber);
    if (key.length < 7) return null;
    const row = (
      await this.db.query<Row>(
        `SELECT b.customer_id FROM bookings b JOIN memberships m ON m.user_id=$1 AND m.organization_id=b.organization_id
         JOIN staff_assignments a ON a.membership_id=m.id AND a.business_id=b.business_id
         WHERE a.resource_ids ? b.resource_id::text AND right(regexp_replace(b.customer_snapshot->>'phone','\\D','','g'),10)=$2 ORDER BY b.created_at DESC LIMIT 1`,
        [actor.uid, key],
      )
    ).rows[0];
    return (row?.customer_id as string | undefined) ?? null;
  }
  /** Upcoming call-created bookings for this caller and organization. */
  private async callerBookings(
    actor: Actor,
    callerPhone: string,
    reference?: string,
  ) {
    const key = phoneKey(callerPhone);
    if (key.length < 7)
      throw new ForbiddenException(
        "I can only change bookings when calling from the phone number used to book.",
      );
    const values: unknown[] = [actor.uid, key];
    let where = "";
    if (reference) {
      values.push(reference.toUpperCase().replace(/\s+/g, ""));
      where = ` AND upper(b.reference)=$3`;
    }
    return (
      await this.db.query<Row>(
        `SELECT b.id FROM bookings b JOIN memberships m ON m.user_id=$1 AND m.organization_id=b.organization_id
         JOIN staff_assignments a ON a.membership_id=m.id AND a.business_id=b.business_id
         WHERE b.status='confirmed' AND b.starts_at>now() AND b.admission_id IS NULL AND b.created_by=$1 AND a.resource_ids ? b.resource_id::text
         AND right(regexp_replace(b.customer_snapshot->>'phone','\\D','','g'),10)=$2${where}
         ORDER BY b.starts_at LIMIT 10`,
        values,
      )
    ).rows.map((r) => r.id as string);
  }
  private span(b: Row) {
    return `${spokenDate(b.local_start.slice(0, 10))} from ${spokenTime(b.local_start.slice(11, 16))} to ${spokenTime(b.local_end.slice(11, 16))}`;
  }
  private summary(b: Row, currency: string) {
    return {
      reference: b.reference as string,
      status: b.status as string,
      date: b.local_start.slice(0, 10) as string,
      start_time: b.local_start.slice(11, 16) as string,
      end_time: b.local_end.slice(11, 16) as string,
      total: money(b.total_minor, currency),
      balance_due: money(b.balance_minor, currency),
    };
  }
  async mine(actor: Actor, input: unknown) {
    await voiceAccess(this.db, actor, ["rescheduling", "cancellation"]);
    const v = mineSchema.parse(input);
    const ids = await this.callerBookings(actor, v.caller_phone);
    const { currency } = await this.bookings.catalog(actor);
    const items = [];
    for (const id of ids) {
      const b = await this.detail(actor, id);
      items.push({ ...this.summary(b, currency), span: this.span(b) });
    }
    return {
      ok: true,
      message: items.length
        ? "Upcoming bookings: " +
          items
            .map((b) => `${b.reference.split("").join(" ")} on ${b.span}`)
            .join("; ") +
          "."
        : "I could not find any upcoming call bookings for this phone number. Bookings made through other channels must be managed by venue staff.",
      bookings: items,
    };
  }
  private async owned(actor: Actor, callerPhone: string, reference: string) {
    const [id] = await this.callerBookings(actor, callerPhone, reference);
    if (!id)
      throw new NotFoundException(
        "I could not find an upcoming call booking with that reference for this phone number. Only bookings originally made by call can be changed by phone.",
      );
    return this.detail(actor, id);
  }
  async reschedule(actor: Actor, input: unknown) {
    await voiceAccess(this.db, actor, ["rescheduling"]);
    const v = rescheduleSchema.parse(input);
    const { interaction_id, ...request } = v;
    request.reference = request.reference.toUpperCase().replace(/\s+/g, "");
    const key = commandKey(
      this.org(actor),
      interaction_id,
      "reschedule",
      request,
    );
    const catalog = await this.bookings.catalog(actor);
    const previous = await this.replay(actor, key, interaction_id);
    if (previous) return this.moved(previous, catalog, null);
    const old = await this.owned(actor, v.caller_phone, v.reference);
    const business = catalog.businesses.find(
      (b: Row) => b.id === old.business_id,
    );
    const current = business?.resources.find(
      (r: Row) => r.id === old.resource_id,
    );
    if (!business || !current)
      throw new ForbiddenException("This booking cannot be changed by phone.");
    const found = await this.resolve(actor, {
      business: business.name,
      space: v.space || current.name,
      activity:
        current.options.find((o: Row) => o.id === old.selection.option_id)
          ?.name ?? "",
    });
    const selection = this.selection(
      found,
      v.date,
      parseTime(v.time),
      v.duration_minutes ?? old.selection.duration_minutes,
      old.selection.people,
    );
    const quote = await this.bookings.quote(actor, {
      selection,
      exclude_booking_id: old.id,
    });
    await this.bookings.reschedule(actor, old.id, {
      command_key: key,
      version: old.version,
      selection,
      quote_token: quote.quote_token,
      reason: `Rescheduled by the caller through the call service${v.interaction_id ? ` (call ${v.interaction_id})` : ""}.`,
    });
    return this.moved(await this.detail(actor, old.id), catalog, old);
  }
  private moved(b: Row, catalog: Row, old: Row | null) {
    const space =
      catalog.businesses
        .flatMap((x: Row) => x.resources)
        .find((r: Row) => r.id === b.resource_id)?.name ?? "";
    const change =
      old && b.total_minor !== old.total_minor
        ? ` The new total is ${money(b.total_minor, catalog.currency)}.`
        : "";
    return {
      ok: true,
      message: `Done. Booking ${b.reference.split("").join(" ")} is now ${space}, ${this.span(b)}.${change}`,
      ...this.summary(b, catalog.currency),
    };
  }
  async cancel(actor: Actor, input: unknown) {
    await voiceAccess(this.db, actor, ["cancellation"]);
    const v = cancelSchema.parse(input);
    const key = commandKey(this.org(actor), v.interaction_id, "cancel", [
      v.reference.toUpperCase().replace(/\s+/g, ""),
      v.caller_phone,
    ]);
    const previous = await this.replay(actor, key, v.interaction_id);
    if (previous) return this.cancelled(actor, previous);
    const b = await this.owned(actor, v.caller_phone, v.reference);
    await this.bookings.status(actor, b.id, {
      command_key: key,
      version: b.version,
      status: "cancelled",
      reason:
        `Cancelled by the caller through the call service${v.reason ? `: ${v.reason}` : ""}`.slice(
          0,
          500,
        ),
    });
    return this.cancelled(actor, await this.detail(actor, b.id));
  }
  private async cancelled(actor: Actor, after: Row) {
    const b = after;
    const { currency } = await this.bookings.catalog(actor);
    const refund = after.refund_due_minor
      ? ` ${money(after.refund_due_minor, currency)} already paid will be refunded by the venue.`
      : "";
    return {
      ok: true,
      message: `Booking ${b.reference.split("").join(" ")} on ${this.span(b)} is cancelled.${refund}`,
      reference: b.reference,
      status: "cancelled",
    };
  }
}
