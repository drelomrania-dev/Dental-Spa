-- Normalized clinical visits, treatment plans and negotiated-price approvals.

alter table practitioners add column if not exists app_id text;
alter table services add column if not exists app_id text;
alter table clinical_visits add column if not exists app_id text;
alter table clinical_visits add column if not exists service_id uuid references services(id);
alter table treatment_plans add column if not exists app_id text;
alter table treatment_plans add column if not exists visit_id uuid references clinical_visits(id);
alter table treatment_plans add column if not exists plan_date date not null default current_date;
alter table treatment_plans add column if not exists original_total numeric(12,2) not null default 0;
alter table treatment_plans add column if not exists total numeric(12,2) not null default 0;
alter table treatment_plan_items add column if not exists app_id text;
alter table price_requests add column if not exists app_id text;
alter table price_requests add column if not exists service_id uuid references services(id);
alter table price_requests add column if not exists plan_id uuid references treatment_plans(id);

update practitioners set app_id=id::text where app_id is null;
update services set app_id=id::text where app_id is null;
update clinical_visits set app_id=id::text where app_id is null;
update treatment_plans set app_id=id::text where app_id is null;
update treatment_plan_items set app_id=id::text where app_id is null;
update price_requests set app_id=id::text where app_id is null;

create unique index if not exists practitioners_clinic_app_id_uidx on practitioners(clinic_id,app_id);
create unique index if not exists services_clinic_app_id_uidx on services(clinic_id,app_id);
create unique index if not exists clinical_visits_clinic_app_id_uidx on clinical_visits(clinic_id,app_id);
create unique index if not exists treatment_plans_clinic_app_id_uidx on treatment_plans(clinic_id,app_id);
create unique index if not exists treatment_plan_items_plan_app_id_uidx on treatment_plan_items(plan_id,app_id);
create unique index if not exists price_requests_clinic_app_id_uidx on price_requests(clinic_id,app_id);

create index if not exists clinical_visits_patient_idx on clinical_visits(patient_id,visit_date desc);
create index if not exists clinical_visits_practitioner_idx on clinical_visits(practitioner_id,visit_date desc) where practitioner_id is not null;
create index if not exists clinical_visits_service_idx on clinical_visits(service_id) where service_id is not null;
create index if not exists treatment_plans_patient_idx on treatment_plans(patient_id,created_at desc);
create index if not exists treatment_plans_practitioner_idx on treatment_plans(practitioner_id) where practitioner_id is not null;
create index if not exists treatment_plans_visit_idx on treatment_plans(visit_id) where visit_id is not null;
create index if not exists treatment_plan_items_service_idx on treatment_plan_items(service_id);
create index if not exists price_requests_patient_idx on price_requests(patient_id,created_at desc);
create index if not exists price_requests_service_idx on price_requests(service_id) where service_id is not null;
create index if not exists price_requests_plan_idx on price_requests(plan_id) where plan_id is not null;
create index if not exists price_requests_plan_item_idx on price_requests(plan_item_id) where plan_item_id is not null;
create index if not exists price_requests_requested_by_idx on price_requests(requested_by,created_at desc);
create index if not exists price_requests_decided_by_idx on price_requests(decided_by) where decided_by is not null;

insert into practitioners(clinic_id,app_id,name,specialty,availability,active)
select r.clinic_id,r.id,coalesce(nullif(r.data->>'name',''),'Praticien'),nullif(r.data->>'specialty',''),
  jsonb_build_object('label',coalesce(r.data->>'availability',''),'phone',coalesce(r.data->>'phone',''),'email',coalesce(r.data->>'email',''),'color',coalesce(r.data->>'color','')),
  coalesce((r.data->>'active')::boolean,true)
from app_records r where r.collection='doctors'
on conflict(clinic_id,app_id) do update set name=excluded.name,specialty=excluded.specialty,availability=excluded.availability,active=excluded.active;

insert into services(clinic_id,app_id,name,description,category,standard_price,duration_minutes,active,booking_eligible)
select r.clinic_id,r.id,coalesce(nullif(r.data->>'name',''),'Service'),nullif(r.data->>'description',''),nullif(r.data->>'category',''),
  case when coalesce(r.data->>'price','') ~ '^\d+(\.\d{1,2})?$' then (r.data->>'price')::numeric else 0 end,
  case when coalesce(r.data->>'duration','') ~ '^\d+$' then greatest((r.data->>'duration')::integer,1) else 30 end,
  coalesce((r.data->>'active')::boolean,true),coalesce((r.data->>'bookingEligible')::boolean,true)
from app_records r where r.collection='treatments'
on conflict(clinic_id,app_id) do update set name=excluded.name,description=excluded.description,category=excluded.category,standard_price=excluded.standard_price,duration_minutes=excluded.duration_minutes,active=excluded.active,booking_eligible=excluded.booking_eligible;

insert into clinical_visits(clinic_id,app_id,patient_id,practitioner_id,service_id,visit_date,notes,follow_up,status,created_at)
select r.clinic_id,r.id,p.id,pr.id,sv.id,
  case when coalesce(r.data->>'date','') ~ '^\d{4}-\d{2}-\d{2}$' then (r.data->>'date')::date else r.created_at::date end,
  coalesce(nullif(r.data->>'notes',''),'Note clinique importée'),nullif(r.data->>'followUp',''),coalesce(nullif(r.data->>'status',''),'Terminé'),r.created_at
from app_records r
join patients p on p.clinic_id=r.clinic_id and p.app_id=r.data->>'patientId'
left join practitioners pr on pr.clinic_id=r.clinic_id and pr.app_id=r.data->>'doctorId'
left join services sv on sv.clinic_id=r.clinic_id and sv.app_id=r.data->'services'->0->>'treatmentId'
where r.collection='visits'
on conflict(clinic_id,app_id) do nothing;

insert into treatment_plans(clinic_id,app_id,patient_id,practitioner_id,visit_id,status,plan_date,original_total,total,created_at)
select r.clinic_id,r.id,p.id,pr.id,v.id,coalesce(nullif(r.data->>'status',''),'Proposé'),
  case when coalesce(r.data->>'date','') ~ '^\d{4}-\d{2}-\d{2}$' then (r.data->>'date')::date else r.created_at::date end,
  case when coalesce(r.data->>'originalTotal','') ~ '^\d+(\.\d{1,2})?$' then (r.data->>'originalTotal')::numeric else 0 end,
  case when coalesce(r.data->>'total','') ~ '^\d+(\.\d{1,2})?$' then (r.data->>'total')::numeric else 0 end,r.created_at
from app_records r
join patients p on p.clinic_id=r.clinic_id and p.app_id=r.data->>'patientId'
left join practitioners pr on pr.clinic_id=r.clinic_id and pr.app_id=r.data->>'doctorId'
left join clinical_visits v on v.clinic_id=r.clinic_id and v.app_id=r.data->>'visitId'
where r.collection='treatmentPlans'
on conflict(clinic_id,app_id) do nothing;

insert into treatment_plan_items(plan_id,app_id,service_id,quantity,original_price,approved_price,status)
select plan.id,coalesce(nullif(item->>'id',''),gen_random_uuid()::text),sv.id,
  case when coalesce(item->>'quantity','') ~ '^\d+(\.\d+)?$' then (item->>'quantity')::numeric else 1 end,
  case when coalesce(item->>'originalPrice','') ~ '^\d+(\.\d{1,2})?$' then (item->>'originalPrice')::numeric else sv.standard_price end,
  case when coalesce(item->>'effectivePrice','') ~ '^\d+(\.\d{1,2})?$' and (item->>'effectivePrice')::numeric<>coalesce(nullif(item->>'originalPrice','')::numeric,sv.standard_price) then (item->>'effectivePrice')::numeric else null end,
  coalesce(nullif(item->>'status',''),'Proposé')
from app_records r
join treatment_plans plan on plan.clinic_id=r.clinic_id and plan.app_id=r.id
cross join lateral jsonb_array_elements(coalesce(r.data->'items','[]'::jsonb)) item
join services sv on sv.clinic_id=r.clinic_id and sv.app_id=item->>'treatmentId'
where r.collection='treatmentPlans'
on conflict(plan_id,app_id) do nothing;

insert into price_requests(clinic_id,app_id,patient_id,service_id,plan_id,plan_item_id,standard_price,proposed_price,reason,requested_by,decided_by,status,decision_reason,created_at,decided_at)
select r.clinic_id,r.id,p.id,sv.id,plan.id,item.id,
  case when coalesce(r.data->>'standardPrice','') ~ '^\d+(\.\d{1,2})?$' then (r.data->>'standardPrice')::numeric else sv.standard_price end,
  case when coalesce(r.data->>'proposedPrice','') ~ '^\d+(\.\d{1,2})?$' then (r.data->>'proposedPrice')::numeric else sv.standard_price end,
  coalesce(nullif(r.data->>'reason',''),'Demande importée'),requester.id,decider.id,coalesce(nullif(r.data->>'status',''),'Pending'),nullif(r.data->>'decisionReason',''),
  coalesce(case when coalesce(r.data->>'requestedAt','') ~ '^\d{4}-\d{2}-\d{2}' then (r.data->>'requestedAt')::timestamptz end,r.created_at),
  case when coalesce(r.data->>'decidedAt','') ~ '^\d{4}-\d{2}-\d{2}' then (r.data->>'decidedAt')::timestamptz end
from app_records r
join patients p on p.clinic_id=r.clinic_id and p.app_id=r.data->>'patientId'
join services sv on sv.clinic_id=r.clinic_id and sv.app_id=r.data->>'treatmentId'
join staff_profiles requester on requester.clinic_id=r.clinic_id and requester.id::text=r.data->>'requestedBy'
left join staff_profiles decider on decider.clinic_id=r.clinic_id and decider.id::text=r.data->>'decidedBy'
left join treatment_plans plan on plan.clinic_id=r.clinic_id and plan.app_id=r.data->>'planId'
left join treatment_plan_items item on item.plan_id=plan.id and item.app_id=r.data->>'planItemId'
where r.collection='priceRequests'
on conflict(clinic_id,app_id) do nothing;

create or replace function clinical_visit_json(p_id uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object('id',v.app_id,'patientId',p.app_id,'doctorId',coalesce(pr.app_id,''),'date',v.visit_date,
    'notes',v.notes,'followUp',coalesce(v.follow_up,''),'status',v.status,
    'services',case when sv.id is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('treatmentId',sv.app_id,'name',sv.name,'price',sv.standard_price)) end)
  from clinical_visits v join patients p on p.id=v.patient_id left join practitioners pr on pr.id=v.practitioner_id left join services sv on sv.id=v.service_id where v.id=p_id
$$;

create or replace function treatment_plan_json(p_id uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object('id',plan.app_id,'patientId',p.app_id,'doctorId',coalesce(pr.app_id,''),'visitId',coalesce(v.app_id,''),'date',plan.plan_date,
    'status',plan.status,'originalTotal',plan.original_total,'total',plan.total,
    'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.app_id,'treatmentId',sv.app_id,'name',sv.name,'quantity',i.quantity,'originalPrice',i.original_price,'effectivePrice',coalesce(i.approved_price,i.original_price),'status',i.status) order by i.id) from treatment_plan_items i join services sv on sv.id=i.service_id where i.plan_id=plan.id),'[]'::jsonb))
  from treatment_plans plan join patients p on p.id=plan.patient_id left join practitioners pr on pr.id=plan.practitioner_id left join clinical_visits v on v.id=plan.visit_id where plan.id=p_id
$$;

create or replace function clinical_price_request_json(p_id uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object('id',r.app_id,'patientId',p.app_id,'treatmentId',sv.app_id,'planId',coalesce(plan.app_id,''),'planItemId',coalesce(item.app_id,''),
    'standardPrice',r.standard_price,'proposedPrice',r.proposed_price,'discountAmount',r.standard_price-r.proposed_price,
    'discountPercent',case when r.standard_price=0 then 0 else round((1-r.proposed_price/r.standard_price)*100) end,
    'reason',r.reason,'requestedBy',r.requested_by,'requestedAt',to_char(r.created_at at time zone 'Africa/Casablanca','YYYY-MM-DD'),
    'status',r.status,'decidedBy',r.decided_by,'decidedAt',case when r.decided_at is null then null else to_char(r.decided_at at time zone 'Africa/Casablanca','YYYY-MM-DD') end,'decisionReason',coalesce(r.decision_reason,''))
  from price_requests r join patients p on p.id=r.patient_id join services sv on sv.id=r.service_id
  left join treatment_plans plan on plan.id=r.plan_id left join treatment_plan_items item on item.id=r.plan_item_id where r.id=p_id
$$;

create or replace function clinical_snapshot()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); role_name text:=current_staff_role(); practitioner uuid;
begin
  if clinic is null then raise exception 'Authentication required'; end if;
  select id into practitioner from practitioners where clinic_id=clinic and staff_id=auth.uid() limit 1;
  return jsonb_build_object(
    'visits',case when has_permission('clinical.view') then coalesce((select jsonb_agg(clinical_visit_json(v.id) order by v.visit_date desc,v.created_at desc) from clinical_visits v where v.clinic_id=clinic and (role_name<>'practitioner' or v.practitioner_id=practitioner)),'[]'::jsonb) else '[]'::jsonb end,
    'plans',case when has_permission('clinical.view') or has_permission('plans.create') or has_permission('priceRequests.create') or has_permission('priceRequests.approve') then coalesce((select jsonb_agg(treatment_plan_json(p.id) order by p.created_at desc) from treatment_plans p where p.clinic_id=clinic and (role_name<>'practitioner' or p.practitioner_id=practitioner)),'[]'::jsonb) else '[]'::jsonb end,
    'priceRequests',case when has_permission('priceRequests.approve') or has_permission('priceRequests.create') then coalesce((select jsonb_agg(clinical_price_request_json(r.id) order by r.created_at desc) from price_requests r where r.clinic_id=clinic and (has_permission('priceRequests.approve') or r.requested_by=auth.uid())),'[]'::jsonb) else '[]'::jsonb end
  );
end;
$$;

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
  if current_staff_role()='practitioner' and practitioner.staff_id is distinct from auth.uid() then raise exception 'Practitioner assignment denied'; end if;
  if nullif(p_service_app_id,'') is not null then
    select * into service from services where clinic_id=clinic and app_id=p_service_app_id and active=true;
    if service.id is null then raise exception 'Service not found'; end if;
  end if;
  insert into clinical_visits(clinic_id,app_id,patient_id,practitioner_id,service_id,visit_date,notes,follow_up,status)
  values(clinic,visit_app,patient.id,practitioner.id,service.id,current_date,trim(p_notes),nullif(trim(coalesce(p_follow_up,'')),''),'Terminé') returning * into visit;
  if service.id is not null and p_create_plan then
    insert into treatment_plans(clinic_id,app_id,patient_id,practitioner_id,visit_id,status,plan_date,original_total,total)
    values(clinic,plan_app,patient.id,practitioner.id,visit.id,'Proposé',current_date,service.standard_price,service.standard_price) returning * into plan;
    insert into treatment_plan_items(plan_id,app_id,service_id,quantity,original_price,status)
    values(plan.id,gen_random_uuid()::text,service.id,1,service.standard_price,'Proposé') returning * into item;
  end if;
  return jsonb_build_object('visit',clinical_visit_json(visit.id),'plan',case when plan.id is null then null else treatment_plan_json(plan.id) end);
end;
$$;

create or replace function create_clinical_price_request(p_patient_app_id text,p_service_app_id text,p_plan_app_id text,p_plan_item_app_id text,p_proposed_price numeric,p_reason text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); patient patients%rowtype; service services%rowtype; plan treatment_plans%rowtype; item treatment_plan_items%rowtype; request price_requests%rowtype;
begin
  if clinic is null or not has_permission('priceRequests.create') then raise exception 'Price request creation denied'; end if;
  if length(trim(coalesce(p_reason,'')))<4 then raise exception 'A justification is required'; end if;
  select * into patient from patients where clinic_id=clinic and app_id=p_patient_app_id;
  select * into service from services where clinic_id=clinic and app_id=p_service_app_id and active=true;
  if patient.id is null or service.id is null then raise exception 'Patient or service not found'; end if;
  if p_proposed_price is null or p_proposed_price<0 or p_proposed_price>=service.standard_price then raise exception 'Proposed price must be below the standard price'; end if;
  if nullif(p_plan_app_id,'') is not null then
    select * into plan from treatment_plans where clinic_id=clinic and app_id=p_plan_app_id and patient_id=patient.id;
    if plan.id is null then raise exception 'Treatment plan not found'; end if;
    select * into item from treatment_plan_items where plan_id=plan.id and app_id=p_plan_item_app_id and service_id=service.id;
    if item.id is null then raise exception 'Treatment plan item not found'; end if;
  end if;
  if exists(select 1 from price_requests where clinic_id=clinic and patient_id=patient.id and service_id=service.id and requested_by=auth.uid() and status='Pending') then raise exception 'A pending request already exists'; end if;
  insert into price_requests(clinic_id,app_id,patient_id,service_id,plan_id,plan_item_id,standard_price,proposed_price,reason,requested_by,status)
  values(clinic,gen_random_uuid()::text,patient.id,service.id,plan.id,item.id,service.standard_price,round(p_proposed_price,2),trim(p_reason),auth.uid(),'Pending') returning * into request;
  return clinical_price_request_json(request.id);
end;
$$;

create or replace function decide_clinical_price_request(p_request_app_id text,p_status text,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); request price_requests%rowtype; plan treatment_plans%rowtype;
begin
  if clinic is null or not has_permission('priceRequests.approve') then raise exception 'Price request approval denied'; end if;
  if p_status not in ('Approved','Rejected') then raise exception 'Invalid decision'; end if;
  select * into request from price_requests where clinic_id=clinic and app_id=p_request_app_id and status='Pending' for update;
  if request.id is null then raise exception 'Pending price request not found'; end if;
  if request.requested_by=auth.uid() then raise exception 'Self approval is not allowed'; end if;
  update price_requests set status=p_status,decided_by=auth.uid(),decided_at=now(),decision_reason=coalesce(nullif(trim(coalesce(p_reason,'')),''),case when p_status='Approved' then 'Prix approuvé' else 'Prix non validé' end) where id=request.id returning * into request;
  if p_status='Approved' and request.plan_item_id is not null then
    update treatment_plan_items set approved_price=request.proposed_price,status='Approuvé' where id=request.plan_item_id;
    update treatment_plans p set total=(select coalesce(sum(coalesce(i.approved_price,i.original_price)*i.quantity),0) from treatment_plan_items i where i.plan_id=p.id),status='Accepté' where p.id=request.plan_id returning * into plan;
  end if;
  return jsonb_build_object('request',clinical_price_request_json(request.id),'plan',case when plan.id is null then null else treatment_plan_json(plan.id) end);
end;
$$;

-- Finance resolves newly approved negotiated prices and the normalized service catalogue first.
create or replace function finance_resolved_price(p_clinic uuid,p_patient text,p_treatment text)
returns numeric language plpgsql stable security definer set search_path=public as $$
declare result numeric;
begin
  select r.proposed_price into result from price_requests r join patients p on p.id=r.patient_id join services s on s.id=r.service_id
  where r.clinic_id=p_clinic and p.app_id=p_patient and s.app_id=p_treatment and r.status='Approved' order by r.decided_at desc nulls last,r.created_at desc limit 1;
  if result is not null then return result; end if;
  select standard_price into result from services where clinic_id=p_clinic and app_id=p_treatment and active=true limit 1;
  if result is not null then return result; end if;
  select case when data->>'proposedPrice' ~ '^\d+(\.\d{1,2})?$' then (data->>'proposedPrice')::numeric end into result from app_records
  where clinic_id=p_clinic and collection='priceRequests' and data->>'patientId'=p_patient and data->>'treatmentId'=p_treatment and data->>'status'='Approved' order by coalesce(data->>'decidedAt',data->>'createdAt','') desc limit 1;
  if result is not null then return result; end if;
  select case when data->>'price' ~ '^\d+(\.\d{1,2})?$' then (data->>'price')::numeric end into result from app_records where clinic_id=p_clinic and collection='treatments' and id=p_treatment limit 1;
  return result;
end;
$$;

revoke all on practitioners,services,clinical_visits,treatment_plans,treatment_plan_items,price_requests from anon,authenticated;
drop policy if exists practitioners_rpc_only on practitioners;
create policy practitioners_rpc_only on practitioners for all to public using(false) with check(false);
drop policy if exists services_rpc_only on services;
create policy services_rpc_only on services for all to public using(false) with check(false);
drop policy if exists clinical_visits_rpc_only on clinical_visits;
create policy clinical_visits_rpc_only on clinical_visits for all to public using(false) with check(false);
drop policy if exists treatment_plans_rpc_only on treatment_plans;
create policy treatment_plans_rpc_only on treatment_plans for all to public using(false) with check(false);
drop policy if exists treatment_plan_items_rpc_only on treatment_plan_items;
create policy treatment_plan_items_rpc_only on treatment_plan_items for all to public using(false) with check(false);
drop policy if exists price_requests_rpc_only on price_requests;
create policy price_requests_rpc_only on price_requests for all to public using(false) with check(false);

revoke all on function clinical_visit_json(uuid),treatment_plan_json(uuid),clinical_price_request_json(uuid),clinical_snapshot(),record_clinical_visit(text,text,text,text,text,boolean),create_clinical_price_request(text,text,text,text,numeric,text),decide_clinical_price_request(text,text,text) from public,anon,authenticated;
grant execute on function clinical_snapshot(),record_clinical_visit(text,text,text,text,text,boolean),create_clinical_price_request(text,text,text,text,numeric,text),decide_clinical_price_request(text,text,text) to authenticated;
