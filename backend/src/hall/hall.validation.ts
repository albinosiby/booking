import {
  acceptsMinimumDuration,
  minimumBookingPrice,
} from "../common/minimum-booking";
import { z } from "zod";
const clock = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/);
const date = z
  .string()
  .refine(
    (v) =>
      /^\d{4}-\d{2}-\d{2}$/.test(v) &&
      !Number.isNaN(Date.parse(v)) &&
      new Date(v).toISOString().startsWith(v),
    "Use a valid calendar date",
  );
const name = z.string().trim().min(2).max(100);
const price = z.number().int().min(0).max(100000000).nullable();
const id = z.uuid();
const duration = z.number().int().min(30).max(1440);
export const hallHoursSchema = z
  .object({
    days: z.array(z.number().int().min(1).max(7)).min(1).max(7),
    opens_at: clock,
    closes_at: clock,
    date_from: date.nullable(),
    date_until: date.nullable(),
  })
  .strict()
  .superRefine((v, ctx) => {
    if (new Set(v.days).size !== v.days.length || v.opens_at === v.closes_at)
      ctx.addIssue({
        code: "custom",
        message: "Choose distinct times and unique weekdays.",
      });
    if (
      (v.date_from === null) !== (v.date_until === null) ||
      (v.date_from && v.date_until && v.date_from > v.date_until)
    )
      ctx.addIssue({ code: "custom", message: "Choose a valid date range." });
  });
const rate = z
  .object({ duration_minutes: duration, price_minor: price })
  .strict();
const tariff = z
  .object({ id, hours: hallHoursSchema, rates: z.array(rate).min(1).max(10) })
  .strict();

const packagePrice = z
  .object({
    id,
    days: z.array(z.number().int().min(1).max(7)).min(1).max(7),
    date_from: date.nullable(),
    date_until: date.nullable(),
    price_minor: price,
  })
  .strict();
const hallPackage = z
  .object({
    id,
    name,
    enabled: z.boolean(),
    hours: hallHoursSchema,
    prices: z.array(packagePrice).max(40),
  })
  .strict();
const hall = z
  .object({
    id,
    name,
    enabled: z.boolean(),
    environment: z.enum(["unspecified", "indoor", "outdoor"]),
    amenities: z.string().trim().max(1000),
    capacity: z.number().int().min(1).max(10000),
    seated_capacity: z.number().int().min(0).max(10000),
    hourly_enabled: z.boolean(),
    sessions: z.array(hallPackage).max(12),
    full_day: hallPackage,
    operating: hallHoursSchema,
    durations: z.array(duration).min(1).max(10),
    default_duration_minutes: duration,
    buffer_before: z.number().int().min(0).max(240),
    buffer_after: z.number().int().min(0).max(240),
    pricing_basis: z.literal("start_time"),
    tariffs: z.array(tariff).max(40),
  })
  .strict();
const minute = (v: string) => Number(v.slice(0, 2)) * 60 + Number(v.slice(3));
const span = (v: z.infer<typeof hallHoursSchema>) =>
  (minute(v.closes_at) - minute(v.opens_at) + 1440) % 1440;
function within(
  child: z.infer<typeof hallHoursSchema>,
  parent: z.infer<typeof hallHoursSchema>,
) {
  return (
    child.days.every((d) => parent.days.includes(d)) &&
    ((minute(child.opens_at) - minute(parent.opens_at) + 1440) % 1440) +
      span(child) <=
      span(parent)
  );
}
export const hallConfigurationSchema = z
  .object({
    kind: z.literal("hall_v1"),
    schema_version: z.literal(1),
    halls: z.array(hall).max(50),
  })
  .strict()
  .superRefine((v, ctx) => {
    const issue = (message: string) =>
      ctx.addIssue({ code: "custom", message });
    const unique = (values: unknown[]) =>
      new Set(values).size === values.length;
    if (
      !unique(v.halls.map((x) => x.id)) ||
      !unique(v.halls.map((p) => p.name.toLowerCase()))
    )
      issue("Use unique identifiers and hall names.");
    for (const p of v.halls) {
      if (p.seated_capacity > p.capacity)
        issue("Seated capacity cannot exceed maximum capacity.");
      const options = [p.full_day, ...p.sessions];
      if (
        !unique(options.map((o) => o.id)) ||
        !unique(p.sessions.map((o) => o.name.toLowerCase()))
      )
        issue("Use unique session names and option IDs.");
      for (const o of options) {
        if (o.hours.date_from !== null || !unique(o.prices.map((r) => r.id)))
          issue("Check package hours and price identifiers.");
        if (p.enabled && o.enabled) {
          const offset =
            (minute(o.hours.opens_at) - minute(p.operating.opens_at) + 1440) %
            1440;
          if (
            !within(o.hours, p.operating) ||
            offset < 0 ||
            offset + span(o.hours) > span(p.operating)
          )
            issue("Package times must fit hall opening hours.");
        }
        for (const r of o.prices) {
          if (
            !unique(r.days) ||
            !r.days.every((d) => o.hours.days.includes(d)) ||
            (r.date_from === null) !== (r.date_until === null) ||
            (r.date_from && r.date_until && r.date_from > r.date_until)
          )
            issue("Check package price weekdays and date range.");
        }
        for (let i = 0; i < o.prices.length; i++)
          for (let j = i + 1; j < o.prices.length; j++) {
            const a = o.prices[i],
              b = o.prices[j];
            if (
              (a.date_from === null) === (b.date_from === null) &&
              a.days.some((d) => b.days.includes(d)) &&
              (!a.date_from ||
                (a.date_from <= b.date_until! && b.date_from! <= a.date_until!))
            )
              issue("Package prices on the same tier cannot overlap.");
          }
      }

      if (
        p.operating.date_from !== null ||
        p.operating.date_until !== null ||
        !unique(p.durations) ||
        !p.durations.includes(p.default_duration_minutes) ||
        !unique(p.tariffs.map((t) => t.id))
      )
        issue(
          "Check hall opening hours, durations and price rule identifiers.",
        );
      for (const t of p.tariffs) {
        if (p.enabled && p.hourly_enabled && !within(t.hours, p.operating))
          issue("Keep tariff hours within hall opening hours.");
        if (
          t.rates.length !== p.durations.length ||
          !unique(t.rates.map((r) => r.duration_minutes)) ||
          t.rates.some((r) => !p.durations.includes(r.duration_minutes))
        )
          issue("Price every allowed duration exactly once per rule.");
      }
      for (let i = 0; i < p.tariffs.length; i++)
        for (let j = i + 1; j < p.tariffs.length; j++) {
          const a = p.tariffs[i].hours,
            b = p.tariffs[j].hours;
          const x =
              (minute(a.opens_at) - minute(p.operating.opens_at) + 1440) % 1440,
            y =
              (minute(b.opens_at) - minute(p.operating.opens_at) + 1440) % 1440;
          const sameTier = (a.date_from === null) === (b.date_from === null);
          const dates =
            a.date_from === null ||
            b.date_from === null ||
            (a.date_from <= b.date_until! && b.date_from <= a.date_until!);
          if (
            sameTier &&
            dates &&
            a.days.some((d) => b.days.includes(d)) &&
            x < y + span(b) &&
            y < x + span(a)
          )
            issue("Price rules on the same tier cannot overlap.");
        }
    }
  });
export type HallConfiguration = z.infer<typeof hallConfigurationSchema>;
export const hallSaveSchema = z
  .object({
    version: z.number().int().positive(),
    configuration: hallConfigurationSchema,
  })
  .strict();
export function assertHallComplete(input: unknown) {
  const v = hallConfigurationSchema.parse(input);
  if (!v.halls.some((p) => p.enabled)) throw Error("Enable at least one hall.");
  for (const p of v.halls.filter((p) => p.enabled)) {
    if (
      p.hourly_enabled &&
      (!p.tariffs.length ||
        p.tariffs.some((t) =>
          t.rates.some(
            (r) =>
              r.duration_minutes === p.default_duration_minutes &&
              r.price_minor === null,
          ),
        ) ||
        p.durations
          .filter((d) => d === p.default_duration_minutes)
          .some((d) => d > span(p.operating)))
    )
      throw Error("Complete hall prices and valid durations.");
  }
  for (const p of v.halls.filter((p) => p.enabled)) {
    const options = [p.full_day, ...p.sessions];
    if (!p.hourly_enabled && !options.some((o) => o.enabled))
      throw Error("Enable at least one booking option per hall.");
    if (
      options.some(
        (o) =>
          o.enabled &&
          (!o.prices.length || o.prices.some((r) => r.price_minor === null)),
      )
    )
      throw Error("Complete enabled session and full-day prices.");
  }
  return v;
}
function applies(
  hours: z.infer<typeof hallHoursSchema>,
  operating: z.infer<typeof hallHoursSchema>,
  localDate: string,
  time: string,
) {
  const day = new Date(localDate + "T00:00:00Z").getUTCDay() || 7;
  const start = (minute(time) - minute(operating.opens_at) + 1440) % 1440,
    from = (minute(hours.opens_at) - minute(operating.opens_at) + 1440) % 1440;
  return (
    hours.days.includes(day) &&
    (!hours.date_from ||
      (localDate >= hours.date_from && localDate <= hours.date_until!)) &&
    start >= from &&
    start < from + span(hours)
  );
}
/** Configuration quote only; occupancy reservations belong to the booking module. */
export function hallHourlyPriceAtStart(
  v: HallConfiguration,
  hallId: string,
  localDate: string,
  time: string,
  d: number,
) {
  if (!date.safeParse(localDate).success || !clock.safeParse(time).success)
    return null;
  const p = v.halls.find(
    (p) => p.id === hallId && p.enabled && p.hourly_enabled,
  );
  if (
    !p ||
    !acceptsMinimumDuration(d, p.default_duration_minutes) ||
    !applies(p.operating, p.operating, localDate, time)
  )
    return null;
  const start = (minute(time) - minute(p.operating.opens_at) + 1440) % 1440;
  if (start < 0 || start + d > span(p.operating)) return null;
  const matches = p.tariffs.filter((t) =>
    applies(t.hours, p.operating, localDate, time),
  );
  const t =
    matches.find((t) => t.hours.date_from !== null) ??
    matches.find((t) => t.hours.date_from === null);
  const price = minimumBookingPrice(t?.rates, p.default_duration_minutes, d);
  return price == null ? null : price;
}

/** Total package quote. All options reference the same parent hall resource. */
export function hallPackagePrice(
  v: HallConfiguration,
  hallId: string,
  optionId: string,
  localDate: string,
) {
  if (!date.safeParse(localDate).success) return null;
  const p = v.halls.find((p) => p.id === hallId && p.enabled);
  const o =
    p &&
    [p.full_day, ...p.sessions].find((o) => o.id === optionId && o.enabled);
  if (
    !p ||
    !o ||
    !applies(o.hours, p.operating, localDate, o.hours.opens_at) ||
    !applies(p.operating, p.operating, localDate, o.hours.opens_at)
  )
    return null;
  const day = new Date(localDate + "T00:00:00Z").getUTCDay() || 7;
  const matches = o.prices.filter(
    (r) =>
      r.days.includes(day) &&
      (!r.date_from ||
        (localDate >= r.date_from && localDate <= r.date_until!)),
  );
  return (
    (
      matches.find((r) => r.date_from !== null) ??
      matches.find((r) => r.date_from === null)
    )?.price_minor ?? null
  );
}
