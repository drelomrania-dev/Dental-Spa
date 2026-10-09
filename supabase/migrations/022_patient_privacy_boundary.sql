-- Expose basic patient identity through RPCs and isolate medical data from reception roles.

create table if not exists patient_medical_records (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id) on delete cascade,
  patient_id uuid not null references patients(id) on delete cascade,
  medical_alerts text,
  emergency_contact jsonb not null default '{}'::jsonb,
  updated_by uuid references staff_profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(patient_id)
);

create index if not exists patient_medical_records_clinic_idx on patient_medical_records(clinic_id,patient_id);

insert into patient_medical_records(clinic_id,patient_id,medical_alerts,emergency_contact)
select clinic_id,id,medical_alerts,emergency_contact from patients
where medical_alerts is not null or emergency_contact<>'{}'::jsonb
on conflict(patient_id) do update set medical_alerts=excluded.medical_alerts,emergency_contact=excluded.emergency_contact,updated_at=now();

update patients set medical_alerts=null,emergency_contact='{}'::jsonb
where medical_alerts is not null or emergency_contact<>'{}'::jsonb;

insert into role_permissions(clinic_id,role,permission,scope)
select id,'practitioner',permission,'assigned' from clinics
cross join (values('patients.medical.view'),('patients.medical.edit')) permissions(permission)
on conflict(clinic_id,role,permission) do update set scope=excluded.scope;

create or replace function patient_basic_json(p_id uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'id',p.app_id,'firstName',p.first_name,'lastName',p.last_name,'phone',coalesce(p.phone,''),'email',coalesce(p.email,''),
    'dateOfBirth',coalesce(p.date_of_birth::text,''),'address',coalesce(p.address,''),'status',p.status,
    'createdAt',to_char(p.created_at,'YYYY-MM-DD'),'updatedAt',p.updated_at
  ) from patients p where p.id=p_id
$$;

create or replace function patient_is_assigned(p_patient_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select current_staff_role()<>'practitioner' or exists(
    select 1 from appointments a join practitioners pr on pr.id=a.practitioner_id
    where a.patient_id=p_patient_id and pr.staff_id=auth.uid()
    union all
    select 1 from clinical_visits v join practitioners pr on pr.id=v.practitioner_id
    where v.patient_id=p_patient_id and pr.staff_id=auth.uid()
  )
$$;

create or replace function patients_snapshot()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); assigned_only boolean;
begin
  if clinic is null or not has_permission('patients.basic.view') then raise exception 'Patient access denied'; end if;
  assigned_only:=current_staff_role()='practitioner' and coalesce((select scope='assigned' from role_permissions where clinic_id=clinic and role='practitioner' and permission='patients.basic.view'),true);
  return coalesce((select jsonb_agg(patient_basic_json(p.id) order by p.created_at desc) from patients p
    where p.clinic_id=clinic and (not assigned_only or patient_is_assigned(p.id))),'[]'::jsonb);
end;
$$;

create or replace function create_patient_record(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); patient patients%rowtype; new_first_name text:=trim(coalesce(p_payload->>'firstName','')); new_last_name text:=trim(coalesce(p_payload->>'lastName',''));
begin
  if clinic is null or not has_permission('patients.create') then raise exception 'Patient creation denied'; end if;
  if length(new_first_name) not between 1 and 80 or length(new_last_name) not between 1 and 80 or length(coalesce(p_payload->>'phone',''))>30 or length(coalesce(p_payload->>'email',''))>160 then raise exception 'Invalid patient details'; end if;
  insert into patients(clinic_id,app_id,first_name,last_name,phone,email,date_of_birth,address,status,updated_at)
  values(clinic,coalesce(nullif(p_payload->>'id',''),gen_random_uuid()::text),new_first_name,new_last_name,nullif(trim(coalesce(p_payload->>'phone','')),''),nullif(lower(trim(coalesce(p_payload->>'email',''))),''),
    nullif(p_payload->>'dateOfBirth','')::date,nullif(trim(coalesce(p_payload->>'address','')),''),coalesce(nullif(p_payload->>'status',''),'Actif'),now()) returning * into patient;
  return patient_basic_json(patient.id);
end;
$$;

create or replace function update_patient_record(p_app_id text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); patient patients%rowtype; new_first_name text; new_last_name text;
begin
  if clinic is null or not has_permission('patients.edit') then raise exception 'Patient update denied'; end if;
  select * into patient from patients where clinic_id=clinic and app_id=p_app_id for update;
  if patient.id is null then raise exception 'Patient not found'; end if;
  new_first_name:=trim(coalesce(p_payload->>'firstName',patient.first_name));new_last_name:=trim(coalesce(p_payload->>'lastName',patient.last_name));
  if length(new_first_name) not between 1 and 80 or length(new_last_name) not between 1 and 80 or length(coalesce(p_payload->>'phone',patient.phone,''))>30 or length(coalesce(p_payload->>'email',patient.email,''))>160 then raise exception 'Invalid patient details'; end if;
  update patients set first_name=new_first_name,last_name=new_last_name,
    phone=case when p_payload?'phone' then nullif(trim(coalesce(p_payload->>'phone','')),'') else phone end,
    email=case when p_payload?'email' then nullif(lower(trim(coalesce(p_payload->>'email',''))),'') else email end,
    date_of_birth=case when p_payload?'dateOfBirth' then nullif(p_payload->>'dateOfBirth','')::date else date_of_birth end,
    address=case when p_payload?'address' then nullif(trim(coalesce(p_payload->>'address','')),'') else address end,
    status=coalesce(nullif(p_payload->>'status',''),status),updated_at=now() where id=patient.id returning * into patient;
  return patient_basic_json(patient.id);
end;
$$;

create or replace function delete_patient_record(p_app_id text)
returns boolean language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); affected integer;
begin
  if clinic is null or current_staff_role()<>'administrator' then raise exception 'Patient deletion denied'; end if;
  delete from patients where clinic_id=clinic and app_id=p_app_id;get diagnostics affected=row_count;return affected=1;
end;
$$;

create or replace function patient_medical_snapshot(p_app_id text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); patient patients%rowtype; medical_row patient_medical_records%rowtype;
begin
  if clinic is null or not has_permission('patients.medical.view') then raise exception 'Medical patient access denied'; end if;
  select * into patient from patients where clinic_id=clinic and app_id=p_app_id;
  if patient.id is null or not patient_is_assigned(patient.id) then raise exception 'Patient not found or not assigned'; end if;
  select * into medical_row from patient_medical_records where patient_id=patient.id;
  return jsonb_build_object('patientId',patient.app_id,'medicalAlerts',coalesce(medical_row.medical_alerts,''),'emergencyContact',coalesce(medical_row.emergency_contact,'{}'::jsonb),'updatedAt',medical_row.updated_at);
end;
$$;

create or replace function update_patient_medical_record(p_app_id text,p_medical_alerts text,p_emergency_contact jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); patient patients%rowtype;
begin
  if clinic is null or not has_permission('patients.medical.edit') then raise exception 'Medical patient update denied'; end if;
  select * into patient from patients where clinic_id=clinic and app_id=p_app_id;
  if patient.id is null or not patient_is_assigned(patient.id) then raise exception 'Patient not found or not assigned'; end if;
  insert into patient_medical_records(clinic_id,patient_id,medical_alerts,emergency_contact,updated_by)
  values(clinic,patient.id,nullif(trim(coalesce(p_medical_alerts,'')),''),coalesce(p_emergency_contact,'{}'::jsonb),auth.uid())
  on conflict(patient_id) do update set medical_alerts=excluded.medical_alerts,emergency_contact=excluded.emergency_contact,updated_by=auth.uid(),updated_at=now();
  return patient_medical_snapshot(p_app_id);
end;
$$;

alter table patients enable row level security;
drop policy if exists patients_member_select on patients;
drop policy if exists patients_member_insert on patients;
drop policy if exists patients_member_update on patients;
drop policy if exists patients_member_delete on patients;
drop policy if exists patients_rpc_only on patients;
create policy patients_rpc_only on patients for all to public using(false) with check(false);

alter table patient_medical_records enable row level security;
drop policy if exists patient_medical_records_rpc_only on patient_medical_records;
create policy patient_medical_records_rpc_only on patient_medical_records for all to public using(false) with check(false);

revoke all on patients,patient_medical_records from anon,authenticated;
revoke all on function patient_basic_json(uuid),patient_is_assigned(uuid),patients_snapshot(),create_patient_record(jsonb),update_patient_record(text,jsonb),delete_patient_record(text),patient_medical_snapshot(text),update_patient_medical_record(text,text,jsonb) from public,anon,authenticated;
grant execute on function patients_snapshot(),create_patient_record(jsonb),update_patient_record(text,jsonb),delete_patient_record(text),patient_medical_snapshot(text),update_patient_medical_record(text,text,jsonb) to authenticated;
