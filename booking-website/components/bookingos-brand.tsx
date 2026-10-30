import bookingOsIcon from "../assets/bookingos-icon.png";

export function BookingOsMark({
  size = 32,
  decorative = false,
}: {
  size?: number;
  decorative?: boolean;
}) {
  return (
    <img
      src={bookingOsIcon.src}
      width={size}
      height={size}
      alt={decorative ? "" : "BookingOS"}
      className="bookingos-mark"
    />
  );
}

export function PoweredByBookingOs() {
  return (
    <span className="bookingos-powered">
      Powered by <BookingOsMark size={24} decorative />{" "}
      <strong>BookingOS</strong>
    </span>
  );
}
