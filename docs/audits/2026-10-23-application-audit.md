# Booking OS application audit — 23 October 2026

## Verdict and scope

Follow-up: additional login-attempt and gateway cache-header changes are now applied locally. See [fix follow-up and release checks](2026-10-23-fix-followup.md) for the process-local limiter's deployment assumptions and the remaining CDN/shared-store work. The original findings below preserve the observed audit baseline.

**Do not interpret this audit as certification that every production page is fully functional.** Source inspection, automated regression suites, build checks, isolated HTTP booking journeys and read-only production HTTP checks were performed. Authenticated production UI walkthroughs could not be completed: the available browser initially exposed no existing login tabs, then repeatedly failed to attach/navigate, including a recovered blank tab. The user's existing session was not available through that connection. No session tokens were extracted from browser storage or local secrets.

The application has substantial implemented functionality and automated coverage. Confirmed defects were found in production admin redirects, public website failure handling, retry behavior and support lifecycle/loading behavior. Local fixes are prepared; **none are deployed**. Production configuration issues and incomplete external-service verification remain open.

**15 findings are documented: 13 addressed locally (including regression-test repairs), with CDN cache policy and admin attempt limiting still open.** Additional verification gaps are listed separately and are not counted as confirmed application defects.

Scope: the Flutter owner/staff application in this repository, Nest/Edge API, public booking website, admin panel, marketing landing page, deployment routing and MCP adapter. Baseline commit: `5989159`, initially clean working tree. The separate `../bookingos` application was not included, as agreed. Production host: `https://bookingos.online`.

Authorization: the user approved local fixes and isolated testing, and read-only production checks. No live database migration, deployment, real booking/payment, account permission change, notification/email send or phone installation was performed. Database-backed tests used disposable in-memory databases. Public booking HTTP tests used the documented six-business in-memory preview.

## Product analysis

- Problem: owners and staff need consistent inventory, booking, collection, admission and venue administration across mobile/web and public booking channels.
- Users: owners, scoped staff/coaches, public booking visitors, platform administrators.
- Core implementation: authentication, organization setup, six venue business types, configuration/activation, bookings/calendar, customers, manual collections, accounts/reports, expenses/income, admissions/coaching, staff access, public-site editing, support, call-service administration and notifications.
- Optional/integration-dependent features: delivered team email, native push, Sarvam calls/recordings, native sharing/downloads and OAuth callbacks. These require deployed credentials, platform provisioning and controlled integration accounts.
- Competitor comparison: not performed; this is a functional/reliability audit, not a market study.
- Main risk: a successful unit/widget test or an HTTP 200 for a Flutter shell does not prove authenticated production UI behavior or external delivery.

## Confirmed issues and fixes

| ID | Priority | Finding | Status |
| --- | --- | --- | --- |
| AUD-01 | P1 | Production signed-out admin routes redirect to `https://bookingos.online:3100/admin/login` | Fixed locally; production remains affected |
| AUD-02 | P2 | Public API outages/timeouts/5xx are converted into “website unavailable” or missing-business pages | Fixed locally |
| AUD-03 | P2 | Public routes lack a route-level loading state and recoverable error boundary | Fixed locally |
| AUD-04 | P2 | Admin error recovery uses `reset`, which clears the error without refetching failed server content in the installed Next version | Fixed locally using `retry` |
| AUD-05 | P2 | Overlapping support reads can overwrite newer data; a pending read can replace the result of a reply | Fixed locally |
| AUD-06 | P2 | Support reply completion may clear a disposed controller after navigation; direct duplicate reply calls are not guarded | Fixed locally |
| AUD-07 | P3 | Support thread Retry does not restore loading state; title field does not expose the API's 160-character limit | Fixed locally |
| AUD-08 | P2 | Production caches unversioned Flutter entry scripts for four hours despite local Nginx `no-cache` policy | Deployment/CDN follow-up required |
| AUD-09 | P2 | Marketing promises exceed currently documented/implemented services | Copy corrected locally |
| AUD-10 | P2 | Admin login has a one-second rejection delay but no attempt budget in application code | Security improvement required; gateway protection unverified |
| AUD-11 | P3 | Missing organization homepages return friendly content with HTTP 200 | Fixed locally with `notFound` and shared unavailable page |
| AUD-12 | P3 | At the 20-open-ticket limit, API text instructs users to close a request, but the customer support repository exposes no close action | Guidance corrected locally |
| AUD-13 | P2 | Login brand wordmark overflows horizontally at 320px and 1.8× text with keyboard visible | Fixed locally |
| AUD-14 | P3 | Desktop call-log regression expects obsolete “Talk time” label | Test corrected locally |
| AUD-15 | P3 | Business-order cache fixture omits the current workspace-session endpoint, leaving the cache unauthorized | Fixture and clock fixed locally |

### AUD-01: internal port in admin redirects

Reproduction: make a signed-out GET to `/admin/organizations`, `/admin/users`, `/admin/support`, `/admin/agent-requests` or `/admin/audit`. Each returned 307 with a Location containing `:3100`. `/admin` itself used a different server redirect and returned the correct public login address. A visitor entering an admin subpage or returning after session expiry can therefore be sent to an internal listener port.

Root cause: setting `NextURL.host` to a hostname without a port does not clear the existing port. `admin-panel/proxy.ts` now explicitly replaces the port using the public request host. Deliberate localhost ports are preserved. Regression: `backend/test/admin-redirect.test.ts` exercises the shared redirect-origin helper with the `/admin/login` path, production host and `localhost:8080`. An initial temporary test also passed against the real proxy with `NextRequest`; the retained regression avoids making backend CI depend on installing admin frontend packages.

Release validation: after an approved deployment, repeat the five signed-out requests; every Location must be `https://bookingos.online/admin/login`, without `:3100`. Preserve the public Host and overwrite forwarded headers at the trusted gateway as already configured.

### AUD-02, AUD-03 and AUD-11: public website failure states

Root cause: `loadWebsite` caught every failure and returned null. This made rate limits, invalid upstream authentication, network timeouts and server outages indistinguishable from an unknown venue. Business pages then called `notFound`, and organization homepages silently rendered an unavailable notice.

Fix: only explicit 404/410 responses map to an unavailable site. Other failures throw a generic sanitized error to a new route error boundary, with “Try again” using Next's server-refetching `retry`. A shared loading page announces pending content using `role=status` and `aria-busy`. Unknown venue and business pages share a friendly unavailable page. The homepage uses `notFound` for unknown sites. Streaming can affect the final transport status after headers have been sent; verify missing-page metadata and HTTP behavior in the released build.

Regression: `booking-website/test/website-response.test.mjs` covers missing/withdrawn sites, 401/403/429/500/502/503/504, valid JSON and malformed JSON. Timeouts/network failures remain sanitized at the server loader. No preview token, private request URL or upstream body is exposed in its thrown message.

### AUD-04: admin error recovery

The installed Next documentation says `retry` refetches and rerenders server content; `reset` only clears the error state and rerenders. The admin boundary now uses `retry`, so a recovered backend can be requested again. This was established by inspecting the installed version's file-convention documentation; an interactive outage/recovery click was blocked by browser availability.

### AUD-05 through AUD-07: support lifecycle and loading

Support list/thread requests lacked generation checks. Start two requests, finish the later one first, and the earlier result could restore stale data. A pending thread read could overwrite a newly sent reply. Generation checks now reject superseded reads; starting a reply supersedes reads. Closed Cubits ignore new loads/replies, duplicate replies are refused while busy, and retrying a thread visibly restores loading and clears the previous error.

The reply screen now checks `mounted` before clearing its controller after await. The create path rejects a duplicate send while active. The title field displays/enforces its 160-character limit, matching backend validation. Three deterministic Cubit regression tests cover stale list results, reply/read races, duplicate sends, disposal guards and retry loading/error transitions. A complete widget test of navigating away during reply remains a useful follow-up.

### AUD-08: production Flutter cache policy

Observed `/app/flutter_bootstrap.js` and `/app/main.dart.js`: `Cache-Control: max-age=14400`. The source Nginx template explicitly requests `no-cache` for these paths, so investigate response rewriting/CDN cache rules or deployment-source drift before changing source again. The measured main bundle was approximately 5.46 MB decoded; this is not a compressed network transfer measurement or a user-perceived loading benchmark.

Fix plan: ensure HTML and unversioned entry scripts revalidate, bypass conflicting edge TTL overrides, purge old entries after an approved deployment, then verify normal and reload navigation across two releases. Keep year-long immutable caching for genuinely hashed Next assets. Acceptance: entry scripts advertise revalidation and clients do not combine stale bootstrap/application assets with a new release.

### AUD-09: marketing/implementation mismatch

`landing-page/src/app/page.tsx` advertises Rooms, Salon and Clinic, cleaning/task-only workflows, online payments and WhatsApp-first automation. The README describes six supported business types and manual collections; the public booking documentation explicitly excludes online payments, and `DeviceMessageShare` opens a user-driven WhatsApp share flow. “Watch demo” scrolls to the journey section instead of opening a demonstration.

Local fix: list the six supported venue types, describe pay-at-venue/manual collections and user-triggered sharing, remove unsupported cleaning/task/proof claims, rename the journey CTA to “See how it works” and label the decorative phone mockups as an illustrative product preview. Review copy with product before release. No new payment/WhatsApp integration was invented during this audit.

### AUD-10: admin authentication hardening

`admin-panel/app/actions.ts` compares a single shared password and adds a one-second sleep to failed attempts. This delays each response but does not impose an aggregate attempt limit against parallel/distributed attempts. The example environment also contains a human-readable sample password; whether production uses it was deliberately not inspected or tested.

Fix plan: enforce a bounded distributed attempt budget at a trusted gateway/shared store, return a recoverable throttled response, use a strong deployment-specific password, and preferably move toward named administrators with MFA and revocation/audit attribution. Do not lock out all operators through an unbounded global counter. Acceptance: controlled staging tests of repeated and parallel failures are throttled while normal sessions remain valid. No password guessing or load attack was run against production.

### AUD-12: support request closure

`SupportService.create` rejects 20 open/in-progress requests and said “close one first.” `SupportRepository` exposes tickets/create/thread/reply only, while status updates exist in the admin flow. The local fix changes the instruction to wait for support to resolve an existing request. A customer close action, pagination beyond the current 100-ticket list and serialized enforcement of the open-ticket cap under concurrent submissions remain possible follow-up improvements.

## Page and loading-state coverage

### AUD-13 and AUD-14: failures reproduced by the full Flutter suite

The initial complete run reproduced a 94-pixel horizontal RenderFlex overflow in `auth_login_redesign_test.dart`'s 320px, 1.8× text, keyboard-visible case. `BookingBrand` laid out an unconstrained wordmark beside its fixed logo. The wordmark now uses a flexible scale-down box within the existing row, preserving the full semantic brand name and fitting the available width. Existing narrow/desktop/auth interaction tests verify the change; this does not reduce text scaling for form labels or controls.

[Verified 320px login preview with enlarged text and simulated keyboard inset](2026-10-23-evidence/login-large-text-keyboard.png). This is the initial viewport from the Flutter widget fixture, not a production browser screenshot; remaining form actions are reached by scrolling in the regression test.

The desktop call-log test expected `Talk time`, while the current screen intentionally labels the sum `Talk time shown` to avoid implying that a limited result page is the full daily aggregate. The assertion was updated to that accurate label; the test now scrolls the recording/close actions into view before tapping them, and continues to exercise call selection, transcript rendering and recording saving. These are stale test expectations and interaction assumptions, not removed application features.

AUD-15: the initial full suite also failed a business-order cache request-count assertion (four requests instead of two). The fixture served only legacy `/workspace`, while the repository now loads POST `/workspace/session`. Workspace initialization therefore failed, leaving retained caching correctly unauthorized. The fixture now handles the current endpoint, and the test explicitly checks successful workspace initialization before checking retention. An injected fixed clock also prevents freshness-window expiry from making this test dependent on machine speed. Production authorization and freshness behavior are unchanged.

The machine-readable [page inventory](2026-10-23-page-inventory.json) enumerates all 69 Flutter screen source files and all Next page files, with direct test-import pointers. A source file can contain several routes, and setup step files can be exercised indirectly through parent-wizard tests. It is an inventory, **not evidence that every button/state was manually exercised**.

| Page family | Pages included | Verification scope and remaining limitation |
| --- | --- | --- |
| Authentication | Register, sign in, verification, password update, callback/loading | Auth/Google/session/guard tests; production shell HTTP checked; actual OAuth, email/reset and current-session browser checks incomplete |
| Dashboard/navigation | Startup, Home, retained tabs, Calendar, future-module fallback | Dashboard, loading/performance, retention, route tests; signed-in production charts/data not inspected |
| Organization | Setup, details, edit | Address validation, edit/reload, responsive widgets; production save intentionally not attempted |
| Businesses | Initial selection, list/reorder, details, add/resource setup | Management, activation, identity/order/configuration tests; live data untouched |
| Turf | Wizard, grounds, spaces, sports, offerings, pricing/rules, review, direct settings | Configuration, time bounds, local drafts, responsive tests; isolated public quote/book completed |
| Courts | Setup, overview, resources, pricing, coaching, review | Badminton/tennis/basketball configuration/coaching tests; each public type booked in memory |
| Pool | Setup, overview, resources, pricing, groups, plans, review | Capacity, group/plan/attendance and responsive tests; public ordinary booking completed |
| Hall | Setup, overview, resources, pricing, review | Hourly/session/full-day validation and shared inventory tests; public booking completed |
| Bookings | List/agenda, Calendar mode, form/review/success, detail/reschedule/refund/history | Existing widget/service tests plus isolated public HTTP journeys; real production booking/payment writes excluded |
| Slot blocks | List/form | Scope, collision and widget tests; production mutations excluded |
| Customers | List/search and detail | Search/preload/pagination/access tests; actual production customer data not inspected |
| Admissions | List, enrollment, detail/renewal/attendance | Fixed/flexible/coaching/capacity/permissions tests; native/live attendance not exercised |
| Coaching | My classes and staff plan assignments | Coach/class/team tests; production coach account walkthrough incomplete |
| Accounts | Overview, transactions, settings, finance entry, reports | Balance, split, routing, report-content and responsive tests; native downloads and real records not inspected |
| Income/expenses | Income, expense list/form/detail | Validation, idempotency, reversal/export/attachment tests; device picker/download handling incomplete |
| Profile | Profile and links | Access/navigation/settings tests; production profile walk blocked |
| Team | List, assignment/detail, invitation, coaching section | Scope/revocation/email-repository tests; actual SMTP inbox delivery not tested |
| Message templates | List, editor, booking preview/share | Placeholder/primary/idempotency tests; actual WhatsApp handoff not completed |
| Website editor | Address, branding, photos, services/spaces, social, policies, publish/preview | Extensive widget/API tests; actual uploads/publication left unchanged |
| Voice agent | Service setup/status, call logs/detail/recording | Request/admin/setup/scoping tests; a real phone call, recording playback and provider outage not exercised |
| Support | List/create, thread/reply | Backend app/admin round-trip plus new lifecycle/loading tests; production sends excluded |
| Admin | Overview, organizations/list/detail, users, support/list/thread, requests/list/detail, audit, login | Build/types/API tests and signed-out production route checks; authenticated UI/actions blocked |
| Public website | Organization home, each business page, customer details/review/confirmation, unavailable/error/loading | Six-type availability→quote→confirm→same-key replay over HTTP; interactive browser journey/screenshot/responsiveness incomplete |
| Marketing | Homepage/navigation/sections/CTAs | Production HTTP, source links and build/type checks; copy gaps above; actual visual/mobile/video testing incomplete |

Loading review focus: first fetch, retained refresh, empty results, failure/retry, duplicate submission, late responses, route disposal and access changes. Existing test families include `loading_animation`, `app_loading_performance`, `startup_background`, `cached_transport`, `repository_cache`, `retained_page_state`, `retained_navigation`, and module-specific stale-response checks. No network-throttled production browser timings, layout-shift measurements or screen-reader walkthrough were obtained.

## System architecture

The owner/staff Flutter client uses module repositories, Cubits, GoRouter and a shared authorized workspace coordinator. API calls use the Supabase-hosted Edge function in the connected configuration; the Nest runtime remains available for legacy/local use. Private data is in PostgreSQL's application schema. Public Next routes use a restricted server proxy and explicit public projections. Admin Next server requests use signed proof and an HttpOnly password-session cookie. A shared gateway serves marketing `/`, Flutter `/app/`, admin `/admin/` and public tenant routing.

Data flow: public availability/quote and owner operations converge on shared inventory rules; command keys provide uncertain-write recovery and deduplication. Authentication: Supabase verifies owner/staff identity, then membership/resource/permission checks authorize requests. Public booking intentionally has no customer login/OTP/payment gateway. Admin authentication is separate and needs the hardening described above.

Scalability concerns to validate in staging: database locks under simultaneous booking/attendance, connection-pool limits per Edge worker, per-venue and per-phone rate limits, report export size/memory, uploads and tenant cache isolation. This audit is not a concurrent production load test.

## Database design and migration handling

Existing schema areas include organizations/locations/businesses/resources/configuration, memberships/invitations, customers/bookings/allocations/commands/payments, accounts/ledger/expenses/income, admissions/sessions/attendance, website settings/photos/limits, support, notifications and call-service configuration. Existing tests exercise tenant relationships, uniqueness/idempotency, conflict serialization, money validation and resource scope.

No schema change is needed for the prepared fixes. No migration was added or applied. Before any separate deployment, the user should reconcile existing migration history with the feature deployment guides, using a current backup and a verified restore process. No production row counts, index execution plans, backup restoration or RLS role grants were inspected during this audit; passing isolated tests cannot establish that production has the same schema.

## API design and error handling

Existing API contracts remain unchanged. Public journey endpoints tested: GET `/public/v1/sites/:slug`; POST `/availability`, `/quote`, `/bookings` below that site. Selections specify business/resource/option/date/time/duration/people; confirmation adds quote token, customer and a command key. Owner bearer and admin proof requirements remain enforced by existing guards and tests.

The public HTTP audit verifies catalog, six-type availability/quotes, unpaid-or-zero-total payment status, confirmation and exact-command replay returning the same reference. Invalid selections return 422; unknown sites return 404. An initial audit expectation of 400 was corrected to match the Edge validation contract, rather than changing the API. Reusing one disposable phone across business types hit the intentional three-confirmations-per-hour per-phone limit after three bookings; final checks used separate fixture phone values. That 429 is a verified protection, not an application defect.

No customer data or secrets are included in the report. Disposable QA references in evidence belong only to in-memory data.

## Testing results and evidence

| Check | Outcome |
| --- | --- |
| Flutter full-suite initial audit | 562 passed, 3 failed; failures diagnosed and local repairs prepared |
| Flutter full-suite final rerun | **568 passed, no failures** |
| Flutter final static analysis | Passed, no issues |
| Flutter final `/app/` web build | Passed, including the final login layout fix; optional Wasm dry run also passed in the preceding build |
| Focused support lifecycle regressions | 3 passed |
| Focused business-order synchronization regressions | 2 passed |
| Large-text login visual fixture | Passed; PNG retained |
| Backend complete regression suite | 295 passed, no failures |
| Backend final admin/support regression subset | 4 passed, no failures; overlaps the full suite |
| Backend build and Edge TypeScript checks | Passed |
| Public website tests | 16 passed, no failures |
| Public website production build | Passed |
| Six-business HTTP availability/quote/confirm/retry journeys | 40 assertions passed against in-memory inventory |
| Built public website pages/proxy checks | Homepage and six business pages passed; validation/allowlist/no-store checks passed |
| Admin final production build | Passed |
| Local authenticated admin rendering | Seven fixture pages and six signed-out redirect checks passed |
| Marketing final build | Passed |
| Gateway routing tests | 3 passed |
| MCP adapter tests/build | 9 passed; build passed |
| Device connection-helper tests | 5 passed |
| Read-only production HTTP | 17 known route/asset/health probes; confirmed redirect and cache findings |
| Live authenticated UI and native/external delivery | Not verified; blockers and exclusions above |

Final command outcomes and totals are recorded in the companion [verification summary](2026-10-23-verification.json). Test and build output is retained under `docs/audits/2026-10-23-evidence/`. Initial environment failures are distinct from application failures: Flutter needed SDK cache permission; `npm test`'s tsx CLI hit a sandbox pipe restriction, so equivalent backend/MCP tests were invoked using `node --import tsx --test`; the backend suite was restarted with two workers to reduce resource pressure. The interrupted initial run is not counted as a pass.

Production HTTP probes measured one request per listed route; they are observations, not service-level percentiles. Flutter `/app/home` returning HTML 200 establishes SPA fallback only. It does not establish successful authentication or rendered Home content. The security headers `X-Frame-Options: DENY` and `X-Content-Type-Options: nosniff` were observed on sampled app/admin responses. HSTS was absent in sampled responses; configure it at the HTTPS gateway only after checking all affected domain requirements. No HSTS configuration was changed.

## Security and data protection

Positive evidence in existing tests: tenant isolation, staff resource/finance scope, revocation, malformed proof/session rejection, preview write restrictions, upload validation, command replay and conflict detection. Sensitive state remains server authorized. The public proxy bounds bodies and does not forward owner tokens.

Unverified deployment properties: production migration/RLS state, actual SMTP/FCM/Sarvam credentials and delivery, MFA/operator policy, gateway rate limiting and backup restoration. These are explicit verification gaps, not assertions that production is insecure. Avoid placing preview links, customer details or admin credentials in generic audit/access logs.

## Development plan and release priorities

1. **P1, approximately half a day:** review/release the admin redirect fix through the usual deployment approval; verify all signed-out subpage redirects on the public origin. Investigate Flutter CDN TTL drift in the same release review.
2. **P2, approximately one day:** release the public failure/loading and support fixes after reviewing the recorded checks; run a controlled backend outage/recovery scenario and navigate away during a pending support reply in staging.
3. **P2, approximately one to two days:** approve marketing corrections and add staging-tested admin attempt limiting with a shared budget; evaluate named admin/MFA requirements.
4. **QA, approximately one to two days once access works:** complete the owner/staff/admin browser matrix at narrow/wide widths, refresh/deep links, slow/offline/failed loads, large text, role change/revocation, file upload/download and keyboard navigation.
5. **Integration QA, approximately one day plus provider access:** dedicated disposable OAuth/reset/email/push/voice flows and supported Android/iOS device lifecycle tests. Test installation requires separate user authorization.

Estimates are planning ranges, not commitments; external-provider access and browser availability are dependencies. No deployment is authorized by this report.

## DevOps, recovery and documentation

Existing CI covers Flutter formatting/analyze/tests/build, API formatting/build/Edge checks/tests, domain routing and an isolated container smoke with admin sessions/process failure. This audit additionally ran the public-site unit tests, MCP checks and fixture HTTP journeys. Consider making these explicit CI gates, adding browser tests against disposable fixtures, and limiting database-test concurrency on small workers.

Monitoring priorities: synthetic public health and signed-out admin redirect checks, API status/latency/error counts, booking conflict/rate-limit trends, background notification delivery outcomes and external-service failure alerts. Sanitize log fields; do not log capability URLs or customer payloads. Backup strategy and recovery drills need independent operational verification.

Local rollback: revert only the audit's focused frontend/support/proxy changes through review; no database rollback is needed. Production rollback, when a release is approved, uses the previous application image and restores/purges the appropriate unversioned asset cache. Preserve database records; no data deletion or schema rollback is required.

Setup/API/user guides already exist in `README.md`, `docs/api.md`, `docs/architecture.md`, `docs/user-guide.md`, `docs/railway-deployment.md` and module guides. This report, its page inventory, command results and evidence make the remaining QA work explicit. The oldest verification sections describe earlier milestones and should not be treated as a current production certification.
