export function date(value?: string | null) {
  if (!value) return "—";
  return new Date(value).toLocaleString("en-IN", { dateStyle: "medium", timeStyle: "short" });
}
export function money(minor: number | string, currency = "INR") {
  return new Intl.NumberFormat("en-IN", { style: "currency", currency }).format(Number(minor) / 100);
}
export function label(value: string) {
  return value.replace(/_/g, " ").replace(/^./, (c) => c.toUpperCase());
}
