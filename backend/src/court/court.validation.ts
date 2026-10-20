import {
  acceptsMinimumDuration,
  minimumBookingPrice,
} from "../common/minimum-booking";
import type { IntervalDates } from "../common/operating-hours";
import {
  hoursSpan,
  hoursWithin,
  windowsOverlap,
  windowApplies,
  fitsOperatingInterval,
} from "../common/operating-hours";
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
export const courtHoursSchema = z
  .object({
    days: z.array(z.number().int().min(1).max(7)).min(1).max(7),
    opens_at: clock,
    closes_at: clock,
    all_day: z.boolean().optional(),
    date_from: date.nullable(),
    date_until: date.nullable(),
  })
  .strict()
  .superRefine((v, ctx) => {
    if (
      new Set(v.days).size !== v.days.length ||
      (v.all_day
        ? v.opens_at !== "00:00" || v.closes_at !== "00:00"
        : v.opens_at === v.closes_at)
    )
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
  .object({ id, hours: courtHoursSchema, rates: z.array(rate).min(1).max(10) })
  .strict();
const court = z
  .object({
    id,
    name,
    enabled: z.boolean(),
    environment: z.enum(["unspecified", "indoor", "outdoor"]),
    surface: z.string().trim().max(80),
    operating: courtHoursSchema,
    durations: z.array(duration).min(1).max(10),
    default_duration_minutes: duration,
    buffer_before: z.number().int().min(0).max(240),
    buffer_after: z.number().int().min(0).max(240),
    pricing_basis: z.literal("start_time"),
    tariffs: z.array(tariff).max(40),
  })
  .strict();
const minute = (v: string) => Number(v.slice(0, 2)) * 60 + Number(v.slice(3));
const span = (v: z.infer<typeof courtHoursSchema>) => hoursSpan(v);
function within(
  child: z.infer<typeof courtHoursSchema>,
  parent: z.infer<typeof courtHoursSchema>,
) {
  return hoursWithin(child, parent);
}
export const courtConfigurationSchema = z
  .object({
    kind: z.literal("court_v1"),
    schema_version: z.literal(1),
    courts: z.array(court).max(50),
  })
  .strict()
  .superRefine((v, ctx) => {
    const issue = (message: string) =>
      ctx.addIssue({ code: "custom", message });
    const unique = (values: unknown[]) =>
      new Set(values).size === values.length;
    if (
      !unique(v.courts.map((x) => x.id)) ||
      !unique(v.courts.map((p) => p.name.toLowerCase()))
    )
      issue("Use unique identifiers and court names.");
    for (const p of v.courts) {
      if (
        p.operating.date_from !== null ||
        p.operating.date_until !== null ||
        !unique(p.durations) ||
        !p.durations.includes(p.default_duration_minutes) ||
        !unique(p.tariffs.map((t) => t.id))
      )
        issue(
          "Check court opening hours, durations and price rule identifiers.",
        );
      for (const t of p.tariffs) {
        if (p.enabled && !within(t.hours, p.operating))
          issue("Keep tariff hours within court opening hours.");
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
            (p.operating.all_day
              ? windowsOverlap(a, b)
              : dates &&
                a.days.some((d) => b.days.includes(d)) &&
                x < y + span(b) &&
                y < x + span(a))
          )
            issue("Price rules on the same tier cannot overlap.");
        }
    }
  });
export type CourtConfiguration = z.infer<typeof courtConfigurationSchema>;
export const courtSaveSchema = z
  .object({
    version: z.number().int().positive(),
    configuration: courtConfigurationSchema,
  })
  .strict();
export function assertCourtComplete(input: unknown) {
  const v = courtConfigurationSchema.parse(input);
  if (!v.courts.some((p) => p.enabled))
    throw Error("Enable at least one court.");
  for (const p of v.courts.filter((p) => p.enabled)) {
    if (
      !p.tariffs.length ||
      p.tariffs.some((t) =>
        t.rates.some(
          (r) =>
            r.duration_minutes === p.default_duration_minutes &&
            r.price_minor === null,
        ),
      ) ||
      p.durations
        .filter((d) => d === p.default_duration_minutes)
        .some((d) => !p.operating.all_day && d > span(p.operating))
    )
      throw Error("Complete court prices and valid durations.");
  }
  return v;
}
function applies(
  hours: z.infer<typeof courtHoursSchema>,
  operating: z.infer<typeof courtHoursSchema>,
  localDate: string,
  time: string,
) {
  return windowApplies(hours, operating, localDate, time);
}
/** Configuration quote only; occupancy reservations belong to the booking module. */
export function courtPriceAtStart(
  v: CourtConfiguration,
  courtId: string,
  localDate: string,
  time: string,
  d: number,
  actualDates?: IntervalDates,
) {
  if (!date.safeParse(localDate).success || !clock.safeParse(time).success)
    return null;
  const p = v.courts.find((p) => p.id === courtId && p.enabled);
  if (
    !p ||
    !acceptsMinimumDuration(d, p.default_duration_minutes) ||
    !applies(p.operating, p.operating, localDate, time)
  )
    return null;
  const start = (minute(time) - minute(p.operating.opens_at) + 1440) % 1440;
  if (
    !fitsOperatingInterval(
      p.operating,
      start,
      d,
      0,
      0,
      new Date(localDate + "T00:00:00Z").getUTCDay() || 7,
      actualDates,
    )
  )
    return null;
  const matches = p.tariffs.filter((t) =>
    applies(t.hours, p.operating, localDate, time),
  );
  const t =
    matches.find((t) => t.hours.date_from !== null) ??
    matches.find((t) => t.hours.date_from === null);
  const price = minimumBookingPrice(t?.rates, p.default_duration_minutes, d);
  return price == null ? null : price;
}
