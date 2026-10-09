create or replace function app_record_allowed(p_collection text,p_action text,p_data jsonb default '{}'::jsonb)
returns boolean
language plpgsql
stable
security definer
set search_path=public
as $$
declare role_name text:=current_staff_role();
begin
  if role_name='administrator' then return true; end if;
  if p_action='select' then
    return case
      when p_collection in ('_clinic','doctors','treatments','bookingLinks','staff','roles') then true
      when p_collection='appointments' then has_permission('appointments.view')
      when p_collection='payments' then has_permission('payments.view.all') or (has_permission('payments.view.own') and p_data->>'collectedBy'=auth.uid()::text)
      when p_collection in ('visits','treatmentPlans') then has_permission('clinical.view')
      when p_collection='priceRequests' then has_permission('priceRequests.approve') or (has_permission('priceRequests.create') and p_data->>'requestedBy'=auth.uid()::text)
      when p_collection='collectionSessions' then has_permission('sessions.manage') or (has_permission('sessions.own') and p_data->>'openedBy'=auth.uid()::text)
      when p_collection='auditEvents' then has_permission('audit.view')
      else false end;
  elsif p_action='insert' then
    return case
      when p_collection='appointments' then has_permission('appointments.create')
      when p_collection='payments' then has_permission('payments.collect') and p_data->>'collectedBy'=auth.uid()::text
      when p_collection='visits' then has_permission('clinical.edit')
      when p_collection='treatmentPlans' then has_permission('plans.create')
      when p_collection='priceRequests' then has_permission('priceRequests.create') and p_data->>'requestedBy'=auth.uid()::text
      when p_collection='collectionSessions' then has_permission('sessions.own') and p_data->>'openedBy'=auth.uid()::text
      when p_collection in ('doctors','treatments','bookingLinks','_clinic') then has_permission('settings.manage') or has_permission('services.manage')
      when p_collection in ('staff','roles') then has_permission('staff.manage') or has_permission('permissions.manage')
      else false end;
  elsif p_action='update' then
    return case
      when p_collection='appointments' then has_permission('appointments.edit')
      when p_collection='payments' then has_permission('payments.correct')
      when p_collection in ('visits','treatmentPlans') then has_permission('clinical.edit')
      when p_collection='priceRequests' then has_permission('priceRequests.approve')
      when p_collection='collectionSessions' then has_permission('sessions.manage') or (has_permission('sessions.own') and p_data->>'openedBy'=auth.uid()::text)
      when p_collection in ('doctors','treatments','bookingLinks','_clinic') then has_permission('settings.manage') or has_permission('services.manage')
      when p_collection in ('staff','roles') then has_permission('staff.manage') or has_permission('permissions.manage')
      else false end;
  elsif p_action='delete' then
    return role_name='administrator';
  end if;
  return false;
end;
$$;

revoke all on function app_record_allowed(text,text,jsonb) from public,anon,authenticated;
grant execute on function app_record_allowed(text,text,jsonb) to authenticated;

drop policy if exists app_records_member_select on app_records;
create policy app_records_member_select on app_records for select to authenticated
using(clinic_id=current_clinic_id() and app_record_allowed(collection,'select',data));

drop policy if exists app_records_member_insert on app_records;
create policy app_records_member_insert on app_records for insert to authenticated
with check(clinic_id=current_clinic_id() and app_record_allowed(collection,'insert',data));

drop policy if exists app_records_member_update on app_records;
create policy app_records_member_update on app_records for update to authenticated
using(clinic_id=current_clinic_id() and app_record_allowed(collection,'update',data))
with check(clinic_id=current_clinic_id() and app_record_allowed(collection,'update',data));

drop policy if exists app_records_member_delete on app_records;
create policy app_records_member_delete on app_records for delete to authenticated
using(clinic_id=current_clinic_id() and app_record_allowed(collection,'delete',data));

drop policy if exists patients_member_select on patients;
create policy patients_member_select on patients for select to authenticated
using(clinic_id=current_clinic_id() and has_permission('patients.basic.view'));
drop policy if exists patients_member_insert on patients;
create policy patients_member_insert on patients for insert to authenticated
with check(clinic_id=current_clinic_id() and has_permission('patients.create'));
drop policy if exists patients_member_update on patients;
create policy patients_member_update on patients for update to authenticated
using(clinic_id=current_clinic_id() and has_permission('patients.edit'))
with check(clinic_id=current_clinic_id() and has_permission('patients.edit'));
drop policy if exists patients_member_delete on patients;
create policy patients_member_delete on patients for delete to authenticated
using(clinic_id=current_clinic_id() and current_staff_role()='administrator');
