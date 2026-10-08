create table if not exists lead_quotes (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id) on delete cascade,
  lead_id uuid not null references leads(id) on delete cascade,
  title text not null,
  amount numeric(12,2) not null check(amount>=0),
  currency text not null default 'MAD',
  status text not null default 'Brouillon' check(status in ('Brouillon','Envoye','Accepte','Refuse','Expire')),
  valid_until date,
  notes text,
  created_by uuid references staff_profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists lead_quotes_lead_created_idx on lead_quotes(lead_id,created_at desc);
alter table lead_quotes enable row level security;

drop policy if exists lead_quotes_member_select on lead_quotes;
create policy lead_quotes_member_select on lead_quotes for select to authenticated
using(clinic_id=current_clinic_id());
drop policy if exists lead_quotes_member_insert on lead_quotes;
create policy lead_quotes_member_insert on lead_quotes for insert to authenticated
with check(clinic_id=current_clinic_id() and current_staff_role() in ('administrator','assistant') and exists(select 1 from leads l where l.id=lead_id and l.clinic_id=current_clinic_id()));
drop policy if exists lead_quotes_member_update on lead_quotes;
create policy lead_quotes_member_update on lead_quotes for update to authenticated
using(clinic_id=current_clinic_id() and current_staff_role() in ('administrator','assistant'))
with check(clinic_id=current_clinic_id() and current_staff_role() in ('administrator','assistant') and exists(select 1 from leads l where l.id=lead_id and l.clinic_id=current_clinic_id()));
drop policy if exists lead_quotes_admin_delete on lead_quotes;
create policy lead_quotes_admin_delete on lead_quotes for delete to authenticated
using(clinic_id=current_clinic_id() and current_staff_role()='administrator');

create or replace function convert_lead_to_patient(p_lead_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  lead_row leads%rowtype;
  patient_row patients%rowtype;
  patient_app_id text;
  patient_was_existing boolean:=false;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if current_staff_role() not in ('administrator','assistant') then raise exception 'Insufficient permission'; end if;
  select * into lead_row from leads where id=p_lead_id and clinic_id=current_clinic_id();
  if lead_row.id is null then raise exception 'Lead unavailable'; end if;

  select * into patient_row from patients
  where clinic_id=lead_row.clinic_id and (
    (lead_row.phone is not null and phone=lead_row.phone) or
    (lead_row.email is not null and lower(email)=lower(lead_row.email))
  ) order by created_at limit 1;

  if patient_row.id is null then
    patient_app_id:=gen_random_uuid()::text;
    insert into patients(clinic_id,app_id,first_name,last_name,phone,email,status)
    values(lead_row.clinic_id,patient_app_id,lead_row.first_name,lead_row.last_name,lead_row.phone,lead_row.email,'Actif')
    returning * into patient_row;
  else
    patient_was_existing:=true;
    patient_app_id:=patient_row.app_id;
  end if;

  update leads set status='Converti',converted_patient_id=patient_row.id,updated_at=now() where id=lead_row.id;
  insert into lead_events(clinic_id,lead_id,event_type,metadata,actor_id)
  values(lead_row.clinic_id,lead_row.id,'lead.converted',jsonb_build_object('patientId',patient_row.id,'patientAppId',patient_app_id),auth.uid());
  return jsonb_build_object('patientId',patient_app_id,'databaseId',patient_row.id,'existing',patient_was_existing);
end;
$$;

revoke all on function convert_lead_to_patient(uuid) from public,anon,authenticated;
grant execute on function convert_lead_to_patient(uuid) to authenticated;
