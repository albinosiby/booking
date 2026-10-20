# Court configuration

Badminton, Tennis and Basketball each use the Court module. A business contains independent physical courts; a booking on one court must not occupy another. Shared/multisport footprints are outside this configuration.

## Owner flow

Home → Configure or Profile → Business settings → court business opens the same direct editor:

1. **Add court** starts an individual court flow. Enter its name, indoor/outdoor type and optional surface.
2. **Continue to timing & pricing** keeps that court selected. Configure operating weekdays/hours, durations, default duration, weekday/time prices and optional seasonal dates. Prices are totals per court for the selected duration. Preparation/cleanup is optional.
3. **Continue** returns to the court list. **Continue & add another court** opens the next court’s details. Both checkpoint locally in the background; validation failures retain the current form.
4. **Review & activation** activates the business when all enabled courts are complete.

New or incomplete courts use the guided flow. Completed courts open their details directly, with Continue and an Edit timing & pricing shortcut. Back from pricing returns to that court's details without losing edits. The overview's Timing & pricing shortcut still opens existing courts directly for targeted settings edits. Save changes remains available for direct editing and partial configuration management. Valid final saves preserve active status. Edits survive moving between sections and restore from the device draft when reopening; leaving before a local write finishes shows a confirmation. A conflict keeps local edits until Reload saved settings is chosen.

Copy timing and pricing replaces selected target courts' opening hours, durations, default duration, buffers and tariffs. It retains target court IDs, names, enabled status, indoor/outdoor and surface details. Copied tariffs receive independent IDs and subsequent source edits do not synchronize targets.

A booking uses its start-time rate, even across a tariff boundary. Dated seasonal rules override ordinary weekly rules. Same-tier overlapping rules are rejected; uncovered start times are unavailable. Duration and buffers must fit operating hours. Midnight displays/accepts 24:00 and persists as 00:00. Equal opening/closing times are invalid, not a full-day shortcut. Overnight operating periods are anchored to the opening weekday; future booking callers must pass the operating-day date to quote helpers.

## Architecture and data

`lib/modules/court` owns immutable CourtConfiguration/CourtResource/Hours/Tariff models, per-screen projections, CourtSetupState, CourtSetupCubit, CourtRepository/RestCourtRepository, screens and feature widgets. Screens invoke Cubit commands; repositories handle authenticated API operations. Dependencies register through GetIt. The authoritative workspace session reconciles writes, including lost responses and consecutive save/activation versions.

`PATCH /v1/businesses/:id/court-configuration` accepts `{version, configuration}` with a `court_v1` graph. See [example](../backend/examples/court-configuration.json). The API requires an organization owner and locks/checks the business version before saving. A stale version returns 409. Invalid graph input is rejected, and wrong business types/foreign resource identifiers cannot mutate data. The transaction synchronizes `businesses.configuration` JSONB and `resources` rows; no new tables or migration are required. Capacity is 1 for exclusive court occupancy, not a player-count limit.

Resource IDs remain stable across names/prices/copying. Deleting courts assigned to staff or pending invitations is blocked until those scopes are removed. Resource-restricted staff read only their assigned courts. Legacy court resources and global flat prices import with original resource IDs; adoption blocks legacy resource/configuration mutation endpoints. A saved court graph is restored from `/v1/workspace`.

The configuration supports up to 50 courts/business, 40 rules/court and 10 durations/court. Durations span 30–1440 minutes. Monetary values are bounded integer minor units. Activation requires at least one enabled court and complete usable prices on each enabled court. Invalid active edits are rejected before modifying the saved ready graph.

## Boundaries and operation

Court setup does not create bookings or reserve time. Concurrency-safe court reservations, cancellations, customer details and payments belong to later booking/payment modules. Staff assignments continue through Team & access. Coaching plans were not included in the approved three-section court implementation.

Existing setup, local database, backups, deployment and CI instructions apply unchanged. Production requires the configured Firebase/PostgreSQL/HTTPS environment. Tests cover three business types, pricing boundaries, copy isolation, legacy identity preservation, conflicts/lost responses, protected staff scopes and narrow-width enlarged-text editing.

## Full-day availability

Choose **Open 24 hours** to hide opening/closing inputs, or **Set opening & closing times** for a custom range. Operating weekdays remain explicit. Pricing can apply to **All 24 hours** or a selected time range. Midnight boundaries store as 00:00 with an explicit all_day flag; equal custom times remain invalid. Cross-midnight bookings and buffers require every occupied day to be open. Overnight tariffs under full-day operation follow their starting weekday/date, and overlapping rules are rejected. Existing start-time pricing and resource conflict/capacity rules remain in force. See [24-hour behavior and verification](24-hour-availability.md).

## Device drafts and final cloud save

Continue never calls the API. Edits and navigation position are autosaved through the shared local draft repository; only final Save changes or Activate publishes to Supabase. See [recovery, conflicts and retry behavior](local-configuration-drafts.md).
