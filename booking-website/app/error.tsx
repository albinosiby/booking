"use client";

export default function Error({ retry }: { retry: () => void }) {
  return (
    <main className="unavailable-page" role="alert">
      <h1>We couldn’t load this booking website.</h1>
      <p>The connection may be interrupted. Please try again.</p>
      <button className="primary" onClick={retry}>Try again</button>
    </main>
  );
}
