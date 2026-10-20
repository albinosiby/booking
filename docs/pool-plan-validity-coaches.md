# Pool plan validity and coach contacts

## Using the screens

Both swimming and coaching plans now offer **Plan validity**:

- Days from activation: 1–3,650 days.
- Months from activation: 1–120 calendar months.
- Years from activation: 1–10 calendar years.
- Fixed expiry date: the selected date remains inclusive.

Zero is invalid. Attendance days/classes remain a separate allowance. The existing configuration models now preserve the chosen unit and period, including in local drafts, review and business details. Existing days and fixed-date configurations retain their values.

Calendar calculations clamp to the last day of the target month: January 31 + one month becomes February 28 (29 in a leap year), and February 29 + one year becomes February 28. They do not approximate a month as 30 days or a year as 365 days. These are plan configuration settings and shared calendar calculations; customer enrollment, activation and attendance management remain separate workflows.

Coach creation and assignment have moved to **Team management → Coaches**. Coaching plans start **Unassigned** and show a read-only assignment in pool configuration. See [Team coaches](team-coaches.md) for the current workflow. Contacts do not create Auth users or staff access. Existing coach contacts and saved assignments remain intact.

## Database migration

**No SQL migration is needed. Do not recreate tables or change existing data.** The business configuration is already JSON. Coach contacts are stored in an optional `coaches` array in that pool business configuration. Validity retains legacy `after_start` / `expiry_days` and `fixed_date` fields; the added modes use `after_months` / `expiry_months` or `after_years` / `expiry_years`. The backend rejects conflicting periods and invalid values.

## Deploy before testing against the cloud

The API source has changed; the currently hosted API must be updated before it can accept the new configuration fields.

1. From `backend`, run `npm run build`, `npm run edge:check`, and `npm run edge:build` using the project's Node environment.
2. In the existing **booking** Supabase project (`scwwkaywewecspsrskft`), open **Edge Functions → booking-api → Code**.
3. Replace the function source with the generated `supabase/functions/booking-api/index.ts` and select **Deploy updates**. Preserve existing secrets and custom Auth verification (`verify_jwt=false`).
4. Test the updated Flutter source. Choose 3 months or 1 year and save the plan. In Team management → Coaches, add a coach and assign the plan. Reopen the plan and confirm the unit, period, coach name and phone remain correct. Adding a coach must not add a Team member.
5. Existing day-based and fixed-date plans should open unchanged. Check that zero is rejected and contact phone duplicates cannot be saved.

No hosted deployment, database migration, APK build or phone installation is performed as part of this source update. Update clients before introducing the new configuration modes. Older clients do not fully understand these modes. For rollback, preserve a copy of the published configuration and use a compatible API/client build; do not translate calendar months into an approximate number of days automatically.

## Verification completed

- Flutter analysis: no issues.
- The original validity implementation passed focused Flutter checks including 320px layouts; the coach editing workflow has since moved to Team management, with dedicated regression tests.
- 37 backend pool/booking tests passed using isolated test storage, including coach contacts without staff creation, existing staff-coach access checks, restricted staff projections and calendar expiry boundaries.
- TypeScript build, Edge type-check and generated Edge bundle build passed.
