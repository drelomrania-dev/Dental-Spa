-- Dental Spa MVP schema for Supabase/Postgres.
-- Apply only after reviewing the clinic's deployment and RLS policy requirements.

create extension if not exists pgcrypto;

create table if not exists clinics (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  currency text not null default 'MAD',
  timezone text not null default 'Africa/Casablanca',
  phone text,
  address text,
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists staff_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  clinic_id uuid not null references clinics(id),
  display_name text not null,
  role text not null check (role in ('administrator','assistant','practitioner')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists patients (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id),
  first_name text not null,
  last_name text not null,
  phone text,
  email text,
  date_of_birth date,
  address text,
  emergency_contact jsonb not null default '{}'::jsonb,
  medical_alerts text,
  status text not null default 'Actif',
  created_at timestamptz not null default now()
);

create table if not exists practitioners (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id),
  staff_id uuid references staff_profiles(id),
  name text not null,
  specialty text,
  availability jsonb not null default '{}'::jsonb,
  active boolean not null default true
);

create table if not exists services (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id),
  name text not null,
  description text,
  category text,
  standard_price numeric(12,2) not null default 0 check (standard_price >= 0),
  duration_minutes integer not null default 30 check (duration_minutes > 0),
  active boolean not null default true,
  booking_eligible boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists appointments (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id),
  patient_id uuid not null references patients(id),
  practitioner_id uuid references practitioners(id),
  service_id uuid references services(id),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'Pending',
  source text not null default 'internal',
  reference text not null unique,
  notes text,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create table if not exists clinical_visits (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id),
  patient_id uuid not null references patients(id),
  practitioner_id uuid references practitioners(id),
  appointment_id uuid references appointments(id),
  visit_date date not null default current_date,
  notes text not null,
  follow_up text,
  status text not null default 'Terminé',
  created_at timestamptz not null default now()
);

create table if not exists treatment_plans (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id),
  patient_id uuid not null references patients(id),
  practitioner_id uuid references practitioners(id),
  status text not null default 'Draft',
  created_at timestamptz not null default now()
);

create table if not exists treatment_plan_items (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references treatment_plans(id) on delete cascade,
  service_id uuid not null references services(id),
  quantity numeric(10,2) not null default 1 check (quantity > 0),
  original_price numeric(12,2) not null check (original_price >= 0),
  approved_price numeric(12,2) check (approved_price >= 0),
  status text not null default 'Proposé'
);

create table if not exists price_requests (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id),
  patient_id uuid not null references patients(id),
  plan_item_id uuid references treatment_plan_items(id),
  standard_price numeric(12,2) not null check (standard_price >= 0),
  proposed_price numeric(12,2) not null check (proposed_price >= 0),
  reason text not null,
  requested_by uuid not null references staff_profiles(id),
  decided_by uuid references staff_profiles(id),
  status text not null default 'Pending',
  decision_reason text,
  created_at timestamptz not null default now(),
  decided_at timestamptz
);

create table if not exists payment_transactions (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id),
  patient_id uuid not null references patients(id),
  plan_id uuid references treatment_plans(id),
  amount numeric(12,2) not null check (amount > 0),
  method text not null,
  reference text not null unique,
  idempotency_key text not null unique,
  collected_by uuid not null references staff_profiles(id),
  status text not null default 'Valid',
  created_at timestamptz not null default now()
);

create table if not exists collection_sessions (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id),
  opened_by uuid not null references staff_profiles(id),
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  opening_cash numeric(12,2) not null default 0,
  counted_cash numeric(12,2),
  status text not null default 'Open',
  discrepancy numeric(12,2)
);

create table if not exists audit_events (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id),
  actor_id uuid references staff_profiles(id),
  action text not null,
  entity_type text not null,
  entity_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists appointments_clinic_start_idx on appointments(clinic_id, starts_at);
create index if not exists appointments_practitioner_start_idx on appointments(practitioner_id, starts_at);
create index if not exists patients_clinic_name_idx on patients(clinic_id, last_name, first_name);
create index if not exists payments_clinic_created_idx on payment_transactions(clinic_id, created_at);

-- RLS is intentionally enabled with no permissive policies in this starter migration.
-- Add clinic-scoped policies only after auth roles and the clinic membership model are reviewed.
alter table clinics enable row level security;
alter table staff_profiles enable row level security;
alter table patients enable row level security;
alter table practitioners enable row level security;
alter table services enable row level security;
alter table appointments enable row level security;
alter table clinical_visits enable row level security;
alter table treatment_plans enable row level security;
alter table treatment_plan_items enable row level security;
alter table price_requests enable row level security;
alter table payment_transactions enable row level security;
alter table collection_sessions enable row level security;
alter table audit_events enable row level security;
