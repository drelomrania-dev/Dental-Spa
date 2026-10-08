-- Secure document-compatible persistence for the existing React MVP.
-- This keeps the current domain objects intact while the normalized schema evolves.

create table if not exists app_records (
  clinic_id uuid not null references clinics(id) on delete cascade,
  collection text not null,
  id text not null,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (clinic_id, collection, id)
);

create index if not exists app_records_collection_idx on app_records(clinic_id, collection, updated_at desc);
alter table app_records enable row level security;

create or replace function current_clinic_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select clinic_id from staff_profiles where id = auth.uid() and active = true limit 1
$$;

create or replace function current_staff_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role from staff_profiles where id = auth.uid() and active = true limit 1
$$;

revoke all on function current_clinic_id() from public;
revoke all on function current_staff_role() from public;
grant execute on function current_clinic_id() to authenticated;
grant execute on function current_staff_role() to authenticated;

drop policy if exists app_records_member_select on app_records;
create policy app_records_member_select on app_records for select to authenticated
using (clinic_id = current_clinic_id());

drop policy if exists app_records_member_insert on app_records;
create policy app_records_member_insert on app_records for insert to authenticated
with check (clinic_id = current_clinic_id());

drop policy if exists app_records_member_update on app_records;
create policy app_records_member_update on app_records for update to authenticated
using (clinic_id = current_clinic_id()) with check (clinic_id = current_clinic_id());

drop policy if exists app_records_member_delete on app_records;
create policy app_records_member_delete on app_records for delete to authenticated
using (clinic_id = current_clinic_id());

drop policy if exists clinics_member_select on clinics;
create policy clinics_member_select on clinics for select to authenticated
using (id = current_clinic_id());

drop policy if exists clinics_admin_update on clinics;
create policy clinics_admin_update on clinics for update to authenticated
using (id = current_clinic_id() and current_staff_role() = 'administrator')
with check (id = current_clinic_id() and current_staff_role() = 'administrator');

drop policy if exists staff_profiles_clinic_select on staff_profiles;
create policy staff_profiles_clinic_select on staff_profiles for select to authenticated
using (clinic_id = current_clinic_id());

create or replace function bootstrap_first_admin(p_name text default 'Administrateur')
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_clinic_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select clinic_id into new_clinic_id from staff_profiles where id = auth.uid();
  if new_clinic_id is not null then return new_clinic_id; end if;
  if exists(select 1 from staff_profiles) then raise exception 'Clinic bootstrap is already complete'; end if;
  insert into clinics(name, currency, timezone, address)
  values ('Dental Spa', 'MAD', 'Africa/Casablanca', 'Casablanca')
  returning id into new_clinic_id;
  insert into staff_profiles(id, clinic_id, display_name, role)
  values (auth.uid(), new_clinic_id, coalesce(nullif(trim(p_name),''),'Administrateur'), 'administrator');
  return new_clinic_id;
end;
$$;

revoke all on function bootstrap_first_admin(text) from public;
grant execute on function bootstrap_first_admin(text) to authenticated;
