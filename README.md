# Student Codex

**A two-surface academic companion for Partido State University (Philippines):
an Android student app, a teacher web dashboard, and one shared Supabase backend.**

Students juggle deadlines from three disconnected places — Google Classroom,
face-to-face classes that never touch Classroom, and personal tasks. Student
Codex unifies them into **one trustworthy deadline list per section** (the
Activity Beacon), so two students in the same class finally see the same
picture of what's due — no matter where each deadline came from.

| Surface | Tech | Entry point |
|---|---|---|
| Android student app | Kotlin 2.2.10 + Jetpack Compose, single-Activity, online-first | `app/` |
| Teacher web dashboard | Standalone vanilla HTML/CSS/JS, no build step | `WebView/` (double-click `index.html`) |
| Shared backend | One Supabase project: Auth + PostgreSQL (RLS) + Edge Functions + Storage | `supabase/` |

## What's in this repository

| Folder | What it is |
|---|---|
| `app/` | The Android student app (package `com.example.studentcodex`, minSdk 26) |
| `WebView/` | Teacher dashboard — self-contained static web app with vendored libraries |
| `supabase/` | 33 versioned SQL migrations (RLS on every table) + 4 plain-SQL test suites |
| `docs/` | ADRs, architecture, PRD, Google Sign-In setup guide, offline-sync design |
| `.plan/` | `PLAN.md` v2.2 — the authoritative 2,587-line replication specification |
| `Document/` | Complete technical documentation + hackathon defense handbook (PDF) |
| `publish-branding/` | OAuth publishing steps + Play Store listing material |
| `School_Details/` | University registry sources (campuses, programs, years, sections) |
| `adminPanel/` | Placeholder — planned, not started |

The repo root also carries Windows PowerShell helper scripts used during
emulator/install development workflows; they are dev tooling, not product code.

## The student app in one minute

One sign-in gate (email + password, Google Sign-In, or guest mode) guards the
whole app. Behind it, four bottom tabs plus a pushed profile page and a
floating **Guidance Assistant** overlay that rides above every screen:

- **Home** — today's picture of what's due and what changed.
- **Activity Beacon** — the deadline hub: every activity you are responsible
  for, deduplicated across sources, grouped by due date (today / tomorrow /
  this week), with filters and a detail sheet. A silent on-resume refresh
  keeps it honest.
- **Community** — campus feed: posts (one image), likes, flat comments,
  reporting with five reasons. Anonymous-posting switch exists in the UI
  but is not persisted yet (see honest status below).
- **Settings** — profile, course enrollment, Google Classroom connection
  card, auto-sync toggle.

Two features carry the product:

1. **Google Classroom import & sync** (read-only). On-device Google consent,
   then two Deno Edge Functions (`classroom-import`, `classroom-sync`) pull
   courses, coursework and announcements into the section's shared list.
   Every item is keyed by a `source_key` (`google_classroom:{course}:{work}`)
   and upserted — **re-syncing never duplicates**; teacher category
   corrections are locked and survive every re-import.
2. **Instant-publish manual activities.** A deadline a teacher gave
   face-to-face is entered once by any student in the section and goes live
   for the whole section immediately (`scope='section'`,
   `verification_status='student-reported'`). No approval queue — one
   student's diligence benefits every classmate. Similar-activity prompts
   guard against accidental duplicates, and soft-delete is available for
   your own rows.

The **Guidance Assistant** is deliberately rule-based and deterministic:
keyword matching with explicit rule precedence, fixed suggested topics, and
an honest fallback — *"I do not have a reliable answer for that yet, and I
would rather not guess."* It never invents official policies or dates.

## The teacher dashboard in one minute

`WebView/` is a three-file static app (plus vendored `supabase.min.js` and
`lucide.min.js`) that runs by double-clicking `index.html` — no server, no
Node.js, no build step. Teacher sign-up is gated to `@parsu.edu.ph` accounts.

Inside: a university-wide cohort filter bar (campus → program → year →
section), a month calendar of section activities with six color-coded
categories (assignment, quiz, exam, project, announcement, other), day and
activity detail sheets, a student-reported feed, and a data-coverage card.

The killer interaction: **one-tap category corrections.** A teacher taps a
misclassified chip, picks the right category, and the correction is stamped
`category_locked` — the database records who corrected it, and every future
Google Classroom re-import respects the lock. Human judgment beats the
classifier, permanently. Corrections are RLS-restricted to sections the
teacher actually teaches.

## Architecture (as built)

```text
Android app (Kotlin 2.2, Compose, manual DI)
│  UI: Compose screens + ViewModels (StateFlow<UiState>)
│  Data: repository interfaces → data/supabase (supabase-kt 3.6.0)
│  Online-first: NO Room, NO WorkManager — one-shot loads + retry
▼  https (publishable key + user JWT)
Supabase (single project)
│  Auth (email+password, Google ID-token)
│  PostgreSQL + RLS on every table; security_invoker views
│  Storage: private bucket community-images
│  Edge Functions (Deno): classroom-import · classroom-sync · site
│        service-role stays inside the functions; tokens transit-only
▼                                    ▼
Google Classroom API (read-only)    Teacher dashboard (WebView/)
   OAuth via on-device consent        same Supabase project + RLS
```

Three load-bearing decisions (full reasoning in `docs/ADR-001`):

1. **Supabase-first.** One project; the Auth UUID is `profiles.id`; RLS on
   every API-exposed table; Edge Functions are the only privileged path.
2. **Online-first Android.** The originally planned Room/WorkManager
   cache-outbox was deliberately not built; every screen is a one-shot load
   with retry. The offline design survives as `docs/OFFLINE-SYNC.md` (planned).
3. **Instant-publish community model.** Student-reported section activities
   go live immediately; there is no approval queue anywhere in the product.

## Data model in brief

Full column-level inventory: `.plan/PLAN.md` §7.2 (33 tables' worth of
schema across 33 migrations; key ones below).

- **Registry** — `campuses` (7 seeded), `programs` (50 seeded),
  `year_levels` (1st–5th), `year_sections` (blocks A–F / 1–3): clean cohort
  data powering sign-up dropdowns and teacher filters.
- **`profiles` / `user_roles`** — identity and role (student / teacher /
  moderator / admin), admin-managed roles.
- **`courses` / `sections` / `enrollments`** — self-service course creation
  with a tiered resolver (exact link → normalized name → fuzzy match →
  create). The catalog grows itself as students enroll.
- **`activities`** — the heart: title, six categories, due date, scope
  (`personal` / `section` / `course`), verification status
  (`imported` / `teacher-confirmed` / `student-reported`), soft delete,
  effort estimate (1–10,080 minutes), category lock.
- **`activity_sources`** — provenance and **dedup**: partial-unique
  `source_key` upserts; clients cannot forge `google_classroom` rows.
- **Community** — `posts`, `comments` (nesting to depth 5 in the DB; flat in
  the app), likes, blocks, `content_reports` moderation model.
- **`google_connections`** — per-user Classroom sync state
  (connected / `disconnected` / revoked / expired, last sync status).

RLS mirrors the product's privacy boundary everywhere: teachers see
section-scoped records across campuses and programs; **personal student
activities remain private by design**, and no workload analytics are
computed on humans.

## Getting started

### Prerequisites

- Android Studio with JDK 21 toolchain (auto-provisioned by Gradle).
- A Supabase project (Auth + Postgres + Edge Functions + Storage).
- For Google Sign-In / Classroom: a Google Cloud OAuth setup (below).

### Android app

1. Create `.env` at the repo root (git-ignored; parsed at build time into
   `BuildConfig` — names only, never commit values):
   - `SUPABASE_URL` (https, required)
   - `SUPABASE_PUBLISHABLE_KEY` (required — the build **fails** on secret or
     service-role keys)
   - `GOOGLE_SERVER_CLIENT_ID` (optional; if empty the Google button shows a
     setup dialog instead of failing)
2. Google OAuth (required for Google Sign-In & Classroom; full guide in
   `docs/GOOGLE-SIGNIN.md`): create a **Web** OAuth client (redirect
   `https://{project-ref}.supabase.co/auth/v1/callback`) for the Supabase
   Google provider, **and an Android client** with package
   `com.example.studentcodex` + your keystore's SHA-1
   (`gradlew signingReport`) — without the Android client, Play services
   refuses with GMS code 13 before any account picker appears.
3. Build and test (Windows host):

   ```powershell
   .\gradlew.bat :app:testDebugUnitTest    # unit suite
   .\gradlew.bat :app:lintDebug            # 0 errors expected
   .\gradlew.bat :app:assembleDebug        # debug APK
   ```

### Teacher dashboard

Open `WebView/index.html` by double-click (any static server also works).
Demo teacher/student accounts are seeded by migration and documented in
`WebView/README.md` — which is also the style reference for this file.

### Backend (Supabase)

```powershell
supabase link --project-ref {ref}
supabase db push        # apply migrations in order
supabase test db        # plain-SQL policy suites (local stack)
```

Migrations are append-only: **never edit an applied one** — add a fix
migration instead. Edge Function secrets (`SUPABASE_URL`,
`SUPABASE_SERVICE_ROLE_KEY`) are injected by the platform, never committed.
`client.json` at the root is the Google OAuth Web client download — it
contains a secret and must stay out of the app, the repo, and any docs; it
is pasted into the Supabase Google provider settings only.

## Testing & verification

- **Android:** 117 automated unit tests across 12 suites (auth, beacon,
  community, settings, home, guidance engine + overlay, auto-syncer, client
  factory) — 0 lint errors.
- **SQL:** 4 plain-SQL suites (RLS policies, Google Classroom source
  identity/dedup, RPC authorization) executed against local PostgreSQL 17
  over the full 33-migration chain (2026-10-30; results register in
  `.plan/PLAN.md` Appendix C).
- **Dashboard:** live browser verification of sign-in, calendar, day
  dialogs, activity sheet, category correction, legend filters, comboboxes
  and mobile layout (2026-10-28, re-audited 2026-10-31).

## Honest status register

This project documents its own truth (the seven-level status system in
`.plan/PLAN.md` v2.2). Notable items:

| Item | Status |
|---|---|
| Migrations 000000–002800 | Applied to the hosted project |
| Migrations 002900–003200 (email/domain gates, RPC EXECUTE hardening) | **Local only — not yet pushed** (0029–0031 gates superseded by the 0031 `@parsu.edu.ph` domain gate; 0032 hardening locally tested 2026-10-30) |
| Offline cache / outbox (Room + WorkManager) | Planned — design in `docs/OFFLINE-SYNC.md` |
| Push notifications / reminders | Deferred |
| Admin panel | Placeholder folder only |
| Comment nesting UI, comment-likes UI, moderator queue UI | Planned (DB-level support exists) |
| Anonymous posting | UI switch present; not persisted by the repository layer |
| Play Store listing material | Present in `publish-branding/` (publishing steps included) |

## Documentation map

- **`.plan/PLAN.md`** — the authoritative replication specification (v2.2):
  every feature, screen, token, migration, function and policy, with honest
  status labels and a test-evidence register (Appendix B/C).
- **`docs/`** — `ADR-001` (Supabase-first), `ADR-002` (env & client),
  `ARCHITECTURE.md`, `PRD.md`, `GOOGLE-SIGNIN.md`, `OFFLINE-SYNC.md`.
- **`Document/`** — complete technical documentation and the hackathon
  defense handbook (PDF).
- **`publish-branding/`** — homepage copy, privacy policy, steps to publish
  the OAuth consent screen and the Play listing.

## Product facts

- App label `Student Codex`; versionName 1.0; minSdk 26 (Android 8.0),
  targetSdk 36, compileSdk 37.
- All user-facing text is English; all date semantics pinned to
  **Asia/Manila** (UTC+8) — date-only due dates land at 23:59 Manila.
- Visual identity: "library green on warm paper" — deep green `#2F5B41` as
  the single accent on a warm paper canvas (never pure neutral).
- Registry reality: 7 campuses, 50 program rows, year levels 1st–5th,
  section blocks A–F and 1–3 — seeded by migrations from `School_Details/`.
