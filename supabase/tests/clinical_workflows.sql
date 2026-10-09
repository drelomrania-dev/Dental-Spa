-- Run against a development database with an active administrator profile.
-- Every fixture and temporary role change is rolled back.
begin;

select set_config(
  'qa.admin_id',
  (select id::text from staff_profiles where active=true and role='administrator' order by created_at limit 1),
  true
);
select set_config('qa.assistant_id',gen_random_uuid()::text,true);
insert into auth.users(id,aud,role,email,created_at,updated_at)
values(current_setting('qa.assistant_id')::uuid,'authenticated','authenticated','qa-clinical@example.invalid',now(),now());
insert into staff_profiles(id,clinic_id,display_name,role,active)
select current_setting('qa.assistant_id')::uuid,clinic_id,'Assistant QA','assistant',true
from staff_profiles where id=current_setting('qa.admin_id')::uuid;
select set_config('request.jwt.claim.sub',current_setting('qa.admin_id'),true);
set local role authenticated;

insert into patients(clinic_id,app_id,first_name,last_name,phone,status)
values(current_clinic_id(),'qa-clinical-patient','Test','Clinique','0600000002','Actif');

do $visit_test$
declare doctor_app text; service_app text; result jsonb; snapshot jsonb;
begin
  select id into doctor_app from app_records where clinic_id=current_clinic_id() and collection='doctors' order by id limit 1;
  select id into service_app from app_records where clinic_id=current_clinic_id() and collection='treatments' and (data->>'price')::numeric>0 order by id limit 1;
  result:=record_clinical_visit('qa-clinical-patient',doctor_app,'Consultation clinique transactionnelle','Contrôle dans une semaine',service_app,true);
  if result->'visit'->>'patientId'<>'qa-clinical-patient' then raise exception 'Clinical visit was not created'; end if;
  if result->'plan' is null or jsonb_array_length(result->'plan'->'items')<>1 then raise exception 'Treatment plan was not created'; end if;
  snapshot:=clinical_snapshot();
  if not exists(select 1 from jsonb_array_elements(snapshot->'visits') row where row->>'patientId'='qa-clinical-patient') then raise exception 'Clinical snapshot is missing the visit'; end if;
end
$visit_test$;

reset role;
select set_config('request.jwt.claim.sub',current_setting('qa.assistant_id'),true);
set local role authenticated;

do $request_test$
declare snapshot jsonb; plan jsonb; item jsonb; service_app text; standard numeric; request jsonb;
begin
  snapshot:=clinical_snapshot();
  select row into plan from jsonb_array_elements(snapshot->'plans') row where row->>'patientId'='qa-clinical-patient' limit 1;
  item:=plan->'items'->0;
  service_app:=item->>'treatmentId';
  select (data->>'price')::numeric into standard from app_records where clinic_id=current_clinic_id() and collection='treatments' and id=service_app;
  request:=create_clinical_price_request('qa-clinical-patient',service_app,plan->>'id',item->>'id',standard-50,'Validation transactionnelle');
  if request->>'status'<>'Pending' or request->>'requestedBy'<>auth.uid()::text then raise exception 'Price request was not created for the assistant'; end if;
end
$request_test$;

reset role;
select set_config('request.jwt.claim.sub',current_setting('qa.admin_id'),true);
set local role authenticated;

do $approval_test$
declare snapshot jsonb; request jsonb; result jsonb; balance jsonb;
begin
  snapshot:=clinical_snapshot();
  select row into request from jsonb_array_elements(snapshot->'priceRequests') row where row->>'patientId'='qa-clinical-patient' and row->>'status'='Pending' limit 1;
  result:=decide_clinical_price_request(request->>'id','Approved','Approuvé par le test transactionnel');
  if result->'request'->>'status'<>'Approved' or result->'plan'->>'status'<>'Accepté' then raise exception 'Price approval did not update request and plan'; end if;
  balance:=finance_account_balance('qa-clinical-patient',request->>'treatmentId');
  if (balance->>'total')::numeric<>(request->>'proposedPrice')::numeric then raise exception 'Finance did not resolve the approved negotiated price'; end if;
end
$approval_test$;

rollback;
