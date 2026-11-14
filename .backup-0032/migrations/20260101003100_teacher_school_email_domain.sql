-- ============================================================================
-- Student Codex migration 0031 — TEACHER GATE: SCHOOL EMAIL DOMAIN
-- (@parsu.edu.ph), replacing the verified-email gate
--
-- Product decision (2026-10-29, pre-presentation): email confirmation is
-- turned OFF on the project, so self-service teacher sign-up needs a new
-- proof of eligibility. The school issues every teacher a
-- @parsu.edu.ph address, so the domain IS the credential:
--
--   * teacher_signup_global / teacher_signup_multi now require the
--     CALLER's auth.users.email to end with '@parsu.edu.ph'
--     (case-insensitive suffix match; forged JWT claims are irrelevant —
--     the address is read from the table, exactly as 0030 read
--     email_confirmed_at).
--   * 0030's email_confirmed_at gate is RETIRED by this migration. With
--     confirmations off, GoTrue auto-confirms every sign-up, so that gate
--     had become a no-op; the domain check is the real gate now. If
--     confirmations are ever switched back on, the emailed click still
--     verifies the address, but teacher eligibility is decided by the
--     domain alone.
--
-- Match semantics: lower(email) LIKE '%@parsu.edu.ph'
--   * 'hollman@parsu.edu.ph'          -> allowed
--   * 'Hollman@PARSU.EDU.PH'          -> allowed (case-insensitive)
--   * 'hollman@gmail.com'             -> rejected
--   * 'x@notparsu.edu.ph'             -> rejected (the @ must sit right
--     before the domain — subdomain and look-alike tricks fail)
--   * 'x@sub.parsu.edu.ph'            -> rejected (exact suffix only)
--
-- COMPANION SETTING (dashboard/CLI, same day): Authentication -> Sign In /
-- Providers -> Email -> "Confirm email" switched OFF, via
-- `supabase config push` with [auth.email] enable_confirmations = false.
-- Sign-up then issues a session immediately (no email sent at all, so the
-- built-in mailer's 2/hour quota is never touched) and the dashboard walks
-- straight through: create account -> grant teacher role -> dashboard.
-- If confirmations are ever switched back ON, sign-ups park on the
-- confirm-email waiting card as before; the domain alone decides teacher
-- eligibility either way.
--
-- Everything else in both functions is byte-for-byte the pre-0031 logic
-- (session gate, payload validation, idempotent role grant, enrollment
-- matching, profile alignment).
--
-- Error surface: SCHOOL_EMAIL_REQUIRED: ... — the teacher dashboard maps
-- it to "Teacher accounts are for @parsu.edu.ph school email addresses."
-- ============================================================================

begin;

create or replace function public.teacher_signup_global()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
begin
  -- Gate: a signed-in session is required (the dashboard signs up, then
  -- finishes the grant; the anon key alone can never call this).
  if v_uid is null then
    raise exception 'Sign in before signing up as a teacher';
  end if;

  -- 0031: eligibility = the caller's email is on the school's staff
  -- domain. Read from auth.users (definer rights), never from JWT claims
  -- — with confirmations off the address is auto-verified by GoTrue at
  -- sign-up, so the domain suffix is the single gate.
  if not exists (
    select 1 from auth.users u
    where u.id = v_uid
      and lower(u.email) like '%@parsu.edu.ph'
  ) then
    raise exception 'SCHOOL_EMAIL_REQUIRED: teacher access is for @parsu.edu.ph school email addresses - sign up with your school email';
  end if;

  -- Teacher role only: no campus/program/year/block choice, no profile
  -- alignment, no enrollments. Visibility comes from activities_select
  -- (teachers read all non-personal activities university-wide).
  -- granted_by is intentionally null - self-service signup (same
  -- deliberate product decision as migrations 0013/0016).
  insert into public.user_roles (user_id, role)
  values (v_uid, 'teacher')
  on conflict (user_id, role) do nothing;

  return 1;
end $function$;


create or replace function public.teacher_signup_multi(p_groups jsonb)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_count integer;
  v0 jsonb;
  v0_program uuid;
  v0_year integer;
  v0_block_id uuid;
  v0_campus uuid;
  v_program uuid;
  v_year integer;
  v_block_id uuid;
  v_campus uuid;
  v_block text;
  v_matched integer := 0;
  v_total integer := 0;
  r record;
begin
  -- Gate: a signed-in session is required.
  if v_uid is null then
    raise exception 'Sign in before signing up as a teacher';
  end if;

  -- 0031: same school-domain gate as teacher_signup_global.
  if not exists (
    select 1 from auth.users u
    where u.id = v_uid
      and lower(u.email) like '%@parsu.edu.ph'
  ) then
    raise exception 'SCHOOL_EMAIL_REQUIRED: teacher access is for @parsu.edu.ph school email addresses - sign up with your school email';
  end if;

  -- Payload shape: a non-empty array of class groups (12 max - see header).
  if p_groups is null or jsonb_typeof(p_groups) <> 'array' then
    raise exception 'p_groups must be a JSON array of class groups';
  end if;
  v_count := jsonb_array_length(p_groups);
  if v_count < 1 then
    raise exception 'Add at least one class group';
  end if;
  if v_count > 12 then
    raise exception 'A teacher account can list up to 12 class groups';
  end if;

  -- Teacher role: granted_by is intentionally null - self-service signup
  -- (same deliberate product decision as migration 0013).
  insert into public.user_roles (user_id, role)
  values (v_uid, 'teacher')
  on conflict (user_id, role) do nothing;

  -- Profile alignment target: FIRST submitted group = primary affiliation.
  -- Extracted here, applied AFTER every group validates (see below) so a
  -- bad payload can never half-write the profile.
  v0 := p_groups->0;
  v0_program := nullif(v0->>'program_id', '');
  v0_year := nullif(v0->>'year_level', '');
  v0_block_id := nullif(v0->>'year_section_id', '');
  v0_campus := nullif(v0->>'campus_id', '');

  -- Validate + enroll every distinct group. 'distinct' folds duplicate
  -- groups in the same payload; ON CONFLICT folds re-runs.
  for r in
    select distinct
      e->>'program_id' as program_id,
      e->>'year_level' as year_level,
      e->>'year_section_id' as year_section_id,
      nullif(e->>'campus_id', '') as campus_id
    from jsonb_array_elements(p_groups) e
  loop
    v_program := nullif(r.program_id, '')::uuid;
    v_year := nullif(r.year_level, '')::integer;
    v_block_id := nullif(r.year_section_id, '')::uuid;
    v_campus := nullif(r.campus_id, '')::uuid;

    -- Same registry validation as 0013, per group: dropdown values only.
    if v_program is null or not exists (select 1 from public.programs p where p.id = v_program) then
      raise exception 'Pick a valid program';
    end if;
    if v_year is null or not exists (select 1 from public.year_levels y where y.level = v_year) then
      raise exception 'Pick a valid year level';
    end if;
    if v_block_id is null or not exists (select 1 from public.year_sections s where s.id = v_block_id) then
      raise exception 'Pick a valid section';
    end if;
    if v_campus is not null and not exists (select 1 from public.campuses c where c.id = v_campus) then
      raise exception 'Invalid campus';
    end if;

    -- Section matching: course sections encode the cohort in their name
    -- ('BSCS 2-A' = BSCS, 2nd year, block A), so match on the
    -- '<year>-<block>' suffix of that program's sections.
    select name into v_block from public.year_sections where id = v_block_id;

    insert into public.enrollments (section_id, user_id, role)
    select s.id, v_uid, 'teacher'
    from public.sections s
    join public.courses c on c.id = s.course_id
    where c.program_id = v_program
      and s.name like '% ' || v_year::text || '-' || v_block
    on conflict (section_id, user_id) do nothing;

    select count(*) into v_matched
    from public.sections s
    join public.courses c on c.id = s.course_id
    where c.program_id = v_program
      and s.name like '% ' || v_year::text || '-' || v_block;

    v_total := v_total + v_matched;
  end loop;

  -- Profile: align with the first submitted group (primary affiliation).
  -- Campus left empty falls back to the program's own campus (0012 made
  -- every program row campus-specific). Every group has been validated by
  -- now, so this can only run on good data.
  update public.profiles
    set program_id = v0_program::uuid,
        year_level = v0_year::integer,
        campus_id = coalesce(v0_campus::uuid,
                             (select p.campus_id from public.programs p where p.id = v0_program::uuid)),
        year_section_id = v0_block_id::uuid
  where id = v_uid;

  return v_total;
end $function$;

-- Execute: authenticated callers only (auth.uid() + the domain gate do
-- the rest; anon stays revoked — fail closed, same pattern as 0028-0030).
revoke execute on function public.teacher_signup_global() from public, anon;
grant execute on function public.teacher_signup_global() to authenticated;
revoke execute on function public.teacher_signup_multi(jsonb) from public, anon;
grant execute on function public.teacher_signup_multi(jsonb) to authenticated;

commit;
