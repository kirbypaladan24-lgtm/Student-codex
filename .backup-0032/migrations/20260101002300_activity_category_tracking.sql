-- ============================================================================
-- Student Codex migration 0023 - ACTIVITY CATEGORY TRACKING
--
-- The six Student Codex tracking categories (the same list the app and the
-- teacher dashboard filter on): assignment, quiz, exam, project,
-- announcement, other ("Activity" in the UI).
--
-- What this migration adds:
--   * suggest_activity_category(): a conservative, title-driven classifier
--     used wherever an activity enters the system from Google Classroom.
--     It only overrides the Classroom work-type mapping when the TITLE
--     clearly states a different deliverable (word-boundary tokens,
--     project > exam > quiz priority so "MIDTERM PROJECT" and "FINAL
--     PROJECT" stay projects). Unclear titles keep the work-type mapping
--     - they never default to assignment.
--   * activities.category_locked / category_locked_by: a teacher's manual
--     correction is recorded and PROTECTED - upsert_activity_from_source()
--     refreshes title/description/due dates on every re-sync but leaves a
--     locked tracking category alone.
--   * The raw Google Classroom resource type keeps living untouched in
--     activity_sources.source_meta->workType (requirement: the original
--     provider data never changes; only the tracking category moves).
--   * One-time, idempotent reclassification of existing activities whose
--     titles clearly indicate a better category (e.g. "MIDTERM PROJECT"
--     imported as an assignment becomes a project). Rows whose category
--     cannot be confidently determined are preserved as-is.
--
-- Nothing else changes: verification status, scope, visibility policies,
-- and the rest of the activity shape are untouched.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Teacher-correction tracking columns.
-- ---------------------------------------------------------------------------
alter table public.activities
  add column if not exists category_locked boolean not null default false;
alter table public.activities
  add column if not exists category_locked_by uuid references auth.users (id)
    on delete set null;

comment on column public.activities.category_locked is
  'True when a teacher manually corrected activity_type; later Google Classroom syncs refresh content but never overwrite a locked tracking category.';
comment on column public.activities.category_locked_by is
  'Who set category_locked (stamped by trigger from auth.uid() on the false->true transition).';

-- ---------------------------------------------------------------------------
-- 2. The classifier. Pure, immutable, no table access.
--
--    Priority order matters: PROJECT beats EXAM so "Midterm Project" /
--    "Final Project" read as the deliverable they are; EXAM beats QUIZ so
--    "Exam Review Quiz" stays a quiz only when no exam token is present.
--    Announcements are a different Classroom resource entirely and are
--    never reclassified by coursework rules.
-- ---------------------------------------------------------------------------
create or replace function public.suggest_activity_category(p_title text, p_fallback text)
returns text
language sql immutable
as $$
  select case
    when p_fallback = 'announcement' then 'announcement'
    when upper(coalesce(p_title, '')) ~ '(^|[^A-Z0-9])(PROJECTS?|CAPSTONE|MACHINE[ -]?PROBLEMS?|MACHINE[ -]?PROJECTS?)([^A-Z0-9]|$)'
      then 'project'
    when upper(coalesce(p_title, '')) ~ '(^|[^A-Z0-9])(EXAMS?|MID[ -]?TERMS?|FINALS|FINAL[ -]?EXAMS?|FINAL[ -]?EXAMINATIONS?|PRELIMINARY|PRELIMS?)([^A-Z0-9]|$)'
      then 'exam'
    when upper(coalesce(p_title, '')) ~ '(^|[^A-Z0-9])(QUIZZES?)([^A-Z0-9]|$)'
      then 'quiz'
    when p_fallback in ('assignment', 'quiz', 'exam', 'project', 'announcement', 'other')
      then p_fallback
    else 'other'
  end
$$;

revoke execute on function public.suggest_activity_category(text, text) from public;
grant execute on function public.suggest_activity_category(text, text) to service_role;

comment on function public.suggest_activity_category(text, text) is
  'Conservative title-driven tracking-category suggestion: only overrides the fallback when the title clearly names a project/exam/quiz deliverable; unclear titles keep the fallback (never defaulted to assignment).';

-- ---------------------------------------------------------------------------
-- 3. The trusted import RPC: classify on first import, respect teacher
--    corrections on every re-import. Signature is unchanged, so the
--    classroom-sync Edge Function and every existing caller keep working
--    without redeployment. Content (title/description/due) still refreshes
--    on re-sync; only a locked category is preserved.
-- ---------------------------------------------------------------------------
create or replace function public.upsert_activity_from_source(
  p_source_key text,
  p_provider text,
  p_external_course_id text,
  p_external_item_id text,
  p_requesting_user_id uuid,
  p_title text,
  p_description text,
  p_activity_type text,
  p_course_id uuid,
  p_section_id uuid,
  p_due_at timestamptz,
  p_estimated_effort_minutes integer,
  p_scope text,
  p_source_meta jsonb
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  existing_activity_id uuid;
begin
  if auth.uid() is not null then
    raise exception 'upsert_activity_from_source is a service-only operation';
  end if;
  if p_provider <> 'google_classroom' then
    raise exception 'this upsert path is for provider imports only';
  end if;

  select s.activity_id into existing_activity_id
  from public.activity_sources s
  where s.source_key = p_source_key;

  if existing_activity_id is not null then
    -- Retry/repeat import: refresh the canonical activity + evidence.
    -- The tracking category follows the classifier ONLY while no teacher
    -- has locked a manual correction; a locked category survives sync.
    update public.activities a
      set title = p_title,
          description = p_description,
          activity_type = case
            when a.category_locked then a.activity_type
            else public.suggest_activity_category(p_title, p_activity_type)
          end,
          course_id = p_course_id,
          section_id = p_section_id,
          due_at = p_due_at,
          estimated_effort_minutes = p_estimated_effort_minutes,
          scope = p_scope,
          updated_at = now()
      where a.id = existing_activity_id;

    update public.activity_sources s
      set source_meta = p_source_meta,
          updated_at = now()
      where s.source_key = p_source_key;

    return existing_activity_id;
  end if;

  -- First import of this provider item: create the canonical activity
  -- with the classified tracking category (the raw Classroom workType
  -- lives on in source_meta untouched).
  insert into public.activities (
    title, description, activity_type, course_id, section_id,
    due_at, estimated_effort_minutes, scope, verification_status,
    created_by_user_id
  ) values (
    p_title, p_description,
    public.suggest_activity_category(p_title, p_activity_type),
    p_course_id, p_section_id,
    p_due_at, p_estimated_effort_minutes, p_scope, 'imported',
    p_requesting_user_id
  )
  returning id into existing_activity_id;

  insert into public.activity_sources (
    activity_id, provider, external_course_id, external_item_id,
    source_key, reported_by_user_id, source_meta
  ) values (
    existing_activity_id, p_provider, p_external_course_id, p_external_item_id,
    p_source_key, p_requesting_user_id, p_source_meta
  );

  return existing_activity_id;
end $$;

revoke execute on function public.upsert_activity_from_source(
  text, text, text, text, uuid, text, text, text, uuid, uuid, timestamptz, integer, text, jsonb
) from public;
grant execute on function public.upsert_activity_from_source(
  text, text, text, text, uuid, text, text, text, uuid, uuid, timestamptz, integer, text, jsonb
) to service_role;

-- ---------------------------------------------------------------------------
-- 4. Guard: stamp WHO locked the category (service flips stay untouched).
--    Everything else in the guard is unchanged.
-- ---------------------------------------------------------------------------
create or replace function public.guard_activity_update() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  caller uuid := auth.uid();
begin
  if new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'activities.created_by_user_id is immutable';
  end if;
  -- A manual category correction locks the tracking category: stamp the
  -- corrector so the audit trail says who overrode the classifier.
  if new.category_locked and not old.category_locked and caller is not null then
    new.category_locked_by := caller;
  end if;
  if caller is null then
    return new; -- trusted service context
  end if;
  if new.verification_status is distinct from old.verification_status
     and new.verification_status in ('teacher-confirmed', 'imported') then
    if not (
      public.is_section_teacher(new.section_id)
      or public.is_section_teacher(old.section_id)
      or public.is_course_teacher(new.course_id)
      or public.is_course_teacher(old.course_id)
      or public.has_role('admin')
    ) then
      raise exception 'verification_status ''%'' can only be set by a teacher of the section/course or an admin', new.verification_status;
    end if;
  end if;
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- 5. One-time reclassification of existing activities (idempotent).
--
--    Only non-personal, non-deleted, unlocked rows whose titles CLEARLY
--    name a different deliverable move; everything else keeps its current
--    category (no defaulting to assignment). Re-running after the first
--    pass is a no-op because suggest() then equals the stored category.
--    Manual entries are included: the same conservative rule applies, and
--    teachers can always re-correct through the dashboard afterwards.
-- ---------------------------------------------------------------------------
with proposals as (
  select a.id,
         public.suggest_activity_category(a.title, a.activity_type) as proposed
  from public.activities a
  where a.deleted_at is null
    and a.scope <> 'personal'
    and a.category_locked = false
    and public.suggest_activity_category(a.title, a.activity_type) <> a.activity_type
)
update public.activities a
set activity_type = p.proposed,
    updated_at = now()
from proposals p
where a.id = p.id;
