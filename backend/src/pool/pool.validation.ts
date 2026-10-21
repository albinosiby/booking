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
export const poolHoursSchema = z
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
  .object({ id, hours: poolHoursSchema, rates: z.array(rate).min(1).max(10) })
  .strict();
const pool = z
  .object({
    id,
    name,
    capacity: z.number().int().min(1).max(10000),
    depth_min_ft: z.number().min(0).max(1000).multipleOf(0.01).nullable(),
    depth_max_ft: z.number().positive().max(1000).multipleOf(0.01).nullable(),
    enabled: z.boolean(),
    regular_swimming: z.boolean(),
    operating: poolHoursSchema,
    durations: z.array(duration).min(1).max(10),
    default_duration_minutes: duration,
    buffer_before: z.number().int().min(0).max(240),
    buffer_after: z.number().int().min(0).max(240),
    pricing_basis: z.literal("start_time"),
    tariffs: z.array(tariff).max(40),
  })
  .strict();
const offer = z
  .object({
    id,
    name,
    pool_ids: z.array(id).max(30),
    group_mode: z.enum(["exact", "up_to", "at_least"]),
    people: z.number().int().min(1).max(10000),
    duration_minutes: duration,
    price_minor: price,
    enabled: z.boolean(),
    availability: poolHoursSchema,
  })
  .strict();
const plan = z
  .object({
    id,
    name,
    kind: z.enum(["swimming", "coaching"]),
    pool_ids: z.array(id).max(30),
    allowance: z.number().int().min(1).max(10000),
    expiry_mode: z.enum([
      "after_start",
      "after_months",
      "after_years",
      "fixed_date",
    ]),
    expiry_days: z.number().int().min(1).max(3650).nullable(),
    expiry_months: z.number().int().min(1).max(120).nullable().optional(),
    expiry_years: z.number().int().min(1).max(10).nullable().optional(),
    expiry_date: date.nullable(),
    price_minor: price,
    enabled: z.boolean(),
    availability: poolHoursSchema,
    class_duration_minutes: duration.nullable(),
    class_seats: z.number().int().min(1).max(10000).nullable(),
    coach_id: id.nullable(),
    renewal: z.literal("none"),
  })
  .strict();
const minute = (v: string) => Number(v.slice(0, 2)) * 60 + Number(v.slice(3));
const span = (v: z.infer<typeof poolHoursSchema>) => hoursSpan(v);
function within(
  child: z.infer<typeof poolHoursSchema>,
  parent: z.infer<typeof poolHoursSchema>,
) {
  return hoursWithin(child, parent);
}
export const poolConfigurationSchema = z
  .object({
    kind: z.literal("pool_v1"),
    schema_version: z.literal(1),
    pools: z.array(pool).max(30),
    group_offers: z.array(offer).max(50),
    plans: z.array(plan).max(50),
    // Coaches are team members now; plans reference their membership id.
    coaches: z
      .array(z.unknown())
      .max(0, "Coach contacts were replaced by staff coaches. Refresh the app.")
      .optional(),
  })
  .strict()
  .superRefine((v, ctx) => {
    const issue = (message: string) =>
      ctx.addIssue({ code: "custom", message });
    const unique = (values: unknown[]) =>
      new Set(values).size === values.length;
    if (
      !unique([...v.pools, ...v.group_offers, ...v.plans].map((x) => x.id)) ||
      !unique(v.pools.map((p) => p.name.toLowerCase()))
    )
      issue("Use unique identifiers and pool names.");
    for (const p of v.pools) {
      if (
        p.depth_min_ft !== null &&
        p.depth_max_ft !== null &&
        p.depth_min_ft > p.depth_max_ft
      )
        issue("Minimum depth cannot exceed maximum depth.");
      if (
        p.operating.date_from !== null ||
        p.operating.date_until !== null ||
        !unique(p.durations) ||
        !p.durations.includes(p.default_duration_minutes) ||
        !unique(p.tariffs.map((t) => t.id))
      )
        issue(
          "Check pool opening hours, durations and price rule identifiers.",
        );
      for (const t of p.tariffs) {
        if (p.enabled && !within(t.hours, p.operating))
          issue("Keep tariff hours within pool opening hours.");
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
    const eligibility = (
      ids: string[],
      hours: z.infer<typeof poolHoursSchema>,
      enabled: boolean,
      count: number,
      d: number,
    ) => {
      if (!unique(ids) || ids.some((id) => !v.pools.some((p) => p.id === id)))
        issue("Use existing, distinct eligible pools.");
      for (const p of v.pools.filter((p) => ids.includes(p.id)))
        if (
          enabled &&
          (!p.enabled ||
            count > p.capacity ||
            !within(hours, p.operating) ||
            (!hours.all_day && d > span(hours)))
        )
          issue("Check eligible pool capacity, hours and duration.");
    };
    for (const o of v.group_offers)
      eligibility(
        o.pool_ids,
        o.availability,
        o.enabled,
        o.people,
        o.duration_minutes,
      );
    for (const p of v.plans) {
      const amounts = [
        p.expiry_days,
        p.expiry_months ?? null,
        p.expiry_years ?? null,
      ];
      const active =
        p.expiry_mode === "after_start"
          ? 0
          : p.expiry_mode === "after_months"
            ? 1
            : p.expiry_mode === "after_years"
              ? 2
              : -1;
      if (
        active === -1
          ? amounts.some((v) => v !== null)
          : amounts.some((v, i) => (i === active ? v === null : v !== null)) ||
            p.expiry_date !== null
      )
        issue(
          "Choose one validity unit and enter its positive period, or select a fixed expiry date.",
        );
      if (
        (p.kind === "coaching" &&
          (p.class_duration_minutes === null || p.class_seats === null)) ||
        (p.kind === "swimming" &&
          (p.class_duration_minutes !== null ||
            p.class_seats !== null ||
            p.coach_id !== null))
      )
        issue("Coaching class fields belong only to coaching plans.");
      eligibility(
        p.pool_ids,
        p.availability,
        p.enabled,
        p.kind === "coaching" ? (p.class_seats ?? 1) : 1,
        p.class_duration_minutes ?? 0,
      );
    }
  });
export type PoolConfiguration = z.infer<typeof poolConfigurationSchema>;
export const poolSaveSchema = z
  .object({
    version: z.number().int().positive(),
    configuration: poolConfigurationSchema,
  })
  .strict();
export function assertPoolComplete(
  input: unknown,
  today = new Date().toISOString().slice(0, 10),
) {
  const v = poolConfigurationSchema.parse(input);
  if (!v.pools.some((p) => p.enabled)) throw Error("Enable at least one pool.");
  for (const p of v.pools.filter((p) => p.enabled)) {
    if (p.depth_min_ft === null || p.depth_max_ft === null)
      throw Error("Enter minimum and maximum depths for every enabled pool.");
    if (
      p.regular_swimming &&
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
          .some((d) => !p.operating.all_day && d > span(p.operating)))
    )
      throw Error("Complete regular swimming prices and valid durations.");
    if (
      !p.regular_swimming &&
      !v.group_offers.some((o) => o.enabled && o.pool_ids.includes(p.id)) &&
      !v.plans.some((x) => x.enabled && x.pool_ids.includes(p.id))
    )
      throw Error(
        "Each enabled pool needs swimming prices, a group offer or a plan.",
      );
  }
  if (
    v.group_offers.some(
      (o) => o.enabled && (!o.pool_ids.length || o.price_minor === null),
    ) ||
    v.plans.some(
      (p) =>
        p.enabled &&
        (!p.pool_ids.length ||
          p.price_minor === null ||
          (p.expiry_mode === "fixed_date" &&
            (!p.expiry_date || p.expiry_date < today))),
    )
  )
    throw Error(
      "Complete eligible pools, prices and nonexpired plan expiry dates.",
    );
  return v;
}
function applies(
  hours: z.infer<typeof poolHoursSchema>,
  operating: z.infer<typeof poolHoursSchema>,
  localDate: string,
  time: string,
) {
  return windowApplies(hours, operating, localDate, time);
}
/** Configuration quote only; occupancy reservations belong to the booking module. */
export function poolPriceAtStart(
  v: PoolConfiguration,
  poolId: string,
  localDate: string,
  time: string,
  d: number,
  people = 1,
  actualDates?: IntervalDates,
) {
  if (
    !date.safeParse(localDate).success ||
    !clock.safeParse(time).success ||
    !Number.isInteger(people) ||
    people < 1
  )
    return null;
  const p = v.pools.find(
    (p) => p.id === poolId && p.enabled && p.regular_swimming,
  );
  if (
    !p ||
    people > p.capacity ||
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
  return price == null ? null : price * people;
}
export function poolGroupPrice(
  v: PoolConfiguration,
  offerId: string,
  poolId: string,
  localDate: string,
  time: string,
  people: number,
  actualDates?: IntervalDates,
) {
  if (
    !date.safeParse(localDate).success ||
    !clock.safeParse(time).success ||
    !Number.isInteger(people) ||
    people < 1
  )
    return null;
  const o = v.group_offers.find(
      (o) => o.id === offerId && o.enabled && o.pool_ids.includes(poolId),
    ),
    p = v.pools.find((p) => p.id === poolId && p.enabled);
  if (
    !o ||
    !p ||
    people > p.capacity ||
    (o.group_mode === "exact"
      ? people !== o.people
      : o.group_mode === "at_least"
        ? people < o.people
        : people > o.people) ||
    !applies(p.operating, p.operating, localDate, time) ||
    !applies(o.availability, p.operating, localDate, time)
  )
    return null;
  const start = (minute(time) - minute(p.operating.opens_at) + 1440) % 1440;
  if (
    !fitsOperatingInterval(
      p.operating,
      start,
      o.duration_minutes,
      0,
      0,
      new Date(localDate + "T00:00:00Z").getUTCDay() || 7,
      actualDates,
    )
  )
    return null;
  return o.price_minor;
}

/** Calendar validity boundary; dates are local calendar dates, never 30/365-day approximations. */
export function poolPlanExpiry(
  plan: PoolConfiguration["plans"][number],
  activationDate: string,
): string {
  date.parse(activationDate);
  if (plan.expiry_mode === "fixed_date") return date.parse(plan.expiry_date);
  const base = new Date(activationDate + "T00:00:00Z");
  if (plan.expiry_mode === "after_start") {
    if (!plan.expiry_days) throw new Error("Missing validity days.");
    base.setUTCDate(base.getUTCDate() + plan.expiry_days);
    return base.toISOString().slice(0, 10);
  }
  const months =
    plan.expiry_mode === "after_years"
      ? (plan.expiry_years ?? 0) * 12
      : (plan.expiry_months ?? 0);
  if (months < 1) throw new Error("Missing validity period.");
  const target = new Date(
    Date.UTC(base.getUTCFullYear(), base.getUTCMonth() + months, 1),
  );
  const lastDay = new Date(
    Date.UTC(target.getUTCFullYear(), target.getUTCMonth() + 1, 0),
  ).getUTCDate();
  target.setUTCDate(Math.min(base.getUTCDate(), lastDay));
  return target.toISOString().slice(0, 10);
}
