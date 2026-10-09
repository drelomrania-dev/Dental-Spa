-- Normalized internal calendar plus secure public cancellation/rescheduling.

alter table appointments add column if not exists app_id text;
alter table appointments add column if not exists estimated_amount numeric(12,2);
alter table appointments add column if not exists room_id text;
alter table appointments add column if not exists updated_at timestamptz not null default now();
alter table appointments add column if not exists cancelled_at timestamptz;
alter table appointments add column if not exists cancellation_reason text;
alter table appointments add column if not exists manage_token_hash text;
alter table appointments add column if not exists manage_token_expires_at timestamptz;
alter table appointments add column if not exists booking_slug text;
update appointments set app_id=id::text where app_id is null;
create unique index if not exists appointments_clinic_app_id_uidx on appointments(clinic_id,app_id);
create unique index if not exists appointments_manage_token_hash_uidx on appointments(manage_token_hash) where manage_token_hash is not null;
create index if not exists appointments_service_idx on appointments(service_id) where service_id is not null;
create index if not exists appointments_patient_start_idx on appointments(patient_id,starts_at desc);

create table if not exists appointment_events (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id) on delete cascade,
  appointment_id uuid not null references appointments(id) on delete cascade,
  event_type text not null check(event_type in ('created','rescheduled','status_changed','cancelled')),
  actor_id uuid references staff_profiles(id),
  actor_type text not null check(actor_type in ('staff','patient','system')),
  previous_value jsonb not null default '{}'::jsonb,
  next_value jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists appointment_events_appointment_idx on appointment_events(appointment_id,created_at desc);
create index if not exists appointment_events_actor_idx on appointment_events(actor_id) where actor_id is not null;
alter table appointment_events enable row level security;

insert into appointments(clinic_id,app_id,patient_id,practitioner_id,service_id,starts_at,ends_at,status,source,reference,notes,estimated_amount,room_id,created_at,updated_at)
select r.clinic_id,r.id,p.id,pr.id,sv.id,
  ((r.data->>'date')::date+coalesce(nullif(r.data->>'time','')::time,time '09:00')) at time zone coalesce(c.timezone,'Africa/Casablanca'),
  (((r.data->>'date')::date+coalesce(nullif(r.data->>'time','')::time,time '09:00'))+make_interval(mins=>coalesce(nullif(r.data->>'duration','')::integer,30))) at time zone coalesce(c.timezone,'Africa/Casablanca'),
  coalesce(nullif(r.data->>'status',''),'En attente'),coalesce(nullif(r.data->>'source',''),'legacy'),
  coalesce(nullif(r.data->>'reference',''),'LEGACY-'||upper(substr(replace(r.id,'-',''),1,18))),nullif(r.data->>'reason',''),
  case when coalesce(r.data->>'estimatedAmount','') ~ '^\d+(\.\d{1,2})?$' then (r.data->>'estimatedAmount')::numeric else null end,
  nullif(r.data->>'roomId',''),r.created_at,r.updated_at
from app_records r join clinics c on c.id=r.clinic_id
join patients p on p.clinic_id=r.clinic_id and p.app_id=r.data->>'patientId'
left join practitioners pr on pr.clinic_id=r.clinic_id and pr.app_id=r.data->>'doctorId'
left join services sv on sv.clinic_id=r.clinic_id and sv.app_id=r.data->>'treatmentId'
where r.collection='appointments' and coalesce(r.data->>'date','') ~ '^\d{4}-\d{2}-\d{2}$'
on conflict(clinic_id,app_id) do nothing;

create or replace function appointment_json(p_id uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'id',a.app_id,'patientId',p.app_id,'doctorId',coalesce(pr.app_id,''),'treatmentId',coalesce(s.app_id,''),
    'date',to_char(a.starts_at at time zone c.timezone,'YYYY-MM-DD'),'time',to_char(a.starts_at at time zone c.timezone,'HH24:MI'),
    'duration',extract(epoch from (a.ends_at-a.starts_at))/60,'reason',coalesce(a.notes,s.name,'Consultation'),'status',a.status,
    'estimatedAmount',a.estimated_amount,'roomId',coalesce(a.room_id,''),'source',a.source,'reference',a.reference,
    'createdAt',a.created_at,'updatedAt',a.updated_at
  ) from appointments a join clinics c on c.id=a.clinic_id join patients p on p.id=a.patient_id
  left join practitioners pr on pr.id=a.practitioner_id left join services s on s.id=a.service_id where a.id=p_id
$$;

create or replace function appointment_slot_available(p_clinic uuid,p_practitioner uuid,p_start timestamptz,p_end timestamptz,p_exclude uuid default null)
returns boolean language sql stable security definer set search_path=public as $$
  select not exists(select 1 from appointments a where a.clinic_id=p_clinic and a.practitioner_id=p_practitioner
    and a.id is distinct from p_exclude and a.status not in ('Annulé','No-show') and p_start<a.ends_at and p_end>a.starts_at)
$$;

create or replace function appointments_snapshot()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); role_name text:=current_staff_role(); practitioner uuid;
begin
  if clinic is null or not has_permission('appointments.view') then raise exception 'Appointment access denied'; end if;
  select id into practitioner from practitioners where clinic_id=clinic and staff_id=auth.uid() limit 1;
  return coalesce((select jsonb_agg(appointment_json(a.id) order by a.starts_at) from appointments a
    where a.clinic_id=clinic and (role_name<>'practitioner' or a.practitioner_id=practitioner)),'[]'::jsonb);
end;
$$;

create or replace function create_internal_appointment(p_patient_app_id text,p_practitioner_app_id text,p_service_app_id text,p_date date,p_time text,p_duration integer,p_reason text,p_status text default 'Confirmé',p_estimated_amount numeric default null,p_room_id text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); timezone_name text; patient patients%rowtype; practitioner practitioners%rowtype; service services%rowtype;
  start_time timestamptz; end_time timestamptz; appointment appointments%rowtype; app_identifier text:=gen_random_uuid()::text;
begin
  if clinic is null or not has_permission('appointments.create') then raise exception 'Appointment creation denied'; end if;
  if p_time!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' or p_duration not between 15 and 480 or p_status not in ('En attente','Confirmé') then raise exception 'Invalid appointment details'; end if;
  select timezone into timezone_name from clinics where id=clinic;
  select * into patient from patients where clinic_id=clinic and app_id=p_patient_app_id;
  select * into practitioner from practitioners where clinic_id=clinic and app_id=p_practitioner_app_id and active=true;
  if patient.id is null or practitioner.id is null then raise exception 'Patient or practitioner not found'; end if;
  if current_staff_role()='practitioner' and practitioner.staff_id is distinct from auth.uid() then raise exception 'Practitioner assignment denied'; end if;
  if nullif(p_service_app_id,'') is not null then select * into service from services where clinic_id=clinic and app_id=p_service_app_id and active=true; if service.id is null then raise exception 'Service not found'; end if; end if;
  start_time:=(p_date+p_time::time) at time zone coalesce(timezone_name,'Africa/Casablanca'); end_time:=start_time+make_interval(mins=>p_duration);
  if start_time<now()-interval '5 minutes' then raise exception 'Appointment cannot be scheduled in the past'; end if;
  perform pg_advisory_xact_lock(hashtext(clinic::text||':'||practitioner.id::text||':'||p_date::text||':'||p_time));
  if not appointment_slot_available(clinic,practitioner.id,start_time,end_time,null) then raise exception 'Appointment slot unavailable'; end if;
  insert into appointments(clinic_id,app_id,patient_id,practitioner_id,service_id,starts_at,ends_at,status,source,reference,notes,estimated_amount,room_id)
  values(clinic,app_identifier,patient.id,practitioner.id,service.id,start_time,end_time,p_status,'internal','RDV-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)),coalesce(nullif(trim(coalesce(p_reason,'')),''),service.name,'Consultation'),coalesce(p_estimated_amount,service.standard_price),nullif(trim(coalesce(p_room_id,'')),'')) returning * into appointment;
  insert into appointment_events(clinic_id,appointment_id,event_type,actor_id,actor_type,next_value) values(clinic,appointment.id,'created',auth.uid(),'staff',appointment_json(appointment.id));
  return appointment_json(appointment.id);
end;
$$;

create or replace function update_internal_appointment(p_app_id text,p_patient_app_id text,p_practitioner_app_id text,p_service_app_id text,p_date date,p_time text,p_duration integer,p_reason text,p_status text,p_estimated_amount numeric default null,p_room_id text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); timezone_name text; existing appointments%rowtype; patient patients%rowtype; practitioner practitioners%rowtype; service services%rowtype;
  start_time timestamptz; end_time timestamptz; previous jsonb; event_name text:='status_changed';
begin
  if clinic is null or not has_permission('appointments.edit') then raise exception 'Appointment edit denied'; end if;
  select * into existing from appointments where clinic_id=clinic and app_id=p_app_id for update;
  if existing.id is null then raise exception 'Appointment not found'; end if;
  if p_status='Annulé' and not has_permission('appointments.cancel') then raise exception 'Appointment cancellation denied'; end if;
  if p_status<>existing.status and not (
    (existing.status='En attente' and p_status in ('Confirmé','Annulé')) or
    (existing.status='Confirmé' and p_status in ('Arrivé','Annulé','No-show')) or
    (existing.status='Arrivé' and p_status in ('En attente clinique','En consultation','Annulé')) or
    (existing.status='En attente clinique' and p_status in ('En consultation','Annulé')) or
    (existing.status='En consultation' and p_status in ('Terminé','Annulé'))
  ) then raise exception 'Invalid appointment status transition'; end if;
  select timezone into timezone_name from clinics where id=clinic;
  select * into patient from patients where clinic_id=clinic and app_id=p_patient_app_id;
  select * into practitioner from practitioners where clinic_id=clinic and app_id=p_practitioner_app_id and active=true;
  if patient.id is null or practitioner.id is null or p_duration not between 15 and 480 or p_time!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'Invalid appointment details'; end if;
  if current_staff_role()='practitioner' and practitioner.staff_id is distinct from auth.uid() then raise exception 'Practitioner assignment denied'; end if;
  if nullif(p_service_app_id,'') is not null then select * into service from services where clinic_id=clinic and app_id=p_service_app_id and active=true; if service.id is null then raise exception 'Service not found'; end if; end if;
  start_time:=(p_date+p_time::time) at time zone coalesce(timezone_name,'Africa/Casablanca'); end_time:=start_time+make_interval(mins=>p_duration);
  perform pg_advisory_xact_lock(hashtext(clinic::text||':'||practitioner.id::text||':'||p_date::text||':'||p_time));
  if p_status not in ('Annulé','No-show') and not appointment_slot_available(clinic,practitioner.id,start_time,end_time,existing.id) then raise exception 'Appointment slot unavailable'; end if;
  previous:=appointment_json(existing.id);
  if existing.starts_at<>start_time or existing.ends_at<>end_time then event_name:='rescheduled'; elsif p_status='Annulé' then event_name:='cancelled'; end if;
  update appointments set patient_id=patient.id,practitioner_id=practitioner.id,service_id=service.id,starts_at=start_time,ends_at=end_time,status=p_status,
    notes=coalesce(nullif(trim(coalesce(p_reason,'')),''),service.name,'Consultation'),estimated_amount=coalesce(p_estimated_amount,service.standard_price),room_id=nullif(trim(coalesce(p_room_id,'')),''),
    cancelled_at=case when p_status='Annulé' then now() else null end,updated_at=now() where id=existing.id;
  insert into appointment_events(clinic_id,appointment_id,event_type,actor_id,actor_type,previous_value,next_value) values(clinic,existing.id,event_name,auth.uid(),'staff',previous,appointment_json(existing.id));
  return appointment_json(existing.id);
end;
$$;

create or replace function public_available_slots(p_slug text,p_date date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare link_row app_records%rowtype; practitioner practitioners%rowtype; duration_minutes integer; maximum_advance integer; clinic_timezone text; result jsonb;
begin
  select * into link_row from app_records where collection='bookingLinks' and data->>'slug'=p_slug and coalesce((data->>'published')::boolean,false)=true limit 1;
  if link_row.id is null then return '[]'::jsonb; end if;
  select timezone into clinic_timezone from clinics where id=link_row.clinic_id;
  select coalesce(nullif(settings.data->>'maximumAdvanceDays','')::integer,90) into maximum_advance from (select 1) base left join app_records settings on settings.clinic_id=link_row.clinic_id and settings.collection='_clinic' and settings.id='settings';
  if p_date<current_date or p_date>current_date+coalesce(maximum_advance,90) or extract(isodow from p_date)=7 then return '[]'::jsonb; end if;
  select * into practitioner from practitioners where clinic_id=link_row.clinic_id and (app_id=nullif(link_row.data->>'doctorId','') or nullif(link_row.data->>'doctorId','') is null) and active=true order by case when app_id=nullif(link_row.data->>'doctorId','') then 0 else 1 end,name limit 1;
  if practitioner.id is null then return '[]'::jsonb; end if;
  duration_minutes:=coalesce(nullif(link_row.data->>'duration','')::integer,30);
  select coalesce(jsonb_agg(to_char(candidate_start at time zone clinic_timezone,'HH24:MI') order by candidate_start),'[]'::jsonb) into result
  from (select (p_date+s.slot_ts::time) at time zone clinic_timezone as candidate_start from generate_series(timestamp '2000-01-01 09:00',timestamp '2000-01-01 16:30',interval '30 minutes') s(slot_ts)
    where not(s.slot_ts::time>=time '12:00' and s.slot_ts::time<time '14:00') and ((p_date+s.slot_ts::time) at time zone clinic_timezone)>now()) candidates
  where appointment_slot_available(link_row.clinic_id,practitioner.id,candidate_start,candidate_start+make_interval(mins=>duration_minutes),null);
  return result;
end;
$$;

create or replace function public_create_booking(p_slug text,p_date date,p_time text,p_first_name text,p_last_name text,p_phone text,p_email text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare link_row app_records%rowtype; practitioner practitioners%rowtype; service services%rowtype; patient patients%rowtype; clinic_timezone text;
  duration_minutes integer; start_time timestamptz; end_time timestamptz; appointment appointments%rowtype; raw_token text:=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
begin
  if p_time!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' or length(trim(p_first_name)) not between 1 and 80 or length(trim(p_last_name)) not between 1 and 80 or length(trim(p_phone)) not between 6 and 30 or length(coalesce(trim(p_email),''))>160 then raise exception 'Invalid booking details'; end if;
  select * into link_row from app_records where collection='bookingLinks' and data->>'slug'=p_slug and coalesce((data->>'published')::boolean,false)=true limit 1;
  if link_row.id is null then raise exception 'Booking page unavailable'; end if;
  select timezone into clinic_timezone from clinics where id=link_row.clinic_id;
  select * into practitioner from practitioners where clinic_id=link_row.clinic_id and (app_id=nullif(link_row.data->>'doctorId','') or nullif(link_row.data->>'doctorId','') is null) and active=true order by case when app_id=nullif(link_row.data->>'doctorId','') then 0 else 1 end,name limit 1;
  select * into service from services where clinic_id=link_row.clinic_id and app_id=nullif(link_row.data->>'treatmentId','');
  if practitioner.id is null then raise exception 'Practitioner unavailable'; end if;
  duration_minutes:=coalesce(nullif(link_row.data->>'duration','')::integer,service.duration_minutes,30);
  start_time:=(p_date+p_time::time) at time zone clinic_timezone;end_time:=start_time+make_interval(mins=>duration_minutes);
  perform pg_advisory_xact_lock(hashtext(link_row.clinic_id::text||':'||practitioner.id::text||':'||p_date::text||':'||p_time));
  if not (public_available_slots(p_slug,p_date)?p_time) then raise exception 'Slot unavailable'; end if;
  select * into patient from patients where clinic_id=link_row.clinic_id and phone=trim(p_phone) limit 1;
  if patient.id is null then insert into patients(clinic_id,app_id,first_name,last_name,phone,email,status) values(link_row.clinic_id,gen_random_uuid()::text,trim(p_first_name),trim(p_last_name),trim(p_phone),nullif(trim(coalesce(p_email,'')),''),'Actif') returning * into patient; end if;
  insert into appointments(clinic_id,app_id,patient_id,practitioner_id,service_id,starts_at,ends_at,status,source,reference,notes,estimated_amount,manage_token_hash,manage_token_expires_at,booking_slug)
  values(link_row.clinic_id,gen_random_uuid()::text,patient.id,practitioner.id,service.id,start_time,end_time,case when link_row.data->>'confirmationPolicy'='manual' then 'En attente' else 'Confirmé' end,'public','RDV-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)),coalesce(service.name,link_row.data->>'title','Consultation'),service.standard_price,encode(extensions.digest(raw_token,'sha256'),'hex'),start_time+interval '30 days',p_slug) returning * into appointment;
  insert into appointment_events(clinic_id,appointment_id,event_type,actor_type,next_value) values(link_row.clinic_id,appointment.id,'created','patient',appointment_json(appointment.id));
  return appointment_json(appointment.id)||jsonb_build_object('manageToken',raw_token);
end;
$$;

create or replace function public_booking_manage(p_token text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare appointment appointments%rowtype; payload jsonb;
begin
  if length(coalesce(p_token,''))<32 then return null; end if;
  select * into appointment from appointments where manage_token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and manage_token_expires_at>now() limit 1;
  if appointment.id is null then return null; end if;
  payload:=appointment_json(appointment.id);
  return payload||jsonb_build_object('bookingSlug',appointment.booking_slug,'canManage',appointment.status not in ('Annulé','Terminé','No-show') and appointment.starts_at>now(),'tokenExpiresAt',appointment.manage_token_expires_at);
end;
$$;

create or replace function public_reschedule_booking(p_token text,p_date date,p_time text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare appointment appointments%rowtype; clinic_timezone text; duration_minutes integer; start_time timestamptz; end_time timestamptz; previous jsonb;
begin
  select * into appointment from appointments where manage_token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and manage_token_expires_at>now() and status not in ('Annulé','Terminé','No-show') for update;
  if appointment.id is null then raise exception 'Booking management link unavailable'; end if;
  if not (public_available_slots(appointment.booking_slug,p_date)?p_time) then raise exception 'Slot unavailable'; end if;
  select timezone into clinic_timezone from clinics where id=appointment.clinic_id; duration_minutes:=extract(epoch from (appointment.ends_at-appointment.starts_at))/60;
  start_time:=(p_date+p_time::time) at time zone clinic_timezone;end_time:=start_time+make_interval(mins=>duration_minutes);
  perform pg_advisory_xact_lock(hashtext(appointment.clinic_id::text||':'||appointment.practitioner_id::text||':'||p_date::text||':'||p_time));
  if not appointment_slot_available(appointment.clinic_id,appointment.practitioner_id,start_time,end_time,appointment.id) then raise exception 'Slot unavailable'; end if;
  previous:=appointment_json(appointment.id);
  update appointments set starts_at=start_time,ends_at=end_time,status='Confirmé',updated_at=now() where id=appointment.id;
  insert into appointment_events(clinic_id,appointment_id,event_type,actor_type,previous_value,next_value) values(appointment.clinic_id,appointment.id,'rescheduled','patient',previous,appointment_json(appointment.id));
  return appointment_json(appointment.id);
end;
$$;

create or replace function public_cancel_booking(p_token text,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare appointment appointments%rowtype; previous jsonb;
begin
  select * into appointment from appointments where manage_token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and manage_token_expires_at>now() and status not in ('Annulé','Terminé','No-show') for update;
  if appointment.id is null then raise exception 'Booking management link unavailable'; end if;
  previous:=appointment_json(appointment.id);
  update appointments set status='Annulé',cancelled_at=now(),cancellation_reason=nullif(trim(coalesce(p_reason,'')),''),updated_at=now() where id=appointment.id;
  insert into appointment_events(clinic_id,appointment_id,event_type,actor_type,previous_value,next_value) values(appointment.clinic_id,appointment.id,'cancelled','patient',previous,appointment_json(appointment.id));
  return appointment_json(appointment.id);
end;
$$;

revoke all on appointments,appointment_events from anon,authenticated;
drop policy if exists appointments_rpc_only on appointments;
create policy appointments_rpc_only on appointments for all to public using(false) with check(false);
drop policy if exists appointment_events_rpc_only on appointment_events;
create policy appointment_events_rpc_only on appointment_events for all to public using(false) with check(false);

revoke all on function appointment_json(uuid),appointment_slot_available(uuid,uuid,timestamptz,timestamptz,uuid),appointments_snapshot(),create_internal_appointment(text,text,text,date,text,integer,text,text,numeric,text),update_internal_appointment(text,text,text,text,date,text,integer,text,text,numeric,text),public_booking_manage(text),public_reschedule_booking(text,date,text),public_cancel_booking(text,text) from public,anon,authenticated;
grant execute on function appointments_snapshot(),create_internal_appointment(text,text,text,date,text,integer,text,text,numeric,text),update_internal_appointment(text,text,text,text,date,text,integer,text,text,numeric,text) to authenticated;
grant execute on function public_booking_manage(text),public_reschedule_booking(text,date,text),public_cancel_booking(text,text) to anon,authenticated;
grant execute on function public_booking_page(text),public_available_slots(text,date),public_create_booking(text,date,text,text,text,text,text) to anon,authenticated;
