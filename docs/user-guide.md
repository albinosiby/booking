# Owner and staff guide

On app and web, the sign-in card supports email/password or **Continue with Google** below the form. The email keyboard's Next action moves to Password, and Done submits the form. Use the eye icon to show or hide your password. **Forgot password?** sits beside the password label and requests a reset for the email entered above. The form scrolls when the keyboard is open or text is enlarged. Wide web windows also show an illustrative calendar beside the form.

1. Choose **Continue with Google**, or create an owner account using your personal full name, email and password. Google sign-in does not require filling in the email/password fields. The organization name is collected in the next step. Your sign-in email must be verified before proceeding.
2. Enter the organization name and first property/branch details. For example, the organization can be “Eden’s Area” and the property/branch “Eden’s Area, Kochi”. They may use the same name if there is only one property. Logo and address line 2 are optional. Country and state are separate searchable selectors. Confirm timezone and currency.
3. Select one or more of the six service cards. Review the suggested name for each selected service, then tap Add selected businesses. You can add more businesses later from Home/Profile.
4. Open Home → Configure. For turf, use the six-step shared-ground wizard described below. For swimming pools, use the direct section editor described below. Badminton, Tennis and Basketball use the court settings overview; Party Hall uses its dedicated hall settings overview.
5. Choose days, opening/closing times, price, and booking duration/buffers. A closing time earlier than opening denotes an overnight operating period.
6. For pools, add capacities/depths, tariffs and optional group/coaching/swimming plans. Swimming plans use 25 attendance days or a custom count with a separate expiry. Admission/attendance processing is a later module.
7. Save rules, review, and activate. The setup button disappears for that business. Resource/rule edits require reactivation.
8. Profile → Team & access → Add team member. Enter name, email and responsibility; optionally enable Also a coach. Choose businesses/resources and explicit permissions. Adding saves their access and sends an email explaining the role, assignments and permissions with app/web login links. Check Email sent/Email not sent; use the entry menu to edit pending access, resend email or cancel access. No manual link sharing is needed.
9. Staff sign in with Google using the exact added email, or use a verified email/password account with that email. Their saved access activates and opens the dashboard automatically. Another email receives no team access. Owners can edit or remove access from Team. After first sign-in, coaching plans are assigned inside staff details; save resource access before changing plans. Older link invitations still require acceptance. See [Email-based team access](team-email-access.md) and [Unified staff management](team-coaches.md).
10. Profile contains business setup, logo, address display, theme preference and sign-out. Long-press a business in Profile to rename it.

Bookings, calendars and manual collections are available in the development build. Production setup and release validation are still required before live operations.

## Turf: two halves and a combined full ground

1. Select Football, Cricket or both.
2. Name the physical ground. Keep “Two halves + combined full ground” for your setup. Add another independent ground only if it is physically separate.
3. Review the A/B diagram and name Half A, Half B and Full Ground.
4. Enable sports for each space. Football defaults to 5s on each half and 7s on the full ground; cricket offers both halves and the full ground. Names and format labels are editable.
5. In Timing & pricing, select Football or Cricket, then Half A, Half B or Full Ground. Choose allowed booking durations and the default duration for that space. Add time-based prices with selected weekdays, start/end times and a price for each allowed duration. Weekdays, Weekend and Every day are shortcuts; individual days can also be selected. All time pickers and screen labels use 24-hour time: 09:00 is morning, 12:00 is noon, 18:00 is evening and 24:00 is midnight. Enter hour 24 and minute 00 for midnight; values such as 24:30 are invalid. The API/database retain midnight as 00:00. Minute-accurate times such as 21:12 are supported.
6. Tap Continue to save that space and return to the sport/space list. Repeat for all enabled spaces. “Copy pricing to the other half” copies the matching sport’s durations, prices, buffers and optional hours. Shared opening hours and individual opening hours/buffers can be expanded separately.
7. After configuring all Football spaces, you can check “Use the same timing and pricing for Cricket.” Each enabled Cricket space uses its matching Football space’s durations, default duration, weekday/time prices, hours and preparation/cleanup times. Cricket names and formats stay unchanged. Later Football edits update Cricket while checked. Uncheck to keep those values and edit Cricket independently. Continue saves the checkbox and copied values.
8. Once all offerings are configured, Continue to review, then tap Activate turf.

Continue saves progress without activating the business; there is no Save draft button. Leaving a screen discards edits made since the last Continue. “Reload saved configuration” fetches the latest server draft; confirm before discarding local changes. Changes to an activated setup require activation again. A version conflict keeps local edits so you can review/reload. Existing legacy turf resources import as independent grounds with their resource IDs preserved; shared arrangements must be chosen explicitly. Replacing spaces that staff or pending invitations use is blocked until those assignments are removed.

The booking start time determines its price. For example, a 17:30–18:30 booking uses the 17:30 price even when another rate begins at 18:00. Rule end times are exclusive. Booking start times outside every price rule are unavailable, and rules for the same weekday cannot overlap. Duration and buffers must still fit within opening hours.

Both halves may be used at once when different sections are booked. Full Ground occupies both sections for either sport. Football and cricket on the same half cannot overlap, including buffers. This module stores these occupancy rules; creating bookings and enforcing overlap at reservation time remain part of the next booking module.

## Edit Turf settings directly

Profile → Business settings → your turf opens a settings overview. Choose Sports, Grounds, Spaces, Sports & formats, Timing & pricing, or Review & activation. There are no numbered steps or Continue buttons in this editor. Save changes persists the selected area; timing/pricing detail saves return to the space list. An active turf remains active after valid changes are saved. An incomplete turf can save partial settings and use Review & activation when ready. All Turf settings returns to the overview while retaining unsaved changes; leaving the settings route asks before discarding them. First-time Home → Configure retains the guided setup flow.

## Swimming pool settings

Open Home → Configure or Profile → Business settings → your swimming pool. Add each pool with its simultaneous capacity and minimum/maximum depth in feet. Open Timing & pricing, select a pool, and configure weekdays/hours, durations and prices per person. Date ranges provide seasonal overrides; Copy timing and pricing preserves each target pool’s capacity and depth.

Group offers choose exact or maximum people, eligible pools, duration, total package price and availability. Swimming plans default to 25 attendance days; enter a custom count if needed. Choose a separate expiry period from activation or fixed expiry date. Coaching plans use a class count, duration, seats, optional assigned coach and separate expiry.

Save changes from any section. Review & activation checks completeness before activating. Active businesses stay active after valid saves. No step-by-step sequence is required for later editing. Plans are definitions at this stage; member purchases and attendance recording will be added separately. See [pool configuration](pool-configuration.md).

## Separate court settings

For Badminton, Tennis or Basketball, open Configure or Profile → Business settings. Under Courts, add each physical court separately. Under Timing & pricing, select a court, choose weekdays/hours/durations and set total prices per court. Add weekend or dated seasonal bands as needed. Copy timing and pricing to selected courts preserves their names and details; copied prices can be changed independently afterward. Save changes from any section; review and activate when ready. Staff access can cover all courts or selected courts through Team & access. See [court configuration](court-configuration.md).

## Party hall settings

Open Configure or Profile → Business settings → your Party Hall business. Add each hall with seated/maximum capacity and optional amenities. Under Booking options & pricing, select a hall and choose which options it offers: hourly, individual sessions, full day, or any combination. Configure hourly durations/time tariffs separately from session/package total prices. Morning and Evening names and hours can be edited; additional sessions can be added. Weekday and dated seasonal prices are supported. Copying replaces options/prices on selected halls while preserving their details. Review and activate when all enabled options are priced. Later edits open directly in the same screens. See [hall configuration](hall-configuration.md).

## Bookings, split payments and rescheduling

Tap New booking from Home, Bookings or Calendar. Expand Business & space, Date & time, Customer details and Split payments. Check available slots or enter a precise time, then Review and Confirm. Cash, UPI, card and bank transfer amounts can be combined on one booking; unpaid and partially paid bookings are allowed. Open booking details to record the balance later.

Reschedule selects a new available date/time (or another assigned space in the same business), previews the new price and keeps the reference/customer/payments. Higher prices increase the balance; excess net payments show refund due. Cancellation releases the slot but does not issue a refund. The owner records refunds separately with a reason. If confirmation is uncertain, use Retry to recover the same request before making another booking/payment. See [booking module](booking-module.md).

## Accounts, expenses and reports

Open Accounts in the bottom bar. Filter by business/space and period to see income, expenses, collections by method, growth and cash flow. Cash and bank cards show recorded whole-organization balances, not a live bank feed.

Start in Profile → Account settings. Add each bank with its opening balance and date; the first bank becomes primary. Set cash opening balance once if you already hold cash. In Payment routing, expand a business and optionally a space to choose receiving banks for UPI, card and bank transfers. Space settings override business defaults, which otherwise use the primary bank. Cash payments stay in Cash in hand. Booking payment forms show the account and let you override it before saving.

Use Add entry → Expense or Extra income. Choose shared organization, business or space, enter category/reason/date, and select the accounts used. Split the amount when multiple methods/accounts are involved. Record payments against existing bookings through the booking itself, avoiding duplicate extra income.

Use Transfer money for cash deposits, withdrawals, bank-to-bank movements or historical unassigned bank receipts. Choose source, destination and amount, and enter the reason. No category selection is needed; transfers are labelled automatically. A transfer changes balances without adding income or expenses. Reversing a mistaken manual entry preserves its original history and requires an owner reason.

Open Reports from the Accounts app bar. Select a month, year or custom dates and download PDF or Excel through the device Save dialog. Reports include summary totals and per-booking received amounts with payment-method breakdowns. Receipt dates determine collections; booking tariffs and amounts received through the cutoff are separate. Transfers and opening balances are not income. Use a shorter period if an export exceeds 20,000 records. See [Accounts module](accounts-module.md).

## Booking notifications

On the configured Android or iOS app, log in and allow notifications when prompted. Owners receive placed, cancelled and rescheduled booking alerts; staff receive them for assigned businesses/spaces when they have booking-management permission. Tap an alert to open the booking. You can use the app with notifications denied; re-enable them in system settings and return to the app to register again. Logging out unlinks this installation and clears its displayed local alerts. Delivery requires the server setup in [Firebase notifications](firebase-notifications.md).
