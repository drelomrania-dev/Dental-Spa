-- Mobile-first public booking now lets the patient choose an eligible service
-- and records the patient's own reason separately from the service catalogue.

create or replace function public_booking_page(p_slug text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare link_row app_records%rowtype; clinic clinics%rowtype; practitioner practitioners%rowtype; settings jsonb; service_rows jsonb;
begin
  select * into link_row from app_records where collection='bookingLinks' and data->>'slug'=p_slug and coalesce((data->>'published')::boolean,false)=true limit 1;
  if link_row.id is null then return null; end if;
  select * into clinic from clinics where id=link_row.clinic_id;
  select * into practitioner from practitioners where clinic_id=link_row.clinic_id and (app_id=nullif(link_row.data->>'doctorId','') or nullif(link_row.data->>'doctorId','') is null) and active=true order by case when app_id=nullif(link_row.data->>'doctorId','') then 0 else 1 end,name limit 1;
  select data into settings from app_records where clinic_id=link_row.clinic_id and collection='_clinic' and id='settings';
  select coalesce(jsonb_agg(jsonb_build_object('id',s.app_id,'name',s.name,'description',coalesce(s.description,''),'category',coalesce(s.category,''),'duration',s.duration_minutes,'price',s.standard_price) order by case when s.app_id=link_row.data->>'treatmentId' then 0 else 1 end,s.name),'[]'::jsonb)
    into service_rows
  from services s
  where s.clinic_id=link_row.clinic_id and s.active and s.booking_eligible and s.app_id is not null
    and (not (link_row.data ? 'serviceIds') or jsonb_array_length(coalesce(link_row.data->'serviceIds','[]'::jsonb))=0 or s.app_id in (select jsonb_array_elements_text(link_row.data->'serviceIds')));
  return jsonb_build_object(
    'title',coalesce(link_row.data->>'title','Réserver une consultation'),'description',coalesce(link_row.data->>'description','Choisissez le créneau qui vous convient.'),
    'confirmationPolicy',case when link_row.data->>'confirmationPolicy'='manual' then 'manual' else 'auto' end,
    'clinicName',clinic.name,'timezone',clinic.timezone,'address',coalesce(clinic.address,''),'phone',coalesce(clinic.phone,''),
    'doctorName',coalesce(practitioner.name,'Équipe Dental Spa'),'defaultServiceId',coalesce(link_row.data->>'treatmentId',''),
    'duration',coalesce(nullif(link_row.data->>'duration','')::integer,30),'maximumAdvanceDays',coalesce(nullif(settings->>'maximumAdvanceDays','')::integer,90),
    'services',service_rows
  );
end;
$$;

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
  if p_date<current_date or p_date>current_date+coalesce(maximum_advance,90) or extract(isodow from p_date)=7 then return '[]'::jsonb; end if;
  select * into practitioner from practitioners where clinic_id=link_row.clinic_id and (app_id=nullif(link_row.data->>'doctorId','') or nullif(link_row.data->>'doctorId','') is null) and active=true order by case when app_id=nullif(link_row.data->>'doctorId','') then 0 else 1 end,name limit 1;
  if practitioner.id is null then return '[]'::jsonb; end if;
  resource_id:=nullif(link_row.data->>'roomId','');
  if resource_id is null then select app_id into resource_id from clinic_resources where clinic_id=link_row.clinic_id and active order by name,app_id limit 1; end if;
  if resource_id is not null and not exists(select 1 from clinic_resources where clinic_id=link_row.clinic_id and app_id=resource_id and active) then return '[]'::jsonb; end if;
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
  if resource_id is not null and not exists(select 1 from clinic_resources where clinic_id=link_row.clinic_id and app_id=resource_id and active) then raise exception 'Appointment resource unavailable'; end if;
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

revoke all on function public_available_slots_for_service(text,date,text),public_create_booking_v2(text,text,text,date,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public_available_slots_for_service(text,date,text),public_create_booking_v2(text,text,text,date,text,text,text,text,text) to anon,authenticated;
