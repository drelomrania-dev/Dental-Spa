# Phase 1 — local platform status

Updated: 2026-10-20 (Africa/Casablanca)

## Implemented in the shared checkout

- The fresh-database baseline is `supabase/migrations/001_initial_schema.sql`, byte-for-byte equal to the existing `supabase/schema.sql`. Migrations 002–029 are ordered for local reset. Migration 029 supplies role defaults to clinics created after the original role migration, with a transactional SQL check.
- `supabase/config.toml` enables local Postgres, Auth, Storage and Edge Runtime on the standard loopback ports. `staff-invite-link` accepts the local app origin on port 4173.
- `scripts/local-start.ps1 -Reset` starts local Supabase, resets only the local database, seeds two synthetic clinics and four Auth accounts, and runs `scripts/verify-local.mjs`. The verifier checks Auth sign-in, staff membership, patient isolation, the private Storage bucket and the invitation Edge Function. Local fixture credentials are written only to ignored `.local-fixtures.json`; the service key stays in process memory.
- `scripts/local-sql-tests.ps1` runs all 13 non-template transactional SQL suites. `scripts/local-e2e.ps1` checks the running local target, runs the verifier, and starts a fresh local-backend browser server. The authenticated browser suite includes a two-clinic patient boundary check.
- The previously started agenda change adds list, week and month views with a demo-mode browser check.

## Checks run on 2026-10-20

| Check | Result |
|---|---|
| `pnpm build` | Passed |
| `pnpm e2e` without local Supabase | 4 public/demo checks passed; 4 authenticated checks skipped by their configured target guards |
| Node syntax, PowerShell parser, Supabase config TOML parse, `git diff --check` | Passed |
| Baseline comparison and SQL suite structure | Baseline matches `schema.sql`; all 13 selected SQL suites have transaction begin and rollback |
| `./scripts/local-start.ps1 -Reset` | Stopped before Supabase start: Docker engine pipe `//./pipe/docker_engine` is unavailable |

## Runtime acceptance still required

Windows needs the already identified restart to enable WSL2 virtualization and the Docker Linux engine. No restart was performed in this phase. After it is available, run the commands in `docs/LOCAL_DEVELOPMENT.md` in order and record the actual migration, SQL, Auth/Storage/Function and authenticated browser results. The local stack has not yet been runtime accepted, and no production Supabase change was made.
