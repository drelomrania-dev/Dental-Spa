-- Revoke, expiry, wrong account and role update boundaries.
begin;

select set_config('qa.admin_id',(select id::text from staff_profiles where role='administrator' and active order by created_at limit 1),true);
select set_config('qa.clinic_id',(select clinic_id::text from staff_profiles where id=current_setting('qa.admin_id')::uuid),true);
select set_config('request.jwt.claim.sub',current_setting('qa.admin_id'),true);
set local role authenticated;
with invitation as (select create_staff_invitation('qa-revoked@example.invalid','Revoked QA','assistant',7) result)
select set_config('qa.revoked_token',result->>'token',true),set_config('qa.revoked_id',result->>'id',true) from invitation;
select set_config('qa.expired_token',create_staff_invitation('qa-expired@example.invalid','Expired QA','assistant',7)->>'token',true);
select set_config('qa.wrong_token',create_staff_invitation('qa-wrong@example.invalid','Wrong QA','assistant',7)->>'token',true);
do $revoke$
begin
  if not revoke_staff_invitation(current_setting('qa.revoked_id')::uuid) then raise exception 'Revoke failed'; end if;
  if public_staff_invitation(current_setting('qa.revoked_token')) is not null then raise exception 'Revoked link remained public'; end if;
end
$revoke$;

reset role;
update staff_invitations set expires_at=now()-interval '1 minute'
where clinic_id=current_setting('qa.clinic_id')::uuid and email='qa-expired@example.invalid';
select set_config('qa.other_id',gen_random_uuid()::text,true);
insert into auth.users(id,aud,role,email,created_at,updated_at)
values(current_setting('qa.other_id')::uuid,'authenticated','authenticated','qa-other@example.invalid',now(),now());
select set_config('request.jwt.claim.sub',current_setting('qa.other_id'),true);
set local role authenticated;

do $denials$
begin
  if public_staff_invitation(current_setting('qa.expired_token')) is not null then raise exception 'Expired link remained public'; end if;
  begin
    perform claim_staff_invitation(current_setting('qa.expired_token'));
    raise exception 'Expired link was claimed';
  exception when others then
    if sqlerrm='Expired link was claimed' then raise; end if;
  end;
  begin
    perform claim_staff_invitation(current_setting('qa.wrong_token'));
    raise exception 'Wrong account claimed invitation';
  exception when others then
    if sqlerrm='Wrong account claimed invitation' then raise; end if;
  end;
  begin
    perform set_staff_membership(current_setting('qa.admin_id')::uuid,'assistant',false);
    raise exception 'Non-admin changed a role';
  exception when others then
    if sqlerrm='Non-admin changed a role' then raise; end if;
  end;
end
$denials$;

reset role;
do $unchanged$
begin
  if exists(select 1 from staff_profiles where id=current_setting('qa.other_id')::uuid)
    or not exists(select 1 from staff_invitations where clinic_id=current_setting('qa.clinic_id')::uuid and email='qa-wrong@example.invalid' and status='pending')
  then raise exception 'Denied claim changed staff state'; end if;
end
$unchanged$;

rollback;
