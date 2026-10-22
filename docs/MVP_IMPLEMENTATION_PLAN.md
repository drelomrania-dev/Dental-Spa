# Dental Spa OS — MVP implementation and acceptance plan

Updated: 2026-10-21 (Africa/Casablanca)

## Architecture and acceptance boundary

The app is React 19/Vite. The intended clinic backend is Supabase Auth, Postgres with RLS, private Storage and Edge Functions. Local demo mode uses browser storage for synthetic UI exercises; it is not a security or persistence acceptance environment. The repository contains migrations through `036_reporting_phase8.sql` and Phase 1–9 implementation. See `HANDOFF_2026-10-22.md` for the laptop continuation context.

The 19 work areas below are the current implementation inventory. “Implemented” means code and demo/static checks exist. It does not mean the fresh local Supabase stack, multi-account permissions or production operation has passed.

| # | Work area | Delivery phase | Current checkpoint |
| --- | --- | --- | --- |
| 1 | Local Auth and development platform | 1 | Implemented; runtime pending |
| 2 | Tenant isolation and role permissions | 1–2 | Implemented; two-clinic runtime pending |
| 3 | Clinic identity and settings | 2 | Implemented; runtime pending |
| 4 | Staff invitations, roles and audit | 1–2 | Implemented; Auth/Edge runtime pending |
| 5 | Practitioners, services, resources and booking links | 2 | Implemented; catalogue runtime pending |
| 6 | Lead pipeline, follow-ups and interactions | 3 | Implemented; CRM/RLS runtime pending |
| 7 | Public intake, consent and private guided media | 3 | Implemented; Storage/Edge runtime pending |
| 8 | Prospect quotes and patient conversion | 3 | Implemented; transactional runtime pending |
| 9 | Public booking and secure management links | 4 | Implemented; token and race runtime pending |
| 10 | Internal agenda and appointment transitions | 4 | Implemented; transactional runtime pending |
| 11 | Patient identity, timeline and medical access separation | 5 | Implemented; Auth/RLS runtime pending |
| 12 | Clinical visits and note revisions | 5 | Implemented; clinical runtime pending |
| 13 | Treatment plans and negotiated price decisions | 5 | Implemented; price/finance runtime pending |
| 14 | Finance accounts and dated installments | 6 | Implemented; ledger runtime pending |
| 15 | Payments, corrections and operational receipts | 6 | Implemented; ledger/runtime and legal review pending |
| 16 | Cash collection sessions | 6 | Implemented; multi-collector runtime pending |
| 17 | Consent, templates and reminders | 7 | Fake sender/demo implemented; runtime and real provider work pending |
| 18 | Role dashboards, reporting and audited exports | 8 | Implemented; report/Auth runtime pending |
| 19 | Integrated phone/desktop and keyboard UX | 9 | Demo/browser pass; local integrated acceptance pending |

## Delivery checkpoints

| Phase | Work | Evidence | Next gate |
| --- | --- | --- | --- |
| 1 | Local stack, fixtures and baseline | Build, demo checks and static SQL structure | Fresh local migration, Auth/Storage/Edge verification |
| 2 | Clinic setup, staff and catalogue | Build, demo UI and SQL syntax | Local catalogue, invitation and role checks |
| 3 | CRM, intake, media and quotes | Demo journeys, SQL and Edge syntax | Local RLS, Storage, token and Edge tests |
| 4 | Booking and agenda | Phone demo, SQL syntax | Local conflict, management token and two-client race |
| 5 | Patient and clinical | Demo journey, SQL syntax | Local assignment, medical privacy and price-to-finance |
| 6 | Finance and cash | Demo journey, PDF check, SQL syntax | Local ledger, receipts and collector separation |
| 7 | Reminders | Demo fake-delivery journey, SQL syntax | Local consent/outbox invalidation and roles |
| 8 | Reporting | Demo exports and SQL syntax | Local aggregate/export RPC and audit checks |
| 9 | Integrated UX | 20 browser passes, build and cross-module demo | Phase 10 local acceptance |
| 10 | Local acceptance and final audit | Static/script review and demo checks passed; WSL platform installation requires restart | After the Windows restart and working Docker Linux engine, run all local migrations, SQL/Auth/Storage/Edge/browser suites with synthetic clinics |

The Phase 9 evidence and exact pending checklist are in `PHASE_9_STATUS.md`. The Phase 10 blocker and checks actually run are in `PHASE_10_STATUS.md`; current test accounting is in `MVP_TEST_REPORT.md`.

## Completion rule

A module is accepted only after its schema, server validation, RLS, UI, persistence, cross-module behavior, error handling and relevant tests pass on the intended local Supabase runtime. A demo screen, SQL parse or build alone cannot satisfy that rule. Release for real patients additionally needs backup/restore, operational and clinic/legal reviews. The app is not a complete EHR or production-ready clinic system.
