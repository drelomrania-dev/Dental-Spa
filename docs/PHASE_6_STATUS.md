# Phase 6 — accounts, receipts and cash sessions

Updated: 2026-10-20 (Africa/Casablanca)

## Implemented in the shared checkout

- Migration `034_finance_phase6.sql` adds dated installments to new accounts: one, two, three or an explicit number of monthly installments. Amounts split in cents and sum to the frozen account price. The server derives paid, due, late and rescheduled states from the immutable ledger and append-only reschedule events. Rescheduling a paid installment is denied. Existing Phase 5 accounts retain their quoted price and plan even when a later payment submits another plan or expected total.
- Accounts opened before Phase 6 have no reliable original due dates. They are displayed as unspecified until an authorized finance corrector enters the agreed first date, monthly count when needed, and source reason. This creates a labeled historical schedule without changing the account price, plan or ledger. A second schedule cannot be created.
- The payment RPC validates cents, price, balance, method, account, collector and open session. Cash collection requires an open session, including for administrators. Idempotency keys are transaction locked; replay of the same payment returns the same transaction, while a changed amount, method, account or session is denied. Overpayment is denied under the account lock. A correction is a separate refund transaction linked to its original payment; correction amount is capped by the unreversed original amount. Cash corrections require the current open session and never alter a closed session.
- A refund restores the account's outstanding balance. Previously refunded accounts with an outstanding balance are reopened in account status so the existing finance report includes them; their ledger and original receipts are unchanged.
- Newly issued receipt snapshots freeze the clinic name, address, phone, currency and timezone, plus patient and service names, amount, balance, method, number and issue time. Correction documents inherit the original document identity and cite its number. Transaction and document rows remain append-only. Existing legacy receipts have no historical clinic identity; their PDFs explicitly say the historical identity is unavailable instead of using today's clinic details.
- Administrators can configure receipt and correction prefixes. The database assigns monotonically increasing per-clinic numbers, including a clinic-local year, in the same transaction as each document. The counters do not reset when a prefix changes. The payment screen offers an optional 80 mm print ticket and a PDF; history distinguishes receipt and correction document and shows the linked original number. The text says a payment document is not a fiscal invoice.
- Collection sessions show server-derived net transactions and cash expected including opening cash. Each collector sees their own session; a manager can see all, validate a submitted session or reject it with a reason. Submission stores counted cash, expected cash and discrepancy. The UI surfaces operation errors. The Phase 6 SQL suite exercises two collector identities and an administrator.

## Checks actually run

| Check | Result |
| --- | --- |
| `pnpm build` | Passed after the Phase 6 UI and schema changes |
| `pnpm e2e` in demo mode | 10 passed, 9 local/Auth checks skipped by target guards; includes the new payment, receipt and cash-session demo journey |
| `pglast` | Migration 034 and `finance_phase6.sql` top-level SQL syntax parsed; PL/pgSQL bodies were not executed |
| `node --check` | Passed for both Phase 6 browser specs and the changed finance/PDF services |
| Receipt PDF bytes check | Passed: issued clinic identity and EUR appeared; later clinic name did not |
| `./scripts/local-sql-tests.ps1` | Could not start: Docker engine pipe `//./pipe/docker_engine` unavailable |

## Runtime acceptance pending

After the previously identified Windows/WSL2 restart makes Docker's Linux engine available, run `./scripts/local-start.ps1 -Reset`, `./scripts/local-sql-tests.ps1`, and `./scripts/local-e2e.ps1` with synthetic fixtures. Confirm fresh migration 034, the transactional finance suite, two-collector Auth/RLS visibility, server-calculated balances and cash discrepancies, receipt identity after clinic edits, PDF/80 mm print output, and the authenticated browser flow. No restart or hosted production change was made. Phase 6 is code-complete and demo/static checked, but **not locally runtime accepted**.

## Decisions requiring clinic or legal review

- Moroccan legal wording, tax identifiers, numbering rules, fiscal invoice format and whether a correction document may be labeled an *avoir* remain unvalidated. The current output is an operational payment receipt or correction document, never a fiscal invoice.
- Choose a retention policy for receipts, corrections, finance schedules and session records before real data is used. Historical legacy clinic identity cannot be reconstructed from the old finance snapshot without independent source evidence.
- Reconcile currency on pre-Phase-6 accounts before real use. The older account migration defaulted currency to MAD, so an older non-MAD account may need source-document review; this phase does not rewrite a frozen account based on today's clinic setting.
- The default installment spacing is one calendar month from the first due date. Confirm whether the clinic wants another cadence for “2 fois” and “3 fois,” and whether a monthly plan has a maximum duration below the current 60 installments.
- Rejected cash sessions retain their submitted count and discrepancy and cannot be edited; the collector opens a new session for subsequent work. Confirm the operational escalation and cash handover procedure for a discrepancy.

Phase 1–5 uncommitted work and the separate Phase 3 corrective changes were preserved. No worktree, production Supabase operation or real patient data was used.
