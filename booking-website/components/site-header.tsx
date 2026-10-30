import Link from "next/link";
import { Icon } from "./icons";
import { BookingOsMark } from "./bookingos-brand";
import type { Website } from "../lib/types";
import { logoLink, siteLink } from "../lib/site-links";

export function SiteHeader({
  site,
  base,
  preview,
}: {
  site: Website;
  base: string;
  preview?: string;
}) {
  return (
    <header className="site-header">
      <div className="header-inner">
        <Link className="site-brand" href={siteLink(base, "", preview)}>
          <span
            className={
              site.has_logo ? "brand-logo" : "brand-logo brand-logo-fallback"
            }
          >
            {site.has_logo ? (
              <img src={logoLink(site.slug, preview)} alt="" />
            ) : (
              <BookingOsMark size={42} decorative />
            )}
          </span>
          <span>{site.title}</span>
        </Link>
        <a
          className="venue-contact"
          href={`tel:${site.contact_phone.replace(/[^\d+]/g, "")}`}
        >
          <Icon name="phone" size={17} />
          <span>Contact venue</span>
        </a>
      </div>
    </header>
  );
}
