"use client";

import Link from "next/link";

export default function RequestError({ retry }: { retry: () => void }) {
  return (
    <div className="card" role="alert">
      <h2>Could not load call service requests</h2>
      <p className="sub">
        The service may be unavailable, the request may no longer exist, or your
        account may not have access. Refresh before retrying any configuration
        changes.
      </p>
      <div className="row">
        <button onClick={retry}>Try again</button>
        <Link className="btn ghost" href="/agent-requests">
          Back to requests
        </Link>
      </div>
    </div>
  );
}
