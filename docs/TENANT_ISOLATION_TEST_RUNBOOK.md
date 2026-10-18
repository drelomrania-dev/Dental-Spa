# Two-clinic tenant-isolation regression

Status: **template pending controlled fixtures**

The existing SQL acceptance tests in `supabase/tests/` run against a development
database with one pre-existing administrator and roll back their fixtures. They
do not provide a safe, portable way to create a second clinic and its Auth user:

- `bootstrap_first_admin()` is intentionally limited to an empty installation.
- `clinics` has an authenticated select/update policy, but no general
  authenticated insert policy.
- `staff_profiles` is clinic-scoped and has no authenticated insert policy.
- Creating `auth.users` and assigning both staff memberships requires a
  controlled service-role fixture step that is not part of this repository's
  SQL test harness.

For that reason, `supabase/tests/tenant_isolation_two_clinics.template.sql` is a
reviewable test template, not a claimed passing test. It must not be converted
into a runnable test by guessing fixture IDs or bypassing RLS with ad-hoc SQL.

## Fixture checklist

Prepare a disposable development or staging project through the approved
service-role/admin procedure:

1. Create two clinics, `clinic_a` and `clinic_b`.
2. Create two distinct Auth users, `admin_a` and `admin_b`.
3. Create active administrator staff rows mapping `admin_a → clinic_a` and
   `admin_b → clinic_b`.
4. Create one uniquely identifiable patient and one legacy `app_records` row in
   each clinic.
5. Record the IDs and app IDs in the template placeholders.
6. Confirm that no fixture is production data and that the SQL run can be
   rolled back.

## Assertions required for a pass

Run the template once as `admin_a` and once as `admin_b`, using the existing
pattern of `request.jwt.claim.sub` plus `set local role authenticated`.

For each identity, verify that:

- `current_clinic_id()` resolves to that user’s clinic.
- Only one clinic is visible through the `clinics` policy.
- The user can read its own patient and legacy record.
- The user cannot read the other clinic’s patient or legacy record.
- The same positive/negative boundary is covered for appointments,
  `clinical_visits`, `treatment_plans`, finance tables, audit events, leads, and
  staff profiles.

The test is complete only when both identities pass the mirrored assertions and
the transaction is rolled back. Until then, the tenant-isolation item remains
open in the release audit.
