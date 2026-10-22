-- Transactional Phase 5 boundary and price lifecycle checks. Synthetic records only.
begin;

select set_config('qa.admin',(select id::text from staff_profiles where active and role='administrator' order by created_at limit 1),true);
select set_config('qa.clinic',(select clinic_id::text from staff_profiles where id=current_setting('qa.admin')::uuid),true);
select set_config('qa.assistant',gen_random_uuid()::text,true);
select set_config('qa.practitioner',gen_random_uuid()::text,true);
select set_config('qa.other_admin',gen_random_uuid()::text,true);
select set_config('qa.other_clinic',gen_random_uuid()::text,true);

insert into auth.users(id,aud,role,email,created_at,updated_at)
values (current_setting('qa.assistant')::uuid,'authenticated','authenticated','phase5-assistant@example.invalid',now(),now()),
       (current_setting('qa.practitioner')::uuid,'authenticated','authenticated','phase5-practitioner@example.invalid',now(),now()),
       (current_setting('qa.other_admin')::uuid,'authenticated','authenticated','phase5-other@example.invalid',now(),now());
insert into clinics(id,name) values(current_setting('qa.other_clinic')::uuid,'Phase 5 other clinic');
insert into staff_profiles(id,clinic_id,display_name,role,active)
values(current_setting('qa.assistant')::uuid,current_setting('qa.clinic')::uuid,'Phase 5 assistant','assistant',true),
      (current_setting('qa.practitioner')::uuid,current_setting('qa.clinic')::uuid,'Phase 5 practitioner','practitioner',true),
      (current_setting('qa.other_admin')::uuid,current_setting('qa.other_clinic')::uuid,'Phase 5 other admin','administrator',true);
insert into role_permissions(clinic_id,role,permission,scope)
values(current_setting('qa.clinic')::uuid,'practitioner','priceRequests.create','assigned')
on conflict(clinic_id,role,permission) do update set scope='assigned';
insert into practitioners(clinic_id,app_id,staff_id,name,active)
values(current_setting('qa.clinic')::uuid,'phase5-doctor',current_setting('qa.practitioner')::uuid,'Phase 5 doctor',true),
      (current_setting('qa.clinic')::uuid,'phase5-other-doctor',null,'Phase 5 other doctor',true);
insert into services(clinic_id,app_id,name,standard_price,duration_minutes,active)
values(current_setting('qa.clinic')::uuid,'phase5-service','Phase 5 service',500,30,true);
insert into patients(clinic_id,app_id,first_name,last_name)
values(current_setting('qa.clinic')::uuid,'phase5-assigned','Assigned','Patient'),
      (current_setting('qa.clinic')::uuid,'phase5-unassigned','Unassigned','Patient'),
      (current_setting('qa.clinic')::uuid,'phase5-account-open','Account','Opened');
insert into patient_medical_records(clinic_id,patient_id,medical_alerts)
select clinic_id,id,'Secret phase5 alert' from patients where clinic_id=current_setting('qa.clinic')::uuid and app_id='phase5-assigned';
insert into appointments(clinic_id,app_id,patient_id,practitioner_id,service_id,starts_at,ends_at,status,reference,notes)
select p.clinic_id,'phase5-appointment',p.id,pr.id,s.id,now()-interval '2 hours',now()-interval '1 hour','Terminé','PHASE5-APPOINTMENT','Routine visit'
from patients p join practitioners pr on pr.clinic_id=p.clinic_id and pr.app_id='phase5-doctor'
join services s on s.clinic_id=p.clinic_id and s.app_id='phase5-service'
where p.clinic_id=current_setting('qa.clinic')::uuid and p.app_id='phase5-assigned';

select set_config('request.jwt.claim.sub',current_setting('qa.practitioner'),true);
set local role authenticated;
do $practitioner_checks$
declare result jsonb; snapshot jsonb;
begin
  begin perform patient_timeline_snapshot('phase5-unassigned');raise exception 'Unassigned timeline exposed';
  exception when others then if sqlerrm='Unassigned timeline exposed' then raise; end if; end;
  begin perform record_clinical_visit('phase5-unassigned','phase5-doctor','Forbidden note',null,'phase5-service',true,null);raise exception 'Unassigned visit created';
  exception when others then if sqlerrm='Unassigned visit created' then raise; end if; end;
  begin perform record_clinical_visit('phase5-assigned','phase5-other-doctor','Forbidden note',null,'phase5-service',true,'phase5-appointment');raise exception 'Other practitioner visit created';
  exception when others then if sqlerrm='Other practitioner visit created' then raise; end if; end;
  result:=record_clinical_visit('phase5-assigned','phase5-doctor','First clinical note','Review next week','phase5-service',true,'phase5-appointment');
  if result->'visit'->>'appointmentId'<>'phase5-appointment' or result->'plan'->>'visitId'<>result->'visit'->>'id' then raise exception 'Appointment to visit to plan link failed'; end if;
  if update_clinical_visit(result->'visit'->>'id','Updated clinical note','Review tomorrow')->>'notes'<>'Updated clinical note' then raise exception 'Visit update failed'; end if;
  begin perform record_clinical_visit('phase5-assigned','phase5-doctor','Duplicate note',null,'phase5-service',true,'phase5-appointment');raise exception 'Duplicate visit created';
  exception when others then if sqlerrm='Duplicate visit created' then raise; end if; end;
  snapshot:=patient_timeline_snapshot('phase5-assigned');
  if jsonb_array_length(snapshot->'appointments')<>1 or jsonb_array_length(snapshot->'visits')<>1 or jsonb_array_length(snapshot->'plans')<>1 then raise exception 'Assigned timeline incomplete'; end if;
  if snapshot::text not like '%Updated clinical note%' or snapshot::text like '%Secret phase5 alert%' then raise exception 'Timeline content boundary failed'; end if;
end
$practitioner_checks$;

reset role;
do $revision_check$
begin
  if not exists(select 1 from clinical_visit_revisions r join clinical_visits v on v.id=r.visit_id
    where v.clinic_id=current_setting('qa.clinic')::uuid and v.app_id is not null and r.previous_notes='First clinical note')
  then raise exception 'Previous clinical note was not retained privately'; end if;
end
$revision_check$;
select set_config('request.jwt.claim.sub',current_setting('qa.assistant'),true);
set local role authenticated;
do $assistant_checks$
declare snapshot jsonb; timeline jsonb; target jsonb; request jsonb;
begin
  timeline:=patient_timeline_snapshot('phase5-assigned');
  if jsonb_array_length(timeline->'appointments')<>1 or jsonb_array_length(timeline->'visits')<>0 or jsonb_array_length(timeline->'plans')<>0 then raise exception 'Reception timeline boundary failed'; end if;
  if timeline::text like '%Updated clinical note%' or timeline::text like '%Secret phase5 alert%' then raise exception 'Clinical data leaked to reception'; end if;
  begin perform patient_medical_snapshot('phase5-assigned');raise exception 'Reception medical access granted';
  exception when others then if sqlerrm='Reception medical access granted' then raise; end if; end;
  snapshot:=clinical_snapshot();
  if jsonb_array_length(snapshot->'visits')<>0 or jsonb_array_length(snapshot->'plans')<>0 then raise exception 'Clinical snapshot leaked to reception'; end if;
  select row into target from jsonb_array_elements(snapshot->'priceTargets') row where row->>'patientId'='phase5-assigned' limit 1;
  if target is null then raise exception 'Price target missing'; end if;
  request:=create_clinical_price_request('phase5-assigned','phase5-service',target->>'planId',target->>'planItemId',400,'Phase 5 first request');
  if request->>'status'<>'Pending' then raise exception 'Price request failed'; end if;
  begin perform create_clinical_price_request('phase5-assigned','phase5-service',target->>'planId',target->>'planItemId',390,'Duplicate pending request');raise exception 'Duplicate price request created';
  exception when others then if sqlerrm='Duplicate price request created' then raise; end if; end;
  begin perform create_clinical_price_request('phase5-unassigned','phase5-service',target->>'planId',target->>'planItemId',390,'Wrong patient plan');raise exception 'Wrong patient plan accepted';
  exception when others then if sqlerrm='Wrong patient plan accepted' then raise; end if; end;
  request:=create_clinical_price_request('phase5-account-open','phase5-service',null,null,420,'Account opens before decision');
  perform set_config('qa.account_open_request',request->>'id',true);
end
$assistant_checks$;

reset role;
insert into role_permissions(clinic_id,role,permission,scope)
values(current_setting('qa.clinic')::uuid,'assistant','priceRequests.approve','clinic')
on conflict(clinic_id,role,permission) do update set scope='clinic';
select set_config('request.jwt.claim.sub',current_setting('qa.assistant'),true);
set local role authenticated;
do $self_approval_check$
declare request jsonb;
begin
  select row into request from jsonb_array_elements(clinical_snapshot()->'priceRequests') row where row->>'patientId'='phase5-assigned' and row->>'status'='Pending' limit 1;
  begin perform decide_clinical_price_request(request->>'id','Approved','Self decision');raise exception 'Self approval accepted';
  exception when others then if sqlerrm='Self approval accepted' then raise; end if; end;
end
$self_approval_check$;
reset role;
delete from role_permissions where clinic_id=current_setting('qa.clinic')::uuid and role='assistant' and permission='priceRequests.approve';
insert into finance_accounts(clinic_id,patient_app_id,treatment_id,quoted_total)
values(current_setting('qa.clinic')::uuid,'phase5-account-open','phase5-service',500);

reset role;
select set_config('request.jwt.claim.sub',current_setting('qa.practitioner'),true);
set local role authenticated;
do $unassigned_price_check$
begin
  begin perform create_clinical_price_request('phase5-unassigned','phase5-service',null,null,350,'Unassigned price');raise exception 'Unassigned price request created';
  exception when others then if sqlerrm='Unassigned price request created' then raise; end if; end;
end
$unassigned_price_check$;

reset role;
select set_config('request.jwt.claim.sub',current_setting('qa.admin'),true);
set local role authenticated;
do $decision_checks$
declare request jsonb; result jsonb; plan jsonb; timeline jsonb;
begin
  select row into request from jsonb_array_elements(clinical_snapshot()->'priceRequests') row where row->>'patientId'='phase5-assigned' and row->>'status'='Pending' limit 1;
  result:=decide_clinical_price_request(request->>'id','Rejected','No discount yet');
  if result->'request'->>'status'<>'Rejected' then raise exception 'Rejection failed'; end if;
  begin perform decide_clinical_price_request(current_setting('qa.account_open_request'),'Approved','Too late');raise exception 'Open account repriced';
  exception when others then if sqlerrm='Open account repriced' then raise; end if; end;
  if (finance_account_balance('phase5-assigned','phase5-service')->>'total')::numeric<>500 then raise exception 'Rejected price affected finance'; end if;
  timeline:=patient_timeline_snapshot('phase5-assigned');plan:=timeline->'plans'->0;
  if (plan->>'total')::numeric<>500 then raise exception 'Rejection affected plan total'; end if;
end
$decision_checks$;

reset role;
select set_config('request.jwt.claim.sub',current_setting('qa.assistant'),true);
set local role authenticated;
do $new_request$
declare target jsonb; request jsonb;
begin
  select row into target from jsonb_array_elements(clinical_snapshot()->'priceTargets') row where row->>'patientId'='phase5-assigned' limit 1;
  request:=create_clinical_price_request('phase5-assigned','phase5-service',target->>'planId',target->>'planItemId',350,'Phase 5 approved request');
  if request->>'status'<>'Pending' then raise exception 'New request after rejection failed'; end if;
  perform set_config('qa.pending_request',request->>'id',true);
end
$new_request$;

reset role;
select set_config('request.jwt.claim.sub',current_setting('qa.other_admin'),true);
set local role authenticated;
do $cross_clinic_checks$
begin
  begin perform patient_timeline_snapshot('phase5-assigned');raise exception 'Other clinic timeline exposed';
  exception when others then if sqlerrm='Other clinic timeline exposed' then raise; end if; end;
  begin perform decide_clinical_price_request(current_setting('qa.pending_request'),'Approved',null);raise exception 'Other clinic decision accepted';
  exception when others then if sqlerrm='Other clinic decision accepted' then raise; end if; end;
end
$cross_clinic_checks$;

reset role;
select set_config('request.jwt.claim.sub',current_setting('qa.admin'),true);
set local role authenticated;
do $approval_checks$
declare request jsonb; result jsonb; plan jsonb;
begin
  select row into request from jsonb_array_elements(clinical_snapshot()->'priceRequests') row where row->>'patientId'='phase5-assigned' and row->>'status'='Pending' limit 1;
  result:=decide_clinical_price_request(request->>'id','Approved','Phase 5 approved');plan:=result->'plan';
  if (plan->>'total')::numeric<>350 or (plan->'items'->0->>'effectivePrice')::numeric<>350 then raise exception 'Approval did not update plan once'; end if;
  if (finance_account_balance('phase5-assigned','phase5-service')->>'total')::numeric<>350 then raise exception 'Approval did not update finance price'; end if;
  begin perform decide_clinical_price_request(request->>'id','Approved','Repeat');raise exception 'Duplicate approval accepted';
  exception when others then if sqlerrm='Duplicate approval accepted' then raise; end if; end;
  if (patient_timeline_snapshot('phase5-assigned')->'plans'->0->>'total')::numeric<>350 then raise exception 'Repeat decision changed plan'; end if;
end
$approval_checks$;

reset role;
insert into finance_accounts(clinic_id,patient_app_id,treatment_id,quoted_total)
values(current_setting('qa.clinic')::uuid,'phase5-assigned','phase5-service',350);
insert into finance_transactions(clinic_id,account_id,kind,amount,method,reference,idempotency_key,collected_by)
select clinic_id,id,'payment',100,'Card','PHASE5-PAYMENT','phase5-payment-key',current_setting('qa.assistant')::uuid
from finance_accounts where clinic_id=current_setting('qa.clinic')::uuid and patient_app_id='phase5-assigned' and treatment_id='phase5-service';
select set_config('request.jwt.claim.sub',current_setting('qa.assistant'),true);
set local role authenticated;
do $payment_reference_check$
declare timeline jsonb;
begin
  timeline:=patient_timeline_snapshot('phase5-assigned');
  if jsonb_array_length(timeline->'payments')<>1 or timeline->'payments'->0->>'reference'<>'PHASE5-PAYMENT' then raise exception 'Permitted payment reference missing'; end if;
  if timeline::text like '%Updated clinical note%' then raise exception 'Clinical note leaked with payment reference'; end if;
end
$payment_reference_check$;

rollback;
