/** Duration is measured from the chosen start, in quarter-hour extensions. */
export function acceptsMinimumDuration(duration: number, minimum: number) {
  return (
    Number.isInteger(duration) &&
    Number.isInteger(minimum) &&
    minimum >= 30 &&
    duration >= minimum &&
    duration <= 1440 &&
    (duration - minimum) % 15 === 0
  );
}
export function minimumBookingPrice(
  rates: { duration_minutes: number; price_minor: number | null }[] | undefined,
  minimum: number,
  duration: number,
) {
  if (!acceptsMinimumDuration(duration, minimum)) return null;
  const base = rates?.find((r) => r.duration_minutes === minimum)?.price_minor;
  if (base == null) return null;
  const amount = Math.round((base * duration) / minimum);
  return Number.isSafeInteger(amount) ? amount : null;
}
