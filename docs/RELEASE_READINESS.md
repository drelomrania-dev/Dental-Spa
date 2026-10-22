# Dental Spa OS — Release readiness

Updated: 2026-10-21 (Africa/Casablanca)

Current gate: **not cleared for real patient or financial data**. The Phase 1–9 shared checkout has 20 passing public/demo browser checks, but local Supabase runtime acceptance remains blocked. Docker Desktop reported `WslVirtualMachinePlatformNotEnabled`; `wsl --install --no-distribution` succeeded and requires a Windows restart before the Linux engine can be checked again. See `PHASE_10_STATUS.md` for actual checks and prerequisites.

## Verified in the repository

- `pnpm build` passes with the official project command.
- The production bundle is route-split and the optional Firebase integration is lazy-loaded.
- `pnpm-workspace.yaml` explicitly allows the dependency build scripts required by the project.
- Role-aware routes use the permission context for assistant and practitioner access, with administrator fallback.
- Supabase schema, migrations through 036 and transactional SQL suites are versioned under `supabase/`. The Phase 1–9 implementation is in the repository; local runtime acceptance remains pending.
- Phase 10 build and 20 public/demo browser checks pass; 11 local/Auth/backend checks are skipped until the local stack runs. SQL parsing has not executed migrations, PL/pgSQL or RLS.

## Historical connected-project evidence (2026-10-18)

These observations were recorded before migrations 029–036 and do not verify the current checkout or current production state:

- The `dental Spa OS` project is connected and the production `main` branch is present.
- Supabase Advisor reported no security or performance issues at that time.
- Email authentication is enabled.
- Leaked-password protection is disabled because the project is on the Free plan and the feature requires Pro or above.
- Scheduled project backups are unavailable on the Free plan.
- Migration `028_security_hardening.sql` was applied successfully to the connected production project on 2026-10-18 after the published-booking-slug preflight returned zero rows.

## Required before real patient use

1. Complete Phase 10 fresh local migrations 001–036, all 21 SQL suites, Auth/RLS/Storage/Edge checks, guarded browser tests and the synthetic two-clinic journey after WSL2/Docker is available.
2. Separately verify the intended remote release target, including invited staff accounts, cash-session isolation and booking concurrency, before any production migration or deployment decision.
3. Decide whether to upgrade Supabase or establish a tested external backup and restore procedure.
4. Build and approve a trusted reminder provider worker, sender identities, consent evidence, templates, delivery policy and retention before any real email or WhatsApp delivery. The current sender is fake.
5. Complete clinic/legal review of Moroccan receipt wording, tax identifiers, numbering, clinical and financial retention, and operating procedures.
6. Configure production SMTP, monitoring, domain and recovery procedures as required for approved operation.

## Migration 028 application checklist

Migration `supabase/migrations/028_security_hardening.sql` is fail-closed by design. Apply it only through the approved Supabase SQL/migration path after completing these checks:

1. Export or otherwise verify a recoverable snapshot of the target database. On the Free plan, scheduled Supabase backups are unavailable; do not treat the migration as recoverable until an external backup/restore path has been tested or the plan is upgraded.
2. Run the preflight query below in the target project. Any returned row must be resolved before applying migration 028; the migration intentionally aborts on blank or duplicate published slugs.

```sql
select lower(trim(data->>'slug')) as slug, count(*) as published_count
from public.app_records
where collection = 'bookingLinks'
  and coalesce((data->>'published')::boolean, false) = true
group by lower(trim(data->>'slug'))
having nullif(lower(trim(data->>'slug')), '') is null
    or count(*) > 1;
```

3. Apply the migration in staging first, then run `supabase/tests/security_hardening.sql` with the project’s SQL test procedure.
4. Verify one assigned practitioner can complete a clinical visit while an unassigned practitioner is denied, and verify public booking still resolves its published slug.
5. Record the migration result and recovery evidence in the release log before enabling real patient traffic.

The 2026-10-18 connected project passed the slug preflight and migration 028 application steps. This is historical evidence; staging and remote regression execution for the current checkout remain pending.

## Automated release gate

Run `pnpm verify:release` locally. The same command runs in `.github/workflows/release-readiness.yml` on pull requests and pushes to `main`; it uses local-data mode and does not require production secrets. Authenticated E2E remains a separate staging-only gate described in `docs/E2E_RUNBOOK.md`.

## Staff invitation Edge Function configuration

The `staff-invite-link` function must be configured with these server-side Supabase Edge Function variables before invitation links are used:

- `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are required by the runtime; the service-role key must never be exposed to the browser.
- `PUBLIC_APP_URL` should be the canonical production origin, for example `https://dental-spa-taupe.vercel.app`.
- `ALLOWED_ORIGINS` may contain a comma-separated union of additional exact origins used by approved preview or staging deployments. Values are normalized to URL origins; paths and credentials are not valid allowlist entries.

The function combines configured origins with its safe localhost and production defaults. It returns `Access-Control-Allow-Origin` only for an allowed request origin; disallowed origins receive no CORS allow header. The frontend derives the production origin from `VITE_PUBLIC_APP_URL` and URL-encodes the invitation token in `/join/<token>`.

Release checks for this flow must cover anonymous `401`, non-administrator `403`, invalid redirect rejection, a valid administrator invitation, and a browser request from each approved production/staging origin. Updating `PUBLIC_APP_URL` or `ALLOWED_ORIGINS` requires redeploying the Edge Function configuration; this repository change does not update Supabase settings automatically. The reproducible deployment and status-only smoke-check procedure is in `docs/SUPABASE_EDGE_FUNCTION_DEPLOYMENT.md`.

## Release conclusion

The core workflows are implemented in code, but the current checkout is not locally runtime accepted or remotely verified. Production deployment, real reminder delivery and use with real patient or financial data remain inactive pending the gates above.
