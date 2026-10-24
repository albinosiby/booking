export default function LoadingSetup() {
  return (
    <div aria-busy="true" aria-label="Loading call service setup">
      <div className="skeleton skeleton-heading" />
      <div className="skeleton skeleton-description" />
      <div className="skeleton skeleton-panel" aria-hidden="true" />
      <p className="sr-only" role="status">
        Loading request details and configuration…
      </p>
    </div>
  );
}
