-- ============================================================================
-- Student Codex — RPC EXECUTE authorization tests (migration 0032, security
-- audit findings F1/F2/F3). Plain SQL, same harness as policies_test.sql:
-- DO blocks with assertions; identity is simulated the Supabase way (role
-- switch + request.jwt.claims, exactly what PostgREST provides). Run once
-- against a freshly migrated database (supabase test db / psql / the
-- Dashboard SQL Editor on a throwaway project).
--
-- Test map:
--   T01–T03  an ordinary authenticated session can NO LONGER directly
--            invoke teacher_signup (F1), import_student_classroom_courses
--            (F2) or enroll_student_courses (F3);
--   T04      anon AND authenticated hold no EXECUTE privilege on the three
--            RPCs — PUBLIC inheritance included;
--   T05      the ACTIVE teacher-registration doors keep working:
--            authenticated still executes teacher_signup_global and
--            teacher_signup_multi (their grants and 0031 domain gates are
--            untouched by 0032);
--   T06      the trusted service path keeps working: service_role still
--            executes the Classroom import and student enrollment RPCs;
--   T07      the student sign-up door is intact end-to-end: inserting an
--            auth.users row with school details + course codes (what
--            GoTrue does at sign-up) still aligns the profile AND creates
--            the course enrollments via the handle_new_user trigger —
--            the definer context EXECUTE revokes cannot touch;
--   T08      the Classroom import door is intact end-to-end as the service
--            role (the Edge Function's exact call), including the
--            idempotent re-run, the external_course_id link and the
--            resulting enrollment;
--   T09      the 0031 school-email domain gate is unchanged: a non-
--            @parsu.edu.ph caller is rejected (SCHOOL_EMAIL_REQUIRED) by
--            BOTH active teacher RPCs and receives no role;
--   T10      a @parsu.edu.ph caller still succeeds on both active teacher
--            RPCs (role granted, profile aligned) — the live dashboard
--            registration flow, byte-for-byte.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Fixture (runs as postgres == service context: no JWT, bypasses RLS).
--   rpc_student — ordinary authenticated user (non-school email)
--   rpc_teacher — school-domain caller (mixed case: the gate is
--                 case-insensitive by design, migration 0031)
-- ----------------------------------------------------------------------------
do $fixture$
begin
  insert into auth.users (id, email, raw_user_meta_data) values
    ('f1000000-0000-4000-8000-0000000000a1', 'rpc.student@rpcaudit.test',
     '{"first_name":"Rpc","last_name":"Audit"}'),
    ('f1000000-0000-4000-8000-0000000000a2', 'rpc.teacher@ParSU.edu.ph',
     '{"first_name":"Thea","last_name":"Parsu"}')
  on conflict (id) do nothing;
  -- on_auth_user_created has created their bare profiles rows.
end $fixture$;

-- ----------------------------------------------------------------------------
-- T01 — F1: authenticated can no longer invoke teacher_signup
-- ----------------------------------------------------------------------------
do $t01$
declare u uuid := 'f1000000-0000-4000-8000-0000000000a1';
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', u::text, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';

  begin
    perform public.teacher_signup(null::uuid, null::integer, null::uuid, null::uuid);
    raise exception 'T01 FAIL: authenticated must not execute teacher_signup';
  exception when insufficient_privilege then null; end;

  execute 'set local role postgres';
  perform set_config('request.jwt.claims', '', true);
end $t01$;

-- ----------------------------------------------------------------------------
-- T02 — F2: authenticated can no longer invoke import_student_classroom_courses
-- ----------------------------------------------------------------------------
do $t02$
declare u uuid := 'f1000000-0000-4000-8000-0000000000a1';
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', u::text, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';

  begin
    perform public.import_student_classroom_courses(null::uuid, null::jsonb);
    raise exception 'T02 FAIL: authenticated must not execute import_student_classroom_courses';
  exception when insufficient_privilege then null; end;

  execute 'set local role postgres';
  perform set_config('request.jwt.claims', '', true);
end $t02$;

-- ----------------------------------------------------------------------------
-- T03 — F3: authenticated can no longer invoke enroll_student_courses
-- ----------------------------------------------------------------------------
do $t03$
declare u uuid := 'f1000000-0000-4000-8000-0000000000a1';
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', u::text, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';

  begin
    perform public.enroll_student_courses(null::uuid, null::uuid, null::integer, null::uuid, null::jsonb);
    raise exception 'T03 FAIL: authenticated must not execute enroll_student_courses';
  exception when insufficient_privilege then null; end;

  execute 'set local role postgres';
  perform set_config('request.jwt.claims', '', true);
end $t03$;

-- ----------------------------------------------------------------------------
-- T04 — privilege audit: anon and authenticated hold no EXECUTE on any of
--       the three RPCs (has_function_privilege sees PUBLIC inheritance)
-- ----------------------------------------------------------------------------
do $t04$
begin
  if has_function_privilege('anon', 'public.teacher_signup(uuid, integer, uuid, uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.import_student_classroom_courses(uuid, jsonb)', 'EXECUTE')
     or has_function_privilege('anon', 'public.enroll_student_courses(uuid, uuid, integer, uuid, jsonb)', 'EXECUTE') then
    raise exception 'T04.1 FAIL: anon must hold no EXECUTE on the three RPCs';
  end if;
  if has_function_privilege('authenticated', 'public.teacher_signup(uuid, integer, uuid, uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.import_student_classroom_courses(uuid, jsonb)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.enroll_student_courses(uuid, uuid, integer, uuid, jsonb)', 'EXECUTE') then
    raise exception 'T04.2 FAIL: authenticated must hold no EXECUTE on the three RPCs (PUBLIC included)';
  end if;
end $t04$;

-- ----------------------------------------------------------------------------
-- T05 — the ACTIVE teacher registration doors stay open to authenticated
-- ----------------------------------------------------------------------------
do $t05$
begin
  if not has_function_privilege('authenticated', 'public.teacher_signup_global()', 'EXECUTE') then
    raise exception 'T05.1 FAIL: authenticated must still execute teacher_signup_global';
  end if;
  if not has_function_privilege('authenticated', 'public.teacher_signup_multi(jsonb)', 'EXECUTE') then
    raise exception 'T05.2 FAIL: authenticated must still execute teacher_signup_multi';
  end if;
end $t05$;

-- ----------------------------------------------------------------------------
-- T06 — the trusted service path stays open (Edge Function context)
-- ----------------------------------------------------------------------------
do $t06$
begin
  if not has_function_privilege('service_role', 'public.import_student_classroom_courses(uuid, jsonb)', 'EXECUTE') then
    raise exception 'T06.1 FAIL: service_role must still execute import_student_classroom_courses';
  end if;
  if not has_function_privilege('service_role', 'public.enroll_student_courses(uuid, uuid, integer, uuid, jsonb)', 'EXECUTE') then
    raise exception 'T06.2 FAIL: service_role must still execute enroll_student_courses';
  end if;
end $t06$;

-- ----------------------------------------------------------------------------
-- T07 — student sign-up door end-to-end: the auth.users INSERT trigger
--       (what GoTrue does at sign-up) still enrolls course codes
-- ----------------------------------------------------------------------------
do $t07$
declare
  prog uuid := (select id from public.programs
                where program_name = 'Bachelor of Science in Computer Science (BSCS)'
                limit 1);
  blk  uuid := (select id from public.year_sections where name = 'A' limit 1);
  newu uuid := gen_random_uuid();
begin
  insert into auth.users (id, email, raw_user_meta_data) values (
    newu, 'rpc.signup@rpcaudit.test',
    jsonb_build_object(
      'first_name', 'Sig', 'last_name', 'Nup',
      'program_id', prog::text,
      'year_level', '2',
      'year_section_id', blk::text,
      'course_codes', jsonb_build_array('CS 101')));

  if not exists (select 1 from public.profiles
                 where id = newu and program_id = prog
                   and year_level = 2 and year_section_id = blk) then
    raise exception 'T07.1 FAIL: sign-up trigger must align the profile school details';
  end if;
  if not exists (
    select 1
    from public.enrollments e
    join public.sections s on s.id = e.section_id
    join public.courses c on c.id = s.course_id
    where e.user_id = newu and e.role = 'student'
      and c.code = 'CS 101' and s.name like '% 2-A') then
    raise exception 'T07.2 FAIL: sign-up trigger must enroll course codes (CS 101 / BSCS 2-A)';
  end if;
end $t07$;

-- ----------------------------------------------------------------------------
-- T08 — Classroom import door end-to-end as the service role (the Edge
--       Function's exact call), including the idempotent re-run
-- ----------------------------------------------------------------------------
do $t08$
declare
  u uuid := 'f1000000-0000-4000-8000-0000000000a1';
  v_first jsonb;
  v_again jsonb;
  v_course uuid;
begin
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role service_role';

  select public.import_student_classroom_courses(
    u,
    jsonb_build_array(jsonb_build_object(
      'externalId', 'gc-rpc-audit-0001',
      'name', 'RPC Authorization Audit Fixture',
      'section', 'A'))
  ) into v_first;

  execute 'set local role postgres';

  if (v_first->>'enrolled')::int <> 1 then
    raise exception 'T08.1 FAIL: service import must enroll exactly 1 course, got %',
      v_first->>'enrolled';
  end if;
  if not (v_first->'created' @> '["RPC Authorization Audit Fixture"]'::jsonb) then
    raise exception 'T08.2 FAIL: service import must create the unknown course';
  end if;

  select id into v_course from public.courses
  where external_course_id = 'gc-rpc-audit-0001';
  if v_course is null then
    raise exception 'T08.3 FAIL: imported course must carry the external_course_id link';
  end if;
  if not exists (
    select 1 from public.enrollments e
    join public.sections s on s.id = e.section_id
    where e.user_id = u and s.course_id = v_course and e.role = 'student') then
    raise exception 'T08.4 FAIL: the student must be enrolled in the imported course';
  end if;

  -- The Edge Function retries safely: re-import is a no-op.
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role service_role';
  select public.import_student_classroom_courses(
    u,
    jsonb_build_array(jsonb_build_object(
      'externalId', 'gc-rpc-audit-0001',
      'name', 'RPC Authorization Audit Fixture',
      'section', 'A'))
  ) into v_again;
  execute 'set local role postgres';

  if (v_again->>'enrolled')::int <> 0 then
    raise exception 'T08.5 FAIL: re-import must be idempotent (enrolled=0), got %',
      v_again->>'enrolled';
  end if;
  if not (v_again->'matched' @> '["RPC Authorization Audit Fixture"]'::jsonb) then
    raise exception 'T08.6 FAIL: re-import should report the course as matched';
  end if;
end $t08$;

-- ----------------------------------------------------------------------------
-- T09 — the 0031 school-email domain gate is unchanged: non-school callers
--       are rejected by BOTH active teacher RPCs and receive no role
-- ----------------------------------------------------------------------------
do $t09$
declare
  u uuid := 'f1000000-0000-4000-8000-0000000000a1';
  prog uuid := (select id from public.programs
                where program_name = 'Bachelor of Science in Computer Science (BSCS)'
                limit 1);
  blk  uuid := (select id from public.year_sections where name = 'A' limit 1);
  v_ok boolean;
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', u::text, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';

  v_ok := false;
  begin
    perform public.teacher_signup_global();
    v_ok := true;
  exception when others then
    if sqlerrm not like 'SCHOOL_EMAIL_REQUIRED:%' then
      raise exception 'T09.1 FAIL: expected SCHOOL_EMAIL_REQUIRED, got %', sqlerrm;
    end if;
  end;
  if v_ok then
    raise exception 'T09.1 FAIL: teacher_signup_global must reject non-school emails';
  end if;

  v_ok := false;
  begin
    perform public.teacher_signup_multi(jsonb_build_array(
      jsonb_build_object('program_id', prog, 'year_level', 2, 'year_section_id', blk)));
    v_ok := true;
  exception when others then
    if sqlerrm not like 'SCHOOL_EMAIL_REQUIRED:%' then
      raise exception 'T09.2 FAIL: expected SCHOOL_EMAIL_REQUIRED, got %', sqlerrm;
    end if;
  end;
  if v_ok then
    raise exception 'T09.2 FAIL: teacher_signup_multi must reject non-school emails';
  end if;

  execute 'set local role postgres';
  perform set_config('request.jwt.claims', '', true);

  if exists (select 1 from public.user_roles where user_id = u and role = 'teacher') then
    raise exception 'T09.3 FAIL: rejected callers must receive no teacher role';
  end if;
end $t09$;

-- ----------------------------------------------------------------------------
-- T10 — a @parsu.edu.ph caller still succeeds on both active teacher RPCs
--       (the live dashboard registration flow)
-- ----------------------------------------------------------------------------
do $t10$
declare
  u uuid := 'f1000000-0000-4000-8000-0000000000a2';
  prog uuid := (select id from public.programs
                where program_name = 'Bachelor of Science in Computer Science (BSCS)'
                limit 1);
  blk  uuid := (select id from public.year_sections where name = 'A' limit 1);
  v_ret integer;
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', u::text, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';

  -- The 0020/0031 sign-up flow.
  select public.teacher_signup_global() into v_ret;
  if v_ret <> 1 then
    raise exception 'T10.1 FAIL: teacher_signup_global should return 1, got %', v_ret;
  end if;

  -- The legacy-payload activation path (mixed-case domain still matches).
  select public.teacher_signup_multi(jsonb_build_array(
    jsonb_build_object('program_id', prog, 'year_level', 2, 'year_section_id', blk)))
    into v_ret;
  if v_ret < 1 then
    raise exception 'T10.2 FAIL: teacher_signup_multi should match the demo cohort sections, got %', v_ret;
  end if;

  execute 'set local role postgres';
  perform set_config('request.jwt.claims', '', true);

  if not exists (select 1 from public.user_roles where user_id = u and role = 'teacher') then
    raise exception 'T10.3 FAIL: the school-domain caller must receive the teacher role';
  end if;
  if not exists (select 1 from public.profiles
                 where id = u and program_id = prog and year_section_id = blk) then
    raise exception 'T10.4 FAIL: teacher_signup_multi must align the profile (first group)';
  end if;
end $t10$;

-- ----------------------------------------------------------------------------
-- Done
-- ----------------------------------------------------------------------------
select 'ALL RPC AUTHORIZATION TESTS PASSED' as result;
