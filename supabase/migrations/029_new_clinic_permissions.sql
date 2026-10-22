-- New clinics must receive the same starting role permissions as clinics that
-- existed when migration 012 ran. Administrators can still change them later.
create or replace function seed_clinic_role_permissions()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into role_permissions(clinic_id, role, permission, scope)
  select new.id, defaults.role, defaults.permission, defaults.scope
  from (values
    ('administrator', '*', 'clinic'),
    ('assistant', 'appointments.view', 'clinic'),
    ('assistant', 'appointments.create', 'clinic'),
    ('assistant', 'appointments.edit', 'clinic'),
    ('assistant', 'appointments.cancel', 'clinic'),
    ('assistant', 'patients.basic.view', 'clinic'),
    ('assistant', 'patients.create', 'clinic'),
    ('assistant', 'patients.edit', 'clinic'),
    ('assistant', 'services.view', 'clinic'),
    ('assistant', 'payments.collect', 'own'),
    ('assistant', 'payments.receipt', 'own'),
    ('assistant', 'payments.view.own', 'own'),
    ('assistant', 'priceRequests.create', 'own'),
    ('assistant', 'sessions.own', 'own'),
    ('assistant', 'acquisition.view', 'clinic'),
    ('assistant', 'acquisition.manage', 'clinic'),
    ('practitioner', 'appointments.view', 'assigned'),
    ('practitioner', 'appointments.edit', 'assigned'),
    ('practitioner', 'patients.basic.view', 'assigned'),
    ('practitioner', 'patients.medical.view', 'assigned'),
    ('practitioner', 'patients.medical.edit', 'assigned'),
    ('practitioner', 'clinical.view', 'assigned'),
    ('practitioner', 'clinical.edit', 'assigned'),
    ('practitioner', 'plans.create', 'assigned'),
    ('practitioner', 'services.view', 'clinic'),
    ('practitioner', 'acquisition.view', 'clinic')
  ) as defaults(role, permission, scope)
  on conflict (clinic_id, role, permission) do nothing;
  return new;
end;
$$;

revoke all on function seed_clinic_role_permissions() from public, anon, authenticated;
drop trigger if exists clinic_default_role_permissions on clinics;
create trigger clinic_default_role_permissions
after insert on clinics for each row execute function seed_clinic_role_permissions();
