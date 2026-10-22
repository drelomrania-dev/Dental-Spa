-- Phase 3: enforce acquisition permissions and preserve commercial history.
-- Migration 008 seeded only clinics that already existed. New clinics need the same guided views.
create or replace function acquisition_seed_photo_protocol()
returns trigger language plpgsql security definer set search_path=public as $$
declare protocol_id uuid;
begin
  insert into capture_protocols(clinic_id,name,description,active)
  values(new.id,'Pré-consultation sourire','Trois vues simples pour préparer l’échange avec le praticien.',true)
  returning id into protocol_id;
  insert into photo_view_definitions(protocol_id,clinic_id,code,label,instructions,sort_order,required)
  select protocol_id,new.id,v.code,v.label,v.instructions,v.sort_order,false from (values
    ('smile-front','Sourire de face','Tenez le téléphone à hauteur de bouche, avec une lumière naturelle.',1),
    ('teeth-front','Dents de face','Montrez les dents de face sans zoom numérique.',2),
    ('concern-close','Zone concernée','Cadrez uniquement la zone qui motive votre demande.',3)
  ) as v(code,label,instructions,sort_order);
  return new;
end $$;
drop trigger if exists acquisition_seed_photo_protocol_trigger on clinics;
create trigger acquisition_seed_photo_protocol_trigger after insert on clinics for each row execute function acquisition_seed_photo_protocol();

with missing as (
  insert into capture_protocols(clinic_id,name,description,active)
  select c.id,'Pré-consultation sourire','Trois vues simples pour préparer l’échange avec le praticien.',true
  from clinics c where not exists(select 1 from capture_protocols p where p.clinic_id=c.id and p.name='Pré-consultation sourire')
  returning id,clinic_id
), protocols as (
  select id,clinic_id from missing
  union all
  select id,clinic_id from capture_protocols where name='Pré-consultation sourire'
)
insert into photo_view_definitions(protocol_id,clinic_id,code,label,instructions,sort_order,required)
select p.id,p.clinic_id,v.code,v.label,v.instructions,v.sort_order,false from protocols p cross join (values
  ('smile-front','Sourire de face','Tenez le téléphone à hauteur de bouche, avec une lumière naturelle.',1),
  ('teeth-front','Dents de face','Montrez les dents de face sans zoom numérique.',2),
  ('concern-close','Zone concernée','Cadrez uniquement la zone qui motive votre demande.',3)
) as v(code,label,instructions,sort_order)
on conflict(protocol_id,code) do nothing;

create or replace function acquisition_lock_contact(p_clinic uuid,p_phone text,p_email text)
returns void language plpgsql security definer set search_path=public as $$
declare contact_key text;
begin
  for contact_key in
    select value from (values
      (case when p_phone<>'' then 'phone:'||p_phone end),
      (case when p_email<>'' then 'email:'||p_email end)
    ) as keys(value) where value is not null order by value
  loop
    perform pg_advisory_xact_lock(hashtextextended(p_clinic::text||':'||contact_key,0));
  end loop;
end $$;
revoke all on function acquisition_lock_contact(uuid,text,text) from public,anon,authenticated;

create or replace function acquisition_lead_guard()
returns trigger language plpgsql security definer set search_path=public as $$
declare normalized_phone text; normalized_email text; contact_changed boolean:=false; matching_patient boolean:=false;
begin
  if length(trim(new.first_name)) not between 1 and 80 or length(coalesce(new.phone,''))>30 or length(coalesce(new.email,''))>160 then
    raise exception 'Invalid lead contact';
  end if;
  if new.owner_id is not null and not exists (
    select 1 from staff_profiles s where s.id=new.owner_id and s.clinic_id=new.clinic_id and s.active
  ) then raise exception 'Owner must be active in this clinic'; end if;
  if new.converted_patient_id is not null and not exists(select 1 from patients p where p.id=new.converted_patient_id and p.clinic_id=new.clinic_id) then raise exception 'Converted patient mismatch'; end if;
  normalized_phone:=regexp_replace(coalesce(new.phone,''),'[^0-9]','','g'); normalized_email:=lower(trim(coalesce(new.email,'')));
  if new.converted_patient_id is not null then
    select exists(select 1 from patients p where p.id=new.converted_patient_id and p.clinic_id=new.clinic_id and (
      (normalized_phone<>'' and regexp_replace(coalesce(p.phone,''),'[^0-9]','','g')=normalized_phone) or
      (normalized_email<>'' and lower(coalesce(p.email,''))=normalized_email)
    )) into matching_patient;
  end if;
  if tg_op='INSERT' then
    contact_changed:=true;
    if new.status='Converti' and coalesce(current_setting('acquisition.converting',true),'')<>'yes' then raise exception 'Use conversion workflow'; end if;
  end if;
  if tg_op='UPDATE' then
    contact_changed:=new.phone is distinct from old.phone or new.email is distinct from old.email;
    if new.clinic_id<>old.clinic_id then raise exception 'Lead cannot change clinic'; end if;
    if new.created_at<>old.created_at or new.created_by is distinct from old.created_by or new.utm is distinct from old.utm then raise exception 'Lead origin is immutable'; end if;
    if new.converted_patient_id is distinct from old.converted_patient_id
      and coalesce(current_setting('acquisition.converting',true),'')<>'yes'
      and not (old.converted_patient_id is null and new.status='Rendez-vous' and matching_patient)
    then raise exception 'Use conversion workflow'; end if;
    if new.status='Converti' and old.status<>'Converti' and coalesce(current_setting('acquisition.converting',true),'')<>'yes' then raise exception 'Use conversion workflow'; end if;
    if old.status='Converti' and new.status<>'Converti' then raise exception 'Converted lead cannot return to pipeline'; end if;
    if new.status='Converti' and new.converted_patient_id is null then raise exception 'Conversion requires a patient'; end if;
  end if;
  if contact_changed and (normalized_phone<>'' or normalized_email<>'') then
    perform acquisition_lock_contact(new.clinic_id,normalized_phone,normalized_email);
    if exists(select 1 from leads l where l.clinic_id=new.clinic_id and l.id<>new.id and (
      (normalized_phone<>'' and regexp_replace(coalesce(l.phone,''),'[^0-9]','','g')=normalized_phone) or
      (normalized_email<>'' and lower(coalesce(l.email,''))=normalized_email)
    )) then raise exception 'Lead contact already exists'; end if;
  end if;
  return new;
end $$;
drop trigger if exists acquisition_lead_guard_trigger on leads;
create trigger acquisition_lead_guard_trigger before insert or update on leads for each row execute function acquisition_lead_guard();

create or replace function acquisition_lead_audit()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_op='INSERT' then
    insert into lead_events(clinic_id,lead_id,event_type,metadata,actor_id)
    values(new.clinic_id,new.id,'lead.created',jsonb_build_object('source',new.source,'status',new.status),auth.uid());
  else
    if old.status is distinct from new.status then
      insert into lead_events(clinic_id,lead_id,event_type,metadata,actor_id)
      values(new.clinic_id,new.id,'lead.stage_changed',jsonb_build_object('from',old.status,'to',new.status),auth.uid());
    end if;
    if old.owner_id is distinct from new.owner_id then
      insert into lead_events(clinic_id,lead_id,event_type,metadata,actor_id)
      values(new.clinic_id,new.id,'lead.owner_changed',jsonb_build_object('from',old.owner_id,'to',new.owner_id),auth.uid());
    end if;
    if old.source is distinct from new.source then
      insert into lead_events(clinic_id,lead_id,event_type,metadata,actor_id)
      values(new.clinic_id,new.id,'lead.source_changed',jsonb_build_object('from',old.source,'to',new.source),auth.uid());
    end if;
    if old.next_follow_up_at is distinct from new.next_follow_up_at then
      insert into lead_events(clinic_id,lead_id,event_type,metadata,actor_id)
      values(new.clinic_id,new.id,'lead.next_action_changed',jsonb_build_object('from',old.next_follow_up_at,'to',new.next_follow_up_at),auth.uid());
    end if;
  end if;
  return null;
end $$;
drop trigger if exists acquisition_lead_audit_trigger on leads;
create trigger acquisition_lead_audit_trigger after insert or update on leads for each row execute function acquisition_lead_audit();

create or replace function create_lead_checked(p_lead jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); existing leads%rowtype; created leads%rowtype; normalized_phone text; normalized_email text; owner uuid;
begin
  if clinic is null or not has_permission('acquisition.manage') then raise exception 'Acquisition management denied'; end if;
  normalized_phone:=regexp_replace(coalesce(p_lead->>'phone',''),'[^0-9]','','g');
  normalized_email:=lower(trim(coalesce(p_lead->>'email','')));
  if normalized_phone='' and normalized_email='' then raise exception 'Phone or email required'; end if;
  if normalized_email<>'' and normalized_email!~*'^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception 'Invalid email'; end if;
  owner:=nullif(p_lead->>'owner_id','')::uuid;
  perform acquisition_lock_contact(clinic,normalized_phone,normalized_email);
  select * into existing from leads where clinic_id=clinic and (
    (normalized_phone<>'' and regexp_replace(coalesce(phone,''),'[^0-9]','','g')=normalized_phone) or
    (normalized_email<>'' and lower(coalesce(email,''))=normalized_email)
  ) order by created_at limit 1;
  if existing.id is not null then
    insert into lead_events(clinic_id,lead_id,event_type,metadata,actor_id)
    values(clinic,existing.id,'lead.duplicate_contact',jsonb_build_object('attemptedSource',p_lead->>'source'),auth.uid());
    return jsonb_build_object('lead',to_jsonb(existing),'deduplicated',true);
  end if;
  insert into leads(clinic_id,first_name,last_name,phone,email,source,status,priority,owner_id,concern,notes,next_follow_up_at)
  values(clinic,trim(coalesce(p_lead->>'first_name','')),trim(coalesce(p_lead->>'last_name','')),
    nullif(trim(coalesce(p_lead->>'phone','')),''),nullif(trim(coalesce(p_lead->>'email','')),''),
    coalesce(nullif(p_lead->>'source',''),'Direct'),coalesce(nullif(p_lead->>'status',''),'Nouveau'),
    coalesce(nullif(p_lead->>'priority',''),'Normale'),owner,nullif(trim(coalesce(p_lead->>'concern','')),''),
    nullif(trim(coalesce(p_lead->>'notes','')),''),nullif(p_lead->>'next_follow_up_at','')::timestamptz) returning * into created;
  return jsonb_build_object('lead',to_jsonb(created),'deduplicated',false);
end $$;

create or replace function acquisition_interaction_after_insert()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  update leads set last_contact_at=new.created_at,status=case when status='Nouveau' then 'Contacte' else status end,updated_at=now()
  where id=new.lead_id and clinic_id=new.clinic_id;
  return null;
end $$;
drop trigger if exists acquisition_interaction_after_insert_trigger on lead_interactions;
create trigger acquisition_interaction_after_insert_trigger after insert on lead_interactions for each row execute function acquisition_interaction_after_insert();

create or replace function acquisition_task_guard()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if not exists(select 1 from leads l where l.id=new.lead_id and l.clinic_id=new.clinic_id) then raise exception 'Task lead mismatch'; end if;
  if new.assigned_to is not null and not exists(select 1 from staff_profiles s where s.id=new.assigned_to and s.clinic_id=new.clinic_id and s.active) then raise exception 'Task assignee mismatch'; end if;
  if tg_op='UPDATE' then
    if new.clinic_id<>old.clinic_id or new.lead_id<>old.lead_id then raise exception 'Task cannot change lead'; end if;
    if new.created_at<>old.created_at or new.created_by is distinct from old.created_by then raise exception 'Task origin is immutable'; end if;
  end if;
  return new;
end $$;
drop trigger if exists acquisition_task_guard_trigger on follow_up_tasks;
create trigger acquisition_task_guard_trigger before insert or update on follow_up_tasks for each row execute function acquisition_task_guard();

create or replace function acquisition_task_audit()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_op='INSERT' then
    insert into lead_events(clinic_id,lead_id,event_type,metadata,actor_id)
    values(new.clinic_id,new.lead_id,'task.created',jsonb_build_object('title',new.title,'dueAt',new.due_at),auth.uid());
  elsif old.status is distinct from new.status then
    insert into lead_events(clinic_id,lead_id,event_type,metadata,actor_id)
    values(new.clinic_id,new.lead_id,'task.status_changed',jsonb_build_object('from',old.status,'to',new.status,'title',new.title),auth.uid());
  end if;
  if tg_op='UPDATE' then
    if old.title is distinct from new.title or old.due_at is distinct from new.due_at or old.assigned_to is distinct from new.assigned_to then
      insert into lead_events(clinic_id,lead_id,event_type,metadata,actor_id)
      values(new.clinic_id,new.lead_id,'task.changed',jsonb_build_object('title',new.title,'dueAt',new.due_at,'assignedTo',new.assigned_to),auth.uid());
    end if;
  end if;
  return null;
end $$;
drop trigger if exists acquisition_task_audit_trigger on follow_up_tasks;
create trigger acquisition_task_audit_trigger after insert or update on follow_up_tasks for each row execute function acquisition_task_audit();

-- Serialize photo consent changes with media inserts on the same intake session.
create or replace function acquisition_photo_consent_guard()
returns trigger language plpgsql security definer set search_path=public as $$
declare session_row intake_sessions%rowtype;
begin
  if new.consent_type='guided_photos' then
    if new.session_id is null then raise exception 'Photo consent requires an intake session'; end if;
    select * into session_row from intake_sessions where id=new.session_id for update;
    if session_row.id is null or session_row.clinic_id<>new.clinic_id or session_row.lead_id<>new.lead_id then
      raise exception 'Photo consent session mismatch';
    end if;
    if new.accepted and session_row.status='Completee' then raise exception 'Completed intake cannot add photo consent'; end if;
  end if;
  return new;
end $$;
drop trigger if exists acquisition_photo_consent_guard_trigger on consent_records;
create trigger acquisition_photo_consent_guard_trigger before insert on consent_records for each row execute function acquisition_photo_consent_guard();

create or replace function acquisition_media_guard()
returns trigger language plpgsql security definer set search_path=public as $$
declare session_row intake_sessions%rowtype; photo_consent boolean;
begin
  if new.session_id is null or new.view_definition_id is null then raise exception 'Guided photo session and view required'; end if;
  select * into session_row from intake_sessions where id=new.session_id for update;
  if session_row.id is null or session_row.clinic_id<>new.clinic_id or session_row.lead_id<>new.lead_id then raise exception 'Photo session mismatch'; end if;
  if tg_op='INSERT' then
    if session_row.status<>'En cours' then raise exception 'Completed intake cannot add photos'; end if;
    select accepted into photo_consent from consent_records
    where session_id=new.session_id and consent_type='guided_photos'
    order by recorded_at desc,id desc limit 1;
    if photo_consent is distinct from true then raise exception 'Active photo consent required'; end if;
  elsif new.clinic_id is distinct from old.clinic_id or new.lead_id is distinct from old.lead_id
    or new.session_id is distinct from old.session_id or new.view_definition_id is distinct from old.view_definition_id
    or new.storage_path is distinct from old.storage_path
    or new.mime_type is distinct from old.mime_type or new.size_bytes is distinct from old.size_bytes
    or new.created_at<>old.created_at then
    raise exception 'Photo metadata is immutable';
  end if;
  if not exists(select 1 from photo_view_definitions v join capture_protocols p on p.id=v.protocol_id where v.id=new.view_definition_id and v.clinic_id=new.clinic_id and p.active) then raise exception 'Photo view mismatch'; end if;
  if new.size_bytes not between 1 and 8388608 or new.mime_type not in ('image/jpeg','image/png','image/webp') then raise exception 'Invalid photo'; end if;
  if exists(select 1 from lead_media m where m.session_id=new.session_id and m.view_definition_id=new.view_definition_id and m.id<>new.id) then raise exception 'Photo view already uploaded'; end if;
  if (select count(*) from lead_media m where m.session_id=new.session_id and m.id<>new.id)>=3 then raise exception 'Maximum three photos'; end if;
  return new;
end $$;
drop trigger if exists acquisition_media_guard_trigger on lead_media;
create trigger acquisition_media_guard_trigger before insert or update on lead_media for each row execute function acquisition_media_guard();

alter table consent_records alter column recorded_at set default clock_timestamp();
create index if not exists consent_records_session_latest_idx on consent_records(session_id,consent_type,recorded_at desc,id desc);

create table if not exists lead_quote_events(
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id) on delete cascade,
  lead_id uuid not null references leads(id) on delete cascade,
  quote_id uuid not null references lead_quotes(id) on delete cascade,
  previous_status text,
  status text not null,
  actor_id uuid references staff_profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table lead_quote_events enable row level security;
create policy lead_quote_events_view on lead_quote_events for select to authenticated
using(clinic_id=current_clinic_id() and has_permission('acquisition.view'));

create or replace function acquisition_quote_guard()
returns trigger language plpgsql security definer set search_path=public as $$
declare clinic_currency text;
begin
  if not exists(select 1 from leads l where l.id=new.lead_id and l.clinic_id=new.clinic_id) then raise exception 'Quote lead mismatch'; end if;
  if length(trim(new.title)) not between 1 and 160 or new.amount<0 or new.amount>999999999.99 then raise exception 'Invalid quote'; end if;
  if tg_op='INSERT' then
    select currency into clinic_currency from clinics where id=new.clinic_id;
    if new.currency is distinct from clinic_currency then raise exception 'Quote currency must match clinic currency'; end if;
  end if;
  if tg_op='UPDATE' then
    if new.clinic_id<>old.clinic_id or new.lead_id<>old.lead_id or new.title<>old.title or new.amount<>old.amount or new.currency<>old.currency or new.valid_until is distinct from old.valid_until or new.notes is distinct from old.notes or new.created_by is distinct from old.created_by or new.created_at<>old.created_at then
      raise exception 'Quote terms are immutable; create a new version';
    end if;
    if old.status in ('Accepte','Refuse','Expire') and new.status<>old.status then raise exception 'Final quote status cannot change'; end if;
    if old.status='Brouillon' and new.status not in ('Brouillon','Envoye','Refuse','Expire') then raise exception 'Send quote before acceptance'; end if;
    if new.status='Accepte' and new.valid_until is not null and new.valid_until<current_date then raise exception 'Expired quote cannot be accepted'; end if;
    if new.status is distinct from old.status then new.updated_at:=now(); end if;
  end if;
  return new;
end $$;
drop trigger if exists acquisition_quote_guard_trigger on lead_quotes;
create trigger acquisition_quote_guard_trigger before insert or update on lead_quotes for each row execute function acquisition_quote_guard();

create or replace function acquisition_quote_audit()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_op='INSERT' then
    insert into lead_quote_events(clinic_id,lead_id,quote_id,previous_status,status,actor_id)
    values(new.clinic_id,new.lead_id,new.id,null,new.status,auth.uid());
  elsif old.status is distinct from new.status then
    insert into lead_quote_events(clinic_id,lead_id,quote_id,previous_status,status,actor_id)
    values(new.clinic_id,new.lead_id,new.id,old.status,new.status,auth.uid());
  end if;
  return null;
end $$;
drop trigger if exists acquisition_quote_audit_trigger on lead_quotes;
create trigger acquisition_quote_audit_trigger after insert or update on lead_quotes for each row execute function acquisition_quote_audit();

create or replace function expire_lead_quotes(p_lead_id uuid)
returns integer language plpgsql security definer set search_path=public as $$
declare changed integer;
begin
  if not has_permission('acquisition.view') then raise exception 'Acquisition access denied'; end if;
  update lead_quotes set status='Expire',updated_at=now()
  where clinic_id=current_clinic_id() and lead_id=p_lead_id and status='Envoye' and valid_until<current_date;
  get diagnostics changed=row_count;
  return changed;
end $$;

-- Remove permissive role-based policies left by the original P0 migration.
drop policy if exists leads_member_select on leads;
create policy leads_member_select on leads for select to authenticated using(clinic_id=current_clinic_id() and has_permission('acquisition.view'));
drop policy if exists leads_member_insert on leads;
create policy leads_member_insert on leads for insert to authenticated with check(clinic_id=current_clinic_id() and has_permission('acquisition.manage'));
drop policy if exists leads_member_update on leads;
create policy leads_member_update on leads for update to authenticated using(clinic_id=current_clinic_id() and has_permission('acquisition.manage')) with check(clinic_id=current_clinic_id() and has_permission('acquisition.manage'));
drop policy if exists leads_admin_delete on leads;
drop policy if exists acquisition_children_admin_delete on lead_interactions;
-- Leads and interactions are retained with their stage and quote history.

do $$ declare t text; begin
  foreach t in array array['lead_interactions','follow_up_tasks','consultation_invitations','intake_sessions','intake_answers','lead_media','consent_records','lead_events','lead_quotes'] loop
    execute format('drop policy if exists %I on %I',t||'_member_select',t);
    execute format('create policy %I on %I for select to authenticated using (clinic_id=current_clinic_id() and has_permission(''acquisition.view''))',t||'_member_select',t);
  end loop;
end $$;
drop policy if exists lead_interactions_member_insert on lead_interactions;
create policy lead_interactions_member_insert on lead_interactions for insert to authenticated with check(clinic_id=current_clinic_id() and has_permission('acquisition.manage') and exists(select 1 from leads where id=lead_id and clinic_id=current_clinic_id()));
drop policy if exists follow_up_tasks_member_insert on follow_up_tasks;
create policy follow_up_tasks_member_insert on follow_up_tasks for insert to authenticated with check(clinic_id=current_clinic_id() and has_permission('acquisition.manage') and exists(select 1 from leads where id=lead_id and clinic_id=current_clinic_id()));
drop policy if exists follow_up_tasks_member_update on follow_up_tasks;
create policy follow_up_tasks_member_update on follow_up_tasks for update to authenticated using(clinic_id=current_clinic_id() and has_permission('acquisition.manage')) with check(clinic_id=current_clinic_id() and has_permission('acquisition.manage'));
drop policy if exists lead_quotes_member_select on lead_quotes;
create policy lead_quotes_member_select on lead_quotes for select to authenticated using(clinic_id=current_clinic_id() and has_permission('acquisition.view'));
drop policy if exists lead_quotes_member_insert on lead_quotes;
create policy lead_quotes_member_insert on lead_quotes for insert to authenticated with check(clinic_id=current_clinic_id() and has_permission('acquisition.manage'));
drop policy if exists lead_quotes_member_update on lead_quotes;
create policy lead_quotes_member_update on lead_quotes for update to authenticated using(clinic_id=current_clinic_id() and has_permission('acquisition.manage')) with check(clinic_id=current_clinic_id() and has_permission('acquisition.manage'));
drop policy if exists lead_quotes_admin_delete on lead_quotes;
-- Commercial proposals are retained for audit, including refused and expired versions.

drop policy if exists lead_media_staff_select on storage.objects;
create policy lead_media_staff_select on storage.objects for select to authenticated using(
  bucket_id='lead-media' and (storage.foldername(name))[1]=current_clinic_id()::text
  and has_permission('acquisition.view') and exists(
    select 1 from lead_media m where m.storage_path=name and m.clinic_id=current_clinic_id()
      and exists(select 1 from consent_records c where c.session_id=m.session_id and c.consent_type='guided_photos' and c.accepted=true
        and not exists(select 1 from consent_records later where later.session_id=c.session_id and later.consent_type=c.consent_type
          and (later.recorded_at,later.id)>(c.recorded_at,c.id)))
  )
);
drop policy if exists lead_media_admin_delete on storage.objects;

create or replace function acquisition_media_cleanup_candidates(p_limit integer default 100)
returns table(media_id uuid,storage_path text)
language sql security definer set search_path=public as $$
  select m.id,m.storage_path from lead_media m
  join intake_sessions s on s.id=m.session_id
  join consultation_invitations i on i.id=s.invitation_id
  where auth.role()='service_role' and (
    (s.status='En cours' and i.status<>'Completee' and i.expires_at<now()-interval '30 days')
    or exists(
      select 1 from consent_records c where c.session_id=s.id and c.consent_type='guided_photos' and c.accepted=false
        and not exists(select 1 from consent_records later where later.session_id=c.session_id and later.consent_type=c.consent_type
          and (later.recorded_at,later.id)>(c.recorded_at,c.id))
    )
  ) order by m.created_at,m.id limit greatest(1,least(coalesce(p_limit,100),100));
$$;
revoke all on function acquisition_media_cleanup_candidates(integer) from public,anon,authenticated;
grant execute on function acquisition_media_cleanup_candidates(integer) to service_role;

create or replace function public_submit_lead_intake(p_token text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare i consultation_invitations%rowtype; l leads%rowtype; saved_session_id uuid; submitted_first_name text; submitted_last_name text; submitted_phone text; submitted_email text; submitted_concern text; photo_ids uuid[];
begin
  if jsonb_typeof(p_payload)<>'object' then raise exception 'Invalid intake payload'; end if;
  select * into i from consultation_invitations where token_hash=extensions.digest(coalesce(p_token,''),'sha256') for update;
  if i.id is null or i.status in ('Revoquee','Expiree','Completee') or i.expires_at<=now() then raise exception 'Invitation unavailable'; end if;
  if coalesce((p_payload->>'consent')::boolean,false)=false then raise exception 'Consent required'; end if;
  submitted_first_name:=trim(coalesce(p_payload->>'firstName','')); submitted_last_name:=trim(coalesce(p_payload->>'lastName',''));
  submitted_phone:=trim(coalesce(p_payload->>'phone','')); submitted_email:=trim(coalesce(p_payload->>'email',''));
  submitted_concern:=trim(coalesce(p_payload->>'concern',''));
  if length(submitted_first_name) not between 1 and 80 or length(submitted_last_name)>80 or length(submitted_phone) not between 6 and 30 or length(submitted_email)>160 or length(submitted_concern) not between 3 and 2000 then raise exception 'Invalid intake fields'; end if;
  if submitted_email<>'' and submitted_email!~*'^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception 'Invalid email'; end if;
  if p_payload ? 'photoIds' then
    if jsonb_typeof(p_payload->'photoIds')<>'array' or jsonb_array_length(p_payload->'photoIds')>3 then raise exception 'Invalid photo selection'; end if;
    select coalesce(array_agg(value::uuid),'{}'::uuid[]) into photo_ids from jsonb_array_elements_text(p_payload->'photoIds');
  else photo_ids:='{}'::uuid[]; end if;
  select * into l from leads where id=i.lead_id and clinic_id=i.clinic_id for update;
  insert into intake_sessions(clinic_id,lead_id,invitation_id,status,answers,submitted_at,updated_at)
  values(i.clinic_id,i.lead_id,i.id,'Completee',p_payload,now(),now())
  on conflict(invitation_id) do update set answers=excluded.answers,status='Completee',submitted_at=now(),updated_at=now() returning id into saved_session_id;
  if exists(select 1 from unnest(photo_ids) photo_id where not exists(
    select 1 from lead_media m where m.id=photo_id and m.clinic_id=i.clinic_id and m.lead_id=i.lead_id and m.session_id=saved_session_id
  )) then raise exception 'Photo does not belong to this invitation'; end if;
  if cardinality(photo_ids)>0 and not exists(select 1 from consent_records c where c.session_id=saved_session_id and c.consent_type='guided_photos' and c.accepted=true and not exists(
    select 1 from consent_records later where later.session_id=saved_session_id and later.consent_type='guided_photos'
      and (later.recorded_at,later.id)>(c.recorded_at,c.id)
  )) then raise exception 'Photo consent required'; end if;
  insert into intake_answers(clinic_id,session_id,question_key,answer)
  select i.clinic_id,saved_session_id,key,value from jsonb_each(p_payload)
  on conflict(session_id,question_key) do update set answer=excluded.answer;
  update leads set first_name=submitted_first_name,last_name=coalesce(nullif(submitted_last_name,''),leads.last_name),phone=submitted_phone,
    email=coalesce(nullif(submitted_email,''),leads.email),concern=submitted_concern,
    status=case when leads.status in ('Rendez-vous','Converti') then leads.status else 'Qualifie' end,updated_at=now() where id=l.id;
  update consultation_invitations set status='Completee',completed_at=now() where id=i.id;
  insert into consent_records(clinic_id,lead_id,session_id,consent_type,accepted,policy_version,evidence)
  values(i.clinic_id,l.id,saved_session_id,'intake_and_contact',true,'1.0',jsonb_build_object('source','public-intake'));
  insert into lead_events(clinic_id,lead_id,event_type,metadata) values(i.clinic_id,l.id,'intake.completed',jsonb_build_object('sessionId',saved_session_id));
  return jsonb_build_object('success',true,'bookingSlug',i.booking_slug,'reference','INT-'||upper(substr(replace(saved_session_id::text,'-',''),1,10)));
end $$;

create or replace function revoke_consultation_invitation(p_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare i consultation_invitations%rowtype;
begin
  if not has_permission('acquisition.manage') then raise exception 'Acquisition management denied'; end if;
  select * into i from consultation_invitations where id=p_id and clinic_id=current_clinic_id() for update;
  if i.id is null then raise exception 'Invitation unavailable'; end if;
  if i.status='Completee' then raise exception 'Completed invitation cannot be revoked'; end if;
  if i.status='Revoquee' then return; end if;
  update consultation_invitations set status='Revoquee' where id=i.id;
  insert into lead_events(clinic_id,lead_id,event_type,metadata,actor_id) values(i.clinic_id,i.lead_id,'invitation.revoked',jsonb_build_object('invitationId',i.id),auth.uid());
end $$;

create or replace function convert_lead_to_patient(p_lead_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare l leads%rowtype; p patients%rowtype; was_existing boolean:=false; normalized_phone text; normalized_email text;
begin
  if not has_permission('acquisition.manage') or not has_permission('patients.create') then raise exception 'Conversion denied'; end if;
  select * into l from leads where id=p_lead_id and clinic_id=current_clinic_id() for update;
  if l.id is null then raise exception 'Lead unavailable'; end if;
  if l.converted_patient_id is not null then
    select * into p from patients where id=l.converted_patient_id and clinic_id=l.clinic_id;
    if p.id is not null then return jsonb_build_object('patientId',p.app_id,'databaseId',p.id,'existing',true); end if;
  end if;
  normalized_phone:=regexp_replace(coalesce(l.phone,''),'[^0-9]','','g'); normalized_email:=lower(trim(coalesce(l.email,'')));
  if normalized_phone='' and normalized_email='' then raise exception 'Contact required before conversion'; end if;
  perform pg_advisory_xact_lock(hashtext(l.clinic_id::text||':contact:'||coalesce(nullif(normalized_phone,''),normalized_email)));
  select * into p from patients where clinic_id=l.clinic_id and (
    (normalized_phone<>'' and regexp_replace(coalesce(phone,''),'[^0-9]','','g')=normalized_phone) or
    (normalized_email<>'' and lower(coalesce(email,''))=normalized_email)
  ) order by created_at limit 1;
  if p.id is null then
    insert into patients(clinic_id,app_id,first_name,last_name,phone,email,status)
    values(l.clinic_id,gen_random_uuid()::text,l.first_name,l.last_name,l.phone,l.email,'Actif') returning * into p;
  else was_existing:=true; end if;
  perform set_config('acquisition.converting','yes',true);
  update leads set status='Converti',converted_patient_id=p.id,updated_at=now() where id=l.id;
  perform set_config('acquisition.converting','',true);
  insert into lead_events(clinic_id,lead_id,event_type,metadata,actor_id)
  values(l.clinic_id,l.id,'lead.converted',jsonb_build_object('patientId',p.id,'patientAppId',p.app_id,'existing',was_existing),auth.uid());
  return jsonb_build_object('patientId',p.app_id,'databaseId',p.id,'existing',was_existing);
end $$;

create or replace function create_consultation_invitation(p_lead_id uuid,p_channel text default 'Lien',p_booking_slug text default 'consultation',p_expires_days integer default 14)
returns jsonb language plpgsql security definer set search_path=public as $$
declare l leads%rowtype; raw_token text:=encode(extensions.gen_random_bytes(24),'hex'); i uuid; expiry timestamptz;
begin
  if not has_permission('acquisition.manage') then raise exception 'Acquisition management denied'; end if;
  select * into l from leads where id=p_lead_id and clinic_id=current_clinic_id() for update;
  if l.id is null or l.status='Converti' then raise exception 'Lead unavailable for intake'; end if;
  if p_channel not in ('Lien','WhatsApp','SMS','Email') then raise exception 'Invalid channel'; end if;
  expiry:=now()+make_interval(days=>greatest(1,least(coalesce(p_expires_days,14),60)));
  insert into consultation_invitations(clinic_id,lead_id,token_hash,channel,status,booking_slug,expires_at)
  values(l.clinic_id,l.id,extensions.digest(raw_token,'sha256'),p_channel,'Envoyee',coalesce(nullif(trim(p_booking_slug),''),'consultation'),expiry) returning id into i;
  update leads set status='Invitation envoyee',updated_at=now() where id=l.id;
  insert into lead_events(clinic_id,lead_id,event_type,metadata,actor_id) values(l.clinic_id,l.id,'invitation.created',jsonb_build_object('channel',p_channel,'expiresAt',expiry),auth.uid());
  return jsonb_build_object('id',i,'token',raw_token,'path','/intake/'||raw_token,'expiresAt',expiry);
end $$;

revoke all on function revoke_consultation_invitation(uuid) from public,anon,authenticated;
grant execute on function revoke_consultation_invitation(uuid) to authenticated;
revoke all on function create_lead_checked(jsonb) from public,anon,authenticated;
grant execute on function create_lead_checked(jsonb) to authenticated;
revoke all on function expire_lead_quotes(uuid) from public,anon,authenticated;
grant execute on function expire_lead_quotes(uuid) to authenticated;
revoke all on function convert_lead_to_patient(uuid) from public,anon,authenticated;
grant execute on function convert_lead_to_patient(uuid) to authenticated;
revoke all on function create_consultation_invitation(uuid,text,text,integer) from public,anon,authenticated;
grant execute on function create_consultation_invitation(uuid,text,text,integer) to authenticated;
