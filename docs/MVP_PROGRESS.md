# Dental Spa MVP — Progress

## Booking

**Implemented:** Calendly-style public calendar, live slots, transactional conflict check, patient matching, references and responsive layouts.  
**Verified:** Supabase RPC tests, 320/390 px and desktop UI, Vercel production.  
**Remaining:** Public cancellation/rescheduling, configurable practitioner/room rules, rate limiting.  
**Risks / blockers:** None for basic booking; advanced availability remains.

## Acquisition & conversion

**Implemented:** Pipeline, lead profile, interactions, follow-ups, token invitations, four-step intake, private guided photos, consent evidence, quotes and conversion to patient.  
**Verified:** Transactional SQL suite, negative Edge Function token test, mobile UI, RLS/grant review.  
**Remaining:** Optional outbound WhatsApp/email providers and advanced attribution dashboards.  
**Risks / blockers:** External messaging intentionally remains manual.

## Existing clinic modules

**Implemented:** Patients, appointments, practitioners, services, clinical visits/plans, negotiated-price screens, receivables, reports and settings persist through Supabase. Finance now uses a normalized append-only ledger with server-calculated balances, idempotent collection, immutable receipt snapshots, linked correction entries and normalized cash sessions. Legacy `app_records` operations have backend permission guards.
**Verified:** Every route loads against the remote database without a visible data error; finance and access-control transactional SQL suites pass and roll back; anonymous users have no finance RPC access.
**Remaining:** Normalize clinical plans/visits and internal appointments; add downloadable PDF receipts; finish practitioner assignment and sensitive clinical-field isolation.
**Risks / blockers:** Finance integrity is enforced at the database command layer, but Moroccan invoice wording/numbering and retention still require clinic/legal validation.

## Deployment

**Implemented:** GitHub `main` auto-deploy, mobile shell, production Supabase default using a browser-safe publishable key.  
**Verified:** Production root requires Supabase authentication and `/book/consultation` loads live remote availability.  
**Remaining:** Configure custom domain, production SMTP, backups and monitoring.  
**Risks / blockers:** Supabase leaked-password protection is not enabled yet.
