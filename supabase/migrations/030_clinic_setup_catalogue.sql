-- Keep first-run configuration and catalogue edits authoritative for booking.
-- app_records remains the compatibility write interface; normalized tables serve booking.

create or replace function app_record_allowed(p_collection text,p_action text,p_data jsonb default '{}'::jsonb)
returns boolean language plpgsql stable security definer set search_path=public as $$
declare role_name text:=current_staff_role(); actor text:=coalesce(p_data->>'collectorUserId',p_data->>'collectedBy');
begin
  if role_name='administrator' then return true; end if;
  if role_name='practitioner' and p_collection in ('appointments','visits','treatmentPlans') then return false; end if;
  if p_action='select' then return case
    when p_collection in ('_clinic','doctors','treatments','bookingLinks') then true
    when p_collection in ('staff','roles') then has_permission('staff.manage') or has_permission('permissions.manage')
    when p_collection='appointments' then has_permission('appointments.view')
    when p_collection='payments' then has_permission('payments.view.all') or (has_permission('payments.view.own') and actor=auth.uid()::text)
    when p_collection in ('visits','treatmentPlans') then has_permission('clinical.view')
    when p_collection='priceRequests' then has_permission('priceRequests.approve') or (has_permission('priceRequests.create') and p_data->>'requestedBy'=auth.uid()::text)
    when p_collection='collectionSessions' then has_permission('sessions.manage') or (has_permission('sessions.own') and p_data->>'openedBy'=auth.uid()::text)
    when p_collection='auditEvents' then has_permission('audit.view') else false end;
  elsif p_action in ('insert','update') then return case
    when p_collection='appointments' then has_permission(case when p_action='insert' then 'appointments.create' else 'appointments.edit' end)
    when p_collection='payments' then has_permission(case when p_action='insert' then 'payments.collect' else 'payments.correct' end) and (p_action='update' or actor=auth.uid()::text)
    when p_collection in ('visits','treatmentPlans') then has_permission(case when p_collection='visits' then 'clinical.edit' else 'plans.create' end)
    when p_collection='priceRequests' then has_permission(case when p_action='insert' then 'priceRequests.create' else 'priceRequests.approve' end) and (p_action='update' or p_data->>'requestedBy'=auth.uid()::text)
    when p_collection='collectionSessions' then has_permission('sessions.manage') or (has_permission('sessions.own') and p_data->>'openedBy'=auth.uid()::text)
    when p_collection='_clinic' then has_permission('settings.manage')
    when p_collection in ('doctors','treatments','bookingLinks') then has_permission('settings.manage') or has_permission('services.manage')
    when p_collection in ('staff','roles') then has_permission('staff.manage') or has_permission('permissions.manage') else false end;
  elsif p_action='delete' then return role_name='administrator'; end if;
  return false;
end;
$$;

create or replace function sync_clinic_catalogue_record()
returns trigger language plpgsql security definer set search_path=public as $$
declare days jsonb; start_label text; end_label text; actor uuid:=auth.uid();
begin
  if new.collection='_clinic' and new.id='settings' then
    if length(trim(coalesce(new.data->>'name',''))) not between 2 and 120
      or length(trim(coalesce(new.data->>'address',''))) not between 3 and 240
      or length(trim(coalesce(new.data->>'phone',''))) not between 6 and 40
      or coalesce(new.data->>'currency','') !~ '^[A-Z]{3}$'
      or not exists(select 1 from pg_timezone_names where name=new.data->>'timezone')
    then raise exception 'Invalid clinic settings'; end if;
    update clinics set name=trim(new.data->>'name'),address=trim(new.data->>'address'),phone=trim(new.data->>'phone'),
      currency=new.data->>'currency',timezone=new.data->>'timezone',updated_at=now() where id=new.clinic_id;
  elsif new.collection='doctors' then
    if length(trim(coalesce(new.data->>'name',''))) not between 2 and 120 then raise exception 'Invalid practitioner name'; end if;
    days:=coalesce(new.data->'availabilityDays','[1,2,3,4,5,6]'::jsonb);
    start_label:=coalesce(new.data->>'startTime','09:00'); end_label:=coalesce(new.data->>'endTime','17:00');
    if jsonb_typeof(days)<>'array' or jsonb_array_length(days)=0
      or exists(select 1 from jsonb_array_elements_text(days) d where d.value !~ '^[1-7]$')
      or start_label !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
      or end_label !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or start_label>=end_label
    then raise exception 'Invalid practitioner availability'; end if;
    insert into practitioners(clinic_id,app_id,name,specialty,availability,active)
    values(new.clinic_id,new.id,trim(new.data->>'name'),nullif(trim(coalesce(new.data->>'specialty','')),''),
      jsonb_build_object('days',days,'start',start_label,'end',end_label,'phone',coalesce(new.data->>'phone',''),'email',coalesce(new.data->>'email','')),
      coalesce((new.data->>'active')::boolean,true))
    on conflict(clinic_id,app_id) do update set name=excluded.name,specialty=excluded.specialty,
      availability=excluded.availability,active=excluded.active;
  elsif new.collection='treatments' then
    if length(trim(coalesce(new.data->>'name',''))) not between 2 and 120
      or coalesce(new.data->>'price','') !~ '^\d+(\.\d{1,2})?$'
      or coalesce(new.data->>'duration','') !~ '^\d+$'
      or (new.data->>'duration')::integer not between 10 and 480
    then raise exception 'Invalid service details'; end if;
    insert into services(clinic_id,app_id,name,description,category,standard_price,duration_minutes,active,booking_eligible)
    values(new.clinic_id,new.id,trim(new.data->>'name'),nullif(trim(coalesce(new.data->>'description','')),''),
      nullif(trim(coalesce(new.data->>'category','')),''),(new.data->>'price')::numeric,(new.data->>'duration')::integer,
      coalesce((new.data->>'active')::boolean,true),coalesce((new.data->>'bookingEligible')::boolean,true))
    on conflict(clinic_id,app_id) do update set name=excluded.name,description=excluded.description,category=excluded.category,
      standard_price=excluded.standard_price,duration_minutes=excluded.duration_minutes,active=excluded.active,booking_eligible=excluded.booking_eligible;
  elsif new.collection='bookingLinks' and coalesce((new.data->>'published')::boolean,false) then
    if not exists(select 1 from services where clinic_id=new.clinic_id and app_id=new.data->>'treatmentId' and active and booking_eligible)
      or not exists(select 1 from practitioners where clinic_id=new.clinic_id and active
        and (nullif(new.data->>'doctorId','') is null or app_id=new.data->>'doctorId'))
      or not exists(select 1 from clinic_resources where clinic_id=new.clinic_id and active
        and (nullif(new.data->>'roomId','') is null or app_id=new.data->>'roomId'))
    then raise exception 'Published booking link requires an active service, practitioner and resource'; end if;
  end if;
  if new.collection in ('_clinic','doctors','treatments','bookingLinks') and actor is not null then
    insert into app_records(clinic_id,collection,id,data) values(new.clinic_id,'auditEvents',gen_random_uuid()::text,
      jsonb_build_object('actorId',actor,'action',case when tg_op='INSERT' then 'created' else 'updated' end,
        'entity',new.collection,'entityId',new.id,'at',now()));
  end if;
  return new;
end;
$$;

drop trigger if exists app_records_clinic_catalogue_sync on app_records;
create trigger app_records_clinic_catalogue_sync after insert or update of data on app_records
for each row when (new.collection in ('_clinic','doctors','treatments','bookingLinks')) execute function sync_clinic_catalogue_record();

create or replace function deactivate_deleted_catalogue_record()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if old.collection='doctors' then update practitioners set active=false where clinic_id=old.clinic_id and app_id=old.id; end if;
  if old.collection='treatments' then update services set active=false where clinic_id=old.clinic_id and app_id=old.id; end if;
  return old;
end;
$$;
drop trigger if exists app_records_catalogue_delete on app_records;
create trigger app_records_catalogue_delete after delete on app_records
for each row when (old.collection in ('doctors','treatments')) execute function deactivate_deleted_catalogue_record();

create or replace function mirror_practitioner_activation()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  update app_records set data=jsonb_set(data,'{active}',to_jsonb(new.active),true),updated_at=now()
  where clinic_id=new.clinic_id and collection='doctors' and id=new.app_id
    and coalesce((data->>'active')::boolean,true) is distinct from new.active;
  return new;
end;
$$;
drop trigger if exists practitioner_activation_mirror on practitioners;
create trigger practitioner_activation_mirror after update of active on practitioners
for each row when (old.active is distinct from new.active) execute function mirror_practitioner_activation();

-- Catalogue entries created after the one-time migration 016 import need replay.
-- Invalid legacy entries abort the migration for explicit repair.
update app_records set data=data where collection in ('doctors','treatments');

-- Existing settings were saved only in app_records. Reconcile them once.
update clinics c set name=coalesce(nullif(trim(r.data->>'name'),''),c.name),
  address=coalesce(nullif(trim(r.data->>'address'),''),c.address),phone=coalesce(nullif(trim(r.data->>'phone'),''),c.phone),
  currency=coalesce(nullif(r.data->>'currency',''),c.currency),timezone=coalesce(nullif(r.data->>'timezone',''),c.timezone),updated_at=now()
from app_records r where r.clinic_id=c.id and r.collection='_clinic' and r.id='settings';

create or replace function practitioner_on_duty(p_practitioner uuid,p_start timestamptz,p_end timestamptz)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from practitioners p join clinics c on c.id=p.clinic_id
    where p.id=p_practitioner and p.active
      and (not (p.availability ? 'days') or exists(select 1 from jsonb_array_elements_text(p.availability->'days') d where d.value=extract(isodow from p_start at time zone c.timezone)::integer::text))
      and (not (p.availability ? 'start') or (p_start at time zone c.timezone)::time >= (p.availability->>'start')::time)
      and (not (p.availability ? 'end') or (p_end at time zone c.timezone)::time <= (p.availability->>'end')::time)
      and (p_start at time zone c.timezone)::date=(p_end at time zone c.timezone)::date)
$$;

create or replace function clinic_resources_snapshot()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id();
begin
  if clinic is null or not (has_permission('appointments.view') or has_permission('services.view')
    or has_permission('services.manage') or has_permission('settings.manage')) then raise exception 'Resource access denied'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',app_id,'name',name,'type',resource_type,'active',active)
    order by active desc,name,app_id) from clinic_resources where clinic_id=clinic),'[]'::jsonb);
end;
$$;

create or replace function appointment_resources_available(p_clinic uuid,p_practitioner uuid,p_resource_id text,p_start timestamptz,p_end timestamptz,p_exclude uuid default null)
returns boolean language sql stable security definer set search_path=public as $$
  select practitioner_on_duty(p_practitioner,p_start,p_end)
    and appointment_slot_available(p_clinic,p_practitioner,p_start,p_end,p_exclude)
    and (p_resource_id is null or exists(select 1 from clinic_resources r where r.clinic_id=p_clinic and r.app_id=p_resource_id and r.active))
    and (p_resource_id is null or not exists(select 1 from appointments a where a.clinic_id=p_clinic and a.room_id=p_resource_id
      and a.id is distinct from p_exclude and a.status not in ('Annulé','No-show') and p_start<a.ends_at and p_end>a.starts_at))
$$;

create or replace function set_staff_membership(p_staff_id uuid,p_role text,p_active boolean)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); member staff_profiles%rowtype;
begin
  if clinic is null or current_staff_role()<>'administrator' then raise exception 'Staff management denied'; end if;
  if p_role not in ('assistant','practitioner') or p_active is null then raise exception 'Invalid staff membership'; end if;
  select * into member from staff_profiles where id=p_staff_id and clinic_id=clinic for update;
  if member.id is null or member.role='administrator' then raise exception 'Staff member unavailable'; end if;
  if p_role='practitioner' and not exists(select 1 from practitioners where clinic_id=clinic and staff_id=p_staff_id) then
    raise exception 'Link a practitioner directory entry before assigning the practitioner role';
  end if;
  update staff_profiles set role=p_role,active=p_active where id=p_staff_id;
  update practitioners set active=p_active and p_role='practitioner' where clinic_id=clinic and staff_id=p_staff_id;
  insert into app_records(clinic_id,collection,id,data) values(clinic,'auditEvents',gen_random_uuid()::text,
    jsonb_build_object('actorId',auth.uid(),'action','staff_membership_changed','entity','staff','entityId',p_staff_id,
      'role',p_role,'active',p_active,'at',now()));
  return jsonb_build_object('id',p_staff_id,'role',p_role,'active',p_active);
end;
$$;

revoke all on function sync_clinic_catalogue_record(),deactivate_deleted_catalogue_record(),practitioner_on_duty(uuid,timestamptz,timestamptz),set_staff_membership(uuid,text,boolean) from public,anon,authenticated;
grant execute on function set_staff_membership(uuid,text,boolean) to authenticated;

create or replace function staff_management_snapshot()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id();
begin
  if clinic is null or not has_permission('staff.manage') then raise exception 'Staff management denied'; end if;
  return jsonb_build_object(
    'members',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.display_name,'email',coalesce(u.email,''),
      'role',s.role,'active',s.active,'practitionerLinked',exists(select 1 from practitioners p where p.clinic_id=clinic and p.staff_id=s.id),
      'createdAt',s.created_at) order by s.active desc,s.display_name)
      from staff_profiles s left join auth.users u on u.id=s.id where s.clinic_id=clinic),'[]'::jsonb),
    'invitations',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'name',i.display_name,'email',i.email,
      'role',i.role,'status',case when i.status='pending' and i.expires_at<=now() then 'expired' else i.status end,
      'expiresAt',i.expires_at,'createdAt',i.created_at) order by i.created_at desc)
      from staff_invitations i where i.clinic_id=clinic and i.created_at>now()-interval '90 days'),'[]'::jsonb)
  );
end;
$$;

create or replace function audit_role_permission_change()
returns trigger language plpgsql security definer set search_path=public as $$
declare item role_permissions%rowtype;
begin
  if tg_op='DELETE' then item:=old; else item:=new; end if;
  if auth.uid() is null then return null; end if;
  insert into app_records(clinic_id,collection,id,data) values(item.clinic_id,'auditEvents',gen_random_uuid()::text,
    jsonb_build_object('actorId',auth.uid(),'action','permission_'||lower(tg_op),'entity','role_permissions',
      'entityId',item.role||':'||item.permission,'scope',item.scope,'at',now()));
  return null;
end;
$$;
drop trigger if exists role_permission_audit on role_permissions;
create trigger role_permission_audit after insert or update or delete on role_permissions
for each row execute function audit_role_permission_change();
revoke all on function mirror_practitioner_activation(),audit_role_permission_change() from public,anon,authenticated;

-- Expose the clinic's configured currency with the public booking identity.
create or replace function public_booking_currency(p_slug text)
returns text language sql stable security definer set search_path=public as $$
  select c.currency from app_records r join clinics c on c.id=r.clinic_id
  where r.collection='bookingLinks' and r.data->>'slug'=p_slug and coalesce((r.data->>'published')::boolean,false)=true limit 1
$$;
revoke all on function public_booking_currency(text) from public,anon,authenticated;
grant execute on function public_booking_currency(text) to anon,authenticated;
