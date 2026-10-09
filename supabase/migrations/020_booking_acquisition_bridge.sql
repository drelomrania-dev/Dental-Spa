-- Keep public bookings, the internal agenda, and the acquisition pipeline in sync.

alter table appointments add column if not exists lead_id uuid references leads(id) on delete set null;
create index if not exists appointments_clinic_lead_idx on appointments(clinic_id,lead_id) where lead_id is not null;
alter table patients add column if not exists updated_at timestamptz not null default now();

create or replace function appointment_json(p_id uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'id',a.app_id,'patientId',p.app_id,'leadId',coalesce(a.lead_id::text,''),'doctorId',coalesce(pr.app_id,''),'treatmentId',coalesce(s.app_id,''),
    'date',to_char(a.starts_at at time zone c.timezone,'YYYY-MM-DD'),'time',to_char(a.starts_at at time zone c.timezone,'HH24:MI'),
    'duration',extract(epoch from (a.ends_at-a.starts_at))/60,'reason',coalesce(a.notes,s.name,'Consultation'),'status',a.status,
    'estimatedAmount',a.estimated_amount,'roomId',coalesce(a.room_id,''),'source',a.source,'reference',a.reference,
    'createdAt',a.created_at,'updatedAt',a.updated_at
  ) from appointments a join clinics c on c.id=a.clinic_id join patients p on p.id=a.patient_id
  left join practitioners pr on pr.id=a.practitioner_id left join services s on s.id=a.service_id where a.id=p_id
$$;

create or replace function sync_appointment_event_to_lead()
returns trigger language plpgsql security definer set search_path=public as $$
declare linked_lead uuid; appointment_reference text; appointment_date text;
begin
  select a.lead_id,a.reference,to_char(a.starts_at at time zone c.timezone,'YYYY-MM-DD HH24:MI')
    into linked_lead,appointment_reference,appointment_date
  from appointments a join clinics c on c.id=a.clinic_id where a.id=new.appointment_id;
  if linked_lead is null then return new; end if;

  if new.event_type in ('created','rescheduled') then
    update leads set status=case when status='Converti' then status else 'Rendez-vous' end,
      last_contact_at=now(),updated_at=now() where id=linked_lead;
  elsif new.event_type='cancelled' then
    update leads set status=case when status='Converti' then status else 'Contacte' end,
      last_contact_at=now(),updated_at=now() where id=linked_lead;
  end if;

  insert into lead_events(clinic_id,lead_id,event_type,metadata)
  values(new.clinic_id,linked_lead,'appointment_'||new.event_type,
    jsonb_build_object('appointmentId',new.appointment_id,'reference',appointment_reference,'scheduledAt',appointment_date,'actorType',new.actor_type));

  if new.event_type in ('created','rescheduled','cancelled') then
    insert into lead_interactions(clinic_id,lead_id,channel,direction,summary,outcome)
    values(new.clinic_id,linked_lead,'Note','Entrant',
      case new.event_type
        when 'created' then 'Rendez-vous réservé en ligne le '||appointment_date
        when 'rescheduled' then 'Rendez-vous reporté en ligne au '||appointment_date
        else 'Rendez-vous annulé en ligne'
      end,appointment_reference);
  end if;
  return new;
end;
$$;

drop trigger if exists appointment_event_lead_sync on appointment_events;
create trigger appointment_event_lead_sync after insert on appointment_events
for each row when (new.event_type in ('created','rescheduled','cancelled')) execute function sync_appointment_event_to_lead();

create or replace function public_create_booking(p_slug text,p_date date,p_time text,p_first_name text,p_last_name text,p_phone text,p_email text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare link_row app_records%rowtype; practitioner practitioners%rowtype; service services%rowtype; patient patients%rowtype; lead leads%rowtype; clinic_timezone text;
  duration_minutes integer; start_time timestamptz; end_time timestamptz; appointment appointments%rowtype; normalized_phone text:=regexp_replace(coalesce(p_phone,''),'[^0-9]','','g'); normalized_email text:=lower(trim(coalesce(p_email,''))); raw_token text:=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
begin
  if p_time!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' or length(trim(p_first_name)) not between 1 and 80 or length(trim(p_last_name)) not between 1 and 80 or length(trim(p_phone)) not between 6 and 30 or length(coalesce(trim(p_email),''))>160 then raise exception 'Invalid booking details'; end if;
  select * into link_row from app_records where collection='bookingLinks' and data->>'slug'=p_slug and coalesce((data->>'published')::boolean,false)=true limit 1;
  if link_row.id is null then raise exception 'Booking page unavailable'; end if;
  select timezone into clinic_timezone from clinics where id=link_row.clinic_id;
  select * into practitioner from practitioners where clinic_id=link_row.clinic_id and (app_id=nullif(link_row.data->>'doctorId','') or nullif(link_row.data->>'doctorId','') is null) and active=true order by case when app_id=nullif(link_row.data->>'doctorId','') then 0 else 1 end,name limit 1;
  select * into service from services where clinic_id=link_row.clinic_id and app_id=nullif(link_row.data->>'treatmentId','');
  if practitioner.id is null then raise exception 'Practitioner unavailable'; end if;
  duration_minutes:=coalesce(nullif(link_row.data->>'duration','')::integer,service.duration_minutes,30);
  start_time:=(p_date+p_time::time) at time zone clinic_timezone;end_time:=start_time+make_interval(mins=>duration_minutes);
  perform pg_advisory_xact_lock(hashtext(link_row.clinic_id::text||':'||practitioner.id::text||':'||p_date::text||':'||p_time));
  if not (public_available_slots(p_slug,p_date)?p_time) then raise exception 'Slot unavailable'; end if;

  -- Serialise matching by contact so simultaneous submissions cannot duplicate a patient or lead.
  perform pg_advisory_xact_lock(hashtext(link_row.clinic_id::text||':contact:'||coalesce(nullif(normalized_phone,''),normalized_email)));
  select * into patient from patients where clinic_id=link_row.clinic_id and (
    (normalized_phone<>'' and regexp_replace(coalesce(phone,''),'[^0-9]','','g')=normalized_phone) or
    (normalized_email<>'' and lower(coalesce(email,''))=normalized_email)
  ) order by created_at limit 1;
  if patient.id is null then
    insert into patients(clinic_id,app_id,first_name,last_name,phone,email,status)
    values(link_row.clinic_id,gen_random_uuid()::text,trim(p_first_name),trim(p_last_name),trim(p_phone),nullif(trim(coalesce(p_email,'')),''),'Actif') returning * into patient;
  else
    update patients set email=coalesce(email,nullif(trim(coalesce(p_email,'')),'')),updated_at=now() where id=patient.id returning * into patient;
  end if;

  select * into lead from leads where clinic_id=link_row.clinic_id and (
    (normalized_phone<>'' and regexp_replace(coalesce(phone,''),'[^0-9]','','g')=normalized_phone) or
    (normalized_email<>'' and lower(coalesce(email,''))=normalized_email)
  ) order by case when status='Converti' then 0 else 1 end,created_at limit 1 for update;
  if lead.id is null then
    insert into leads(clinic_id,first_name,last_name,phone,email,source,status,priority,concern,converted_patient_id,last_contact_at)
    values(link_row.clinic_id,trim(p_first_name),trim(p_last_name),trim(p_phone),nullif(trim(coalesce(p_email,'')),''),'Site web','Rendez-vous','Normale',coalesce(service.name,link_row.data->>'title','Consultation'),patient.id,now()) returning * into lead;
  else
    update leads set first_name=coalesce(nullif(first_name,''),trim(p_first_name)),last_name=coalesce(nullif(last_name,''),trim(p_last_name)),
      phone=coalesce(phone,trim(p_phone)),email=coalesce(email,nullif(trim(coalesce(p_email,'')),'')),source=case when source='Direct' then 'Site web' else source end,
      status=case when status='Converti' then status else 'Rendez-vous' end,concern=coalesce(concern,service.name,link_row.data->>'title','Consultation'),
      converted_patient_id=coalesce(converted_patient_id,patient.id),last_contact_at=now(),updated_at=now()
    where id=lead.id returning * into lead;
  end if;

  insert into appointments(clinic_id,app_id,patient_id,lead_id,practitioner_id,service_id,starts_at,ends_at,status,source,reference,notes,estimated_amount,manage_token_hash,manage_token_expires_at,booking_slug)
  values(link_row.clinic_id,gen_random_uuid()::text,patient.id,lead.id,practitioner.id,service.id,start_time,end_time,case when link_row.data->>'confirmationPolicy'='manual' then 'En attente' else 'Confirmé' end,'public','RDV-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)),coalesce(service.name,link_row.data->>'title','Consultation'),service.standard_price,encode(extensions.digest(raw_token,'sha256'),'hex'),start_time+interval '30 days',p_slug) returning * into appointment;
  insert into appointment_events(clinic_id,appointment_id,event_type,actor_type,next_value) values(link_row.clinic_id,appointment.id,'created','patient',appointment_json(appointment.id));
  return appointment_json(appointment.id)||jsonb_build_object('manageToken',raw_token);
end;
$$;

revoke all on function sync_appointment_event_to_lead() from public,anon,authenticated;
grant execute on function public_create_booking(text,date,text,text,text,text,text) to anon,authenticated;
