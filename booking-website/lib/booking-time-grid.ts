import type { Slot } from "./types";

export type TimeCell = {
  key: string;
  date: string;
  slot: Slot;
  enabled: boolean;
  start: boolean;
  end: boolean;
  inRange: boolean;
  label: string;
};
export type TimeRange = { start: string; duration: number };

export const minutesLabel = (minutes: number) =>
  `${Math.floor(minutes / 60) ? `${Math.floor(minutes / 60)} hr` : ""}${minutes % 60 ? `${minutes >= 60 ? " " : ""}${minutes % 60} min` : ""}`;

export function rangeEnd(
  date: string,
  start: string,
  duration: number,
  endSlots: Slot[] = [],
) {
  if (!date || !start || !duration) return null;
  const fallback = new Date(
    Date.parse(`${date}T${start}:00Z`) + duration * 60000,
  )
    .toISOString()
    .slice(0, 16);
  const selected = endSlots.find(
    (slot) => slot.duration_minutes === duration && slot.available,
  );
  return selected
    ? `${selected.date ?? fallback.slice(0, 10)}T${selected.time}`
    : fallback;
}

/** End options are prevalidated by the same API that supplies the app's New Booking grid. */
export function preloadedEnds(slot: Slot | undefined): Slot[] | undefined {
  return slot?.end_options?.map(([duration, stamp]) => ({
    time: stamp.slice(11, 16),
    date: stamp.slice(0, 10),
    duration_minutes: duration,
    available: true,
    status: "available",
    total_minor: 0,
  }));
}

/** Keep the original start boundaries visible while merging valid finish boundaries. */
export function bookingTimeCells({
  date,
  start,
  duration,
  slots,
  endSlots,
  minimum,
  loading = false,
  locked = false,
  pool = false,
}: TimeRange & {
  date: string;
  slots: Slot[];
  endSlots: Slot[];
  minimum: number | null;
  loading?: boolean;
  locked?: boolean;
  pool?: boolean;
}): TimeCell[] {
  if (!date) return [];
  const starts = new Map(
    slots.map((slot) => [`${slot.date ?? date}T${slot.time}`, slot]),
  );
  const ends = new Map(
    endSlots.map((slot) => [
      `${slot.date ?? rangeEnd(date, start, slot.duration_minutes ?? 0)?.slice(0, 10) ?? date}T${slot.time}`,
      slot,
    ]),
  );
  const startKey = `${date}T${start}`,
    finishKey = rangeEnd(date, start, duration, endSlots);
  const choosingEnd = !!minimum && !!start,
    waiting = choosingEnd && !duration;
  // An available validated range also proves its interior is free. This supports
  // older API versions until they provide interval_available on each conflict.
  const freeRanges =
    !pool && minimum
      ? slots.flatMap((slot) =>
          slot.available
            ? (slot.end_options ?? []).map(([, end]) => ({
                start: `${slot.date ?? date}T${slot.time}`,
                end,
              }))
            : [],
        )
      : [];
  return [...new Set([...starts.keys(), ...ends.keys()])].sort().map((key) => {
    const base = starts.get(key),
      finish = ends.get(key),
      slot = finish ?? base!;
    const isStart = choosingEnd && key === startKey;
    const isEnd = choosingEnd && !!duration && key === finishKey;
    const inRange =
      choosingEnd && !!finishKey && key > startKey && key < finishKey;
    const difference = start
      ? (Date.parse(`${key}:00Z`) - Date.parse(`${startKey}:00Z`)) / 60000
      : 0;
    const belowMinimum = difference > 0 && difference < (minimum ?? 0);
    const freeInterval =
      !pool && !!minimum && !base?.available &&
      (base?.interval_available === true ||
        (base?.interval_available === undefined &&
          freeRanges.some((range) => range.start < key && key < range.end)));
    // Start availability covers the whole minimum booking, not just this instant.
    const availableLabel =
      base?.status === "past"
        ? "Past"
        : freeInterval
          ? "Available · cannot start"
          : base?.status === "blocked"
            ? "Blocked"
            : base?.available
              ? pool && base.remaining_capacity != null
                ? `${base.remaining_capacity} places`
                : "Available"
              : !pool && minimum
                ? `Unavailable for ${minutesLabel(minimum)}`
                : "Unavailable";
    const label = isStart
      ? "Start · tap to clear"
      : isEnd
        ? "End · tap to clear"
        : waiting
          ? loading
            ? "Checking…"
            : finish?.available
              ? minutesLabel(finish.duration_minutes!)
              : finish?.status === "minimum" || belowMinimum
                ? `Min. ${minutesLabel(minimum!)}`
                : finish?.status === "past" ||
                    (!finish && base?.status === "past")
                  ? "Past"
                  : finish?.status === "blocked" || base?.status === "blocked"
                    ? "Blocked"
                    : finish?.status === "booked"
                      ? pool
                        ? "Unavailable"
                        : "Overlaps a booking"
                      : "Not a valid end"
          : inRange
            ? "Selected range"
            : base?.status === "end_only" || !base
              ? "End only"
              : availableLabel;
    return {
      key,
      date: key.slice(0, 10),
      slot,
      start: isStart,
      end: isEnd,
      inRange,
      label,
      enabled:
        !locked &&
        (isStart ||
          isEnd ||
          (!loading &&
            (waiting ? finish?.available === true : base?.available === true))),
    };
  });
}

/** Selected boundaries toggle; after a complete range another available tile starts a new one. */
export function chooseTimeCell(
  range: TimeRange,
  cell: TimeCell,
  minimum: number | null,
  defaultDuration: number,
): TimeRange {
  if (!cell.enabled) return range;
  if (!minimum) return { start: cell.slot.time, duration: defaultDuration };
  if (cell.start) return { start: "", duration: 0 };
  if (cell.end) return { start: range.start, duration: 0 };
  if (range.start && !range.duration)
    return { start: range.start, duration: cell.slot.duration_minutes ?? 0 };
  return { start: cell.slot.time, duration: 0 };
}
