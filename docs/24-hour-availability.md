# Explicit 24-hour availability

Turf, Court and Pool support explicit full-day operation or custom opening/closing times. Backend scope was explicitly approved by the owner. The feature retains existing models, repositories and Cubit state management. Existing schedules retain their meaning.

## UI and models

- A shared AppHoursMode selector presents the two choices. Time inputs disappear in full-day mode; operating weekdays remain selectable.
- Price rules can apply to all 24 hours or a specific time range. Rates still depend on booking start time.
- Explicit full-day schedules use all_day=true, canonical opens_at=00:00 and closes_at=00:00, and a 1440-minute span. Turf price bands use corresponding starts_at/ends_at values.
- Without the flag, equal times remain invalid. Existing configurations omit the flag and keep their meaning.
- Models, Cubit state and repository boundaries remain separate. No database migration or business record update has been performed.

## Backend behavior

1. Accepts and validates an optional explicit all_day flag in the approved configuration schemas. Reject non-midnight boundaries when that flag is set.
2. Computes a full-day span only when explicitly selected; retain existing timed/overnight semantics otherwise.
3. Price lookup and authoritative booking inventory accept continuous availability across consecutive selected days, including preparation/cleanup. An end exactly at midnight is exclusive. Crossing into a closed day remains invalid.
4. Preserves operating-day timezone semantics, existing conflict checks, resource ownership and split-ground occupancy. Price remains the start-time rate.
5. Verify full-day rule overlap, dated rules, closed weekdays, midnight crossings, buffers, legacy inputs and full configuration save/activation. Restart only the API if required after validation; leave Auth and saved accounts untouched.

## Verification

All 89 backend tests pass, including 16 new full-day cases. Tests save and activate all three types, create actual midnight bookings in an isolated database, enforce court/turf conflicts and pool capacity, retain start-time pricing, and check closed weekdays, buffers, overnight bands, seasonal boundaries and daylight-saving dates. All 104 Flutter regression tests pass. A subsequent focused run passes all six full-day tests, including preservation of other overnight turf spaces. Flutter analysis and TypeScript compilation are clean.

The local API and Auth emulator were found stopped. Auth was started with the existing saved account import and export-on-exit enabled; the updated API uses the existing local database. API health is OK and phone reverse mappings for 3000/9099 are present. No production database or owner financial records were altered for testing. Native phone inspection is pending because the display is off.
