-- Run against a development database with an active administrator profile.
-- Internal/public fixtures are created in one transaction and rolled back.
begin;

select set_config('request.jwt.claim.sub',(select id::text from staff_profiles where active=true and role='administrator' order by created_at limit 1),true);
set local role authenticated;

do $appointment_test$
declare clinic uuid:=current_clinic_id(); patient_app text; practitioner_app text; service_app text; test_date date:=current_date+40;
  created jsonb; updated jsonb; public_date date:=current_date+30; public_date_2 date; slots jsonb; slots_2 jsonb; booked jsonb; managed jsonb; moved jsonb; cancelled jsonb; token text;
begin
  while extract(isodow from test_date)=7 loop test_date:=test_date+1; end loop;
  select app_id into patient_app from patients where clinic_id=clinic order by created_at limit 1;
  select id into practitioner_app from app_records where clinic_id=clinic and collection='doctors' order by id limit 1;
  select id into service_app from app_records where clinic_id=clinic and collection='treatments' order by id limit 1;

  created:=create_internal_appointment(patient_app,practitioner_app,service_app,test_date,'08:00',30,'Rendez-vous QA','Confirmé',null,null);
  if created->>'reference' is null then raise exception 'Internal appointment was not created'; end if;
  begin
    perform create_internal_appointment(patient_app,practitioner_app,service_app,test_date,'08:15',30,'Conflit QA','Confirmé',null,null);
    raise exception 'Overlapping appointment unexpectedly succeeded';
  exception when others then if sqlerrm='Overlapping appointment unexpectedly succeeded' then raise; end if; end;

  updated:=update_internal_appointment(created->>'id',patient_app,practitioner_app,service_app,test_date,'08:30',30,'Rendez-vous QA déplacé','Confirmé',null,null);
  if updated->>'time'<>'08:30' then raise exception 'Internal reschedule failed'; end if;
  updated:=update_internal_appointment(created->>'id',patient_app,practitioner_app,service_app,test_date,'08:30',30,'Rendez-vous QA déplacé','Arrivé',null,null);
  if updated->>'status'<>'Arrivé' then raise exception 'Status transition failed'; end if;

  while extract(isodow from public_date)=7 loop public_date:=public_date+1; end loop;
  slots:=public_available_slots('consultation',public_date);
  if jsonb_array_length(slots)=0 then raise exception 'No public slots available for QA'; end if;
  booked:=public_create_booking('consultation',public_date,slots->>0,'Test','Agenda','0600000003','qa-agenda@example.invalid');
  token:=booked->>'manageToken';
  if length(token)<32 then raise exception 'Management token was not issued'; end if;
  managed:=public_booking_manage(token);
  if managed->>'reference'<>booked->>'reference' or coalesce((managed->>'canManage')::boolean,false)=false then raise exception 'Management page lookup failed'; end if;

  public_date_2:=public_date+1;while extract(isodow from public_date_2)=7 loop public_date_2:=public_date_2+1; end loop;
  slots_2:=public_available_slots('consultation',public_date_2);
  if jsonb_array_length(slots_2)=0 then raise exception 'No reschedule slots available for QA'; end if;
  moved:=public_reschedule_booking(token,public_date_2,slots_2->>0);
  if moved->>'date'<>public_date_2::text then raise exception 'Public reschedule failed'; end if;
  cancelled:=public_cancel_booking(token,'Test transactionnel');
  if cancelled->>'status'<>'Annulé' then raise exception 'Public cancellation failed'; end if;
end
$appointment_test$;

reset role;
do $event_test$
begin
  if (select count(*) from appointment_events where next_value->>'reason' like 'Rendez-vous QA%')<3 then raise exception 'Internal appointment events are incomplete'; end if;
  if not exists(select 1 from appointment_events where actor_type='patient' and event_type='rescheduled') then raise exception 'Public reschedule event is missing'; end if;
  if not exists(select 1 from appointment_events where actor_type='patient' and event_type='cancelled') then raise exception 'Public cancellation event is missing'; end if;
end
$event_test$;

rollback;
