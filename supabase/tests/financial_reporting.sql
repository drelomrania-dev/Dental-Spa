-- Aggregated report, detailed audited export, and permission denial. Fixtures roll back.
begin;
select set_config('qa.reporting_admin',(select id::text from staff_profiles where active=true and role='administrator' order by created_at limit 1),true);
select set_config('request.jwt.claim.sub',current_setting('qa.reporting_admin'),true);
set local role authenticated;
do $report_test$
declare clinic uuid:=current_clinic_id();report jsonb;exported jsonb;
begin
  perform set_config('qa.reporting_clinic',clinic::text,true);
  perform create_patient_record(jsonb_build_object('id','qa-report-patient','firstName','Test','lastName','Rapport','phone','0600000099','status','Actif'));
  insert into app_records(clinic_id,collection,id,data) values(clinic,'treatments','qa-report-treatment',jsonb_build_object('id','qa-report-treatment','name','Soin rapport','price',500,'active',true));
  perform record_finance_payment('qa-report-patient','qa-report-treatment','',500,'Comptant','Carte','qa-report-payment-key',null,null);
  report:=finance_report_snapshot(current_date,current_date);
  if (report->'summary'->>'netCollected')::numeric<500 then raise exception 'Report total is incomplete'; end if;
  if not exists(select 1 from jsonb_array_elements(report->'byMethod') row where row->>'label'='Carte') then raise exception 'Method aggregation is missing'; end if;
  if not exists(select 1 from jsonb_array_elements(report->'byTreatment') row where row->>'label'='Soin rapport') then raise exception 'Treatment aggregation is missing'; end if;
  exported:=finance_report_export(current_date,current_date);
  if not exists(select 1 from jsonb_array_elements(exported) row where row->>'patient'='Test Rapport') then raise exception 'Detailed export is incomplete'; end if;
end
$report_test$;
reset role;
do $report_audit$
begin
  if not exists(select 1 from audit_events where clinic_id=current_setting('qa.reporting_clinic')::uuid and action='finance.report.exported' and (metadata->>'rowCount')::integer>0) then raise exception 'Export audit is missing'; end if;
end
$report_audit$;
select set_config('qa.reporting_user',gen_random_uuid()::text,true);
insert into auth.users(id,aud,role,email,created_at,updated_at) values(current_setting('qa.reporting_user')::uuid,'authenticated','authenticated','qa-report-no-access@example.invalid',now(),now());
insert into staff_profiles(id,clinic_id,display_name,role,active) select current_setting('qa.reporting_user')::uuid,clinic_id,'Rapport sans accès','assistant',true from staff_profiles where id=current_setting('qa.reporting_admin')::uuid;
select set_config('request.jwt.claim.sub',current_setting('qa.reporting_user'),true);
set local role authenticated;
do $report_denial$
begin
  begin perform finance_report_snapshot(current_date,current_date);raise exception 'Unauthorized report unexpectedly succeeded';exception when others then if sqlerrm='Unauthorized report unexpectedly succeeded' then raise;end if;end;
  begin perform finance_report_export(current_date,current_date);raise exception 'Unauthorized export unexpectedly succeeded';exception when others then if sqlerrm='Unauthorized export unexpectedly succeeded' then raise;end if;end;
end
$report_denial$;
rollback;
