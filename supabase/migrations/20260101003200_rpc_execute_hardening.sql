-- ============================================================================
-- Student Codex migration 0032 — RPC EXECUTE HARDENING (security audit
-- findings F1/F2/F3)
--
-- WHY: three SECURITY DEFINER RPCs were executable by `authenticated` even
-- though no live client needs that door:
--   * teacher_signup (0013) — the dashboard stopped calling it in 0020
--     (flat single-group metadata is normalized into teacher_signup_multi
--     by the activation card). Its authenticated grant let ANY signed-in
--     user self-grant the teacher role, bypassing every later gate on the
--     successor RPCs (0028 email-ownership proof, 0030 verified-email DB
--     gate, 0031 @parsu.edu.ph school-domain eligibility).
--   * import_student_classroom_courses (0022, redefined 0027) — the only
--     caller is the classroom-import Edge Function, which calls it with
--     the service-role key AFTER verifying the caller's session JWT and
--     re-fetching the picked courses from Google (a stale/forged course id
--     stops there). The function trusts its p_user argument, so a direct
--     authenticated call could enroll arbitrary users and create/link
--     course rows without any of that verification.
--   * enroll_student_courses (0017, redefined 0018/0021/0027) — the only
--     callers are the two auth.users metadata triggers (handle_new_user,
--     handle_user_profile_sync), which run as the SECURITY DEFINER owner
--     (postgres) — the authenticated grant was never needed by them.
--
-- WHAT THIS DOES: pure privilege change. Three REVOKEs (plus idempotent
-- re-assertions of the creation-time public/anon revokes, and of the
-- service_role grants so this file documents the intended end state by
-- itself). NO function body is modified. Legitimate callers keep working:
--   * Edge Function import  -> service_role EXECUTE (kept below)
--   * auth.users triggers   -> definer (owner) EXECUTE, unaffected by grants
--   * teacher registration  -> teacher_signup_global / teacher_signup_multi
--                              keep their authenticated grant and their
--                              0031 domain gate, byte-for-byte unchanged.
--
-- This matches the house pattern already used by upsert_activity_from_source
-- (migration 0023): service-context RPCs are granted to service_role only.
--
-- Verified by tests/rpc_authorization_test.sql (T01–T10).
-- ============================================================================

begin;

-- F1: legacy single-group teacher signup — no live caller; close the door.
revoke execute on function public.teacher_signup(uuid, integer, uuid, uuid)
  from authenticated;

-- F2: Classroom course import — Edge Function (service role) only.
revoke execute on function public.import_student_classroom_courses(uuid, jsonb)
  from authenticated;

-- F3: student course enrollment — auth.users triggers (definer) only.
revoke execute on function public.enroll_student_courses(uuid, uuid, integer, uuid, jsonb)
  from authenticated;

-- Legitimate service paths stay open (idempotent re-assertion of 0027's
-- grants so this migration fully documents the intended end state):
grant execute on function public.import_student_classroom_courses(uuid, jsonb)
  to service_role;
grant execute on function public.enroll_student_courses(uuid, uuid, integer, uuid, jsonb)
  to service_role;

-- Belt and braces: the creation-time revokes, re-asserted (idempotent).
revoke execute on function public.teacher_signup(uuid, integer, uuid, uuid)
  from public, anon;
revoke execute on function public.import_student_classroom_courses(uuid, jsonb)
  from public, anon;
revoke execute on function public.enroll_student_courses(uuid, uuid, integer, uuid, jsonb)
  from public, anon;

commit;
