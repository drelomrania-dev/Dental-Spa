# Phase 5 — patient, clinical and negotiated price

Updated: 2026-10-20 (Africa/Casablanca)

## Implemented in the shared checkout

- Added migration `033_patient_clinical_phase5.sql`. The patient timeline RPC returns clinic-scoped appointments, assigned clinical visits/plans, and only payment references permitted by the caller's finance grant. Reception receives no clinical notes or plans; practitioner access follows active appointment or visit assignment. The basic patient record remains separate from medical alerts.
- A visit can be attached to one matching appointment for the same patient and practitioner. Visit and optional plan creation stay in one transaction. Duplicate appointment linkage, cancelled/no-show linkage, other-practitioner action and unassigned patient action are denied. Clinicians can amend notes and follow-up text; prior values are retained in a private revision table. Plan status changes have an RPC and cannot reset an approved price.
- The patient profile shows the linked chronology, clinical details only to clinical readers, permitted payment references, and an administrative contact editor. The clinical screen supports appointment selection, note correction and plan status updates. Errors remain visible so staff can retry without losing form input.
- Price requesters receive narrow patient/service/plan-item targets rather than clinical notes or full plans. Requests enforce clinic and practitioner assignment, one pending or approved request per patient/service, a server-side standard price, and no existing finance account. Decisions reject self-approval and require a pending request. Rejection leaves the plan and finance price at standard; approval updates the linked plan item and total once. Finance resolves the approved quote when it opens a new account. An account opened before approval blocks the approval rather than silently changing a frozen account.
- The negotiated-price screen shows justification, request date, linked-plan indication, decision date and reason; it hides action controls for the requester's own pending request. No clinical notes were added to CRM messaging or finance screens.
- In Supabase mode, the payment form waits for the authoritative finance balance before allowing collection, so an approved quote is displayed from the server rather than inferred from the collector's limited price-request history.
- Added `supabase/tests/patient_clinical_phase5.sql` with transactional assignment, privacy, appointment/visit/plan, correction, price request, self-approval, cross-clinic, rejection, duplicate approval, finance resolution and payment-reference cases. Added a passing demo browser journey and authenticated role/cross-clinic browser checks that will run when the local Auth target exists.

## Checks actually run

| Check | Result |
| --- | --- |
| `pnpm build` | Passed on the shared checkout after the Phase 3 corrective handoff and the Phase 5 UI changes |
| `pnpm e2e` in demo mode with a fresh Vite server | 9 passed, 8 local/authenticated checks skipped by target guards |
| PostgreSQL top-level syntax parse with `pglast` | Migration 033 and the Phase 5 SQL suite parsed; PL/pgSQL bodies were not executed |
| `./scripts/local-sql-tests.ps1` | Stopped: Docker engine pipe `//./pipe/docker_engine` unavailable |
| `git diff --check` | Passed; Git reported only local LF/CRLF conversion warnings |

## Runtime acceptance still required

After the already identified Windows/WSL2 restart makes Docker's Linux engine available, run `./scripts/local-start.ps1 -Reset`, `./scripts/local-sql-tests.ps1`, and `./scripts/local-e2e.ps1` with synthetic fixtures. Confirm migration 033 and all transactional suites, assignment-scoped practitioner and reception Auth/RLS behavior, two-clinic denial, the linked visit/plan and price decision flow, and that an approved price reaches finance exactly once. The SQL and authenticated browser behavior is **not runtime accepted**. No Windows restart, hosted production deployment or real patient data was used.

Clinical visit revisions are retained privately for audit, but a user-facing revision viewer and a formal medical-record retention policy are not part of this phase. Payment accounts already opened at the standard price remain frozen; a later discount requires a separate finance correction process rather than rewriting the account.
