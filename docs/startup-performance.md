# Startup and shared API performance — 19 October 2026

## Findings and changes

The user confirmed the previous API deployment was already installed and the delay affects startup and other pages, not only time slots. Public read-only checks from the development machine measured health responses of approximately 2.13 s and 1.88 s and a static catalog response of 0.94 s. These samples include network, Edge execution and (for health) a database query; they do not isolate database time or measure the phone's network.

Two sources of unnecessary work were found in shared paths:

1. Every authenticated request updated a migrated identity row, even when its subject was already linked. Linked and new identities now use a single read. Only an unbound migration claim triggers the existing conditional binding write. Every request still verifies the user with Supabase Auth. There is no token/user permission cache, relaxed verification or new identity-claim policy.
2. Workspace loading previously queried resources separately for every business. It now batches resources for the authorized business IDs and organization, then applies the existing per-space staff filters and configuration projections. Independent organization/business/assignment/location reads run together. The owner test with six businesses uses six total workspace queries and one resource query, instead of eleven total workspace queries with six resource queries.

Resource response fields, model/repository/Cubit contracts, permissions and existing data are preserved.

## Deploy this new update yourself

This is a newer bundle than the previously deployed slot optimization. No SQL migration is needed. No live schema/data changes or deployment were performed. No APK was built or installed.

1. Save/download the currently deployed booking-api code as a rollback copy.
2. Copy the latest generated bundle:

   ```sh
   pbcopy < "/Users/albinosiby/Tatos Dev/booking/supabase/functions/booking-api/index.ts"
   ```

3. In the booking Supabase project (`scwwkaywewecspsrskft`), open Edge Functions → booking-api → Code. Replace index.ts and select Deploy updates.
4. Keep existing secrets, `BOOKING_DATABASE_URL` and the existing function-managed authentication setting (`verify_jwt=false`) unchanged.
5. Open the public verification URL:

   https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/health

   Confirm it returns `revision: "2026-10-19-workspace-performance"` alongside status ok. This identifies the new deployed code without exposing account data.
6. Reopen the existing app, time startup, then test Home, Bookings, Accounts and New booking. This backend update works with the existing app; rebuilding an APK is not required for these server changes.

If there are errors, restore the saved previous function source and redeploy. No database rollback is needed. No SQL validation query is required because there is no schema/data migration.

## Verification and limits

102 backend tests passed across authentication, workspace, Edge routing, bookings, turf, courts, pools and halls. Checks cover original identity binding, email changes, forbidden migration claims, staff scoping and shared booking inventory. TypeScript and Edge type-check/build passed.

The Supabase connector denied inspection access and there was no open dashboard browser session. Live private logs and authenticated endpoint timing could not be inspected. No claim is made that cloud startup latency is eliminated; deployment verification and a new on-phone timing sample are needed to assess the remaining delay.
