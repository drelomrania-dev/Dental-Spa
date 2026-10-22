# Phase 3 — Acquisition CRM, intake media and prospect quotes

Updated: 2026-10-21 (Africa/Casablanca)

## Implemented in the shared checkout

- The pipeline now shows all seven stages, including **Perdu**. Staff can filter by source and stage, and see an ordered queue of open follow-ups with overdue dates. A lead record exposes source, owner, next action, notes, interaction chronology, stage/owner/source/action history, invitations, private photos and quote status history. Recovery from **Perdu** is visible and audited.
- Migration `031_acquisition_crm_hardening.sql` makes CRM reads require `acquisition.view` and direct writes require `acquisition.manage`; the invitation and conversion RPCs enforce the same grant. It validates tenant ownership for leads, tasks, quotes and guided media, records stage/owner/source/action/task/quote changes, preserves quote terms and history, and removes direct deletion policies. Contact matching on lead creation and patient conversion uses clinic-scoped normalized phone/email with transaction locks; repeat conversion returns the linked patient. Prospect quotes remain separate from clinical plan prices. A sent quote past its validity date becomes **Expire** when its lead record is loaded; an expired quote cannot be accepted.
- Intake submission now rejects revoked, expired and completed tokens, validates contact, concern and selected photo IDs, requires explicit contact consent and keeps an existing appointment/converted stage. Invitation revocation is available in the lead record. A completed intake cannot be resubmitted.
- The media Edge Function validates the token, active guided view, JPEG/PNG/WebP file signature, MIME type, 8 MB limit, one photo per view and three photos per session. Upload records photo consent. The public form can withdraw it; the Edge Function writes withdrawal evidence, removes Storage objects and media records. Staff signed URLs last fifteen minutes and are issued only while the latest guided-photo consent is active. The private bucket remains tenant scoped. A service-role-only cleanup function can remove withdrawn media left by a failed delete and abandoned, unsubmitted photos thirty days after invitation expiry. It still needs a trusted schedule/deployment; completed media retention needs clinic/legal policy confirmation.
- Prospect quotes use the clinic's configured currency. The database rejects cross-currency quote inserts and preserves the currency on each immutable quote version.
- Added `supabase/tests/acquisition_phase3.sql` for stage recovery/history, quote transitions and immutability, currency enforcement, revocation, repeat conversion/patient link, and assistant grant revocation. Demo browser journeys cover lost/recovery, follow-up, quote acceptance/history in a EUR clinic, revoked intake, duplicate contact routing, completed one-time intake and the four-step intake at a 390px phone viewport.
- A follow-up review tightened simultaneous phone/email contact locking, blocked origin/audit metadata changes, made tenant checks independent of the caller's read grant, and changed cleanup to fetch eligible media directly so old empty invitations cannot starve later files. Completed invitations cannot be revoked, preserving the token-based photo withdrawal path until expiry.
- Photo consent changes and media inserts now lock the same intake session. A media insert checks the latest consent and requires an intake still in progress, so a withdrawal or completion cannot leave a late accessible photo. Photo metadata cannot be rewritten after insert. Consent timestamps use wall-clock time with a stable ID tie-break; staff signed URLs and cleanup use the same latest-consent order. The legacy direct Storage delete policy was removed so photo deletion follows the withdrawal or cleanup path. The SQL suite includes service-role fixtures for upload before consent, metadata alteration, upload after withdrawal and upload after completion.
- A clinic created after the original photo seed migration now receives the three guided views automatically. Migration 031 backfills clinics that were created in the meantime; the SQL suite checks the new-clinic trigger and the synthetic clinic's views.

## Checks actually run

| Check | Result |
| --- | --- |
| `pnpm build` | Passed again on 2026-10-21 against the shared Phase 1–8 checkout |
| `pnpm e2e` in demo mode | Earlier full run: 6 passed, 5 authenticated checks skipped by target guards. Targeted Phase 3 run on 2026-10-21: 3 passed, including narrow-phone intake and no horizontal page overflow. |
| PostgreSQL SQL syntax parse with `pglast` | Passed for migration 031 and acquisition SQL suites; this does not execute PL/pgSQL bodies |
| Edge TypeScript parse through Vite transform | Passed for both acquisition Edge Functions |
| `node --check`, `git diff --check` | Passed |
| `./scripts/local-sql-tests.ps1` | Could not start: Docker Linux engine stopped because Windows Virtual Machine Platform was disabled. `wsl --install --no-distribution` succeeded on 2026-10-21; Windows reports the change requires a restart before it takes effect. |

## Runtime acceptance still required

After the pending Windows restart, confirm Docker's Linux engine starts, then run `./scripts/local-start.ps1 -Reset`, `./scripts/local-sql-tests.ps1`, and `./scripts/local-e2e.ps1` using synthetic fixtures only. Confirm migration 031 and all transactional suites, Auth/RLS behavior with assistant grant removal, signed Storage URLs, invalid/expired/revoked token responses, photo upload/withdrawal and cleanup in the local Edge runtime. The SQL and Edge behavior is **not runtime verified**. No hosted production Supabase or real patient data was touched.

The cleanup Edge Function is implemented but not scheduled or deployed. A trusted scheduler must call it with the service-role bearer key and repeat runs while batches remove files. Confirm a clinic-approved retention period for completed intake media before adding any completed-media deletion rule. Payment history export remains Phase 8 scope.

Phase 1–8 work was preserved in the shared checkout. No new worktree or restart was performed.
