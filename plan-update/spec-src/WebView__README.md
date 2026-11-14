# WebView — Student Codex Teacher Dashboard

The teacher-facing web view of **Student Codex**, relocated to the project
root as a **fully self-contained static web app** — no server, no build step,
no Node.js required. This folder is the canonical home of the teacher
dashboard (the sandbox preview is only a mirror of these files).

## How to open it

**Option 1 — just double-click `index.html`.**
Everything the app needs is inside this folder:

- `vendor/supabase.min.js` — the Supabase client, bundled locally
- `vendor/lucide.min.js` — the icon set, bundled locally
- `styles.css` + `app.js` — the dashboard itself

Only the *data* goes over the network (live Supabase). Works in Chrome,
Edge, Firefox — and later inside the Android app's own WebView.

**Option 2 — serve it locally** (nicer URLs, closer to production):

```
# any static file server works, e.g.
python -m http.server 8080
# then open http://localhost:8080
```

## What it does

- **Sign in** for existing teacher accounts (demo: `demo.teacher@studentcodex.app` / `demo-teacher-123`).
  Both the sign-in and sign-up password fields carry an **eye toggle** (show/hide
  the password; the caret never leaves the field, keyboard-operable, re-hidden
  on tab switch or sign-out).
- **Create teacher account** (self-service sign-up): first/last name, email,
  password, then your **class groups** — four **multi-select dropdowns** fed
  by the live ParSU registry: Campus (optional filter), Program (all 50
  offerings, searchable), Year level and Block. Each dropdown stays
  **collapsed** (label + live summary + chevron, e.g. "BSCS", "2nd, 3rd",
  "A, B, C +5") and **rolls its checkbox panel down** only while open —
  click again, click outside, or press Escape to roll it back up; only one
  panel is open at a time. **Every checked combination instantly becomes a
  removable chip** (e.g. BSCS + 2nd year + blocks A,B → 2 classes in one
  gesture), so multi-class teachers no longer add classes one by one.
  Unchecking only changes the generator — remove a class with its ✕, or
  Clear all (which resets the checkboxes too); up to 12 per account (the
  RPC's cap, enforced with inline feedback). The `teacher_signup_multi`
  RPC (Supabase migration `20260101001600_teacher_signup_multi.sql`, live)
  grants the teacher role and enrolls the account in **every added group's
  sections** at once. Older single-group accounts (migration
  `20260101001300`) keep working; the activation card normalizes them.
  Sign-up is **instant and email-free** (0031): teacher eligibility is the
  **@parsu.edu.ph school email domain** — the sign-up form only accepts
  school addresses, and the role-granting RPCs enforce the same domain
  server-side (migration `20260101003100`, live), so no verification email
  is ever sent and no quota is consumed. Create account → teacher role →
  dashboard, in one submit.
- **Cohort filter bar** — Campus / Program / Year / Section dropdowns with a
  live "N of M sections · K scheduled in <month>" count, plus a one-tap
  Reset. Every dropdown lists the **full school registry** straight from the
  database (all 7 campuses, all 50 programs, 1st–5th year, blocks A–F/1–3 —
  never hard-coded), so you can pick any cohort; the count line and an
  inline note tell you when none of *your* sections match (row-level
  security still keeps the data itself limited to the sections you teach).
- **Month calendar** — assignments, quizzes, exams, projects and
  announcements are rendered *inside the day boxes* (date number top-left,
  type-colored uppercase chips below), with prev/next/Today navigation and
  a day-detail dialog (course · section · time · effort · description ·
  verification badge). The green month header carries the **interactive
  legend / category filter row** on its right side (under the month +
  prev/Today/next controls): the six type colors, the dashed
  student-reported mark and the dark-green past-due state — every entry is
  a one-tap filter toggle, with a Clear button while any filter is on.
  Pressing any chip, day-sheet item or feed row opens
  the **full activity sheet**, whose fact cards show the **deadline and the
  upload date side by side** ("Due Oct 9, 3:59 PM" / "Posted in Classroom
  Oct 7, 2:45 PM"). For Google Classroom entries the upload card reads
  **when the work was posted in Classroom itself** — Google's own
  `creationTime`, carried in `activity_sources.source_meta.
  classroomCreationTime` by the classroom-sync function — not the sync
  time; rows synced before the field existed read "Unknown" until the next
  sync backfills it. Manual/student-reported entries show the app upload
  time. Past-due values tint red, upcoming green; `today ·`/`yesterday ·`
  stamps match the Android app.
- **Student-reported feed** — read-only. When a student reports a
  face-to-face, not-in-Classroom activity in the app, it publishes
  STRAIGHT onto the calendar (a "Student-reported" badge + dashed chip
  outline mark the origin). Teachers never approve anything — the
  dashboard is view-only by design.
- **Past due = done** — entries are never deleted: the day after their due
  date they gray out (chips, day sheets, feed rows) to read as "done";
  due-today stays live until midnight. The header legend documents it.
- **Data coverage** — Classroom sync state, last refresh, and the privacy rule.

## File map

| File | Role |
|---|---|
| `index.html` | Entry point — shell, overlays, toasts, script loads |
| `styles.css` | The full design system (deep-green `#2f5b41` brand palette) |
| `app.js` | All logic: auth gate, registry, session/role checks, calendar, reports, dialogs |
| `vendor/supabase.min.js` | `@supabase/supabase-js` v2 bundled as a classic script |
| `vendor/lucide.min.js` | Lucide icon set (UMD) |
| `README.md` | This file |

## Data & security model

Everything runs through the signed-in teacher's Supabase session with the
**publishable key only** — never a service key. Row-level security decides
what is visible: a teacher sees section-scoped activities for sections they
are enrolled to teach. **Personal student activities never appear here**
(the activities RLS keeps them private to their creator).

## Embedding in the Android app (later)

This folder is laid out so it can be dropped into
`app/src/main/assets/webview/` and loaded with a WebView
(`webView.loadUrl("file:///android_asset/webview/index.html")`) with
JavaScript enabled. The app already ships the same publishable key, so the
session model matches.

## Notes

- **Email confirmation is OFF** (flipped 2026-10-29 together with
  migration 0031; it was ON 2026-10-24→29 for click-only verification, and
  briefly off 2026-10-24 to unblock demo sign-ups — accounts from every
  window are grandfathered). A sign-up now receives a **session
  immediately**: no email is sent at all, so the built-in mailer's
  **2 auth emails per hour project-wide cap**
  (`[auth.rate_limit] email_sent = 2`, unmanaged by `supabase config
  push` — verified) can never block teacher sign-up. The mailer only
  matters again if confirmation is re-enabled or someone needs a
  password-reset email.
- **Teacher verification is the school email domain (0031)**: the
  role-granting RPCs (`teacher_signup_global` / `teacher_signup_multi`)
  require the caller's `auth.users.email` to end with **@parsu.edu.ph**
  (case-insensitive, exact suffix — `@notparsu.edu.ph` and
  `@sub.parsu.edu.ph` both fail). The address is read from the table via
  SECURITY DEFINER, so forged JWT claims are irrelevant; anon stays
  revoked (fail closed). 0030's `email_confirmed_at` gate is retired by
  0031 — with confirmation off, GoTrue auto-confirms every sign-up, so
  the domain is the single eligibility rule. The sign-up form enforces
  the same domain client-side (submit stays disabled with a hint until
  the address is a school one), and a server-side rejection surfaces as
  “Teacher accounts are for @parsu.edu.ph school email addresses.” The
  earlier click-only machinery (0029/0030) remains in the code as a
  dormant fallback: if confirmation is ever switched back on, sign-ups
  park on the “Confirm your email” waiting card with its Continue /
  Resend / 90 s background watch — but the domain, not the click, decides
  teacher eligibility either way. The typed 6-digit code path was fully
  removed in 0029.
- How the confirmation setting is managed (reversible, with the Supabase
  CLI from this repo): `supabase config pull` (syncs the hosted auth
  config into `supabase/config.toml`) → set `[auth.email]
  enable_confirmations = true/false` → `supabase config push`. That is
  how it was flipped OFF on 2026-10-29 for the 0031 domain-gate model
  (and ON earlier the same day). With confirmation back ON, sign-ups
  would park on the waiting card again — the domain gate still decides
  teacher eligibility regardless.
- Accounts created while confirmation was ON can simply sign in now. If
  one was created mid-sign-up (role not yet granted) and its address is
  on the school domain, the “Activate teacher access” card finishes the
  enrollment automatically; a non-school address is told to re-sign-up
  with its @parsu.edu.ph email.
- **Gmail / personal addresses can no longer create teacher accounts** —
  the school domain is the requirement (that is the point of 0031).
  Testing sign-up needs any address ending in @parsu.edu.ph.
- A multi-class demo teacher was created during verification:
  `multiclass.teacher@studentcodex.app` / `multi-class-123` (BSCS 2-A Goa +
  BSHM 1-B San Jose class groups — 6 enrollments). A second one exercises
  the checkbox quick picker: `checkbox.teacher@studentcodex.app` /
  `checkbox-123` (Cora Checkbox — BSCS 2-A + 2-B Goa, BSHM 1-B San Jose).
  A third exercises the dropdown picker: `dropdown.teacher@studentcodex.app` /
  `dropdown-123` (Dora Dropdown — BSCS 2-A Goa).
  Delete either under Dashboard → Authentication → Users when no longer
  needed.
