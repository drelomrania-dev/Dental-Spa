-- Resource collisions and public contact throttling must be enforced in the database.
begin;

select set_config('request.jwt.claim.sub',(select id::text from staff_profiles where active=true and role='administrator' order by created_at limit 1),true);
set local role authenticated;

do $resource_test$
declare clinic uuid:=current_clinic_id(); patient_app text; practitioner_one text; practitioner_two text; service_app text; test_date date:=current_date+55; first_booking jsonb; second_booking jsonb;
begin
  while extract(isodow from test_date)=7 loop test_date:=test_date+1; end loop;
  select row->>'id' into patient_app from jsonb_array_elements(patients_snapshot()) row limit 1;
  select min(id),max(id) into practitioner_one,practitioner_two from app_records where clinic_id=clinic and collection='doctors' and coalesce((data->>'active')::boolean,true);
  select id into service_app from app_records where clinic_id=clinic and collection='treatments' and coalesce((data->>'active')::boolean,true) order by id limit 1;
  if practitioner_one=practitioner_two then raise exception 'Two practitioners are required for resource QA'; end if;
  perform upsert_clinic_resource('qa-chair-one','Fauteuil QA 1','chair',true);
  perform upsert_clinic_resource('qa-chair-two','Fauteuil QA 2','chair',true);
  first_booking:=create_internal_appointment(patient_app,practitioner_one,service_app,test_date,'08:00',30,'Ressource QA 1','Confirmé',null,'qa-chair-one');
  begin
    perform create_internal_appointment(patient_app,practitioner_two,service_app,test_date,'08:00',30,'Conflit ressource QA','Confirmé',null,'qa-chair-one');
    raise exception 'Overlapping resource unexpectedly succeeded';
  exception when others then if sqlerrm='Overlapping resource unexpectedly succeeded' then raise; end if; end;
  second_booking:=create_internal_appointment(patient_app,practitioner_two,service_app,test_date,'08:00',30,'Ressource QA 2','Confirmé',null,'qa-chair-two');
  if first_booking->>'roomId'<>'qa-chair-one' or second_booking->>'roomId'<>'qa-chair-two' then raise exception 'Resource assignment failed'; end if;
end
$resource_test$;

reset role;
do $public_rate_test$
declare booking_date date:=current_date+60; slots jsonb; booked jsonb; attempt integer;
begin
  for attempt in 1..3 loop
    while extract(isodow from booking_date)=7 loop booking_date:=booking_date+1; end loop;
    slots:=public_available_slots('consultation',booking_date);
    if jsonb_array_length(slots)=0 then raise exception 'No public slot for rate QA'; end if;
    booked:=public_create_booking('consultation',booking_date,slots->>0,'Test','Limite','0600000099','qa-rate@example.invalid');
    if coalesce(booked->>'roomId','')='' then raise exception 'Public booking resource was not assigned'; end if;
    booking_date:=booking_date+1;
  end loop;
  while extract(isodow from booking_date)=7 loop booking_date:=booking_date+1; end loop;
  slots:=public_available_slots('consultation',booking_date);
  begin
    perform public_create_booking('consultation',booking_date,slots->>0,'Test','Limite','06 00 00 00 99','QA-RATE@example.invalid');
    raise exception 'Rate-limited booking unexpectedly succeeded';
  exception when others then
    if sqlerrm='Rate-limited booking unexpectedly succeeded' then raise;
    elsif sqlerrm<>'Booking rate limit exceeded' then raise exception 'Unexpected rate-limit error: %',sqlerrm; end if;
  end;
end
$public_rate_test$;

rollback;
