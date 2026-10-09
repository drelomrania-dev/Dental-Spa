# Dental Spa MVP — Implementation plan

## Current architecture

- React 19 + Vite single-page application.
- Supabase Auth, Postgres, RLS, Storage and Edge Functions in production.
- `patients` and Acquisition use normalized tables; legacy operational modules still use tenant-scoped `app_records` while their normalized migrations are completed.
- Vercel deploys `main` from `drelomrania-dev/Dental-Spa`.

## Delivery sequence

| Phase | Scope | State | Acceptance checkpoint |
|---|---|---|---|
| 0 | Audit, deployment, mobile shell | Complete | Build and Vercel production verified |
| 1 | Auth, permissions, clinic settings, staff, patients, services | In progress | Backend permission tests pass for every preset |
| 2 | Internal calendar and public booking | In progress | Public booking is live; cancellation/rescheduling remain |
| 3 | Visits, treatment plans, quotations | In progress | Existing screens persist remotely; normalized transactional model remains |
| 4 | Approvals, payments, balances, receipts, corrections | In progress | Existing flow persists remotely; server-authoritative ledger remains |
| 5 | Collection sessions and role dashboards | In progress | Existing flow persists remotely; scope enforcement remains |
| 6 | End-to-end, security, recovery and acceptance | In progress | Mandatory journey and permission suite passes |
| P0 Acquisition | Leads, intake, guided media, quotes, conversion | Complete | Transactional SQL test and mobile UI checks pass |

## Dependency map

`Auth + clinic membership → permissions → patients/services/resources → appointments → clinical plans → approvals → payments → collection closing → reporting`.

## Main risks

- Legacy `app_records` modules need normalized server-side commands before handling real financial or clinical history.
- Supabase email delivery is rate-limited until a production SMTP provider is configured.
- Receipt PDF, refunds/corrections, public cancellation/rescheduling and room/chair availability are not yet production-complete.
- Moroccan invoice and retention requirements require clinic/legal validation.

## Definition of complete

A module is complete only when schema, RLS, server validation, UI, persistence, cross-module links, error handling and tests are all verified. A rendered screen alone is not considered complete.
