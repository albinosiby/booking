import type { Metadata } from "next";
import bookingOsIcon from "../assets/bookingos-icon.png";
import { logoLink } from "./site-links";
import type { Website } from "./types";

/** Reuse the public header logo so website branding follows its publication rules. */
export function siteIcons(
  site: Website | null,
  preview?: string,
): Metadata["icons"] {
  return {
    icon: site?.has_logo
      ? { url: logoLink(site.slug, preview) }
      : { url: bookingOsIcon.src, type: "image/png", sizes: "192x192" },
  };
}
