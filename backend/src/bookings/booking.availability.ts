import { BadRequestException, ConflictException } from "@nestjs/common";
import { Queryable } from "../common/database";
import {
  inventoryAllocations,
  SlotBlockedException,
} from "../slot-blocks/inventory-blocks";
import {
  bookingBoundaries,
  buildQuote,
  checkInventory,
  quoteContext,
} from "./booking.inventory";
import { BookingSelection } from "./booking.validation";
type Row = Record<string, any>;
/** Shared authoritative availability for authenticated and restricted guest callers. */
export async function bookingAvailability(
  db: Queryable,
  b: Row,
  selection: BookingSelection,
  endTimes = false,
  excludeBookingId?: string | null,
) {
  const context = quoteContext(b, b.timezone);
  const option = context.spaces
    .find((r: Row) => r.id === selection.resource_id)
    ?.options.find((o: Row) => o.id === selection.option_id);
  if (!option) throw new BadRequestException("Choose a valid booking option.");
  const footprint =
    b.configuration.kind === "turf_v1"
      ? b.configuration.layouts.find(
          (layout: Row) => layout.id === selection.resource_id,
        ).section_ids
      : [selection.resource_id];
  const inventoryKeys = footprint.map((id: string) => b.id + ":" + id);
  const all = await inventoryAllocations(
      db,
      b.id,
      new Date(
        Date.parse(selection.date + "T00:00:00Z") - 2 * 86400000,
      ).toISOString(),
      new Date(
        Date.parse(selection.date + "T00:00:00Z") + 3 * 86400000,
      ).toISOString(),
      inventoryKeys,
    ),
    times = option.fixed_time
      ? [option.fixed_time]
      : Array.from(
          { length: 96 },
          (_, n) =>
            `${String(Math.floor(n / 4)).padStart(2, "0")}:${String((n % 4) * 15).padStart(2, "0")}`,
        );
  const slots: Row[] = [];
  const now = Date.now();
  if (endTimes) {
    if (!option.minimum_duration)
      throw new BadRequestException("This option uses a fixed duration.");
    const startMinute =
      Number(selection.time.slice(0, 2)) * 60 + Number(selection.time.slice(3));
    const durations = [
      ...new Set([
        ...Array.from(
          { length: Math.ceil(option.minimum_duration / 15) - 1 },
          (_, n) => (n + 1) * 15,
        ),
        ...option.durations,
      ]),
    ].sort((a, b) => a - b);
    for (const duration of durations) {
      const endMinute = (startMinute + duration) % 1440;
      const time = `${String(Math.floor(endMinute / 60)).padStart(2, "0")}:${String(endMinute % 60).padStart(2, "0")}`;
      if (duration < option.minimum_duration) {
        slots.push({
          time,
          duration_minutes: duration,
          available: false,
          status: "minimum",
          total_minor: 0,
        });
        continue;
      }
      let q: ReturnType<typeof buildQuote>;
      try {
        q = buildQuote(
          b,
          { ...selection, duration_minutes: duration },
          b.timezone,
          Number.NEGATIVE_INFINITY,
          context,
        );
      } catch (e) {
        if (e instanceof BadRequestException) continue;
        throw e;
      }
      const base = {
        time: q.local_end.slice(11, 16),
        date: q.local_end.slice(0, 10),
        duration_minutes: duration,
        total_minor: q.total_minor,
      };
      if (Date.parse(q.starts_at) < now) {
        slots.push({ ...base, available: false, status: "past" });
        continue;
      }
      try {
        const checked = checkInventory(q, all, excludeBookingId ?? undefined);
        slots.push({
          ...base,
          available: true,
          status: "available",
          remaining_capacity: checked.remaining_capacity,
        });
      } catch (e) {
        if (!(e instanceof ConflictException)) throw e;
        slots.push({
          ...base,
          available: false,
          status: e instanceof SlotBlockedException ? "blocked" : "booked",
        });
      }
    }
    return { slots };
  }
  for (const time of times) {
    let q: ReturnType<typeof buildQuote>;
    try {
      // Past starts are display-only; quotes and writes retain future checks.
      q = buildQuote(
        b,
        { ...selection, time },
        b.timezone,
        Number.NEGATIVE_INFINITY,
        context,
      );
    } catch (e) {
      if (e instanceof BadRequestException) continue;
      throw e;
    }
    if (Date.parse(q.starts_at) < now) {
      slots.push({
        time,
        available: false,
        status: "past",
        total_minor: q.total_minor,
      });
      continue;
    }
    try {
      const checked = checkInventory(q, all, excludeBookingId ?? undefined);
      let endOptions: [number, string][] | undefined;
      if (option.minimum_duration) {
        // For a fixed start, price and occupied interval grow monotonically.
        // Find the last valid duration without checking every possible pair.
        let low = 0,
          high = option.durations.length - 1;
        while (low < high) {
          const middle = Math.ceil((low + high) / 2);
          try {
            const candidate = buildQuote(
              b,
              {
                ...selection,
                time,
                duration_minutes: option.durations[middle],
              },
              b.timezone,
              Number.NEGATIVE_INFINITY,
              context,
            );
            checkInventory(candidate, all, excludeBookingId ?? undefined);
            low = middle;
          } catch (error) {
            if (
              !(error instanceof BadRequestException) &&
              !(error instanceof ConflictException)
            )
              throw error;
            high = middle - 1;
          }
        }
        const instant = Date.parse(q.starts_at);
        endOptions = option.durations
          .slice(0, low + 1)
          .map((duration: number) => [
            duration,
            context.stamp(instant + duration * 60000),
          ]);
      }
      slots.push({
        time,
        available: true,
        status: "available",
        total_minor: q.total_minor,
        remaining_capacity: checked.remaining_capacity,
        ...(endOptions ? { end_options: endOptions } : {}),
      });
    } catch (e) {
      if (!(e instanceof ConflictException)) throw e;
      slots.push({
        time,
        available: false,
        status: e instanceof SlotBlockedException ? "blocked" : "booked",
        total_minor: q.total_minor,
      });
    }
  }
  if (option.minimum_duration) {
    const present = new Set(
      slots.map((slot) => `${slot.date ?? selection.date}T${slot.time}`),
    );
    for (const boundary of bookingBoundaries(b, selection)) {
      if (present.has(boundary.date + "T" + boundary.time)) continue;
      let instant: number;
      try {
        instant = context.time(boundary.date, boundary.time);
      } catch (error) {
        if (error instanceof BadRequestException) continue;
        throw error;
      }
      const past = instant < now;
      slots.push({
        ...boundary,
        available: false,
        past,
        status: past ? "past" : "end_only",
        total_minor: 0,
      });
    }
    slots.sort((a, b) =>
      `${a.date ?? selection.date}T${a.time}`.localeCompare(
        `${b.date ?? selection.date}T${b.time}`,
      ),
    );
  }
  return { slots };
}
