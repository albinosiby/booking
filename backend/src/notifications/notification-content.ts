export type BookingNotificationDetails = {
  customer_name?: string | null;
  space_name?: string | null;
  starts_at?: string | null;
  ends_at?: string | null;
  timezone?: string | null;
};

// Keep user-provided names on a single line and bound the push payload size.
function label(value: unknown, fallback: string) {
  if (typeof value !== "string") return fallback;
  const text = value
    .replace(/[\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/gu, " ")
    .replace(/\s+/gu, " ")
    .trim();
  return Array.from(text).slice(0, 80).join("") || fallback;
}

function bookingTime(details: BookingNotificationDetails) {
  if (!details.starts_at || !details.timezone) return "Time unavailable";
  const start = new Date(details.starts_at);
  if (!Number.isFinite(start.getTime())) return "Time unavailable";
  try {
    const date = new Intl.DateTimeFormat("en-IN", {
      timeZone: details.timezone,
      day: "numeric",
      month: "short",
      year: "numeric",
    });
    const time = new Intl.DateTimeFormat("en-IN", {
      timeZone: details.timezone,
      hour: "numeric",
      minute: "2-digit",
      hour12: true,
      timeZoneName: "short",
    });
    const formatTime = (value: Date) =>
      time
        .format(value)
        .replace(/\s+/gu, " ")
        .replace(/\b(am|pm)\b/gi, (part) => part.toUpperCase());
    const first = `${date.format(start)}, ${formatTime(start)}`;
    const end = details.ends_at ? new Date(details.ends_at) : null;
    if (!end || !Number.isFinite(end.getTime()) || end <= start) return first;
    const endDate = date.format(end);
    return `${first} – ${endDate === date.format(start) ? "" : `${endDate}, `}${formatTime(end)}`;
  } catch {
    // An invalid legacy timezone must not prevent delivery or use server-local time.
    return "Time unavailable";
  }
}

export function bookingNotificationBody(
  reference: string,
  details?: BookingNotificationDetails | null,
) {
  const booking = label(reference, "Booking");
  if (!details) return `Booking ${booking}. Open Booking OS for details.`;
  return [
    `Name: ${label(details.customer_name, "Customer")}`,
    `Space: ${label(details.space_name, "Booked space")}`,
    `Time: ${bookingTime(details)}`,
    booking,
  ].join("\n");
}
