-- Close first-admin registration after bootstrap and serialize the one-time setup.

create or replace function public_bootstrap_available()
returns boolean language sql stable security definer set search_path=public as $$
  select not exists(select 1 from staff_profiles)
$$;

create or replace function bootstrap_first_admin(p_name text default 'Administrateur')
returns uuid language plpgsql security definer set search_path=public as $$
declare new_clinic_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  perform pg_advisory_xact_lock(hashtext('dentalflow:first-admin-bootstrap'));
  select clinic_id into new_clinic_id from staff_profiles where id=auth.uid();
  if new_clinic_id is not null then return new_clinic_id; end if;
  if exists(select 1 from staff_profiles) then raise exception 'Clinic bootstrap is already complete'; end if;
  insert into clinics(name,currency,timezone,address) values('Dental Spa','MAD','Africa/Casablanca','Casablanca') returning id into new_clinic_id;
  insert into staff_profiles(id,clinic_id,display_name,role) values(auth.uid(),new_clinic_id,coalesce(nullif(trim(p_name),''),'Administrateur'),'administrator');
  return new_clinic_id;
end;
$$;

revoke all on function public_bootstrap_available(),bootstrap_first_admin(text) from public,anon,authenticated;
grant execute on function public_bootstrap_available() to anon,authenticated;
grant execute on function bootstrap_first_admin(text) to authenticated;
