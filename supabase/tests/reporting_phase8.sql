-- Transactional synthetic aggregate, reconciliation, permission and export audit checks.
begin;
select set_config('qa.phase8_admin',(select id::text from staff_profiles where active and role='administrator' order by created_at limit 1),true);
select set_config('qa.phase8_clinic',(select clinic_id::text from staff_profiles where id=current_setting('qa.phase8_admin')::uuid),true);
select set_config('qa.phase8_viewer',gen_random_uuid()::text,true);
insert into auth.users(id,aud,role,email,created_at,updated_at)
values(current_setting('qa.phase8_viewer')::uuid,'authenticated','authenticated','phase8-viewer@example.invalid',now(),now());
insert into staff_profiles(id,clinic_id,display_name,role,active)
values(current_setting('qa.phase8_viewer')::uuid,current_setting('qa.phase8_clinic')::uuid,'Phase 8 report viewer','assistant',true);
insert into role_permissions(clinic_id,role,permission,scope)
values(current_setting('qa.phase8_clinic')::uuid,'assistant','reports.finance','clinic')
on conflict(clinic_id,role,permission) do update set scope=excluded.scope;
delete from role_permissions where clinic_id=current_setting('qa.phase8_clinic')::uuid and role='assistant'
  and permission in ('payments.collect','payments.view.own','payments.view.all','payments.correct','sessions.own','sessions.manage');
insert into patients(clinic_id,app_id,first_name,last_name)
values(current_setting('qa.phase8_clinic')::uuid,'phase8-report-patient','Phase','Eight');
insert into app_records(clinic_id,collection,id,data)
values(current_setting('qa.phase8_clinic')::uuid,'treatments','phase8-report-service',
  jsonb_build_object('id','phase8-report-service','name','Phase 8 service','price',240,'active',true));

select set_config('request.jwt.claim.sub',current_setting('qa.phase8_admin'),true);
set local role authenticated;
do $phase8_admin$
declare clinic uuid:=current_clinic_id(); l uuid; p uuid; report jsonb; crm jsonb; exported jsonb; payment jsonb;
begin
  payment:=record_finance_payment('phase8-report-patient','phase8-report-service','',240,'Comptant','Carte','phase8-report-payment',null,null);
  perform set_config('qa.phase8_payment',payment->>'id',true);
  select id into p from patients where clinic_id=clinic and app_id='phase8-report-patient';
  insert into leads(clinic_id,first_name,last_name,phone,source,status)
    values(clinic,'Phase','Eight','0699918001','Phase 8 source','Nouveau') returning id into l;
  insert into follow_up_tasks(clinic_id,lead_id,title,due_at)
    values(clinic,l,'Phase 8 follow-up',now()-interval '1 day');
  insert into appointments(clinic_id,app_id,patient_id,lead_id,starts_at,ends_at,status,source,reference)
    values(clinic,'phase8-report-booking',p,l,now()+interval '7 days',now()+interval '7 days 30 minutes','Confirmé','internal','PHASE8-BOOKING');
  report:=finance_report_snapshot(current_date,current_date);
  if (report->'summary'->>'grossCollected')::numeric<240 then raise exception 'Ledger payment omitted'; end if;
  if abs((report->'summary'->>'grossCollected')::numeric-(report->'summary'->>'corrections')::numeric-(report->'summary'->>'netCollected')::numeric)>0.001
    then raise exception 'Ledger reconciliation failed'; end if;
  crm:=crm_report_snapshot();
  if not exists(select 1 from jsonb_array_elements(crm->'bySource') x where x->>'label'='Phase 8 source' and (x->>'booked')::integer=1)
    then raise exception 'CRM source/booking conversion missing'; end if;
  if (crm->'summary'->>'overdueFollowUps')::integer<1 then raise exception 'Overdue follow-up missing'; end if;
  exported:=finance_payment_history_export('Phase Eight','Carte');
  if not exists(select 1 from jsonb_array_elements(exported) x where x->>'patient'='Phase Eight' and (x->>'paid')::numeric=240)
    then raise exception 'History export does not match ledger'; end if;
  if (finance_receipt_export_authorize((payment->>'id')::uuid,'pdf')->>'reference') is distinct from (payment->>'reference')
    then raise exception 'Audited receipt authorization returned wrong ledger row'; end if;
  if not exists(select 1 from jsonb_array_elements(report_export_audit_snapshot(30)) x where x->>'action'='finance.receipt.exported')
    then raise exception 'Export audit viewer omitted receipt event'; end if;
end $phase8_admin$;
reset role;
do $phase8_audit$
begin
  if not exists(select 1 from audit_events where clinic_id=current_setting('qa.phase8_clinic')::uuid and action='finance.payment_history.exported' and (metadata->>'rowCount')::integer>=1)
    then raise exception 'History export audit missing'; end if;
  if not exists(select 1 from audit_events where clinic_id=current_setting('qa.phase8_clinic')::uuid and action='finance.receipt.exported' and entity_id=current_setting('qa.phase8_payment')::uuid and metadata->>'format'='pdf')
    then raise exception 'Receipt export audit missing'; end if;
end $phase8_audit$;

select set_config('request.jwt.claim.sub',current_setting('qa.phase8_viewer'),true);
set local role authenticated;
do $phase8_viewer$
declare report jsonb; crm jsonb;
begin
  report:=finance_report_snapshot(current_date,current_date);
  if report->'sessions'<>'[]'::jsonb then raise exception 'Aggregate viewer received session rows'; end if;
  if report::text like '%Phase Eight%' then raise exception 'Aggregate viewer received patient detail'; end if;
  crm:=crm_report_snapshot();
  if crm::text like '%0699918001%' or crm::text like '%Phase Eight%' then raise exception 'CRM aggregate contains lead detail'; end if;
  begin perform finance_payment_history_export('','');raise exception 'Unauthorized history export succeeded';
  exception when others then if sqlerrm='Unauthorized history export succeeded' then raise; end if;end;
  begin perform finance_report_export(current_date,current_date);raise exception 'Unauthorized finance export succeeded';
  exception when others then if sqlerrm='Unauthorized finance export succeeded' then raise; end if;end;
  begin perform finance_snapshot();raise exception 'Aggregate viewer received finance detail snapshot';
  exception when others then if sqlerrm='Aggregate viewer received finance detail snapshot' then raise; end if;end;
  begin perform finance_receipt_export_authorize(current_setting('qa.phase8_payment')::uuid,'pdf');raise exception 'Unpermitted receipt export succeeded';
  exception when others then if sqlerrm='Unpermitted receipt export succeeded' then raise; end if;end;
  begin perform report_export_audit_snapshot(30);raise exception 'Unpermitted audit read succeeded';
  exception when others then if sqlerrm='Unpermitted audit read succeeded' then raise; end if;end;
end $phase8_viewer$;
reset role;
insert into role_permissions(clinic_id,role,permission,scope)
values(current_setting('qa.phase8_clinic')::uuid,'assistant','reports.export','clinic')
on conflict(clinic_id,role,permission) do update set scope=excluded.scope;
delete from role_permissions where clinic_id=current_setting('qa.phase8_clinic')::uuid and role='assistant' and permission='reports.finance';
select set_config('request.jwt.claim.sub',current_setting('qa.phase8_viewer'),true);
set local role authenticated;
do $phase8_export_only$
declare exported jsonb;
begin
  begin perform finance_report_snapshot(current_date,current_date);raise exception 'Export-only user received aggregates';
  exception when others then if sqlerrm='Export-only user received aggregates' then raise; end if;end;
  exported:=finance_payment_history_export('PHASE8-NOMATCH','Carte');
  if exported<>'[]'::jsonb then raise exception 'History filter ignored'; end if;
end $phase8_export_only$;
reset role;
delete from role_permissions where clinic_id=current_setting('qa.phase8_clinic')::uuid and role='assistant' and permission='acquisition.view';
select set_config('request.jwt.claim.sub',current_setting('qa.phase8_viewer'),true);
set local role authenticated;
do $phase8_crm_denial$
begin
  begin perform crm_report_snapshot();raise exception 'Unauthorized CRM aggregate succeeded';
  exception when others then if sqlerrm='Unauthorized CRM aggregate succeeded' then raise; end if;end;
end $phase8_crm_denial$;
reset role;
select set_config('qa.phase8_other_admin',(select id::text from staff_profiles where active and role='administrator' and clinic_id<>current_setting('qa.phase8_clinic')::uuid order by created_at limit 1),true);
select set_config('request.jwt.claim.sub',current_setting('qa.phase8_other_admin'),true);
set local role authenticated;
do $phase8_other_clinic$
declare crm jsonb; exported jsonb;
begin
  crm:=crm_report_snapshot();
  if crm::text like '%Phase 8 source%' then raise exception 'Other clinic received CRM source'; end if;
  exported:=finance_payment_history_export('Phase Eight','Carte');
  if exported<>'[]'::jsonb then raise exception 'Other clinic received payment history'; end if;
  begin perform finance_receipt_export_authorize(current_setting('qa.phase8_payment')::uuid,'pdf');raise exception 'Other clinic received receipt';
  exception when others then if sqlerrm='Other clinic received receipt' then raise; end if;end;
end $phase8_other_clinic$;
rollback;
