import { BadRequestException } from "@nestjs/common";
import { z } from "zod";
import {
  calendarDate,
  clock,
  customerSchema,
  paymentSchema,
} from "../bookings/booking.validation";
import { addDate, localStamp, zonedTime } from "../bookings/booking.inventory";

type Row = Record<string, any>;
export const enrollmentSchema = z
  .object({
    business_id: z.uuid(),
    resource_id: z.uuid(),
    // Exactly one of a configured plan or a staff-agreed subscription.
    plan_id: z.uuid().optional(),
    subscription: z.lazy(() => subscriptionSchema).optional(),
    starts_on: calendarDate,
    mode: z.enum(["fixed", "flexible", "membership"]),
    weekdays: z.array(z.number().int().min(1).max(7)).max(7),
    time: clock,
    duration_minutes: z.number().int().min(30).max(1440),
    customer: customerSchema,
    payments: z.array(paymentSchema).max(20),
    plan_amount_minor: z.number().int().min(0).max(100000000).optional(),
    renewed_from: z.uuid().nullable().default(null),
  })
  .strict();
export const createAdmissionSchema = enrollmentSchema.extend({
  command_key: z.uuid(),
  preview_token: z.string().regex(/^[a-f0-9]{64}$/),
});
/** A fixed weekly schedule to lay out before choosing a start time. */
export const slotChartSchema = z
  .object({
    business_id: z.uuid(),
    resource_id: z.uuid(),
    plan_id: z.uuid().optional(),
    subscription: z.lazy(() => subscriptionTermSchema).optional(),
    starts_on: calendarDate,
    weekdays: z.array(z.number().int().min(1).max(7)).min(1).max(7),
    duration_minutes: z.number().int().min(30).max(1440),
  })
  .strict();
/** Days before a term ends when it is listed for next month's payment. */
export function reminderDays(configuration: Row | null | undefined): number {
  return configuration?.renewal_reminder_days ?? 3;
}
/** Every subscription shares this plan id; its terms live in the snapshot. */
export const SUBSCRIPTION_PLAN_ID = "00000000-0000-4000-8000-000000000005";
export function isSubscription(plan: Row | null | undefined) {
  return plan?.subscription != null;
}
/** Length of a subscription: whole months, or a custom last day. */
export const subscriptionTermSchema = z
  .object({
    months: z.number().int().min(1).max(24).nullable(),
    ends_on: calendarDate.nullable(),
  })
  .strict();
/** Staff-agreed subscription: fee per month (or for the custom period). */
export const subscriptionSchema = subscriptionTermSchema
  .extend({ monthly_minor: z.number().int().min(0).max(100000000) })
  .strict();
export function subscriptionExpiry(
  start: string,
  term: z.infer<typeof subscriptionTermSchema>,
) {
  if ((term.months === null) === (term.ends_on === null))
    throw new BadRequestException(
      "Choose a number of months or a custom end date.",
    );
  return term.months
    ? expiryFrom(
        { expiry_mode: "after_months", expiry_months: term.months },
        start,
      )
    : term.ends_on!;
}
/**
 * Monthly fees: month k is due k months after activation, so each month end
 * opens the next fee. A custom period is a single fee due at activation.
 */
export function instalments(
  start: string,
  term: z.infer<typeof subscriptionSchema>,
) {
  const count = term.months ?? 1;
  return Array.from({ length: count }, (_, k) => ({
    due_on: k
      ? expiryFrom({ expiry_mode: "after_months", expiry_months: k }, start)
      : start,
    amount_minor: term.monthly_minor,
  }));
}
/** Fees due on or before [date]. */
export function dueBy(plan: Row, date: string) {
  return ((plan.subscription?.instalments ?? []) as Row[])
    .filter((i) => i.due_on <= date)
    .reduce((n, i) => n + i.amount_minor, 0);
}
/** A plan-like snapshot so subscriptions reuse the admission engine. */
export function subscriptionPlan(
  configuration: Row | null | undefined,
  start: string,
  term: z.infer<typeof subscriptionSchema>,
) {
  if (configuration?.subscriptions_enabled !== true)
    throw new BadRequestException(
      "Subscriptions are off for this space. Turn them on in Configure first.",
    );
  const expires = subscriptionExpiry(start, term),
    fees = instalments(start, term),
    total = fees.reduce((n, i) => n + i.amount_minor, 0);
  if (total > 100000000)
    throw new BadRequestException(
      "This subscription is above the maximum amount. Choose fewer months or a lower fee.",
    );
  return {
    id: SUBSCRIPTION_PLAN_ID,
    name: "Subscription",
    kind: configuration?.kind === "pool_v1" ? "swimming" : "play",
    enabled: true,
    track_attendance: true,
    follow_court_hours: true,
    expiry_mode: "fixed_date",
    expiry_date: expires,
    price_minor: total,
    allowance: 0,
    class_duration_minutes: null,
    class_seats: null,
    coach_id: null,
    renewal: "none",
    subscription: {
      months: term.months,
      ends_on: term.months ? null : expires,
      monthly_minor: term.monthly_minor,
      instalments: fees,
    },
  };
}
export function expiryFrom(plan: Row, start: string) {
  if (plan.expiry_mode === "fixed_date") return plan.expiry_date as string;
  if (plan.expiry_mode === "after_start")
    return addDate(start, plan.expiry_days);
  const [year, month, day] = start.split("-").map(Number);
  const count =
    plan.expiry_mode === "after_years"
      ? plan.expiry_years * 12
      : plan.expiry_months;
  const target = new Date(Date.UTC(year, month - 1 + count, 1));
  const last = new Date(
    Date.UTC(target.getUTCFullYear(), target.getUTCMonth() + 1, 0),
  ).getUTCDate();
  return `${target.toISOString().slice(0, 7)}-${String(Math.min(day, last)).padStart(2, "0")}`;
}
export const courtTypes = ["badminton", "tennis", "basketball"];
export const admissionTypes = ["pool", ...courtTypes];
/** Bookable spaces of a pool or court configuration. */
export function admissionSpaces(c: Row | null | undefined): Row[] {
  return c?.kind === "pool_v1"
    ? c.pools
    : c?.kind === "court_v1"
      ? c.courts
      : [];
}
/** Pool plans list `pool_ids`; court plans list `court_ids`. */
export function planSpaceIds(plan: Row): string[] {
  return plan.pool_ids ?? plan.court_ids ?? [];
}
// Coaches are reassigned in staff details after admissions exist, so the
// current configuration decides who teaches a plan. The admission snapshot
// only answers for plans that were removed from the configuration.
export function currentCoachId(
  config: Row | undefined,
  planId: string,
  snapshot?: Row,
): string | null {
  const plan = config?.plans?.find((p: Row) => p.id === planId);
  return (plan ? plan.coach_id : snapshot?.coach_id) ?? null;
}
/** Coach names by membership id; see `coachNames` in the admission service. */
export type CoachNames = Map<string, string>;
export function coachName(names: CoachNames, coachId: string | null) {
  if (coachId === null) return "Unassigned";
  return names.get(coachId) ?? "Unassigned";
}
export function currentCoachName(
  config: Row | undefined,
  planId: string,
  snapshot: Row | undefined,
  names: CoachNames,
) {
  return config?.plans?.some((p: Row) => p.id === planId)
    ? coachName(names, currentCoachId(config, planId))
    : (snapshot?.coach_name ?? "Unassigned");
}
export function validSwimmingDuration(pool: Row, duration: number) {
  const minimum = pool.default_duration_minutes ?? pool.durations?.[0] ?? 60;
  return (
    Number.isInteger(duration) &&
    duration >= minimum &&
    duration <= 1440 &&
    (duration - minimum) % 30 === 0
  );
}
export function interval(
  pool: Row,
  plan: Row,
  date: string,
  time: string,
  duration: number,
  zone: string,
) {
  if (plan.kind === "coaching" && duration !== plan.class_duration_minutes)
    throw new BadRequestException(
      "Use the configured coaching class duration.",
    );
  if (plan.kind !== "coaching" && !validSwimmingDuration(pool, duration))
    throw new BadRequestException(
      "Use the configured minimum visit duration, then extend in 30-minute steps.",
    );
  const start = zonedTime(date, time, zone),
    end = start + duration * 60000;
  const endStamp = localStamp(end, zone);
  for (const hours of [
    pool.operating,
    ...(plan.follow_court_hours ? [] : [plan.availability]),
  ]) {
    const minute = (v: string) =>
      Number(v.slice(0, 2)) * 60 + Number(v.slice(3));
    const overnight =
      !hours.all_day && minute(hours.closes_at) <= minute(hours.opens_at);
    const operatingDate =
      overnight && minute(time) < minute(hours.opens_at)
        ? addDate(date, -1)
        : date;
    const day = new Date(operatingDate + "T00:00:00Z").getUTCDay() || 7;
    if (
      !hours.days.includes(day) ||
      (hours.date_from && operatingDate < hours.date_from) ||
      (hours.date_until && operatingDate > hours.date_until)
    )
      throw new BadRequestException(
        "The session is outside plan or space operating days.",
      );
    if (hours.all_day) {
      const last = localStamp(end - 1, zone).slice(0, 10);
      for (let d = date; d <= last; d = addDate(d, 1))
        if (
          !hours.days.includes(new Date(d + "T00:00:00Z").getUTCDay() || 7) ||
          (hours.date_from && d < hours.date_from) ||
          (hours.date_until && d > hours.date_until)
        )
          throw new BadRequestException("The session crosses a closed day.");
    } else {
      const opens = zonedTime(operatingDate, hours.opens_at, zone);
      const closes = zonedTime(
        overnight ? addDate(operatingDate, 1) : operatingDate,
        hours.closes_at,
        zone,
      );
      if (start < opens || end > closes)
        throw new BadRequestException(
          "The session must fit space and plan operating hours.",
        );
    }
  }
  return {
    date,
    time,
    starts_at: new Date(start).toISOString(),
    ends_at: new Date(end).toISOString(),
    local_start: localStamp(start, zone),
    local_end: endStamp,
  };
}
export function fixedDates(
  start: string,
  expiry: string,
  weekdays: number[],
  allowance: number,
) {
  if (!weekdays.length || new Set(weekdays).size !== weekdays.length)
    throw new BadRequestException(
      "Choose unique weekdays for the fixed schedule.",
    );
  const dates: string[] = [];
  for (
    let date = start;
    date <= expiry && dates.length < allowance;
    date = addDate(date, 1)
  ) {
    if (weekdays.includes(new Date(date + "T00:00:00Z").getUTCDay() || 7))
      dates.push(date);
  }
  if (!dates.length)
    throw new BadRequestException(
      "No selected weekdays occur before expiry. Choose another weekday or an earlier start date.",
    );
  return dates;
}
