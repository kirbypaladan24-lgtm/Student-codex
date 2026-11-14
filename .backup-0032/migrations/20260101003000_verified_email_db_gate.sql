-- ============================================================================
-- Student Codex migration 0030 - VERIFIED-EMAIL GATE FROM AUTH.USERS
--
-- WHY (2026-10-29): 0029 gated the teacher role RPCs on the JWT's
-- email_verified claim - but live probing of the hosted project shows its
-- GoTrue does NOT sign that claim into access tokens (payload keys: iss,
-- sub, aud, exp, iat, email, phone, app_metadata, user_metadata, role,
-- aal, amr, session_id, is_anonymous - no email_verified, for confirmed
-- and unconfirmed users alike). The claim gate can therefore never pass:
-- every teacher sign-up would park on the confirm-email card forever.
--
-- HOW: read the authoritative column instead. auth.users.email_confirmed_at
-- is NULL until the emailed Confirm button is consumed, non-NULL afterwards,
-- and exists in every GoTrue version ever shipped. A SECURITY DEFINER
-- function (owner postgres) reads auth.users the same way the Dashboard
-- SQL editor does. The JWT keeps exactly one job: identifying the caller
-- (auth.uid(), signature-verified by PostgREST) - claims about email state
-- are no longer trusted at all.
--
-- Guard semantics (fail closed):
--   * no session (anon, service key) -> rejected by the session gate;
--   * email_confirmed_at null (button not clicked yet) -> EMAIL_NOT_VERIFIED
--     so the dashboard routes to the confirm-email card;
--   * email_confirmed_at set -> grant. Re-grants stay idempotent: accounts
--     that already hold the teacher role never call these RPCs again.
--
-- PREREQUISITE (dashboard, not SQL): Authentication -> Sign In / Providers
-- -> Email -> "Confirm email" ON. With it OFF, GoTrue auto-confirms every
-- sign-up (email_confirmed_at set at creation, no email sent) and this gate
-- passes without proof - the switch IS the security boundary.
--
-- Scope: teacher_signup() from 0013 stays as-is - the dashboard stopped
-- calling it in 0020, so it has no reachable caller to protect.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- teacher_signup_global - 0020 flow, verified-email gate from auth.users
-- ---------------------------------------------------------------------------
create or replace function public.teacher_signup_global() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
begin
  -- Gate: a signed-in session is required (the dashboard signs up, then
  -- finishes the grant once the emailed Confirm button has been clicked;
  -- the anon key alone can never call this).
  if v_uid is null then
    raise exception 'Sign in before signing up as a teacher';
  end if;

  -- 0030: proof of email ownership = auth.users.email_confirmed_at, set by
  -- GoTrue the moment the emailed Confirm button is clicked. Read from the
  -- table (definer rights), NOT from JWT claims - this project's GoTrue
  -- does not sign email_verified into tokens (see header).
  if not exists (
    select 1 from auth.users u
    where u.id = v_uid and u.email_confirmed_at is not null
  ) then
    raise exception 'EMAIL_NOT_VERIFIED: teacher access needs a verified email - click the button in the email sent to your address, then continue in the dashboard';
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
end $$;

revoke execute on function public.teacher_signup_global() from public, anon;
grant execute on function public.teacher_signup_global() to authenticated;

-- ---------------------------------------------------------------------------
-- teacher_signup_multi - legacy pre-0020 activation, same gate
-- ---------------------------------------------------------------------------
create or replace function public.teacher_signup_multi(
  p_groups jsonb
) returns integer
language plpgsql security definer set search_path = '' as $$
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

  -- 0030: proof of email ownership - same auth.users lookup as
  -- teacher_signup_global.
  if not exists (
    select 1 from auth.users u
    where u.id = v_uid and u.email_confirmed_at is not null
  ) then
    raise exception 'EMAIL_NOT_VERIFIED: teacher access needs a verified email - click the button in the email sent to your address, then continue in the dashboard';
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
end $$;

-- Execute: authenticated callers only (auth.uid() inside does the rest).
revoke execute on function public.teacher_signup_multi(jsonb) from public, anon;
grant execute on function public.teacher_signup_multi(jsonb) to authenticated;

commit;

-- ---------------------------------------------------------------------------
-- Verify block (sandbox psql / Dashboard SQL Editor):
--   -- user whose email_confirmed_at is null -> EMAIL_NOT_VERIFIED
--   select public.teacher_signup_global();
--
--   -- user whose email_confirmed_at is set -> 1, role granted
--   select public.teacher_signup_global();
-- ---------------------------------------------------------------------------
