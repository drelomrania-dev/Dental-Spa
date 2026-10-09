-- Basic identity and medical data must have separate server-side access boundaries.
begin;

select set_config('qa.admin_id',(select id::text from staff_profiles where active=true and role='administrator' order by created_at limit 1),true);
select set_config('qa.assistant_id',gen_random_uuid()::text,true);
insert into auth.users(id,aud,role,email,created_at,updated_at)
values(current_setting('qa.assistant_id')::uuid,'authenticated','authenticated','qa-patient-access@example.invalid',now(),now());
insert into staff_profiles(id,clinic_id,display_name,role,active)
select current_setting('qa.assistant_id')::uuid,clinic_id,'Assistant Patient QA','assistant',true from staff_profiles where id=current_setting('qa.admin_id')::uuid;

select set_config('request.jwt.claim.sub',current_setting('qa.admin_id'),true);
set local role authenticated;

do $admin_patient_test$
declare patient jsonb; medical jsonb;
begin
  patient:=create_patient_record(jsonb_build_object('id','qa-private-patient','firstName','Test','lastName','Privé','phone','0600000005','email','qa-private@example.invalid'));
  if patient->>'id'<>'qa-private-patient' then raise exception 'Basic patient creation failed'; end if;
  medical:=update_patient_medical_record('qa-private-patient','Allergie QA',jsonb_build_object('name','Contact QA'));
  if medical->>'medicalAlerts'<>'Allergie QA' then raise exception 'Medical record update failed'; end if;
end
$admin_patient_test$;

reset role;
select set_config('request.jwt.claim.sub',current_setting('qa.assistant_id'),true);
set local role authenticated;

do $assistant_patient_test$
declare snapshot jsonb;
begin
  snapshot:=patients_snapshot();
  if not exists(select 1 from jsonb_array_elements(snapshot) row where row->>'id'='qa-private-patient') then raise exception 'Assistant cannot access basic patient identity'; end if;
  if snapshot::text like '%Allergie QA%' then raise exception 'Medical alert leaked into basic patient snapshot'; end if;
  begin perform patient_medical_snapshot('qa-private-patient');raise exception 'Assistant unexpectedly accessed medical data';
  exception when others then if sqlerrm='Assistant unexpectedly accessed medical data' then raise; end if; end;
  begin execute 'select medical_alerts from patients limit 1';raise exception 'Assistant unexpectedly selected patient storage';
  exception when insufficient_privilege then null; end;
  begin execute 'select medical_alerts from patient_medical_records limit 1';raise exception 'Assistant unexpectedly selected medical storage';
  exception when insufficient_privilege then null; end;
end
$assistant_patient_test$;

rollback;
