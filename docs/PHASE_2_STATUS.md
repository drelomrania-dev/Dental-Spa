# Phase 2 — clinic setup, staff and catalogue

Updated: 2026-10-20 (Africa/Casablanca)

## Implemented in the shared checkout

- Added a first-run checklist in Settings and a dashboard prompt until clinic identity, an active practitioner, a booking-eligible service, an active resource and a published link are present. An empty clinic can add and edit practitioners, services, resources and public booking links. Practitioner working days and hours, service active/booking eligibility, and link publish state are editable.
- Migration `030_clinic_setup_catalogue.sql` synchronizes clinic settings and catalogue writes from compatibility `app_records` into the normalized `clinics`, `practitioners` and `services` tables used by public booking. It validates fields and published link prerequisites, applies practitioner working hours and active resource checks to slot availability, and deactivates normalized catalogue rows when compatibility records are deleted. Clinic settings writes require `settings.manage`; staff/role records are no longer readable by every member.
- The public booking page shows the configured clinic name, address, phone, currency and timezone. The booking calendar derives today's date from the clinic timezone. Receipt PDFs use the configured currency, address, phone and timezone. Existing receipt finance snapshots still do not contain historical clinic identity; see limitation below.
- Administrators can change a claimed staff member's assistant/practitioner role or active status through a server RPC. Practitioner activation is mirrored to the directory. The staff snapshot exposes whether a practitioner link exists and shows expired invitations as expired. Role changes, role permission edits and setup/catalogue changes enter the existing audit collection; administrators can inspect recent events in Settings.
- Added SQL cases for clinic/catalogue synchronization, booking eligibility, availability, service-manager and staff denial, and invitation revocation, expiry and wrong-account claims. Added an empty-clinic demo browser journey and an authenticated route/audit check.

## Checks actually run

| Check | Result |
| --- | --- |
| `pnpm build` | Passed |
| `pnpm e2e` in browser demo mode | 5 passed, 5 authenticated checks skipped because local Supabase is unavailable |
| `node` receipt PDF bytes check | Passed: saved clinic identity fields and EUR text appeared |
| PostgreSQL and PL/pgSQL syntax parse with `pglast` | Passed for migration 030 and both new SQL suites |
| `git diff --check` | Passed |
| `./scripts/local-sql-tests.ps1` | Could not start: Docker engine pipe `//./pipe/docker_engine` unavailable |

## Runtime acceptance pending

The Windows/WSL2 restart requested in Phase 1 was not performed. Docker's Linux engine is unavailable, so a fresh migration run, all 15 transactional SQL suites, local invitation Edge Function/Auth claim, two-account route checks, and authenticated clinic/catalogue browser journey have **not** run. This phase is implemented and statically checked, but it is **not locally accepted**. Run `./scripts/local-start.ps1 -Reset`, `./scripts/local-sql-tests.ps1`, and `./scripts/local-e2e.ps1` after Docker starts, using the synthetic fixtures only. Do not apply migration 030 to hosted production as part of this local phase.

## Decisions and limits

- Existing payment receipt snapshots freeze financial values but not the clinic identity. A PDF generated after a later clinic name/address/currency change uses the current clinic settings. Historical identity snapshots should be added with the receipt/document phase and checked against legal wording requirements.
- The current working-hours control is one weekly day set and one daily time range per practitioner. Lunch, leave and per-day exceptions remain for later scheduling work.
- Phase 1's uncommitted local platform files and the preexisting agenda changes were preserved. No hosted Supabase data or configuration was touched.
