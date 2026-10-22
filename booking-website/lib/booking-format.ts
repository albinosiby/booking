export { minutesLabel as durationLabel } from "./booking-time-grid";

export const timeLabel = (time: string) => {
  const hour = Number(time.slice(0, 2));
  return `${hour % 12 || 12}:${time.slice(3, 5)} ${hour < 12 ? "am" : "pm"}`;
};

export const moneyLabel = (minor: number, currency: string) =>
  new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency,
    maximumFractionDigits: minor % 100 ? 2 : 0,
  }).format(minor / 100);
