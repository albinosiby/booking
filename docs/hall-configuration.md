# Party hall configuration

Each Party Hall business contains separate physical halls. Hourly bookings, named sessions and a full-day package are alternative products on the same hall resource. A hall can offer any combination; other halls have independent settings.

## Screens and flow

Home → Configure and Profile → Business settings → the hall business open a direct section overview:

- **Halls**: name, maximum guests, seated capacity, optional indoor/outdoor and amenities, enabled status and removal. Seated capacity may be zero for standing-only events and cannot exceed maximum capacity.
- **Booking options & pricing**: select a hall, set opening weekdays/hours and optional preparation/cleanup time. Enable hourly bookings, individual sessions or the full-day package. Open each option's editor directly.
- **Review & activation**: check all enabled options and activate. Explicit final saves preserve ready status; incomplete new-business drafts can save partial settings.

Hourly pricing supports allowed/default durations, weekday/time bands and paired seasonal dates. Each duration has its own total price per hall. The booking start determines the price across a tariff boundary. Unpriced start times are unavailable.

Morning and Evening are initial session names, with editable names, weekdays, start/end times and enabled flags. Additional sessions can be added or removed. The full-day package has its own editable name, weekdays and start/end times. Each session/package has independent total prices by weekday and optional date range. Dated prices override regular weekly prices; ambiguous same-tier overlaps are rejected. Days without a matching price are unavailable.

Full day means the configured package interval within the hall's opening hours. Equal start/end times are invalid, not an implicit 24-hour interval. UI midnight is 24:00 and stored midnight is 00:00. Overnight periods follow the opening weekday. Session/package time plus preparation and cleanup must fit within hall opening hours. Different options may overlap as alternatives; they do not create separate simultaneous hall capacity.

Copy booking options and pricing replaces selected target halls' opening hours, durations, buffers, enabled booking options and all prices. It preserves hall IDs, names, enabled hall status, capacities, environment and amenities. Copied option/rule IDs are fresh, so subsequent edits remain independent. Continue returns to the section list and checkpoints locally. Edits remain when moving between sections and restore from the device draft on reopening; leaving before a local write finishes shows a confirmation. Version conflicts retain local edits until Reload saved settings is selected.

## Models, repositories and Cubit

`lib/modules/hall` owns immutable HallConfiguration/HallResource, HallHours/Tariff, HallPackage and HallPackagePrice models; per-screen projections; HallSetupState/HallSetupCubit; HallRepository/RestHallRepository; screens and widgets. The Cubit handles option selection, editing, independent copies, persistence and activation reconciliation. Screens invoke Cubit commands and render typed models. GetIt registers the repository and factory-created Cubit. The authoritative workspace session supplies current versions and reconciles uncertain responses.

## API and database

`PATCH /v1/businesses/:id/hall-configuration` takes `{version, configuration}` and returns `{id, version}`. See [request example](../backend/examples/hall-configuration.json). The graph uses `kind: "hall_v1"`, `schema_version: 1` and `halls`. Each hall contains an hourly flag/tariffs, session array and a full_day package. All options are nested under the same hall ID. Monetary values are bounded integer minor units.

The local Nest API checks owner/tenant authorization, business type and expected version under a business lock. Resource synchronization, graph/version update and auditing are transactional. The graph is persisted in `businesses.configuration` JSONB and hall capacity in existing `resources` rows; no schema migration is needed. Invalid active changes are rejected before mutation. Deleting staff-assigned or pending-invitation halls is blocked, and resource-restricted staff see only their assigned hall graphs. Legacy mutation endpoints reject changes after adoption. Legacy hall IDs/capacity and flat hourly prices are imported without guessing session/full-day prices.

Limits: 50 halls per business, 12 sessions per hall, 40 rules per hourly/package option, 10 hourly durations and 10000 maximum guests. Activation requires at least one enabled hall, at least one enabled booking option per enabled hall and complete prices for all enabled options.

## Scope, tests and operations

Configuration and quote helpers do not create bookings. The next booking module must reserve the shared parent hall resource atomically across every option, including buffers, so a full-day reservation blocks overlapping hourly/session bookings. Guest capacity describes event attendance and does not make a hall simultaneously shareable. Payments, extra services and event attendance remain separate modules.

Tests cover independent option selection/prices, seasonal rules, buffers, capacities, copy isolation, stable identities, lost responses/conflicts, legacy conversion, tenant/staff protection and enlarged-text narrow-width activation/direct editing. Existing CI, local setup, database backup and production deployment instructions apply unchanged. No production deployment or device installation is performed by this feature build.

## Device drafts and final cloud save

Continue never calls the API. Edits and navigation position are autosaved through the shared local draft repository; only final Save changes or Activate publishes to Supabase. See [recovery, conflicts and retry behavior](local-configuration-drafts.md).
