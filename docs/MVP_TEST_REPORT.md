# Dental Spa MVP — Test report

Date: 2026-10-08  
Environment: local Vite against production Supabase; Vercel production smoke test.

| Test | Result | Evidence |
|---|---|---|
| Production build | Pass | Vite transformed 1,683 modules; only the existing chunk-size warning remains |
| Public booking metadata and slots | Pass | Remote RPC returned whitelisted metadata and live 30-minute slots |
| Booking responsive UI | Pass | 320 px, 390 px and desktop; no horizontal overflow or console errors |
| Booking conflict protection | Pass at database command level | Advisory lock and slot recheck deployed |
| Acquisition core journey | Pass | `supabase/tests/acquisition_p0.sql` completed and rolled back |
| Invalid media token | Pass | `acquisition-media` returned HTTP 401 and created no object |
| Acquisition mobile UI | Pass | Pipeline, profile and four intake steps checked at 390 px |
| Remote module route smoke test | Pass | 14 internal routes loaded with no visible data error |
| Production remote backend | Pass | Root shows Supabase Auth; booking page loads remote clinic data |

## Not yet passed

- Simultaneous public booking load test with two real HTTP clients.
- Assistant/direct-API permission matrix.
- Server-authoritative negotiated-price and payment ledger tests.
- Payment idempotency, refunds/corrections and immutable receipt tests.
- Full-day operational journey and cash-session isolation.

No final production-readiness claim is made until the remaining tests pass.
