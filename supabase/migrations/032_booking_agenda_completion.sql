-- Phase 4: service-aware public management and agenda status safeguards.
-- Keep existing hashed management tokens, locks and contact throttling intact.

create or replace function appointment_json(p_id uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'id',a.app_id,'patientId',p.app_id,'leadId',coalesce(a.lead_id::text,''),'doctorId',coalesce(pr.app_id,''),'treatmentId',coalesce(s.app_id,''),'serviceName',coalesce(s.name,''),
    'startsAt',a.starts_at,
    'date',to_char(a.starts_at at time zone c.timezone,'YYYY-MM-DD'),'time',to_char(a.starts_at at time zone c.timezone,'HH24:MI'),
    'duration',extract(epoch from (a.ends_at-a.starts_at))/60,'reason',coalesce(a.notes,s.name,'Consultation'),'status',a.status,
    'estimatedAmount',a.estimated_amount,'roomId',coalesce(a.room_id,''),'source',a.source,'reference',a.reference,
    'createdAt',a.created_at,'updatedAt',a.updated_at
  ) from appointments a join clinics c on c.id=a.clinic_id join patients p on p.id=a.patient_id
  left join practitioners pr on pr.id=a.practitioner_id left join services s on s.id=a.service_id where a.id=p_id
$$;

-- Retain the existing service choice and contact matching RPC with clinic-local
-- date bounds and a mandatory active chair/room.
create or replace function public_available_slots_for_service(p_slug text,p_date date,p_service_app_id text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare link_row app_records%rowtype; practitioner practitioners%rowtype; service services%rowtype; duration_minutes integer; maximum_advance integer; clinic_timezone text; result jsonb; resource_id text;
begin
  select * into link_row from app_records where collection='bookingLinks' and data->>'slug'=p_slug and coalesce((data->>'published')::boolean,false)=true limit 1;
  if link_row.id is null then return '[]'::jsonb; end if;
  select * into service from services s where s.clinic_id=link_row.clinic_id and s.app_id=p_service_app_id and s.active and s.booking_eligible
    and (not (link_row.data ? 'serviceIds') or jsonb_array_length(coalesce(link_row.data->'serviceIds','[]'::jsonb))=0 or s.app_id in (select jsonb_array_elements_text(link_row.data->'serviceIds')));
  if service.id is null then return '[]'::jsonb; end if;
  select timezone into clinic_timezone from clinics where id=link_row.clinic_id;
  select coalesce(nullif(config.data->>'maximumAdvanceDays','')::integer,90) into maximum_advance from (select 1) base left join app_records config on config.clinic_id=link_row.clinic_id and config.collection='_clinic' and config.id='settings';
  if p_date<(now() at time zone clinic_timezone)::date or p_date>(now() at time zone clinic_timezone)::date+coalesce(maximum_advance,90) or extract(isodow from p_date)=7 then return '[]'::jsonb; end if;
  select * into practitioner from practitioners where clinic_id=link_row.clinic_id and (app_id=nullif(link_row.data->>'doctorId','') or nullif(link_row.data->>'doctorId','') is null) and active=true order by case when app_id=nullif(link_row.data->>'doctorId','') then 0 else 1 end,name limit 1;
  if practitioner.id is null then return '[]'::jsonb; end if;
  resource_id:=nullif(link_row.data->>'roomId','');
  if resource_id is null then select app_id into resource_id from clinic_resources where clinic_id=link_row.clinic_id and active order by name,app_id limit 1; end if;
  if resource_id is null or not exists(select 1 from clinic_resources where clinic_id=link_row.clinic_id and app_id=resource_id and active) then return '[]'::jsonb; end if;
  duration_minutes:=case when service.app_id=link_row.data->>'treatmentId' then coalesce(nullif(link_row.data->>'duration','')::integer,service.duration_minutes,30) else coalesce(service.duration_minutes,30) end;
  select coalesce(jsonb_agg(to_char(candidate_start at time zone clinic_timezone,'HH24:MI') order by candidate_start),'[]'::jsonb) into result
  from (select (p_date+s.slot_ts::time) at time zone clinic_timezone as candidate_start from generate_series(timestamp '2000-01-01 09:00',timestamp '2000-01-01 16:30',interval '30 minutes') s(slot_ts)
    where not(s.slot_ts::time>=time '12:00' and s.slot_ts::time<time '14:00') and ((p_date+s.slot_ts::time) at time zone clinic_timezone)>now()) candidates
  where appointment_resources_available(link_row.clinic_id,practitioner.id,resource_id,candidate_start,candidate_start+make_interval(mins=>duration_minutes),null);
  return result;
end;
$$;

create or replace function public_create_booking_v2(p_slug text,p_service_app_id text,p_reason text,p_date date,p_time text,p_first_name text,p_last_name text,p_phone text,p_email text default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare link_row app_records%rowtype; practitioner practitioners%rowtype; service services%rowtype; patient patients%rowtype; lead leads%rowtype; clinic_timezone text;
  duration_minutes integer; start_time timestamptz; end_time timestamptz; appointment appointments%rowtype; normalized_phone text:=regexp_replace(coalesce(p_phone,''),'[^0-9]','','g'); normalized_email text:=lower(trim(coalesce(p_email,''))); raw_token text:=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-',''); resource_id text; recent_count integer; daily_count integer; visit_reason text:=trim(coalesce(p_reason,''));
begin
  if p_time!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' or length(trim(p_first_name)) not between 1 and 80 or length(trim(p_last_name)) not between 1 and 80 or length(trim(p_phone)) not between 6 and 30 or length(normalized_phone) not between 6 and 20 or length(coalesce(trim(p_email),''))>160 or length(visit_reason) not between 3 and 500 then raise exception 'Invalid booking details'; end if;
  if normalized_email<>'' and normalized_email!~'^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception 'Invalid booking details'; end if;
  select * into link_row from app_records where collection='bookingLinks' and data->>'slug'=p_slug and coalesce((data->>'published')::boolean,false)=true limit 1;
  if link_row.id is null then raise exception 'Booking page unavailable'; end if;
  select * into service from services s where s.clinic_id=link_row.clinic_id and s.app_id=p_service_app_id and s.active and s.booking_eligible
    and (not (link_row.data ? 'serviceIds') or jsonb_array_length(coalesce(link_row.data->'serviceIds','[]'::jsonb))=0 or s.app_id in (select jsonb_array_elements_text(link_row.data->'serviceIds')));
  if service.id is null then raise exception 'Service unavailable'; end if;
  select timezone into clinic_timezone from clinics where id=link_row.clinic_id;
  select * into practitioner from practitioners where clinic_id=link_row.clinic_id and (app_id=nullif(link_row.data->>'doctorId','') or nullif(link_row.data->>'doctorId','') is null) and active=true order by case when app_id=nullif(link_row.data->>'doctorId','') then 0 else 1 end,name limit 1;
  if practitioner.id is null then raise exception 'Practitioner unavailable'; end if;
  resource_id:=nullif(link_row.data->>'roomId','');
  if resource_id is null then select app_id into resource_id from clinic_resources where clinic_id=link_row.clinic_id and active order by name,app_id limit 1; end if;
  if resource_id is null or not exists(select 1 from clinic_resources where clinic_id=link_row.clinic_id and app_id=resource_id and active) then raise exception 'Appointment resource unavailable'; end if;
  duration_minutes:=case when service.app_id=link_row.data->>'treatmentId' then coalesce(nullif(link_row.data->>'duration','')::integer,service.duration_minutes,30) else coalesce(service.duration_minutes,30) end;
  start_time:=(p_date+p_time::time) at time zone clinic_timezone;end_time:=start_time+make_interval(mins=>duration_minutes);
  perform pg_advisory_xact_lock(hashtext(link_row.clinic_id::text||':practitioner:'||practitioner.id::text));
  if resource_id is not null then perform pg_advisory_xact_lock(hashtext(link_row.clinic_id::text||':resource:'||resource_id)); end if;
  perform pg_advisory_xact_lock(hashtext(link_row.clinic_id::text||':contact:'||coalesce(nullif(normalized_phone,''),normalized_email)));
  if not appointment_resources_available(link_row.clinic_id,practitioner.id,resource_id,start_time,end_time,null) or not (public_available_slots_for_service(p_slug,p_date,p_service_app_id)?p_time) then raise exception 'Slot unavailable'; end if;
  select count(*) into recent_count from appointments a join patients p on p.id=a.patient_id where a.clinic_id=link_row.clinic_id and a.source='public' and a.created_at>now()-interval '30 minutes' and ((normalized_phone<>'' and regexp_replace(coalesce(p.phone,''),'[^0-9]','','g')=normalized_phone) or (normalized_email<>'' and lower(coalesce(p.email,''))=normalized_email));
  select count(*) into daily_count from appointments a join patients p on p.id=a.patient_id where a.clinic_id=link_row.clinic_id and a.source='public' and a.created_at>now()-interval '24 hours' and ((normalized_phone<>'' and regexp_replace(coalesce(p.phone,''),'[^0-9]','','g')=normalized_phone) or (normalized_email<>'' and lower(coalesce(p.email,''))=normalized_email));
  if recent_count>=3 or daily_count>=8 then raise exception 'Booking rate limit exceeded'; end if;
  select * into patient from patients where clinic_id=link_row.clinic_id and ((normalized_phone<>'' and regexp_replace(coalesce(phone,''),'[^0-9]','','g')=normalized_phone) or (normalized_email<>'' and lower(coalesce(email,''))=normalized_email)) order by created_at limit 1;
  if patient.id is null then insert into patients(clinic_id,app_id,first_name,last_name,phone,email,status) values(link_row.clinic_id,gen_random_uuid()::text,trim(p_first_name),trim(p_last_name),trim(p_phone),nullif(normalized_email,''),'Actif') returning * into patient;
  else update patients set email=coalesce(email,nullif(normalized_email,'')),updated_at=now() where id=patient.id returning * into patient; end if;
  select * into lead from leads where clinic_id=link_row.clinic_id and ((normalized_phone<>'' and regexp_replace(coalesce(phone,''),'[^0-9]','','g')=normalized_phone) or (normalized_email<>'' and lower(coalesce(email,''))=normalized_email)) order by case when status='Converti' then 0 else 1 end,created_at limit 1 for update;
  if lead.id is null then insert into leads(clinic_id,first_name,last_name,phone,email,source,status,priority,concern,converted_patient_id,last_contact_at) values(link_row.clinic_id,trim(p_first_name),trim(p_last_name),trim(p_phone),nullif(normalized_email,''),'Site web','Rendez-vous','Normale',visit_reason,patient.id,now()) returning * into lead;
  else update leads set first_name=coalesce(nullif(first_name,''),trim(p_first_name)),last_name=coalesce(nullif(last_name,''),trim(p_last_name)),phone=coalesce(phone,trim(p_phone)),email=coalesce(email,nullif(normalized_email,'')),source=case when source='Direct' then 'Site web' else source end,status=case when status='Converti' then status else 'Rendez-vous' end,concern=visit_reason,converted_patient_id=coalesce(converted_patient_id,patient.id),last_contact_at=now(),updated_at=now() where id=lead.id returning * into lead; end if;
  insert into appointments(clinic_id,app_id,patient_id,lead_id,practitioner_id,service_id,starts_at,ends_at,status,source,reference,notes,estimated_amount,room_id,manage_token_hash,manage_token_expires_at,booking_slug)
  values(link_row.clinic_id,gen_random_uuid()::text,patient.id,lead.id,practitioner.id,service.id,start_time,end_time,case when link_row.data->>'confirmationPolicy'='manual' then 'En attente' else 'Confirmé' end,'public','RDV-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)),visit_reason,service.standard_price,resource_id,encode(digest(raw_token,'sha256'),'hex'),start_time+interval '30 days',p_slug) returning * into appointment;
  insert into appointment_events(clinic_id,appointment_id,event_type,actor_type,next_value) values(link_row.clinic_id,appointment.id,'created','patient',appointment_json(appointment.id));
  return appointment_json(appointment.id)||jsonb_build_object('manageToken',raw_token,'serviceName',service.name);
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
  if p_status in ('Annulé','No-show') and not has_permission('appointments.cancel') then raise exception 'Appointment cancellation denied'; end if;
  if p_status<>existing.status and not (
    (existing.status='En attente' and p_status in ('Confirmé','Annulé')) or (existing.status='Confirmé' and p_status in ('Arrivé','Annulé','No-show')) or
    (existing.status='Arrivé' and p_status in ('En attente clinique','En consultation','Annulé')) or (existing.status='En attente clinique' and p_status in ('En consultation','Annulé')) or
    (existing.status='En consultation' and p_status in ('Terminé','Annulé'))
  ) then raise exception 'Invalid appointment status transition'; end if;
  select timezone into timezone_name from clinics where id=clinic;
  select * into patient from patients where clinic_id=clinic and app_id=p_patient_app_id;
  select * into practitioner from practitioners where clinic_id=clinic and app_id=p_practitioner_app_id
    and (active or (p_status in ('Annulé','No-show') and id=existing.practitioner_id));
  if patient.id is null or practitioner.id is null or p_duration not between 15 and 480 or p_time!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'Invalid appointment details'; end if;
  if current_staff_role()='practitioner' and practitioner.staff_id is distinct from auth.uid() then raise exception 'Practitioner assignment denied'; end if;
  if nullif(p_service_app_id,'') is not null then
    select * into service from services where clinic_id=clinic and app_id=p_service_app_id
      and (active or (p_status in ('Annulé','No-show') and id=existing.service_id));
    if service.id is null then raise exception 'Service not found'; end if;
  end if;
  if resource_id is null then resource_id:=existing.room_id; end if;
  if resource_id is null then select app_id into resource_id from clinic_resources where clinic_id=clinic and active order by name,app_id limit 1;
  elsif not exists(select 1 from clinic_resources where clinic_id=clinic and app_id=resource_id
    and (active or (p_status in ('Annulé','No-show') and app_id=existing.room_id))) then raise exception 'Appointment resource unavailable'; end if;
  if resource_id is null then raise exception 'Appointment resource unavailable'; end if;
  start_time:=(p_date+p_time::time) at time zone coalesce(timezone_name,'Africa/Casablanca'); end_time:=start_time+make_interval(mins=>p_duration);
  if p_status='No-show' and existing.starts_at>now() then raise exception 'No-show requires a started appointment'; end if;
  if p_status='No-show' and (start_time<>existing.starts_at or end_time<>existing.ends_at or resource_id is distinct from existing.room_id) then raise exception 'No-show cannot reschedule appointment'; end if;
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

create or replace function public_booking_reschedule_slots(p_token text,p_date date)
returns jsonb language plpgsql stable security definer set search_path=public,extensions as $$
declare booking appointments%rowtype; clinic_timezone text; clinic_today date; maximum_advance integer; duration_minutes integer; result jsonb; resource_id text;
begin
  if length(coalesce(p_token,''))<32 then return '[]'::jsonb; end if;
  select * into booking from appointments where manage_token_hash=encode(digest(p_token,'sha256'),'hex')
    and manage_token_expires_at>now() and starts_at>now() and status not in ('Annulé','Terminé','No-show') limit 1;
  if booking.id is null then return '[]'::jsonb; end if;
  resource_id:=booking.room_id;
  if resource_id is null then select app_id into resource_id from clinic_resources where clinic_id=booking.clinic_id and active order by name,app_id limit 1; end if;
  if resource_id is null then return '[]'::jsonb; end if;
  select timezone into clinic_timezone from clinics where id=booking.clinic_id;
  clinic_today:=(now() at time zone clinic_timezone)::date;
  select coalesce(nullif(data->>'maximumAdvanceDays','')::integer,90) into maximum_advance
    from app_records where clinic_id=booking.clinic_id and collection='_clinic' and id='settings';
  if p_date<clinic_today or p_date>clinic_today+coalesce(maximum_advance,90) or extract(isodow from p_date)=7 then return '[]'::jsonb; end if;
  duration_minutes:=extract(epoch from (booking.ends_at-booking.starts_at))/60;
  select coalesce(jsonb_agg(to_char(candidate_start at time zone clinic_timezone,'HH24:MI') order by candidate_start),'[]'::jsonb) into result
  from (select (p_date+s.slot_ts::time) at time zone clinic_timezone as candidate_start
    from generate_series(timestamp '2000-01-01 09:00',timestamp '2000-01-01 16:30',interval '30 minutes') s(slot_ts)
    where not(s.slot_ts::time>=time '12:00' and s.slot_ts::time<time '14:00')
      and ((p_date+s.slot_ts::time) at time zone clinic_timezone)>now()) candidates
  where appointment_resources_available(booking.clinic_id,booking.practitioner_id,resource_id,
    candidate_start,candidate_start+make_interval(mins=>duration_minutes),booking.id);
  return result;
end;
$$;

create or replace function public_reschedule_booking(p_token text,p_date date,p_time text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare booking appointments%rowtype; clinic_timezone text; duration_minutes integer; start_time timestamptz; end_time timestamptz; previous jsonb; resource_id text;
begin
  if length(coalesce(p_token,''))<32 or coalesce(p_time,'')!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'Booking management link unavailable'; end if;
  select * into booking from appointments where manage_token_hash=encode(digest(p_token,'sha256'),'hex')
    and manage_token_expires_at>now() and starts_at>now() and status not in ('Annulé','Terminé','No-show') for update;
  if booking.id is null then raise exception 'Booking management link unavailable'; end if;
  resource_id:=booking.room_id;
  if resource_id is null then select app_id into resource_id from clinic_resources where clinic_id=booking.clinic_id and active order by name,app_id limit 1; end if;
  if resource_id is null then raise exception 'Appointment resource unavailable'; end if;
  select timezone into clinic_timezone from clinics where id=booking.clinic_id;
  duration_minutes:=extract(epoch from (booking.ends_at-booking.starts_at))/60;
  start_time:=(p_date+p_time::time) at time zone clinic_timezone; end_time:=start_time+make_interval(mins=>duration_minutes);
  perform pg_advisory_xact_lock(hashtext(booking.clinic_id::text||':practitioner:'||booking.practitioner_id::text));
  perform pg_advisory_xact_lock(hashtext(booking.clinic_id::text||':resource:'||resource_id));
  if not (public_booking_reschedule_slots(p_token,p_date)?p_time)
    or not appointment_resources_available(booking.clinic_id,booking.practitioner_id,resource_id,start_time,end_time,booking.id)
    then raise exception 'Slot unavailable'; end if;
  previous:=appointment_json(booking.id);
  update appointments set starts_at=start_time,ends_at=end_time,room_id=resource_id,status='Confirmé',manage_token_expires_at=start_time+interval '30 days',updated_at=now() where id=booking.id;
  insert into appointment_events(clinic_id,appointment_id,event_type,actor_type,previous_value,next_value)
    values(booking.clinic_id,booking.id,'rescheduled','patient',previous,appointment_json(booking.id));
  return appointment_json(booking.id)||jsonb_build_object('canManage',true);
end;
$$;

create or replace function public_cancel_booking(p_token text,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare booking appointments%rowtype; previous jsonb;
begin
  if length(coalesce(p_token,''))<32 then raise exception 'Booking management link unavailable'; end if;
  select * into booking from appointments where manage_token_hash=encode(digest(p_token,'sha256'),'hex')
    and manage_token_expires_at>now() and starts_at>now() and status not in ('Annulé','Terminé','No-show') for update;
  if booking.id is null then raise exception 'Booking management link unavailable'; end if;
  previous:=appointment_json(booking.id);
  update appointments set status='Annulé',cancelled_at=now(),cancellation_reason=nullif(trim(coalesce(p_reason,'')),''),updated_at=now() where id=booking.id;
  insert into appointment_events(clinic_id,appointment_id,event_type,actor_type,previous_value,next_value)
    values(booking.clinic_id,booking.id,'cancelled','patient',previous,appointment_json(booking.id));
  return appointment_json(booking.id)||jsonb_build_object('canManage',false);
end;
$$;

revoke all on function appointment_json(uuid),public_booking_reschedule_slots(text,date),public_available_slots_for_service(text,date,text),public_create_booking_v2(text,text,text,date,text,text,text,text,text),update_internal_appointment(text,text,text,text,date,text,integer,text,text,numeric,text),public_reschedule_booking(text,date,text),public_cancel_booking(text,text) from public,anon,authenticated;
grant execute on function public_booking_reschedule_slots(text,date),public_available_slots_for_service(text,date,text),public_create_booking_v2(text,text,text,date,text,text,text,text,text),public_reschedule_booking(text,date,text),public_cancel_booking(text,text) to anon,authenticated;
grant execute on function update_internal_appointment(text,text,text,text,date,text,integer,text,text,numeric,text) to authenticated;
