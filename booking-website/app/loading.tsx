import { BookingOsMark } from "../components/bookingos-brand";

export default function Loading() {
  return (
    <main className="page-loading" aria-busy="true" role="status">
      <BookingOsMark size={64} />
      <p>Loading booking website…</p>
    </main>
  );
}
