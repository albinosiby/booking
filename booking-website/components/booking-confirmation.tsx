"use client";
import { useState } from "react";
import Link from "next/link";
import type { Confirmation } from "../lib/types";
import { siteLink } from "../lib/site-links";
import { Icon } from "./icons";
import {
  BookingReceipt,
  BookingVisitNotes,
  ReceiptAmount,
} from "./booking-receipt";
import type { ReceiptDetails } from "./booking-receipt";

export function BookingConfirmation(
  props: ReceiptDetails & { booking: Confirmation },
) {
  const { site, booking, name } = props;
  const [copyState, setCopyState] = useState<"idle" | "copied" | "error">(
    "idle",
  );
  async function copyReference() {
    try {
      await navigator.clipboard.writeText(booking.reference);
      setCopyState("copied");
    } catch {
      setCopyState("error");
    }
  }
  const firstName = name.trim().split(/\s+/)[0];
  return (
    <div className="confirmation-view">
      <div className="confirmation-heading">
        <span className="confirmation-success-mark">
          <Icon name="check" size={34} />
        </span>
        <p className="eyebrow">Booking confirmed</p>
        <h1>You’re all set{firstName ? `, ${firstName}` : ""}.</h1>
        <p>
          Your time at <strong>{site.title}</strong> is reserved.
          <br />
          We look forward to seeing you.
        </p>
      </div>
      <BookingReceipt
        {...props}
        confirmed
        aside={
          <>
            <ReceiptAmount
              booking={booking}
              paid={booking.payment_status === "paid"}
            />
            <div className="receipt-secured">
              <Icon name="check" size={17} />
              <span>Your booking is secured</span>
            </div>
          </>
        }
        reference={
          <>
            <div className="reference-information">
              <p className="eyebrow">Booking reference</p>
              <strong>{booking.reference}</strong>
              <p>Show this reference when you arrive.</p>
            </div>
            <div className="reference-copy">
              <button className="receipt-outline" onClick={copyReference}>
                <Icon
                  name={copyState === "copied" ? "check" : "copy"}
                  size={17}
                />
                {copyState === "copied" ? "Copied" : "Copy reference"}
              </button>
              <p role="status">
                {copyState === "error"
                  ? "Couldn’t copy. You can select the reference above."
                  : copyState === "copied"
                    ? "Reference copied to clipboard."
                    : ""}
              </p>
            </div>
          </>
        }
      />
      <div className="confirmation-actions">
        <button className="receipt-outline" onClick={() => window.print()}>
          <Icon name="print" size={18} />
          Print booking
        </button>
        <Link className="primary" href={siteLink(site.slug)}>
          Make another booking
          <Icon name="arrow" size={18} />
        </Link>
      </div>
      <BookingVisitNotes site={site} />
    </div>
  );
}
