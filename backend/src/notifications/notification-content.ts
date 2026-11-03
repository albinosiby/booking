export type BookingNotificationDetails = {
  customer_name?: string | null;
  space_name?: string | null;
  starts_at?: string | null;
  ends_at?: string | null;
  timezone?: string | null;
};

export type StaffCashNotificationDetails = {
  amount_minor: number;
  balance_after_minor: number;
  currency: string;
  staff_name: string;
  collector_name: string;
};

export type SubscriptionFeeDetails = {
  customer_name: string | null;
  space_name: string | null;
  amount_minor: number;
  currency: string;
  due_on: string;
};

export function subscriptionFeeNotificationBody(
  details: SubscriptionFeeDetails,
) {
  if (
    !Number.isSafeInteger(details?.amount_minor) ||
    details.amount_minor < 0 ||
    !/^[A-Z]{3}$/.test(details.currency)
  )
    throw new Error("Invalid subscription fee snapshot");
  const money = new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: details.currency,
  }).format(details.amount_minor / 100);
  return `Collect ${money} from ${label(details.customer_name, "a subscriber")} for this month at ${label(details.space_name, "the space")}.`;
}

export function staffCashNotificationBody(
  details: StaffCashNotificationDetails,
  forStaff: boolean,
) {
  if (
    !Number.isSafeInteger(details?.amount_minor) ||
    details.amount_minor <= 0 ||
    !Number.isSafeInteger(details.balance_after_minor) ||
    details.balance_after_minor < 0 ||
    !/^[A-Z]{3}$/.test(details.currency)
  )
    throw new Error("Invalid cash notification snapshot");
  const money = (minor: number) =>
    new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: details.currency,
    }).format(minor / 100);
  return `${forStaff ? `${label(details.collector_name, "The owner")} collected` : "You collected"} ${money(details.amount_minor)} from ${forStaff ? "you" : label(details.staff_name, "staff")}.\nRemaining to hand over: ${money(details.balance_after_minor)}.`;
}

export type CallWalletNotificationDetails = {
  balance_paise: number;
  minutes_left: number;
  currency: string;
};

export function callWalletNotificationBody(
  details: CallWalletNotificationDetails,
  empty: boolean,
) {
  if (
    !Number.isSafeInteger(details?.balance_paise) ||
    !Number.isSafeInteger(details.minutes_left) ||
    details.minutes_left < 0 ||
    details.currency !== "INR"
  )
    throw new Error("Invalid wallet notification snapshot");
  const balance = new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
  }).format(details.balance_paise / 100);
  return empty
    ? `Your call balance is ${balance}. Recharge now so callers can keep booking by phone.`
    : `Only ${balance} left (about ${details.minutes_left} min of calls). Recharge to avoid interruptions.`;
}

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
