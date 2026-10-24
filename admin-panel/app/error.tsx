"use client";
import Link from "next/link";
import { Icon } from "../components/icon";
export default function Error({
  error,
  retry,
}: {
  error: Error & { digest?: string };
  retry: () => void;
}) {
  return (
    <main>
      <div className="card error-card">
        <span className="error-icon">
          <Icon name="support" size={28} />
        </span>
        <h2>Let's try that again.</h2>
        <p className="sub">
          Something interrupted this request. Try again, or sign in to start a
          new session.
        </p>
        <div className="row">
          <button onClick={retry}>Try again</button>
          <Link className="btn ghost" href="/login">
            Back to sign in
          </Link>
        </div>
        {error.digest && (
          <small className="error-reference">Reference: {error.digest}</small>
        )}
      </div>
    </main>
  );
}
