# Edit organization

Owner flow: **Profile → Organization details → Edit**. The form pre-fills the organization name, phone and each existing location's structured address. Country controls the available states; timezone is read-only. Save is enabled after changes, shows field validation, retains inputs on failure and refreshes the shared workspace after success. Back navigation warns before discarding changes. Conflicting updates offer Reload latest details, with a warning before replacing unsaved edits.

## Architecture

`OrganizationEditDraft` and `OrganizationEditLocation` are backend-neutral immutable models. `OrganizationEditCubit` owns form validation, option loading, request generations, access changes and save/conflict states. `OrganizationEditRepository` is the persistence contract; `RestOrganizationEditRepository` maps HTTP fields and reuses the existing cached country/state catalogs. Widgets only bind models through Cubit. Editing has a separate Cubit from the read-only details page.

`GET /v1/organization/details` returns the owner-authorized organization, currency, locations, fixed timezones and a SHA-256 revision token. `PATCH /v1/organization/details` accepts revision, name, contact_phone and the complete existing locations array. Each location includes id, name, address_line_1, nullable address_line_2, city, nullable state_code, country_code and postal_code. Currency and timezone are not writable in this endpoint.

The server derives the organization from active owner membership. It locks the organization and its locations, compares the revision and applies all edits in one transaction. Foreign/duplicate/missing locations are rejected. Country/state/pincode rules are shared with registration. A repeated identical save succeeds after a lost response; a conflicting save returns HTTP 409. Successful changes create an organization.updated audit event. The API uses the existing Supabase Auth verification and restricted server database role.

## Migration instructions

**No database migration is required. Do not run any migration SQL for this feature.** All updated columns already exist. Only the application API function and Flutter build need updating.

Future changes that need migrations must be prepared as SQL with instructions for the user to apply, following AGENTS.md. No live organization names, phone numbers or addresses were changed while implementing or testing this feature.

## Deployment

From backend, run `npm run edge:check` and `npm run edge:build`. Deploy the generated `supabase/functions/booking-api/index.ts` to the existing booking-api function, preserving its current `verify_jwt=false` gateway setting: the function itself verifies Supabase Auth tokens and enforces owner access. No new credentials, grants, tables or policies are needed.

Build Android with the existing `.local/dart-defines-supabase.json`. Do not install on a phone unless the user requests it.
