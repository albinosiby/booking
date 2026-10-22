import Link from "next/link";
import type { Business, Website } from "../lib/types";
import { Icon } from "./icons";
import { SiteHeader } from "./site-header";
import { SpaceIllustration } from "./space-illustration";
import { imageLink, siteLink } from "../lib/site-links";

const descriptions: Record<string, string> = {
  turf: "Make time for your next game. Choose your turf, sport and a time that works for your team.",
  pool: "A little movement. A little time for yourself. Reserve your next swim.",
  badminton:
    "Bring your doubles partner or practise your singles. Your next rally starts here.",
  tennis:
    "Find your rhythm on court. Choose an available time for your next match.",
  basketball: "Get your team together and make the court yours for a game.",
  hall: "Find a space for your next occasion. Explore available dates and venue tariffs.",
};
function startingTariff(b: Business, currency: string) {
  const options = b.resources
    .flatMap((r) => r.options)
    .filter((o) => o.from_minor !== null)
    .sort((a, b) => a.from_minor! - b.from_minor!);
  const o = options[0];
  if (!o) return "View tariffs & availability";
  const price = new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency,
    maximumFractionDigits: o.from_minor! % 100 ? 2 : 0,
  }).format(o.from_minor! / 100);
  const minutes = o.minimum_duration ?? o.default_duration;
  const duration = minutes % 60 === 0 ? `${minutes / 60} hr` : `${minutes} min`;
  return `From ${price}${b.type === "pool" ? " / person" : ""} · ${duration}`;
}
export function OrganisationHome({
  site,
  preview,
}: {
  site: Website | null;
  preview?: string;
}) {
  if (!site)
    return (
      <main className="unavailable-page">
        <Icon name="calendar" size={32} />
        <h1>This website isn’t available yet.</h1>
        <p>Check the organisation’s link or contact the venue.</p>
      </main>
    );
  const addresses = [
    ...new Set(site.businesses.map((b) => b.address).filter(Boolean)),
  ];
  return (
    <>
      <a className="skip-link" href="#services">
        Skip to services
      </a>
      <SiteHeader site={site} preview={preview} />
      <main className="home-shell">
        {site.is_preview && (
          <div className="notice">
            Owner preview · Explore your website. Reservations cannot be
            submitted.
          </div>
        )}
        {site.status === "paused" && (
          <div className="notice">
            Online bookings are temporarily paused. Please contact the venue.
          </div>
        )}
        <section
          className={`home-hero ${site.hero_image ? "has-photo" : ""}`}
          aria-labelledby="hero-title"
        >
          {site.hero_image && (
            <img
              className="hero-photo"
              src={imageLink(site.slug, site.hero_image, preview)}
              alt={`${site.title} venue`}
              fetchPriority="high"
            />
          )}
          <div className="hero-shade" />
          <div className="hero-copy">
            <p className="eyebrow">Welcome to {site.title}</p>
            <h1 id="hero-title">
              A space for your
              <br />
              next great moment.
            </h1>
            <p>
              {site.description ||
                `Discover the spaces and services at ${site.title}. Find your time and book directly with us.`}
            </p>
            <a className="primary hero-cta" href="#services">
              Explore our spaces <Icon name="arrow" />
            </a>
            <span className="hero-note">
              Choose your space. Find your time. You’re all set.
            </span>
          </div>
          {!site.hero_image && (
            <div className="hero-decoration" aria-hidden="true">
              <span />
              <span />
              <span />
            </div>
          )}
        </section>
        <div className="home-benefits">
          <span>
            <Icon name="calendar" /> Live availability
          </span>
          <span>
            <Icon name="check" /> Book directly with the venue
          </span>
          <span>
            <Icon name="clock" /> Pay at the venue
          </span>
        </div>
        <section
          className="home-services"
          id="services"
          aria-labelledby="services-title"
        >
          <div className="section-intro">
            <div>
              <p className="eyebrow">Find your space</p>
              <h2 id="services-title">What would you like to book?</h2>
            </div>
            <p>
              Explore our services, check tariffs
              <br />
              and choose an available time.
            </p>
          </div>
          {!site.businesses.length && (
            <div className="empty-state">
              <h3>Our spaces are getting ready.</h3>
              <p>Please contact the venue for bookings.</p>
            </div>
          )}
          <div className="service-grid">
            {site.businesses.map((b) => {
              const photo = b.resources.flatMap((r) => r.images)[0];
              return (
                <Link
                  className="service-card"
                  key={b.id}
                  href={siteLink(site.slug, `/book/${b.id}`, preview)}
                  aria-label={`Book ${b.name}`}
                >
                  <div className={`service-card-image service-${b.type}`}>
                    {photo ? (
                      <img
                        src={imageLink(site.slug, photo, preview)}
                        alt={b.name}
                        loading="lazy"
                      />
                    ) : (
                      <SpaceIllustration
                        type={b.type}
                        name={b.name}
                        sport={b.type === "turf" ? "football" : undefined}
                      />
                    )}
                    <span className="service-location">{b.location_name}</span>
                  </div>
                  <div className="service-card-copy">
                    <h3>{b.name}</h3>
                    <p>
                      {descriptions[b.type] ||
                        `Explore ${b.name} and find your next available booking.`}
                    </p>
                    <div className="service-tariff">
                      {startingTariff(b, site.currency)}
                    </div>
                    <div className="service-card-action">
                      <span>View tariffs & book</span>
                      <span className="service-arrow">
                        <Icon name="arrow" />
                      </span>
                    </div>
                  </div>
                </Link>
              );
            })}
          </div>
        </section>
        <section className="home-about">
          <div>
            <p className="eyebrow">Your visit</p>
            <h2>We’ll see you here.</h2>
            <p>
              Have a question about a space or your booking? Get in touch with
              our team.
            </p>
            <a
              className="contact-link"
              href={`tel:${site.contact_phone.replace(/[^\d+]/g, "")}`}
            >
              <Icon name="phone" size={19} />
              {site.contact_phone}
            </a>
          </div>
          <div className="venue-addresses">
            {addresses.map((a) => (
              <p key={a}>{a}</p>
            ))}
            {site.instructions && <p>{site.instructions}</p>}
          </div>
        </section>
      </main>
      <footer className="home-footer">
        <span>{site.title}</span>
        <span>Find your space. Make it your time.</span>
      </footer>
    </>
  );
}
