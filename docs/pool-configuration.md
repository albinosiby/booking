# Swimming pool configuration

## Scope and flow

An owner configures multiple pools under one Swimming Pool business. Home → Configure and Profile → Business settings open the same overview.

1. **Add pool** opens that pool's details: name, capacity and minimum/maximum depth.
2. **Continue to timing & pricing** keeps the same pool selected. Set hours, admission options, durations and per-person prices.
3. **Continue** returns to the pool list. **Continue & add another pool** opens the next pool. Both checkpoint locally in the background; validation failures retain the current selection and values.
4. Configure optional group offers, coaching or swimming plans, then review and activate.

A pool used only for groups/plans can finish its physical and timing setup before products are added. Activation still requires an enabled eligible product. New or incomplete pools use the guided flow. Completed pools open details directly with Continue and an Edit timing & pricing shortcut; Timing & pricing also remains a direct shortcut. Back from pricing returns to that pool's details. Group offers and plans retain their separate editors because they may cover multiple pools. Valid final saves preserve active status. Device drafts restore on reopening; leaving before a local write finishes shows a confirmation; version conflicts retain local edits until explicit reload.

Each pool has a stable resource ID, name, simultaneous capacity, minimum/maximum depth in feet and enabled status. Capacity and depth remain independent when copying timing/pricing to another pool. Disabled pools may retain incomplete draft details.

## Prices and products

Timing & pricing selects one pool. Configure opening weekdays/hours, allowed visit durations, default duration and per-person prices in weekday/time bands. Optional paired dates create seasonal overrides. A dated band takes precedence over a weekly band; bands within the same tier cannot overlap. Admission uses the booking start-time rate and duration. An uncovered start time is unavailable. Duration plus optional preparation/cleanup time must fit operating hours. Opening hours describe when the pool operates; buffers reserve time before/after a visit. Midnight displays and accepts 24:00, while the API stores 00:00.

Group offers define eligible pools, an exact or maximum group size, visit duration, total package price, weekdays/time window and optional dates. Each offer chooses its own size rule. The configured package price is the total, not a per-person rate. Eligible pools must support the advertised group size.

Swimming plans default to **25 attendance days**, with an editable positive count. A day means one distinct calendar day; repeat visits that day consume one entitlement when attendance recording is implemented. Expiry is separate: choose calendar days from activation or a fixed expiry date. Counts and expiry periods are independent. Plans have eligible pools, total price and attendance windows. There is no automatic renewal.

Coaching plans have class count, price, duration, seats, pool eligibility, class windows and separate expiry. The optional coach selector lists active organization owners and staff assigned to this business. Resource-restricted coaches must cover every selected pool. Access and coaching definitions use separate screen models.

These screens configure product definitions. Plan purchases, member entitlements, attendance deduction, class sessions, admissions, payment collection and concurrency-safe bookings are future modules. Pricing helpers validate configuration quotes but do not reserve capacity.

## Architecture and persistence

`lib/modules/pool` owns immutable models, screen projections, `PoolRepository`, `RestPoolRepository`, `PoolSetupCubit`, screens and feature widgets. Screens render projections and call Cubit commands; repositories communicate through the authenticated HTTP service. GetIt registers the repository and factory-created Cubit. The shared session coordinator refreshes the authoritative workspace after writes. Lost responses are reconciled against saved graph/version state rather than blindly repeating committed writes.

The local Nest API persists a `pool_v1` graph in `businesses.configuration` JSONB. Each pool also synchronizes an existing `resources` row for capacity and staff assignment scopes. No new database table is needed for this configuration module. Model/repository contracts isolate Flutter from a future storage migration; a cloud implementation must preserve the server authorization, transaction and validation guarantees.

Owner-only writes lock the business, check its expected version and validate the graph. Resource synchronization and configuration writes are transactional. Foreign resource/coach IDs are rejected; deleting pools used by active staff or pending invitations is blocked. Active edits are checked for activation completeness before mutation, so invalid edits leave the saved active state intact. Resource-restricted staff receive a filtered read projection. See [API](api.md) and [request example](../backend/examples/pool-configuration.json).

Legacy pools retain resource IDs/capacity. Missing depths require owner input. An existing attendance-day plan can be imported, while visit/unlimited definitions remain disabled for deliberate conversion. Legacy plan prices are not reused as admission prices.

## Validation and verification

Activation requires enabled pools, valid capacities/depths and at least one usable admission tariff or enabled product per pool. Product references, hours, capacities, coach access, tariff overlap, monetary precision and fixed expiry are checked server-side. Inputs are bounded to 30 pools, 50 group offers and 50 plans.

Flutter tests cover serialization, independent copy behavior, conflicts, lost writes/activation, legacy conversion and the complete configuration flow at 320px with enlarged text. Backend tests cover atomic persistence, tenant isolation, staff scopes, coach revocation, pricing and expiry validation. Existing CI runs Flutter analysis/tests and backend build/tests; existing database backup and production deployment guidance applies unchanged.

## Full-day availability

Choose **Open 24 hours** to hide opening/closing inputs, or **Set opening & closing times** for a custom range. Operating weekdays remain explicit. Pricing can apply to **All 24 hours** or a selected time range. Midnight boundaries store as 00:00 with an explicit all_day flag; equal custom times remain invalid. Cross-midnight bookings and buffers require every occupied day to be open. Overnight tariffs under full-day operation follow their starting weekday/date, and overlapping rules are rejected. Existing start-time pricing and resource conflict/capacity rules remain in force. See [24-hour behavior and verification](24-hour-availability.md).

## Device drafts and final cloud save

Continue never calls the API. Edits and navigation position are autosaved through the shared local draft repository; only final Save changes or Activate publishes to Supabase. See [recovery, conflicts and retry behavior](local-configuration-drafts.md).
