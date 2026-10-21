# Pool options in New booking

Select a swimming pool business and pool space in New booking. The three options are Single visit, Swimming plan and Coaching. They appear only for a new pool booking, not a reschedule or another business type.

Single visit keeps the current start/end grid, pricing, discount and split-payment flow. Swimming plan and Coaching replace only section 3 (Date & time) with shared admission schedule fields, scoped to the selected business/pool and plan kind. Customer, Space, the three option chips and Payments remain in the same New booking layout, including while reviewing an admission. The selected customer and date carry over. Swimming visit duration starts at the pool’s configured minimum and can be extended in 30-minute steps. Coaching keeps the plan’s fixed class duration. Coaching shows the assigned coach read-only. Review displays allowance, expiry and payment information before Confirm admission.

Switching preserves the customer and pool. If schedule, plan or payment entries would be discarded, a confirmation is required. Cancel keeps the current form. The same business and space selectors remain available. Changing pool reloads that pool’s plans; leaving a pool business returns to the single-visit flow. Existing discard confirmation protects entered schedule and payments. Missing plans show an empty state and owners can open Configure plans. Switching is disabled during loading, confirmation or an uncertain saved result; the existing retry flow verifies that same command.

Models own the selected pool option and filtered plan choices. BookingFormCubit coordinates single visits; AdmissionCubit and the existing admission repository own plan previews and creation. Shared AdmissionScheduleFields, AdmissionPaymentFields and AdmissionReviewSummary widgets are reused by New booking and the standalone New admission/renewal page. Plan validity metadata maps through the repository to calculate the displayed expiry from the activation date using calendar month/year clamping, then the server preview confirms it. No separate booking is created when an admission is purchased; fixed admission sessions continue to follow the existing admission backend rules.

No new migration or backend deployment is needed for this UI change. The previously prepared/deployed admissions API and its database migration must already be available. Reload the updated Flutter source to test. No APK was built and no phone installation, deployment or live migration was performed.

Manual checks: select a pool and customer, switch through all three options, verify only matching plans appear, verify configured duration and assigned coach, enter a payment and decline/accept switching, then confirm one admission and check that only one admission purchase was recorded. Repeat with a pool missing one plan kind and with an assigned staff account.

## Flow audit fixes

The admission form now uses the same cached bank account and space-to-bank routing catalog as Single visit. UPI/card/bank payments show the mapped/primary bank and allow another receiving account to be selected. The form shows the split-payment total and remaining balance, offers Pay balance, and rejects invalid amounts and overpayments before review. Authoritative preview totals are checked again in case the plan price changed.

Definitive confirmation rejection clears the old preview and requires a new review. Unknown network results keep the original command and locked draft for retry; a saved admission cannot be submitted again. Option switching also guards loading and an already-open discard prompt. Admission time input uses the shared 24-hour picker.

These are app/repository changes using existing APIs. No new migration or API deployment is required. Local automated checks cover all three flows, unpaid/partial/full split payments, bank routing and account overrides, switching/cancel-discard, stale preview recovery, idempotent retry and light/dark narrow-screen rendering. Backend regression checks run against an isolated in-memory database, not the live project.

The admission footer uses Review admission / Confirm admission / Retry confirmation in place of booking actions. Flexible attendance hides weekday/start-time controls; fixed attendance reveals them. Expiry is read-only and follows the selected plan’s configured validity. No new migration or API deployment is needed for this layout change.

## Loading optimization

Pool plan metadata is warmed after the priority booking reads using the existing two-worker background queue, only for authorized users with an activated pool. This warm-up loads metadata only; it does not fetch previews, reservations, invoices or reports. Adjacent Swimming plan/Coaching switches reuse the already authorized typed catalog for up to 20 seconds, preserving its original fetch timestamp and avoiding a fresh loading frame. Expired/denied catalog state is not reused. Availability, preview and final confirmation remain server-validated. No API deployment, migration or APK build is required.
