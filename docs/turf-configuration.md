# Turf configuration

The implemented workflow is sports → physical grounds → bookable spaces → offerings/formats → timing/pricing → review/activation. The default has two physical sections, three layout choices and six football/cricket offerings. Independent additional grounds are supported. Custom arbitrary subdivisions are future scope.

## Correcting a closing-time mismatch

The selected space shows its effective opening/closing times above its pricing controls. A rule outside those hours displays an inline explanation next to that rule. For a closing-only mismatch, such as Half A closing at 23:00 while its rule ends at 24:00, **Extend this space to 24:00** updates the draft in one action. Continue checkpoints it locally; explicit Save changes or Activate publishes through the existing repository.

The command extends the space and, when necessary, the shared closing limit together. Spaces that inherited the previous shared hours receive equivalent overrides so their availability is preserved. Linked Cricket continues to follow its matching Football space. Opening times and weekdays are retained; mismatched weekdays, earlier opening requirements and unsupported full-day intervals require explicit editing. Overnight comparisons are anchored to opening time. Midnight displays as 24:00 and persists as 00:00. Invalid configurations are still blocked by client and server validation.

## Models, state and repositories

`lib/modules/turf/models/turf_configuration.dart` defines immutable sport, ground, section, layout, offering, rate, price-band and operating-hours models. Each step has a typed view projection in `turf_step_models.dart`; `TurfSetupState` owns the draft, expected server version, current step, unsaved-change flag and operation state. `TurfSetupCubit` orchestrates all six screens as one configuration transaction workflow. Fields and dialogs own their presentation controllers only.

`TurfRepository` is backend-independent; `RestTurfRepository` writes through the local Nest API. Both repository and Cubit factories are registered in the composition root. Screens invoke Cubit commands and do not issue database requests. The Cubit observes `WorkspaceSession` for authorized snapshot refreshes, preserves edits on conflicts, and reconciles committed saves after lost responses without retrying mutations.

## Persistence and ownership

The authoritative, schema-versioned `turf_v1` graph is stored in the existing PostgreSQL `businesses.configuration` JSONB column. Each bookable layout has a matching `resources` row with a stable UUID; those IDs remain compatible with staff assignment scopes. No destructive schema migration or replacement of existing local data is required. Graph sizes are bounded: 10 grounds, 30 layouts, 60 offerings and 10 duration rates per offering and 40 weekday/time bands per offering. A complete graph is loaded by indexed business/organization ownership rather than globally scanned.

`backend/src/turf/` owns the authenticated controller, transaction service and strict Zod schemas. Saves take an owner-scoped business lock and compare the expected version. They validate section references and exact split/single footprints, synchronize layout resources atomically, preserve IDs on ordinary edits, prevent cross-business resource IDs and reject deletion of staff-assigned or live-invitation spaces. Valid saves preserve ready status; incomplete active edits are rejected before mutation. Activation requires selected sports, an enabled offering per space, valid prices for enabled durations and enough operating time for duration plus buffers. Hour overrides must fit within shared days/hours, including overnight intervals.

Restricted staff receive only their assigned layout/offer data and referenced sections. A staff snapshot is not an editable owner graph.

## Physical occupancy and future bookings

Half A occupies A, Half B occupies B, and Full Ground occupies A+B. Layout overlap depends on common sections within the same ground, never on the sport label. Independent grounds do not conflict. `turfLayoutsOverlap` provides the tested topology relation for the future booking service, but configuration is not a booking reservation system.

The booking module must resolve the selected offering into its physical section IDs and apply before/after buffers to its interval. Reserve every occupied section atomically under organization/business ownership; availability checks alone must not decide concurrent writes. Add database interval constraints or equivalent locked inventory when bookings are implemented. Define occupancy keys with business and ground identity so IDs cannot connect unrelated tenants. Staff permissions must be enforced again for booking mutations. Public website availability is also future scope.

## Verification

Backend tests cover drafts/activation, same-half and full-ground relationships, independent grounds, invalid references, timing overrides, stale versions, tenant boundaries, atomic name swaps, staff projection and protected assignments. Flutter tests cover immutable topology, draft restore with stable IDs, completeness, copy-to-half behavior, football-only operation, lost-response reconciliation, conflicts and all six screens at 320px with enlarged text. Web and Android builds are verified separately; iOS compilation still requires the missing native toolchain.

## Individual weekday/time pricing

Timing & pricing presents sport selection, a list of that sport’s spaces, and an individual offering editor. Allowed durations and a default duration are separate from tariff bands. Each `TurfPriceBand` contains an immutable weekday list, minute-accurate start/end times and integer minor-unit prices for every allowed duration. Screens emit Cubit commands; repository persistence remains unchanged.

`pricing_basis` is `start_time`. `turfPriceAtStart` selects the half-open band containing the booking start; crossing another price band does not change the fee. Operating hours, duration and buffers still constrain bookings. Same-day overlapping bands are rejected; uncovered start times are unavailable. These are recurring weekly tariffs, not date-range holiday seasons.

Continue advances immediately and checkpoints the current step locally in the background. In an individual pricing editor it validates that offering, then returns to the space list; other offerings may remain incomplete. Advancing to review requires all enabled offerings to be complete. Saved legacy flat rates load as a stable all-operating-hours band. An empty new `pricing_rules` array never falls back to flat prices. The backend prevents older clients from stripping saved time-band pricing.

All time controls use the shared `showAppTimePicker` and `TimeFormat` presentation boundary. Midnight input/display is `24:00`; the control returns canonical `00:00` to Cubit and repositories. This preserves existing duration, overnight, overlap and price logic without schema changes. Saved canonical midnight is formatted as `24:00` in rule buttons, opening hours and review.

## Reuse Football settings for Cricket

A checkbox becomes available after all enabled Football spaces are priced and each enabled Cricket space has an enabled Football counterpart. `TurfConfiguration.cricketUsesFootball` persists in JSONB as `cricket_uses_football`. `TurfSetupCubit` synchronizes settings by layout on every edit while linked; immutable models retain Cricket names/formats and resource identities, and pricing-band IDs remain independent. Linked Cricket controls are read-only until the checkbox is cleared. Clearing it keeps the copied values. The repository contract is unchanged. Backend validation rejects inconsistent linked graphs and prevents older clients silently omitting an active link.

## Direct editing from Profile

`/businesses/:id/settings` opens `TurfSetupScreen` in editing mode with a typed `TurfSettingsOverviewModel` and six section cards. The existing TurfSetupCubit/repository manage both onboarding and editing. Section selection bypasses onboarding progress gates without bypassing save validation. Explicit Save changes publishes accumulated edits; ready businesses remain active after a valid save and require complete validation. Failed reactivation retains the intended active state and retries activation without repeating a committed configuration write. Draft data remains in Cubit when moving between sections, and exiting dirty settings requires confirmation. `/businesses/:id/setup` retains guided onboarding. Backend schema and API contracts are unchanged.

After activation, the Cubit reads the authoritative WorkspaceSession snapshot to update its expected version. A matching ready configuration reconciles an uncertain activation response. Consecutive section saves therefore use the latest committed version without repeating a saved write.

## Full-day availability

Choose **Open 24 hours** to hide opening/closing inputs, or **Set opening & closing times** for a custom range. Operating weekdays remain explicit. Pricing can apply to **All 24 hours** or a selected time range. Midnight boundaries store as 00:00 with an explicit all_day flag; equal custom times remain invalid. Cross-midnight bookings and buffers require every occupied day to be open. Overnight tariffs under full-day operation follow their starting weekday/date, and overlapping rules are rejected. Existing start-time pricing and resource conflict/capacity rules remain in force. See [24-hour behavior and verification](24-hour-availability.md).

## Device drafts and final cloud save

Continue never calls the API. Edits and navigation position are autosaved through the shared local draft repository; only final Save changes or Activate publishes to Supabase. See [recovery, conflicts and retry behavior](local-configuration-drafts.md).
