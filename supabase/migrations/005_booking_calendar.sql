-- Harden the public booking flow and expose only safe calendar metadata.

create or replace function public_booking_page(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'title', coalesce(r.data->>'title','Réserver une consultation'),
    'description', coalesce(r.data->>'description','Choisissez le créneau qui vous convient.'),
    'confirmationPolicy', case when r.data->>'confirmationPolicy'='manual' then 'manual' else 'auto' end,
    'clinicName', c.name,
    'timezone', c.timezone,
    'address', coalesce(c.address,''),
    'phone', coalesce(c.phone,''),
    'doctorName', coalesce(d.data->>'name','Équipe Dental Spa'),
    'treatmentName', coalesce(t.data->>'name',r.data->>'title','Consultation'),
    'duration', coalesce(nullif(r.data->>'duration','')::integer,nullif(t.data->>'duration','')::integer,30),
    'maximumAdvanceDays', coalesce(nullif(settings.data->>'maximumAdvanceDays','')::integer,90)
  )
  from app_records r
  join clinics c on c.id=r.clinic_id
  left join app_records d on d.clinic_id=r.clinic_id and d.collection='doctors' and d.id=nullif(r.data->>'doctorId','')
  left join app_records t on t.clinic_id=r.clinic_id and t.collection='treatments' and t.id=nullif(r.data->>'treatmentId','')
  left join app_records settings on settings.clinic_id=r.clinic_id and settings.collection='_clinic' and settings.id='settings'
  where r.collection='bookingLinks'
    and r.data->>'slug'=p_slug
    and coalesce((r.data->>'published')::boolean,false)=true
  limit 1
$$;

create or replace function public_available_slots(p_slug text,p_date date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  link_row app_records%rowtype;
  doctor_app_id text;
  duration_minutes integer;
  maximum_advance integer;
  clinic_timezone text;
  result jsonb;
begin
  select * into link_row from app_records
  where collection='bookingLinks' and data->>'slug'=p_slug
    and coalesce((data->>'published')::boolean,false)=true limit 1;
  if link_row.id is null then return '[]'::jsonb; end if;

  select timezone into clinic_timezone from clinics where id=link_row.clinic_id;
  select coalesce(nullif(settings.data->>'maximumAdvanceDays','')::integer,90) into maximum_advance
  from (select 1) base left join app_records settings on settings.clinic_id=link_row.clinic_id and settings.collection='_clinic' and settings.id='settings';
  maximum_advance:=coalesce(maximum_advance,90);
  if p_date<current_date or p_date>current_date+maximum_advance or extract(isodow from p_date)=7 then return '[]'::jsonb; end if;

  doctor_app_id:=nullif(link_row.data->>'doctorId','');
  if doctor_app_id is null then
    select id into doctor_app_id from app_records
    where clinic_id=link_row.clinic_id and collection='doctors' and coalesce((data->>'active')::boolean,true)=true
    order by data->>'name',id limit 1;
  end if;
  duration_minutes:=coalesce(nullif(link_row.data->>'duration','')::integer,30);

  select coalesce(jsonb_agg(to_char(candidate_start,'HH24:MI') order by candidate_start),'[]'::jsonb) into result
  from (
    select p_date+s.slot_ts::time as candidate_start
    from generate_series(timestamp '2000-01-01 09:00',timestamp '2000-01-01 16:30',interval '30 minutes') as s(slot_ts)
    where not (s.slot_ts::time>=time '12:00' and s.slot_ts::time<time '14:00')
      and (p_date+s.slot_ts::time)>timezone(coalesce(clinic_timezone,'Africa/Casablanca'),now())
  ) candidates
  where not exists (
    select 1 from app_records a
    where a.clinic_id=link_row.clinic_id and a.collection='appointments'
      and a.data->>'doctorId'=coalesce(doctor_app_id,'')
      and coalesce(a.data->>'status','') not in ('Annulé','No-show')
      and (a.data->>'date')::date=p_date
      and candidates.candidate_start < ((a.data->>'date')::date+(a.data->>'time')::time)+make_interval(mins=>coalesce(nullif(a.data->>'duration','')::integer,30))
      and candidates.candidate_start+make_interval(mins=>duration_minutes) > ((a.data->>'date')::date+(a.data->>'time')::time)
  );
  return result;
end;
$$;

create or replace function public_create_booking(
  p_slug text,p_date date,p_time text,p_first_name text,p_last_name text,
  p_phone text,p_email text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  link_row app_records%rowtype;
  doctor_app_id text;
  treatment_name text;
  patient_app_id text;
  appointment_id text:=gen_random_uuid()::text;
  appointment_ref text:='RDV-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
  duration_minutes integer;
  appointment_data jsonb;
begin
  if p_time!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'Invalid appointment slot'; end if;
  if length(trim(p_first_name)) not between 1 and 80 or length(trim(p_last_name)) not between 1 and 80 or length(trim(p_phone)) not between 6 and 30 or length(coalesce(trim(p_email),''))>160 then raise exception 'Invalid contact details'; end if;
  select * into link_row from app_records where collection='bookingLinks' and data->>'slug'=p_slug and coalesce((data->>'published')::boolean,false)=true limit 1;
  if link_row.id is null then raise exception 'Booking page unavailable'; end if;

  doctor_app_id:=nullif(link_row.data->>'doctorId','');
  if doctor_app_id is null then
    select id into doctor_app_id from app_records where clinic_id=link_row.clinic_id and collection='doctors' and coalesce((data->>'active')::boolean,true)=true order by data->>'name',id limit 1;
  end if;
  duration_minutes:=coalesce(nullif(link_row.data->>'duration','')::integer,30);
  select coalesce(data->>'name',link_row.data->>'title','Consultation') into treatment_name from app_records where clinic_id=link_row.clinic_id and collection='treatments' and id=nullif(link_row.data->>'treatmentId','') limit 1;
  treatment_name:=coalesce(treatment_name,link_row.data->>'title','Consultation');

  perform pg_advisory_xact_lock(hashtext(link_row.clinic_id::text||':'||coalesce(doctor_app_id,'')||':'||p_date::text||':'||p_time));
  if not (public_available_slots(p_slug,p_date)?p_time) then raise exception 'Slot unavailable'; end if;

  select app_id into patient_app_id from patients where clinic_id=link_row.clinic_id and phone=trim(p_phone) limit 1;
  if patient_app_id is null then
    patient_app_id:=gen_random_uuid()::text;
    insert into patients(clinic_id,app_id,first_name,last_name,phone,email,status)
    values(link_row.clinic_id,patient_app_id,trim(p_first_name),trim(p_last_name),trim(p_phone),nullif(trim(p_email),''),'Actif');
  end if;

  appointment_data:=jsonb_build_object(
    'id',appointment_id,'patientId',patient_app_id,'doctorId',coalesce(doctor_app_id,''),
    'treatmentId',coalesce(link_row.data->>'treatmentId',''),'date',p_date::text,'time',p_time,
    'duration',duration_minutes,'reason',treatment_name,
    'status',case when link_row.data->>'confirmationPolicy'='manual' then 'En attente' else 'Confirmé' end,
    'source','public','reference',appointment_ref
  );
  insert into app_records(clinic_id,collection,id,data) values(link_row.clinic_id,'appointments',appointment_id,appointment_data);
  return appointment_data;
end;
$$;

revoke execute on function current_clinic_id() from public,anon;
revoke execute on function current_staff_role() from public,anon;
grant execute on function current_clinic_id() to authenticated;
grant execute on function current_staff_role() to authenticated;
