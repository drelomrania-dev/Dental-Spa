-- Aggregate CRM reporting and an audited payment-history export. Detail rows
-- never travel through an aggregate report RPC.
alter function finance_report_snapshot(date,date) rename to finance_report_snapshot_internal;
revoke all on function finance_report_snapshot_internal(date,date) from public,anon,authenticated;
create function finance_report_snapshot(p_from date default null,p_to date default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare report jsonb;
begin
  if current_clinic_id() is null or not has_permission('reports.finance') then raise exception 'Financial report access denied'; end if;
  report:=finance_report_snapshot_internal(p_from,p_to);
  if not has_permission('sessions.manage') then report:=jsonb_set(report,'{sessions}','[]'::jsonb); end if;
  return report;
end $$;
revoke all on function finance_report_snapshot(date,date) from public,anon,authenticated;
grant execute on function finance_report_snapshot(date,date) to authenticated;

create or replace function crm_report_snapshot()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); result jsonb;
begin
  if clinic is null or not has_permission('acquisition.view') then raise exception 'CRM report access denied'; end if;
  with lead_scope as (
    select l.id,l.source,l.status from leads l where l.clinic_id=clinic
  ), booked as (
    select distinct a.lead_id from appointments a
    where a.clinic_id=clinic and a.lead_id is not null and a.status not in ('Annulé','No-show')
  ), source_totals as (
    select l.source,count(*) total,count(*) filter(where b.lead_id is not null) booked,
      count(*) filter(where l.status='Converti') converted
    from lead_scope l left join booked b on b.lead_id=l.id group by l.source
  )
  select jsonb_build_object(
    'summary',jsonb_build_object(
      'leads',(select count(*) from lead_scope),
      'booked',(select count(*) from lead_scope l join booked b on b.lead_id=l.id),
      'converted',(select count(*) from lead_scope where status='Converti'),
      'openFollowUps',(select count(*) from follow_up_tasks t where t.clinic_id=clinic and t.status='A faire'),
      'overdueFollowUps',(select count(*) from follow_up_tasks t where t.clinic_id=clinic and t.status='A faire' and t.due_at<now()),
      'completedFollowUps',(select count(*) from follow_up_tasks t where t.clinic_id=clinic and t.status='Terminee')
    ),
    'byStage',coalesce((select jsonb_agg(jsonb_build_object('label',status,'count',total) order by status)
      from (select status,count(*) total from lead_scope group by status) x),'[]'::jsonb),
    'bySource',coalesce((select jsonb_agg(jsonb_build_object('label',source,'count',total,'booked',booked,'converted',converted) order by total desc,source)
      from source_totals),'[]'::jsonb)
  ) into result;
  return result;
end $$;

create or replace function finance_payment_history_export(p_query text default '',p_method text default '')
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); result jsonb; row_count integer;
begin
  if clinic is null or not has_permission('reports.export') then raise exception 'Payment history export access denied'; end if;
  if length(coalesce(p_query,''))>200 or length(coalesce(p_method,''))>100 then raise exception 'Invalid export filter'; end if;
  with export_rows as (
    select t.reference,to_char(t.occurred_at at time zone coalesce(r.snapshot->'clinic'->>'timezone','Africa/Casablanca'),'YYYY-MM-DD') business_date,
      coalesce(nullif(r.snapshot->>'patientName',''),trim(concat_ws(' ',p.first_name,p.last_name)),'') patient_name,
      coalesce(nullif(r.snapshot->>'treatmentName',''),s.name,legacy.data->>'name','Soin') treatment_name,
      t.kind,coalesce(r.snapshot->>'originalReceiptNumber','') original_reference,a.quoted_total,
      finance_effect(t.kind,t.amount) paid,greatest(a.quoted_total-finance_account_paid(a.id),0) remaining,
      a.payment_plan,t.method,coalesce(t.reason,'') reason,t.occurred_at
    from finance_transactions t join finance_accounts a on a.id=t.account_id
      join finance_receipts r on r.transaction_id=t.id and r.clinic_id=t.clinic_id
      left join patients p on p.clinic_id=a.clinic_id and p.app_id=a.patient_app_id
      left join services s on s.clinic_id=a.clinic_id and s.app_id=a.treatment_id
      left join app_records legacy on legacy.clinic_id=a.clinic_id and legacy.collection='treatments' and legacy.id=a.treatment_id
    where t.clinic_id=clinic and (coalesce(p_method,'')='' or t.method=p_method)
  ), filtered as (
    select * from export_rows e where coalesce(trim(p_query),'')='' or
      lower(e.reference||' '||e.patient_name||' '||e.treatment_name) like '%'||lower(trim(p_query))||'%'
  )
  select count(*),coalesce(jsonb_agg(jsonb_build_object(
    'reference',reference,'date',business_date,'patient',patient_name,'treatment',treatment_name,
    'type',kind,'originalReference',original_reference,'total',quoted_total,'paid',paid,
    'remaining',remaining,'plan',payment_plan,'method',method,'reason',reason)
    order by occurred_at desc,reference desc),'[]'::jsonb) into row_count,result from filtered;
  if row_count>5000 then raise exception 'Export too large; narrow the search'; end if;
  insert into audit_events(clinic_id,actor_id,action,entity_type,metadata)
    values(clinic,auth.uid(),'finance.payment_history.exported','finance_report',
      jsonb_build_object('rowCount',row_count,'hasQueryFilter',coalesce(trim(p_query),'')<>'','method',coalesce(p_method,'')));
  return result;
end $$;

create or replace function finance_receipt_export_authorize(p_transaction_id uuid,p_action text default 'pdf')
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); transaction_row finance_transactions%rowtype; result jsonb;
begin
  if clinic is null or not has_permission('payments.receipt') then raise exception 'Receipt export denied'; end if;
  if p_action not in ('pdf','print') then raise exception 'Invalid receipt export action'; end if;
  select * into transaction_row from finance_transactions where id=p_transaction_id and clinic_id=clinic;
  if transaction_row.id is null or not (has_permission('payments.view.all') or transaction_row.collected_by=auth.uid())
    then raise exception 'Receipt export denied'; end if;
  result:=finance_transaction_json(transaction_row.id);
  insert into audit_events(clinic_id,actor_id,action,entity_type,entity_id,metadata)
    values(clinic,auth.uid(),'finance.receipt.exported','finance_receipt',transaction_row.id,
      jsonb_build_object('format',p_action,'reference',transaction_row.reference));
  return result;
end $$;

create or replace function report_export_audit_snapshot(p_limit integer default 30)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); result jsonb;
begin
  if clinic is null or not has_permission('audit.view') then raise exception 'Audit access denied'; end if;
  if p_limit is null or p_limit<1 or p_limit>100 then raise exception 'Invalid audit limit'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'action',a.action,'at',a.created_at,
    'actorId',a.actor_id,'metadata',a.metadata) order by a.created_at desc),'[]'::jsonb) into result
  from (select * from audit_events where clinic_id=clinic and action in
    ('finance.report.exported','finance.payment_history.exported','finance.receipt.exported')
    order by created_at desc limit p_limit) a;
  return result;
end $$;

revoke all on function crm_report_snapshot(),finance_payment_history_export(text,text),finance_receipt_export_authorize(uuid,text),report_export_audit_snapshot(integer) from public,anon,authenticated;
grant execute on function crm_report_snapshot(),finance_payment_history_export(text,text),finance_receipt_export_authorize(uuid,text),report_export_audit_snapshot(integer) to authenticated;
