-- Private guided-photo storage. Public uploads are accepted only by the
-- acquisition-media Edge Function after validating a one-time intake token.

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('lead-media','lead-media',false,8388608,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists lead_media_staff_select on storage.objects;
create policy lead_media_staff_select on storage.objects for select to authenticated
using(bucket_id='lead-media' and (storage.foldername(name))[1]=current_clinic_id()::text);

drop policy if exists lead_media_admin_delete on storage.objects;
create policy lead_media_admin_delete on storage.objects for delete to authenticated
using(bucket_id='lead-media' and (storage.foldername(name))[1]=current_clinic_id()::text and current_staff_role()='administrator');

with created as (
  insert into capture_protocols(clinic_id,name,description,active)
  select c.id,'Pré-consultation sourire','Trois vues simples pour préparer l’échange avec le praticien.',true
  from clinics c
  where not exists(select 1 from capture_protocols p where p.clinic_id=c.id and p.name='Pré-consultation sourire')
  returning id,clinic_id
), protocols as (
  select id,clinic_id from created
  union all
  select p.id,p.clinic_id from capture_protocols p where p.name='Pré-consultation sourire'
)
insert into photo_view_definitions(protocol_id,clinic_id,code,label,instructions,sort_order,required)
select p.id,p.clinic_id,v.code,v.label,v.instructions,v.sort_order,false
from protocols p cross join (values
  ('smile-front','Sourire de face','Tenez le téléphone à hauteur de bouche, avec une lumière naturelle.',1),
  ('teeth-front','Dents de face','Montrez les dents de face sans zoom numérique.',2),
  ('concern-close','Zone concernée','Cadrez uniquement la zone qui motive votre demande.',3)
) as v(code,label,instructions,sort_order)
on conflict(protocol_id,code) do nothing;
