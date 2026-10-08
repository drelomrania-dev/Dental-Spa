-- Supabase applies explicit default grants to API roles when functions are created.
-- Keep the staff-only invitation issuer inaccessible to anonymous callers.
revoke all on function create_consultation_invitation(uuid,text,text,integer) from public,anon,authenticated;
grant execute on function create_consultation_invitation(uuid,text,text,integer) to authenticated;
