# Access-first startup

Startup still verifies the signed-in user's workspace and permissions with the server before opening Home. The workspace repository now returns immediately after that access check and authorized-cache setup, without downloading the organization logo.

WorkspaceCubit loads optional branding separately through WorkspaceLogoRepository. Its completion updates the current authorized workspace only if the load generation, organization and logo key still match. Failed branding leaves Home usable. Existing logo bytes stay visible while the same organization's unchanged logo is refreshed. Sign-out, permission denial, removed logos and changed logo identities cannot reuse an unrelated image. Optional repository logo-update events also deliver stale-cache background refresh results without reloading the workspace; subscriptions are cancelled on disposal.

Home's existing dashboard and unpaid-balance requests continue running independently and in parallel after access is verified. Retained repository snapshots and existing Home figures stay visible during refresh. A logo-only workspace update no longer triggers duplicate dashboard/balance requests. Changes to actual business data and access still update Home normally.

No authentication or authorization check was skipped. This removes optional image/download latency from the full-screen startup indicator; the first-ever launch still depends on the network response needed to verify access. Actual phone startup timing has not been measured for this change.

## Testing

- Delay the logo indefinitely: Workspace reaches ready and Home can load figures.
- Complete the logo later: branding updates without another dashboard request.
- Revalidate workspace: cached data and the same logo remain visible.
- Fail the logo: workspace remains ready.
- Sign out or reject access while an image is pending: no old logo/workspace reappears.
- Update a cached logo in the background: current branding refreshes safely.

## Run and recovery

No database migration, API deployment or new configuration is required. Run the updated Flutter app to test startup. No APK has been built or installed.

To revert, restore the previous workspace repository/Cubit, HomeCubit and optional branding interfaces together. Existing server data and retained cache format are unchanged.
