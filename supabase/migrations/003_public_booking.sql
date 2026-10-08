-- Public booking API. Anonymous callers can use only these narrowly scoped functions.

create or replace function public_booking_page(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select data from app_records
  where collection = 'bookingLinks'
    and data->>'slug' = p_slug
    and coalesce((data->>'published')::boolean,false) = true
  limit 1
$$;

create or replace function public_available_slots(p_slug text, p_date date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  link_row app_records%rowtype;
  result jsonb;
begin
  select * into link_row from app_records
  where collection='bookingLinks' and data->>'slug'=p_slug
    and coalesce((data->>'published')::boolean,false)=true limit 1;
  if link_row.id is null then return '[]'::jsonb; end if;
  select coalesce(jsonb_agg(slot order by slot),'[]'::jsonb) into result
  from (values ('09:00'),('09:30'),('10:00'),('10:30'),('11:00'),('14:00'),('14:30'),('15:00'),('15:30'),('16:00')) slots(slot)
  where not exists (
    select 1 from app_records a
    where a.clinic_id=link_row.clinic_id and a.collection='appointments'
      and a.data->>'date'=p_date::text and a.data->>'time'=slot
      and a.data->>'doctorId'=coalesce(link_row.data->>'doctorId','')
      and coalesce(a.data->>'status','') not in ('Annulé','No-show')
  );
  return result;
end;
$$;

create or replace function public_create_booking(
  p_slug text, p_date date, p_time text, p_first_name text, p_last_name text,
  p_phone text, p_email text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  link_row app_records%rowtype;
  patient_record app_records%rowtype;
  patient_id text;
  appointment_id text := gen_random_uuid()::text;
  appointment_ref text := 'RDV-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
  duration_minutes integer;
  appointment_data jsonb;
begin
  if p_date < current_date or p_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'Invalid appointment slot'; end if;
  if length(trim(p_first_name))<1 or length(trim(p_last_name))<1 or length(trim(p_phone))<6 then raise exception 'Invalid contact details'; end if;
  select * into link_row from app_records
  where collection='bookingLinks' and data->>'slug'=p_slug
    and coalesce((data->>'published')::boolean,false)=true limit 1;
  if link_row.id is null then raise exception 'Booking page unavailable'; end if;
  perform pg_advisory_xact_lock(hashtext(link_row.clinic_id::text || ':' || coalesce(link_row.data->>'doctorId','') || ':' || p_date::text || ':' || p_time));
  if exists(select 1 from app_records a where a.clinic_id=link_row.clinic_id and a.collection='appointments'
      and a.data->>'date'=p_date::text and a.data->>'time'=p_time
      and a.data->>'doctorId'=coalesce(link_row.data->>'doctorId','')
      and coalesce(a.data->>'status','') not in ('Annulé','No-show')) then raise exception 'Slot unavailable'; end if;
  select * into patient_record from app_records p where p.clinic_id=link_row.clinic_id and p.collection='patients' and p.data->>'phone'=trim(p_phone) limit 1;
  if patient_record.id is null then
    patient_id := gen_random_uuid()::text;
    insert into app_records(clinic_id,collection,id,data) values(link_row.clinic_id,'patients',patient_id,jsonb_build_object('id',patient_id,'firstName',trim(p_first_name),'lastName',trim(p_last_name),'phone',trim(p_phone),'email',coalesce(trim(p_email),''),'createdAt',current_date::text,'status','Actif'));
  else patient_id := patient_record.id; end if;
  duration_minutes := coalesce((link_row.data->>'duration')::integer,30);
  appointment_data := jsonb_build_object('id',appointment_id,'patientId',patient_id,'doctorId',coalesce(link_row.data->>'doctorId',''),'treatmentId',coalesce(link_row.data->>'treatmentId',''),'date',p_date::text,'time',p_time,'duration',duration_minutes,'reason',coalesce(link_row.data->>'title','Consultation'),'status',case when link_row.data->>'confirmationPolicy'='manual' then 'En attente' else 'Confirmé' end,'source','public','reference',appointment_ref);
  insert into app_records(clinic_id,collection,id,data) values(link_row.clinic_id,'appointments',appointment_id,appointment_data);
  return appointment_data;
end;
$$;

revoke all on function public_booking_page(text) from public;
revoke all on function public_available_slots(text,date) from public;
revoke all on function public_create_booking(text,date,text,text,text,text,text) from public;
grant execute on function public_booking_page(text) to anon, authenticated;
grant execute on function public_available_slots(text,date) to anon, authenticated;
grant execute on function public_create_booking(text,date,text,text,text,text,text) to anon, authenticated;
