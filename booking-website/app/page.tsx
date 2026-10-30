import { BookingOsMark } from "../components/bookingos-brand";

export default function Home() {
  return (
    <main className="unavailable-page">
      <BookingOsMark size={80} />
      <h1>Your next game starts here.</h1>
      <p>
        Open your organisation’s booking link to browse spaces and reserve an
        available time.
      </p>
    </main>
  );
}
