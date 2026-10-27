# Fixes applied after the field-value test run

Nothing here is committed. Tests are in `backend/test/field-*.test.ts`.

| Bug | Fix | File |
|---|---|---|
| Customer snapshot mismatch (bookings BUG-3) | Snapshot is copied from the stored customer when `customer.id` is given | `backend/src/bookings/booking.service.ts` |
| NUL and other client-input Postgres errors return 500 (bookings BUG-14, workspace BUG-4/12, finance BUG-4) | SQLSTATE 22021, 22P05, 22P02, 22001, 23514 now return 422 `VALIDATION_ERROR` over HTTP | `backend/src/common/errors.filter.ts`, `backend/edge/handler.ts` |
| Years 0000-1499 and 9999 crash bookings (BUG-7) | `calendarDate` accepts 2000-2100 only | `backend/src/bookings/booking.validation.ts` |
| Public per-phone limit bypassed (BUG-15) | Rate-limit key uses the last 10 digits | `backend/src/website/website.service.ts` |
| Reschedule outside plan dates (finance BUG-9) | `ymd()` helper compares date strings, not Date objects, at 7 sites | `backend/src/admissions/admission.service.ts` |
| Archived category re-activated, `active:false` ignored on create (BUG-5, BUG-6) | `active` is optional; update keeps the stored value, create honours it | `expenses/expenses.validation.ts`, `expenses.service.ts`, `income/income.service.ts` |
| Timezone `+05:30` / `asia/kolkata` accepted (workspace BUG-1) | Requires canonical-cased IANA id or `UTC` | `backend/src/workspace/validation.ts` |
| Admin proof replay (workspace BUG-13) | Nonce is single use per process | `backend/src/admin/panel-auth.ts` |

## Not a bug
Finance BUG-2 (transfer out of "Unassigned bank receipts"): `docs/accounts-module.md` and `docs/user-guide.md` describe this as the way to allocate unassigned receipts. The test still carries a `todo`; delete or invert it.

## Caveats
- The remaining NUL `todo` tests call the service layer directly, so they still fail there. Over HTTP the filter now returns 422.
- The admin-proof nonce store is per process. Edge isolates do not share it.
- The Postgres error mapping is generic, so the message does not say which field was bad.
- Tests whose old expectations changed were updated: `field-common` (years), `field-edge` (22P02 now 422), `field-bookings` (4xx).
