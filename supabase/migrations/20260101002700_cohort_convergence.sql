-- ============================================================================
-- Student Codex migration 0027 — COHORT COURSE CONVERGENCE
--
-- WHY (user report, 2026-10-29): a student who imported their Google
-- Classroom courses ends up with course rows whose CODE is the full GC
-- name, e.g. "CC4 - Data Structures and Algorithms 2026-2027". A classmate
-- of the SAME cohort (same program/year/block) who types the short form
-- ("CC4", "CC4 - Data Structures and Algorithms") matches nothing exactly,
-- so enroll_student_courses creates a PARALLEL course row + a parallel
-- cohort section — and the classmate never sees the imported schoolwork,
-- because activity visibility is per section_id row (RLS). One student's
-- sync should cover the whole cohort.
--
-- HOW (three coordinated changes; NO data pass — the live registry was
-- audited 2026-10-29 and contains no divergent twins to merge):
--   1. course_text_matches(typed, code, title) — shared fuzzy matcher:
--      token-subset comparison in BOTH directions (typed tokens ⊆ course
--      tokens or course tokens ⊆ typed tokens). Tokens are alphanumeric
--      runs ≥3 chars; pure digits and stop-words are dropped from the
--      typed side. "CC4" ↔ "CC4 - Data Structures and Algorithms
--      2026-2027" match in both directions; "CC42"/"MEET"/"GE7" do not.
--   2. enroll_student_courses gains a fuzzy tier between the exact-code
--      match and course creation: a typed entry that RESEMBLES an existing
--      course enrolls into that course (its cohort section) instead of
--      creating a parallel row. Such codes are reported in the new
--      'fuzzy_matched' return array.
--   3. import_student_classroom_courses gains (a) the same fuzzy tier as
--      import Tier 2b — a GC course whose name resembles an existing
--      manual course LINKS that row instead of creating a parallel one —
--      and (b) a cohort-section preference: when the importer needs an
--      enrollment, the section is resolved/created under the importer's
--      COHORT name ("BSCS 2-B" — same formula as the manual path, now the
--      shared cohort_section_name() helper) instead of the Google section
--      label, so manual and imported members converge on ONE section row.
--      The GC label remains the fallback when the importer has no cohort.
--
-- KNOWN LIMITS (deliberate, honest):
--   * Pre-existing differently-spelled twins are NOT merged (none exist
--     today); the exact tier still wins for exact text, and a later import
--     links only the longest-candidate row.
--   * A GC course serving multiple cohorts still writes one activity row
--     whose section follows the latest syncer (unchanged upsert semantics).
--   * Fuzzy matching needs ≥1 significant (≥3-char, non-digit, non-stop-
--     word) token; "GE 6"-style entries keep today's create behavior.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Shared helpers
-- ---------------------------------------------------------------------------

create or replace function public.course_text_matches(p_typed text, p_code text, p_title text)
returns boolean
language sql immutable as $$
  with typed as (
    select coalesce(array_agg(tok), '{}'::text[]) as toks
    from (
      select btrim(tok) as tok
      from unnest(regexp_split_to_array(lower(coalesce(p_typed, '')), '[^a-z0-9]+')) tok
    ) s
    where char_length(tok) >= 3
      and tok !~ '^[0-9]+$'
      and tok not in ('and', 'or', 'the', 'for', 'nor', 'but', 'not', 'its',
                       'yet', 'are', 'was', 'has', 'had', 'with', 'from')
  ), course as (
    select coalesce(array_agg(tok), '{}'::text[]) as toks
    from (
      select btrim(tok) as tok
      from unnest(
        regexp_split_to_array(lower(coalesce(p_code, '')), '[^a-z0-9]+')
        || regexp_split_to_array(lower(coalesce(p_title, '')), '[^a-z0-9]+')
      ) tok
    ) s
    where char_length(tok) >= 3
      and tok !~ '^[0-9]+$'
  )
  select cardinality(typed.toks) > 0
    and cardinality(course.toks) > 0
    and (typed.toks <@ course.toks or course.toks <@ typed.toks)
  from typed, course
$$;

comment on function public.course_text_matches(text, text, text) is
  'Fuzzy course-text matcher: token-subset in either direction (typed ⊆ course or course ⊆ typed); tokens are alnum runs >=3 chars, pure digits and stop-words dropped from the typed side. Conservative by design: no substring/prefix guessing.';

create or replace function public.cohort_section_name(
  p_program uuid,
  p_year integer,
  p_block_id uuid
) returns text
language sql stable as $$
  select left(
           coalesce(
             nullif(substring(pr.program_name from '\(([^)]+)\)\s*$'), ''),
             nullif(btrim(pr.program_name), ''),
             'CLASS'
           ), 72)
         || ' ' || p_year::text || '-' || coalesce(ys.name, '?')
  from (select 1) dummy
  left join public.programs pr on pr.id = p_program
  left join public.year_sections ys on ys.id = p_block_id
$$;

comment on function public.cohort_section_name(uuid, integer, uuid) is
  'Cohort section name ("BSCS 2-B"): program short name (else full, else CLASS) + year + block. The single source of the naming convention both the manual sign-up path and the Classroom import path create sections under.';

revoke execute on function public.course_text_matches(text, text, text) from public;
revoke execute on function public.cohort_section_name(uuid, integer, uuid) from public;
grant execute on function public.course_text_matches(text, text, text) to authenticated, service_role;
grant execute on function public.cohort_section_name(uuid, integer, uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. enroll_student_courses v3 — fuzzy resolution tier before creation
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

  -- The cohort comes from the student's own school details. Without year +
  -- block there is nothing to create or match against — report and exit.
  if p_year is null or p_block_id is null then
    return jsonb_build_object(
      'enrolled', 0, 'matched', to_jsonb(v_matched),
      'unknown', to_jsonb(v_unknown), 'no_section', to_jsonb(v_no_section),
      'invalid', to_jsonb(v_invalid), 'fuzzy_matched', to_jsonb(v_fuzzy),
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
  v_section_name := public.cohort_section_name(p_program, p_year, p_block_id);

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
    -- Kept from migration 0021: a course entry is the WHOLE course name —
    -- letters, digits, spaces and the punctuation real course titles use.
    if v_code !~ '^[A-Za-z0-9][A-Za-z0-9 .,:;()/&+\-]{0,159}$' then
      v_invalid := v_invalid || v_code;
      continue;
    end if;

    -- serialize creation per code: concurrent sign-ups typing 'CC1'/'cc1'
    -- must converge on ONE course, and unique(code,title) is case-SENSITIVE
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('courses:' || upper(v_code)));

    -- Tier 1: the course behind the code (case-insensitive; the student's
    -- own program wins if the same code is listed under several programs).
    select c.id into v_course
    from public.courses c
    where upper(btrim(c.code)) = upper(v_code)
    order by (c.program_id = p_program) desc nulls last, c.code
    limit 1;

    -- Tier 2 (NEW): the course the typed entry RESEMBLES. A classmate
    -- typing "CC4" or "CC4 - Data Structures and Algorithms" while the
    -- imported course row is "CC4 - Data Structures and Algorithms
    -- 2026-2027" converges on THAT row (and its cohort section) instead
    -- of creating a parallel course nobody else sees. Longest candidate
    -- code wins = the most specific match.
    if v_course is null then
      select c.id into v_course
      from public.courses c
      where public.course_text_matches(v_code, c.code, c.title)
      order by (c.program_id = p_program) desc nulls last,
               char_length(c.code) desc, c.code
      limit 1;
      if v_course is not null then
        v_fuzzy := v_fuzzy || v_code;
      end if;
    end if;

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
        order by (c.program_id = p_program) desc nulls last, c.code
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
        values (v_course, v_section_name)
        returning id into v_section;
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
    'fuzzy_matched', to_jsonb(v_fuzzy),
    'created_courses', to_jsonb(v_created_courses),
    'created_sections', to_jsonb(v_created_sections)
  );
end $$;

revoke execute on function public.enroll_student_courses(uuid, uuid, integer, uuid, jsonb) from public, anon;
grant execute on function public.enroll_student_courses(uuid, uuid, integer, uuid, jsonb) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. import_student_classroom_courses v2 — fuzzy Tier 2b + cohort sections
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
  v_sections_created integer := 0;
begin
  if p_user is null then
    raise exception 'import_student_classroom_courses: missing user';
  end if;

  -- Newly-created courses attach to the student's program so they show
  -- up in that program's catalog. Null for legacy rows is fine. The year +
  -- block name the COHORT section preference below.
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

    -- Resolution tier 1: the row already carries this external id.
    select c.id into v_course
    from public.courses c
    where c.external_course_id = v_ext
    limit 1;

    if v_course is not null then
      v_matched := v_matched || v_name;
    end if;

    if v_course is null then
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
        v_resolved_by_name := true;
      end if;
    end if;

    if v_course is null then
      -- Resolution tier 2b (NEW): an existing course that RESEMBLES this
      -- Classroom course (token-subset, both directions) — a classmate
      -- typed "CC4" at sign-up while the GC course is "CC4 - Data
      -- Structures and Algorithms 2026-2027". Link it instead of creating
      -- a parallel row. Longest candidate code wins = most specific.
      select c.id, c.external_course_id into v_course, v_linked_existing
      from public.courses c
      where public.course_text_matches(v_name, c.code, c.title)
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
           or public.course_text_matches(v_name, c.code, c.title)
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

    -- NEW: the importer's COHORT section first. Resolving (or creating)
    -- the section under the same "BSCS 2-B" convention as the manual
    -- sign-up path means classmates who typed the short code converge on
    -- ONE section row with the importer — the shared calendar.
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
      order by
        (case when v_prog_short is null then false
              else s.name like v_prog_short || ' %' end) desc,
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
          order by
            (case when v_prog_short is null then false
                  else s.name like v_prog_short || ' %' end) desc,
            s.name
          limit 1;
        end;
      end if;
    end if;

    -- Fallback: the Classroom course's own section label, else the course
    -- name (importer has no cohort on their profile).
    if v_section is null then
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
-- Verify block (sandbox psql / Dashboard SQL Editor, as the service role):
--   select public.course_text_matches('CC4', 'CC4 - Data Structures and Algorithms 2026-2027', 'CC4 - Data Structures and Algorithms 2026-2027');  -- true
--   select public.course_text_matches('CC42', 'CC4 - Data Structures and Algorithms 2026-2027', 'CC4 - Data Structures and Algorithms 2026-2027'); -- false
--   select public.course_text_matches('and', 'CC4 - Data Structures and Algorithms 2026-2027', 'CC4 - Data Structures and Algorithms 2026-2027');  -- false (stop-word)
-- ---------------------------------------------------------------------------
