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

revoke all on function public_acquisition_intake_page(text) from public;
grant execute on function public_acquisition_intake_page(text) to anon,authenticated;
