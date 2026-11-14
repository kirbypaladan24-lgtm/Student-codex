/* ============================================================================
   Student Codex — Teacher Dashboard (standalone WebView build)

   One self-contained file: auth gate (sign in / teacher sign-up), cohort
   filter bar, the month calendar (activities inside the day boxes), the
   read-only student-reported feed, and data coverage.

   The dashboard is VIEW-ONLY: teachers sign up, sign in and look. When a
   student reports a face-to-face class activity in the app it is published
   straight into `activities` (student-reported, section-scoped, cohort
   derived from the reporter's own enrollment) — it appears on this
   calendar immediately, with no confirmation queue anywhere.

   Security model — identical to the Android app:
   • talks to hosted Supabase with the PUBLISHABLE key only;
   • every read runs through the signed-in teacher's session;
   • row-level security decides what is visible (a teacher sees only the
     sections they are enrolled to teach; personal student activities never
     appear here).
   ========================================================================== */
(() => {
  'use strict';

  /* ================================ config ============================== */

  const SUPABASE_URL = 'https://wzhkfhijjwhteqkrlzfm.supabase.co';
  const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_hcIjy5in8ffyVf0IEzHruQ_rKfVWsfU';
  const DEMO_EMAIL = 'demo.teacher@studentcodex.app';
  const DEMO_PASSWORD = 'demo-teacher-123';
  const ALL = '__all__';

  const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const MONTH_NAMES = ['January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'];
  const MAX_CHIPS = 3;

  const ACTIVITY_COLUMNS = 'id, title, description, activity_type, course_id, section_id, due_at, estimated_effort_minutes, scope, verification_status, created_by_user_id, created_at, category_locked';

  const ACTIVITY_TYPES = ['assignment', 'quiz', 'exam', 'project', 'announcement', 'other'];
  const TYPE_META = {
    assignment: { label: 'Assignment', icon: 'clipboard-list' },
    quiz: { label: 'Quiz', icon: 'help-circle' },
    exam: { label: 'Exam', icon: 'calendar-check' },
    project: { label: 'Project', icon: 'briefcase' },
    announcement: { label: 'Announcement', icon: 'megaphone' },
    other: { label: 'Activity', icon: 'file-text' },
  };
  const VERIFICATION_META = {
    'teacher-confirmed': { label: 'Teacher-confirmed', icon: 'badge-check', cls: 'badge-verified' },
    imported: { label: 'Classroom-imported', icon: 'download', cls: 'badge-imported' },
    'student-reported': { label: 'Student-reported', icon: 'message-square', cls: 'badge-reported' },
    'needs-review': { label: 'Needs review', icon: 'help-circle', cls: 'badge-review' },
  };

  /* ============================== utilities ============================= */

  const $ = (sel, root = document) => root.querySelector(sel);

  function esc(v) {
    return String(v ?? '')
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function ic(name, cls = 'ic-4') {
    return `<i data-lucide="${name}" class="ic ${cls}" aria-hidden="true"></i>`;
  }

  function refreshIcons() {
    if (window.lucide && typeof window.lucide.createIcons === 'function') {
      window.lucide.createIcons();
    }
  }

  function typeMeta(t) { return TYPE_META[t] || TYPE_META.other; }
  function verificationMeta(status) { return VERIFICATION_META[status] || VERIFICATION_META['needs-review']; }

  function programShortName(programName) {
    if (!programName) return '';
    const parens = programName.match(/\(([^)]+)\)\s*$/);
    if (parens) return parens[1].trim();
    return programName.length > 24 ? programName.slice(0, 22).trimEnd() + '…' : programName;
  }

  function parseCohort(sectionName) {
    if (!sectionName) return { year: null, block: null };
    const m = sectionName.match(/(\d+)\s*[-–]\s*([A-Za-z0-9]+)\s*$/);
    if (!m) return { year: null, block: null };
    const year = Number.parseInt(m[1], 10);
    return { year: Number.isFinite(year) ? year : null, block: m[2].toUpperCase() };
  }

  function localDateKey(d) {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${y}-${m}-${day}`;
  }

  function activityDueKey(a) {
    if (!a.due_at) return null;
    const d = new Date(a.due_at);
    if (Number.isNaN(d.getTime())) return null;
    return localDateKey(d);
  }

  function effortLabel(minutes) {
    if (minutes == null || minutes <= 0) return null;
    const h = Math.floor(minutes / 60);
    const m = minutes % 60;
    if (h && m) return `${h}h ${m}m`;
    if (h) return `${h}h`;
    return `${m}m`;
  }

  function timeLabel(iso) {
    if (!iso) return null;
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return null;
    return d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
  }

  // Sheet-level due label: the activity sheet has no day context (unlike
  // the day dialog, which heads with the full date), so the DATE always
  // rides along - "due Today, 3:59 PM" / "due Oct 9, 3:59 PM". A past-due
  // entry no longer reads as if it were due today.
  function sheetDueLabel(iso) {
    if (!iso) return null;
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return null;
    const key = localDateKey(d);
    const todayKey = localDateKey(new Date());
    const datePart = key === todayKey
      ? 'Today'
      : d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
    const time = timeLabel(iso);
    return time ? `${datePart}, ${time}` : datePart;
  }

  function monthLabel({ year, month }) { return `${MONTH_NAMES[month]} ${year}`; }

  function ordinal(n) {
    const suffixes = ['th', 'st', 'nd', 'rd'];
    const v = n % 100;
    return n + (suffixes[(v - 20) % 10] ?? suffixes[v] ?? suffixes[0]);
  }

  function monthKeyString({ year, month }) {
    return `${year}-${String(month + 1).padStart(2, '0')}`;
  }

  function monthRange({ year, month }) {
    const from = new Date(year, month, 1, 0, 0, 0, 0);
    const to = new Date(year, month + 1, 0, 23, 59, 59, 999); // day 0 of next month
    return { fromIso: from.toISOString(), toIso: to.toISOString() };
  }

  function shiftMonth({ year, month }, delta) {
    const d = new Date(year, month + delta, 1);
    return { year: d.getFullYear(), month: d.getMonth() };
  }

  function initialsOf(name, email) {
    return String(name || email || '?')
      .split(/[\s@.]+/).filter(Boolean).slice(0, 2)
      .map((p) => (p[0] || '').toUpperCase()).join('') || 'T';
  }

  function friendlyAuthError(error) {
    const msg = (error && error.message) || 'Sign-in failed.';
    if (/invalid login credentials/i.test(msg)) return 'Incorrect email or password. Check your credentials and try again.';
    if (/email not confirmed/i.test(msg)) return 'This account has not confirmed its email yet — resend a confirmation link below, click it in your inbox, then sign in.';
    if (/rate limit/i.test(msg)) return 'Too many attempts. Please wait a moment and try again.';
    return msg;
  }

  function messageFromError(error) {
    if (!error) return 'Unknown error.';
    if (typeof error === 'string') return error;
    if (error instanceof Error) return error.message;
    if (typeof error === 'object' && typeof error.message === 'string' && error.message.length) return error.message;
    const detail = error.details ?? error.hint;
    if (typeof detail === 'string') return detail;
    try { return JSON.stringify(error); } catch { return 'Unknown error.'; }
  }

  /* =========================== supabase client ========================== */

  if (!window.supabase || typeof window.supabase.createClient !== 'function') {
    document.getElementById('app').innerHTML = `
      <div class="gate"><div class="alert alert-destructive">${ic('alert-triangle')}
        <div><p class="alert-title">Could not load the dashboard runtime</p>
        <p class="alert-desc">vendor/supabase.min.js failed to load. Make sure the whole WebView folder was copied.</p></div></div></div>`;
    return;
  }

  const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
    auth: { persistSession: true, autoRefreshToken: true },
  });

  /* ============================ school registry ========================= */

  let registryCache = null;
  let registryInflight = null;

  async function fetchRegistry() {
    if (registryCache) return registryCache;
    if (registryInflight) return registryInflight;
    registryInflight = (async () => {
      const [campusesRes, programsRes, levelsRes, blocksRes] = await Promise.all([
        sb.from('campuses').select('id, name, sort_order').order('sort_order'),
        sb.from('programs').select('id, program_name, campus_id').order('program_name'),
        sb.from('year_levels').select('level, label').order('level'),
        sb.from('year_sections').select('id, name, sort_order').order('sort_order'),
      ]);
      const firstError = campusesRes.error ?? programsRes.error ?? levelsRes.error ?? blocksRes.error;
      if (firstError) throw firstError;
      registryCache = {
        campuses: (campusesRes.data ?? []).map((c) => ({ id: c.id, name: c.name })),
        programs: (programsRes.data ?? []).map((p) => ({ id: p.id, programName: p.program_name, campusId: p.campus_id })),
        yearLevels: (levelsRes.data ?? []).map((y) => ({ level: y.level, label: y.label })),
        yearSections: (blocksRes.data ?? []).map((s) => ({ id: s.id, name: s.name })),
      };
      return registryCache;
    })();
    try { return await registryInflight; } finally { registryInflight = null; }
  }

  /* ================================= state ============================== */

  const now0 = new Date();

  const S = {
    stage: 'restoring',           // restoring|signin|checking|loading|ready|not-teacher
    sessionEmail: null,
    teacherName: null,
    sections: [],
    reporterProfiles: {},
    googleConnection: null,
    lastRefresh: null,
    loadError: null,
    pendingTeacherSignup: null,

    visibleMonth: { year: now0.getFullYear(), month: now0.getMonth() },
    monthActivities: [],
    monthLoading: false,

    filter: { campusId: null, programId: null, year: null, block: null },

    // searchable filter combos: one panel open at a time (axis); the
    // typed query and highlighted option live here so full re-renders
    // (auto-refresh, month jumps, picks) never lose them
    combo: { axis: null, query: '', hl: 0, focusAfter: null },

    // category filters driven by the interactive calendar legend: which
    // activity types are pinned (empty = all types) plus the two state
    // toggles (student-reported / past-due-done)
    typeFilter: [],
    flagFilter: { reported: false, past: false },

    // teacher-correctable categories: the sections/courses THIS teacher
    // is enrolled to teach (category corrections are offered only there)
    // and the in-flight guard for the category PATCH
    teacherSectionIds: new Set(),
    teacherCourseIds: new Set(),
    categoryBusy: false,

    registry: { campuses: [], programs: [], yearLevels: [], yearSections: [], },
    registryLoading: false,
    registryError: null,

    // auth view
    authMode: 'signin',
    // password reveal (eye) toggles, keyed by input id — full renders
    // restore the input type from here; tab switch / sign-out re-hide
    pwVisible: {},
    authDraft: {
      email: '', password: '', firstName: '', lastName: '',
    },
    authError: null,
    signinBusy: false,
    signupBusy: false,
    signupError: null,
    signupNeedsDbPush: false,
    signupNeedsConfirm: false,
    authNeedsConfirm: false,
    resendBusy: false,
    resendInfo: null,
    activateBusy: false,
    activateError: null,
  };

  let handledUid = null;
  let uid = null;
  const monthCache = new Map();
  /** Empty months already probed for neighbours — avoids repeat queries. */
  const probedEmptyMonths = new Set();
  /** activities currently shown on the calendar (filtered) — the day sheet
   *  must list exactly what the day cell shows */
  let visibleActivities = [];

  function render() {
    const app = $('#app');
    if (S.stage === 'restoring' || S.stage === 'checking') {
      app.innerHTML = gateHtml(S.stage === 'restoring' ? 'Restoring your session…' : 'Verifying teacher access…');
    } else if (S.stage === 'signin' || S.stage === 'loading') {
      app.innerHTML = authHtml();
    } else if (S.stage === 'not-teacher') {
      app.innerHTML = notTeacherHtml();
    } else {
      app.innerHTML = dashboardHtml();
    }
    refreshIcons();
    // searchable combos survive re-renders: an open panel's search box
    // re-takes focus (its query lives in S.combo), and the combo that
    // just picked an option hands focus back to its trigger
    if (S.combo.axis) {
      const comboInput = document.querySelector(`.combo[data-combo="${S.combo.axis}"] .combo-input`);
      if (comboInput) {
        comboInput.focus();
        comboInput.setSelectionRange(comboInput.value.length, comboInput.value.length);
      }
    } else if (S.combo.focusAfter) {
      const comboTrigger = document.querySelector(`.combo[data-combo="${S.combo.focusAfter}"] .combo-btn`);
      if (comboTrigger) comboTrigger.focus();
      S.combo.focusAfter = null;
    }
  }

  function gateHtml(text) {
    return `<div class="page"><div class="gate">
      <div class="spinner" role="status" aria-label="Loading"></div>
      <p>${esc(text)}</p>
    </div>${footerHtml()}</div>`;
  }

  function footerHtml() {
    return `<footer class="app-footer"><p>${ic('lock-keyhole', 'ic-3')}
      Student Codex — Teacher Dashboard · reads live data from Supabase with your session
      (row-level security enforced; publishable key only, never a service key)</p></footer>`;
  }

  /* ============================== auth views ============================ */

  function authHtml() {
    const d = S.authDraft;
    const busy = S.stage === 'loading';
    const signInMode = S.authMode === 'signin';

    return `<div class="page"><div class="auth-wrap"><div class="auth-col">
      <div class="brand-head">
        <div class="brand-badge">${ic('graduation-cap', 'ic-7')}</div>
        <h1>Student Codex — Teacher Dashboard</h1>
        <p>The university-wide calendar for assignments, quizzes, exams and announcements.</p>
      </div>

      <div class="auth-card">
        <div class="mode-tabs" role="tablist" aria-label="Sign in or create an account">
          <button type="button" role="tab" aria-selected="${signInMode}" class="mode-tab" data-action="auth-mode" data-mode="signin">Sign in</button>
          <button type="button" role="tab" aria-selected="${!signInMode}" class="mode-tab" data-action="auth-mode" data-mode="signup">Create teacher account</button>
        </div>

        <div class="auth-body">
          ${signInMode ? signInFormHtml(d, busy) : signUpFormHtml(d, busy)}
        </div>
      </div>
    </div></div>${footerHtml()}</div>`;
  }

  // Shown under the sign-in error / sign-up notice while an account is
  // waiting on an email confirmation: re-sends the confirmation email to
  // the address currently in the draft (both forms bind data-draft="email").
  function resendRowHtml() {
    const email = (S.authDraft.email || '').trim();
    const disabled = S.resendBusy || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
    return `<div style="margin-top:8px">
      <button type="button" class="btn btn-outline btn-xs" data-action="resend-confirmation" ${disabled ? 'disabled' : ''}>
        ${S.resendBusy ? '<span class="spinner spinner-sm" aria-hidden="true"></span> Sending…' : `${ic('mail', 'ic-3h')} Resend confirmation email`}
      </button>
      ${S.resendInfo ? `<p class="field-hint" role="status" style="margin:6px 0 0">${esc(S.resendInfo)}</p>` : ''}
    </div>`;
  }

  async function resendConfirmation() {
    const email = (S.authDraft.email || '').trim();
    if (!email || S.resendBusy) return;
    S.resendBusy = true; S.resendInfo = null; render();
    const { error } = await sb.auth.resend({ type: 'signup', email });
    S.resendBusy = false;
    S.resendInfo = error
      ? friendlyAuthError(error)
      : 'Confirmation email re-sent. Click the link in it (check spam too), then sign in below.';
    render();
  }

  /* ---- password reveal (eye) toggle ------------------------------------- */
  /* The eye button sits inside the password field's .pw-wrap. Its state
     lives in S.pwVisible so full re-renders (busy spinners, errors, demo
     fill) keep the field revealed if it was; tab switches and sign-out
     re-hide it (safe default). mousedown is prevented on the button so the
     caret never leaves the field mid-typing — the click still fires. */

  function pwType(inputId) {
    return S.pwVisible[inputId] ? 'text' : 'password';
  }

  function pwToggleHtml(inputId) {
    const shown = !!S.pwVisible[inputId];
    const label = shown ? 'Hide password' : 'Show password';
    return `<button type="button" class="pw-toggle" data-action="pw-toggle" data-pw="${inputId}"
      aria-label="${label}" aria-pressed="${shown}" title="${label}">${ic(shown ? 'eye-off' : 'eye', 'ic-4')}</button>`;
  }

  function resetPwVisible() {
    S.pwVisible = {};
  }

  function signInFormHtml(d, busy) {
    const submitting = S.signinBusy || busy;
    return `<form data-form="signin" novalidate>
      <label class="field"><span class="field-label" for="si-email">Email</span>
        <input id="si-email" class="input" type="email" data-draft="email" value="${esc(d.email)}" autocomplete="email" required></label>
      <label class="field"><span class="field-label" for="si-password">Password</span>
        <span class="pw-wrap">
          <input id="si-password" class="input" type="${pwType('si-password')}" data-draft="password" value="${esc(d.password)}" autocomplete="current-password" required>
          ${pwToggleHtml('si-password')}
        </span></label>

      ${(S.authError || S.loadError) ? `<p class="field-error" role="alert">${esc(S.authError || S.loadError)}</p>` : ''}
      ${S.authNeedsConfirm ? resendRowHtml() : ''}

      <div style="margin-top:16px">
        <button type="submit" class="btn btn-primary btn-block" ${submitting ? 'disabled' : ''}>
          ${submitting ? '<span class="spinner spinner-sm" aria-hidden="true"></span> Signing in…' : 'Sign in'}
        </button>
      </div>

      <div class="demo-box">
        <p>${ic('sparkles', 'ic-3')} Demo project — try the sample teacher:</p>
        <div style="margin-top:4px">
          <button type="button" class="btn btn-ghost btn-xs" data-action="fill-demo">Use demo teacher credentials</button>
        </div>
      </div>
    </form>`;
  }

  function canSubmitDraft(d) {
    return d.firstName.trim().length > 0 && d.lastName.trim().length > 0 &&
      d.email.trim().length > 3 && d.password.length >= 6;
  }

  function updateSignupSubmit(form) {
    const btn = form.querySelector('button[type="submit"]');
    if (!btn || S.signupBusy) return;
    btn.disabled = !canSubmitDraft(S.authDraft);
  }

  function signUpFormHtml(d, busy) {
    const submitting = S.signupBusy || busy;
    const canSubmit = !submitting && canSubmitDraft(d);

    return `<form data-form="signup" novalidate>
      <div class="grid-2">
        <label class="field"><span class="field-label" for="su-first">First name</span>
          <input id="su-first" class="input" data-draft="firstName" value="${esc(d.firstName)}" autocomplete="given-name" required></label>
        <label class="field"><span class="field-label" for="su-last">Last name</span>
          <input id="su-last" class="input" data-draft="lastName" value="${esc(d.lastName)}" autocomplete="family-name" required></label>
      </div>

      <label class="field"><span class="field-label" for="su-email">School email</span>
        <input id="su-email" class="input" type="email" data-draft="email" value="${esc(d.email)}" autocomplete="email" required></label>

      <label class="field"><span class="field-label" for="su-password">Password</span>
        <span class="pw-wrap">
          <input id="su-password" class="input" type="${pwType('su-password')}" data-draft="password" value="${esc(d.password)}" autocomplete="new-password" minlength="6" required>
          ${pwToggleHtml('su-password')}
        </span>
        <p class="field-hint">At least 6 characters.</p></label>

      <div class="cohort-box" style="margin-top:16px">
        <p class="box-title" style="margin-bottom:8px">No class setup needed</p>
        <p class="pick-note" style="margin:0">Once your account is active you'll see activities from every campus,
        program, year level, block and course in the university — narrow them down any time with the
        dashboard filters.</p>
      </div>

      ${S.registryError ? `<p class="field-error">Could not load the school registry: ${esc(S.registryError)}</p>` : ''}

      ${S.signupError ? `
        <div class="alert ${S.signupNeedsDbPush || S.signupNeedsConfirm ? '' : 'alert-destructive'}" style="margin-top:12px" role="alert">
          ${ic('user-plus')}
          <div>
            <p class="alert-title">${S.signupNeedsDbPush ? 'One more step' : S.signupNeedsConfirm ? 'Confirm your email' : 'Could not sign up'}</p>
            <p class="alert-desc">${esc(S.signupError)}</p>
          </div>
        </div>
        ${S.signupNeedsConfirm ? resendRowHtml() : ''}` : ''}

      <div style="margin-top:16px">
        <button type="submit" class="btn btn-primary btn-block" ${canSubmit ? '' : 'disabled'}>
          ${submitting ? '<span class="spinner spinner-sm" aria-hidden="true"></span> Creating your account…' : `${ic('log-in')} Create teacher account`}
        </button>
      </div>
    </form>`;
  }

  function notTeacherHtml() {
    return `<div class="page"><div class="gate" style="max-width:28rem;margin:0 auto">
      <div class="auth-col" style="max-width:none">
        <div class="alert" role="alert">
          ${ic('shield-question')}
          <div>
            <p class="alert-title">This account has no teacher access</p>
            <p class="alert-desc">You are signed in as <b>${esc(S.sessionEmail || '')}</b>${
              S.pendingTeacherSignup
                ? ' — your teacher sign-up is one step away from activation.'
                : '. Teacher accounts are created with the “Create teacher account” tab, or granted by an admin.'}</p>
          </div>
        </div>

        ${S.pendingTeacherSignup ? `
        <div class="card" style="margin-top:16px">
          <div class="card-body">
            <p class="card-title" style="margin:0;font-size:14px">Activate teacher access</p>
            <p style="margin:6px 0 0;font-size:12px;line-height:1.55;color:var(--muted-foreground)">
              This finishes your teacher sign-up: grants the teacher role and opens the university-wide
              calendar — every campus, program, year level and block, narrowed down with the dashboard filters.</p>
            ${S.activateError ? `<p class="field-error" role="alert">${esc(S.activateError)}</p>` : ''}
            <div style="margin-top:12px">
              <button type="button" class="btn btn-primary btn-block" data-action="activate-teacher" ${S.activateBusy ? 'disabled' : ''}>
                ${S.activateBusy ? '<span class="spinner spinner-sm" aria-hidden="true"></span> Activating…' : 'Activate teacher access'}
              </button>
            </div>
          </div>
        </div>` : ''}

        <div style="margin-top:16px">
          <button type="button" class="btn btn-outline btn-block" data-action="sign-out">
            ${ic('log-out', 'ic-3h')} Sign out and use another account
          </button>
        </div>
      </div>
    </div>${footerHtml()}</div>`;
  }

  /* ============================== dashboard ============================= */

  /** Category filters (interactive legend): empty typeFilter + both flags
   *  off means "show everything". Past-due keeps whole-day granularity -
   *  due-today stays live until midnight, same rule as the graying. */
  function matchesCategoryFilters(a) {
    if (S.typeFilter.length && !S.typeFilter.includes(a.activity_type)) return false;
    if (S.flagFilter.reported && a.verification_status !== 'student-reported') return false;
    if (S.flagFilter.past) {
      const todayKey = localDateKey(new Date());
      const dueKey = activityDueKey(a) ?? todayKey;
      if (dueKey >= todayKey) return false;
    }
    return true;
  }

  function dashboardHtml() {
    const monthName = monthLabel(S.visibleMonth);
    const campusNames = {};
    for (const c of S.registry.campuses) campusNames[c.id] = c.name;

    // The program filter stays valid only while its program is offered at
    // the chosen campus (registry-driven cascade, same rule as sign-up).
    if (S.filter.programId) {
      const stillOffered = S.registry.programs.some((p) =>
        p.id === S.filter.programId && (!S.filter.campusId || p.campusId === S.filter.campusId));
      if (!stillOffered) S.filter.programId = null;
    }

    const filteredSections = filterSections(S.sections, S.filter);
    const filteredSectionIds = new Set(filteredSections.map((s) => s.sectionId));
    const sectionMatched = S.monthActivities.filter((a) => a.section_id && filteredSectionIds.has(a.section_id));
    const filteredActivities = sectionMatched.filter(matchesCategoryFilters);
    visibleActivities = filteredActivities;
    const hiddenByCategory = sectionMatched.length - filteredActivities.length;

    return `<div class="page">
      <header class="dash-header">
        <div class="dash-header-inner">
          <div class="dash-logo">${ic('graduation-cap', 'ic-5')}</div>
          <div class="dash-title">
            <h1>Student Codex — Teacher Dashboard</h1>
            <p>University calendar · ${S.sections.length} sections · ${S.monthActivities.length} scheduled in ${esc(monthName)}</p>
          </div>
          <div class="dash-me">
            <div class="who">
              <p class="name">${esc(S.teacherName || 'Teacher')}</p>
              <p class="email">${esc(S.sessionEmail || '')}</p>
            </div>
            <div class="avatar" aria-hidden="true">${esc(initialsOf(S.teacherName, S.sessionEmail))}</div>
            <button type="button" class="btn btn-outline btn-sm" data-action="sign-out">
              ${ic('log-out', 'ic-3h')}<span class="hide-sm">Sign out</span><span class="sr-only-sm">Sign out</span>
            </button>
          </div>
        </div>
      </header>

      <main class="dash-main">
        ${S.loadError ? `
        <div class="alert alert-destructive" role="alert">
          ${ic('alert-triangle')}
          <div style="flex:1;min-width:0">
            <p class="alert-title">Could not load dashboard data</p>
            <p class="alert-desc">${esc(S.loadError)}</p>
          </div>
          <button type="button" class="btn btn-outline btn-sm" data-action="refresh">Retry</button>
        </div>` : ''}

        ${S.sections.length === 0 ? `
        <div class="alert" role="status">
          ${ic('info')}
          <div>
            <p class="alert-title">No class sections in the registry yet</p>
            <p class="alert-desc">Your teacher account is active and sees the whole university — but no
            sections exist yet. As soon as sections appear, their activities land on this calendar.</p>
          </div>
        </div>` : `
        ${filterBarHtml(S.sections, campusNames, filteredSections.length, filteredActivities.length, monthName)}`}

        <div class="dash-grid">
          <div class="cal-col">
            ${S.sections.length === 0 ? `
            <div class="cal-placeholder"><p>No sections to show for ${esc(monthName)}. Once sections exist in the registry, their
            assignments, quizzes, exams and announcements appear here on the calendar.</p></div>` : `
            ${calendarHtml(filteredActivities, filteredSections, hiddenByCategory)}`}
          </div>

          <div class="side-col">
            ${studentReportsPanelHtml()}
            ${coverageCardHtml()}
          </div>
        </div>
      </main>
      ${footerHtml()}
    </div>`;
  }

  function filterSections(sections, f) {
    return sections.filter((s) => {
      if (f.campusId && s.campusId !== f.campusId) return false;
      if (f.programId && s.programId !== f.programId) return false;
      if (f.year != null && s.cohortYear !== f.year) return false;
      if (f.block && s.cohortBlock !== f.block) return false;
      return true;
    });
  }

  /* ------------------------ searchable filter combos ------------------- */
  /* Native <select> dropdowns carry no search box, and the registry lists
     run long (all campuses, all 50 programs, every block). Every filter is
     now a combobox: a trigger button that rolls a panel down with a search
     input pinned on top and a scrollable option list that narrows as you
     type. One panel is open at a time; Escape, an outside click or Tab
     rolls it back up; ArrowUp/Down + Enter pick without the mouse. */

  const COMBO_META = {
    campusId: { label: 'Campus', all: 'All campuses', search: 'Search campuses…', noun: 'campuses' },
    programId: { label: 'Program', all: 'All programs', search: 'Search programs…', noun: 'programs' },
    year: { label: 'Year level', all: 'All years', search: 'Search years…', noun: 'year levels' },
    block: { label: 'Section block', all: 'All sections', search: 'Search sections…', noun: 'sections' },
  };
  // word forms so typing "second" finds "2nd year"
  const YEAR_WORDS = { 1: 'first', 2: 'second', 3: 'third', 4: 'fourth', 5: 'fifth', 6: 'sixth' };

  function comboOptions(axis) {
    // ONE source of truth for every dropdown's list: the registry tables
    // when loaded (full university lists; programs cascade to the chosen
    // campus) or the teacher's own sections while the registry is still
    // loading / failed. Each option: { value, label, search, title? } —
    // `search` carries the FULL text (untruncated program names, year word
    // forms) so typing matches what the teacher actually means.
    const reg = S.registry;
    const f = S.filter;
    const meta = COMBO_META[axis];
    const allOption = { value: ALL, label: meta.all, search: meta.all };
    const uniqueBy = (rows, key) => {
      const seen = new Set(); const out = [];
      for (const r of rows) { const k = key(r); if (k && !seen.has(k)) { seen.add(k); out.push(r); } }
      return out;
    };
    const registryReady = reg.campuses.length > 0 && reg.programs.length > 0;
    if (registryReady) {
      if (axis === 'campusId') {
        return [allOption].concat(reg.campuses.map((c) => ({ value: c.id, label: c.name, search: c.name })));
      }
      if (axis === 'programId') {
        // programs narrow to the chosen campus (registry-driven cascade,
        // same rule the native select had); duplicate names get the campus
        // appended to the label
        const programs = f.campusId ? reg.programs.filter((p) => p.campusId === f.campusId) : reg.programs;
        return [allOption].concat(programs.map((p) => {
          const dupes = programs.filter((x) => x.programName === p.programName).length > 1;
          const campusName = (reg.campuses.find((c) => c.id === p.campusId) || {}).name || 'Campus';
          return {
            value: p.id,
            label: programShortName(p.programName) + (dupes ? ` · ${campusName.replace(' Campus', '')}` : ''),
            search: `${p.programName} ${campusName}`,
            title: p.programName,
          };
        }));
      }
      if (axis === 'year') {
        return [allOption].concat(reg.yearLevels.map((y) => ({
          value: String(y.level),
          label: `${y.label} year`,
          search: `${y.label} year ${y.level} ${YEAR_WORDS[y.level] ?? ''}`,
        })));
      }
      return [allOption].concat(reg.yearSections.map((s) => ({
        value: s.name,
        label: `Section ${s.name}`,
        search: `section ${s.name}`,
      })));
    }
    // fallback: derive the lists from the teacher's own sections
    const sections = S.sections;
    if (axis === 'campusId') {
      const campusNames = {};
      for (const c of reg.campuses) campusNames[c.id] = c.name;
      return [allOption].concat(uniqueBy(sections.filter((s) => s.campusId), (s) => s.campusId)
        .map((s) => ({ value: s.campusId, label: campusNames[s.campusId] ?? 'Campus', search: campusNames[s.campusId] ?? 'Campus' })));
    }
    if (axis === 'programId') {
      return [allOption].concat(uniqueBy(sections.filter((s) => s.programId), (s) => s.programId)
        .map((s) => ({ value: s.programId, label: programShortName(s.programName), search: s.programName, title: s.programName })));
    }
    if (axis === 'year') {
      return [allOption].concat([...new Set(sections.map((s) => s.cohortYear).filter((y) => y != null))].sort((a, b) => a - b)
        .map((y) => ({ value: String(y), label: `${ordinal(y)} year`, search: `${ordinal(y)} year ${y} ${YEAR_WORDS[y] ?? ''}` })));
    }
    return [allOption].concat([...new Set(sections.map((s) => s.cohortBlock).filter((b) => !!b))].sort()
      .map((b) => ({ value: b, label: `Section ${b}`, search: `section ${b}` })));
  }

  function comboMatches(option, query) {
    const q = (query || '').trim().toLowerCase();
    if (!q) return true;
    return option.search.toLowerCase().includes(q);
  }

  function comboVisible(axis) {
    return comboOptions(axis).filter((o) => comboMatches(o, S.combo.query));
  }

  function comboCurrentValue(axis) {
    return axis === 'year' ? (S.filter.year != null ? String(S.filter.year) : ALL) : (S.filter[axis] ?? ALL);
  }

  function comboCountText(axis) {
    // the "All …" row is not a real option — counts report real entries
    const real = comboOptions(axis).filter((o) => String(o.value) !== String(ALL));
    const q = (S.combo.query || '').trim().toLowerCase();
    if (!q) return `${real.length} ${COMBO_META[axis].noun}`;
    const visibleReal = real.filter((o) => comboMatches(o, q));
    return `${visibleReal.length} of ${real.length} match`;
  }

  function comboOptionHtml(axis, option, index) {
    const selected = String(option.value) === String(comboCurrentValue(axis));
    const highlighted = index === S.combo.hl;
    return `<button type="button" class="combo-opt${selected ? ' is-selected' : ''}${highlighted ? ' is-hl' : ''}"
      role="option" aria-selected="${selected}" id="combo-opt-${axis}-${index}"
      data-action="combo-pick" data-combo="${axis}" data-combo-value="${esc(option.value)}"
      ${option.title ? `title="${esc(option.title)}"` : ''}>
      <span class="co-label">${esc(option.label)}</span>
      ${selected ? ic('check', 'ic-4') : ''}
    </button>`;
  }

  function comboNoneHtml() {
    return `<p class="combo-none" role="status">${ic('search-x', 'ic-3h')}
      No match for "${esc(S.combo.query)}" — try fewer letters.</p>`;
  }

  function comboWidgetHtml(axis) {
    const meta = COMBO_META[axis];
    const options = comboOptions(axis);
    const current = options.find((o) => String(o.value) === String(comboCurrentValue(axis))) || options[0];
    const isSet = String(current.value) !== String(ALL);
    const open = S.combo.axis === axis;
    const visible = options.filter((o) => comboMatches(o, S.combo.query));
    S.combo.hl = Math.max(0, Math.min(S.combo.hl, Math.max(0, visible.length - 1)));
    const listHtml = visible.length
      ? visible.map((o, i) => comboOptionHtml(axis, o, i)).join('')
      : comboNoneHtml();
    return `<div class="combo${open ? ' open' : ''}" data-combo="${axis}">
      <button type="button" class="combo-btn${isSet ? ' is-set' : ''}" data-action="combo-toggle" data-combo="${axis}"
        role="combobox" aria-expanded="${open}" aria-haspopup="listbox" aria-controls="combo-pop-${axis}"
        aria-label="${esc(meta.label)} filter, currently ${esc(current.label)}"
        title="${esc(current.title || current.label)}">
        <span class="cv">${esc(current.label)}</span>
        ${ic('chevron-down', 'ic-4')}
      </button>
      <div class="combo-pop" id="combo-pop-${axis}">
        <div class="combo-search">
          ${ic('search', 'ic-3h')}
          <input type="text" class="combo-input" data-combo-search="${axis}"
            placeholder="${esc(meta.search)}" value="${esc(S.combo.query)}"
            aria-label="${esc(meta.search)}" aria-controls="combo-opts-${axis}"
            aria-autocomplete="list" autocomplete="off" spellcheck="false">
        </div>
        <p class="combo-count">${esc(comboCountText(axis))}</p>
        <div class="combo-options" id="combo-opts-${axis}" role="listbox" aria-label="${esc(meta.label)} options">
          ${listHtml}
        </div>
      </div>
    </div>`;
  }

  // repaints an OPEN panel from state without a full re-render — used while
  // typing (the caret must stay in the search box) and when a panel rolls
  // down over stale markup
  function paintComboPanel(axis) {
    const comboEl = document.querySelector(`.combo[data-combo="${axis}"]`);
    if (!comboEl) return;
    const visible = comboVisible(axis);
    S.combo.hl = Math.max(0, Math.min(S.combo.hl, Math.max(0, visible.length - 1)));
    const box = comboEl.querySelector('.combo-options');
    if (box) {
      box.innerHTML = visible.length
        ? visible.map((o, i) => comboOptionHtml(axis, o, i)).join('')
        : comboNoneHtml();
    }
    const input = comboEl.querySelector('.combo-input');
    if (input) {
      // never rewrite the field mid-typing (same value = no caret jump)
      if (input.value !== S.combo.query) input.value = S.combo.query;
      input.setAttribute('aria-activedescendant', visible.length ? `combo-opt-${axis}-${S.combo.hl}` : '');
    }
    const count = comboEl.querySelector('.combo-count');
    if (count) count.textContent = comboCountText(axis);
    refreshIcons();
    const hlEl = box ? box.children[S.combo.hl] : null;
    if (hlEl && hlEl.scrollIntoView) hlEl.scrollIntoView({ block: 'nearest' });
  }

  function openCombo(axis) {
    S.combo.axis = axis;
    S.combo.query = '';
    // start the highlight on the currently selected option so Enter
    // re-picks it and the arrows move from there
    const options = comboOptions(axis);
    const idx = options.findIndex((o) => String(o.value) === String(comboCurrentValue(axis)));
    S.combo.hl = idx > 0 ? idx : 0;
    // one panel at a time: roll every other combo back up first
    document.querySelectorAll('.combo.open').forEach((el) => {
      if (el.dataset.combo !== axis) {
        el.classList.remove('open');
        const b = el.querySelector('.combo-btn');
        if (b) b.setAttribute('aria-expanded', 'false');
      }
    });
    const comboEl = document.querySelector(`.combo[data-combo="${axis}"]`);
    if (!comboEl) return;
    comboEl.classList.add('open');
    const btn = comboEl.querySelector('.combo-btn');
    if (btn) btn.setAttribute('aria-expanded', 'true');
    paintComboPanel(axis);
    const input = comboEl.querySelector('.combo-input');
    if (input) input.focus();
  }

  function closeCombo(refocus) {
    const axis = S.combo.axis;
    S.combo.axis = null;
    S.combo.query = '';
    S.combo.hl = 0;
    document.querySelectorAll('.combo.open').forEach((el) => {
      el.classList.remove('open');
      const b = el.querySelector('.combo-btn');
      if (b) b.setAttribute('aria-expanded', 'false');
    });
    if (refocus && axis) {
      const btn = document.querySelector(`.combo[data-combo="${axis}"] .combo-btn`);
      if (btn) btn.focus();
    }
  }

  function filterBarHtml(sections, campusNames, matchedCount, activityCount, monthLabelStr) {
    // Option lists come from the FULL school registry (the campuses /
    // programs / year_levels / year_sections database tables — never
    // hard-coded) through comboOptions() above, so every campus, program,
    // year and section the university offers can be picked — and each
    // dropdown narrows as you type, because these lists run long (every
    // campus, all 50 programs, every block). Since 0020 the calendar is
    // university-wide: these filters narrow ALL sections (row-level
    // security still keeps personal student activities private to their
    // creator).
    const f = S.filter;
    const hasAnyFilter = f.campusId || f.programId || f.year != null || f.block;

    return `<section class="card filter-bar" aria-label="Filter sections by campus, program, year and section">
      <div class="filter-head">
        <p class="ftitle">${ic('filter', 'ic-3h')} Filter sections</p>
        <p class="filter-count" aria-live="polite"><b>${matchedCount}</b> of ${sections.length} sections · <b>${activityCount}</b> scheduled in ${esc(monthLabelStr)}</p>
      </div>
      <div class="filter-grid">
        <div>
          <p class="fl-label ${f.campusId ? 'active' : ''}">Campus</p>
          ${comboWidgetHtml('campusId')}
        </div>
        <div>
          <p class="fl-label ${f.programId ? 'active' : ''}">Program</p>
          ${comboWidgetHtml('programId')}
        </div>
        <div>
          <p class="fl-label ${f.year != null ? 'active' : ''}">Year</p>
          ${comboWidgetHtml('year')}
        </div>
        <div>
          <p class="fl-label ${f.block ? 'active' : ''}">Section</p>
          ${comboWidgetHtml('block')}
        </div>
      </div>
      ${matchedCount === 0 && sections.length > 0 ? `
      <p class="field-error" role="status" style="margin:10px 0 0">
        No section you teach matches this filter — your ${sections.length} sections are in a different cohort.
        Pick a cohort you teach, or reset to show them all.</p>` : ''}
      ${hasAnyFilter ? `<div class="filter-reset">
        <button type="button" class="btn btn-ghost btn-xs" data-action="reset-filter">${ic('rotate-ccw', 'ic-3')} Reset — show all my sections</button>
      </div>` : ''}
    </section>`;
  }

  /* ------------------------------ calendar ------------------------------ */

  function calendarHtml(activities, sections, hiddenByCategory = 0) {
    const todayKey = localDateKey(new Date());

    // activities keyed by local due-date
    const byDay = new Map();
    for (const a of activities) {
      const key = activityDueKey(a);
      if (!key) continue;
      if (!byDay.has(key)) byDay.set(key, []);
      byDay.get(key).push(a);
    }
    for (const list of byDay.values()) {
      list.sort((a, b) => String(a.due_at ?? '').localeCompare(String(b.due_at ?? '')));
    }

    // 6 rows × 7 cols starting on Sunday of week 1
    const { year, month } = S.visibleMonth;
    const first = new Date(year, month, 1);
    const start = new Date(first);
    start.setDate(1 - first.getDay());
    const cells = [];
    for (let i = 0; i < 42; i++) {
      const d = new Date(start);
      d.setDate(start.getDate() + i);
      cells.push({ date: d, key: localDateKey(d), inMonth: d.getMonth() === month });
    }

    const cellsHtml = cells.map(({ date, key, inMonth }, i) => {
      if (!inMonth) {
        return `<div class="cal-cell blank" aria-hidden="true"></div>`;
      }
      const dayActivities = byDay.get(key) ?? [];
      const visible = dayActivities.slice(0, MAX_CHIPS);
      const hidden = dayActivities.length - visible.length;
      const checker = (Math.floor(i / 7) + i) % 2 === 0;
      const isToday = key === todayKey;
      // Whole-day granularity: an entry grays out the day AFTER its due
      // date; due-today stays live until midnight (students get the day).
      const isPast = key < todayKey;
      const ariaDate = date.toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' });
      const ariaLabel = `${ariaDate}${dayActivities.length ? `, ${dayActivities.length} activities` : ', no activities'}`;

      return `<button type="button" class="cal-cell${checker ? ' checker' : ''}${isToday ? ' today' : ''}" data-action="open-day" data-day="${key}" aria-label="${esc(ariaLabel)}">
        <span class="cal-date">${date.getDate()}</span>
        <span class="cal-chips">
          ${visible.map((a) => {
            const meta = typeMeta(a.activity_type);
            const student = a.verification_status === 'student-reported';
            return `<span class="chip chip-${esc(a.activity_type)}${student ? ' student-reported' : ''}${isPast ? ' past' : ''}" data-action="open-activity" data-id="${esc(a.id)}" title="${isPast ? 'Done · ' : ''}${student ? 'Student-reported · ' : ''}${esc(meta.label)}: ${esc(a.title)}">
              ${ic(meta.icon, 'ic-3')}<span class="chip-text">${esc(a.title)}</span>
            </span>`;
          }).join('')}
          ${hidden > 0 ? `<span class="chip-more">+${hidden} more</span>` : ''}
        </span>
      </button>`;
    }).join('');

    return `<section class="card cal" aria-label="Calendar for ${esc(monthLabel(S.visibleMonth))}">
      <header class="cal-monthbar">
        <h2>${MONTH_NAMES[month]} ${year}
          ${S.monthLoading ? '<span class="spinner spinner-sm spinner-onprimary" aria-label="Loading activities"></span>' : ''}
        </h2>
        <div class="cal-nav">
          <button type="button" class="btn btn-sm btn-onprimary" data-action="prev-month" aria-label="Previous month">${ic('chevron-left')}</button>
          <button type="button" class="btn btn-sm btn-onprimary" data-action="today">Today</button>
          <button type="button" class="btn btn-sm btn-onprimary" data-action="next-month" aria-label="Next month">${ic('chevron-right')}</button>
        </div>
      </header>

      ${emptyMonthHintHtml()}

      <div class="cal-weekdays" role="row">
        ${WEEKDAYS.map((d) => `<div role="columnheader"><span class="wd-full">${d}</span><span class="wd-1">${d[0]}</span></div>`).join('')}
      </div>

      <div class="cal-grid" role="row">
        ${cellsHtml}
      </div>

      <footer class="cal-legend" role="group" aria-label="Filter activities by category">
        <span class="lg lg-lead">Filter:</span>
        ${ACTIVITY_TYPES.map((t) => {
          const on = S.typeFilter.includes(t);
          return `<button type="button" class="lg lg-btn${on ? ' is-on' : ''}" data-action="type-filter" data-type="${t}" aria-pressed="${on}" title="Show only ${esc(typeMeta(t).label)} entries">
            <span class="sw sw-${t}" aria-hidden="true"></span>${esc(typeMeta(t).label)}
          </button>`;
        }).join('')}
        ${(() => {
          const on = S.flagFilter.reported;
          return `<button type="button" class="lg lg-btn${on ? ' is-on' : ''}" data-action="flag-filter" data-flag="reported" aria-pressed="${on}" title="Show only student-reported entries">
            <span class="sw sw-student" aria-hidden="true"></span>Dashed outline = student-reported
          </button>`;
        })()}
        ${(() => {
          const on = S.flagFilter.past;
          return `<button type="button" class="lg lg-btn${on ? ' is-on' : ''}" data-action="flag-filter" data-flag="past" aria-pressed="${on}" title="Show only past-due (done) entries">
            <span class="sw sw-done" aria-hidden="true"></span>Dark green = past due (done)
          </button>`;
        })()}
        ${(S.typeFilter.length || S.flagFilter.reported || S.flagFilter.past) ? `
        <span class="lg lg-status" role="status">${hiddenByCategory ? `${hiddenByCategory} hidden by category filters` : 'Category filters are on'}</span>
        <button type="button" class="lg-btn lg-clear" data-action="clear-type-filter" title="Clear all category filters">${ic('rotate-ccw', 'ic-3')} Clear filters</button>` : ''}
      </footer>
    </section>`;
  }

  /* ------------------------- student-reported feed ---------------------- */

  function reporterName(uid) {
    const p = uid ? S.reporterProfiles[uid] : undefined;
    return [p?.first_name, p?.last_name].filter(Boolean).join(' ') || p?.username || 'A student';
  }

  // Read-only feed of the student-reported activities already shown on the
  // calendar for the visible month (same filtered set the day boxes show).
  // Teachers never act on these — publishing IS the student's action.
  function studentReportsPanelHtml() {
    const sectionById = new Map(S.sections.map((s) => [s.sectionId, s]));
    const todayKey = localDateKey(new Date());
    const reports = visibleActivities
      .filter((a) => a.verification_status === 'student-reported')
      .sort((a, b) => String(a.due_at ?? '').localeCompare(String(b.due_at ?? '')));

    const listHtml = reports.map((a) => {
      const section = a.section_id ? sectionById.get(a.section_id) : undefined;
      const due = a.due_at ? new Date(a.due_at).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }) : null;
      // Feed rows gray out like calendar chips once their due date passes.
      const past = (activityDueKey(a) ?? todayKey) < todayKey;
      return `<li class="report-item${past ? ' done' : ''}" data-action="open-activity" data-id="${esc(a.id)}" role="button" tabindex="0" aria-label="Open full details: ${esc(a.title)}">
        <p class="rtitle">${esc(a.title)}${past ? ' <span class="done-tag">done</span>' : ''}</p>
        <p class="rmeta">
          <span>${esc(reporterName(a.created_by_user_id))}</span>
          ${due ? `<span aria-hidden="true">·</span>${ic('calendar-clock', 'ic-3')}<span>due ${esc(due)}</span>` : ''}
          ${section ? `<span aria-hidden="true">·</span><span class="badge">${esc(section.courseCode ?? '')} ${esc(section.sectionName)}</span>` : ''}
        </p>
        ${a.description ? `<p class="rnotes line-clamp-2">${esc(a.description)}</p>` : ''}
      </li>`;
    }).join('');

    return `<div class="card">
      <div class="card-head">
        <p class="card-title">${ic('megaphone', 'ic-4')} Student-reported <span class="badge badge-secondary" style="margin-left:auto">${reports.length}</span></p>
        <p class="card-desc">Reported by students in class — on the calendar immediately, no confirmation needed.</p>
      </div>
      <div class="card-body card-body-top">
        ${reports.length === 0 ? `
        <div class="empty-state">
          ${ic('check-circle-2', 'ic-6')}
          <p class="et">None in ${esc(monthLabel(S.visibleMonth))}</p>
          <p class="ed">When students report face-to-face work from the app, it lands here — and on the calendar — instantly.</p>
        </div>` : `
        <ul class="report-list" aria-live="polite">${listHtml}</ul>`}
      </div>
    </div>`;
  }

  /* ------------------------------ coverage ------------------------------ */

  function coverageCardHtml() {
    const synced = S.googleConnection?.status === 'connected';
    const refreshedLabel = S.lastRefresh
      ? new Date(S.lastRefresh).toLocaleString(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })
      : '—';

    return `<div class="card">
      <div class="card-head">
        <p class="card-title">Data coverage</p>
        <p class="card-desc">Where this calendar's data comes from.</p>
      </div>
      <div class="card-body card-body-top" style="display:flex;flex-direction:column;gap:12px">
        <div class="cover-box">
          <p class="ct">${ic('cloud-off', 'ic-3h')} ${synced
            ? `Google Classroom sync: ${esc(S.googleConnection.google_email ?? 'connected')}`
            : 'Google Classroom sync not enabled yet'}</p>
          <p class="cd">${synced
            ? 'Classroom coursework and announcements import automatically for connected students.'
            : 'Teacher-confirmed entries, instant student reports (no approval queue) and demo imports. Classroom sync arrives with the Edge Function phase.'}</p>
        </div>
        <div class="cover-row">
          <div>
            <p class="lbl">Last refresh</p>
            <p class="val">${esc(refreshedLabel)}</p>
          </div>
          <button type="button" class="btn btn-outline btn-sm" data-action="refresh">${ic('refresh-cw', 'ic-3h')} Refresh</button>
        </div>
        <p class="privacy-note">${ic('lock-keyhole', 'ic-3')}
          Teachers see section-scoped records across every campus and program. Personal student activities remain private by design.</p>
      </div>
    </div>`;
  }

  /* ================================ dialogs ============================= */

  // Overlays STACK now: the day sheet opens a full activity sheet on top of
  // itself; closing (button, backdrop or Escape) pops only the top one, so
  // the day sheet is still underneath, exactly where it was.
  function mountOverlay(html, { label } = {}) {
    const overlays = $('#overlays');
    const overlay = document.createElement('div');
    overlay.className = 'overlay';
    overlay.innerHTML = `<div class="dialog" role="dialog" aria-modal="true" ${label ? `aria-label="${esc(label)}"` : ''}>${html}</div>`;
    overlays.appendChild(overlay);
    overlay.addEventListener('mousedown', (e) => { if (e.target === overlay) closeOverlay(); });
    refreshIcons();
    const firstFocus = overlay.querySelector('select, input, button:not([data-autofocus-skip])');
    if (firstFocus) firstFocus.focus();
    return overlay;
  }

  function closeOverlay() {
    const overlays = $('#overlays');
    if (overlays.lastElementChild) overlays.lastElementChild.remove();
  }

  document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    // an open filter combo rolls up first — overlays only pop once no
    // combo panel is open on the dashboard
    if (S.combo.axis) { closeCombo(true); return; }
    if ($('#overlays').firstElementChild) closeOverlay();
  });

  // role="button" list rows (day-sheet items, feed rows): Enter and Space
  // must act like a click - native buttons get this for free, list items
  // do not.
  document.addEventListener('keydown', (e) => {
    if (e.key !== 'Enter' && e.key !== ' ') return;
    if (!(e.target instanceof Element)) return;
    const el = e.target.closest('[data-action][role="button"]');
    if (!el) return;
    e.preventDefault();
    el.click();
  });

  function daySheet(dayKey) {
    const byDay = new Map();
    for (const a of visibleActivities) {
      const key = activityDueKey(a);
      if (!key) continue;
      if (!byDay.has(key)) byDay.set(key, []);
      byDay.get(key).push(a);
    }
    const activities = (byDay.get(dayKey) ?? []).slice().sort((a, b) =>
      String(a.due_at ?? '').localeCompare(String(b.due_at ?? '')));

    const sectionById = new Map(S.sections.map((s) => [s.sectionId, s]));
    const todayKey = localDateKey(new Date());
    const isPastDay = dayKey < todayKey;
    const dateLabel = new Date(dayKey + 'T00:00:00').toLocaleDateString(undefined, {
      weekday: 'long', month: 'long', day: 'numeric', year: 'numeric',
    });

    const items = activities.map((a) => {
      const meta = typeMeta(a.activity_type);
      const ver = verificationMeta(a.verification_status);
      const section = a.section_id ? sectionById.get(a.section_id) : undefined;
      const effort = effortLabel(a.estimated_effort_minutes);
      const time = timeLabel(a.due_at);
      const metaLine = [
        meta.label,
        section ? `${section.courseCode ?? ''} ${section.sectionName}` : '',
        time ? `due ${time}` : '',
        effort || '',
      ].filter(Boolean).join(' · ');
      return `<li class="day-item${isPastDay ? ' past' : ''}" data-action="open-activity" data-id="${esc(a.id)}" role="button" tabindex="0" aria-label="Open full details: ${esc(a.title)}">
        <span class="dicon chip-${esc(a.activity_type)}">${ic(meta.icon, 'ic-4')}</span>
        <div style="min-width:0;flex:1">
          <p class="dtitle">${esc(a.title)}</p>
          <p class="dmeta">${esc(metaLine)}</p>
          ${a.description ? `<p class="ddesc line-clamp-4">${esc(a.description)}</p>` : ''}
          <div style="margin-top:8px"><span class="badge ${ver.cls}">${ic(ver.icon, 'ic-3')} ${esc(ver.label)}</span>${isPastDay ? ` <span class="badge badge-done">${ic('check-circle-2', 'ic-3')} Done</span>` : ''}</div>
        </div>
      </li>`;
    }).join('');

    mountOverlay(`
      <div class="dialog-head">
        <h3>${esc(dateLabel)}</h3>
        <p>${activities.length === 0 ? 'Nothing scheduled for this day.' : `${activities.length} scheduled ${activities.length === 1 ? 'activity' : 'activities'} for the filtered sections.`}</p>
      </div>
      <div class="dialog-body">
        ${activities.length === 0
          ? `<div class="empty-state"><p class="ed">No assignments, quizzes, exams or announcements fall on this day for the filtered sections.</p></div>`
          : `<ul class="day-list">${items}</ul>`}
      </div>
      <div class="dialog-foot">
        <button type="button" class="btn btn-outline" data-action="close-overlay">Close</button>
      </div>`, { label: dateLabel });
  }

  // ===================== category correction row ======================== //
  // The six Student Codex tracking categories (same list the legend
  // filters on). Offered to teachers enrolled on the activity's own
  // section or course - the RLS update policy allows exactly them. A
  // correction saves immediately and sets category_locked, which the
  // import RPC honors on every later Google Classroom sync (the raw
  // Classroom workType stays untouched in activity_sources.source_meta).
  function categoryRowHtml(activity) {
    const canCorrect =
      S.teacherSectionIds.has(activity.section_id) ||
      S.teacherCourseIds.has(activity.course_id);
    if (!canCorrect) return '';
    return `
      <p class="a-notes-label">Category
        <span class="a-cat-lock${activity.category_locked ? ' is-on' : ''}">${activity.category_locked ? 'teacher-corrected' : ''}</span>
      </p>
      <div class="a-cat-row" role="radiogroup" aria-label="Tracking category">
        ${ACTIVITY_TYPES.map((t) => {
          const current = t === activity.activity_type;
          return `<button type="button" class="a-cat-opt${current ? ' is-current' : ''}" role="radio" aria-checked="${current}" data-action="set-category" data-id="${esc(activity.id)}" data-type="${t}"${S.categoryBusy ? ' disabled' : ''} title="Track this as ${esc(typeMeta(t).label)}">
            ${esc(typeMeta(t).label)}
          </button>`;
        }).join('')}
      </div>
      <p class="a-cat-hint">Corrections save immediately and are preserved on future Google Classroom syncs.</p>`;
  }

  // ============================ activity sheet ============================
  //
  // FULL-CONTENT sheet for ONE activity. Opened by pressing a calendar
  // chip, a day-sheet item or a student-reported feed row. Everything the
  // row could only preview is here: the whole title, the full notes, the
  // verification and origin badges. Long notes start clamped (8 lines) and
  // grow through a See more / See less toggle that only appears when the
  // text really overflows - short notes never show a button.
  function activitySheet(activity) {
    if (!activity) return;
    const meta = typeMeta(activity.activity_type);
    const ver = verificationMeta(activity.verification_status);
    const sectionById = new Map(S.sections.map((s) => [s.sectionId, s]));
    const section = activity.section_id ? sectionById.get(activity.section_id) : undefined;
    const effort = effortLabel(activity.estimated_effort_minutes);
    const due = sheetDueLabel(activity.due_at);
    const metaLine = [
      meta.label,
      section ? `${section.courseCode ?? ''} ${section.sectionName}` : '',
      due ? `due ${due}` : '',
      effort || '',
    ].filter(Boolean).join(' \u00b7 ');
    const todayKey = localDateKey(new Date());
    const past = (activityDueKey(activity) ?? todayKey) < todayKey;

    const overlay = mountOverlay(`
      <div class="dialog-head">
        <h3>${esc(activity.title)}</h3>
        <p>${esc(metaLine)}</p>
      </div>
      <div class="dialog-body">
        <div class="a-badges">
          <span class="badge ${ver.cls}">${ic(ver.icon, 'ic-3')} ${esc(ver.label)}</span>
          ${activity.verification_status === 'student-reported' ? `<span class="badge badge-secondary">${ic('megaphone', 'ic-3')} Student-reported</span>` : ''}
          ${past ? `<span class="badge badge-done">${ic('check-circle-2', 'ic-3')} Done</span>` : ''}
        </div>
        ${categoryRowHtml(activity) ? `<div class="a-cat">${categoryRowHtml(activity)}</div>` : ''}
        ${activity.description ? `
        <div class="a-notes">
          <p class="a-notes-label">${ic('file-text', 'ic-3')} Notes</p>
          <p class="adesc">${esc(activity.description)}</p>
          <button type="button" class="see-more" data-see="more" hidden>See more</button>
        </div>` : `
        <p class="a-notes-empty">No notes on this entry.</p>`}
      </div>
      <div class="dialog-foot">
        <button type="button" class="btn btn-outline" data-action="close-overlay">Close</button>
      </div>`, { label: activity.title });

    // Overflow check AFTER mount: the button stays hidden unless the notes
    // really need more room than the 8-line clamp.
    const desc = overlay.querySelector('.adesc');
    const toggle = overlay.querySelector('.see-more');
    if (desc && toggle) {
      if (desc.scrollHeight > desc.clientHeight + 2) toggle.hidden = false;
      toggle.addEventListener('click', () => {
        const expanding = toggle.dataset.see === 'more';
        desc.classList.toggle('expanded', expanding);
        toggle.dataset.see = expanding ? 'less' : 'more';
        toggle.textContent = expanding ? 'See less' : 'See more';
      });
    }
  }

  /* ================================ toasts ============================== */

  function toast({ title, description, variant = 'default' }) {
    const box = $('#toasts');
    const el = document.createElement('div');
    el.className = `toast${variant === 'destructive' ? ' toast-destructive' : ''}`;
    el.setAttribute('role', 'status');
    el.innerHTML = `<div style="min-width:0">
        <p class="tt">${esc(title)}</p>
        ${description ? `<p class="td">${esc(description)}</p>` : ''}
      </div>
      <button type="button" class="toast-close" aria-label="Dismiss">${ic('x', 'ic-3h')}</button>`;
    el.querySelector('.toast-close').addEventListener('click', () => el.remove());
    box.appendChild(el);
    refreshIcons();
    setTimeout(() => { el.remove(); }, variant === 'destructive' ? 8000 : 6000);
  }

  /* ============================= data loading =========================== */

  async function fetchMonth(key) {
    const cacheKey = monthKeyString(key);
    const cached = monthCache.get(cacheKey);
    if (cached) {
      S.monthActivities = cached; render();
      if (!cached.length && S.sections.length) probeNearbyMonths(key);
      return;
    }
    S.monthLoading = true; render();
    try {
      const { fromIso, toIso } = monthRange(key);
      // 0020: university-wide — RLS hands teachers every non-personal row;
      // scope='section' keeps the calendar on the section grid (course-only
      // rows have no section to render and stay off it by design).
      const { data, error } = await sb.from('activities')
        .select(ACTIVITY_COLUMNS)
        .eq('scope', 'section')
        .is('deleted_at', null)
        .gte('due_at', fromIso)
        .lte('due_at', toIso)
        .order('due_at', { ascending: true })
        .limit(500);
      if (error) throw error;
      monthCache.set(cacheKey, data ?? []);
      S.monthActivities = data ?? [];
      await ensureReporterProfiles(S.monthActivities);
      if (!S.monthActivities.length && S.sections.length) probeNearbyMonths(key);
    } catch (error) {
      S.loadError = messageFromError(error);
    } finally {
      S.monthLoading = false;
      render();
    }
  }

  function setMonth(key) {
    S.visibleMonth = key;
    fetchMonth(key);
  }

  // When the visible month is completely empty for this teacher's
  // sections, quietly peek at the neighbouring months (results land in
  // monthCache, so navigating there later is instant) and re-render: the
  // calendar then shows a "nothing here — N activities in <month> →"
  // jump hint instead of looking broken. A month where only the FILTER
  // hides everything never reaches this path (the unfiltered month load
  // is what triggers the probe).
  async function probeNearbyMonths(key) {
    const fromKey = monthKeyString(key);
    if (probedEmptyMonths.has(fromKey)) return;
    probedEmptyMonths.add(fromKey);
    const targets = [shiftMonth(key, 1), shiftMonth(key, -1)];
    await Promise.all(targets.map(async (target) => {
      const targetKey = monthKeyString(target);
      if (monthCache.has(targetKey)) return;
      const { fromIso, toIso } = monthRange(target);
      const { data, error } = await sb.from('activities')
        .select(ACTIVITY_COLUMNS)
        .eq('scope', 'section')
        .is('deleted_at', null)
        .gte('due_at', fromIso)
        .lte('due_at', toIso)
        .order('due_at', { ascending: true })
        .limit(500);
      if (!error) monthCache.set(targetKey, data ?? []);
    }));
    render();
  }

  // The jump-hint row under the calendar's month bar: shown ONLY when the
  // visible month is truly empty AND a probed neighbour month holds
  // activities. Clicking a chip loads that month (already cached).
  function emptyMonthHintHtml() {
    if (S.monthLoading || S.monthActivities.length || !S.sections.length) return '';
    const current = S.visibleMonth.year * 12 + S.visibleMonth.month;
    const hits = [shiftMonth(S.visibleMonth, 1), shiftMonth(S.visibleMonth, -1)]
      .map((k) => ({ key: k, count: (monthCache.get(monthKeyString(k)) || []).length }))
      .filter((n) => n.count > 0);
    if (!hits.length) return '';
    const chips = hits.map(({ key, count }) => {
      const forward = key.year * 12 + key.month > current;
      return `<button type="button" class="jump" data-action="jump-month"
        data-year="${key.year}" data-month="${key.month}">
        ${count} ${count === 1 ? 'activity' : 'activities'} in ${esc(monthLabel(key))}
        ${ic(forward ? 'chevron-right' : 'chevron-left', 'ic-3h')}
      </button>`;
    }).join('');
    return `<div class="cal-emptyhint" role="status">
      ${ic('search', 'ic-3h')}
      <p>Nothing scheduled in ${esc(monthLabel(S.visibleMonth))}.</p>
      ${chips}
    </div>`;
  }

  // Resolves display names for the authors of student-reported activities
  // (their ids arrive on the rows themselves). Missing names fall back to
  // "A student" — never worth failing the calendar over.
  async function ensureReporterProfiles(activities) {
    const ids = [...new Set(activities
      .filter((a) => a.verification_status === 'student-reported' && a.created_by_user_id)
      .map((a) => a.created_by_user_id))];
    const missing = ids.filter((id) => !S.reporterProfiles[id]);
    if (!missing.length) return;
    try {
      const { data, error } = await sb.from('profiles').select('id, username, first_name, last_name').in('id', missing);
      if (error) throw error;
      for (const p of data ?? []) S.reporterProfiles[p.id] = p;
      render();
    } catch { /* names are cosmetic */ }
  }

  function goToToday() {
    const now = new Date();
    setMonth({ year: now.getFullYear(), month: now.getMonth() });
  }

  async function fetchBundle(theUid) {
    // 0020: the university-wide calendar — the filter bar works on EVERY
    // section in the registry (sections/courses/programs are readable by
    // all authenticated users), and RLS on activities gives teachers every
    // non-personal row. The teacher-enrollment query is gone: a teacher
    // account needs no cohort.
    const [profileRes, sectionsRes, enrollRes, googleRes] = await Promise.all([
      sb.from('profiles').select('id, username, first_name, last_name').eq('id', theUid).maybeSingle(),
      sb.from('sections').select('id, name, term, course_id').order('name'),
      sb.from('enrollments').select('section_id, role').eq('user_id', theUid),
      sb.from('google_connections')
        .select('user_id, google_email, status, last_sync_at, last_sync_status, last_sync_error')
        .eq('user_id', theUid).maybeSingle(),
    ]);
    if (sectionsRes.error) throw sectionsRes.error;

    const profile = profileRes.data ?? null;
    const teacherName = [profile?.first_name, profile?.last_name].filter(Boolean).join(' ').trim();

    const sectionRows = sectionsRes.data ?? [];

    // Which sections (and courses) this account is enrolled to TEACH -
    // the RLS update policy allows exactly these teachers to correct an
    // activity's tracking category, so the sheet offers the picker there.
    const enrollRows = enrollRes.error ? [] : enrollRes.data ?? [];
    const teacherSectionIds = new Set(
      enrollRows.filter((e) => e.role === 'teacher').map((e) => e.section_id));
    const teacherCourseIds = new Set(
      sectionRows.filter((s) => teacherSectionIds.has(s.id)).map((s) => s.course_id).filter(Boolean));

    const courseIds = [...new Set(sectionRows.map((s) => s.course_id).filter(Boolean))];
    let courseRows = [];
    if (courseIds.length) {
      const res = await sb.from('courses').select('id, code, title, program_id').in('id', courseIds);
      if (res.error) throw res.error;
      courseRows = res.data ?? [];
    }

    const programIds = [...new Set(courseRows.map((c) => c.program_id).filter(Boolean))];
    let programRows = [];
    if (programIds.length) {
      const res = await sb.from('programs').select('id, program_name, campus_id').in('id', programIds);
      if (res.error) throw res.error;
      programRows = res.data ?? [];
    }

    const courseById = new Map(courseRows.map((c) => [c.id, c]));
    const programById = new Map(programRows.map((p) => [p.id, p]));
    const sections = sectionRows.map((s) => {
      const course = courseById.get(s.course_id ?? '');
      const program = programById.get(course?.program_id ?? '');
      const cohort = parseCohort(s.name);
      return {
        sectionId: s.id, sectionName: s.name, term: s.term ?? null,
        courseId: s.course_id ?? null, courseCode: course?.code ?? null, courseTitle: course?.title ?? null,
        programId: program?.id ?? null, programName: program?.program_name ?? null, campusId: program?.campus_id ?? null,
        cohortYear: cohort.year, cohortBlock: cohort.block,
      };
    }).sort((a, b) => `${a.courseCode ?? ''}${a.sectionName}`.localeCompare(`${b.courseCode ?? ''}${b.sectionName}`));

    return {
      teacherName: teacherName || profile?.username || '',
      sections,
      googleConnection: googleRes.data ?? null,
      teacherSectionIds,
      teacherCourseIds,
    };
  }

  async function handleSession(session) {
    const theUid = session.user.id;
    if (handledUid === theUid) return;
    handledUid = theUid;
    uid = theUid;

    S.stage = 'checking';
    S.sessionEmail = session.user.email ?? null;
    render();

    const { data: roles, error: rolesError } = await sb.from('user_roles').select('role').eq('user_id', theUid);
    if (rolesError) {
      handledUid = null;
      S.stage = 'signin';
      S.loadError = `Could not verify your account role: ${rolesError.message}`;
      render();
      return;
    }

    const isTeacher = (roles ?? []).some((r) => r.role === 'teacher');
    if (!isTeacher) {
      const meta = session.user.user_metadata ?? {};
      // Multi-class sign-up metadata (0016): class_groups array. Older
      // accounts signed up before 0016 store the flat single-group fields —
      // normalize those into a one-element array so activation is uniform.
      const rawGroups = Array.isArray(meta.class_groups) && meta.class_groups.length
        ? meta.class_groups
        : (meta.teacher_signup === true && typeof meta.program_id === 'string' && typeof meta.year_section_id === 'string'
          ? [{ program_id: meta.program_id, year_level: meta.year_level, year_section_id: meta.year_section_id, campus_id: meta.campus_id }]
          : null);
      if (rawGroups) {
        // Legacy pre-0020 payload: activation still runs teacher_signup_multi.
        const groups = rawGroups.map((g) => ({
          programId: g.program_id,
          yearLevel: typeof g.year_level === 'number' ? g.year_level : (Number.parseInt(String(g.year_level ?? '0'), 10) || 0),
          yearSectionId: g.year_section_id,
          campusId: typeof g.campus_id === 'string' ? g.campus_id : null,
        })).filter((g) => typeof g.programId === 'string' && typeof g.yearSectionId === 'string');
        S.pendingTeacherSignup = groups.length ? { groups } : { global: true };
      } else {
        // 0020 sign-ups carry no class choices — activation just grants the role.
        S.pendingTeacherSignup = meta.teacher_signup === true ? { global: true } : null;
      }
      S.stage = 'not-teacher';
      render();
      return;
    }

    S.pendingTeacherSignup = null;
    S.stage = 'loading';
    S.loadError = null;
    render();
    monthCache.clear();
    probedEmptyMonths.clear();
    try {
      const bundle = await fetchBundle(theUid);
      Object.assign(S, bundle);
      S.stage = 'ready';
      S.loadError = null;
      S.lastRefresh = Date.now();
      render();
      fetchMonth(S.visibleMonth);
    } catch (error) {
      S.stage = 'ready';
      S.loadError = messageFromError(error);
      render();
    }
  }

  let refreshBusy = false;
  async function refresh() {
    if (!uid || refreshBusy) return;
    refreshBusy = true;
    try {
      const bundle = await fetchBundle(uid);
      Object.assign(S, bundle);
      S.loadError = null;
      S.lastRefresh = Date.now();
      monthCache.clear();
      probedEmptyMonths.clear();
      render();
      fetchMonth(S.visibleMonth);
    } catch (error) {
      S.loadError = messageFromError(error);
      render();
    } finally {
      refreshBusy = false;
    }
  }

  // Live-on-return: monthCache lives only in memory, so a dashboard left
  // open on a desk or in a background tab freezes at whatever it last
  // loaded — an activity a student uploads from their phone would never
  // appear until someone clicks Refresh or reloads the page. When the
  // teacher comes back to the tab (it becomes visible again / regains
  // focus), silently refresh whenever the data is older than 10 seconds.
  // refreshBusy makes an overlap with a manual Refresh a harmless no-op,
  // and the stage check keeps the sign-in / activation screens untouched.
  function autoRefreshOnReturn() {
    if (!uid || S.stage !== 'ready' || refreshBusy) return;
    if (Date.now() - (S.lastRefresh ?? 0) < 10000) return;
    refresh();
  }
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') autoRefreshOnReturn();
  });
  window.addEventListener('focus', autoRefreshOnReturn);

  function resetAfterSignOut() {
    handledUid = null;
    uid = null;
    monthCache.clear();
    probedEmptyMonths.clear();
    Object.assign(S, {
      stage: 'signin', sessionEmail: null, teacherName: null, sections: [],
      reporterProfiles: {}, googleConnection: null, lastRefresh: null, loadError: null,
      pendingTeacherSignup: null, monthActivities: [], monthLoading: false,
      authError: null, signupError: null, signupNeedsDbPush: false, activateError: null,
      signupNeedsConfirm: false, authNeedsConfirm: false, resendInfo: null,
      pwVisible: {},
      // a fresh sign-in starts unfiltered — otherwise the next account
      // inherits the previous teacher's view and looks "missing" data
      filter: { campusId: null, programId: null, year: null, block: null },
      combo: { axis: null, query: '', hl: 0, focusAfter: null },
      typeFilter: [],
      flagFilter: { reported: false, past: false },
      teacherSectionIds: new Set(),
      teacherCourseIds: new Set(),
      categoryBusy: false,
    });
    render();
  }

  /* ================================ actions ============================= */

  async function signIn(email, password) {
    S.authNeedsConfirm = false;
    const { data, error } = await sb.auth.signInWithPassword({ email, password });
    if (error) {
      S.authNeedsConfirm = /email not confirmed/i.test(String(error.message ?? ''));
      return friendlyAuthError(error);
    }
    if (data.session) await handleSession(data.session);
    return null;
  }

  // Normalizes a class-group payload for the teacher_signup_multi RPC.
  // campus_id is omitted when the group was picked under "All campuses"
  // — the server falls back to the program's own campus (migration 0012).
  function groupsRpcPayload(groups) {
    return groups.map((g) => {
      const obj = { program_id: g.programId, year_level: g.yearLevel, year_section_id: g.yearSectionId };
      if (g.campusId) obj.campus_id = g.campusId;
      return obj;
    });
  }

  async function signUpTeacher(input) {
    // 0020: a teacher account is just an identity — no campus, program,
    // year or block choice. The role is granted right here when the project
    // returns a session immediately (or on the activation card after email
    // confirmation); visibility is university-wide via the activities RLS.
    const metadata = {
      teacher_signup: true,
      first_name: input.firstName,
      last_name: input.lastName,
    };

    const { data, error } = await sb.auth.signUp({
      email: input.email, password: input.password, options: { data: metadata },
    });
    if (error) return { ok: false, message: friendlyAuthError(error) };

    const session = data.session;
    if (!session) {
      // The account exists, but the project demands a confirmed email
      // before it issues a session (auth.email.enable_confirmations on the
      // hosted project). The draft email is kept so the resend button works.
      return {
        ok: false, needsConfirm: true,
        message: 'Your account was created, but this Supabase project requires email confirmation. ' +
          `Click “Confirm your email” in the message sent to ${input.email} (check spam too), then sign in below.`,
      };
    }

    const { error: rpcError } = await sb.rpc('teacher_signup_global');
    if (rpcError) {
      const missing = rpcError.code === 'PGRST202' || /could not find the function/i.test(rpcError.message);
      if (missing) {
        return {
          ok: false, needsDbPush: true,
          message: 'Your account was created, but teacher access needs one database update. ' +
            'Run "supabase db push" on the StudentCodex project (migration 0019 — teacher_signup_global), then sign in below.',
        };
      }
      return { ok: false, message: messageFromError(rpcError) };
    }

    handledUid = null; // force re-gate now that the role exists
    await handleSession(session);
    return { ok: true };
  }

  async function activateTeacher(pending) {
    // 0020: no class choices — activation grants the teacher role, which
    // unlocks the university-wide calendar. Legacy pending sign-ups (class-
    // group metadata from before 0020) still complete the old way.
    const legacyGroups = pending.groups && pending.groups.length
      ? groupsRpcPayload(pending.groups) : null;
    const { error: rpcError } = legacyGroups
      ? await sb.rpc('teacher_signup_multi', { p_groups: legacyGroups })
      : await sb.rpc('teacher_signup_global');
    if (rpcError) {
      const missing = rpcError.code === 'PGRST202' || /could not find the function/i.test(rpcError.message);
      if (missing) {
        return {
          ok: false, needsDbPush: true,
          message: 'Teacher activation needs one database update. Run "supabase db push" on the ' +
            'StudentCodex project (migration 0019 — teacher sign-up), then try again.',
        };
      }
      return { ok: false, message: messageFromError(rpcError) };
    }

    const { data: sessionData } = await sb.auth.getSession();
    if (sessionData.session) {
      handledUid = null;
      await handleSession(sessionData.session);
    }
    return { ok: true };
  }

  /* ============================ event wiring ============================ */

  document.addEventListener('click', (e) => {
    const btn = e.target.closest('[data-action]');
    if (!btn) return;
    const action = btn.dataset.action;

    switch (action) {
      case 'auth-mode':
        S.authMode = btn.dataset.mode;
        S.authError = null; S.signupError = null; S.signupNeedsDbPush = false;
        S.signupNeedsConfirm = false; S.authNeedsConfirm = false; S.resendInfo = null;
        resetPwVisible();
        render();
        break;
      case 'fill-demo':
        S.authDraft.email = DEMO_EMAIL;
        S.authDraft.password = DEMO_PASSWORD;
        S.authError = null;
        render();
        break;
      case 'sign-out':
        resetAfterSignOut();
        sb.auth.signOut();
        break;
      case 'resend-confirmation':
        resendConfirmation();
        break;
      case 'pw-toggle': {
        // reveal/hide in place — no re-render, so the typed value, caret
        // and scroll stay exactly where they are
        const id = btn.dataset.pw;
        const input = document.getElementById(id);
        if (!input) break;
        const show = input.type === 'password';
        S.pwVisible[id] = show;
        input.type = show ? 'text' : 'password';
        const label = show ? 'Hide password' : 'Show password';
        btn.setAttribute('aria-label', label);
        btn.setAttribute('aria-pressed', show ? 'true' : 'false');
        btn.setAttribute('title', label);
        btn.innerHTML = ic(show ? 'eye-off' : 'eye', 'ic-4');
        refreshIcons();
        break;
      }
      case 'prev-month':
        setMonth(shiftMonth(S.visibleMonth, -1));
        break;
      case 'next-month':
        setMonth(shiftMonth(S.visibleMonth, 1));
        break;
      case 'jump-month':
        setMonth({ year: Number(btn.dataset.year), month: Number(btn.dataset.month) });
        break;
      case 'today':
        goToToday();
        break;
      case 'open-day':
        daySheet(btn.dataset.day);
        break;
      case 'open-activity': {
        const activity = visibleActivities.find((a) => String(a.id) === String(btn.dataset.id));
        if (activity) activitySheet(activity);
        break;
      }
      case 'combo-toggle': {
        const axis = btn.dataset.combo;
        if (S.combo.axis === axis) closeCombo(true);
        else openCombo(axis);
        break;
      }
      case 'combo-pick': {
        // same semantics the native selects had: ALL resets the axis to
        // null; year values are numbers; a campus change re-validates
        // the program filter (registry-driven cascade)
        const axis = btn.dataset.combo;
        const raw = btn.dataset.comboValue;
        const value = raw === ALL ? null : raw;
        if (axis === 'year') S.filter.year = value === null ? null : Number(value);
        else S.filter[axis] = value;
        if (axis === 'campusId' && S.filter.programId) {
          const stillOffered = S.registry.programs.some((p) =>
            p.id === S.filter.programId && (!S.filter.campusId || p.campusId === S.filter.campusId));
          if (!stillOffered) S.filter.programId = null;
        }
        S.combo.axis = null;
        S.combo.query = '';
        S.combo.hl = 0;
        S.combo.focusAfter = axis;
        render();
        break;
      }
      case 'set-category': {
        if (S.categoryBusy) break;
        const catId = btn.dataset.id;
        const catType = btn.dataset.type;
        const activity = visibleActivities.find((a) => String(a.id) === String(catId));
        if (!activity || activity.activity_type === catType || !ACTIVITY_TYPES.includes(catType)) break;
        S.categoryBusy = true;
        const catRoot = btn.closest('.a-cat');
        if (catRoot) catRoot.querySelectorAll('.a-cat-opt').forEach((b) => { b.disabled = true; });
        (async () => {
          try {
            const { data, error } = await sb.from('activities')
              .update({ activity_type: catType, category_locked: true })
              .eq('id', catId)
              .select('id, activity_type, category_locked');
            if (error) throw error;
            const updated = Array.isArray(data) ? data[0] : null;
            if (!updated) throw new Error('You can only correct categories for sections you teach.');
            activity.activity_type = updated.activity_type;
            activity.category_locked = updated.category_locked;
            const cacheKey = monthKeyString(S.visibleMonth);
            const cached = monthCache.get(cacheKey);
            if (cached) {
              const row = cached.find((x) => String(x.id) === String(catId));
              if (row) { row.activity_type = updated.activity_type; row.category_locked = updated.category_locked; }
            }
            toast({
              title: 'Category updated',
              description: `Now tracked as ${typeMeta(updated.activity_type).label}. Future Classroom syncs keep it.`,
            });
            if (catRoot) {
              catRoot.innerHTML = categoryRowHtml(activity);
              // the sheet header carries the type label as its first
              // segment - keep it in sync with the correction
              const headP = catRoot.closest('.dialog')?.querySelector('.dialog-head p');
              if (headP) {
                const parts = headP.textContent.split(' \u00b7 ');
                if (parts.length > 1) { parts[0] = typeMeta(updated.activity_type).label; headP.textContent = parts.join(' \u00b7 '); }
              }
            }
            render();
          } catch (error) {
            toast({
              title: 'Could not update the category',
              description: messageFromError(error),
              variant: 'destructive',
            });
          } finally {
            S.categoryBusy = false;
            if (catRoot) catRoot.querySelectorAll('.a-cat-opt').forEach((b) => { b.disabled = false; });
          }
        })();
        break;
      }
      case 'type-filter': {
        const t = btn.dataset.type;
        const idx = S.typeFilter.indexOf(t);
        if (idx === -1) S.typeFilter.push(t); else S.typeFilter.splice(idx, 1);
        render();
        // keep keyboard focus on the toggle after the re-render
        const again = document.querySelector(`.lg-btn[data-type="${t}"]`);
        if (again) again.focus();
        break;
      }
      case 'flag-filter': {
        const flag = btn.dataset.flag;
        if (flag === 'reported' || flag === 'past') {
          S.flagFilter[flag] = !S.flagFilter[flag];
          render();
          const again = document.querySelector(`.lg-btn[data-flag="${flag}"]`);
          if (again) again.focus();
        }
        break;
      }
      case 'clear-type-filter':
        S.typeFilter = [];
        S.flagFilter = { reported: false, past: false };
        render();
        break;
      case 'reset-filter':
        S.filter = { campusId: null, programId: null, year: null, block: null };
        render();
        break;
      case 'refresh':
        refresh();
        break;
      case 'activate-teacher':
        if (S.pendingTeacherSignup && !S.activateBusy) {
          S.activateBusy = true; S.activateError = null; render();
          activateTeacher(S.pendingTeacherSignup).then((result) => {
            S.activateBusy = false;
            if (!result.ok) { S.activateError = result.message; render(); }
          });
        }
        break;
      case 'close-overlay':
        closeOverlay();
        break;
    }
  });

  // the password eye toggle: swallowing mousedown keeps the caret in the
  // input while revealing (focus never leaves the field being typed in);
  // the click itself still fires normally
  document.addEventListener('mousedown', (e) => {
    if (e.target.closest && e.target.closest('.pw-toggle')) e.preventDefault();
  });

  document.addEventListener('input', (e) => {
    const el = e.target;

    // searchable filter combo: narrow the open panel's list as the
    // teacher types — repaint only the panel, never the whole app, so
    // the caret stays exactly where it is
    if (el.dataset && el.dataset.comboSearch) {
      const axis = el.dataset.comboSearch;
      if (S.combo.axis === axis) {
        S.combo.query = el.value;
        S.combo.hl = 0; // a fresh query restarts from the top match
        paintComboPanel(axis);
      }
      return;
    }

    if (el.dataset.draft) {
      S.authDraft[el.dataset.draft] = el.value;
      // live-enable the submit button while typing (it used to stay dead
      // until some other event triggered a full re-render)
      const form = el.closest('form[data-form="signup"]');
      if (form) updateSignupSubmit(form);
    }
  });

  // combo keyboard support: the search box owns the arrows + Enter; the
  // trigger rolls its panel down on ArrowDown; Tab rolls it up and moves on
  document.addEventListener('keydown', (e) => {
    if (!(e.target instanceof Element)) return;
    const comboEl = e.target.closest('.combo');
    if (!comboEl) return;
    if (e.key === 'Tab') { closeCombo(false); return; }
    const axis = comboEl.dataset.combo;
    const input = e.target.closest('.combo-input');
    if (!input) {
      // the trigger button: Enter/Space natively click (toggle); the
      // arrows roll the panel down directly
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        if (S.combo.axis !== axis) openCombo(axis);
      }
      return;
    }
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      const count = comboVisible(axis).length;
      if (!count) return;
      const dir = e.key === 'ArrowDown' ? 1 : -1;
      S.combo.hl = (S.combo.hl + dir + count) % count;
      paintComboPanel(axis);
    } else if (e.key === 'Enter') {
      e.preventDefault();
      const optBtn = document.getElementById(`combo-opt-${axis}-${S.combo.hl}`);
      if (optBtn) optBtn.click(); // reuses the combo-pick path verbatim
    } else if (e.key === 'Home') {
      e.preventDefault();
      S.combo.hl = 0;
      paintComboPanel(axis);
    } else if (e.key === 'End') {
      e.preventDefault();
      S.combo.hl = Math.max(0, comboVisible(axis).length - 1);
      paintComboPanel(axis);
    }
  });

  // a click outside the open combo panel rolls it back up (mousedown, so
  // it happens before whatever was clicked underneath acts)
  document.addEventListener('mousedown', (e) => {
    if (!S.combo.axis) return;
    if (e.target instanceof Element && e.target.closest('.combo')) return;
    closeCombo(false);
  });

  document.addEventListener('submit', (e) => {
    const form = e.target.closest('form[data-form]');
    if (!form) return;
    e.preventDefault();
    const kind = form.dataset.form;

    if (kind === 'signin') {
      if (S.signinBusy || S.stage === 'loading') return;
      const email = S.authDraft.email.trim();
      const password = S.authDraft.password;
      S.authError = null; S.authNeedsConfirm = false; S.resendInfo = null;
      S.signinBusy = true; render();
      signIn(email, password).then((message) => {
        S.signinBusy = false;
        if (message) { S.authError = message; render(); }
        // success → handleSession re-renders
        else if (S.stage === 'signin' || S.stage === 'loading') render();
      });
      return;
    }

    if (kind === 'signup') {
      if (S.signupBusy) return;
      const d = S.authDraft;
      S.signupError = null; S.signupNeedsDbPush = false; S.signupNeedsConfirm = false; S.resendInfo = null;
      S.signupBusy = true; render();
      signUpTeacher({
        firstName: d.firstName.trim(),
        lastName: d.lastName.trim(),
        email: d.email.trim(),
        password: d.password,
      }).then((result) => {
        S.signupBusy = false;
        if (result && !result.ok) {
          S.signupError = result.message;
          S.signupNeedsDbPush = !!result.needsDbPush;
          S.signupNeedsConfirm = !!result.needsConfirm;
          render();
        } else if (S.authMode === 'signup' && S.stage !== 'ready' && S.stage !== 'loading') {
          render(); // keep button state consistent
        }
        // ok:true → the session gate takes over; this card disappears
      });
      return;
    }
  });

  /* ================================= boot =============================== */

  render();

  // The registry is anon-readable, so the dashboard filter bar's
  // campus / program / year / block dropdowns can populate before any
  // account exists.
  S.registryLoading = true;
  fetchRegistry().then((registry) => {
    S.registry = registry;
    S.registryLoading = false;
    render();
  }).catch((error) => {
    S.registryLoading = false;
    S.registryError = messageFromError(error);
    render();
  });

  sb.auth.getSession().then(async ({ data }) => {
    if (!data.session) {
      if (S.stage === 'restoring') { S.stage = 'signin'; render(); }
      return;
    }
    await handleSession(data.session);
  });

  sb.auth.onAuthStateChange((event, session) => {
    if (event === 'SIGNED_OUT') {
      resetAfterSignOut();
    } else if ((event === 'SIGNED_IN' || event === 'TOKEN_REFRESHED') && session) {
      if (handledUid !== session.user.id) handleSession(session);
    }
  });
})();



