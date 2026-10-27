# Backend field-value and module test report: workspace, team, auth, admin, support, notifications, Sarvam, agent calls, Edge

Date: 2026-10-27. Scope: `backend/src/{workspace,admin,common,notifications,support,sarvam,agent-calls}`, `backend/edge`, and the deployed bundles in `supabase/functions`.
No source or existing test file was edited. No migration was applied; all database tests use in-memory PGlite. No network was used.

## Summary

| File (all new, `backend/test/`) | Tests | Pass | Todo (known bug) | Fail |
|---|---:|---:|---:|---:|
| `field-workspace.test.ts` | 55 | 42 | 13 | 0 |
| `field-team.test.ts` | 40 | 39 | 1 | 0 |
| `field-auth-common.test.ts` | 31 | 27 | 4 | 0 |
| `field-admin-support.test.ts` | 37 | 28 | 9 | 0 |
| `field-agent-sarvam.test.ts` | 18 | 16 | 2 | 0 |
| `field-edge.test.ts` | 26 | 24 | 2 | 0 |
| `field-notifications.test.ts` | 20 | 16 | 4 | 0 |
| **Total** | **227** | **192** | **35** | **0** |

Every suite is runnable (`cd backend && npx tsx --test test/field-<area>.test.ts`). A bug is recorded as a test with `{ todo: 'BUG-<n>' }`, so the suite stays green. The bug test still runs and fails for the stated reason. When a bug is fixed the test starts passing, so remove the `todo` option.

Run times: `field-team` and `field-workspace` take 2 to 4 minutes each on this machine. The first call into `country-state-city` costs about 45 seconds and the 2 MB logo upload costs about 10 seconds. The other files finish in under a minute.

Result: 25 distinct issues (BUG-1 to BUG-25). No cross-tenant read or write, privilege escalation, last-owner removal, self-removal, token replay or expired-token acceptance was found. Every such probe was refused (see "Security checks that held"). The top issues are validation or robustness gaps. The two worth acting on first are BUG-1 and BUG-13.

## Issues

Severity is the impact if triggered in production. "Low" means a defense-in-depth or UX gap with no data exposure beyond the caller's own tenant.

| ID | Severity | Module | Field / input | Expected | Actual | Cause (file:line) | Suggested fix |
|---|---|---|---|---|---|---|---|
| BUG-1 | Medium | workspace | `location.timezone` (create org, edit keeps stored value) `"+05:30"`, `"asia/kolkata"` | Only canonical IANA ids from the catalog | Accepted and stored. Postgres reads `'+05:30'` as POSIX UTC-5:30, the opposite sign. The value is snapshotted into `bookings.price_snapshot.timezone` and used in `AT TIME ZONE` queries (`booking.service.ts:850-898`), so day buckets shift by 11 hours. A test shows `+05:30` and `Asia/Kolkata` give different results in Postgres. | `workspace/validation.ts:34`, check at `:58` (`Intl.DateTimeFormat` accepts offsets and any letter case) | Require membership in `Intl.supportedValuesOf("timeZone")` plus `UTC`, as `GET /v1/catalog` already advertises. |
| BUG-2 | Low-Medium | workspace | `orgSchema.contact_phone` e.g. `"abcdefgh"`, `"call me maybe"` | Same phone-number rule as `organizationEditSchema` | Creation only checks length 6-30. The edit schema requires `^\+?[\d ()-]+$` with 6-15 digits, so an organization created with a non-numeric phone can never be saved again from the edit screen (even unchanged). Both tests (schema and edit round-trip) show it. | `workspace/validation.ts:70` vs `workspace/organization-edit.ts:8-19` | Share one phone schema. |
| BUG-3 | Low | workspace, support | Name-like fields made only of invisible characters, e.g. `"​​"` | Rejected as blank | Accepted by organization name, business rename, resource name, invitation `display_name` and support ticket subject. `trim()` does not strip U+200B/U+200D/U+2060. | `workspace/validation.ts:3`, `:116`; `workspace.service.ts:474` (rename); `support.service.ts:17` | Strip `\p{Cf}` and zero-width characters before the length check. |
| BUG-4 | Low-Medium | all text inputs | `"\u0000"` in organization or business name, support subject or message, admin search `q` | 4xx validation error | Postgres error 22021 (invalid UTF-8 byte 0x00) reaches the filter and returns `500 INTERNAL_ERROR`. Tests for organization create, business rename, support create and admin users search. | No NUL guard in any schema; `common/errors.filter.ts:36` and `edge/handler.ts:889` only map `23505` | Reject `\u0000` in a shared string helper, and map class-22 errors to 400 (see BUG-12). |
| BUG-5 | Low | workspace | `invitation.email` 65+ char local part, `a@<250 chars>.com`, 5000-char address | Reject over RFC 5321 limits (64 / 254) | A 5000-character email is stored in `invitations` and `memberships`. The text column has no limit. | `workspace/validation.ts:115` (`z.email()` has no max) | Add `.max(254)` and a local-part check. |
| BUG-6 | Low | workspace | `location.state_code` for countries with no states (e.g. `AQ`, `"ZZ"`) | `null` or empty only | Any string up to 10 characters is accepted. Postal code is also free text for non-IN countries. | `workspace/validation.ts:44-50` (state check only runs when the country has states) | Require `state_code === null` when `State.getStatesOfCountry` is empty. |
| BUG-7 | Low | workspace, mailer | Invitation `display_name` with CR/LF or control characters; duplicate `permissions` | Single-line name; unique permissions | `"Alice\r\nBcc: x"` is accepted. The plain-text access email puts name and business names on their own lines, so an owner can inject lines such as a phishing sentence (HTML side is escaped; subject strips CR/LF). `["view_bookings","view_bookings"]` is stored twice. | `workspace/validation.ts:116,118`; `workspace/team-access-mailer.ts:82-100` | Strip control characters in `name`; `[...new Set(permissions)]` in the transform. |
| BUG-8 | Low (info) | workspace | Business name differing only by case | Treated as a duplicate | `"Turf"` and `"turf"` coexist. The unique index is case-sensitive. Resources behave the same. Likely confusing in pickers and reports. | `migrations/001_workspace.sql` `UNIQUE(organization_id,name)` | Unique index on `lower(name)` (migration for the user to apply). |
| BUG-9 | Low | workspace | `GET /v1/workspace` as staff | No creator account id | `organization` is `to_jsonb(o)`, so staff receive `created_by` (the owner's auth uid) and the order revision. | `workspace/workspace.service.ts:111` | Select an explicit column list for non-owners. |
| BUG-10 | Low | supabase-auth | Auth server returns `200` with non-JSON, empty or `null` body | `503` retryable | `response.json()` throws a `SyntaxError`/`TypeError`, so the user sees `500` and an `INTERNAL_ERROR` log. | `common/supabase-auth.ts:47` | Wrap the parse and shape check; throw `ServiceUnavailableException`. |
| BUG-11 | Low-Medium | supabase-auth | `user_metadata.full_name` (client-editable) `""`, 5000 chars, newline, NUL, `"​"` | Fallback to email local part, length <= 120, no control characters | Passed through as the actor name, then stored as the owner `display_name` by `createOrganization`. An empty name is stored empty. A NUL name makes organization creation fail with 500. Names of any length reach emails and tickets. | `common/supabase-auth.ts:94-97`; `workspace.service.ts:356` | Sanitize and bound the name in `supabaseActor`. |
| BUG-12 | Low-Medium | errors filter, Edge | Postgres client-input errors `22P02` (bad uuid), `22021`, `22001`, `23514` | 4xx | Everything except `23505` becomes `500 INTERNAL_ERROR`. Express and Edge share the gap. The owner-role migration check (`invitations_role_check`) would also surface as 500 if it is not applied, see Notes. | `common/errors.filter.ts:36`; `edge/handler.ts:889` | Map 22xxx to 400 and 23503/23514 to 409/422 with generic messages. |
| BUG-13 | Medium | admin panel auth | Replay of a captured `x-bookingos-admin` proof within 60 s | Single use | The nonce is never recorded, so the same method/path/body can be replayed for 60 s (admin state changes such as `PUT /users/:id/active`, or `tool-key` rotation, are replayable if a header is leaked from a log or proxy). | `admin/panel-auth.ts:27-40` | Keep a short-lived nonce set per instance (best effort on Edge) or bind proofs to a server-issued challenge. |
| BUG-14 | Low | admin | `PUT /v1/admin/users/:id/active` on the `sarvam:` voice-agent membership | Refused (managed only through the verified connection flow) | Any admin, including `support` role, can switch the managed voice membership on without verification. Activation of access still needs the integration flags, so impact is limited to inconsistent state. | `admin/admin.service.ts:238-265` (no `user_id NOT LIKE 'sarvam:%'` filter, no super-admin requirement) | Exclude `sarvam:%` and require super-admin for reactivation. |
| BUG-15 | Low (info) | admin | `?status=bogus` on tickets and agent requests | 400 | Silently ignored, returns all rows. | `admin/admin.service.ts:269`, `:338` | Reject unknown values. |
| BUG-16 | Low-Medium | admin | `PUT /agent-requests/:id/connection` with an unknown organization id | 404 | `ensureManaged` inserts a membership with a foreign key to a missing organization: pg `23503`, `500`. | `admin/admin.service.ts:492` (calls `sarvam.service.ts` `ensure`, which never checks the organization exists) | Look up the organization first, return `NotFoundException`. |
| BUG-17 | Low | notifications | Push `token` of 30 spaces | Rejected | `min(20)` counts whitespace, so a blank token registers and is later sent to FCM. | `notifications/notification.service.ts:15` | `.trim().min(20)` or a `^\S+$` regex. |
| BUG-18 | Low | bookings customers | `?q=900&q=000` (repeated query parameter) | Empty list or 400 | `search.replace is not a function`, `500`. The Express handler passes the raw array through. Edge always gives a string. | `bookings/booking.service.ts:940-948`; `bookings/booking.controller.ts:26` | Coerce or `z.string()`-parse `q`. |
| BUG-19 | Low | admissions customers | `q = "%%%"` or `"___"` | Literal match | The name search builds `%q%` for `ILIKE` without escaping, so `%%%` returns every customer visible to the caller. The tenant and staff scope still apply. The same pattern is used at `:1164` for the admissions list. | `admissions/admission.service.ts:233` (`"%" + q + "%"`), `:1164` | Escape `\`, `%`, `_` as `admin.service.ts` `search()` does. |
| BUG-20 | Low | agent calls, sarvam | `interaction_id` `"."` or `"a/."` | Rejected | The regex allows dot segments (only `..` is refused). `new URL(".../transcripts/.")` normalises to the list endpoint `/transcripts/`, so the stored id fetches a different provider route. Only the provider-key holder can create such ids. | `sarvam/sarvam.service.ts:33-37`; `agent-calls/agent-calls.service.ts:330-334` | Require at least one alphanumeric character per segment, or `encodeURIComponent` each segment. |
| BUG-21 | Low | agent calls | `call-events` `duration_seconds` of `null`, `""`, `[]`, `true`, `" "` | Validation error | `z.coerce.number()` turns them into 0 or 1 and stores them. | `agent-calls/agent-calls.service.ts:336` | Use `z.number()` or a preprocessed numeric string. |
| BUG-22 | Low-Medium | Edge | Path with malformed percent-encoding, e.g. `DELETE /v1/team/%E0%A4%A`, `/public/v1/sites/%E0%A4%A` | 400/404 | `decodeURIComponent` throws `URIError`, mapped to `500`. | `edge/handler.ts:711` and `:810` | Catch `URIError` and return `404`. |
| BUG-23 | Low (info, documented by a passing test) | Edge | `POST /v1/notifications/installations/revoke` | Per-client throttle | One global bucket of 120 per minute for the whole worker. Anyone can exhaust it and block logged-out device cleanup. | `edge/handler.ts` ("installation-cleanup" key) | Key the bucket by client IP or installation id. |
| BUG-24 | Low | FCM | `Retry-After: -30` from the provider | Clamp to 0 | `retryAfterSeconds` is -30 (`Number("-30") \|\| ...`). The dispatcher uses `Math.ceil` of it. | `notifications/fcm-sender.ts:185` | `Math.max(0, ...)`. |
| BUG-25 | Low | FCM, mailer | Event kind or permission named `__proto__`, `constructor`, `toString` | Treated as unknown | Plain-object lookups return inherited members: kind passes the `INVALID_EVENT` guard; permission label becomes a function and `teamAccessMessage` throws `TypeError`. Not reachable today because database and zod enums bound the values. | `notifications/fcm-sender.ts:111`; `workspace/team-access-mailer.ts:76` | Use `Map` or `Object.hasOwn`. |

## Security checks that held

These probes all passed as expected:

- **Privilege escalation.** For `staff` and `manager` members, 24 owner-only operations (team list, invite, email add/update/resend, revoke/delete member and invitation, member edit including self-promotion to owner, owner coach, plan coaches, business create/rename/resource/activate/reorder, organization details and edit, logo upload) were all `403`. Removed members and users without membership are refused everywhere.
- **Owner role.** A sole owner cannot remove, delete or demote themselves. Owner rows cannot be edited through the member editor, even by another owner. Two owners removing each other concurrently always leave exactly one active owner. Promoting a member to owner clears permissions and assignments. Voice (`sarvam:`) memberships cannot be removed, edited or deleted through Team.
- **Cross-tenant.** Another organization's owner cannot revoke, edit, delete, resend or cancel your people or invitations. Foreign business and resource ids in assignments, `location_id`, order lists and `resource_ids` are refused. An email active or pending in another organization cannot be added or claimed (also through the upper-case form). Support tickets, call logs, customer directory, logo and device registrations are isolated per tenant.
- **Invitation tokens.** Only `^[a-f0-9]{64}$` is accepted. The stored hash cannot be used as a token. Tokens are single use and a superseded or cancelled token is dead. An expired token is refused. A different email gets 403 and leaves the invite usable. The `team()` listing never exposes hashes or tokens.
- **Duplicate invites.** Email-login duplicates (any case) conflict and leave one pending row, including four concurrent adds. Inviting yourself or an active teammate conflicts. Re-adding a removed member reactivates the same membership row once.
- **Auth.** `supabaseActor` maps provider 4xx to 401 and 429/5xx or network failure to 503. Unverified, anonymous or incomplete identities are refused. Non-`sb_publishable_` keys and non-https URLs are refused before any network call. Metadata cannot choose the actor id. Identity SQL is parameterised. `coalesceActorChecks` isolates copies, does not cache failures, and handles more than 128 distinct tokens.
- **Admin panel proof.** Shape, 60 s freshness window (symmetric, both directions), method, exact path and query, body bytes and key order, secret length of at least 32, and spoofed copies of the actor object are all enforced. Panel proofs never open member routes, and bearer tokens never open admin routes (Express guard and Edge).
- **Edge.** UUID path parameters, 3 MB body limit by header and by stream, JSON content type, CORS allow-list exactness (origin `null`, ports, case, trailing slash), 120-per-minute actor limit, voice tool-key format, invite redirect token format, public website sub-routes and body cap.
- **Deployed bundles.** Every route literal in `edge/handler.ts` (more than 100) and the owner-guard messages are present in `supabase/functions/booking-api/index.ts`. The revision string matches. The push bundle checks the dispatch secret.
- **Errors.** Zod errors are 422 with field paths and never echo values. Unknown errors never leak messages or stack traces. The 23505 conflict never echoes the constraint name.

## Fields covered

Workspace (`field-workspace`):
- **Location:** `name`, `address_line_1`, `address_line_2`, `city`, `state_code`, `country_code`, `postal_code`, `timezone`.
- **Organization create:** `name`, `contact_phone`, `currency`, `location`.
- **Organization edit:** `revision`, `name`, `contact_phone`, `locations[]` (`id` and address fields, unknown keys such as `timezone`, duplicates, 0/1/100/101 entries).
- **Business:** `name`, `type`, `location_id`; rename `name`; order `business_ids`, `revision`.
- **Resource:** `name`, `capacity`.
- **Configuration:** `version`, `opens_at`, `closes_at`, `days`, `duration_minutes`, `price_minor`, `buffer_minutes`, `plan_name`, `validity_days`, `entitlement`, `visit_limit`, and the pool-only rules. Activation preconditions and a corrupted stored configuration.
- **Invitation:** `email`, `display_name`, `role`, `permissions`, `assignments[].business_id` and `resource_ids`.
- **Other fields:** acceptance `token`, logo `content_type` and `base64` (signature vs type, 11/12 byte minimum, 2,097,152/2,097,153 byte boundary, data URI, SVG, garbage), catalog countries, states and timezones, and coach rules (`isCoach`, `coachProblem` scope matrix).

Team (`field-team`): `team`, `invite`, `accept`, `revoke`, `deleteTeamRecord`, `updateMember`, email `add`/`update`/`deliver`/`session`, `ownerCoach`, `planCoaches` against the scenarios in "Security checks that held".

Auth and common (`field-auth-common`): bearer header forms, `AuthGuard` config failure, `supabaseActor` status/body/metadata cases, `coalesceActorChecks`, `ErrorsFilter` status table, panel proof shape/freshness/binding/secret, `AdminGuard` header typing, push dispatch endpoint (method, secret, enable flag, caller-chosen recipients).

Admin, support, notifications, customers (`field-admin-support`):
- **Admin routes:** every admin route as non-admin, inactive admin, support role and unsigned panel actor. UUID path ids, `limit`, `q` (wildcards, escape, whitespace, NUL), `status` filters.
- **Admin bodies:** `setUserActive.active`, ticket `reply.body`, `status`, agent-request `version`, `status`, `admin_note`, `user_message`, connection `api_key`, `sarvam_org_id`, `workspace_id`, `app_id`, `version`, `phone_number`, `deployment_id`, `approved_services`, verify `tools_confirmed`, and admin-Sarvam settings, callback and approve payloads.
- **Support:** `category`, `subject`, `message`, reply `message`, open-ticket cap of 20, tenant isolation, reopen on reply.
- **Devices:** `installation_id`, `installation_secret`, `token`, `platform`, unregister and revoke proofs, token collisions.
- **Customer lookups:** customer directory `q`, `after`, strict keys, staff scope; customer search by phone and by name.

Agent calls and Sarvam (`field-agent-sarvam`): request `services` and `note`, toggle `enabled`, `version`, `resource_ids`, call-history `start`, `end`, `offset` (ISO and offset forms, 31-day boundary), `interaction_id` for transcript, recording and call-events, call-event `caller_phone`, `duration_seconds`, `transcript`, `summary`, `caller_name`, `disposition`, tool key format and every integration state (disabled, unverified, paused, requested, rejected), rotated keys, approved-services gating, `voiceResult`, owner Sarvam `save` payload and tenant rules.

Edge (`field-edge`): path decoding, parameters, auth header, body forms, admin proof binding, CORS, rate limits, revoke endpoint, voice routes, public website, catalog, error shapes, bundle freshness and deno manifests.

Notifications (`field-notifications`): booking push text (name, space, reference, time, timezone, ends before start, 80 code-point cap, surrogate pairs), FCM sender (kind, service-account JSON validation, token carried only in the body, status and `Retry-After` classification, OAuth failures), team-access email (HTML escaping, subject, permissions, role labels, login URL validation), SMTP mailer configuration and failure handling.

## Notes and not covered

- `migrations/20261027110000_invitations_allow_owner_role.sql` is not applied to any live database by this work. Until the user applies it, the owner role in invitations violates `invitations_role_check` and (via BUG-12) surfaces as 500. Tests run against PGlite with all migrations applied.
- Some behaviours are inconsistent but not wrong: Express answers 400 for a bad UUID path parameter and Edge answers 422. Workspace validation uses 422 while support and admin use 400. `Bearer` is matched case-sensitively in both runtimes.
- `supabase/functions/*/index.ts` are generated bundles. They are checked for freshness against source, not executed. The Edge handler is exercised through `createHandler`.
- Not covered: real Postgres or RLS behaviour (PGlite only), live Supabase Auth, SMTP and FCM over the network (injected fakes), Sarvam provisioning flows (`sarvam-setup`, `sarvam-provisioning-remote`) beyond payload validation, and voice booking tools in `voice.service.ts`.
