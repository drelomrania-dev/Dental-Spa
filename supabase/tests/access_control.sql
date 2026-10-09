-- Run against a development database with an active administrator profile.
-- Exercises the legacy-record guards under administrator and assistant roles.
-- Every fixture and temporary role change is rolled back.
begin;

select set_config(
  'request.jwt.claim.sub',
  (select id::text from staff_profiles where active=true and role='administrator' order by created_at limit 1),
  true
);
set local role authenticated;

do $admin_test$
declare
  clinic uuid:=current_clinic_id();
begin
  if clinic is null then raise exception 'Missing administrator clinic context'; end if;

  insert into app_records(clinic_id,collection,id,data)
  values(clinic,'appointments','qa-access-admin',jsonb_build_object('status','planned'));

  update app_records
  set data=jsonb_set(data,'{status}','"confirmed"'::jsonb),updated_at=now()
  where clinic_id=clinic and collection='appointments' and id='qa-access-admin';

  if not exists(
    select 1 from app_records
    where clinic_id=clinic and collection='appointments' and id='qa-access-admin' and data->>'status'='confirmed'
  ) then raise exception 'Administrator update was not visible'; end if;

  delete from app_records
  where clinic_id=clinic and collection='appointments' and id='qa-access-admin';
end
$admin_test$;

reset role;
update staff_profiles
set role='assistant'
where id=current_setting('request.jwt.claim.sub',true)::uuid;
set local role authenticated;

do $assistant_test$
declare
  clinic uuid:=current_clinic_id();
  uid text:=auth.uid()::text;
begin
  if current_staff_role()<>'assistant' then raise exception 'Temporary assistant context was not applied'; end if;
  if not app_record_allowed('appointments','select','{}'::jsonb) then raise exception 'Assistant cannot view appointments'; end if;
  if app_record_allowed('auditEvents','select','{}'::jsonb) then raise exception 'Assistant can unexpectedly view audit events'; end if;

  insert into app_records(clinic_id,collection,id,data)
  values(clinic,'appointments','qa-access-assistant',jsonb_build_object('status','planned'));

  update app_records
  set data=jsonb_set(data,'{status}','"confirmed"'::jsonb),updated_at=now()
  where clinic_id=clinic and collection='appointments' and id='qa-access-assistant';

  insert into app_records(clinic_id,collection,id,data)
  values(clinic,'payments','qa-access-payment',jsonb_build_object('collectedBy',uid,'amount',100));

  if not exists(
    select 1 from app_records
    where clinic_id=clinic and collection='payments' and id='qa-access-payment'
  ) then raise exception 'Assistant cannot view own payment'; end if;

  begin
    insert into app_records(clinic_id,collection,id,data)
    values(clinic,'auditEvents','qa-access-audit','{}'::jsonb);
    raise exception 'Assistant audit insert unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;

  delete from app_records
  where clinic_id=clinic and collection='appointments' and id='qa-access-assistant';
  if not exists(
    select 1 from app_records where clinic_id=clinic and collection='appointments' and id='qa-access-assistant'
  ) then raise exception 'Assistant delete unexpectedly succeeded'; end if;
end
$assistant_test$;

rollback;
