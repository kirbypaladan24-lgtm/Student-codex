-- ============================================================================
-- Student Codex migration 0024 - QUIZ TOKEN REGEX FIX + DATA PASS RE-RUN
--
-- 0023's classifier regex QUIZZES? only matched "QUIZZE"/"QUIZZES" and
-- never a bare "QUIZ", so titles like "2.4 Quiz 2" kept their fallback
-- category. The token is corrected here to QUI(ZZES?)? (quiz + quizzes),
-- and the idempotent reclassification pass from 0023 runs again so the
-- two quiz-titled rows the audit flagged land in the right category.
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
    when upper(coalesce(p_title, '')) ~ '(^|[^A-Z0-9])(QUI(ZZES?)?)([^A-Z0-9]|$)'
      then 'quiz'
    when p_fallback in ('assignment', 'quiz', 'exam', 'project', 'announcement', 'other')
      then p_fallback
    else 'other'
  end
$$;

revoke execute on function public.suggest_activity_category(text, text) from public;
grant execute on function public.suggest_activity_category(text, text) to service_role;

-- Same idempotent pass as 0023 (now catches the quiz-titled rows).
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
