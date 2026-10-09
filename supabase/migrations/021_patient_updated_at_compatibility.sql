-- Compatibility for projects created before normalized patient update tracking.
alter table patients add column if not exists updated_at timestamptz not null default now();
