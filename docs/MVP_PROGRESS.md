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

**Implemented:** Patients, appointments, practitioners, services, clinical visits/plans, negotiated-price screens, payments, receivables, collection sessions, reports and settings all persist through Supabase.  
**Verified:** Every route loads against the remote database without a visible data error.  
**Remaining:** Move finance/clinical modules from `app_records` to normalized transactional commands; granular backend permissions; PDF receipts; corrections/refunds; complete cash-session scope tests.  
**Risks / blockers:** These modules are functional for controlled acceptance testing, not yet certified for unsupervised real-clinic finance.

## Deployment

**Implemented:** GitHub `main` auto-deploy, mobile shell, production Supabase default using a browser-safe publishable key.  
**Verified:** Production root requires Supabase authentication and `/book/consultation` loads live remote availability.  
**Remaining:** Configure custom domain, production SMTP, backups and monitoring.  
**Risks / blockers:** Supabase leaked-password protection is not enabled yet.
