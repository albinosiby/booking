export type OperatingHours = {
  days: number[];
  opens_at: string;
  closes_at: string;
  all_day?: boolean;
  date_from?: string | null;
  date_until?: string | null;
};
const minute = (v: string) => Number(v.slice(0, 2)) * 60 + Number(v.slice(3));
const weekday = (date: string) =>
  new Date(date + "T00:00:00Z").getUTCDay() || 7;
const shiftedDay = (day: number, offset: number) =>
  ((((day - 1 + offset) % 7) + 7) % 7) + 1;
const dateNumber = (date: string) => Date.parse(date + "T00:00:00Z") / 86400000;
const shiftDate = (date: string, offset: number) =>
  new Date((dateNumber(date) + offset) * 86400000).toISOString().slice(0, 10);
export const hoursSpan = (
  h: Pick<OperatingHours, "opens_at" | "closes_at" | "all_day">,
) =>
  h.all_day ? 1440 : (minute(h.closes_at) - minute(h.opens_at) + 1440) % 1440;
export function hoursWithin(child: OperatingHours, parent: OperatingHours) {
  if (!child.days.every((d) => parent.days.includes(d))) return false;
  if (parent.all_day)
    return child.days.every(
      (d) =>
        minute(child.opens_at) + hoursSpan(child) <= 1440 ||
        parent.days.includes(shiftedDay(d, 1)),
    );
  return (
    ((minute(child.opens_at) - minute(parent.opens_at) + 1440) % 1440) +
      hoursSpan(child) <=
    hoursSpan(parent)
  );
}
/** Actual weekday/date windows, including rules crossing Sunday or a seasonal boundary. */
export function windowsOverlap(a: OperatingHours, b: OperatingHours) {
  for (const day of a.days)
    for (const offset of [-1, 0, 1]) {
      if (!b.days.includes(shiftedDay(day, offset))) continue;
      const startA = minute(a.opens_at),
        startB = minute(b.opens_at) + offset * 1440;
      if (startA >= startB + hoursSpan(b) || startB >= startA + hoursSpan(a))
        continue;
      const from = Math.max(
        a.date_from ? dateNumber(a.date_from) : -Infinity,
        b.date_from ? dateNumber(b.date_from) - offset : -Infinity,
      );
      const until = Math.min(
        a.date_until ? dateNumber(a.date_until) : Infinity,
        b.date_until ? dateNumber(b.date_until) - offset : Infinity,
      );
      if (from > until) continue;
      if (!Number.isFinite(from) || !Number.isFinite(until)) return true;
      const firstDay = new Date(from * 86400000).getUTCDay() || 7;
      if (from + ((day - firstDay + 7) % 7) <= until) return true;
    }
  return false;
}
export function windowApplies(
  h: OperatingHours,
  operating: OperatingHours,
  date: string,
  time: string,
) {
  let ruleDate = date;
  if (
    operating.all_day &&
    !h.all_day &&
    minute(h.closes_at) < minute(h.opens_at) &&
    minute(time) < minute(h.opens_at)
  )
    ruleDate = shiftDate(date, -1);
  const start = (minute(time) - minute(operating.opens_at) + 1440) % 1440;
  const from = (minute(h.opens_at) - minute(operating.opens_at) + 1440) % 1440;
  const timeMatches = operating.all_day
    ? (minute(time) - minute(h.opens_at) + 1440) % 1440 < hoursSpan(h)
    : start >= from && start < from + hoursSpan(h);
  return (
    h.days.includes(weekday(ruleDate)) &&
    (!h.date_from || (ruleDate >= h.date_from && ruleDate <= h.date_until!)) &&
    timeMatches
  );
}
export function weeklyWindowApplies(
  h: OperatingHours,
  operating: OperatingHours,
  day: number,
  time: string,
) {
  const overnight = !h.all_day && minute(h.closes_at) < minute(h.opens_at);
  const ruleDay =
    operating.all_day && overnight && minute(time) < minute(h.opens_at)
      ? shiftedDay(day, -1)
      : day;
  const start = (minute(time) - minute(operating.opens_at) + 1440) % 1440,
    from = (minute(h.opens_at) - minute(operating.opens_at) + 1440) % 1440;
  return (
    h.days.includes(ruleDay) &&
    (operating.all_day
      ? (minute(time) - minute(h.opens_at) + 1440) % 1440 < hoursSpan(h)
      : start >= from && start < from + hoursSpan(h))
  );
}
/** End is exclusive; ending exactly at midnight does not require next-day opening. */
export type IntervalDates = { from: string; until: string };
export function fitsOperatingInterval(
  h: OperatingHours,
  start: number,
  duration: number,
  before: number,
  after: number,
  day: number,
  actualDates?: IntervalDates,
) {
  if (h.all_day && actualDates)
    return allDayDatesCover(h, actualDates.from, actualDates.until);
  if (!h.all_day)
    return start - before >= 0 && start + duration + after <= hoursSpan(h);
  const first = Math.floor((start - before) / 1440),
    last = Math.ceil((start + duration + after) / 1440) - 1;
  for (let offset = first; offset <= last; offset++)
    if (!h.days.includes(shiftedDay(day, offset))) return false;
  return true;
}
/** Inventory checks timezone-resolved booking dates. */
export function allDayDatesCover(
  h: Pick<OperatingHours, "days" | "date_from" | "date_until">,
  from: string,
  until: string,
) {
  for (let cursor = dateNumber(from); cursor <= dateNumber(until); cursor++) {
    const date = new Date(cursor * 86400000).toISOString().slice(0, 10);
    if (
      !h.days.includes(weekday(date)) ||
      (h.date_from && date < h.date_from) ||
      (h.date_until && date > h.date_until)
    )
      return false;
  }
  return true;
}
