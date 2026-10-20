# WhatsApp booking messages and templates

## App flow

- After creating a booking, the confirmation section offers **Share on WhatsApp**.
- Booking details has an app-bar **Share booking** icon for existing bookings too.
- The preview refreshes the saved booking and primary template in parallel; it shows the final discounted total, net received and outstanding balance. Times come from the saved venue-local timestamps, use 24-hour formatting and identify next-day endings.
- **Share on WhatsApp** opens the composer; the user selects the recipient, reviews and sends manually. **Copy message** is available if WhatsApp cannot open. No message is automatically sent and opening the composer is not tracked as successful delivery.
- Sharing uses WhatsApp's custom URL scheme with its [documented click-to-chat entry point](https://faq.whatsapp.com/5913398998672934) as fallback. The app uses the locally installed, pinned `url_launcher` 6.3.3 package.

## Profile → Booking message templates

The predefined booking confirmation template is always available. It uses the supplied layout without the PlaySpots promotion. Edit as new template preserves the original; custom templates are also edited as new copies. Each template supports a name, body and optional venue website. Preview uses clearly labelled sample data. Set as primary applies one template across this organization. Deleting the primary custom template returns to the predefined template.

Owners manage templates; staff with booking/payment/finance read access can use them when sharing a booking they are authorized to view. Bookings are re-read through the existing authorization-protected booking detail API. Stored templates contain text/placeholders only, not generated customer messages. Changing accounts or losing access clears previews and ignores late responses. Cached template reads remain scoped to the verified workspace. Confirmation does not wait for template requests. If templates cannot load, the sharing preview explicitly labels the predefined fallback; authorization failures never fall back to exposing a message.

Writing rules and tappable insertion chips explain supported placeholders, `*bold*`, `_italic_`, line breaks, automatic prices/times and avoiding fixed customer names or amounts. Unknown, incomplete or nested placeholders prevent saving. Templates are plain text; there is no expression evaluation or executable template code. Name length is 2–80 characters; message length is 1–6000; up to 50 custom templates are allowed per organization.

Supported fields:
`{customer_name}`, `{booking_reference}`, `{venue_name}`, `{space_name}`, `{booking_date}`, `{start_time}`, `{end_time}`, `{subtotal}`, `{discount}`, `{booking_total}`, `{amount_received}`, `{balance_due}`, `{organization_name}`, `{website}`, `{booking_status}`.

The default sentence uses `{booking_status}` so existing cancelled/completed bookings are not described as confirmed. Non-confirmed previews also show a warning to review wording, because custom templates may contain fixed text. Website is blank unless entered in that template. A valid website starts with http or https.

## Migration — apply yourself

**Nothing has been applied or deployed to the live database. No APK was built or installed.**

The latest combined API also includes the earlier full-bank-number feature. Apply any missing bank-number migration before deploying this combined bundle. Do not rerun already applied migrations.

1. Select Supabase project **booking** (`scwwkaywewecspsrskft`). Confirm a current backup/recovery point is available. Use SQL Editor as the database owner.
2. Preflight:
   ```sql
   select to_regclass('booking_app.organizations') as organizations,
          to_regclass('booking_app.schema_migrations') as migration_registry;
   select rolname from pg_roles where rolname='booking_api';
   select column_name from information_schema.columns
   where table_schema='booking_app' and table_name='money_accounts'
     and column_name='account_number';
   select to_regclass('booking_app.booking_message_templates') as templates;
   select name from booking_app.schema_migrations
   where name in ('20261020054343_bank_account_full_number.sql',
                  '20261020055734_booking_message_templates.sql');
   ```
   Existing organizations/registry and restricted booking_api role must exist. If `account_number` is missing, first run the bank-number SQL and validation described in `docs/bank-account-full-number.md`; postpone API deployment until both migrations are ready. If the templates table already exists, inspect its migration status before applying anything again.
3. Run this complete transaction once:
   `/Users/albinosiby/Tatos Dev/booking/supabase/migrations/20261020055734_booking_message_templates.sql`

   It creates only the private `booking_app.booking_message_templates` table, adds organization/name and single-primary indexes, grants access to the restricted server role and records the migration. It does not change bookings, payments or bank data. Public/anon/authenticated table access is revoked; this table is accessed through the hosted API, not the client Data API. Keep `booking_app` out of exposed Data API schemas.
4. Validate without selecting private template contents:
   ```sql
   select to_regclass('booking_app.booking_message_templates');
   select indexname from pg_indexes
   where schemaname='booking_app' and tablename='booking_message_templates';
   select name from booking_app.schema_migrations
   where name='20261020055734_booking_message_templates.sql';
   select has_table_privilege('booking_api','booking_app.booking_message_templates','SELECT') as api_read,
          has_table_privilege('booking_api','booking_app.booking_message_templates','INSERT') as api_write,
          has_table_privilege('anon','booking_app.booking_message_templates','SELECT') as anon_read,
          has_table_privilege('authenticated','booking_app.booking_message_templates','SELECT') as client_read;
   ```
   Expect a table, three indexes including its primary key, one migration row, true/true/false/false.
5. Deploy the prepared API:
   ```sh
   pbcopy < "/Users/albinosiby/Tatos Dev/booking/supabase/functions/booking-api/index.ts"
   ```
   Paste into **Edge Functions → booking-api → Code → index.ts**, deploy updates, and preserve existing secrets and function-level Auth verification settings.
6. Open:
   `https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/health`
   Expect revision **2026-10-20-message-templates**. This is the combined latest revision, replacing the bank-number-only revision mentioned in the earlier guide.
7. Run the updated Flutter app. No additional secrets, WhatsApp Business account or automated messaging API is needed for this manual sharing flow.

## Check in the app

1. Profile → Booking message templates: preview the predefined template, edit as new, enter a unique name, save and set it as primary. Verify the original remains unchanged after reopening.
2. Try an invalid placeholder such as `{not_a_field}` and an incomplete `{customer_name`; saving must be blocked.
3. Create a booking with a discount and partial split payment. Confirm booking succeeds before any sharing request; open Share and compare total/received/pending with saved details.
4. Record another payment, reopen Share and check the reduced pending balance. Reschedule and check the new date/time. Check a midnight/next-day booking.
5. Copy the message; optionally open WhatsApp and manually choose a recipient. Do not use real customer details for test messages.
6. Verify staff can share only bookings they can view and cannot create/delete/change primary templates. Switch accounts while a preview loads; previous content must disappear.
7. Delete the primary custom template; the predefined one should become primary. Test a disconnected template request: fallback must be visibly labelled, with retry available.

## Recovery

If the migration fails, issue `ROLLBACK;` if the editor session remains in a failed transaction, inspect the error and rerun preflight before retrying. Lock timeout is ten seconds; retry during quieter writes if necessary. Do not apply a partial SQL excerpt.

Leave the additive table and saved templates in place if reverting the client. Do not drop tables or delete template data to resolve a UI issue. A previous API can continue to serve existing bookings, but keep the bank-number owner-only redaction if bank numbers have already been saved; do not redeploy an older `a.*` staff response unchanged. No reverse migration is required for a client rollback.

## Validation performed locally

Backend tests use an isolated in-memory PostgreSQL database, including the companion migration in `backend/migrations/`. They cover input validation, read-only predefined content, idempotent copy creation, owner/staff restrictions, tenant isolation, unique primary selection, deletion fallback and authenticated Edge routing. Flutter tests cover rendering, saved balances, frozen retries, stale access responses, explicit fallback, copy/share gateway invocation and narrow screens with enlarged text. Existing booking and Home collection regressions were also run.

No actual WhatsApp message was sent by the tests. Native composer behavior still needs a manual check on the phone after you run the updated app.

## API contract

All endpoints require a verified bearer session. Organization scope comes from the active database membership, never a supplied organization ID.

- `GET /v1/message-templates`: predefined/custom templates, primary flags and `can_manage`.
- `POST /v1/message-templates`: owner-only `{command_key, name, body, website_url}`; returns `{id}`. Repeating the same key/data returns the same ID; altered data conflicts.
- `PUT /v1/message-templates/primary`: owner-only `{id}` where id is a custom UUID or `default`; selection is serialized by organization and enforced by a unique partial index.
- `DELETE /v1/message-templates/:id`: owner-only custom deletion. A deleted primary implicitly falls back to the predefined template.

Malformed fields return validation errors; unauthorized writes are forbidden; duplicate names/key conflicts return conflict errors. Looking up another organization's template returns unavailable rather than revealing its content. No endpoint sends WhatsApp messages.


## Template UI update

Saved templates now use compact list tiles instead of individual cards. Tap a tile for a sample chat-style preview; the overflow menu holds Edit as new template, Set as primary and Delete. The app-bar plus button creates a template.

The editor has Write/Preview tabs owned by its Cubit/model and a fixed Save action. Text and insertion position survive tab switches. Insert field opens a searchable picker and inserts the selected placeholder at the cursor. Website and writing guidance are expandable. The reusable preview renders basic single-line bold/italic styling while saving, copying and sharing the original unchanged text. Sample data is labelled explicitly. The real booking share preview uses the same visual component.

This UI update needs no additional migration or API deployment. The original template feature still requires the migration/deployment documented above if you have not applied them. No APK was built or installed.
