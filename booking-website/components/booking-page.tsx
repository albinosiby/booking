"use client";
import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { SiteHeader } from "./site-header";
import { SpaceGallery } from "./space-gallery";
import { BookingTimePicker } from "./booking-time-picker";
import { BookingReview } from "./booking-review";
import { BookingConfirmation } from "./booking-confirmation";
import { BookingCustomerDetails } from "./booking-customer-details";
import { siteLink } from "../lib/site-links";
import {
  useBooking,
  dateAfter,
  durationLabel,
  timeLabel,
  moneyLabel,
} from "../lib/use-booking";
import { SpaceIllustration } from "./space-illustration";
import { Icon } from "./icons";
import type { Resource, Website } from "../lib/types";
const dayName = (date: string, format: Intl.DateTimeFormatOptions) =>
  new Date(date + "T12:00:00Z").toLocaleDateString("en-GB", {
    ...format,
    timeZone: "UTC",
  });
function Step({
  number,
  icon,
  children,
}: {
  number: string;
  icon: "calendar" | "people" | "clock";
  children: React.ReactNode;
}) {
  return (
    <div className="step-heading">
      <span className="step-icon">
        <Icon name={icon} />
      </span>
      <span className="step-number">{number}</span>
      <h2>{children}</h2>
    </div>
  );
}
export function BookingPage({
  slug,
  preview,
  initialSite = null,
}: {
  slug: string;
  preview?: string;
  initialSite?: Website | null;
}) {
  const b = useBooking(slug, preview, initialSite),
    [showTariffs, setShowTariffs] = useState(false),
    calendar = useRef<HTMLInputElement>(null);
  useEffect(() => {
    if (b.mode !== "slots") window.scrollTo({ top: 0, behavior: "auto" });
  }, [b.mode]);
  const { site, business, resource, option, quote, confirmation } = b;
  if (b.loading)
    return (
      <main className="page-loading" aria-busy="true">
        <div className="loader" />
        <p>Getting your spaces ready…</p>
      </main>
    );
  if (!site)
    return (
      <main className="unavailable-page">
        <div className="empty-symbol">
          <Icon name="calendar" size={32} />
        </div>
        <h1>This booking website isn’t available yet.</h1>
        <p>
          {b.error ||
            "Please check the organisation’s booking link or contact the venue."}
        </p>
        <button className="primary" onClick={() => window.location.reload()}>
          Try again
        </button>
      </main>
    );
  const money = (v: number) => moneyLabel(v, site.currency),
    isPool = business?.type === "pool",
    isTurf = business?.type === "turf",
    isHall = business?.type === "hall";
  const resources = [...(business?.resources ?? [])].sort((a, c) =>
    isTurf ? c.section_ids.length - a.section_ids.length : 0,
  );
  const selectedName = (r: Resource) =>
    isTurf ? (r.name.split(" · ").at(-1) ?? r.name) : r.name;
  const selectedQuote = confirmation ?? quote;
  const reviewQuote = quote ?? b.pending?.quote;
  const canContinue = !!quote && !b.quoting && !b.pending;
  const lastDate = business ? dateAfter(business.today, site.advance_days) : "";
  const firstDate =
    b.date || business?.today || new Date().toISOString().slice(0, 10);
  const remaining = Math.min(
    14,
    Math.max(
      1,
      Math.round(
        (Date.parse(lastDate + "T12:00:00Z") -
          Date.parse(firstDate + "T12:00:00Z")) /
          86400000,
      ) + 1,
    ),
  );
  const dateStrip = Array.from({ length: remaining }, (_, n) =>
    dateAfter(firstDate, n),
  );
  const summary = (
    <aside className="reservation" aria-label="Your reservation">
      <div className="reservation-top">
        <p className="eyebrow">Your reservation</p>
        <h2>
          {selectedQuote?.space_name ??
            (resource ? selectedName(resource) : "Choose your space")}
        </h2>
        <p>{selectedQuote?.local_start.slice(0, 10) ?? b.date}</p>
      </div>
      <div className="reservation-body">
        <dl>
          <div>
            <dt>Time</dt>
            <dd>
              {selectedQuote
                ? `${timeLabel(selectedQuote.local_start.slice(11, 16))} – ${timeLabel(selectedQuote.local_end.slice(11, 16))}`
                : b.start
                  ? `${timeLabel(b.start)} – choose finish`
                  : "Choose a time"}
            </dd>
          </div>
          <div>
            <dt>Duration</dt>
            <dd>
              {selectedQuote
                ? durationLabel(
                    Math.round(
                      (Date.parse(selectedQuote.ends_at) -
                        Date.parse(selectedQuote.starts_at)) /
                        60000,
                    ),
                  )
                : "—"}
            </dd>
          </div>
          {isPool && (
            <div>
              <dt>People</dt>
              <dd>{b.people}</dd>
            </div>
          )}
        </dl>
        {selectedQuote &&
          selectedQuote.local_start.slice(0, 10) !==
            selectedQuote.local_end.slice(0, 10) && (
            <p className="next-day">
              Ends {selectedQuote.local_end.slice(0, 10)} (next day)
            </p>
          )}
        <div className="reservation-total">
          <span>Total</span>
          <strong>
            {b.quoting
              ? "…"
              : selectedQuote
                ? money(selectedQuote.total_minor)
                : "—"}
          </strong>
        </div>
        {b.mode === "slots" && (
          <button
            className="primary continue"
            disabled={!canContinue}
            onClick={b.continue}
          >
            Continue to details <Icon name="arrow" />
          </button>
        )}
        <p className="timezone-note">
          {business?.timezone ?? selectedQuote?.timezone}
        </p>
      </div>
    </aside>
  );
  return (
    <>
      <a className="skip-link" href="#booking-content">
        Skip to booking
      </a>
      <SiteHeader site={site} preview={preview} />
      <main className="booking-shell" id="booking-content">
        {site.is_preview && (
          <div className="notice">
            Owner preview · Explore the booking flow. Reservations cannot be
            submitted.
          </div>
        )}
        {site.status === "paused" && (
          <div className="notice">
            Online bookings are temporarily paused. Please contact the venue.
          </div>
        )}
        {b.mode !== "success" && (
          <nav className="booking-breadcrumb" aria-label="Breadcrumb">
            <Link href={siteLink(slug, "", preview)}>
              <Icon name="back" size={17} /> All services
            </Link>
            <span>/</span>
            <span>{business?.name}</span>
          </nav>
        )}
        {b.mode === "slots" && (
          <div className="page-intro">
            <div>
              <p className="eyebrow">Reservation details</p>
              <h1>Choose your space and time</h1>
              {business && (
                <p className="site-description">
                  {business.name} · {business.location_name}
                </p>
              )}
            </div>
            <div className="secure-label">
              <span />
              Direct booking with the venue
            </div>
          </div>
        )}
        {b.mode === "slots" && resource && (
          <SpaceGallery
            key={resource.id}
            slug={slug}
            images={resource.images}
            name={selectedName(resource)}
            preview={preview}
          />
        )}
        {site.businesses.length > 1 && b.mode === "slots" && (
          <nav className="business-tabs" aria-label="Choose a business">
            {site.businesses.map((v) => (
              <button
                key={v.id}
                className={v.id === business?.id ? "active" : ""}
                disabled={!!b.pending}
                onClick={() => b.chooseBusiness(v.id)}
              >
                {v.name}
              </button>
            ))}
          </nav>
        )}
        {b.error && (
          <div className="error-banner" role="alert">
            <span>{b.error}</span>
            {!b.pending && b.mode === "slots" && (
              <button onClick={b.retry}>Refresh availability</button>
            )}
          </div>
        )}
        {!business && b.mode === "slots" ? (
          <div className="empty-state">
            <Icon name="calendar" size={32} />
            <h2>No spaces are available online yet.</h2>
            <p>Please contact the venue for bookings.</p>
          </div>
        ) : (
          <div
            className={`booking-layout ${b.mode !== "slots" ? "checkout-layout" : ""}`}
          >
            <div className="booking-main">
              {b.mode === "slots" && business && resource && option && (
                <>
                  <section className="date-section">
                    <Step number="01" icon="calendar">
                      Choose a date
                    </Step>
                    <div className="date-card">
                      <div className="date-card-top">
                        <div>
                          <h3>
                            {dayName(b.date, {
                              month: "long",
                              year: "numeric",
                            })}
                          </h3>
                          <p>Swipe to browse or open the calendar</p>
                        </div>
                        <div className="calendar-control">
                          <button
                            className="icon-button"
                            aria-label="Open date picker"
                            onClick={() => calendar.current?.showPicker()}
                          >
                            <Icon name="calendar" />
                          </button>
                          <input
                            ref={calendar}
                            aria-label="Booking date"
                            type="date"
                            min={business.today}
                            max={lastDate}
                            value={b.date}
                            onChange={(e) => b.chooseDate(e.target.value)}
                          />
                        </div>
                      </div>
                      <div className="date-strip">
                        {b.date > business.today && (
                          <button
                            className="date-back"
                            aria-label="Previous dates"
                            onClick={() =>
                              b.chooseDate(
                                dateAfter(
                                  b.date,
                                  -Math.min(
                                    7,
                                    Math.round(
                                      (Date.parse(b.date) -
                                        Date.parse(business.today)) /
                                        86400000,
                                    ),
                                  ),
                                ),
                              )
                            }
                          >
                            <Icon name="back" />
                          </button>
                        )}
                        {dateStrip.map((date) => (
                          <button
                            key={date}
                            className={`date-tile ${date === b.date ? "selected" : ""}`}
                            aria-pressed={date === b.date}
                            onClick={() => b.chooseDate(date)}
                          >
                            <span>{dayName(date, { weekday: "short" })}</span>
                            <strong>{date.slice(8, 10)}</strong>
                            <i />
                          </button>
                        ))}
                        {dateAfter(firstDate, remaining - 1) < lastDate && (
                          <button
                            className="date-back"
                            aria-label="Next dates"
                            onClick={() =>
                              b.chooseDate(dateAfter(firstDate, 7))
                            }
                          >
                            <Icon name="arrow" />
                          </button>
                        )}
                      </div>
                    </div>
                  </section>
                  <div className="selection-layout">
                    <section className="space-section">
                      <Step number="02" icon="people">
                        Choose your{" "}
                        {isTurf
                          ? "turf"
                          : isPool
                            ? "pool space"
                            : isHall
                              ? "hall"
                              : "court"}
                      </Step>
                      {isTurf ? (
                        <>
                          <div className="resource-options">
                            {resources.map((r) => {
                              const ro =
                                r.options.find(
                                  (o) => o.sport === option.sport,
                                ) ?? r.options[0];
                              return (
                                <button
                                  key={r.id}
                                  className={`resource-card ${r.id === resource.id ? "selected" : ""}`}
                                  aria-pressed={r.id === resource.id}
                                  onClick={() => b.chooseResource(r)}
                                >
                                  <span className="resource-title">
                                    {selectedName(r)}
                                    {r.id === resource.id && (
                                      <span className="selection-check">
                                        <Icon name="check" size={14} />
                                      </span>
                                    )}
                                  </span>
                                  <span>
                                    {r.section_ids.length > 1
                                      ? "Reserves both halves"
                                      : r.section_ids.length === 1
                                        ? "Individual half"
                                        : "Ground booking"}
                                    {ro.from_minor !== null
                                      ? ` · from ${money(ro.from_minor)}/${durationLabel(ro.minimum_duration ?? ro.default_duration)}`
                                      : ""}
                                  </span>
                                </button>
                              );
                            })}
                          </div>
                          {resources.some((r) => r.section_ids.length > 1) && (
                            <p className="helper">
                              A full turf reserves both halves. Choose a half
                              for a smaller game.
                            </p>
                          )}
                          <div className="sport-options">
                            {resource.options.map((o) => (
                              <button
                                key={o.id}
                                className={`sport-card ${o.sport === "cricket" ? "cricket" : ""} ${o.id === option.id ? "selected" : ""}`}
                                aria-pressed={o.id === option.id}
                                onClick={() => b.chooseOption(o.id)}
                              >
                                <span
                                  className="sport-emoji"
                                  aria-hidden="true"
                                >
                                  {o.sport === "cricket" ? "🏏" : "⚽"}
                                </span>
                                <span>
                                  <strong>
                                    {o.sport
                                      ? o.sport[0].toUpperCase() +
                                        o.sport.slice(1)
                                      : o.name}
                                  </strong>
                                  <small>
                                    {o.format || `${o.sport ?? "Sports"} pitch`}
                                  </small>
                                </span>
                                {o.id === option.id && (
                                  <span className="selection-check">
                                    <Icon name="check" size={14} />
                                  </span>
                                )}
                              </button>
                            ))}
                          </div>
                          <p className="helper">
                            Tap a half on the pitch, or choose Full Turf above.
                            The centre line is the split.
                          </p>
                          <SpaceIllustration
                            type={business.type}
                            sport={option.sport}
                            name={selectedName(resource)}
                            selected={resource}
                            resources={resources}
                            onSelect={b.chooseResource}
                          />
                        </>
                      ) : (
                        <>
                          <div className="illustrated-options">
                            {resources.map((r) => (
                              <button
                                key={r.id}
                                className={`illustrated-card ${r.id === resource.id ? "selected" : ""}`}
                                aria-pressed={r.id === resource.id}
                                onClick={() => b.chooseResource(r)}
                              >
                                <SpaceIllustration
                                  type={business.type}
                                  name={`${r.name} · ${business.location_name}`}
                                />
                                <div className="illustrated-caption">
                                  <span>
                                    <strong>{r.name}</strong>
                                    <small>
                                      {isPool
                                        ? `Up to ${r.capacity} people`
                                        : business.location_name}
                                    </small>
                                  </span>
                                  {r.id === resource.id && (
                                    <span className="selection-check">
                                      <Icon name="check" size={16} />
                                    </span>
                                  )}
                                </div>
                              </button>
                            ))}
                          </div>
                          {isHall && resource.options.length > 1 && (
                            <div className="option-buttons">
                              {resource.options.map((o) => (
                                <button
                                  className={
                                    o.id === option.id ? "selected" : ""
                                  }
                                  key={o.id}
                                  onClick={() => b.chooseOption(o.id)}
                                >
                                  {o.name}
                                </button>
                              ))}
                            </div>
                          )}
                        </>
                      )}
                      <div className="space-footer">
                        <Icon name="pin" size={17} />
                        <p>{business.address}</p>
                      </div>
                      <button
                        className="text-button"
                        onClick={() => setShowTariffs(!showTariffs)}
                        aria-expanded={showTariffs}
                      >
                        {showTariffs ? "Hide tariffs" : "View tariffs"}
                        <Icon name="chevron" size={15} />
                      </button>
                      {showTariffs && (
                        <div className="tariffs">
                          <h3>{option.name}</h3>
                          <p>
                            Rates per{" "}
                            {durationLabel(
                              option.minimum_duration ??
                                option.default_duration,
                            )}
                            {isPool ? ", per person" : ""}. Final price is
                            confirmed for your selected time.
                          </p>
                          {option.tariffs.length ? (
                            option.tariffs.map((t, n) => (
                              <div key={n}>
                                <span>
                                  {t.days.length === 7 || !t.days.length
                                    ? "Every day"
                                    : t.days
                                        .map(
                                          (d) =>
                                            [
                                              "",
                                              "Mon",
                                              "Tue",
                                              "Wed",
                                              "Thu",
                                              "Fri",
                                              "Sat",
                                              "Sun",
                                            ][d],
                                        )
                                        .join(", ")}
                                  {t.opens_at && (
                                    <>
                                      {" "}
                                      · {timeLabel(t.opens_at)}–
                                      {timeLabel(t.closes_at ?? "00:00")}
                                    </>
                                  )}
                                  {t.date_from && (
                                    <>
                                      {" "}
                                      · {t.date_from}
                                      {t.date_until
                                        ? ` to ${t.date_until}`
                                        : " onwards"}
                                    </>
                                  )}
                                </span>
                                <strong>
                                  {t.price_minor === null
                                    ? "Unavailable"
                                    : money(t.price_minor)}
                                </strong>
                              </div>
                            ))
                          ) : (
                            <p>
                              Choose a date and time to see this option’s price.
                            </p>
                          )}
                        </div>
                      )}
                    </section>
                    <section className="time-section">
                      {isPool && (
                        <div className="people-section">
                          <Step number="03" icon="people">
                            Number of people
                          </Step>
                          <label htmlFor="people">How many people</label>
                          <div className="people-counter">
                            <button
                              aria-label="Fewer people"
                              disabled={b.people <= 1}
                              onClick={() => b.changePeople(b.people - 1)}
                            >
                              −
                            </button>
                            <input
                              id="people"
                              aria-label="Number of people"
                              type="number"
                              min="1"
                              max={resource.capacity}
                              value={b.people}
                              onChange={(e) =>
                                b.changePeople(Number(e.target.value))
                              }
                            />
                            <button
                              aria-label="More people"
                              disabled={b.people >= resource.capacity}
                              onClick={() => b.changePeople(b.people + 1)}
                            >
                              +
                            </button>
                          </div>
                          <p className="helper">
                            {option.from_minor !== null
                              ? `From ${money(option.from_minor)} per person / ${durationLabel(option.minimum_duration ?? option.default_duration)}`
                              : "Price depends on the selected time"}
                          </p>
                          <p className="people-range">
                            Enter 1 to {resource.capacity} people.
                          </p>
                        </div>
                      )}
                      <Step number={isPool ? "04" : "03"} icon="clock">
                        {option.minimum_duration
                          ? "Choose start and end time"
                          : "Choose a session"}
                      </Step>
                      <BookingTimePicker
                        date={b.date}
                        start={b.start}
                        duration={b.duration}
                        finish={b.finish}
                        minimum={option.minimum_duration}
                        cells={b.timeCells}
                        loading={b.slotLoading || b.endLoading}
                        locked={!!b.pending}
                        onSelect={b.chooseCell}
                        onRefresh={b.retry}
                      />
                    </section>
                  </div>
                </>
              )}
              {b.mode === "details" && reviewQuote && (
                <BookingCustomerDetails
                  site={site}
                  business={business}
                  booking={reviewQuote}
                  name={b.name}
                  phone={b.phone}
                  people={b.people}
                  onNameChange={b.setName}
                  onPhoneChange={b.setPhone}
                  onBack={b.back}
                  onReview={b.review}
                />
              )}
              {b.mode === "review" && reviewQuote && (
                <BookingReview
                  site={site}
                  business={business}
                  booking={reviewQuote}
                  name={b.name}
                  phone={b.phone}
                  people={b.people}
                  confirming={b.confirming}
                  uncertain={b.uncertain}
                  locked={b.confirming || !!b.pending}
                  disabled={
                    b.confirming ||
                    site.is_preview ||
                    (!b.pending && !quote) ||
                    (!b.pending && site.status !== "published")
                  }
                  onEdit={b.back}
                  onConfirm={b.confirm}
                />
              )}
              {b.mode === "success" && confirmation && (
                <BookingConfirmation
                  key={confirmation.reference}
                  site={site}
                  business={business}
                  booking={confirmation}
                  name={b.name}
                  phone={b.phone}
                  people={b.people}
                />
              )}
            </div>
            {b.mode === "slots" && summary}
          </div>
        )}
        <footer className="site-footer">
          <span>Booking directly with {site.title}</span>
          <span>
            Powered by <strong>Booking OS</strong>
          </span>
        </footer>
      </main>
      {b.mode === "slots" && business && (
        <div className="mobile-reservation">
          <div>
            <span>
              {resource ? selectedName(resource) : "Your reservation"}
            </span>
            <strong>
              {quote ? money(quote.total_minor) : "Choose a time"}
            </strong>
          </div>
          <button
            className="primary"
            disabled={!canContinue}
            onClick={b.continue}
          >
            Continue <Icon name="arrow" size={17} />
          </button>
        </div>
      )}
    </>
  );
}
