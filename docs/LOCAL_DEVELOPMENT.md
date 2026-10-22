# Full local development and acceptance

The browser's localStorage mode is useful for UI previews. Use this local Supabase
stack for Auth, clinic permissions, booking, clinical, finance and CRM acceptance.
It uses synthetic data only and does not connect to the hosted project.

## Prerequisites

- Docker Desktop with a running Linux engine and WSL2 virtualization on Windows.
- Node.js, pnpm and the Supabase CLI through `pnpm dlx supabase`.
- Ports 4173 and 54320–54324 available.

Windows may require a restart after enabling WSL2 and the virtual machine
platform. Confirm `docker info` succeeds before starting Supabase.

## Start from a fresh local database

From PowerShell in the repository root:

```powershell
./scripts/local-start.ps1 -Reset
./scripts/local-sql-tests.ps1
./scripts/local-e2e.ps1
```

`-Reset` destroys only the **local** Supabase database and reapplies migrations.
Omit it to keep the current local database. The start script checks that the API
URL is loopback on port 54321 before it creates any fixtures. It creates two
synthetic clinics, four Auth users, staff memberships, a practitioner, a
service, a booking link and one patient per clinic. Credentials go only into
the ignored `.local-fixtures.json`; the service-role key stays in process memory.
It then checks all four sign-ins, role-to-clinic membership, patient isolation,
the private Storage bucket and the local `staff-invite-link` Edge Function.
If any check fails, fix the local stack before continuing to SQL or browser tests.

Run the app separately for manual exploration with:

```powershell
./scripts/local-dev.ps1
```

The app opens at `http://127.0.0.1:4173`. The local Auth and Storage API is at
`http://127.0.0.1:54321`; local Studio and mail testing use the URLs printed by
Supabase. The scripts set process environment variables, so they do not replace
an existing `.env.local` used for another environment. Stop this manual app
server before `local-e2e.ps1`; browser acceptance starts its own fresh server
and refuses to reuse a server with unknown backend settings.

## Acceptance boundaries

- SQL suites run in transactions and roll their test records back. The
  `tenant_isolation_two_clinics.template.sql` remains a separate controlled
  review until its full cross-table assertions are automated.
- The authenticated Playwright suite uses the generated clinic A administrator
  and assistant plus clinic B administrator. It checks route permissions and
  patient separation in the browser. Public tests use synthetic booking pages.
- The local fixture accounts are test accounts, not staff invitations. Run the
  invitation and practitioner-claim workflow separately in the browser.
- Never copy `.local-fixtures.json` into the repository, a release record, or a
  hosted project. Reset the local database to clean up fixtures.

The hosted Supabase upgrade, backup/restore process, live email/WhatsApp
delivery and legal review remain release decisions after local acceptance.
