-- Transactional synthetic Phase 6 checks. Requires the local seeded administrator.
begin;
select set_config('qa.admin',(select id::text from staff_profiles where active and role='administrator' order by created_at limit 1),true);
select set_config('qa.clinic',(select clinic_id::text from staff_profiles where id=current_setting('qa.admin')::uuid),true);
select set_config('qa.collector_a',gen_random_uuid()::text,true);
select set_config('qa.collector_b',gen_random_uuid()::text,true);
insert into auth.users(id,aud,role,email,created_at,updated_at)
values(current_setting('qa.collector_a')::uuid,'authenticated','authenticated','phase6-a@example.invalid',now(),now()),
      (current_setting('qa.collector_b')::uuid,'authenticated','authenticated','phase6-b@example.invalid',now(),now());
insert into staff_profiles(id,clinic_id,display_name,role,active)
values(current_setting('qa.collector_a')::uuid,current_setting('qa.clinic')::uuid,'Phase 6 A','assistant',true),
      (current_setting('qa.collector_b')::uuid,current_setting('qa.clinic')::uuid,'Phase 6 B','assistant',true);
insert into patients(clinic_id,app_id,first_name,last_name)
values(current_setting('qa.clinic')::uuid,'phase6-patient','Phase','Six');
insert into app_records(clinic_id,collection,id,data)
values(current_setting('qa.clinic')::uuid,'treatments','phase6-service',
  jsonb_build_object('id','phase6-service','name','Phase 6 service','price',900,'active',true,'bookingEligible',true));
insert into finance_accounts(clinic_id,patient_app_id,treatment_id,quoted_total,payment_plan)
values(current_setting('qa.clinic')::uuid,'phase6-patient','phase6-legacy',500,'2 fois');

select set_config('request.jwt.claim.sub',current_setting('qa.admin'),true);
set local role authenticated;
do $phase6_admin$
declare replay jsonb; account jsonb; legacy jsonb; payment jsonb; correction jsonb; item jsonb;
  original_snapshot jsonb; first_session jsonb; second_session jsonb; saved_name text; submitted jsonb;
begin
  perform configure_finance_documents('TESTREC','TESTCOR');
  select row into legacy from jsonb_array_elements(finance_snapshot()->'accounts') row where row->>'treatmentId'='phase6-legacy';
  legacy:=initialize_finance_schedule((legacy->>'id')::uuid,current_date-30,99,'Signed historical plan');
  if legacy->>'plan'<>'2 fois' or (legacy->>'total')::numeric<>500 or jsonb_array_length(legacy->'installments')<>2
    or legacy->'installments'->0->>'source'<>'historical_entry' then raise exception 'Historical schedule changed frozen account'; end if;
  begin
    perform initialize_finance_schedule((legacy->>'id')::uuid,current_date,2,'Duplicate historical plan');
    raise exception 'Duplicate historical schedule accepted';
  exception when others then if sqlerrm='Duplicate historical schedule accepted' then raise; end if; end;
  first_session:=open_finance_session(100);
  perform set_config('qa.session_a',first_session->>'id',true);
  payment:=record_finance_payment_phase6('phase6-patient','phase6-service','',300,'3 fois','Espèces',
    'phase6-payment-key',(first_session->>'id')::uuid,null,(now() at time zone 'Africa/Casablanca')::date,3);
  perform set_config('qa.payment',payment->>'id',true);
  if (finance_document_config()->>'nextReceipt')::bigint<>2 then raise exception 'Receipt counter did not advance'; end if;
  if payment->>'receiptNumber' not like 'TESTREC-%' or payment->'document'->'clinic'->>'name' is null
    or payment->'document'->>'patientName'<>'Phase Six' then raise exception 'Receipt identity or numbering missing'; end if;
  replay:=record_finance_payment_phase6('phase6-patient','phase6-service','',300,'3 fois','Espèces',
    'phase6-payment-key',(first_session->>'id')::uuid,null,null,null);
  if replay->>'id'<>payment->>'id' then raise exception 'Payment retry created a second entry'; end if;
  begin
    perform record_finance_payment_phase6('phase6-patient','phase6-service','',301,'3 fois','Espèces',
      'phase6-payment-key',(first_session->>'id')::uuid,null,null,null);
    raise exception 'Changed idempotency payload accepted';
  exception when others then if sqlerrm='Changed idempotency payload accepted' then raise; end if; end;
  account:=finance_account_balance('phase6-patient','phase6-service');
  if (account->>'total')::numeric<>900 or jsonb_array_length(account->'installments')<>3 then raise exception 'Frozen account or schedule missing'; end if;
  if (select sum((x->>'amount')::numeric) from jsonb_array_elements(account->'installments') x)<>900 then raise exception 'Installments do not sum to account'; end if;
  if account->'installments'->0->>'status'<>'paid' or account->'installments'->1->>'status'<>'due' then raise exception 'Installment allocation invalid'; end if;
  item:=reschedule_finance_installment((account->'installments'->1->>'id')::uuid,(now() at time zone 'Africa/Casablanca')::date+40,'Patient request');
  if item->>'status'<>'rescheduled' or jsonb_array_length(item->'rescheduleHistory')<>1 then raise exception 'Reschedule history invalid'; end if;
  begin
    perform record_finance_payment_phase6('phase6-patient','phase6-service','',601,'Comptant','Espèces',
      'phase6-overpay-key',(first_session->>'id')::uuid,null,null,null);
    raise exception 'Overpayment accepted';
  exception when others then if sqlerrm='Overpayment accepted' then raise; end if; end;
  original_snapshot:=payment->'document';
  select name into saved_name from clinics where id=current_setting('qa.clinic')::uuid;
  perform set_config('qa.clinic_name',saved_name,true);
  correction:=correct_finance_payment((payment->>'id')::uuid,100,'Synthetic refund','phase6-correction-key');
  if (finance_document_config()->>'nextCorrection')::bigint<>2 then raise exception 'Correction counter did not advance'; end if;
  if correction->>'reversesTransactionId'<>payment->>'id' or correction->>'receiptNumber' not like 'TESTCOR-%'
    or correction->'document'->>'originalReceiptNumber'<>payment->>'receiptNumber' then raise exception 'Linked correction document invalid'; end if;
  if (finance_account_balance('phase6-patient','phase6-service')->>'paid')::numeric<>200 then raise exception 'Refund ledger effect invalid'; end if;
  if (select p->'document' from jsonb_array_elements(finance_snapshot()->'payments') p where p->>'id'=payment->>'id')<>original_snapshot then raise exception 'Original receipt was changed'; end if;
  begin
    perform correct_finance_payment((payment->>'id')::uuid,201,'Too much refund','phase6-excess-refund');
    raise exception 'Excess correction accepted';
  exception when others then if sqlerrm='Excess correction accepted' then raise; end if; end;
  second_session:=open_finance_session(0);
  perform set_config('qa.session_admin',second_session->>'id',true);
  submitted:=submit_finance_session((first_session->>'id')::uuid,300);
  if (submitted->>'discrepancy')::numeric<>0 then raise exception 'Cash expectation incorrect'; end if;
  perform validate_finance_session((first_session->>'id')::uuid);
  perform record_finance_payment_phase6('phase6-patient','phase6-service','',50,'Comptant','Carte',
    'phase6-frozen-account',null,500,null,null);
  account:=finance_account_balance('phase6-patient','phase6-service');
  if (account->>'total')::numeric<>900 or account->>'plan'<>'3 fois' or jsonb_array_length(account->'installments')<>3
    then raise exception 'Existing account price or plan was rewritten'; end if;
end $phase6_admin$;

reset role;
update clinics set name='Phase 6 renamed clinic' where id=current_setting('qa.clinic')::uuid;
set local role authenticated;
do $historical_identity$
declare payment jsonb;
begin
  select p into payment from jsonb_array_elements(finance_snapshot()->'payments') p
    where p->>'id'=current_setting('qa.payment');
  if payment->'document'->'clinic'->>'name'<>current_setting('qa.clinic_name')
    or payment->'document'->'clinic'->>'name'='Phase 6 renamed clinic' then raise exception 'Historical receipt identity drifted'; end if;
end $historical_identity$;

-- Two independent collectors see only their own session. The administrator can see both.
select set_config('request.jwt.claim.sub',current_setting('qa.collector_a'),true);
do $collector_a$
declare session_a jsonb; snapshot jsonb;
begin
  session_a:=open_finance_session(25);
  perform set_config('qa.a_session',session_a->>'id',true);
  snapshot:=finance_snapshot();
  if jsonb_array_length(snapshot->'sessions')<>1 or snapshot->'sessions'->0->>'id'<>session_a->>'id' then raise exception 'Collector A session isolation failed'; end if;
  if jsonb_array_length(snapshot->'accounts')<>0 then raise exception 'Collector A saw account ledger'; end if;
end $collector_a$;
select set_config('request.jwt.claim.sub',current_setting('qa.collector_b'),true);
do $collector_b$
declare session_b jsonb; snapshot jsonb;
begin
  session_b:=open_finance_session(10);
  snapshot:=finance_snapshot();
  if jsonb_array_length(snapshot->'sessions')<>1 or snapshot->'sessions'->0->>'id'<>session_b->>'id' then raise exception 'Collector B session isolation failed'; end if;
  begin
    perform submit_finance_session(current_setting('qa.a_session')::uuid,25);
    raise exception 'Collector B closed A session';
  exception when others then if sqlerrm='Collector B closed A session' then raise; end if; end;
  perform submit_finance_session((session_b->>'id')::uuid,9);
end $collector_b$;
select set_config('request.jwt.claim.sub',current_setting('qa.admin'),true);
do $admin_validation$
declare snapshot jsonb; result jsonb;
begin
  snapshot:=finance_snapshot();
  if jsonb_array_length(snapshot->'sessions')<4 then raise exception 'Administrator session overview incomplete'; end if;
  select row into result from jsonb_array_elements(snapshot->'sessions') row
    where row->>'openedBy'=current_setting('qa.collector_b');
  perform reject_finance_session((result->>'id')::uuid,'Count discrepancy');
  snapshot:=finance_snapshot();
  if not exists(select 1 from jsonb_array_elements(snapshot->'sessions') row where row->>'openedBy'=current_setting('qa.collector_b')
    and row->>'status'='Rejected' and (row->>'discrepancy')::numeric=-1) then raise exception 'Rejection or discrepancy missing'; end if;
end $admin_validation$;
reset role;
do $immutability$
begin
  begin update finance_installments set amount=1 where account_id=(select account_id from finance_transactions where id=current_setting('qa.payment')::uuid);raise exception 'Installment mutated';
  exception when others then if sqlerrm='Installment mutated' then raise; end if; end;
  begin update finance_receipts set snapshot='{}'::jsonb where transaction_id=current_setting('qa.payment')::uuid;raise exception 'Receipt mutated';
  exception when others then if sqlerrm='Receipt mutated' then raise; end if; end;
end $immutability$;
rollback;
