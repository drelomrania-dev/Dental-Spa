-- Phase 4 booking/agenda contract. Run with synthetic local fixtures; all writes roll back.
begin;
select set_config('qa.phase4_admin',(select id::text from staff_profiles where role='administrator' and active order by created_at limit 1),true);
select set_config('qa.phase4_assistant',(select id::text from staff_profiles where role='assistant' and active order by created_at limit 1),true);
select set_config('request.jwt.claim.sub',current_setting('qa.phase4_admin'),true);
set local role authenticated;

do $phase4$
declare clinic uuid:=current_clinic_id(); patient_app text; booking_date date; next_date date; slots jsonb; moved_slots jsonb; booked jsonb; moved jsonb; cancelled jsonb; internal jsonb; token text; second_message text;
begin
  if clinic is null or current_setting('qa.phase4_assistant')='' then raise exception 'Two local staff fixtures required'; end if;
  select row->>'id' into patient_app from jsonb_array_elements(patients_snapshot()) row limit 1;
  if patient_app is null then raise exception 'Synthetic patient fixture required'; end if;
  perform upsert_clinic_resource('qa-phase4-chair','Fauteuil Phase 4','chair',true);
  insert into app_records(clinic_id,collection,id,data) values
    (clinic,'doctors','qa-phase4-doctor',jsonb_build_object('id','qa-phase4-doctor','name','Dr Phase 4','availabilityDays',jsonb_build_array(1),'startTime','10:00','endTime','12:00','active',true)),
    (clinic,'treatments','qa-phase4-short',jsonb_build_object('id','qa-phase4-short','name','Consultation Phase 4','price',100,'duration',30,'active',true,'bookingEligible',true)),
    (clinic,'treatments','qa-phase4-long',jsonb_build_object('id','qa-phase4-long','name','Soin long Phase 4','price',200,'duration',60,'active',true,'bookingEligible',true)),
    (clinic,'bookingLinks','qa-phase4-link',jsonb_build_object('id','qa-phase4-link','slug','qa-phase4-link','title','Phase 4','treatmentId','qa-phase4-short','serviceIds',jsonb_build_array('qa-phase4-short','qa-phase4-long'),'doctorId','qa-phase4-doctor','roomId','qa-phase4-chair','duration',30,'published',true));
  booking_date:=current_date+((8-extract(isodow from current_date)::integer)%7)+35;
  next_date:=booking_date+7;
  slots:=public_available_slots_for_service('qa-phase4-link',booking_date,'qa-phase4-long');
  if not slots?'10:00' or slots?'09:00' or slots?'11:30' then raise exception 'Working hours or service duration failed: %',slots; end if;
  booked:=public_create_booking_v2('qa-phase4-link','qa-phase4-long','Motif synthétique Phase 4',booking_date,'10:00','Phase','Quatre','0600000491','phase4@example.invalid');
  token:=booked->>'manageToken';
  if (booked->>'duration')::integer<>60 or booked->>'leadId' is null or booked->>'patientId' is null or booked->>'roomId'<>'qa-phase4-chair' then raise exception 'Booking patient/lead/resource link incomplete: %',booked; end if;
  begin
    perform public_create_booking_v2('qa-phase4-link','qa-phase4-long','Autre motif synthétique',booking_date,'10:00','Autre','Patient','0600000492',null);
    raise exception 'Overlapping booking unexpectedly succeeded';
  exception when others then
    get stacked diagnostics second_message=message_text;
    if second_message<>'Slot unavailable' then raise exception 'Unexpected simultaneous-slot result: %',second_message; end if;
  end;
  if public_available_slots_for_service('qa-phase4-link',booking_date,'qa-phase4-long')?'10:30' then raise exception 'Overlapping slot remained visible'; end if;
  internal:=create_internal_appointment(patient_app,'qa-phase4-doctor','qa-phase4-short',booking_date,'11:00',30,'Conflit fauteuil Phase 4','Confirmé',null,'qa-phase4-chair');
  if internal->>'roomId'<>'qa-phase4-chair' then raise exception 'Internal appointment resource missing'; end if;
  begin
    perform create_internal_appointment(patient_app,'qa-phase4-doctor','qa-phase4-short',booking_date,'11:00',30,'Conflit Phase 4','Confirmé',null,'qa-phase4-chair');
    raise exception 'Internal collision unexpectedly succeeded';
  exception when others then
    get stacked diagnostics second_message=message_text;
    if second_message<>'Appointment practitioner or resource unavailable' then raise exception 'Unexpected internal collision result: %',second_message; end if;
  end;
  update app_records set data=jsonb_set(data,'{published}','false'::jsonb) where clinic_id=clinic and collection='bookingLinks' and id='qa-phase4-link';
  moved_slots:=public_booking_reschedule_slots(token,next_date);
  if not moved_slots?'10:00' or moved_slots?'09:00' or moved_slots?'11:30' then raise exception 'Management slots ignored working hours/duration: %',moved_slots; end if;
  moved:=public_reschedule_booking(token,next_date,'10:00');
  if moved->>'date'<>next_date::text or (moved->>'duration')::integer<>60 or moved->>'reason'<>'Motif synthétique Phase 4' then raise exception 'Service-aware reschedule lost booking data'; end if;
  cancelled:=public_cancel_booking(token,'Annulation synthétique');
  if cancelled->>'status'<>'Annulé' or jsonb_array_length(public_booking_reschedule_slots(token,next_date))<>0 then raise exception 'Cancellation did not close management link'; end if;
  begin
    perform public_reschedule_booking(token,next_date,'10:30');
    raise exception 'Cancelled token unexpectedly rescheduled';
  exception when others then
    get stacked diagnostics second_message=message_text;
    if second_message<>'Booking management link unavailable' then raise exception 'Unexpected cancelled-token result: %',second_message; end if;
  end;
  perform set_config('qa.phase4_internal',internal->>'id',true);
  perform set_config('qa.phase4_patient',patient_app,true);
end
$phase4$;

-- An assistant may edit an appointment but cannot mark no-show after revocation.
reset role;
delete from role_permissions where clinic_id=(select clinic_id from staff_profiles where id=current_setting('qa.phase4_assistant')::uuid)
  and role='assistant' and permission='appointments.cancel';
select set_config('request.jwt.claim.sub',current_setting('qa.phase4_assistant'),true);
set local role authenticated;
do $permission$
declare booking jsonb; message text;
begin
  select row into booking from jsonb_array_elements(appointments_snapshot()) row where row->>'id'=current_setting('qa.phase4_internal');
  begin
    perform update_internal_appointment(booking->>'id',booking->>'patientId',booking->>'doctorId',booking->>'treatmentId',(booking->>'date')::date,booking->>'time',(booking->>'duration')::integer,booking->>'reason','No-show',null,booking->>'roomId');
    raise exception 'Assistant no-show unexpectedly succeeded';
  exception when others then
    get stacked diagnostics message=message_text;
    if message<>'Appointment cancellation denied' then raise exception 'Unexpected no-show permission result: %',message; end if;
  end;
  begin
    perform update_internal_appointment(booking->>'id',booking->>'patientId',booking->>'doctorId',booking->>'treatmentId',(booking->>'date')::date,booking->>'time',(booking->>'duration')::integer,booking->>'reason','Annulé',null,booking->>'roomId');
    raise exception 'Assistant cancellation unexpectedly succeeded';
  exception when others then
    get stacked diagnostics message=message_text;
    if message<>'Appointment cancellation denied' then raise exception 'Unexpected cancellation permission result: %',message; end if;
  end;
end
$permission$;
reset role;

-- A no-show can only be recorded once the appointment has started.
select set_config('request.jwt.claim.sub',current_setting('qa.phase4_admin'),true);
set local role authenticated;
do $timing$
declare booking jsonb; message text;
begin
  select row into booking from jsonb_array_elements(appointments_snapshot()) row where row->>'id'=current_setting('qa.phase4_internal');
  begin
    perform update_internal_appointment(booking->>'id',booking->>'patientId',booking->>'doctorId',booking->>'treatmentId',(booking->>'date')::date,booking->>'time',(booking->>'duration')::integer,booking->>'reason','No-show',null,booking->>'roomId');
    raise exception 'Future no-show unexpectedly succeeded';
  exception when others then
    get stacked diagnostics message=message_text;
    if message<>'No-show requires a started appointment' then raise exception 'Unexpected no-show timing result: %',message; end if;
  end;
end
$timing$;

reset role;
update appointments set starts_at=date_trunc('minute',now()-interval '2 hours'),ends_at=date_trunc('minute',now()-interval '90 minutes')
  where app_id=current_setting('qa.phase4_internal');
set local role authenticated;
do $no_show$
declare booking jsonb; saved jsonb;
begin
  select row into booking from jsonb_array_elements(appointments_snapshot()) row where row->>'id'=current_setting('qa.phase4_internal');
  saved:=update_internal_appointment(booking->>'id',booking->>'patientId',booking->>'doctorId',booking->>'treatmentId',(booking->>'date')::date,booking->>'time',(booking->>'duration')::integer,booking->>'reason','No-show',null,booking->>'roomId');
  if saved->>'status'<>'No-show' then raise exception 'Started no-show was not saved'; end if;
end
$no_show$;
rollback;
