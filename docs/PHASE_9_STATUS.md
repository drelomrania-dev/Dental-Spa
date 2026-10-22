# Phase 9 — integrated UX and synthetic clinic journey

Updated: 2026-10-21 (Africa/Casablanca)

## Implemented in the shared checkout

- Audited 17 internal routes and four public entry/error routes at 390×844 and 1440×844. The audit checks visible headings, page overflow, visible control names and uncaught browser errors. It includes the real synthetic lead profile plus agenda, patient/clinical, collections, reminders, reports and settings routes. Nine key dialogs were opened at both widths and checked for labels, overflow and keyboard focus.
- Fixed the 390px report overflow by allowing report grid children to shrink and keeping wide tables scrollable within cards. Added a visible keyboard focus outline throughout public and internal controls.
- Added explicit names to prospect, patient and payment searches, payment-method filter, resource name/type and lead notes/invitation link. Removed the inert global search and notification controls, which had appeared actionable but had no behavior.
- Dialogs now focus a field on open, keep Tab inside, close with Escape and return focus to the trigger. Acquisition and lead action dialogs show save errors inside the dialog, retaining entered values for retry. A browser test injects a synthetic browser-storage write failure, observes the error and succeeds on retry.
- The local demo public booking flow now connects a booking to an existing or new CRM lead by normalized contact, updates the pipeline to `Rendez-vous`, preserves a `Converti` lead, and stores the lead ID on the appointment. A CRM-link failure after a saved booking is surfaced on the confirmation with the booking reference. The Supabase public booking transaction was not modified.
- Added `e2e/phase9-audit.spec.js` and `e2e/phase9-journey.spec.js`. The integrated phone journey passed lead creation/follow-up, public booking, linked agenda/patient, visit and plan, assistant price request and administrator approval, partial cash payment with a two-installment plan, cash-session validation, finance report reconciliation and reminder consent/queue inspection. It confirms the clinical note does not enter the reminder outbox.
- Reconciled `MVP_IMPLEMENTATION_PLAN.md`, `MVP_PROGRESS.md` and `MVP_TEST_REPORT.md` with Phase 1–9 implementation versus local runtime acceptance. The earlier 2026-10-10 hosted smoke report is explicitly historical for this uncommitted checkout.

## Checks actually run

| Check | Result |
| --- | --- |
| `pnpm build` | Passed; Vite transformed 1,697 modules |
| `pnpm e2e --reporter=line` | 20 passed, 11 skipped local/Auth/backend checks, 31 total |
| Targeted Phase 9 audit | 6 passed: two route widths, two dialog widths, failed-save/focus recovery and demo role denial |
| Targeted Phase 9 journey | 1 passed at 390px |
| `node --check` on both Phase 9 specs; `git diff --check` | Passed; Git emitted existing LF/CRLF conversion warnings |
| `docker info` | Could not run in this shell: `docker` is not on PATH. Earlier phases found the Docker Linux engine pipe unavailable. No Windows restart occurred. |

## Phase 10 local acceptance checklist

Use only synthetic fixtures after the already identified Windows/WSL2 restart. Confirm Docker Desktop's Linux engine is running and `docker info` works in the shell, then follow `LOCAL_DEVELOPMENT.md`:

1. Run `./scripts/local-start.ps1 -Reset` and record fresh application of baseline plus migrations 029–036, local Auth fixture sign-ins, tenant memberships, private Storage bucket and invitation Edge Function health. Keep the fixture file ignored.
2. Run `./scripts/local-sql-tests.ps1`; record each transactional suite result, including Phase 3 contact/media races, Phase 4 booking/resource conflicts, Phase 5 assignment and medical privacy, Phase 6 ledger/session rules, Phase 7 consent/outbox invalidation and Phase 8 reports/audit. SQL syntax parsing already recorded in earlier phases is not runtime evidence.
3. Run `./scripts/local-e2e.ps1` with the generated two-clinic and multi-role fixture accounts. Ensure all 11 currently skipped authenticated/local browser tests execute, including route denial, two-clinic patient isolation, clinical privacy, collector separation, reminder grants and audited report/export permissions. Exercise the staff invitation/claim path and public intake media upload/withdrawal through local Edge/Storage.
4. Run the two-client public booking HTTP race check and secure management-token reschedule/cancel checks. Verify lead/patient/agenda linkage under local Postgres, including existing-contact deduplication and a declined or expired token.
5. Repeat the synthetic clinic journey against local Supabase: lead/intake → booking → appointment → patient/clinical visit and plan → negotiated decision → installment/payment/receipt → cash session → reporting and reminder queue. Verify server-derived values and role boundaries with two staff identities; use no real patient or provider delivery.
6. Investigate and fix any failing migration, SQL, Auth, Storage, Edge or browser result, then update the test report with exact outcomes. Do not mark Phases 1–9 runtime accepted based only on this Phase 9 demo pass.

## Remaining product and release limits

The reminder sender is fake; no trusted scheduler, real provider worker, email or WhatsApp delivery was deployed. The app has no complete EHR scope or approved clinical record retention policy. Operational receipts are not fiscal invoices; clinic/legal review is still required for Moroccan wording, tax identifiers, numbering and retention. Backup/restore, monitoring, domain/SMTP and operational clinic sign-off remain separate release work. No hosted production action or real patient data was used in Phase 9. The shared Phase 1–8 changes and Phase 3 corrections were preserved without reset or worktree.
