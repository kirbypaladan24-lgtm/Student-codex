-- ============================================================================
-- Student Codex migration 0033 — COHORT COURSE ISOLATION
--
-- WHY (user report, 2026-11-04): students who chose courses while importing
-- from Google Classroom (or typing codes at sign-up) ended up with the COURSE
-- and SECTION of another program, year or block. The resolution tiers only
-- PREFERRED the student's own program in their ORDER BY — they never
-- RESTRICTED to it — so an exact/fuzzy name match could link the student to
-- a DIFFERENT program's course row, and the '%<year>-<block>' section lookup
-- could then land them in that program's similarly-suffixed section.
--
-- RULE (what this migration enforces): a student's courses are exactly
--   (a) courses their OWN program offers (or legacy program-neutral rows),
--   (b) the Google Classroom courses they import, and
--   (c) their enrollment always sits in THEIR OWN cohort section
--       ('<program short> <year>-<block>' — migration 0027's formula).
--
-- HOW (four coordinated changes):
--   1. section_in_foreign_cohort(name, own_short) — true when a section name
--      carries a DIFFERENT program's short prefix ('BSIT 2-A' seen by a
--      BSCS student). Programs sharing a short name (the same degree at two
--      campuses, migration 0012) are NOT foreign to each other, so campus
--      twins keep converging on one section.
--   2. enroll_student_courses v4 — the course tiers now RESTRICT to the
--      student's program (own rows first, legacy program-null rows allowed,
--      other programs NEVER linked by code or fuzzy match); the cohort
--      params coalesce from the profile row when the caller's metadata
--      lacks them; the section lookup excludes foreign-cohort sections and
--      prefers the exact cohort-formula name.
--   3. import_student_classroom_courses v3 — the same program restriction
--      for the exact-name (tier 2) and fuzzy (tier 2b) tiers. The exact
--      external-id tier (tier 1) stays GLOBAL on purpose: one Google class
--      is one course row by design (classmates of any program in the SAME
--      Google class converge on it, each with their own cohort section).
--      The cohort section lookup gets the same foreign-cohort exclusion,
--      and — the reported 'years mixed up' path — a student WITH a cohort
--      on their profile never falls back to the Classroom section label
--      anymore (the label is whatever cohort the teacher typed in Google,
--      not necessarily the importer's). Such courses are reported in the
--      new 'no_section' array instead of being enrolled into a wrong
--      cohort.
--   4. One-time repair — enrollments that are UNAMBIGUOUSLY cross-cohort
--      are deleted: student-role rows into sections whose name is another
--      program's cohort formula, or the own program's formula with the
--      wrong year/block, or a bare '<year>-<block>' label that is not the
--      student's own. Affected students simply re-add / re-import the
--      course — with the hardened doors above it then lands in their own
--      program + cohort section.
--
-- KNOWN LIMITS (deliberate, honest):
--   * The repair only judges formula-shaped section names; a teacher's
--     free-text section label cannot be validated against a cohort.
--   * Importers with NO school details on their profile still fall back to
--     the Classroom-label section — there is nothing to match against.
--   * The sign-up 'Add %s as a new course' row still accepts any typed
--     name; the server now scopes where it lands, so a mistyped foreign
--     name becomes the student's OWN program's course instead of a link
--     into another program's row.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Foreign-cohort section detector
-- ---------------------------------------------------------------------------

create or replace function public.section_in_foreign_cohort(
  p_section_name text,
  p_own_short text
) returns boolean
language sql stable as $$
  select exists (
    select 1
    from public.programs p
    where p_section_name like substring(p.program_name from '\(([^)]+)\)\s*$') || ' %'
      and substring(p.program_name from '\(([^)]+)\)\s*$') is distinct from p_own_short
  )
$$;

comment on function public.section_in_foreign_cohort(text, text) is
  'True when the section name carries a DIFFERENT program''s short prefix (e.g. "BSIT 2-A" seen by a "BSCS" student). Programs sharing a short name (same degree, two campuses) are not foreign to each other. A null own short makes every program-prefixed section foreign.';

revoke execute on function public.section_in_foreign_cohort(text, text) from public;
grant execute on function public.section_in_foreign_cohort(text, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. enroll_student_courses v4 — program-restricted tiers + own-cohort sections
-- ---------------------------------------------------------------------------

create or replace function public.enroll_student_courses(
  p_user uuid,
  p_program uuid,
  p_year integer,
  p_block_id uuid,
  p_codes jsonb
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_program uuid;
  v_year integer;
  v_block_id uuid;
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
  v_fuzzy text[] := '{}';
  v_created_courses text[] := '{}';
  v_created_sections text[] := '{}';
  r record;
begin
  if p_user is null then
    raise exception 'enroll_student_courses: missing user';
  end if;

  -- COHORT (0033): the caller's values win, but a gap (a Settings save whose
  -- metadata carries only the edited fields) now falls back to the PROFILE
  -- row instead of silently enrolling with no cohort at all. handle_new_user
  -- writes the profile before calling this, so sign-up benefits too.
  select coalesce(p_program, pr.program_id),
         coalesce(p_year, pr.year_level),
         coalesce(p_block_id, pr.year_section_id)
    into v_program, v_year, v_block_id
  from public.profiles pr
  where pr.id = p_user;

  -- Without year + block there is nothing to create or match against —
  -- report and exit.
  if v_year is null or v_block_id is null then
    return jsonb_build_object(
      'enrolled', 0, 'matched', to_jsonb(v_matched),
      'unknown', to_jsonb(v_unknown), 'no_section', to_jsonb(v_no_section),
      'invalid', to_jsonb(v_invalid), 'fuzzy_matched', to_jsonb(v_fuzzy),
      'created_courses', to_jsonb(v_created_courses),
      'created_sections', to_jsonb(v_created_sections),
      'skipped', 'no cohort'
    );
  end if;

  select name into v_block from public.year_sections where id = v_block_id;
  if v_block is null then
    raise exception 'enroll_student_courses: invalid block';
  end if;

  -- Program short name ('BSCS' from '… (BSCS)') doubles as the cohort
  -- prefix when a section has to be created; full name is the fallback.
  select substring(program_name from '\(([^)]+)\)\s*$'), btrim(program_name)
    into v_prog_short, v_prog_name
  from public.programs where id = v_program;
  v_section_name := public.cohort_section_name(v_program, v_year, v_block_id);

  -- Sorted by UPPER-cased code: deterministic order (same input = same
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
    if v_code !~ '^[A-Za-z0-9][A-Za-z0-9 .,:;()/&+\-]{0,159}$' then
      v_invalid := v_invalid || v_code;
      continue;
    end if;

    -- serialize creation per code: concurrent sign-ups typing 'CC1'/'cc1'
    -- must converge on ONE course, and unique(code,title) is case-SENSITIVE
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('courses:' || upper(v_code)));

    -- Tier 1 (0033: RESTRICTED, no longer a mere preference): the course
    -- behind the code, case-insensitive — the student's OWN program's rows
    -- plus legacy program-neutral rows only. A code that only exists under
    -- ANOTHER program is no longer linked; the student's own row is
    -- created below instead.
    select c.id into v_course
    from public.courses c
    where upper(btrim(c.code)) = upper(v_code)
      and (v_program is null or c.program_id is null or c.program_id = v_program)
    order by (c.program_id = v_program) desc nulls last, c.code
    limit 1;

    -- Tier 2: the course the typed entry RESEMBLES — same program scope.
    if v_course is null then
      select c.id into v_course
      from public.courses c
      where public.course_text_matches(v_code, c.code, c.title)
        and (v_program is null or c.program_id is null or c.program_id = v_program)
      order by (c.program_id = v_program) desc nulls last,
               char_length(c.code) desc, c.code
      limit 1;
      if v_course is not null then
        v_fuzzy := v_fuzzy || v_code;
      end if;
    end if;

    if v_course is null then
      begin
        insert into public.courses (program_id, code, title)
        values (v_program, v_code, v_code)
        returning id into v_course;
        v_created_courses := v_created_courses || v_code;
      exception when unique_violation then
        -- lost a creation race — take the winner's course, under the same
        -- program scope (the winner is a classmate of the same program).
        select c.id into v_course
        from public.courses c
        where upper(btrim(c.code)) = upper(v_code)
          and (v_program is null or c.program_id is null or c.program_id = v_program)
        order by (c.program_id = v_program) desc nulls last, c.code
        limit 1;
      end;
    end if;
    if v_course is null then
      v_unknown := v_unknown || v_code;
      continue;
    end if;

    -- The student's section of that course: the cohort suffix (' 2-A'),
    -- never one carrying ANOTHER program's short prefix (0033).
    select s.id into v_section
    from public.sections s
    where s.course_id = v_course
      and s.name like '% ' || v_year::text || '-' || v_block
      and not public.section_in_foreign_cohort(s.name, v_prog_short)
    order by
      (case when v_prog_short is null then false
            else s.name like v_prog_short || ' %' end) desc,
      (s.name = v_section_name) desc,
      s.name
    limit 1;

    if v_section is null then
      -- no own-cohort section yet -> create it under the same naming
      -- convention the teacher sweep matches ('BSCS 2-A')
      begin
        insert into public.sections (course_id, name)
        values (v_course, v_section_name)
        returning id into v_section;
        v_created_sections := v_created_sections || v_section_name;
      exception when unique_violation then
        null; -- lost a race; the re-select below finds the winner's row
      end;
      select s.id into v_section
      from public.sections s
      where s.course_id = v_course
        and s.name like '% ' || v_year::text || '-' || v_block
        and not public.section_in_foreign_cohort(s.name, v_prog_short)
      order by
        (case when v_prog_short is null then false
              else s.name like v_prog_short || ' %' end) desc,
        (s.name = v_section_name) desc,
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
    'fuzzy_matched', to_jsonb(v_fuzzy),
    'created_courses', to_jsonb(v_created_courses),
    'created_sections', to_jsonb(v_created_sections)
  );
end $$;

revoke execute on function public.enroll_student_courses(uuid, uuid, integer, uuid, jsonb) from public, anon;
grant execute on function public.enroll_student_courses(uuid, uuid, integer, uuid, jsonb) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. import_student_classroom_courses v3 — program-scoped name tiers,
--    cohort-strict sections, no Classroom-label fallback for cohort students
-- ---------------------------------------------------------------------------

create or replace function public.import_student_classroom_courses(
  p_user uuid,
  p_courses jsonb
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_program uuid;
  v_year integer;
  v_block_id uuid;
  v_block text;
  v_prog_short text;
  r record;
  v_ext text;
  v_name text;
  v_section_label text;
  v_course uuid;
  v_linked_existing text;
  v_resolved_by_name boolean;
  v_norm_name text;
  v_section_name text;
  v_section uuid;
  v_enrolled integer := 0;
  v_created text[] := '{}';
  v_linked text[] := '{}';
  v_matched text[] := '{}';
  v_invalid text[] := '{}';
  v_no_section text[] := '{}';
  v_sections_created integer := 0;
begin
  if p_user is null then
    raise exception 'import_student_classroom_courses: missing user';
  end if;

  -- The importer's cohort drives everything below: program-scoped name
  -- tiers, and the section every enrollment lands in.
  select program_id, year_level, year_section_id
    into v_program, v_year, v_block_id
  from public.profiles where id = p_user;

  select name into v_block from public.year_sections where id = v_block_id;
  select substring(program_name from '\(([^)]+)\)\s*$') into v_prog_short
  from public.programs where id = v_program;

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
    v_resolved_by_name := false;

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

    -- Resolution tier 1: the row already carries this external id. GLOBAL
    -- by design — one Google class is one course row; classmates of any
    -- program inside the SAME class converge on it, each in their own
    -- cohort section. A wrong row can only be here if an earlier import
    -- linked it — and tiers 2/2b below can no longer do that (0033).
    select c.id into v_course
    from public.courses c
    where c.external_course_id = v_ext
    limit 1;

    if v_course is not null then
      v_matched := v_matched || v_name;
    end if;

    if v_course is null then
      -- Resolution tier 2 (0033: program-scoped): an existing course that
      -- IS this Classroom course by normalised name — the student's own
      -- program's rows (or legacy program-neutral rows) only.
      select c.id, c.external_course_id into v_course, v_linked_existing
      from public.courses c
      where (
        upper(regexp_replace(c.code, '[^A-Za-z0-9]', '', 'g')) = v_norm_name
        or upper(regexp_replace(c.title, '[^A-Za-z0-9]', '', 'g')) = v_norm_name
      )
        and (v_program is null or c.program_id is null or c.program_id = v_program)
      order by (c.program_id = v_program) desc nulls last, c.code
      limit 1;
      if v_course is not null then
        v_resolved_by_name := true;
      end if;
    end if;

    if v_course is null then
      -- Resolution tier 2b (0033: program-scoped): an existing course that
      -- RESEMBLES this Classroom course (token-subset, both directions) —
      -- same scope: own program or program-neutral rows only. A lookalike
      -- from another program is no longer linked; a fresh row is created
      -- under the importer's program instead.
      select c.id, c.external_course_id into v_course, v_linked_existing
      from public.courses c
      where public.course_text_matches(v_name, c.code, c.title)
        and (v_program is null or c.program_id is null or c.program_id = v_program)
      order by (c.program_id = v_program) desc nulls last,
               char_length(c.code) desc, c.code
      limit 1;
      if v_course is not null then
        v_resolved_by_name := true;
      end if;
    end if;

    if v_course is not null and v_resolved_by_name then
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
    end if;

    if v_course is null then
      -- Resolution tier 3: nobody in the importer's program knows this
      -- course yet — create it under its Classroom name.
      begin
        insert into public.courses (program_id, code, title, external_course_id)
        values (v_program, v_name, v_name, v_ext)
        returning id into v_course;
        v_created := v_created || v_name;
      exception when unique_violation then
        -- lost a creation race: re-find whichever row won. The external-id
        -- arm must win when present; the name arms keep the program scope.
        select c.id into v_course
        from public.courses c
        where c.external_course_id = v_ext
           or (
             (v_program is null or c.program_id is null or c.program_id = v_program)
             and (
               upper(regexp_replace(c.code, '[^A-Za-z0-9]', '', 'g')) = v_norm_name
               or public.course_text_matches(v_name, c.code, c.title)
             )
           )
        order by (c.external_course_id = v_ext) desc, char_length(c.code) desc, c.code
        limit 1;
      end;
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

    -- The importer's COHORT section — resolved or created under the same
    -- 'BSCS 2-B' convention as the manual sign-up path, and never a
    -- section that carries ANOTHER program's short prefix (0033).
    v_section := null;
    v_section_name := null;
    if v_year is not null and v_block is not null then
      v_section_name := public.cohort_section_name(v_program, v_year, v_block_id);
      perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtext('gc-section:' || v_course::text || ':' || upper(v_section_name)));
      select s.id into v_section
      from public.sections s
      where s.course_id = v_course
        and s.name like '% ' || v_year::text || '-' || v_block
        and not public.section_in_foreign_cohort(s.name, v_prog_short)
      order by
        (case when v_prog_short is null then false
              else s.name like v_prog_short || ' %' end) desc,
        (s.name = v_section_name) desc,
        s.name
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
          where s.course_id = v_course
            and s.name like '% ' || v_year::text || '-' || v_block
            and not public.section_in_foreign_cohort(s.name, v_prog_short)
          order by
            (case when v_prog_short is null then false
                  else s.name like v_prog_short || ' %' end) desc,
            (s.name = v_section_name) desc,
            s.name
          limit 1;
        end;
      end if;
    end if;

    -- Fallback: the Classroom course's own section label, else the course
    -- name — ONLY for importers with no cohort on their profile (0033).
    -- A student whose year + block are known must land in their own cohort
    -- section, never in a Google label that belongs to whatever cohort the
    -- teacher typed in Classroom. When the cohort section could not be
    -- resolved or created, the course is reported under 'no_section'
    -- instead of being enrolled wrong.
    if v_section is null and (v_year is null or v_block is null) then
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
    end if;

    if v_section is null then
      v_no_section := v_no_section || v_name;
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
    'no_section', to_jsonb(v_no_section),
    'sectionsCreated', v_sections_created
  );
end $$;

revoke execute on function public.import_student_classroom_courses(uuid, jsonb) from public, anon;
grant execute on function public.import_student_classroom_courses(uuid, jsonb) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. One-time repair — drop UNAMBIGUOUSLY cross-cohort enrollments
--
--    Only student-role rows whose section name is cohort-formula-shaped:
--      * '<short> <year>-<block>' where <short> is ANOTHER program's short
--        (another program's cohort section), or
--      * '<short> <year>-<block>' with the OWN short but a year/block that
--        is not the student's (the 'mixed up years' report), or
--      * a bare '<year>-<block>' label that is not the student's own.
--    Teacher rows, students without complete profile cohorts, and any
--    free-text section name are left untouched.
-- ---------------------------------------------------------------------------

do $$
declare
  v_removed integer;
begin
  with doomed as (
    select e.id
    from public.enrollments e
    join public.sections s on s.id = e.section_id
    join public.profiles pr on pr.id = e.user_id
    join public.programs pg on pg.id = pr.program_id
    join public.year_sections ys on ys.id = pr.year_section_id
    where e.role = 'student'
      and pr.program_id is not null
      and pr.year_level is not null
      and pr.year_section_id is not null
      and (
        -- another program's cohort-formula section
        (
          s.name ~ '^[A-Za-z0-9]+ [0-9]+-[A-Za-z0-9]+$'
          and exists (
            select 1 from public.programs p2
            where substring(p2.program_name from '\(([^)]+)\)\s*$')
                  = split_part(s.name, ' ', 1)
          )
          and substring(pg.program_name from '\(([^)]+)\)\s*$')
              is distinct from split_part(s.name, ' ', 1)
        )
        -- own program's formula, wrong year/block
        or (
          s.name ~ '^[A-Za-z0-9]+ [0-9]+-[A-Za-z0-9]+$'
          and substring(pg.program_name from '\(([^)]+)\)\s*$')
              = split_part(s.name, ' ', 1)
          and s.name is distinct from
              public.cohort_section_name(pr.program_id, pr.year_level, pr.year_section_id)
        )
        -- bare '<year>-<block>' label that is not the student's own
        or (
          s.name ~ '^[0-9]+-[A-Za-z0-9]+$'
          and s.name is distinct from pr.year_level::text || '-' || ys.name
        )
      )
  )
  delete from public.enrollments e
  using doomed d
  where e.id = d.id;

  get diagnostics v_removed = row_count;
  raise notice 'migration 0033: removed % cross-cohort enrollment row(s)', v_removed;
end $$;

commit;

-- ---------------------------------------------------------------------------
-- Verify block (sandbox psql / Dashboard SQL Editor, as the service role):
--   -- 1. own-program exact code still links:
--   select public.enroll_student_courses('<student>', '<own-program-uuid>', 2, '<block-A-uuid>',
--     '["CC 101"]'::jsonb);                       -- matched contains CC 101
--   -- 2. a code that exists ONLY under another program no longer links —
--   --    it becomes a new course under the student's own program:
--   select public.enroll_student_courses('<student>', '<own-program-uuid>', 2, '<block-A-uuid>',
--     '["FOREIGN-ONLY-CODE"]'::jsonb);            -- created_courses contains it
--   -- 3. the foreign-section detector:
--   select public.section_in_foreign_cohort('BSIT 2-A', 'BSCS');  -- true
--   select public.section_in_foreign_cohort('BSCS 2-A', 'BSCS');  -- false
--   select public.section_in_foreign_cohort('BSCS 2-A', null);    -- true
--   -- 4. a cohort-complete importer never lands in the Classroom label:
--   select public.import_student_classroom_courses('<student>',
--     '[{"externalId":"test-gc-1","name":"CC 101","section":"BSIT 3-A"}]'::jsonb);
--   --    -> enrolled in '<own short> 2-A', never 'BSIT 3-A'
-- ---------------------------------------------------------------------------
