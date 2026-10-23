# API · v1

Authenticated requests carry `Authorization: Bearer <Firebase ID token>`. Production requires verified email. Staff mutations below are owner-only unless marked otherwise. Errors return `{code,message,request_id}` with HTTP 401/403/404/409/422/429/500. Inputs are validated server-side; unknown fields are rejected by the principal schemas. The server selects actor and organization from identity, never from a caller-supplied owner identifier.

| Method | Path | Access / result |
|---|---|---|
| GET | `/v1/catalog` | Public countries and IANA zones |
| GET | `/v1/catalog/states/:country` | Public state/province options |
| GET | `/v1/workspace` | Signed-in user; organization, membership, accessible businesses/resources and locations |
| POST | `/v1/organizations` | New owner; organization and location created atomically |
| POST | `/v1/businesses` | Owner; draft business |
| PATCH | `/v1/businesses/:id` | Owner; rename `{name}` |
| POST | `/v1/businesses/:id/resources` | Owner; `{name,capacity}` |
| DELETE | `/v1/businesses/:id/resources/:resourceId` | Owner; blocked if explicitly assigned |
| PATCH | `/v1/businesses/:id/configuration` | Owner; legacy operating/product rules with current version |
| PATCH | `/v1/businesses/:id/turf-configuration` | Owner; versioned shared-ground configuration |
| PATCH | `/v1/businesses/:id/hall-configuration` | Owner; versioned halls and hourly/session/full-day prices |
| PATCH | `/v1/businesses/:id/court-configuration` | Owner; versioned independent courts and tariffs |
| PATCH | `/v1/businesses/:id/pool-configuration` | Owner; versioned pools, tariffs, offers and plans |
| POST | `/v1/businesses/:id/activate` | Owner; validates saved rules and resources |
| GET | `/v1/team` | Owner; memberships and invitations (no token hashes) |
| POST | `/v1/team` | Owner; save email-based access and send access email |
| POST | `/v1/workspace/session` | Verified identity; activate matching email grant and return workspace |
| PATCH | `/v1/invitations/:id/access` | Owner; edit pending email grant and send updated summary |
| POST | `/v1/invitations/:id/email` | Owner; resend pending access email |
| POST | `/v1/invitations` | Legacy owner endpoint; private share URL |
| POST | `/v1/invitations/accept` | Invited signed-in email; `{token}` |
| DELETE | `/v1/invitations/:id` | Owner; cancel invitation |
| PATCH | `/v1/team/:id` | Owner; staff role/permissions/assignments |
| DELETE | `/v1/team/:id` | Owner; remove access, cannot remove owner |
| POST | `/v1/organization/logo` | Owner; `{content_type,base64}` ≤ 2 MB decoded |
| GET | `/v1/organization/logo` | Active member; private image bytes |

A public `GET /health` checks database readiness without returning organization information.

## Organization request

```json
{
 "name":"Eden’s Area","contact_phone":"9876543210","currency":"INR",
 "location":{"name":"Eden’s Area, Kochi","address_line_1":"Road 1","address_line_2":null,"city":"Kochi","state_code":"KL","country_code":"IN","postal_code":"682001","timezone":"Asia/Kolkata"}
}
```

Creation returns HTTP 201 and `{id}`. `/workspace` is the authoritative read model after mutations. Organization is `null` for an account with no membership. A removed member receives 403.

## Configuration request

```json
{
 "version":2,"opens_at":"06:00","closes_at":"23:00","days":[1,2,3,4,5,6,7],
 "duration_minutes":60,"price_minor":150000,"buffer_minutes":0,
 "plan_name":null,"validity_days":null,"entitlement":null,"visit_limit":null
}
```

Business types are `turf`, `badminton`, `tennis`, `basketball`, `pool`, `hall`. Weekdays are ISO Monday=1 through Sunday=7. This legacy endpoint requires a pool to have nonempty `plan_name`, `validity_days`, `entitlement` (`unlimited`, `visits`, `attendance_days`), and a positive `visit_limit` when limited. Non-pools must leave subscription fields null. Prices are integer minor units in the organization's currency. Configure increments version and returns business to draft. A stale version returns 409.

New pool clients use the dedicated graph endpoint below; the legacy configuration endpoint rejects changes after `pool_v1` adoption.

## Invitation request

```json
{
 "email":"staff@example.com","display_name":"Staff member","role":"staff",
 "permissions":["view_bookings","manage_bookings","collect_payments"],
 "assignments":[{"business_id":"<uuid>","resource_ids":[]}]
}
```

An empty resource array grants access to all resources within that assigned business. A nonempty array restricts access to those IDs. At least one business is required. Role is `staff` or `manager`; neither grants owner administration. Additional permissions: `mark_attendance`, `manage_subscriptions`, `record_expenses`, `view_finance`, plus the `coach` responsibility flag. The legacy `manage_attendance` marker remains accepted for compatibility. This legacy link endpoint returns an `invitation_url`, expires after seven days, and uses `delivery: share_link`. The current Team UI uses `POST /v1/team` for email-based access instead; see [Team email endpoints and session bootstrap](team-email-access.md#architecture-and-api). Keep links private; do not log them.

## Turf configuration

`PATCH /v1/businesses/:id/turf-configuration` requires a verified owner session in production. It accepts `{ "version": <current business version>, "configuration": <turf_v1 graph> }` and returns `{ "id": "<business id>", "version": <next version> }`. See the complete [request example](../backend/examples/turf-configuration.json). Generate fresh UUIDs when creating new grounds, sections, layouts and offerings; retain IDs when editing saved entities.

The graph contains `kind`, `schema_version`, `sports`, `grounds` (physical sections), `layouts` (section footprints), `offerings` (sport, format, enabled, duration/price rates, before/after buffers, optional hours override), and shared `operating` days/hours. Draft rate prices may be null; activation requires all enabled prices. Prices use integer minor units. A split ground requires exactly two half layouts and one full layout occupying both halves. A single ground has one section and one full layout.

Saving is atomic and changes the business to draft. A stale version returns 409; invalid topology returns 422; non-owner access returns 403. Replacing resources assigned to staff or pending invitations returns 409. Layout IDs are also resource IDs, so staff scopes remain stable across renaming and price edits. Legacy resource/configuration endpoints reject mutations after adoption of `turf_v1`.

`GET /v1/workspace` restores the saved configuration. Owners receive the complete graph; resource-restricted staff receive only their assigned layouts, offerings and referenced sections. Staff projections are read models and cannot be submitted as owner configurations. `POST /v1/businesses/:id/activate` validates completeness and resource mapping before activating the turf.

### Turf tariff fields

Each offering includes `default_duration_minutes`, `pricing_basis: "start_time"` and `pricing_rules`. Top-level `rates` identifies allowed durations; with `pricing_rules` present, prices come only from those bands. A band has `{id, days, starts_at, ends_at, rates}`. Days use ISO weekdays. Times use HH:mm, including arbitrary minutes; rule intervals are start-inclusive/end-exclusive. Rates contain `{duration_minutes, price_minor}` for every allowed duration. Draft prices may be null; activation requires nonempty, fully priced bands for enabled offerings.

Bands must fit effective operating hours and may not overlap on shared weekdays. The default duration must be allowed. A booking keeps its start-time band price across a tariff boundary. Its duration and buffers must fit operating hours. No matching band means unavailable. Up to 40 bands per offering are supported.

Legacy graphs without `pricing_rules` remain readable with flat prices. Once time-band pricing is saved, edits that omit it are rejected to protect data from older clients. The Flutter reader migrates legacy flat prices into one stable all-operating-hours band on the next save. An explicitly empty band list has no fallback.

The UI accepts and displays midnight as `24:00`; all requests and stored values normalize it to `00:00`. API HH:mm validation remains 00–23 hours. Values such as `24:30` are invalid; `24:00` is a display alias, not a distinct time or an automatic full-day interval.

`cricket_uses_football` is an optional boolean on the turf graph (legacy absence means independent settings). When true, each enabled Cricket offering must have an enabled Football counterpart on the same layout with identical rates, default duration, buffers, hours override and price bands, excluding band IDs. Names, formats and offering/layout IDs remain sport-specific. Divergent linked payloads are rejected. A client editing an already-linked graph must explicitly include the flag; setting it false retains copied values while allowing independent settings.

## Swimming pool configuration

`PATCH /v1/businesses/:id/pool-configuration` accepts `{ "version": <current business version>, "configuration": <pool_v1 graph> }` and returns `{ "id": "<business id>", "version": <next version> }`. It requires an organization owner, with verified email in production. See the complete [request example](../backend/examples/pool-configuration.json).

The graph contains `kind: "pool_v1"`, `schema_version: 1`, `pools`, `group_offers` and `plans`. Pool IDs are stable resource IDs. Pools contain capacity, minimum/maximum depths in feet, operating windows, durations, buffers and per-person time tariffs. Offer prices are total package prices, and each offer selects `group_mode: "exact"` or `"up_to"`. Prices use integer minor units; times use canonical HH:mm with midnight 00:00.

Swimming plans use attendance-day allowance (25 by default or custom). Coaching plans use class allowance with duration, seats and optional coach membership ID. Both have `expiry_mode: "after_start"` with `expiry_days`, or `"fixed_date"` with `expiry_date`. Allowance and expiry are independent. `renewal` is `"none"`. Availability can have paired dates; dated tariffs override weekly tariffs.

Writes atomically synchronize resource rows and configuration, increment version and save a draft. The Flutter editor reactivates previously active businesses after valid saves; active edits are validated for completeness before writing. Stale versions return 409, invalid definitions 422 and non-owner access 403. Foreign resource IDs or coaches are rejected, and assigned resources cannot be removed. Staff receive only authorized pool/product references in `/workspace`. Activation verifies saved resource mappings and coach access.

## Court configuration

`PATCH /v1/businesses/:id/court-configuration` accepts `{version, configuration}` and returns `{id, version}`. The graph has `kind: "court_v1"`, `schema_version: 1` and `courts`. Each court includes its stable ID, name, enabled status, environment, surface, operating hours, durations/default duration, before/after buffers, `pricing_basis: "start_time"` and tariffs. Prices are integer minor-unit totals per court. Dated bands override weekly bands; same-tier overlaps are rejected. See [complete request](../backend/examples/court-configuration.json) and [feature rules](court-configuration.md).

Owner authorization, expected-version checking, atomic resource synchronization, active completeness validation and restricted staff projections follow the dedicated pool/turf endpoints. Only badminton/tennis/basketball businesses are accepted. Court resource capacity is 1 for exclusive occupancy. Activation validates the saved graph/resource mapping. Legacy mutation endpoints reject changes after court_v1 adoption.

## Party hall configuration

`PATCH /v1/businesses/:id/hall-configuration` accepts `{version, configuration}` and returns `{id, version}`. Owner-only; requires a hall business, tenant ownership and current version. The graph contains `kind: "hall_v1"`, `schema_version: 1` and `halls`. Hall fields include capacities, optional descriptive details, operating hours/buffers, `hourly_enabled`, duration tariffs, `sessions` and `full_day`. Session/package prices contain independent weekdays, optional paired dates and integer minor-unit totals. See [complete example](../backend/examples/hall-configuration.json) and [rules](hall-configuration.md).

Writes synchronize existing resource rows transactionally. Active edits require complete enabled options before mutation; draft saves may contain missing prices. Stale versions return 409, invalid data is rejected and non-owners cannot mutate. Staff projections and protected resource IDs follow the court/pool contracts. Activation checks completeness and saved resource capacity mappings. Legacy resource/configuration mutation endpoints are blocked after hall_v1 adoption.

## Booking operations

All endpoints are under `/v1/bookings` with bearer authentication and organization/resource scope checks. The current connected build uses Supabase Auth.

| Method | Path suffix | Purpose |
|---|---|---|
| GET | `/catalog` | Accessible bookable businesses/options, history filters and action permissions |
| GET | `/customers?q=...` | Phone lookup within accessible customer booking history |
| POST | `/availability` | Priced suggested start times and occupancy for a selection |
| POST | `/quote` | Current authoritative price/availability and quote token |
| POST | `/` | Atomic booking and optional initial split payment creation |
| GET | `/` | Paginated business/resource/date/status/customer/reference filters |
| GET | `/:id` | Booking, balance, immutable payment entries and history |
| POST | `/:id/reschedule` | Atomic replacement of reservation and agreed price |
| POST | `/:id/payments` | Append split collections or owner-recorded refunds |
| POST | `/:id/customer` | Update booking contact snapshot and notes |
| POST | `/:id/status` | Cancel, complete or mark no-show with a reason |
| GET | `/commands/:key` | Recover the actor's committed command result |
| GET | `/dashboard` | Scoped daily counts, values, collections/refunds and upcoming bookings |
| GET | `/collections` | Paginated ledger and full method totals for date/business filters |
| GET | `/outstanding` | Scoped balances/refunds due with full totals and pagination |

Selection: `{business_id, resource_id, option_id, date:"2030-06-04", time:"09:00", duration_minutes:60, people:1}`. Quote/availability take `{selection, exclude_booking_id:null}`; rescheduling supplies the existing booking ID for authorized self-exclusion. Fixed hall packages require their configured start/duration. Quotes return total_minor, starts_at/ends_at, local_start/local_end, timezone, quote_token and remaining_capacity.

Creation takes `{command_key, selection, quote_token, customer:{id:null,name,phone,email:null}, notes, payments:[]}`. Each payment is `{method:"cash"|"upi"|"card"|"bank_transfer", amount_minor:10000, reference:"", received_at:"2026-10-15T06:00:00Z"}`. For a ₹500 booking, cash10000 + UPI20000 + card20000 is fully paid. Payment timestamps cannot be in the future. Responses to successful commands are `{id}`; fetch details for current state.

Reschedule takes `{command_key, version, selection, quote_token, reason}`. Additional collections/refunds take `{command_key, version, kind:"collection"|"refund", payments:[...], reason}`; refunds are owner-only and limited to refund due. Status changes take `{command_key, version, status, reason}`. Customer edits take `{command_key, version, customer, notes}`. Never change a command key/payload while retrying an uncertain write; reusing a key for different data returns 409.

List filters: business_id, resource_id, date, date_until, overlap=true (calendar interval overlap), q, status and cursor. Collections filters: business_id, date or today=true and cursor. Page size is 100; next_cursor is null at the end. Collection totals cover all matching entries. Conflict responses include occupied inventory, changed tariffs/versions and protected configuration/history. See [booking rules and boundaries](booking-module.md).

Calendar date badges: `GET /v1/bookings/date-counts?date=2030-06-01&date_until=2030-06-30` returns `{items:[{date:"2030-06-01",count:3},...]}`, including zeros. The inclusive range is limited to 62 days. Optional `business_id`, `resource_id`, `status` and `q` match the calendar list filters. Counts use booking-local dates, include overnight continuations with exclusive end boundaries, enforce organization/staff visibility, and are independent of booking-page pagination. All statuses are included unless filtered.

## Sarvam voice agent

Owner routes under `/v1/sarvam` manage the connection, tool key and call logs. Public tool routes under `/voice/v1` (`catalog`, `availability`, `bookings`, `my-bookings`, `reschedule`, `cancel`) authenticate with the `X-API-Key` tool key and act as the organization's restricted voice membership. See [Sarvam voice agent](sarvam-voice-agent.md).

## Accounts

Accounts routes are under `/v1/accounts`; see [Accounts API and accounting rules](accounts-module.md#api). They include scoped overview/transactions, bank management, cash opening balance, business/space payment routing, manual split income/expenses, balanced transfers, reversals and protected PDF/XLSX reports. Reports accept date/business/space filters; transaction-only search/type/account filters are rejected for exports. Existing booking payment requests now optionally accept `account_id`; otherwise the configured routing is resolved atomically with the payment posting. Existing booking clients remain compatible.


Booking form response additions: turf catalog options include `sport` (`football`/`cricket`) and `format`. Availability returns `{slots:[{time:"09:00",available:true,status:"available",total_minor:50000,remaining_capacity:null}]}`. `status` can be `past`, `booked` or `available`; past and occupied starts have `available:false`. Only valid priced starts within configured hours are included. Past results are display-only and quote/confirmation still reject past bookings. Clients must recheck via quote and confirmation; a tile does not reserve inventory.

## Public booking website

Owner configuration endpoints and restricted guest site/catalog/availability/quote/confirmation operations are documented in [Public booking website API contracts](public-booking-website.md#api-contracts). Guest operations share the authoritative booking inventory but do not expose customer search, payments, staff, group offers or plans. This feature requires its prepared migration and updated API deployment.


The organisation homepage is `/<slug>`; service booking pages are `/<slug>/book/<business-id>`. Owner-only photo upload/read/removal routes and publication-aware guest image routes are documented in [Homepage and photos API additions](public-booking-website.md#api-additions). Photo uploads require the additional `20261022045215_booking_website_images.sql` migration.


## Unified staff permissions

Staff invitation/member payloads retain the existing `display_name`, `email`, `role`, `permissions` and `assignments` contract. `coach` identifies coaching responsibility; it grants no attendance capability. New explicit permissions are `mark_attendance` and `manage_subscriptions`. The old `manage_attendance` marker is accepted as an attendance grant for compatibility; new clients replace it with `mark_attendance` when saving. New invitations do not automatically receive operational permissions. The permission backfill and release/recovery steps are in [Unified staff management](team-coaches.md).

Admission preview/create/renewal/cancellation/session-management operations require `manage_subscriptions`; ordinary booking operations continue to use `manage_bookings`. Attendance and flexible check-in require `mark_attendance` (or the legacy attendance marker) and current business/resource access. Coaches are additionally restricted to the coaching plans currently assigned to them; owner corrections still require a reason. Coach-only memberships may read My classes; general admission endpoints require an explicit operational permission. Admission detail returns `can_attend`, and My classes returns `students[].markable`, reflecting these current permissions. Permission and current plan scope are rechecked inside write transactions.

Existing owner-only `plan-coaches`, owner coach opt-in and conflict-check endpoints are reused inside staff details. They retain configuration version checks, resource coverage validation and overlap warnings. Coach-plan saves remain distinct from staff-access saves. The removed `/team/coaches` client page redirects to `/team`.
