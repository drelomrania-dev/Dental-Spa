# Playwright E2E runbook

This workspace contains a browser-test foundation for Dental Spa OS. It does not create users, seed production data, or modify application code.

## Install and run

```powershell
pnpm install
pnpm e2e:install
pnpm e2e
```

Without Supabase test configuration, the local runner starts Vite in local-data mode. Public shell and invalid-token tests run without credentials.

## Authenticated two-context tests

Use an isolated Supabase project or dedicated synthetic clinic. Never use real patient data. Set `E2E_SUPABASE_URL`, `E2E_SUPABASE_ANON_KEY`, `E2E_ADMIN_EMAIL`, `E2E_ADMIN_PASSWORD`, `E2E_ASSISTANT_EMAIL`, and `E2E_ASSISTANT_PASSWORD`, then run `pnpm e2e`. For a deployed test target, set `E2E_BASE_URL`. Do not point this suite at production until isolated test accounts and cleanup procedures are approved.

## Current coverage

- Public booking shell at `/book/consultation`.
- Safe invalid-token states for booking management and staff invitations.
- Administrator login shell.
- Administrator report access.
- Assistant denial of reports and allowance for appointments.
- Independent browser sessions for administrator and assistant.

Authenticated checks verify UI route structure, not database authorization proof. Pair them with the Supabase SQL/RLS suites and a staging recovery drill before release.
