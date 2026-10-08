-- Acquisition & conversion P0: tenant-scoped lead CRM and tokenized mobile intake.

create table if not exists leads (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id) on delete cascade,
  first_name text not null,
  last_name text not null default '',
  phone text,
  email text,
  source text not null default 'Direct',
  status text not null default 'Nouveau' check (status in ('Nouveau','Contacte','Qualifie','Invitation envoyee','Rendez-vous','Converti','Perdu')),
  priority text not null default 'Normale' check (priority in ('Basse','Normale','Haute','Urgente')),
  owner_id uuid references staff_profiles(id) on delete set null,
  concern text,
  notes text,
  utm jsonb not null default '{}'::jsonb,
  converted_patient_id uuid references patients(id) on delete set null,
  last_contact_at timestamptz,
  next_follow_up_at timestamptz,
  created_by uuid references staff_profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists lead_interactions (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id) on delete cascade,
  lead_id uuid not null references leads(id) on delete cascade,
  channel text not null check (channel in ('Telephone','WhatsApp','Email','Note','Visite')),
  direction text not null default 'Sortant' check (direction in ('Entrant','Sortant','Interne')),
  summary text not null,
  outcome text,
  created_by uuid references staff_profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);

create table if not exists capture_protocols (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id) on delete cascade,
  name text not null,
  description text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists photo_view_definitions (
  id uuid primary key default gen_random_uuid(),
  protocol_id uuid not null references capture_protocols(id) on delete cascade,
  clinic_id uuid not null references clinics(id) on delete cascade,
  code text not null,
  label text not null,
  instructions text,
  example_asset_url text,
  sort_order integer not null default 0,
  required boolean not null default true,
  unique(protocol_id,code)
);

create table if not exists consultation_invitations (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id) on delete cascade,
  lead_id uuid not null references leads(id) on delete cascade,
  token_hash bytea not null unique,
  channel text not null default 'Lien' check (channel in ('Lien','WhatsApp','SMS','Email')),
  status text not null default 'Envoyee' check (status in ('Creee','Envoyee','Ouverte','Completee','Expiree','Revoquee')),
  booking_slug text not null default 'consultation',
  expires_at timestamptz not null,
  first_opened_at timestamptz,
  completed_at timestamptz,
  created_by uuid references staff_profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);

create table if not exists intake_sessions (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id) on delete cascade,
  lead_id uuid not null references leads(id) on delete cascade,
  invitation_id uuid not null references consultation_invitations(id) on delete cascade,
  status text not null default 'Completee' check (status in ('En cours','Completee')),
  answers jsonb not null default '{}'::jsonb,
  submitted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(invitation_id)
);

create table if not exists intake_answers (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id) on delete cascade,
  session_id uuid not null references intake_sessions(id) on delete cascade,
  question_key text not null,
  answer jsonb not null,
  created_at timestamptz not null default now(),
  unique(session_id,question_key)
);

create table if not exists lead_media (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id) on delete cascade,
  lead_id uuid not null references leads(id) on delete cascade,
  session_id uuid references intake_sessions(id) on delete set null,
  view_definition_id uuid references photo_view_definitions(id) on delete set null,
  storage_path text not null,
  mime_type text,
  size_bytes bigint check (size_bytes is null or size_bytes >= 0),
  quality_status text not null default 'A verifier' check (quality_status in ('A verifier','Acceptee','A reprendre')),
  uploaded_by uuid references staff_profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists follow_up_tasks (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id) on delete cascade,
  lead_id uuid not null references leads(id) on delete cascade,
  title text not null,
  due_at timestamptz not null,
  assigned_to uuid references staff_profiles(id) on delete set null,
  status text not null default 'A faire' check (status in ('A faire','Terminee','Annulee')),
  completed_at timestamptz,
  created_by uuid references staff_profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);

create table if not exists consent_records (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id) on delete cascade,
  lead_id uuid not null references leads(id) on delete cascade,
  session_id uuid references intake_sessions(id) on delete set null,
  consent_type text not null,
  accepted boolean not null,
  policy_version text not null default '1.0',
  evidence jsonb not null default '{}'::jsonb,
  recorded_at timestamptz not null default now()
);

create table if not exists lead_events (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id) on delete cascade,
  lead_id uuid not null references leads(id) on delete cascade,
  event_type text not null,
  metadata jsonb not null default '{}'::jsonb,
  actor_id uuid references staff_profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists leads_clinic_status_created_idx on leads(clinic_id,status,created_at desc);
create index if not exists leads_clinic_follow_up_idx on leads(clinic_id,next_follow_up_at) where next_follow_up_at is not null;
create index if not exists lead_interactions_lead_created_idx on lead_interactions(lead_id,created_at desc);
create index if not exists intake_sessions_lead_idx on intake_sessions(lead_id,created_at desc);
create index if not exists follow_up_tasks_clinic_due_idx on follow_up_tasks(clinic_id,status,due_at);
create index if not exists lead_events_lead_created_idx on lead_events(lead_id,created_at desc);

alter table leads enable row level security;
alter table lead_interactions enable row level security;
alter table capture_protocols enable row level security;
alter table photo_view_definitions enable row level security;
alter table consultation_invitations enable row level security;
alter table intake_sessions enable row level security;
alter table intake_answers enable row level security;
alter table lead_media enable row level security;
alter table follow_up_tasks enable row level security;
alter table consent_records enable row level security;
alter table lead_events enable row level security;

do $$
declare table_name text;
begin
  foreach table_name in array array['leads','lead_interactions','capture_protocols','photo_view_definitions','consultation_invitations','intake_sessions','intake_answers','lead_media','follow_up_tasks','consent_records','lead_events']
  loop
    execute format('drop policy if exists %I on %I',table_name||'_member_select',table_name);
    execute format('create policy %I on %I for select to authenticated using (clinic_id=current_clinic_id())',table_name||'_member_select',table_name);
    execute format('drop policy if exists %I on %I',table_name||'_member_insert',table_name);
    execute format('create policy %I on %I for insert to authenticated with check (clinic_id=current_clinic_id())',table_name||'_member_insert',table_name);
    execute format('drop policy if exists %I on %I',table_name||'_member_update',table_name);
    execute format('create policy %I on %I for update to authenticated using (clinic_id=current_clinic_id()) with check (clinic_id=current_clinic_id())',table_name||'_member_update',table_name);
  end loop;
end $$;

drop policy if exists leads_admin_delete on leads;
create policy leads_admin_delete on leads for delete to authenticated
using (clinic_id=current_clinic_id() and current_staff_role()='administrator');

drop policy if exists acquisition_children_admin_delete on lead_interactions;
create policy acquisition_children_admin_delete on lead_interactions for delete to authenticated
using (clinic_id=current_clinic_id() and current_staff_role()='administrator');

create or replace function create_consultation_invitation(
  p_lead_id uuid,
  p_channel text default 'Lien',
  p_booking_slug text default 'consultation',
  p_expires_days integer default 14
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  lead_row leads%rowtype;
  raw_token text:=encode(extensions.gen_random_bytes(24),'hex');
  invitation_id uuid;
  expiration timestamptz:=now()+make_interval(days=>greatest(1,least(coalesce(p_expires_days,14),60)));
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if current_staff_role() not in ('administrator','assistant') then raise exception 'Insufficient permission'; end if;
  select * into lead_row from leads where id=p_lead_id and clinic_id=current_clinic_id();
  if lead_row.id is null then raise exception 'Lead unavailable'; end if;
  if p_channel not in ('Lien','WhatsApp','SMS','Email') then raise exception 'Invalid channel'; end if;

  insert into consultation_invitations(clinic_id,lead_id,token_hash,channel,status,booking_slug,expires_at)
  values(lead_row.clinic_id,lead_row.id,extensions.digest(raw_token,'sha256'),p_channel,'Envoyee',coalesce(nullif(trim(p_booking_slug),''),'consultation'),expiration)
  returning id into invitation_id;
  update leads set status='Invitation envoyee',updated_at=now() where id=lead_row.id;
  insert into lead_events(clinic_id,lead_id,event_type,metadata,actor_id)
  values(lead_row.clinic_id,lead_row.id,'invitation.created',jsonb_build_object('channel',p_channel,'expiresAt',expiration),auth.uid());

  return jsonb_build_object('id',invitation_id,'token',raw_token,'path','/intake/'||raw_token,'expiresAt',expiration);
end;
$$;

create or replace function public_acquisition_intake_page(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  invitation_row consultation_invitations%rowtype;
  lead_row leads%rowtype;
  clinic_row clinics%rowtype;
  photo_views jsonb;
begin
  if length(coalesce(p_token,''))<32 then return null; end if;
  select * into invitation_row from consultation_invitations
  where token_hash=extensions.digest(p_token,'sha256') and status not in ('Revoquee','Expiree') limit 1;
  if invitation_row.id is null or invitation_row.expires_at<=now() then return null; end if;
  select * into lead_row from leads where id=invitation_row.lead_id;
  select * into clinic_row from clinics where id=invitation_row.clinic_id;
  select coalesce(jsonb_agg(jsonb_build_object('code',v.code,'label',v.label,'instructions',coalesce(v.instructions,''),'required',v.required) order by v.sort_order),'[]'::jsonb)
  into photo_views from photo_view_definitions v join capture_protocols p on p.id=v.protocol_id
  where v.clinic_id=invitation_row.clinic_id and p.active=true;
  update consultation_invitations set status=case when status='Envoyee' then 'Ouverte' else status end,
    first_opened_at=coalesce(first_opened_at,now()) where id=invitation_row.id;
  return jsonb_build_object(
    'clinicName',clinic_row.name,
    'clinicAddress',coalesce(clinic_row.address,''),
    'firstName',lead_row.first_name,
    'bookingSlug',invitation_row.booking_slug,
    'photoViews',photo_views,
    'expiresAt',invitation_row.expires_at,
    'completed',invitation_row.status='Completee'
  );
end;
$$;

create or replace function public_submit_lead_intake(p_token text,p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  invitation_row consultation_invitations%rowtype;
  lead_row leads%rowtype;
  saved_session_id uuid;
  submitted_first_name text:=trim(coalesce(p_payload->>'firstName',''));
  submitted_last_name text:=trim(coalesce(p_payload->>'lastName',''));
  submitted_phone text:=trim(coalesce(p_payload->>'phone',''));
  submitted_email text:=trim(coalesce(p_payload->>'email',''));
begin
  if jsonb_typeof(p_payload)<>'object' then raise exception 'Invalid intake payload'; end if;
  select * into invitation_row from consultation_invitations
  where token_hash=extensions.digest(coalesce(p_token,''),'sha256') and status not in ('Revoquee','Expiree') limit 1;
  if invitation_row.id is null or invitation_row.expires_at<=now() then raise exception 'Invitation unavailable'; end if;
  if coalesce((p_payload->>'consent')::boolean,false)=false then raise exception 'Consent required'; end if;
  if length(submitted_first_name) not between 1 and 80 or length(submitted_last_name)>80 or length(submitted_phone) not between 6 and 30 or length(submitted_email)>160 then raise exception 'Invalid contact details'; end if;
  if submitted_email<>'' and submitted_email!~*'^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception 'Invalid email'; end if;
  select * into lead_row from leads where id=invitation_row.lead_id;

  insert into intake_sessions(clinic_id,lead_id,invitation_id,status,answers,submitted_at,updated_at)
  values(invitation_row.clinic_id,invitation_row.lead_id,invitation_row.id,'Completee',p_payload,now(),now())
  on conflict(invitation_id) do update set answers=excluded.answers,status='Completee',submitted_at=now(),updated_at=now()
  returning id into saved_session_id;

  insert into intake_answers(clinic_id,session_id,question_key,answer)
  select invitation_row.clinic_id,saved_session_id,key,value from jsonb_each(p_payload)
  on conflict(session_id,question_key) do update set answer=excluded.answer;

  update leads set first_name=submitted_first_name,last_name=coalesce(nullif(submitted_last_name,''),leads.last_name),phone=submitted_phone,
    email=coalesce(nullif(submitted_email,''),leads.email),concern=coalesce(nullif(trim(p_payload->>'concern'),''),leads.concern),
    status='Qualifie',updated_at=now() where id=lead_row.id;
  update consultation_invitations set status='Completee',completed_at=now() where id=invitation_row.id;
  insert into consent_records(clinic_id,lead_id,session_id,consent_type,accepted,policy_version,evidence)
  values(invitation_row.clinic_id,lead_row.id,saved_session_id,'intake_and_contact',true,'1.0',jsonb_build_object('source','public-intake'));
  insert into lead_events(clinic_id,lead_id,event_type,metadata)
  values(invitation_row.clinic_id,lead_row.id,'intake.completed',jsonb_build_object('sessionId',saved_session_id));
  return jsonb_build_object('success',true,'bookingSlug',invitation_row.booking_slug,'reference','INT-'||upper(substr(replace(saved_session_id::text,'-',''),1,10)));
end;
$$;

revoke all on function create_consultation_invitation(uuid,text,text,integer) from public,anon,authenticated;
grant execute on function create_consultation_invitation(uuid,text,text,integer) to authenticated;
revoke all on function public_acquisition_intake_page(text) from public;
revoke all on function public_submit_lead_intake(text,jsonb) from public;
grant execute on function public_acquisition_intake_page(text) to anon,authenticated;
grant execute on function public_submit_lead_intake(text,jsonb) to anon,authenticated;
