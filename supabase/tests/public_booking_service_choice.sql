-- Service choice and patient-supplied booking reason must reach the normalized
-- agenda and the Acquisition lead. All fixtures are rolled back.
begin;

select set_config('request.jwt.claim.sub',(select id::text from staff_profiles where active=true and role='administrator' order by created_at limit 1),true);
set local role authenticated;

do $service_booking_test$
declare clinic uuid:=current_clinic_id(); booking_date date:=current_date+70; page jsonb; service_app text; slots jsonb; booked jsonb; reason_text text:='Douleur légère lors de la mastication depuis trois jours'; lead_uuid uuid;
begin
  while extract(isodow from booking_date)=7 loop booking_date:=booking_date+1; end loop;
  page:=public_booking_page('consultation');
  if jsonb_array_length(page->'services')<1 then raise exception 'Public service catalogue is empty'; end if;
  service_app:=page->'services'->0->>'id';
  slots:=public_available_slots_for_service('consultation',booking_date,service_app);
  if jsonb_array_length(slots)=0 then raise exception 'No slot for selected public service'; end if;
  booked:=public_create_booking_v2('consultation',service_app,reason_text,booking_date,slots->>0,'Test','Motif','0600000088','qa-booking-reason@example.invalid');
  if booked->>'treatmentId'<>service_app then raise exception 'Selected service was not persisted'; end if;
  if booked->>'reason'<>reason_text then raise exception 'Patient booking reason was not persisted'; end if;
  lead_uuid:=(booked->>'leadId')::uuid;
  perform set_config('qa.booking_reason_lead',lead_uuid::text,true);
  perform set_config('qa.booking_reason_service',service_app,true);
  if not exists(select 1 from leads where id=lead_uuid and clinic_id=clinic and concern=reason_text and status='Rendez-vous') then raise exception 'Booking reason was not wired to Acquisition'; end if;

  begin
    perform public_create_booking_v2('consultation','service-inexistant','Motif valide',booking_date,slots->>0,'Test','Refus','0600000087',null);
    raise exception 'Unavailable service unexpectedly succeeded';
  exception when others then if sqlerrm='Unavailable service unexpectedly succeeded' then raise; elsif sqlerrm<>'Service unavailable' then raise exception 'Unexpected service validation error: %',sqlerrm; end if; end;
  begin
    perform public_create_booking_v2('consultation',service_app,'x',booking_date,slots->>0,'Test','Refus','0600000086',null);
    raise exception 'Short booking reason unexpectedly succeeded';
  exception when others then if sqlerrm='Short booking reason unexpectedly succeeded' then raise; elsif sqlerrm<>'Invalid booking details' then raise exception 'Unexpected reason validation error: %',sqlerrm; end if; end;
end
$service_booking_test$;

reset role;
do $service_booking_storage$
begin
  if not exists(select 1 from appointments a join services s on s.id=a.service_id where a.lead_id=current_setting('qa.booking_reason_lead')::uuid and a.notes='Douleur légère lors de la mastication depuis trois jours' and s.app_id=current_setting('qa.booking_reason_service')) then raise exception 'Booking reason or service is missing from the agenda'; end if;
end
$service_booking_storage$;

rollback;
