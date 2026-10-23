# Automatic staff access and navigation

## Behaviour

- Access is checked silently every 30 seconds while the application is in the foreground and signed in. Returning to the foreground also checks access (resume checks are throttled to 30 seconds).
- This uses the existing authenticated workspace-session endpoint. It is polling, not instant push. A change appears after the next successful check and network response; an offline device cannot receive it. The server continues to authorize every protected operation immediately.
- Checks do not replace content with loading screens, fetch logos, or run preloading. Concurrent checks are coalesced. Transient connectivity failures keep the current UI. Revoked membership clears the workspace.
- Access-denied API responses clear retained reads and ask the workspace repository/Cubit to reconcile access before delivering the typed failure. Workspace checks do not recursively trigger recovery. Ordinary permission reductions redirect open detail/edit screens to Home; Home and Profile rebuild in place. Financial and booking Cubits continue to clear their scope-bound state.
- User/logout generations reject late checks. The foreground timer stops doing network work in the background and is disposed with the application.

## Navigation

- Home and Profile are always available to a signed-in member of a workspace.
- Calendar and Bookings require view bookings, manage bookings, or collect payments.
- Accounts and Income require view finance. Collection-only staff collect payments from bookings/admissions, not the full financial dashboard.
- My classes is visible on Home, in Profile, and in the bottom navigation/sidebar only with the explicit coach flag. Space assignment alone does not make a staff member a coach.
- Coach-only attendance staff use My classes; Profile does not also expose the broader Plans & Coaching page. Other admission access permissions expose Plans & Coaching.
- Customers requires booking view/manage or payment collection access. Expenses requires finance view or expense recording.
- Bank settings, organization/business configuration, team management, website management, message-template management and agent service remain owner-only.
- Direct routes use the same access policy as navigation. Filtering maps visual positions to stable router branch indices, so hiding Accounts cannot accidentally open another tab.
- Coach class state is refreshed when workspace/plan assignments change, cleared on coach removal, and old asynchronous class/attendance results cannot overwrite the newer state. Attendance marking still requires the existing attendance permission and server time-window checks.

## Deployment and migration

No database migration, Supabase setting, or API deployment is needed for these changes. Existing coach/session/attendance endpoints are reused. Run the updated Flutter source to test. No APK was built or installed.

## Manual verification

1. Sign in as an owner on one device and as staff on another.
2. Enable Also a coach, assign a coaching plan and its spaces, and grant Mark attendance. Within the next successful foreground check, My classes should appear; open it and verify the assigned students.
3. Grant and remove view finance while staff stays on Accounts. Removing it should send staff Home and remove Accounts/Income. Granting it should reveal them again.
4. Remove a space or coach status while a class/detail is open. Verify old students are cleared and the user is returned Home. Unrelated permissions must not grant attendance marking.
5. Verify collection-only staff see collection actions and Customers but no Accounts tab, Income dashboard or bank settings.
6. Background the app, change permissions, then resume. Check that the UI updates without restarting. Disconnect the network: content should remain visible, but protected writes must never bypass server checks.
7. Test logout during an in-flight refresh; the prior user's workspace must not reappear.
