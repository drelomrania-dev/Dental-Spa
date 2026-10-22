# Phase 7 — consent and appointment/installment reminders

Updated: 2026-10-20 (Africa/Casablanca)

## Implemented in the shared checkout

- Migration `035_reminders_phase7.sql` adds per-clinic reminder rules, versioned message templates, explicit per-patient/per-channel consent with append-only evidence, an idempotent outbox and delivery-attempt history. All six email/WhatsApp templates start as drafts. Only a clinic settings manager can approve them. The assistant receives `reminders.manage` by default; a clinic can revoke it. All writes/read snapshots use permission-gated RPCs and the new tables deny direct authenticated access.
- Appointment reminders default to 24 hours before the appointment. Installment reminders default to three days before and at 09:00 on the due date in the clinic timezone. Each rule can be changed or disabled. The source is the normalized appointment ID/start time or Phase 6 installment ID/current due date, never the legacy document record. Installment reminders require an unpaid installment and outstanding account balance.
- Queueing requires an approved template, affirmative channel consent and a current patient email/phone. A unique source-version key prevents duplicate rows on repeated scans. A cancelled row can be reactivated if consent or a template is restored while the source is still valid. Appointment cancellation/rescheduling, installment rescheduling/payment, consent withdrawal, contact change, template edits and rule changes invalidate queued/retry rows. Fake dispatch rechecks validity and due time. The SQL migration also exposes a service-role-only `queue_due_reminders_all()` entry point for a future trusted scheduler; no scheduler is deployed yet.
- Templates accept only `{clinic}`, `{first_name}`, `{date}` and `{time}`. Appointment reasons and clinical notes never enter a message. Reminder delivery events are separate from manual Acquisition CRM interactions. The Rappels page supports consent evidence, rule setup, draft/approval, the outbox, a simulated send/failure, retry status and delivery history.
- The fake sender changes only local database/demo state. It makes **no email, WhatsApp, or provider network call**. The provider boundary is the trusted server-side worker: after clinic approval, it would claim due outbox rows, revalidate source/consent under transaction locks, submit an approved template to an approved provider, then record a provider result and retry schedule. Provider credentials and delivery must never be placed in the browser module. The current `fake_dispatch_reminder` RPC is for synthetic acceptance only.
- Added `supabase/tests/reminders_phase7.sql` for defaults, opt-in and template approval, unsupported variables, queue idempotency, retry delay, withdrawal, role removal, cross-clinic isolation, reschedule, cancellation and paid-installment invalidation. Added a demo browser journey and a guarded local Auth browser permission check.

## Checks actually run

| Check | Result |
| --- | --- |
| `pnpm build` | Passed after Phase 7 changes |
| `pnpm e2e --reporter=line` | 11 demo/public tests passed; 10 local Auth/backend checks skipped by target guards, including the Phase 7 Auth spec |
| Targeted Phase 7 demo Playwright journey | Passed: no queue before consent/template approval; appointment and installment queue; no clinical reason in message; fake failure; consent withdrawal cancels both rows |
| `pglast` | Migration top-level SQL, all 13 PL/pgSQL function bodies and the new transactional SQL suite parsed. This does not execute SQL against Postgres. |
| `node --check` | Passed for `src/services/reminders.js` and both Phase 7 browser specs |
| `./scripts/local-sql-tests.ps1` | Could not start: Docker engine pipe `//./pipe/docker_engine` unavailable; the local database container is not running |
| `git diff --check` | Passed; Git reported existing local LF/CRLF conversion warnings |

## Runtime acceptance still required

After the already identified Windows/WSL2 restart makes the Docker Linux engine available, run `./scripts/local-start.ps1 -Reset`, `./scripts/local-sql-tests.ps1`, and `./scripts/local-e2e.ps1` with synthetic fixtures. Confirm fresh migration 035, all 20 transactional SQL suites, role and tenant isolation, appointment and installment invalidation triggers, retry behavior, and the authenticated Phase 7 browser check. The SQL/Auth integration is **not runtime accepted**. No restart, hosted production change or real patient delivery was performed.

The service-role queue endpoint is ready for a trusted schedule, but no schedule is configured. Until then the Rappels page's **Préparer les rappels dus** action queues due items. Simulated delivery is manual. Before a real provider is enabled, the clinic must approve sender identities, message wording/language, WhatsApp and email consent evidence, delivery window, retry/escalation policy, retention, and the provider agreement. A real delivery worker must be built and tested with provider callbacks and transactional final validation; the fake sender cannot be used for real patient messaging.

Phase 1–6 uncommitted work and the separate Phase 3 corrections were preserved in the shared checkout.
