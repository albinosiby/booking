import type { Business, Quote, Website } from "../lib/types";
import { durationLabel, timeLabel } from "../lib/booking-format";
import { BookingVisitNotes, ReceiptAmount } from "./booking-receipt";
import { Icon } from "./icons";

export function BookingCustomerDetails({
  site,
  business,
  booking,
  name,
  phone,
  people,
  onNameChange,
  onPhoneChange,
  onBack,
  onReview,
}: {
  site: Website;
  business?: Business;
  booking: Quote;
  name: string;
  phone: string;
  people: number;
  onNameChange: (value: string) => void;
  onPhoneChange: (value: string) => void;
  onBack: () => void;
  onReview: () => void;
}) {
  const date = new Date(
    `${booking.local_start.slice(0, 10)}T12:00:00Z`,
  ).toLocaleDateString("en-GB", {
    weekday: "short",
    day: "numeric",
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  });
  const duration = Math.round(
    (Date.parse(booking.ends_at) - Date.parse(booking.starts_at)) / 60000,
  );
  const overnight =
    booking.local_end.slice(0, 10) !== booking.local_start.slice(0, 10);
  const spaceName = booking.space_name
    .split(" · ")
    .filter((part, i, all) => i === 0 || part !== all[i - 1])
    .join(" · ");

  return (
    <div className="confirmation-view customer-details-view">
      <div className="customer-navigation">
        <button className="text-button" onClick={onBack}>
          <Icon name="back" size={17} />
          Back to times
        </button>
        <ol className="checkout-progress" aria-label="Booking progress">
          <li className="complete">
            <span>
              <Icon name="check" size={12} />
            </span>
            Space & time
          </li>
          <li aria-current="step">
            <span>2</span>Your details
          </li>
          <li>
            <span>3</span>Review
          </li>
        </ol>
      </div>
      <div className="confirmation-heading review-heading customer-heading">
        <p className="eyebrow">Make it your time</p>
        <h1>Who’s the booking for?</h1>
        <p>Just your name and number. We’ll take care of the rest.</p>
      </div>
      <div className="customer-details-card">
        <section
          className="customer-form-panel"
          aria-labelledby="contact-heading"
        >
          <div className="customer-form-heading">
            <span className="receipt-service-icon">
              <Icon name="people" size={23} />
            </span>
            <div>
              <h2 id="contact-heading">Your contact details</h2>
              <p>So the venue knows who to expect.</p>
            </div>
          </div>
          <form
            onSubmit={(event) => {
              event.preventDefault();
              onReview();
            }}
          >
            <div className="customer-field">
              <label htmlFor="customer-name">Full name</label>
              <input
                id="customer-name"
                name="name"
                autoComplete="name"
                value={name}
                minLength={2}
                maxLength={100}
                required
                onChange={(event) => onNameChange(event.target.value)}
                placeholder="Enter your full name"
              />
            </div>
            <div className="customer-field">
              <label htmlFor="customer-phone">Phone number</label>
              <input
                id="customer-phone"
                name="phone"
                type="tel"
                autoComplete="tel"
                value={phone}
                required
                minLength={7}
                maxLength={25}
                pattern={"\\+?[0-9\\s\\(\\)\\-]{7,25}"}
                aria-describedby="customer-phone-help"
                onChange={(event) => onPhoneChange(event.target.value)}
                placeholder="e.g. +91 98765 43210"
              />
              <p id="customer-phone-help" className="customer-field-help">
                Include your country code so the venue can reach you.
              </p>
            </div>
            <p className="customer-privacy">
              Your details are shared with {site.title} to manage this booking.
            </p>
            <button className="primary customer-review-button" type="submit">
              Review booking <Icon name="arrow" size={18} />
            </button>
            <p className="customer-submit-note">
              You can check everything before confirming.
            </p>
          </form>
        </section>
        <aside
          className="customer-booking-summary"
          aria-label="Your booking summary"
        >
          <div className="customer-summary-heading">
            <p className="eyebrow">Your booking</p>
            <h2>{spaceName}</h2>
            <p>{business?.name ?? site.title}</p>
          </div>
          <div className="customer-summary-body">
            <dl className="customer-booking-facts">
              <div>
                <dt><Icon name="calendar" size={17} />Date</dt>
                <dd>{date}</dd>
              </div>
              <div>
                <dt><Icon name="clock" size={17} />Time</dt>
                <dd>
                  {timeLabel(booking.local_start.slice(11, 16))} –{" "}
                  {timeLabel(booking.local_end.slice(11, 16))}
                  {overnight && (
                    <span className="receipt-next-day"> +1 day</span>
                  )}
                  <small>{durationLabel(duration)} · {booking.timezone}</small>
                </dd>
              </div>
              {business?.type === "pool" && (
                <div>
                  <dt><Icon name="people" size={17} />People</dt>
                  <dd>
                    {people} {people === 1 ? "person" : "people"}
                  </dd>
                </div>
              )}
              {business && (
                <div>
                  <dt><Icon name="pin" size={17} />Venue</dt>
                  <dd>{business.location_name}</dd>
                </div>
              )}
            </dl>
            <div className="customer-booking-total">
              <ReceiptAmount booking={booking} />
            </div>
          </div>
        </aside>
      </div>
      <BookingVisitNotes site={site} />
    </div>
  );
}
