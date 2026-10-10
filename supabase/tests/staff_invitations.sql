-- Staff invitations bind an Auth identity to exactly one clinic and role.
begin;

select set_config('qa.admin_id',(select id::text from staff_profiles where active=true and role='administrator' order by created_at limit 1),true);
select set_config('request.jwt.claim.sub',current_setting('qa.admin_id'),true);
set local role authenticated;
select set_config('qa.assistant_token',create_staff_invitation('qa-staff-assistant@example.invalid','Accueil QA','assistant',7)->>'token',true);
select set_config('qa.practitioner_token',create_staff_invitation('qa-staff-practitioner@example.invalid','Dr QA','practitioner',7)->>'token',true);

do $admin_snapshot$
declare snapshot jsonb:=staff_management_snapshot();
begin
  if (select count(*) from jsonb_array_elements(snapshot->'invitations') row where row->>'email' like 'qa-staff-%')<>2 then raise exception 'Pending invitations are missing from staff snapshot'; end if;
end
$admin_snapshot$;

reset role;
select set_config('qa.assistant_id',gen_random_uuid()::text,true);
select set_config('qa.practitioner_id',gen_random_uuid()::text,true);
insert into auth.users(id,aud,role,email,created_at,updated_at) values
  (current_setting('qa.assistant_id')::uuid,'authenticated','authenticated','qa-staff-assistant@example.invalid',now(),now()),
  (current_setting('qa.practitioner_id')::uuid,'authenticated','authenticated','qa-staff-practitioner@example.invalid',now(),now());

select set_config('request.jwt.claim.sub',current_setting('qa.assistant_id'),true);
set local role authenticated;
do $assistant_claim$
declare page jsonb:=public_staff_invitation(current_setting('qa.assistant_token')); access_context jsonb;
begin
  if page->>'role'<>'assistant' then raise exception 'Public invitation metadata is incorrect'; end if;
  access_context:=claim_staff_invitation(current_setting('qa.assistant_token'));
  if access_context->>'role'<>'assistant' then raise exception 'Assistant role was not claimed'; end if;
  if claim_staff_invitation(current_setting('qa.assistant_token'))->>'role'<>'assistant' then raise exception 'Claim is not idempotent'; end if;
end
$assistant_claim$;

reset role;
select set_config('request.jwt.claim.sub',current_setting('qa.practitioner_id'),true);
set local role authenticated;
do $practitioner_claim$
declare access_context jsonb:=claim_staff_invitation(current_setting('qa.practitioner_token'));
begin
  if access_context->>'role'<>'practitioner' then raise exception 'Practitioner role was not claimed'; end if;
end
$practitioner_claim$;

reset role;
do $grants$
begin
  if not exists(select 1 from practitioners where staff_id=current_setting('qa.practitioner_id')::uuid and active) then raise exception 'Practitioner identity was not linked to the clinical directory'; end if;
  if has_table_privilege('anon','public.staff_invitations','select') or has_table_privilege('authenticated','public.staff_invitations','select') then raise exception 'Invitation table is directly readable'; end if;
end
$grants$;

rollback;
