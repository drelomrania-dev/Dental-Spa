# Dental Spa OS — Release readiness

Updated: 2026-10-18

## Verified in the repository

- `pnpm build` passes with the official project command.
- The production bundle is route-split and the optional Firebase integration is lazy-loaded.
- `pnpm-workspace.yaml` explicitly allows the dependency build scripts required by the project.
- Role-aware routes use the permission context for assistant and practitioner access, with administrator fallback.
- Supabase schema, migrations and transactional SQL suites are versioned under `supabase/`.
- The working tree has no uncommitted user changes outside the current audit edits.

## Verified in the connected Supabase project

- The `dental Spa OS` project is connected and the production `main` branch is present.
- Supabase Advisor currently reports no security or performance issues.
- Email authentication is enabled.
- Leaked-password protection is disabled because the project is on the Free plan and the feature requires Pro or above.
- Scheduled project backups are unavailable on the Free plan.
- Migration `028_security_hardening.sql` was applied successfully to the connected production project on 2026-10-18 after the published-booking-slug preflight returned zero rows.

## Required before real patient use

1. Complete browser E2E with a real invited assistant or practitioner account.
2. Run the full operational journey with two staff accounts and cash-session isolation.
3. Decide whether to upgrade Supabase or establish an external backup and restore procedure.
4. Configure production SMTP if automated confirmation or notification emails are required.
5. Complete clinic/legal review of Moroccan receipt wording, numbering and retention.
6. Run the simultaneous public-booking load test and optional edge/WAF abuse test.

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

The repository release can be built and deployed without applying this migration, but production database hardening is not complete until this checklist has passed. The connected production project has now passed the slug preflight and migration application steps; staging regression execution remains recommended before broader rollout.

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

The MVP is technically deployable and the core booking, acquisition, clinical and finance workflows are implemented. It is not yet operationally cleared for real patient or financial data until the second-account E2E, recovery strategy and clinic/legal checks are complete.
