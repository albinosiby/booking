# Flutter screen and field-value test report: auth, organization, team, support and shared components

Date: 2026-10-27. Scope: auth, organization, profile (organization edit), team, businesses, workspace, support, agent_calls, configuration_drafts, `lib/design_system/components`, `lib/utils` (validators, helpers, retained cache), router guard.
No `lib/` or existing `test/` file was edited. No APK, device or migration was touched.

## Summary

| File | Passing | Skipped (BUG) |
|---|---|---|
| `test/field_validators_test.dart` | 27 | 11 |
| `test/field_auth_test.dart` | 57 | 5 |
| `test/field_router_test.dart` | 30 | 4 |
| `test/field_organization_test.dart` | 31 | 9 |
| `test/field_team_test.dart` | 40 | 4 |
| `test/field_support_test.dart` | 16 | 2 |
| `test/field_design_system_test.dart` | 17 | 0 |
| `test/field_services_test.dart` | 13 | 0 |
| Total | 231 | 35 |

Every file was run on its own and is green. Each skipped test was re-run with its skip removed and failed, so all 35 skips are confirmed defects, grouped into 20 bug IDs (BUG-1 to BUG-20). Widget tests use `[BUG-n]` in the test name with `skip: true`, because `testWidgets` only accepts a bool for `skip`; unit tests carry `skip: 'BUG-n: ...'`.

Note: other agents were running `flutter test` in the same repo at the same time. This caused "Cannot copy file ... NativeAssetsManifest.json" tool crashes and slow runs. Re-run a crashed file by itself.

## Issues

| ID | Severity | Screen | Field / input | Expected | Actual | File:line | Suggested fix |
|---|---|---|---|---|---|---|---|
| BUG-1 | Low | Register, org create, staff form | Name | Length counted in characters: 61 emoji is valid, one emoji is below the minimum | `String.length` counts UTF-16 units: 61 emoji are rejected as over 120, one emoji passes the 2-character minimum | `lib/utils/helpers/validation.dart:4-8` | Use `value.trim().characters.length` |
| BUG-2 | Low | Register, staff | Name | Single-character names such as 李 accepted | Rejected by the 2-character minimum | `validation.dart:4` | Minimum 1 character, or only reject empty |
| BUG-3 | Low | Sign in, register, staff invite | Email | `a@b..co`, `a@-b.com`, `a@.b.com` invalid | Accepted by the `x@y.z` regex | `validation.dart:9-12` | Stricter domain regex (labels with no leading or trailing hyphen or dot) |
| BUG-4 | Low | Auth, staff invite | Email | Reject more than 254 characters locally | 300-character email passes and fails later on the server | `validation.dart:9` | Add max-length check |
| BUG-5 | Low | Auth, staff invite | Email (paste) | Zero-width space (U+200B) rejected or stripped | Survives `trim()` and `\s`: passes validation, then fails at the server | `validation.dart:9`, `auth_screen.dart:44` | Strip `[​-‍﻿]` before validating and sending |
| BUG-6 | Medium | Register, update password | Password | Whitespace-only password rejected | 8 spaces accepted | `validation.dart:14` | Reject `value.trim().isEmpty` |
| BUG-7 | Low | Register, update password | Password | Reject over 72 bytes (bcrypt limit) with a clear message | No maximum length; generic server error | `validation.dart:14` | Add max-length rule and message |
| BUG-8 | Low | Resource setup | Price | `10,50` and `1,000` understood or clearly explained | Rejected with a generic message | `validation.dart:17` | Normalise the decimal separator or improve the message |
| BUG-9 | Low | Router | `from` return path | `/sign-in/` and `/Sign-In` blocked like `/sign-in` | Exact-match blocklist lets them through | `lib/utils/helpers/safe_return_path.dart:12-25` | Normalise the path (lowercase, strip trailing slash) before matching |
| BUG-10 | Medium | Sign in | Password | A password that registration accepted can sign in | 8-space password registers but sign-in rejects it with "This field is required", locking the account out | `lib/modules/auth/screens/auth_screen.dart:167-169` | Sign-in should require non-empty only (`value.isNotEmpty`), not `Validation.required`; also fix BUG-6 |
| BUG-11 | Low | Router | `from=/onboarding/businesses` | Blocked as a return path | Blocklist has `/onboarding` but the real route is `/onboarding/businesses` | `safe_return_path.dart:18`, `routes.dart` | Block by prefix |
| BUG-12 | Medium | Update password, verify email | Any auth action | Page stays mounted while `AuthState.busy` | Redirect sends authenticated, busy users to `/loading`, which unmounts the form and discards typed values (a failed password save loses the input) | `lib/config/routes/route_guard.dart:41-43` | Skip the busy to loading redirect when `auth.status == signedIn` and the page is an auth page |
| BUG-13 | Low | Router | `?invite=` (empty) | Treated as no invitation | Signed-in user is sent to `/invite?token=` | `route_guard.dart:26-29` | Treat empty as null |
| BUG-14 | Low | Router | `?invite=<junk>` | Format-checked (64 hex) before navigating | Any string is forwarded to the accept screen | `route_guard.dart:26-29` | Validate with the same regex as `AuthContinuation` |
| BUG-15 | Medium | Organization create | Contact number | Only a real phone number (6 to 15 digits, digits and `+ ( ) - space`) | Any 6 or more characters: `abcdefgh`, `!!!!!!!`, emoji and a 60-digit number all accepted. The edit screen rejects these, so a created organization can have a number the edit screen won't save | `lib/modules/organization/screens/organization_screen.dart:158-160` vs `lib/modules/profile/cubit/organization_edit_cubit.dart:174-180` | Share one phone validator between create and edit |
| BUG-16 | Low | Organization create | Address line 1, city | Same limits as edit (line 1 up to 200) | Create uses `Validation.name` (120), edit allows 200 | `organization_screen.dart` | Share the length rules |
| BUG-17 | Low | Organization create (any `AppPicker`) | State picker | Sheet fits on a 320x568 screen at 3x text | RenderFlex overflow by 251px after typing in a field and opening the State picker | `lib/design_system/components/app_picker.dart:80-84` | Make the header and search scroll, or use `LayoutBuilder` heights |
| BUG-18 | Medium | Team list | Member name | Initials from the first characters; any name renders | A word starting with an emoji or other astral character splits a surrogate pair: "string is not well-formed UTF-16" and the list fails to render. The same pattern is in `admission_cards.dart:91` | `lib/modules/team/widgets/team_desktop_widgets.dart:57-61` | Use `p.characters.first` |
| BUG-19 | Low | Team list | `display_name` null | Placeholder such as "Team member" | `TypeError`, list crashes (`TeamRemovalTarget` already handles null) | `lib/modules/team/screens/team_screen.dart:107-110` | `member['display_name'] as String? ?? 'Team member'` |
| BUG-20 | Medium | Support | Topic dropdown | No overflow at 320 or 390px | `DropdownButtonFormField` overflows by 49px on the right at every phone width tested (390 and 320) | `lib/modules/support/screens/support_screens.dart:67` | Set `isExpanded: true` |

Observations (not filed as bugs):
- `TeamEmailResult.message` tells owners to "check server SMTP settings", which is developer wording.
- The `OrganizationScreen` state picker is only validated through `AppPicker`'s `required`, which works.
- Resource setup numeric fields use `int.tryParse` without trim, so a pasted `" 15"` is rejected, and capacity, validity and visit-limit fields have no upper bound. I read this code but did not write tests for it (no `resource_setup_screen` widget test).

## Screens and fields covered

- Auth sign in: email, password; empty, whitespace, 9 invalid email formats, paste with spaces and newline, unicode and emoji password, 500-character password, visibility toggle, keyboard type and autofill flags, double tap, keyboard Done plus tap, loading disables fields, backend error and generic error, retry. Forgot password: empty, invalid and valid email, failure.
- Auth register: name (empty, 1 char, padded, 121, unicode, Malayalam, emoji), email, password (7 vs 8), double tap, email-confirmation notice, existing-account error, invitation mode, 320x568 at 1x/2x/3x text with keyboard and errors, 200-character unbroken input, mode switch carrying `invite` and an encoded `from`.
- Password update and verification screens: empty, short, mismatch (trailing space), unicode, double tap, backend failure and retry, whitespace-only, small screen.
- Router `routeRedirect` guard: signed out, loading, workspace startup, organization and onboarding holds, verification, password recovery, invitations and continuation expiry, owner-only and permission-gated paths, coach path, manager, hostile `from`, emoji round trip.
- Organization create: name, phone, branch, address 1 and 2, city, pincode (IN and non-IN), country and state pickers, logo picker (success, rejection, cancel), double tap, create failure (known and unknown), catalog failure and retry, small screen and large text.
- Staff access form (team): name, invite email, role picker, business and resource selection, permissions, non-owner, double tap, loading, failure, email-sent and not-sent dialogs, editing existing member (email locked), small screen at 3x.
- Team list: loading, empty, error with retry, generic error, long and emoji names at 320 and 1440 px.
- Support: title, message, topic; empty, whitespace, short, trim, unicode, max length on paste, double tap, failure, history loading, empty and error, thread reply (empty, trim, double tap, failure), small screen.
- Business rename (cubit), agent call request note and service selection (cubit), configuration draft JSON, `RetainedReadCache` (unauthorized, corrupt storage, malformed JSON, scope change, access failure lock, shared in-flight request, expiry).
- Design system: `AppTextField`, `AppButton`, `AppPicker` (search, disabled, required, dialog on wide screens), `AppErrorWidget`, `AppEmptyState`, `confirmAction`, `showMessage`.

Not covered: organization edit screen widget fields (existing tests cover its cubit rules), business setup screens (`resource_setup_screen`, `businesses_screen`), agent call screens, and `shared_preferences` or secure-storage services, which need platform channel mocks.
