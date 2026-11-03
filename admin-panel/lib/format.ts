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
/** Paise as a plain rupee figure for form fields: 1080 → "10.80", 25000 → "250". */
export function rupeeInput(paise?: number | null) {
  if (paise == null) return "";
  return paise % 100 ? (paise / 100).toFixed(2) : String(paise / 100);
}
/** Rupees without trailing ".00": 25000 → "₹250", 1080 → "₹10.80". */
export function rupees(paise: number | string) {
  const n = Number(paise);
  return new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    minimumFractionDigits: n % 100 ? 2 : 0,
  }).format(n / 100);
}
