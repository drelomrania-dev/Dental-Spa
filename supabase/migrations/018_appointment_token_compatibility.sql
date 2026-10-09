-- Supabase installs pgcrypto in a protected extension schema on some projects;
-- generate the 256-bit opaque token from two random UUIDs instead.
create or replace function public_create_booking(p_slug text,p_date date,p_time text,p_first_name text,p_last_name text,p_phone text,p_email text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare link_row app_records%rowtype; practitioner practitioners%rowtype; service services%rowtype; patient patients%rowtype; clinic_timezone text;
  duration_minutes integer; start_time timestamptz; end_time timestamptz; appointment appointments%rowtype;
  raw_token text:=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
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

revoke all on function public_create_booking(text,date,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public_create_booking(text,date,text,text,text,text,text) to anon,authenticated;
