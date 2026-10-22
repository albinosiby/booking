# Pool plan validity and staff coaches

## Using the screens

Both swimming and coaching plans now offer **Plan validity**:

- Days from activation: 1–3,650 days.
- Months from activation: 1–120 calendar months.
- Years from activation: 1–10 calendar years.
- Fixed expiry date: the selected date remains inclusive.

Zero is invalid. Attendance days/classes remain a separate allowance. The existing configuration models now preserve the chosen unit and period, including in local drafts, review and business details. Existing days and fixed-date configurations retain their values.

Calendar calculations clamp to the last day of the target month: January 31 + one month becomes February 28 (29 in a leap year), and February 29 + one year becomes February 28. They do not approximate a month as 30 days or a year as 365 days. These are plan configuration settings and shared calendar calculations; customer enrollment, activation and attendance management remain separate workflows.

Coaches are staff members managed in **Team & access**. Enable **Also a coach**, assign businesses/resources and explicitly enable attendance if needed. After acceptance, assign plans inside **Edit staff → Coaching plans**. Pool configuration shows the current coach read-only. See [Unified staff management](team-coaches.md) for the current workflow and rollout. Separate coach contacts are no longer supported.


## Database migration

**Plan validity needs no SQL migration.** It is stored in the existing business JSON. Staff-coach conversion and the explicit permission backfill have their own required data migrations; see [Unified staff management](team-coaches.md). Validity retains legacy `after_start` / `expiry_days` and `fixed_date` fields; the added modes use `after_months` / `expiry_months` or `after_years` / `expiry_years`. The backend rejects conflicting periods and invalid values.

## Deploy before testing against the cloud

The API source has changed; the currently hosted API must be updated before it can accept the new configuration fields.

1. From `backend`, run `npm run build`, `npm run edge:check`, and `npm run edge:build` using the project's Node environment.
2. In the existing **booking** Supabase project (`scwwkaywewecspsrskft`), open **Edge Functions → booking-api → Code**.
3. Replace the function source with the generated `supabase/functions/booking-api/index.ts` and select **Deploy updates**. Preserve existing secrets and custom Auth verification (`verify_jwt=false`).
4. Test the updated Flutter source. Choose 3 months or 1 year and save the plan. In Team & access, invite a staff member with Also a coach enabled; after acceptance, assign the plan in their staff details. Reopen the plan and confirm the validity and coach name remain correct.
5. Existing day-based and fixed-date plans should open unchanged. Check that zero is rejected and coaching plans require an eligible staff coach.

No hosted deployment, database migration, APK build or phone installation is performed as part of this source update. Update clients before introducing the new configuration modes. Older clients do not fully understand these modes. For rollback, preserve a copy of the published configuration and use a compatible API/client build; do not translate calendar months into an approximate number of days automatically.

## Verification completed

- Flutter analysis: no issues.
- The original validity implementation passed focused Flutter checks including 320px layouts; the coach editing workflow has since moved to Team management, with dedicated regression tests.
- 37 backend pool/booking tests passed using isolated test storage, including historical contact behavior (since replaced by the staff-coach migrations), staff-coach access checks, restricted staff projections and calendar expiry boundaries.
- TypeScript build, Edge type-check and generated Edge bundle build passed.
