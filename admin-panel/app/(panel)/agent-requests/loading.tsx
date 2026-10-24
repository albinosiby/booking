export default function LoadingRequests() {
  return (
    <div aria-busy="true" aria-label="Loading call service requests">
      <div className="skeleton skeleton-heading" />
      <div className="skeleton skeleton-description" />
      <div className="request-grid" aria-hidden="true">
        {[0, 1, 2, 3, 4, 5].map((key) => (
          <div key={key} className="skeleton request-skeleton" />
        ))}
      </div>
      <p className="sr-only" role="status">
        Loading call service requests…
      </p>
    </div>
  );
}
