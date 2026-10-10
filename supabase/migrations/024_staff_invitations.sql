-- Secure staff onboarding without depending on Supabase's outbound email quota.

create table if not exists staff_invitations (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id) on delete cascade,
  email text not null,
  display_name text not null,
  role text not null check(role in ('assistant','practitioner')),
  token_hash text not null unique,
  status text not null default 'pending' check(status in ('pending','claimed','revoked','expired')),
  expires_at timestamptz not null,
  invited_by uuid references staff_profiles(id) on delete set null,
  claimed_by uuid references staff_profiles(id) on delete set null,
  claimed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists staff_invitations_clinic_status_idx on staff_invitations(clinic_id,status,created_at desc);
create unique index if not exists staff_invitations_pending_email_uidx on staff_invitations(clinic_id,(lower(email))) where status='pending';
alter table staff_invitations enable row level security;

create or replace function staff_management_snapshot()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id();
begin
  if clinic is null or not has_permission('staff.manage') then raise exception 'Staff management denied'; end if;
  return jsonb_build_object(
    'members',coalesce((select jsonb_agg(jsonb_build_object(
      'id',s.id,'name',s.display_name,'email',coalesce(u.email,''),'role',s.role,'active',s.active,'createdAt',s.created_at
    ) order by s.active desc,s.display_name) from staff_profiles s left join auth.users u on u.id=s.id where s.clinic_id=clinic),'[]'::jsonb),
    'invitations',coalesce((select jsonb_agg(jsonb_build_object(
      'id',i.id,'name',i.display_name,'email',i.email,'role',i.role,'status',i.status,'expiresAt',i.expires_at,'createdAt',i.created_at
    ) order by i.created_at desc) from staff_invitations i where i.clinic_id=clinic and i.created_at>now()-interval '90 days'),'[]'::jsonb)
  );
end;
$$;

create or replace function create_staff_invitation(p_email text,p_display_name text,p_role text,p_expires_days integer default 7)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare clinic uuid:=current_clinic_id(); normalized_email text:=lower(trim(coalesce(p_email,''))); raw_token text:=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-',''); saved staff_invitations%rowtype;
begin
  if clinic is null or not has_permission('staff.manage') then raise exception 'Staff management denied'; end if;
  if normalized_email!~'^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' or length(normalized_email)>160 or length(trim(coalesce(p_display_name,''))) not between 2 and 100 or p_role not in ('assistant','practitioner') or p_expires_days not between 1 and 30 then raise exception 'Invalid staff invitation'; end if;
  if exists(select 1 from staff_profiles s join auth.users u on u.id=s.id where lower(u.email)=normalized_email) then raise exception 'This email already belongs to a staff member'; end if;
  update staff_invitations set status='expired',updated_at=now() where clinic_id=clinic and status='pending' and expires_at<=now();
  update staff_invitations set status='revoked',updated_at=now() where clinic_id=clinic and status='pending' and lower(email)=normalized_email;
  insert into staff_invitations(clinic_id,email,display_name,role,token_hash,expires_at,invited_by)
  values(clinic,normalized_email,trim(p_display_name),p_role,encode(digest(raw_token,'sha256'),'hex'),now()+make_interval(days=>p_expires_days),auth.uid()) returning * into saved;
  return jsonb_build_object('id',saved.id,'token',raw_token,'email',saved.email,'name',saved.display_name,'role',saved.role,'expiresAt',saved.expires_at,'path','/join/'||raw_token);
end;
$$;

create or replace function public_staff_invitation(p_token text)
returns jsonb language plpgsql stable security definer set search_path=public,extensions as $$
declare invitation staff_invitations%rowtype; clinic_name text;
begin
  if length(coalesce(p_token,''))<32 then return null; end if;
  select * into invitation from staff_invitations where token_hash=encode(digest(p_token,'sha256'),'hex') and expires_at>now()
    and (status='pending' or (status='claimed' and claimed_by=auth.uid())) limit 1;
  if invitation.id is null then return null; end if;
  select name into clinic_name from clinics where id=invitation.clinic_id;
  return jsonb_build_object('email',invitation.email,'name',invitation.display_name,'role',invitation.role,'clinicName',clinic_name,'expiresAt',invitation.expires_at,'claimed',invitation.status='claimed');
end;
$$;

create or replace function claim_staff_invitation(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare invitation staff_invitations%rowtype; account_email text; existing staff_profiles%rowtype; doctor_app_id text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if length(coalesce(p_token,''))<32 then raise exception 'Invitation unavailable'; end if;
  select * into invitation from staff_invitations where token_hash=encode(digest(p_token,'sha256'),'hex') for update;
  if invitation.id is null or invitation.status in ('revoked','expired') then raise exception 'Invitation unavailable'; end if;
  if invitation.expires_at<=now() then update staff_invitations set status='expired',updated_at=now() where id=invitation.id; raise exception 'Invitation expired'; end if;
  if invitation.status='claimed' then
    if invitation.claimed_by=auth.uid() then return current_access_context(); end if;
    raise exception 'Invitation already claimed';
  end if;
  select lower(email) into account_email from auth.users where id=auth.uid();
  if account_email is null or account_email<>lower(invitation.email) then raise exception 'Invitation email does not match authenticated account'; end if;
  select * into existing from staff_profiles where id=auth.uid();
  if existing.id is not null and existing.clinic_id<>invitation.clinic_id then raise exception 'Account already belongs to another clinic'; end if;
  if existing.id is null then
    insert into staff_profiles(id,clinic_id,display_name,role,active) values(auth.uid(),invitation.clinic_id,invitation.display_name,invitation.role,true);
  else
    update staff_profiles set display_name=invitation.display_name,role=invitation.role,active=true where id=auth.uid();
  end if;
  if invitation.role='practitioner' then
    select id into doctor_app_id from app_records where clinic_id=invitation.clinic_id and collection='doctors' and lower(coalesce(data->>'email',''))=account_email order by created_at limit 1;
    if doctor_app_id is null then
      doctor_app_id:=gen_random_uuid()::text;
      insert into app_records(clinic_id,collection,id,data) values(invitation.clinic_id,'doctors',doctor_app_id,jsonb_build_object('id',doctor_app_id,'name',invitation.display_name,'email',invitation.email,'specialty','Médecin dentiste','availability','À configurer','active',true));
    end if;
    insert into practitioners(clinic_id,app_id,staff_id,name,specialty,availability,active)
    values(invitation.clinic_id,doctor_app_id,auth.uid(),invitation.display_name,'Médecin dentiste','{}'::jsonb,true)
    on conflict(clinic_id,app_id) do update set staff_id=excluded.staff_id,name=excluded.name,active=true;
  end if;
  update staff_invitations set status='claimed',claimed_by=auth.uid(),claimed_at=now(),updated_at=now() where id=invitation.id;
  return current_access_context();
end;
$$;

create or replace function revoke_staff_invitation(p_invitation_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare clinic uuid:=current_clinic_id(); changed integer;
begin
  if clinic is null or not has_permission('staff.manage') then raise exception 'Staff management denied'; end if;
  update staff_invitations set status='revoked',updated_at=now() where id=p_invitation_id and clinic_id=clinic and status='pending';
  get diagnostics changed=row_count;
  return changed=1;
end;
$$;

revoke all on staff_invitations from anon,authenticated;
drop policy if exists staff_invitations_rpc_only on staff_invitations;
create policy staff_invitations_rpc_only on staff_invitations for all to public using(false) with check(false);
revoke all on function staff_management_snapshot(),create_staff_invitation(text,text,text,integer),public_staff_invitation(text),claim_staff_invitation(text),revoke_staff_invitation(uuid) from public,anon,authenticated;
grant execute on function staff_management_snapshot(),create_staff_invitation(text,text,text,integer),claim_staff_invitation(text),revoke_staff_invitation(uuid) to authenticated;
grant execute on function public_staff_invitation(text) to anon,authenticated;
