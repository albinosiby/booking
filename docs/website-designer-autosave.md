# Website designer autosave

The application dependency factory enables a 700 ms debounce on WebsiteSettingsCubit.
Each valid change to the website address, branding text, social links, business and
space visibility/rules, default policies, and photo selection/removal schedules a
save through the existing WebsiteRepository. Closely spaced changes are batched.
Other consumers may omit autosaveDelay to retain explicit-save behavior.

Autosaves do not set the blocking busy flag: users can continue typing. Only one
save pipeline runs at a time. Server acknowledgements advance the baseline/version
without replacing newer field edits, and pending edits schedule the next write.
Photo operations are serialized with settings writes and use the latest version.
Publication operations wait for an existing autosave and save newer edits first.
There is no automatic publish/unpublish action. On an already published website,
saved settings continue to affect the live site as they did with manual Save.

The editor no longer keys its form subtree by the server version. Autosave replies
therefore do not rebuild input state or remove keyboard focus. Explicit reload,
address save and copy-to-all still refresh fields when appropriate.

The footer shows saving, pending/validation, failed/retry or all-saved status.
Incomplete/invalid fields are retained in the form rather than posted automatically.
The API remains authoritative for slug uniqueness and business/payment validation.
A failed write retains edits and stops automatic retry loops. Save now / Retry save
is still available; uncertain version conflicts require reviewing/reloading the
current server settings before retrying.

Back navigation waits for in-flight work and flushes pending changes. On failed or
invalid saves, users choose Keep editing or Discard changes. This is cloud autosave,
not durable offline drafts: forcibly terminating the process cannot guarantee a
pending/failed edit survives. Timers are cancelled on disposal and workspace access
changes; late responses cannot repopulate a different account's editor.

## Verification

```sh
flutter test test/website_autosave_test.dart
flutter test test/booking_website_test.dart test/field_booking_website_test.dart
```

Coverage includes debounce, typing during a slow response, sequential versions,
validation, explicit retry, photo upload/removal, pending navigation flush, retained
focus, workspace invalidation, publication ordering and existing editor behavior.
The existing field suite has five pre-existing skipped cases unrelated to autosave.

Run/publish the updated Flutter client to use it. No schema migration, API deployment
or APK build is required by this change. No live database changes were performed.
