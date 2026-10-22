-- First-run settings, live catalogue sync, availability and staff denial.
begin;

select set_config('qa.admin_id',(select id::text from staff_profiles where role='administrator' and active order by created_at limit 1),true);
select set_config('qa.clinic_id',(select clinic_id::text from staff_profiles where id=current_setting('qa.admin_id')::uuid),true);
select set_config('request.jwt.claim.sub',current_setting('qa.admin_id'),true);
set local role authenticated;

insert into app_records(clinic_id,collection,id,data) values
  (current_setting('qa.clinic_id')::uuid,'_clinic','settings',jsonb_build_object('id','settings','name','QA Clinic Setup','address','12 Test Street','phone','+212 600000000','currency','EUR','timezone','Europe/Paris'))
on conflict(clinic_id,collection,id) do update set data=excluded.data;

reset role;
do $clinic$
begin
  if not exists(select 1 from clinics where id=current_setting('qa.clinic_id')::uuid and name='QA Clinic Setup' and address='12 Test Street'
    and phone='+212 600000000' and currency='EUR' and timezone='Europe/Paris') then
    raise exception 'Clinic settings did not reach the public booking source';
  end if;
end
$clinic$;

set local role authenticated;
insert into app_records(clinic_id,collection,id,data) values
  (current_setting('qa.clinic_id')::uuid,'doctors','qa-setup-doctor',jsonb_build_object('id','qa-setup-doctor','name','Dr Setup','specialty','Dentiste','availabilityDays',jsonb_build_array(1),'startTime','10:00','endTime','12:00','active',true)),
  (current_setting('qa.clinic_id')::uuid,'treatments','qa-setup-service',jsonb_build_object('id','qa-setup-service','name','Test Service','category','Diagnostic','price',175,'duration',30,'active',true,'bookingEligible',true));

reset role;
do $catalogue$
declare doctor_id uuid; service_id uuid; monday date;
begin
  select id into doctor_id from practitioners where clinic_id=current_setting('qa.clinic_id')::uuid and app_id='qa-setup-doctor' and active;
  select id into service_id from services where clinic_id=current_setting('qa.clinic_id')::uuid and app_id='qa-setup-service' and active and booking_eligible and standard_price=175;
  if doctor_id is null or service_id is null then raise exception 'Catalogue write did not reach normalized tables'; end if;
  monday:=current_date+((8-extract(isodow from current_date)::integer)%7)+7;
  if not practitioner_on_duty(doctor_id,(monday+time '10:00') at time zone 'Europe/Paris',(monday+time '10:30') at time zone 'Europe/Paris')
    or practitioner_on_duty(doctor_id,(monday+time '09:00') at time zone 'Europe/Paris',(monday+time '09:30') at time zone 'Europe/Paris')
    or practitioner_on_duty(doctor_id,(monday+1+time '10:00') at time zone 'Europe/Paris',(monday+1+time '10:30') at time zone 'Europe/Paris')
  then raise exception 'Practitioner working hours were not enforced'; end if;
end
$catalogue$;

set local role authenticated;
insert into app_records(clinic_id,collection,id,data) values
  (current_setting('qa.clinic_id')::uuid,'bookingLinks','qa-setup-link',jsonb_build_object('id','qa-setup-link','slug','qa-setup-link','title','QA Booking','treatmentId','qa-setup-service','serviceIds',jsonb_build_array('qa-setup-service'),'doctorId','qa-setup-doctor','roomId','chair-1','published',true,'duration',30));

reset role;
do $booking$
declare page jsonb:=public_booking_page('qa-setup-link');
begin
  if page->>'clinicName'<>'QA Clinic Setup' or page->>'address'<>'12 Test Street' or page->>'phone'<>'+212 600000000'
    or page->>'timezone'<>'Europe/Paris' or public_booking_currency('qa-setup-link')<>'EUR'
    or jsonb_array_length(page->'services')<>1 then raise exception 'Public booking identity or service list is stale'; end if;
end
$booking$;

set local role authenticated;
update app_records set data=jsonb_set(data,'{bookingEligible}','false'::jsonb,true)
where clinic_id=current_setting('qa.clinic_id')::uuid and collection='treatments' and id='qa-setup-service';

reset role;
do $inactive$
begin
  if exists(select 1 from services where clinic_id=current_setting('qa.clinic_id')::uuid and app_id='qa-setup-service' and booking_eligible) then
    raise exception 'Ineligible service remained bookable';
  end if;
  if jsonb_array_length(public_booking_page('qa-setup-link')->'services')<>0 then
    raise exception 'Public page exposed an ineligible service';
  end if;
end
$inactive$;

-- Service management alone must not allow changing clinic identity.
reset role;
select set_config('qa.assistant_id',(select id::text from staff_profiles where clinic_id=current_setting('qa.clinic_id')::uuid and role='assistant' and active limit 1),true);
do $assistant_exists$
begin
  if current_setting('qa.assistant_id',true) is null or current_setting('qa.assistant_id')='' then raise exception 'Fixture assistant required'; end if;
end
$assistant_exists$;
set local role authenticated;
select set_staff_membership(current_setting('qa.assistant_id')::uuid,'assistant',false);
reset role;
do $deactivated$
begin
  if exists(select 1 from staff_profiles where id=current_setting('qa.assistant_id')::uuid and active)
    or not exists(select 1 from app_records where clinic_id=current_setting('qa.clinic_id')::uuid and collection='auditEvents'
      and data->>'action'='staff_membership_changed' and data->>'entityId'=current_setting('qa.assistant_id'))
  then raise exception 'Staff deactivation or audit event missing'; end if;
end
$deactivated$;
set local role authenticated;
select set_staff_membership(current_setting('qa.assistant_id')::uuid,'assistant',true);
reset role;
select set_config('qa.practitioner_id',(select id::text from staff_profiles where clinic_id=current_setting('qa.clinic_id')::uuid and role='practitioner' and active limit 1),true);
set local role authenticated;
select set_staff_membership(current_setting('qa.practitioner_id')::uuid,'assistant',true);
reset role;
do $role_change$
begin
  if not exists(select 1 from staff_profiles where id=current_setting('qa.practitioner_id')::uuid and role='assistant' and active)
    or exists(select 1 from practitioners where staff_id=current_setting('qa.practitioner_id')::uuid and active)
  then raise exception 'Practitioner role downgrade was not enforced'; end if;
end
$role_change$;
set local role authenticated;
select set_staff_membership(current_setting('qa.practitioner_id')::uuid,'practitioner',true);
reset role;
do $role_restore$
begin
  if not exists(select 1 from practitioners where staff_id=current_setting('qa.practitioner_id')::uuid and active)
  then raise exception 'Practitioner identity was not restored'; end if;
end
$role_restore$;
insert into role_permissions(clinic_id,role,permission,scope) values(current_setting('qa.clinic_id')::uuid,'assistant','services.manage','clinic') on conflict do nothing;
select set_config('request.jwt.claim.sub',current_setting('qa.assistant_id'),true);
set local role authenticated;
do $denied$
begin
  if app_record_allowed('_clinic','update','{}'::jsonb) then raise exception 'Service manager can edit clinic identity'; end if;
  begin
    perform set_staff_membership(current_setting('qa.admin_id')::uuid,'assistant',false);
    raise exception 'Assistant changed staff membership';
  exception when others then
    if sqlerrm='Assistant changed staff membership' then raise; end if;
  end;
end
$denied$;

rollback;
