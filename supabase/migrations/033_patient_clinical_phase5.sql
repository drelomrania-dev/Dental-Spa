-- Phase 5: appointment-linked clinical work and price decisions.

create unique index if not exists clinical_visits_one_appointment_idx on clinical_visits(appointment_id) where appointment_id is not null;

create table if not exists clinical_visit_revisions (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id),
  visit_id uuid not null references clinical_visits(id),
  previous_notes text not null,
  previous_follow_up text,
  changed_by uuid not null references staff_profiles(id),
  changed_at timestamptz not null default now()
);
create index if not exists clinical_visit_revisions_visit_idx on clinical_visit_revisions(visit_id,changed_at desc);
alter table clinical_visit_revisions enable row level security;
revoke all on clinical_visit_revisions from anon,authenticated;

create or replace function patient_is_assigned(p_patient_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select current_staff_role()<>'practitioner' or exists(
    select 1 from appointments a join practitioners pr on pr.id=a.practitioner_id
    where a.patient_id=p_patient_id and a.status not in ('Annulé','No-show') and pr.staff_id=auth.uid()
    union all
    select 1 from clinical_visits v join practitioners pr on pr.id=v.practitioner_id
    where v.patient_id=p_patient_id and pr.staff_id=auth.uid()
  )
$$;

create or replace function clinical_visit_json(p_id uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object('id',v.app_id,'patientId',p.app_id,'doctorId',coalesce(pr.app_id,''),
    'appointmentId',coalesce(a.app_id,''),'date',v.visit_date,'notes',v.notes,
    'followUp',coalesce(v.follow_up,''),'status',v.status,
    'services',case when sv.id is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('treatmentId',sv.app_id,'name',sv.name,'price',sv.standard_price)) end)
  from clinical_visits v join patients p on p.id=v.patient_id
  left join practitioners pr on pr.id=v.practitioner_id
  left join appointments a on a.id=v.appointment_id
  left join services sv on sv.id=v.service_id where v.id=p_id
$$;

create or replace function clinical_snapshot()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); role_name text:=current_staff_role(); practitioner uuid;
begin
  if clinic is null then raise exception 'Authentication required'; end if;
  select id into practitioner from practitioners where clinic_id=clinic and staff_id=auth.uid() limit 1;
  return jsonb_build_object(
    'visits',case when has_permission('clinical.view') then coalesce((select jsonb_agg(clinical_visit_json(v.id) order by v.visit_date desc,v.created_at desc) from clinical_visits v where v.clinic_id=clinic and (role_name<>'practitioner' or v.practitioner_id=practitioner)),'[]'::jsonb) else '[]'::jsonb end,
    'plans',case when has_permission('clinical.view') or has_permission('plans.create') then coalesce((select jsonb_agg(treatment_plan_json(p.id) order by p.created_at desc) from treatment_plans p where p.clinic_id=clinic and (role_name<>'practitioner' or p.practitioner_id=practitioner)),'[]'::jsonb) else '[]'::jsonb end,
    'priceTargets',case when has_permission('priceRequests.create') then coalesce((select jsonb_agg(jsonb_build_object('planId',p.app_id,'planItemId',i.app_id,'patientId',patient.app_id,'treatmentId',s.app_id,'standardPrice',i.original_price) order by p.created_at desc) from treatment_plan_items i join treatment_plans p on p.id=i.plan_id join patients patient on patient.id=p.patient_id join services s on s.id=i.service_id where p.clinic_id=clinic and (role_name<>'practitioner' or p.practitioner_id=practitioner)),'[]'::jsonb) else '[]'::jsonb end,
    'priceRequests',case when has_permission('priceRequests.approve') or has_permission('priceRequests.create') then coalesce((select jsonb_agg(clinical_price_request_json(r.id) order by r.created_at desc) from price_requests r where r.clinic_id=clinic and (has_permission('priceRequests.approve') or r.requested_by=auth.uid())),'[]'::jsonb) else '[]'::jsonb end
  );
end;
$$;

create or replace function patient_timeline_snapshot(p_app_id text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); patient patients%rowtype; practitioner uuid; role_name text:=current_staff_role();
begin
  if clinic is null or not has_permission('patients.basic.view') then raise exception 'Patient access denied'; end if;
  select * into patient from patients where clinic_id=clinic and app_id=p_app_id;
  if patient.id is null or not patient_is_assigned(patient.id) then raise exception 'Patient not found or not assigned'; end if;
  select id into practitioner from practitioners where clinic_id=clinic and staff_id=auth.uid() limit 1;
  return jsonb_build_object(
    'appointments',case when has_permission('appointments.view') then coalesce((select jsonb_agg(appointment_json(a.id) order by a.starts_at desc) from appointments a where a.clinic_id=clinic and a.patient_id=patient.id and (role_name<>'practitioner' or a.practitioner_id=practitioner)),'[]'::jsonb) else '[]'::jsonb end,
    'visits',case when has_permission('clinical.view') then coalesce((select jsonb_agg(clinical_visit_json(v.id) order by v.visit_date desc,v.created_at desc) from clinical_visits v where v.clinic_id=clinic and v.patient_id=patient.id and (role_name<>'practitioner' or v.practitioner_id=practitioner)),'[]'::jsonb) else '[]'::jsonb end,
    'plans',case when has_permission('clinical.view') then coalesce((select jsonb_agg(treatment_plan_json(p.id) order by p.created_at desc) from treatment_plans p where p.clinic_id=clinic and p.patient_id=patient.id and (role_name<>'practitioner' or p.practitioner_id=practitioner)),'[]'::jsonb) else '[]'::jsonb end,
    'payments',case when has_permission('payments.view.all') or has_permission('payments.view.own') then coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'date',to_char(t.occurred_at at time zone 'Africa/Casablanca','YYYY-MM-DD'),'reference',t.reference,'treatmentId',a.treatment_id,'paid',finance_effect(t.kind,t.amount),'kind',t.kind) order by t.occurred_at desc) from finance_transactions t join finance_accounts a on a.id=t.account_id where t.clinic_id=clinic and a.patient_app_id=patient.app_id and (has_permission('payments.view.all') or t.collected_by=auth.uid())),'[]'::jsonb) else '[]'::jsonb end
  );
end;
$$;

drop function if exists record_clinical_visit(text,text,text,text,text,boolean);
create function record_clinical_visit(p_patient_app_id text,p_practitioner_app_id text,p_notes text,p_follow_up text default null,p_service_app_id text default null,p_create_plan boolean default true,p_appointment_app_id text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); patient patients%rowtype; practitioner practitioners%rowtype; service services%rowtype;
  appointment appointments%rowtype; visit clinical_visits%rowtype; plan treatment_plans%rowtype;
begin
  if clinic is null or not has_permission('clinical.edit') then raise exception 'Clinical edit denied'; end if;
  if length(trim(coalesce(p_notes,'')))<2 then raise exception 'Clinical notes are required'; end if;
  select * into patient from patients where clinic_id=clinic and app_id=p_patient_app_id;
  select * into practitioner from practitioners where clinic_id=clinic and app_id=p_practitioner_app_id and active=true;
  if patient.id is null or practitioner.id is null then raise exception 'Patient or practitioner not found'; end if;
  if current_staff_role()='practitioner' and practitioner.staff_id is distinct from auth.uid() then raise exception 'Practitioner assignment denied'; end if;
  if current_staff_role()='practitioner' and not patient_is_assigned(patient.id) then raise exception 'Patient not assigned'; end if;
  if nullif(p_appointment_app_id,'') is not null then
    select * into appointment from appointments where clinic_id=clinic and app_id=p_appointment_app_id and patient_id=patient.id and practitioner_id=practitioner.id for update;
    if appointment.id is null or appointment.status in ('Annulé','No-show') then raise exception 'Appointment not found or unavailable'; end if;
    if appointment.starts_at>now() then raise exception 'Appointment has not started'; end if;
    if exists(select 1 from clinical_visits where appointment_id=appointment.id) then raise exception 'Appointment already has a visit'; end if;
  end if;
  if nullif(p_service_app_id,'') is not null then
    select * into service from services where clinic_id=clinic and app_id=p_service_app_id and active=true;
    if service.id is null then raise exception 'Service not found'; end if;
  end if;
  if p_create_plan and service.id is not null and not has_permission('plans.create') then raise exception 'Plan creation denied'; end if;
  insert into clinical_visits(clinic_id,app_id,patient_id,practitioner_id,appointment_id,service_id,visit_date,notes,follow_up,status)
  values(clinic,gen_random_uuid()::text,patient.id,practitioner.id,appointment.id,service.id,current_date,trim(p_notes),nullif(trim(coalesce(p_follow_up,'')),''),'Terminé') returning * into visit;
  if service.id is not null and p_create_plan then
    insert into treatment_plans(clinic_id,app_id,patient_id,practitioner_id,visit_id,status,plan_date,original_total,total)
    values(clinic,gen_random_uuid()::text,patient.id,practitioner.id,visit.id,'Proposé',current_date,service.standard_price,service.standard_price) returning * into plan;
    insert into treatment_plan_items(plan_id,app_id,service_id,quantity,original_price,status)
    values(plan.id,gen_random_uuid()::text,service.id,1,service.standard_price,'Proposé');
  end if;
  return jsonb_build_object('visit',clinical_visit_json(visit.id),'plan',case when plan.id is null then null else treatment_plan_json(plan.id) end);
end;
$$;

create or replace function update_clinical_visit(p_visit_app_id text,p_notes text,p_follow_up text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); visit clinical_visits%rowtype; practitioner uuid;
begin
  if clinic is null or not has_permission('clinical.edit') then raise exception 'Clinical edit denied'; end if;
  if length(trim(coalesce(p_notes,'')))<2 then raise exception 'Clinical notes are required'; end if;
  select id into practitioner from practitioners where clinic_id=clinic and staff_id=auth.uid() limit 1;
  select * into visit from clinical_visits where clinic_id=clinic and app_id=p_visit_app_id and (current_staff_role()<>'practitioner' or practitioner_id=practitioner) for update;
  if visit.id is null then raise exception 'Visit not found or not assigned'; end if;
  insert into clinical_visit_revisions(clinic_id,visit_id,previous_notes,previous_follow_up,changed_by)
  values(clinic,visit.id,visit.notes,visit.follow_up,auth.uid());
  update clinical_visits set notes=trim(p_notes),follow_up=nullif(trim(coalesce(p_follow_up,'')),'') where id=visit.id;
  return clinical_visit_json(visit.id);
end;
$$;

create or replace function update_treatment_plan_status(p_plan_app_id text,p_status text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); plan treatment_plans%rowtype; practitioner uuid;
begin
  if clinic is null or not has_permission('plans.create') then raise exception 'Plan update denied'; end if;
  if p_status not in ('Proposé','Accepté','Rejeté') then raise exception 'Invalid plan status'; end if;
  select id into practitioner from practitioners where clinic_id=clinic and staff_id=auth.uid() limit 1;
  select * into plan from treatment_plans where clinic_id=clinic and app_id=p_plan_app_id and (current_staff_role()<>'practitioner' or practitioner_id=practitioner) for update;
  if plan.id is null then raise exception 'Plan not found or not assigned'; end if;
  if exists(select 1 from price_requests where plan_id=plan.id and status='Pending') then raise exception 'Plan has a pending price request'; end if;
  if p_status<>'Accepté' and exists(select 1 from price_requests where plan_id=plan.id and status='Approved') then raise exception 'Approved plan price cannot be reset'; end if;
  update treatment_plans set status=p_status where id=plan.id;
  return treatment_plan_json(plan.id);
end;
$$;

create or replace function create_clinical_price_request(p_patient_app_id text,p_service_app_id text,p_plan_app_id text,p_plan_item_app_id text,p_proposed_price numeric,p_reason text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); patient patients%rowtype; service services%rowtype; plan treatment_plans%rowtype; item treatment_plan_items%rowtype; request price_requests%rowtype; practitioner uuid; standard numeric;
begin
  if clinic is null or not has_permission('priceRequests.create') then raise exception 'Price request creation denied'; end if;
  if length(trim(coalesce(p_reason,'')))<4 then raise exception 'A justification is required'; end if;
  select * into patient from patients where clinic_id=clinic and app_id=p_patient_app_id;
  select * into service from services where clinic_id=clinic and app_id=p_service_app_id and active=true;
  if patient.id is null or service.id is null then raise exception 'Patient or service not found'; end if;
  if current_staff_role()='practitioner' and not patient_is_assigned(patient.id) then raise exception 'Patient not assigned'; end if;
  if nullif(p_plan_app_id,'') is not null then
    select id into practitioner from practitioners where clinic_id=clinic and staff_id=auth.uid() limit 1;
    select * into plan from treatment_plans where clinic_id=clinic and app_id=p_plan_app_id and patient_id=patient.id and (current_staff_role()<>'practitioner' or practitioner_id=practitioner) for update;
    if plan.id is null then raise exception 'Treatment plan not found or not assigned'; end if;
    select * into item from treatment_plan_items where plan_id=plan.id and app_id=p_plan_item_app_id and service_id=service.id;
    if item.id is null then raise exception 'Treatment plan item not found'; end if;
    standard:=item.original_price;
  else
    if nullif(p_plan_item_app_id,'') is not null then raise exception 'Plan item requires a plan'; end if;
    standard:=service.standard_price;
  end if;
  if p_proposed_price is null or p_proposed_price<0 or round(p_proposed_price,2)>=standard then raise exception 'Proposed price must be below the standard price'; end if;
  perform pg_advisory_xact_lock(hashtext(clinic::text||':'||patient.app_id||':'||service.app_id));
  if exists(select 1 from finance_accounts where clinic_id=clinic and patient_app_id=patient.app_id and treatment_id=service.app_id) then raise exception 'Finance account already opened'; end if;
  if exists(select 1 from price_requests where clinic_id=clinic and patient_id=patient.id and service_id=service.id and status in ('Pending','Approved')) then raise exception 'A price request already exists'; end if;
  insert into price_requests(clinic_id,app_id,patient_id,service_id,plan_id,plan_item_id,standard_price,proposed_price,reason,requested_by,status)
  values(clinic,gen_random_uuid()::text,patient.id,service.id,plan.id,item.id,standard,round(p_proposed_price,2),trim(p_reason),auth.uid(),'Pending') returning * into request;
  return clinical_price_request_json(request.id);
end;
$$;

create or replace function decide_clinical_price_request(p_request_app_id text,p_status text,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); request price_requests%rowtype; plan treatment_plans%rowtype; patient_app text; service_app text;
begin
  if clinic is null or not has_permission('priceRequests.approve') then raise exception 'Price request approval denied'; end if;
  if p_status not in ('Approved','Rejected') then raise exception 'Invalid decision'; end if;
  select * into request from price_requests where clinic_id=clinic and app_id=p_request_app_id and status='Pending' for update;
  if request.id is null then raise exception 'Pending price request not found'; end if;
  if request.requested_by=auth.uid() then raise exception 'Self approval is not allowed'; end if;
  select app_id into patient_app from patients where id=request.patient_id;
  select app_id into service_app from services where id=request.service_id;
  perform pg_advisory_xact_lock(hashtext(clinic::text||':'||patient_app||':'||service_app));
  if p_status='Approved' and exists(select 1 from finance_accounts where clinic_id=clinic and patient_app_id=patient_app and treatment_id=service_app) then raise exception 'Finance account already opened'; end if;
  update price_requests set status=p_status,decided_by=auth.uid(),decided_at=now(),decision_reason=coalesce(nullif(trim(coalesce(p_reason,'')),''),case when p_status='Approved' then 'Prix approuvé' else 'Prix non validé' end) where id=request.id returning * into request;
  if p_status='Approved' and request.plan_item_id is not null then
    update treatment_plan_items set approved_price=request.proposed_price,status='Approuvé' where id=request.plan_item_id and approved_price is null;
    if not found then raise exception 'Plan item already priced'; end if;
    update treatment_plans p set total=(select coalesce(sum(coalesce(i.approved_price,i.original_price)*i.quantity),0) from treatment_plan_items i where i.plan_id=p.id),status='Accepté' where p.id=request.plan_id returning * into plan;
  end if;
  return jsonb_build_object('request',clinical_price_request_json(request.id),'plan',case when plan.id is null then null else treatment_plan_json(plan.id) end);
end;
$$;

revoke all on function clinical_visit_json(uuid),patient_timeline_snapshot(text),record_clinical_visit(text,text,text,text,text,boolean,text),update_clinical_visit(text,text,text),update_treatment_plan_status(text,text) from public,anon,authenticated;
grant execute on function patient_timeline_snapshot(text),record_clinical_visit(text,text,text,text,text,boolean,text),update_clinical_visit(text,text,text),update_treatment_plan_status(text,text) to authenticated;
