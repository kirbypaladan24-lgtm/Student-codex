-- ============================================================================
-- Student Codex migration 0021 — COURSE NAMES, NOT SHORT CODES
--
-- WHY: the Google Classroom sync (Edge Function classroom-sync) matches a
-- Classroom course to the student's own course by comparing the Classroom
-- course NAME (normalized: upper-cased, punctuation stripped) with the
-- local course code — an exact or starts-with match. Short registrar
-- codes ("CC4") only match when the Classroom name happens to START with
-- the code; in practice a Classroom course is named after the whole
-- subject ("Application Development and Implementation"), so the student
-- must enter the WHOLE course name. The app now labels the field
-- "Course name" and instructs exactly that.
--
-- THIS MIGRATION widens what a course entry may be:
--   * courses.code: 1..32 chars -> 1..160 chars (a full subject name fits;
--     the CHECK is re-created under a stable name courses_code_len);
--   * enroll_student_courses junk guard: letters/digits/spaces/hyphens
--     only -> letters, digits, spaces and the punctuation real course
--     names use: - ( ) . , : ; / & +
-- The app-side validator (SchoolDirectoryRepository.looksLikeCourseCode)
-- mirrors the same shape. Matching itself is UNCHANGED — the Edge
-- Function already strips punctuation on BOTH sides before comparing
-- (norm()), so punctuation in a stored course name cannot break a match.
--
-- No data changes: existing short-code courses keep working; every
-- existing enrollment, section and activity row is untouched.
-- ============================================================================

begin;

-- 1. Widen courses.code (the original CHECK was created unnamed in
--    migration 0002, so Postgres named it courses_code_check).
alter table public.courses drop constraint courses_code_check;
alter table public.courses add constraint courses_code_len
  check (char_length(code) between 1 and 160);

-- 2. Same enrollment door, relaxed name shape.

create or replace function public.enroll_student_courses(
  p_user uuid,
  p_program uuid,
  p_year integer,
  p_block_id uuid,
  p_codes jsonb
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_block text;
  v_prog_short text;
  v_prog_name text;
  v_section_name text;
  v_code text;
  v_course uuid;
  v_section uuid;
  v_enrolled integer := 0;
  v_matched text[] := '{}';
  v_unknown text[] := '{}';
  v_no_section text[] := '{}';
  v_invalid text[] := '{}';
  v_created_courses text[] := '{}';
  v_created_sections text[] := '{}';
  r record;
begin
  if p_user is null then
    raise exception 'enroll_student_courses: missing user';
  end if;

  -- The cohort comes from the student's own school details. Without year +
  -- block there is nothing to create or match against — report and exit.
  if p_year is null or p_block_id is null then
    return jsonb_build_object(
      'enrolled', 0, 'matched', to_jsonb(v_matched),
      'unknown', to_jsonb(v_unknown), 'no_section', to_jsonb(v_no_section),
      'invalid', to_jsonb(v_invalid),
      'created_courses', to_jsonb(v_created_courses),
      'created_sections', to_jsonb(v_created_sections),
      'skipped', 'no cohort'
    );
  end if;

  select name into v_block from public.year_sections where id = p_block_id;
  if v_block is null then
    raise exception 'enroll_student_courses: invalid block';
  end if;

  -- Program short name ('BSCS' from '… (BSCS)') doubles as the cohort
  -- prefix when a section has to be created; full name is the fallback.
  select substring(program_name from '\(([^)]+)\)\s*$'), btrim(program_name)
    into v_prog_short, v_prog_name
  from public.programs where id = p_program;
  v_section_name := left(coalesce(nullif(v_prog_short, ''), v_prog_name, 'CLASS'), 72)
                    || ' ' || p_year::text || '-' || v_block;

  -- Sorted by upper-cased code: deterministic order (same input = same
  -- result) AND a global lock order, so two concurrent sign-ups sharing
  -- two codes can never deadlock on the advisory locks below.
  for r in
    select code from (
      select distinct btrim(code_text) as code
      from jsonb_array_elements_text(
        case when jsonb_typeof(p_codes) = 'array' then p_codes else '[]'::jsonb end
      ) as code_text
      limit 32
    ) d
    order by upper(code)
  loop
    v_code := nullif(r.code, '');
    if v_code is null then continue; end if;

    -- junk guard (the app guards pre-submit too; defense in depth).
    -- Migration 0021: a course entry is now the WHOLE course name —
    -- the Google Classroom sync matches a Classroom course by its full
    -- name — so letters, digits, spaces and the punctuation real
    -- course titles use are all valid, up to 160 chars.
    if v_code !~ '^[A-Za-z0-9][A-Za-z0-9 .,:;()/&+\-]{0,159}$' then
      v_invalid := v_invalid || v_code;
      continue;
    end if;

    -- serialize creation per code: concurrent sign-ups typing 'CC1'/'cc1'
    -- must converge on ONE course, and unique(code,title) is case-SENSITIVE
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('courses:' || upper(v_code)));

    -- The course behind the code (case-insensitive; the student's own
    -- program wins if the same code is listed under several programs).
    select c.id into v_course
    from public.courses c
    where upper(btrim(c.code)) = upper(v_code)
    order by (c.program_id = p_program) desc, c.code
    limit 1;

    if v_course is null then
      begin
        insert into public.courses (program_id, code, title)
        values (p_program, v_code, v_code)
        returning id into v_course;
        v_created_courses := v_created_courses || v_code;
      exception when unique_violation then
        -- lost a creation race (lock guards case variants; this is the
        -- belt-and-braces path) — take the winner's course
        select c.id into v_course
        from public.courses c
        where upper(btrim(c.code)) = upper(v_code)
        order by (c.program_id = p_program) desc, c.code
        limit 1;
      end;
    end if;
    if v_course is null then
      v_unknown := v_unknown || v_code;
      continue;
    end if;

    -- The student's section of that course: the cohort suffix (' 2-A').
    select s.id into v_section
    from public.sections s
    where s.course_id = v_course
      and s.name like '% ' || p_year::text || '-' || v_block
    order by
      (case when v_prog_short is null then false
            else s.name like v_prog_short || ' %' end) desc,
      s.name
    limit 1;

    if v_section is null then
      -- no cohort section yet -> create it under the same naming
      -- convention the teacher sweep matches ('BSCS 2-A')
      begin
        insert into public.sections (course_id, name)
        values (v_course, v_section_name);
        v_created_sections := v_created_sections || v_section_name;
      exception when unique_violation then
        null; -- lost a race; the re-select below finds the winner's row
      end;
      select s.id into v_section
      from public.sections s
      where s.course_id = v_course
        and s.name like '% ' || p_year::text || '-' || v_block
      order by
        (case when v_prog_short is null then false
              else s.name like v_prog_short || ' %' end) desc,
        s.name
      limit 1;
    end if;
    if v_section is null then
      v_no_section := v_no_section || v_code;
      continue;
    end if;

    insert into public.enrollments (section_id, user_id, role)
    values (v_section, p_user, 'student')
    on conflict (section_id, user_id) do nothing;
    if found then
      v_enrolled := v_enrolled + 1;
    end if;
    v_matched := v_matched || v_code;
  end loop;

  return jsonb_build_object(
    'enrolled', v_enrolled,
    'matched', to_jsonb(v_matched),
    'unknown', to_jsonb(v_unknown),
    'no_section', to_jsonb(v_no_section),
    'invalid', to_jsonb(v_invalid),
    'created_courses', to_jsonb(v_created_courses),
    'created_sections', to_jsonb(v_created_sections)
  );
end $$;

revoke execute on function public.enroll_student_courses(uuid, uuid, integer, uuid, jsonb) from public, anon;
grant execute on function public.enroll_student_courses(uuid, uuid, integer, uuid, jsonb) to authenticated, service_role;

commit;

-- ---------------------------------------------------------------------------
-- Verify block (Dashboard SQL Editor):
--   select public.enroll_student_courses(
--     '<student-uuid>',
--     (select id from public.programs where program_name like '%Information Technology%' limit 1),
--     2, (select id from public.year_sections where name = 'A'),
--     '["Application Development and Implementation (IT 323)", "MEETING", "!!!"]'::jsonb);
-- "Application Development and Implementation (IT 323)" -> course CREATED
--   with the whole name as code+title, cohort section, enrolled
-- MEETING -> course created / matched, enrolled
-- !!!     -> reported in 'invalid', skipped (still junk)
-- re-run: enrolled=0, nothing duplicated (idempotent).
-- ---------------------------------------------------------------------------
