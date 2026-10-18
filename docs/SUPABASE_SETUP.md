# Supabase production setup

The production application uses Supabase Auth, PostgreSQL, RLS, Storage and Edge Functions. LocalStorage remains available only as a development fallback when `VITE_DATA_BACKEND` is not set to `supabase`.

## Current status

- MCP server: connected and authenticated.
- Production backend: active and used by the deployed application.
- Schema and migrations: versioned in `supabase/schema.sql` and `supabase/migrations/`.
- RLS: enabled with clinic-scoped role policies and RPC-only boundaries for sensitive patient and finance data.
- Acceptance suites: versioned in `supabase/tests/` and documented in `docs/MVP_TEST_REPORT.md`.

## Safe environment and release sequence

1. Apply migrations to a non-production Supabase project first.
2. Run the SQL acceptance suites and confirm rollback cleanup.
3. Verify Auth redirect URLs, SMTP settings, leaked-password protection and Edge Function secrets.
4. Run the two-account browser E2E and the full operational journey.
5. Confirm backups, restoration ownership, monitoring and incident procedures.
6. Promote the reviewed migration set to production and record the release.

Do not import real patient data until backups, retention, audit logging, access review and clinic/legal validation are complete.
