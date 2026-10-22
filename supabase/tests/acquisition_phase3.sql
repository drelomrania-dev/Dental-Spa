-- Transactional Phase 3 CRM checks. Requires the synthetic local administrator.
begin;
select set_config('request.jwt.claim.sub',(select id::text from staff_profiles where active and role='administrator' order by created_at limit 1),true);
set local role authenticated;

do $test$
declare clinic uuid:=current_clinic_id(); administrator_id uuid:=auth.uid(); assistant_id uuid; v_lead_id uuid; v_quote_id uuid; expired_quote_id uuid; invitation jsonb; token text; converted jsonb; again jsonb; duplicate jsonb; existing_patient uuid; event_count integer;
begin
  if clinic is null then raise exception 'Synthetic administrator required'; end if;
  insert into leads(clinic_id,first_name,last_name,phone,email,source)
  values(clinic,'Phase','Three','0611112233','phase3@example.invalid','Instagram') returning id into v_lead_id;
  duplicate:=create_lead_checked(jsonb_build_object('first_name','Repeated','phone','06 11 11 22 33','source','Google'));
  if duplicate->>'deduplicated'<>'true' or duplicate->'lead'->>'id'<>v_lead_id::text then raise exception 'Duplicate contact was not routed to existing lead'; end if;
  begin
    insert into leads(clinic_id,first_name,phone) values(clinic,'Direct duplicate','0611112233');
    raise exception 'Direct duplicate insert accepted';
  exception when others then
    if sqlerrm='Direct duplicate insert accepted' then raise; end if;
  end;
  update leads set status='Perdu',owner_id=auth.uid() where id=v_lead_id;
  update leads set status='Contacte' where id=v_lead_id;
  select count(*) into event_count from lead_events where lead_id=v_lead_id and event_type='lead.stage_changed';
  if event_count<>2 then raise exception 'Stage history missing'; end if;

  insert into lead_interactions(clinic_id,lead_id,channel,direction,summary)
  values(clinic,v_lead_id,'Telephone','Sortant','Recovery call');
  if (select status from leads where id=v_lead_id)<>'Contacte' then raise exception 'Interaction rewrote recovered stage'; end if;

  insert into lead_quotes(clinic_id,lead_id,title,amount,currency,status,valid_until)
  values(clinic,v_lead_id,'Commercial estimate',1250,(select currency from clinics where id=clinic),'Brouillon',current_date+7) returning id into v_quote_id;
  begin
    insert into lead_quotes(clinic_id,lead_id,title,amount,currency,status)
    values(clinic,v_lead_id,'Wrong currency',100,(select case when currency='EUR' then 'MAD' else 'EUR' end from clinics where id=clinic),'Brouillon');
    raise exception 'Cross-currency quote accepted';
  exception when others then
    if sqlerrm='Cross-currency quote accepted' then raise; end if;
  end;
  begin
    update lead_quotes set status='Accepte' where id=v_quote_id;
    raise exception 'Draft acceptance should fail';
  exception when others then
    if sqlerrm='Draft acceptance should fail' then raise; end if;
  end;
  update lead_quotes set status='Envoye' where id=v_quote_id;
  update lead_quotes set status='Accepte' where id=v_quote_id;
  if (select count(*) from lead_quote_events where quote_id=v_quote_id)<>3 then raise exception 'Quote status history missing'; end if;
  begin
    update lead_quotes set amount=100 where id=v_quote_id;
    raise exception 'Quote terms changed';
  exception when others then
    if sqlerrm='Quote terms changed' then raise; end if;
  end;
  insert into lead_quotes(clinic_id,lead_id,title,amount,currency,status,valid_until)
  values(clinic,v_lead_id,'Expired estimate',900,(select currency from clinics where id=clinic),'Envoye',current_date-1) returning id into expired_quote_id;
  if expire_lead_quotes(v_lead_id)<>1 or (select status from lead_quotes where id=expired_quote_id)<>'Expire' then raise exception 'Quote expiry failed'; end if;

  invitation:=create_consultation_invitation(v_lead_id,'Lien','consultation',1);
  token:=invitation->>'token';
  if public_acquisition_intake_page(token) is null then raise exception 'Valid token rejected'; end if;
  perform revoke_consultation_invitation((invitation->>'id')::uuid);
  if public_acquisition_intake_page(token) is not null then raise exception 'Revoked token accepted'; end if;
  begin
    perform public_submit_lead_intake(token,jsonb_build_object('consent',true));
    raise exception 'Revoked submission accepted';
  exception when others then
    if sqlerrm='Revoked submission accepted' then raise; end if;
  end;

  converted:=convert_lead_to_patient(v_lead_id);
  again:=convert_lead_to_patient(v_lead_id);
  if converted->>'databaseId'<>again->>'databaseId' then raise exception 'Conversion duplicated patient'; end if;
  select id into existing_patient from patients where id=(converted->>'databaseId')::uuid and clinic_id=clinic;
  if existing_patient is null then raise exception 'Patient link missing'; end if;
  if (select count(*) from leads where id=v_lead_id and converted_patient_id=existing_patient)<>1 then raise exception 'Lead link missing'; end if;

  select id into assistant_id from staff_profiles where clinic_id=clinic and role='assistant' and active order by created_at limit 1;
  if assistant_id is null then raise exception 'Synthetic assistant required'; end if;
  delete from role_permissions where clinic_id=clinic and role='assistant' and permission in ('acquisition.manage','acquisition.view');
  perform set_config('request.jwt.claim.sub',assistant_id::text,true);
  if has_permission('acquisition.manage') or has_permission('acquisition.view') then raise exception 'Acquisition grant revocation ineffective'; end if;
  if exists(select 1 from leads where id=v_lead_id) then raise exception 'CRM read boundary failed'; end if;
  begin
    perform create_lead_checked(jsonb_build_object('first_name','Denied','phone','0699999999'));
    raise exception 'CRM write boundary failed';
  exception when others then
    if sqlerrm='CRM write boundary failed' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub',administrator_id::text,true);
end $test$;

set local role service_role;
do $media$
declare clinic uuid; new_clinic_id uuid; v_lead_id uuid; invitation_id uuid; session_id uuid; first_view_id uuid; second_view_id uuid; media_id uuid;
begin
  insert into clinics(name,currency,timezone) values('QA Phase 3 Photo Clinic','MAD','Africa/Casablanca') returning id into new_clinic_id;
  if (select count(*) from photo_view_definitions where clinic_id=new_clinic_id)<>3 then raise exception 'New clinic photo protocol missing'; end if;
  select clinic_id into clinic from staff_profiles where active and role='administrator' order by created_at limit 1;
  insert into leads(clinic_id,first_name,phone) values(clinic,'Media consent test','0698765432') returning id into v_lead_id;
  insert into consultation_invitations(clinic_id,lead_id,token_hash,status,expires_at)
  values(clinic,v_lead_id,extensions.digest(gen_random_uuid()::text,'sha256'),'Envoyee',now()+interval '1 day') returning id into invitation_id;
  insert into intake_sessions(clinic_id,lead_id,invitation_id,status)
  values(clinic,v_lead_id,invitation_id,'En cours') returning id into session_id;
  select v.id into first_view_id from photo_view_definitions v join capture_protocols p on p.id=v.protocol_id
  where v.clinic_id=clinic and p.active order by v.sort_order limit 1;
  select v.id into second_view_id from photo_view_definitions v join capture_protocols p on p.id=v.protocol_id
  where v.clinic_id=clinic and p.active and v.id<>first_view_id order by v.sort_order limit 1;
  if first_view_id is null or second_view_id is null then raise exception 'Synthetic photo protocol required'; end if;
  begin
    insert into lead_media(clinic_id,lead_id,session_id,view_definition_id,storage_path,mime_type,size_bytes)
    values(clinic,v_lead_id,session_id,first_view_id,'qa/without-consent.png','image/png',10);
    raise exception 'Media without consent accepted';
  exception when others then
    if sqlerrm<>'Active photo consent required' then raise; end if;
  end;
  insert into consent_records(clinic_id,lead_id,session_id,consent_type,accepted)
  values(clinic,v_lead_id,session_id,'guided_photos',true);
  insert into lead_media(clinic_id,lead_id,session_id,view_definition_id,storage_path,mime_type,size_bytes)
  values(clinic,v_lead_id,session_id,first_view_id,'qa/consented.png','image/png',10) returning id into media_id;
  begin
    update lead_media set storage_path='qa/changed.png' where id=media_id;
    raise exception 'Photo metadata changed';
  exception when others then
    if sqlerrm<>'Photo metadata is immutable' then raise; end if;
  end;
  insert into consent_records(clinic_id,lead_id,session_id,consent_type,accepted)
  values(clinic,v_lead_id,session_id,'guided_photos',false);
  begin
    insert into lead_media(clinic_id,lead_id,session_id,view_definition_id,storage_path,mime_type,size_bytes)
    values(clinic,v_lead_id,session_id,second_view_id,'qa/after-withdrawal.png','image/png',10);
    raise exception 'Media after withdrawal accepted';
  exception when others then
    if sqlerrm<>'Active photo consent required' then raise; end if;
  end;
  update intake_sessions set status='Completee' where id=session_id;
  begin
    insert into consent_records(clinic_id,lead_id,session_id,consent_type,accepted)
    values(clinic,v_lead_id,session_id,'guided_photos',true);
    raise exception 'Completed intake accepted photo consent';
  exception when others then
    if sqlerrm<>'Completed intake cannot add photo consent' then raise; end if;
  end;
  begin
    insert into lead_media(clinic_id,lead_id,session_id,view_definition_id,storage_path,mime_type,size_bytes)
    values(clinic,v_lead_id,session_id,second_view_id,'qa/after-completion.png','image/png',10);
    raise exception 'Completed intake accepted a photo';
  exception when others then
    if sqlerrm<>'Completed intake cannot add photos' then raise; end if;
  end;
end $media$;

rollback;
