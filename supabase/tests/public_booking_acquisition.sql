-- Public booking must populate the patient agenda and acquisition pipeline exactly once.
begin;

select set_config('request.jwt.claim.sub',(select id::text from staff_profiles where active=true and role='administrator' order by created_at limit 1),true);
set local role authenticated;

do $booking_bridge_test$
declare clinic uuid:=current_clinic_id(); booking_date date:=current_date+35; second_date date; slots jsonb; second_slots jsonb; first_booking jsonb; second_booking jsonb; lead_uuid uuid;
begin
  while extract(isodow from booking_date)=7 loop booking_date:=booking_date+1; end loop;
  slots:=public_available_slots('consultation',booking_date);
  if jsonb_array_length(slots)=0 then raise exception 'No public slot for bridge test'; end if;

  first_booking:=public_create_booking('consultation',booking_date,slots->>0,'Test','Pipeline','0600000004','qa-pipeline@example.invalid');
  if first_booking->>'leadId' is null or first_booking->>'leadId'='' then raise exception 'Booking is not linked to a lead'; end if;
  lead_uuid:=(first_booking->>'leadId')::uuid;
  if not exists(select 1 from leads where id=lead_uuid and clinic_id=clinic and status='Rendez-vous' and source='Site web') then raise exception 'Lead was not added to the booking stage'; end if;
  if not (appointments_snapshot() @> jsonb_build_array(jsonb_build_object('reference',first_booking->>'reference'))) then raise exception 'Booking is missing from agenda snapshot'; end if;
  if not exists(select 1 from lead_events where lead_id=lead_uuid and event_type='appointment_created') then raise exception 'Lead booking event is missing'; end if;
  if not exists(select 1 from lead_interactions where lead_id=lead_uuid and summary like 'Rendez-vous réservé en ligne%') then raise exception 'Lead booking history is missing'; end if;

  second_date:=booking_date+1; while extract(isodow from second_date)=7 loop second_date:=second_date+1; end loop;
  second_slots:=public_available_slots('consultation',second_date);
  if jsonb_array_length(second_slots)=0 then raise exception 'No second public slot for deduplication test'; end if;
  second_booking:=public_create_booking('consultation',second_date,second_slots->>0,'Test','Pipeline','06 00 00 00 04','QA-PIPELINE@example.invalid');
  if second_booking->>'leadId'<>lead_uuid::text then raise exception 'Repeated contact created another lead'; end if;
  if (select count(*) from leads where clinic_id=clinic and (phone in ('0600000004','06 00 00 00 04') or lower(email)='qa-pipeline@example.invalid'))<>1 then raise exception 'Lead deduplication failed'; end if;
  if (select count(*) from patients where clinic_id=clinic and (phone in ('0600000004','06 00 00 00 04') or lower(email)='qa-pipeline@example.invalid'))<>1 then raise exception 'Patient deduplication failed'; end if;
end
$booking_bridge_test$;

reset role;
do $booking_storage_test$
declare lead_uuid uuid;
begin
  select id into lead_uuid from leads where lower(email)='qa-pipeline@example.invalid' limit 1;
  if not exists(select 1 from appointments a join patients p on p.id=a.patient_id where p.phone='0600000004' and a.lead_id=lead_uuid) then raise exception 'Patient appointment is missing from normalized agenda storage'; end if;
end
$booking_storage_test$;

rollback;
