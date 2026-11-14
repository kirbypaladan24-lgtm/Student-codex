-- ============================================================================
-- Student Codex migration 0026 - ACTIVITY TITLE TOKEN + DATA PASS RE-RUN
--
-- Follow-up to 0023/0024/0025: the classifier recognized project / exam /
-- quiz deliverables but not ACTIVITY-titled ones, so Google Classroom
-- coursework named "Group activity" / "Group Activity No. 1" /
-- "Individual Activity" / "First Activity in OOP" kept the Classroom
-- work-type mapping (assignment) even though the title clearly names an
-- activity - the exact flaw reported on the teacher dashboard.
--
-- The token list gains ACTIVIT(Y|IES) (word-boundary matched, so
-- "Interactive" can never match) BELOW project/exam/quiz priority:
-- "Quiz Activity" stays a quiz and "Activity Project" stays a project,
-- announcements remain untouchable as before, and unclear titles still
-- keep the fallback mapping - nothing is ever defaulted to assignment.
--
-- The idempotent reclassification pass from 0023 runs again so the four
-- affected imported rows land in the Activity category (slug "other" -
-- the same category the Android app and the dashboard legend/filters
-- label "Activity"). Locked teacher corrections, personal rows and
-- announcements stay untouched, as designed.
-- ============================================================================

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
    when upper(coalesce(p_title, '')) ~ '(^|[^A-Z0-9])(QUIZ(ZES?)?)([^A-Z0-9]|$)'
      then 'quiz'
    when upper(coalesce(p_title, '')) ~ '(^|[^A-Z0-9])(ACTIVIT(Y|IES))([^A-Z0-9]|$)'
      then 'other'
    when p_fallback in ('assignment', 'quiz', 'exam', 'project', 'announcement', 'other')
      then p_fallback
    else 'other'
  end
$$;

revoke execute on function public.suggest_activity_category(text, text) from public;
grant execute on function public.suggest_activity_category(text, text) to service_role;

comment on function public.suggest_activity_category(text, text) is
  'Conservative title-driven tracking-category suggestion: overrides the fallback only when the title clearly names a project/exam/quiz/activity deliverable; unclear titles keep the fallback (never defaulted to assignment).';

-- Same idempotent pass as 0023/0024/0025 (now catches activity-titled rows).
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
