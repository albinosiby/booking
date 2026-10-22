import type { ReactNode } from "react";
import type { Business, Quote, Website } from "../lib/types";
import { durationLabel, moneyLabel, timeLabel } from "../lib/booking-format";
import { Icon } from "./icons";

export type ReceiptDetails = {
  site: Website;
  business?: Business;
  booking: Quote;
  name: string;
  phone: string;
  people: number;
};

export function BookingReceipt({
  site,
  business,
  booking,
  name,
  phone,
  people,
  confirmed = false,
  aside,
  reference,
}: ReceiptDetails & {
  confirmed?: boolean;
  aside: ReactNode;
  reference?: ReactNode;
}) {
  const date = new Date(
    `${booking.local_start.slice(0, 10)}T12:00:00Z`,
  ).toLocaleDateString("en-GB", {
    weekday: "long",
    day: "numeric",
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  });
  const overnight =
    booking.local_end.slice(0, 10) !== booking.local_start.slice(0, 10);
  const duration = Math.round(
    (Date.parse(booking.ends_at) - Date.parse(booking.starts_at)) / 60000,
  );
  const spaceName = booking.space_name
    .split(" · ")
    .filter((part, i, all) => i === 0 || part !== all[i - 1])
    .join(" · ");
  return (
    <section className="booking-receipt" aria-label="Booking details">
      <div className="receipt-main">
        <div className="receipt-heading">
          <span className="receipt-service-icon">
            <Icon name="calendar" size={25} />
          </span>
          <div>
            <p className="eyebrow">{business?.name ?? "Your reservation"}</p>
            <h2>{spaceName}</h2>
            <p className="receipt-organisation">{site.title}</p>
          </div>
          {confirmed && (
            <span className="receipt-status">
              <Icon name="check" size={14} />
              Confirmed
            </span>
          )}
        </div>
        <dl className="receipt-details">
          <div>
            <dt>
              <Icon name="calendar" size={17} />
              Date
            </dt>
            <dd>{date}</dd>
          </div>
          <div>
            <dt>
              <Icon name="clock" size={17} />
              Time
            </dt>
            <dd>
              {timeLabel(booking.local_start.slice(11, 16))} –{" "}
              {timeLabel(booking.local_end.slice(11, 16))}
              {overnight && <span className="receipt-next-day"> +1 day</span>}
            </dd>
            <dd className="receipt-detail-note">
              {durationLabel(duration)} · {booking.timezone}
            </dd>
          </div>
          <div>
            <dt>
              <Icon name="people" size={17} />
              Booked for
            </dt>
            <dd>{name}</dd>
            {business?.type === "pool" && (
              <dd className="receipt-detail-note">
                {people} {people === 1 ? "person" : "people"}
              </dd>
            )}
          </div>
          <div>
            <dt>
              <Icon name="phone" size={17} />
              Phone number
            </dt>
            <dd>{phone}</dd>
          </div>
        </dl>
        {business && (
          <div className="receipt-location">
            <span>
              <Icon name="pin" size={20} />
            </span>
            <div>
              <h3>{business.location_name}</h3>
              <p>{business.address}</p>
            </div>
          </div>
        )}
      </div>
      <aside className="receipt-payment" aria-label="Booking total">
        {aside}
      </aside>
      {reference && <div className="receipt-reference">{reference}</div>}
    </section>
  );
}

export function ReceiptAmount({
  booking,
  paid = booking.total_minor === 0,
}: {
  booking: Quote;
  paid?: boolean;
}) {
  return (
    <>
      <p className="receipt-amount-label">
        {paid ? "Booking total" : "Total to pay at venue"}
      </p>
      <p className="receipt-amount">
        {moneyLabel(booking.total_minor, booking.currency)}
      </p>
      <span className="receipt-payment-badge">
        <Icon name={paid ? "check" : "clock"} size={15} />
        {paid ? "No payment due" : "Pay at the venue"}
      </span>
      <p className="receipt-payment-note">
        {paid
          ? "You’re all set. There’s nothing to pay for this booking."
          : "Pay directly at the venue when you arrive. No online payment has been collected."}
      </p>
    </>
  );
}

export function BookingVisitNotes({
  site,
  review = false,
}: {
  site: Website;
  review?: boolean;
}) {
  return (
    <div className="booking-visit-notes">
      <section className="visit-instructions">
        <span className="visit-note-icon">
          <Icon name="pin" size={21} />
        </span>
        <div>
          <h2>Before your visit</h2>
          <p>
            {site.instructions ||
              "Keep your booking reference handy and show it at the venue when you arrive."}
          </p>
          {site.cancellation_policy && (
            <details className="visit-policy" open={review}>
              <summary>
                Cancellation policy
                <Icon name="chevron" size={14} />
              </summary>
              <p>{site.cancellation_policy}</p>
            </details>
          )}
        </div>
      </section>
      <section className="visit-contact">
        <p className="eyebrow">We’re here to help</p>
        <h2>Questions about your visit?</h2>
        <p>Contact the venue for help with your booking.</p>
        <a href={`tel:${site.contact_phone.replace(/[^\d+]/g, "")}`}>
          <Icon name="phone" size={17} />
          {site.contact_phone}
          <Icon name="arrow" size={17} />
        </a>
      </section>
    </div>
  );
}
