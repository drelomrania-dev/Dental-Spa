# Phase 10 — local acceptance status

Updated: 2026-10-21 (Africa/Casablanca)

## Current result

**Local runtime acceptance is blocked pending a Windows restart.** In the earlier Phase 10 check, WSL2 could not start, `docker` was absent from PATH, and the Docker Desktop executable's read-only `info` command could not connect to the missing `//./pipe/docker_engine`. A later Phase 3 machine check launched Docker Desktop; its backend reported `WslVirtualMachinePlatformNotEnabled`. Phase 3 then ran `wsl --install --no-distribution` successfully, and Windows stated that a restart is required for the change to take effect. No restart has occurred in this acceptance phase, and Docker Linux engine availability has not been reverified after one.

The shared checkout and its uncommitted Phase 1–9 work were preserved. No local Supabase reset, hosted production change, real patient data, or real message delivery occurred.

## Checks actually run

| Check | Result |
| --- | --- |
| Phase 1–9 handoffs and `LOCAL_DEVELOPMENT.md` | Reviewed before testing |
| Docker/WSL inspection | Earlier Phase 10 `docker.exe info` could not connect to the missing engine pipe; later Phase 3 reported `WslVirtualMachinePlatformNotEnabled` and a successful `wsl --install --no-distribution` requiring restart |
| `pnpm build` | Passed; Vite transformed 1,697 modules |
| `pnpm e2e --reporter=line` in demo mode | 20 passed; 11 local/Auth/backend tests skipped by guards (31 total) |
| `node --check` on local fixture/verifier and booking-race files | Passed |
| PowerShell parser on local scripts; config TOML parse | Passed |
| `pglast` top-level parse of 36 migrations and 21 selected SQL suites | Passed; does not execute PL/pgSQL or database behavior |
| Baseline and suite structure | `001_initial_schema.sql` matches `schema.sql` byte for byte; all 21 selected SQL suites contain `BEGIN` and `ROLLBACK` |
| `git diff --check` | Passed; Git printed LF/CRLF conversion warnings |

Static review found that `e2e/booking-race-local.spec.js` requested the slug `consultation` while the synthetic fixture publishes `local-consultation`. The test now uses the fixture slug in its page, slot and booking RPC calls. Its two-client HTTP race still requires local Supabase and has **not** run.

## Runtime work remaining after the prerequisite

After the human completes the required Windows restart and Docker Desktop's Linux engine is running, confirm `docker info`, then follow `LOCAL_DEVELOPMENT.md` using only synthetic fixtures:

1. `./scripts/local-start.ps1 -Reset`: fresh migrations 001–036, two-clinic fixture creation, four Auth sign-ins, tenant isolation, private bucket and invitation Edge health.
2. `./scripts/local-sql-tests.ps1`: all 21 transactional suites. The two-clinic template remains a separate controlled review until its full cross-table assertions are automated.
3. `./scripts/local-e2e.ps1`: local verifier and all guarded authenticated/browser tests, with explicit results for staff invitation/claim, private intake upload/withdrawal and invalid/revoked/expired token paths.
4. The two-client booking race, secure management-token reschedule/cancel and full synthetic lead → booking → patient → visit/plan → price decision → installment/payment → cash → reporting/reminder journey against local Supabase. Confirm two-clinic and multi-role boundaries and cleanup.

Investigate failures and rerun affected checks before marking any module locally accepted. The 2026-10-10 hosted smoke evidence belongs to an earlier deployment and does not verify this checkout. Remote verification and production release remain separate gates. The fake reminder sender and production deployment stay inactive; provider, backup/restore, clinic workflow and Moroccan legal/retention decisions remain open.
