# Expense page and report

## Owner workflow

Choose a month or year, then use the category chips to narrow the page. Search by reason or reference. The active business, space, account, day and search filters appear as removable chips; **Clear filters** resets them while keeping the selected period.

The summary shows gross expenses, reversals, net spent, net cash spent, net bank/digital spent and the net daily or monthly average. The daily cards show the reason, category, space, payment methods and the amount spent. Select a day to see that day's ledger, add an expense with that date prefilled, or download that day's report. The trend chart is collapsible on mobile.

The main Download action opens an explicit report chooser. Select a month or year, a space or all spaces, a category or all expenses, and PDF or Excel. Choosing a space also scopes the request to its business. The scope preview shows the selected space; hidden page filters do not carry over. The selected-day Download action uses the currently visible filters and that day.

## Accounting and export

Expense amounts and cash/bank methods use the existing finance ledger. Reversals reduce expenses on the date recorded. Net spent equals gross expenses minus reversals; net cash plus net bank/digital equals net spent. Transfers between accounts are excluded. The overview computes day, category, reason/space and payment-method totals from the full filtered period, independent of the paginated ledger list.

PDF and Excel reports show the export date in the organization's timezone. The PDF uses readable landscape A4 tables for expense and payment details, including split payments, reversals, references, recording staff and invoice counts. Reports are derived from the exact exported rows. A period with more than 20,000 entries must be narrowed before export.

The API response adds daily and payment-method fields without a schema migration. Until the updated API is deployed, the app displays a dash for unavailable cash/bank breakdowns rather than inventing zero. No production deployment or phone installation was performed for this change.
