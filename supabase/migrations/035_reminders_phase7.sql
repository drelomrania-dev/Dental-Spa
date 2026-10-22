-- Phase 7: consent-bound operational reminders. No provider is connected.
create table reminder_rules (
  clinic_id uuid not null references clinics(id) on delete cascade,
  kind text not null check(kind in ('appointment','installment_before','installment_due')),
  enabled boolean not null default true,
  lead_amount integer not null check(lead_amount between 0 and 168),
  updated_at timestamptz not null default now(),
  primary key(clinic_id,kind),
  check ((kind='appointment' and lead_amount between 1 and 168) or (kind<>'appointment' and lead_amount between 0 and 30))
);
create table reminder_templates (
  clinic_id uuid not null references clinics(id) on delete cascade,
  kind text not null check(kind in ('appointment','installment_before','installment_due')),
  channel text not null check(channel in ('email','whatsapp')),
  body text not null check(length(body) between 10 and 500),
  approved boolean not null default false,
  revision integer not null default 1,
  approved_by uuid references staff_profiles(id),
  approved_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key(clinic_id,kind,channel)
);
create table reminder_consents (
  clinic_id uuid not null references clinics(id) on delete cascade,
  patient_id uuid not null references patients(id) on delete cascade,
  channel text not null check(channel in ('email','whatsapp')),
  granted boolean not null,
  evidence text not null check(length(trim(evidence)) between 4 and 300),
  recorded_by uuid not null references staff_profiles(id),
  recorded_at timestamptz not null default now(),
  primary key(clinic_id,patient_id,channel)
);
create table reminder_consent_events (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id) on delete cascade,
  patient_id uuid not null references patients(id) on delete cascade,
  channel text not null,
  granted boolean not null,
  evidence text not null,
  recorded_by uuid not null references staff_profiles(id),
  recorded_at timestamptz not null default now()
);
create table reminder_outbox (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id) on delete cascade,
  patient_id uuid not null references patients(id) on delete cascade,
  kind text not null check(kind in ('appointment','installment_before','installment_due')),
  channel text not null check(channel in ('email','whatsapp')),
  source_id uuid not null,
  source_version text not null,
  scheduled_at timestamptz not null,
  recipient text not null,
  body text not null,
  template_revision integer not null,
  status text not null default 'queued' check(status in ('queued','retry','sent_fake','cancelled')),
  attempts integer not null default 0 check(attempts>=0),
  next_attempt_at timestamptz,
  last_error text,
  queued_at timestamptz not null default now(),
  delivered_at timestamptz,
  cancelled_at timestamptz,
  unique(clinic_id,kind,channel,source_id,source_version)
);
create index reminder_outbox_pending_idx on reminder_outbox(clinic_id,status,next_attempt_at,scheduled_at);
create table reminder_delivery_events (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id) on delete cascade,
  outbox_id uuid not null references reminder_outbox(id) on delete restrict,
  attempt integer not null,
  outcome text not null check(outcome in ('fake_sent','fake_failed','cancelled')),
  detail text,
  occurred_at timestamptz not null default now()
);

alter table reminder_rules enable row level security;
alter table reminder_templates enable row level security;
alter table reminder_consents enable row level security;
alter table reminder_consent_events enable row level security;
alter table reminder_outbox enable row level security;
alter table reminder_delivery_events enable row level security;
revoke all on reminder_rules,reminder_templates,reminder_consents,reminder_consent_events,reminder_outbox,reminder_delivery_events from anon,authenticated;

create or replace function seed_reminder_settings()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into role_permissions(clinic_id,role,permission,scope) values(new.id,'assistant','reminders.manage','clinic') on conflict do nothing;
  insert into reminder_rules(clinic_id,kind,lead_amount) values
    (new.id,'appointment',24),(new.id,'installment_before',3),(new.id,'installment_due',0);
  insert into reminder_templates(clinic_id,kind,channel,body) values
    (new.id,'appointment','email','Bonjour {first_name}, rappel de votre rendez-vous chez {clinic} le {date} à {time}.'),
    (new.id,'appointment','whatsapp','Bonjour {first_name}, rappel de votre rendez-vous chez {clinic} le {date} à {time}.'),
    (new.id,'installment_before','email','Bonjour {first_name}, votre échéance chez {clinic} est prévue le {date}. Contactez le cabinet si nécessaire.'),
    (new.id,'installment_before','whatsapp','Bonjour {first_name}, votre échéance chez {clinic} est prévue le {date}. Contactez le cabinet si nécessaire.'),
    (new.id,'installment_due','email','Bonjour {first_name}, votre échéance chez {clinic} est prévue aujourd’hui, le {date}.'),
    (new.id,'installment_due','whatsapp','Bonjour {first_name}, votre échéance chez {clinic} est prévue aujourd’hui, le {date}.');
  return new;
end $$;
create trigger clinic_reminder_settings after insert on clinics for each row execute function seed_reminder_settings();
insert into reminder_rules(clinic_id,kind,lead_amount)
select c.id,v.kind,v.lead_amount from clinics c cross join (values ('appointment',24),('installment_before',3),('installment_due',0)) v(kind,lead_amount)
on conflict do nothing;
insert into reminder_templates(clinic_id,kind,channel,body)
select c.id,v.kind,v.channel,v.body from clinics c cross join (values
  ('appointment','email','Bonjour {first_name}, rappel de votre rendez-vous chez {clinic} le {date} à {time}.'),
  ('appointment','whatsapp','Bonjour {first_name}, rappel de votre rendez-vous chez {clinic} le {date} à {time}.'),
  ('installment_before','email','Bonjour {first_name}, votre échéance chez {clinic} est prévue le {date}. Contactez le cabinet si nécessaire.'),
  ('installment_before','whatsapp','Bonjour {first_name}, votre échéance chez {clinic} est prévue le {date}. Contactez le cabinet si nécessaire.'),
  ('installment_due','email','Bonjour {first_name}, votre échéance chez {clinic} est prévue aujourd’hui, le {date}.'),
  ('installment_due','whatsapp','Bonjour {first_name}, votre échéance chez {clinic} est prévue aujourd’hui, le {date}.')
) v(kind,channel,body) on conflict do nothing;
insert into role_permissions(clinic_id,role,permission,scope)
select id,'assistant','reminders.manage','clinic' from clinics on conflict do nothing;

create or replace function reminder_render(p_body text,p_clinic text,p_first_name text,p_date text,p_time text)
returns text language sql immutable as $$
  select replace(replace(replace(replace(p_body,'{clinic}',p_clinic),'{first_name}',p_first_name),'{date}',p_date),'{time}',p_time)
$$;

create or replace function reminder_source_valid(p_row reminder_outbox)
returns boolean language plpgsql stable security definer set search_path=public as $$
declare current_version text; current_patient uuid; current_contact text; due_date date; remaining numeric; lead_amount integer; clinic_timezone text; current_start timestamptz;
  current_name text; clinic_name text; template_body text; expected_body text;
begin
  if not exists(select 1 from reminder_rules where clinic_id=p_row.clinic_id and kind=p_row.kind and enabled) or
     not exists(select 1 from reminder_templates where clinic_id=p_row.clinic_id and kind=p_row.kind and channel=p_row.channel and approved and revision=p_row.template_revision) or
     not exists(select 1 from reminder_consents where clinic_id=p_row.clinic_id and patient_id=p_row.patient_id and channel=p_row.channel and granted)
  then return false; end if;
  select case when p_row.channel='email' then nullif(trim(email),'') else nullif(trim(phone),'') end
    into current_contact from patients where id=p_row.patient_id and clinic_id=p_row.clinic_id;
  if current_contact is distinct from p_row.recipient then return false; end if;
  select r.lead_amount,c.timezone,c.name,t.body,p.first_name into lead_amount,clinic_timezone,clinic_name,template_body,current_name
    from reminder_rules r join clinics c on c.id=r.clinic_id
    join reminder_templates t on t.clinic_id=r.clinic_id and t.kind=r.kind and t.channel=p_row.channel
    join patients p on p.id=p_row.patient_id and p.clinic_id=r.clinic_id
    where r.clinic_id=p_row.clinic_id and r.kind=p_row.kind;
  if p_row.kind='appointment' then
    select (extract(epoch from a.starts_at)::bigint)::text,a.patient_id,a.starts_at into current_version,current_patient,current_start from appointments a
      where a.id=p_row.source_id and a.clinic_id=p_row.clinic_id and a.status in ('En attente','Confirmé') and a.starts_at>now();
    if current_start is null then return false; end if;
    if p_row.scheduled_at is distinct from current_start-make_interval(hours=>lead_amount) then return false; end if;
    expected_body:=reminder_render(template_body,clinic_name,current_name,to_char(current_start at time zone clinic_timezone,'YYYY-MM-DD'),to_char(current_start at time zone clinic_timezone,'HH24:MI'));
  else
    select coalesce((select r.new_due_date from finance_installment_reschedules r where r.installment_id=i.id order by r.changed_at desc,r.id desc limit 1),i.original_due_date),
      a.quoted_total-finance_account_paid(a.id),p.id into due_date,remaining,current_patient
      from finance_installments i join finance_accounts a on a.id=i.account_id and a.clinic_id=i.clinic_id
      join patients p on p.clinic_id=a.clinic_id and p.app_id=a.patient_app_id
      where i.id=p_row.source_id and i.clinic_id=p_row.clinic_id;
    if due_date is null or remaining<=0 or (finance_installment_json(p_row.source_id)->>'status')='paid' then return false; end if;
    current_version:=due_date::text;
    if p_row.scheduled_at is distinct from (((due_date-lead_amount)::timestamp+time '09:00') at time zone clinic_timezone) then return false; end if;
    expected_body:=reminder_render(template_body,clinic_name,current_name,due_date::text,'');
  end if;
  return coalesce(current_patient=p_row.patient_id and current_version=p_row.source_version and expected_body=p_row.body,false);
end $$;

create or replace function reminder_cancel_obsolete(p_clinic uuid)
returns integer language plpgsql security definer set search_path=public as $$
declare changed integer;
begin
  with invalidated as (
    update reminder_outbox o set status='cancelled',cancelled_at=now(),last_error='Source, consent, template or rule changed'
      where o.clinic_id=p_clinic and o.status in ('queued','retry') and not reminder_source_valid(o)
      returning o.clinic_id,o.id,o.attempts,o.last_error
  ) insert into reminder_delivery_events(clinic_id,outbox_id,attempt,outcome,detail)
    select clinic_id,id,attempts,'cancelled',last_error from invalidated;
  get diagnostics changed=row_count;
  return changed;
end $$;

create or replace function reminder_snapshot(p_patient_app_id text default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id();
begin
  if clinic is null or not has_permission('reminders.manage') then raise exception 'Reminder access denied'; end if;
  return jsonb_build_object(
    'rules',coalesce((select jsonb_agg(jsonb_build_object('kind',kind,'enabled',enabled,'leadAmount',lead_amount) order by kind)
      from reminder_rules where clinic_id=clinic),'[]'::jsonb),
    'templates',coalesce((select jsonb_agg(jsonb_build_object('kind',kind,'channel',channel,'body',body,'approved',approved,'revision',revision,'approvedAt',approved_at) order by kind,channel)
      from reminder_templates where clinic_id=clinic),'[]'::jsonb),
    'consents',coalesce((select jsonb_agg(jsonb_build_object('patientId',p.app_id,'channel',c.channel,'granted',c.granted,'evidence',c.evidence,'recordedAt',c.recorded_at) order by p.app_id,c.channel)
      from reminder_consents c join patients p on p.id=c.patient_id where c.clinic_id=clinic and (p_patient_app_id is null or p.app_id=p_patient_app_id)),'[]'::jsonb),
    'outbox',coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'patientId',p.app_id,'kind',o.kind,'channel',o.channel,'sourceId',o.source_id,
      'scheduledAt',o.scheduled_at,'recipient',o.recipient,'body',o.body,'status',o.status,'attempts',o.attempts,'nextAttemptAt',o.next_attempt_at,
      'lastError',o.last_error,'queuedAt',o.queued_at,'deliveredAt',o.delivered_at) order by o.queued_at desc)
      from reminder_outbox o join patients p on p.id=o.patient_id where o.clinic_id=clinic and (p_patient_app_id is null or p.app_id=p_patient_app_id)
      limit 200),'[]'::jsonb),
    'events',coalesce((select jsonb_agg(jsonb_build_object('outboxId',e.outbox_id,'attempt',e.attempt,'outcome',e.outcome,'detail',e.detail,'at',e.occurred_at) order by e.occurred_at desc)
      from reminder_delivery_events e where e.clinic_id=clinic and exists(select 1 from reminder_outbox o join patients p on p.id=o.patient_id where o.id=e.outbox_id and (p_patient_app_id is null or p.app_id=p_patient_app_id))
      limit 200),'[]'::jsonb));
end $$;

create or replace function configure_reminder_rule(p_kind text,p_enabled boolean,p_lead_amount integer)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); row reminder_rules%rowtype;
begin
  if clinic is null or not has_permission('settings.manage') then raise exception 'Reminder rule change denied'; end if;
  update reminder_rules set enabled=p_enabled,lead_amount=p_lead_amount,updated_at=now()
    where clinic_id=clinic and kind=p_kind returning * into row;
  if row.clinic_id is null then raise exception 'Reminder rule not found'; end if;
  perform reminder_cancel_obsolete(clinic);
  return jsonb_build_object('kind',row.kind,'enabled',row.enabled,'leadAmount',row.lead_amount);
end $$;

create or replace function save_reminder_template(p_kind text,p_channel text,p_body text,p_approve boolean)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); row reminder_templates%rowtype;
begin
  if clinic is null or not has_permission('settings.manage') then raise exception 'Template change denied'; end if;
  if length(trim(coalesce(p_body,''))) not between 10 and 500 then raise exception 'Invalid template length'; end if;
  if regexp_replace(p_body,'\{(clinic|first_name|date|time)\}','','g') ~ '[{}]'
    then raise exception 'Unsupported template variable'; end if;
  update reminder_templates set body=trim(p_body),approved=p_approve,revision=revision+1,
    approved_by=case when p_approve then auth.uid() else null end,approved_at=case when p_approve then now() else null end,updated_at=now()
    where clinic_id=clinic and kind=p_kind and channel=p_channel returning * into row;
  if row.clinic_id is null then raise exception 'Template not found'; end if;
  perform reminder_cancel_obsolete(clinic);
  return jsonb_build_object('kind',row.kind,'channel',row.channel,'body',row.body,'approved',row.approved,'revision',row.revision);
end $$;

create or replace function record_reminder_consent(p_patient_app_id text,p_channel text,p_granted boolean,p_evidence text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); patient patients%rowtype;
begin
  if clinic is null or not has_permission('reminders.manage') then raise exception 'Consent change denied'; end if;
  if p_channel not in ('email','whatsapp') or p_granted is null or length(trim(coalesce(p_evidence,''))) not between 4 and 300 then raise exception 'Invalid consent evidence'; end if;
  select * into patient from patients where clinic_id=clinic and app_id=p_patient_app_id for update;
  if patient.id is null then raise exception 'Patient not found'; end if;
  if p_granted and ((p_channel='email' and nullif(trim(patient.email),'') is null) or (p_channel='whatsapp' and nullif(trim(patient.phone),'') is null))
    then raise exception 'Patient contact missing'; end if;
  insert into reminder_consents(clinic_id,patient_id,channel,granted,evidence,recorded_by)
    values(clinic,patient.id,p_channel,p_granted,trim(p_evidence),auth.uid())
    on conflict(clinic_id,patient_id,channel) do update set granted=excluded.granted,evidence=excluded.evidence,recorded_by=excluded.recorded_by,recorded_at=now();
  insert into reminder_consent_events(clinic_id,patient_id,channel,granted,evidence,recorded_by)
    values(clinic,patient.id,p_channel,p_granted,trim(p_evidence),auth.uid());
  perform reminder_cancel_obsolete(clinic);
  return jsonb_build_object('patientId',patient.app_id,'channel',p_channel,'granted',p_granted);
end $$;

create or replace function reminder_queue_for_clinic(p_clinic uuid,p_as_of timestamptz)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=p_clinic; row record; due_date date; scheduled timestamptz; body text; recipient text; queued integer:=0;
begin
  if clinic is null or not exists(select 1 from clinics where id=clinic) then raise exception 'Clinic not found'; end if;
  if p_as_of>now()+interval '1 minute' then raise exception 'Future queue time denied'; end if;
  perform reminder_cancel_obsolete(clinic);
  for row in
    select a.id source_id,a.patient_id,a.starts_at source_time,(extract(epoch from a.starts_at)::bigint)::text source_version,c.name clinic_name,c.timezone,p.first_name,p.email,p.phone,
      r.kind,r.lead_amount,t.channel,t.body template_body,t.revision
    from appointments a join clinics c on c.id=a.clinic_id join patients p on p.id=a.patient_id
    join reminder_rules r on r.clinic_id=a.clinic_id and r.kind='appointment' and r.enabled
    join reminder_templates t on t.clinic_id=a.clinic_id and t.kind=r.kind and t.approved
    join reminder_consents co on co.clinic_id=a.clinic_id and co.patient_id=a.patient_id and co.channel=t.channel and co.granted
    where a.clinic_id=clinic and a.status in ('En attente','Confirmé') and a.starts_at>p_as_of
      and a.starts_at-make_interval(hours=>r.lead_amount)<=p_as_of
    union all
    select i.id,p.id,null::timestamptz,coalesce((select rs.new_due_date from finance_installment_reschedules rs where rs.installment_id=i.id order by rs.changed_at desc,rs.id desc limit 1),i.original_due_date)::text,
      c.name,c.timezone,p.first_name,p.email,p.phone,r.kind,r.lead_amount,t.channel,t.body,t.revision
    from finance_installments i join finance_accounts a on a.id=i.account_id and a.clinic_id=i.clinic_id
    join patients p on p.clinic_id=a.clinic_id and p.app_id=a.patient_app_id join clinics c on c.id=i.clinic_id
    join reminder_rules r on r.clinic_id=i.clinic_id and r.kind in ('installment_before','installment_due') and r.enabled
    join reminder_templates t on t.clinic_id=i.clinic_id and t.kind=r.kind and t.approved
    join reminder_consents co on co.clinic_id=i.clinic_id and co.patient_id=p.id and co.channel=t.channel and co.granted
    where i.clinic_id=clinic and (finance_installment_json(i.id)->>'status')<>'paid'
      and a.quoted_total>finance_account_paid(a.id)
  loop
    recipient:=case when row.channel='email' then nullif(trim(row.email),'') else nullif(trim(row.phone),'') end;
    if recipient is null then continue; end if;
    if row.kind='appointment' then
      scheduled:=row.source_time-make_interval(hours=>row.lead_amount);
      body:=reminder_render(row.template_body,row.clinic_name,row.first_name,to_char(row.source_time at time zone row.timezone,'YYYY-MM-DD'),to_char(row.source_time at time zone row.timezone,'HH24:MI'));
    else
      due_date:=row.source_version::date;
      scheduled:=((due_date-row.lead_amount)::timestamp+time '09:00') at time zone row.timezone;
      if due_date<(p_as_of at time zone row.timezone)::date then continue; end if;
      body:=reminder_render(row.template_body,row.clinic_name,row.first_name,due_date::text,'');
    end if;
    if scheduled>p_as_of then continue; end if;
    insert into reminder_outbox(clinic_id,patient_id,kind,channel,source_id,source_version,scheduled_at,recipient,body,template_revision)
      values(clinic,row.patient_id,row.kind,row.channel,row.source_id,row.source_version,scheduled,recipient,body,row.revision)
      on conflict(clinic_id,kind,channel,source_id,source_version) do update
        set status='queued',scheduled_at=excluded.scheduled_at,recipient=excluded.recipient,body=excluded.body,
          template_revision=excluded.template_revision,attempts=0,next_attempt_at=null,last_error=null,cancelled_at=null,queued_at=now()
        where reminder_outbox.status='cancelled';
    if found then queued:=queued+1; end if;
  end loop;
  return jsonb_build_object('queued',queued,'cancelled',reminder_cancel_obsolete(clinic));
end $$;

create or replace function queue_due_reminders(p_as_of timestamptz default now())
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id();
begin
  if clinic is null or not has_permission('reminders.manage') then raise exception 'Reminder queue denied'; end if;
  return reminder_queue_for_clinic(clinic,p_as_of);
end $$;

-- Trusted scheduler entry point. It only creates outbox rows; delivery remains fake/manual.
create or replace function queue_due_reminders_all()
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic_row record; result jsonb; queued integer:=0; cancelled integer:=0;
begin
  if auth.role()<>'service_role' then raise exception 'Trusted scheduler only'; end if;
  for clinic_row in select id from clinics loop
    result:=reminder_queue_for_clinic(clinic_row.id,now());
    queued:=queued+(result->>'queued')::integer;
    cancelled:=cancelled+(result->>'cancelled')::integer;
  end loop;
  return jsonb_build_object('queued',queued,'cancelled',cancelled);
end $$;

create or replace function fake_dispatch_reminder(p_id uuid,p_fail boolean default false)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); row reminder_outbox%rowtype;
begin
  if clinic is null or not has_permission('reminders.manage') then raise exception 'Reminder dispatch denied'; end if;
  select * into row from reminder_outbox where id=p_id and clinic_id=clinic for update;
  if row.id is null then raise exception 'Reminder not found'; end if;
  if row.status not in ('queued','retry') then raise exception 'Reminder is not dispatchable'; end if;
  if row.scheduled_at>now() then raise exception 'Reminder is not due'; end if;
  if row.next_attempt_at is not null and row.next_attempt_at>now() then raise exception 'Retry is not due'; end if;
  if not reminder_source_valid(row) then
    update reminder_outbox set status='cancelled',cancelled_at=now(),last_error='Source, consent, template or rule changed' where id=row.id;
    insert into reminder_delivery_events(clinic_id,outbox_id,attempt,outcome,detail) values(clinic,row.id,row.attempts,'cancelled','Validation before dispatch');
    return jsonb_build_object('id',row.id,'status','cancelled');
  end if;
  if p_fail then
    update reminder_outbox set status='retry',attempts=attempts+1,next_attempt_at=now()+make_interval(mins=>least(60,5*(row.attempts+1))),last_error='Synthetic provider failure'
      where id=row.id;
    insert into reminder_delivery_events(clinic_id,outbox_id,attempt,outcome,detail) values(clinic,row.id,row.attempts+1,'fake_failed','Synthetic provider failure');
    return jsonb_build_object('id',row.id,'status','retry','attempts',row.attempts+1);
  end if;
  update reminder_outbox set status='sent_fake',attempts=attempts+1,delivered_at=now(),next_attempt_at=null,last_error=null where id=row.id;
  insert into reminder_delivery_events(clinic_id,outbox_id,attempt,outcome,detail) values(clinic,row.id,row.attempts+1,'fake_sent','Local fake sender; no network delivery');
  return jsonb_build_object('id',row.id,'status','sent_fake','attempts',row.attempts+1);
end $$;

create or replace function reminder_invalidate_trigger()
returns trigger language plpgsql security definer set search_path=public as $$
declare sources uuid[]; patient uuid;
begin
  if tg_table_name='appointments' then
    sources:=array[new.id];
  elsif tg_table_name='finance_installment_reschedules' then
    sources:=array[new.installment_id];
  elsif tg_table_name='finance_transactions' then
    select array_agg(id) into sources from finance_installments where account_id=new.account_id and clinic_id=new.clinic_id;
  elsif tg_table_name='patients' then
    patient:=new.id;
  end if;
  with invalidated as (
    update reminder_outbox o set status='cancelled',cancelled_at=now(),last_error='Source or contact changed'
      where o.clinic_id=new.clinic_id and o.status in ('queued','retry')
        and ((sources is not null and o.source_id=any(sources)) or (patient is not null and o.patient_id=patient))
      returning o.clinic_id,o.id,o.attempts,o.last_error
  ) insert into reminder_delivery_events(clinic_id,outbox_id,attempt,outcome,detail)
    select clinic_id,id,attempts,'cancelled',last_error from invalidated;
  return new;
end $$;
create trigger appointment_reminder_invalidate after update on appointments for each row execute function reminder_invalidate_trigger();
create trigger finance_payment_reminder_invalidate after insert on finance_transactions for each row execute function reminder_invalidate_trigger();
create trigger finance_reschedule_reminder_invalidate after insert on finance_installment_reschedules for each row execute function reminder_invalidate_trigger();
create trigger patient_contact_reminder_invalidate after update of email,phone on patients for each row execute function reminder_invalidate_trigger();

revoke all on function seed_reminder_settings(),reminder_render(text,text,text,text,text),reminder_source_valid(reminder_outbox),reminder_cancel_obsolete(uuid),
  reminder_snapshot(text),configure_reminder_rule(text,boolean,integer),save_reminder_template(text,text,text,boolean),record_reminder_consent(text,text,boolean,text),
  reminder_queue_for_clinic(uuid,timestamptz),queue_due_reminders(timestamptz),queue_due_reminders_all(),fake_dispatch_reminder(uuid,boolean),reminder_invalidate_trigger() from public,anon,authenticated;
grant execute on function reminder_snapshot(text),configure_reminder_rule(text,boolean,integer),save_reminder_template(text,text,text,boolean),
  record_reminder_consent(text,text,boolean,text),queue_due_reminders(timestamptz),fake_dispatch_reminder(uuid,boolean) to authenticated;
grant execute on function queue_due_reminders_all() to service_role;
