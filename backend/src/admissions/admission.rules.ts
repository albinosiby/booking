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
    plan_id: z.uuid(),
    starts_on: calendarDate,
    mode: z.enum(["fixed", "flexible"]),
    weekdays: z.array(z.number().int().min(1).max(7)).max(7),
    time: clock,
    duration_minutes: z.number().int().min(30).max(1440),
    customer: customerSchema,
    payments: z.array(paymentSchema).max(20),
    renewed_from: z.uuid().nullable().default(null),
  })
  .strict();
export const createAdmissionSchema = enrollmentSchema.extend({
  command_key: z.uuid(),
  preview_token: z.string().regex(/^[a-f0-9]{64}$/),
});
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
  for (const hours of [pool.operating, plan.availability]) {
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
  if (dates.length !== allowance)
    throw new BadRequestException(
      `Only ${dates.length} of ${allowance} sessions fit before expiry. Choose an earlier start or more weekdays.`,
    );
  return dates;
}
