# Dental Spa MVP — Test report

Date: 2026-10-09
Environment: local Vite against production Supabase; Vercel production smoke test.

| Test | Result | Evidence |
|---|---|---|
| Production build | Pass | Vite transformed 1,689 modules; only the existing chunk-size warning remains |
| Public booking metadata and slots | Pass | Remote RPC returned whitelisted metadata and live 30-minute slots |
| Booking responsive UI | Pass | 320 px, 390 px and desktop; no horizontal overflow or console errors |
| Booking conflict protection | Pass at database command level | Advisory lock and slot recheck deployed |
| Normalized appointment workflow | Pass | `supabase/tests/appointment_workflows.sql` verified internal creation, overlap rejection, reschedule, status transition, public management, cancellation and event history, then rolled back |
| Booking → agenda → Acquisition | Pass | `supabase/tests/public_booking_acquisition.sql` verified agenda visibility, `Rendez-vous` Kanban placement, linked history and phone/email deduplication, then rolled back |
| Public booking management UI | Pass | Live booking form and invalid/expired management-token state verified at 390×844 without submitting patient data |
| Acquisition core journey | Pass | `supabase/tests/acquisition_p0.sql` completed and rolled back |
| Invalid media token | Pass | `acquisition-media` returned HTTP 401 and created no object |
| Acquisition mobile UI | Pass | Pipeline, profile and four intake steps checked at 390 px |
| Remote module route smoke test | Pass | 14 internal routes loaded with no visible data error |
| Production remote backend | Pass | Root shows Supabase Auth; booking page loads remote clinic data |
| Legacy-record backend permissions | Pass | `supabase/tests/access_control.sql` verified administrator and assistant behavior, then rolled back |
| Server-authoritative finance ledger | Pass | `supabase/tests/finance_ledger.sql` verified idempotency, overpayment rejection, linked correction, immutable access boundary and cash reconciliation, then rolled back |
| Finance API exposure | Pass | Four RPC-only RLS policies; zero anonymous finance grants; no finance QA rows remained |
| Finance browser UI | Pass | Remote history, correction modal and authoritative balance verified; 390×844 payment form has no horizontal overflow and a 45 px primary action |
| Clinical workflow transaction | Pass | Temporary assistant request → administrator approval → plan repricing → finance price resolution, all rolled back |
| Clinical browser UI | Pass | Remote clinical and negotiated-price pages plus both creation modals load without writing patient data |
| Patient privacy boundary | Pass | `supabase/tests/patient_access.sql` verified basic reception access, medical-data denial, direct-table denial and administrator medical access, then rolled back |
| Patient regression suite | Pass | Acquisition, finance, clinical, appointment and booking bridge suites all pass after the patient RPC migration; zero QA patients, medical records or Auth users remain |

## Not yet passed

- Simultaneous public booking load test with two real HTTP clients.
- Public booking rate-limit/abuse test before large-scale promotion.
- Browser E2E using a dedicated assistant Auth account (the current project has only the administrator account).
- Downloadable PDF receipt rendering and legal wording review.
- Full-day operational journey with two real staff accounts and cash-session isolation.

No final production-readiness claim is made until the remaining tests pass.
