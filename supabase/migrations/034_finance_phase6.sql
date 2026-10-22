-- Phase 6: dated receivables, immutable payment documents and reconciled tills.
-- Accounts opened in earlier phases keep their quoted_total and payment_plan.

create table finance_document_settings (
  clinic_id uuid primary key references clinics(id) on delete cascade,
  receipt_prefix text not null default 'REC' check (receipt_prefix ~ '^[A-Z0-9]{2,12}$'),
  correction_prefix text not null default 'COR' check (correction_prefix ~ '^[A-Z0-9]{2,12}$'),
  next_receipt bigint not null default 1 check (next_receipt > 0),
  next_correction bigint not null default 1 check (next_correction > 0),
  updated_at timestamptz not null default now()
);
alter table finance_document_settings enable row level security;
revoke all on finance_document_settings from anon,authenticated;
create policy finance_document_settings_rpc_only on finance_document_settings for all to public using(false) with check(false);

create table finance_installments (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id) on delete cascade,
  account_id uuid not null references finance_accounts(id) on delete restrict,
  sequence_no integer not null check(sequence_no between 1 and 120),
  original_due_date date not null,
  amount numeric(12,2) not null check(amount > 0),
  source text not null default 'at_opening' check(source in ('at_opening','historical_entry')),
  source_reason text,
  created_by uuid references staff_profiles(id),
  created_at timestamptz not null default now(),
  unique(account_id,sequence_no)
);
create index finance_installments_due_idx on finance_installments(clinic_id,original_due_date);
alter table finance_installments enable row level security;
revoke all on finance_installments from anon,authenticated;
create policy finance_installments_rpc_only on finance_installments for all to public using(false) with check(false);

create table finance_installment_reschedules (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id) on delete cascade,
  installment_id uuid not null references finance_installments(id) on delete restrict,
  old_due_date date not null,
  new_due_date date not null,
  reason text not null check(length(trim(reason)) >= 4),
  changed_by uuid not null references staff_profiles(id),
  changed_at timestamptz not null default now()
);
create index finance_installment_reschedules_latest_idx on finance_installment_reschedules(installment_id,changed_at desc,id desc);
alter table finance_installment_reschedules enable row level security;
revoke all on finance_installment_reschedules from anon,authenticated;
create policy finance_installment_reschedules_rpc_only on finance_installment_reschedules for all to public using(false) with check(false);

-- A refund restores an outstanding balance. Legacy "refunded" account status had
-- hidden that balance from the finance report despite the append-only ledger.
update finance_accounts set status='open',updated_at=now()
where status='refunded' and quoted_total>finance_account_paid(id);

create or replace function finance_next_document_number(p_clinic uuid,p_kind text)
returns text language plpgsql security definer set search_path=public as $$
declare row finance_document_settings%rowtype; number_value bigint; prefix_value text;
begin
  insert into finance_document_settings(clinic_id) values(p_clinic) on conflict do nothing;
  if p_kind='payment' then
    update finance_document_settings set next_receipt=next_receipt+1,updated_at=now()
      where clinic_id=p_clinic returning * into row;
    number_value:=row.next_receipt-1; prefix_value:=row.receipt_prefix;
  elsif p_kind='correction' then
    update finance_document_settings set next_correction=next_correction+1,updated_at=now()
      where clinic_id=p_clinic returning * into row;
    number_value:=row.next_correction-1; prefix_value:=row.correction_prefix;
  else raise exception 'Invalid document kind'; end if;
  return prefix_value||'-'||to_char(clock_timestamp() at time zone (select timezone from clinics where id=p_clinic),'YYYY')||'-'||lpad(number_value::text,greatest(6,length(number_value::text)),'0');
end $$;

create or replace function finance_document_identity(p_clinic uuid,p_patient text,p_treatment text)
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object('clinic',jsonb_build_object('name',c.name,'address',c.address,'phone',c.phone,
      'currency',c.currency,'timezone',c.timezone),
    'patientName',coalesce((select p.first_name||' '||p.last_name from patients p where p.clinic_id=c.id and p.app_id=p_patient),''),
    'treatmentName',coalesce((select s.name from services s where s.clinic_id=c.id and s.app_id=p_treatment),
      (select r.data->>'name' from app_records r where r.clinic_id=c.id and r.collection='treatments' and r.id=p_treatment),''))
  from clinics c where c.id=p_clinic
$$;

create or replace function finance_installment_json(p_id uuid,p_as_of date default null)
returns jsonb language sql stable security definer set search_path=public as $$
  with item as (
    select i.*,coalesce((select r.new_due_date from finance_installment_reschedules r where r.installment_id=i.id order by r.changed_at desc,r.id desc limit 1),i.original_due_date) due_date,
      coalesce((select sum(earlier.amount) from finance_installments earlier where earlier.account_id=i.account_id and earlier.sequence_no<i.sequence_no),0) prior_amount
    from finance_installments i where i.id=p_id
  )
  select jsonb_build_object('id',item.id,'accountId',item.account_id,'sequence',item.sequence_no,
    'originalDueDate',item.original_due_date,'dueDate',item.due_date,'amount',item.amount,
    'source',item.source,'sourceReason',item.source_reason,'createdBy',item.created_by,
    'paid',least(item.amount,greatest(finance_account_paid(item.account_id)-item.prior_amount,0)),
    'remaining',item.amount-least(item.amount,greatest(finance_account_paid(item.account_id)-item.prior_amount,0)),
    'status',case when finance_account_paid(item.account_id)>=item.prior_amount+item.amount then 'paid'
      when item.due_date<coalesce(p_as_of,(now() at time zone (select timezone from clinics where id=item.clinic_id))::date)
        then 'late' when item.due_date<>item.original_due_date then 'rescheduled' else 'due' end,
    'rescheduleHistory',coalesce((select jsonb_agg(jsonb_build_object('oldDueDate',r.old_due_date,'newDueDate',r.new_due_date,'reason',r.reason,'changedAt',r.changed_at,'changedBy',r.changed_by) order by r.changed_at,r.id)
      from finance_installment_reschedules r where r.installment_id=item.id),'[]'::jsonb)) from item
$$;

create or replace function finance_account_json(p_id uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object('id',a.id,'patientId',a.patient_app_id,'treatmentId',a.treatment_id,
    'doctorId',coalesce(a.doctor_id,''),'total',a.quoted_total,'paid',finance_account_paid(a.id),
    'remaining',greatest(a.quoted_total-finance_account_paid(a.id),0),'plan',a.payment_plan,
    'currency',a.currency,'status',a.status,'createdAt',a.created_at,
    'installments',coalesce((select jsonb_agg(finance_installment_json(i.id) order by i.sequence_no)
      from finance_installments i where i.account_id=a.id),'[]'::jsonb))
  from finance_accounts a where a.id=p_id
$$;

create or replace function finance_transaction_json(p_transaction_id uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'id',t.id,'accountId',a.id,'patientId',a.patient_app_id,'treatmentId',a.treatment_id,'doctorId',coalesce(a.doctor_id,''),
    'date',to_char(t.occurred_at at time zone coalesce(r.snapshot->'clinic'->>'timezone','Africa/Casablanca'),'YYYY-MM-DD'),
    'total',case when t.kind='payment' and not exists(select 1 from finance_transactions earlier where earlier.account_id=t.account_id and earlier.kind='payment' and (earlier.occurred_at,earlier.id)<(t.occurred_at,t.id)) then a.quoted_total else 0 end,
    'accountTotal',a.quoted_total,'paid',finance_effect(t.kind,t.amount),
    'remaining',greatest(a.quoted_total-finance_account_paid(a.id),0),'plan',a.payment_plan,'method',t.method,
    'status',case when finance_account_paid(a.id)>=a.quoted_total then 'Payé' else 'Partiel' end,
    'reference',t.reference,'idempotencyKey',t.idempotency_key,'collectorUserId',t.collected_by,
    'sessionId',coalesce(t.session_id::text,''),'kind',t.kind,'reason',coalesce(t.reason,''),
    'reversesTransactionId',t.reverses_transaction_id,'receiptNumber',r.receipt_number,
    'document',r.snapshot,'occurredAt',t.occurred_at)
  from finance_transactions t join finance_accounts a on a.id=t.account_id
  join finance_receipts r on r.transaction_id=t.id where t.id=p_transaction_id
$$;

create or replace function finance_snapshot()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); result jsonb;
begin
  if clinic is null then raise exception 'Authentication required'; end if;
  if not (has_permission('payments.view.all') or has_permission('payments.view.own') or has_permission('payments.collect') or has_permission('sessions.own') or has_permission('sessions.manage')) then raise exception 'Finance access denied'; end if;
  select jsonb_build_object(
    'payments',coalesce((select jsonb_agg(finance_transaction_json(t.id) order by t.occurred_at desc)
      from finance_transactions t where t.clinic_id=clinic and
      (has_permission('payments.view.all') or (has_permission('payments.view.own') and t.collected_by=auth.uid()))),'[]'::jsonb),
    'accounts',case when has_permission('payments.view.all') then coalesce((select jsonb_agg(finance_account_json(a.id) order by a.created_at desc)
      from finance_accounts a where a.clinic_id=clinic),'[]'::jsonb) else '[]'::jsonb end,
    'sessions',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'openedBy',s.opened_by,'openedAt',s.opened_at,
      'date',s.business_date,'status',initcap(s.status),'openingCash',s.opening_cash,'closedAt',s.closed_at,
      'countedCash',s.counted_cash,'recordedTotal',s.recorded_total,'recordedCash',s.recorded_cash,
      'discrepancy',s.discrepancy,'validatedAt',s.validated_at,'validatedBy',s.validated_by,
      'rejectionReason',s.rejection_reason,
      'liveTotal',(select coalesce(sum(finance_effect(t.kind,t.amount)),0) from finance_transactions t where t.session_id=s.id),
      'liveCash',s.opening_cash+(select coalesce(sum(finance_effect(t.kind,t.amount)) filter(where lower(t.method) in ('espèces','especes','cash')),0) from finance_transactions t where t.session_id=s.id)) order by s.opened_at desc)
      from finance_collection_sessions s where s.clinic_id=clinic and
      (has_permission('sessions.manage') or (has_permission('sessions.own') and s.opened_by=auth.uid()))),'[]'::jsonb)
  ) into result;
  return result;
end $$;

create or replace function initialize_finance_schedule(p_account_id uuid,p_first_due_date date,p_installment_count integer,p_reason text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); account finance_accounts%rowtype; count_value integer;
  cents bigint; base_cents bigint; n integer;
begin
  if clinic is null or not has_permission('payments.correct') then raise exception 'Historical schedule entry denied'; end if;
  if p_first_due_date is null or length(trim(coalesce(p_reason,'')))<4 then raise exception 'Date and source reason required'; end if;
  select * into account from finance_accounts where id=p_account_id and clinic_id=clinic for update;
  if account.id is null then raise exception 'Finance account not found'; end if;
  if exists(select 1 from finance_installments where account_id=account.id) then raise exception 'Schedule already exists'; end if;
  count_value:=case account.payment_plan when 'Comptant' then 1 when '2 fois' then 2 when '3 fois' then 3
    when 'Mensuel' then p_installment_count else null end;
  if count_value is null or count_value<1 or count_value>60 or account.quoted_total*100<count_value
    or (account.payment_plan='Mensuel' and count_value<2) then raise exception 'Invalid historical installment count'; end if;
  cents:=(account.quoted_total*100)::bigint; base_cents:=cents/count_value;
  for n in 1..count_value loop
    insert into finance_installments(clinic_id,account_id,sequence_no,original_due_date,amount,source,source_reason,created_by)
    values(clinic,account.id,n,(p_first_due_date+(n-1)*interval '1 month')::date,
      (base_cents+case when n=count_value then cents-base_cents*count_value else 0 end)/100.0,
      'historical_entry',trim(p_reason),auth.uid());
  end loop;
  return finance_account_json(account.id);
end $$;

create or replace function finance_account_balance(p_patient_app_id text,p_treatment_id text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); account finance_accounts%rowtype; resolved numeric;
begin
  if clinic is null or not (has_permission('payments.collect') or has_permission('payments.view.all')) then raise exception 'Finance access denied'; end if;
  select * into account from finance_accounts where clinic_id=clinic and patient_app_id=p_patient_app_id and treatment_id=p_treatment_id;
  if account.id is not null then return finance_account_json(account.id); end if;
  resolved:=coalesce(finance_resolved_price(clinic,p_patient_app_id,p_treatment_id),0);
  return jsonb_build_object('total',resolved,'paid',0,'remaining',resolved,'plan',null,'installments','[]'::jsonb);
end $$;

create or replace function record_finance_payment_phase6(
  p_patient_app_id text,p_treatment_id text,p_doctor_id text,p_amount numeric,p_plan text,p_method text,
  p_idempotency_key text,p_session_id uuid default null,p_expected_total numeric default null,
  p_first_due_date date default null,p_installment_count integer default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); account finance_accounts%rowtype; session finance_collection_sessions%rowtype;
  resolved_total numeric; already_paid numeric; transaction_id uuid; receipt_no text; existing_id uuid;
  count_value integer; base_cents bigint; cents bigint; n integer; due_date date; identity jsonb; currency_value text;
begin
  if clinic is null or not has_permission('payments.collect') then raise exception 'Payment collection denied'; end if;
  if p_amount is null or p_amount<=0 or p_amount<>round(p_amount,2) or length(trim(coalesce(p_method,'')))<2
    or length(trim(coalesce(p_idempotency_key,'')))<8 then raise exception 'Invalid payment details'; end if;
  if not exists(select 1 from patients where clinic_id=clinic and app_id=p_patient_app_id) then raise exception 'Patient not found'; end if;
  perform pg_advisory_xact_lock(hashtext(clinic::text||':finance-key:'||p_idempotency_key));
  select id into existing_id from finance_transactions where clinic_id=clinic and idempotency_key=p_idempotency_key;
  if existing_id is not null then
    if not exists(select 1 from finance_transactions t join finance_accounts a on a.id=t.account_id
      where t.id=existing_id and t.kind='payment' and a.patient_app_id=p_patient_app_id and a.treatment_id=p_treatment_id
      and t.amount=p_amount and t.method=trim(p_method) and t.session_id is not distinct from p_session_id)
      then raise exception 'Idempotency key belongs to a different payment'; end if;
    return finance_transaction_json(existing_id);
  end if;
  if current_staff_role()<>'administrator' then
    if p_session_id is null then raise exception 'An open collection session is required'; end if;
    select * into session from finance_collection_sessions where id=p_session_id and clinic_id=clinic and opened_by=auth.uid() and status='open' for update;
    if session.id is null then raise exception 'Collection session unavailable'; end if;
  elsif p_session_id is not null then
    select * into session from finance_collection_sessions where id=p_session_id and clinic_id=clinic and status='open' for update;
    if session.id is null then raise exception 'Collection session unavailable'; end if;
  end if;
  if lower(trim(p_method)) in ('espèces','especes','cash') and p_session_id is null
    then raise exception 'Cash collection requires an open session'; end if;
  perform pg_advisory_xact_lock(hashtext(clinic::text||':'||p_patient_app_id||':'||p_treatment_id));
  select * into account from finance_accounts where clinic_id=clinic and patient_app_id=p_patient_app_id and treatment_id=p_treatment_id for update;
  if account.id is null then
    resolved_total:=finance_resolved_price(clinic,p_patient_app_id,p_treatment_id);
    if resolved_total is null and current_staff_role()='administrator' then resolved_total:=p_expected_total; end if;
    if resolved_total is null or resolved_total<=0 or resolved_total<>round(resolved_total,2) then raise exception 'No approved treatment price is available'; end if;
    if p_plan not in ('Comptant','2 fois','3 fois','Mensuel') then raise exception 'Invalid payment plan'; end if;
    count_value:=case p_plan when 'Comptant' then 1 when '2 fois' then 2 when '3 fois' then 3 else p_installment_count end;
    if count_value is null or count_value<1 or count_value>60 or resolved_total*100<count_value then raise exception 'Invalid installment count'; end if;
    if p_plan='Mensuel' and (p_installment_count is null or p_installment_count<2) then raise exception 'Monthly plan requires at least two installments'; end if;
    select currency into currency_value from clinics where id=clinic;
    insert into finance_accounts(clinic_id,patient_app_id,treatment_id,doctor_id,quoted_total,payment_plan,currency)
      values(clinic,p_patient_app_id,p_treatment_id,nullif(p_doctor_id,''),resolved_total,p_plan,currency_value) returning * into account;
    due_date:=coalesce(p_first_due_date,(now() at time zone (select timezone from clinics where id=clinic))::date);
    if due_date<(now() at time zone (select timezone from clinics where id=clinic))::date then raise exception 'First due date cannot be in the past'; end if;
    cents:=(resolved_total*100)::bigint; base_cents:=cents/count_value;
    for n in 1..count_value loop
      insert into finance_installments(clinic_id,account_id,sequence_no,original_due_date,amount)
      values(clinic,account.id,n,(due_date+(n-1)*interval '1 month')::date,
        (base_cents+case when n=count_value then cents-base_cents*count_value else 0 end)/100.0);
    end loop;
  end if;
  already_paid:=finance_account_paid(account.id);
  if p_amount>account.quoted_total-already_paid then raise exception 'Payment exceeds outstanding balance'; end if;
  identity:=jsonb_set(finance_document_identity(clinic,p_patient_app_id,p_treatment_id),'{clinic,currency}',to_jsonb(account.currency));
  receipt_no:=finance_next_document_number(clinic,'payment');
  insert into finance_transactions(clinic_id,account_id,session_id,kind,amount,method,reference,idempotency_key,collected_by)
    values(clinic,account.id,p_session_id,'payment',p_amount,trim(p_method),receipt_no,p_idempotency_key,auth.uid()) returning id into transaction_id;
  update finance_accounts set status=case when already_paid+p_amount>=quoted_total then 'paid' else 'open' end,updated_at=now() where id=account.id;
  insert into finance_receipts(clinic_id,transaction_id,receipt_number,snapshot)
    values(clinic,transaction_id,receipt_no,identity||jsonb_build_object('documentType','receipt','number',receipt_no,
      'patientId',p_patient_app_id,'treatmentId',p_treatment_id,'accountTotal',account.quoted_total,
      'amount',p_amount,'remaining',greatest(account.quoted_total-already_paid-p_amount,0),
      'method',trim(p_method),'plan',account.payment_plan,'issuedAt',now(),'collectorId',auth.uid()));
  return finance_transaction_json(transaction_id);
end $$;

create or replace function record_finance_payment(
  p_patient_app_id text,p_treatment_id text,p_doctor_id text,p_amount numeric,p_plan text,p_method text,
  p_idempotency_key text,p_session_id uuid default null,p_expected_total numeric default null)
returns jsonb language sql security definer set search_path=public as $$
  select record_finance_payment_phase6(p_patient_app_id,p_treatment_id,p_doctor_id,p_amount,p_plan,p_method,
    p_idempotency_key,p_session_id,p_expected_total,null,null)
$$;

create or replace function correct_finance_payment(p_transaction_id uuid,p_amount numeric,p_reason text,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); original finance_transactions%rowtype; reversed numeric; transaction_id uuid;
  receipt_no text; existing_id uuid; account finance_accounts%rowtype; identity jsonb; current_session uuid;
begin
  if clinic is null or not has_permission('payments.correct') then raise exception 'Payment correction denied'; end if;
  if p_amount is null or p_amount<=0 or p_amount<>round(p_amount,2) or length(trim(coalesce(p_reason,'')))<4
    or length(trim(coalesce(p_idempotency_key,'')))<8 then raise exception 'Invalid correction details'; end if;
  perform pg_advisory_xact_lock(hashtext(clinic::text||':finance-key:'||p_idempotency_key));
  select id into existing_id from finance_transactions where clinic_id=clinic and idempotency_key=p_idempotency_key;
  if existing_id is not null then
    if not exists(select 1 from finance_transactions where id=existing_id and kind='refund' and reverses_transaction_id=p_transaction_id
      and amount=p_amount and reason=trim(p_reason)) then raise exception 'Idempotency key belongs to a different correction'; end if;
    return finance_transaction_json(existing_id);
  end if;
  select id into current_session from finance_collection_sessions
    where clinic_id=clinic and opened_by=auth.uid() and status='open' for update;
  if current_staff_role()<>'administrator' and current_session is null then raise exception 'An open collection session is required'; end if;
  select * into original from finance_transactions where id=p_transaction_id and clinic_id=clinic and kind='payment' for update;
  if original.id is null then raise exception 'Original payment not found'; end if;
  if lower(original.method) in ('espèces','especes','cash') and current_session is null
    then raise exception 'Cash correction requires an open session'; end if;
  select * into account from finance_accounts where id=original.account_id for update;
  select coalesce(sum(amount),0) into reversed from finance_transactions where reverses_transaction_id=original.id and kind='refund';
  if p_amount>original.amount-reversed then raise exception 'Correction exceeds refundable amount'; end if;
  -- Corrections use the identity printed on the original document. Legacy documents without
  -- a historical identity remain explicitly unknown instead of borrowing today's settings.
  select snapshot into identity from finance_receipts where transaction_id=original.id;
  receipt_no:=finance_next_document_number(clinic,'correction');
  insert into finance_transactions(clinic_id,account_id,session_id,kind,amount,method,reference,idempotency_key,collected_by,reverses_transaction_id,reason)
    values(clinic,original.account_id,current_session,'refund',p_amount,original.method,receipt_no,p_idempotency_key,auth.uid(),original.id,trim(p_reason)) returning id into transaction_id;
  update finance_accounts set status='open',updated_at=now() where id=original.account_id;
  insert into finance_receipts(clinic_id,transaction_id,receipt_number,snapshot)
    values(clinic,transaction_id,receipt_no,(identity-'documentType'-'number'-'amount'-'remaining'-'issuedAt'-'collectorId')||
      jsonb_build_object('documentType','correction','number',receipt_no,'originalTransactionId',original.id,
      'originalReceiptNumber',original.reference,'amount',p_amount,'reason',trim(p_reason),
      'remaining',greatest(account.quoted_total-finance_account_paid(account.id),0),'issuedAt',now(),'actorId',auth.uid()));
  return finance_transaction_json(transaction_id);
end $$;

create or replace function reject_finance_session(p_session_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); row finance_collection_sessions%rowtype;
begin
  if clinic is null or not has_permission('sessions.manage') then raise exception 'Collection session rejection denied'; end if;
  if length(trim(coalesce(p_reason,'')))<4 then raise exception 'A rejection reason is required'; end if;
  update finance_collection_sessions set status='rejected',rejection_reason=trim(p_reason),validated_at=now(),validated_by=auth.uid()
    where id=p_session_id and clinic_id=clinic and status='submitted' returning * into row;
  if row.id is null then raise exception 'Submitted collection session not found'; end if;
  return jsonb_build_object('id',row.id,'status','Rejected','rejectionReason',row.rejection_reason,
    'validatedAt',row.validated_at,'validatedBy',row.validated_by);
end $$;

create or replace function reschedule_finance_installment(p_installment_id uuid,p_due_date date,p_reason text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); item finance_installments%rowtype; old_date date;
begin
  if clinic is null or not has_permission('payments.correct') then raise exception 'Installment reschedule denied'; end if;
  if p_due_date is null or length(trim(coalesce(p_reason,'')))<4 then raise exception 'Invalid reschedule details'; end if;
  select * into item from finance_installments where id=p_installment_id and clinic_id=clinic for update;
  if item.id is null then raise exception 'Installment not found'; end if;
  if (finance_installment_json(item.id)->>'status')='paid' then raise exception 'Paid installment cannot be rescheduled'; end if;
  select coalesce((select new_due_date from finance_installment_reschedules where installment_id=item.id order by changed_at desc,id desc limit 1),item.original_due_date) into old_date;
  if p_due_date=old_date then raise exception 'Due date unchanged'; end if;
  insert into finance_installment_reschedules(clinic_id,installment_id,old_due_date,new_due_date,reason,changed_by)
    values(clinic,item.id,old_date,p_due_date,trim(p_reason),auth.uid());
  return finance_installment_json(item.id);
end $$;

create or replace function configure_finance_documents(p_receipt_prefix text,p_correction_prefix text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); row finance_document_settings%rowtype;
begin
  if clinic is null or not has_permission('settings.manage') then raise exception 'Document settings denied'; end if;
  if p_receipt_prefix !~ '^[A-Z0-9]{2,12}$' or p_correction_prefix !~ '^[A-Z0-9]{2,12}$'
    or p_receipt_prefix=p_correction_prefix then raise exception 'Invalid document prefixes'; end if;
  insert into finance_document_settings(clinic_id,receipt_prefix,correction_prefix)
    values(clinic,p_receipt_prefix,p_correction_prefix)
    on conflict(clinic_id) do update set receipt_prefix=excluded.receipt_prefix,
      correction_prefix=excluded.correction_prefix,updated_at=now() returning * into row;
  return jsonb_build_object('receiptPrefix',row.receipt_prefix,'correctionPrefix',row.correction_prefix,
    'nextReceipt',row.next_receipt,'nextCorrection',row.next_correction);
end $$;

create or replace function finance_document_config()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); row finance_document_settings%rowtype;
begin
  if clinic is null or not has_permission('settings.manage') then raise exception 'Document settings denied'; end if;
  select * into row from finance_document_settings where clinic_id=clinic;
  return jsonb_build_object('receiptPrefix',coalesce(row.receipt_prefix,'REC'),
    'correctionPrefix',coalesce(row.correction_prefix,'COR'),
    'nextReceipt',coalesce(row.next_receipt,1),'nextCorrection',coalesce(row.next_correction,1));
end $$;

create or replace function reject_finance_schedule_mutation()
returns trigger language plpgsql set search_path=public as $$
begin raise exception 'Finance schedule history is immutable; create a reschedule event instead'; end $$;
create trigger finance_installments_immutable before update or delete on finance_installments for each row execute function reject_finance_schedule_mutation();
create trigger finance_reschedules_immutable before update or delete on finance_installment_reschedules for each row execute function reject_finance_schedule_mutation();

revoke all on function finance_next_document_number(uuid,text),finance_document_identity(uuid,text,text),
  finance_installment_json(uuid,date),finance_account_json(uuid),reject_finance_schedule_mutation(),
  record_finance_payment_phase6(text,text,text,numeric,text,text,text,uuid,numeric,date,integer),
  reschedule_finance_installment(uuid,date,text),configure_finance_documents(text,text),
  reject_finance_session(uuid,text),finance_document_config(),initialize_finance_schedule(uuid,date,integer,text) from public,anon,authenticated;
grant execute on function record_finance_payment_phase6(text,text,text,numeric,text,text,text,uuid,numeric,date,integer),
  reschedule_finance_installment(uuid,date,text),configure_finance_documents(text,text),
  reject_finance_session(uuid,text),finance_document_config(),initialize_finance_schedule(uuid,date,integer,text) to authenticated;
