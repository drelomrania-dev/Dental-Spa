-- The pgcrypto extension lives in the `extensions` schema on hosted Supabase.
-- Existing function bodies call `digest`; include that trusted schema until the
-- schema-qualified source in migrations 017/018 is used on fresh installs.
alter function public_create_booking(text,date,text,text,text,text,text) set search_path=public,extensions;
alter function public_booking_manage(text) set search_path=public,extensions;
alter function public_reschedule_booking(text,date,text) set search_path=public,extensions;
alter function public_cancel_booking(text,text) set search_path=public,extensions;
