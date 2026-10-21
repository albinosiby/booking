import {
  inventoryIsBlocked,
  SlotBlockedException,
} from "../slot-blocks/inventory-blocks";
import { allDayDatesCover } from "../common/operating-hours";
import { BadRequestException, ConflictException } from "@nestjs/common";
import { createHash } from "node:crypto";
import { BookingSelection } from "./booking.validation";
import { turfPriceAtStart } from "../turf/turf.validation";
import { courtPriceAtStart } from "../court/court.validation";
import { poolPriceAtStart, poolGroupPrice } from "../pool/pool.validation";
import {
  hallHourlyPriceAtStart,
  hallPackagePrice,
} from "../hall/hall.validation";
type Row = Record<string, any>;
export const minute = (s: string) =>
  Number(s.slice(0, 2)) * 60 + Number(s.slice(3));
export const addDate = (s: string, days: number) =>
  new Date(Date.parse(s + "T00:00:00Z") + days * 86400000)
    .toISOString()
    .slice(0, 10);
const zoneFormats = new Map<string, Intl.DateTimeFormat>();
const dateParts = (t: number, zone: string) => {
  let f = zoneFormats.get(zone);
  if (!f) {
    f = new Intl.DateTimeFormat("en-CA", {
      timeZone: zone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    });
    if (zoneFormats.size < 256) zoneFormats.set(zone, f);
  }
  return Object.fromEntries(
    f.formatToParts(new Date(t)).map((p) => [p.type, p.value]),
  );
};
export function localStamp(t: number, zone: string) {
  const p = dateParts(t, zone);
  return `${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}`;
}
export function zonedTime(date: string, time: string, zone: string): number {
  const wanted = date + "T" + time,
    base = Date.parse(wanted + ":00Z");
  const candidates = new Set<number>();
  for (const sample of [base - 86400000, base, base + 86400000]) {
    const p = localStamp(sample, zone);
    const offset = Date.parse(p + ":00Z") - Math.floor(sample / 60000) * 60000;
    const t = base - offset;
    if (localStamp(t, zone) === wanted) candidates.add(t);
  }
  if (candidates.size !== 1)
    throw new BadRequestException(
      "This local time is missing or ambiguous due to daylight saving. Choose another start time.",
    );
  return [...candidates][0];
}
export function bookingOptions(b: Row) {
  const c = b.configuration;
  if (!c) return [];
  const resource = (p: Row, options: Row[]) => ({
    id: p.id,
    name: p.name,
    capacity: p.capacity ?? 1,
    options,
  });
  const hourly = (
    id: string,
    name: string,
    durations: number[],
    defaultDuration = durations[0],
    flexible = true,
  ) => ({
    id,
    name,
    kind: flexible ? "hourly" : "group",
    minimum_duration: flexible ? defaultDuration : null,
    duration_step: flexible ? 15 : null,
    durations: flexible
      ? Array.from(
          { length: Math.floor((1440 - defaultDuration) / 15) + 1 },
          (_, i) => defaultDuration + i * 15,
        )
      : durations,
    default_duration: defaultDuration,
    fixed_time: null,
  });
  if (c.kind === "turf_v1")
    return c.layouts
      .map((p: Row) =>
        resource(
          {
            ...p,
            name: `${c.grounds.find((g: Row) => g.id === p.ground_id)?.name ?? ""} · ${p.name}`,
          },
          c.offerings
            .filter((o: Row) => o.enabled && o.layout_id === p.id)
            .map((o: Row) => ({
              ...hourly(
                o.id,
                `${o.sport === "football" ? "Football" : "Cricket"} · ${o.format}`,
                o.rates.map((r: Row) => r.duration_minutes),
                o.default_duration_minutes,
              ),
              sport: o.sport,
              format: o.format,
            })),
        ),
      )
      .filter((p: Row) => p.options.length);
  if (c.kind === "court_v1")
    return c.courts
      .filter((p: Row) => p.enabled)
      .map((p: Row) =>
        resource(p, [
          hourly(
            "hourly",
            "Court booking",
            p.durations,
            p.default_duration_minutes,
          ),
        ]),
      );
  if (c.kind === "pool_v1")
    return c.pools
      .filter((p: Row) => p.enabled)
      .map((p: Row) =>
        resource(p, [
          ...(p.regular_swimming
            ? [
                hourly(
                  "regular",
                  "Regular admission",
                  p.durations,
                  p.default_duration_minutes,
                ),
              ]
            : []),
          ...c.group_offers
            .filter((o: Row) => o.enabled && o.pool_ids.includes(p.id))
            .map((o: Row) => ({
              ...hourly(
                o.id,
                o.name,
                [o.duration_minutes],
                o.duration_minutes,
                false,
              ),
              group_mode: o.group_mode,
              group_people: o.people,
            })),
        ]),
      )
      .filter((p: Row) => p.options.length);
  if (c.kind === "hall_v1")
    return c.halls
      .filter((p: Row) => p.enabled)
      .map((p: Row) =>
        resource(p, [
          ...(p.hourly_enabled
            ? [
                hourly(
                  "hourly",
                  "Hourly booking",
                  p.durations,
                  p.default_duration_minutes,
                ),
              ]
            : []),
          ...[...p.sessions, p.full_day]
            .filter((o: Row) => o.enabled)
            .map((o: Row) => ({
              id: o.id,
              name: o.name,
              kind: o.id === p.full_day.id ? "full_day" : "session",
              durations: [
                (minute(o.hours.closes_at) - minute(o.hours.opens_at) + 1440) %
                  1440,
              ],
              fixed_time: o.hours.opens_at,
            })),
        ]),
      );
  return [];
}
/** Request-local only: never reuse availability or configuration across requests. */
export function quoteContext(b: Row, timezone: string) {
  const spaces = bookingOptions(b);
  const times = new Map<string, number>();
  const stamps = new Map<number, string>();
  return {
    spaces,
    time(date: string, time: string) {
      const key = date + "T" + time;
      if (!times.has(key)) times.set(key, zonedTime(date, time, timezone));
      return times.get(key)!;
    },
    stamp(time: number) {
      if (!stamps.has(time)) stamps.set(time, localStamp(time, timezone));
      return stamps.get(time)!;
    },
  };
}

/** Include operating boundaries even where a full minimum booking cannot start. */
export function bookingBoundaries(b: Row, selection: BookingSelection) {
  const config = b.configuration;
  const resource =
    config.kind === "turf_v1"
      ? config.offerings.find((o: Row) => o.id === selection.option_id)
      : (config.courts ?? config.pools ?? config.halls).find(
          (r: Row) => r.id === selection.resource_id,
        );
  const hours =
    config.kind === "turf_v1"
      ? (resource.hours_override ?? config.operating)
      : resource.operating;
  const start = hours.all_day ? 0 : minute(hours.opens_at);
  const span = hours.all_day
    ? 1440
    : (minute(hours.closes_at) - start + 1440) % 1440;
  const boundaries = new Map<string, { time: string; date: string }>();
  for (const offset of [-1, 0]) {
    const operatingDate = addDate(selection.date, offset);
    const day = new Date(operatingDate + "T00:00:00Z").getUTCDay() || 7;
    if (
      !hours.days.includes(day) ||
      (hours.date_from && operatingDate < hours.date_from) ||
      (hours.date_until && operatingDate > hours.date_until)
    )
      continue;
    const points = new Set([start, start + span]);
    for (
      let value = Math.ceil(start / 15) * 15;
      value <= start + span;
      value += 15
    )
      points.add(value);
    for (const point of points) {
      const date = addDate(operatingDate, Math.floor(point / 1440));
      if (date < selection.date) continue;
      const value = point % 1440;
      const time = `${String(Math.floor(value / 60)).padStart(2, "0")}:${String(value % 60).padStart(2, "0")}`;
      boundaries.set(date + "T" + time, { date, time });
    }
  }
  return [...boundaries.values()];
}

export function buildQuote(
  b: Row,
  s: BookingSelection,
  timezone: string,
  now = Date.now(),
  context?: ReturnType<typeof quoteContext>,
) {
  const c = b.configuration;
  const timeAt =
    context?.time ??
    ((date: string, time: string) => zonedTime(date, time, timezone));
  const stampAt =
    context?.stamp ?? ((time: number) => localStamp(time, timezone));
  const space = (context?.spaces ?? bookingOptions(b)).find(
    (r: Row) => r.id === s.resource_id,
  );
  const option = space?.options.find((o: Row) => o.id === s.option_id);
  if (!option || !option.durations.includes(s.duration_minutes))
    throw new BadRequestException(
      "Choose an enabled space, booking option and allowed duration.",
    );
  let hours: Row,
    before = 0,
    after = 0,
    price: number | null = null,
    quantity = 1,
    capacity = 1,
    keys = [s.resource_id],
    optionName = option.name;
  if (c.kind === "turf_v1") {
    const o = c.offerings.find((o: Row) => o.id === s.option_id);
    hours = o.hours_override ?? c.operating;
    before = o.buffer_before;
    after = o.buffer_after ?? 5;
    const layout = c.layouts.find((p: Row) => p.id === s.resource_id);
    keys = layout.section_ids;
  } else {
    const p = (c.courts ?? c.pools ?? c.halls).find(
      (p: Row) => p.id === s.resource_id,
    );
    hours = p.operating;
    before = p.buffer_before;
    after = p.buffer_after ?? 5;
    if (c.kind === "pool_v1") {
      quantity = s.people;
      capacity = p.capacity;
    }
    if (c.kind === "hall_v1" && s.people > p.capacity)
      throw new BadRequestException("Guest count exceeds hall capacity.");
  }
  const actualStart = timeAt(s.date, s.time);
  const actualEnd = actualStart + s.duration_minutes * 60000;
  const actualDates = {
    from: stampAt(actualStart).slice(0, 10),
    until: stampAt(actualEnd - 1).slice(0, 10),
  };
  const overnight = minute(hours.closes_at) < minute(hours.opens_at);
  const opDate =
    overnight && minute(s.time) < minute(hours.opens_at)
      ? addDate(s.date, -1)
      : s.date;
  const day = new Date(opDate + "T00:00:00Z").getUTCDay() || 7;
  if (c.kind === "turf_v1")
    price = turfPriceAtStart(
      c,
      s.option_id,
      day,
      s.time,
      s.duration_minutes,
      actualDates,
    );
  if (c.kind === "court_v1")
    price = courtPriceAtStart(
      c,
      s.resource_id,
      opDate,
      s.time,
      s.duration_minutes,
      actualDates,
    );
  if (c.kind === "pool_v1")
    price =
      s.option_id === "regular"
        ? poolPriceAtStart(
            c,
            s.resource_id,
            opDate,
            s.time,
            s.duration_minutes,
            s.people,
            actualDates,
          )
        : poolGroupPrice(
            c,
            s.option_id,
            s.resource_id,
            opDate,
            s.time,
            s.people,
            actualDates,
          );
  if (c.kind === "hall_v1") {
    if (s.option_id === "hourly")
      price = hallHourlyPriceAtStart(
        c,
        s.resource_id,
        opDate,
        s.time,
        s.duration_minutes,
      );
    else {
      if (option.fixed_time !== s.time)
        throw new BadRequestException(
          "A session/package uses its configured start time.",
        );
      price = hallPackagePrice(c, s.resource_id, s.option_id, opDate);
    }
  }
  if (price === null)
    throw new BadRequestException(
      "No configured price or operating hours match this selection.",
    );
  if (!Number.isSafeInteger(price) || price < 0 || price > 100000000)
    throw new BadRequestException(
      "Booking total exceeds the supported limit. Adjust the offering or group size.",
    );
  const start = actualStart;
  let end = actualEnd;
  if (option.fixed_time !== null) {
    const p = c.halls.find((p: Row) => p.id === s.resource_id),
      o = [p.full_day, ...p.sessions].find((o: Row) => o.id === s.option_id);
    const endDate =
      minute(o.hours.closes_at) <= minute(s.time) ? addDate(s.date, 1) : s.date;
    end = timeAt(endDate, o.hours.closes_at);
  }
  const open = hours.all_day ? 0 : timeAt(opDate, hours.opens_at),
    close = hours.all_day
      ? 0
      : timeAt(overnight ? addDate(opDate, 1) : opDate, hours.closes_at);
  if (start < now)
    throw new BadRequestException("Choose a future date and time.");
  if (
    hours.all_day
      ? !allDayDatesCover(
          {
            days: hours.days,
            date_from: hours.date_from,
            date_until: hours.date_until,
          },
          stampAt(start).slice(0, 10),
          stampAt(end - 1).slice(0, 10),
        )
      : start < open || end > close
  )
    throw new BadRequestException("Booking must fit operating hours.");
  const discount = s.discount;
  const discountMinor = discount
    ? discount.type === "percent"
      ? Math.round((price * discount.value) / 10000)
      : discount.value
    : 0;
  if (discountMinor > price)
    throw new BadRequestException(
      "Discount cannot exceed the booking subtotal.",
    );
  const base = {
    business_id: b.id,
    resource_id: s.resource_id,
    business_name: b.name,
    space_name: space.name,
    option_name: optionName,
    timezone,
    selection: s,
    starts_at: new Date(start).toISOString(),
    ends_at: new Date(end).toISOString(),
    local_start: stampAt(start),
    local_end: stampAt(end),
    occupied_from: new Date(start).toISOString(),
    occupied_until: new Date(end).toISOString(),
    cleanup_minutes: after,
    preparation_minutes: before,
    subtotal_minor: price,
    discount_minor: discountMinor,
    total_minor: price - discountMinor,
    business_version: b.version,
    inventory_keys: keys.map((k: string) => b.id + ":" + k),
    quantity,
    capacity,
  };
  return {
    ...base,
    quote_token: createHash("sha256")
      .update(JSON.stringify(base))
      .digest("hex"),
  };
}

export type InventoryQuote = Pick<
  ReturnType<typeof buildQuote>,
  | "inventory_keys"
  | "occupied_from"
  | "occupied_until"
  | "capacity"
  | "quantity"
>;
export function inventoryRemaining(
  q: InventoryQuote,
  allocations: Row[],
  exclude?: string,
) {
  if (inventoryIsBlocked(q, allocations)) return 0;
  const matches = allocations.filter(
    (a) =>
      a.booking_id !== exclude &&
      q.inventory_keys.includes(a.inventory_key) &&
      Date.parse(a.starts_at) < Date.parse(q.occupied_until) &&
      Date.parse(a.ends_at) > Date.parse(q.occupied_from),
  );
  let available = q.capacity;
  for (const key of q.inventory_keys) {
    const events: { time: number; delta: number }[] = [];
    for (const a of matches.filter((a) => a.inventory_key === key)) {
      events.push(
        {
          time: Math.max(Date.parse(q.occupied_from), Date.parse(a.starts_at)),
          delta: a.quantity,
        },
        {
          time: Math.min(Date.parse(q.occupied_until), Date.parse(a.ends_at)),
          delta: -a.quantity,
        },
      );
    }
    events.sort((a, b) => a.time - b.time || a.delta - b.delta);
    let occupied = 0,
      peak = 0;
    for (const e of events) {
      occupied += e.delta;
      peak = Math.max(peak, occupied);
    }
    available = Math.min(available, q.capacity - peak);
  }
  return Math.max(0, available);
}
export function checkInventory<T extends InventoryQuote>(
  q: T,
  allocations: Row[],
  exclude?: string,
) {
  if (inventoryIsBlocked(q, allocations)) throw new SlotBlockedException();
  const remaining = inventoryRemaining(q, allocations, exclude);
  if (q.quantity > remaining)
    throw new ConflictException(
      q.capacity === 1
        ? "This space is no longer available. Choose another slot."
        : "Not enough pool capacity for this interval.",
    );
  return { ...q, remaining_capacity: remaining };
}
