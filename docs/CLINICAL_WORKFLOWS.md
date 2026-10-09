# Clinical workflows

Migration `016_clinical_workflows.sql` moves visits, treatment plans and negotiated-price decisions to normalized Supabase tables.

## Commands and access

- `clinical_snapshot()` filters visits and plans by clinic and, for practitioner accounts, by the practitioner linked to the Auth identity.
- `record_clinical_visit(...)` creates a visit and its optional one-item treatment plan in one transaction.
- `create_clinical_price_request(...)` resolves the standard catalogue price on the server and rejects zero-context, duplicate-pending or non-discount requests.
- `decide_clinical_price_request(...)` requires approval permission, blocks self-approval, updates the plan item and recalculates the plan total transactionally.
- Finance resolves an approved negotiated price before opening a payment account.

Direct browser access to the six normalized clinical/catalogue tables is denied. The RPC layer enforces clinic, permission and practitioner assignment boundaries.

Run `supabase/tests/clinical_workflows.sql` against a development database. It creates a temporary assistant Auth identity inside a transaction, exercises visit → plan → request → approval → finance-price resolution, and rolls everything back.
