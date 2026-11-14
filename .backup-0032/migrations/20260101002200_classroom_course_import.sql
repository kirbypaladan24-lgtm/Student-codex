-- ============================================================================
-- Student Codex migration 0022 — CLASSROOM COURSE IMPORT
--
-- WHY: matching a Google Classroom course to the student's own course by
-- NAME alone (the classroom-sync Edge Function normalises and compares the
-- Classroom course name with the local course code/title) demands the
-- student types the whole course name exactly. Students know their
-- subjects by their Classroom names, so the app now offers IMPORT: pick
-- your Classroom courses once and the account is enrolled in them
-- directly — no typing, no matching guesswork.
--
-- THIS MIGRATION adds the import door:
--   * courses.external_course_id — the Google Classroom course id a row
--     was imported from (or got linked to). A partial unique index makes
--     the id a one-to-one link; classroom-sync prefers it as an EXACT
--     match tier ahead of the name heuristics;
--   * import_student_classroom_courses(p_user, p_courses) — the trusted,
--     idempotent RPC the classroom-import Edge Function calls with the
--     student's picked Classroom courses:
--       - course resolution, in order: exact external_id link > same
--         course by normalised name (linked) > brand-new course row
--         created under its Classroom name (attached to the student's
--         program);
--       - a student already enrolled anywhere in the course is left
--         alone (the common case: the sign-up chips already enrolled
--         them — this only adds the external link);
--       - otherwise the course's Classroom section (its own section
--         label, else the course name) is created/ensured and the
--         student enrolled as a student. Classmates importing the same
--         Classroom course converge on the same course + section rows.
--
-- No data changes: every existing course, section, enrollment and
-- activity row is untouched; short-code courses keep name-matching.
-- ============================================================================

begin;

-- 1. The Google Classroom course link.

alter table public.courses add column if not exists external_course_id text;

create unique index if not exists courses_external_course_id_key
  on public.courses (external_course_id) where external_course_id is not null;

comment on column public.courses.external_course_id is
  'Google Classroom course id when this row was imported from (or linked to) a Classroom course; classroom-sync matches it exactly.';

-- 2. The import door (same trust model as enroll_student_courses:
--    service-context only, SECURITY DEFINER, pinned search_path).

create or replace function public.import_student_classroom_courses(
  p_user uuid,
  p_courses jsonb
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_program uuid;
  r record;
  v_ext text;
  v_name text;
  v_section_label text;
  v_course uuid;
  v_linked_existing text;
  v_norm_name text;
  v_section_name text;
  v_section uuid;
  v_enrolled integer := 0;
  v_created text[] := '{}';
  v_linked text[] := '{}';
  v_matched text[] := '{}';
  v_invalid text[] := '{}';
  v_sections_created integer := 0;
begin
  if p_user is null then
    raise exception 'import_student_classroom_courses: missing user';
  end if;

  -- Newly-created courses attach to the student's program so they show
  -- up in that program's catalog. Null for legacy rows is fine.
  select program_id into v_program from public.profiles where id = p_user;

  -- Sorted by UPPER-CASED name: deterministic order (same input = same
  -- result) AND a global lock order, so two concurrent imports sharing
  -- courses can never deadlock on the advisory locks below.
  for r in
    select * from (
      select
        nullif(btrim(item->>'externalId'), '') as external_id,
        nullif(btrim(item->>'name'), '') as name,
        nullif(btrim(item->>'section'), '') as section_label
      from jsonb_array_elements(
        case when jsonb_typeof(p_courses) = 'array' then p_courses else '[]'::jsonb end
      ) as item
      limit 32
    ) d
    order by upper(coalesce(name, '')), coalesce(external_id, '')
  loop
    v_ext := r.external_id;
    v_name := r.name;
    v_section_label := r.section_label;

    -- Shape guards (the Edge Function pre-truncates; defense in depth).
    if v_ext is null or char_length(v_ext) > 64
       or v_name is null or char_length(v_name) > 160
       or (v_section_label is not null and char_length(v_section_label) > 80)
    then
      v_invalid := v_invalid || coalesce(v_name, v_ext, '?');
      continue;
    end if;

    -- Serialize per Classroom course: everyone importing this exact
    -- Classroom course converges on ONE row (the partial unique index
    -- enforces it; the lock avoids the throw/catch churn).
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('gc-course:' || v_ext));

    v_norm_name := upper(regexp_replace(v_name, '[^A-Za-z0-9]', '', 'g'));

    -- Resolution tier 1: the row already carries this external id.
    select c.id into v_course
    from public.courses c
    where c.external_course_id = v_ext
    limit 1;

    if v_course is not null then
      v_matched := v_matched || v_name;
    else
      -- Resolution tier 2: an existing course that IS this Classroom
      -- course by normalised name (the student added the full name by
      -- hand, or a classmate's import created it). Link it.
      select c.id, c.external_course_id into v_course, v_linked_existing
      from public.courses c
      where (
        upper(regexp_replace(c.code, '[^A-Za-z0-9]', '', 'g')) = v_norm_name
        or upper(regexp_replace(c.title, '[^A-Za-z0-9]', '', 'g')) = v_norm_name
      )
      order by (c.program_id = v_program) desc nulls last, c.code
      limit 1;

      if v_course is not null then
        if v_linked_existing is null then
          -- The guarded update keeps a name-twin already linked to a
          -- DIFFERENT Classroom course untouched (rare, but honest).
          update public.courses
             set external_course_id = v_ext, updated_at = now()
           where id = v_course and external_course_id is null;
          v_linked := v_linked || v_name;
        else
          v_matched := v_matched || v_name;
        end if;
      else
        -- Resolution tier 3: nobody knows this course yet — create it
        -- under its Classroom name (the app labels the field "Course
        -- name", and classroom-sync name-matches it exactly anyway).
        begin
          insert into public.courses (program_id, code, title, external_course_id)
          values (v_program, v_name, v_name, v_ext)
          returning id into v_course;
          v_created := v_created || v_name;
        exception when unique_violation then
          -- lost a creation race: re-find whichever row won.
          select c.id into v_course
          from public.courses c
          where c.external_course_id = v_ext
             or upper(regexp_replace(c.code, '[^A-Za-z0-9]', '', 'g')) = v_norm_name
          order by (c.external_course_id = v_ext) desc, c.code
          limit 1;
        end;
      end if;
    end if;

    if v_course is null then
      v_invalid := v_invalid || v_name;
      continue;
    end if;

    -- Already a member of this course somewhere (e.g. the sign-up chips
    -- enrolled the student in the cohort section): nothing left to do.
    if exists (
      select 1
      from public.enrollments e
      join public.sections s on s.id = e.section_id
      where s.course_id = v_course and e.user_id = p_user
    ) then
      continue;
    end if;

    -- The Classroom section of this course: the Classroom course's own
    -- section label, else the course name itself. Deterministic per
    -- Classroom course, so classmates converge on the same section row.
    v_section_name := left(coalesce(v_section_label, v_name), 80);

    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('gc-section:' || v_course::text || ':' || upper(v_section_name)));

    select s.id into v_section
    from public.sections s
    where s.course_id = v_course and s.name = v_section_name
    limit 1;

    if v_section is null then
      begin
        insert into public.sections (course_id, name)
        values (v_course, v_section_name)
        returning id into v_section;
        v_sections_created := v_sections_created + 1;
      exception when unique_violation then
        select s.id into v_section
        from public.sections s
        where s.course_id = v_course and s.name = v_section_name
        limit 1;
      end;
    end if;

    if v_section is null then
      v_invalid := v_invalid || v_name;
      continue;
    end if;

    insert into public.enrollments (section_id, user_id, role)
    values (v_section, p_user, 'student')
    on conflict (section_id, user_id) do nothing;
    if found then
      v_enrolled := v_enrolled + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'enrolled', v_enrolled,
    'created', to_jsonb(v_created),
    'linked', to_jsonb(v_linked),
    'matched', to_jsonb(v_matched),
    'invalid', to_jsonb(v_invalid),
    'sectionsCreated', v_sections_created
  );
end $$;

revoke execute on function public.import_student_classroom_courses(uuid, jsonb) from public, anon;
grant execute on function public.import_student_classroom_courses(uuid, jsonb) to authenticated, service_role;

commit;

-- ---------------------------------------------------------------------------
-- Verify block (Dashboard SQL Editor, as the service role):
--   select public.import_student_classroom_courses(
--     '<student-uuid>',
--     '[{"externalId":"gc-123","name":"CC4 Data Structure and Algorithm","section":"B"},
--            {"externalId":"gc-456","name":"Application Development and Implementation"}]'::jsonb);
-- gc-123 -> course CREATED (code=title=full name, external_course_id=gc-123),
--           section 'B', student enrolled
-- gc-456 -> course CREATED, section named after the course, enrolled
-- re-run -> enrolled=0, everything reported under 'matched' (idempotent).
-- ---------------------------------------------------------------------------
