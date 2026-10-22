# Dental Spa OS — MVP test report

Updated: 2026-10-21 (Africa/Casablanca)
Environment: shared checkout, local Vite/browser-storage demo. No hosted backend changes or real patient data.

## Current checkout checks

| Check | Actual result | Meaning |
| --- | --- | --- |
| `pnpm build` | Passed; 1,697 modules transformed | Client bundle compiles |
| `pnpm e2e --reporter=line` | **20 passed, 11 skipped** (31 total) | Public/demo Chromium checks pass; local Auth/backend guards skipped |
| Phase 9 route audit | Passed at 390px and 1440px across 17 internal and 4 public entry/error routes | No page-level horizontal overflow, unnamed visible controls or uncaught page errors in those baseline states |
| Phase 9 dialog audit | Passed at 390px and 1440px for 9 key CRM, patient, agenda, clinical, approval and cash dialogs | Visible form controls named; focus enters dialog, Escape closes and restores focus |
| Failed-save recovery | Passed with injected demo storage failure | CRM dialog displayed the failure, retained input and saved after retry |
| Demo role denial | Passed | Assistant was denied clinical, reports, payment history and settings routes; agenda remained available |
| Integrated synthetic journey | Passed at 390px | Lead/follow-up → booking → agenda/patient → visit/plan → price approval → cash payment/session → report/reminder consent |
| `node --check` for Phase 9 specs; `git diff --check` | Passed; Git emitted existing local LF/CRLF conversion warnings | Syntax/whitespace only |
| Docker/WSL prerequisite | Phase 10 found no running engine; later Phase 3 launched Docker Desktop, saw `WslVirtualMachinePlatformNotEnabled`, and completed `wsl --install --no-distribution` | Windows requires a restart; local Supabase runtime checks remain blocked |
| Phase 10 SQL structure/parse | 36 migrations and 21 selected transactional SQL suites parsed; baseline matches `schema.sql` | Syntax/structure evidence only; no migration or PL/pgSQL execution |
| Phase 10 local script syntax | Node, PowerShell and TOML checks passed | Scripts parse; Auth/Storage/Edge behavior remains unverified |

Existing Phase 1–8 status files record their own build/demo/static results, SQL syntax parsing and the earlier Docker engine blocker. Phase 10 corrected the booking-race test slug to match the synthetic fixture; the HTTP race has not run. Parsing SQL or displaying a demo screen does **not** execute migrations, PL/pgSQL, RLS or Edge Functions.

## Pending local acceptance

After the human completes the required Windows restart and Docker Desktop's Linux engine is running, run from the repository root:

```powershell
./scripts/local-start.ps1 -Reset
./scripts/local-sql-tests.ps1
./scripts/local-e2e.ps1
```

Record actual fresh migration results, all 21 transactional SQL suites, Auth sign-in and invitation claims, two-clinic/role denial, private Storage and Edge token/media behavior, booking management and two-client race, patient/clinical/finance/reminder/report RPC results, audited exports and the full synthetic clinic browser journey. The current 11 guarded browser tests must run against this target. The exact checklist and current blocker are in `PHASE_10_STATUS.md` and `LOCAL_DEVELOPMENT.md`.

## Historical evidence boundary

The previous report dated 2026-10-10 described hosted Supabase and production smoke checks on an earlier code/deployment state. Those results were useful historical evidence for booking, CRM, finance and access-control work, but they do not accept the Phase 1–9 implementation or migrations 029–036. No current production readiness, complete EHR capability or real message delivery is claimed.
