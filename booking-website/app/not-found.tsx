import { BookingOsMark } from "../components/bookingos-brand";

export default function NotFound() {
  return (
    <main className="unavailable-page">
      <BookingOsMark size={64} />
      <h1>This booking page isn’t available.</h1>
      <p>Check the organisation’s link or contact the venue.</p>
    </main>
  );
}
