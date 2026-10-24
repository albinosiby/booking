import "server-only";
export function bookingApiUrl(slug: string, operation = "", preview?: string) {
  const raw =
    process.env.BOOKING_API_BASE_URL ??
    "https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api";
  const base = new URL(raw);
  if (
    base.protocol !== "https:" &&
    !(
      base.protocol === "http:" &&
      ["localhost", "127.0.0.1"].includes(base.hostname)
    )
  )
    throw new Error("Booking API must use HTTPS");
  const url = new URL(
    `${base.toString().replace(/\/$/, "")}/public/v1/sites/${encodeURIComponent(slug)}${operation ? "/" + operation : ""}`,
  );
  if (preview) url.searchParams.set("preview", preview);
  return url;
}
export function bookingHeaders() {
  return {
    apikey:
      process.env.BOOKING_API_PUBLISHABLE_KEY ??
      "sb_publishable_d6iVFApYyh41BlF9GkTsgw_h0d-chZN",
  };
}

import { cache } from "react";
import type { Website } from "./types";
import { readWebsiteResponse } from "./website-response";
/** Share the request-scoped public read between page rendering and metadata. */
export const loadWebsite = cache(
  async (slug: string, preview?: string): Promise<Website | null> => {
    try {
      const response = await fetch(bookingApiUrl(slug, "", preview), {
        headers: bookingHeaders(),
        cache: "no-store",
        signal: AbortSignal.timeout(10000),
      });
      return await readWebsiteResponse(response);
    } catch {
      throw new Error("The booking website could not be loaded. Please retry.");
    }
  },
);
