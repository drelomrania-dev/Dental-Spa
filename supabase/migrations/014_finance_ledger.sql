-- Normalized, append-only finance ledger. Existing document-store payments are
-- migrated once and remain readable for rollback/audit purposes.

create table if not exists finance_accounts (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id) on delete cascade,
  patient_app_id text not null,
  treatment_id text not null,
  doctor_id text,
  quoted_total numeric(12,2) not null check(quoted_total>=0),
  payment_plan text not null default 'Comptant',
  currency text not null default 'MAD',
  status text not null default 'open' check(status in ('open','paid','refunded','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(clinic_id,patient_app_id,treatment_id),
  foreign key(clinic_id,patient_app_id) references patients(clinic_id,app_id) on delete restrict
);

create table if not exists finance_collection_sessions (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id) on delete cascade,
  opened_by uuid not null references staff_profiles(id) on delete restrict,
  business_date date not null default current_date,
  opening_cash numeric(12,2) not null default 0 check(opening_cash>=0),
  status text not null default 'open' check(status in ('open','submitted','validated','rejected')),
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  counted_cash numeric(12,2),
  recorded_total numeric(12,2),
  recorded_cash numeric(12,2),
  discrepancy numeric(12,2),
  validated_at timestamptz,
  validated_by uuid references staff_profiles(id),
  rejection_reason text,
  legacy_app_id text,
  unique(clinic_id,legacy_app_id)
);
create table if not exists finance_transactions (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id) on delete cascade,
  account_id uuid not null references finance_accounts(id) on delete restrict,
  session_id uuid references finance_collection_sessions(id) on delete restrict,
  kind text not null check(kind in ('payment','refund','correction')),
  amount numeric(12,2) not null check(amount>0),
  method text not null,
  reference text not null,
  idempotency_key text not null,
  collected_by uuid not null references staff_profiles(id) on delete restrict,
  reverses_transaction_id uuid references finance_transactions(id) on delete restrict,
  reason text,
  occurred_at timestamptz not null default now(),
  legacy_app_id text,
  metadata jsonb not null default '{}'::jsonb,
  unique(clinic_id,reference),
  unique(clinic_id,idempotency_key),
  unique(clinic_id,legacy_app_id)
);

create index if not exists finance_transactions_account_idx on finance_transactions(account_id,occurred_at,id);
create index if not exists finance_transactions_session_idx on finance_transactions(session_id) where session_id is not null;

create table if not exists finance_receipts (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id) on delete cascade,
  transaction_id uuid not null unique references finance_transactions(id) on delete restrict,
  receipt_number text not null,
  issued_at timestamptz not null default now(),
  snapshot jsonb not null,
  unique(clinic_id,receipt_number)
);

alter table finance_accounts enable row level security;
alter table finance_collection_sessions enable row level security;
alter table finance_transactions enable row level security;
alter table finance_receipts enable row level security;

revoke all on finance_accounts,finance_collection_sessions,finance_transactions,finance_receipts from anon,authenticated;

create or replace function finance_effect(p_kind text,p_amount numeric)
returns numeric language sql immutable as $$
  select case when p_kind='payment' then p_amount else -p_amount end
$$;

create or replace function finance_account_paid(p_account_id uuid)
returns numeric language sql stable security definer set search_path=public as $$
  select coalesce(sum(finance_effect(kind,amount)),0)::numeric(12,2)
  from finance_transactions where account_id=p_account_id
$$;

create or replace function finance_resolved_price(p_clinic uuid,p_patient text,p_treatment text)
returns numeric language plpgsql stable security definer set search_path=public as $$
declare result numeric;
begin
  select case when data->>'proposedPrice' ~ '^\d+(\.\d{1,2})?$' then (data->>'proposedPrice')::numeric end
  into result
  from app_records
  where clinic_id=p_clinic and collection='priceRequests'
    and data->>'patientId'=p_patient and data->>'treatmentId'=p_treatment and data->>'status'='Approved'
  order by coalesce(data->>'decidedAt',data->>'createdAt','') desc limit 1;
  if result is not null then return result; end if;

  select case when data->>'price' ~ '^\d+(\.\d{1,2})?$' then (data->>'price')::numeric end
  into result
  from app_records
  where clinic_id=p_clinic and collection='treatments' and id=p_treatment limit 1;
  return result;
end;
$$;

create or replace function finance_transaction_json(p_transaction_id uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'id',t.id,'patientId',a.patient_app_id,'treatmentId',a.treatment_id,'doctorId',coalesce(a.doctor_id,''),
    'date',to_char(t.occurred_at at time zone 'Africa/Casablanca','YYYY-MM-DD'),
    'total',case when t.kind='payment' and not exists(select 1 from finance_transactions earlier where earlier.account_id=t.account_id and earlier.kind='payment' and (earlier.occurred_at,earlier.id)<(t.occurred_at,t.id)) then a.quoted_total else 0 end,
    'accountTotal',a.quoted_total,
    'paid',finance_effect(t.kind,t.amount),'remaining',greatest(a.quoted_total-finance_account_paid(a.id),0),
    'plan',a.payment_plan,'method',t.method,'status',case when finance_account_paid(a.id)>=a.quoted_total then 'Payé' else 'Partiel' end,
    'reference',t.reference,'idempotencyKey',t.idempotency_key,'collectorUserId',t.collected_by,
    'sessionId',coalesce(t.session_id::text,''),'kind',t.kind,'reason',coalesce(t.reason,''),
    'receiptNumber',r.receipt_number,'occurredAt',t.occurred_at
  )
  from finance_transactions t join finance_accounts a on a.id=t.account_id
  join finance_receipts r on r.transaction_id=t.id where t.id=p_transaction_id
$$;

create or replace function finance_snapshot()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); role_name text:=current_staff_role(); result jsonb;
begin
  if clinic is null then raise exception 'Authentication required'; end if;
  if not (has_permission('payments.view.all') or has_permission('payments.view.own') or has_permission('payments.collect') or has_permission('sessions.own') or has_permission('sessions.manage')) then
    raise exception 'Finance access denied';
  end if;
  select jsonb_build_object(
    'payments',coalesce((
      select jsonb_agg(finance_transaction_json(t.id) order by t.occurred_at desc)
      from finance_transactions t where t.clinic_id=clinic
        and (role_name='administrator' or has_permission('payments.view.all') or (has_permission('payments.view.own') and t.collected_by=auth.uid()))
    ),'[]'::jsonb),
    'sessions',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',s.id,'openedBy',s.opened_by,'openedAt',s.opened_at,'date',s.business_date,'status',initcap(s.status),
        'openingCash',s.opening_cash,'closedAt',s.closed_at,'countedCash',s.counted_cash,
        'recordedTotal',s.recorded_total,'recordedCash',s.recorded_cash,'discrepancy',s.discrepancy,'validatedAt',s.validated_at,'validatedBy',s.validated_by
      ) order by s.opened_at desc)
      from finance_collection_sessions s where s.clinic_id=clinic
        and (role_name='administrator' or has_permission('sessions.manage') or (has_permission('sessions.own') and s.opened_by=auth.uid()))
    ),'[]'::jsonb)
  ) into result;
  return result;
end;
$$;

create or replace function finance_account_balance(p_patient_app_id text,p_treatment_id text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); account finance_accounts%rowtype; paid numeric;
begin
  if clinic is null or not (has_permission('payments.collect') or has_permission('payments.view.all')) then raise exception 'Finance access denied'; end if;
  select * into account from finance_accounts where clinic_id=clinic and patient_app_id=p_patient_app_id and treatment_id=p_treatment_id;
  if account.id is null then
    return jsonb_build_object('total',coalesce(finance_resolved_price(clinic,p_patient_app_id,p_treatment_id),0),'paid',0,'remaining',coalesce(finance_resolved_price(clinic,p_patient_app_id,p_treatment_id),0));
  end if;
  paid:=finance_account_paid(account.id);
  return jsonb_build_object('total',account.quoted_total,'paid',paid,'remaining',greatest(account.quoted_total-paid,0));
end;
$$;

create or replace function record_finance_payment(
  p_patient_app_id text,p_treatment_id text,p_doctor_id text,p_amount numeric,p_plan text,p_method text,
  p_idempotency_key text,p_session_id uuid default null,p_expected_total numeric default null
)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); account finance_accounts%rowtype; session finance_collection_sessions%rowtype;
  resolved_total numeric; already_paid numeric; transaction_id uuid; receipt_no text; existing_id uuid;
begin
  if clinic is null or not has_permission('payments.collect') then raise exception 'Payment collection denied'; end if;
  if p_amount is null or p_amount<=0 or length(trim(coalesce(p_method,'')))<2 or length(trim(coalesce(p_idempotency_key,'')))<8 then raise exception 'Invalid payment details'; end if;
  if not exists(select 1 from patients where clinic_id=clinic and app_id=p_patient_app_id) then raise exception 'Patient not found'; end if;

  select id into existing_id from finance_transactions where clinic_id=clinic and idempotency_key=p_idempotency_key;
  if existing_id is not null then return finance_transaction_json(existing_id); end if;

  if current_staff_role()<>'administrator' then
    if p_session_id is null then raise exception 'An open collection session is required'; end if;
    select * into session from finance_collection_sessions where id=p_session_id and clinic_id=clinic and opened_by=auth.uid() and status='open' for update;
    if session.id is null then raise exception 'Collection session unavailable'; end if;
  elsif p_session_id is not null then
    select * into session from finance_collection_sessions where id=p_session_id and clinic_id=clinic and status='open' for update;
    if session.id is null then raise exception 'Collection session unavailable'; end if;
  end if;

  perform pg_advisory_xact_lock(hashtext(clinic::text||':'||p_patient_app_id||':'||p_treatment_id));
  select * into account from finance_accounts where clinic_id=clinic and patient_app_id=p_patient_app_id and treatment_id=p_treatment_id for update;
  if account.id is null then
    resolved_total:=finance_resolved_price(clinic,p_patient_app_id,p_treatment_id);
    if resolved_total is null and current_staff_role()='administrator' then resolved_total:=p_expected_total; end if;
    if resolved_total is null or resolved_total<=0 then raise exception 'No approved treatment price is available'; end if;
    insert into finance_accounts(clinic_id,patient_app_id,treatment_id,doctor_id,quoted_total,payment_plan)
    values(clinic,p_patient_app_id,p_treatment_id,nullif(p_doctor_id,''),resolved_total,coalesce(nullif(p_plan,''),'Comptant')) returning * into account;
  end if;
  already_paid:=finance_account_paid(account.id);
  if p_amount>account.quoted_total-already_paid then raise exception 'Payment exceeds outstanding balance'; end if;

  receipt_no:='REC-'||to_char(clock_timestamp() at time zone 'Africa/Casablanca','YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
  insert into finance_transactions(clinic_id,account_id,session_id,kind,amount,method,reference,idempotency_key,collected_by)
  values(clinic,account.id,p_session_id,'payment',round(p_amount,2),trim(p_method),receipt_no,p_idempotency_key,auth.uid()) returning id into transaction_id;
  update finance_accounts set status=case when already_paid+p_amount>=quoted_total then 'paid' else 'open' end,updated_at=now() where id=account.id;
  insert into finance_receipts(clinic_id,transaction_id,receipt_number,snapshot)
  values(clinic,transaction_id,receipt_no,jsonb_build_object('clinicId',clinic,'patientId',p_patient_app_id,'treatmentId',p_treatment_id,'total',account.quoted_total,'amount',round(p_amount,2),'remaining',greatest(account.quoted_total-already_paid-p_amount,0),'method',trim(p_method),'plan',account.payment_plan,'issuedAt',now(),'collectorId',auth.uid()));
  return finance_transaction_json(transaction_id);
end;
$$;

create or replace function correct_finance_payment(p_transaction_id uuid,p_amount numeric,p_reason text,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); original finance_transactions%rowtype; reversed numeric; transaction_id uuid; receipt_no text; existing_id uuid;
begin
  if clinic is null or not has_permission('payments.correct') then raise exception 'Payment correction denied'; end if;
  if p_amount is null or p_amount<=0 or length(trim(coalesce(p_reason,'')))<4 or length(trim(coalesce(p_idempotency_key,'')))<8 then raise exception 'Invalid correction details'; end if;
  select id into existing_id from finance_transactions where clinic_id=clinic and idempotency_key=p_idempotency_key;
  if existing_id is not null then return finance_transaction_json(existing_id); end if;
  select * into original from finance_transactions where id=p_transaction_id and clinic_id=clinic and kind='payment' for update;
  if original.id is null then raise exception 'Original payment not found'; end if;
  select coalesce(sum(amount),0) into reversed from finance_transactions where reverses_transaction_id=original.id and kind in ('refund','correction');
  if p_amount>original.amount-reversed then raise exception 'Correction exceeds refundable amount'; end if;
  receipt_no:='AVOIR-'||to_char(clock_timestamp() at time zone 'Africa/Casablanca','YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
  insert into finance_transactions(clinic_id,account_id,session_id,kind,amount,method,reference,idempotency_key,collected_by,reverses_transaction_id,reason)
  values(clinic,original.account_id,original.session_id,'refund',round(p_amount,2),original.method,receipt_no,p_idempotency_key,auth.uid(),original.id,trim(p_reason)) returning id into transaction_id;
  update finance_accounts set status=case when finance_account_paid(id)<=0 then 'refunded' else 'open' end,updated_at=now() where id=original.account_id;
  insert into finance_receipts(clinic_id,transaction_id,receipt_number,snapshot)
  select clinic,transaction_id,receipt_no,jsonb_build_object('clinicId',clinic,'originalTransactionId',original.id,'amount',round(p_amount,2),'reason',trim(p_reason),'issuedAt',now(),'actorId',auth.uid());
  return finance_transaction_json(transaction_id);
end;
$$;

create or replace function open_finance_session(p_opening_cash numeric default 0)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); row finance_collection_sessions%rowtype;
begin
  if clinic is null or not has_permission('sessions.own') then raise exception 'Collection session access denied'; end if;
  if coalesce(p_opening_cash,0)<0 then raise exception 'Invalid opening cash'; end if;
  insert into finance_collection_sessions(clinic_id,opened_by,opening_cash)
  values(clinic,auth.uid(),round(coalesce(p_opening_cash,0),2)) returning * into row;
  return jsonb_build_object('id',row.id,'openedBy',row.opened_by,'openedAt',row.opened_at,'date',row.business_date,'status','Open','openingCash',row.opening_cash);
exception when unique_violation then raise exception 'A collection session is already open';
end;
$$;

create or replace function submit_finance_session(p_session_id uuid,p_counted_cash numeric)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); row finance_collection_sessions%rowtype; total numeric; cash_expected numeric;
begin
  if clinic is null or not has_permission('sessions.own') then raise exception 'Collection session access denied'; end if;
  select * into row from finance_collection_sessions where id=p_session_id and clinic_id=clinic and opened_by=auth.uid() and status='open' for update;
  if row.id is null then raise exception 'Open collection session not found'; end if;
  if p_counted_cash is null or p_counted_cash<0 then raise exception 'Invalid counted cash'; end if;
  select coalesce(sum(finance_effect(kind,amount)),0) into total from finance_transactions where session_id=row.id;
  select row.opening_cash+coalesce(sum(finance_effect(kind,amount)) filter(where lower(method) in ('espèces','especes','cash')),0)
  into cash_expected from finance_transactions where session_id=row.id;
  update finance_collection_sessions set status='submitted',closed_at=now(),counted_cash=round(p_counted_cash,2),recorded_total=total,recorded_cash=cash_expected,discrepancy=round(p_counted_cash,2)-cash_expected where id=row.id returning * into row;
  return jsonb_build_object('id',row.id,'status','Submitted','closedAt',row.closed_at,'countedCash',row.counted_cash,'recordedTotal',row.recorded_total,'recordedCash',row.recorded_cash,'discrepancy',row.discrepancy);
end;
$$;

create or replace function validate_finance_session(p_session_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); row finance_collection_sessions%rowtype;
begin
  if clinic is null or not has_permission('sessions.manage') then raise exception 'Collection session validation denied'; end if;
  update finance_collection_sessions set status='validated',validated_at=now(),validated_by=auth.uid()
  where id=p_session_id and clinic_id=clinic and status='submitted' returning * into row;
  if row.id is null then raise exception 'Submitted collection session not found'; end if;
  return jsonb_build_object('id',row.id,'status','Validated','validatedAt',row.validated_at,'validatedBy',row.validated_by);
end;
$$;

-- Backfill legacy collection sessions and payments. Invalid local user ids are
-- attributed to the clinic administrator while preserving the original JSON.
insert into finance_collection_sessions(clinic_id,opened_by,business_date,opening_cash,status,opened_at,closed_at,counted_cash,recorded_total,recorded_cash,discrepancy,validated_at,validated_by,legacy_app_id)
select r.clinic_id,
  coalesce((select s.id from staff_profiles s where s.clinic_id=r.clinic_id and s.id::text=r.data->>'openedBy'),(select s.id from staff_profiles s where s.clinic_id=r.clinic_id and s.role='administrator' order by s.created_at limit 1)),
  coalesce(nullif(r.data->>'date','')::date,r.created_at::date),coalesce(nullif(r.data->>'openingCash','')::numeric,0),
  case lower(coalesce(r.data->>'status','open')) when 'submitted' then 'submitted' when 'validated' then 'validated' else 'open' end,
  coalesce(nullif(r.data->>'openedAt','')::timestamptz,r.created_at),nullif(r.data->>'closedAt','')::timestamptz,
  nullif(r.data->>'countedCash','')::numeric,nullif(r.data->>'recordedTotal','')::numeric,nullif(r.data->>'recordedTotal','')::numeric,nullif(r.data->>'discrepancy','')::numeric,
  nullif(r.data->>'validatedAt','')::timestamptz,
  (select s.id from staff_profiles s where s.clinic_id=r.clinic_id and s.id::text=r.data->>'validatedBy'),r.id
from app_records r where r.collection='collectionSessions'
  and exists(select 1 from staff_profiles s where s.clinic_id=r.clinic_id)
on conflict(clinic_id,legacy_app_id) do nothing;

with ranked as (
  select id,row_number() over(partition by clinic_id,opened_by order by opened_at desc,id desc) as position
  from finance_collection_sessions where status='open'
)
update finance_collection_sessions s
set status='submitted',closed_at=coalesce(s.closed_at,now()),recorded_total=coalesce(s.recorded_total,0),recorded_cash=coalesce(s.recorded_cash,s.opening_cash),discrepancy=coalesce(s.discrepancy,0)
from ranked r where r.id=s.id and r.position>1;

create unique index if not exists finance_one_open_session_per_user
  on finance_collection_sessions(clinic_id,opened_by) where status='open';

insert into finance_accounts(clinic_id,patient_app_id,treatment_id,doctor_id,quoted_total,payment_plan,status,created_at,updated_at)
select r.clinic_id,r.data->>'patientId',r.data->>'treatmentId',max(nullif(r.data->>'doctorId','')),
  greatest(sum(case when coalesce(r.data->>'total','') ~ '^\d+(\.\d{1,2})?$' then (r.data->>'total')::numeric else 0 end),0),
  max(coalesce(nullif(r.data->>'plan',''),'Comptant')),'open',min(r.created_at),max(r.updated_at)
from app_records r where r.collection='payments' and coalesce(r.data->>'patientId','')<>'' and coalesce(r.data->>'treatmentId','')<>''
  and exists(select 1 from patients p where p.clinic_id=r.clinic_id and p.app_id=r.data->>'patientId')
group by r.clinic_id,r.data->>'patientId',r.data->>'treatmentId'
having sum(case when coalesce(r.data->>'total','') ~ '^\d+(\.\d{1,2})?$' then (r.data->>'total')::numeric else 0 end)>0
on conflict(clinic_id,patient_app_id,treatment_id) do nothing;

insert into finance_transactions(clinic_id,account_id,session_id,kind,amount,method,reference,idempotency_key,collected_by,occurred_at,legacy_app_id,metadata)
select r.clinic_id,a.id,s.id,'payment',(r.data->>'paid')::numeric,coalesce(nullif(r.data->>'method',''),'Autre'),
  coalesce(nullif(r.data->>'reference',''),'LEGACY-'||r.id),coalesce(nullif(r.data->>'idempotencyKey',''),'legacy:'||r.id),
  coalesce((select sp.id from staff_profiles sp where sp.clinic_id=r.clinic_id and sp.id::text=coalesce(r.data->>'collectorUserId',r.data->>'collectedBy')),(select sp.id from staff_profiles sp where sp.clinic_id=r.clinic_id and sp.role='administrator' order by sp.created_at limit 1)),
  coalesce(nullif(r.data->>'createdAt','')::timestamptz,r.created_at),r.id,r.data
from app_records r
join finance_accounts a on a.clinic_id=r.clinic_id and a.patient_app_id=r.data->>'patientId' and a.treatment_id=r.data->>'treatmentId'
left join finance_collection_sessions s on s.clinic_id=r.clinic_id and s.legacy_app_id=r.data->>'sessionId'
where r.collection='payments' and coalesce(r.data->>'status','')<>'Annulé' and coalesce(r.data->>'paid','') ~ '^\d+(\.\d{1,2})?$' and (r.data->>'paid')::numeric>0
on conflict(clinic_id,legacy_app_id) do nothing;

insert into finance_receipts(clinic_id,transaction_id,receipt_number,snapshot)
select t.clinic_id,t.id,t.reference,jsonb_build_object('legacy',true,'source',t.metadata,'issuedAt',t.occurred_at)
from finance_transactions t where t.legacy_app_id is not null
on conflict(transaction_id) do nothing;

update finance_accounts a set status=case when finance_account_paid(a.id)>=a.quoted_total then 'paid' else 'open' end;

create or replace function reject_finance_ledger_mutation()
returns trigger language plpgsql as $$ begin raise exception 'Finance ledger entries are immutable; create a correction instead'; end $$;
drop trigger if exists finance_transactions_immutable on finance_transactions;
create trigger finance_transactions_immutable before update or delete on finance_transactions for each row execute function reject_finance_ledger_mutation();
drop trigger if exists finance_receipts_immutable on finance_receipts;
create trigger finance_receipts_immutable before update or delete on finance_receipts for each row execute function reject_finance_ledger_mutation();
revoke all on function reject_finance_ledger_mutation() from public,anon,authenticated;

revoke all on function finance_effect(text,numeric),finance_account_paid(uuid),finance_resolved_price(uuid,text,text),finance_transaction_json(uuid),finance_snapshot(),finance_account_balance(text,text),record_finance_payment(text,text,text,numeric,text,text,text,uuid,numeric),correct_finance_payment(uuid,numeric,text,text),open_finance_session(numeric),submit_finance_session(uuid,numeric),validate_finance_session(uuid) from public,anon,authenticated;
grant execute on function finance_snapshot(),finance_account_balance(text,text),record_finance_payment(text,text,text,numeric,text,text,text,uuid,numeric),correct_finance_payment(uuid,numeric,text,text),open_finance_session(numeric),submit_finance_session(uuid,numeric),validate_finance_session(uuid) to authenticated;

-- Transitional compatibility for older clients still writing app_records.
create or replace function app_record_allowed(p_collection text,p_action text,p_data jsonb default '{}'::jsonb)
returns boolean language plpgsql stable security definer set search_path=public as $$
declare role_name text:=current_staff_role(); actor text:=coalesce(p_data->>'collectorUserId',p_data->>'collectedBy');
begin
  if role_name='administrator' then return true; end if;
  if p_action='select' then return case
    when p_collection in ('_clinic','doctors','treatments','bookingLinks','staff','roles') then true
    when p_collection='appointments' then has_permission('appointments.view')
    when p_collection='payments' then has_permission('payments.view.all') or (has_permission('payments.view.own') and actor=auth.uid()::text)
    when p_collection in ('visits','treatmentPlans') then has_permission('clinical.view')
    when p_collection='priceRequests' then has_permission('priceRequests.approve') or (has_permission('priceRequests.create') and p_data->>'requestedBy'=auth.uid()::text)
    when p_collection='collectionSessions' then has_permission('sessions.manage') or (has_permission('sessions.own') and p_data->>'openedBy'=auth.uid()::text)
    when p_collection='auditEvents' then has_permission('audit.view') else false end;
  elsif p_action='insert' then return case
    when p_collection='appointments' then has_permission('appointments.create')
    when p_collection='payments' then has_permission('payments.collect') and actor=auth.uid()::text
    when p_collection='visits' then has_permission('clinical.edit') when p_collection='treatmentPlans' then has_permission('plans.create')
    when p_collection='priceRequests' then has_permission('priceRequests.create') and p_data->>'requestedBy'=auth.uid()::text
    when p_collection='collectionSessions' then has_permission('sessions.own') and p_data->>'openedBy'=auth.uid()::text
    when p_collection in ('doctors','treatments','bookingLinks','_clinic') then has_permission('settings.manage') or has_permission('services.manage')
    when p_collection in ('staff','roles') then has_permission('staff.manage') or has_permission('permissions.manage') else false end;
  elsif p_action='update' then return case
    when p_collection='appointments' then has_permission('appointments.edit') when p_collection='payments' then has_permission('payments.correct')
    when p_collection in ('visits','treatmentPlans') then has_permission('clinical.edit') when p_collection='priceRequests' then has_permission('priceRequests.approve')
    when p_collection='collectionSessions' then has_permission('sessions.manage') or (has_permission('sessions.own') and p_data->>'openedBy'=auth.uid()::text)
    when p_collection in ('doctors','treatments','bookingLinks','_clinic') then has_permission('settings.manage') or has_permission('services.manage')
    when p_collection in ('staff','roles') then has_permission('staff.manage') or has_permission('permissions.manage') else false end;
  elsif p_action='delete' then return role_name='administrator'; end if;
  return false;
end $$;
