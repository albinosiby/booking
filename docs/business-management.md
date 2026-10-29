# Profile and business management

Owners can now remove a configured or draft business from its options menu. Removal archives it, preserves booking/payment history and blocks unresolved bookings or admissions. See [business removal and migration/recovery steps](business-removal.md) before releasing this feature.

Profile is a navigation hub for the signed-in user's identity, organization, Businesses, Team & access, Accounts & payments, appearance and sign-out. Owner-only management actions are hidden for staff and guarded on direct routes. The customer directory and booking history are documented in [Customers](customers.md).

## Navigation

- Profile → Businesses (`/businesses`) lists all organization businesses, statuses and space counts.
- Add business (`/businesses/add`) reuses service selection and naming. Initial onboarding continues at `/onboarding/businesses`.
- View details (`/businesses/:id`) shows business type, status, location/address/timezone and spaces/capacities. Rename, Configure/Continue setup and View bookings are visible actions.
- Configure opens the existing business-specific settings/setup screen, retaining its validations and configuration lifecycle.
- View bookings (`/businesses/:id/bookings`) opens the existing booking list with that business selected.
- Organization details (`/organization/details`) shows existing organization and owner contact data, locations, and the existing logo replacement action. Editing contact/address fields and changing the login email are not part of this milestone.

## Shared display order

Long press a business in Businesses and drag it to a new position, then select Save order. Further drags update the same unsaved order. Cancel restores the saved order. The page auto-scrolls at the edge while dragging through longer lists, and accessibility reorder actions enter the same draft. The saved order applies to business lists, Home/calendar business groups, booking/payment filters, new-booking business cards, finance selectors/payment routing and team assignments. Chronological booking order is preserved within groups; transaction lists remain chronological. Staff inherit the relative order of the businesses they can access.

Order is organization-wide, persisted in `businesses.display_order`, and returned by Workspace, Booking and Accounts catalogs. Retained form widgets use the current workspace order without resetting entered data. Repository write invalidation refreshes affected catalogs. Other devices receive the saved order on workspace/catalog refresh; no new real-time subscription is introduced.

The first migration ranks existing businesses Turf, Swimming Pool, Badminton, Tennis, Basketball, Party Hall, with deterministic name/ID ordering inside each type. New businesses append to the existing order. Reordering does not change configuration versions or historical booking/payment records.

## API and storage

`PUT /v1/businesses/order` requires the current active owner and accepts:

```json
{"business_ids":["<first-business-uuid>","<second-business-uuid>"],"revision":2}
```

The response returns `business_ids` and the incremented `revision`. The current revision is supplied as `organization.business_order_revision` in the workspace response.

The backend validates UUIDs, duplicates, complete organization ownership and membership. Organization-row locking serializes additions and reorder saves. Both actions increment the order revision; stale editors receive HTTP 409 and reload the latest server order. Business creation cannot race with an order save and disappear from the list. Successful changes create the existing audit-event records. Nest and Edge routes support the endpoint and include PUT in their CORS method lists.

## Migration and release

`backend/migrations/004_business_order.sql` is an additive migration for the existing backend migration runner, shared by the Nest and Edge deployments. The local Nest runner applies pending migrations at startup. For the hosted private-schema deployment, apply this migration with the established database migration process before deploying the rebuilt Edge function. Edge does not run migrations automatically. No additional Data API table exposure or client credentials are needed.

Backend builds: `npm run build`, `npm run edge:check`, `npm run edge:build` from `backend`. The generated Edge bundle is `supabase/functions/booking-api/index.ts`.

Validation covers order persistence, missing/duplicate/foreign IDs, stale revisions, staff permissions and catalog consistency, plus Flutter reorder/cancel/save/failure behavior, owner/staff Profile navigation and narrow layouts. Run `flutter analyze`, `flutter test`, and the backend tests before release. Existing database backup and migration recovery procedures apply; preserve saved order columns when rolling back only the application version.

## Hosted release — 16 October 2026

Migration `004_business_order.sql` is applied to the existing private `booking_app` schema in project `scwwkaywewecspsrskft`. The rebuilt `booking-api` Edge Function was deployed through the signed-in Supabase dashboard at 15:47:48 IST. Both order columns and the migration ledger entry were verified. Organization, business, booking, payment and financial ledger row counts were unchanged. Existing runtime grants cover the new ordering fields.

Live checks returned HTTP 200 for health and the public catalog, and HTTP 401 for unauthenticated workspace and business-order requests. The dashboard reported four invocations and no server errors after these checks. Existing custom authentication settings were retained. No live test bookings, payments or business reorder mutations were created. Recovery source and a migration/deployment manifest are stored in the ignored `.local/releases/business-order-2026-10-16T10-16-25.350Z` folder.

## Expanded business details

Workspace management → View details opens a responsive overview with a status card, configured/enabled space counts, organization and owner contact information, display position, currency, venue address and timezone. Configure/Continue setup, View bookings, Rename business and Refresh remain available near the top. Phone and owner details are labelled with their organization context; no separate business contact fields are invented.

Spaces and booking options expand to show the saved configuration:

- Courts: indoor/outdoor setting, surface, operating weekdays/hours, durations/defaults, preparation/cleanup and per-court time/seasonal tariffs.
- Pools: capacity, depth range, regular admission rules and prices, group sizes/offers, swimming/coaching allowances, expiry, class duration/capacity and coach-assignment status.
- Halls: guest/seated capacity, environment, amenities, hourly rules, named sessions/full-day packages and their day/seasonal prices.
- Turf: physical grounds, split/full-ground relationships, bookable layouts, sports/formats, hours, buffers, duration-based pricing and linked Cricket/Football pricing.

Disabled entries remain visible and labelled. Missing, unsupported or malformed configurations retain the saved resource summary and direct the owner to configuration, without inventing opening hours or prices. Only the selected business is mapped into detail state. Workspace refresh updates the summary; loss of owner access removes configuration details. Scroll and expansion state use the existing page/session lifetime, and contact/address text can be selected.

This is a Flutter presentation change using existing workspace data: no new API endpoint, Supabase migration or backend deployment is needed. Release the updated Flutter client to use it. Verification covers all four saved configuration formats, missing/malformed data, disabled entries, access changes, refresh, management navigation, light/dark themes and narrow layouts with enlarged text.

Business-details verification: targeted analysis is clean and all 15 detail/architecture tests pass, including Rename → Configure navigation, refreshed configuration and removal of owner access. Rendered previews were checked for narrow dark-theme pool details and wide turf details. The previously reported drag-reorder failures are resolved by the ordering verification below.

## Ordering reliability

The business list uses a native reorderable sliver in the page’s single scroll view, so dragging can reach businesses outside the initial viewport. Stable business IDs identify rows. The installed Flutter `onReorderItem` callback already accounts for the removed item when moving down; the Cubit uses its destination directly.

A synchronous save lock prevents repeated taps, cancellation or another move from discarding an in-flight draft before workspace busy-state events arrive. Permission checks and revision checks remain authoritative. Failed or uncertain saves reload the latest server snapshot and show the existing error/reconciliation message rather than assuming the save succeeded. The server uses an organization lock and one transaction; competing saves with the same revision cannot interleave two different orders.

Saved-order verification covers both 390- and 320-pixel drag flows, enlarged text, dragging through eight businesses, repeated moves, Cancel, duplicate Save, persistence after reopening, actual PUT payload/revision, retained-catalog invalidation, live booking/finance selector order without resetting entered data, Home/team session updates, and owner/staff catalog consistency across fresh backend service instances. Other devices receive the latest order on workspace/catalog refresh.

No database migration or backend deployment is needed for these client fixes. The existing `004_business_order.sql` schema remains in use. No live organization order, booking or payment was changed during verification.

Final ordering verification on 16 October 2026: all **240 Flutter tests** passed, including both original mobile drag cases, long-list auto-scroll, duplicate-save protection, retained booking/finance selections, customer history and business details. Targeted Flutter analysis reported no issues. All **23 backend workspace/Edge checks** passed, including concurrent saves and owner/staff catalog consistency. The original drag cases now wait for settled scroll geometry and verify that the starting row is hit-testable before pressing.
