-- Security hardening for practitioner assignment boundaries and public booking slugs.
-- Existing duplicate published slugs fail closed before the unique index is created.

create or replace function current_practitioner_app_id()
returns text language sql stable security definer set search_path=public as $$
  select app_id from practitioners
  where clinic_id=current_clinic_id() and staff_id=auth.uid() and active=true
  order by id limit 1
$$;

create or replace function normalize_published_booking_slug()
returns trigger language plpgsql security definer set search_path=public as $$
declare canonical_slug text;
begin
  if new.collection<>'bookingLinks' then return new; end if;
  canonical_slug:=lower(trim(coalesce(new.data->>'slug','')));
  if new.data ? 'slug' then new.data:=jsonb_set(new.data,'{slug}',to_jsonb(canonical_slug),true); end if;
  if coalesce((new.data->>'published')::boolean,false) then
    if canonical_slug='' then raise exception 'Published booking slug is required' using errcode='check_violation'; end if;
    if exists(select 1 from app_records existing where existing.collection='bookingLinks'
      and lower(trim(existing.data->>'slug'))=canonical_slug
      and coalesce((existing.data->>'published')::boolean,false)=true
      and (existing.clinic_id,existing.collection,existing.id) is distinct from (new.clinic_id,new.collection,new.id))
    then raise exception 'Published booking slug already in use' using errcode='unique_violation'; end if;
  end if;
  return new;
end;
$$;

drop trigger if exists app_records_booking_slug_guard on app_records;
create trigger app_records_booking_slug_guard before insert or update of collection,data on app_records
for each row execute function normalize_published_booking_slug();

do $$
declare duplicate_slug text;
begin
  if exists(select 1 from app_records where collection='bookingLinks' and coalesce((data->>'published')::boolean,false)=true and nullif(trim(data->>'slug'),'') is null)
  then raise exception 'Cannot enforce published booking slug uniqueness; a published booking link has no slug' using errcode='check_violation'; end if;
  select lower(trim(data->>'slug')) into duplicate_slug from app_records
  where collection='bookingLinks' and coalesce((data->>'published')::boolean,false)=true and nullif(trim(data->>'slug'),'') is not null
  group by lower(trim(data->>'slug')) having count(*)>1 limit 1;
  if duplicate_slug is not null then raise exception 'Cannot enforce published booking slug uniqueness; duplicate slug: %',duplicate_slug using errcode='unique_violation'; end if;
end;
$$;

create unique index if not exists app_records_published_booking_slug_uidx
on app_records (lower(trim(data->>'slug')))
where collection='bookingLinks' and coalesce((data->>'published')::boolean,false)=true and nullif(trim(data->>'slug'),'') is not null;

create or replace function app_record_allowed(p_collection text,p_action text,p_data jsonb default '{}'::jsonb)
returns boolean language plpgsql stable security definer set search_path=public as $$
declare role_name text:=current_staff_role(); actor text:=coalesce(p_data->>'collectorUserId',p_data->>'collectedBy');
begin
  if role_name='administrator' then return true; end if;
  if role_name='practitioner' and p_collection in ('appointments','visits','treatmentPlans') then return false; end if;
  if p_action='select' then return case
    when p_collection in ('_clinic','doctors','treatments','bookingLinks','staff','roles') then true
    when p_collection='appointments' then has_permission('appointments.view')
    when p_collection='payments' then has_permission('payments.view.all') or (has_permission('payments.view.own') and actor=auth.uid()::text)
    when p_collection in ('visits','treatmentPlans') then has_permission('clinical.view')
    when p_collection='priceRequests' then has_permission('priceRequests.approve') or (has_permission('priceRequests.create') and p_data->>'requestedBy'=auth.uid()::text)
    when p_collection='collectionSessions' then has_permission('sessions.manage') or (has_permission('sessions.own') and p_data->>'openedBy'=auth.uid()::text)
    when p_collection='auditEvents' then has_permission('audit.view') else false end;
  elsif p_action='insert' then return case
    when p_collection='appointments' then has_permission('appointments.create')
    when p_collection='payments' then has_permission('payments.collect') and actor=auth.uid()::text
    when p_collection='visits' then has_permission('clinical.edit')
    when p_collection='treatmentPlans' then has_permission('plans.create')
    when p_collection='priceRequests' then has_permission('priceRequests.create') and p_data->>'requestedBy'=auth.uid()::text
    when p_collection='collectionSessions' then has_permission('sessions.own') and p_data->>'openedBy'=auth.uid()::text
    when p_collection in ('doctors','treatments','bookingLinks','_clinic') then has_permission('settings.manage') or has_permission('services.manage')
    when p_collection in ('staff','roles') then has_permission('staff.manage') or has_permission('permissions.manage') else false end;
  elsif p_action='update' then return case
    when p_collection='appointments' then has_permission('appointments.edit')
    when p_collection='payments' then has_permission('payments.correct')
    when p_collection in ('visits','treatmentPlans') then has_permission('clinical.edit')
    when p_collection='priceRequests' then has_permission('priceRequests.approve')
    when p_collection='collectionSessions' then has_permission('sessions.manage') or (has_permission('sessions.own') and p_data->>'openedBy'=auth.uid()::text)
    when p_collection in ('doctors','treatments','bookingLinks','_clinic') then has_permission('settings.manage') or has_permission('services.manage')
    when p_collection in ('staff','roles') then has_permission('staff.manage') or has_permission('permissions.manage') else false end;
  elsif p_action='delete' then return role_name='administrator'; end if;
  return false;
end;
$$;

revoke all on function current_practitioner_app_id() from public,anon,authenticated;
grant execute on function current_practitioner_app_id() to authenticated;
revoke all on function normalize_published_booking_slug() from public,anon,authenticated;
revoke all on function app_record_allowed(text,text,jsonb) from public,anon,authenticated;
grant execute on function app_record_allowed(text,text,jsonb) to authenticated;

create or replace function record_clinical_visit(p_patient_app_id text,p_practitioner_app_id text,p_notes text,p_follow_up text default null,p_service_app_id text default null,p_create_plan boolean default true)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); patient patients%rowtype; practitioner practitioners%rowtype; service services%rowtype;
  visit clinical_visits%rowtype; plan treatment_plans%rowtype; item treatment_plan_items%rowtype; visit_app text:=gen_random_uuid()::text; plan_app text:=gen_random_uuid()::text;
begin
  if clinic is null or not has_permission('clinical.edit') then raise exception 'Clinical edit denied'; end if;
  if length(trim(coalesce(p_notes,'')))<2 then raise exception 'Clinical notes are required'; end if;
  select * into patient from patients where clinic_id=clinic and app_id=p_patient_app_id;
  select * into practitioner from practitioners where clinic_id=clinic and app_id=p_practitioner_app_id and active=true;
  if patient.id is null or practitioner.id is null then raise exception 'Patient or practitioner not found'; end if;
  if current_staff_role()='practitioner' then
    if practitioner.staff_id is distinct from auth.uid() then raise exception 'Practitioner assignment denied'; end if;
    if not exists(select 1 from appointments a where a.clinic_id=clinic and a.patient_id=patient.id and a.practitioner_id=practitioner.id and a.status not in ('Annulé','No-show')
      union all select 1 from clinical_visits v where v.clinic_id=clinic and v.patient_id=patient.id and v.practitioner_id=practitioner.id)
    then raise exception 'Patient is not assigned to practitioner'; end if;
  end if;
  if nullif(p_service_app_id,'') is not null then
    select * into service from services where clinic_id=clinic and app_id=p_service_app_id and active=true;
    if service.id is null then raise exception 'Service not found'; end if;
  end if;
  insert into clinical_visits(clinic_id,app_id,patient_id,practitioner_id,service_id,visit_date,notes,follow_up,status)
  values(clinic,visit_app,patient.id,practitioner.id,service.id,current_date,trim(p_notes),nullif(trim(coalesce(p_follow_up,'')),''),'Terminé') returning * into visit;
  if service.id is not null and p_create_plan then
    insert into treatment_plans(clinic_id,app_id,patient_id,practitioner_id,visit_id,status,plan_date,original_total,total)
    values(clinic,plan_app,patient.id,practitioner.id,visit.id,'Proposé',current_date,service.standard_price,service.standard_price) returning * into plan;
    insert into treatment_plan_items(plan_id,app_id,service_id,quantity,original_price,status) values(plan.id,gen_random_uuid()::text,service.id,1,service.standard_price,'Proposé') returning * into item;
  end if;
  return jsonb_build_object('visit',clinical_visit_json(visit.id),'plan',case when plan.id is null then null else treatment_plan_json(plan.id) end);
end;
$$;

revoke all on function record_clinical_visit(text,text,text,text,text,boolean) from public,anon,authenticated;
grant execute on function record_clinical_visit(text,text,text,text,text,boolean) to authenticated;
