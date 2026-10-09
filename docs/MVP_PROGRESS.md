# Dental Spa MVP — Progress

## Booking

**Implemented:** Calendly-style public calendar, live slots, normalized internal agenda, transactional conflict checks, patient/lead deduplication, secure management links, public rescheduling/cancellation, references and responsive layouts. Every public booking is linked to the patient agenda and to the Acquisition `Rendez-vous` stage with an auditable history.
**Verified:** Appointment and booking-to-Acquisition SQL suites, rollback cleanup, 390 px and desktop public UI, invalid-token management UI and production build.
**Remaining:** Configurable room/chair availability and public-endpoint rate limiting.
**Risks / blockers:** None for the core booking-to-agenda-to-pipeline journey; advanced resource availability remains.

## Acquisition & conversion

**Implemented:** Pipeline, lead profile, interactions, follow-ups, token invitations, four-step intake, private guided photos, consent evidence, quotes and conversion to patient.  
**Verified:** Transactional SQL suite, negative Edge Function token test, mobile UI, RLS/grant review.  
**Remaining:** Optional outbound WhatsApp/email providers and advanced attribution dashboards.  
**Risks / blockers:** External messaging intentionally remains manual.

## Existing clinic modules

**Implemented:** Patients, appointments, practitioners, services, receivables, reports and settings persist through Supabase. Patient identity and medical records now have separate RPC-only access boundaries, with assignment-scoped clinical access and no direct browser table grants. Finance uses a normalized append-only ledger with server-calculated balances, idempotent collection, immutable receipt snapshots, linked correction entries and normalized cash sessions. Clinical visits, treatment plans and negotiated-price approvals use normalized transactional commands; finance consumes approved prices. Legacy `app_records` operations have backend permission guards.
**Verified:** Patient privacy plus all prior access-control, acquisition, finance, clinical and appointment transactional suites pass and roll back; zero QA rows remain. Anonymous users have no patient, finance or clinical table access.
**Remaining:** Add downloadable PDF receipts and finish two-real-account browser E2E.
**Risks / blockers:** Finance integrity is enforced at the database command layer, but Moroccan invoice wording/numbering and retention still require clinic/legal validation.

## Deployment

**Implemented:** GitHub `main` auto-deploy, mobile shell, production Supabase default using a browser-safe publishable key.  
**Verified:** Production root requires Supabase authentication and `/book/consultation` loads live remote availability.  
**Remaining:** Configure custom domain, production SMTP, backups and monitoring.  
**Risks / blockers:** Supabase leaked-password protection is not enabled yet.
