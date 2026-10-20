import {
  acceptsMinimumDuration,
  minimumBookingPrice,
} from "../common/minimum-booking";
import type { IntervalDates } from "../common/operating-hours";
import {
  hoursSpan,
  hoursWithin,
  windowsOverlap,
  weeklyWindowApplies,
  fitsOperatingInterval,
} from "../common/operating-hours";
import { z } from "zod";
const name = z.string().trim().min(2).max(100);
const time = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/);
export const turfHoursSchema = z
  .object({
    days: z.array(z.number().int().min(1).max(7)).min(1).max(7),
    opens_at: time,
    closes_at: time,
    all_day: z.boolean().optional(),
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
        message:
          "Choose distinct opening/closing times and unique operating days.",
      });
  });
const tariffRateSchema = z
  .object({
    duration_minutes: z.number().int().min(30).max(1440),
    price_minor: z.number().int().min(0).max(100000000).nullable(),
  })
  .strict();
const priceBandSchema = z
  .object({
    id: z.uuid(),
    days: z.array(z.number().int().min(1).max(7)).min(1).max(7),
    starts_at: time,
    ends_at: time,
    all_day: z.boolean().optional(),
    rates: z.array(tariffRateSchema).min(1).max(10),
  })
  .strict()
  .superRefine((v, ctx) => {
    if (v.all_day && (v.starts_at !== "00:00" || v.ends_at !== "00:00"))
      ctx.addIssue({
        code: "custom",
        message: "All-day price rules use midnight boundaries.",
      });
  });
const minute = (value: string) =>
  Number(value.slice(0, 2)) * 60 + Number(value.slice(3));
export const turfConfigurationSchema = z
  .object({
    kind: z.literal("turf_v1"),
    schema_version: z.literal(1),
    sports: z.array(z.enum(["football", "cricket"])).max(2),
    grounds: z
      .array(
        z
          .object({
            id: z.uuid(),
            name,
            arrangement: z.enum(["split", "single"]),
            sections: z
              .array(z.object({ id: z.uuid(), name }).strict())
              .min(1)
              .max(2),
          })
          .strict(),
      )
      .min(1)
      .max(10),
    layouts: z
      .array(
        z
          .object({
            id: z.uuid(),
            ground_id: z.uuid(),
            name,
            section_ids: z.array(z.uuid()).min(1).max(2),
          })
          .strict(),
      )
      .min(1)
      .max(30),
    offerings: z
      .array(
        z
          .object({
            id: z.uuid(),
            layout_id: z.uuid(),
            sport: z.enum(["football", "cricket"]),
            name,
            format: z.string().trim().min(2).max(40),
            enabled: z.boolean(),
            rates: z
              .array(
                z
                  .object({
                    duration_minutes: z.number().int().min(30).max(1440),
                    price_minor: z
                      .number()
                      .int()
                      .min(0)
                      .max(100000000)
                      .nullable(),
                  })
                  .strict(),
              )
              .min(1)
              .max(10),
            pricing_rules: z.array(priceBandSchema).max(40).optional(),
            pricing_basis: z.literal("start_time").optional(),
            default_duration_minutes: z
              .number()
              .int()
              .min(30)
              .max(1440)
              .optional(),
            buffer_before: z.number().int().min(0).max(240),
            buffer_after: z.number().int().min(0).max(240),
            hours_override: turfHoursSchema.nullable(),
          })
          .strict(),
      )
      .min(2)
      .max(60),
    operating: turfHoursSchema,
    cricket_uses_football: z.boolean().optional(),
  })
  .strict()
  .superRefine((v, ctx) => {
    const issue = (message: string) =>
      ctx.addIssue({ code: "custom", message });
    const unique = (ids: string[]) => new Set(ids).size === ids.length;
    if (
      !unique(v.sports) ||
      !unique(v.grounds.map((g) => g.id)) ||
      !unique(v.grounds.flatMap((g) => g.sections.map((s) => s.id))) ||
      !unique(v.layouts.map((l) => l.id)) ||
      !unique(v.offerings.map((o) => o.id))
    )
      issue("Duplicate identifiers or sports are not allowed.");
    if (!unique(v.layouts.map((l) => l.name.toLowerCase())))
      issue("Every space needs a distinct name.");
    if (v.cricket_uses_football) {
      const football = v.offerings.filter(
        (o) => o.enabled && o.sport === "football",
      );
      const cricket = v.offerings.filter(
        (o) => o.enabled && o.sport === "cricket",
      );
      const settings = (o: (typeof v.offerings)[number]) =>
        JSON.stringify({
          rates: o.rates,
          default_duration_minutes:
            o.default_duration_minutes ?? o.rates[0]?.duration_minutes,
          buffer_before: o.buffer_before,
          buffer_after: o.buffer_after,
          hours_override: o.hours_override,
          pricing_rules: o.pricing_rules?.map(({ id, ...band }) => band),
        });
      if (
        !v.sports.includes("football") ||
        !v.sports.includes("cricket") ||
        !football.length ||
        !cricket.length ||
        cricket.some((c) => {
          const source = football.find((f) => f.layout_id === c.layout_id);
          return !source || settings(source) !== settings(c);
        })
      )
        issue("Linked Cricket settings must match Football for each space.");
    }
    const grounds = new Map(v.grounds.map((g) => [g.id, g]));
    const layouts = new Map(v.layouts.map((l) => [l.id, l]));
    for (const layout of v.layouts) {
      const ground = grounds.get(layout.ground_id);
      if (
        !ground ||
        !unique(layout.section_ids) ||
        layout.section_ids.some(
          (id) => !ground.sections.some((s) => s.id === id),
        )
      )
        issue("Spaces can occupy only sections of their own ground.");
    }
    for (const ground of v.grounds) {
      const split = ground.arrangement === "split";
      const spaces = v.layouts.filter((l) => l.ground_id === ground.id);
      const footprints = spaces.map((l) => [...l.section_ids].sort().join(","));
      const expected = ground.sections.map((s) => s.id);
      if (split)
        expected.push(
          ground.sections
            .map((s) => s.id)
            .sort()
            .join(","),
        );
      if (
        ground.sections.length !== (split ? 2 : 1) ||
        spaces.length !== (split ? 3 : 1) ||
        !unique(footprints) ||
        expected.some((id) => !footprints.includes(id))
      )
        issue(
          "A split ground needs Half A, Half B and Full Ground; a single ground needs one full space.",
        );
    }
    const pairs = v.offerings.map((o) => `${o.layout_id}:${o.sport}`);
    if (!unique(pairs) || v.offerings.length !== v.layouts.length * 2)
      issue("Each space needs one football and one cricket offering record.");
    for (const offer of v.offerings) {
      if (
        !layouts.has(offer.layout_id) ||
        (offer.enabled && !v.sports.includes(offer.sport))
      )
        issue(
          "Enabled offerings must belong to a configured space and selected sport.",
        );
      if (!unique(offer.rates.map((r) => String(r.duration_minutes))))
        issue("Booking durations cannot be repeated.");
      if (
        offer.default_duration_minutes !== undefined &&
        !offer.rates.some(
          (r) => r.duration_minutes === offer.default_duration_minutes,
        )
      )
        issue("The default booking duration must be an allowed duration.");
      const effective = offer.hours_override ?? v.operating;
      const open = minute(effective.opens_at),
        span = hoursSpan(effective);
      const intervals: {
        days: number[];
        start: number;
        end: number;
        opens: string;
        closes: string;
        allDay?: boolean;
      }[] = [];
      if (offer.pricing_rules) {
        if (!unique(offer.pricing_rules.map((rule) => rule.id)))
          issue("Pricing rule IDs must be unique within an offering.");
        for (const band of offer.pricing_rules) {
          const start = (minute(band.starts_at) - open + 1440) % 1440;
          const length = band.all_day
            ? 1440
            : (minute(band.ends_at) - minute(band.starts_at) + 1440) % 1440;
          if (
            !unique(band.days.map(String)) ||
            !length ||
            (offer.enabled &&
              !hoursWithin(
                {
                  days: band.days,
                  opens_at: band.starts_at,
                  closes_at: band.ends_at,
                  all_day: band.all_day,
                },
                effective,
              ))
          )
            issue(
              `Keep ${offer.name} pricing rules within its operating days and hours.`,
            );
          if (
            !unique(band.rates.map((r) => String(r.duration_minutes))) ||
            band.rates.length !== offer.rates.length ||
            offer.rates.some(
              (r) =>
                !band.rates.some(
                  (b) => b.duration_minutes === r.duration_minutes,
                ),
            )
          )
            issue(
              "Each pricing rule needs a price for every allowed booking duration.",
            );
          if (
            intervals.some((other) =>
              effective.all_day
                ? windowsOverlap(
                    {
                      days: band.days,
                      opens_at: band.starts_at,
                      closes_at: band.ends_at,
                      all_day: band.all_day,
                    },
                    {
                      days: other.days,
                      opens_at: other.opens,
                      closes_at: other.closes,
                      all_day: other.allDay,
                    },
                  )
                : band.days.some((d) => other.days.includes(d)) &&
                  start < other.end &&
                  other.start < start + length,
            )
          )
            issue(
              `Pricing rules overlap for ${offer.name}. Use separate days or times.`,
            );
          intervals.push({
            days: band.days,
            start,
            end: start + length,
            opens: band.starts_at,
            closes: band.ends_at,
            allDay: band.all_day,
          });
        }
      }
      const hours = offer.hours_override;
      if (hours && offer.enabled) {
        if (!hoursWithin(hours, v.operating))
          issue(
            "Offering hours must fall within the shared operating days and hours, including overnight periods.",
          );
      }
    }
  });
export const turfSaveSchema = z
  .object({
    version: z.number().int().positive(),
    configuration: turfConfigurationSchema,
  })
  .strict();
export type TurfConfiguration = z.infer<typeof turfConfigurationSchema>;
export function assertTurfComplete(input: unknown): TurfConfiguration {
  const v = turfConfigurationSchema.parse(input);
  if (
    !v.sports.length ||
    v.layouts.some(
      (l) => !v.offerings.some((o) => o.layout_id === l.id && o.enabled),
    ) ||
    v.sports.some(
      (s) => !v.offerings.some((o) => o.sport === s && o.enabled),
    ) ||
    v.offerings.some(
      (o) =>
        o.enabled &&
        (o.pricing_rules !== undefined
          ? !o.pricing_rules.length ||
            o.pricing_rules.some((b) =>
              b.rates.some(
                (r) =>
                  r.duration_minutes ===
                    (o.default_duration_minutes ??
                      o.rates[0].duration_minutes) && r.price_minor === null,
              ),
            )
          : o.rates.some(
              (r) =>
                r.duration_minutes ===
                  (o.default_duration_minutes ?? o.rates[0].duration_minutes) &&
                r.price_minor === null,
            )),
    )
  )
    throw new Error(
      "Select sports, enable an offering for every space, and enter all enabled prices before activation.",
    );
  for (const offer of v.offerings.filter((o) => o.enabled)) {
    const hours = offer.hours_override ?? v.operating;
    const minute = (t: string) =>
      Number(t.slice(0, 2)) * 60 + Number(t.slice(3));
    const span = hoursSpan(hours);
    if (
      offer.rates
        .filter(
          (r) =>
            r.duration_minutes ===
            (offer.default_duration_minutes ?? offer.rates[0].duration_minutes),
        )
        .some((r) => !hours.all_day && r.duration_minutes > span)
    )
      throw new Error(
        "Booking duration must fit the offering operating hours.",
      );
  }
  return v;
}
/** Shared by future booking inventory: sport never changes physical occupancy. */
export function turfLayoutsOverlap(
  v: TurfConfiguration,
  left: string,
  right: string,
): boolean {
  const a = v.layouts.find((l) => l.id === left),
    b = v.layouts.find((l) => l.id === right);
  if (!a || !b) throw new Error("Unknown turf layout");
  return (
    a.ground_id === b.ground_id &&
    a.section_ids.some((id) => b.section_ids.includes(id))
  );
}

/** Caller supplies the local operating day/time. Bands are [start,end); fees use booking start. */
export function turfPriceAtStart(
  config: TurfConfiguration,
  offeringId: string,
  day: number,
  startTime: string,
  duration: number,
  actualDates?: IntervalDates,
): number | null {
  if (
    !time.safeParse(startTime).success ||
    !Number.isInteger(day) ||
    day < 1 ||
    day > 7
  )
    return null;
  const offer = config.offerings.find((o) => o.id === offeringId && o.enabled);
  if (
    !offer ||
    !acceptsMinimumDuration(
      duration,
      offer.default_duration_minutes ?? offer.rates[0].duration_minutes,
    )
  )
    return null;
  const hours = offer.hours_override ?? config.operating;
  const start = (minute(startTime) - minute(hours.opens_at) + 1440) % 1440;
  const span = hoursSpan(hours);
  if (
    !hours.days.includes(day) ||
    !fitsOperatingInterval(hours, start, duration, 0, 0, day, actualDates)
  )
    return null;
  if (offer.pricing_rules === undefined)
    return minimumBookingPrice(
      offer.rates,
      offer.default_duration_minutes ?? offer.rates[0].duration_minutes,
      duration,
    );
  const band = offer.pricing_rules.find((b) => {
    return weeklyWindowApplies(
      {
        days: b.days,
        opens_at: b.starts_at,
        closes_at: b.ends_at,
        all_day: b.all_day,
      },
      hours,
      day,
      startTime,
    );
  });
  return minimumBookingPrice(
    band?.rates,
    offer.default_duration_minutes ?? offer.rates[0].duration_minutes,
    duration,
  );
}
