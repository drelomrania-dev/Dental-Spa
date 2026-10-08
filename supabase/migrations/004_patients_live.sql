-- Move the patient module from the transition document store to public.patients.

alter table patients add column if not exists app_id text;
update patients set app_id=id::text where app_id is null;
create unique index if not exists patients_clinic_app_id_uidx on patients(clinic_id,app_id);

insert into patients(clinic_id,app_id,first_name,last_name,phone,email,date_of_birth,address,medical_alerts,status,created_at)
select r.clinic_id,r.id,coalesce(r.data->>'firstName',''),coalesce(r.data->>'lastName',''),nullif(r.data->>'phone',''),nullif(r.data->>'email',''),
  case when coalesce(r.data->>'dateOfBirth','') ~ '^\d{4}-\d{2}-\d{2}$' then (r.data->>'dateOfBirth')::date else null end,
  nullif(r.data->>'address',''),nullif(r.data->>'medicalAlerts',''),coalesce(r.data->>'status','Actif'),coalesce(r.created_at,now())
from app_records r where r.collection='patients'
on conflict(clinic_id,app_id) do update set
  first_name=excluded.first_name,last_name=excluded.last_name,phone=excluded.phone,email=excluded.email,
  date_of_birth=excluded.date_of_birth,address=excluded.address,medical_alerts=excluded.medical_alerts,status=excluded.status;

drop policy if exists patients_member_select on patients;
create policy patients_member_select on patients for select to authenticated using(clinic_id=current_clinic_id());
drop policy if exists patients_member_insert on patients;
create policy patients_member_insert on patients for insert to authenticated with check(clinic_id=current_clinic_id());
drop policy if exists patients_member_update on patients;
create policy patients_member_update on patients for update to authenticated using(clinic_id=current_clinic_id()) with check(clinic_id=current_clinic_id());
drop policy if exists patients_member_delete on patients;
create policy patients_member_delete on patients for delete to authenticated using(clinic_id=current_clinic_id());

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
  patient_app_id text;
  appointment_id text := gen_random_uuid()::text;
  appointment_ref text := 'RDV-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
  duration_minutes integer;
  appointment_data jsonb;
begin
  if p_date < current_date or p_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'Invalid appointment slot'; end if;
  if length(trim(p_first_name))<1 or length(trim(p_last_name))<1 or length(trim(p_phone))<6 then raise exception 'Invalid contact details'; end if;
  select * into link_row from app_records where collection='bookingLinks' and data->>'slug'=p_slug and coalesce((data->>'published')::boolean,false)=true limit 1;
  if link_row.id is null then raise exception 'Booking page unavailable'; end if;
  perform pg_advisory_xact_lock(hashtext(link_row.clinic_id::text || ':' || coalesce(link_row.data->>'doctorId','') || ':' || p_date::text || ':' || p_time));
  if exists(select 1 from app_records a where a.clinic_id=link_row.clinic_id and a.collection='appointments' and a.data->>'date'=p_date::text and a.data->>'time'=p_time and a.data->>'doctorId'=coalesce(link_row.data->>'doctorId','') and coalesce(a.data->>'status','') not in ('Annulé','No-show')) then raise exception 'Slot unavailable'; end if;
  select app_id into patient_app_id from patients where clinic_id=link_row.clinic_id and phone=trim(p_phone) limit 1;
  if patient_app_id is null then
    patient_app_id := gen_random_uuid()::text;
    insert into patients(clinic_id,app_id,first_name,last_name,phone,email,status)
    values(link_row.clinic_id,patient_app_id,trim(p_first_name),trim(p_last_name),trim(p_phone),nullif(trim(p_email),''),'Actif');
  end if;
  duration_minutes := coalesce((link_row.data->>'duration')::integer,30);
  appointment_data := jsonb_build_object('id',appointment_id,'patientId',patient_app_id,'doctorId',coalesce(link_row.data->>'doctorId',''),'treatmentId',coalesce(link_row.data->>'treatmentId',''),'date',p_date::text,'time',p_time,'duration',duration_minutes,'reason',coalesce(link_row.data->>'title','Consultation'),'status',case when link_row.data->>'confirmationPolicy'='manual' then 'En attente' else 'Confirmé' end,'source','public','reference',appointment_ref);
  insert into app_records(clinic_id,collection,id,data) values(link_row.clinic_id,'appointments',appointment_id,appointment_data);
  return appointment_data;
end;
$$;
