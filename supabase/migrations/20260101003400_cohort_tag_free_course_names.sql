-- ============================================================================
-- Student Codex migration 0034 — COHORT-TAG-FREE COURSE NAMES
--
-- WHY (user report, 2026-11-05): a student who picked "GE6 BSCS 2A" in the
-- Google Classroom import ended up with the course "GE6 BSCS 2B" after
-- finalizing. The Google course names carry the teacher's cohort label —
-- "GE6 BSCS 2A" and "GE6 BSCS 2B" are the SAME subject for two blocks —
-- and the resolution tiers glued every block's import onto ONE row: the
-- exact tier compares whole names ("GE6BSCS2A" <> "GE6BSCS2B"), but the
-- fuzzy tier (course_text_matches) drops sub-3-char tokens, so the "2A"/
-- "2B" discriminators vanished and the FIRST importer's tagged row name
-- ("GE6 BSCS 2B") became EVERY importer's course name. The enrollment
-- section was already cohort-correct (0033) — the COURSE ROW NAME was the
-- wrong part, and the conflation kept producing it.
--
-- RULE (what this migration enforces): the COURSE row is the SUBJECT; the
-- cohort lives in the SECTION (migration 0027's '<short> <year>-<block>'
-- formula), never in the course name. A Google Classroom course name (or
-- a typed course entry) is cleaned of its cohort label BEFORE any tier
-- sees it, so every block's import converges on ONE subject row while
-- each student stays enrolled in their OWN cohort section:
--   strip_cohort_label('GE6 BSCS 2B')          -> 'GE6'
--   strip_cohort_label('GE6 BSCS 2A')          -> 'GE6'
--   strip_cohort_label('Numerical Methods-2A') -> 'Numerical Methods'
--   strip_cohort_label('26-1-NC1-BSCS2A')      -> '26-1-NC1'
--   strip_cohort_label('GEE3C')                -> 'GEE3C'  (a code, not a tag)
--
-- HOW (three coordinated changes):
--   1. strip_cohort_label(text) — strips a trailing school-year range, a
--      leading '<program short> <year><block>' prefix, and a trailing
--      '<year><block>' tag (with its optional program-short word). A tag
--      glued straight onto a NON-program word ("GEE3C") is a course code
--      and stays. Never returns an empty string.
--   2. import_student_classroom_courses v4 + enroll_student_courses v5 —
--      the CLEANED name drives every resolution tier and every creation;
--      the candidate side is compared through the same stripper so
--      not-yet-renamed tagged rows still converge.
--   3. One-time repair — rows imported from Classroom (external_course_id
--      set, code = title, the import-created shape) are renamed to their
--      cleaned name when the target name is free.
--
-- No enrollment, section or activity row is touched by the repair: only
-- course.code/title change (everything references courses by id).
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Cohort-label stripper (+ its program-short probe)
-- ---------------------------------------------------------------------------

create or replace function public.is_program_short(p_word text)
returns boolean
language sql stable set search_path = '' as $$
  select p_word is not null and btrim(p_word) <> '' and exists (
    select 1 from public.programs p
    where substring(p.program_name from '\(([^)]+)\)\s*$') = upper(btrim(p_word))
  )
$$;

comment on function public.is_program_short(text) is
  'True when the word is a program short name from the programs registry (case-insensitive) — "BSCS", "BSIT". Programs sharing a short (campus twins, migration 0012) all count.';

create or replace function public.strip_cohort_label(p_text text)
returns text
language plpgsql stable set search_path = '' as $$
declare
  v text := btrim(coalesce(p_text, ''));
  v_try text;
  v_word text;
begin
  if v = '' then return coalesce(p_text, ''); end if;

  -- (1) Trailing school-year range: 'CC4 - ... 2026-2027'. A 4-digit year
  --     is required, so term-ish codes ('26-1') never match.
  v_try := btrim(regexp_replace(v, '[ \-–—]+[0-9]{4}[ \-–—]+[0-9]{2,4}[[:space:]]*$', ''));
  if v_try <> '' and v_try is distinct from v then v := v_try; end if;

  -- (2) Leading '<program short><sep?><year><sep?><block><sep>' prefix:
  --     'BSCS 2A PATH-FIT3 ...' -> 'PATH-FIT3 ...'. Only a known program
  --     short may open the name this way ('Methods 2B ...' is untouched).
  v_word := coalesce((regexp_match(v, '^([A-Za-z]{3,8})[ \-–—]*[0-9][ \-–—]?[A-Za-z][ \-–—]'))[1], '');
  if v_word <> '' and public.is_program_short(v_word) then
    v_try := btrim(regexp_replace(v, '^[A-Za-z]{3,8}[ \-–—]*[0-9][ \-–—]?[A-Za-z][ \-–—]+', ''));
    if v_try <> '' then v := v_try; end if;
  end if;

  -- (3) Trailing '<year><block>' tag ('Methods-2A', 'BSCS 2B', 'Filipino 2 B').
  if v ~ '[0-9][ \-–—]?[A-Za-z]$' then
    if v ~ '[ \-–—][0-9][ \-–—]?[A-Za-z]$' then
      -- separated from the rest of the name: always a tag
      v_try := btrim(regexp_replace(v, '[ \-–—]*[0-9][ \-–—]?[A-Za-z]$', ''));
      if v_try <> '' then
        v := v_try;
        -- (3b) a dangling program short left behind: 'GE6 BSCS' -> 'GE6'
        v_word := coalesce((regexp_match(v, '[ \-–—]([A-Za-z]{2,8})$'))[1], '');
        if v_word <> '' and public.is_program_short(v_word) then
          v_try := btrim(regexp_replace(v, '[ \-–—]+[A-Za-z]{2,8}$', ''));
          if v_try <> '' then v := v_try; end if;
        end if;
      end if;
    else
      -- glued to the word before it ('BSCS2A'): only a program short may
      -- sit right before the year. 'GEE3C' ('GEE' is not a program) is a
      -- course code, not a tag — it keeps its full form.
      v_word := coalesce((regexp_match(v, '([A-Za-z]{2,8})[0-9][ \-–—]?[A-Za-z]$'))[1], '');
      if v_word <> '' and public.is_program_short(v_word) then
        v_try := btrim(regexp_replace(v, '[ \-–—]*[A-Za-z]{2,8}[0-9][ \-–—]?[A-Za-z]$', ''));
        if v_try <> '' then v := v_try; end if;
      end if;
    end if;
  end if;

  return v;
end $$;

comment on function public.strip_cohort_label(text) is
  'Cleans a course name of its cohort label: a trailing school-year range, a leading "<program short> <year><block>" prefix, and a trailing "<year><block>" tag with its optional program-short word. A tag glued onto a non-program word ("GEE3C") is a course code and stays. Never returns an empty string — an all-tag input keeps its raw form.';

revoke execute on function public.is_program_short(text) from public;
revoke execute on function public.strip_cohort_label(text) from public;
grant execute on function public.is_program_short(text) to authenticated, service_role;
grant execute on function public.strip_cohort_label(text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. enroll_student_courses v5 — the typed entry is cleaned before the tiers
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
  v_clean text;
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
  -- metadata carries only the edited fields) falls back to the PROFILE row.
  select coalesce(p_program, pr.program_id),
         coalesce(p_year, pr.year_level),
         coalesce(p_block_id, pr.year_section_id)
    into v_program, v_year, v_block_id
  from public.profiles pr
  where pr.id = p_user;

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

    -- 0034: the typed entry often carries the cohort label copied from a
    -- Google Classroom name ('GE6 BSCS 2A'). The COURSE is the SUBJECT —
    -- clean the label before any tier sees it; the section is the
    -- student's own cohort either way.
    v_clean := public.strip_cohort_label(v_code);

    -- serialize creation per code: concurrent sign-ups typing 'CC1'/'cc1'
    -- must converge on ONE course, and unique(code,title) is case-SENSITIVE
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('courses:' || upper(v_clean)));

    -- Tier 1 (0033 program-restricted, 0034 cleaned): the course behind
    -- the code, case-insensitive — the student's OWN program's rows plus
    -- legacy program-neutral rows only, with not-yet-renamed tagged rows
    -- ('GE6 BSCS 2B') still reachable through the stripper.
    select c.id into v_course
    from public.courses c
    where (upper(btrim(c.code)) = upper(v_clean)
           or upper(btrim(public.strip_cohort_label(c.code))) = upper(v_clean))
      and (v_program is null or c.program_id is null or c.program_id = v_program)
    order by (c.program_id = v_program) desc nulls last,
             (upper(btrim(c.code)) = upper(v_clean)) desc,
             char_length(c.code) desc, c.code
    limit 1;

    -- Tier 2: the course the typed entry RESEMBLES — same program scope,
    -- matched on the cleaned text.
    if v_course is null then
      select c.id into v_course
      from public.courses c
      where public.course_text_matches(v_clean, c.code, c.title)
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
        values (v_program, v_clean, v_clean)
        returning id into v_course;
        v_created_courses := v_created_courses || v_code;
      exception when unique_violation then
        -- lost a creation race — take the winner's course, under the same
        -- program scope and the same cleaned name.
        select c.id into v_course
        from public.courses c
        where (upper(btrim(c.code)) = upper(v_clean)
               or upper(btrim(public.strip_cohort_label(c.code))) = upper(v_clean))
          and (v_program is null or c.program_id is null or c.program_id = v_program)
        order by (c.program_id = v_program) desc nulls last,
                 (upper(btrim(c.code)) = upper(v_clean)) desc,
                 char_length(c.code) desc, c.code
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
-- 3. import_student_classroom_courses v4 — cleaned Classroom names
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
  v_clean_name text;
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

    -- 0034: the Google course name carries the teacher's cohort label
    -- ('GE6 BSCS 2A' / 'GE6 BSCS 2B' = one subject, two blocks). The
    -- COURSE is the SUBJECT: clean the label before any tier sees it, so
    -- every block's import converges on ONE row while each student lands
    -- in their OWN cohort section. The raw name is still what the reports
    -- carry (it is what the student picked in the app's picker).
    v_clean_name := public.strip_cohort_label(v_name);
    v_norm_name := upper(regexp_replace(v_clean_name, '[^A-Za-z0-9]', '', 'g'));

    -- Serialize per Classroom course: everyone importing this exact
    -- Classroom course converges on ONE row (the partial unique index
    -- enforces it; the lock avoids the throw/catch churn).
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('gc-course:' || v_ext));

    -- Resolution tier 1: the row already carries this external id. GLOBAL
    -- by design — one Google class is one course row; classmates of any
    -- program inside the SAME class converge on it, each in their own
    -- cohort section.
    select c.id into v_course
    from public.courses c
    where c.external_course_id = v_ext
    limit 1;

    if v_course is not null then
      v_matched := v_matched || v_name;
    end if;

    if v_course is null then
      -- Resolution tier 2 (0033 program-scoped, 0034 cleaned): an existing
      -- course that IS this Classroom course by normalised name — the
      -- student's own program's rows (or legacy program-neutral rows)
      -- only, with tagged rows compared through the stripper too.
      select c.id, c.external_course_id into v_course, v_linked_existing
      from public.courses c
      where (
        upper(regexp_replace(c.code, '[^A-Za-z0-9]', '', 'g')) = v_norm_name
        or upper(regexp_replace(public.strip_cohort_label(c.code), '[^A-Za-z0-9]', '', 'g')) = v_norm_name
        or upper(regexp_replace(c.title, '[^A-Za-z0-9]', '', 'g')) = v_norm_name
        or upper(regexp_replace(public.strip_cohort_label(c.title), '[^A-Za-z0-9]', '', 'g')) = v_norm_name
      )
        and (v_program is null or c.program_id is null or c.program_id = v_program)
      order by (c.program_id = v_program) desc nulls last,
               (public.strip_cohort_label(c.code) = v_clean_name) desc,
               char_length(c.code) desc, c.code
      limit 1;
      if v_course is not null then
        v_resolved_by_name := true;
      end if;
    end if;

    if v_course is null then
      -- Resolution tier 2b (0033 program-scoped, 0034 cleaned): an
      -- existing course that RESEMBLES this Classroom course
      -- (token-subset, both directions) — same scope, matched on the
      -- cleaned text.
      select c.id, c.external_course_id into v_course, v_linked_existing
      from public.courses c
      where public.course_text_matches(v_clean_name, c.code, c.title)
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
      -- course yet — create it under its cleaned Classroom name.
      begin
        insert into public.courses (program_id, code, title, external_course_id)
        values (v_program, v_clean_name, v_clean_name, v_ext)
        returning id into v_course;
        v_created := v_created || v_name;
      exception when unique_violation then
        -- lost a creation race: re-find whichever row won. The external-id
        -- arm must win when present; the name arms keep the program scope
        -- and the cleaned name.
        select c.id into v_course
        from public.courses c
        where c.external_course_id = v_ext
           or (
             (v_program is null or c.program_id is null or c.program_id = v_program)
             and (
               upper(regexp_replace(c.code, '[^A-Za-z0-9]', '', 'g')) = v_norm_name
               or public.course_text_matches(v_clean_name, c.code, c.title)
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

    -- Fallback: the Classroom course's own section label, else the
    -- cleaned course name — ONLY for importers with no cohort on their
    -- profile (0033). A student whose year + block are known must land in
    -- their own cohort section, never in a Google label that belongs to
    -- whatever cohort the teacher typed in Classroom.
    if v_section is null and (v_year is null or v_block is null) then
      v_section_name := left(coalesce(v_section_label, v_clean_name), 80);
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
-- 4. One-time repair — rename import-created course rows to their cleaned
--    name. Only rows the import door itself created (external_course_id
--    set and code = title) are touched; teacher catalog rows keep their
--    names. Skipped when the cleaned name is already taken (converging
--    imports resolve the rest through the tiers above) or when a sibling
--    row would map onto the same cleaned name.
-- ---------------------------------------------------------------------------

do $$
declare
  v_renamed integer;
begin
  with doomed as (
    select c.id
    from public.courses c
    where c.external_course_id is not null
      and c.code = c.title
      and (public.strip_cohort_label(c.code) <> c.code
           or public.strip_cohort_label(c.title) <> c.title)
      -- target not already in use by another row
      and not exists (
        select 1 from public.courses c2
        where c2.id <> c.id
          and c2.code = public.strip_cohort_label(c.code)
          and c2.title = public.strip_cohort_label(c.title)
      )
      -- no sibling import row would rename onto the same target
      and not exists (
        select 1 from public.courses c3
        where c3.id <> c.id
          and c3.external_course_id is not null
          and c3.code = c3.title
          and public.strip_cohort_label(c3.code) = public.strip_cohort_label(c.code)
          and public.strip_cohort_label(c3.title) = public.strip_cohort_label(c.title)
          and (public.strip_cohort_label(c3.code) <> c3.code
               or public.strip_cohort_label(c3.title) <> c3.title)
      )
  )
  update public.courses c
     set code = public.strip_cohort_label(c.code),
         title = public.strip_cohort_label(c.title),
         updated_at = now()
  from doomed d
  where c.id = d.id;

  get diagnostics v_renamed = row_count;
  raise notice 'migration 0034: renamed % imported course row(s) to cohort-tag-free names', v_renamed;
end $$;

commit;

-- ---------------------------------------------------------------------------
-- Verify block (Dashboard SQL Editor / supabase db query, as the service role):
--   select public.strip_cohort_label('GE6 BSCS 2B');            -- GE6
--   select public.strip_cohort_label('GE6 BSCS 2A');            -- GE6
--   select public.strip_cohort_label('Numerical Methods-2A');   -- Numerical Methods
--   select public.strip_cohort_label('26-1-NC1-BSCS2A');        -- 26-1-NC1
--   select public.strip_cohort_label('26-1-SDF1-BSCS-2A');      -- 26-1-SDF1
--   select public.strip_cohort_label('GEE3C-BSCS2A');           -- GEE3C
--   select public.strip_cohort_label('GEE3C');                  -- GEE3C (code, not a tag)
--   select public.strip_cohort_label('GE7-Science, Technology, and Society');  -- unchanged
--   select public.strip_cohort_label('CC4 - Data Structures and Algorithms 2026-2027');
--                                                              -- CC4 - Data Structures and Algorithms
--   select public.strip_cohort_label('BSCS 2A PATH-FIT3 1st Semester 2026-2027');
--                                                              -- PATH-FIT3 1st Semester
--   select public.strip_cohort_label('GE6');                    -- GE6 (unchanged)
-- ---------------------------------------------------------------------------
