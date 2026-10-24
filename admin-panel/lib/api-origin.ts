export function configuredApiBase(raw: string | undefined): string {
  if (!raw?.trim()) {
    throw new Error("Set BOOKING_API_BASE_URL to the live Booking API before opening the admin panel.");
  }
  const base = new URL(raw.trim());
  const local = base.protocol === "http:" && ["localhost", "127.0.0.1"].includes(base.hostname);
  if ((!local && base.protocol !== "https:") || base.username || base.password || base.search || base.hash) {
    throw new Error("Booking API must use HTTPS without credentials, query parameters or fragments.");
  }
  return base.toString().replace(/\/$/, "");
}
