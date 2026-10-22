export default function Loading() {
  return (
    <div aria-busy="true" aria-label="Loading workspace">
      <div className="skeleton skeleton-heading" />
      <div className="skeleton skeleton-description" />
      <div className="metric-grid">
        {[0, 1, 2, 3].map((key) => (
          <div className="skeleton skeleton-metric" key={key} />
        ))}
      </div>
      <div className="skeleton skeleton-panel" />
      <p className="sr-only" role="status">
        Loading workspace…
      </p>
    </div>
  );
}
