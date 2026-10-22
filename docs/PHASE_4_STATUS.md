# Phase 4 — public booking and internal agenda

Updated: 2026-10-20 (Africa/Casablanca)

## Implemented in the shared checkout

- Migration `032_booking_agenda_completion.sql` preserves the hashed management token, public contact throttle, and practitioner/resource transaction locks. Public service slots now use the clinic-local date and require an active chair or room. The booked service, patient-written reason, patient ID and Acquisition lead ID reach the agenda snapshot. Public rescheduling uses the original appointment duration, assigned resource and practitioner working hours even if the original booking link has since been unpublished. A legacy booking without a resource receives an active resource when rescheduled. Token cancellation and rescheduling are rejected after the appointment starts; rescheduling extends the token expiry relative to the new date.
- Internal status changes require `appointments.cancel` for both cancellation and no-show. No-show is allowed only after the appointment starts and cannot move its slot. Cancellation/no-show can still close an appointment whose original practitioner, service or resource was later deactivated. Existing status transitions, tenant checks and conflict locks remain in force.
- The public management screen uses the new token-scoped slot RPC, shows the selected service and original reason, gives a loading/empty/conflict state, and uses the clinic timezone for the date input. The phone booking flow keeps conflict feedback visible while refreshing slots. At 390px width, the booking flow fits without horizontal overflow.
- The agenda keeps its preexisting list/week/month views, adds permission-gated patient and prospect record links, restricts status choices to valid transitions, hides future no-show and unauthorized cancellation choices, filters inactive practitioners on new bookings, and translates resource conflicts into clear feedback. Demo overlap checks now allow an appointment to be cancelled or marked no-show after its old slot was reused. Agenda monetary labels use the clinic currency.
- Added a transactional SQL suite for service duration and working hours, public/internal slot collision, booking to CRM links, management after link unpublish, reschedule/cancel, cancelled token denial, assistant cancellation/no-show denial and future no-show denial. Added a 390px demo browser journey for booking, agenda link and released slot visibility, plus a local-only two-client HTTP race check for when Supabase starts.

## Checks actually run

| Check | Result |
| --- | --- |
| `pnpm build` | Passed after the final code changes |
| `pnpm e2e` in demo mode | 7 passed, 6 local/authenticated checks skipped by their target guards |
| PostgreSQL syntax parse with `pglast` | Migration 032 and `booking_agenda_phase4.sql` parsed; PL/pgSQL bodies were not executed |
| `node --check` on new browser test, `git diff --check` on Phase 4 edits | Passed |
| `./scripts/local-sql-tests.ps1` | Could not start: Docker engine pipe `//./pipe/docker_engine` unavailable |

## Runtime acceptance still required

After the previously identified Windows/WSL2 restart and local Docker engine are available, run `./scripts/local-start.ps1 -Reset`, `./scripts/local-sql-tests.ps1`, and `./scripts/local-e2e.ps1` with synthetic fixtures. Confirm migration 032 and all transactional suites, Auth/RLS permissions, token management responses, public booking to patient/lead/agenda links, and the local-only two-client race check. The new SQL suite checks sequential collision and lock-protected code paths, but the concurrent race has **not** been executed. Phase 4 is code-complete and statically/demo checked; it is **not locally runtime accepted**. No hosted production system or real patient data was touched.

Phase 1–3 uncommitted files and the earlier calendar implementation were preserved. No worktree, restart or hosted deployment was performed.
