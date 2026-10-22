# Phase 8 — dashboards and reporting

Updated: 2026-10-21 (Africa/Casablanca)

## Implemented in the shared checkout

- The role-aware dashboard now obtains clinic-wide finance figures from `finance_report_snapshot` instead of reducing the caller's payment rows. It shows today and seven-day net collections from the append-only finance ledger. A collector with only own-payment access sees only their own permitted operations. A user with only `reports.finance` can load the aggregate without requiring a finance detail snapshot. Loading, empty and error states are explicit.
- `crm_report_snapshot` returns only clinic-scoped aggregate lead stages, sources, distinct lead-linked bookings, converted patients, open and overdue follow-ups. The dashboard shows source and booking conversion rates without lead contact or note fields. The RPC requires `acquisition.view`; direct lead detail still follows the Phase 3 RLS rules.
- The finance report keeps operational cash collection distinct from accounting revenue. Its gross collections, corrections, net collections, method, treatment and daily totals originate in normalized `finance_transactions`; outstanding derives from normalized accounts and the ledger. The report displays the gross − corrections = net reconciliation result. The existing detailed finance CSV remains a server-side `reports.export` RPC with an audit insert.
- Migration `036_reporting_phase8.sql` wraps the existing finance aggregate so individual cash-session rows are returned only to `sessions.manage`. It adds a filtered PaymentHistory CSV RPC requiring `reports.export`, scoped to the caller's clinic and audited in the same transaction. The CSV button is hidden without that grant; in Supabase mode, no client payment rows are used to construct the file. It caps export size at 5,000 rows and escapes spreadsheet formula prefixes.
- Receipt PDF and 80 mm print buttons request `payments.receipt` authorization on the exact clinic ledger transaction before generating a document. The server also requires `payments.view.all` or that the caller collected the payment, then writes a receipt export audit event. Settings can read the clinic's normalized export audit through an `audit.view` RPC. Local demo exports write demo audit entries before download. Live Firebase exports and backups are hidden because they have no equivalent server audit boundary.
- Phase 8 SQL acceptance covers ledger reconciliation, CRM source/booking/follow-up aggregation, no patient fields in aggregate results, session-row redaction, export and receipt permission denials, audit rows, filtered export, audit-view denial and cross-clinic isolation. Demo and guarded authenticated browser checks cover report views, CSV/PDF downloads and role routing.

## Checks actually run

| Check | Result |
| --- | --- |
| `pnpm build` | Passed after the Phase 8 UI and audit changes |
| `pnpm e2e --reporter=line` | 13 public/demo passed, 11 local Auth/backend checks skipped by target guards, including the latest separate Phase 3 demo addition |
| Targeted Phase 8 demo browser check | Passed after final audit-view change: dashboard sections, finance reconciliation, report CSV, history CSV, receipt PDF, local audit display |
| `pglast` | Migration 036 and `reporting_phase8.sql` top-level SQL parsed; all five new PL/pgSQL function bodies parsed. No database execution |
| `node --check`, `git diff --check` | Passed; Git emitted existing LF/CRLF conversion warnings |
| `./scripts/local-sql-tests.ps1` | Stopped: Docker engine pipe `//./pipe/docker_engine` is unavailable |

## Export and audit boundary

The browser issues CSV, receipt PDF or print from the app only after a successful permission-gated server RPC. The detailed finance and history CSV RPCs insert `audit_events` before returning rows. The receipt authorization RPC returns the authorized ledger document and inserts an event before the browser renders it. Audit entries record authorized requests; they cannot prove a browser completed a download or physical print. A user who can view information can still use browser or operating-system capture outside the app's export buttons. Demo audit records in local storage are for synthetic workflow checks and are not tamper resistant.

## Runtime acceptance still required

After the previously identified Windows/WSL2 restart makes the Docker Linux engine available, run `./scripts/local-start.ps1 -Reset`, `./scripts/local-sql-tests.ps1`, and `./scripts/local-e2e.ps1` with synthetic fixtures. Confirm fresh migration 036, the new SQL suite, Auth/RLS role and clinic boundaries, actual report/export RPC results, normalized audit display, and the authenticated Phase 8 browser check. SQL/Auth/RLS/browser integration is **not locally accepted**. No restart, hosted production change or real patient data was used.

The Phase 7 fake sender remains a release-only risk: it must not be used for real patient messaging. No real delivery provider was activated in Phase 8. The Phase 1–7 uncommitted work and separate Phase 3 corrective changes were preserved.
