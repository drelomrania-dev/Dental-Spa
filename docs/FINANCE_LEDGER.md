# Finance ledger

The production payment flow is implemented by migrations `014_finance_ledger.sql` and `015_finance_hardening.sql`.

## Integrity model

- `finance_accounts` fixes the approved total for one patient/treatment balance.
- `finance_transactions` is append-only. Payments add value; refunds/corrections subtract value and reference the original transaction.
- `finance_receipts` stores an immutable issue-time snapshot and number.
- `finance_collection_sessions` records open, submitted and administrator-validated cash sessions.
- Browser clients cannot read or mutate these tables directly. Authenticated RPCs validate the clinic, role, amount, outstanding balance, idempotency key and session ownership.
- The server resolves the treatment total from an approved negotiated-price request or the clinic treatment catalogue. Only an administrator may provide a fallback total when neither exists.

## Application commands

- `finance_snapshot()` returns only the operations/sessions allowed for the current staff member.
- `finance_account_balance(patient, treatment)` returns an authoritative balance for collection.
- `record_finance_payment(...)` rejects duplicate idempotency keys and overpayments.
- `correct_finance_payment(...)` adds a linked refund entry; it never edits the original payment.
- `open_finance_session`, `submit_finance_session` and `validate_finance_session` enforce the cash-session lifecycle.

Run `supabase/tests/finance_ledger.sql` against a development database with an active administrator profile. The suite creates fixtures inside a transaction and always rolls them back.

## Known product boundary

The on-screen receipt can be printed from the browser and downloaded as a clinic-branded A4 PDF after collection or from payment history. Payment and correction PDFs use the immutable ledger snapshot and are gated by `payments.receipt`.

The PDF is explicitly labelled as a payment receipt rather than a fiscal invoice. Final Moroccan fiscal/legal wording, numbering and retention still require clinic/legal validation.
