# Admin live data

Admin totals, organizations, users, support, agent requests and audit records come from the authenticated `/v1/admin` API. Requests use `cache: no-store`; the panel layout explicitly renders dynamically. No demo-data fallback is used in production page code. Isolated fixtures under `deploy/test` are test-only and are not copied into the runtime image.

The overview rejects missing, negative, non-integer or invalid totals instead of displaying a fabricated zero. Genuine zero counts are displayed normally. API failures reach the retryable error boundary; empty collections use the existing empty states. `BOOKING_API_BASE_URL` must be explicitly configured; there is no implicit project fallback.

Every panel page has a **Refresh data** control. The overview, organizations, users and audit log also refresh every 30 seconds while visible, when the tab becomes visible again and when the connection returns. Automatic refresh pauses while a form has focus. Other pages refresh manually to avoid interrupting editing. Sidebar links disable prefetching so navigation requests current server data. The overview shows its server-render timestamp; this represents when data was loaded, not a claim of push-based realtime updates.

The decorative login dashboard and hardcoded avatar initials were removed. The shared-password panel identifies the current session by its authorized role; it does not invent a personal administrator identity.

The frontend source changes require the usual admin deployment; API contracts are unchanged and no migration is required. Separately, the approved production QA-data cleanup has now completed as documented below. It removed explicitly identified stored test records, not rows selected solely because a name resembled test data.

Verification: admin production build passed; seven focused backend/admin-total tests passed, covering genuine values/zeros, invalid payloads, authorization, redirect behavior and live-service query behavior in isolated databases. Five focused API-origin/overview/redirect regressions also passed after requiring an explicit source. The user approved removal of the 51 persisted QA organizations; cleanup completed with verified backup and preservation checks. The live database now contains JK Group and RK Groups, four application memberships, eight businesses and seven bookings. See the [cleanup completion and frozen candidate manifest](audits/2026-10-24-live-admin-cleanup.md). Authenticated production browser rendering remains unverified.
