begin;

select set_config('qa.security_admin_id',(select id::text from staff_profiles where active=true and role='administrator' order by created_at limit 1),true);
select set_config('qa.security_practitioner_id',gen_random_uuid()::text,true);
insert into auth.users(id,aud,role,email,created_at,updated_at) values(current_setting('qa.security_practitioner_id')::uuid,'authenticated','authenticated','qa-security-practitioner@example.invalid',now(),now());
select set_config('request.jwt.claim.sub',current_setting('qa.security_admin_id'),true);
set local role authenticated;

do $slug_test$
declare clinic uuid:=current_clinic_id(); normalized text;
begin
  insert into app_records(clinic_id,collection,id,data) values(clinic,'bookingLinks','qa-security-booking-1',jsonb_build_object('slug',' QA-Security-Slug ','published',true));
  select data->>'slug' into normalized from app_records where clinic_id=clinic and collection='bookingLinks' and id='qa-security-booking-1';
  if normalized<>'qa-security-slug' then raise exception 'Published booking slug was not normalized'; end if;
  begin
    insert into app_records(clinic_id,collection,id,data) values(clinic,'bookingLinks','qa-security-booking-2',jsonb_build_object('slug','qa-security-slug','published',true));
    raise exception 'Duplicate published booking slug unexpectedly succeeded';
  exception when unique_violation then null; end;
end
$slug_test$;

select set_config('qa.security_practitioner_app',(select id from app_records where clinic_id=current_clinic_id() and collection='doctors' order by id limit 1),true);
insert into app_records(clinic_id,collection,id,data) values
  (current_clinic_id(),'appointments','qa-security-legacy-appointment',jsonb_build_object('doctorId',current_setting('qa.security_practitioner_app'))),
  (current_clinic_id(),'visits','qa-security-legacy-visit',jsonb_build_object('doctorId',current_setting('qa.security_practitioner_app'))),
  (current_clinic_id(),'treatmentPlans','qa-security-legacy-plan',jsonb_build_object('doctorId',current_setting('qa.security_practitioner_app')));

select set_config('request.jwt.claim.sub',current_setting('qa.security_practitioner_id'),true);
set local role authenticated;
do $legacy_denial_test$
begin
  if app_record_allowed('appointments','select','{}'::jsonb) then raise exception 'Practitioner legacy appointment access was allowed'; end if;
  if app_record_allowed('visits','select','{}'::jsonb) then raise exception 'Practitioner legacy visit access was allowed'; end if;
  if app_record_allowed('treatmentPlans','select','{}'::jsonb) then raise exception 'Practitioner legacy treatment-plan access was allowed'; end if;
end
$legacy_denial_test$;

rollback;
