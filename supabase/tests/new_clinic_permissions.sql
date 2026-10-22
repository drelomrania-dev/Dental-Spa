-- A clinic created after migration 029 receives usable but scoped staff roles.
begin;

do $test$
declare new_clinic uuid;
begin
  insert into clinics(name, currency, timezone)
  values ('QA new clinic permissions', 'MAD', 'Africa/Casablanca')
  returning id into new_clinic;

  if not exists (select 1 from role_permissions where clinic_id = new_clinic and role = 'administrator' and permission = '*') then
    raise exception 'New clinic has no administrator permission';
  end if;
  if not exists (select 1 from role_permissions where clinic_id = new_clinic and role = 'assistant' and permission = 'appointments.view' and scope = 'clinic') then
    raise exception 'New clinic assistant cannot view appointments';
  end if;
  if not exists (select 1 from role_permissions where clinic_id = new_clinic and role = 'assistant' and permission = 'payments.collect' and scope = 'own') then
    raise exception 'New clinic assistant payment scope is missing';
  end if;
  if not exists (select 1 from role_permissions where clinic_id = new_clinic and role = 'practitioner' and permission = 'patients.medical.view' and scope = 'assigned') then
    raise exception 'New clinic practitioner medical scope is missing';
  end if;
  if exists (select 1 from role_permissions where clinic_id = new_clinic and role <> 'administrator' and permission in ('reports.export', 'permissions.manage')) then
    raise exception 'New clinic staff received an administrative permission';
  end if;
end;
$test$;

rollback;
