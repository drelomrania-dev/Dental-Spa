# Dental Spa OS Control Room

This document is the operating protocol for the central audit/progress station.

## Lanes

- **Audit Station** — central coordinator: inspect progress, choose the next safe mission, check blockers, and sequence phases.
- **UX/UI** — user flows, accessibility, responsive behavior, visual consistency, and usability improvements.
- **Feature Delivery** — highest-priority unfinished product features, including application code, migrations, tests, and documentation.
- **QA & Security** — regression checks, privacy/access control, migration safety, production risks, and release quality gates.
- **Releases & Deployment** — the only release gate: validate a coherent change set, commit intended changes, push to `origin/main`, deploy, and record rollback notes.

## Phase loop

1. Audit Station reads `docs/MVP_PROGRESS.md`, `docs/MVP_IMPLEMENTATION_PLAN.md`, the current Git status, and the latest lane handoffs.
2. Assign one focused mission per available lane. Do not start overlapping work on the same files without coordination.
3. Each lane preserves unrelated user changes and verifies its work before declaring completion.
4. Completed work is handed to Releases & Deployment with the template below.
5. Releases & Deployment runs the quality gate. If clean and coherent, it commits, pushes, and deploys. If not, it records the blocker and returns the work to the responsible lane.
6. After a successful release, Audit Station records the result and starts the next highest-priority phase.

## Release handoff template

```text
Lane:
Mission:
Summary:
Changed files:
Checks run and results:
Known risks:
Database/migration impact:
Deployment notes:
Recommended next mission:
```

## Release gate

Releases & Deployment must not discard unrelated changes or use destructive resets. It must confirm the intended diff, run the strongest available checks, and record:

- commit SHA;
- push result and remote branch;
- deployment target and result;
- migrations or environment changes;
- rollback procedure;
- any follow-up mission for Audit Station.

## Current chat routing

The Codex sidebar section **Dental Spa OS — Control Room** contains this Audit Station, Feature Delivery Lane, and Releases & Deployment Lane. UX/UI and QA/Security remain planned lanes until the desktop policy permits creating additional specialist chats.
