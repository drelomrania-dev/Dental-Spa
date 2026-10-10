-- Permission-scoped collection reporting. Aggregates and detailed exports are
-- separate commands so granting dashboard access does not grant patient rows.

create or replace function finance_report_snapshot(p_from date default null,p_to date default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id();date_from date:=coalesce(p_from,date_trunc('month',current_date)::date);date_to date:=coalesce(p_to,current_date);result jsonb;
begin
  if clinic is null or not has_permission('reports.finance') then raise exception 'Financial report access denied'; end if;
  if date_from>date_to or date_to-date_from>730 then raise exception 'Invalid report period'; end if;
  with period_transactions as (
    select t.*,a.treatment_id,finance_effect(t.kind,t.amount) signed_amount,(t.occurred_at at time zone 'Africa/Casablanca')::date business_date
    from finance_transactions t join finance_accounts a on a.id=t.account_id
    where t.clinic_id=clinic and (t.occurred_at at time zone 'Africa/Casablanca')::date between date_from and date_to
  ),treatment_names as (
    select ids.treatment_id,coalesce((select s.name from services s where s.clinic_id=clinic and s.app_id=ids.treatment_id limit 1),(select r.data->>'name' from app_records r where r.clinic_id=clinic and r.collection='treatments' and r.id=ids.treatment_id limit 1),'Soin') name
    from (select distinct treatment_id from period_transactions) ids
  )
  select jsonb_build_object(
    'period',jsonb_build_object('from',date_from,'to',date_to),
    'summary',jsonb_build_object(
      'grossCollected',coalesce((select sum(amount) from period_transactions where kind='payment'),0),
      'corrections',coalesce((select sum(amount) from period_transactions where kind in ('refund','correction')),0),
      'netCollected',coalesce((select sum(signed_amount) from period_transactions),0),
      'transactionCount',(select count(*) from period_transactions),
      'averageTransaction',coalesce((select round(avg(amount),2) from period_transactions where kind='payment'),0),
      'outstanding',coalesce((select sum(greatest(a.quoted_total-finance_account_paid(a.id),0)) from finance_accounts a where a.clinic_id=clinic and a.status not in ('cancelled','refunded')),0),
      'openAccountCount',(select count(*) from finance_accounts a where a.clinic_id=clinic and greatest(a.quoted_total-finance_account_paid(a.id),0)>0)
    ),
    'byMethod',coalesce((select jsonb_agg(jsonb_build_object('label',method,'value',value,'count',operation_count) order by value desc) from (select method,sum(signed_amount) value,count(*) operation_count from period_transactions group by method) x),'[]'::jsonb),
    'byTreatment',coalesce((select jsonb_agg(jsonb_build_object('id',x.treatment_id,'label',n.name,'value',x.value,'count',x.operation_count) order by x.value desc) from (select treatment_id,sum(signed_amount) value,count(*) operation_count from period_transactions group by treatment_id) x join treatment_names n using(treatment_id)),'[]'::jsonb),
    'byCollector',coalesce((select jsonb_agg(jsonb_build_object('id',x.collected_by,'label',coalesce(s.display_name,'Utilisateur'),'value',x.value,'count',x.operation_count) order by x.value desc) from (select collected_by,sum(signed_amount) value,count(*) operation_count from period_transactions group by collected_by) x left join staff_profiles s on s.id=x.collected_by),'[]'::jsonb),
    'byDay',coalesce((select jsonb_agg(jsonb_build_object('date',business_date,'value',value,'count',operation_count) order by business_date) from (select business_date,sum(signed_amount) value,count(*) operation_count from period_transactions group by business_date) x),'[]'::jsonb),
    'sessions',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'date',s.business_date,'collector',coalesce(sp.display_name,'Utilisateur'),'status',initcap(s.status),'recordedTotal',coalesce(s.recorded_total,0),'recordedCash',coalesce(s.recorded_cash,0),'countedCash',s.counted_cash,'discrepancy',coalesce(s.discrepancy,0)) order by s.business_date desc,s.opened_at desc) from finance_collection_sessions s left join staff_profiles sp on sp.id=s.opened_by where s.clinic_id=clinic and s.business_date between date_from and date_to),'[]'::jsonb)
  ) into result;
  return result;
end;
$$;

create or replace function finance_report_export(p_from date,p_to date)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id();result jsonb;
begin
  if clinic is null or not has_permission('reports.export') then raise exception 'Financial export access denied'; end if;
  if p_from is null or p_to is null or p_from>p_to or p_to-p_from>730 then raise exception 'Invalid export period'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('reference',t.reference,'date',to_char(t.occurred_at at time zone 'Africa/Casablanca','YYYY-MM-DD HH24:MI'),'patient',trim(concat_ws(' ',p.first_name,p.last_name)),'treatment',coalesce(s.name,legacy.data->>'name','Soin'),'type',t.kind,'amount',finance_effect(t.kind,t.amount),'method',t.method,'collector',coalesce(sp.display_name,'Utilisateur'),'sessionId',coalesce(t.session_id::text,''),'reason',coalesce(t.reason,'')) order by t.occurred_at desc),'[]'::jsonb) into result
  from finance_transactions t join finance_accounts a on a.id=t.account_id left join patients p on p.clinic_id=t.clinic_id and p.app_id=a.patient_app_id left join services s on s.clinic_id=t.clinic_id and s.app_id=a.treatment_id left join app_records legacy on legacy.clinic_id=t.clinic_id and legacy.collection='treatments' and legacy.id=a.treatment_id left join staff_profiles sp on sp.id=t.collected_by
  where t.clinic_id=clinic and (t.occurred_at at time zone 'Africa/Casablanca')::date between p_from and p_to;
  insert into audit_events(clinic_id,actor_id,action,entity_type,metadata) values(clinic,auth.uid(),'finance.report.exported','finance_report',jsonb_build_object('from',p_from,'to',p_to,'rowCount',jsonb_array_length(result)));
  return result;
end;
$$;

revoke all on function finance_report_snapshot(date,date),finance_report_export(date,date) from public,anon,authenticated;
grant execute on function finance_report_snapshot(date,date),finance_report_export(date,date) to authenticated;
