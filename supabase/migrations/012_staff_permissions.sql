create table if not exists role_permissions (
  clinic_id uuid not null references clinics(id) on delete cascade,
  role text not null check(role in ('administrator','assistant','practitioner')),
  permission text not null,
  scope text not null default 'clinic' check(scope in ('own','assigned','clinic')),
  created_at timestamptz not null default now(),
  primary key(clinic_id,role,permission)
);

alter table role_permissions enable row level security;
drop policy if exists role_permissions_member_select on role_permissions;
create policy role_permissions_member_select on role_permissions for select to authenticated
using(clinic_id=current_clinic_id());
drop policy if exists role_permissions_admin_insert on role_permissions;
create policy role_permissions_admin_insert on role_permissions for insert to authenticated
with check(clinic_id=current_clinic_id() and current_staff_role()='administrator');
drop policy if exists role_permissions_admin_update on role_permissions;
create policy role_permissions_admin_update on role_permissions for update to authenticated
using(clinic_id=current_clinic_id() and current_staff_role()='administrator')
with check(clinic_id=current_clinic_id() and current_staff_role()='administrator');
drop policy if exists role_permissions_admin_delete on role_permissions;
create policy role_permissions_admin_delete on role_permissions for delete to authenticated
using(clinic_id=current_clinic_id() and current_staff_role()='administrator');

insert into role_permissions(clinic_id,role,permission,scope)
select c.id,p.role,p.permission,p.scope
from clinics c cross join (values
  ('administrator','*','clinic'),
  ('assistant','appointments.view','clinic'),('assistant','appointments.create','clinic'),('assistant','appointments.edit','clinic'),('assistant','appointments.cancel','clinic'),
  ('assistant','patients.basic.view','clinic'),('assistant','patients.create','clinic'),('assistant','patients.edit','clinic'),
  ('assistant','services.view','clinic'),('assistant','payments.collect','own'),('assistant','payments.receipt','own'),('assistant','payments.view.own','own'),
  ('assistant','priceRequests.create','own'),('assistant','sessions.own','own'),('assistant','acquisition.view','clinic'),('assistant','acquisition.manage','clinic'),
  ('practitioner','appointments.view','assigned'),('practitioner','appointments.edit','assigned'),
  ('practitioner','patients.basic.view','assigned'),('practitioner','clinical.view','assigned'),('practitioner','clinical.edit','assigned'),
  ('practitioner','plans.create','assigned'),('practitioner','services.view','clinic'),('practitioner','acquisition.view','clinic')
) as p(role,permission,scope)
on conflict(clinic_id,role,permission) do update set scope=excluded.scope;

create or replace function has_permission(p_permission text)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select exists(
    select 1 from staff_profiles s
    where s.id=auth.uid() and s.active=true and (
      s.role='administrator' or exists(
        select 1 from role_permissions rp where rp.clinic_id=s.clinic_id and rp.role=s.role and rp.permission=p_permission
      )
    )
  )
$$;

create or replace function current_access_context()
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select jsonb_build_object(
    'id',s.id,'clinicId',s.clinic_id,'displayName',s.display_name,'role',s.role,
    'permissions',case when s.role='administrator' then jsonb_build_array('*') else coalesce((select jsonb_agg(jsonb_build_object('permission',rp.permission,'scope',rp.scope) order by rp.permission) from role_permissions rp where rp.clinic_id=s.clinic_id and rp.role=s.role),'[]'::jsonb) end
  ) from staff_profiles s where s.id=auth.uid() and s.active=true limit 1
$$;

revoke all on function has_permission(text) from public,anon,authenticated;
revoke all on function current_access_context() from public,anon,authenticated;
grant execute on function has_permission(text) to authenticated;
grant execute on function current_access_context() to authenticated;
