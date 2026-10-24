"use client";
import { useState } from "react";
import type { Quote } from "../lib/types";
import { moneyLabel } from "../lib/booking-format";

export type PaymentChoiceProps = {
  payment: NonNullable<Quote["payment"]>;
  currency: string;
  qrUrl: string;
  percentage: number;
  transactionId: string;
  locked: boolean;
  onPercentage: (value: number) => void;
  onTransactionId: (value: string) => void;
};
export function BookingPaymentChoice(props: PaymentChoiceProps) {
  const {
    payment,
    currency,
    qrUrl,
    percentage,
    transactionId,
    locked,
    onPercentage,
    onTransactionId,
  } = props;
  const [copyState, setCopyState] = useState("");
  const [qrFailed, setQrFailed] = useState(false);
  const selected = payment.options.find(
    (option) => option.percentage === percentage,
  );
  if (!payment.options.length) return null;
  async function copyUpi() {
    try {
      await navigator.clipboard.writeText(payment.upi_id);
      setCopyState("UPI ID copied");
    } catch {
      setCopyState("Could not copy. Select the UPI ID and copy it manually.");
    }
  }
  return (
    <section
      className="checkout-payment"
      aria-labelledby="checkout-payment-heading"
    >
      <h2 id="checkout-payment-heading">
        {payment.required ? "Payment required" : "Payment options"}
      </h2>
      <p>
        Choose how much to pay directly to the venue. A transaction ID is
        required for a UPI payment. The venue will verify the transfer.
      </p>
      <div
        className="payment-option-chips"
        role="group"
        aria-label="Choose payment amount"
      >
        {!payment.required && (
          <button
            type="button"
            aria-pressed={percentage === 0}
            disabled={locked}
            onClick={() => onPercentage(0)}
          >
            Pay at venue
          </button>
        )}
        {payment.options.map((option) => (
          <button
            type="button"
            key={option.percentage}
            aria-pressed={percentage === option.percentage}
            disabled={locked}
            onClick={() => onPercentage(option.percentage)}
          >
            {option.percentage === 100
              ? "Full"
              : option.percentage === 50
                ? "Half"
                : "Pay"}{" "}
            ({option.percentage}%) · {moneyLabel(option.amount_minor, currency)}
          </button>
        ))}
      </div>
      {qrFailed ? (
        <p role="alert">
          Current payment details could not load or have changed. Do not pay
          using an old QR code or UPI ID. Return to slot selection and refresh
          before paying. If you already paid, contact the venue rather than
          paying again.
        </p>
      ) : (
        <div className="checkout-payment-details">
          <img
            key={qrUrl}
            src={qrUrl}
            width={200}
            height={200}
            alt="Venue UPI payment QR code"
            onError={() => setQrFailed(true)}
          />
          <div>
            <p>
              Venue UPI ID:{" "}
              <strong className="checkout-upi-id">{payment.upi_id}</strong>
            </p>
            <button
              className="secondary"
              type="button"
              disabled={locked}
              onClick={copyUpi}
            >
              Copy UPI ID
            </button>
            {copyState && <p role="status">{copyState}</p>}
            {selected && (
              <p>
                <strong>
                  Pay {moneyLabel(selected.amount_minor, currency)}
                </strong>{" "}
                in your UPI app, then enter its transaction ID below.
              </p>
            )}
            <p>
              Check the recipient and amount in your UPI app before paying. Do
              not pay twice if a booking request fails; contact the venue with
              your transaction ID.
            </p>
          </div>
        </div>
      )}
      {selected && !qrFailed && (
        <label className="checkout-transaction-id">
          UPI transaction ID / UTR
          <input
            value={transactionId}
            onChange={(event) => onTransactionId(event.target.value)}
            maxLength={64}
            minLength={6}
            pattern="[A-Za-z0-9._-]{6,64}"
            required
            disabled={locked}
            autoComplete="off"
            spellCheck={false}
            placeholder="Enter the ID from your payment app"
          />
          <small>
            This is submitted for verification. It does not automatically mark
            your booking as paid.
          </small>
        </label>
      )}
    </section>
  );
}
