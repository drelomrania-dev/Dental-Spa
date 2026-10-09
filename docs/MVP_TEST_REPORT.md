# Dental Spa MVP — Test report

Date: 2026-10-09
Environment: local Vite against production Supabase; Vercel production smoke test.

| Test | Result | Evidence |
|---|---|---|
| Production build | Pass | Vite transformed 1,685 modules; only the existing chunk-size warning remains |
| Public booking metadata and slots | Pass | Remote RPC returned whitelisted metadata and live 30-minute slots |
| Booking responsive UI | Pass | 320 px, 390 px and desktop; no horizontal overflow or console errors |
| Booking conflict protection | Pass at database command level | Advisory lock and slot recheck deployed |
| Acquisition core journey | Pass | `supabase/tests/acquisition_p0.sql` completed and rolled back |
| Invalid media token | Pass | `acquisition-media` returned HTTP 401 and created no object |
| Acquisition mobile UI | Pass | Pipeline, profile and four intake steps checked at 390 px |
| Remote module route smoke test | Pass | 14 internal routes loaded with no visible data error |
| Production remote backend | Pass | Root shows Supabase Auth; booking page loads remote clinic data |
| Legacy-record backend permissions | Pass | `supabase/tests/access_control.sql` verified administrator and assistant behavior, then rolled back |
| Server-authoritative finance ledger | Pass | `supabase/tests/finance_ledger.sql` verified idempotency, overpayment rejection, linked correction, immutable access boundary and cash reconciliation, then rolled back |
| Finance API exposure | Pass | Four RPC-only RLS policies; zero anonymous finance grants; no finance QA rows remained |
| Finance browser UI | Pass | Remote history, correction modal and authoritative balance verified; 390×844 payment form has no horizontal overflow and a 45 px primary action |

## Not yet passed

- Simultaneous public booking load test with two real HTTP clients.
- Browser E2E using a dedicated assistant Auth account (the current project has only the administrator account).
- Downloadable PDF receipt rendering and legal wording review.
- Full-day operational journey with two real staff accounts and cash-session isolation.

No final production-readiness claim is made until the remaining tests pass.
