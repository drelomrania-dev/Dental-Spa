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

## Required before real patient use

1. Complete browser E2E with a real invited assistant or practitioner account.
2. Run the full operational journey with two staff accounts and cash-session isolation.
3. Decide whether to upgrade Supabase or establish an external backup and restore procedure.
4. Configure production SMTP if automated confirmation or notification emails are required.
5. Complete clinic/legal review of Moroccan receipt wording, numbering and retention.
6. Run the simultaneous public-booking load test and optional edge/WAF abuse test.

## Release conclusion

The MVP is technically deployable and the core booking, acquisition, clinical and finance workflows are implemented. It is not yet operationally cleared for real patient or financial data until the second-account E2E, recovery strategy and clinic/legal checks are complete.
