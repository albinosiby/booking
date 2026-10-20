# Architecture and scope

## Dependency boundaries

Flutter screens render immutable screen models using `BlocBuilder` and invoke named Cubit commands. Widgets never call database APIs or repository methods. Typed draft models carry validated form values; repository implementations handle transport serialization and persistence. TextEditingControllers, form keys and dialogs remain widget-owned presentation objects; business selections, wizard steps, opening hours, days, pool entitlement, logo selection and staff permissions belong to Cubit state.

Every implemented module has `models/`, `repositories/`, `cubit/` and `screens/`. OrganizationRepository, BusinessRepository, TeamRepository, ProfileRepository, DashboardRepository and AuthRepository are focused contracts. Business listing and resource setup share BusinessRepository; staff assignment and invitation acceptance share TeamRepository. Sharing a module contract avoids duplicating persistence rules for each screen. Each data screen has a dedicated immutable model and screen Cubit. Registration/sign-in reuse AuthScreen and AuthCubit; verification observes the same authentication session and AuthState model. The authentication session is intentionally shared so navigation and Firebase session changes stay consistent.

`di/feature_injection.dart` registers module repositories and screen Cubit factories. Screens own and dispose the factory-created Cubits. App providers own AuthCubit, WorkspaceCubit and SettingsCubit. `WorkspaceSession` is the backend-independent snapshot/refresh contract used by feature Cubits. WorkspaceCubit coordinates authoritative refreshes and uncertain saves without retrying mutations; screen Cubits preserve their selection state across those snapshots. Screens pass only explicit commands to Cubits, never closures containing repository operations.

Current persistence path: Screen → feature Cubit → module repository → RestWorkspaceRepository/RestApiService → local Nest API → disk-backed PGlite PostgreSQL. The database lives on the development Mac, not in the phone. Dashboard repositories observe the authorized workspace snapshot rather than issuing duplicate database reads. Startup and the future-module placeholders have screen models/Cubits for loading and permission state; the placeholders do not pretend to have booking or payment persistence.

To migrate, implement the same contracts and replace their registrations in the composition root. Alternatively preserve the REST boundary and replace the API's database adapter. Screens and Cubits should not need changing when the contract and business behavior remain the same. A cloud migration still requires reviewed schema/data migration, tenant authorization/RLS or Firebase rules, authentication/token integration, secure deployment and backups; replacing a repository alone does not provision these. Firebase Auth is independent of business-data persistence and currently uses its local emulator. No Supabase connection or production Firebase business database has been configured.

Shared visuals are exported from `design_system/design_system.dart`; Dio remains behind RestApiService.

The app uses ScreenUtil with a 390 × 844 reference size, bounded scaling, 600/1200 adaptive breakpoints, scrollable forms, and a floating elevated bottom bar at every viewport size. Its rounded Material surface has safe-area margins, a bounded width on larger screens, animated active indicators and visible labels for all five destinations; Scaffold reserves the full navigation height so it does not cover content. ThemeMode is a non-sensitive shared preference. Firebase manages credentials and sessions; passwords never enter application persistence or logging. Offline writes are not supported; booking and collection writes use the authenticated API.

Nest controllers delegate to WorkspaceService and validated inputs. Database encapsulates transactions and parameterized queries. Development uses disk-backed PGlite; production uses a pg connection pool with TLS verification. Schema creation is idempotent for the initial module only; future schema changes must add reviewed, versioned migrations rather than modifying the baseline in-place.

## Data ownership

Organization → locations → businesses → resources. Businesses and resources have composite organization-scoped references. Addresses are individual location columns: `name`, `address_line_1`, `address_line_2`, `city`, `state_code`, `country_code`, `postal_code`, `timezone`.

Each user belongs to one organization in this initial release. The schema isolates independent organizations, but multi-organization switching, SaaS billing and independently owned sub-businesses are future scope. Owners see everything; staff see assigned businesses and, when restricted, selected resources. Manager is a responsibility label; it does not grant owner-only setup/team privileges. Action permissions are stored for subsequent booking/finance modules, which must enforce them again on every server operation.

Resource/rule edits return a business to draft so it must be reviewed and activated again. Configuration saves have optimistic version checks. Pool products snapshot explicit entitlement; plan sale/renewal/attendance and hourly capacity allocation are later modules.

Metadata writes are not automatically retried after network uncertainty. The client reloads the authoritative workspace so a committed organization/resource/configuration does not leave onboarding stuck. Monetary writes in later modules must add persisted idempotency keys.

## Authentication and invitations

Firebase ID tokens are verified server-side, including revocation checks. Production additionally requires email verification. Organization membership is read on every request; removed access cannot continue using a still-valid ID token.

Invitation secrets are random 256-bit tokens, stored only as SHA-256 hashes with a seven-day expiry. The create endpoint returns a private share link once. No email is sent. Acceptance requires the invited email and is transactional and single-use. New invitations for the same email revoke pending older ones. Assignment checks reject cross-business/organization resources. Existing staff assignments and pending invitations prevent deleting their explicitly assigned resource.

## Logos and audit

A small optional logo is stored in a private `logo_assets` row and referenced by a nullable `logo_storage_key` in organizations. Format signatures and a 2 MB cap are checked server-side. Authenticated reads use no-store caching; there are no public asset URLs. Moving this asset to private object storage can be done behind the repository before scale warrants it.

Audit records identify actor, organization, action, entity and timestamp. Exceptions expose safe messages and request IDs, with no request bodies, auth tokens, passwords or image bytes in logs. Rate limiting and security headers are enabled.

## Next approved boundaries

Implement booking inventory/concurrency first, then collections/finance and pool subscription usage. Calendar/Bookings/Payments now use the booking API and its authoritative inventory/ledger. The public website will share that future authoritative inventory.

## Pool feature boundary

The Pool module follows the same screen → immutable screen model / Cubit → repository → authenticated API boundary as Turf. `PoolSetupCubit` owns selected-section/entity, editable graph, coach-loading state and save/activation reconciliation. Its repository contract can be rebound independently of screens. The local API stores versioned `pool_v1` JSONB and stable resource rows transactionally. Resource IDs remain staff-scope keys; coach IDs reference organization memberships. Owner authorization, tenant isolation, expected-version checks and full activation validation remain server responsibilities. Product definitions do not create attendance ledgers, purchases or capacity reservations; those require separate transactional modules.

## Independent courts

Badminton, Tennis and Basketball use `modules/court` with immutable configuration/screen models, a factory-created CourtSetupCubit and CourtRepository/RestCourtRepository. The `court_v1` graph is stored in business JSONB and synchronized transactionally with exclusive resources (capacity 1). IDs remain stable for staff assignments; restricted workspace projections filter the graph. Copying changes timing/pricing only and produces independent tariff IDs. The owner-only API validates versions and completeness; quote helpers do not create reservations. See [court configuration](court-configuration.md).

## Party hall options

The Hall module uses typed screen projections, immutable configuration/package models, HallSetupCubit and HallRepository/RestHallRepository. Owner writes store a hall_v1 JSONB graph and synchronize stable hall resources/capacities transactionally. All pricing options belong to one parent hall; future reservations must lock that common resource. Package prices vary by weekdays/dates while hourly prices additionally depend on start time/duration. See [hall configuration](hall-configuration.md).

## Booking transactions

Booking models, repositories and screen Cubits live in modules/bookings. Nest BookingService authorizes organization/resource scopes, locks the business, prices the selection and reserves shared inventory transactionally. Per-booking versions protect collections and edits; command UUID/hash records make retries safe. Resource-section allocations handle turf, capacities handle pools and exclusive parent resources handle courts/halls. Collections/refunds and history are append-only. Migration002 adds normalized operational tables and a migration ledger preserves existing data. See [booking module](booking-module.md).

## Accounts and ledger

`modules/accounts` provides screen models, repository contracts/REST implementation and Cubits for overview, bank/cash settings, entries, transactions and reports. Accounts replaces the Payments shell screen while retaining its route. The backend ledger posts each booking payment exactly once in the booking transaction; manual transfers create equal opposing account movements. Immutable events, reversals, organization-scoped foreign keys, unique command keys and repeatable-read report snapshots protect financial consistency. Owner balances are separate from staff-scoped reporting. See [Accounts module](accounts-module.md).
