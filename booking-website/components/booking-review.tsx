"use client";
import { Icon } from "./icons";
import {
  BookingReceipt,
  BookingVisitNotes,
  ReceiptAmount,
} from "./booking-receipt";
import type { ReceiptDetails } from "./booking-receipt";
import {
  BookingPaymentChoice,
  type PaymentChoiceProps,
} from "./booking-payment-choice";

export function BookingReview({
  confirming,
  uncertain,
  locked,
  disabled,
  onEdit,
  onConfirm,
  paymentChoice,
  ...details
}: ReceiptDetails & {
  confirming: boolean;
  uncertain: boolean;
  locked: boolean;
  disabled: boolean;
  onEdit: () => void;
  onConfirm: () => void;
  paymentChoice?: PaymentChoiceProps;
}) {
  return (
    <div className="confirmation-view review-view">
      <div className="review-navigation">
        <button className="text-button" disabled={locked} onClick={onEdit}>
          <Icon name="back" size={17} />
          Edit your details
        </button>
        <span>
          <span />
          One step to go
        </span>
      </div>
      <div className="confirmation-heading review-heading">
        <p className="eyebrow">Review & confirm</p>
        <h1>One last look. Then it’s yours.</h1>
        <p>Check your booking details below before confirming.</p>
      </div>
      {paymentChoice && (
        <BookingPaymentChoice
          key={details.booking.quote_token}
          {...paymentChoice}
        />
      )}
      <BookingReceipt
        {...details}
        aside={
          <>
            <ReceiptAmount booking={details.booking} />
            {uncertain && (
              <div className="confirmation-warning" role="status">
                We haven’t received the booking result yet. Retry to check the
                same reservation safely. Your details are locked to prevent a
                duplicate booking.
              </div>
            )}
            {details.site.is_preview && (
              <p className="confirmation-warning">
                This is a read-only preview. Reservations cannot be submitted.
              </p>
            )}
            <button
              className="primary receipt-confirm-button"
              disabled={disabled}
              onClick={onConfirm}
            >
              {confirming && <span className="receipt-button-spinner" />}
              {confirming
                ? "Confirming…"
                : uncertain
                  ? "Retry confirmation"
                  : "Confirm booking"}
              {!confirming && <Icon name="arrow" size={18} />}
            </button>
            <p className="receipt-confirm-note">
              Your slot is secured when your booking is confirmed.
            </p>
          </>
        }
      />
      <BookingVisitNotes site={details.site} review />
    </div>
  );
}
