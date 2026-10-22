# Dental Spa OS — MVP progress

Updated: 2026-10-21 (Africa/Casablanca)

## Current status

Phases 1–9 have implementation in the repository. The 390px/desktop demo browser audit and a single synthetic journey across the major modules pass. Phase 10's static/script review and repeat build/demo checks pass, but the fresh local Supabase stack has **not** been accepted. Docker Desktop reported `WslVirtualMachinePlatformNotEnabled`; `wsl --install --no-distribution` succeeded and requires a Windows restart before Docker's Linux engine can be checked again. Migrations 001–036, transactional SQL, real Auth/RLS roles, private Storage, Edge Functions and authenticated browser journeys still need runtime execution. The historical 2026-10-10 hosted smoke results do not validate the new migrations. See `HANDOFF_2026-10-22.md` for laptop continuation.

| Phase | Delivered code and demo scope | Acceptance state |
| --- | --- | --- |
| 1 | Local stack scripts, fixtures, baseline migration, Auth target guards | Code/static pass; local runtime pending |
| 2 | Clinic setup, staff link/roles, practitioners, services and resources | Demo/static pass; local runtime pending |
| 3 | CRM pipeline, follow-ups, intake, private media and prospect quotes | Demo/static pass; SQL/Storage/Edge pending |
| 4 | Public booking, management tokens, agenda and collision logic | Demo/static pass; SQL/token/concurrent HTTP pending |
| 5 | Patient timeline/privacy, clinical visits/plans and negotiated prices | Demo/static pass; Auth/RLS/transaction pending |
| 6 | Accounts/installments, ledger, receipts/corrections and cash sessions | Demo/static pass; ledger/multi-collector pending |
| 7 | Consent, templates, outbox and fake reminders | Demo/static pass; SQL/roles pending; no real sender |
| 8 | Role dashboards, normalized reports and audited export RPCs | Demo/static pass; report/export RPC runtime pending |
| 9 | Integrated viewport/keyboard/error UX and synthetic journey | 20 Playwright demo/public passes; local integration pending |
| 10 | Static acceptance review, local scripts and two-client race fixture correction | Build and 20 demo/public browser passes; Windows restart required before Docker/WSL2 runtime acceptance |

## Phase 9 integration findings

- Phone report tables now scroll inside their cards instead of widening the page. Labels were added to prospect/patient/payment search, payment method and resource setup controls. The nonfunctional header search and notification affordances were removed.
- Dialogs now focus a field, trap Tab, close on Escape and restore focus. CRM modal save failures are visible inside the dialog so entered values can be corrected and retried. A synthetic storage failure and retry passed.
- Demo public booking now links a matched or newly created CRM lead and the appointment; a post-booking CRM sync failure is shown with the saved booking reference. The Supabase booking command already has its own transactional CRM link and was not changed in Phase 9.
- One phone browser journey passed lead/follow-up → public booking → appointment/patient → clinical visit/plan → price approval → partial cash payment/installment → cash session → report → reminder consent/queue check. Browser demo mode does not establish database or security acceptance.

## Remaining before real clinic operation

Run `docs/LOCAL_DEVELOPMENT.md` and the Phase 10 checklist with synthetic clinics. Resolve any migration, SQL, Auth, Storage, Edge, role or browser failures found there. A trusted provider worker and clinic-approved consent/template/retention policy are needed for real reminders; the current fake sender never sends. Backup/restore, monitoring, operational receipt/invoice wording, tax/numbering, retention and clinic workflow decisions still need review. The application is not a complete EHR and is not production-ready for real patient or financial data.
