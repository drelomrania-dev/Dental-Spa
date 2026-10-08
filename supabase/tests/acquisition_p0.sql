-- Run against a development database with an active administrator profile.
-- Every fixture is rolled back.
begin;

select set_config(
  'request.jwt.claim.sub',
  (select id::text from staff_profiles where active=true and role='administrator' order by created_at limit 1),
  true
);
set local role authenticated;

do $test$
declare
  clinic uuid:=current_clinic_id();
  test_lead_id uuid;
  invitation jsonb;
  token text;
  intake_page jsonb;
  submission jsonb;
  converted jsonb;
begin
  if clinic is null then raise exception 'Missing administrator clinic context'; end if;

  insert into leads(clinic_id,first_name,last_name,phone,email,source,concern)
  values(clinic,'Test','Rollback','0600000000','qa-acquisition@example.invalid','Direct','Validation transactionnelle')
  returning id into test_lead_id;

  insert into lead_interactions(clinic_id,lead_id,channel,direction,summary)
  values(clinic,test_lead_id,'Note','Interne','Interaction transactionnelle');
  insert into follow_up_tasks(clinic_id,lead_id,title,due_at)
  values(clinic,test_lead_id,'Relance transactionnelle',now()+interval '1 day');
  insert into lead_quotes(clinic_id,lead_id,title,amount,status)
  values(clinic,test_lead_id,'Devis transactionnel',1250,'Brouillon');

  invitation:=create_consultation_invitation(test_lead_id,'Lien','consultation',1);
  token:=invitation->>'token';
  intake_page:=public_acquisition_intake_page(token);
  if intake_page->>'firstName'<>'Test' then raise exception 'Intake page mismatch'; end if;
  if jsonb_array_length(intake_page->'photoViews')<3 then raise exception 'Photo protocol missing'; end if;

  submission:=public_submit_lead_intake(token,jsonb_build_object(
    'firstName','Test','lastName','Rollback','phone','0600000000','email','qa-acquisition@example.invalid',
    'concern','Validation transactionnelle','urgency','Normale','availability','Matin',
    'previousCare','','photoIds',jsonb_build_array(),'consent',true
  ));
  if coalesce((submission->>'success')::boolean,false)=false then raise exception 'Intake submission failed'; end if;
  if not exists(select 1 from intake_sessions where lead_id=test_lead_id and status='Completee') then raise exception 'Completed session missing'; end if;
  if not exists(select 1 from consent_records where lead_id=test_lead_id and accepted=true) then raise exception 'Consent evidence missing'; end if;

  converted:=convert_lead_to_patient(test_lead_id);
  if converted->>'patientId' is null then raise exception 'Patient conversion failed'; end if;
  if not exists(select 1 from patients where clinic_id=clinic and app_id=converted->>'patientId') then raise exception 'Converted patient missing'; end if;
end
$test$;

rollback;
