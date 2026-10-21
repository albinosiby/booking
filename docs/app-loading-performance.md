# App-wide loading audit — 21 October 2026

## Live observation before deployment

The deployed health endpoint returned revision `2026-10-20-slot-blocks`, not the later prepared API revisions. Four read-only health checks from this development machine took 2.441, 2.294, 1.975 and 2.207 seconds to first response/total. These include client/network/gateway/runtime/database time; they are not phone UI benchmarks and do not establish which server component accounts for the delay. No authenticated data, schema or reservations were modified for these checks.

**The source fixes below are not live until the API is deployed and the updated Flutter source/build is running.** No APK is built or installed by this task.

## Findings and changes

1. Every normal API startup eagerly imported PDFKit and ExcelJS through the report renderers. Both now import only inside the requested PDF/Excel branch. A build invariant rejects eager report-engine imports in the generated Edge entry point. Report downloads still use the same libraries, font and formats; ordinary pages no longer initialize those packages.
2. Workspace authorization/data assembly required six database statements for membership, organization, businesses, assignments, locations and resources. It now uses two: current membership verification plus one scoped snapshot query. Tenant/business/resource filtering and the existing staff configuration redaction remain enforced. Tests assert the two-statement budget with real multi-business data.
3. System-account setup executed two INSERT round trips on catalog reads. It is now one conditional INSERT for both system accounts, avoiding existing-row insertion attempts and retaining ON CONFLICT protection against concurrent first setup.
4. Simultaneous requests using the exact same bearer token repeated the Auth and migrated-identity lookup in the same worker. An in-flight-only coalescer shares that verification. It retains no completed identities, permissions or successful tokens: later calls revalidate, other tokens are separate and each service still checks current membership/assignments. Sharing applies only to concurrent requests handled by the same function worker.
5. The app's retained cache notified subscribers after every refresh, even when the JSON was identical. That caused avoidable Home/Accounts/list reloads and buffering indicators. It now notifies on changed content or recovery from a failed refresh, while still updating freshness on identical responses.
6. The retained cache access key serialized full business configuration, prices and branding. Changing presentation data could discard unrelated cached pages. The key now uses backend/user/organization, membership, business identity/status and visible resource IDs. Reordering resources or changing a name/price does not change access scope; permission, assignment, paused status, organization and user changes still invalidate it. Explicit writes still invalidate relevant data.
7. Every transaction discarded setup catalogs and the logo twice. Transaction writes now keep only unaffected country/state references, booking/admission setup catalogs and branding. Balances, finance catalogs, lists, customer searches and transaction details are invalidated as before. Configuration, bank mapping, organization and team writes use full invalidation. Logout/denial/scope changes still purge everything; no financial result is preserved by this optimization.
8. Admission list/detail repository reads bypassed retained snapshots and requested catalog then data sequentially. They now use retained reads and start independent requests together. Loaded content remains present during refresh; changed snapshots update the list/detail through coalesced repository events. Form drafts do not subscribe to those events, so background refresh cannot overwrite entered customer, schedule or payment data. Editable organization forms still request a fresh snapshot rather than silently editing a stale revision.
9. Edge responses now include `Server-Timing: app;dur=..., auth;dur=...` for JSON responses and downloads, so runtime work can be distinguished from total client elapsed time after deployment. Headers contain durations only, not tokens, SQL or customer data.

The existing two-job preloader, retained tab navigation, cached-content loading animations, pool metadata warm-up and final server validation remain in place. Availability, quotes, payments and final booking/admission/block confirmation are not converted into trusted stale-data reads. The database pool limit is unchanged.

## Apply the fixes

No new migration is needed for this audit. Earlier feature migrations must already be applied; do not run a blind db push. Save a copy of the currently deployed function for recovery. Run in order, stopping on failure:

```sh
cd "/Users/albinosiby/Tatos Dev/booking"
npm --prefix backend run build
npm --prefix backend run edge:check
npm --prefix backend run edge:build
npx supabase functions deploy booking-api --project-ref scwwkaywewecspsrskft --use-api --no-verify-jwt
curl -i "https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/health"
```

Expected revision: **`2026-10-21-app-loading`**. Keep current secrets, project and function-side Supabase Auth verification unchanged. Reload/restart the updated Flutter source for app-side changes. An already installed older binary does not pick up Flutter changes from an API deployment; no APK is prepared by this task.

## Verify after deployment

- Confirm the health revision and Server-Timing header. Repeat a few checks without drawing conclusions from one cold request.
- Compare total client elapsed time with `app;dur`. The difference includes network/gateway/startup overhead outside the measured handler; `auth;dur` is the authentication portion inside the handler. Neither header includes database query text or parameters.
- Open Home, Bookings, Calendar, Accounts, Expenses, Team and Admissions, revisit them and resume the app. Previously authorized content should stay visible while refreshing. A first uncached load still needs the server.
- Record a payment, then revisit New booking: its setup and branding should remain cached, but balances and reservations must refresh. Change pool hours, bank routing or staff assignments and verify those setup/permission changes are reflected.
- Check invoice/report downloads on demand, including one monthly PDF and Excel export. They now initialize report engines when used, not at every page request.
- Sign out/switch organization; verify no previous user's content appears. Test a denied staff assignment and an expired/invalid token.

If health remains slow after deployment, capture its total elapsed time and Server-Timing and compare the deployed revision. These code changes reduce known redundant work, but no numerical end-to-end speedup is claimed until the new deployment is measured. First authentication/workspace authorization is still required before private business content can be shown.

## Recovery

Restore the saved previous function source if a deployment fails. No schema rollback is needed. Restore the previous Flutter source/build as a unit if reverting app-side behavior. The access-scope format change naturally discards incompatible older retained snapshots on the first authorized load; it does not alter business data.

Local verification runs use isolated in-memory databases and fake transports, plus the existing widget/integration-style tests. No live migration, deployment, authenticated booking creation, APK build or phone installation is performed.

## Verification completed

- Full backend suite: 187 passing tests against isolated local databases.
- Full Flutter suite: 351 passing tests.
- Final focused cache/transport/admission-refresh checks: 31 passing tests.
- Final authentication/query-budget/Edge routing checks: 25 passing tests.
- PDF/Excel accounting and expense regression checks after lazy imports: 19 passing tests.
- Full Flutter analysis, TypeScript build, Edge type-check/build and whitespace checks passed.

The live measurements above are from the old deployment. New production response times still need to be measured after you deploy this revision. Dependency configuration retains the existing function-local deno.json and pinned npm specifiers; see the [official dependency guide](https://supabase.com/docs/guides/functions/dependencies).
