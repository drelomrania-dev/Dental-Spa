-- Run against a development database with an active administrator profile.
-- Every finance fixture is rolled back.
begin;

select set_config(
  'request.jwt.claim.sub',
  (select id::text from staff_profiles where active=true and role='administrator' order by created_at limit 1),
  true
);
set local role authenticated;

do $finance_test$
declare
  clinic uuid:=current_clinic_id();
  session jsonb;
  payment jsonb;
  duplicate_payment jsonb;
  correction jsonb;
  submitted jsonb;
  transaction_id uuid;
  balance jsonb;
begin
  if clinic is null then raise exception 'Missing administrator clinic context'; end if;

  perform create_patient_record(jsonb_build_object('id','qa-finance-patient','firstName','Test','lastName','Finance','phone','0600000001','status','Actif'));
  insert into app_records(clinic_id,collection,id,data)
  values(clinic,'treatments','qa-finance-treatment',jsonb_build_object('id','qa-finance-treatment','name','Test finance','price',1000,'active',true));

  session:=open_finance_session(100);
  payment:=record_finance_payment('qa-finance-patient','qa-finance-treatment','',600,'2 fois','Espèces','qa-finance-payment-key',(session->>'id')::uuid,null);
  duplicate_payment:=record_finance_payment('qa-finance-patient','qa-finance-treatment','',600,'2 fois','Espèces','qa-finance-payment-key',(session->>'id')::uuid,null);
  if payment->>'id'<>duplicate_payment->>'id' then raise exception 'Idempotency failed'; end if;
  if (payment->>'remaining')::numeric<>400 then raise exception 'Incorrect balance after payment'; end if;

  transaction_id:=(payment->>'id')::uuid;
  correction:=correct_finance_payment(transaction_id,100,'Erreur de saisie','qa-finance-correction-key');
  if (correction->>'paid')::numeric<>-100 then raise exception 'Correction sign is invalid'; end if;

  balance:=finance_account_balance('qa-finance-patient','qa-finance-treatment');
  if (balance->>'paid')::numeric<>500 or (balance->>'remaining')::numeric<>500 then raise exception 'Ledger balance is invalid'; end if;

  begin
    perform record_finance_payment('qa-finance-patient','qa-finance-treatment','',600,'2 fois','Espèces','qa-finance-overpayment-key',(session->>'id')::uuid,null);
    raise exception 'Overpayment unexpectedly succeeded';
  exception when others then
    if sqlerrm='Overpayment unexpectedly succeeded' then raise; end if;
  end;

  begin
    update finance_transactions set amount=1 where id=transaction_id;
    raise exception 'Immutable ledger update unexpectedly succeeded';
  exception when others then
    if sqlerrm='Immutable ledger update unexpectedly succeeded' then raise; end if;
  end;

  submitted:=submit_finance_session((session->>'id')::uuid,600);
  if (submitted->>'discrepancy')::numeric<>0 then raise exception 'Cash reconciliation is invalid'; end if;
  perform validate_finance_session((session->>'id')::uuid);

  if jsonb_array_length(finance_snapshot()->'payments')<2 then raise exception 'Finance snapshot is incomplete'; end if;
end
$finance_test$;

rollback;
