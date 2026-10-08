# Supabase migration plan

The Supabase MCP connection is configured for the Dental Spa project. The application remains localStorage-first until the schema and access policies are reviewed.

## Current status

- MCP server: connected and authenticated.
- Local mode: still the default.
- Schema draft: `supabase/schema.sql`.
- RLS: enabled with no permissive policies, intentionally failing closed.

## Safe migration sequence

1. Review `supabase/schema.sql` in the Supabase SQL editor.
2. Create a non-production branch/project for acceptance testing.
3. Apply the schema and confirm all RLS tables are inaccessible without an authenticated clinic member.
4. Configure Firebase/Supabase Auth identity mapping and clinic membership.
5. Add clinic-scoped policies for administrator, assistant, and practitioner permissions.
6. Build a Supabase adapter behind the existing data-store interface.
7. Run booking race, payment idempotency, confidentiality, and persistence tests against the branch.
8. Keep the current localStorage mode until the branch passes acceptance testing; only then enable a reviewed Supabase adapter.

Do not import real patient data until backups, retention, audit logging, and access review are complete.
