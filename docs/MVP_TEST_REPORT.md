# Dental Spa MVP — Test report

Date: 2026-10-10
Environment: local Vite against production Supabase; Vercel production smoke test.

| Test | Result | Evidence |
|---|---|---|
| Production build | Pass | Vite transformed 1,693 modules; only the existing chunk-size warning remains |
| Public booking metadata and slots | Pass | Remote RPC returned whitelisted metadata and live 30-minute slots |
| Booking responsive UI | Pass | 320 px, 390 px and desktop; no horizontal overflow or console errors |
| Booking conflict protection | Pass at database command level | Advisory lock and slot recheck deployed |
| Chair/room availability and abuse limit | Pass | `supabase/tests/booking_resources_rate_limits.sql` verified cross-practitioner resource collision rejection, separate-resource concurrency, public resource assignment and rejection of the fourth booking by the same normalized contact, then rolled back |
| Normalized appointment workflow | Pass | `supabase/tests/appointment_workflows.sql` verified internal creation, overlap rejection, reschedule, status transition, public management, cancellation and event history, then rolled back |
| Booking → agenda → Acquisition | Pass | `supabase/tests/public_booking_acquisition.sql` verified agenda visibility, `Rendez-vous` Kanban placement, linked history and phone/email deduplication, then rolled back |
| Booking service and visit reason | Pass | `supabase/tests/public_booking_service_choice.sql` verified the public service catalogue, service-specific slots, backend reason validation, normalized agenda persistence and Acquisition concern linkage, then rolled back |
| Progressive booking mobile UI | Pass | Seven focused steps—service, reason, date, time, identity, contact and review—were exercised at 390×844 through the final confirmation screen without writing a booking or causing horizontal overflow |
| Public booking management UI | Pass | Live booking form and invalid/expired management-token state verified at 390×844 without submitting patient data |
| Acquisition core journey | Pass | `supabase/tests/acquisition_p0.sql` completed and rolled back |
| Invalid media token | Pass | `acquisition-media` returned HTTP 401 and created no object |
| Acquisition mobile UI | Pass | Pipeline, profile and four intake steps checked at 390 px |
| Remote module route smoke test | Pass | 14 internal routes loaded with no visible data error |
| Production remote backend | Pass | Root shows Supabase Auth; booking page loads remote clinic data |
| Legacy-record backend permissions | Pass | `supabase/tests/access_control.sql` verified administrator and assistant behavior, then rolled back |
| Server-authoritative finance ledger | Pass | `supabase/tests/finance_ledger.sql` verified idempotency, overpayment rejection, linked correction, immutable access boundary and cash reconciliation, then rolled back |
| Finance API exposure | Pass | Four RPC-only RLS policies; zero anonymous finance grants; no finance QA rows remained |
| Financial reporting and export | Pass | `supabase/tests/financial_reporting.sql` verified date-scoped aggregates, method/service/collector groupings, detailed CSV source rows, audit logging and denial without `reports.finance` / `reports.export`, then rolled back |
| Finance browser UI | Pass | Remote history, correction modal and authoritative balance verified; 390×844 payment form has no horizontal overflow and a 45 px primary action |
| Clinical workflow transaction | Pass | Temporary assistant request → administrator approval → plan repricing → finance price resolution, all rolled back |
| Clinical browser UI | Pass | Remote clinical and negotiated-price pages plus both creation modals load without writing patient data |
| Patient privacy boundary | Pass | `supabase/tests/patient_access.sql` verified basic reception access, medical-data denial, direct-table denial and administrator medical access, then rolled back |
| Patient regression suite | Pass | Acquisition, finance, clinical, appointment and booking bridge suites all pass after the patient RPC migration; zero QA patients, medical records or Auth users remain |
| Downloadable payment receipt | Pass | Browser-native PDF generator produced a valid one-page A4 receipt; Poppler rendering showed no clipping/overlap and pypdf verified French accents and payment fields |
| Staff invitation boundary | Pass | `supabase/tests/staff_invitations.sql` verified assistant and practitioner claims, practitioner-directory linkage, idempotence, RPC-only storage and rollback cleanup |
| Staff access-link function | Pass | `staff-invite-link` is active with JWT verification and returned HTTP 401 to an anonymous request |
| Auth bootstrap hardening | Pass | Public bootstrap reports closed after the first administrator; the production-mode login screen no longer exposes free administrator registration |
| Staff invitation mobile UI | Pass | Invalid/expired link state rendered at 390×844 without overflow |

## Not yet passed

- Simultaneous public booking load test with two real HTTP clients.
- Optional IP-level edge/WAF throttling test for repeated invalid requests.
- Browser E2E using a dedicated invited assistant Auth account (the current project still has only the administrator account).
- Clinic/legal review of Moroccan receipt wording, numbering and retention.
- Full-day operational journey with two real staff accounts and cash-session isolation.

No final production-readiness claim is made until the remaining tests pass.
