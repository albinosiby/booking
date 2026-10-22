"use client";
export default function Error({ error, reset }: { error: Error; reset: () => void }) {
  return (
    <main>
      <div className="card">
        <h2>Something went wrong</h2>
        <p className="err">{error.message || "Request failed."}</p>
        <p className="sub">Check that the booking API is available and its admin signing configuration matches the panel.</p>
        <button onClick={reset}>Try again</button>
      </div>
    </main>
  );
}
