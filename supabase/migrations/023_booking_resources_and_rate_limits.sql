-- Clinic resources, transactional resource availability, and contact-level booking throttling.

create table if not exists clinic_resources (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id) on delete cascade,
  app_id text not null,
  name text not null,
  resource_type text not null check(resource_type in ('chair','room')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(clinic_id,app_id)
);
create index if not exists clinic_resources_active_idx on clinic_resources(clinic_id,active,name);
create index if not exists appointments_room_start_idx on appointments(clinic_id,room_id,starts_at) where room_id is not null;
alter table clinic_resources enable row level security;

insert into clinic_resources(clinic_id,app_id,name,resource_type)
select c.id,'chair-1','Fauteuil 1','chair' from clinics c
where not exists(select 1 from clinic_resources r where r.clinic_id=c.id);

create or replace function seed_default_clinic_resource()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into clinic_resources(clinic_id,app_id,name,resource_type)
  values(new.id,'chair-1','Fauteuil 1','chair') on conflict(clinic_id,app_id) do nothing;
  return new;
end;
$$;
drop trigger if exists clinic_default_resource on clinics;
create trigger clinic_default_resource after insert on clinics for each row execute function seed_default_clinic_resource();

update app_records link
set data=jsonb_set(link.data,'{roomId}',to_jsonb((select r.app_id from clinic_resources r where r.clinic_id=link.clinic_id and r.active order by r.name,r.app_id limit 1)),true),
  updated_at=now()
where link.collection='bookingLinks' and nullif(link.data->>'roomId','') is null
  and exists(select 1 from clinic_resources r where r.clinic_id=link.clinic_id and r.active);

create or replace function clinic_resources_snapshot()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id();
begin
  if clinic is null or not has_permission('appointments.view') then raise exception 'Resource access denied'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',app_id,'name',name,'type',resource_type,'active',active) order by active desc,name,app_id)
    from clinic_resources where clinic_id=clinic),'[]'::jsonb);
end;
$$;

create or replace function upsert_clinic_resource(p_app_id text,p_name text,p_resource_type text,p_active boolean default true)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); resource_id text:=nullif(trim(coalesce(p_app_id,'')),''); saved clinic_resources%rowtype;
begin
  if clinic is null or not (has_permission('settings.manage') or has_permission('services.manage')) then raise exception 'Resource management denied'; end if;
  if length(trim(coalesce(p_name,''))) not between 2 and 80 or p_resource_type not in ('chair','room') then raise exception 'Invalid resource details'; end if;
  if resource_id is null then resource_id:='resource-'||substr(replace(gen_random_uuid()::text,'-',''),1,12); end if;
  if coalesce(p_active,true)=false and not exists(select 1 from clinic_resources where clinic_id=clinic and active and app_id<>resource_id) then raise exception 'At least one active resource is required'; end if;
  insert into clinic_resources(clinic_id,app_id,name,resource_type,active)
  values(clinic,resource_id,trim(p_name),p_resource_type,coalesce(p_active,true))
  on conflict(clinic_id,app_id) do update set name=excluded.name,resource_type=excluded.resource_type,active=excluded.active,updated_at=now()
  returning * into saved;
  if not saved.active then
    update app_records link set data=jsonb_set(link.data,'{roomId}',to_jsonb((select r.app_id from clinic_resources r where r.clinic_id=clinic and r.active order by r.name,r.app_id limit 1)),true),updated_at=now()
    where link.clinic_id=clinic and link.collection='bookingLinks' and link.data->>'roomId'=saved.app_id;
  end if;
  return jsonb_build_object('id',saved.app_id,'name',saved.name,'type',saved.resource_type,'active',saved.active);
end;
$$;

create or replace function appointment_resources_available(p_clinic uuid,p_practitioner uuid,p_resource_id text,p_start timestamptz,p_end timestamptz,p_exclude uuid default null)
returns boolean language sql stable security definer set search_path=public as $$
  select appointment_slot_available(p_clinic,p_practitioner,p_start,p_end,p_exclude)
    and (p_resource_id is null or not exists(
      select 1 from appointments a where a.clinic_id=p_clinic and a.room_id=p_resource_id
        and a.id is distinct from p_exclude and a.status not in ('Annulé','No-show')
        and p_start<a.ends_at and p_end>a.starts_at
    ))
$$;

create or replace function create_internal_appointment(p_patient_app_id text,p_practitioner_app_id text,p_service_app_id text,p_date date,p_time text,p_duration integer,p_reason text,p_status text default 'Confirmé',p_estimated_amount numeric default null,p_room_id text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); timezone_name text; patient patients%rowtype; practitioner practitioners%rowtype; service services%rowtype;
  start_time timestamptz; end_time timestamptz; appointment appointments%rowtype; app_identifier text:=gen_random_uuid()::text; resource_id text:=nullif(trim(coalesce(p_room_id,'')),'');
begin
  if clinic is null or not has_permission('appointments.create') then raise exception 'Appointment creation denied'; end if;
  if p_time!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' or p_duration not between 15 and 480 or p_status not in ('En attente','Confirmé') then raise exception 'Invalid appointment details'; end if;
  select timezone into timezone_name from clinics where id=clinic;
  select * into patient from patients where clinic_id=clinic and app_id=p_patient_app_id;
  select * into practitioner from practitioners where clinic_id=clinic and app_id=p_practitioner_app_id and active=true;
  if patient.id is null or practitioner.id is null then raise exception 'Patient or practitioner not found'; end if;
  if current_staff_role()='practitioner' and practitioner.staff_id is distinct from auth.uid() then raise exception 'Practitioner assignment denied'; end if;
  if nullif(p_service_app_id,'') is not null then select * into service from services where clinic_id=clinic and app_id=p_service_app_id and active=true; if service.id is null then raise exception 'Service not found'; end if; end if;
  if resource_id is null then select app_id into resource_id from clinic_resources where clinic_id=clinic and active order by name,app_id limit 1;
  elsif not exists(select 1 from clinic_resources where clinic_id=clinic and app_id=resource_id and active) then raise exception 'Appointment resource unavailable'; end if;
  if resource_id is null then raise exception 'Appointment resource unavailable'; end if;
  start_time:=(p_date+p_time::time) at time zone coalesce(timezone_name,'Africa/Casablanca'); end_time:=start_time+make_interval(mins=>p_duration);
  if start_time<now()-interval '5 minutes' then raise exception 'Appointment cannot be scheduled in the past'; end if;
  perform pg_advisory_xact_lock(hashtext(clinic::text||':practitioner:'||practitioner.id::text));
  if resource_id is not null then perform pg_advisory_xact_lock(hashtext(clinic::text||':resource:'||resource_id)); end if;
  if not appointment_resources_available(clinic,practitioner.id,resource_id,start_time,end_time,null) then raise exception 'Appointment practitioner or resource unavailable'; end if;
  insert into appointments(clinic_id,app_id,patient_id,practitioner_id,service_id,starts_at,ends_at,status,source,reference,notes,estimated_amount,room_id)
  values(clinic,app_identifier,patient.id,practitioner.id,service.id,start_time,end_time,p_status,'internal','RDV-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)),coalesce(nullif(trim(coalesce(p_reason,'')),''),service.name,'Consultation'),coalesce(p_estimated_amount,service.standard_price),resource_id) returning * into appointment;
  insert into appointment_events(clinic_id,appointment_id,event_type,actor_id,actor_type,next_value) values(clinic,appointment.id,'created',auth.uid(),'staff',appointment_json(appointment.id));
  return appointment_json(appointment.id);
end;
$$;

create or replace function update_internal_appointment(p_app_id text,p_patient_app_id text,p_practitioner_app_id text,p_service_app_id text,p_date date,p_time text,p_duration integer,p_reason text,p_status text,p_estimated_amount numeric default null,p_room_id text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); timezone_name text; existing appointments%rowtype; patient patients%rowtype; practitioner practitioners%rowtype; service services%rowtype;
  start_time timestamptz; end_time timestamptz; previous jsonb; event_name text:='status_changed'; resource_id text:=nullif(trim(coalesce(p_room_id,'')),'');
begin
  if clinic is null or not has_permission('appointments.edit') then raise exception 'Appointment edit denied'; end if;
  select * into existing from appointments where clinic_id=clinic and app_id=p_app_id for update;
  if existing.id is null then raise exception 'Appointment not found'; end if;
  if p_status='Annulé' and not has_permission('appointments.cancel') then raise exception 'Appointment cancellation denied'; end if;
  if p_status<>existing.status and not (
    (existing.status='En attente' and p_status in ('Confirmé','Annulé')) or (existing.status='Confirmé' and p_status in ('Arrivé','Annulé','No-show')) or
    (existing.status='Arrivé' and p_status in ('En attente clinique','En consultation','Annulé')) or (existing.status='En attente clinique' and p_status in ('En consultation','Annulé')) or
    (existing.status='En consultation' and p_status in ('Terminé','Annulé'))
  ) then raise exception 'Invalid appointment status transition'; end if;
  select timezone into timezone_name from clinics where id=clinic;
  select * into patient from patients where clinic_id=clinic and app_id=p_patient_app_id;
  select * into practitioner from practitioners where clinic_id=clinic and app_id=p_practitioner_app_id and active=true;
  if patient.id is null or practitioner.id is null or p_duration not between 15 and 480 or p_time!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'Invalid appointment details'; end if;
  if current_staff_role()='practitioner' and practitioner.staff_id is distinct from auth.uid() then raise exception 'Practitioner assignment denied'; end if;
  if nullif(p_service_app_id,'') is not null then select * into service from services where clinic_id=clinic and app_id=p_service_app_id and active=true; if service.id is null then raise exception 'Service not found'; end if; end if;
  if resource_id is null then resource_id:=existing.room_id; end if;
  if resource_id is null then select app_id into resource_id from clinic_resources where clinic_id=clinic and active order by name,app_id limit 1;
  elsif not exists(select 1 from clinic_resources where clinic_id=clinic and app_id=resource_id and active) then raise exception 'Appointment resource unavailable'; end if;
  if resource_id is null then raise exception 'Appointment resource unavailable'; end if;
  start_time:=(p_date+p_time::time) at time zone coalesce(timezone_name,'Africa/Casablanca'); end_time:=start_time+make_interval(mins=>p_duration);
  perform pg_advisory_xact_lock(hashtext(clinic::text||':practitioner:'||practitioner.id::text));
  if resource_id is not null then perform pg_advisory_xact_lock(hashtext(clinic::text||':resource:'||resource_id)); end if;
  if p_status not in ('Annulé','No-show') and not appointment_resources_available(clinic,practitioner.id,resource_id,start_time,end_time,existing.id) then raise exception 'Appointment practitioner or resource unavailable'; end if;
  previous:=appointment_json(existing.id);
  if existing.starts_at<>start_time or existing.ends_at<>end_time or existing.room_id is distinct from resource_id then event_name:='rescheduled'; elsif p_status='Annulé' then event_name:='cancelled'; end if;
  update appointments set patient_id=patient.id,practitioner_id=practitioner.id,service_id=service.id,starts_at=start_time,ends_at=end_time,status=p_status,
    notes=coalesce(nullif(trim(coalesce(p_reason,'')),''),service.name,'Consultation'),estimated_amount=coalesce(p_estimated_amount,service.standard_price),room_id=resource_id,
    cancelled_at=case when p_status='Annulé' then now() else null end,updated_at=now() where id=existing.id;
  insert into appointment_events(clinic_id,appointment_id,event_type,actor_id,actor_type,previous_value,next_value) values(clinic,existing.id,event_name,auth.uid(),'staff',previous,appointment_json(existing.id));
  return appointment_json(existing.id);
end;
$$;

create or replace function public_available_slots(p_slug text,p_date date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare link_row app_records%rowtype; practitioner practitioners%rowtype; duration_minutes integer; maximum_advance integer; clinic_timezone text; result jsonb; resource_id text;
begin
  select * into link_row from app_records where collection='bookingLinks' and data->>'slug'=p_slug and coalesce((data->>'published')::boolean,false)=true limit 1;
  if link_row.id is null then return '[]'::jsonb; end if;
  select timezone into clinic_timezone from clinics where id=link_row.clinic_id;
  select coalesce(nullif(settings.data->>'maximumAdvanceDays','')::integer,90) into maximum_advance from (select 1) base left join app_records settings on settings.clinic_id=link_row.clinic_id and settings.collection='_clinic' and settings.id='settings';
  if p_date<current_date or p_date>current_date+coalesce(maximum_advance,90) or extract(isodow from p_date)=7 then return '[]'::jsonb; end if;
  select * into practitioner from practitioners where clinic_id=link_row.clinic_id and (app_id=nullif(link_row.data->>'doctorId','') or nullif(link_row.data->>'doctorId','') is null) and active=true order by case when app_id=nullif(link_row.data->>'doctorId','') then 0 else 1 end,name limit 1;
  if practitioner.id is null then return '[]'::jsonb; end if;
  resource_id:=nullif(link_row.data->>'roomId','');
  if resource_id is null then select app_id into resource_id from clinic_resources where clinic_id=link_row.clinic_id and active order by name,app_id limit 1; end if;
  if resource_id is not null and not exists(select 1 from clinic_resources where clinic_id=link_row.clinic_id and app_id=resource_id and active) then return '[]'::jsonb; end if;
  duration_minutes:=coalesce(nullif(link_row.data->>'duration','')::integer,30);
  select coalesce(jsonb_agg(to_char(candidate_start at time zone clinic_timezone,'HH24:MI') order by candidate_start),'[]'::jsonb) into result
  from (select (p_date+s.slot_ts::time) at time zone clinic_timezone as candidate_start from generate_series(timestamp '2000-01-01 09:00',timestamp '2000-01-01 16:30',interval '30 minutes') s(slot_ts)
    where not(s.slot_ts::time>=time '12:00' and s.slot_ts::time<time '14:00') and ((p_date+s.slot_ts::time) at time zone clinic_timezone)>now()) candidates
  where appointment_resources_available(link_row.clinic_id,practitioner.id,resource_id,candidate_start,candidate_start+make_interval(mins=>duration_minutes),null);
  return result;
end;
$$;

create or replace function public_create_booking(p_slug text,p_date date,p_time text,p_first_name text,p_last_name text,p_phone text,p_email text default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare link_row app_records%rowtype; practitioner practitioners%rowtype; service services%rowtype; patient patients%rowtype; lead leads%rowtype; clinic_timezone text;
  duration_minutes integer; start_time timestamptz; end_time timestamptz; appointment appointments%rowtype; normalized_phone text:=regexp_replace(coalesce(p_phone,''),'[^0-9]','','g'); normalized_email text:=lower(trim(coalesce(p_email,''))); raw_token text:=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-',''); resource_id text; recent_count integer; daily_count integer;
begin
  if p_time!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' or length(trim(p_first_name)) not between 1 and 80 or length(trim(p_last_name)) not between 1 and 80 or length(trim(p_phone)) not between 6 and 30 or length(normalized_phone) not between 6 and 20 or length(coalesce(trim(p_email),''))>160 then raise exception 'Invalid booking details'; end if;
  select * into link_row from app_records where collection='bookingLinks' and data->>'slug'=p_slug and coalesce((data->>'published')::boolean,false)=true limit 1;
  if link_row.id is null then raise exception 'Booking page unavailable'; end if;
  select timezone into clinic_timezone from clinics where id=link_row.clinic_id;
  select * into practitioner from practitioners where clinic_id=link_row.clinic_id and (app_id=nullif(link_row.data->>'doctorId','') or nullif(link_row.data->>'doctorId','') is null) and active=true order by case when app_id=nullif(link_row.data->>'doctorId','') then 0 else 1 end,name limit 1;
  select * into service from services where clinic_id=link_row.clinic_id and app_id=nullif(link_row.data->>'treatmentId','');
  if practitioner.id is null then raise exception 'Practitioner unavailable'; end if;
  resource_id:=nullif(link_row.data->>'roomId','');
  if resource_id is null then select app_id into resource_id from clinic_resources where clinic_id=link_row.clinic_id and active order by name,app_id limit 1; end if;
  if resource_id is not null and not exists(select 1 from clinic_resources where clinic_id=link_row.clinic_id and app_id=resource_id and active) then raise exception 'Appointment resource unavailable'; end if;
  duration_minutes:=coalesce(nullif(link_row.data->>'duration','')::integer,service.duration_minutes,30);
  start_time:=(p_date+p_time::time) at time zone clinic_timezone; end_time:=start_time+make_interval(mins=>duration_minutes);
  perform pg_advisory_xact_lock(hashtext(link_row.clinic_id::text||':practitioner:'||practitioner.id::text));
  if resource_id is not null then perform pg_advisory_xact_lock(hashtext(link_row.clinic_id::text||':resource:'||resource_id)); end if;
  perform pg_advisory_xact_lock(hashtext(link_row.clinic_id::text||':contact:'||coalesce(nullif(normalized_phone,''),normalized_email)));
  if not appointment_resources_available(link_row.clinic_id,practitioner.id,resource_id,start_time,end_time,null) or not (public_available_slots(p_slug,p_date)?p_time) then raise exception 'Slot unavailable'; end if;

  select count(*) into recent_count from appointments a join patients p on p.id=a.patient_id
  where a.clinic_id=link_row.clinic_id and a.source='public' and a.created_at>now()-interval '30 minutes' and (
    (normalized_phone<>'' and regexp_replace(coalesce(p.phone,''),'[^0-9]','','g')=normalized_phone) or (normalized_email<>'' and lower(coalesce(p.email,''))=normalized_email));
  select count(*) into daily_count from appointments a join patients p on p.id=a.patient_id
  where a.clinic_id=link_row.clinic_id and a.source='public' and a.created_at>now()-interval '24 hours' and (
    (normalized_phone<>'' and regexp_replace(coalesce(p.phone,''),'[^0-9]','','g')=normalized_phone) or (normalized_email<>'' and lower(coalesce(p.email,''))=normalized_email));
  if recent_count>=3 or daily_count>=8 then raise exception 'Booking rate limit exceeded'; end if;

  select * into patient from patients where clinic_id=link_row.clinic_id and ((normalized_phone<>'' and regexp_replace(coalesce(phone,''),'[^0-9]','','g')=normalized_phone) or (normalized_email<>'' and lower(coalesce(email,''))=normalized_email)) order by created_at limit 1;
  if patient.id is null then
    insert into patients(clinic_id,app_id,first_name,last_name,phone,email,status) values(link_row.clinic_id,gen_random_uuid()::text,trim(p_first_name),trim(p_last_name),trim(p_phone),nullif(trim(coalesce(p_email,'')),''),'Actif') returning * into patient;
  else update patients set email=coalesce(email,nullif(trim(coalesce(p_email,'')),'')),updated_at=now() where id=patient.id returning * into patient; end if;

  select * into lead from leads where clinic_id=link_row.clinic_id and ((normalized_phone<>'' and regexp_replace(coalesce(phone,''),'[^0-9]','','g')=normalized_phone) or (normalized_email<>'' and lower(coalesce(email,''))=normalized_email)) order by case when status='Converti' then 0 else 1 end,created_at limit 1 for update;
  if lead.id is null then
    insert into leads(clinic_id,first_name,last_name,phone,email,source,status,priority,concern,converted_patient_id,last_contact_at)
    values(link_row.clinic_id,trim(p_first_name),trim(p_last_name),trim(p_phone),nullif(trim(coalesce(p_email,'')),''),'Site web','Rendez-vous','Normale',coalesce(service.name,link_row.data->>'title','Consultation'),patient.id,now()) returning * into lead;
  else
    update leads set first_name=coalesce(nullif(first_name,''),trim(p_first_name)),last_name=coalesce(nullif(last_name,''),trim(p_last_name)),phone=coalesce(phone,trim(p_phone)),email=coalesce(email,nullif(trim(coalesce(p_email,'')),'')),source=case when source='Direct' then 'Site web' else source end,status=case when status='Converti' then status else 'Rendez-vous' end,concern=coalesce(concern,service.name,link_row.data->>'title','Consultation'),converted_patient_id=coalesce(converted_patient_id,patient.id),last_contact_at=now(),updated_at=now() where id=lead.id returning * into lead;
  end if;

  insert into appointments(clinic_id,app_id,patient_id,lead_id,practitioner_id,service_id,starts_at,ends_at,status,source,reference,notes,estimated_amount,room_id,manage_token_hash,manage_token_expires_at,booking_slug)
  values(link_row.clinic_id,gen_random_uuid()::text,patient.id,lead.id,practitioner.id,service.id,start_time,end_time,case when link_row.data->>'confirmationPolicy'='manual' then 'En attente' else 'Confirmé' end,'public','RDV-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)),coalesce(service.name,link_row.data->>'title','Consultation'),service.standard_price,resource_id,encode(digest(raw_token,'sha256'),'hex'),start_time+interval '30 days',p_slug) returning * into appointment;
  insert into appointment_events(clinic_id,appointment_id,event_type,actor_type,next_value) values(link_row.clinic_id,appointment.id,'created','patient',appointment_json(appointment.id));
  return appointment_json(appointment.id)||jsonb_build_object('manageToken',raw_token);
end;
$$;

create or replace function public_reschedule_booking(p_token text,p_date date,p_time text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare appointment appointments%rowtype; clinic_timezone text; duration_minutes integer; start_time timestamptz; end_time timestamptz; previous jsonb;
begin
  select * into appointment from appointments where manage_token_hash=encode(digest(p_token,'sha256'),'hex') and manage_token_expires_at>now() and status not in ('Annulé','Terminé','No-show') for update;
  if appointment.id is null then raise exception 'Booking management link unavailable'; end if;
  select timezone into clinic_timezone from clinics where id=appointment.clinic_id; duration_minutes:=extract(epoch from (appointment.ends_at-appointment.starts_at))/60;
  start_time:=(p_date+p_time::time) at time zone clinic_timezone; end_time:=start_time+make_interval(mins=>duration_minutes);
  perform pg_advisory_xact_lock(hashtext(appointment.clinic_id::text||':practitioner:'||appointment.practitioner_id::text));
  if appointment.room_id is not null then perform pg_advisory_xact_lock(hashtext(appointment.clinic_id::text||':resource:'||appointment.room_id)); end if;
  if not (public_available_slots(appointment.booking_slug,p_date)?p_time) or not appointment_resources_available(appointment.clinic_id,appointment.practitioner_id,appointment.room_id,start_time,end_time,appointment.id) then raise exception 'Slot unavailable'; end if;
  previous:=appointment_json(appointment.id);
  update appointments set starts_at=start_time,ends_at=end_time,status='Confirmé',updated_at=now() where id=appointment.id;
  insert into appointment_events(clinic_id,appointment_id,event_type,actor_type,previous_value,next_value) values(appointment.clinic_id,appointment.id,'rescheduled','patient',previous,appointment_json(appointment.id));
  return appointment_json(appointment.id);
end;
$$;

revoke all on clinic_resources from anon,authenticated;
drop policy if exists clinic_resources_rpc_only on clinic_resources;
create policy clinic_resources_rpc_only on clinic_resources for all to public using(false) with check(false);
revoke all on function seed_default_clinic_resource(),clinic_resources_snapshot(),upsert_clinic_resource(text,text,text,boolean),appointment_resources_available(uuid,uuid,text,timestamptz,timestamptz,uuid) from public,anon,authenticated;
grant execute on function clinic_resources_snapshot(),upsert_clinic_resource(text,text,text,boolean) to authenticated;
grant execute on function public_available_slots(text,date),public_create_booking(text,date,text,text,text,text,text),public_reschedule_booking(text,date,text) to anon,authenticated;
