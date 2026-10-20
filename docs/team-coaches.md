# Coaches and pool-space assignments

Open **Profile → Team management → Coaches**. Use the **Add coach** app-bar icon to add a contact with name, phone and pool business. This creates neither a login nor staff access. New contacts have no assigned pool spaces; new coaching plans start Unassigned. Pool configuration displays the current coach without offering an Add coach action or dropdown.

## Assign pool spaces

On a coach card, choose **Assign pool spaces**, select one or more checkboxes, then **Save assignments**. Existing assignments are checked. Clear all to leave the coach unassigned. Several coaches may share a pool space. Assigned pools appear as chips on the coach card.

Pool-space assignment is independent of coaching-plan assignment. Under **Assign coaching plans**, only plans whose eligible pools are all covered by the coach’s assigned spaces are offered. Selecting a plan assigned to another coach replaces that plan assignment. Unchecking removes the current coach from that plan.

If a space removal would invalidate saved coaching-plan assignments, the editor lists the affected plans. Saving asks for confirmation. Cancel keeps the online assignments intact and retains the checkbox edits. Confirm saves the space changes and clears only the affected plan assignments in one version-checked configuration update. Prices, opening hours, capacity, validity and unrelated coaches/plans remain unchanged.

Save the pool configuration and coaching plans first so they appear in Team management. Team saves publish immediately through the repository and refresh the workspace. Cached cards stay visible during reload. Save failures retain checkbox selections. Stale versions are rejected; close the editor, refresh Coaches, then retry. Already-open local pool drafts use the existing version-conflict handling.

## Existing data and authorization

Old contact records without an explicit `pool_ids` property retain the pools implied by their existing coaching-plan assignments. On the next configuration save, the app writes those inferred assignments explicitly. A contact without previous plan assignments starts with no spaces. An explicit empty array always means unassigned, never every pool.

Existing staff-based coach assignments continue to use their staff-resource authorization checks; they are not converted into contact records or automatically made coaches. Contacts never grant authentication or app access. Pool-restricted staff see only relevant contacts and pool IDs within their assigned resources.

Deleting a pool removes its coach-space references along with its existing references in offers/plans, after the pool deletion confirmation. Backend validation rejects duplicate or foreign space IDs and coaching-plan assignments outside a contact's explicit pool coverage.

## Deployment and migration

**No SQL migration is needed.** Space IDs are stored in the existing business JSON configuration under `coaches[].pool_ids`. No live data or schema changes were applied.

The hosted API must be updated to accept and validate the new field:

1. The generated source is `supabase/functions/booking-api/index.ts`. It includes the latest validation and staff projection changes.
2. Open the existing **booking** Supabase project (`scwwkaywewecspsrskft`) → **Edge Functions → booking-api**. Download the current function as a backup.
3. Copy the generated source on the Mac:
   ```bash
   pbcopy < "/Users/albinosiby/Tatos Dev/booking/supabase/functions/booking-api/index.ts"
   ```
4. Replace `index.ts` in the function's Code editor and choose **Deploy updates**.
5. Preserve `BOOKING_DATABASE_URL` and the existing custom Auth verification setting (`verify_jwt=false`). No secret, gateway or database changes are required.
6. Run the latest Flutter source. Add a coach, assign Pool A/Pool B, save and reopen to check persistence. Assign a covered coaching plan, then remove its pool; verify Cancel preserves it and Confirm returns the affected plan to Unassigned. Test a second coach on the same pool if needed.

Update clients before using explicit assignments; older clients do not understand the new field. If rolling back, use compatible API/client code and preserve published business configuration rather than overwriting it with an older snapshot.

No hosted deployment, APK build or phone installation was performed for this change.

## Verification

Flutter analysis passed with no issues. All 29 focused Flutter tests passed, including small-screen space selection, covered-plan filtering, confirmation/cancellation, unassignment, stale versions, existing-data compatibility and access changes. All 38 backend pool/booking tests passed in isolated test storage. TypeScript build, Edge type-check and generated Edge bundle build passed.
