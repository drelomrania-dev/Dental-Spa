-- Tighten write access: reception/administration manage the commercial
-- pipeline; public intake writes only through token-validating server code.

drop policy if exists leads_member_insert on leads;
create policy leads_member_insert on leads for insert to authenticated
with check(clinic_id=current_clinic_id() and current_staff_role() in ('administrator','assistant'));

drop policy if exists lead_interactions_member_insert on lead_interactions;
create policy lead_interactions_member_insert on lead_interactions for insert to authenticated
with check(clinic_id=current_clinic_id() and exists(select 1 from leads l where l.id=lead_id and l.clinic_id=current_clinic_id()));
drop policy if exists lead_interactions_member_update on lead_interactions;
drop policy if exists leads_member_update on leads;
create policy leads_member_update on leads for update to authenticated
using(clinic_id=current_clinic_id() and current_staff_role() in ('administrator','assistant'))
with check(clinic_id=current_clinic_id() and current_staff_role() in ('administrator','assistant'));

drop policy if exists follow_up_tasks_member_insert on follow_up_tasks;
create policy follow_up_tasks_member_insert on follow_up_tasks for insert to authenticated
with check(clinic_id=current_clinic_id() and current_staff_role() in ('administrator','assistant') and exists(select 1 from leads l where l.id=lead_id and l.clinic_id=current_clinic_id()));
drop policy if exists follow_up_tasks_member_update on follow_up_tasks;
create policy follow_up_tasks_member_update on follow_up_tasks for update to authenticated
using(clinic_id=current_clinic_id() and current_staff_role() in ('administrator','assistant'))
with check(clinic_id=current_clinic_id() and current_staff_role() in ('administrator','assistant') and exists(select 1 from leads l where l.id=lead_id and l.clinic_id=current_clinic_id()));

drop policy if exists capture_protocols_member_insert on capture_protocols;
create policy capture_protocols_member_insert on capture_protocols for insert to authenticated
with check(clinic_id=current_clinic_id() and current_staff_role()='administrator');
drop policy if exists capture_protocols_member_update on capture_protocols;
create policy capture_protocols_member_update on capture_protocols for update to authenticated
using(clinic_id=current_clinic_id() and current_staff_role()='administrator')
with check(clinic_id=current_clinic_id() and current_staff_role()='administrator');

drop policy if exists photo_view_definitions_member_insert on photo_view_definitions;
create policy photo_view_definitions_member_insert on photo_view_definitions for insert to authenticated
with check(clinic_id=current_clinic_id() and current_staff_role()='administrator' and exists(select 1 from capture_protocols p where p.id=protocol_id and p.clinic_id=current_clinic_id()));
drop policy if exists photo_view_definitions_member_update on photo_view_definitions;
create policy photo_view_definitions_member_update on photo_view_definitions for update to authenticated
using(clinic_id=current_clinic_id() and current_staff_role()='administrator')
with check(clinic_id=current_clinic_id() and current_staff_role()='administrator' and exists(select 1 from capture_protocols p where p.id=protocol_id and p.clinic_id=current_clinic_id()));

drop policy if exists consultation_invitations_member_insert on consultation_invitations;
drop policy if exists consultation_invitations_member_update on consultation_invitations;
drop policy if exists intake_sessions_member_insert on intake_sessions;
drop policy if exists intake_sessions_member_update on intake_sessions;
drop policy if exists intake_answers_member_insert on intake_answers;
drop policy if exists intake_answers_member_update on intake_answers;
drop policy if exists lead_media_member_insert on lead_media;
drop policy if exists lead_media_member_update on lead_media;
drop policy if exists consent_records_member_insert on consent_records;
drop policy if exists consent_records_member_update on consent_records;
drop policy if exists lead_events_member_insert on lead_events;
drop policy if exists lead_events_member_update on lead_events;
