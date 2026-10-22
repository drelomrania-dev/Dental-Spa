-- Transactional synthetic Phase 7 permission and state checks.
begin;
select set_config('qa.admin',(select id::text from staff_profiles where active and role='administrator' order by created_at limit 1),true);
select set_config('qa.clinic',(select clinic_id::text from staff_profiles where id=current_setting('qa.admin')::uuid),true);
select set_config('qa.patient',gen_random_uuid()::text,true);
select set_config('qa.appointment',gen_random_uuid()::text,true);
select set_config('qa.account',gen_random_uuid()::text,true);
select set_config('qa.installment',gen_random_uuid()::text,true);
select set_config('qa.assistant',gen_random_uuid()::text,true);
select set_config('qa.other_clinic',gen_random_uuid()::text,true);
select set_config('qa.other_admin',gen_random_uuid()::text,true);
insert into auth.users(id,aud,role,email,created_at,updated_at) values
  (current_setting('qa.assistant')::uuid,'authenticated','authenticated','phase7-assistant@example.invalid',now(),now()),
  (current_setting('qa.other_admin')::uuid,'authenticated','authenticated','phase7-other@example.invalid',now(),now());
insert into clinics(id,name,timezone) values(current_setting('qa.other_clinic')::uuid,'Other synthetic clinic','Africa/Casablanca');
insert into staff_profiles(id,clinic_id,display_name,role,active) values
  (current_setting('qa.assistant')::uuid,current_setting('qa.clinic')::uuid,'Phase 7 assistant','assistant',true),
  (current_setting('qa.other_admin')::uuid,current_setting('qa.other_clinic')::uuid,'Other admin','administrator',true);
insert into patients(id,clinic_id,app_id,first_name,last_name,email,phone) values
  (current_setting('qa.patient')::uuid,current_setting('qa.clinic')::uuid,'phase7-patient','Synthetic','Patient','phase7@example.invalid','+212600000007');
insert into appointments(id,clinic_id,patient_id,starts_at,ends_at,status,source,reference,app_id) values
  (current_setting('qa.appointment')::uuid,current_setting('qa.clinic')::uuid,current_setting('qa.patient')::uuid,
   now()+interval '12 hours',now()+interval '12 hours 30 minutes','Confirmé','internal','PHASE7-APPT','phase7-appt');
insert into finance_accounts(id,clinic_id,patient_app_id,treatment_id,quoted_total,payment_plan)
  values(current_setting('qa.account')::uuid,current_setting('qa.clinic')::uuid,'phase7-patient','phase7-service',100,'Comptant');
insert into finance_installments(id,clinic_id,account_id,sequence_no,original_due_date,amount)
  values(current_setting('qa.installment')::uuid,current_setting('qa.clinic')::uuid,current_setting('qa.account')::uuid,1,
    ((now() at time zone 'Africa/Casablanca')::date+1),100);

select set_config('request.jwt.claim.sub',current_setting('qa.admin'),true);
set local role authenticated;
do $phase7_admin$
declare snap jsonb; queued jsonb; appointment_row jsonb; installment_row jsonb; retry_row jsonb;
begin
  snap:=reminder_snapshot();
  if has_table_privilege('authenticated','reminder_outbox','select') or has_table_privilege('authenticated','reminder_consents','update')
    then raise exception 'Direct reminder table privilege leaked'; end if;
  if jsonb_array_length(snap->'rules')<>3 or (select (x->>'leadAmount')::integer from jsonb_array_elements(snap->'rules') x where x->>'kind'='appointment')<>24
    or (select (x->>'leadAmount')::integer from jsonb_array_elements(snap->'rules') x where x->>'kind'='installment_before')<>3
    or (select (x->>'leadAmount')::integer from jsonb_array_elements(snap->'rules') x where x->>'kind'='installment_due')<>0 then raise exception 'Default rules missing'; end if;
  queued:=queue_due_reminders();
  if (queued->>'queued')::integer<>0 then raise exception 'Unapproved or unconsented reminder queued'; end if;
  begin perform queue_due_reminders_all();raise exception 'Staff invoked trusted scheduler';
  exception when others then if sqlerrm='Staff invoked trusted scheduler' then raise; end if; end;
  perform save_reminder_template('appointment','email','Bonjour {first_name}, rendez-vous chez {clinic} le {date} à {time}.',true);
  perform save_reminder_template('installment_before','email','Bonjour {first_name}, échéance chez {clinic} le {date}.',true);
  begin
    perform save_reminder_template('appointment','email','Bonjour {medical_alerts}, rendez-vous le {date}.',true);
    raise exception 'Clinical variable accepted';
  exception when others then if sqlerrm='Clinical variable accepted' then raise; end if; end;
  perform record_reminder_consent('phase7-patient','email',true,'Synthetic signed intake');
  queued:=queue_due_reminders();
  if (queued->>'queued')::integer<>2 then raise exception 'Expected appointment and installment reminders, got %',queued; end if;
  queued:=queue_due_reminders();
  if (queued->>'queued')::integer<>0 then raise exception 'Queue retry duplicated rows'; end if;
  snap:=reminder_snapshot();
  select x into appointment_row from jsonb_array_elements(snap->'outbox') x where x->>'kind'='appointment';
  select x into installment_row from jsonb_array_elements(snap->'outbox') x where x->>'kind'='installment_before';
  perform set_config('qa.outbox_id',appointment_row->>'id',true);
  if appointment_row->>'body' like '%medical%' or appointment_row->>'body' like '%PHASE7-APPT%' then raise exception 'Sensitive or internal appointment text leaked'; end if;
  retry_row:=fake_dispatch_reminder((appointment_row->>'id')::uuid,true);
  if retry_row->>'status'<>'retry' or (retry_row->>'attempts')::integer<>1 then raise exception 'Failure did not schedule retry'; end if;
  begin
    perform fake_dispatch_reminder((appointment_row->>'id')::uuid,false);
    raise exception 'Early retry accepted';
  exception when others then if sqlerrm='Early retry accepted' then raise; end if; end;
  perform record_reminder_consent('phase7-patient','email',false,'Patient withdrew');
  snap:=reminder_snapshot();
  if exists(select 1 from jsonb_array_elements(snap->'outbox') x where x->>'status' in ('queued','retry')) then raise exception 'Withdrawal did not cancel pending reminders'; end if;
  if not exists(select 1 from jsonb_array_elements(snap->'events') x where x->>'outcome'='fake_failed') then raise exception 'Failure history missing'; end if;
end $phase7_admin$;

-- Assistant may record consent but loses all reminder access when grant is revoked.
select set_config('request.jwt.claim.sub',current_setting('qa.assistant'),true);
do $assistant_allowed$
begin
  perform reminder_snapshot();
  perform record_reminder_consent('phase7-patient','whatsapp',true,'Synthetic phone consent');
  begin
    perform configure_reminder_rule('appointment',false,24);
    raise exception 'Assistant changed clinic rule';
  exception when others then if sqlerrm='Assistant changed clinic rule' then raise; end if; end;
end $assistant_allowed$;
reset role;
delete from role_permissions where clinic_id=current_setting('qa.clinic')::uuid and role='assistant' and permission='reminders.manage';
set local role authenticated;
do $assistant_denied$
begin
  begin perform reminder_snapshot();raise exception 'Revoked assistant read reminders';
  exception when others then if sqlerrm='Revoked assistant read reminders' then raise; end if; end;
  begin perform record_reminder_consent('phase7-patient','email',true,'Synthetic regrant');raise exception 'Revoked assistant changed consent';
  exception when others then if sqlerrm='Revoked assistant changed consent' then raise; end if; end;
end $assistant_denied$;

-- Another clinic cannot read or dispatch an ID from this clinic.
select set_config('request.jwt.claim.sub',current_setting('qa.other_admin'),true);
do $other_clinic$
declare snap jsonb;
begin
  snap:=reminder_snapshot();
  if jsonb_array_length(snap->'outbox')<>0 then raise exception 'Cross-clinic outbox visible'; end if;
  begin perform fake_dispatch_reminder(current_setting('qa.outbox_id')::uuid,false);raise exception 'Cross-clinic dispatch succeeded';
  exception when others then if sqlerrm='Cross-clinic dispatch succeeded' then raise; end if; end;
end $other_clinic$;

select set_config('request.jwt.claim.sub',current_setting('qa.admin'),true);
do $obsolescence$
declare snap jsonb; queued jsonb;
begin
  perform record_reminder_consent('phase7-patient','email',true,'Synthetic consent restored');
  perform save_reminder_template('appointment','email','Bonjour {first_name}, rendez-vous {date} {time} chez {clinic}.',true);
  queued:=queue_due_reminders();
  snap:=reminder_snapshot();
  if (queued->>'queued')::integer<>2 or not exists(select 1 from jsonb_array_elements(snap->'outbox') x where x->>'kind'='appointment' and x->>'status'='queued')
    then raise exception 'Restored consent did not requeue valid reminders'; end if;
end $obsolescence$;
reset role;
update appointments set starts_at=starts_at+interval '1 hour',ends_at=ends_at+interval '1 hour' where id=current_setting('qa.appointment')::uuid;
set local role authenticated;
do $reschedule$
declare queued jsonb; row_id uuid; snap jsonb;
begin
  queued:=queue_due_reminders();
  if (queued->>'queued')::integer<1 then raise exception 'Rescheduled appointment not queued'; end if;
  snap:=reminder_snapshot();
  select (x->>'id')::uuid into row_id from jsonb_array_elements(snap->'outbox') x where x->>'sourceId'=current_setting('qa.appointment') and x->>'status'='queued' limit 1;
  perform fake_dispatch_reminder(row_id,false);
  snap:=reminder_snapshot();
  if not exists(select 1 from jsonb_array_elements(snap->'outbox') x where x->>'id'=row_id::text and x->>'status'='sent_fake' and (x->>'attempts')::integer=1) then raise exception 'Fake delivery not recorded'; end if;
end $reschedule$;
reset role;
update appointments set status='Annulé' where id=current_setting('qa.appointment')::uuid;
insert into finance_installment_reschedules(clinic_id,installment_id,old_due_date,new_due_date,reason,changed_by)
  values(current_setting('qa.clinic')::uuid,current_setting('qa.installment')::uuid,
    ((now() at time zone 'Africa/Casablanca')::date+1),((now() at time zone 'Africa/Casablanca')::date+2),'Synthetic reschedule',current_setting('qa.admin')::uuid);
set local role authenticated;
do $cancelled$
declare snap jsonb;
begin
  snap:=reminder_snapshot();
  if exists(select 1 from jsonb_array_elements(snap->'outbox') x where x->>'sourceId'=current_setting('qa.installment') and x->>'status' in ('queued','retry')) then raise exception 'Installment reschedule did not cancel'; end if;
  if exists(select 1 from jsonb_array_elements(snap->'outbox') x where x->>'sourceId'=current_setting('qa.appointment') and x->>'status' in ('queued','retry')) then raise exception 'Appointment cancel did not cancel'; end if;
  perform queue_due_reminders();
  snap:=reminder_snapshot();
  if not exists(select 1 from jsonb_array_elements(snap->'outbox') x where x->>'sourceId'=current_setting('qa.installment') and x->>'status'='queued') then raise exception 'Rescheduled installment was not requeued'; end if;
end $cancelled$;
reset role;
insert into finance_transactions(clinic_id,account_id,kind,amount,method,reference,idempotency_key,collected_by)
  values(current_setting('qa.clinic')::uuid,current_setting('qa.account')::uuid,'payment',100,'Carte','PHASE7-PAY','phase7-payment',current_setting('qa.admin')::uuid);
set local role authenticated;
do $paid$
declare snap jsonb;
begin
  snap:=reminder_snapshot();
  if exists(select 1 from jsonb_array_elements(snap->'outbox') x where x->>'sourceId'=current_setting('qa.installment') and x->>'status' in ('queued','retry')) then raise exception 'Paid installment reminder survived'; end if;
end $paid$;
rollback;
