<!--
STUDENT CODEX — DOCUMENTATION SOURCE
====================================
Editable markdown source for the two generated PDFs:

  1. Student-Codex-Complete-Technical-Documentation.pdf
     (Parts I-VIII + X: Chapters 1-31 and 37-39)
  2. Student-Codex-Hackathon-Defense-Handbook.pdf
     (front sections + Part IX: Chapters 32-36 + Appendix)

Constrained markdown format: # / ## / ### headings, plain paragraphs,
"- " bullets, "1. " numbered items, | tables | (header row first),
fenced ``` code blocks, "> NOTE:" / "> WARNING:" callouts, **bold**,
*italic*, `inline code`. Figures 1-4 render from the generated PNG
diagrams (system architecture, sign-up sequence, dedup sequence,
ER overview).

Status labels are used verbatim throughout: BUILT & VERIFIED /
IMPLEMENTED — VERIFICATION INCOMPLETE / PARTIALLY IMPLEMENTED /
PLANNED / DEFERRED / KNOWN LIMITATION / UNRESOLVED.

Generated 2026-11-01 from the repository verified the same day.
Migration 0032 is locally tested and NOT deployed to the hosted
Supabase project (hosted at 0028).
-->


# STUDENT CODEX — COMPLETE TECHNICAL DOCUMENTATION

(source for Student-Codex-Complete-Technical-Documentation.pdf)

# Chapter 1 — Understanding Student Codex

This chapter is the entry point of the technical documentation. It defines what
Student Codex is, who uses it, the problem it was built to solve, and the shape
of the solution at the level of its four modules. Later chapters go deeper:
Chapter 2 maps each problem to the solution as it actually shipped, Chapter 3
describes the complete system architecture, Chapter 4 covers the technology
stack, and Chapter 5 walks the source tree. The project was built as a
hackathon entry, and this documentation is written for a reader who must defend
every claim to technical judges — capability statements use the project's
verified status labels, and factual claims carry evidence inline.

## 1.1 Project Identity

Student Codex is one product in three cooperating parts. The first part is a
native Android app, written in Kotlin with Jetpack Compose (Material 3), that
university students use to browse, record, and track academic activities. The
second part is the teacher dashboard: a self-contained static web application
in the `WebView/` folder — plain HTML, CSS, and JavaScript with two vendored
libraries, no build step, no framework, and no server of its own
(`WebView/README.md`). The third part is a single hosted Supabase backend that
both clients share: Supabase Auth, PostgreSQL with row-level security (RLS),
three Deno Edge Functions, and one private Storage bucket. The database schema
is defined by 33 versioned SQL migrations (Chapter 5 lists every range).

Around that core sits the fourth module: a read-only Google Classroom
integration. A student who consents links their Google Classroom account, and
their courses, coursework, and announcements are imported as read-only
activity records. The integration is deliberately import-only — Student Codex
never writes back to Google Classroom (Section 1.6 explains the boundary).

The deployment context is a single university, ParSU, identified by its
school-email domain `@parsu.edu.ph`. That domain is the server-side
eligibility gate for teacher registration (migration 0031), and the university
registry — campuses, programs, year levels, sections — is seeded in the
database and feeds every sign-up dropdown on both clients (migration 000700;
the school registry dropdowns are `BUILT & VERIFIED`).

Two user groups and one deliberate third state cover every account type.
University students are the primary users of the Android app: they enroll
through the sign-up form (or finish a Google-first account through profile
completion), import their Classroom courses, record face-to-face activities,
and read the Beacon. Teachers are the users of the web dashboard: they
register with a school-domain address, get the teacher role from the gated
RPCs, and read the university-wide calendar. The third state is the guest: an
unauthenticated visitor exploring demo content — guests can read but cannot
write to the community or the Beacon, so nothing in the product trusts a
session that does not exist.

| Module | Form | Primary users |
|---|---|---|
| Android student app | Kotlin + Jetpack Compose (Material 3) native app | Students |
| Teacher dashboard | Static web app in `WebView/` (no build step) | Teachers |
| Shared Supabase backend | Auth, PostgreSQL + RLS, 3 Edge Functions, 1 private Storage bucket | Both |
| Google Classroom integration | Read-only import via per-student OAuth | Students |

## 1.2 The Problem: Fragmented Academic Announcements

The problem Student Codex addresses is not a shortage of academic information —
it is that the information exists in fragments that no single tool assembles.
Four facets of that fragmentation matter, because each one maps to a specific
piece of the solution in Chapter 2.

### Google Classroom covers online coursework only

Google Classroom is where the online part of a course lives: assignments,
quizzes, and announcements that a teacher deliberately posts there. It holds
exactly what teachers type into it, and nothing else. A deadline that exists
only in a classroom discussion never becomes a Classroom post, so the record
students need is simply absent from the tool they are told to check.

### Face-to-face activities never reach Classroom

Universities also run on face-to-face instruction, and its announcements —
notes written on the board, deadlines given verbally in a lecture room, dates
agreed in a laboratory session — never reach Google Classroom at all. Students
copy them into personal notebooks, phone notes, or group chats, and the
fidelity of those copies decays with every retelling. There is no system of
record for this half of academic life, which is why it is the half students
forget.

### No university-wide workload visibility

Because the fragments live in different places, nobody can see the whole. A
student cannot see every recorded deadline across their enrolled sections in
one calendar, and a teacher cannot see whether the deadlines they set collide
with deadlines set by other teachers in other sections. No existing tool gives
university-wide visibility of recorded workload — that is a gap this project
names explicitly.

### Students juggle scattered announcements and miss deadlines

The practical result for a student is triage across scattered sources: check
Classroom, check the group chat, check last week's notes, and hope nothing was
missed. Under that load, deadlines are missed not because students are
careless but because no consolidated view exists to be careful with. This is
the user-facing pain the whole design answers.

## 1.3 The Proposed Solution

Student Codex consolidates every recorded academic activity into one shared
database table and gives that table two intake paths and two consumption
surfaces. The intake paths are, first, a read-only import of Google Classroom
coursework and announcements, and second, manual recording — a student or
teacher creates the face-to-face activity in the app, and it publishes to the
section instantly, with no approval queue (migration 0015). The consumption
surfaces are the Beacon, the student's consolidated list in the Android app,
and the teacher dashboard's month calendar, which shows recorded non-personal
activities university-wide.

Every activity row carries provenance labels, so the origin of each entry is
visible rather than guessed: a `source` (GOOGLE_CLASSROOM, MANUAL, or
STUDENT_REPORT) and a `verification_status` (`imported`, `teacher-confirmed`,
`student-reported`, or `needs_review`), rendered as badges in the app and as
chips on the dashboard. The verified core flow is:

1. Students import Classroom coursework and record face-to-face activities
   manually.
2. Both kinds of entry land in the shared `activities` table with provenance
   labels.
3. The Beacon list shows each student their consolidated activities, and the
   teacher dashboard calendar shows recorded activities university-wide
   (non-personal scope only).

Two honesty anchors come with that solution statement. First, the dashboard
shows recorded information only — no tool can guarantee that every real-world
university activity has been entered, and this one does not claim it. Second,
the app is online-first: there is no offline write path, and connectivity is
required for every read and write (offline cache is `PLANNED`).

## 1.4 Core Objectives

The objectives below are the measurable intent behind the solution; Chapter 2
shows the actual shipped status of each.

1. Consolidate every recorded academic activity — imported, teacher-created,
   or student-reported — into one shared `activities` table (migration 000200
   defines it; migrations 0021–0027 extend it for Classroom import).
2. Keep the origin of every entry visible through provenance labels and
   badges, so imported, teacher-confirmed, and student-reported work are never
   confused.
3. Let students publish face-to-face activities to their section instantly,
   with no approval queue anywhere (migration 0015).
4. Give teachers university-wide visibility of recorded non-personal
   activities across all sections, while personal student activities stay
   private to their creator (migration 0019).
5. Run both clients against one shared backend — a single source of truth with
   one RLS rule set and no cross-database sync (Chapter 3).
6. Complement Google Classroom with a read-only import, never a replacement
   (Section 1.6).
7. Stay honest about coverage and freshness: recorded is not the same as
   complete, and Classroom changes appear only at the next successful sync.

Read as a set, the objectives trade scope for verifiability. Nothing above
requires a background service, an offline engine, or a second database — each
of which would add a component the team would have to operate and defend
without adding a solved problem for the student. The chapters that follow
keep that discipline: what is claimed is what is built, and what is not built
is labeled, not implied.

## 1.5 The Four Main Modules

### The Android student app

The student app is a single-activity Compose application
(`MainActivity.kt:10-21`). Its main navigation is a Material 3 bottom bar with
four destinations — HOME, BEACON, COMMUNITY, SETTINGS (`ui/StudentCodexApp.kt`,
`TopDestination` enum at `StudentCodexApp.kt:61-66`) — plus a pushed Profile
route and a floating Guidance overlay above every page. The Beacon screen is
the consolidated activity list with filters and an editor; Settings carries
the Google Classroom connect, sync, and auto-sync cards. Authentication
(email/password, Google Sign-In, and a guest/demo mode), the Beacon, the
community feed, and the guidance assistant are `BUILT & VERIFIED`; Google
Sign-In via Credential Manager is `IMPLEMENTED — VERIFICATION INCOMPLETE`
(verified during development; not re-exercised in the 2026-10-30 pass).

### The teacher dashboard

The dashboard is a set of static files a teacher opens in a browser: sign-in
and self-service sign-up, a university-wide cohort filter bar, a month
calendar that renders activities inside the day boxes, a read-only feed of
student-reported activities, and a category-correction action. It is
`BUILT & VERIFIED` (browser-verified 2026-10-28) against the same backend the
app uses, with the same publishable key and the same RLS policies deciding
what each teacher may see (`WebView/app.js`).

### The shared Supabase backend

Both clients talk to one hosted Supabase project: Auth for sessions,
PostgreSQL with RLS for all data, three Edge Functions for the Google-side
work, and one private Storage bucket for community images. The schema is 33
versioned SQL migrations, numbered 000000 through 003200. One honesty anchor
belongs here: the hosted project has migrations through 0028 applied, and
0029–0032 exist locally only — migration 0032 (RPC privilege hardening) is
`IMPLEMENTED — VERIFICATION INCOMPLETE`, locally tested and NOT deployed to
the hosted project (roadmap item M2.1 is that deployment).

### The Google Classroom integration

The integration is implemented as two Edge Functions — `classroom-import`
(course picker) and `classroom-sync` (coursework and announcements) — calling
the Google Classroom REST API with per-student, user-level OAuth tokens that
are read-only and transit-only. Course import is `BUILT & VERIFIED`; sync is
`BUILT & VERIFIED` (live browser-verified 2026-10-28; the Edge Functions were
not re-exercised against real Google OAuth in the 2026-10-30 SQL run). Sync is
client-triggered only — on app open when the opt-in auto-sync toggle is on, on
a manual "Sync now", or through the import picker — with no background
service, no push, and no Pub/Sub anywhere in the codebase.

### How the four modules work together

The modules cooperate through the shared `activities` table rather than through
each other. A student-reported face-to-face activity and a Classroom import
both become rows in that one table, tagged with different provenance; the
Beacon reads it per student under RLS, and the dashboard calendar reads it
university-wide for non-personal rows under the same policies. When a teacher
corrects an imported activity's category, the correction locks that category
so later re-syncs cannot overwrite it (migration 0023). The full request flows
— who calls what, with which key — are the subject of Chapter 3.

## 1.6 Complementing Google Classroom, Not Replacing It

Student Codex COMPLEMENTS Google Classroom through a read-only import; it does
not replace it, and nothing in the codebase writes back to Google's side. The
OAuth scopes requested are read-only (classroom rosters and coursework), the
imported rows are read-only in the app, and the Google access token is minted
per sync on the student's device, travels in the request body, and is never
stored server-side. Classroom remains the system of record for online
coursework; Student Codex is the layer that consolidates it with everything
Classroom never sees.

This boundary is also a scope statement. Teachers keep using Google Classroom
exactly as they do today — posting online coursework there, announcing
face-to-face deadlines in the room — and Student Codex picks up both halves
through import and manual recording. The project does not manage coursework
submissions, grading, or Classroom administration, and it does not need
teachers to change their Classroom habits for the calendar to fill.

> NOTE: Read-only has one precise consequence worth defending: revoking
> Google access takes effect at the next sync, and a Classroom-side change
> (for example an edited deadline) is reflected only when a client-triggered
> sync next succeeds. There is no push from Google and no polling service.

## 1.7 What Student Codex Does Not Claim

The following boundaries are part of the design, not gaps in documentation, and
each one is stated where it is architecturally relevant in later chapters.

- Offline support: none. The app is online-first; every read and write needs
  connectivity. An offline cache with write sync (Room + WorkManager) is
  `PLANNED` and exists only as a design document (`docs/OFFLINE-SYNC.md`).
- Push notifications and reminders: `DEFERRED` (a placeholder row in
  Settings). Sync is client-triggered, so freshness depends on the client.
- Guidance assistant: a deterministic, rule-based engine — six keyword rules
  with precedence and an honest rephrase fallback — not an LLM
  (`domain/guidance/GuidanceEngine.kt`).
- Data coverage: recorded is not complete. The dashboard shows what students
  and teachers actually recorded or imported — a `KNOWN LIMITATION` stated on
  the dashboard itself.
- Teacher identity: email confirmation is OFF (a test configuration), and the
  `@parsu.edu.ph` domain suffix proves eligibility, not mailbox ownership;
  production identity verification is `UNRESOLVED` (Chapter 3 details the
  trust model).
- Duplicate manual reports: the editor prompts when a similar activity exists,
  but title-token matching does not guarantee manual dedup — a `KNOWN
  LIMITATION` (Chapter 2 contrasts it with the guaranteed import dedup).

Chapter 2 next turns the problem statement of Section 1.2 into a row-by-row
mapping of shipped solutions, with the evidence and the exact status label for
each.

---


# Chapter 2 — Problem-to-Solution Mapping

This chapter is the bridge between the problem statement (Chapter 1, Section
1.2) and the architecture that implements it (Chapter 3). Each row of the
mapping table states an existing problem, the solution Student Codex actually
built for it, the mechanism as verified in the source, and the shipped status.
Only problems the system actually addresses appear here — the residual issues
the current release does not solve are listed separately in Section 2.2, so a
reader never has to guess which is which.

Status labels are used verbatim from the project's seven-label system:
`BUILT & VERIFIED`, `IMPLEMENTED — VERIFICATION INCOMPLETE`, `PARTIALLY
IMPLEMENTED`, `PLANNED`, `DEFERRED`, `KNOWN LIMITATION`, `UNRESOLVED`.

The statuses below are not the writers' judgment calls; they come from the
verified feature inventory (PLAN.md v2.2, §1.2), the 2026-10-31 full-repo
audit, and live browser verification on 2026-10-28, re-verified against the
repository on 2026-11-01. Where a capability was verified during development
but not re-exercised in the latest pass, the label says so — no status is
upgraded beyond its evidence.

## 2.1 The Mapping Table

| Existing Problem | Student Codex Solution | How It Works | Actual Status |
|---|---|---|---|
| Fragmented academic activities | One shared `activities` table for every intake path | Imported, teacher-created, and student-reported rows land in the same schema; Beacon and the teacher calendar both read it | `BUILT & VERIFIED` |
| Face-to-face activities not in Classroom | Manual activity creation with instant section publish | Student reports a real `activities` row at once, `verification_status='student-reported'`; no approval queue (migration 0015) | `BUILT & VERIFIED` |
| Students struggling to track deadlines | Beacon list with date grouping, filters, detail sheet | One-shot fetch plus silent refresh on tab resume (BeaconViewModel.kt:123-131); newest-first LIFO ordering | `BUILT & VERIFIED`; reminders `DEFERRED` |
| No consolidated activity view | Per-student Beacon across all sources | One RLS-filtered query returns own, enrolled-section, and imported rows together (activities_select policy, migrations 0019/0020) | `BUILT & VERIFIED` |
| Teachers lacking cross-section visibility | University-wide teacher calendar with cohort filters | RLS grants teachers every non-personal section/course row (migration 0019); dashboard renders them in a month calendar | `BUILT & VERIFIED` |
| Duplicate imported activities | Source-key upsert dedup | `activity_sources.source_key` unique partial index; `upsert_activity_from_source` upserts on conflict, updating the shared row | `BUILT & VERIFIED` (gc_source_identity_test.sql) |
| Uncertain activity origin | Provenance labels and badges | `source` and `verification_status` columns resolved from the row (SupabaseActivityRepository.kt:203-213); ClassroomBadge / ManualBadge chips | `BUILT & VERIFIED` |

### Fragmented academic activities

The consolidation is physical, not presentational: there are not two stores
joined at display time, but one `activities` table (migration 000200) that
every intake path writes. An imported Classroom item, a teacher-created
deadline, and a student-reported board note become rows of the same shape —
title, description, type, scope, due date, effort, provenance — so the Beacon
and the dashboard calendar are two views of one data set. That single-table
decision is what makes the rest of this chapter's rows possible.

### Face-to-face activities not in Classroom

Recording is a first-class action, not an afterthought: the Beacon editor asks
for title, notes, type, due date, and one of the student's own sections (own
enrollments plus taught sections via `getMySections`), and
saving publishes straight to the section calendar — "reporting IS publishing,"
with no approval queue anywhere (Repositories.kt:14-24; migration 0015 header;
strings.xml:164 "No approval needed."). Teacher-created rows are stamped
`teacher-confirmed` and student rows `student-reported` by a guard trigger
that raises on role mismatch, so the label is enforced by the database rather
than trusted from the client.

### Students struggling to track deadlines

The Beacon gives the consolidated list: filters (including a Classroom-only
filter), date grouping, and a full-content detail sheet (BeaconScreen.kt,
ActivityDetailSheet.kt — Chapter 8 covers the Beacon end to end), with Home
showing upcoming activities. The list loads once and silently refreshes when
the tab resumes, keeping whatever is on screen during the fetch
(BeaconViewModel.kt:123-131). What this row does not claim is notification:
push notifications and reminders are `DEFERRED` (a placeholder row in
SettingsScreen), so the student still has to open the app.

### No consolidated activity view

Visibility per student is decided server-side by one policy: the
activities_select policy (current form from migrations 0019/0020) returns the
caller's own rows, rows of sections they are enrolled in, and rows of courses
they are enrolled in — imported and manual alike. The app therefore renders a
genuinely consolidated view from a single query rather than stitching several
endpoints together. Guests are a deliberate exception: they read demo content
only and cannot write to the Beacon or community.

Scope semantics keep the consolidation honest on both sides. A `personal`
activity is private to its creator — invisible to everyone else, teachers
included — while a `section` activity is visible to the section and, by
migration 0019, to all teachers university-wide. The Beacon therefore mixes
private reminders and shared class work in one list without ever leaking the
former, and the dashboard calendar renders only the latter.

### Teachers lacking cross-section visibility

Migration 0019 deliberately widens teacher reads to university-wide: any
teacher may read every non-personal (section- or course-scoped) activity,
while personal student activities remain invisible even to teachers. The
dashboard turns that into a month calendar with a cohort filter bar driven by
the live school registry (webview_app.js:1193-1237 filter bar; :1241-1298
calendar), so a teacher can look at any cohort's recorded load. One anchor
repeats here because it belongs to this row: the calendar shows RECORDED
information only — it is a `KNOWN LIMITATION` that real-world coverage is not
guaranteed, and the dashboard says so on its data-coverage card
(webview_app.js:1355-1410).

### Duplicate imported activities

Deduplication for imports is guaranteed by the database, not by application
logic. Every Classroom item is stored with a source key of the form
`google_classroom:{courseId}:{courseWorkId}` (or the announcement variant) in
`activity_sources`, under a unique partial index. The
`upsert_activity_from_source` RPC upserts on that key, so when Student B syncs
coursework that Student A already synced, the SAME shared row is updated —
repeated sync attempts never create a second record. The upsert is atomic and
retry-safe — `ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO
UPDATE`, with the partial-index predicate required — and a composite unique
on (provider, external_course_id, external_item_id) stands as a second guard.
This behavior is verified by `gc_source_identity_test.sql`, and the full
mechanism belongs to Chapter 3's sync flow.

### Uncertain activity origin

Origin is a stored attribute, not an inference: the `source` column
(GOOGLE_CLASSROOM / MANUAL / STUDENT_REPORT) and `verification_status`
(`imported` / `teacher-confirmed` / `student-reported` / `needs_review`) are
resolved from the row itself (SupabaseActivityRepository.kt:203-213) and
rendered as UI chips — a Google-branded green Classroom badge, a ManualBadge,
and verification chips in the app; type-colored chips and a "Student-reported"
badge on the dashboard. A teacher correcting a category cannot accidentally
launder an import either: the correction locks the category (migration 0023)
but the provenance columns stay intact across re-syncs.

## 2.2 Residual Issues This Release Does Not Solve

The problems above are solved to the status shown; the issues below are
explicitly not solved by the current build. They are the honest remainder of
the mapping, each with its verbatim status label.

| Residual issue | Status | Where it stands |
|---|---|---|
| Manual duplicates from similar student reports | `KNOWN LIMITATION` | Editor prompts on title-token similarity; nothing is merged or blocked |
| Complete real-world activity coverage | `KNOWN LIMITATION` | Dashboard shows recorded data only; entry depends on students and teachers |
| Freshness of Classroom changes | `KNOWN LIMITATION` | Reflected only at the next successful client-triggered sync |
| Offline access and write cache | `PLANNED` | Design exists in `docs/OFFLINE-SYNC.md` only (Room + WorkManager) |
| Push notifications / reminders | `DEFERRED` | Placeholder row in Settings; no FCM, no background service |
| Teacher workload analytics | `PLANNED` | DB view `section_workload_daily` exists; no client consumes it |
| Production teacher identity verification | `UNRESOLVED` | Domain suffix proves eligibility, not mailbox ownership; roadmap M2.3 |
| RPC EXECUTE hardening (migration 0032) | `IMPLEMENTED — VERIFICATION INCOMPLETE` | Locally tested, NOT deployed to the hosted project (hosted at 0028) |
| Anonymous community posting | `PARTIALLY IMPLEMENTED` | UI switch only; the flag is not persisted |

Two of these rows deserve one sentence each, because they are the ones judges
probe. The manual-duplicate row is the mirror image of the import dedup above:
title-token matching asks the student "is this the same activity?" but does not
enforce an answer, so two students can still report the same deadline twice.
The migration 0032 row is a deployment-state fact, not a design gap — the
privilege revokes are written, tested locally, and scheduled for hosted
deployment as roadmap item M2.1.

The teacher-identity row has one more nuance worth stating here rather than
leaving it implicit: the email-click verification machinery from migrations
0029–0030 still exists in the code as a dormant fallback, but the current gate
is the `@parsu.edu.ph` domain check, and email confirmation is OFF as a test
configuration. A production decision on identity verification has not been
made — that is exactly what the `UNRESOLVED` label is for.

Chapter 3 next describes the machine behind this table: every component, its
responsibilities, and the exact request flows that make each solution row
work.

---


# Chapter 3 — Complete System Architecture

This chapter describes the system as it is actually built and verified — not an
aspiration diagram. It lists every component and its responsibilities, explains
why both clients share one backend, and then walks the four real request flows
with the keys and tokens each one uses. The chapter closes with the precise
content of the system-architecture diagram (Figure 1) and the architectural
non-goals that judges most often ask about. File-level locations for everything
named here are in Chapter 5; technology choices are defended in Chapter 4.

## 3.1 The Big Picture

There are exactly two clients and one backend. The clients are the Android
student app (Kotlin + Jetpack Compose, using the supabase-kt library) and the
teacher dashboard (a browser running static files from disk, using vendored
supabase-js). The backend is a single hosted Supabase project exposing four
services to those clients: Auth (GoTrue), the PostgREST data API over
PostgreSQL with row-level security, Edge Functions (Deno), and Storage (one
private bucket, `community-images`). One external system completes the
picture: the Google Classroom REST API, which only the Edge Functions ever
call, using per-student, user-level OAuth tokens.

Two structural decisions follow from that shape. First, all authorization is
server-side: both clients hold only the publishable key, and RLS decides every
row each session may read or write. Second, there is no second database and no
synchronization job between databases — the teacher dashboard and the student
app read and write the same tables under the same policies, so a student's
report is visible on a teacher's calendar the moment it is committed.

## 3.2 Components and Their Responsibilities

| Component | Responsibility | Key evidence |
|---|---|---|
| Android student app | Student UX: auth gate, Beacon, community, settings; triggers Classroom import/sync | MainActivity.kt; ui/StudentCodexApp.kt |
| Teacher dashboard (browser) | Teacher sign-in/up, cohort filters, month calendar, category corrections | WebView/app.js |
| Supabase Auth (GoTrue) | Sessions (email/password, Google ID token); fires the profile/role/enrollment triggers | handle_new_user trigger (migrations 0017/0018/0027) |
| PostgreSQL + RLS | All tables, policies, guard triggers, SECURITY DEFINER RPCs | migrations 000000–003200 |
| PostgREST | The data-API surface both clients call; RLS filters every row | verified flows below |
| Edge Functions (Deno) | Server-side Google Classroom access and privileged RPC calls; public site | functions/classroom-import, classroom-sync, site |
| Storage | Community post images in one private bucket | bucket community-images (migration 000500) |
| Google Classroom API | External source of courses, coursework, announcements (read-only) | REST, user-level OAuth scopes |

### The Android student app

The app is a single-activity Compose client whose only network doorway is the
supabase-kt client built once in the manual DI container with the project URL
and the publishable key — never a secret key (AppContainer.kt:57-62). Its
responsibilities are the student-facing surfaces (Home, Beacon, Community,
Settings, Profile) and the triggering of Classroom work: the import picker at
sign-up and in Settings, the manual "Sync now", and the opt-in auto-sync that
runs on app open via a lifecycle observer (StudentCodexApp.kt:215-234). The UI
and ViewModels never see Supabase or HTTP — repository interfaces are the
boundary (Repositories.kt:6-9), which is what keeps the app testable with
fakes.

### The teacher dashboard

The dashboard is static files served from disk — no server, no build step
(`WebView/README.md`). Its responsibilities are teacher authentication and
self-service registration, the university-wide cohort filter bar, the month
calendar with day-detail dialogs, the read-only student-reported feed and
data-coverage card, and category corrections on activities in taught sections.
Every data operation goes through supabase-js with the publishable key, so the
dashboard has no privileged path of its own; RLS is what makes it a teacher
tool rather than a student tool.

### Supabase Auth

Auth owns sessions: email/password sign-in for both clients, and the Google
Sign-In path in the app, where a Google ID token from Android Credential
Manager is exchanged for a Supabase session. Auth is also the trigger point for
onboarding — the `handle_new_user` SECURITY DEFINER trigger fills `profiles`,
derives the username, grants `user_roles`, and enrolls the student through
`enroll_student_courses` (migrations 0017/0018/0027). One test-configuration
fact belongs here because it shapes every statement about registration: email
confirmation is OFF (`supabase/config.toml`, enable_confirmations = false), so
a sign-up receives a session immediately.

### PostgreSQL with RLS (behind PostgREST)

The database is the system's source of truth and its authorization engine.
Its tables carry the registry (campuses, programs, year levels, sections),
the academic graph (courses, sections, enrollments), the activity domain
(activities, activity_sources, activity_groups), the community domain (posts,
comments, likes, reports), and the Classroom link registry (google_connections)
— the full domain-grouped inventory is in Chapter 5. Every client-exposed table
has RLS enabled with explicit policies (for example activities_select, current
form from migrations 0019/0020; activities_insert from migration 0015), anonymous
is denied everywhere (policies_test T03), and guard triggers enforce invariants
the policies cannot express (for example guard_activity_insert raising P0001 on
scope or role violations).

### Edge Functions

Three Deno Edge Functions run server-side, and they exist for exactly one
reason: work that must not happen in a client. `classroom-import` (197 lines)
lists a Google account's ACTIVE courses and imports the picked ones through the
`import_student_classroom_courses` RPC. `classroom-sync` (405 lines) imports
coursework and announcements of linked courses as read-only `imported`
activities through `upsert_activity_from_source`, normalizes due dates to
Asia/Manila 23:59 (fixed +08:00; fn_classroom-sync.ts:30), and maintains the
`google_connections` registry. `site` (192 lines) serves the public home page
and privacy policy, which exist because Google OAuth consent-screen verification
requires authorized-domain branding URLs. The two Classroom functions are the
only code that holds the service-role key.

### Storage

One private bucket, `community-images`, holds community post images under an
own-folder layout `{uid}/{postId}/{ts}.jpg` (migration 000500 defines the
bucket and its four storage policies). Uploads and downloads are authenticated
only — the policies allow writes inside the owner's folder and reads to any
authenticated user, and nothing is public. The app posts one image per post
even though the schema allows three; the mismatch is documented in the
community material and is a deliberate app-side limit.

### Google Classroom API

The Classroom API is an external REST system reached with user-level OAuth
tokens carrying read-only scopes (rosters and coursework). It is never called
from the Android app or the dashboard directly — all calls happen inside the
Edge Functions, server-side, with the access token the student's device minted
for that run. The token is transit-only: no refresh tokens are held, no client
secrets ship in the app, and revoking access on the Google side takes effect at
the next sync.

## 3.3 The Actual Request Flows

The four flows below are the verified traffic of the system. One global fact
frames them: the Android app makes ZERO direct RPC calls — its data access is
REST tables plus Edge Function invocations, nothing else.

### Android reads and writes

1. The app calls PostgREST through the supabase-kt client (postgrest-kt) with
   the publishable key and the user's session JWT attached.
2. PostgREST maps the request to SQL against the target table.
3. RLS evaluates the row-level policies for that authenticated user and filters
   or rejects accordingly — the Beacon query, the community feed views, and
   profile reads all pass through this same gate.
4. Writes follow the same path with insert/update policies and guard triggers;
   image bytes for posts go to Storage instead of PostgREST.

### Google Classroom course import

1. The student explicitly picks the Google account (system AccountPicker, 180s
   timeout — GoogleAccountResolution.kt:27, :59), then the on-device
   Authorization API consent sheet grants the read-only scopes and mints a
   short-lived access token.
2. The app calls the `classroom-import` Edge Function with `action:"list"` and
   the token; listing needs no Supabase session because the Google token alone
   authorizes it — Google returns only that account's own courses
   (fn_classroom-import.ts:4-10). The function is deployed --no-verify-jwt for
   exactly this reason.
3. The app shows the picker (ClassroomImportSheet); the student picks courses.
4. The app calls `action:"import"` with the picked ids plus its Supabase session
   JWT. The Edge Function verifies that JWT against /auth/v1/user — "that
   check is the security boundary that protects the RPC" (fn_classroom-import.ts:16-18)
   — and re-fetches the picked course ids from Google server-side.
5. The Edge Function invokes `import_student_classroom_courses` with the service
   key. The RPC resolves each course through its matching tiers (exact
   external_course_id link, normalized name match with the fuzzy
   `course_text_matches` tier, or a brand-new course row) and enrolls the
   student, under advisory locks (migrations 0022/0027).

### Google Classroom coursework sync

1. A sync is triggered by the client only: app open with the opt-in auto-sync
   toggle on (StudentCodexApp.kt:215-234), a manual "Sync now", or the import
   picker. Auto-sync requests the token silently, pinned to the chosen account,
   skips when consent is needed, never throws, and holds an AtomicBoolean
   in-flight guard (ClassroomAutoSync.kt:61).
2. The app calls the `classroom-sync` Edge Function with the session JWT in the
   Authorization header and the Google access token in the request body — the
   token is transit-only and never stored (fn_classroom-sync.ts:1-13).
3. The Edge Function verifies the session JWT via /auth/v1/user
   (fn_classroom-sync.ts:48-59).
4. For each linked course it fetches coursework and announcements from Google,
   normalizing due dates without a time to 23:59 Asia/Manila (fixed +08:00).
5. It calls `upsert_activity_from_source` with the service key: an atomic
   upsert keyed on `activity_sources.source_key`, so a new item INSERTs while a
   known item UPDATEs the same shared row — Student B syncing what Student A
   already synced never creates a duplicate. Locked categories survive
   (migration 0023).
6. It upserts the `google_connections` registry row and returns a summary JSON
   (imported / updated / classesTotal / matched / skipped); unmatched classes
   are skipped and reported, never force-created.

### Teacher dashboard

1. The browser loads the static files from disk; `app.js` creates the
   supabase-js client with the publishable key (webview_app.js:26-27, :239).
2. The teacher signs in with email/password through Auth; sign-up collects up
   to 12 class groups and calls `teacher_signup_global` (or legacy
   `teacher_signup_multi`) — webview_app.js:616, :2024, :2058-2059 — which
   grants the teacher role and enrolls the account, gated server-side by the
   `@parsu.edu.ph` domain check (migration 0031).
3. Every subsequent read goes through PostgREST under RLS: the calendar query
   returns all non-personal section/course rows visible to teachers
   university-wide (migration 0019), and personal student activities never
   appear.
4. Category corrections are PATCHes to `activity_type` on activities in taught
   sections, which RLS restricts and which stamp `category_locked`
   (webview_app.js:2189-2222; refusal path :2206).

## 3.4 Why One Shared Backend

The single-backend decision is the architecture's load-bearing wall, and it
earns its place three ways. First, one source of truth: there is exactly one
`activities` table, so the Beacon, the dashboard calendar, and every future
client consume the same committed rows — there is no merge step in which a
student report and a teacher's calendar can disagree. Second, one RLS rule
set: the policies that keep personal activities private and grant teachers
university-wide non-personal visibility are written once and enforced for both
clients; the dashboard cannot accidentally show more than the app allows,
because neither can bypass the database. Third, no cross-database sync: with
one database there is nothing to reconcile, no sync workers to operate, and no
eventual-consistency window between what a student posted and what a teacher
sees.

The trade-offs were accepted consciously. A single hosted project is a single
failure domain and a single region — the app is online-first by the same
logic. And because both clients depend on the hosted schema, schema changes
are migration-numbered and reviewed as one history (Chapter 5) rather than
coordinated across services.

## 3.5 Keys, Tokens, and Trust Boundaries

The system distinguishes authentication from authorization, and the sentence
worth defending is: signing in never makes anyone a teacher. A session proves
identity; the teacher role exists only as `user_roles` rows granted by the
gated registration RPCs and triggers; RLS enforces per-row access; EXECUTE
privileges gate the RPCs. The keys and tokens each live exactly where they
should:

- Publishable (anon) key — public by design; RLS is the boundary. Embedded in
  the app through BuildConfig after Gradle rejects any secret or service-role
  value (app_build.gradle.kts:98-133, :151-167) and in the dashboard as plain
  constants (webview_app.js:26-27).
- Service-role key — lives ONLY in Edge Function server context as an
  environment variable (fn_classroom-sync.ts:44-46; fn_classroom-import.ts:41-43);
  it never ships in any client.
- Supabase session JWT — attached automatically by both client libraries;
  verified again server-side by the Classroom Edge Functions through
  /auth/v1/user before any privileged RPC runs.
- Google access token — minted per run on the student's device, travels in the
  request body, is used in transit only; no refresh tokens and no client
  secrets exist in the app, and the Google OAuth client_id is a public
  identifier (supabase/config.toml, [auth.external.google]).

> NOTE: Migration 0032 tightened this model after the F1/F2/F3 audit: three
> SECURITY DEFINER RPCs that were executable by any authenticated user were
> REVOKED from authenticated (migration 0032:43-53), leaving the Edge Function
> service path and the auth trigger path as the only callers. 0032 is locally
> tested and NOT deployed to the hosted project — the hosted project runs
> migrations through 0028 (roadmap M2.1/M2.2 is deploy and verify).

Two further honesty anchors complete the trust picture. Teacher registration
currently relies on the `@parsu.edu.ph` domain suffix, which proves
eligibility, not mailbox ownership, and production identity verification is
`UNRESOLVED` (roadmap M2.3). And `client.json` at the repository root holds a
live OAuth client secret — flagged in the audit, treated as a credential, and
slated for cleanup under roadmap item M2.5; its values are never reproduced in
this documentation.

## 3.6 Figure 1 — System Architecture

**Figure 1 — System architecture** (placeholder: the diagram generator renders
exactly the nodes and arrows described here).

The diagram shows five top-level nodes. Node 1: the student's Android device
running the Student Codex app (Kotlin + Jetpack Compose; supabase-kt client
holding the publishable key). Node 2: the teacher's browser running the Student
Codex dashboard (vanilla HTML/CSS/JS static files served from disk — no server;
vendored supabase-js). Node 3: the Supabase hosted project, drawn as one group
containing four sub-nodes — Auth (GoTrue), PostgreSQL with RLS behind the
PostgREST data API, Edge Functions (Deno: classroom-import, classroom-sync,
site), and Storage (private bucket `community-images`). Node 4: the Google
Classroom API, drawn as an external system. Node 5 (annotation, not a box): the
public home page and privacy policy served by the `site` Edge Function, which
has no data-flow arrows in this diagram.

The arrows, each labeled, are:

- Android app → Auth: email/password or Google ID token sign-in; session JWT
  returned.
- Android app → PostgREST: table reads and writes with the publishable key and
  the user's session JWT; RLS filters every row (no direct RPC calls).
- Android app → Edge Functions: classroom-import and classroom-sync
  invocations; Supabase session JWT in the Authorization header, Google access
  token in the request body (transit-only).
- Android app → Storage: authenticated upload and download of community post
  images into the caller's own folder (`{uid}/{postId}/{ts}.jpg`).
- Teacher dashboard → Auth: email/password sign-in.
- Teacher dashboard → PostgREST: table reads and category-correction PATCHes
  via supabase-js with the publishable key; RLS decides visibility.
- Edge Functions → Google Classroom API: server-side fetches of courses,
  coursework, and announcements using the per-student read-only OAuth token.
- Edge Functions → PostgreSQL: privileged RPC calls with the service-role key
  (`import_student_classroom_courses`, `upsert_activity_from_source`).

There is no arrow from either client to the Google Classroom API, no arrow
between the two clients, and no arrow from any client directly to the RPC
layer — those absences are the architecture's security statement.

## 3.7 Architectural Non-Goals

The architecture deliberately does not contain the following, and each absence
is verifiable in the source rather than merely asserted. There is no background
sync, no push, and no Pub/Sub: zero matches across the functions and
migrations, so a Classroom change waits for the next client-triggered sync.
There is no offline write path: the app is online-first, and the offline cache
(Room + WorkManager) is `PLANNED` design only (`docs/OFFLINE-SYNC.md`). There
is no second database or replication topology, per Section 3.4. There is no
server-side rendering or API layer of our own beyond the Edge Functions — the
two clients speak Supabase's APIs directly under RLS. And the guidance
assistant is a deterministic in-app rule engine, not a model call
(GuidanceEngine.kt), so no inference traffic appears in any flow above. The
consequences of these choices for the technology list are the subject of
Chapter 4.

---


# Chapter 4 — Technology Stack

This chapter covers every technology the system actually uses — and, just as
deliberately, the well-known technologies it does not. The stack is small on
purpose: a hackathon-scale team must be able to explain each dependency to a
judge, so nothing is included that the product does not exercise. The inventory
below is the complete list; nothing outside it appears in the build. Where each
technology lives in the source tree is Chapter 5's job; this chapter explains
what each one is, why it is there, and what its limits are.

## 4.1 Stack at a Glance

| Technology | Purpose | Where It Is Used | Why It Is Used |
|---|---|---|---|
| Kotlin + Jetpack Compose (Material 3) | Native Android UI | Android app | Declarative single-activity UI; Material 3 components; no XML layouts |
| supabase-kt (BOM 3.6.0) + ktor-client-okhttp 3.4.3 | Typed Supabase client (auth, data, storage, functions) | Android app | Community Kotlin client; one BOM pin keeps modules version-aligned |
| play-services-auth (Credential Manager + Authorization API) | Google Sign-In; Classroom consent | Android app | On-device ID token; consent sheet mints short-lived access tokens |
| multiplatform-settings (russhwolf) | Key-value local persistence | Android app | The only local store needed: session, auto-sync toggle, overlay prefs |
| Vanilla HTML/CSS/JS + vendored supabase-js v2 + lucide | Teacher dashboard | `WebView/` | No build step; runs from disk; publishable-key client |
| Supabase platform (Auth, Postgres, RLS, Edge Functions, Storage) | Hosted backend | Cloud project | One source of truth; server-side authorization via RLS |
| 33 versioned SQL migrations | Schema, policies, RPCs | `supabase/migrations/` | Ordered, reviewable history; explicit security changes |
| Google Classroom REST API (user-level OAuth) | Read-only course/coursework import | Via Edge Functions | Per-student consent; read-only scopes; never called from clients |

## 4.2 Android App Technologies

### Kotlin + Jetpack Compose (Material 3)

In plain language: Compose is how every screen the student sees is drawn — the
UI is Kotlin code that describes the screen, and Material 3 supplies the
look-and-feel components (navigation bar, cards, chips, dialogs) so the app
looks like a current Android app without a design system of its own.

Why Student Codex needs it: the product is a student-facing mobile app, and
Compose is the current Android UI toolkit — it removes the two-language
(XML layout + Kotlin logic) split that a hackathon team cannot afford to
debug. The app is a single Activity (MainActivity.kt:10-21) with one Compose
tree, navigation handled by a NavHost over a four-destination enum
(StudentCodexApp.kt:61-66).

How it works here: the build targets compileSdk 37, targetSdk 36, and minSdk 26
(app_build.gradle.kts:137-144), with Java 11 bytecode compatibility
(:179-182). State flows from ViewModels through `collectAsStateWithLifecycle`,
and the Material 3 NavigationBar renders the bottom tabs. All Compose
artifacts come through the Compose BOM (app_build.gradle.kts:190-202).

Limitations: Compose UI is only as testable as the state behind it — the
project's answer is ViewModel-level unit tests (11 test files; see Chapter 5),
not screenshot tests. There is no multiplatform sharing; this is Android-only
code.

Defense answer: "One activity, one Compose tree, Material 3, current SDK
targets — the UI layer is the smallest part of the app because the
architecture keeps screens thin over repositories."

### supabase-kt (BOM 3.6.0) + ktor-client-okhttp 3.4.3

In plain language: supabase-kt is the library the app uses to talk to the
backend — signing in, reading and writing tables, uploading images, and
invoking Edge Functions. It is the app's single network doorway; nothing else
in the app opens a socket.

Why Student Codex needs it: the backend is Supabase, and a typed Kotlin client
removes hand-rolled REST plumbing. The community-maintained client is pinned
through a platform BOM so that auth-kt, postgrest-kt, storage-kt, and
functions-kt all stay version-aligned, with ktor-client-okhttp as the
HTTP engine aligned to that release — the pinned versions of record are the
supabase-kt BOM 3.6.0 and ktor-client-okhttp 3.4.3 (dependency block:
app_build.gradle.kts:204-221).

How it works here: exactly one client instance is built, lazily, in the manual
DI container — from the URL and the publishable key only:

```kotlin
val supabaseClient: SupabaseClient by lazy {
    createSupabaseClient(
        supabaseUrl = BuildConfig.SUPABASE_URL,
        supabasePublishableKey = BuildConfig.SUPABASE_PUBLISHABLE_KEY,
    )
}
```

(AppContainer.kt:57-62) The session JWT travels automatically in the
Authorization header; for Edge Function calls the Google access token rides in
the request body (app_build.gradle.kts:216-219).

What happens internally: postgrest-kt maps repository calls to PostgREST
requests that RLS filters server-side; auth-kt manages the session;
storage-kt uploads post images to the private bucket; functions-kt invokes the
Classroom Edge Functions. The Gradle build guarantees no privileged key can
ever reach this client — a secret or service-role value fails the build
outright (app_build.gradle.kts:98-133).

Limitations: it is community-maintained, not an official Supabase client, so
version alignment is the team's responsibility — hence the single BOM pin. The
Google Sign-In exchange path is `IMPLEMENTED — VERIFICATION INCOMPLETE`
(verified during development; not re-exercised in the 2026-10-30 pass).

Defense answer: "One Supabase client, built once with public values only, kept
behind repository interfaces — the build script rejects secret keys by
inspection before they can ship."

### play-services-auth: Credential Manager + Authorization API

In plain language: this is Google's Android machinery for two distinct jobs.
Credential Manager produces a Google ID token that Supabase Auth exchanges for
a session (Google Sign-In). The Authorization API shows the consent sheet that
grants the read-only Classroom scopes and returns a short-lived access token.

Why Student Codex needs it: both Google-touching features must happen on the
student's device with the student's explicit choice — the account picker with
its 180-second timeout is the visible proof of that choice
(GoogleAccountResolution.kt:27, :59).

How it works here: `CredentialManagerGoogleAuth` wraps sign-in and reports
not-configured when the web client ID is absent, so the auth gate shows a
setup notice instead of failing silently (AppContainer.kt:76-84);
`PlayServicesClassroomAuthorizer` wraps the consent sheet. The only embedded
Google value is the public web client ID (GOOGLE_SERVER_CLIENT_ID), which is
optional and format-checked at build time (app_build.gradle.kts:82-89).

Limitations: the ID-token path depends on correct Google Cloud configuration;
tokens from the Authorization API are per-run and expire, which is by design —
there are no refresh tokens anywhere.

Defense answer: "No client secret ever ships — the app holds a public client
ID, and every Classroom token is minted per run, used in transit, and
dropped."

### multiplatform-settings (russhwolf)

In plain language: this is a thin key-value store — on Android it is
SharedPreferences underneath — for the three things the app must remember
between launches: the session, the Classroom auto-sync toggle, and the
guidance-overlay preferences (AppContainer.kt:139-144).

Why Student Codex needs it: these are flags and a session handle, not queryable
data, so a database would be over-engineering. This is the ONLY local
persistence in the app — there is no Room and no DataStore (Section 4.5).

Limitations: it stores no activity data and no cache; if the device is offline,
there is nothing locally to show (online-first, `PLANNED` offline support).

Defense answer: "Local state is three settings and a session — we persist
exactly that, in SharedPreferences, and nothing else."

## 4.3 Teacher Dashboard Technologies

The dashboard is deliberately the opposite of a framework project: vanilla
HTML, CSS, and JavaScript, with two vendored libraries (`supabase.min.js`,
`lucide.min.js`) loaded as classic scripts from the `vendor/` folder
(webview_index.html:19-21). There is no bundler, no Node toolchain, and no
framework — `WebView/README.md` documents that opening `index.html` by
double-click runs the whole product, with only the data going over the network.

Why this is used: the teacher-facing surface is one authenticated calendar
page, and a build step would add a toolchain to explain and maintain for zero
product capability. The Supabase client is vendored so the folder works offline
from disk and behind strict networks; lucide is vendored for the same reason
(`WebView/README.md` file map).

How it works here: `app.js` (2,477 lines, 87 functions) contains all logic —
the auth gate, registry loading, session and role checks, the cohort filter
bar, the calendar, dialogs, and toasts — and creates the supabase-js client
with the publishable key (webview_app.js:239). Authorization is entirely RLS;
the script holds no secret of any kind.

Limitations: no type checking and no component model — the mitigations are
small scoped functions and the fact that the data layer is one client object.
A stale Phase-0 document claimed a React teacher website; that claim is
outdated and the folder contains no `.tsx` anywhere (the PLAN document is the
authority on current state).

Defense answer: "One static folder, two vendored libraries, no build step, and
RLS as the only authorization — the dashboard cannot leak what it has no
privilege to see."

## 4.4 Backend Technologies

### The Supabase platform

In plain language: Supabase is the entire backend as a service — user
accounts, a PostgreSQL database, serverless functions, and file storage — one
hosted project instead of four operated systems.

Why Student Codex needs it: the architecture (Chapter 3) requires one shared
backend with server-enforced row authorization, and Supabase provides Auth,
PostgREST, Edge Functions, and Storage with RLS as the single policy point for
both clients.

How it works here: Auth (GoTrue) issues sessions and fires the onboarding
triggers; PostgreSQL holds the table set with RLS on every client-exposed table
(the domain-grouped inventory is in Chapter 5); Deno Edge Functions run the two
Classroom functions and the public site function; Storage holds the single
private `community-images` bucket. The Google OAuth client for sign-in is
configured in `supabase/config.toml` ([auth.external.google] enabled, client_id
only).

Limitations: one hosted project is one region and one availability domain, and
it is a managed dependency — the app is online-first in part because of it.
Email confirmation is OFF (test configuration), and the hosted auth rate limit
is 2 emails per hour project-wide.

Defense answer: "We did not stand up an auth service, a database, and an
object store — we use one platform whose row-level security is the security
boundary for both clients."

### 33 versioned SQL migrations

In plain language: the entire backend — tables, policies, triggers, and
privileged functions — is expressed as 33 ordered SQL files, numbered 000000
through 003200, so every change to the data model is reviewable and
replayable in order.

Why Student Codex needs it: security changes must be auditable line by line.
When the F1/F2/F3 audit found three over-privileged RPCs, the fix was a pure
privilege migration — revokes, no body changes — that a reviewer can read in
seconds:

```sql
revoke execute on function public.teacher_signup(uuid, integer, uuid, uuid)
  from authenticated;
```

(migration 0032:43-45, with the other two revokes at :47-53)

How it works here: the migrations build the core schema (000000–000800), demo
seeds (000900–001100), then the feature history — student self-publish (0015),
university-wide teacher visibility (0019), Classroom import and category
locking (0021–0027), teacher registration gates (0028–0031), and the RPC
hardening (0032). The hosted project has migrations through 0028 applied;
0029–0032 exist locally only.

Limitations: migration 0032 is `IMPLEMENTED — VERIFICATION INCOMPLETE` —
locally tested against a replicated platform surface, NOT deployed to the
hosted project. The full range table with purposes is in Chapter 5.

Defense answer: "Every table, policy, and privilege is a numbered migration —
including the security fixes, which are pure revokes you can audit in one
screen."

### Google Classroom REST API (user-level OAuth)

In plain language: Classroom's web API lets a program read the courses,
coursework, and announcements of the Google account that consented — and that
is all Student Codex asks of it, with read-only scopes.

Why Student Codex needs it: it is the only way to consolidate the online half
of academic announcements without teachers doing extra work; the import is
per-student, consented, and read-only.

How it works here: only the Edge Functions call the API, server-side, with the
per-run access token from the student's device; due dates without a time are
normalized to 23:59 Asia/Manila (fixed +08:00; fn_classroom-sync.ts:30), and
items are upserted by source key so re-syncs update rather than duplicate.

Limitations: read-only means read-only — Classroom-side changes appear only at
the next successful client-triggered sync, and revocation takes effect at the
same boundary. There is no push or Pub/Sub integration (`PLANNED` only as a
future roadmap item).

Defense answer: "We consume Classroom exactly as Google allows a student to:
their account, their consent, read-only scopes, and no writes back."

## 4.5 What Is Deliberately NOT Used

The absences below are decisions, not omissions, and each has a reason a judge
can be told. They also bound the current verification state — none of them is
half-wired into the build.

- No Room, no DataStore. The only local persistence is multiplatform-settings
  (SharedPreferences) for the session, the auto-sync toggle, and overlay
  preferences. An offline cache with write sync is `PLANNED` and exists only
  as the design document `docs/OFFLINE-SYNC.md` (roadmap M3.1); the app is
  online-first today.
- No WorkManager. Classroom auto-sync is a lifecycle observer that runs on
  ON_START when the student opted in (StudentCodexApp.kt:215-234) — grep finds
  zero WorkManager usage. Consequence: no background sync; freshness is
  client-triggered only.
- No FCM / push notifications. Reminders are `DEFERRED` — a placeholder row in
  Settings — because a hackathon scope cannot absorb a notification pipeline
  and the consent model it implies (roadmap M3.5).
- No React (or any JS framework). The dashboard is vanilla with vendored
  libraries; the Phase-0 architecture document's React claim is stale and the
  PLAN document supersedes it.
- No DI framework. `AppContainer` is a hand-written lazy-singleton container —
  "no DI framework for the MVP" (AppContainer.kt:36-38) — following the build
  plan's no-dependency-sprawl rule; tests inject fakes at the repository
  interfaces.
- No direct RPC calls from the app. The Android client speaks REST tables and
  Edge Functions only; privileged RPCs are reachable solely from the Edge
  Functions' service-key context (Chapter 3, Section 3.5).

> NOTE: The offline cache and push notifications are the two absences most
> likely to be challenged — the honest framing is scope: both are roadmap
> items (`PLANNED` / `DEFERRED`) with designs and placeholders already in
> place, not unknown unknowns.

Together with Chapter 3's flows, this stack list is the complete dependency
surface of Student Codex. Chapter 5 next maps it onto the actual source tree —
where each of these technologies and every responsibility above lives on disk.

---


# Chapter 5 — Application Structure

This chapter is the map of the source tree as it exists on disk. It covers the
three areas of the codebase in turn — the Android app under
`app/src/main/java/com/example/studentcodex/` (abbreviated `…/studentcodex/`
after this first use), the teacher dashboard under `WebView/`, and the backend
under `supabase/` — and closes with a lookup table that answers "where do I
read about X" for the topics judges and maintainers most often ask. Paths are
repo-relative; capabilities are stated with their verified status labels, and
the architecture behind this layout is Chapter 3.

## 5.1 Android App (…/studentcodex/)

### Entry point and application

The app has one activity: `MainActivity` fetches the DI container from
`StudentCodexApplication` and sets the single Compose root
(MainActivity.kt:10-21). The container is `di/AppContainer.kt`, a hand-written
lazy-singleton holder (no DI framework — AppContainer.kt:36-38) whose full
component list is the table at the end of this subsection. The one shared
Supabase client is built inside the container from BuildConfig values only
(URL and publishable key — AppContainer.kt:57-62), so no screen or ViewModel
can construct another.

### Navigation and app shell

`ui/StudentCodexApp.kt` is the app shell. Authentication is the gate before
navigation: the auth state machine moves CheckingSession → SignedOut
(AuthGateScreen) → CompletingProfile (ProfileCompletionScreen) → SignedIn, and
only the SignedIn state shows the main UI. The bottom bar is a Material 3
NavigationBar over the `TopDestination` enum:

```kotlin
enum class TopDestination(val route: String, val labelRes: Int, val icon: ImageVector) {
    HOME("home", R.string.nav_home, Icons.Rounded.Home),
    BEACON("beacon", R.string.nav_beacon, Icons.Rounded.TrackChanges),
    COMMUNITY("community", R.string.nav_community, Icons.Rounded.Forum),
    SETTINGS("settings", R.string.nav_settings, Icons.Rounded.Settings),
}
```

(StudentCodexApp.kt:61-66) A pushed `profile` route sits one tap below
Settings, and the floating `GuidanceOverlay` rides above every page
(StudentCodexApp.kt:303-309). The Classroom auto-sync observer also lives
here: on ON_START it asks the auto-syncer to run if the student's toggle is on
(StudentCodexApp.kt:215-234).

### Screens

| Screen | File | What it does |
|---|---|---|
| Auth gate | `…/studentcodex/ui/auth/AuthGateScreen.kt` | Sign-in / sign-up / guest; Google-first profile completion (:413) |
| Profile completion | `…/studentcodex/ui/auth/ProfileCompletionScreen.kt` | Completes Google-first accounts before entering |
| Home | `…/studentcodex/ui/home/HomeScreen.kt` | Upcoming activities with detail sheet |
| Beacon | `…/studentcodex/ui/beacon/BeaconScreen.kt` | Activity list, filters, editor, detail |
| Community | `…/studentcodex/ui/community/CommunityScreen.kt` | Feed, composer, comments |
| Settings | `…/studentcodex/ui/settings/SettingsScreen.kt` | Profile row, password, school details, Classroom connect/sync/auto-sync cards, deferred notifications row, sign-out |
| Profile | `…/studentcodex/ui/profile/ProfileScreen.kt` | Identity view only: name, email, program |

Each screen has its ViewModel beside it in the same package (AuthViewModel,
HomeViewModel, BeaconViewModel, CommunityViewModel, SettingsViewModel,
GuidanceViewModel), which is where the unit tests point (see the map at
Section 5.4).

### Components and domain models

Shared UI components live in `…/studentcodex/ui/components/`:
`ClassroomImportSheet.kt` (the course picker modal used at sign-up and in
Settings), `ActivityDetailSheet.kt` (full-content sheet with See more / See
less), `ClassroomBadge.kt` (the Google-brand green badge and ManualBadge
provenance chips), and the `rememberClassroomImportLauncher` wiring used by
the app shell. Domain models are deliberately small and UI-free:
`domain/model/Activity.kt` (the `Activity` model with the `ActivitySource`
enum — GOOGLE_CLASSROOM / MANUAL / STUDENT_REPORT — and newest-first LIFO
ordering), `Community.kt` (flat comment model), and `Profile.kt`.

### Utilities and string resources

Two small utilities complete the data layer. `AppContextHolder` attaches the
application context once at container creation so image uploads can resolve
picked photos through the ContentResolver, and `ContentResolverImageSource`
is the image-source abstraction the community repository consumes
(AppContainer.kt:43-46, :100). Date and text presentation helpers
(`Formatters`) sit with the components, and every user-visible label lives in
`strings.xml` — including the Beacon editor's share hint, which states the
no-approval rule in the product's own voice: "Shared with your course section
— your teacher and classmates see it on the calendar instantly. No approval
needed." (strings.xml:164).

### Repositories: the Supabase boundary

`data/repo/Repositories.kt` defines the interfaces the UI is allowed to see —
ActivityRepository, CommunityRepository, ProfileRepository,
ContentReportRepository, ClassroomConnectionRepository, ClassroomSyncRepository,
ClassroomImportRepository — plus the result/state types
(ClassroomSyncResult, ClassroomImportResult, ClassroomConnectionState). The
doc comment states the rule: "UI and ViewModels only ever see these
interfaces - never Supabase, Room, or HTTP details" (Repositories.kt:6-9).
Supabase-backed implementations live in `data/supabase/`
(SupabaseActivityRepository, SupabaseCommunityRepository,
SupabaseProfileRepository, SupabaseClassroomConnectionRepository,
SupabaseClassroomSyncRepository, SupabaseClassroomImportRepository, and the
client factory function `createSupabaseClient`), with
`data/school/SchoolDirectoryRepository.kt` feeding the registry dropdowns.

### Authentication and Google services

Authentication splits between Supabase and Google helpers in
`data/auth/`: `AuthRepository.kt` (interface) and
`SupabaseAuthRepository.kt` (email/password plus the Google ID-token path, and
guest state); `GoogleAuthManager.kt` with `CredentialManagerGoogleAuth`
(Credential Manager sign-in; reports not-configured when the client ID is
absent); `GoogleAccountResolution.kt` (the explicit account choice — system
AccountPicker, 180-second timeout); and `ClassroomAuthorization.kt` (the
consent sheet that mints read-only Classroom tokens).
`data/repo/ClassroomAutoSync.kt` holds the auto-syncer — silent token request
pinned to the chosen account, consent-needed skip, never-throws behavior, and
the AtomicBoolean in-flight guard (ClassroomAutoSync.kt:61).

### Manual DI container (complete component list)

| Component | Implementation | Role |
|---|---|---|
| `supabaseClient` | `createSupabaseClient(BuildConfig…)` | The single Supabase client (lazy) |
| `authRepository` | `SupabaseAuthRepository` | Email/password + Google ID token auth |
| `schoolDirectoryRepository` | `SupabaseSchoolDirectoryRepository` | Registry dropdowns; in-memory reference cache |
| `googleAuthManager` | `CredentialManagerGoogleAuth` | Credential Manager Google Sign-In |
| `activityRepository` | `SupabaseActivityRepository` | Beacon reads/writes through RLS |
| `communityRepository` | `SupabaseCommunityRepository` | Feed, posts, comments, likes, images |
| `profileRepository` | `SupabaseProfileRepository` | Profile read |
| `classroomConnectionRepository` | `SupabaseClassroomConnectionRepository` | `google_connections` state |
| `classroomSyncRepository` | `SupabaseClassroomSyncRepository` | classroom-sync Edge Function runs |
| `classroomImportRepository` | `SupabaseClassroomImportRepository` | Course list + import via Edge Function |
| `classroomAuthorizer` | `PlayServicesClassroomAuthorizer` | On-device Google consent sheet |
| `classroomAutoSyncStore` | `RusshwolfClassroomAutoSyncStore` | Auto-sync preference (Settings) |
| `classroomAutoSyncer` | `ClassroomAutoSyncer` | Silent ON_START re-import when opted in |
| `guidanceEngine` | `DemoGuidanceEngine` (eager) | Deterministic guidance rules |

All components are lazy singletons except the guidance engine, which is
created eagerly (AppContainer.kt:159). The repository interfaces are what the
unit tests target with fakes — the container itself needs no framework.

## 5.2 Teacher Dashboard (WebView/)

The dashboard folder is small enough to enumerate completely. It contains four
authored files plus two vendored libraries, per the README's own file map
(`WebView/README.md`), and nothing else runs the product:

| File | Role |
|---|---|
| `WebView/index.html` | Entry point: shell divs (#app, #overlays, #toasts) and the three script loads (1,204 B) |
| `WebView/styles.css` | The full design system, including the deep-green brand palette (47.5 KB) |
| `WebView/app.js` | All logic: auth gate, registry, session/role checks, calendar, reports, dialogs (2,477 lines, 87 functions) |
| `WebView/README.md` | How to open it, demo credentials, the data-security model, notes |
| `WebView/vendor/supabase.min.js` | `@supabase/supabase-js` v2 bundled as a classic script |
| `WebView/vendor/lucide.min.js` | Lucide icon set (UMD) |

`index.html` loads the vendored scripts before `app.js` and renders everything
into `#app` with dialogs mounting into `#overlays` (webview_index.html:13-21).
`app.js` creates the client with the publishable key (webview_app.js:239),
implements sign-in and gated sign-up — the client-side `@parsu.edu.ph` hint
(webview_app.js:35) in front of the real server-side gate (migration 0031) —
then the university-wide cohort filter bar (:1193-1237), the month calendar
with day-detail dialog and legend filters (:1241-1298, :1320-1342), the
full-content activity sheet (:1560+), the student-reported feed and
data-coverage card (:1355-1410), and category corrections that PATCH
`activity_type` and stamp `category_locked` (:2189-2222, refusal path :2206).

Sign-up deserves its own sentence because it is the dashboard's one write
path: the form collects names, email, and password, then up to 12 class
groups chosen from multi-select dropdowns fed by the live registry — every
checked combination becomes a removable chip — and one submit calls the
role-granting RPC (server-side cap enforced in migration 0016). An
activation card normalizes legacy single-group accounts created through the
older RPC (migration 0013). Demo teacher accounts and credentials are
documented in the README with their storage locations noted; this chapter
does not reproduce credential values.

The presentation layer is plain CSS discipline rather than a component
library: past-due entries gray out the day after their due date (they are
never deleted), the layout adapts to mobile widths, and errors surface as
toasts with explicit empty and error states. Password fields carry a
keyboard-operable show/hide eye toggle that re-hides on tab switch or
sign-out (`WebView/README.md`).

Workload summaries, aggregate analytics, and proposed-deadline preview are
absent by verification — zero matches in the code — even though the database
view `section_workload_daily` exists unused; those features are `PLANNED`.

## 5.3 Backend (supabase/)

### Migrations: 33 files, 000000–003200

The schema is expressed as 33 ordered SQL files in `supabase/migrations/`. The
range table below is the reading order for a reviewer:

| Migrations | Purpose |
|---|---|
| 000000–000800 | Core schema: profiles/roles, academics, activities, community, moderation, Storage bucket, school registry, phase views + `google_connections` |
| 000900–001100 | Demo seed data (fixed-UUID teacher, students, courses, sections, enrollments, activities, posts) |
| 001200 | `programs.campus_id` NOT NULL (campus binding) |
| 001300 / 001600 | Teacher signup RPCs: legacy single-group; multi-group ≤ 12 |
| 001500 | Student self-publish — no approval queue (activities_insert policy) |
| 001700 / 001800 | `enroll_student_courses`: course-code self-service enrollment |
| 001900 | University-wide teacher visibility (activities_select) |
| 002000 | Manila due-date repair |
| 002100–002700 | Classroom import: course matching tiers, category lock, cohort convergence |
| 002800 | OTP-gated teacher RPCs (superseded by later model) |
| 002900 / 003000 | Email-click verification; verified-email DB gate |
| 003100 | `@parsu.edu.ph` school-email domain gate (retires 0030's gate) |
| 003200 | RPC EXECUTE hardening (F1/F2/F3 revokes) — locally tested only |

> NOTE: The hosted project has migrations through 0028 applied; 0029–0032
> exist locally only. Migration 0032 is `IMPLEMENTED — VERIFICATION
> INCOMPLETE` — locally tested against a replicated platform surface, NOT
> deployed to the hosted project (deploy is roadmap M2.1, verification M2.2).

Key objects defined along that history: the table set below; the views
`feed_posts`, `my_posts`, `feed_comments` (anonymity-safe — the author is
nulled server-side) and `section_workload_daily` (no client consumes it); the
RPCs `upsert_activity_from_source`, `import_student_classroom_courses`,
`enroll_student_courses`, `teacher_signup_multi`, `teacher_signup_global`,
`suggest_activity_category`; the auth triggers `handle_new_user` and
`handle_user_profile_sync`; and the guard family
(guard_activity_insert/update, guard_post_update, guard_comment_insert,
the three rate guards, and the profile/connection guards).

The tables group into six domains, each introduced by the migrations named
in Section 5.3's range table:

| Domain | Tables | Introduced by |
|---|---|---|
| Identity and registry | `programs`, `profiles`, `user_roles`; `campuses`, `year_levels`, `year_sections` | 000000/000600, 000700 (+0012 campus binding) |
| Academic graph | `courses`, `sections`, `enrollments` | 000100 |
| Activity domain | `activities`, `activity_sources`, `activity_reports`, `activity_groups`, `activity_group_members`, `activity_participants` | 000200, 0023 |
| Community | `posts`, `post_images`, `comments`, `post_likes`, `comment_likes`, `user_blocks` | 000300 |
| Moderation | `content_reports` | 000400 |
| Classroom link | `google_connections` | 000800 |

One of those tables is legacy by the project's own record: `activity_reports`
carries the pending-to-matched workflow that migration 0015 drained when
instant student publishing replaced it, and the `activity_groups` family
completes the group/participation model in the schema. Neither appears in
the request flows of Chapter 3, which is the practical map of what the two
clients actually exercise — reading the migration history in order is how a
reviewer tells shipped-and-active from shipped-and-dormant.

### Edge Functions: three

| Edge Function | Size | Role |
|---|---|---|
| `supabase/functions/classroom-import` | 197 lines | List ACTIVE Google courses; import picked ids via `import_student_classroom_courses` (session JWT verified; service key) |
| `supabase/functions/classroom-sync` | 405 lines | Import coursework + announcements as read-only `imported` rows via `upsert_activity_from_source`; maintains `google_connections`; summary JSON |
| `supabase/functions/site` | 192 lines | Public home page + privacy policy at /functions/v1/site[/home\|/privacy] (OAuth branding requirement) |

The two Classroom functions verify the caller's Supabase session JWT through
/auth/v1/user before invoking anything privileged
(fn_classroom-import.ts:16-18; fn_classroom-sync.ts:48-59), and both use the
service-role key only inside their own server context.

### Security policies

RLS is enabled on every client-exposed table, and anonymous is denied
everywhere (policies_test T03). The load-bearing policies: activities_select
(current from 0019/0020 — own rows, participant, teacher university-wide for
section/course scope, or enrollment scope), activities_insert (0015 —
personal for students, section/course for teachers), activities_update
(owner-personal, section/course teacher for the category path, admin), and
the community set (own-row writes, moderator deletes, anonymity
immutability). Storage carries four policies (migration 000500): own-folder
inserts/updates/deletes and authenticated reads on `community-images`. Guard
triggers back the policies where row-shape invariants are needed — for
example guard_activity_insert raises P0001 on scope/role/enrollment
violations, and guard_activity_update stamps category locks.

Policy logic itself lives in SECURITY DEFINER helper functions with pinned
search paths — `has_role`, `is_enrolled`, `is_section_teacher`,
`is_course_teacher`, and `activity_visible_to_user` (the teacher branch of
the activities read rule) — so every policy evaluates the same predicates the
migrations established, and the two clients cannot drift apart on what a
teacher or a student may see. The full policy-by-policy walkthrough belongs
to the security chapter later in this documentation; the constraint that
matters for structure is that no policy exists outside
`supabase/migrations/`.

### Storage

One private bucket, `community-images` (migration 000500). Post images are
laid out under the uploader's own folder as `{uid}/{postId}/{ts}.jpg` at
position 1; the app posts one image per post even though the schema allows
three. Uploads and downloads are authenticated only — nothing in the bucket
is public, and guests cannot write anywhere in the product.

## 5.4 Source-Code Map

The table below is the fast lookup for the topics this documentation is most
often asked about. Repository-state caveat: the working tree is ahead of the
two committed revisions — the dashboard rework, migrations 0021–0032, the
classroom-import and site Edge Functions, and 4 new Kotlin files are
uncommitted working-tree state (repository hygiene is roadmap item M2.4), so
checkout-to-verified-state instructions belong to that roadmap item.

| If asked about… | Look at… |
|---|---|
| Android auth (email, Google, guest) | `…/studentcodex/data/auth/` (AuthRepository.kt, SupabaseAuthRepository.kt, GoogleAuthManager.kt, GoogleAccountResolution.kt); `…/studentcodex/ui/auth/` (AuthGateScreen.kt, ProfileCompletionScreen.kt, AuthViewModel.kt) |
| Activity Beacon | `…/studentcodex/ui/beacon/BeaconScreen.kt` + BeaconViewModel; `…/studentcodex/data/supabase/SupabaseActivityRepository.kt`; `…/studentcodex/domain/model/Activity.kt` |
| Community | `…/studentcodex/ui/community/CommunityScreen.kt` + CommunityViewModel; `…/studentcodex/data/supabase/SupabaseCommunityRepository.kt`; migrations 000300/000800 |
| Guidance assistant | `…/studentcodex/domain/guidance/GuidanceEngine.kt` + DemoGuidanceEngine.kt; `…/studentcodex/ui/guidance/` (GuidanceViewModel.kt, overlay/) |
| Classroom import + sync | `…/studentcodex/data/repo/ClassroomAutoSync.kt`; `…/studentcodex/data/supabase/SupabaseClassroomImportRepository.kt`, SupabaseClassroomSyncRepository.kt, SupabaseClassroomConnectionRepository.kt; `supabase/functions/classroom-import`, `supabase/functions/classroom-sync`; migrations 0021–0027 |
| Teacher dashboard auth | `WebView/app.js` (auth gate; `teacher_signup_global` / `teacher_signup_multi` calls); migration 0031; `WebView/README.md` |
| Dashboard calendar | `WebView/app.js` (filter bar, month calendar, day dialog); migration 0019 |
| Category corrections | `WebView/app.js` set-category flow; migration 0023 (`category_locked`, `category_locked_by`) |
| Row-level security | `supabase/migrations/` (000200, 0015, 0019, 0020, 000300 policy blocks); `policies_test.sql` |
| Migration history | `supabase/migrations/` — 33 files, 000000–003200 (range table above) |
| Tests | `app/src/test/java/com/example/studentcodex/` (11 unit-test files; PLAN cites 117 unit tests); `tests/rpc_authorization_test.sql` (per migration 0032's header) plus `gc_source_identity_test.sql`, `phase_completion_test.sql`, `policies_test.sql` |

That map, together with the range table in Section 5.3, is the complete
navigation surface of the repository. One more orientation aid helps a
reviewer verify the honesty anchors quoted throughout this part.

## 5.5 Where the Honesty Anchors Live

Every boundary this documentation states is checkable in the tree, and the
list below says exactly where:

- Email confirmation OFF: `supabase/config.toml`, enable_confirmations =
  false (config.toml:230) — a test configuration, reversible through the
  Supabase CLI; the hosted auth rate limit `[auth.rate_limit]` email_sent is
  2/hour project-wide (config.toml:198-200, dashboard-managed).
- Migration 0032 not deployed: `supabase/migrations/` holds 0029–0032 as
  local-only files while the hosted project runs through 0028 (NOTE above;
  roadmap M2.1/M2.2).
- Domain suffix is not ownership: migration 0031's suffix check reads the
  address server-side; production identity verification is `UNRESOLVED`
  (roadmap M2.3).
- Offline work is unbuilt and labeled so: `docs/OFFLINE-SYNC.md` describes
  future work only — no Room, no WorkManager in the build (Chapter 4).
- Stale documentation superseded: `docs/ARCHITECTURE.md` is Phase-0-era and
  claims a Room cache/sync outbox, a React teacher website, and Guidance as a
  fifth tab — none of which match the current tree; the PLAN document is the
  authority.
- Flagged credential: `client.json` at the repository root holds a live
  OAuth client secret (audit finding; roadmap M2.5; values never reproduced
  in this documentation).
- Repository state: the repository has two commits (the initial import and an
  auth-gate button tweak); the current product is uncommitted working-tree
  state (Section 5.4's caveat; roadmap M2.4).

With the five chapters of this part, a reader can now name the product and
its boundaries (Chapter 1), defend each solved problem (Chapter 2), draw the
architecture from memory (Chapter 3), account for every dependency (Chapter
4), and find any of it on disk (Chapter 5). The deep-dive chapters that
follow open these files in order: authentication and onboarding (Chapter 6),
the Home screen (Chapter 7), the Activity Beacon (Chapter 8), and the
community module (Chapter 9), with the Classroom pipeline and the teacher
dashboard in the chapters after them.

---


# Chapter 6 — Authentication and User Onboarding

Part II described the shared backend; this chapter opens Part III, the Android
student app, at its front door. Every screen described in Chapters 7 through 11
sits behind one gate: a single `AuthViewModel` owned by the app root decides
whether the student is restoring a session, signing in, completing a profile,
or already inside the app. The chapter follows the real code path only: what
the gate renders, what each button actually does, how a sign-up form's school
and course choices travel to the database inside auth metadata, and how the
resulting session is attached to every later request. Teacher registration is
explicitly out of scope here — it exists only on the web dashboard (see
Chapter 16).

## 6.1 What the auth gate is

The gate is not a screen but a state machine. `StudentCodexApp` (in
`app/src/main/java/com/example/studentcodex/ui/StudentCodexApp.kt`, cited
below as `…/ui/StudentCodexApp.kt`) constructs one `AuthViewModel` at the root
of the composition and switches over four states
(`…/ui/auth/AuthViewModel.kt:113-173` at the call site):

| Gate state | Meaning | Rendered by |
|---|---|---|
| `CheckingSession` | Cold start; a persisted Supabase session is being restored | `SessionRestoreScreen` (quiet spinner) |
| `SignedOut` | No session; sign-in / sign-up form | `AuthGateScreen` |
| `CompletingProfile` | A real session exists but the account has no name yet (first-time Google users, or an abandoned Google sign-up) | `ProfileCompletionScreen` |
| `SignedIn` | A real Supabase session, or the demo guest bypass | `StudentCodexMain` (bottom navigation) |

The states are the `AuthUiState` sealed interface
(`…/ui/auth/AuthViewModel.kt:80-143`); `SignedOut` additionally carries the
whole sign-up form state (mode, credentials, four school dropdown selections,
course-code chips, loading/error flags). One instance of the ViewModel lives at
the root, and the gate plus the Settings sign-out button are its only two UI
touchpoints (class KDoc, `…/ui/auth/AuthViewModel.kt:145-149`). On `init` it
does exactly two things: restore a session and load the school registry
(`…/ui/auth/AuthViewModel.kt:193-196`).

Session restoration is bounded, not indefinite. At cold start the supabase-kt
Auth plugin sits in `Initializing` while it loads the stored session, so
`SupabaseAuthRepository.currentSession()` waits up to two seconds
(`SESSION_RESTORE_TIMEOUT_MS = 2_000L`) for either `Authenticated` or
`NotAuthenticated`, then falls back to a snapshot that is null when nothing
was stored (`…/data/auth/AuthRepository.kt:201-214`). Sessions persist across
app restarts through the Auth plugin's default `SettingsSessionManager`
(SharedPreferences on Android) — the repository's KDoc calls out that no extra
code is needed for "stay signed in" (`…/data/auth/AuthRepository.kt:190-194`).
A restored account whose profile was never completed is routed straight into
`CompletingProfile`, not into the app
(`…/ui/auth/AuthViewModel.kt:747-756`).

## 6.2 Email and password accounts

### How it works

Signing in is a single call: `AuthViewModel.signIn()` trims the email,
validates shape (one `@`, no spaces) and a minimum password length of six —
Supabase's default — then delegates to `AuthRepository.signIn()`
(`…/ui/auth/AuthViewModel.kt:464-475`). The repository calls the supabase-kt
`signInWith(Email)` builder and maps failure shapes: Supabase reports duplicate
accounts through error codes (`email_exists`, `user_already_exists`,
`identity_already_exists`) or, on older servers, a plain "already registered"
message, and both shapes become one domain exception,
`DuplicateAccountException`, so the UI shows a single clear message
(`…/data/auth/AuthRepository.kt:216-231` and `:412-427`). The ViewModel
resolves that exception to `AuthError.EmailTaken`; other remote errors keep the
server's message because it is the most actionable text available
(`…/ui/auth/AuthViewModel.kt:794-797`).

Sign-up validates in a fixed order — email shape, both names present, all four
school dropdowns chosen, password length, password confirmation match, at
least one course code — each failure resolving to a typed
`AuthError.Validation` value that the screen turns into a localized string
(`…/ui/auth/AuthViewModel.kt:477-543`). Validation lives in the ViewModel on
purpose: the class KDoc separates local, translatable validation problems from
remote failures that carry the server's message
(`…/ui/auth/AuthViewModel.kt:31-35`).

### What happens internally

`SupabaseAuthRepository.signUp()` sends the email and password plus a JSON
`data` object of user metadata (the mechanism of Section 6.5). The return
value distinguishes two worlds: a null result or an active session means the
project auto-confirmed the address and signed the user in during the sign-up
call itself (`SignUpResult.SignedIn`); otherwise the account exists but email
confirmation is required (`SignUpResult.ConfirmationRequired`), and the
ViewModel switches back to the sign-in form with a notice explaining the
inbox link (`…/data/auth/AuthRepository.kt:233-282`;
`…/ui/auth/AuthViewModel.kt:515-535`).

> NOTE: In the current test configuration email confirmation is OFF
> (`supabase/config.toml` `enable_confirmations = false`), so the hosted
> project follows the auto-confirm path and `ConfirmationRequired` is the
> dormant branch. The code handles both because the hosted project's
> configuration can change without an app rebuild.

## 6.3 Google Sign-In via Credential Manager

Google Sign-In on Android uses the modern Credential Manager API, not the
retired `GoogleSignInClient`. Its status in this project is IMPLEMENTED —
VERIFICATION INCOMPLETE: it was verified during development, but it was not
re-exercised in the 2026-10-30 verification pass (FACTBASE §3).

The flow has two halves. On the device, `CredentialManagerGoogleAuth` builds a
`GetGoogleIdOption` with the web-application client ID from
`GOOGLE_SERVER_CLIENT_ID` (a BuildConfig value, optional) and
`setFilterByAuthorizedAccounts(false)` so every Google account on the device
is offered, first-time users included
(`…/data/auth/GoogleAuthManager.kt:85-97`). The KDoc records the audience
rule: the ID token's audience is the *Web application* OAuth client ID — the
same client ID the Supabase dashboard's Google provider is configured with —
and for Play services to mint such a token the app's package name and SHA-1
signing fingerprint must be registered in the same Google Cloud project
(`…/data/auth/GoogleAuthManager.kt:65-78`). On the Supabase side,
`SupabaseAuthRepository.signInWithGoogleIdToken()` exchanges the token through
the `IDToken` provider with `provider = Google`, and Supabase creates the
account on first use, so one call covers both "sign in" and "sign up"
(`…/data/auth/AuthRepository.kt:284-305`).

Failure taxonomy is explicit because each failure has a different fix.
`GoogleAuthOutcome` distinguishes `NotConfigured` (no web client ID in the
build — the gate shows a setup dialog explaining the developer-side steps,
`…/ui/auth/AuthViewModel.kt:563-566`), `Cancelled`, `NoAccount` (no Google
account on the device, typical of a fresh emulator), `Rejected` (Google Play
services GMS code 13, meaning the package/SHA-1 registration is missing —
surfaced with the docs pointer, `…/data/auth/GoogleAuthManager.kt:119-127`),
and generic `Error`
(`…/data/auth/GoogleAuthManager.kt:16-45`). The ViewModel maps each to an
`AuthError.Google` variant resolved to strings in the UI
(`…/ui/auth/AuthViewModel.kt:586-601`).

### The Google-first completion path

A first-time Google user lands in `CompletingProfile`, because a brand-new
Google account reports `SessionInfo.profileCompleted = false`
(`…/ui/auth/AuthViewModel.kt:572-581`). One form then collects first and last
name (prefilled from the Google profile name mirrored into user metadata —
the first word becomes the first name, the rest the last name,
`…/ui/auth/AuthViewModel.kt:815-821`), a password when the account has no
email credential yet, the same school dropdowns as sign-up, and course codes.
Submitting calls `AuthRepository.completeGoogleProfile()`, which performs one
`auth.updateUser` call carrying the optional password plus the same metadata
payload as sign-up (`…/data/auth/AuthRepository.kt:307-340`). The
`handle_user_profile_sync` trigger reacts to the metadata update and finishes
the account server-side (Section 6.5). "Sign out instead" on that form revokes
the half-finished session and returns to the gate, and the next Google
sign-in asks again (`…/ui/auth/AuthViewModel.kt:659-670`).

## 6.4 Guest mode

"Explore without an account" is a UI state, not an account. Tapping it calls
`AuthViewModel.signInAsGuest()`, which simply publishes
`AuthUiState.SignedIn` with `SessionInfo(userId = null, email = null,
isGuest = true)` (`…/ui/auth/AuthViewModel.kt:676-681`). The guest session
exists only in memory and never touches Supabase — it is the explicit
explore-without-an-account path (SessionInfo KDoc,
`…/data/auth/AuthRepository.kt:30-35`). Guests browse demo content and cannot
write: the Beacon replaces its add button with a signed-out notice, the
Community composer opens in read-only explainer mode, and the repositories
additionally reject a missing session (`BeaconScreen.kt` guest branch;
`SupabaseCommunityRepository.kt` session checks). Signing out as a guest is
labeled "Exit demo mode" in Settings and skips the remote revoke because
there is no session to revoke (`…/ui/auth/AuthViewModel.kt:683-698`).

## 6.5 The sign-up form: registry dropdowns and course chips

The sign-up form collects names, email, password with confirmation, and — the
part specific to Student Codex — a school identity assembled from database
registries, never hardcoded values. The school directory (programs, campuses,
year levels, year sections) is loaded by `SchoolDirectoryRepository` from the
database and cached in memory as reference data (AppContainer KDoc;
`…/di/AppContainer.kt:67-74`); while the first fetch is in flight the
dropdowns render disabled, and a failed fetch shows an inline error with a
retry (`SchoolDirectoryState`, `…/ui/auth/AuthViewModel.kt:70-78`).

The four questions are ordered campus → program → year level → section, and
the order is load-bearing: choosing a campus narrows the Program dropdown to
that campus's offerings, and a program the new campus does not offer is
dropped so the stale id can never be submitted
(`…/ui/auth/AuthViewModel.kt:247-263`). The "multi-select class groups" of
the outline are the course chips: a searchable picker where a row tap or a
typed entry adds a course chip. Known codes canonicalize against the registry
case-insensitively and duplicates fold silently; unknown codes are accepted
as typed because the catalog cannot list every subject a real semester
offers — the server creates the course (and the cohort section) from the code
at save time (`…/ui/auth/AuthViewModel.kt:284-322`). Removing a chip only
stops the code from being submitted, because the enrollment door server-side
is append-only (`…/ui/auth/AuthViewModel.kt:324-329`). The Google completion
form reuses the same four school handlers and the same course picker
(`…/ui/auth/AuthViewModel.kt:221-269`).

The Classroom import launcher is available at sign-up as well as later in
Settings. Because the gate forms cannot enroll anything yet (no session),
picked Classroom courses land as sanitized course-name chips, and the token
plus picked ids are stashed; when the account exists,
`runPendingClassroomImport()` runs the real import through the Edge Function
and one immediate sync, deliberately silent — the chips already enrolled the
courses by name at submit, so a failure here changes nothing the next sync
cannot heal (`…/ui/auth/AuthViewModel.kt:331-434` and `:711-738`). The full
import mechanics belong to Chapter 11 and the Classroom chapter
(Chapter 12).

## 6.6 Auth metadata as the enrollment transport

This is the chapter's most important mechanism, so it is worth stating in
plain language first: the app never enrolls anyone directly. It writes the
student's answers into the *user metadata* that Supabase Auth stores with the
account, and database triggers read that metadata and do the enrollment. The
metadata is the transport; the triggers are the worker.

### How it works

`SupabaseAuthRepository.signUp()` attaches this payload
(`…/data/auth/AuthRepository.kt:253-263`):

```json
{
  "first_name": "…", "last_name": "…", "full_name": "…",
  "profile_completed": true,
  "program_id": "…", "year_level": 1,
  "campus_id": "…", "year_section_id": "…",
  "course_codes": ["…", "…"]
}
```

The key names are shared constants deliberately kept in step with the SQL
triggers (`META_*` companion constants,
`…/data/auth/AuthRepository.kt:465-478`). When Supabase Auth creates the
user, the `handle_new_user` trigger — a SECURITY DEFINER function — fills the
`profiles` row, derives a unique username through
`derive_username`/`claim_username`, grants the student `user_roles` row, and
enrolls the student via the `enroll_student_courses` RPC, which creates any
missing course from its code (self-service creation with a fuzzy matching
tier), converges classmates onto the same course and section rows with
advisory locks, and caps the code list at 32 (FACTBASE §7; migrations
0017/0018/0027). The same RPC call path is why the app itself makes zero
direct RPC calls: the enrollment RPC is invoked by the trigger in the
database, not by the client (FACTBASE §4).

`profile_completed` is the flag that keeps first-use and later updates
coherent. `SessionInfo.profileCompleted` is derived from the metadata key
(`…/data/auth/AuthRepository.kt:438-439`), and `hasEmailCredential` from the
app-metadata `providers` array (`:440-441`) — the two facts the completion
form needs.

### The metadata update path

Two screens write metadata updates rather than a new account, and both rely
on the second trigger, `handle_user_profile_sync`. First, the Google
completion form's `completeGoogleProfile()` writes names, school references,
course codes, and optionally a password (Section 6.3). Second, the Settings
school-details sheet's `updateSchoolDetails()` writes `profile_completed`,
the four school references and the codes — with names deliberately absent, so
the coalescing trigger leaves first/last name and username exactly as they
were, while the codes re-run the idempotent enrollment door
(`…/data/auth/AuthRepository.kt:364-382`). In both cases
`handle_user_profile_sync` re-runs the profile fill and enrollment on the
metadata update (FACTBASE §7).

### Limitations

Email confirmation is OFF in the test configuration, so a sign-up is a live
account immediately; the `ConfirmationRequired` branch is dormant. Google
Sign-In carries the project's IMPLEMENTED — VERIFICATION INCOMPLETE label
above. And because enrollment travels through metadata, a sign-up performed
while the school registry failed to load cannot happen at all — the form
requires all four dropdowns chosen, which is the honest failure rather than
an account with no cohort.

## 6.7 How the session is used for backend requests

After the gate, every repository call rides one shared supabase-kt client.
The client is built once from build-time configuration carrying the Supabase
URL and the publishable key only — never a secret key
(`…/di/AppContainer.kt:48-62`). The supabase-kt client attaches the
authenticated session's JWT to each PostgREST and Storage request, and
PostgREST evaluates row-level security with `auth.uid()` for every table
access (FACTBASE §4). In practice this means the app can ask broadly — the
Beacon repository selects all non-deleted rows from `activities` with no
per-user filter — and RLS returns exactly the rows the signed-in student may
see (Chapter 8). The publishable key being public is by design: RLS is the
boundary, not key secrecy (FACTBASE §15).

Authentication and authorization stay separated: signing in does not make
anyone a teacher. Roles come only from `user_roles` rows granted by the gated
RPCs and triggers, and RLS enforces per-row access (FACTBASE §15). The app
side of that split is visible here: nothing in the auth gate requests or
stores a role — the student sign-up path simply never grants one, and an
account that holds a teacher role earned it on the dashboard (Chapter 16).

## 6.8 Who performs each operation

| Operation | Performed by | Evidence |
|---|---|---|
| Gate state machine + form validation | `AuthViewModel` | `…/ui/auth/AuthViewModel.kt:150-159` |
| Sign-in / sign-up / session restore | `SupabaseAuthRepository` (interface `AuthRepository`) | `…/data/auth/AuthRepository.kt:195-282` |
| Google ID token from the device | `CredentialManagerGoogleAuth` (interface `GoogleAuthManager`) | `…/data/auth/GoogleAuthManager.kt:79-140` |
| ID token → Supabase session | `SupabaseAuthRepository.signInWithGoogleIdToken` | `…/data/auth/AuthRepository.kt:284-305` |
| Google-first profile completion | `ProfileCompletionScreen` + `completeGoogleProfile` + `handle_user_profile_sync` | `…/ui/StudentCodexApp.kt:145-167` |
| School registry dropdown data | `SchoolDirectoryRepository` (in-memory cache) | `…/di/AppContainer.kt:67-74` |
| Account + profile + role + enrollment | Supabase Auth + `handle_new_user` trigger + `enroll_student_courses` | FACTBASE §7, migrations 0017/0018/0027 |
| Guest bypass | `AuthViewModel.signInAsGuest` (UI state only) | `…/ui/auth/AuthViewModel.kt:676-681` |
| Deferred Classroom import at sign-up | `ClassroomImportRepository` + `ClassroomSyncRepository` via `runPendingClassroomImport` | `…/ui/auth/AuthViewModel.kt:721-738` |
| JWT attachment + RLS evaluation | supabase-kt client + PostgREST | FACTBASE §4 |

## 6.9 Figure 2 — Sign-up and enrollment sequence

The following placeholder defines the diagram the documentation set renders
as Figure 2. Nodes are actors or database objects; arrows are calls or row
writes, labeled with the mechanism named in the verified sequence
(FACTBASE §20).

```text
FIGURE 2 (placeholder) — Sign-up and enrollment sequence

Nodes (left to right):
  [Sign-up form (AuthGateScreen / ProfileCompletionScreen)]
  [Supabase Auth (GoTrue)]
  [handle_new_user / handle_user_profile_sync triggers]
  [profiles] [user_roles] [enroll_student_courses]
  [App signed-in (StudentCodexMain)]

Arrows:
  1. Sign-up form -> Supabase Auth:
     signUp(email, password, metadata: names + school ids + course_codes)
  2. Supabase Auth -> trigger: user created fires handle_new_user
  3. trigger -> profiles: insert row (names, school references, username)
  4. trigger -> user_roles: grant 'student'
  5. trigger -> enroll_student_courses: enroll by course codes
     (creates missing courses, advisory locks, 32-code cap)
  6. Supabase Auth -> App signed-in: session JWT
     (auto-confirm path; ConfirmationRequired is the dormant branch)

Google-first completion path (dashed, parallel):
  G1. Google Credential Manager -> Supabase Auth: ID token
  G2. Supabase Auth -> App: session with profile_completed=false
  G3. ProfileCompletionScreen -> Supabase Auth: updateUser(metadata + password)
  G4. handle_user_profile_sync trigger -> profiles + enroll_student_courses
      (re-runs enrollment on the metadata update)
  G5. App signed-in
```

## 6.10 Limitations and defense

The honest list for this chapter: email confirmation is off (test
configuration), Google Sign-In is IMPLEMENTED — VERIFICATION INCOMPLETE, the
guest mode writes nothing by design, and sign-up requires a successful school
registry fetch because the cohort is never optional. None of these are hidden;
each surfaces in the UI or in this documentation. Defense answer for judges:
"Authentication is delegated entirely to Supabase Auth — Credential Manager
feeds it a Google ID token, email accounts go straight to GoTrue, and the app
never handles passwords beyond passing them through; the interesting engineering
is that enrollment travels inside auth metadata and is executed by database
triggers, so no client can forge an enrollment it was not entitled to."

Cross-references: the repository pattern behind every call is Chapter 5's
architecture; the Beacon visibility that the session unlocks is Chapter 8;
the Settings surface for school-detail re-enrollment is Chapter 11.

---


# Chapter 7 — Home Screen

Home is the start destination of the main app (`…/ui/StudentCodexApp.kt`,
`startDestination = TopDestination.HOME.route`), and it is deliberately the
smallest screen in this documentation: an overview that answers two questions
before the student taps anything — what is due soon, and what is happening in
the community — plus one entry point into the assistant. This chapter
describes only what the screen actually renders and where each value comes
from; the Beacon (Chapter 8), the community feed (Chapter 9), and the
Guidance assistant (Chapter 10) carry their own chapters.

## 7.1 What the screen displays

The content state is `HomeUiState.Content`
(`…/ui/home/HomeViewModel.kt:23-32`), and `HomeContent` renders it as a
single scrollable list (`…/ui/home/HomeScreen.kt:123-203`):

- A time-of-day greeting (`Good morning/afternoon/evening`, personalized with
  the signed-in student's first name when the profile fetch succeeded) and,
  under it, a plain-language workload summary: either "No deadlines in the
  next 7 days." or a pluralized count. The count is `dueSoonCount` — every
  upcoming deadline falling within the next seven days, not just the preview
  rows — so the number answers "how much is coming at me?" before any row is
  read (`HomeViewModel.kt:99-102`; strings in `res/values/strings.xml:119-126`).
- An "Upcoming deadlines" section with at most three rows
  (`HomePreviewCount = 3`, `HomeViewModel.kt:114`), each row showing the type
  icon, a two-line title, the Google Classroom provenance chip when the row
  was imported, a metadata line (course code and estimated effort when
  present), and a trailing due block with an urgency label and exact local
  time tinted error-red when overdue (`HomeScreen.kt:224-282`). When the
  list is empty the section renders an empty state instead; otherwise a
  "See all activities" button opens the Beacon tab
  (`HomeScreen.kt:162-171`).
- A "From the community" section with at most two recent posts
  (`CommunityPreviewCount = 2`, `HomeViewModel.kt:115`), each preview showing
  the author mark and name (or "Anonymous"), two lines of post text, and a
  quiet engagement line joining comment and like counts; tapping anywhere on
  the preview opens the Community tab (`HomeScreen.kt:323-373`).
- An "Ask a study question" button that does not navigate anywhere: it opens
  the floating Guidance assistant's chat panel — the same surface the chat
  head and the edge handle open (`HomeScreen.kt:191-202`;
  `…/ui/StudentCodexApp.kt:269-275`).

Two details are worth defending because they look like decoration but are
not. The greeting's clock is the school calendar's zone (Asia/Manila), the
same zone every due label runs on, so "Good evening" arrives with the Manila
evening whatever the device clock is set to; morning runs to noon,
afternoon to 18:00, evening after that (`HomeScreen.kt:388-404`). And the
row anatomy is flat and dense by design — no card wrappers — matching the
Beacon rows so the two lists read as the same data
(`HomeScreen.kt:219-282`).

### Screen states and empty states

The screen itself is a three-way `when` over the ViewModel state
(`HomeScreen.kt:92-102`): `Loading` renders `ActivityListSkeleton`, `Error`
renders the shared `ErrorState` component with a retry button, and `Content`
renders the list above. Inside `Content`, both sections have their own empty
texts — "Nothing due soon" with an explanatory message when no upcoming
activity exists, and the community empty state when nobody has posted
(`strings.xml:126-127`, `:196-197`) — so an empty overview still reads as a
state, not as a broken screen. Row taps carry an accessibility label that
names the activity being opened (`activity_detail_cd`, used as the
`onClickLabel` in `HomeScreen.kt:236-238`), the same convention the Beacon
rows follow.

## 7.2 Where the data comes from

One ViewModel aggregates three repositories, and the repositories are the
only things that know about the network
(`…/ui/home/HomeViewModel.kt:35-39`):

| Value | Source chain | Evidence |
|---|---|---|
| Upcoming activities | `HomeViewModel` → `ActivityRepository.getActivities()` → PostgREST `select` on `activities` (RLS-scoped) | `HomeViewModel.kt:84-86`; `SupabaseActivityRepository.kt:42-61` |
| Recent posts | `HomeViewModel` → `CommunityRepository.getRecentPosts()` → `feed_posts` view | `HomeViewModel.kt:87`; `SupabaseCommunityRepository.kt:53-61` |
| Greeting name | `ProfileRepository.getProfile()` → the signed-in student's `profiles` row | `HomeViewModel.kt:93-98` |

The upcoming list is computed, not served: the ViewModel takes the full
RLS-filtered activity list, keeps only rows whose `dueAt` is after now —
work that already lapsed is history, and the overview must never lead with
past deadlines — sorts by due date, and takes the first three
(`HomeViewModel.kt:79-108`). The profile fetch is best-effort by design: a
profile hiccup must never take the deadlines overview down with it, so the
greeting simply falls back to the no-name form (`HomeViewModel.kt:88-98`).
Guests get the same screen with no name in the greeting.

## 7.3 How it loads and refreshes

Loading is one-shot on creation: `init { load() }` publishes `Loading`
(rendered as the activity list skeleton), fetches all three sources, and
publishes `Content`, or `Error` with the exception's message when anything
throws (`HomeViewModel.kt:44-57`). The screen adds a silent on-resume
refresh through a `LifecycleEventObserver`: because the saved-state back
stack keeps this ViewModel alive across tab switches, a school work just
added under the Beacon — or anything published meanwhile — would otherwise
stay invisible on Home until a process restart, so every resume silently
reloads the overview (`…/ui/home/HomeScreen.kt:80-87`). The silent path
keeps the current content while fetching (no skeleton flash) and keeps
whatever is on screen when it fails; only the first load's hard errors reach
the error state, where an explicit retry button re-runs `load()`
(`HomeViewModel.kt:59-77`, `:111`).

## 7.4 Interaction

There is exactly one rich interaction: tapping an upcoming row opens
`ActivityDetailSheet`, the full-content modal sheet the Beacon rows open —
full title, full course name, type, due, upload time, effort, verification
chips, and the complete notes with See more / See less when they run long
(`HomeScreen.kt:88-112`; the sheet itself is documented in Chapter 8).
Everything else on the screen navigates: "See all activities" to the Beacon
tab, post previews to the Community tab, and the guidance button to the
floating assistant's panel. No swipe gestures, no pull-to-refresh, and no
long-press affordances exist on this screen.

The community previews are previews in the strict sense: they render the
post's text clamped to two lines, the author's mark and display name (or the
"Anonymous" label when the row says so), and the engagement line — but no
like button and no comment thread. Interacting with a post means going to
the feed, where those affordances live (Chapter 9). This keeps the overview
read-only, which is also why the previews never write anything back to the
repository.

## 7.5 Live versus local

Home is online-first with no cache, like every screen in the app: there is
no Room, no DataStore, and no persisted feed — the only local persistence in
the whole app is SharedPreferences (session, auto-sync toggle, overlay
preferences; FACTBASE §5). Every value on the screen was fetched from
Supabase during this process's lifetime, and a cold start with no
connectivity lands on the error state with a retry button, not on stale
content. The offline cache and write outbox are PLANNED work recorded in
`docs/OFFLINE-SYNC.md`, not a shipped capability (FACTBASE §3).

## 7.6 What the screen deliberately does not do

The omissions are as intentional as the contents. Home does not fetch
anything the Beacon does not already fetch — it reuses the same
`getActivities()` call, so there is no second query shape to keep in sync.
It does not compute workload aggregates; the `dueSoonCount` is a count, not
the dashboard's `section_workload_daily` view, which no client consumes
(FACTBASE §12). It does not show overdue work at all — the comment on the
filtering step states the rule plainly: the Beacon keeps overdue rows at its
bottom, and the Home overview must never lead with or count past deadlines
(`HomeViewModel.kt:81-86`). And it does not refresh on a timer; freshness
comes from the resume observer and from the student's own navigation.

Defense answer for judges: "Home is intentionally thin — three repository
reads composed into one overview, computed entirely client-side from
RLS-filtered lists, with a silent on-resume refresh so it is never stale
after a tab switch. It contains no widget we cannot point to in the source,
and it shows exactly what the same repositories serve the Beacon and the
feed — one source of truth, three views."

---


# Chapter 8 — Activity Beacon

The Activity Beacon is the center of the student app: the single list where
every deadline the student is responsible for converges, regardless of where
it was born. A row in the Beacon can be a coursework item pulled read-only
from Google Classroom, a deadline a teacher entered for their section, a
report a classmate published for the class, or the student's own entry. This
chapter is correspondingly the deepest in Part III: it covers the purpose,
the data model, every lifecycle operation (create, retrieve, edit, delete,
view), the ordering rules, the provenance labels, the duplicate-prevention
behavior, the visibility rules, and — in one table — exactly which layer
enforces each rule. Teacher-side views of the same rows are Chapters 16
and 17; the Classroom sync that produces imported rows is Chapter 12, and
activity identity and deduplication are Chapter 14.

## 8.1 Purpose and semantics

### What it is

The Beacon is a per-student list of `activities` rows the signed-in student
is allowed to see, ordered as a newest-first stack, with filters, a
full-content detail sheet, and an editor for recording new work by hand
(`…/ui/beacon/BeaconScreen.kt`; `…/ui/beacon/BeaconViewModel.kt`). It is not
a calendar and not a task manager: there is no status, no completion
tracking, and no notification. It answers one question — what is due, for
which class, from which origin, and how trustworthy is the record.

### Why Student Codex needs it

Google Classroom only ever contained the online half of a student's
deadlines; face-to-face announcements (board notes, verbal deadlines) never
reached it (FACTBASE §1). The Beacon is where both halves meet: imported
Classroom rows and human-entered rows live in one table with provenance
labels, so the student reads one list instead of reconciling two worlds, and
classmates converge on shared rows instead of each maintaining a private
copy. The list is intentionally honest about trust — every row carries a
label saying whether it was imported, teacher-confirmed, or student-reported
— because the reader must be able to judge the record, not just see it.

### How it works, in one paragraph

The screen owns a `BeaconViewModel`, which owns nothing but the
`ActivityRepository` interface (`…/ui/beacon/BeaconViewModel.kt:92-94`). One
PostgREST `select` returns the RLS-filtered rows with joined course and
source data (`SupabaseActivityRepository.kt:42-61`); the ViewModel filters
and sorts client-side; the screen renders rows, chips, and sheets; writes go
back through the repository as plain inserts and updates that the database's
policies, triggers, and check constraints either accept or reject. The app
never calls an RPC for any of this — the verified architecture records zero
direct RPC calls from the Android client (FACTBASE §4).

## 8.2 Activity types and scopes

Two orthogonal vocabularies describe a row. The *type* is what the work is;
the *scope* is who may see it. The type vocabulary is fixed by a database
check constraint and mirrored in the app's `ActivityType` enum
(`…/domain/model/Activity.kt:11`):

| Wire value | App enum | Meaning |
|---|---|---|
| `assignment` | `ASSIGNMENT` | Homework or graded submission |
| `quiz` | `QUIZ` | Short assessment |
| `exam` | `EXAM` | Major assessment |
| `project` | `PROJECT` | Extended work |
| `announcement` | `ANNOUNCEMENT` | Informational, no deadline implied |
| `other` | `OTHER` | Generic school work (labeled "Activity" in the UI) |

The scope vocabulary is likewise constrained in SQL: `scope in ('personal',
'section', 'course')`, with `activities_scope_section_requires_section` and
`activities_scope_course_requires_course` enforcing that a section-scoped row
names a section and a course-scoped row names a course (migration 000200,
`activities` table definition). Scope is the privacy boundary of the whole
system, so it deserves its own statements:

- `personal` rows are private to their creator. They are invisible to every
  other account — *including teachers*: the teacher read path only opens for
  `scope in ('section', 'course')` (Section 8.13).
- `section` rows belong to one section of one course: visible to every
  enrolled student of that section and, since the global-visibility
  migration, to every teacher university-wide.
- `course` rows attach to a course as a whole and are visible through
  enrollment in any of its sections; in the current app this scope is
  written by teacher and service paths, not by the student editor.

The student editor writes `scope='section'` for every new activity and
`scope='personal'` only when editing a pre-existing personal row — the
insert sends `"section"` or `"personal"` depending on whether a section was
chosen (`SupabaseActivityRepository.kt:74`). Scope is immutable from the
app: the update payload never touches it
(`SupabaseActivityRepository.kt:104-126`).

## 8.3 The origins of a row

The Beacon's provenance model has two axes that the code resolves from the
row itself. `ActivitySource` (GOOGLE_CLASSROOM / MANUAL / STUDENT_REPORT,
`…/domain/model/Activity.kt:14`) answers "where did this record come from";
`VerificationStatus` (IMPORTED / TEACHER_CONFIRMED / STUDENT_REPORTED /
NEEDS_REVIEW, `Activity.kt:17`) answers "how trustworthy is it". The
repository resolves them at parse time with a deterministic rule: a row with
a `google_classroom` source attachment is GOOGLE_CLASSROOM; otherwise a
`student-reported` verification makes it STUDENT_REPORT; everything else is
MANUAL (`SupabaseActivityRepository.kt:203-213`). The four real-world
origins follow.

### Personal activities (manual, private)

A personal activity is a planner entry: a row with `scope='personal'`,
`verification_status='student-reported'`, created by and visible to exactly
one student. The insert policy allows any authenticated user to create
personal rows with themselves as creator (migration 0015,
`activities_insert`). No one else ever reads it — not classmates, not
teachers, not moderators of other tables — and the soft-delete exception in
the select policy exists precisely so the creator can still see (and
therefore un-see, by deleting) their own deleted rows. In the current
editor, personal rows are the edit path: the edit and delete affordances
render on a row only when it is the user's own, not Classroom-imported, and
personal — the `editable` computation in `BeaconActivityRow`
(`…/ui/beacon/BeaconScreen.kt:344`).

### Section activities: student reporting is publishing

A section activity is the classroom's shared record. The product decision is
written into migration 0015's header verbatim: student reports publish
INSTANTLY; a report is written directly into `activities` as a
section-scoped, student-reported row; there is no approval queue anywhere —
the origin stays visible as a badge, "a LABEL, not a gate" (migration 0015,
`student self-publish`). The app states the same thing to the student in the
editor's share hint: "Shared with your course section — your teacher and
classmates see it on the calendar instantly. No approval needed."
(`strings.xml:164`). The legacy pending→matched queue that once existed in
`activity_reports` was drained by that same migration and remains only as
an audit table.

Section 8.4 walks the exact insert path. The key enforcement is layered: the
RLS insert policy lets a student insert a `section` row only with
`verification_status='student-reported'` into a section they are enrolled in
with role `student` (0015), and the `guard_activity_insert` trigger raises
if a `student-reported` section row's creator is not an enrolled student of
that section — teachers cannot file fake student reports, and students
cannot publish into sections they do not belong to (0015, guard text).

### Teacher-confirmed activities

A row created by a teacher of the target section carries
`verification_status='teacher-confirmed'`, and that is the only way to get
that label: the guard trigger raises "verification_status 'teacher-confirmed'
requires a teacher of the section/course or an admin" for anyone else
(migration 000200 guard, restated in 0015). Teachers register only on the
dashboard (Chapter 16), but an account holding the teacher role can sign
into this app too, and the same `activities` row shape serves both
clients — with the dashboard's category corrections locking the type
across re-syncs (`category_locked`, migration 0023; Chapter 18). In the
app, the editor's save path mirrors the enrollment role it fetched: a
taught section
saves as `teacher-confirmed`, a student enrollment as `student-reported`
(`…/ui/beacon/BeaconViewModel.kt:267-270`; `…/data/repo/Repositories.kt:22-25`).

### Classroom-imported activities

An imported row is read-only evidence: coursework or an announcement that
the `classroom-sync` Edge Function upserted with
`verification_status='imported'`, carrying an `activity_sources` attachment
whose `source_key` (`google_classroom:{courseId}:{courseWorkId}`) is its
identity (Chapters 12 and 14; FACTBASE §11). The `imported` status is reserved for
the sync service — the guard trigger raises on any client attempt to insert
it — and in the app these rows are read-only: they render the green Google
Classroom badge, they never show edit/delete affordances, and their raw
Classroom workType and metadata live in `source_meta` server-side. The
app-side signature of an import is exactly the `activity_sources(provider)`
join column the repository selects
(`SupabaseActivityRepository.kt:44-52`).

## 8.4 What happens when a student reports a face-to-face activity

Step by step, with the layer that acts at each step:

1. The student taps "Add school works" (`BeaconScreen.kt` guest check first:
   guests get the sign-in notice instead). `openEditor()` resets the sheet
   and `loadSections()` fetches the student's own sections — student
   enrollments and taught sections alike — every time, never a session-stale
   cache, so courses added under Settings appear on the next open
   (`BeaconViewModel.kt:151-188`).
2. The editor asks exactly one cohort question — which course — through a
   searchable dropdown over those sections; campus, program, year and block
   are already baked into the section row, and the profile already carries
   them for display (`BeaconScreen.kt` `CourseSectionDropdown`;
   `…/data/repo/Repositories.kt:44-61`). With exactly one section there is
   nothing to pick: it is auto-selected
   (`BeaconViewModel.kt:172-179`).
3. The student fills title, optional notes, a type chip, and an optional due
   DATE. A due date means end-of-day on the school calendar — 23:59
   Asia/Manila — kept stable whatever the device zone is set to
   (`BeaconViewModel.kt:356-364`).
4. On save, validation is local first (title non-blank; a section chosen for
   a new class row — `TITLE_BLANK` and `SECTION_REQUIRED` are resolved to
   strings in the sheet), then the repository inserts one row:
   `scope='section'`, `verification_status='student-reported'`,
   `created_by_user_id` = the signed-in user, `section_id`/`course_id` from
   the pick (`BeaconViewModel.kt:239-286`;
   `SupabaseActivityRepository.kt:63-102`).
5. The database decides: the `activities_insert` RLS policy and the
   `guard_activity_insert` trigger verify the creator is an enrolled student
   of that section (0015). If they pass, the row exists — instantly. There
   is no queue, no pending state, no notification to wait for.
6. From that moment the row is visible to every student enrolled in the
   section (select policy, Section 8.13) and to every teacher in the
   university (teacher read branch, migrations 0019/0020). On the teacher
   dashboard it appears in the read-only student-reported feed and the
   calendar (Chapter 16).
7. The editor closes and the list reloads keeping the active filter
   (`BeaconViewModel.kt:280-281`), so the student's own report is at the top
   of the stack — LIFO ordering (Section 8.8).

> NOTE: The honesty point of this flow is that "student-reported" is a
> label, not a gate. The dashboard shows the teacher what the section's
> students recorded; it does not certify that the real-world teacher
> announced it. Recorded information is all the system ever has
> (FACTBASE §16).

## 8.5 Duplicate prevention, honestly stated

### Imported rows: guaranteed single identity

For Classroom rows the guarantee is structural. Every imported item carries
a `source_key` with a UNIQUE partial index —
`google_classroom:{courseId}:{courseWorkId}` (or the announcement variant) —
and the sync path upserts `ON CONFLICT (source_key) DO UPDATE`, so Student B
syncing what Student A already synced UPDATES the same shared record and
never creates a second row; repeated sync attempts are not duplicate
records. The behavior is verified by `gc_source_identity_test.sql`, and a
second guard — the composite unique on (provider, external_course_id,
external_item_id) — backs the source key (FACTBASE §11; Chapter 14 carries
the full sequence). Teacher category corrections survive those updates
because `category_locked` rows keep their type (migration 0023).

### Manual rows: no duplicate detection at all

For manual reports there is deliberately NO structural dedup — and, verified
against the code on 2026-11-01, no similarity prompt either:
`BeaconScreen.kt` and `BeaconViewModel.kt` contain no matching or
duplicate-check logic (grep-verified: zero hits for similarity/matching). If
two students report the same face-to-face activity, TWO rows are created.
The Guidance assistant's canned answer claims otherwise — "If a similar
activity already exists, Student Codex will ask whether it is the same one
before saving - nothing is merged silently"
(`…/domain/guidance/GuidanceEngine.kt:53-54`) — but that text describes a
behavior the app does not implement; it is canned-answer drift, documented
as such in Chapter 10. Title-token logic exists ONLY in the database
classifier `suggest_activity_category` (migration 0023), which suggests a
category — it never deduplicates. The honest consequence: two rows
describing the same real-world deadline CAN coexist in the section's list,
each with its own reporter, each visible to the section and to teachers, and
each independently editable or withdrawable by its own creator. Judges
should hear this stated plainly rather than discovered: imported identity is
enforced by a unique index; manual identity is unassisted, because two
humans typing two titles about one deadline is a semantics problem, not a
constraint problem.

## 8.6 Creating an activity: the editor sheet

The editor is a `ModalBottomSheet` (`ActivityEditorSheet`) whose fields are
exactly: title (required, single line), notes (optional, multi-line),
type (six chips — all six options fit, so no dropdown), due date (a
read-only field opening a Material `DatePickerDialog`, blank = no deadline),
and — for a new row — the course picker over the student's own sections
(`BeaconScreen.kt` editor section). For an edited class row the sheet
instead shows the row's course code as fixed origin information, because
scope is immutable server-side so no picker is offered
(`BeaconScreen.kt`, `originCourseCode` branch).

There is NO effort field. The `ActivityDraft` carries an optional
`effortMinutes` for interface completeness, but the ViewModel never sets it,
so every manual row is written with `estimated_effort_minutes = null`
(`…/data/repo/Repositories.kt:26-42`; `BeaconViewModel.kt:259-270`). Effort
renders only on imported rows, where Classroom's metadata supplied it
(Chapters 12 and 14) — this is a KNOWN LIMITATION stated as such in Section 8.16.
The save path's full payload is small enough to show whole
(`SupabaseActivityRepository.kt:66-89`):

```kotlin
insert(buildJsonObject {
    put("title", draft.title)
    put("description", draft.description)
    put("activity_type", draft.type)
    put("due_at", draft.dueAt?.toString())
    put("estimated_effort_minutes", draft.effortMinutes)
    put("scope", if (draft.sectionId != null) "section" else "personal")
    put("section_id", draft.sectionId)
    put("course_id", draft.sectionId?.let { draft.courseId })
    put("verification_status",
        if (draft.teacherConfirmed) "teacher-confirmed" else "student-reported")
    put("created_by_user_id", uid)
})
```

The comment in the repository records a real failure this design survived: a
teacher sending `student-reported` for their own section hit the guard's
"requires the creator to be enrolled in that section" error, which is why
the role drives the status now
(`SupabaseActivityRepository.kt:77-83`).

## 8.7 Retrieving the list

Retrieval is one-shot, not observed. `load()` publishes `Loading`, performs
one `getActivities()`, and publishes either `Content` or `Error`
(`BeaconViewModel.kt:108-118`); there is no polling, no realtime channel,
and no pull-to-refresh (FACTBASE §8). The screen adds a silent on-resume
refresh — the same rule Home follows — because the saved-state back stack
keeps the ViewModel alive across tab switches, so a Classroom sync just run
under Settings, or a classmate's newly published work, would otherwise stay
invisible until a process restart. The refresh keeps the current filter,
keeps the current content while fetching (no skeleton flash), and on failure
keeps whatever is on screen; the explicit retry button still surfaces hard
errors (`BeaconViewModel.kt:122-141`; FACTBASE cites
`BeaconViewModel.kt:123-131`).

The wire query is one joined select with a filter and an order
(`SupabaseActivityRepository.kt:42-61`):

```kotlin
client.postgrest.from("activities")
    .select(columns = Columns.list(
        "id", "title", "description", "activity_type", "due_at",
        "estimated_effort_minutes", "scope", "verification_status",
        "deleted_at", "created_at", "created_by_user_id",
        "course:courses(id,code,title)",
        "activity_sources(provider)",
    )) {
        filter { filter("deleted_at", FilterOperator.IS, null) }
        order("created_at", Order.DESCENDING)
    }
```

Two details matter. First, soft-deleted rows are filtered here for everyone,
though the select policy keeps them readable to their creator — the app
chooses to hide them, the database chooses who *could* see them. Second, the
wire already arrives stacked newest-first; the ViewModel re-sorts
client-side anyway (Section 8.8) so the rule has exactly one implementation
the sort and the filter chips can never disagree about.

## 8.8 Ordering: the two-tier LIFO stack

The Beacon is a last-in-first-displayed stack keyed on the server's
`created_at` — the upload stamp, never a device clock — so the same order
appears on every device. The stack splits in two tiers
(`BeaconViewModel.kt:325-354`):

- Tier 1 (top): every NOT-overdue work, newest upload first.
- Tier 2 (bottom): the OVERDUE works as their own trailing stack, also
  newest upload first, under a red "Overdue · n" section header.

A deadline that already passed never buries actionable work, while the
overdue group still reads last-in-first-display. A work with no deadline is
never overdue and stays in the top tier. Rows with an unknown upload time
sink last *within* their tier rather than claiming the top of either stack,
and the title is a stable tie-break. There is no due-date grouping inside
either tier — grouping would re-order the stack by deadline, so each row
keeps its own trailing due emphasis instead, and one quiet caption states
the rule to the student: "Newest uploads first" (`strings.xml:139`;
`BeaconScreen.kt` order-caption comment). "Now" is sampled once per publish
so the filter predicates, the sort, and the rows' overdue tinting all agree
on which side of the deadline line every item sits
(`BeaconViewModel.kt:325-335`).

## 8.9 Editing and deleting

Editing opens the same sheet pre-filled from the row (title, notes, type,
due date as a local date), with the row's course code shown as fixed origin
when it is a class row (`BeaconViewModel.kt:196-207`). The update payload
changes only the mutable content fields — title, description, type, due
date — while ownership, scope, and verification are server-enforced as
immutable (`SupabaseActivityRepository.kt:104-126`;
`…/data/repo/Repositories.kt:77-83`). The screen offers the edit and delete
icon buttons on the user's own rows that are not Classroom-imported, with
the current affordance gated to personal rows
(`…/ui/beacon/BeaconScreen.kt:344`); the server-side reporter self-service policy
additionally lets a reporter edit or withdraw their own student-reported
section rows (migration 0015, `activities_update_own_student_report`), so
the database's permission is broader than the current screen's affordance —
a fact worth stating rather than glossing.

Deletion is soft: `deleteActivity()` writes `deleted_at = now` on the row and
the row disappears from every feed immediately
(`SupabaseActivityRepository.kt:128-136`). The UI confirms first with a
dialog naming the activity; a delete of a class report is the reporter's own
withdraw — the entry also disappears from the teacher's calendar
(`…/data/repo/Repositories.kt:84-90`). A missed delete (row not found or
not permitted) is a silent no-op that the next list refresh reveals
honestly, and delete failures surface as a list reload that keeps the row
(`SupabaseActivityRepository.kt:134-135`; `BeaconViewModel.kt:288-299`).
Imported rows are read-only evidence in the app regardless of who synced
them — they never show the affordances
(`…/domain/model/Activity.kt:45-53`).

## 8.10 The detail sheet

`ActivityDetailSheet` is the full-content view for one row, shared by the
Beacon rows and the Home upcoming rows (`…/ui/components/ActivityDetailSheet.kt:43-60`).
Its reason to exist is stated in its own KDoc: the list rows are deliberately
dense, so long notes never fit — this sheet is where the whole record opens
up. It renders the full title (no line cap), the provenance chip and a
verification chip in the same visual language as the rows, then fact rows
for type, the full course name ("code - title", where the rows only ever
showed the code), the due value with its urgency color, the upload stamp the
LIFO order runs on, and effort when present. The notes start clamped to
eight lines with a See more / See less toggle that only appears when the
first layout pass actually overflows — short notes never show a button
(`ActivityDetailSheet.kt:177-217`). The sheet is a plain `ModalBottomSheet`
with no actions inside it: it is a reader, not an editor; editing happens
from the row's own affordances.

## 8.11 Provenance and verification in the UI

Every row wears exactly one provenance chip beside its title, chosen by a
simple rule: `GOOGLE_CLASSROOM` source renders the Google-brand green
`ClassroomBadge` (solid `0xFF0F9D58`, white content, school icon); every
human-entered row — personal entry, student report, teacher entry — renders
the neutral in-app `ManualBadge` (`…/ui/components/ClassroomBadge.kt:36-101`;
`BeaconScreen.kt` chip branch). The Classroom chip's KDoc states its job:
one glance answers "did the Classroom sync actually work?" for the student
who synced AND for classmates seeing the same section rows; the manual chip
answers "a human entered this in the app". Below the chip, a quiet plain-text
metadata line carries the trust and context half: course code,
verification label, "Personal" when applicable, effort minutes when present,
and the upload time that explains the stack's order
(`BeaconScreen.kt` `activityMetadata`). The detail sheet adds the compact
`VerificationChip` for the same four statuses. The Beacon's filter chips
include a Classroom-only filter, alongside overdue/not-overdue and the type
filters (`BeaconFilter` enum, `BeaconViewModel.kt:26-40`).

## 8.12 Database persistence

Every Beacon row is one `activities` row (migration 000200, with 0015/0023
amendments). The columns the app actually reads and writes:

| Column | Shape | Written by the app | Notes |
|---|---|---|---|
| `title` | text, 1-200 chars | yes | check-constrained length |
| `description` | text nullable | yes | the "notes" field |
| `activity_type` | text, 6-value check | yes | editor chips |
| `course_id` / `section_id` | FKs nullable | yes (from the pick) | scope constraints require them for their scopes |
| `due_at` | timestamptz nullable | yes | end-of-day Manila for manual dates |
| `estimated_effort_minutes` | int, 1-10080 check | always null | imports set it; the editor has no field |
| `scope` | text, 3-value check | yes | immutable after insert |
| `verification_status` | text, 4-value check | yes (role-derived) | `imported` reserved for the sync service |
| `created_by_user_id` | uuid NOT NULL, FK | yes | ownership anchor, immutable |
| `created_at` / `updated_at` | timestamptz | no | LIFO key / `set_updated_at` |
| `deleted_at` | timestamptz nullable | yes (soft delete) | hidden from feeds, creator-visible |
| `category_locked` / `category_locked_by` | from 0023 | no | teacher correction lock (Chapters 14 and 18) |

Alongside the row, `activity_sources` records provenance for imported items
(provider `google_classroom`/`student_manual`/`teacher_manual`, external ids,
`source_key`, `source_meta`), with the two unique indexes of Section 8.5.
Manual student rows simply have no source attachment — that absence is what
the repository's source resolution reads as MANUAL or STUDENT_REPORT
(`SupabaseActivityRepository.kt:203-213`).

## 8.13 Visibility: how scope and ownership interact

The select policy is the single source of truth for who reads what. Its
current shape (migrations 0019/0020; the mirrored SQL is the policy the
FACTBASE records as current):

```sql
create policy activities_select on public.activities
  for select to authenticated
  using (
    (deleted_at is null or created_by_user_id = auth.uid())
    and (
      created_by_user_id = auth.uid()
      or exists (select 1 from activity_participants ap
                 where ap.activity_id = activities.id
                   and ap.user_id = auth.uid())
      or (public.has_role('teacher') and scope in ('section', 'course'))
      or (scope = 'section' and exists (…enrollment in activities.section_id…))
      or (scope = 'course'   and exists (…enrollment in a section of
                                          activities.course_id…))
    )
  );
```

Read as a table over the row's scope and the reader's relationship to it:

| Row scope | Creator | Section enrollee | Other student | Teacher | Moderator |
|---|---|---|---|---|---|
| personal | read (incl. soft-deleted) | no | no | no | no |
| section | read (incl. soft-deleted) | read | no | read (university-wide) | no |
| course | read (incl. soft-deleted) | read via any section of the course | no | read (university-wide) | no |

Three consequences are worth saying out loud. First, ownership and scope
compose: a personal row is visible only to its creator even though the
creator is also the "own rows" branch — no other branch can ever reach it.
Second, the teacher branch is deliberately university-wide and deliberately
excludes personal rows: a teacher reads ALL section and course work from
every campus, program, year and block, but a student's private planner stays
private from faculty too (migration 0020 header; FACTBASE §12). Third, the
`deleted_at` clause at the top is what makes soft delete work under
PostgreSQL's rule that a SELECT policy's USING is also checked on UPDATE:
soft-deleted rows stay visible only to their creator so the creator can
still act on them, and everyone else — and every feed — never sees them
(policy comment in the mirrored SQL).

## 8.14 Which layer enforces which rule

The Beacon is a good place to see the project's enforcement philosophy:
the client is convenient, the server is correct. Nothing security-relevant
lives only in Kotlin.

| Rule | Enforced by | Evidence |
|---|---|---|
| Title non-blank; section chosen; type valid | Android (ViewModel + sheet validation) | `BeaconViewModel.kt:239-257` |
| Only own sections offered as audience | Android + RLS read scope of `enrollments` | `SupabaseActivityRepository.kt:145-173` |
| `created_by_user_id = auth.uid()` on insert | RLS `activities_insert` | migration 0015 |
| Student section insert requires enrollment, role student | RLS + `guard_activity_insert` trigger | migration 0015 |
| `teacher-confirmed` only by teacher/admin | `guard_activity_insert` trigger (P0001 raise) | migrations 000200/0015 |
| `imported` reserved for sync service | `guard_activity_insert` trigger | migration 0015 |
| Scope immutability, verification upgrades teacher-only | `guard_activity_update` trigger | migrations 000200/0023 |
| Who can read a row | RLS `activities_select` | migrations 0019/0020 |
| Reporter edit/withdraw of own report | RLS `activities_update_own_student_report` | migration 0015 |
| Import identity (one row per Classroom item) | SQL function `upsert_activity_from_source` + unique indexes, invoked by the `classroom-sync` Edge Function with the service key | FACTBASE §11; Chapter 14 |
| Category corrections locked across re-syncs | `category_locked` columns + guard stamping | migration 0023 |
| 3-value scopes, 6-value types, lengths, effort range | check constraints | migration 000200 |
| Soft delete hides rows | RLS clause + app filter | policy; `SupabaseActivityRepository.kt:54` |
| LIFO order, filters, chips, affordances | Android only (presentation) | `BeaconViewModel.kt:325-354` |

The Edge Functions touch the Beacon only through the sync path: they verify
the session JWT, carry the Google token in transit, and invoke the upsert
SQL function with the service key — never with a client credential
(FACTBASE §4; Chapters 12 and 14).

## 8.15 Error handling

The list has three states — `Loading` (skeleton), `Error` (message + retry
button re-running `load()`), and `Content` — and the silent resume refresh
never escalates into `Error`, so a flaky network degrades to "the list you
already have" instead of a wall of red (`BeaconViewModel.kt:108-141`). The
editor keeps its failures local and actionable: validation errors render
inline under the offending flow, a save failure keeps the sheet open with
the draft intact and the server's message shown, and the save button
disables itself while in flight (`BeaconScreen.kt` editor sheet;
`BeaconViewModel.kt:282-285`). Section fetching inside the editor stops its
spinner on failure and shows the honest "no courses" hint, with retry by
reopening (`BeaconViewModel.kt:182-187`). Empty states are distinguished:
an overall empty list ("No activities yet") versus a filter that matches
nothing ("Nothing in this filter") — different situations, different text
(`strings.xml:135-136`, `:173-174`).

## 8.16 Current limitations

The honest list, each item verifiable in the sections above:

- No effort field in the editor — manual rows carry `estimated_effort_minutes
  = null`, and effort renders only on imported rows. KNOWN LIMITATION.
- Title-token matching before save is a prompt, not a guarantee: two rows
  describing the same real-world activity can coexist (Section 8.5). KNOWN
  LIMITATION.
- Online-first: no offline cache, no write outbox; connectivity is required
  for every read and write (FACTBASE §16; offline is PLANNED,
  `docs/OFFLINE-SYNC.md`).
- No push, no reminders, no realtime: freshness arrives with the next
  one-shot load or silent resume refresh, and a Classroom change is not
  reflected until the next successful sync (FACTBASE §11).
- Recorded is not complete: the list shows what people recorded or imported,
  with no guarantee that all real-world university activities were entered
  (FACTBASE §16).
- The screen's edit/delete affordance is currently gated to the user's own
  personal rows even though the server policy permits reporter self-service
  on student-reported section rows (Section 8.9) — the UI is narrower than
  the database allows.

## 8.17 Defense answer

If a judge asks "how do you know students can't post fake work to someone
else's class, and how do you know the list is trustworthy": the answer is
that the app's writes are constrained by an RLS policy requiring the creator
to be an enrolled student of the target section, a trigger that rejects
verification labels the creator's role cannot back, and a select policy that
derives visibility from enrollment rather than from anything the client
sends — while the provenance chips make every row's origin legible at a
glance, so trust is displayed rather than assumed. The one soft spot —
manual duplicate reports — has no mitigation in the current build and honestly
documented as not a guarantee, because merging two human-typed titles about
one deadline is a judgment call the system refuses to make silently.

---


# Chapter 9 — Community Module

The community is the app's social surface: a campus feed of study-related
posts with images, likes, comments, and a reporting path for content that
breaks the rules. It reuses the same session and the same repository pattern
as every other screen, but it is the module where the gap between what the
database supports and what the app currently exposes is widest — and where
this documentation is most careful to say exactly which half is real. The
chapter follows one post through its life: created, read, liked, commented,
reported, and optionally removed.

## 9.1 Purpose and boundaries

### What it is

The Community tab renders a newest-first feed of posts from signed-in
students, each post showing an author mark and name (or an anonymous label),
the text, an optional image, and an engagement line of comment and like
counts (`…/ui/community/CommunityScreen.kt`). One `CommunityViewModel` backs
the feed with three sheets on demand — the composer, the comments thread,
and the report dialog (`…/ui/community/CommunityViewModel.kt:77-92`). Guests
browse but never write: the composer opens in read-only explainer mode and
the repositories reject a missing session before any insert
(`CommunityViewModel.kt:113-123`; `SupabaseCommunityRepository.kt` session
checks).

### Why Student Codex needs it

The product problem was fragmented announcements; the community adds the
conversations around them — questions about a deadline, shared study
material, campus help — inside the same authenticated surface instead of
pushing students to external group chats. The safety model is deliberately
server-side (migration 000300's header lists it): ownership enforced in the
database, a 3-image limit enforced by the database, likes unique per
(user, target) in the database, replies depth-limited by a trigger, and
anonymity implemented as "author hidden in the public interface" rather
than as authorlessness.

## 9.2 Reading the feed: anonymity-safe views

Reads never touch the base `posts` table directly. The repository selects
from `feed_posts` (and `feed_comments` for threads), invoker-safe views
created with `security_invoker = true` so RLS stays active for the reading
user (`SupabaseCommunityRepository.kt:53-61`; migration 000300, rebuilt in
000800). The view computes what the feed needs in one place: like count,
comment count (non-deleted only), `liked_by_me` for the requesting user, and
ordered `image_paths` as a JSON array, plus `author_name` resolved from the
joined profiles row (migration 000800, view definition). The feed page size
is 50 posts newest-first; a comment thread is fetched oldest-first capped at
200 (`SupabaseCommunityRepository.kt:280-289`).

The anonymity-safety property is structural, not a UI convention: for an
anonymous row the view emits `null` as the author id and joins profiles on
that null, so the author's name can never leak through the public interface
— the view definitions state this in their own comments, and a separate
`my_posts` view lets an author see their own anonymous history precisely
because `auth.uid()` evaluates per requesting user (migration 000800). In
the app, an anonymous row simply renders the "Anonymous" label and the
anonymous author mark (`CommunityScreen.kt` author branches).

### What the app maps out of the view

The repository selects a fixed column set — id, content, `is_anonymous`,
`author_name`, `created_at`, `like_count`, `comment_count`, `liked_by_me`,
`image_paths` — and maps it to the `CommunityPost` domain object with
sensible null fallbacks (empty name, zero counts, no image path)
(`SupabaseCommunityRepository.kt:282-289`, `:238-253`). Only the first
image path is taken (`firstImagePath`), matching the one-photo app even
though the view aggregates up to three. Post timestamps fall back to
`Instant.now()` when the view's value is unreadable, which keeps a malformed
row rendering instead of dropping it silently. The feed itself renders the
engagement line — pluralized comment and like counts joined with a dot —
under two lines of clamped text (`CommunityScreen.kt` post card), and the
liked state drives the like affordance rather than any local tally.

### Sheet state machines

Both interactive sheets are state machines with the post id baked in so a
retry cannot reload the wrong thread. The comments sheet is
`CommentsUiState` — `Loading(postId)`, `Error(postId, message)`, or
`Content(post, comments, draft, isSending, sendError)` — and reopening the
same post is a no-op while a different post resets the whole state
(`CommunityViewModel.kt:26-44`, `:200-217`). The report dialog is
`ReportPostUiState` with its own `sending` and `submitted` flags: a
submitted report locks the dialog into its thank-you state instead of
allowing a double submit, and the details field is clamped to 1000
characters as the user types (`CommunityViewModel.kt:63-75`, `:294-300`).
Loading the feed itself follows the shared pattern — `Loading`, `Error`
with a retry, `Content` — one-shot on ViewModel creation, re-run only by
the explicit retry button (`CommunityViewModel.kt:94-109`).

Two boundaries close this section. The feed is online-first like every
screen in the app: there is no cached copy, so a cold start without
connectivity lands on the error state rather than on stale posts (FACTBASE
§16). And the feed read here is the same `getRecentPosts()` call the Home
preview truncates to two rows (Chapter 7), so the overview and the full
feed can never disagree about what exists — they are one query seen twice.

## 9.3 Creating a post — and the anonymity honesty point

The composer sheet collects the post text, an optional photo picked from the
gallery, and offers a "Post anonymously" switch whose note reads "Your name
is hidden from other students" (`CommunityScreen.kt` composer section; the
switch state lives in `ComposerUiState.isAnonymous`,
`CommunityViewModel.kt:52-61`). Submitting requires text or a photo, marks
the sheet as posting, and calls the repository
(`CommunityViewModel.kt:158-180`).

The sheet previews exactly what will be posted: an author mark that
switches to the anonymous rendering when the toggle flips, the author's
name or the "Anonymous" label beside it, the draft text, and the picked
photo with a remove affordance (`CommunityScreen.kt:309-325`, `:365-380`).
The photo is picked through an activity-result launcher into a content URI
string, carried in the composer state, and only read into bytes at upload
time — so picking and posting are two separately failing steps with
separately worded errors. Guests see the same sheet in explainer mode: the
draft is not writable, and the note states that posting, liking,
commenting and reporting all need an account
(`CommunityViewModel.kt:113-136`; `strings.xml:245`).

> WARNING: The anonymous switch is UI-only. The ViewModel's submit call
> passes only the text and the image URI — the `isAnonymous` flag is dropped
> at `CommunityViewModel.kt:166` — and the repository then hard-wires the
> column: `put("is_anonymous", false)` at
> `SupabaseCommunityRepository.kt:149` (comments likewise at `:110`).
> Anonymous posting is PARTIALLY IMPLEMENTED: the switch exists, the
> database, views and seeds fully support anonymity, but every post the
> current app actually creates is attributed. The roadmap records the fix as
> "wire-or-remove" (FACTBASE §18, M1.1).

Image count is likewise half-and-half, in the opposite direction: the
database enforces a maximum of three images per post through the
`post_images` unique (post_id, position) constraint with
`position between 1 and 3` (migration 000300), and the view aggregates up
to three ordered paths — but the app attaches exactly one photo per post,
recorded at position 1 (`SupabaseCommunityRepository.kt:169-189`). So the
schema allows 3; the app posts 1. Both halves of this asymmetry matter to
state correctly, because the assistant's canned community answer claims
"up to three images" and "you can post anonymously"
(`…/domain/guidance/GuidanceEngine.kt:85-88`) — true of the schema, untrue
of the app's writes. Chapter 10 carries that caveat; this chapter is the
source of record.

Creation itself is a three-step sequence in the repository: insert the
`posts` row (author, content, `is_anonymous=false`), upload the image if any
and register its `post_images` row at position 1, then re-read the created
post through the feed view so the card the UI prepends matches exactly what
everyone else will see (`SupabaseCommunityRepository.kt:137-167`). On
success the ViewModel prepends the created post to the feed state and closes
the sheet; on failure it keeps the draft, the photo, and shows the error
(`CommunityViewModel.kt:164-179`). Two database guards bound the write:
`posts_insert` requires `author_id = auth.uid()`, and the rate guard rejects
the 9th post within a rolling 10 minutes (migration 000300; rate guards in
migration 000800 — posts max 8 per 10 minutes, comments max 30 per 10
minutes, reports max 10 per hour).

## 9.4 Images and storage integration

Image bytes live in Supabase Storage, and only paths live in PostgreSQL —
the split is stated as the model in the storage migration's header. The
bucket `community-images` is private: it is never made public for
convenience, and reads are granted to authenticated users because the feed
itself is visible to signed-in students only (migration 000500 storage
policies). Uploads go to the uploader's own folder — the path is
`{uid}/{postId}/{timestamp}.jpg` — and the insert policy enforces the folder
prefix with `(storage.foldername(name))[1] = auth.uid()::text`, so a
modified client still cannot write into someone else's folder
(`SupabaseCommunityRepository.kt:174-189`; storage policies). Update and
delete policies are scoped to the uploader's own objects in the same way.

Downloads are authenticated: the repository calls
`downloadAuthenticated(path)` on the same bucket, and a missing or
unreadable object degrades to a text-only card instead of crashing the feed
— failures log and return null (`SupabaseCommunityRepository.kt:197-203`).
The image source seam (`PostImageSource` /
`ContentResolverImageSource`) exists so the picker's content URI is read
through the ContentResolver in production while unit tests inject bytes
(`SupabaseCommunityRepository.kt:293-308`).

## 9.5 Likes

A like is a row, not a counter. `toggleLike()` reads the current post from
the view, deletes the caller's `post_likes` row if it exists or inserts one
if it does not — the table's unique (post_id, user_id) makes double-liking
structurally impossible — and then re-reads the canonical post so the count
comes from the server, with no client-side arithmetic to drift
(`SupabaseCommunityRepository.kt:63-86`). The class KDoc gives the reason:
a race where someone else likes at the same moment resolves to the truth.
Like failures are non-fatal by policy: the ViewModel keeps the feed and
surfaces the reason (`CommunityViewModel.kt:184-198`). Comment likes exist
in the schema (`comment_likes`, its own policies and unique constraint, and
a `liked_by_me` column in `feed_comments`), but the app has no comment-like
UI — PLANNED, not built (FACTBASE §3).

## 9.6 Comments: flat in the app, nested in the database

The comments sheet for a post loads the thread oldest-first behind a
loading state, and sending a comment inserts a `comments` row and appends
it, bumping the feed's advertised count so the two surfaces stay in step
(`CommunityViewModel.kt:200-279`). Sending is guarded the same way every
write in the app is: the draft is trimmed, empty sends return, an in-flight
send blocks re-entry, and a failure keeps the thread and the draft while
explaining itself in the sheet (`CommunityViewModel.kt:230-262`). The
app's `Comment` model is flat —
there is no reply UI, no parent picker, and no threading rendered
(`…/domain/model/Community.kt`, flat model; FACTBASE §3 lists comments as
PARTIALLY IMPLEMENTED for exactly this reason). The database is more
capable than the UI: `comments.parent_comment_id` is self-referencing, the
`guard_comment_insert` trigger validates that a parent exists, belongs to
the same post, is not deleted, and keeps total depth within five levels,
and `guard_comment_update` makes parent linkage immutable so no cycle can
ever be constructed (migration 000300). Comments are written with
`is_anonymous=false` hard-wired (`SupabaseCommunityRepository.kt:110`), the
same honesty point as posts. Author display names come from the view's
joined profiles row — the comment row itself carries no name, which is why
the repository re-reads the canonical view row after inserting
(`SupabaseCommunityRepository.kt:99-135`).

## 9.7 Reporting content

Any signed-in student can report a post from a dialog offering exactly five
reasons — spam, harassment, off topic, inappropriate, other — plus optional
details capped at 1000 characters (`CommunityScreen.kt` report dialog;
`strings.xml:200-207`; the reason values are the database's check
constraint, migration 000400). Submitting inserts a `content_reports` row
with the reporter, `target_type='post'`, the target id, the reason, and
`status='open'` forced by the insert policy
(`SupabaseCommunityRepository.kt:210-224`). When no report repository is
wired (guests, tests), the dialog closes honestly with "Sign in to report
posts" (`CommunityViewModel.kt:307-314`). The report entry point itself is
only wired for signed-in users — guests do not see it at all
(`CommunityScreen.kt:101`).

> NOTE: Reporting is BUILT & VERIFIED at the database level and PARTIALLY
> IMPLEMENTED as a product feature: the table, guards, rate limit (10 per
> rolling hour), and triage permissions all exist and are tested, but there
> is no moderator UI anywhere in the project — no queue, no review screen,
> no action buttons (FACTBASE §3; the moderation queue UI is PLANNED,
> M3.3). A report is filed and then waits.

The guards keep the queue trustworthy while it waits: reporters cannot edit
a report's substance or its status (`guard_content_report_update` raises
for anyone but moderators/admins), reporters see only their own reports in
`content_reports_select`, and reports are retained rather than deleted —
there is deliberately no delete policy on the table (migration 000400).
Moderator and admin removal of the reported content itself is authorized by
separate delete policies on `posts` and `comments`
(`has_role('moderator') or has_role('admin')`, migration 000300).

## 9.8 The privacy model

Three mechanisms compose. First, own-row writes: every write policy on
posts, comments, likes and images requires the acting user to be the author
(`author_id = auth.uid()` / `user_id = auth.uid()`), and anonymity is
immutable after creation because flipping a post from anonymous to named
would retroactively reveal history — `guard_post_update` raises on both an
author change and an `is_anonymous` change (migration 000300). Second,
blocking is enforced by RLS itself: `user_blocks` (unique blocker/blocked,
no self-blocks) feeds the `posts_select` and `comments_select` policies,
which exclude anything authored by a user the caller has blocked, while the
caller's own posts always remain visible (migration 000300). Third, soft
deletion: `deleted_at` hides a post or comment from everyone except its
author — the policy comment explains the PostgreSQL subtlety that SELECT
policies' USING clauses are also enforced as WITH CHECK on UPDATE, which is
what lets an author still see and delete their own deleted content while
nobody else ever does. The feed views additionally filter `deleted_at is
null` so deleted rows never reach rendering.

## 9.9 Database relationships

The community's tables and their relationships, as verified in migrations
000300/000400/000800:

| Table | Relates to | Cardinality / constraint |
|---|---|---|
| `posts` | `auth.users` (author) | many-per-user; content 1-5000 chars |
| `post_images` | `posts` | ≤3 per post, unique (post_id, position 1-3) |
| `comments` | `posts`, self (`parent_comment_id`) | depth ≤5; parent same-post, non-deleted, immutable |
| `post_likes` / `comment_likes` | posts/comments + users | unique per (target, user) |
| `user_blocks` | users x users | unique (blocker, blocked), no self |
| `content_reports` | reporter + polymorphic target | 5 reasons; status open/actioned/dismissed |
| `feed_posts` / `my_posts` / `feed_comments` | views over the above | security_invoker; anonymity-safe |

## 9.10 Capabilities and limitations

What works end to end: feed reading through the anonymity-safe views,
posting text with exactly one image, liking with server-truth counts, flat
comments, and filing reports into a guarded queue. What is deliberately
half-built, stated with the verbatim status labels: anonymous posting is
PARTIALLY IMPLEMENTED (UI switch present, flag never persisted); comments
are PARTIALLY IMPLEMENTED (flat in the app, depth-5 nesting in the DB);
reporting is BUILT & VERIFIED at the DB level with no moderator UI; comment
likes, a nested reply UI, and the moderation queue are PLANNED. What does
not exist at all: comment editing or deletion affordances in the app,
multiple image selection, and any client for `my_posts` beyond the view
itself. And the Guidance assistant's canned community answer overstates the
app — "up to three images… you can post anonymously" describes the schema's
ceilings, not the app's writes (GuidanceEngine.kt:85-88) — so any judge
demo should show the switch and then show the persisted row.

Defense answer for judges: "The community's safety model lives in the
database — ownership, anonymity immutability, depth limits, rate limits, and
blocking are all enforced server-side where a modified client cannot bypass
them — and the one place the app lags its own schema, the anonymous flag, is
documented as PARTIALLY IMPLEMENTED with a wire-or-remove roadmap item
rather than hidden."

---


# Chapter 10 — Student Guidance Assistant

The Guidance assistant is a small, deliberately transparent feature, and this
chapter's first job is to prevent a common misreading: the assistant is NOT
an AI model. It is a deterministic keyword matcher — six hand-written rules
with explicit precedences — that answers questions about using Student Codex
and offers generic study-planning advice. Every answer it can give was
written by a developer and lives in one Kotlin file
(`app/src/main/java/com/example/studentcodex/domain/guidance/GuidanceEngine.kt`,
cited below as `…/domain/guidance/GuidanceEngine.kt`, 134 lines). It never
calls an external service, never generates text, and never learns; calling
it an LLM would be false in both directions — to judges and to users.

## 10.1 Purpose and contract

### What it is

The engine's contract is stated in its own interface KDoc: deterministic,
keyword/phrase matching over normalized input with explicit rule precedence;
when confidence is low it must say so and offer a safe next step — it never
invents official university policies, dates, or deadlines; and rules live in
data (`RULES`), not in screen code, so they can be revised and tested
without touching UI (`GuidanceEngine.kt:3-11`). The shipped implementation
is `DemoGuidanceEngine`, constructed eagerly in the app's manual DI
container (`…/di/AppContainer.kt:159`).

### Why Student Codex needs it

A deadline tool's users ask the same handful of questions at the moment of
confusion — how do I add something, why is this list ordered this way, can I
post anonymously — and a deterministic assistant answers those instantly,
offline from any AI service, with zero hallucination risk beyond the
canned text itself. The honest-fallback design (Section 10.4) is the
important part: rather than bluffing, the assistant refuses and redirects,
which is exactly the behavior a documentation-grade project should show in
an assistant-shaped surface.

## 10.2 The rule set

Six rules, each a set of keywords or phrases, a precedence, and a canned
`GuidanceAnswer` (text plus suggested follow-up topics). The precedence
numbers are the whole arbitration system:

| Rule | Precedence | Keywords / phrases (verbatim set) | Answer covers |
|---|---|---|---|
| add-activity | 30 | `add activity`, `add an activity`, `manual activity`, `create activity`, `new activity`, `record activity` | Recording face-to-face deadlines in the Beacon; the similar-activity prompt |
| beacon | 25 | `activity beacon`, `beacon`, `workload`, `upcoming`, `deadline`, `deadlines`, `calendar` | What the Beacon combines and how items are counted |
| classroom | 20 | `classroom`, `google`, `sync`, `import`, `connect` | Read-only Google Classroom import, per-account connection |
| community | 15 | `community`, `post`, `anonymous`, `comment`, `reply`, `report`, `moderation` | Community posting and moderation expectations |
| study | 10 | `study`, `exam`, `test`, `cram`, `review`, `memorize`, `focus`, `concentrate` | Study-session advice anchored to the Beacon list |
| planning | 10 | `plan`, `time management`, `schedule`, `week`, `prioritize`, `procrastinate` | Deadline-first weekly planning advice |

(`GuidanceEngine.kt:45-114`.) Each answer also carries its suggestions —
for example, the add-activity answer suggests "How does matching work?" and
"How does the Activity Beacon work?" — so the conversation continues by
tapping rather than typing, and the suggested starter topics for an empty
conversation are the four shown when the panel first opens
(`suggestedTopics`, `GuidanceEngine.kt:38-43`).

## 10.3 Normalization, matching, and selection

Input is normalized before any comparison: lowercase, trim, strip every
character that is not a letter, digit, or whitespace, then collapse runs of
whitespace to single spaces (`GuidanceEngine.kt:26-27`). Matching is
substring containment — a rule matches when any of its keywords appears as
a substring of the normalized text (`rule.keywords.any { it in text }`) —
and selection takes the matching rule with the highest precedence
(`maxByOrNull { it.precedence }`, `GuidanceEngine.kt:124-126`). Two
consequences follow directly from this design. First, precedence resolves
overlap: a message containing both "beacon" and "community" gets the beacon
answer (25 beats 15), deterministically, every time. Second, the two
precedence-10 rules (study, planning) are peers — a message matching both
resolves to whichever the maximum picks deterministically from the list
order, which is acceptable because both answers are generic advice.

There is no scoring, no partial matching, no confidence value, and no
state: `respond(input: String)` is a pure function of one string
(`GuidanceEngine.kt:12-18`). The ViewModel's KDoc says it plainly — "The
engine is synchronous and deterministic - there is deliberately no loading
state between question and answer"
(`…/ui/guidance/GuidanceViewModel.kt:12-14`).

### One input, traced end to end

A concrete trace shows every rule of the previous paragraphs at work. The
user types `"Deadline tomorrow - how do I add an Activity?"`:

1. Normalization lowercases it, strips the hyphen and question mark, and
collapses the spaces to `deadline tomorrow how do i add an activity`.
2. Keyword containment matches two rules: beacon (`deadline`) and
add-activity (`add an activity` — the phrase survives normalization as
plain words).
3. `maxByOrNull { it.precedence }` picks add-activity (30 over 25), so the
answer is the manual-activity steps with the similar-activity caveat, and
the suggestions offered are "How does matching work?" and "How does the
Activity Beacon work?".
4. The ViewModel appends the user's message and the answer to the
transcript and bumps the unread badge by one; if the panel was closed, the
chat head's red badge is what tells the student a reply landed
(`GuidanceViewModel.kt:33-47`).

The same input will produce the same answer on every device, on every
retry, forever — which is what makes the engine unit-testable in the
strict sense (Section 10.6).

## 10.4 Fallback behavior

Two fallbacks exist, and both texts are worth quoting because they carry the
feature's honesty. Empty input (after normalization) returns:

```text
Ask me anything about using Student Codex, planning your study time,
or the community rules.
```

with the full starter-topic list as suggestions
(`GuidanceEngine.kt:118-123`). Unmatched input — the more important case —
returns:

```text
I do not have a reliable answer for that yet, and I would rather not
guess. Try one of the topics below, or rephrase your question - for
official university policies, dates, or instructor instructions, always
check the official source.
```

with the first two starter topics (`GuidanceEngine.kt:127-132`). The
refusal is load-bearing: the assistant knows its own scope, states that it
will not guess, and points policy and date questions at official sources —
the same honesty anchor the rest of the documentation carries
("recorded is not complete coverage"; FACTBASE §16).

## 10.5 The conversation surface: one ViewModel, two shapes

The assistant's UI is a floating overlay that rides above every page of the
signed-in app (`…/ui/StudentCodexApp.kt:313-319`). Exactly one
`GuidanceViewModel` exists per signed-in session, shared by every surface
that shows the conversation — the chat head's card, the edge handle's card,
and Home's "Ask a study question" button, which expands the same panel
(`…/ui/StudentCodexApp.kt:195-201`, `:269-275`). When the session goes
away, the transcript goes with it: the app root disposes and calls
`clearConversation()` because the shared conversation must not outlive the
account that asked the questions (`GuidanceViewModel.kt:57-65`;
`…/ui/StudentCodexApp.kt:209-213`).

The overlay has two user-selectable shapes, chosen in Settings with
segmented buttons and persisted so the choice survives restarts
(`…/ui/settings/SettingsScreen.kt` `FloatingAssistantPreference`;
`…/ui/StudentCodexApp.kt:203-207`):

- **Chat head** — a draggable bubble; drag to move it, tap to ask a
  question.
- **Edge panel** — a handle docked to a screen edge; drag the handle to
  move it, tap or pull it toward the middle to open.

Both content descriptions are in the strings file
(`strings.xml:289-290`), and the switch previews itself live because the
overlay stays visible over the Settings page. The controller persists more
than the mode: the whole floating presentation — chat head versus edge
panel, the docked positions, and whether the panel stands open — is
remembered through the overlay store, so the assistant reappears exactly
where the student left it (`…/ui/StudentCodexApp.kt:202-207`). The
ViewModel itself tracks an `unreadReplies` counter that the chat head
shows as a badge; a reply counts as seen once the panel is open when it
arrives, and suggestion chips simply send their label as a normal question
(`GuidanceViewModel.kt:22-55`).

The conversation model is exactly the visible transcript: a list of
`GuidanceMessage` entries appended on send — the user's message and the
engine's answer, both at once (`GuidanceViewModel.kt:33-47`). There is NO
context beyond it: `respond()` receives one string, the engine holds no
history, and nothing about previous turns influences the next answer beyond
what the user re-types. This is stated in the fact base as verified
behavior (FACTBASE §10) and is visible in the code's shapes — a stateless
interface plus a message list.

## 10.6 Capabilities, limitations, and canned-text drift

What the assistant does well: instant, offline, deterministic answers to
the six topic families; honest refusal outside them; suggested follow-ups
that keep the conversation inside its own competence; one shared transcript
across every surface; and full unit coverage — `DemoGuidanceEngineTest` is
one of the eleven unit-test files, and the engine, ViewModel, and overlay
controller each have their own test file (FACTBASE §6, §10).

What it cannot do: hold a conversation, remember preferences, answer
anything requiring reasoning over the student's actual data, or produce
text nobody wrote. And one specific honesty point that the documentation
set treats as required reading: the canned community answer overstates the
app — "The community is for study-related posts with up to three images.
You can post anonymously - your name is hidden from other students"
(`GuidanceEngine.kt:85-88`). The schema does allow three images and the
database does support anonymity, but the app posts one image and does not
persist the anonymous flag (Chapter 9). The same drift pattern appears in
three other canned answers, verified by reading them against the shipped
screens:

| Canned claim | Reality | Where |
|---|---|---|
| "up to three images… post anonymously" | One image; anonymous flag never persisted | `GuidanceEngine.kt:85-88`; Chapter 9 |
| "The list is grouped by due date" | Two-tier LIFO stack, no date grouping | `GuidanceEngine.kt:62-67`; Chapter 8 |
| "an optional effort estimate" in the add-activity steps | The editor has no effort field | `GuidanceEngine.kt:50-54`; Chapter 8 |
| "you connect it from your Profile tab" | Classroom connection lives in Settings | `GuidanceEngine.kt:74-77`; Chapter 11 |

None of these are hidden: they are canned strings written before later UI
decisions, they are listed here because a judge may read them on screen,
and fixing them is string editing, not engineering. The rule engine itself
is BUILT & VERIFIED (FACTBASE §3).

## 10.7 Testing and evidence

The assistant is one of the best-covered features in the app relative to
its size. `DemoGuidanceEngineTest` unit-tests the engine itself — the FACTBASE
records it among the eleven unit-test files
(`app/src/test/java/com/example/studentcodex/…`; FACTBASE §6) — and the
surfaces around it have their own files: `GuidanceViewModelTest` for the
transcript and badge behavior, and `GuidanceOverlayControllerTest` for the
persisted overlay presentation (FACTBASE §6). Because the engine is a pure
function over one string, its tests are table-driven assertions of the
form "this input yields this answer" with no mocks, no fakes, and no
flakiness surface — the property that a rule change that shifts an answer
breaks exactly one test line.

The interface/implementation split exists for the same reason the rest of
the app splits: `GuidanceEngine` is the seam, `DemoGuidanceEngine` is the
shipped implementation, and a future engine (or a wired-down rule set)
could replace it without touching any screen — the ViewModel takes the
interface, and the container constructs the implementation eagerly
(`…/di/AppContainer.kt:159`).

## 10.8 Defense answer

If a judge asks "is this an AI assistant": the answer is no, and the
project says so on purpose. "It is a deterministic, unit-tested rule engine
with six topics and an explicit refusal path — no model, no API calls, no
hallucination surface — and where its canned text drifted behind later UI
decisions, the documentation lists the drift instead of papering over it."

---


# Chapter 11 — Profile and Settings

Profile and Settings are two pages with one division of labor between them:
the Profile page is the identity — who the signed-in student is — and the
Settings page is every action — everything the student can change about the
account or the app. This split was an explicit refactor: the Settings
page's KDoc records that the Profile page's Connections and Preferences
sections "moved HERE" (`app/src/main/java/com/example/studentcodex/ui/settings/SettingsScreen.kt`,
cited below as `…/ui/settings/SettingsScreen.kt:80-97`), and the Profile
screen's own closing comment states it as a rule — every action moved to
the Settings page, "this page is the identity itself"
(`…/ui/profile/ProfileScreen.kt:144-146`). This chapter walks both pages
exactly as built, then closes with the one table every examiner should see:
what lives in Supabase and what lives on the device.

## 11.1 Where the pages sit

Settings is the fourth bottom-bar tab (`TopDestination.SETTINGS`,
`…/ui/StudentCodexApp.kt:61-66`); Profile is a pushed route one tap deeper
(`PROFILE_ROUTE = "profile"`), with Back returning to the Settings tab
(`…/ui/StudentCodexApp.kt:292-309`). Sign-out lives on the Settings page
itself, after all of its operation buttons, so the auth gate callback is
passed straight to the tab (`…/ui/StudentCodexApp.kt:297-301`). Guests see
a reduced Settings page — the Profile entry, the floating-assistant card,
the demo notice, the notifications row, and the exit-demo row — because
there is no account behind a guest session to manage
(`SettingsScreen.kt:94-97`).

## 11.2 The Profile page: identity only

### What renders

The page has three visual blocks and no actions. First, a header row with a
back button and the title. Second, a flat identity header: a 56dp
`AuthorMark` avatar (the same author mark the community uses, so the
student's face in the app is consistent), the display name in headline
typography, and under it either "Signed in as {email}" for real sessions or
the "Demo mode — not signed in" banner for guests
(`…/ui/profile/ProfileScreen.kt:88-124`). Third, the school details, one
per line at full width so long names never collapse into a truncated row:
university, program, and year level (`ProfileScreen.kt:126-142`).

The data comes from one repository read. `SupabaseProfileRepository` selects
the student's own `profiles` row with joined labels — program name, campus
name, section name — and composes them: the display name is first plus last
name with a fallback to the username, the university line is the campus
name with a "Partido State University" fallback, and the year line is the
ordinal year label joined to the section name with a dot ("2nd year ·
BSCS 2-A") (`…/data/supabase/SupabaseProfileRepository.kt:25-61`). Guests
get an all-empty profile object rather than a fake one. The screen keeps
the shared state pattern — skeleton while loading, error state with retry,
content — with the same three-state shape every screen in Part III uses
(`ProfileScreen.kt:48-56`).

### The orphaned version note

One string in the resources file deserves its own paragraph because an
earlier documentation draft rendered a claim about it.
`profile_version_note` exists in `res/values/strings.xml:333` — "Student
Codex MVP build — sign-in is real; lists and community content are demo
data, not synced yet." — but no screen references it: a search across the
Kotlin sources returns zero usages. It is an orphaned leftover from the
demo-data phase, and its text is now false (the lists and community content
are live Supabase data, as Chapters 8 and 9 document). The corrected claim,
per the verified fact base, is that the string exists but is rendered by no
screen (FACTBASE §19); profile editing itself remains PLANNED (roadmap
M3.6), which is why the identity page has no edit affordances at all.

## 11.3 The Settings page, row by row

The page is a vertical stack of action cards and two modal sheets, with no
section headers — the row titles carry the grouping
(`SettingsScreen.kt:267-270`):

- **Profile** — one tap to the pushed identity page
  (`SettingsScreen.kt:236-242`).
- **Floating assistant** — the chat-head / edge-panel preference, segmented
  buttons that apply immediately everywhere and persist across restarts
  (`SettingsScreen.kt:459-518`; Chapter 10).
- **Change password** and **Change school details** — each opens its own
  modal bottom sheet (`SettingsScreen.kt:270-286`, `:364-395`).
- **Google Classroom connection card** — registry state, Connect & Sync,
  and disconnect (`SettingsScreen.kt:288-303`).
- **Auto-sync school works** — its own card below the connection card,
  shown only when an account is connected (`SettingsScreen.kt:305-327`).
- **Notifications** — a deferred, non-clickable row (Section 11.8).
- **Sign out** (or **Exit demo mode**) — the last row, no chevron
  (`SettingsScreen.kt:343-359`).

The shared row component makes the clickability honest by construction: an
entry that leads somewhere passes an onClick and shows a chevron; terminal
actions hide the chevron; informational rows pass a null onClick so the
card shows no ripple at all (`SettingsActionCard` KDoc,
`SettingsScreen.kt:398-403`).

## 11.4 Change password

The password sheet wraps the same form that used to sit inline on the page:
new password and confirmation, a save button that disables itself while
saving, and the SettingsViewModel's validation before the call
(`SettingsScreen.kt:535-559`). The write is one call —
`AuthRepository.changePassword()` performs `auth.updateUser { password =
newPassword }` (`…/data/auth/AuthRepository.kt:400-402`) — and it changes
only the email credential; a Google-linked account keeps its Google button
either way. Nothing about the password is stored locally: the session that
survives the change is the Supabase Auth session, refreshed by the same
plugin that restored it at cold start (Chapter 6).

## 11.5 Change school details — re-enrollment through metadata

The school sheet is the sign-up form come back as an edit: the same four
registry dropdowns (campus first, narrowing program), the same course chip
editor, and — because this is also where courses are managed — the Google
Classroom import launcher, wired through the same
`rememberClassroomImportLauncher` handshake the auth gate uses
(`SettingsScreen.kt:203-213`, `:375-395`). The sheet opens prefilled:
`loadSchoolSelection()` reads the four stored references from the profiles
row, with nulls treated as unchosen for legacy accounts, and
`loadMyCourseCodes()` prefills the chips from the student's current
enrollments (`…/data/auth/AuthRepository.kt:84-94`, `:346-362`,
`:384-398`).

Saving is the metadata transport of Chapter 6, run in reverse:
`updateSchoolDetails()` performs one `auth.updateUser` carrying
`profile_completed`, the four school ids, and the course codes — with names
deliberately absent, so the coalescing trigger leaves the name and username
exactly as they were (`…/data/auth/AuthRepository.kt:364-382`). On the
server, the `handle_user_profile_sync` trigger writes the new school
references to `profiles` and re-runs the idempotent `enroll_student_courses`
door for the codes — which is why newly added courses show up in the
Beacon editor's course picker on its very next open
(`…/ui/beacon/BeaconViewModel.kt:158-166`). Removing a chip here only stops
a code from being re-submitted; the enrollment door is append-only
(`…/ui/auth/AuthViewModel.kt:324-329`).

## 11.6 The Google Classroom connection card

The card renders the real registry state from `google_connections` — the
row the `classroom-sync` Edge Function maintains — through the
`ClassroomConnectionState` vocabulary: `NeverConnected`, `Connected` (with
the Google email, last sync time, status and error), `Revoked`, `Expired`,
`Disconnected`, and `NotSignedIn` for guests
(`…/data/repo/Repositories.kt:287-311`). Connect & Sync is where the
screen, not the ViewModel, owns the Google handshake, because the
Authorization API consent sheet needs a live activity
(`SettingsScreen.kt:127-201`):

1. If the registry already knows a connected Google email, the token request
   is pinned to THAT account — a re-sync must never quietly pull another
   account's roster; if the pinned account has left the device
   (`PinUnresolved`), the student picks a real one.
2. Otherwise the system account chooser runs
   (`awaitGoogleAccountChoice`), an AccountManager-backed picker that lists
   every Google account on the device, including managed Workspace accounts
   Google's own pickers sometimes hide (FACTBASE §6).
3. The consent outcome flows to the ViewModel, which runs the Edge Function
   import and stamps the account on the connection registry; cancelled
   consent is silent, and every other failure surfaces under the card
   (`SettingsScreen.kt:139-201`).

Disconnect is the one client-initiated transition the database allows: the
owner may set the connection to `disconnected`, and every other field of
the registry is service-managed — the `guard_google_connection_update`
trigger raises on any attempt to edit the email or the sync stamps
(migration 000800). The full sync mechanics are Chapter 12; this card is
the app-side control surface.

## 11.7 Auto-sync: what the toggle actually does

The auto-sync card is a single toggle, and its behavior is narrower than
the word "auto" suggests — the documentation states the boundary in one
line: ON_START silent sync pinned to the chosen account, and NOT a
background service. When the toggle is on, `ClassroomAutoSyncer.runIfDue()`
runs at every app open and every return from background, triggered by a
`LifecycleEventObserver` on ON_START in the app root
(`…/ui/StudentCodexApp.kt:224-234`, cited by the FACTBASE as
`StudentCodexApp.kt:215-234`), and once immediately when the toggle is
flipped on (`SettingsScreen.kt:313-324`). Flipping it on also refreshes the
connection card so the "last sync" note updates.

Every run is defensive by design (`…/data/repo/ClassroomAutoSync.kt:33-91`):

- Skips unless the toggle is on and the connection state is `Connected`.
- Pins the silent token request to the registry's Google email, so a
  background run can never import a different account's grant.
- Requests the token silently only — an account that would need a consent
  sheet (revoked, expired, new device) is simply skipped, because
  auto-sync must never interrupt the student with a Google dialog.
- Guards overlapping runs with an `AtomicBoolean` (toggle-on racing
  ON_START).
- Never throws; failures stay quiet and the next app open retries.

There is no WorkManager, no FCM, and no foreground service anywhere in the
app — the FACTBASE records a grep-verified zero across functions and
migrations (FACTBASE §6, §11). If nobody opens the app, nothing syncs; and
if a Classroom deadline changes on Google's side, the change is not
reflected until the next successful sync (FACTBASE §11). The repeated runs
are safe because the underlying import is the same idempotent upsert the
manual Sync now button runs — an extra run converges data, it never
duplicates it (Chapter 8, Section 8.5).

## 11.8 The deferred notifications row

Notifications is a DEFERRED capability, and the row says so instead of
pretending: it renders with the standard card styling but a null onClick —
no ripple, no navigation — and its note reads "Deferred - not part of the
first release." (`SettingsScreen.kt:330-341`; `strings.xml:330-332`). It
is shown to guests as well, as a preference row rather than an account
action. This is the same honesty pattern as the community's report queue
(Chapter 9): the row exists so the Settings page reads as a complete map of
the product's surfaces, including the ones that are not built.

## 11.9 Sign out and exit demo

The last row ends the session. For a real session, "Sign out" calls the
auth gate's sign-out, which returns the UI to the gate immediately and
revokes the Supabase session behind it; for a guest, the row is labeled
"Exit demo mode" and skips the remote revoke because there is nothing to
revoke (`SettingsScreen.kt:343-359`; `…/ui/auth/AuthViewModel.kt:683-698`).
The row has no chevron — it is a terminal action, and the visual language
says so (`SettingsScreen.kt:398-403`). Signing out also clears the shared
Guidance transcript, because the conversation must not outlive the account
that asked the questions (Chapter 10).

## 11.10 What is stored where

The app's persistence footprint is deliberately tiny — SharedPreferences
only, no Room and no DataStore (FACTBASE §5) — and the split is worth a
table because it answers the first privacy question any examiner asks:

| Data | Where | Written by | Evidence |
|---|---|---|---|
| Identity: names, username, school references | Supabase `profiles` | the auth triggers | Chapter 6; `SupabaseProfileRepository.kt:25-61` |
| Enrollment transport (school ids, course codes) | Supabase Auth user metadata | sign-up, Google completion, school sheet | `…/data/auth/AuthRepository.kt:364-382` |
| Classroom connection state, last sync | Supabase `google_connections` | the sync Edge Function | migration 000800; Chapter 12 |
| All content: activities, posts, comments, reports | Supabase tables + Storage | Chapters 8-9 | — |
| Auth session (JWT, "stay signed in") | local SharedPreferences via the Auth plugin's default session manager | supabase-kt | `…/data/auth/AuthRepository.kt:190-194` |
| Auto-sync toggle | local SharedPreferences, key `classroomAutoSyncEnabled` | the Settings card | `ClassroomAutoSync.kt:22-31` |
| Overlay mode, docked positions, panel state | local SharedPreferences via `RusshwolfOverlayStore` | the Settings preference, dragging | `…/ui/StudentCodexApp.kt:202-207` |

Nothing sensitive rides the local store: no password material, no Google
tokens (tokens are transit-only and never stored anywhere in the app;
FACTBASE §11), and no content cache — clearing the app's data loses a
preference and a session, not a semester.

Defense answer for judges: "Profile is a read-only identity page fed by one
joined query; Settings concentrates every mutating action, and the
app's entire local footprint is three SharedPreferences-backed preferences
plus the Auth session — every fact that matters lives in the one shared
Supabase backend, which is the whole architectural point."

---


# Chapter 12 — Complete Google Classroom Integration

## 12.1 What this chapter covers

Google Classroom is the largest existing source of structured academic deadlines at the
university: assignments, quizzes and announcements that teachers already maintain online.
Student Codex does not compete with it. The app imports a student's Classroom coursework
read-only and merges it with the face-to-face activities that never reach Classroom at all
(board notes, verbal deadlines, lab schedules) — see Chapter 8 for the Beacon side of that
merge. The integration never writes back to Google: every Classroom API call the system
makes is a read (list courses, list coursework, list announcements), and the OAuth scopes
requested reflect exactly that.

This chapter walks the pipeline in the order a technical judge would probe it: Google
account choice, OAuth scopes and token minting, course listing and import, coursework and
announcement synchronization, Edge Function processing, database writes, multi-student
convergence, failure behavior, automatic synchronization, token hygiene, security, and the
current limitations. Course matching (Chapter 13) and activity identity and
deduplication (Chapter 14) are cross-referenced instead of repeated here.

Status summary before the detail (feature inventory, FACTBASE):

| Capability | Status |
|---|---|
| Classroom course import (picker at sign-up and Settings) | BUILT & VERIFIED |
| Coursework/announcement sync (classroom-sync Edge Function) | BUILT & VERIFIED (live browser-verified 2026-10-28; Edge Functions not re-exercised against real Google OAuth in the 2026-10-30 SQL run) |
| Auto-sync on app open (opt-in; NOT a background service) | BUILT & VERIFIED |
| Import dedup (source-key upsert) + classification | BUILT & VERIFIED (gc_source_identity_test.sql) |
| Teacher category corrections locked across re-syncs | BUILT & VERIFIED (migration 0023) |
| RPC execute hardening (migration 0032) | IMPLEMENTED — VERIFICATION INCOMPLETE (locally tested, NOT deployed to the hosted project) |
| Classroom Pub/Sub event-driven sync | PLANNED (roadmap M4.1, Tier 4 — future work only) |

## 12.2 Two separate Google relationships

The app has two distinct Google touchpoints, and mixing them up is the most common
misreading of the architecture. The first is *identity*: a student may sign in to Student
Codex with their Google account, in which case Android's Credential Manager produces a
Google ID token that Supabase Auth accepts (app/src/main/java/com/example/studentcodex/
data/auth/GoogleAuthManager.kt; wired as `CredentialManagerGoogleAuth` in
…/studentcodex/di/AppContainer.kt:82-84). That flow authenticates the student *to Supabase*
and is labeled IMPLEMENTED — VERIFICATION INCOMPLETE (verified during development; not
re-exercised in the 2026-10-30 pass). The second is *authorization*: reading that
student's Classroom roster, which is a completely different permission, granted through a
different Google API, on a different cadence.

Classroom authorization is the subject of this chapter. It uses the play-services-auth
Authorization API and the classic `GoogleAuthUtil` path — never Credential Manager —
because what is needed is a short-lived *access token* carrying read-only Classroom
scopes, not an ID token. The Supabase OAuth client for Google sign-in is configured in
`supabase/config.toml` under `[auth.external.google] enabled = true` with a public
`client_id`; the Classroom token path does not involve that client at all (the app's
Classroom authorization "uses a public web client ID", supabase/functions/classroom-sync/
index.ts:13).

Every Classroom operation in the app is driven by the Google account the student picked
explicitly. There is no silent single-account resolution anywhere in the flow, as the next
section details.

## 12.3 Google account authentication: the explicit choice

**What it is.** Before any Classroom consent sheet can appear, the app must know *which
Google account* to read. The student makes that decision themselves in a system account
chooser: `awaitGoogleAccountChoice()` in
…/studentcodex/data/auth/GoogleAccountResolution.kt:27-55 launches
`AccountPicker.newChooseAccountIntent(...)` with `alwaysPromptForAccount = true`, limited
to account type `com.google`, and returns the picked account's email or null when the
chooser is dismissed.

**Why Student Codex needs it.** A device may hold several Google accounts (a personal one
plus a school Workspace one), and the Classroom roster usually lives on exactly one of
them. The file's own doc comment states the design intent plainly: "This chooser is THE
Google account choice for every Classroom authorization in the app (import, connect,
re-sync): the student picks the account explicitly, so the roster that gets imported can
never be silently guessed" (GoogleAccountResolution.kt:16-19). The chooser is
AccountManager-backed, so it "lists EVERY Google account on the device, plus an
Add-account row" — deliberately broader than Google's own authorization sheets, which
hide accounts that cannot complete their flow (GoogleAccountResolution.kt:22-25).

**How it works internally.** The chooser is launched through the activity's
`activityResultRegistry` with a registry key, awaited on a `CompletableDeferred`, and
bounded by a 180-second timeout (`PICKER_TIMEOUT_MS = 180_000L`,
GoogleAccountResolution.kt:59). A dismissed chooser (`resultCode != RESULT_OK` or timeout)
returns null and the calling flow treats it as a silent cancel. The import launcher goes
further on the no-silent-guessing rule: "the email typed into the sign-up form is
deliberately NOT used as a silent pin (it may be a personal address while the Classroom
roster lives on a school Workspace account)" (…/studentcodex/ui/components/
ClassroomImportSheet.kt:229-238). An account picked earlier in the same screen session is
reused without re-asking; otherwise the system chooser opens first
(ClassroomImportSheet.kt:254-322).

Once the account is known, every later authorization is *pinned* to it: while the
connection registry knows the connected `google_email`, the Settings connect card and the
auto-syncer reuse exactly that account, so "a re-sync must never quietly import another
account's roster" (…/studentcodex/ui/settings/SettingsScreen.kt:127-136). If the pinned
account has left the device, the authorization returns `PinUnresolved` and the UI falls
back to the system chooser rather than guessing (SettingsScreen.kt:181-199).

**Defense answer.** "Which Google account gets read is always the student's explicit
pick — a system AccountPicker that lists every account on the device, then a pin stored
in the connection registry so background syncs reuse the same account and never another
one's roster."

## 12.4 The OAuth scopes: read-only Classroom

**What they are.** The exact scope strings requested are defined once, in
`ClassroomScopes` (…/studentcodex/data/auth/ClassroomAuthorization.kt:74-81):

```kotlin
object ClassroomScopes {
    val READONLY = listOf(
        "https://www.googleapis.com/auth/classroom.courses.readonly",
        "https://www.googleapis.com/auth/classroom.coursework.me.readonly",
        "https://www.googleapis.com/auth/classroom.announcements.readonly",
    )
}
```

**Why these three.** `classroom.courses.readonly` covers listing the courses the account
is enrolled in — enough for the import picker. `classroom.coursework.me.readonly` covers
the coursework visible to the requesting user in those courses; the `.me.` form is the
student-view scope, not the teacher-wide `coursework.students.readonly` form.
`classroom.announcements.readonly` covers course announcements. Nothing else is requested:
no rosters of other students, no grade access, no post/create/update/delete scopes of any
kind. The Edge Functions make read-only calls against exactly these surfaces:
`courses?courseStates=ACTIVE`, `courses/{id}/courseWork`, and
`courses/{id}/announcements` (supabase/functions/classroom-import/index.ts:77;
supabase/functions/classroom-sync/index.ts:110, 284, 327).

**How they travel.** For pinned requests through the classic GoogleAuthUtil path, the
scopes are joined into GoogleAuthUtil's `oauth2:`-prefixed form
(`CLASSROOM_SCOPE_STRING = "oauth2:" + ClassroomScopes.READONLY.joinToString(" ")`,
ClassroomAuthorization.kt:427-428). For the Authorization API path they become
`Scope(...)` objects on the `AuthorizationRequest` (ClassroomAuthorization.kt:223-225).

> NOTE: the verified fact base summarizes these scopes as "classroom.rosters + coursework
> (read-only)"; the exact strings in code are the three URLs quoted above, and they are
> the authoritative list. No scope grants write access to Classroom.

**Defense answer.** "We request exactly three read-only scopes — courses, my coursework,
announcements — and every API call we make is a read; the app cannot modify anything in
Google Classroom even if it wanted to."

## 12.5 How the app obtains access: the on-device Authorization API

**What happens internally.** `PlayServicesClassroomAuthorizer`
(…/studentcodex/data/auth/ClassroomAuthorization.kt:156) exposes two entry points:
`fetchAccessToken` (interactive — used by the import launcher and the Settings connect
card) and `fetchSilentAccessToken` (silent-only — used by the auto-syncer). The
unpinned interactive path builds an `AuthorizationRequest` with the three scopes and
calls `Identity.getAuthorizationClient(host).authorize(request)`. A subtlety of the
Google SDK is documented in the class KDoc: `AuthorizationClient.authorize` "only returns
the token directly when the account has ALREADY granted the scopes. Otherwise the Task
succeeds with hasResolution() and a PendingIntent pointing at Google's consent activity —
the app must launch that intent itself" (ClassroomAuthorization.kt:139-146). The
implementation therefore launches the consent activity through the activity's result
registry and awaits it with a 300-second timeout (`awaitConsentSheet`,
ClassroomAuthorization.kt:260-298).

The pinned path is different and deliberately so: when an account email is known, the
request "runs the classic GoogleAuthUtil path, which is STRICTLY bound to that account -
the Authorization API's setAccount is only a hint, and with an existing grant for another
account it returns that grant's token silently, which would import the wrong roster"
(ClassroomAuthorization.kt:148-154). `GoogleAuthUtil.getToken` blocks on the network and
runs on `Dispatchers.IO`; a consent-needing account throws `UserRecoverableAuthException`
whose intent is launched (then the token retried once) in the interactive path, while the
silent path converts any pinned failure into `SilentUnavailable` and skips the run
(ClassroomAuthorization.kt:300-362).

**Outcome vocabulary.** The sealed interface `ClassroomAuthorizationOutcome` enumerates
every way a request can end (ClassroomAuthorization.kt:34-72): `Token` ("authorizes one
sync run"), `Cancelled`, `Declined`, `Rejected` (GMS code 13, developer-side fix),
`Error`, `SilentUnavailable` (consent needed — auto-sync must never show a sheet), and
`PinUnresolved` (the pinned email names no account on this device).

**Defense answer.** "Tokens are minted on-device by Google Play services' Authorization
API with an explicit consent sheet; when we know which account should be read we use
GoogleAuthUtil strictly bound to that account, because the Authorization API's account
hint can silently return a different account's grant."

## 12.6 Course retrieval: `classroom-import` action "list"

**How it works.** The `classroom-import` Edge Function's default action lists the ACTIVE
courses of whichever Google account the access token belongs to; the app calls it the
moment consent is granted and renders the result in the course picker sheet. The function
reads `googleAccessToken` from the request body (a missing token is a 400) and calls
Google `courses?courseStates=ACTIVE&pageSize=100`, paginating up to
five pages "most accounts fit one page, a handful of teachers do not"
(supabase/functions/classroom-import/index.ts:71-95). If Google answers 401 or 403 —
revoked, expired consent or missing scope — the function returns a failure telling the
student to reconnect rather than proceeding with a dead token
(classroom-import/index.ts:80-87). The list response trims names to 160 and section
labels to 80 characters before handing them to the app (classroom-import/index.ts:100-110).

**Why "list" needs no Supabase session.** This action is intentionally usable before the
student even has a Student Codex account, so the function is deployed `--no-verify-jwt`
for exactly this reason: "the Google token alone authorizes it (Google returns only that
account's own courses), which lets the pre-sign-up gate offer the import too"
(classroom-import/index.ts:5-10). The action grants nothing and writes nothing; the
security-relevant action is "import", which does require a session (section 12.11).

## 12.7 Course selection and linking: the picker sheet

**Where the picker appears.** The course picker is a modal bottom sheet
(`ClassroomImportSheet`, …/studentcodex/ui/components/ClassroomImportSheet.kt:72-82)
driven by a five-state machine: Idle (closed), Authorizing (Google consent sheet on
screen), LoadingCourses (list fetching), PickingCourses (the tickable course rows), and
Importing (the picked courses being submitted) (ClassroomImportSheet.kt:46-71). It is
offered at sign-up — an "Import from Google Classroom" outlined button inside the course
codes field, above the manual picker, with the hint "Tap to choose which Google account
to import from" (…/studentcodex/ui/auth/AuthGateScreen.kt:828-859;
app/src/main/res/values/strings.xml:317, 329) — and again in Settings, where the same
launcher and sheet are attached to the school details sheet
(SettingsScreen.kt:203-213, 386-390). Google-first accounts also see it during profile
completion (…/studentcodex/ui/StudentCodexApp.kt:160-166).

**What the student picks.** Each row shows the course name as the teacher wrote it and,
when present, the Classroom section label (ClassroomImportSheet.kt:134-156); the ids
behind the rows are the stable Google course ids — "the stable exact-match link"
(…/studentcodex/data/repo/Repositories.kt:221-223) — which is what makes everything
downstream converge (Chapter 13).

**What happens on confirm.** The ViewModel forwards the minted access token, the picked
course ids, and the Google account email to `SupabaseClassroomImportRepository.
importCourses`, which invokes the Edge Function with `action: "import"`, the token in the
body, the id array, and the account email "so the server can pin every later sync to the
same account" (…/studentcodex/data/supabase/SupabaseClassroomImportRepository.kt:60-86;
ClassroomImportSheet.kt:222-226).

## 12.8 Coursework import: `classroom-import` action "import"

**What it is.** The committing action: the picked course ids are turned into real
`courses`, `sections` and `enrollments` rows for the student.

**How it works, step by step** (supabase/functions/classroom-import/index.ts):

1. Identify the caller. The session JWT is taken from the Authorization header — and a
   raw service key submitted as the bearer is explicitly rejected
   (`if (!jwt || jwt === SERVICE_KEY)`, :115) — then verified by calling the platform's
   `/auth/v1/user` endpoint; a non-200 or missing id aborts with `invalid_session`
   (:113-123).
2. Re-fetch from Google server-side. The function first re-lists the account's ACTIVE
   courses (section 12.6), then intersects with the picked ids: "Only ids Google just
   confirmed ACTIVE — a stale/forged id stops here" (:148). A picked id that is no longer
   active is never imported; if none survive, the run fails with
   `no_matching_active_courses` (:149-156).
3. Pre-truncate and call the trusted RPC. The surviving courses are shaped to
   `{externalId, name, section}` within the RPC's guards (:160-164) and submitted to
   `import_student_classroom_courses(p_user, p_courses)` "with the SERVICE key"
   (:166-170). The RPC's matching tiers, advisory locking and cohort convergence are
   Chapter 13's subject.
4. Stamp the connection registry. A successful import writes the `google_connections`
   row as `connected` with `google_email`, `last_sync_at`, and a clean `last_sync_status`,
   "and record[s] WHICH Google account the student picked so every later sync pins to it
   (a background run must never quietly import another account's roster)" (:180-192).
   The write is an upsert with `Prefer: resolution=merge-duplicates` in service context
   (:131-138).

The RPC's own summary (`enrolled`, `created`, `linked`, `matched`, `invalid`,
`sectionsCreated`) is returned to the app verbatim and parsed into
`ClassroomImportResult` (SupabaseClassroomImportRepository.kt:117-144).

**Why the server re-fetches.** Trusting a client-supplied course payload would let a
modified client enroll arbitrary fabrications. By re-fetching from Google with the token
the client just presented, the Edge Function guarantees only real, currently-active
Classroom courses enter the RPC — a forged id "stops here".

**Defense answer.** "The server re-fetches the picked ids from Google before anything is
written, so only real, active Classroom courses can be imported — and the write itself
happens in a SECURITY DEFINER RPC reachable only from the Edge Function's service
context."

## 12.9 Coursework and announcements: the `classroom-sync` import

**What it is.** The second Edge Function imports the coursework and announcements of the
student's *linked* courses as read-only activities. Its header states the contract:
"Imports the signed-in user's Google Classroom coursework + announcements into the
canonical `activities` table as read-only 'imported' evidence"
(supabase/functions/classroom-sync/index.ts:4-5).

**How it works, step by step** (supabase/functions/classroom-sync/index.ts):

1. Identify the caller: session JWT verified via `/auth/v1/user`, exactly as in import
   (:48-59).
2. Probe the Google token: list `courses?courseStates=ACTIVE&pageSize=100`
   (:107-134). A 401/403 is distinguished from other failures: the registry row is
   stamped `revoked` (401) or `expired` (403) with the Google detail truncated to 500
   characters, and the student is told to reconnect (:114-128).
3. Load the student's local sections: the function fetches the caller's enrollments
   joined to sections and courses (limit 500) and keeps those with a course code
   (:136-159).
4. Match each Classroom course to a local section: the exact `external_course_id` link
   first — "Tier 0 — the EXACT link ... so no name heuristic is needed at all"
   (:169-173) — then a normalized course-code comparison, with a preference for the
   section whose name matches the Classroom course's own section label (:174-190). No
   match: the course is "skipped and reported, never force-created" (:19-21,
   :178-184).
5. Import every PUBLISHED coursework item and every announcement of each matched course
   through `upsert_activity_from_source` with the service key (:199-243, :272-364).
   Unpublished coursework is filtered out (`if (cw.state && cw.state !== "PUBLISHED")
   continue`, :301-302).
6. Record the outcome: `google_connections` gets `connected` plus a status of `ok` or
   `partial`, with the skipped lists folded into `last_sync_error` (:367-387), and the
   app receives the summary JSON (:389-402).

**Announcements as activities.** An announcement is imported with the source key
`google_classroom_announcement:{courseId}:{announcementId}`, activity type
`announcement`, a title that is the announcement text collapsed and truncated to 80
characters, and — because "an announcement has no due date; pin it to its post time so it
lands on the calendar day it was made" — a `dueAt` of the announcement's `creationTime`
(:326-354). Classroom coursework maps its `workType` to a Student Codex type:
ASSIGNMENT to assignment, SHORT_ANSWER_QUESTION and MULTIPLE_CHOICE_QUESTION to quiz,
everything else to other (:260-270); migration 0023's title-token classifier then refines
that mapping (section 12.14).

**Due dates.** Classroom dates are DATE-first: "a due date without a time means
end-of-day (23:59) Asia/Manila (fixed +8, no DST)" (:22-24, :245-258) — the same rule
the app applies to manual entries, so imported and manual deadlines sort consistently on
the Beacon.

**A teacher-owned class the student is in** can return 403 on coursework with student
scopes; the class is still matched, but its coursework is skipped and reported with the
reason "coursework not granted by the current Google scopes" — announcements may still
import (:287-294).

## 12.10 From Google data to Supabase tables

The whole chain is: app (Google token + session JWT) → Edge Function (verifies session,
calls Google, decides) → RPC (SECURITY DEFINER, service context) → tables. No client
ever talks to Google at all — every Classroom API call happens inside the Edge Functions
— and no client ever calls either RPC directly (verified: the app makes zero direct RPC
calls, FACTBASE architecture section).

| Step | Actor | Writes to |
|---|---|---|
| Course list | classroom-import action "list" | nothing (read-only probe) |
| Course import | classroom-import action "import" → import_student_classroom_courses | courses, sections, enrollments, google_connections |
| Coursework/announcement sync | classroom-sync → upsert_activity_from_source | activities, activity_sources, google_connections |
| Connection state | both functions, service context | google_connections (upsert merge) |

The sync summary JSON the app renders on the connection card is exactly this shape
(fn_classroom-sync/index.ts:389-402, parsed in
SupabaseClassroomSyncRepository.kt:62-90):

```json
{
  "status": "ok | partial | failed",
  "imported": 3,
  "updated": 11,
  "classesTotal": 6,
  "matchedClasses": [{ "classroomName": "...", "courseCode": "...", "sectionName": "..." }],
  "skippedClasses": [{ "classroomName": "...", "reason": "no matching course code in your subjects" }],
  "skippedCoursework": [],
  "syncedAt": "2026-10-28T02:21:07.342Z"
}
```

`imported` counts items whose source key had no existing `activity_sources` row;
`updated` counts refreshes of rows that already existed — the function checks for the
source row before each RPC call precisely to report these two numbers separately
(fn_classroom-sync/index.ts:211-218, 241-242). Chapter 22's RLS policies govern what
may then be read from those tables.

## 12.11 Edge Function processing: the security boundary

Both Edge Functions verify the caller's Supabase session JWT by forwarding it to
`{SUPABASE_URL}/auth/v1/user` with the service key as apikey; anything other than a 200
with a user id aborts with 401 `invalid_session`
(classroom-import/index.ts:112-123; classroom-sync/index.ts:48-59). The import function
additionally rejects the service key itself presented as the bearer token (:115) — a
session JWT and the service credential must never be confused.

The `classroom-import` header names why this check carries the whole write path:

```text
//   * action "import": the picked course ids are re-fetched from Google
//     (so only real, currently-active Classroom courses enter), then run
//     through import_student_classroom_courses() — the trusted, idempotent
//     RPC from migration 0022 — which resolves each course to an exact
//     external_course_id link (created or name-linked) and enrolls the
//     student in it. THIS action requires the caller's Supabase session
//     JWT (Authorization header), verified manually below — that check is
//     the security boundary that protects the RPC.
```

(supabase/functions/classroom-import/index.ts:11-18)

**What the boundary actually protects.** The RPCs the functions call are
SECURITY DEFINER functions that act *as* the caller the function supplies
(`p_user`) — the database cannot tell a forged p_user from a real one, so the only place
the claim "this user is who they say they are" can be checked is the Edge Function,
where the platform verifies the JWT. The tokens themselves are used in transit only:
"Tokens are used in transit only — nothing is stored server-side" (classroom-import/
index.ts:21-22); the sync function adds "so there is no refresh token to leak and no
client secret anywhere (the app's authorization uses a public web client ID)"
(classroom-sync/index.ts:10-13).

**Defense answer.** "The Edge Functions are the trust boundary: they verify the session
JWT against the platform's own user endpoint, re-fetch everything from Google, and only
then invoke service-context RPCs; the service key never leaves the server environment
and the Google token is never stored."

## 12.12 Database record creation

**What a first import writes.** `upsert_activity_from_source` (created in migration
0008's Phase-5 block, re-created with classification in migration 0023) inserts one
`activities` row with `verification_status = 'imported'`, `created_by_user_id` set to the
requesting student, and one `activity_sources` row with `provider = 'google_classroom'`,
the external ids, the unique `source_key`, and `source_meta` carrying the raw Classroom
facts (courseName, sectionLabel, workType, alternateLink) — "the raw Classroom workType
keeps living untouched in activity_sources.source_meta" (migration 0023 header;
upsert_activity_from_source body in migration 0008:243-260 and 0023:147-166).

**Why guards accept it.** Two triggers would reject these rows from any client
context: `guard_activity_insert` raises `verification_status 'imported' is reserved for
the sync service` for any JWT-carrying caller, and `guard_activity_source_insert` raises
`google_classroom sources are created by the sync service only` when `auth.uid()` is not
null (migration 0002, guard bodies at :188-208 and :255-262). The service context (no
JWT) passes both — which is precisely why the RPC is service-role-only by grant
(migration 0008:265-270) and by its own guard (`if auth.uid() is not null then raise
exception 'upsert_activity_from_source is a service-only operation'`, migration
0008:209-210, unchanged in 0023:106-107). The full identity and dedup mechanics — the
source-key format, the partial unique indexes, convergence across students — are
Chapter 14's subject.

**What the app may then do with such rows.** Imported activities are read-only in the
app: they surface on the Beacon with the Google Classroom provenance chip and the
'imported' verification chip (Chapter 8), and only a teacher's category correction or the
next sync ever changes them.

## 12.13 Multiple students syncing the same course

**Why this matters.** A Classroom course is shared state: every enrolled student's token
returns the same course id, the same coursework ids, the same announcement ids. If each
sync created per-student rows, the university calendar would count one assignment three
times for a three-student class and the teacher dashboard would show phantom workload.

**How convergence happens.** The shared Google identifiers are reused as the shared
database identifiers: the activity's source key is built from the Classroom course and
item ids (Chapter 14), and the course row is linked by `external_course_id` (Chapter
13). Student B syncing what Student A already synced computes the *same* source key, so
the upsert finds A's row and updates it instead of inserting a second one. Migration
0002's design principle says it once for the whole schema: "The canonical activity is
what calendars/workload count — sources, reports and sync attempts are evidence, never
extra workload rows" (supabase/migrations/, migration 0002 header).

**Defense answer.** "Because Classroom ids are the same for every enrolled student, we
use them as the canonical identity — classmates' syncs converge on one shared activity
row instead of stacking duplicates."

## 12.14 What happens when Google data changes

A re-sync is an UPDATE, not an INSERT. When the source key already exists,
`upsert_activity_from_source` refreshes the shared row's title, description, course and
section references, due date, effort and scope, plus `source_meta` (migration
0008:220-239; 0023:117-141). One field is deliberately exempt: the tracking category
follows the classifier only while no teacher has locked a manual correction —

```sql
activity_type = case
  when a.category_locked then a.activity_type
  else public.suggest_activity_category(p_title, p_activity_type)
end,
```

(migration 0023:124-127) — so "a teacher's manual correction is recorded and PROTECTED -
upsert_activity_from_source() refreshes title/description/due dates on every re-sync but
leaves a locked tracking category alone" (migration 0023 header). The corrector is
stamped by the update guard on the false-to-true transition of `category_locked`
(migration 0023:192-194). A deleted Classroom coursework item is *not* removed: the sync
imports what Google lists, and nothing deletes the shared row — an honest limitation
(section 12.19).

## 12.15 What happens when a sync fails

Failures are classified, reported, and — in the automatic path — silent.

- Unmatched classes are skipped and reported in the summary JSON with a reason
  (`skippedClasses`, reason "no matching course code in your subjects"); the run
  finishes with `status: "partial"` and the registry's `last_sync_error` names the
  skipped classes (fn_classroom-sync/index.ts:178-184, 367-387).
- Coursework a teacher's scopes will not share is skipped with the reason "coursework
  not granted by the current Google scopes" (:287-294).
- Google refusing the token sets the registry to `revoked` or `expired` and returns the
  reconnect message (:114-128). Any other failure path (`fail`) stamps
  `last_sync_status: "failed"` with a truncated error and returns a structured
  failure (:97-105).
- The automatic syncer never throws: `runIfDue` wraps the connection read, the token
  fetch and the sync in `runCatching` and returns null on any failure — "Failures stay
  quiet too: the next app open retries" (…/studentcodex/data/repo/ClassroomAutoSync.kt:
  63-90).
- Manual sync surfaces errors: every non-cancel authorization failure routes to the
  ViewModel's error channel and renders under the connection card
  (SettingsScreen.kt:139-166), and the sync result's error/message fields are shown on
  the card (:294-322).

**Defense answer.** "Nothing fails silently in the manual path — every skip and error is
in the summary and on the connection card — and the automatic path is deliberately
silent because it runs at app open and must never interrupt the student."

## 12.16 Automatic synchronization on app open

**What it is.** An opt-in preference that runs the same idempotent sync whenever the app
comes to the foreground. The UI copy is honest about the scope: "Auto-sync school works
— Quietly imports new Google Classroom work every time you open the app."
(strings.xml:307-308).

**How it works.**

1. The toggle lives on its own card in Settings, shown only while the Classroom
   connection is Connected (SettingsScreen.kt:305-322), and persists through
   `RusshwolfClassroomAutoSyncStore` — SharedPreferences via multiplatform-settings, key
   `classroomAutoSyncEnabled`, default false (ClassroomAutoSync.kt:21-31). This is the
   app's only local persistence layer (FACTBASE technology stack).
2. The trigger is an `ON_START` `LifecycleEventObserver` registered in the main
   composable (StudentCodexApp.kt:215-234): every app open and every return from
   background calls `container.classroomAutoSyncer.runIfDue(appActivity)`. Flipping the
   toggle on also fires one immediate run (SettingsScreen.kt:311-321).
3. `runIfDue` declines unless: the toggle is on, the registry state is Connected, and no
   run is already in flight — an `AtomicBoolean` guards the toggle-flip and ON_START
   race (`running.compareAndSet(false, true)`, ClassroomAutoSync.kt:60-61, 79).
4. The token request is silent-only and pinned to the registry's `google_email`:
   `fetchSilentAccessToken` returns a token only if the account already granted the
   scopes; anything needing a consent sheet comes back `SilentUnavailable` and the run
   is skipped — "auto-sync must never interrupt the student with a Google dialog"
   (ClassroomAutoSync.kt:41-48; ClassroomAuthorization.kt:109-128).
5. There is no throttle window, by design: "the sync is the SAME idempotent Edge Function
   the manual 'Sync now' button runs (upsert by source key), so an extra run always
   converges the data instead of duplicating it" (ClassroomAutoSync.kt:36-39).

**What it is not.** It is not a background service. It runs only while the app process
is alive and foregrounded; there is no WorkManager, no foreground service, no push
trigger (section 12.19 and Chapter 15).

**Defense answer.** "Auto-sync is an opt-in foreground refresh — a lifecycle observer,
an in-flight guard, and a silent-only pinned token; it reuses the exact idempotent sync
the manual button runs, so there is nothing to throttle and nothing to break."

## 12.17 Token handling

**The lifecycle of a token.** A Classroom access token is minted on-device for one sync
run: interactive flows show Google's consent sheet when needed; silent flows skip
instead. The token then travels in the request body (`googleAccessToken`) alongside the
account email, both read once by the Edge Function, used against Google, and dropped.
"Tokens are used in transit only — nothing is stored server-side, so there is no refresh
token to leak and no client secret anywhere (the app's authorization uses a public web
client ID)" (classroom-sync/index.ts:10-13; the same claim in
SupabaseClassroomImportRepository.kt:30-35 and
SupabaseClassroomSyncRepository.kt:25-30).

**What is never stored, anywhere.** No refresh tokens, no client secrets, no tokens in
the database — the `google_connections` table's own header comment states the contract:
"REFRESH/ACCESS TOKENS ARE NEVER STORED HERE ... this table only records
status/last-sync" (migration 0008, table block :112-130). The app's local persistence is
limited to the auto-sync boolean (section 12.16).

**Revocation.** Each sync re-authorizes from scratch, so a student revoking the app's
access in their Google account settings takes effect at the next sync attempt: Google
answers 401, the registry flips to `revoked`, and the student is told to reconnect
(classroom-sync/index.ts:114-128; FACTBASE Classroom section). There is no lingering
credential that survives revocation.

**Defense answer.** "We hold a read-only access token for the seconds of one sync run,
never persist it, never hold a refresh token or client secret — revoking access in
Google settings bites on the very next sync."

## 12.18 Security considerations

**Client-side: public by design.** The Android app is built from the URL plus the
publishable key only — "never a secret key" (AppContainer.kt:48-62) — and the teacher
dashboard uses the same publishable key with supabase-js. Row Level Security, not key
secrecy, is the boundary for every client-facing table; the policies that matter here
(activities, activity_sources, google_connections, enrollments) are covered in Chapter
22. `google_connections` is service-managed: the owner may only disconnect, and any
attempt to touch `google_email` or `last_sync_*` as the owner raises
`connection details are managed by the sync service` (migration 0008, guard at :135-162).

**Server-side: the service key stays in the Edge Functions.** Both Classroom functions
read `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` from the Deno environment and refuse
to start otherwise (`server_misconfigured`, 500) (classroom-import/index.ts:41-43;
classroom-sync/index.ts:44-46). All database writes happen with the service key in that
context. A live OAuth client secret does exist in `client.json` at the repository root —
flagged as a credential-hygiene issue on roadmap item M2.5, never used by the app and
never reproduced in documentation (FACTBASE security section).

**The RPCs were the weak point, and migration 0032 closes it.** The F2 audit finding
(2026-10-29/30): `import_student_classroom_courses` takes a caller-supplied `p_user`,
performed no `auth.uid()` check, and was granted to `authenticated` — contradicting its
own "service-context only" header. The reproduced attack enrolled a foreign user into
forged courses and hijacked the `external_course_id` link. Migration 0032 revokes
EXECUTE from `authenticated` (re-asserting the service_role grant), leaving "the Edge
Function's service-key path ... the only remaining caller" (FACTBASE security section;
migration 0032 fix lines cited there). Deployment honesty: 0032 is applied and tested
locally only — the hosted project still runs migrations through 0028, so its status is
IMPLEMENTED — VERIFICATION INCOMPLETE; deploying and re-verifying is roadmap M2.1/M2.2.
`upsert_activity_from_source` never had that exposure: it was service_role-only by grant
from migration 0008 and rejects any JWT caller by guard (section 12.12).

**Defense answer.** "Clients hold only the publishable key behind RLS; the service key
exists only in the Edge Function runtime; and the one RPC that was over-granted is fixed
by a pure privilege revocation in migration 0032 — locally tested, with deployment to
the hosted project as the next roadmap step."

## 12.19 Current limitations and verification state

Honesty first — these are the boundaries a judge should hear from us, not discover:

- **Client-triggered only.** Synchronization runs when the app asks: app open with
  auto-sync on, manual "Sync now", or the import flow. There is no background service,
  no WorkManager, no Firebase push, and no Google Pub/Sub listener — grep-verified zero
  matches across the functions and migrations (FACTBASE Classroom section), and zero
  matches for WorkManager/FirebaseMessaging/Pub-Sub patterns across the inspected
  Android sources in this documentation pass. Event-driven sync via Classroom Pub/Sub
  is PLANNED future work (roadmap M4.1, Tier 4) and must not be presented as built.
- **Propagation delay.** A change in Google Classroom — a deadline edit, a new
  assignment — is not reflected until the next *successful* sync by some student in that
  course, after which the shared row updates for everyone (section 12.14; Chapter 15
  details the timing).
- **Deleted Classroom items linger.** The sync imports what Google lists; it does not
  remove activities whose coursework disappeared from Classroom. KNOWN LIMITATION.
- **One activity row per Classroom item across sections.** A Classroom course serving
  multiple sections writes one activity row whose `section_id` follows the latest syncer
  (migration 0027 header, KNOWN LIMITS block) — visibility remains correct through
  course-level RLS, but the section attribution moves.
- **Verification state.** The two Edge Functions were verified live on 2026-10-28
  (browser-verified end to end); the 2026-10-30 run was a SQL-level verification that
  did not re-exercise the functions against real Google OAuth, so live-OAuth
  re-verification is roadmap M1.5 and the sync path carries the caveat BUILT & VERIFIED
  (live browser-verified 2026-10-28; Edge Functions not re-exercised against real Google
  OAuth in the 2026-10-30 SQL run). Migration 0032 remains IMPLEMENTED — VERIFICATION
  INCOMPLETE (locally tested, NOT deployed to hosted).

---


# Chapter 13 — Course Matching

## 13.1 The problem: one course, many names

A Google Classroom course must land on exactly one `courses` row in Student Codex, or the
whole shared-calendar idea collapses: two rows for the same real course mean two Beacon
feeds, two calendar entries per assignment, and classmates who never see each other's
imported work. The catch is that nobody types a course name the same way twice. The
teacher writes "CC4 - Data Structures and Algorithms 2026-2027" in Classroom; a student
types "CC4" at sign-up; a classmate types "CC4 - Data Structures and Algorithms". Before
migration 0022, matching a Classroom course to the student's own course "demands the
student types the whole course name exactly" (migration 0022, WHY block,
supabase/migrations/). Migration 0027 records what happens without fuzzy help, from a
real user report dated 2026-10-29: a classmate of the same cohort "who types the short
form ... matches nothing exactly, so enroll_student_courses creates a PARALLEL course row
+ a parallel cohort section — and the classmate never sees the imported schoolwork,
because activity visibility is per section_id row (RLS)" (migration 0027, WHY block).

Course matching is therefore not a convenience feature — it is the mechanism that makes
one student's import cover the whole cohort. This chapter documents the implemented
strategy exactly as it runs in `import_student_classroom_courses` (created in migration
0022, revised in migration 0027) and in the `classroom-sync` Edge Function's own matching
step. Chapter 12 covers the surrounding pipeline; Chapter 14 covers what happens to the
imported activities themselves.

## 13.2 The resolution pipeline

When the `classroom-import` Edge Function submits the student's picked Classroom courses
to `import_student_classroom_courses(p_user, p_courses)` (Chapter 12.8), the RPC resolves
each course through three tiers in strict order. The tiers are cumulative safety nets,
not alternatives a caller chooses:

| Tier | Match condition | Result |
|---|---|---|
| 1 | existing course row carries this exact external_course_id | use that row (reported 'matched') |
| 2 | existing course's code or title equals the normalized Classroom name | use that row and link the id (reported 'linked') |
| 2b | existing course resembles the Classroom name (token subset, both directions) | use that row and link the id (reported 'linked') |
| 3 | no course matches anything | create a new row under the Classroom name (reported 'created') |

Two mechanics run around the tiers regardless of which one fires. First, the picked
courses are processed "Sorted by UPPER-CASED name: deterministic order (same input = same
result) AND a global lock order, so two concurrent imports sharing courses can never
deadlock on the advisory locks below" (migration 0022:82-84). Second, each course is
serialized by a transaction-scoped advisory lock — `pg_advisory_xact_lock(hashtext(
'gc-course:' || v_ext))` — whose stated purpose is: "everyone importing this exact
Classroom course converges on ONE row (the partial unique index enforces it; the lock
avoids the throw/catch churn)" (migration 0022:111-115).

### Tier 1 — the exact external id link

Migration 0022 added the link column and made it one-to-one:

```sql
alter table public.courses add column if not exists external_course_id text;

create unique index if not exists courses_external_course_id_key
  on public.courses (external_course_id) where external_course_id is not null;
```

(supabase/migrations/, migration 0022:40-43)

The partial unique index is what turns "linking" into a guarantee: at most one course row
in the entire database can carry a given Google course id, so every student who imports
that Classroom course — this term or any later term — resolves to the same row. Tier 1
simply selects it (`where c.external_course_id = v_ext limit 1`, migration 0027:394-398)
and reports the course under `matched`. The classroom-sync Edge Function honors the same
link first, ahead of any name logic: "Tier 0 — the EXACT link: this local course row was
imported from (or linked to) this very Google Classroom course (migration 0022) by the
classroom-import door, so no name heuristic is needed at all. Hand-typed courses keep
falling through to the name tiers" (supabase/functions/classroom-sync/index.ts:169-173).

### Tier 2 — the normalized course-name match

If no row carries the id yet, the RPC normalizes the Classroom name — `upper(
regexp_replace(v_name, '[^A-Za-z0-9]', '', 'g'))` (migration 0027:392) — and looks for a
course whose code or title normalizes to the same string, "the student added the full name
by hand, or a classmate's import created it" (migration 0022:127-130). Candidates are
ordered so the student's own program wins ties (`order by (c.program_id = v_program) desc
nulls last, c.code`, migration 0027:410-415). A hit does not overwrite blindly: the id is
attached with a guarded update — `update public.courses set external_course_id = v_ext
... where id = v_course and external_course_id is null` — because "The guarded update
keeps a name-twin already linked to a DIFFERENT Classroom course untouched (rare, but
honest)" (migration 0022:141-146). A row already linked to another course is left alone
and simply reported as matched.

### Tier 2b — the fuzzy text match (migration 0027)

Tier 2 requires exact normalized equality, which still misses "CC4" versus the full
banner name. Migration 0027 inserts a fuzzy tier between the exact name match and
creation, built on a shared helper that both enrollment paths use:

```sql
--   course_text_matches(typed, code, title) — shared fuzzy matcher:
--      token-subset comparison in BOTH directions (typed tokens ⊆ course
--      tokens or course tokens ⊆ typed tokens). Tokens are alphanumeric
--      runs ≥3 chars; pure digits and stop-words are dropped from the
--      typed side.
```

(supabase/migrations/, migration 0027:16-21)

The mechanics are deliberately conservative: both texts are lowercased and split on
non-alphanumeric runs; tokens shorter than three characters and pure-digit tokens are
discarded (stop-words like "and", "for", "with" are additionally dropped from the typed
side); the match is true only when one token set is a subset of the other. The comment on
the function itself says it once more: "Conservative by design: no substring/prefix
guessing" (migration 0027:84-86). When several courses resemble the Classroom name, "the
longest candidate code wins = most specific" — `order by ... char_length(c.code) desc,
c.code` (migration 0027:426-432). A Tier 2b hit links the row exactly like a Tier 2 hit
(guarded update, `linked` report).

### Tier 3 — create a brand-new course row

When nothing matches, the RPC creates the course under its Classroom name:

```sql
insert into public.courses (program_id, code, title, external_course_id)
values (v_program, v_name, v_name, v_ext)
returning id into v_course;
```

(supabase/migrations/, migration 0027:456-458)

The new row attaches to the student's program "so they show up in that program's catalog"
(migration 0022:78-80), and its code and title are both the full Classroom name — which
matters downstream because classroom-sync's name tier normalizes and compares against
exactly that text. If two imports race past the advisory lock anyway, the insert raises a
unique violation and the exception handler "re-find[s] whichever row won" by external id,
normalized name, or fuzzy resemblance (migration 0027:460-469). Classmates importing the
same course later hit Tier 1 and never create a second row.

## 13.3 From a matched course to the student's enrollment

A resolved course row is useless to the student until they are enrolled in one of its
sections — that enrollment is what RLS keys Beacon visibility on (Chapter 22). The RPC
first checks whether the student is already a member of the course anywhere: "Already a
member of this course somewhere (e.g. the sign-up chips enrolled the student in the
cohort section): nothing left to do" (migration 0027:477-486). This is what makes
re-imports idempotent — migration 0022's own verify block notes that a re-run reports
`enrolled = 0` with everything under `matched`.

When an enrollment is needed, the section is resolved with a two-step preference,
revised by migration 0027. The preferred section is the importer's *cohort* section —
resolved or created "under the same 'BSCS 2-B' convention as the manual sign-up path",
using the shared helper `cohort_section_name(program, year, block)`: program short name
(the parenthesized suffix of the program name, else the full name, else `CLASS`), a
space, the year, a hyphen, and the block letter (migration 0027:87-103). The stated goal
is convergence: "manual and imported members converge on ONE section row" (migration
0027:27-34). The section lookup matches any section of the course whose name ends with
the importer's `year-block` suffix, preferring one prefixed by the program short name;
if none exists, it is created under the cohort name, guarded by a `gc-section` advisory
lock and a unique-violation re-select (migration 0027:488-525). The fallback, for an
importer with no cohort on their profile, is "the Classroom course's own section label,
else the course name" — deterministic per Classroom course, "so classmates converge on
the same section row" (migration 0027:527-550, quoting migration 0022:188-191).

The final write is deliberately boring: `insert into public.enrollments (section_id,
user_id, role) values (v_section, p_user, 'student') on conflict (section_id, user_id)
do nothing` (migration 0027:557-559). No duplicates, no role escalation, no error on a
concurrent twin — the conflict clause simply absorbs it.

## 13.4 The sync-side view: unmatched courses are skipped, never forced

The `classroom-sync` Edge Function runs its own lightweight matching on every sync
(Chapter 12.9): the exact external id first, then a normalized comparison of the
Classroom course name against the student's local course codes (equality, or the
normalized name starting with the code), with a preference for the local section whose
name equals the Classroom course's own section label
(supabase/functions/classroom-sync/index.ts:168-191). A Classroom course that matches
none of the student's subjects is not force-created: it is appended to `skippedClasses`
with the reason "no matching course code in your subjects" and reported in the summary
JSON — "Unmatched classes are skipped and reported, never force-created" (the same
function's header, :19-21). This is the honest boundary between the two functions: import
*creates* structure with the student's consent (they ticked the course), sync only fills
in coursework for structure that already exists.

## 13.5 A worked example: "CS 101 — Introduction to Programming"

One real-shaped course, three students, both orders of arrival. The Classroom course has
id `gc-9001`, name "CS 101 — Introduction to Programming", and section label "IT-1A".
All three students are in the BSCS program, year 1, in different blocks.

**Student A (block B) imports the course first.** Tier 1: no row carries `gc-9001` —
miss. Tier 2: the normalized name `CS101INTRODUCTIONTOPROGRAMMING` matches no existing
code or title — miss. Tier 2b: no course's tokens are a subset of the Classroom name's
tokens — miss. Tier 3 fires: a new `courses` row is created with
`code = title = 'CS 101 — Introduction to Programming'`, `external_course_id = gc-9001`,
attached to BSCS. A is not yet a member of the course, so the cohort preference resolves
section `BSCS 1-B` (created if absent, under its `gc-section` advisory lock) and A is
enrolled as a student. The import summary reports the course under `created`, with
`sectionsCreated` counting the new section.

**Student B (block A) imports the same course.** Tier 1 hits immediately: the row A
created carries `gc-9001`, and the partial unique index guarantees it is the only one.
The course is reported `matched`. B has no enrollment in this course yet, so the cohort
preference resolves `BSCS 1-A` and B is enrolled there. Result: two students, two
sections, ONE course row — and, once either syncs, one shared set of activity rows
(Chapter 14) visible to both sections through course- and section-scoped RLS.

**Classmate C never imports; C types at sign-up.** If C types the full name, the manual
path's exact tier finds the row. If C types "Introduction to Programming", the manual
path's Tier 1 (exact code) misses, but its fuzzy tier — the same `course_text_matches`
helper — compares C's tokens `{introduction, programming}` ("to" is under three
characters and dropped) against the imported row's tokens `{introduction, programming}`
("cs" under three characters, "101" pure digits — both dropped): the sets are equal, so
each is a subset of the other and the match is true. C is enrolled into the same course
row's cohort section `BSCS 1-C`. One student's import now covers the entire cohort —
exactly the property migration 0027 was written to restore.

**The reverse order — C types first, A imports later.** Suppose C's sign-up created a
manual course with code "Introduction to Programming" (no external id), and A imports the
Classroom course afterwards. Tier 1 misses (no id anywhere). Tier 2 misses:
`CS101INTRODUCTIONTOPROGRAMMING` does not equal `INTRODUCTIONTOPROGRAMMING`. Tier 2b
hits: the Classroom name's tokens `{introduction, programming}` are a superset of the
manual row's tokens, so `course_text_matches` is true, and the guarded update links
`external_course_id = gc-9001` onto C's row (its `external_course_id` was null, so the
update applies; the course is reported `linked`). From that moment the manual row and the
Classroom course are the same course, and every later sync resolves by Tier 1.

**What no tier ever does:** merge two existing rows that are both already populated
(pre-existing differently-spelled twins stay separate — "none exist today", migration
0027:38-40), or create a second row for a course whose id is already linked (the partial
unique index makes that impossible).

## 13.6 Limitations and defense

The implemented strategy is honest about its edges, and judges should hear them stated
plainly rather than discovered:

- **No twin merging.** "Pre-existing differently-spelled twins are NOT merged (none exist
  today); the exact tier still wins for exact text, and a later import links only the
  longest-candidate row" (migration 0027, KNOWN LIMITS). Cleaning up any future twins
  would be a deliberate data pass, not a silent side effect.
- **Fuzzy matching needs a significant token.** "Fuzzy matching needs ≥1 significant
  (≥3-char, non-digit, non-stop-word) token; 'GE 6'-style entries keep today's create
  behavior" (migration 0027, KNOWN LIMITS). Short codes with no letters of length three
  or more fall through to creation — a KNOWN LIMITATION accepted to keep the matcher
  conservative.
- **A multi-section Classroom course writes one activity row whose section follows the
  latest syncer** ("A GC course serving multiple cohorts still writes one activity row
  whose section follows the latest syncer (unchanged upsert semantics)", migration 0027,
  KNOWN LIMITS). Visibility stays correct through course-level RLS; the section
  attribution on the shared row moves.
- **Sync never force-creates.** An unmatched course is skipped and reported
  (section 13.4); only the student-confirmed import creates courses.

**Defense answer.** "Course matching is a deterministic three-tier resolution — exact
Classroom id, normalized name, then a conservative token-subset fuzzy tier — finished by
creating the course under its Classroom name under a per-course advisory lock, with a
partial unique index making the id link one-to-one; classmates therefore converge on the
same course, section and activity rows no matter who imports first or how they typed the
name."

---


# Chapter 14 — Activity Identity and Deduplication

## 14.1 The identity format

Deduplication has to start from one question: when two syncs hand the database two
descriptions of the same assignment, how does the database *know* they are the same
assignment? Student Codex's answer is a source identity — a string that names the item
in Google's own terms, and is therefore identical no matter which student's sync
produced it, no matter when, and no matter how many times. Everything else in this
chapter is the machinery that turns that string into a database-level guarantee.

The format is stated twice in the codebase, once at the table where it is stored and
once in the Edge Function that constructs it — deliberately, so the contract is
checkable from either side. The table definition first
(supabase/migrations/, migration 0002:49-54):

```text
-- activity_sources — evidence about where an activity came from.
-- provider-owned records carry a unique source_key:
--   google_classroom:{courseId}:{courseWorkId}
--   google_classroom_announcement:{courseId}:{announcementId}
-- Many students syncing the same Classroom item must resolve to ONE source
-- row (unique constraint below).
```

The Edge Function states the same contract in its design header — "each Classroom item
is imported through upsert_activity_from_source() — service-only, idempotent by the
unique source_key google_classroom:{courseId}:{courseWorkId} /
google_classroom_announcement:{courseId}:{announcementId} — so a re-sync refreshes
content instead of duplicating rows" (supabase/functions/classroom-sync/index.ts:14-18) —
and constructs the keys inline at the two import sites:

```text
sourceKey: `google_classroom:${course.id}:${cw.id}`,
```

(supabase/functions/classroom-sync/index.ts:305, coursework)

```text
sourceKey: `google_classroom_announcement:${course.id}:${ann.id}`,
```

(supabase/functions/classroom-sync/index.ts:338, announcements)

Three properties follow directly from the format. It is *provider-scoped* (the
`google_classroom` and `google_classroom_announcement` prefixes keep coursework and
announcements from ever colliding — the coursework id space and the announcement id
space are different Google resources, and the prefix keeps them different in our key
space too). It is *global* (the course id and item id are Google's identifiers, not
per-student values). And it is *stable* (Google does not reissue ids for the same
coursework item, so the key computed today equals the key computed next month for the
same assignment). Those three properties are what the whole dedup design stands on.

### The announcement variant

Announcements are a separate Classroom resource, and the import treats them accordingly:
the key prefix is `google_classroom_announcement`, the activity type is hardcoded to
`announcement`, the title is the announcement text collapsed to single spaces and
truncated to 80 characters, and the due date is the announcement's creation time —
"An announcement has no due date; pin it to its post time so it lands on the calendar day
it was made" (supabase/functions/classroom-sync/index.ts:326-354). The `source_meta`
also differs: coursework records `{courseName, sectionLabel, workType, alternateLink}`
(:314-319) while announcements record `{courseName, sectionLabel, kind:
'announcement'}` (:349-353). The dedup semantics are identical for both variants: same
announcement id from two students' syncs, same key, one shared row. The classifier
respects the distinction too — `suggest_activity_category` returns 'announcement'
unchanged whenever its fallback is 'announcement', "Announcements are a different
Classroom resource entirely and are never reclassified by coursework rules"
(supabase/migrations/, migration 0023:49-53).

## 14.2 Why Classroom IDs are shared across enrolled students

A Google Classroom course is a single shared object; every student enrolled in it reads
the same courseWork and announcements resources with the same identifiers. When Student
A and Student B both grant the read-only scopes and sync, Google's API returns the same
`course.id` and the same `cw.id` for the same assignment — the `.me.` in the
`classroom.coursework.me.readonly` scope (Chapter 12.4) restricts *which courses* are
visible, not *which ids* identify the items inside them. This is not an implementation
choice of Student Codex; it is simply how Classroom models a course, and it is the reason
the source key can be used as a shared identity rather than a per-student one.

One nuance is worth stating precisely because judges ask about it: the student scope
limits *reach*, not *identity*. A student's token lists their own courses; it does not
rename the resources inside them. There is also one real case where a matched course's
coursework is not readable at all — a teacher-owned class where the coursework endpoint
answers 403 with student scopes; the Edge Function then skips that course's coursework
with the reason "coursework not granted by the current Google scopes" while the class
itself and its announcements may still import (supabase/functions/classroom-sync/
index.ts:287-294, Chapter 12.9).

The consequence: two completely independent students, on two devices, with two Google
accounts, running syncs minutes or months apart, compute byte-identical source keys for
the same coursework item. The database treats those two syncs as two statements about
one object, not two objects.

## 14.3 Why imported activities must NOT become per-student rows

Suppose each syncing student produced their own `activities` row for the same Classroom
assignment. Three things break immediately. The Beacon would list the same assignment
once per syncing classmate (Chapter 8). The teacher dashboard's calendar and any workload
aggregate would multiply the assignment by the number of syncers — phantom workload,
inflated counts. And a deadline edit in Classroom would update only the rows of students
who synced after the edit, leaving classmates with stale copies that disagree.

The schema's design principles say this once, at the top of migration 0002: "The
canonical activity is what calendars/workload count — sources, reports and sync attempts
are evidence, never extra workload rows" and "Google Classroom identity is unique per
provider item (source_key) so repeated imports cannot duplicate activities (dedup rule
1)" (supabase/migrations/, migration 0002:6-15). So the shape is: ONE `activities` row
per Classroom coursework item — the canonical record everyone reads — with ONE
`activity_sources` row as its evidence, keyed by the shared source key. Which student
happened to sync first is recorded (the activity's `created_by_user_id` and the source's
`reported_by_user_id` are the first syncer), but it does not own the row: the row's
`scope` is `section` (set by the Edge Function on every call,
supabase/functions/classroom-sync/index.ts:236), so the whole section — and every teacher
(Chapter 22) — reads it through RLS like any other class activity.

## 14.4 The constraints that enforce one row

Identity formats are intentions; constraints are guarantees. Two indexes back the source
key, both created in migration 0002 (supabase/migrations/, migration 0002:69-73):

```sql
create unique index if not exists activity_sources_source_key_key
  on public.activity_sources (source_key) where source_key is not null;
create unique index if not exists activity_sources_provider_external_key
  on public.activity_sources (provider, external_course_id, external_item_id)
  where external_item_id is not null;
```

The first is the primary guard: at most one `activity_sources` row in the whole database
may carry a given non-null `source_key`. It is a *partial* index because manual sources
(`student_manual`, `teacher_manual`) legitimately have no source key at all — `source_key
is null` for them, and the partial predicate `where source_key is not null` excludes them
from uniqueness. The second is the belt-and-braces guard: even if some future code path
computed a different string format for the same item, the tuple (provider,
external_course_id, external_item_id) — `('google_classroom', courseId, courseWorkId)` —
still collides and still rejects the duplicate. Two independent locks on the same
physical fact.

These constraints are why the guarantee is unconditional: whatever a buggy or malicious
caller submits, a second `activity_sources` row for the same Classroom item cannot exist.
The worst outcome of a malformed sync is an error, never a duplicate.

**The concurrency case, walked through.** Two students sync the same course at the same
moment, and both Edge Function calls reach the upsert for the same coursework item before
either commits. Each RPC call resolves the source key, finds nothing, and inserts. The
first insert succeeds; the second hits `activity_sources_source_key_key` and fails with a
unique violation — the statement is rejected, the transaction rolls back, and that sync
run reports the failure (the Edge Function converts an RPC error into a structured
`failed` response, supabase/functions/classroom-sync/index.ts:240). No second row exists
at any instant. The *next* sync by either student finds the committed key and takes the
update path. A moment of duplicated *work*, never a duplicated *record* — the correct
trade for a system whose calendars count rows.

## 14.5 upsert_activity_from_source: the trusted writer

**What it is.** Constraints stop duplicates; something still has to write the first row
and refresh it afterwards. That writer is a single SECURITY DEFINER function that both
inserts and refreshes canonical activities: "the trusted, atomic, retry-safe import path
every Classroom sync call will use (idempotent by the unique source_key; converges
instead of duplicating)" (supabase/migrations/, migration 0008:15-18). It was created in
migration 0008's Phase-5 block and re-created with the same signature in migration 0023
to add category classification; the Edge Function's calls did not change, which is why
the function header notes the signature "is unchanged, so the classroom-sync Edge
Function and every existing caller keep working without redeployment" (migration
0023:81-85).

**The service-role-only guard.** The function refuses every JWT-carrying caller before
doing anything:

```sql
if auth.uid() is not null then
  raise exception 'upsert_activity_from_source is a service-only operation';
end if;
if p_provider <> 'google_classroom' then
  raise exception 'this upsert path is for provider imports only';
end if;
```

(supabase/migrations/, migration 0008:209-214; identical in migration 0023:105-110)

The privilege grants match: EXECUTE is revoked from public and granted to `service_role`
only (migration 0008:265-270; re-asserted in migration 0023:171-176). So the function is
reachable from exactly one context — the Edge Functions' service-key calls (Chapter
12.11) — and even a hypothetical direct PostgREST call with a user JWT would be rejected
twice: by the grant, and by the guard.

**The resolution step.** The function looks the source up by key — `select s.activity_id
into existing_activity_id from public.activity_sources s where s.source_key =
p_source_key` (migration 0008:216-218) — and branches on the result.

**The update path (a re-sync).** When the key exists, the canonical row is refreshed in
place: title, description, activity_type, course_id, section_id, due_at, effort, scope,
and `updated_at` are all set from the new Classroom state, and the source row's
`source_meta` is refreshed with it (migration 0008:220-237). Migration 0023's version
adds one deliberate exemption, examined in section 14.6. No new row is created on this
path — the identity already exists, so the sync is a statement of change about it.

**The insert path (a first import).** When the key does not exist, the function creates
the canonical activity — `verification_status` hardcoded to `'imported'`,
`created_by_user_id` set to the requesting student, the activity type passed through
`suggest_activity_category` — and then its evidence row, carrying the provider, the
external ids, the source key, the reporting user, and the source meta (migration
0008:243-262; migration 0023:147-166). Note what is NOT parameterized: no caller can
choose the verification status, and the guards from migration 0002 would reject an
`'imported'` activity or a `google_classroom` source from any client context anyway
(`verification_status 'imported' is reserved for the sync service`,
`google_classroom sources are created by the sync service only`, migration
0002:188-208, 255-262).

**What the classifier contributes on insert.** The Edge Function maps Classroom's
`workType` to a first-guess category (assignment, quiz, other — Chapter 12.9), and
`suggest_activity_category(p_title, p_fallback)` refines it from the title with
word-boundary tokens and a deliberate priority: "PROJECT beats EXAM so 'Midterm
Project' / 'Final Project' read as the deliverable they are; EXAM beats QUIZ so 'Exam
Review Quiz' stays a quiz only when no exam token is present" (migration 0023:47-53).
The rule is deliberately one-way: the classifier "only overrides the Classroom work-type
mapping when the TITLE clearly states a different deliverable ... Unclear titles keep
the work-type mapping - they never default to assignment" (migration 0023:9-15). The
raw workType survives untouched in `source_meta`, so the original provider data is never
lost to the classification (migration 0023:20-22).

**Atomicity and the partial-index predicate.** The source-key upsert contract was
verified by the dedicated test `gc_source_identity_test.sql` (BUILT & VERIFIED,
FACTBASE feature inventory), which exercised the atomic retry-safe upsert pattern against
the constraint:

```text
INSERT ... ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO UPDATE
```

The `WHERE source_key IS NOT NULL` inside the conflict target is REQUIRED, not
decorative: PostgreSQL can only use a partial unique index for conflict arbitration when
the ON CONFLICT clause repeats the index's predicate, so a bare `ON CONFLICT (source_key)`
cannot infer `activity_sources_source_key_key` at all. The shipped RPC body takes the
select-then-update-or-insert route inside one SECURITY DEFINER call (as quoted above),
and the partial unique index remains the hard floor under both styles: whichever way a
concurrent pair of first-imports interleaves, at most one source row for the key can
exist, and every later call resolves to it.

## 14.6 What a re-sync updates — and what it protects

A repeated synchronization is an UPDATE of the shared row. The full field list from the
current body (migration 0023:117-141):

| Field | On re-sync |
|---|---|
| title | overwritten from Classroom |
| description | overwritten from Classroom |
| activity_type | re-classified — unless the category is locked |
| course_id / section_id | re-pointed to the current match |
| due_at | overwritten (Manila-normalized, Chapter 12.9) |
| estimated_effort_minutes | overwritten (null for Classroom items) |
| scope | overwritten ('section') |
| updated_at | refreshed |
| source_meta | refreshed (raw workType, links, labels preserved) |

The one protected field is the tracking category. A teacher's manual correction sets
`category_locked`, and the update path keeps it:

```sql
activity_type = case
  when a.category_locked then a.activity_type
  else public.suggest_activity_category(p_title, p_activity_type)
end,
```

(supabase/migrations/, migration 0023:124-127)

The migration header states the contract: a teacher's correction "is recorded and
PROTECTED - upsert_activity_from_source() refreshes title/description/due dates on every
re-sync but leaves a locked tracking category alone", while "the raw Google Classroom
resource type keeps living untouched in activity_sources.source_meta" (migration 0023
header). The corrector is stamped by the update guard on the false-to-true transition of
`category_locked` (migration 0023:182-194). Status: BUILT & VERIFIED (feature inventory,
FACTBASE).

Note what the protected case implies for an *unlocked* row: the classifier runs again on
every re-sync, so an imported "Midterm Exam" that arrived mapped as assignment by
workType is corrected to exam by its title on the very next sync, and a teacher who
prefers a different category simply sets it once on the dashboard — the lock takes over
from that point. Migration 0023 also shipped a one-time, idempotent reclassification
pass over *existing* rows: "Only non-personal, non-deleted, unlocked rows whose titles
CLEARLY name a different deliverable move; everything else keeps its current category
(no defaulting to assignment). Re-running after the first pass is a no-op"
(migration 0023:214-221). That pass repaired history; the update path quoted above keeps
the present honest.

Two asymmetries are worth stating honestly. A Classroom *deletion* is not a deletion
here — the sync imports what Google lists, so a coursework item that disappears stops
being refreshed but its row remains (KNOWN LIMITATION, Chapter 12.19). And the
classifier only ever runs on the sync path; it never rewrites a teacher's or student's
manual rows on its own.

## 14.7 Requests, attempts, records — three different things

Judges conflate these three, so the documentation must not. They are different objects
with different guarantees:

| Concept | What it is | Can it repeat? | Effect on the database |
|---|---|---|---|
| Repeated API request | one HTTP call to an Edge Function | yes, freely | zero or one upsert per item |
| Repeated sync attempt | one full classroom-sync run (many requests) | yes, freely | zero or one row per source key, ever |
| Duplicate database record | two rows for the same Classroom item | no | prevented by the partial unique index |

A *repeated API request* is cheap and safe: the Edge Function is stateless between
calls, and each item it processes resolves through the source key. A *repeated
synchronization attempt* — auto-sync firing on every app open (Chapter 12.16), a manual
"Sync now", a retry after a failure — walks every item again and lands on the same
resolution: first run INSERT, every later run UPDATE. The Edge Function even
distinguishes the two outcomes in its summary by checking for the source row before each
RPC call — `imported` counts first-time inserts, `updated` counts refreshes
(supabase/functions/classroom-sync/index.ts:211-218, 241-242). A *duplicate database
record* is the one thing in the column that cannot happen for imported items: the
partial unique index on `source_key` rejects the second insert at the storage level, and
the composite (provider, external_course_id, external_item_id) index rejects it again
even under a format change.

A concrete run makes the counters tangible. A course carries 40 published coursework
items and 15 announcements; Student A syncs first and sees `imported: 55, updated: 0`.
Student B syncs the same course a minute later: `imported: 0, updated: 55` — the same 55
keys resolved to the same 55 rows, refreshed rather than created. Auto-sync running on
every app open for a week produces seven `updated: 55` runs and not one extra row. The
counts differ between the two students; the database does not.

> NOTE: this guarantee is specific to *imported* items. Manual student reports of
> face-to-face activities have no provider identity, and their similarity-based
> duplicate prompt does not guarantee deduplication — see section 14.9.

## 14.8 Figure 3 — Shared-activity dedup sequence

The chapter's diagram (Figure 3) shows one coursework item crossing two students' syncs
and landing as one row. Exact content for the figure generator:

```text
Student A sync
  -> classroom-sync Edge Function
     (session JWT verified; Google token in body, transit-only)
  -> upsert_activity_from_source (service role, source_key =
     google_classroom:{courseId}:{courseWorkId})
  -> source key not found: INSERT activities (verification 'imported',
     scope 'section', created_by = A)
     + INSERT activity_sources (source_key, provider 'google_classroom')

Student B sync (same coursework, different student, same ids)
  -> classroom-sync Edge Function
  -> upsert_activity_from_source (same source_key)
  -> source key found: UPDATE the existing shared row
     (title/description/type-unless-locked/course/section/due/effort/scope
     + source_meta) — no second row is created

Teacher category correction at any point
  -> category_locked = true (corrector stamped)
  -> every later sync UPDATE keeps a.activity_type
```

The invariant the figure must make visible: the two students' traffic converges on ONE
`activities` row and ONE `activity_sources` row, and the locked category survives the
right-hand UPDATE. The matching course convergence that precedes this (same course row,
per-student cohort sections) is Chapter 13's subject and is not repeated here.

## 14.9 The contrast with manual entries

Imported dedup is *identity-based*: the same Google ids compute the same key, and a
constraint enforces one row. Manual entries — a student recording a face-to-face
deadline — have no external identity to key on, and the app performs NO duplicate
detection for them (verified 2026-11-01: `BeaconScreen.kt` / `BeaconViewModel.kt`
contain no similarity or matching logic). Two students recording the same real-world
deadline produce two rows. The Guidance assistant's canned text ("Student Codex will
ask whether it is the same one before saving") describes a prompt the app does not
implement — canned-answer drift, documented in Chapter 10 — and title-token logic
exists only in the category classifier `suggest_activity_category`, which suggests
types, never merges rows (the editor behavior is Chapter 8's subject). This is the
precise, defensible boundary: for data with a provider identity we guarantee no
duplicates; for data without one the system stays honest and does not pretend to
merge what two humans typed.

The same asymmetry explains the schema's three provider values on `activity_sources`:
`google_classroom` (keyed, unique, service-written), versus `student_manual` and
`teacher_manual` (unkeyed, human-written, allowed to repeat — they are evidence of who
recorded what, not identity claims). Even on the Classroom side the human trail is kept
honestly: `reported_by_user_id` on the source row names the student whose sync first
created it, and the activity's `created_by_user_id` names the same student — provenance
for the audit trail, not ownership. Nothing about the shared row belongs to that student
in the visibility sense; RLS decides readership from scope and enrollment (Chapter 22).

## 14.10 Limitations and defense

- **Dedup is scoped to provider identity.** Only imported items carry the guarantee;
  manual duplicates are mitigated by a prompt, not prevented (section 14.9). KNOWN
  LIMITATION.
- **Deletions do not propagate.** A coursework item removed from Classroom leaves its
  row in place, unrefreshed by later syncs (Chapter 12.19). KNOWN LIMITATION.
- **Section attribution follows the latest syncer** for a Classroom course serving
  multiple sections (migration 0027 header) — the row stays shared and visible, but its
  `section_id` moves. KNOWN LIMITATION.
- **The verification is test-level for identity, live-level for the pipeline.** The
  identity guarantee was verified by gc_source_identity_test.sql; the Edge Function
  pipeline carrying it was verified live 2026-10-28 and not re-exercised against real
  Google OAuth in the 2026-10-30 SQL run (Chapter 12.19).

**Defense answer.** "Every imported item is identified by the key
google_classroom:{courseId}:{courseWorkId} — Google's own shared ids — enforced unique by
a partial index with a composite second guard, written only by a service-role RPC that
updates on conflict; so repeated syncs, retries, and multiple students converge on one
canonical activity row, and a duplicate imported record is not merely avoided, it is
impossible at the storage level."

---


# Chapter 15 — Synchronization Limitations and Future Improvements

## 15.1 The online-first approach

Student Codex is an online-first application: every meaningful operation — reading the
Beacon, creating a manual activity, posting in the community, importing from Classroom,
loading the teacher dashboard — requires a live connection to the hosted Supabase
backend. There is no local database of activities, no write queue, and no offline mode.
The app's only local persistence is a small set of preferences in SharedPreferences via
multiplatform-settings: the session, the Classroom auto-sync toggle, and the guidance
overlay preferences — "the ONLY local persistence (no Room/DataStore)" (FACTBASE
technology stack; …/studentcodex/data/repo/ClassroomAutoSync.kt:21-31 for the toggle
store). An offline cache and write outbox exist only as design notes in
`docs/OFFLINE-SYNC.md`, which "describes UNBUILT future work and is accurately labeled
as such" (FACTBASE contradictory-docs section); the build status is PLANNED (roadmap
M3.1, Room + WorkManager).

This is a deliberate scope decision for the hackathon build, and it is stated here
plainly rather than papered over: connectivity is a hard precondition for every feature
that touches data. Offline is not a half-supported mode either — the app does not
pretend to work without a network; operations fail visibly with error states on the
screens that attempted them (toasts and error rows, e.g. the connection card's failure
rendering in SettingsScreen.kt:294-322). What is persisted locally is exactly enough to
restore the session on the next launch: the Supabase session token, so a returning
student skips the auth gate while the data itself is always fetched fresh.

What the online-first design buys in exchange is simplicity with a single source of
truth — one shared database, one RLS rule set, and no client/server reconciliation logic
anywhere (Chapter 22). Every duplicate-avoidance and convergence guarantee in Chapters
13 and 14 rests on there being exactly one copy of every row, which is only true
because no client ever holds a divergent copy.

## 15.2 When synchronization runs

Classroom synchronization is *client-triggered*: something in the app must ask for it.
There are exactly three triggers, and each has verifiable preconditions:

| Trigger | Where | Preconditions |
|---|---|---|
| App open / return from background | ON_START LifecycleEventObserver (…/studentcodex/ui/StudentCodexApp.kt:215-234) | auto-sync toggle on; connection Connected; no run in flight; silent token available |
| Manual "Sync now" | Settings connection card (…/studentcodex/ui/settings/SettingsScreen.kt:769-832) | student taps; interactive consent allowed |
| Import picker | course import flow | a sync "fires one right after importing" |

The third trigger is recorded in the import function itself: after a successful course
import stamps the connection, "A follow-up sync (the app fires one right after
importing) refines last_sync_*" (supabase/functions/classroom-import/index.ts:180-185).
Flipping the auto-sync toggle on also fires one immediate run
(SettingsScreen.kt:311-321). Outside these three paths, nothing in the system ever calls
the Classroom API.

The three triggers differ in how they fail. The app-open trigger fails silently by
design — a skipped run returns null and the next open retries (Chapter 12.15). The
manual trigger surfaces every failure under the connection card, including Google
rejections that flip the registry to `revoked` or `expired`. The import-triggered sync
inherits the manual path's error visibility, which is also why the import action's own
failures (invalid session, no matching active courses, RPC errors) are returned as
structured JSON the app renders (Chapter 12.8).

## 15.3 The auto-sync preference

Auto-sync is opt-in and off by default. The toggle lives on its own card in Settings —
shown only while the Classroom connection is `Connected` (SettingsScreen.kt:305-322) —
and its UI copy is precise about what it does: "Auto-sync school works — Quietly imports
new Google Classroom work every time you open the app."
(app/src/main/res/values/strings.xml:307-308). The value persists in SharedPreferences
through `RusshwolfClassroomAutoSyncStore`, key `classroomAutoSyncEnabled`, default
`false` (…/studentcodex/data/repo/ClassroomAutoSync.kt:21-31), so the preference
survives restarts while storing nothing personal and nothing sensitive.

The runtime behavior on each app open is fully specified in Chapter 12.16: toggle check,
connection check, an `AtomicBoolean` in-flight guard, a silent-only token request pinned
to the connected Google account, and a quiet skip whenever Google would need a consent
sheet. The relevant limitation here is the timing: ON_START fires when the app process
is alive and foregrounded — nothing runs before that moment and nothing runs after it.

## 15.4 What requires connectivity

Everything, in both directions. Reads — the Beacon list, activity details, community
feed, teacher dashboard — are live queries against Supabase; there is no cache to fall
back on. Writes — manual activity creation, edits, soft deletes, community posts and
comments, teacher category corrections — go straight to the database; a failed write
surfaces as an error to the user and is not queued for later. The one quasi-exception is
Classroom sync itself: it is also online-only, but because it is idempotent
(Chapter 14), a failed or skipped run costs nothing — the next successful attempt
converges the data exactly as this one would have. That property, not an offline queue,
is what makes the online-first stance survivable for the synchronization path.

Concretely, the connectivity-required set is the entire product surface:

| Operation | Offline behavior |
|---|---|
| Beacon list / detail sheet | error state, no cached list |
| Manual activity create/edit/delete | fails with an error, nothing queued |
| Community feed/post/comment/like | fails with an error, nothing queued |
| Classroom list/import/sync | fails or is skipped; safe to retry later |
| Teacher dashboard (browser) | page fails to load data |
| Guidance assistant | still answers (on-device rules, no network) |

The single offline-capable surface is the Guidance assistant, whose deterministic rules
run entirely on-device (…/studentcodex/domain/guidance/GuidanceEngine.kt) — a nice
demonstration that the limitation is a data-layer decision, not an architectural
inability to run logic locally.

## 15.5 No background synchronization

There is no background execution for Classroom sync: no WorkManager, no foreground
service, no JobScheduler, no Firebase Cloud Messaging, and no server-side listener.
Verification is grep-based and was re-run for this documentation pass: a search across
the inspected source mirrors — the Android Kotlin sources, the Edge Functions, the SQL
migrations, and the manifest — returns zero matches for WorkManager, ForegroundService,
JobScheduler, FirebaseMessaging, or Pub/Sub patterns. The fact base records the same
result repo-wide: "NO background sync, NO push, NO Pub/Sub (grep-verified 0 across
functions+migrations)" (FACTBASE Classroom section). The auto-sync feature is exactly
what its status label says: "Classroom auto-sync on app open (opt-in; NOT a background
service)" (feature inventory) — a lifecycle observer inside a running app, not a service
of any kind.

Relatedly, there is no throttle window even while the app is open: every ON_START
fires an attempt, because "the sync is the SAME idempotent Edge Function the manual
'Sync now' button runs (upsert by source key), so an extra run always converges the data
instead of duplicating it" (…/studentcodex/data/repo/ClassroomAutoSync.kt:36-39).
Foreground-only execution is also a defensible privacy and battery position: the
student's Google token is used when the student is looking at the app, never by an
invisible background process, and no FCM registration exists to keep alive.

The consequence deserves its own sentence, because it is the most commonly
over-assumed property: closing the app stops all Classroom synchronization until it is
opened again.

## 15.6 What happens when the app is not opened

Nothing syncs — for that student. The shared-row design (Chapters 13 and 14) softens
this in one specific, defensible way: because every enrolled student's sync converges on
the same canonical rows, the data stays fresh as long as *some* student in the course
opens the app. One active classmate with auto-sync on keeps the whole section's Beacon
current, and the teacher dashboard current, without anyone else doing anything. That is
the cohort property that migration 0027 was written to protect.

The honest complement: if nobody in a course ever syncs — everyone uninstalled, or
nobody enabled auto-sync and nobody taps Sync now — then nothing about that course ever
updates, and its recorded state grows stale silently. The system has no mechanism that
would notice, let alone repair, that situation.

## 15.7 What happens when an activity changes in Google Classroom

A teacher edits a deadline, publishes a new assignment, or posts an announcement in
Google Classroom. Student Codex does nothing at that moment — no notification arrives,
nothing is polled, no webhook fires. The change is reflected only when the next
*successful* sync by some student in that course pulls the item again, at which point
`upsert_activity_from_source` UPDATEs the shared row (title, description, due date, and
category unless locked — Chapter 14.6) and the correction is instantly visible to every
reader of that row: the whole section and every teacher. Before that sync, every
student sees the old deadline; after it, everyone sees the new one; there is no
per-student divergence because there is no per-student copy.

Two propagation asymmetries complete the picture. A coursework item *deleted* in
Classroom is never removed by sync — the import walks what Google lists, so the row
simply stops being refreshed (KNOWN LIMITATION, Chapter 12.19). And the teacher
dashboard shows recorded information only — "no guarantee that all real-world university
activities have been entered" (FACTBASE teacher-dashboard section) — which compounds
with sync timing: a deadline everyone sees on the dashboard is at best as fresh as the
last successful sync by some student in that course.

Freshness is therefore bounded by student behavior, and the fact base lists it among
the guarantees the system does not make: "freshness of Classroom changes until the next
successful sync" (FACTBASE reliability section, not-guaranteed list). KNOWN LIMITATION.

## 15.8 Real-time Classroom notifications do not exist

To be unambiguous, because this is where a demo can accidentally imply more than is
built: Student Codex has no real-time integration with Google Classroom. There is no
Google Classroom Pub/Sub subscription, no push notification channel, no polling
service, and no event-driven sync of any kind. The roadmap positions Classroom Pub/Sub
event-driven sync as Tier 4 future work (milestone M4.1) and nothing more; presenting it
as anything but PLANNED would misstate the build. Push notifications generally are
DEFERRED — the Settings screen shows a notifications placeholder row (feature
inventory) — and offline support is likewise PLANNED, not partially present.

## 15.9 Future improvements

The roadmap (PLAN.md v2.2 §10.3; NOT approved work) contains the improvements that
would close each gap above. They are listed here with their honest statuses, not as
commitments:

| Roadmap item | What it would add | Status |
|---|---|---|
| M3.1 offline cache + write sync | Room cache, WorkManager outbox, connectivity-aware writes | PLANNED |
| M3.5 push notifications | reminder/deadline pushes beyond the Settings placeholder | DEFERRED |
| M4.1 Classroom Pub/Sub | event-driven sync on Classroom changes | PLANNED (Tier 4) |
| M1.5 Edge Function live-OAuth re-verification | re-run the 2026-10-28 live verification | verification debt |
| M2.1/M2.2 deploy 0029-0032 + hosted verification | ship the RPC hardening to hosted | IMPLEMENTED — VERIFICATION INCOMPLETE (local) |
| M3.2 workload summaries + proposed-deadline preview | teacher analytics on the existing view | PLANNED |

The current architecture was shaped so these land as additions, not rewrites: the sync
is idempotent by source key, so a future Pub/Sub listener or a WorkManager retry can
fire the same upserts with the same convergence guarantees (Chapter 14); the shared
backend means an event-driven server-side syncer would need no client changes at all;
and the auto-sync preference already models an opt-in, privacy-conscious toggle that a
notification system could reuse. No such component exists today.

## 15.10 Defense answer

"We are explicit that synchronization is client-triggered and online-first: it runs on
app open when the student opted in, on a manual tap, or after an import — never in the
background, never via push, and there is no offline queue; Classroom changes propagate
on the next successful sync by any student in the course, at which point one shared row
updates for everyone. The roadmap lists Pub/Sub event-driven sync and offline write
support as planned future work, and we never present them as built."

---


# Chapter 16 — Teacher Dashboard Overview

## 16.1 What the teacher dashboard is

The teacher dashboard is the second client of Student Codex: a browser-based web
application, served as plain static files from the `WebView/` folder, that a
teacher opens to see every recorded academic activity in the university on one
month calendar. Where the Android app is a student's personal tool (my classes,
my deadlines, my notes), the dashboard is a teacher's institutional lens: a
read-mostly, university-wide view of the shared `activities` table that both
clients point at. There is exactly one backend and one `activities` table; the
dashboard simply reads it with a teacher's session instead of a student's
(FACTBASE §4; `WebView/app.js:14-19`).

The dashboard is deliberately small. It is five project files plus two vendored
libraries, with no framework, no bundler, and no build step (FACTBASE §12;
`WebView/README.md` "File map"). Everything it does — sign-in, sign-up, cohort
filtering, the calendar, the read-only student-reported feed, category
corrections — lives in one 2,477-line JavaScript file, `WebView/app.js`, which
the fact base describes as 87 functions and about 111.7 KB (FACTBASE §12). The
chapter inventory below cites that file heavily because that file *is* the
product.

## 16.2 Why Student Codex needs a second client

The problem statement the project defends is that academic deadlines are
fragmented: Google Classroom holds online coursework for the students enrolled
in each course, face-to-face announcements live on whiteboards and in spoken
instructions, and no existing tool shows a teacher what has been recorded
across the whole university (FACTBASE §1). Students are the ones who record —
they import Classroom coursework and report face-to-face activities from the
Android app. Teachers are the ones who need to *see the accumulated record*:
which sections already have a quiz next week, which deadlines collide, what
students have reported from class.

The dashboard therefore does not duplicate the app. It is the read side of the
recording system, plus exactly one write capability (category correction,
Chapter 18). Its own header comment states the design in one sentence: "The
dashboard is VIEW-ONLY: teachers sign up, sign in and look"
(`WebView/app.js:8-12`). No approval queue exists anywhere — when a student
reports an activity it publishes straight into `activities` and appears on this
calendar immediately (`WebView/app.js:9-12`; migration
`supabase/migrations/20260101001500_student_self_publish.sql:4-10`).

## 16.3 Teacher authentication: sign-in

Signing in is email and password only. The dashboard creates one supabase-js
client with the project's publishable key (`WebView/app.js:239-241`) and calls
`signInWithPassword` (`WebView/app.js:1970-1979`). There is no Google sign-in
button here — that path exists only in the Android app. On load, the page
restores a persisted session with `getSession` before showing the sign-in card
(`WebView/app.js:2444-2450`), and an `onAuthStateChange` listener routes
sign-in, token refresh, and sign-out events through the same session handler
(`WebView/app.js:2452-2473`).

What happens internally matters more than the form itself. A successful
sign-in is only *authentication* — the dashboard then verifies that this
account actually holds the teacher role by reading `user_roles` from the
database (`handleSession`, `WebView/app.js:1863-1872`). An account without the
role lands on a dedicated "This account has no teacher access" screen
(`notTeacherHtml`, `WebView/app.js:816-853`) instead of the calendar. This is
the first rung of the authorization ladder described fully in Chapter 19:
signing in does not make anyone a teacher.

The publishable key is public by design. It is embedded in plain text at the
top of `app.js` (`WebView/app.js:26-27`) next to a header comment stating the
security model: every read runs through the signed-in teacher's session and
"row-level security decides what is visible" (`WebView/app.js:14-19`). The
footer repeats the claim on every screen ("publishable key only, never a
service key", `WebView/app.js:393-397`). Nothing sensitive is hidden in the
client; the server is the boundary. Chapter 19 covers the implications.

Sign-in errors are translated into plain language before display:
`friendlyAuthError` maps invalid credentials, unconfirmed email, the
`SCHOOL_EMAIL_REQUIRED` domain-gate error, the mailer's hourly email quota,
rate limits, and expired one-time links to human-readable sentences
(`WebView/app.js:175-207`). The sign-in card also carries a demo box with a
"Use demo teacher credentials" button (`WebView/app.js:746-751`) that fills the
form from the `DEMO_EMAIL` / `DEMO_PASSWORD` constants (`WebView/app.js:28-29`).
Demo credential *values* are intentionally not reproduced anywhere in this
documentation; they are documented in `WebView/README.md` and defined as
constants in `WebView/app.js:28-29`, which is where a judge can find them.

## 16.4 Teacher registration (sign-up)

### The current flow: role-only sign-up

Today's sign-up form asks for exactly four things: first name, last name,
school email, and a password of at least six characters
(`signUpFormHtml`, `WebView/app.js:766-814`; `canSubmitDraft`,
`WebView/app.js:755-758`). In place of any class selection it shows a static
"No class setup needed" box explaining that the account will see activities
from every campus, program, year level, block and course, narrowed later with
the dashboard filters (`WebView/app.js:789-794`).

Internally, `signUpTeacher` (`WebView/app.js:1992-2049`) performs two steps.
First, `auth.signUp` creates the account with `teacher_signup: true` plus the
name in the user metadata (`WebView/app.js:1998-2012`). Because email
confirmation is currently OFF on the project (Chapter 19), Supabase returns a
session immediately and no email is sent. Second, the dashboard calls the
`teacher_signup_global` RPC (`WebView/app.js:2024`), which grants the teacher
role and nothing else — no campus, program, year, section or course choices,
no enrollments (migration
`supabase/migrations/20260101001900_global_teacher_visibility.sql:143-167`).
If the RPC is missing on the target project, the form explains that a database
update is needed rather than failing silently (`WebView/app.js:2035-2042`).

### The legacy multi-group flow

An older registration flow, still fully supported server-side, collected up to
12 *class groups* through four multi-select dropdowns (campus, program, year
level, block) whose checked combinations became removable chips; the
`teacher_signup_multi` RPC (migration
`supabase/migrations/20260101001600_teacher_signup_multi.sql`) granted the role
and enrolled the account in every added group's sections at once. This flow is
documented in `WebView/README.md` ("Create teacher account"), and the 12-group
cap is enforced server-side in the RPC body (cap check in the 0031
redefinition, `supabase/migrations/20260101003100_teacher_school_email_domain.sql:127-137`).
The demo teacher accounts listed in `WebView/README.md` were created through
these multi-group pickers during verification.

In the current `app.js`, the multi-group picker itself is no longer part of the
sign-up form — the 0019/0020 product decision made teacher sign-up
cohort-free, so the form above says "No class setup needed"
(`WebView/app.js:789-794`). What remains is the *completion path* for accounts
whose sign-up predates that change: `derivePendingTeacherSignup`
(`WebView/app.js:1827-1851`) normalizes legacy `class_groups` (or older
single-group) metadata from the session, and `activateTeacher`
(`WebView/app.js:2051-2084`) finishes those legacy pending sign-ups by calling
`teacher_signup_multi` with the preserved groups (`WebView/app.js:2055-2059`),
or `teacher_signup_global` for cohort-free accounts. The activation card on the
"no teacher access" screen offers this with one button
(`WebView/app.js:831-844`). So the accurate statement is:
`teacher_signup_global` is the RPC the live sign-up form calls;
`teacher_signup_multi` is the legacy RPC that still completes pre-change
activations and still accepts new calls under its own 12-group cap.

### The email gate: client hint, server enforcement

The form will not submit unless the typed address ends with the school domain:
`SCHOOL_EMAIL_SUFFIX = '@parsu.edu.ph'` (`WebView/app.js:35`), checked by
`isSchoolEmail` (`WebView/app.js:477-479`) through `emailLegalityError`
(`WebView/app.js:481-492`), which also rejects a curated blocklist of
disposable email domains (`WebView/app.js:465-473`) and keeps the submit
button disabled until the draft is valid (`WebView/app.js:2391-2402`). The
field's hint text states the rule plainly: "teacher accounts are school-domain
only" (`WebView/app.js:778-780`).

The client check is convenience, not security — it stops typos from creating
an account that could never activate (`WebView/app.js:30-34`). The REAL gate
is server-side: both `teacher_signup_global` and `teacher_signup_multi` read
the caller's `auth.users.email` through SECURITY DEFINER rights and raise
`SCHOOL_EMAIL_REQUIRED` unless it ends with `@parsu.edu.ph` (case-insensitive
exact suffix; `@notparsu.edu.ph` and `@sub.parsu.edu.ph` both fail)
(`supabase/migrations/20260101003100_teacher_school_email_domain.sql:69-75`
and `:118-125`, match semantics `:22-28`). Because the check reads the table
rather than JWT claims, a tampered token cannot smuggle a different address
past it. The dashboard translates the error into one sentence — "Teacher
accounts are for @parsu.edu.ph school email addresses" — in both the auth and
RPC error paths (`WebView/app.js:181-183`, `:221-227`).

## 16.5 The dashboard: cohort filter bar

Once signed in, the teacher sees a header (name, email, sign-out), a filter
bar, the month calendar, and two side cards. The filter bar
(`filterBarHtml`, `WebView/app.js:1193-1237`) offers four filters — Campus,
Program, Year, Section — plus a live count line and a Reset button. Its options
never come from hard-coded lists: `fetchRegistry`
(`WebView/app.js:248-269`) loads the `campuses`, `programs`, `year_levels`,
and `year_sections` tables directly from the database, so every campus, all 50
programs, years 1–5 and every block the university actually offers are
pickable (`WebView/README.md` "Cohort filter bar"). The registry is
anon-readable, so it populates even before any account signs in
(`WebView/app.js:2430-2442`), and each dropdown is a searchable combobox with
keyboard support rather than a native select, because the program list alone
runs to 50 entries (`comboOptions` `WebView/app.js:979-1047`; keyboard
handling `WebView/app.js:2324-2360`).

The count line under the bar's title reads "N of M sections · K scheduled in
<Month>" — the number of sections matching the current filter out of all
sections, and how many activities are scheduled in the visible month
(`WebView/app.js:1209`). Reset clears all four filters in one tap (the Reset button renders at
`WebView/app.js:1233-1235`; its handler at `:2268-2271`), and a fresh
sign-in always starts unfiltered so one teacher's view is never inherited by
the next (`WebView/app.js:1955-1957`). When a filter matches none of the
sections, an inline note says so and suggests resetting
(`WebView/app.js:1229-1232`). Picking a campus re-validates the program filter
against that campus's offerings, the registry-driven cascade
(`WebView/app.js:876-882`, `:2177-2181`).

Since the 0019/0020 university-wide decision, these filters narrow *all*
sections in the registry, not just the teacher's own — the filter bar's
comment says exactly that, with the caveat that row-level security still keeps
personal student activities private to their creator
(`WebView/app.js:1199-1202`). Chapter 17 covers what that means.

## 16.6 The month calendar

The calendar (`calendarHtml`, `WebView/app.js:1241-1345`) renders a fixed
six-row by seven-column grid starting on the Sunday of the month's first week
(`WebView/app.js:1256-1266`). Activities appear *inside the day boxes* as
type-colored chips: an icon and the title, up to three chips per day
(`MAX_CHIPS`, `WebView/app.js:41`), with a "+N more" overflow marker
(`WebView/app.js:1273-1293`). The month bar above offers previous / next /
Today navigation (`WebView/app.js:1303-1307`).

Data comes from `fetchMonth` (`WebView/app.js:1642-1675`): a single PostgREST
query on `activities` restricted to `scope = 'section'`, `deleted_at` null,
and `due_at` within the visible month, ordered by due time and capped at 500
rows (`WebView/app.js:1656-1663`). Two details in that query are deliberate.
First, the scope filter keeps the calendar on the section grid — course-only
rows have no section to render and stay off it by design, even though RLS
would let a teacher read them (`WebView/app.js:1653-1655`). Second, months are
cached in memory (`monthCache`, `WebView/app.js:349`), and a completely empty
month triggers a quiet probe of the neighboring months so the calendar can
show a "Nothing scheduled in <Month> — N activities in <next month>" jump hint
instead of looking broken (`probeNearbyMonths` `WebView/app.js:1689-1709`;
`emptyMonthHintHtml` `WebView/app.js:1711-1734`).

Clicking a day opens a day-detail dialog (`daySheet`,
`WebView/app.js:1475-1529`) listing that day's activities with course,
section, due time, effort, a description preview, and a verification badge.
Clicking a chip, a day-sheet row, or a feed row opens the full-content
activity sheet (`activitySheet`, `WebView/app.js:1558-1620`): the complete
title and notes (long notes start clamped and grow through a See more / See
less toggle that appears only when the text really overflows,
`WebView/app.js:1607-1619`), the origin badges, and — for sections the teacher
teaches — the category picker (Chapter 18). Dialogs stack: the day sheet can
open the activity sheet on top of itself, and Escape or a backdrop click pops
only the top one (`WebView/app.js:1434-1461`).

The calendar legend is interactive (`WebView/app.js:1320-1343`). Each of the
six category buttons (Assignment, Quiz, Exam, Project, Announcement,
Activity) toggles a category filter; two more toggles filter to
student-reported entries and to past-due entries (`matchesCategoryFilters`,
`WebView/app.js:857-869`). A status line reports how many entries the category
filters are hiding (`WebView/app.js:1340-1342`). The legend doubles as the
key to the chip colors and the past-due graying described below.

## 16.7 Provenance labels, past-due graying, the feed, and coverage

Every dashboard entry carries its origin. `VERIFICATION_META`
(`WebView/app.js:54-59`) defines four badges — Teacher-confirmed,
Classroom-imported, Student-reported, Needs review — rendered on day sheets,
the activity sheet, and chip tooltips (`WebView/app.js:1289`,
`:1505-1511`, `:1589-1593`). Student-reported entries additionally get a
dashed chip outline and a secondary "Student-reported" badge, so a teacher can
tell at a glance which deadlines students reported from class versus which
came from a Classroom import (`WebView/app.js:1289`, `:1591`; the legend
documents the dashed outline at `:1330-1332`). This is the same provenance
honesty the Android app renders as Classroom/Manual badges (FACTBASE §8).

Past due reads as done. Entries are never deleted from the calendar; the day
after their due date they gray out — chips, day-sheet rows, and feed rows —
and pick up a "Done" badge, while due-today entries stay live until midnight
(`WebView/app.js:1277-1279` whole-day granularity; graying classes at
`:1289`, `:1505-1511`; feed rows `:1367-1370`; sheet badge `:1592`). The
legend states the rule outright: "Dark green = past due (done)"
(`WebView/app.js:1334-1338`).

The side column holds two read-only cards. The Student-reported card
(`studentReportsPanelHtml`, `WebView/app.js:1357-1395`) lists the
student-reported activities already shown on the calendar for the visible
month, with the reporter's name (resolved from `profiles` by
`ensureReporterProfiles`, `WebView/app.js:1736-1751`), due date, section, and
a description preview. Teachers never act on these — "publishing IS the
student's action" (`WebView/app.js:1354-1356`); there is no approve/reject
control anywhere in the file. The Data coverage card
(`coverageCardHtml`, `WebView/app.js:1399-1430`) states where the calendar's
data comes from (Classroom sync status for connected students, the last
refresh timestamp, a Refresh button) and repeats the privacy rule: teachers
see section-scoped records across every campus and program; personal student
activities remain private by design (`WebView/app.js:1426-1427`). The
dashboard also silently refreshes when the teacher returns to a tab left open,
if the data is older than ten seconds (`autoRefreshOnReturn`,
`WebView/app.js:1922-1938`) — there is no server push; all loads are
client-triggered.

## 16.8 Category correction (overview)

The dashboard's only write path is the category correction, covered in depth
in Chapter 18. In brief: the activity sheet shows a six-option category picker
only when the signed-in teacher is enrolled (as teacher) on that activity's
section or course (`categoryRowHtml`, `WebView/app.js:1538-1556`; the
taught-section sets are computed in `fetchBundle`, `WebView/app.js:1779-1786`).
A correction PATCHes `activity_type` and `category_locked` onto the row
(`WebView/app.js:2189-2241`), saves immediately, and is preserved on future
Classroom syncs. If RLS filters the update to zero rows, the dashboard shows
"You can only correct categories for sections you teach."
(`WebView/app.js:2206`). Teachers cannot edit deadlines, titles, or owners
anywhere in the dashboard — no such control exists in `app.js`.

## 16.9 Student app versus teacher dashboard

The two clients share one backend but answer two different questions. The
following comparison is the one to give a judge who asks why this is not one
app.

| Aspect | Android student app | Teacher dashboard |
|---|---|---|
| Client | Native Kotlin + Jetpack Compose, Material 3 | Browser, vanilla HTML/CSS/JS |
| View | Personal + own sections (enrollment-driven) | University-wide, all non-personal activities |
| Writes | Manual activities, student reports, posts, comments | Category corrections only |
| Classroom | Import + sync (OAuth per student) | Read imported results only |
| Personal activities | Creator's own private planner | Never visible (RLS keeps them private) |
| Community, guidance | Included | Not present |

Evidence for the right column: the dashboard performs no inserts anywhere in
`app.js` — its single `.update` call is the category PATCH
(`WebView/app.js:2200-2203`); its header declares it view-only
(`WebView/app.js:8-12`); and the read scope is the 0019 policy described in
Chapter 17. The left column is the Android app's verified feature set
(FACTBASE §6, §8).

## 16.10 Mobile layout, error states, and toasts

The dashboard is responsive. `index.html` ships the standard viewport meta
(`WebView/index.html:5`), weekday headers render full names on wide screens
and single letters on narrow ones (`wd-full` / `wd-1` spans,
`WebView/app.js:1312-1314`), and header buttons swap visible and
screen-reader-only labels at small widths (`hide-sm` / `sr-only-sm`,
`WebView/app.js:906`). The full responsive design system lives in
`WebView/styles.css` (47.5 KB per FACTBASE §12; the deep-green `#2f5b41` brand
palette per the README file map). The README notes the folder works in Chrome,
Edge, and Firefox.

Failures are surfaced, never swallowed. A failed dashboard load renders a
destructive alert with the error text and a Retry button
(`WebView/app.js:913-921`); a failed registry load shows its own error on the
sign-up card (`WebView/app.js:796`, `:2438-2442`); a filter search with no
matches says so (`comboNoneHtml`, `WebView/app.js:1084-1087`); empty states
for no sections and no student reports carry explanatory copy
(`WebView/app.js:923-930`, `:1386-1392`). Successes and failures of the
category correction arrive as toasts — "Category updated … Future Classroom
syncs keep it." or "Could not update the category" with the server message
(`toast`, `WebView/app.js:1624-1638`; calls at `:2215-2218` and `:2231-2235`).

## 16.11 File inventory and the no-build-step deployment story

| File | Role |
|---|---|
| WebView/index.html | Entry shell; mounts #app, #overlays, #toasts; loads scripts |
| WebView/styles.css | The full design system (47.5 KB) |
| WebView/app.js | All logic: auth, registry, calendar, dialogs (2,477 lines) |
| WebView/vendor/supabase.min.js | supabase-js v2 bundled as a classic script |
| WebView/vendor/lucide.min.js | Lucide icon set (UMD) |
| WebView/README.md | Run instructions, demo account locations, config notes |

Evidence: the README file map (`WebView/README.md` "File map") and FACTBASE
§12, which records the file sizes and the "NO framework, NO build step" check.
`index.html` is a 1,204-byte shell whose body is three mount points and three
classic script tags — the vendored Supabase client, the vendored icon set, and
`app.js` (`WebView/index.html:12-22`). If the vendored Supabase script fails
to load, the app renders a "Could not load the dashboard runtime" alert rather
than a blank page (`WebView/app.js:231-237`).

Deployment is opening the folder. The README's two supported paths are:
double-click `index.html` (everything except the data is inside the folder;
only data goes over the network), or serve the folder with any static file
server such as `python -m http.server` for nicer URLs (`WebView/README.md`
"How to open it"). There is no Node toolchain, no bundling, and no
environment-specific build: the same files run from disk or from a static
host. The folder is also laid out to drop into
`app/src/main/assets/webview/` later and load inside the Android app's own
WebView, because the app already ships the same publishable key
(`WebView/README.md` "Embedding in the Android app (later)").

## 16.12 Limitations and defense answer

The dashboard is BUILT & VERIFIED as a feature set (browser-verified
2026-10-28, FACTBASE §3), with honest limits. It is online-only — a static
page talking to hosted Supabase, with no offline mode anywhere. It shows
RECORDED information only; it does not guarantee that all real-world
university activities have been entered (Chapter 17). It offers no workload
summaries or analytics — those are PLANNED, not built (Chapter 17). Its only
write is the category correction; teachers cannot edit deadlines or titles,
and there is no approval queue to moderate student reports. Demo seed data and
demo teacher accounts live on the hosted project (FACTBASE §16; locations in
`WebView/README.md`), and the current email-confirmation-off configuration is
a testing decision discussed in Chapter 19.

Defense answer: "The teacher dashboard is a zero-build static web app — five
files plus two vendored libraries — that reads the same Supabase tables the
Android app writes, under the same row-level security. It gives teachers a
university-wide, provenance-labeled calendar of everything students and
imports have recorded, plus exactly one corrective write (category), and it
makes no claim beyond what was actually recorded."

---


# Chapter 17 — University-Wide Workload Visibility

## 17.1 What university-wide visibility means

By default, a teacher who signs into the dashboard sees recorded activities
from every campus, program, year level, block and course in the university —
not only the sections they personally teach. This is a deliberate product
decision, recorded in the migration that implemented it: teacher sign-up
carries no campus/program/year/section/course choices, "a teacher is just an
account with the teacher role; the dashboard shows activities from EVERY
campus, program, year, block and course in the university, and the teacher
narrows the view with the filter bar" (migration
`supabase/migrations/20260101001900_global_teacher_visibility.sql:4-10`; the
file's own header comment titles it "0020 — Global Teacher Visibility", and
`WebView/app.js` comments refer to the change by both numbers). Cohort-
restricted teacher calendars — visibility driven by the teacher's own
enrollments — were retired for reads at the same time.

Student Codex needs this because the problem it attacks is fragmentation at
university scale. A teacher asking "is anything already scheduled for BSCS
2-A next week?" is not asking about their own sections only; they are asking
about the record as a whole, including deadlines other teachers set and work
students imported from Classroom or reported from class. Restricting the
answer to taught sections would rebuild the exact silo the project exists to
remove.

## 17.2 How the read policy works

The mechanism is one clause in the `activities_select` RLS policy. A teacher —
resolved by the established `has_role('teacher')` SECURITY DEFINER helper —
may read every non-personal activity, regardless of enrollment:

```sql
-- 0020: university-wide teacher read — no enrollment needed.
or (
  public.has_role('teacher')
  and scope in ('section', 'course')
)
```

Evidence: `supabase/migrations/20260101001900_global_teacher_visibility.sql:47-87`
(the full policy, teacher branch at `:63-67`). Students keep exactly the same
visibility as before: their own rows, rows they participate in, and
section/course-scoped rows of sections they are enrolled in
(`:68-85`). Soft-deleted rows stay hidden from everyone but their creator
(`:55`). The migration also adds the identical teacher branch to the
`activity_visible_to_user()` helper so participants/reports/sources policies
keep a single source of truth for visibility (`:95-135`, with the
`viewer = auth.uid()` guard at `:110-114` so one caller's role powers can
never leak to another user id). Chapter 22 covers the full policy set.

Two design notes from the migration are worth repeating to a judge. The policy
uses `has_role()` rather than a raw `user_roles` EXISTS because `has_role` is
the SECURITY DEFINER helper every other policy already trusts — it bypasses
`user_roles` RLS and avoids recursion (`:30-35`). And because PostgreSQL
enforces a SELECT policy's USING as a WITH CHECK on updated rows, the
visibility rule also constrains what an updated row may become (`:50-54`).

## 17.3 What the calendar actually renders

RLS decides what a teacher *may* read; the dashboard decides what it *draws*.
The month query filters `scope = 'section'` explicitly, because the calendar
is a section grid and course-only rows have no section to render
(`WebView/app.js:1653-1663`). Course-scoped rows are therefore readable by a
teacher under RLS but intentionally stay off the calendar. Every rendered row
carries its `due_at`; the query windows `due_at` between the first and last
instant of the visible month (`monthRange`, `WebView/app.js:158-162`;
`.gte/.lte` at `:1660-1661`), orders by due time, and caps at 500 rows
(`:1663`). Classroom-imported due dates arrive normalized to Asia/Manila
23:59 (FACTBASE §11), so day-box placement is consistent across imports.

The cohort filters from Chapter 16 narrow this university-wide result set
client-side: `filterSections` matches each section's campus, program, cohort
year and block against the chosen filter values (`WebView/app.js:952-960`),
and only activities in the surviving sections are drawn
(`WebView/app.js:884-889`). The filter lists themselves come from the full
registry tables, not from the teacher's own assignments
(`WebView/app.js:979-1047`). The whole arrangement means a teacher needs no
cohort on their account at all: `fetchBundle` loads every section in the
registry and derives each one's program and campus by joining courses and
programs, precisely because the teacher-enrollment query is gone
(`WebView/app.js:1758-1816`).

The contrast with the student side is the point. A student's Beacon list is
enrollment-driven — they see their own rows plus the section/course-scoped
rows of sections they are enrolled in (FACTBASE §8). A teacher's calendar is
role-driven — the same section-scoped rows, but for every section in the
university. The table below is the complete read matrix after migration 0019:

| Row scope | Enrolled student | Other student | Teacher | Creator |
|---|---|---|---|---|
| personal | no | no | no | yes |
| section (own section) | yes | no | yes | yes |
| section (other section) | no | no | yes | yes |
| course (own course) | yes | no | yes | yes |
| soft-deleted | no | no | no | yes |

Evidence: the policy branches at
`supabase/migrations/20260101001900_global_teacher_visibility.sql:56-86`
(creator `:57`, participants `:58-62`, teacher `:63-67`, student enrollment
`:68-85`, soft-delete rule `:55`); student visibility unchanged per the
migration header `:14-16`.

## 17.4 Why personal activities are excluded

Personal-scope activities — a student's private planner entries — are invisible
to teachers, exactly as they are invisible to every other student. The
migration's header states the rule: "Personal-scope rows of OTHER users stay
private from everyone but their creator (and participants) — teachers
included" (`supabase/migrations/20260101001900_global_teacher_visibility.sql:16-19`).
The teacher branch of both the policy and the helper requires
`scope in ('section', 'course')` (`:63-67`, `:110-114`), so a personal row
never matches it.

This is a privacy boundary, not an oversight. A student recording "finish my
thesis draft" as a personal activity is writing to a private planner; the
university-wide calendar shows institutional workload, not named personal
histories. The dashboard states this on-screen in the Data coverage card:
"Teachers see section-scoped records across every campus and program. Personal
student activities remain private by design." (`WebView/app.js:1426-1427`).

## 17.5 What "recorded workload" means

Everything on the teacher calendar is a row somebody actually entered, and its
provenance badge says who or what: `Classroom-imported` (a student's sync
wrote it via the Edge Function path), `Student-reported` (a student reported
a face-to-face activity from the Android app, published instantly with no
approval queue), or `Teacher-confirmed` (a teacher-originated row)
(`WebView/app.js:54-59`; FACTBASE §8). "Recorded workload" is therefore the
union of what students imported, what students reported, and what teachers
recorded — nothing else. There is no scraping of the university's official
systems and no inference: Google Classroom is the only external source, and it
is read-only import (FACTBASE §1, §11).

The practical value for a teacher is the ability to identify deadlines that
are already recorded across sections — before adding another one. Filtering
to a program and year shows every recorded quiz, exam, project and assignment
for that cohort in the visible month, with student-reported items marked by
their dashed outline and badge (`WebView/app.js:1289`, `:1591`). A teacher who
sees a collision can act in the real world (move their own deadline at the
source, talk to the other teacher); the dashboard's only in-system write is
the category correction of Chapter 18.

A concrete walkthrough makes the mechanism tangible. Suppose BSCS second-year
students imported a Google Classroom coursework item "Machine Project 3"
(due the 14th) and one student reported a face-to-face quiz announcement
("Lab quiz — sorting algorithms", due the 16th) from the Android app. Both
rows land in `activities` as section-scoped rows of BSCS 2-A — the import
with verification status `imported`, the report with `student-reported`,
published instantly by migration
`supabase/migrations/20260101001500_student_self_publish.sql:4-10`. A teacher
who has never taught BSCS 2-A signs in, picks that program and year in the
filter bar, and both entries appear in the day boxes with their provenance
badges — because the teacher branch of `activities_select` matched on role
and scope alone. Had the same student also recorded "draft the project
writeup" as a personal planner entry, that row would not appear for the
teacher, or for any classmate: personal scope never enters the read matrix's
teacher column.

## 17.6 The honesty boundary: recorded is not complete

> WARNING: The system displays RECORDED information only. It does NOT
> guarantee that all real-world university activities have been entered.

This is the single most important caveat when presenting the dashboard, and it
is structural, not fixable by polish. Coverage depends entirely on students
importing Classroom coursework, students reporting face-to-face activities,
and teachers recording their own — if nobody records an announcement made at
a whiteboard, it is not on the calendar (FACTBASE §12, §16). Freshness has the
same shape: a Classroom deadline change is not reflected until the next
successful student sync, because all sync is client-triggered — there is no
push and no Pub/Sub (FACTBASE §11). An empty week on the dashboard means "no
recorded activity", which is different from "no activity".

## 17.7 Workload analytics are PLANNED, not built

The dashboard today has no workload summaries, no aggregate analytics, and no
proposed-deadline preview. This is a verified absence, not an assumption: the
fact base records zero matches for those features in `WebView/app.js`
(FACTBASE §12 "Absent (verified 0 matches)"), and a read of the full file
confirms it — the only aggregation in the dashboard is the filter bar's count
line ("N of M sections · K scheduled in <Month>",
`WebView/app.js:1209`) and the per-card report count (`:1382`).

The database is one step ahead of the client. Migration
`supabase/migrations/20260101000800_phase_completion.sql:372-388` defines the
view `section_workload_daily` (security_invoker, so RLS stays active for the
querying teacher): per section, per due date, an `activity_count` and a
`total_effort_minutes` rollup of non-deleted, section-scoped activities
(phase comment at `:366-371`). No client consumes it — not the dashboard, not
the Android app. Teacher workload summaries and the proposed-deadline preview
are roadmap items (M3.2, "workload summaries + proposed-deadline preview",
FACTBASE §18), correctly labeled PLANNED. A claim that Student Codex
"analyzes student workload" would be false; the accurate claim is that it
records and displays the raw material such analysis would use.

## 17.8 Limitations and defense answer

Limitations, stated plainly. University-wide visibility is read-only breadth:
a teacher sees other sections' activities but cannot correct anything outside
the sections they teach (Chapter 18). Personal activities are invisible by
design, so a teacher's picture of a *student's* total load is necessarily
partial — it is the institutional picture, not the personal one. Recorded is
not complete, and recorded is not fresh (sync is client-triggered). The
500-row-per-month query cap (`WebView/app.js:1663`) is generous for current
data volumes but is a bound. And analytics remain PLANNED: the
`section_workload_daily` view exists at the database layer with no consumer.

Defense answer: "University-wide visibility is one RLS clause — teachers read
all non-personal activities, no enrollment needed — behind the same filters a
student's enrollment already obeys. It is deliberately honest: every entry is
labeled with its origin, personal planner entries stay private even from
teachers, and we say plainly that the calendar shows what was recorded, not
what exists. Aggregate analytics are on the roadmap, and we do not claim
them."

---


# Chapter 18 — Activity Category Correction

## 18.1 What the categories are

Student Codex tracks every activity under exactly six categories. The
dashboard defines them as a constant array with display metadata
(`WebView/app.js:45-53`):

```text
assignment    -> "Assignment"    (clipboard-list icon)
quiz          -> "Quiz"          (help-circle icon)
exam          -> "Exam"          (calendar-check icon)
project       -> "Project"       (briefcase icon)
announcement  -> "Announcement"  (megaphone icon)
other         -> "Activity"      (file-text icon)
```

The same six values are the database contract. Migration 0023's header names
them "the six Student Codex tracking categories (the same list the app and the
teacher dashboard filter on): assignment, quiz, exam, project, announcement,
other ('Activity' in the UI)"
(`supabase/migrations/20260101002300_activity_category_tracking.sql:4-7`), and
its `suggest_activity_category` classifier can only ever return those values
(`:55-71`). This set was verified against all three sources — the dashboard's
`ACTIVITY_TYPES`/`TYPE_META`, the migration header, and the classifier's CASE
branches — and they agree. The category column is `activities.activity_type`;
"tracking category" is the migration's term for it, distinguishing it from the
raw provider type stored separately (Section 18.5).

The category set is not just stored — it drives the dashboard's visual
language. Each category owns a chip color class (`chip-assignment`,
`chip-quiz`, and so on, applied wherever a chip renders,
`WebView/app.js:1289`), an icon (`TYPE_META`, `:46-53`), and a toggle in the
calendar's interactive legend (`:1322-1327`). The legend's category filters
match on the same `activity_type` values (`matchesCategoryFilters`,
`:860-861`), so a correction is instantly reflected in filtering as well as
rendering: correct a miscategorized entry from Assignment to Exam and it
moves chips, colors, and filter behavior in one write.

Why categories need correcting at all: Google Classroom coursework arrives
with a `workType` whose vocabulary does not match this six-way split, and the
import classifier is deliberately conservative — it only overrides the
work-type mapping when the *title* clearly names a project, exam or quiz
deliverable, and unclear titles keep the fallback rather than defaulting to
assignment (`:9-15`, `:76-77`). A human teacher looking at "Case Study 2"
knows things a title-token regex cannot. The correction flow exists
to let that judgment win, permanently.

## 18.2 How a teacher corrects a category

The picker lives in the full-content activity sheet (Chapter 16).
`categoryRowHtml` (`WebView/app.js:1531-1556`) renders a six-button radio
group labeled "Category", with the current category checked, a small
"teacher-corrected" marker when the row is already locked
(`WebView/app.js:1545`), and a hint: "Corrections save immediately and are
preserved on future Google Classroom syncs." (`WebView/app.js:1555`). The
row is rendered only when the signed-in teacher is enrolled as teacher on the
activity's own section or course — `canCorrect` checks the `teacherSectionIds`
/ `teacherCourseIds` sets that `fetchBundle` built from the `enrollments`
table (`WebView/app.js:1539-1542`; set construction at `:1779-1786`). A
teacher browsing a section they do not teach sees the sheet without the
picker at all: the offer itself is enrollment-scoped, not just the write.

Pressing a category button fires the `set-category` action
(`WebView/app.js:2189-2241`). The handler first guards against no-ops: it
ignores repeat clicks while a correction is in flight, ignores the category
that is already selected, and ignores any value outside `ACTIVITY_TYPES`
(`:2190-2194`). It then disables every option button (so a double-click
cannot race the PATCH) and issues the dashboard's single write:

```javascript
const { data, error } = await sb.from('activities')
  .update({ activity_type: catType, category_locked: true })
  .eq('id', catId)
  .select('id, activity_type, category_locked');
```

Evidence: `WebView/app.js:2200-2203`. The update writes exactly two columns —
`activity_type` and `category_locked` — and asks for the row back. On
success, the client updates the in-memory activity and the month cache, so
the calendar chip re-colors without a refetch (`:2207-2214`), repaints the
picker row, and synchronizes the sheet header's first segment (the category
label) with the correction (`:2219-2229`). A toast confirms: "Category
updated — Now tracked as <Label>. Future Classroom syncs keep it."
(`:2215-2218`).

## 18.3 What happens internally: RLS and the guard

The PATCH succeeds or fails server-side, on two layers. The first layer is the
`activities_update` RLS policy (migration
`supabase/migrations/20260101000200_activities.sql:389-402`): an
authenticated user may update a row only if it is their own personal row, or
they are the section's teacher (`is_section_teacher`), or the course's
teacher (`is_course_teacher`), or an admin. A teacher correcting a category
in a section they do not teach matches no branch, so the UPDATE affects zero
rows; PostgREST returns an empty result; the dashboard's `!updated` check
turns that into the refusal the teacher actually reads — "You can only
correct categories for sections you teach." (`WebView/app.js:2205-2206`).
(Students have their own update path: the reporter can edit or withdraw their
own student-reported section rows under
`activities_update_own_student_report`,
`supabase/migrations/20260101001500_student_self_publish.sql:114-127`, and
owners can edit their own personal rows under the policy's first branch.)

The second layer is the `guard_activity_update` trigger
(`supabase/migrations/20260101002300_activity_category_tracking.sql:182-211`).
Three rules matter here. `created_by_user_id` is immutable — any attempt to
reassign an activity's owner raises, for everyone (`:187-189`). A manual
category correction locks the tracking category: on the `category_locked`
false-to-true transition the trigger stamps `category_locked_by` with
`auth.uid()`, so the audit trail records *who* overrode the classifier
(`:190-194`); service-context writes (caller null, i.e. the import RPC) pass
through untouched (`:195-197`). And a `verification_status` transition *into*
`teacher-confirmed` or `imported` requires a teacher of that section/course or
an admin (`:198-209`) — a correcting teacher cannot smuggle a status change
into a category fix. One further PostgreSQL subtlety, documented in migration
0019's own notes: for UPDATE, the SELECT policy's USING applies as a WITH
CHECK on the new row, so an updated row must remain visible after the change
(`supabase/migrations/20260101001900_global_teacher_visibility.sql:50-54`).
The full policy inventory is Chapter 22's subject.

## 18.4 How the correction survives Classroom re-imports

This is the reason `category_locked` exists. Classroom sync is repeatable —
multiple students in the same course sync the same coursework item, and every
sync lands in `upsert_activity_from_source`, the trusted import RPC, which
upserts by `source_key` and *refreshes* title, description, due date, effort
and scope on every re-import
(`supabase/migrations/20260101002300_activity_category_tracking.sql:113-134`).
Without protection, the next sync would reclassify the row and quietly undo
the teacher's correction. The protection is one CASE branch in that UPDATE:

```sql
activity_type = case
  when a.category_locked then a.activity_type
  else public.suggest_activity_category(p_title, p_activity_type)
end,
```

Evidence: `supabase/migrations/20260101002300_activity_category_tracking.sql:121-127`.
A locked category survives every later sync; an unlocked one keeps following
the classifier. Content still refreshes either way — only the tracking
category is frozen.

Two supporting facts complete the design. First, the raw Google Classroom
resource type is never overwritten: it lives untouched in
`activity_sources.source_meta->workType`, because "the original provider data
never changes; only the tracking category moves" (`:20-22`; the re-import
updates `source_meta` wholesale at `:136-139`, carrying the fresh provider
value). Second, the RPC itself is service-only — it raises if any client
session calls it (`if auth.uid() is not null then raise exception
'upsert_activity_from_source is a service-only operation'`, `:106-108`), and
it is granted to `service_role` only (`:171-176`), so the lock logic cannot
be bypassed from a browser. Migration 0023 also ran a one-time, idempotent
reclassification of existing rows whose titles clearly named a better
category (non-personal, non-deleted, unlocked rows only; re-running is a
no-op) (`:214-236`) — teachers can always re-correct anything it moved.

## 18.5 The classifier, for completeness

`suggest_activity_category(p_title, p_fallback)` is a pure, immutable,
table-free SQL function (`:55-71`). Its priority order is deliberate:
PROJECT beats EXAM so "Midterm Project" and "Final Project" stay projects;
EXAM beats QUIZ so "Exam Review Quiz" stays a quiz only when no exam token is
present; announcements are a different Classroom resource entirely and are
never reclassified by coursework rules (`:49-53`). Word-boundary regexes
match PROJECTS/CAPSTONE/MACHINE PROBLEM variants, EXAMS/MIDTERMS/FINALS/
PRELIMS variants, and QUIZZES (`:61-66`); a valid fallback passes through
(`:67-68`); anything else becomes `other` (`:69`). It is granted to
`service_role` only (`:73-74`). This is deterministic title matching — not
AI — and it is the same classifier the Android import path relies on
(FACTBASE §11).

## 18.6 Restrictions: what a teacher cannot do

The honest scope statement has three parts. First, corrections are offered
and permitted only for sections (or courses) the teacher is enrolled to
teach — enforced twice, client-side by the picker's visibility
(`WebView/app.js:1539-1542`) and server-side by the `activities_update`
policy, whose zero-row result becomes the refusal message
(`WebView/app.js:2205-2206`). Second, the category is the *only* field the
dashboard writes: `app.js` contains exactly one `.update` call in the entire
file — the two-column PATCH above (`WebView/app.js:2200-2203`) — and no
control anywhere creates, deletes, re-titles, re-dates, or re-assigns an
activity. Teachers who want a deadline moved must change it at the source
(Google Classroom, or the announcement itself); Student Codex deliberately
offers no deadline editing to teachers, and this documentation does not
claim any. The owner column is immutable outright for every caller
(`supabase/migrations/20260101002300_activity_category_tracking.sql:187-189`).
Third, students edit only their own rows — personal entries and their own
student-reported section entries (FACTBASE §8; policy references in Section
18.3) — and imported rows are read-only in the Android app.

## 18.7 Example: correcting a misclassified import

A worked example ties the layers together. A Classroom coursework item titled
"Machine Problem 4 — Linked Lists" is imported by a student; Classroom calls
it an assignment-type work, and the title's "MACHINE PROBLEM" token is on the
project regex, so the classifier records it as `project`
(`supabase/migrations/20260101002300_activity_category_tracking.sql:61-62`).
Suppose instead the item was titled "MP4" — no token matches, the fallback
passes through, and the row lands as `assignment`. The section's teacher
opens the entry from the day box, sees the category is wrong, and presses
Project in the sheet's picker.

What follows, in order: the dashboard PATCHes `activity_type='project'` and
`category_locked=true` for that row (`WebView/app.js:2200-2203`). RLS checks
`activities_update` — this teacher is enrolled on the section, so the row
passes (`supabase/migrations/20260101000200_activities.sql:389-402`). The
`guard_activity_update` trigger sees the false-to-true transition of
`category_locked` and stamps `category_locked_by` with the teacher's
`auth.uid()` (`supabase/migrations/20260101002300_activity_category_tracking.sql:192-194`).
The updated row returns; the client repaints the chip, the picker, and the
sheet header, and shows the confirmation toast (`WebView/app.js:2207-2229`).
Next week another student in the same course runs a Classroom sync: the same
`source_key` upsert takes the UPDATE path, refreshes title, description, due
date, effort and scope — and leaves `activity_type` untouched because
`a.category_locked` is true (`:121-127`). The raw Classroom workType is
still sitting in `source_meta`, unchanged (`:20-22`). If the teacher instead
had not been enrolled on that section, the PATCH would have matched zero
rows and the toast would have read "Could not update the category — You can
only correct categories for sections you teach."
(`WebView/app.js:2205-2206`, `:2230-2235`).

## 18.8 Limitations and defense answer

Limitations. The correction is a label fix, not a data fix: it changes how an
entry is tracked and filtered, never its content, due date, or ownership. The
teacher-corrected marker (`category_locked`) records who corrected
(`category_locked_by`) but the dashboard shows only that a correction exists,
not its history — there is no audit UI. A correction can be made and re-made
freely within the six values, but a locked row stays locked; there is no
dashboard control to unlock it back to classifier control (the lock simply
keeps whatever category is current). And the picker appears only in the
activity sheet, so a teacher must open an entry to correct it — there is no
bulk correction.

Defense answer: "Category correction is the dashboard's single write, and it
is intentionally narrow: two columns, one RPC-free PATCH, restricted by RLS
to sections the teacher actually teaches, with a trigger stamping who
corrected. The interesting engineering is persistence — a teacher's
correction sets `category_locked`, and the Classroom re-import path
explicitly preserves a locked `activity_type` while still refreshing title,
description and due date, with the raw Classroom workType kept untouched in
`source_meta`. Machine classification serves until a human disagrees, and the
human wins from then on."

---


# Chapter 19 — Teacher Dashboard Security

## 19.1 The authorization ladder

The dashboard's security story is easiest to defend as a ladder with four
separate rungs, each answering a different question. No rung implies the one
below it, and each is enforced somewhere the browser cannot touch.

| Rung | Question it answers | Enforced by | What it unlocks |
|---|---|---|---|
| Authentication | Who is this account? | Supabase Auth sign-in | A session JWT — nothing else |
| Teacher role | Is this account a teacher? | `user_roles`, gated RPCs only | University-wide read, non-personal rows |
| Enrollment | Teaches this section? | `enrollments` rows | Category corrections, teacher-confirmed status |
| RLS per-row | May this request touch this row? | Row-level security policies | The actual read/write set |

The separation is visible in the code. Signing in successfully is only
authentication: `signIn` calls `signInWithPassword` and then `handleSession`
independently reads `user_roles` to decide whether the account is a teacher at
all — a signed-in student lands on the "no teacher access" screen
(`WebView/app.js:1970-1979`, `:1863-1872`, `:816-853`). The teacher role
itself is never set client-side: it enters `user_roles` only through the
`teacher_signup_global` / `teacher_signup_multi` RPCs, whose bodies are
SECURITY DEFINER and whose grants exclude anon
(`supabase/migrations/20260101001900_global_teacher_visibility.sql:143-167`
and `:166-167`; redefinition with the domain gate in
`supabase/migrations/20260101003100_teacher_school_email_domain.sql:222-225`).
Enrollment is a third thing again: `fetchBundle` separately computes the
sections and courses the account is enrolled to *teach*, and only those gate
the correction picker (`WebView/app.js:1764-1786`, `:1539-1542`). The client
versions of all these checks are user experience, not enforcement — the same
questions are answered server-side by RLS on every request, which is why a
tampered client cannot talk its way past them.

### The ladder in one request

One request exercises all four rungs. A teacher presses Project in a category
picker (Chapter 18). The PATCH leaves the browser carrying the teacher's
session JWT; the publishable key in the request identifies the project and
nothing more. Rung one, authentication: Supabase validates the JWT and resolves
it to a user id. Rung two, role: the update passes only because RLS and the
guard resolve that account's `user_roles` — a student sending the byte-for-byte
same request would fail the rungs below. Rung three, enrollment: the
`activities_update` policy checks `is_section_teacher` against the row's own
section, so the same teacher PATCHing an entry in a section they do not teach
matches zero rows (`supabase/migrations/20260101000200_activities.sql:389-402`).
Rung four, per-row semantics: `guard_activity_update` stamps the corrector and
enforces immutability on the owner column
(`supabase/migrations/20260101002300_activity_category_tracking.sql:187-209`).
The dashboard's UI offered the button only because it had asked the same
questions earlier (`WebView/app.js:1539-1542`) — but the server never trusted
those answers.

## 19.2 The publishable-key model

The dashboard ships the project's publishable key in plain text
(`WebView/app.js:26-27`) and says so in its header: it "talks to hosted
Supabase with the PUBLISHABLE key only", every read runs through the signed-in
teacher's session, and "row-level security decides what is visible"
(`WebView/app.js:14-19`). The client is created with session persistence and
token auto-refresh (`WebView/app.js:239-241`), and the on-screen footer
repeats the model on every page ("publishable key only, never a service key",
`:393-397`). The service-role key exists only inside Edge Function server
contexts and never in any client (FACTBASE §15).

This is the standard Supabase architecture, and the honest framing matters:
the publishable key is *public by design*, so the dashboard must assume an
attacker holds it. Nothing in `WebView/` is secret except the teacher's own
session token, which supabase-js stores and refreshes for the signed-in user.
Every protection consequently lives server-side — RLS policies per table,
EXECUTE privileges per RPC, and guard triggers per mutation. A judge asking
"you put your key in a JavaScript file?" gets the answer: yes, deliberately;
the key identifies the project, it does not authorize anything; the session
JWT authorizes, and RLS decides what that session may touch.

## 19.3 University-wide read access, decided by RLS

What a teacher may read is one clause of the `activities_select` policy:
`has_role('teacher') and scope in ('section', 'course')` — no enrollment
needed, personal-scope rows excluded, soft-deleted rows hidden
(`supabase/migrations/20260101001900_global_teacher_visibility.sql:47-87`).
The identical teacher branch was added to `activity_visible_to_user()` so the
helper stays the single source of truth for the participants/reports/sources
policies (`:95-135`), with a `viewer = auth.uid()` guard so one caller's role
can never be borrowed for another user id (`:110-114`). Chapter 17 walks the
visibility matrix; Chapter 22 catalogs the full policy set. The security
point for this chapter is that breadth-of-read is a *policy decision*
recorded in a migration, not a client-side filter that could be patched out —
the same PostgREST request from a student session gets student visibility,
whatever JavaScript made the request.

## 19.4 Teacher-confirmed operations and correction permissions

The write side is narrower than the read side, and deliberately so. The
`activities_update` policy allows an update only for the owner of a personal
row, a teacher enrolled on the row's section or course, or an admin
(`supabase/migrations/20260101000200_activities.sql:389-402`) — this is the
server-side rule behind the taught-sections-only category correction of
Chapter 18, and a zero-row update is what produces the dashboard's refusal
message (`WebView/app.js:2205-2206`). On top of the policy, guard triggers
police semantics: `created_by_user_id` is immutable for everyone, and a
`verification_status` transition into `teacher-confirmed` or `imported`
requires a teacher of that section/course or an admin
(`supabase/migrations/20260101002300_activity_category_tracking.sql:187-209`;
the same rule for inserts, including the reserved `imported` status, at
`supabase/migrations/20260101001500_student_self_publish.sql:85-95`).

The dashboard itself performs no teacher-confirmed writes at all. Its single
`.update` call in 2,477 lines is the two-column category PATCH
(`WebView/app.js:2200-2203`); there is no activity creation, deletion, or
deadline editing anywhere in `WebView/app.js`. Teacher-confirmed rows exist in
the data model (the badge renders, `WebView/app.js:55`), but they are produced
by the database rules above — not by any dashboard control. In short: broad
read, one narrow write, status escalation impossible from this client.

## 19.5 The current competition/testing configuration, stated honestly

Three facts about teacher registration must be presented exactly as they are.

First, email confirmation is OFF. The project's auth configuration sets
`[auth.email] enable_confirmations = false` (`supabase/config.toml:223-230`),
so a sign-up receives a session immediately and no email is sent at all —
which also keeps the hosted mailer's 2-auth-emails-per-hour project-wide cap
(`[auth.rate_limit] email_sent = 2`, `supabase/config.toml:198-203`) out of
the sign-up path (FACTBASE §15). This is a testing configuration for the
competition, not a hardened production choice.

Second, the @parsu.edu.ph domain check is an eligibility gate, not proof of
mailbox ownership. The 0031 gate proves the address *looks like* school staff
email (case-insensitive exact suffix, read from `auth.users` via SECURITY
DEFINER so forged JWT claims are irrelevant,
`supabase/migrations/20260101003100_teacher_school_email_domain.sql:69-75`);
it does not prove the signer controls that inbox. Anyone who can register a
`@parsu.edu.ph`-looking address with the school's mail system — or subvert it
— passes. The earlier verification machinery remains as dormant fallback: the
dashboard still carries the full 0029/0030 click-to-confirm waiting card
(`WebView/app.js:452-702`) and `EMAIL_NOT_VERIFIED` compatibility branches
(`:2026-2034`, `:2061-2066`), which wake up only if confirmation is ever
switched back on.

### The dormant verification machinery, in one paragraph

If confirmation is ever re-enabled, sign-ups stop receiving a session and the
waiting card takes over: `beginEmailWait` parks the flow
(`WebView/app.js:566-577`), the emailed Confirm button is the entire proof
(no code is typed), `verifyContinue` signs back in with the password held in
memory only (`:646-672`, never persisted — the state field's comment at
`:338-344`), and a slow background watch re-attempts the sign-in every 90
seconds, capped at 25 attempts, so a teacher who never presses Continue still
lands on the dashboard after clicking the email (`:674-699`). A latch
(`verifyCompleting`, `:591-639`) keeps the three completion paths — Continue,
the watch, and a session arriving via the email button's redirect — from
double-running the role grant; the RPCs are idempotent anyway, belt and
suspenders (`:593-599`). Under the 0031 model none of this runs. One related
client-side detail is worth noting as defense in depth: the sign-up form also
rejects a curated blocklist of disposable email domains with its own message
(`WebView/app.js:462-492`) — redundant under the school-domain rule, but it
keeps throwaway addresses from ever reaching the account-creation call.

Third, deployment state: the hosted project has migrations through 0028
applied; 0029 through 0032 — including the 0031 domain gate and the 0032 RPC
revokes — exist locally, SQL-tested, and not yet pushed (FACTBASE §5, §13;
deployment is roadmap M2.1 with post-deploy verification M2.2). The
`WebView/README.md` notes section describes the 0031 gate as "live"; the
verified 2026-11-01 repo audit is the authority on what is actually hosted,
and it says hosted is at 0028. Until 0029–0032 are pushed, the server-side
domain gate is not in force on the hosted database, and the dashboard's own
client-side suffix check (`WebView/app.js:477-492`) is the only part of the
gate a hosted sign-up currently exercises. Production teacher identity
verification as a product decision is UNRESOLVED — roadmap M2.3 (FACTBASE
§15, §18). This chapter does not claim otherwise.

## 19.6 What a request-tampering attacker can and cannot do

Assume an attacker reads all of `WebView/`, holds the publishable key, and
sends hand-crafted PostgREST and RPC requests with a session JWT they
legitimately own (their own account, student or teacher). The summary table
first, then the evidence:

| Attacker goal | Result | Where enforced |
|---|---|---|
| Impersonate another user | Fails | Supabase-signed JWTs |
| Read others' personal activities | Fails | `activities_select` (0019) |
| Read soft-deleted rows | Fails | `activities_select` (`:55`) |
| Correct a category outside taught sections | Zero-row no-op | `activities_update` (0002) |
| Escalate an entry to `teacher-confirmed` | Fails | `guard_activity_update` (0023) |
| Call `upsert_activity_from_source` | Fails | service-role grant + raise (0023) |
| Self-grant teacher role via legacy `teacher_signup` | Post-0032: fails | 0032 revoke (F1) |
| Enroll victims via the import/enroll RPCs | Post-0032: fails | 0032 revokes (F2/F3) |
| Read the school registry | Succeeds | by design (anon-readable) |
| Self-service teacher sign-up (gated RPCs) | Succeeds if eligible | 0031 domain gate (see 19.5 on hosted state) |

What they CAN do: open the dashboard from disk (it is public static files);
read the registry tables (`campuses`, `programs`, `year_levels`,
`year_sections` — anon-readable by design, `WebView/app.js:2430-2442`); sign
up a normal account; read every activity their own role entitles them to; and
call the RPCs still granted to `authenticated` — `teacher_signup_global` and
`teacher_signup_multi`, which are self-service by deliberate product decision
(`granted_by` intentionally null,
`supabase/migrations/20260101001900_global_teacher_visibility.sql:157-159`),
where the 0031 domain gate is the eligibility check that answers them.

What they CANNOT do: forge another user's JWT (Supabase signs sessions); read
another user's personal activities or anyone's soft-deleted rows
(`activities_select`, migration 0019); update any activity in a section they
do not teach — the policy filters the row set to zero and the mutation is a
no-op (`supabase/migrations/20260101000200_activities.sql:389-402`;
`WebView/app.js:2205-2206`); escalate an activity to `teacher-confirmed` or
`imported` without being that section's teacher (guard triggers, Section
19.4); or call `upsert_activity_from_source` at all — it is granted to
`service_role` only and raises outright when any client session calls it
(`supabase/migrations/20260101002300_activity_category_tracking.sql:106-108`,
`:171-176`). Client-side conveniences (the hidden picker, the disabled submit
button) are bypassable by definition; every rule above answers server-side.

> WARNING: One caveat must survive every telling: migration 0032 — the F1/F2/F3
> RPC revokes — is LOCALLY TESTED, NOT DEPLOYED to the hosted project. Until
> M2.1 pushes it, the hosted database still exposes the three revoked doors
> (legacy `teacher_signup`, `import_student_classroom_courses`,
> `enroll_student_courses`) to any authenticated caller. The findings, attack
> reproductions, and the pure-privilege fix are Chapter 27's subject; this
> chapter only cross-references them.

## 19.7 Session handling on the client

The client-side session handling is conventional and worth one paragraph of
its own because judges ask about it. The supabase-js client persists the
session and auto-refreshes the token (`WebView/app.js:239-241`); boot restores
it with `getSession` before anything renders (`:2444-2450`); and every auth
event flows through one handler that re-runs the role gate
(`onAuthStateChange`, `:2452-2473`). Sign-out — button or event — resets the
entire application state, including the cohort filters (so the next account
never inherits the previous teacher's view, `:1940-1966`) and the
password-reveal toggles, which re-hide on tab switch and sign-out as the safe
default (`:704-724`). The password eye toggle itself is a small security-adjacent
usability detail: its `mousedown` is swallowed so the caret never leaves the
field mid-typing (`:2290-2295`), and the demo fill button only writes the
demo constants into the form — it performs no sign-in on its own
(`:2101-2106`). None of this is the security boundary — it is hygiene around
the boundary described above.

## 19.8 Limitations and defense answer

Limitations, plainly. Identity assurance is weak by competition design:
confirmation is off, the domain suffix proves eligibility rather than
ownership, and production verification is UNRESOLVED (M2.3). The hosted
database is behind the local working tree by migrations 0029–0032, so the
strongest server-side gates in the codebase are not yet in force there
(M2.1/M2.2). The dashboard is a static page with no server of its own, so it
adds no server-side rate limiting or logging beyond what Supabase provides.
And the publishable key means the client must always be treated as fully
public — which the design does treat it as, by putting every rule server-side.

Defense answer: "The dashboard authenticates, then asks the database what the
account is: role from `user_roles`, breadth from an RLS clause, write
permission from taught-section policies, semantics from guard triggers — four
rungs, all server-side, behind a publishable key that is public by design.
For the competition we state our configuration honestly: email confirmation
is off, the school-domain check proves eligibility not ownership, and the
hardening migration is tested locally and queued for deployment — the audit
that found those gaps is part of the project, not something hidden."

---


# Chapter 20 — Database Architecture

Student Codex keeps exactly one database: the hosted Supabase project's
PostgreSQL instance, shared by the Android app and the teacher dashboard as the
single source of truth (FACTBASE §4; Chapter 3). The schema was built by 33
ordered SQL migrations numbered 0000 through 0032 under `supabase/migrations/`
(FACTBASE §5) — the hosted project has migrations through 0028 applied, while
0029–0032 exist as local files not yet pushed (FACTBASE §13; the deployment
story is Chapter 24's subject). This chapter is the schema reference itself:
the conventions every table follows, a complete reference for all 23 tables and
4 views, the foreign-key relationships that carry the security model, the
Storage bucket, and the entity-relationship overview rendered as Figure 4.

The companion chapters complete the picture: Chapter 21 documents the functions
and triggers that write across table boundaries, Chapter 22 catalogs the
row-level security policies summarized in the "Access Rules" column below, and
Chapter 24 explains how the schema reached its current shape. SQL excerpts in
this part are quoted verbatim from the migration source mirrors kept alongside
this documentation (for example `mig_000200_activities.sql`), which reproduce
the files under `supabase/migrations/`.

## 20.1 Schema conventions

Every table in the schema follows the same six conventions, declared once in
the header comment of the first migration and kept ever since (mirror
`mig_000000_core.sql:5-13`):

```sql
-- Conventions used across all Student Codex migrations:
--   * ids are uuid (gen_random_uuid(), core since PG13)
--   * timestamps are timestamptz, updated_at maintained by trigger
--   * every API-exposed table enables RLS with explicit policies
--   * policy helpers are SECURITY DEFINER with pinned empty search_path and
--     fully-qualified object references (plan §2 security rules)
--   * trusted data (roles, structure) is admin/service-managed: no client
--     insert/update/delete policies exist for it
```

Three of these conventions deserve explanation because they shape everything
that follows. First, primary keys are UUIDs generated by the database, so no
client ever mints an identifier and ids carry no ordering information —
ordering is always an explicit column such as `created_at` or `due_at`.
Second, `updated_at` is not written by clients at all: the
`set_updated_at()` trigger stamps it on every UPDATE (mirror
`mig_000000_core.sql:18-23`), which keeps client payloads small and audit
timings honest. Third, the split between "client-editable data" and "trusted
data" is a table-level design decision made before any policy is written:
`user_roles`, `enrollments`, and the registry tables have no client write
policies at all, so a modified client cannot grant itself a role or a
membership no matter what it sends (Chapter 25 walks the authorization model;
Chapter 19 shows the dashboard side).

Beyond those conventions, the schema leans on CHECK constraints rather than
application code for shape guarantees: text lengths are bounded everywhere
(`title` between 1 and 200, `content` at most 5000), enums are CHECK lists
rather than PostgreSQL enum types (`scope`, `activity_type`,
`verification_status`), and structural invariants are table constraints — for
example a `section`-scoped activity must carry a `section_id`. The community
tables enforce their limits the same way: `post_images.position` is bounded to
1–3 with a unique `(post_id, position)`, which makes a fourth image impossible
regardless of the client (mirror `mig_000300_community.sql:33-42`).

## 20.2 Complete table reference

The 23 tables fall into five domains. Each table below lists its purpose, the
columns that matter for understanding the system, its foreign-key
relationships, and a one-line summary of its access rules — the full policy
SQL for the important ones is quoted in Chapter 22. Columns are cited from the
migration mirrors; migration numbers indicate where a table or column was
introduced.

### 20.2.1 Identity and registry

| Table | Purpose | Important Columns | Relationships | Access Rules |
|---|---|---|---|---|
| `programs` | University and program pairs (official ParSU registry, seeded 0007) | `university_name`, `program_name`, unique pair, `campus_id` (NOT NULL since 0012) | `campus_id` → `campuses`; referenced by `profiles.program_id`, `courses.program_id` | SELECT to authenticated (0000) and anon (0007); no client write policies |
| `profiles` | App profile fields only; identity lives in `auth.users` | `id`, `username` (unique, `^[a-z0-9_]{3,24}$`), `first_name`, `last_name` (0006), `program_id`, `year_level` (1–8), `campus_id`, `year_section_id` (0007) | `id` → `auth.users` (cascade); `program_id` → `programs`; `campus_id` → `campuses`; `year_section_id` → `year_sections`; `year_level` → `year_levels.level` | SELECT to authenticated; UPDATE own row; no client INSERT/DELETE; `guard_profile_update` makes `id` and `username` immutable |
| `user_roles` | Trusted role grants | `user_id`, `role` (student/teacher/moderator/admin), `granted_by`, unique `(user_id, role)` | `user_id` → `auth.users` (cascade) | SELECT own rows or moderator/admin; no client write policies — grants only via gated RPCs and triggers |
| `campuses` | Campus lookup; seven campuses seeded in registry order (0007) | `name` (unique), `sort_order` | referenced by `programs.campus_id`, `profiles.campus_id` | SELECT to anon + authenticated; no client writes |
| `year_levels` | Year-level lookup (1st–5th, seeded 0007) | `level` (integer PK), `label` | referenced by `profiles.year_level` (FK added by 0007) | SELECT to anon + authenticated; no client writes |
| `year_sections` | Registrar block labels A–F and 1–3 (seeded 0007) | `name` (unique), `sort_order` | referenced by `profiles.year_section_id` | SELECT to anon + authenticated; no client writes |

The lookup tables are readable by anonymous requests on purpose: the sign-up
form needs campus, program, year, and block options before any account exists
(mirror `mig_000700_school_details.sql:13-16`). `profiles` deserves one extra
note: rows are never inserted by clients. The `handle_new_user` trigger on
`auth.users` creates the row at sign-up and fills it from sign-up metadata
(Chapter 21), which is why there is no INSERT policy at all (mirror
`mig_000000_core.sql:60-61`).

### 20.2.2 Academic structure

| Table | Purpose | Important Columns | Relationships | Access Rules |
|---|---|---|---|---|
| `courses` | The course catalog — rows students create by typing a code, or Classroom imports create | `code` (1–32), `title` (1–200), unique `(code, title)`, `program_id`, `external_course_id` (0022, partial-unique) | `program_id` → `programs`; referenced by `sections.course_id`, `activities.course_id` | SELECT to authenticated; no client writes — rows created/linked by RPCs in service context (Chapter 21) |
| `sections` | A class group of one course; the name encodes the cohort (`BSCS 2-A`) | `course_id`, `name` (1–80), `term`, unique `(course_id, name, coalesce(term,''))` | `course_id` → `courses` (cascade); referenced by `enrollments.section_id`, `activities.section_id` | SELECT to authenticated; created by the enrollment/import RPCs only |
| `enrollments` | The single membership fact: who is in which section, as what | `section_id`, `user_id`, `role` (`student` or `teacher`), `enrolled_at`, unique `(section_id, user_id)` | `section_id` → `sections` (cascade); `user_id` → `auth.users` (cascade) | SELECT own rows, own sections' rosters as teacher, admin; no client writes — trusted data |

`courses.external_course_id` is the one-to-one link to a Google Classroom
course, enforced unique where not null (mirror
`mig_002200_course_import.sql:40-43`). It is the exact-match tier that lets a
later sync skip all name heuristics (Chapter 12) and the anchor of the import
matching tiers (Chapter 13).

### 20.2.3 The activity domain

The six activity tables implement one principle stated in migration 0002's
header: "The canonical activity is what calendars/workload count — sources,
reports and sync attempts are evidence, never extra workload rows" (mirror
`mig_000200_activities.sql:6-9`). The canonical row is `activities`:

```sql
create table if not exists public.activities (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 200),
  description text,
  activity_type text not null default 'other'
    check (activity_type in ('assignment', 'quiz', 'exam', 'project', 'announcement', 'other')),
  course_id uuid references public.courses (id) on delete set null,
  section_id uuid references public.sections (id) on delete set null,
  due_at timestamptz,
  estimated_effort_minutes integer check (estimated_effort_minutes between 1 and 10080),
  scope text not null default 'personal'
    check (scope in ('personal', 'section', 'course')),
  verification_status text not null default 'student-reported'
    check (verification_status in ('imported', 'teacher-confirmed', 'student-reported', 'needs-review')),
  created_by_user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint activities_scope_section_requires_section
    check (scope <> 'section' or section_id is not null),
  constraint activities_scope_course_requires_course
    check (scope <> 'course' or course_id is not null)
);
```

(Evidence: migration 0002, mirror `mig_000200_activities.sql:18-40`; the
`category_locked boolean not null default false` and `category_locked_by uuid`
columns were appended by 0023, mirror `mig_002300_category.sql:35-39`.)

| Table | Purpose | Important Columns | Relationships | Access Rules |
|---|---|---|---|---|
| `activities` | The canonical workload row; the Beacon list and the teacher calendar both read it | `title`, `activity_type`, `scope` (personal/section/course), `due_at`, `estimated_effort_minutes`, `verification_status`, `created_by_user_id`, `deleted_at` (soft delete), `category_locked`/`category_locked_by` (0023) | `created_by_user_id` → `auth.users` (cascade, NOT NULL); `course_id`/`section_id` → set null; CHECKs tie each scope to its id | Visibility SELECT; self-publish INSERT (0015); UPDATE owner/teacher/admin plus reporter self-service; guards police verification status (Chapter 22) |
| `activity_sources` | Provenance evidence: where an activity came from | `provider` (google_classroom/student_manual/teacher_manual), `source_key`, `external_course_id`, `external_item_id`, `source_meta` jsonb | `activity_id` → `activities` (cascade); `reported_by_user_id` → `auth.users` | SELECT follows parent visibility (`activity_visible_to_user`); INSERT student-manual-own or teacher-manual; no UPDATE — evidence is immutable |
| `activity_reports` | Legacy pending→matched report queue, drained by 0015; kept as an audit table | `reporter_user_id`, `activity_id`, `title`, `status` (pending/matched/confirmed/rejected/needs_review/withdrawn) | `reporter_user_id` → `auth.users` (cascade); `activity_id` → `activities` (set null) | Reporter INSERT as `pending`; guarded UPDATE workflow; clients no longer write it — the app publishes activities directly (Chapter 8) |
| `activity_groups` | Optional grouping of section activities that represent the same assignment | `title`, `created_by_user_id` | referenced by `activity_group_members.group_id` | SELECT when any member activity is visible; no client write policies |
| `activity_group_members` | Group membership rows | `group_id`, `activity_id`, unique pair | `group_id` → `activity_groups` (cascade); `activity_id` → `activities` (cascade) | SELECT via `activity_visible_to_user`; no client writes |
| `activity_participants` | Explicit audience model: personal shares and targeted students | `activity_id`, `user_id`, unique pair | `activity_id` → `activities` (cascade); `user_id` → `auth.users` (cascade) | SELECT own rows or visible activity; INSERT/DELETE by the activity owner or a teacher of it |

The dedup backbone of the whole Classroom integration lives in
`activity_sources` as two partial unique indexes — the `source_key`
(`google_classroom:{courseId}:{courseWorkId}`, or the announcement variant)
makes repeated syncs of one Classroom item converge on one row (Chapter 14):

```sql
create unique index if not exists activity_sources_source_key_key
  on public.activity_sources (source_key) where source_key is not null;
create unique index if not exists activity_sources_provider_external_key
  on public.activity_sources (provider, external_course_id, external_item_id)
  where external_item_id is not null;
```

(Evidence: migration 0002, mirror `mig_000200_activities.sql:69-73`.)

### 20.2.4 The community domain

| Table | Purpose | Important Columns | Relationships | Access Rules |
|---|---|---|---|---|
| `posts` | Community posts; text up to 5000 chars, image-only posts allowed since 0008 | `author_id`, `content`, `is_anonymous`, `edited_at`, `deleted_at` | `author_id` → `auth.users` (cascade, NOT NULL) | SELECT live-or-own minus blocked authors; INSERT own; UPDATE own non-deleted; DELETE own or moderator/admin (Chapter 22) |
| `post_images` | Up to three images per post, enforced by the database | `post_id`, `storage_path`, `position` (1–3), unique `(post_id, position)` | `post_id` → `posts` (cascade) | SELECT when the parent post is visible; INSERT by the post author on a live post; no UPDATE — rows are replaced |
| `comments` | One table for comments and replies (self-referencing) | `post_id`, `parent_comment_id`, `author_id`, `content` (1–2000), `is_anonymous` | `post_id` → `posts` (cascade); `parent_comment_id` → `comments` (cascade); `author_id` → `auth.users` | SELECT visible post minus blocked; INSERT own with a visible post (guard validates parent and depth ≤5); UPDATE own; DELETE own or moderator |
| `post_likes` | One like per user per post | `post_id`, `user_id`, unique pair | `post_id` → `posts` (cascade); `user_id` → `auth.users` (cascade) | SELECT to authenticated; INSERT/DELETE own only |
| `comment_likes` | One like per user per comment | `comment_id`, `user_id`, unique pair | `comment_id` → `comments` (cascade); `user_id` → `auth.users` (cascade) | SELECT to authenticated; INSERT/DELETE own only |
| `user_blocks` | Blocklist whose effect is enforced through RLS itself | `blocker`, `blocked`, check `blocker <> blocked`, unique pair | both → `auth.users` (cascade) | SELECT/INSERT/DELETE own rows only |

The blocking design is worth calling out: there is no "hide blocked content"
flag anywhere. The `posts_select` and `comments_select` policies subtract the
blocked authors inside the policy, so a blocked user's content disappears for
the blocker at the database layer, not in the UI (mirror
`mig_000300_community.sql:203-214`; Chapter 22).

### 20.2.5 Moderation and the Classroom connection

| Table | Purpose | Important Columns | Relationships | Access Rules |
|---|---|---|---|---|
| `content_reports` | Report queue for moderator triage (five fixed reasons) | `reporter_id`, `target_type` (post/comment), `target_id`, `reason` (spam/harassment/off-topic/inappropriate/other), `status` (open/actioned/dismissed) | `reporter_id` → `auth.users` (cascade); `target_id` is polymorphic with no FK (deliberate) | Reporter INSERT as `open`; UPDATE moderator/admin only (guard); no DELETE; rate guard 10 per hour |
| `google_connections` | Per-user Classroom connection STATE registry — tokens never live here | `user_id` (PK), `google_email`, `status` (connected/disconnected/revoked/expired), `last_sync_at`, `last_sync_status`, `last_sync_error` | `user_id` → `auth.users` (PK, cascade) | SELECT own; UPDATE own disconnect-only (guard); INSERT/DELETE service-only — written by the Edge Functions |

`google_connections` is deliberately minimal. Its own header comment states
the rule twice: "REFRESH/ACCESS TOKENS ARE NEVER STORED HERE" — the table only
records connection state and the outcome of the last sync so the app can
render an honest connection card (mirror `mig_000800_phase.sql:112-119`;
Chapter 23 for the writers, Chapter 26 for the token policy).

## 20.3 The relationships that matter

### 20.3.1 Identity is anchored to auth.users

Every person-typed table points at `auth.users`, the Supabase-managed identity
table, rather than duplicating accounts. `profiles.id` is literally the auth
user id with `on delete cascade`, so an account deletion removes the profile,
and via cascades from there the person's posts, comments, likes, blocks,
reports, connections, and created activities (mirror
`mig_000000_core.sql:45-46`). The same anchor pattern repeats for
`user_roles.user_id`, `enrollments.user_id`, and the author columns. This is
what makes "delete my account" a single-cascade operation rather than a
cross-table scrub.

### 20.3.2 The registry chain

School structure forms one chain: `profiles` → `programs` → `campuses`, plus
the two lookups `year_levels` and `year_sections` referenced from `profiles`.
Migration 0012 tightened the chain by making `programs.campus_id` NOT NULL —
after that point "every program row IS campus-specific", which the teacher
signup RPCs rely on when a caller leaves campus empty and the program's own
campus is used as the fallback (mirror `mig_001300_teacher_signup.sql:72-77`;
FACTBASE §13). The chain is read-mostly: all writes are admin or service
context, so student-supplied school details can only ever reference registry
rows that already exist — the sign-up trigger validates and otherwise ignores
them (mirror `mig_000700_school_details.sql:203-236`).

### 20.3.3 Membership is one table

`enrollments` is the only place membership exists. A row says "this user, in
this section, with this role" (`student` or `teacher`), and everything else
derives from it: the RLS helpers `is_enrolled`, `is_section_teacher`, and
`is_course_teacher` (Chapter 21) read it inside every visibility policy
(Chapter 22), the teacher's correction rights resolve through it (Chapter 18),
and the workload view aggregates per section (Chapter 17). There is no
separate "teacher of course" table — `is_course_teacher` joins enrollments to
sections to check whether any section of that course has the caller as
teacher (mirror `mig_000100_academic.sql:69-79`).

### 20.3.4 Activities and their evidence

`activities` sits at the center of the schema with three kinds of edges. The
creator edge (`created_by_user_id`, NOT NULL, cascade) makes every row
attributable — even an imported row records which student's sync created it.
The scope edges (`course_id`, `section_id`, both set-null) place the row in
the academic structure without hard-coupling history to it: deleting a course
orphan's nothing, it just detaches. And the evidence edge is
`activity_sources.activity_id` (cascade, one row per provider item thanks to
the unique `source_key`), which is what turns a re-sync into an UPDATE of the
shared row instead of a duplicate (Chapter 14). The CHECK constraints quoted
above complete the design: a `section`-scoped row cannot exist without a
section, and a `course`-scoped row cannot exist without a course.

### 20.3.5 Deliberate non-relationships

Two absences are design decisions, not omissions. First,
`content_reports.target_id` has no foreign key on purpose: the target is
polymorphic (`post` or `comment`) and "target validity is checked by the
app/Edge layer; target_id is polymorphic by design" (mirror
`mig_000400_moderation.sql:68-69`). Second, nothing references
`activity_groups` from the client side — grouping is documented as a trusted,
service-side operation ("plan §9 Phase 5", mirror
`mig_000200_activities.sql:527`), so the tables exist and are RLS-readable
but no client write path leads to them.

## 20.4 Indexes and query paths

The schema's indexes match its two hot query paths: "what is due for this
viewer" and "render this feed". The Beacon's date-ordered reads are served by
a partial index that skips soft-deleted rows entirely:

```sql
create index if not exists activities_due_at_idx on public.activities (due_at)
  where deleted_at is null;
create index if not exists activities_section_idx on public.activities (section_id);
create index if not exists activities_course_idx on public.activities (course_id);
create index if not exists activities_creator_idx on public.activities (created_by_user_id);
```

(Evidence: migration 0002, mirror `mig_000200_activities.sql:42-46`.) The
section, course, and creator indexes exist because the RLS visibility policy
filters on exactly those columns for enrolled students and teachers, so the
policy's EXISTS subqueries probe an index rather than the heap. The community
feed is ordered newest-first, so `posts` carries `created_at desc` plus an
author index, and each child table indexes its parent (`post_images.post_id`,
`comments.post_id` and `parent_comment_id`, the two likes tables) because the
feed views count children per post (mirror `mig_000300_community.sql:30-82`).
Moderation's queue lookup is covered by `content_reports(status)` and the
polymorphic `(target_type, target_id)` pair (mirror
`mig_000400_moderation.sql:20-21`).

Uniqueness doubles as an index strategy throughout: `profiles.username` is a
partial unique index over non-null handles, `sections` is unique on
`(course_id, name, coalesce(term,''))`, `courses.external_course_id` is a
partial unique index, and the two `activity_sources` unique indexes from
§20.2.3 are both the dedup rule and the lookup path the sync RPC uses to find
an existing item by `source_key`. Advisory locks, not indexes, serialize
concurrent course creation — that mechanism belongs to Chapter 21.

## 20.5 Views

Four views sit on top of the tables, all created in migration 0008 (their
first, simpler forms date to 0003). Three serve the community feed and one
serves an analytics future:

- `feed_posts` — the public feed with `like_count`, `comment_count`,
  `image_count`, `liked_by_me`, and ordered `image_paths`, joined to profiles
  for the author display name.
- `feed_comments` — the comment thread view with the same shape.
- `my_posts` — the requesting author's own posts, anonymous ones included
  ("the author always sees their own history", mirror
  `mig_000800_phase.sql:308-311`).
- `section_workload_daily` — per section and day, `activity_count` and
  `total_effort_minutes` over live section-scoped activities. No client
  consumes it: the workload-summary feature is PLANNED (FACTBASE §12).

All four are `security_invoker` views, which means RLS still applies to the
selecting user — the view is not a privilege bypass. The anonymity handling
is the subtle part: the author id is nulled BEFORE the profiles join, so a
display name can never leak for an anonymous post:

```sql
create view public.feed_posts with (security_invoker = true) as
select
  p.id,
  p.content,
  p.is_anonymous,
  case when p.is_anonymous then null else p.author_id end as author_id,
  pr.first_name || ' ' || pr.last_name as author_name,
  p.created_at,
  p.edited_at,
  (select count(*) from public.post_likes pl where pl.post_id = p.id) as like_count,
  (select count(*) from public.comments c where c.post_id = p.id and c.deleted_at is null) as comment_count,
  (select count(*) from public.post_images pi where pi.post_id = p.id) as image_count,
  exists (
    select 1 from public.post_likes pl
    where pl.post_id = p.id and pl.user_id = auth.uid()
  ) as liked_by_me,
  (
    select coalesce(jsonb_agg(pi.storage_path order by pi.position), '[]'::jsonb)
    from public.post_images pi
    where pi.post_id = p.id
  ) as image_paths
from public.posts p
left join public.profiles pr
  on pr.id = case when p.is_anonymous then null else p.author_id end
where p.deleted_at is null;
```

(Evidence: migration 0008, mirror `mig_000800_phase.sql:282-306`; the same
null-before-join pattern in `feed_comments` at `:337-356`.)

## 20.6 The Storage bucket

Community images live in one Storage bucket, `community-images`, created
PRIVATE by migration 0005 — "never make private images public for
convenience" (mirror `mig_000500_storage.sql:9-11`). Image bytes live in
Storage; the `post_images` rows hold only object paths and metadata. Objects
follow the own-folder layout `{uid}/{postId}/{ts}.jpg` (FACTBASE §4), and the
four bucket policies grant authenticated reads plus own-folder writes, with
the folder prefix checked inside the policy so a modified client still cannot
write into someone else's folder. The policy SQL is quoted in Chapter 22;
the upload flow from the app side is Chapter 9's subject.

## 20.7 Figure 4 — Entity-relationship overview

**Figure 4 — Entity-relationship overview** (placeholder: the diagram
generator renders exactly the entities and edges described here.)

The diagram is a deliberately simplified overview of core entities, not the
full schema — with 23 tables, a complete ER drawing would be unreadable, so
the complete detail lives in the table reference above and the diagram keeps
only the entities a reviewer needs to hold in their head (the table-plus-
simplified-diagram pattern). The nodes are: `profiles` at the center,
`user_roles`, the registry chain `campuses` → `programs`, `enrollments`,
`sections`, `courses`, `activities`, `activity_sources`, `posts`,
`post_images`, `comments`, `post_likes`, `comment_likes`, `content_reports`,
and `google_connections`; `auth.users` is drawn as the external identity
anchor that every person-typed edge points to.

The edges, each labeled, are:

- `profiles` — `user_roles`: one-to-one in the simplified drawing (the schema
  key is unique `(user_id, role)`, so the pair is what is unique).
- `profiles` — `enrollments` — `sections` — `courses` — `programs` —
  `campuses`: the membership and registry chain; the enrollments edge carries
  the role attribute (`student`/`teacher`).
- `activities` — `profiles` (creator, NOT NULL); `activities` —
  `activity_sources` (one-to-one evidence, unique `source_key`);
  `activities` — `sections` (scope placement, alongside the weaker
  `activities` — `courses` scope edge).
- `posts` — `profiles` (author); `posts` — `post_images`;
  `posts` — `comments` with the self-referencing `parent_comment_id` loop
  drawn on `comments`; `post_likes`/`comment_likes` as small link tables
  between profiles and their targets.
- `content_reports` — `profiles` (reporter), with a dashed, unlabeled edge to
  posts/comments marking the polymorphic `target_id` (no FK).
- `google_connections` — `profiles` (one row per user; `user_id` is the
  primary key).

What the diagram omits, on purpose: the `activity_reports`,
`activity_groups`, `activity_group_members`, and `activity_participants`
tables (legacy audit, trusted grouping, and the participant audience model —
all present in the reference above), the `year_levels` and `year_sections`
lookups, and every policy annotation, which belongs to Chapter 22's subject.

## 20.8 What the schema does not enforce

An honest reading of the schema includes what it cannot promise. The database
stores what students and teachers record or import — recorded is not the same
as complete real-world coverage, and nothing in the schema claims otherwise
(FACTBASE §16). The comments table supports depth-5 nested replies, but the
app renders a flat thread: the feature is PARTIALLY IMPLEMENTED at the client
while BUILT & VERIFIED at the schema level (FACTBASE §3). The same gap appears
twice more in the community domain: `post_images` allows three images while
the app posts one, and `is_anonymous` columns, views, and guards fully
support anonymous posting while the app currently hard-wires the flag to
false (Chapter 9). Finally, the schema performs no title-similarity dedup for
manual entries — two students reporting the same face-to-face activity create
two section rows, and the only automatic dedup that exists is the
`source_key` identity for imported items (Chapter 14).

## 20.9 Defense answer

If a judge asks "show me your data model", the answer is: one shared
PostgreSQL schema of 23 tables under RLS, with identity anchored to
`auth.users`, membership centralized in one enrollments table, one canonical
`activities` table that both clients read, and provenance in a side table
whose unique `source_key` makes imported data converge instead of duplicate.
Every rule a client could otherwise fake — roles, membership, image limits,
block lists, soft deletes — is a database constraint or policy, not UI code
(Chapters 21 and 22 cover the mechanisms).

---


# Chapter 21 — Important Database Functions and Triggers

Chapter 20 described the tables; this chapter describes the code that lives
inside the database. Student Codex uses PostgreSQL functions and triggers
for three distinct jobs, and keeping the three apart is the key to reading
the schema. First, a handful of SECURITY DEFINER RPCs act as *trusted
writers*: operations that must insert or update rows the calling client
could never touch directly, such as granting a teacher role or importing a
Classroom course. Second, guard triggers act as a *second enforcement
layer* behind the RLS policies — policies decide which rows a request may
touch, guards decide whether the resulting row is honest (Chapter 22).
Third, small helper functions let policies read trusted tables without
recursive policy evaluation. The Android app makes zero direct RPC calls
(FACTBASE §4) — every function below is invoked either by a trigger, by the
teacher dashboard, or by an Edge Function with the service key (Chapter 23).

## 21.1 The function reference

The reference is grouped by job. "Caller" lists who actually invokes the
function today; "Security Context" states the EXECUTE posture after migration
0032 (the hardening migration; Chapter 24 and Chapter 27). Migration numbers
mark where each function was introduced or last redefined.

### 21.1.1 Trusted writer RPCs (the service door)

| Function / Trigger | Responsibility | Caller | Security Context | Important Behavior |
|---|---|---|---|---|
| `upsert_activity_from_source(...)` (0008, redefined 0023) | Import or refresh one Classroom item as the canonical activity | `classroom-sync` Edge Function with the service key | SECURITY DEFINER; EXECUTE granted to `service_role` only | Guard rejects any JWT caller; upsert keyed on `source_key`; a re-import UPDATEs the shared row; a locked category is preserved |
| `import_student_classroom_courses(p_user, p_courses)` (0022, redefined 0027) | Enroll a student in their picked Classroom courses, creating or linking course rows | `classroom-import` Edge Function with the service key | SECURITY DEFINER; service-context only after 0032 (F2) | Matching tiers: exact `external_course_id`, normalized name, fuzzy `course_text_matches`, then create; advisory locks; 32-course cap; idempotent; returns a summary jsonb |
| `enroll_student_courses(p_user, p_program, p_year, p_block_id, p_codes)` (0017, redefined 0018/0021/0027) | Course-code self-service enrollment at student sign-up | The two `auth.users` triggers, running as definer; service_role grant kept | SECURITY DEFINER; trigger/service only after 0032 (F3) | Exact-code tier, fuzzy tier, cohort-section creation, advisory locks, 32-code cap; returns a summary jsonb |

### 21.1.2 Teacher registration RPCs

| Function / Trigger | Responsibility | Caller | Security Context | Important Behavior |
|---|---|---|---|---|
| `teacher_signup(p_program, p_year_level, p_year_section, p_campus)` (0013) | Legacy single-group teacher self-service | None live — the dashboard stopped calling it in 0020 | SECURITY DEFINER; EXECUTE revoked from `authenticated` by 0032 (F1) | Superseded; the revocation closed a door that let any signed-in user self-grant the teacher role (Chapter 27) |
| `teacher_signup_multi(p_groups)` (0016, redefined 0028 and 0031) | Multi-class teacher sign-up, up to 12 class groups | Teacher dashboard, legacy activation path (`WebView/app.js:2058`) | SECURITY DEFINER; `authenticated` + 0031 domain gate | Validates every group against the registry; enrolls as teacher of matched cohort sections; idempotent |
| `teacher_signup_global()` (0019, redefined 0028 and 0031) | Role-only teacher onboarding — the current dashboard flow | Teacher dashboard (`WebView/app.js:616`, `:2024`) | SECURITY DEFINER; `authenticated` + 0031 domain gate | Grants the teacher role and nothing else: no profile alignment, no enrollments; visibility comes from the 0019 read policy |

### 21.1.3 Auth triggers

| Function / Trigger | Responsibility | Caller | Security Context | Important Behavior |
|---|---|---|---|---|
| `handle_new_user()` (0000, redefined 0006/0007) | Create and fill the profile row at sign-up; grant `user_roles`; enroll course codes | `on_auth_user_created` AFTER INSERT trigger on `auth.users` | SECURITY DEFINER; runs in the GoTrue service context as trigger definer | Reads `raw_user_meta_data`; validates school ids against the registry via `try_uuid`; derives and claims a username; role-grant and enrollment wiring from 0017/0018 (FACTBASE §7) |
| `handle_user_profile_sync()` (0006, redefined 0007) | Apply later metadata updates (the Google completion flow) | `on_auth_user_profile_sync` AFTER UPDATE trigger on `auth.users` | SECURITY DEFINER | Acts only when `profile_completed = 'true'`; idempotent; claims a username only while none is set |

### 21.1.4 RLS helper functions

| Function / Trigger | Responsibility | Caller | Security Context | Important Behavior |
|---|---|---|---|---|
| `has_role(target_role)` (0000) | Does the caller hold a role? | Policies on `user_roles`, `activities`, `posts`, `comments`, `content_reports`, `enrollments` | SECURITY DEFINER, STABLE, pinned search_path | Reads `user_roles` directly, bypassing its RLS — avoids recursive policy evaluation |
| `is_enrolled(target_section)` (0001) | Is the caller enrolled in a section (any role)? | `activities_select` and related policies | SECURITY DEFINER, STABLE | EXISTS over `enrollments` for `auth.uid()` |
| `is_section_teacher(target_section)` (0001) | Is the caller the teacher of a section? | Activity update/correction policies, enrollment rosters | SECURITY DEFINER, STABLE | `enrollments` row with `role = 'teacher'` |
| `is_course_teacher(target_course)` (0001) | Does the caller teach any section of a course? | Activity policies | SECURITY DEFINER, STABLE | Joins `enrollments` to `sections` on `course_id` |
| `activity_visible_to_user(activity, viewer)` (0002, redefined 0019) | Single source of truth for "who can see an activity" | Policies on `activity_sources`, `activity_participants`, `activity_group_members`, `activity_reports` | SECURITY DEFINER, STABLE | Own row, participant, teacher non-personal branch (0019), section enrollment, course enrollment; deliberately NOT used inside `activities_select` (§21.4.6) |

### 21.1.5 Classification and matching helpers

| Function / Trigger | Responsibility | Caller | Security Context | Important Behavior |
|---|---|---|---|---|
| `suggest_activity_category(p_title, p_fallback)` (0023) | Conservative title-token category classifier | `upsert_activity_from_source` (service) | IMMUTABLE, no table access; EXECUTE granted to `service_role` | Priority project > exam > quiz so "Midterm Project" stays a project; unclear titles keep the fallback; regex fixes in 0024–0026 |
| `course_text_matches(p_typed, p_code, p_title)` (0027) | Fuzzy course-text matcher | `enroll_student_courses`, `import_student_classroom_courses` | IMMUTABLE; `authenticated` + `service_role` grants | Token-subset comparison in both directions; tokens are alphanumeric runs ≥3 chars; digits and stop-words dropped (Chapter 13) |
| `cohort_section_name(p_program, p_year, p_block_id)` (0027) | The cohort section naming convention ("BSCS 2-B") | The two enrollment RPCs | STABLE; `authenticated` + `service_role` grants | Program short name (else full name, else `CLASS`) + year + block; the single source of the convention both sign-up paths create sections under |

### 21.1.6 Username helpers

| Function / Trigger | Responsibility | Caller | Security Context | Important Behavior |
|---|---|---|---|---|
| `derive_username(given, family)` (0006) | Fold first/last names into a handle | `claim_username` and the auth triggers | IMMUTABLE SQL | Lowercase, Latin-1 accents folded to ASCII, non-`[a-z0-9]` runs collapsed to one underscore, truncated to 24; NULL when no valid 3–24 char handle results |
| `claim_username(base)` (0006) | Claim a free username | Auth triggers | SECURITY DEFINER | Tries `base`, then `base_2`, `base_3`, … (shortening when the suffix would pass 24 chars), up to 20 attempts; NULL when none fits |
| `try_uuid(value)` (0007) | Safe UUID parse of client-supplied metadata | Auth triggers | IMMUTABLE | A malformed id becomes NULL instead of crashing the sign-up |

### 21.1.7 Guard triggers

| Function / Trigger | Responsibility | Caller | Security Context | Important Behavior |
|---|---|---|---|---|
| `guard_activity_insert` (0002, redefined 0015) | Origin honesty on activity insert | BEFORE INSERT on `activities` | SECURITY DEFINER | `imported` reserved for the sync service; `teacher-confirmed` requires a teacher of the section/course or an admin; a section `student-reported` row requires creator enrollment; raises P0001 |
| `guard_activity_update` (0002, redefined 0023) | Immutability and category-lock stamping | BEFORE UPDATE on `activities` | SECURITY DEFINER | `created_by_user_id` immutable; status escalation into `teacher-confirmed`/`imported` is teacher/admin only; stamps `category_locked_by` on the false→true transition |
| `guard_activity_source_insert` (0002) | Classroom sources are sync-only | BEFORE INSERT on `activity_sources` | SECURITY DEFINER | Raises when `provider = 'google_classroom'` and `auth.uid()` is not null |
| `guard_activity_report_update` (0002) | Legacy report workflow honesty | BEFORE UPDATE on `activity_reports` | SECURITY DEFINER | Reporter immutable; non-staff may only withdraw; closed reports locked; linking to an activity is staff-only |
| `guard_post_update` (0003) | Author and anonymity immutability | BEFORE UPDATE on `posts` | SECURITY DEFINER | `author_id` and `is_anonymous` immutable; a content change stamps `edited_at` |
| `guard_comment_insert` (0003) | Parent and depth validation | BEFORE INSERT on `comments` | SECURITY DEFINER | Parent must exist, belong to the same post, and not be deleted; reply depth limit of 5 |
| `guard_comment_update` (0003) | Linkage immutability | BEFORE UPDATE on `comments` | SECURITY DEFINER | Author, post, parent linkage, and anonymity immutable — re-parenting is impossible, so no cycle can form |
| `guard_content_report_update` (0004) | Triage is staff-only | BEFORE UPDATE on `content_reports` | SECURITY DEFINER | Reporter, target, reason, details, and status changes require moderator/admin |
| `guard_profile_update` (0000) | Profile identity immutability | BEFORE UPDATE on `profiles` | SECURITY DEFINER | `id` immutable; `username` immutable once set, lowercased and validated on write |
| `guard_google_connection_update` (0008) | The owner may only disconnect | BEFORE UPDATE on `google_connections` | SECURITY DEFINER | Service context writes anything; an owner may only set `status` to `disconnected` — sync details are service-managed |

### 21.1.8 Rate guards and utilities

| Function / Trigger | Responsibility | Caller | Security Context | Important Behavior |
|---|---|---|---|---|
| `guard_post_insert_rate` (0008) | Anti-spam: at most 8 posts per rolling 10 minutes | BEFORE INSERT on `posts` | SECURITY DEFINER | Counts the author's rows regardless of caller RLS context; the service context (no JWT) is exempt |
| `guard_comment_insert_rate` (0008) | At most 30 comments per rolling 10 minutes | BEFORE INSERT on `comments` | SECURITY DEFINER | Same shape as the post guard |
| `guard_content_report_insert_rate` (0008) | At most 10 reports per rolling hour | BEFORE INSERT on `content_reports` | SECURITY DEFINER | Same shape; rate limiting lives here because no Edge layer intermediates these writes |
| `set_updated_at()` (0000) | Keep `updated_at` current | BEFORE UPDATE on roughly twenty tables | Plain trigger function (not definer) | Stamps `now()` on every update; clients never send the column |

## 21.2 Why SECURITY DEFINER functions exist here

A SECURITY DEFINER function executes with the privileges of its owner rather
than the caller, and Student Codex needs exactly that power in a few narrow
places: some legitimate operations must write rows that the calling user's
own RLS context could never write. A signed-in teacher cannot INSERT into
`user_roles` — there is no client write policy on that table at all — yet
`teacher_signup_global()` must insert the teacher role for them. A student
cannot INSERT into `enrollments` or `courses`, yet their sign-up must create
course rows and enrollments. The resolution is the one this schema uses
everywhere: the write happens inside a SECURITY DEFINER function whose body
validates the request far more strictly than any policy could, and whose
EXECUTE grant is limited to the contexts that are allowed to reach it at all
(mirror `mig_001300_teacher_signup.sql:7-13` states the rationale in the
0013 header, and the pattern repeats in every later RPC).

The privilege is deliberately narrow, in three ways. The functions pin an
empty `search_path` and fully-qualify every object reference, closing the
search-path hijacking class of attacks — the convention is declared in
migration 0000 and repeated in every definition. The bodies validate their
inputs against the registry (a crafted payload cannot inject free text or
foreign ids, mirror `mig_001300_teacher_signup.sql:50-63`). And the guard
inside the service-only RPCs refuses JWT callers outright, so the definer
power is reachable only from the service key:

```sql
  if auth.uid() is not null then
    raise exception 'upsert_activity_from_source is a service-only operation';
  end if;
  if p_provider <> 'google_classroom' then
    raise exception 'this upsert path is for provider imports only';
  end if;
```

(Evidence: migration 0023, mirror `mig_002300_category.sql:106-111`; the same
guard has stood since the function's 0008 introduction, mirror
`mig_000800_phase.sql:209-214`.)

## 21.3 Who may execute privileged operations after 0032

Migration 0032 answered an audit finding (Chapter 27) by making the EXECUTE
posture explicit: three RPCs that were historically granted to
`authenticated` even though no live client needed that door lost the grant,
and nothing else changed. The whole migration is worth reading because it is
a pure privilege change — no function body was modified:

```sql
-- F1: legacy single-group teacher signup — no live caller; close the door.
revoke execute on function public.teacher_signup(uuid, integer, uuid, uuid)
  from authenticated;

-- F2: Classroom course import — Edge Function (service role) only.
revoke execute on function public.import_student_classroom_courses(uuid, jsonb)
  from authenticated;

-- F3: student course enrollment — auth.users triggers (definer) only.
revoke execute on function public.enroll_student_courses(uuid, uuid, integer, uuid, jsonb)
  from authenticated;

-- Legitimate service paths stay open (idempotent re-assertion of 0027's
-- grants so this migration fully documents the intended end state):
grant execute on function public.import_student_classroom_courses(uuid, jsonb)
  to service_role;
grant execute on function public.enroll_student_courses(uuid, uuid, integer, uuid, jsonb)
  to service_role;
```

(Evidence: migration 0032, mirror `mig_003200_hardening.sql:43-60`; the
creation-time `public`/`anon` revokes are re-asserted at `:63-68`.)

After 0032, exactly three kinds of caller can reach privileged operations.
First, the two Classroom RPCs are service-context only: an Edge Function
holding the service-role key invokes them after verifying the caller's
session JWT itself (Chapter 23) — the JWT check moved from the database
boundary to the function boundary, where it is actually performed. Second,
`enroll_student_courses` survives for its real callers, the two
`auth.users` triggers, because a trigger executes as its function's definer
(owner) regardless of grants — the 0032 header notes "the authenticated grant
was never needed by them" (mirror `mig_003200_hardening.sql:20-23`). Third,
teachers reach role grants only through `teacher_signup_global` and
`teacher_signup_multi`, whose authenticated grants and 0031 domain gates are
untouched by 0032. Local verification of exactly this matrix is the
`rpc_authorization_test.sql` run of 2026-10-30 (T01–T10, PASSED); the
migration is IMPLEMENTED — VERIFICATION INCOMPLETE overall because it is
tested locally and NOT deployed to the hosted project (FACTBASE §3, §15).

## 21.4 How the important ones work

### 21.4.1 guard_activity_insert — origin honesty

The RLS policy decides whether an insert is allowed for *this user*; the
guard then decides whether the row *tells the truth*. The 0015 redefinition
added the rule that makes student self-publishing honest: a section-scoped
`student-reported` row can only be created by an enrolled student of that
section, so teachers cannot file fake student reports and students cannot
publish into sections they do not belong to:

```sql
  if new.scope = 'section' and new.verification_status = 'student-reported'
     and not (
       public.has_role('admin')
       or exists (
         select 1 from public.enrollments e
         where e.section_id = new.section_id
           and e.user_id = caller
           and e.role = 'student'
       )
     ) then
    raise exception 'verification_status ''student-reported'' on a section activity requires the creator to be enrolled in that section';
  end if;
```

(Evidence: migration 0015, mirror `mig_001500_self_publish.sql:96-108`; the
reserved `imported` and teacher-confirmed rules sit directly above it at
`:85-95`.) A plpgsql `raise exception` surfaces as SQLSTATE P0001
(`raise_exception`), which is why the test suite's T08.1 — written to expect
42501 — reports a mismatch that predates 0032 and is unrelated to it
(FACTBASE §15).

### 21.4.2 upsert_activity_from_source — the atomic import

This is the function every Classroom sync call funnels through, and its
behavior is the dedup guarantee of Chapter 14: it looks up the
`source_key`, and either refreshes the existing canonical row and its
evidence or creates both for the first time, in one statement each, so a
retried or repeated sync converges instead of duplicating. The 0023
redefinition added the teacher-correction protection — when a category is
locked, the refresh keeps the stored category and only the classifier
output is skipped:

```sql
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
```

(Evidence: migration 0023, mirror `mig_002300_category.sql:121-134`; the
first-import branch with the classified category at `:147-158`.) The
`guard_activity_update` trigger stamps `category_locked_by` from
`auth.uid()` when a teacher flips the lock (Chapter 18), and because the
upsert runs with no JWT, the service's own writes never touch the stamp.

### 21.4.3 import_student_classroom_courses — tiers and locks

The import RPC resolves each picked Classroom course through ordered tiers —
exact `external_course_id` link, normalized name match, the 0027 fuzzy tier,
then creation under the Classroom name — and converges classmates onto the
same rows using advisory locks taken in a deterministic (upper-cased) order,
which also makes concurrent imports deadlock-free (Chapter 13 walks the
matching semantics):

```sql
    -- Serialize per Classroom course: everyone importing this exact
    -- Classroom course converges on ONE row (the partial unique index
    -- enforces it; the lock avoids the throw/catch churn).
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('gc-course:' || v_ext));
```

(Evidence: migration 0022, mirror `mig_002200_course_import.sql:111-115`; the
same pattern per section at `:193-194` and, in the 0027 body, mirror
`mig_002700_cohort.sql:389-397`.) The loop reads at most 32 courses
(`limit 32`, mirror `mig_002200_course_import.sql:94`), every write uses
`on conflict do nothing` or a caught `unique_violation` re-select, and the
return value is a summary jsonb (`enrolled`, `created`, `linked`,
`matched`, `invalid`, `sectionsCreated`) that the Edge Function passes
straight back to the app (Chapter 23).

### 21.4.4 enroll_student_courses — the sign-up enrollment engine

The student's typed course codes at sign-up are resolved by the third trusted
writer, whose 0027 body shares the import RPC's shape: exact-code tier
(case-insensitive, the student's own program preferred), the fuzzy
`course_text_matches` tier, creation as a last resort, the cohort section
resolved or created under `cohort_section_name`, per-code advisory locks, and
the same 32-entry cap. Its callers are the two auth triggers — the sign-up
metadata carries the course codes, and `handle_new_user` passes them in
(wiring introduced by 0017/0018; FACTBASE §7; the 0032 header confirms the
trigger pair as the only callers, mirror `mig_003200_hardening.sql:20-23`).
The F3 audit finding was precisely that this function trusted its `p_user`
argument while still being executable by `authenticated`; after 0032 the
trigger definer context is the only non-service path left (Chapter 27).

### 21.4.5 The teacher registration lineage

The three teacher RPCs tell the project's security story in miniature.
Migration 0013 opened self-service teacher sign-up with a single gate — a
signed-in session — and documented the product decision in its header
("teacher sign-up is open to any authenticated account in this deployment",
mirror `mig_001300_teacher_signup.sql:15-20`). Migration 0016 added the
multi-class variant with a 12-group cap. Migration 0019 added
`teacher_signup_global`, which grants the role and nothing else, because
university-wide reads no longer depend on enrollments. Migration 0028 added
an email-ownership proof (the JWT's `amr` claim must show an OTP or
magic-link session), 0029–0030 refined it, and 0031 replaced all of it with
the school-email domain gate that stands today in both active RPCs:

```sql
  if not exists (
    select 1 from auth.users u
    where u.id = v_uid
      and lower(u.email) like '%@parsu.edu.ph'
  ) then
    raise exception 'SCHOOL_EMAIL_REQUIRED: teacher access is for @parsu.edu.ph school email addresses - sign up with your school email';
  end if;
```

(Evidence: migration 0031, mirror `mig_003100_domain_gate.sql:69-75`; the
suffix match is case-insensitive and rejects subdomain look-alikes,
`:22-28`.) The honest caveat travels with it: the suffix proves eligibility,
not mailbox ownership, and production teacher identity verification remains
UNRESOLVED on the roadmap (FACTBASE §15; Chapter 19 §19.5). The 0013
function itself was never retrofitted with any of these gates — which is
exactly why 0032 revoked its authenticated grant instead (F1).

### 21.4.6 The RLS helpers and the recursion trap

The membership helpers exist because a policy on `activities` needs to read
`enrollments`, and a naive subquery would subject that read to the
`enrollments` policy, which itself calls helpers — PostgreSQL detects this
as infinite recursion and rejects the policy. The SECURITY DEFINER helpers
read the trusted tables with owner privileges, sidestepping their RLS
cleanly, and are themselves granted only to `authenticated` and
`service_role`:

```sql
create or replace function public.is_enrolled(target_section uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.enrollments e
    where e.section_id = target_section and e.user_id = auth.uid()
  )
$$;
```

(Evidence: migration 0001, mirror `mig_000100_academic.sql:51-57`.) One
further subtlety is documented in the schema itself:
`activity_visible_to_user` must NOT be called from `activities_select`,
because STABLE functions see the statement-start snapshot — a row inserted
by `INSERT ... RETURNING` (what PostgREST clients use) would be invisible to
the helper, and every client insert would be rejected. The policy therefore
expresses visibility with row-local columns and EXISTS subqueries on other
tables, and the helper is reserved for policies on *other* tables where the
referenced activity is already committed (mirror
`mig_000200_activities.sql:328-336`).

### 21.4.7 suggest_activity_category — the deterministic classifier

The classifier is pure, immutable SQL with no table access, and its whole
philosophy is conservatism: it only overrides the Classroom work-type
fallback when the title clearly names a deliverable, and its priority order
is chosen so compound titles resolve sensibly — PROJECT beats EXAM so
"MIDTERM PROJECT" stays a project, EXAM beats QUIZ so an "Exam Review Quiz"
keeps the quiz only when no exam token is present:

```sql
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
```

(Evidence: migration 0023, mirror `mig_002300_category.sql:55-71`.) It is
deterministic guidance, not AI — the same title always yields the same
category — and it classifies, it does not dedup (FACTBASE §8). The raw
Classroom `workType` survives untouched in
`activity_sources.source_meta` (mirror `mig_002300_category.sql:20-22`).

### 21.4.8 Username derivation and the auth triggers

The username pipeline runs entirely in the database so a profile row is
never left without its identity fields. `derive_username` folds the
collected names into a handle ("Juan Dela Cruz" → `juan_dela_cruz`),
`claim_username` appends `_2`, `_3`, … when the base is taken (giving up
after 20 attempts, leaving the handle claimable later in-app), and both are
called from the two auth triggers — `handle_new_user` for the email sign-up
path where the names arrive with the INSERT, and `handle_user_profile_sync`
for the Google flow where they arrive later via `updateUser` once the user
completes the in-app form (mirror `mig_000600_profile_names.sql:1-16`). Both
triggers tolerate a username race: on `unique_violation` they keep the
profile with names but without a handle rather than failing the sign-up
(mirror `mig_000600_profile_names.sql:102-109`). The 0007 redefinition added
the school-details columns and the registry validation that ignores
malformed or foreign ids (mirror `mig_000700_school_details.sql:208-272`);
Chapter 6 walks the flows from the app side.

### 21.4.9 The guard family and set_updated_at

The remaining guards share one shape: BEFORE row-level triggers, SECURITY
DEFINER so their internal reads are trusted, raising plain exceptions on
violation. The community guards make anonymity a one-way door —
`guard_post_update` and `guard_comment_update` refuse any change to
`author_id` or `is_anonymous`, because "switching a post from anonymous to
named would retroactively reveal history" (mirror
`mig_000300_community.sql:94-96`) — and the comment guards keep the reply
tree sound (parent exists, same post, not deleted, depth ≤5, linkage
immutable so no cycle can form). The report and connection guards confine
triage and sync-state writes to staff and service respectively. At the
bottom of the family sits the one function everything shares:

```sql
create or replace function public.set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;
```

(Evidence: migration 0000, mirror `mig_000000_core.sql:18-23`.) It is the
only frequently-used trigger function that is not SECURITY DEFINER — it
touches nothing but the row being updated, so it needs no privilege.

## 21.5 Limitations and the defense answer

The function layer has known limits worth stating. Rate guards throttle
per-user writes but nothing throttles a distributed abuse pattern, and the
database cannot see the Edge layer at all. The classifier is a heuristic —
unclear titles keep the fallback rather than guessing (mirror
`mig_002300_category.sql:77`) — and fuzzy matching deliberately requires a
significant token, so "GE 6"-style entries still create fresh courses
(mirror `mig_002700_cohort.sql:43-44`). Most importantly, the 0032 EXECUTE
posture is verified locally, not on the hosted project: hosted ACL probes on
2026-10-29/30 showed the three revoked RPCs still executable by
`authenticated` there, and closing that gap is roadmap item M2.1 (FACTBASE
§15, §18; Chapter 24).

The defense answer for this chapter: privileged writes in Student Codex do
not trust the client at all — they run as SECURITY DEFINER functions with
pinned search paths, registry-validated inputs, and an EXECUTE grant surface
that (after 0032) admits only the Edge Functions' service key, the auth
triggers' definer context, and the domain-gated teacher RPCs; the audit that
produced that posture and its local test evidence are Chapter 27's subject.

---


# Chapter 22 — Row Level Security

Row Level Security (RLS) is the layer that makes the whole architecture
defensible, so this chapter explains it from plain language down to the
actual policy SQL. The previous two chapters covered the tables (Chapter 20)
and the functions and triggers (Chapter 21); policies are the third pillar,
and they are what the database actually enforces on every request from both
clients. Chapter 19 already framed the dashboard's side of the model and
Chapter 26 the key inventory; this chapter is the systematic catalog of how
rows are protected, with the five most important policies quoted in full from
the migration sources.

## 22.1 What row-level security is, in plain language

Plain language first: with RLS enabled, a table no longer has a single
content. Every user who queries it sees *their own version of it* — the rows
their policy allows — and writes are checked the same way before they land.
The check is not code in the app; it is a predicate the database evaluates
per row, per request, after the database already knows who is asking. A
modified or malicious client can send any query it likes; it cannot send a
different identity, because identity comes from the session token the
database validates itself.

Technically, an RLS policy is a named rule attached to a table for one
operation (`for select`, `for insert`, `for update`, `for delete`) and
scoped to one or more database roles (`to authenticated`, `to anon`). SELECT
policies supply a `USING` expression that filters the rows a query may see;
INSERT and UPDATE policies supply a `WITH CHECK` expression that a new or
updated row must satisfy to be written. Several policies for the same
operation are OR-ed together — which is how Student Codex expresses "owner
OR participant OR enrolled student OR teacher" in one place. If no policy
matches, the default is deny: that is why tables with no write policies at
all (`user_roles`, `enrollments`, the registry tables) are client-read-only
by construction. The service role bypasses RLS entirely, a fact the schema
itself relies on and documents (mirror `mig_000000_core.sql:100-102`,
`mig_001900_global_visibility.sql:54`).

What happens internally is worth one paragraph because it explains two
design choices later. PostgREST validates the caller's JWT and publishes its
claims as `request.jwt.claims` before executing the query — the same
mechanism the local test harness simulates with a role switch plus claim
injection (mirror `test_rpc_authorization.sql:4-6`). Policies then read
`auth.uid()`, which resolves the `sub` claim. And for UPDATE, PostgreSQL
enforces the SELECT policy's `USING` as a `WITH CHECK` on the new row — the
updated row must remain visible — a behavior the migrations lean on for soft
deletes, as §22.8 explains.

## 22.2 Why Student Codex needs RLS as its boundary

Both clients talk to the database with the publishable key, which is public
by design (FACTBASE §15; Chapter 26). The Android app embeds it in the
supabase-kt client, the teacher dashboard ships it in a plain JavaScript
file, and the project treats "an attacker holds the publishable key" as the
starting assumption (Chapter 19 §19.2). There is no API server of our own in
between — requests go straight to PostgREST — so there is nowhere else to
put authorization. The database itself is therefore the policy enforcement
point: every rule that matters lives in a policy, a guard trigger, or a
CHECK constraint, and the clients' own checks are user experience, not
enforcement. This is also why the app's request surface can stay boring:
tables plus Edge Functions, zero direct RPC calls (FACTBASE §4), with the
privileged work hidden behind the function layer of Chapter 21.

## 22.3 Identity, roles, and ownership

Every policy in the schema begins from two questions the database answers on
its own: *who is asking*, and *whose row is this*. The first is
`auth.uid()`, resolved from the verified JWT — a client cannot forge it
because GoTrue signs the token and PostgREST verifies it before any policy
runs. The second is almost always a literal ownership comparison: a column
on the row equals `auth.uid()`. The helper that extends identity with
trusted role data is `has_role`, a SECURITY DEFINER function so the policy
can read `user_roles` without recursively evaluating that table's own policy
(Chapter 21 §21.4.6):

```sql
create or replace function public.has_role(target_role text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid() and ur.role = target_role
  )
$$;
```

(Evidence: migration 0000, mirror `mig_000000_core.sql:119-125`.)

The role tiers fall out of the policy scopes. Every client-facing policy is
written `to authenticated`, so anonymous requests — a missing or invalid
JWT — match no policy at all and are denied everywhere; the local policy
test suite verifies this as its T03 scenario (FACTBASE §13). The
`authenticated` tier is every signed-in user, teacher or student alike, and
the distinction between them is not a different key or a different endpoint:
it is `has_role('teacher')` inside the policy. The `service_role` tier
bypasses RLS entirely and exists only inside Edge Function server contexts
(Chapter 23). Guests in the app are a UI state, not a database tier — they
hold no session, so at the database they reach only what the `anon` role
can read: the four sign-up lookup tables (`programs`, `campuses`,
`year_levels`, `year_sections`; Chapter 20 §20.2.1) and none of the
content tables (Chapter 6).

## 22.4 Membership, teacher access, and personal privacy

Three building blocks decide who sees an activity, and they compose rather
than compete. Ownership: the creator always sees their own rows.
Membership: an enrolled student sees `section`-scoped rows of their sections
and `course`-scoped rows of their courses, checked by `is_enrolled` /
`is_section_teacher` / `is_course_teacher` (Chapter 21). Teacher breadth:
since the 0019/0020 rework (FACTBASE §13), a teacher reads *every*
non-personal activity university-wide — `has_role('teacher') and scope in ('section',
'course')` — with no enrollment requirement, because the dashboard's filter
bar narrows the view client-side after the read (Chapter 17; mirror
`mig_001900_global_visibility.sql:4-10`).

Personal-activity privacy is the negative space of those rules and is worth
stating precisely: a `scope = 'personal'` row is visible only to its creator
and to explicit `activity_participants` rows. It is invisible to every other
student, and — deliberately — to every teacher, because the teacher branch
requires a section or course scope. The same clause structure is repeated
inside `activity_visible_to_user`, so the sources, participants, and report
policies inherit identical semantics (mirror
`mig_001900_global_visibility.sql:95-135`). The privacy guarantee is thus a
property of one policy expression, not of any client's good behavior.

## 22.5 The five most important policies, quoted

Each policy below is presented the way a reviewer should read it: what it
permits, who is allowed, the condition, what it denies, and where it is
defined. The SQL is quoted verbatim from the migration source mirrors.

### 22.5.1 activities_select — the visibility rule

- Permits: reading every activity the viewer owns, participates in, or can
  reach through membership or role.
- Allowed: authenticated sessions only.
- Condition: live rows (soft-deleted only for the creator), then owner OR
  participant OR teacher-with-non-personal-scope OR section enrollment OR
  course enrollment.
- Denied: other users' personal rows (teachers included), soft-deleted rows,
  rows of sections/courses the student is not enrolled in, everything for
  anonymous.
- Defined: migration 0019 (mirror `mig_001900_global_visibility.sql:47-87`;
  student branches unchanged since 0002, teacher branch added 0019).

```sql
create policy activities_select on public.activities
  for select to authenticated
  using (
    -- NOTE: for UPDATE, PostgreSQL enforces SELECT policies' USING as a
    -- WITH CHECK on the new row — the updated row must remain visible.
    -- Soft-deleted rows therefore stay visible ONLY to their creator so
    -- authors can soft-delete their own activities; everyone else (and the
    -- feed) never sees them. The service (no JWT) bypasses RLS entirely.
    (deleted_at is null or created_by_user_id = auth.uid())
    and (
      created_by_user_id = auth.uid()
      or exists (
        select 1 from public.activity_participants ap
        where ap.activity_id = activities.id
          and ap.user_id = auth.uid()
      )
      -- 0020: university-wide teacher read — no enrollment needed.
      or (
        public.has_role('teacher')
        and scope in ('section', 'course')
      )
      or (
        scope = 'section'
        and exists (
          select 1 from public.enrollments e
          where e.section_id = activities.section_id
            and e.user_id = auth.uid()
        )
      )
      or (
        scope = 'course'
        and exists (
          select 1
          from public.enrollments e
          join public.sections s on s.id = e.section_id
          where s.course_id = activities.course_id
            and e.user_id = auth.uid()
        )
      )
    )
  );
```

(The comment's "0020" label is the migration file's own internal numbering;
the file is migration 0019 in this documentation's numbering — see the note
in Chapter 24 §24.2.)

### 22.5.2 activities_insert — student self-publishing

- Permits: a student creating personal activities, publishing
  `student-reported` section rows in sections they are enrolled in, and
  teachers creating section/course-scoped rows.
- Allowed: authenticated sessions only, writing as themselves.
- Condition: `created_by_user_id = auth.uid()` plus the scope branch.
- Denied: inserting on another user's behalf; section/course scope without
  being that section's teacher or that course's teacher; a
  `student-reported` section row without enrollment in that section;
  everything for anonymous.
- Defined: migration 0015 (mirror `mig_001500_self_publish.sql:49-68`;
  origin-honesty escalation is policed separately by
  `guard_activity_insert`, Chapter 21 §21.4.1).

```sql
create policy activities_insert on public.activities
  for insert to authenticated
  with check (
    created_by_user_id = auth.uid()
    and (
      scope = 'personal'
      or (
        scope = 'section'
        and verification_status = 'student-reported'
        and exists (
          select 1 from public.enrollments e
          where e.section_id = activities.section_id
            and e.user_id = auth.uid()
            and e.role = 'student'
        )
      )
      or (scope = 'section' and public.is_section_teacher(activities.section_id))
      or (scope = 'course' and public.is_course_teacher(activities.course_id))
    )
  );
```

This single policy is migration 0015's headline: student reports publish
instantly, with no approval queue anywhere (Chapter 8; FACTBASE §8). The
enrollment check inside it is what stops a student from publishing into a
section they do not belong to, and the same rule is re-asserted by the guard
trigger as defense in depth.

### 22.5.3 posts_insert — community writes are own-row writes

- Permits: a signed-in user creating a post authored by themselves.
- Allowed: authenticated sessions only.
- Condition: `author_id = auth.uid()` — nothing else.
- Denied: creating a post as another user; posting as anonymous (the
  unauthenticated tier); guest writes; anything beyond the schema's own
  length and rate checks.
- Defined: migration 0003 (mirror `mig_000300_community.sql:216-218`).

```sql
create policy posts_insert on public.posts
  for insert to authenticated
  with check (author_id = auth.uid());
```

The brevity is the point: community authorship is not negotiable, and every
other community rule is either a sibling policy of the same shape
(`comments_insert`, the likes tables, `user_blocks`) or a guard trigger
behind it. The comment policy adds visibility so a comment can only land on
a post the writer can actually see — RLS applies inside the policy's
subquery, so an invisible post rejects the insert (mirror
`mig_000300_community.sql:290-294`):

```sql
create policy comments_insert on public.comments
  for insert to authenticated
  with check (
    author_id = auth.uid()
    and exists (
      select 1 from public.posts p where p.id = comments.post_id
    )
  );
```

(Evidence: mirror `mig_000300_community.sql:295-302`. The parent-linkage and
depth rules are enforced by `guard_comment_insert`, not the policy, because
a policy must not subquery its own table — PostgreSQL would reject it with
"infinite recursion detected in policy", mirror `:291-294`.)

### 22.5.4 community_images_insert_own_folder — storage writes

- Permits: an authenticated user uploading an image object into the
  `community-images` bucket, under their own first-level folder.
- Allowed: authenticated sessions only.
- Condition: the bucket matches AND the object path's first folder segment
  equals the caller's user id.
- Denied: uploads into another user's folder (`{uid}/...` prefix enforced
  server-side, so a modified client gains nothing), uploads into other
  buckets, anonymous uploads.
- Defined: migration 0005 (mirror `mig_000500_storage.sql:28-33`).

```sql
create policy community_images_insert_own_folder on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'community-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
```

This is a policy on `storage.objects`, Supabase's storage catalog table, so
the same RLS machinery protects object bytes as protects rows. The bucket is
private and reads are granted to authenticated users as a group (the feed is
signed-in-only), while update and delete policies repeat the own-folder
check (mirror `mig_000500_storage.sql:23-53`).

### 22.5.5 The moderator exception

One community policy breaks the own-row pattern on purpose, and stating it
completes the picture: moderators and admins may delete any post or comment
as a moderation action, a grant that exists alongside the author's own
delete policy and is exercised through the same soft-delete guard path
(mirror `mig_000300_community.sql:229-232`):

```sql
-- Moderators and admins may remove content as a moderation action.
create policy posts_delete_moderator on public.posts
  for delete to authenticated
  using (public.has_role('moderator') or public.has_role('admin'));
```

No moderator UI exists yet — the moderation queue is BUILT & VERIFIED at the
database level with no client (FACTBASE §3) — but the rule a future queue
would need is already the law of the table.

## 22.6 Community privacy mechanics

The community rules combine four mechanisms, each in its right place.
Writes are own-row (§22.5.3): authorship equals identity, so nobody can
post, comment, or like as someone else. Anonymity is immutable: once a post
or comment is created, `guard_post_update` and `guard_comment_update` refuse
any change to `is_anonymous` or `author_id`, because flipping a post from
anonymous to named would retroactively reveal history (mirror
`mig_000300_community.sql:94-96`); the flag is therefore a decision made
once, at creation. Moderation deletes exist as the single staff override
(§22.5.5). And the read surface anonymizes server-side: the `feed_posts` and
`feed_comments` views null the author id for anonymous rows *before* joining
profiles, so a display name can never leak, while `my_posts` lets the author
see their own anonymous history (Chapter 20 §20.5). The honesty footnote
belongs here too: the app's composer currently hard-wires `is_anonymous =
false`, so anonymous posting is PARTIALLY IMPLEMENTED — the database side
is complete, the client side is not (FACTBASE §9; Chapter 9).

## 22.7 Storage security in summary

The bucket model follows the same principle as the tables: a private bucket,
a group read grant for authenticated users, and own-folder writes. The four
policies from migration 0005 are `community_images_read` (authenticated
SELECT on the bucket), `community_images_insert_own_folder`,
`community_images_update_own_folder`, and `community_images_delete_own_folder`
(mirror `mig_000500_storage.sql:22-53`). The path convention
`{uid}/{postId}/{ts}.jpg` means the policy's folder check and the app's
layout agree by construction: an object written under any other prefix
fails `WITH CHECK` at the database, whether the writer is the shipped app or
a tampered one. Signed URLs are not part of this design; downloads run as
authenticated requests through the Storage API with the policies above
deciding (FACTBASE §4).

## 22.8 Two engineering subtleties worth knowing

The soft-delete trick. The `activities_select` and `posts_select` policies
keep soft-deleted rows visible only to their creator
(`deleted_at is null or created_by_user_id = auth.uid()`). The reason is the
UPDATE semantics from §22.1: because PostgreSQL enforces SELECT policies'
USING as a WITH CHECK on updated rows, an author soft-deleting their own row
(set `deleted_at`) would fail the policy's first clause the moment the row
became deleted — the exception clause is what makes the write legal, while
everyone else's feed never sees the row again (mirror
`mig_000200_activities.sql:328-336`, `mig_000300_community.sql:198-202`).

The snapshot trap. `activities_select` deliberately does not call
`activity_visible_to_user` even though that helper expresses the same
visibility: STABLE functions see the statement-start snapshot, so a row
inserted by `INSERT ... RETURNING` — the PostgREST write pattern — would be
invisible to the helper and every client insert would be rejected. The
policy therefore inlines its checks against row-local columns and other
tables, and the helper is reserved for policies on tables that reference an
already-committed activity (mirror `mig_000200_activities.sql:328-336`;
Chapter 21 §21.4.6). Both subtleties are documented in the migration files
themselves, which is the best defense that they are understood rather than
accidental.

## 22.9 Limitations and the defense answer

The policy layer's verification state must be stated exactly. The local
`policies_test.sql` run of 2026-10-30 was PARTIALLY PASSED with two known
issues that both predate migration 0032 and are unrelated to it: a programs
fixture missing `campus_id` (invalid after 0012's NOT NULL) and T08.1, which
expects SQLSTATE 42501 where migration 0015's guard raises P0001 (FACTBASE
§15). The hosted project runs migrations only through 0028, so the 0032
EXECUTE posture described in Chapter 21 is not yet active there — hosted ACL
probes on 2026-10-29/30 showed the three RPCs still executable by
`authenticated` on the hosted project (FACTBASE §15; deployment is roadmap
item M2.1, Chapter 24). RLS also says nothing about data quality: a policy
guarantees who may read a row, not that the row reflects the real world —
recorded is not complete coverage (FACTBASE §16).

The defense answer: every client reaches the database with a public key and
a session token, and the database itself decides row by row what that
session may see and touch — identity from the verified JWT, ownership from
column equality, membership from the enrollment helpers, teacher breadth
from one audited policy clause, and denial by default everywhere else; the
policies are versioned in migrations and quoted in this chapter, so the
rules can be read by anyone with the repo.

---


# Chapter 23 — Edge Functions

The backend has exactly three Edge Functions, all Deno programs deployed on
the hosted Supabase project: `classroom-sync` (405 lines), `classroom-import`
(197 lines), and `site` (192 lines) (FACTBASE §11, §14; line counts from the
source mirrors `fn_classroom-sync.ts`, `fn_classroom-import.ts`,
`fn_site.ts`). They exist for three reasons no client could cover on its own:
the two Classroom functions must call Google's APIs and the privileged
database RPCs from a server context where the service-role key lives, they
must do it without ever persisting a Google token, and `site` must serve the
project's public pages from a domain Google's OAuth consent screen accepts.
Chapter 12 tells the same story from the app's point of view; this chapter is
the per-function reference — responsibility, input, authentication,
authorization, processing, database operations, responses, errors, security,
and who actually calls each function.

## 23.1 The deployment model

Two facts about the platform shape everything below. First, each function
receives `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` as auto-injected
environment variables — the service key exists only in this server context
and never in any client (fn_classroom-sync.ts:26-27; Chapter 26). Second,
JWT verification is a per-function deployment flag: a function deployed with
`--no-verify-jwt` receives requests whether or not an `Authorization` header
is present, and must do its own identity checks in code. Student Codex
deploys exactly two functions with that flag — `classroom-import` (so its
session-less `list` action can serve the pre-sign-up picker; the `import`
action then verifies the session JWT in code) and `site` — and each use is
safe for a specific, argued reason (§23.3 and §23.4). Everything else the
functions do behind a session JWT they verify themselves against the
platform's `/auth/v1/user`
endpoint, which is the boundary the comment in `classroom-import` names
outright: "that check is the security boundary that protects the RPC"
(fn_classroom-import.ts:15-18).

## 23.2 classroom-sync

**Responsibility.** Import the signed-in user's Google Classroom coursework
and announcements into the canonical `activities` table as read-only
`imported` evidence for their *linked* courses (fn_classroom-sync.ts:1-5).
This is the function behind "Sync now", the post-import follow-up sync, and
the opt-in auto-sync on app open (Chapter 12; Chapter 15).

**Input.** A POST request with the caller's Supabase session JWT in the
`Authorization` header, and a JSON body carrying the freshly minted Google
access token plus, when known, the Google account email
(fn_classroom-sync.ts:49-51, :68-81). The Android caller sends exactly that
shape (SupabaseClassroomSyncRepository.kt:40-52).

**Authentication.** The function never trusts the JWT at face value: it
forwards it to the platform's user endpoint and accepts only a 200 response
with a user id:

```ts
  // ---- 1. Identify the caller (platform already verified the JWT). ------
  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.toLowerCase().startsWith("bearer ") ? authHeader.slice(7).trim() : "";
  if (!jwt) return json({ error: "missing_bearer_token" }, 401);

  const meRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${jwt}` },
  });
  if (meRes.status !== 200) return json({ error: "invalid_session" }, 401);
  const me = await meRes.json();
  const uid: string | undefined = me?.id;
  if (!uid) return json({ error: "invalid_session" }, 401);
```

(fn_classroom-sync.ts:48-59.)

**Authorization.** Two independent gates decide what may be synced. The
Google token authorizes its own account's data — Google returns only the
courses of the account that consented. The local scope comes from matching:
the function fetches the caller's own enrollments and only a Classroom course
that resolves to one of those sections is imported, with unmatched classes
"skipped and reported, never force-created" (fn_classroom-sync.ts:136-159,
:161-191). The exact-link tier comes first — "Tier 0 — the EXACT link" by
`external_course_id`, ahead of the normalized course-code heuristics
(:168-176) — which is why courses imported through `classroom-import` match
without any name guessing (Chapter 13).

**Data processing.** For every matched course the function pages through
`courseWork` and `announcements` (pageSize 100), imports only PUBLISHED
coursework, maps Google work types to tracking categories
(ASSIGNMENT → assignment, question types → quiz, else other,
:260-270), and normalizes due dates with DATE-first semantics: a due date
without a time means end-of-day 23:59 on the Manila wall clock, computed
with a fixed UTC+8 offset and no DST (:245-258, :30). Announcements carry no
due date, so they are pinned to their creation time to land on the calendar
day they were made (:344-348).

**Database operations.** Every item is imported through the
`upsert_activity_from_source` RPC *with the service key* — the
service-only, idempotent upsert of Chapter 21 — after a pre-check of the
`source_key` so the response can report new versus refreshed items
(:212-218):

```ts
    const rpcRes = await fetch(`${SUPABASE_URL}/rest/v1/rpc/upsert_activity_from_source`, {
      method: "POST",
      headers: service,
      body: JSON.stringify({
        p_source_key: args.sourceKey,
        p_provider: "google_classroom",
        p_external_course_id: args.externalCourseId,
        p_external_item_id: args.externalItemId,
        p_requesting_user_id: uid,
        p_title: args.title,
        p_description: args.description,
        p_activity_type: args.activityType,
        p_course_id: args.courseId,
        p_section_id: args.sectionId,
        p_due_at: args.dueAt,
        p_estimated_effort_minutes: null,
        p_scope: "section",
        p_source_meta: args.sourceMeta,
      }),
    });
```

(fn_classroom-sync.ts:220-239.) The function also maintains the
`google_connections` state registry, POSTing an upsert with
`Prefer: resolution=merge-duplicates` (:89-95) — connected status, the
account email, and the last-sync outcome (:367-387).

**Response.** A summary JSON object: `status` (`ok` or `partial`),
`imported`, `updated`, `classesTotal`, `matchedClasses` (with course code
and section name), `skippedClasses` and `skippedCoursework` (each with a
reason), and `syncedAt` (fn_classroom-sync.ts:389-402). The app's
`ClassroomSyncResult` parses exactly these fields
(SupabaseClassroomSyncRepository.kt:78-87).

**Error handling.** Wrong method → 405; missing configuration → 500; missing
JWT or invalid session → 401; missing Google token → 400. Google refusing
the token (401/403) is distinguished and recorded in the registry as
`revoked` or `expired` with a reconnect message (:114-128); any import-time
RPC failure funnels through `fail()`, which stamps a failed last-sync state
and returns a failed summary (:97-105). A partial outcome (skips) is
reported honestly as `partial`, not `ok`.

**Security considerations.** The Google access token is transit-only — "used
in transit only — nothing is stored server-side, so there is no refresh
token to leak and no client secret anywhere" (:9-13; Chapter 26). The
service key never leaves the function. The trusted writes are bounded by
the RPC's own service-only guard (Chapter 21), and the sync is read-only
toward Google by scope (Chapter 12 §12.4).

**Actual callers.** The Android app's `SupabaseClassroomSyncRepository`
(:40-52) — invoked by manual sync, the import sheet's follow-up sync, and
`ClassroomAutoSync.kt` on app open (FACTBASE §6; Chapter 15). Nobody else:
the teacher dashboard makes no Edge Function calls, and no other client
exists.

## 23.3 classroom-import

**Responsibility.** The course-level import door: `action:"list"` returns
the Google account's ACTIVE Classroom courses for the app's picker, and
`action:"import"` enrolls the student in the picked courses by running them
through the trusted import RPC (fn_classroom-import.ts:4-18; Chapter 12
§12.6–12.8).

**Input.** A POST body with `action` (list or import), the Google access
token, and for import the picked `courseIds` plus the account email
(:45-64). The import action additionally requires the session JWT in the
`Authorization` header.

**Authentication.** The two actions authenticate differently, and the split
is deliberate. `list` needs no Supabase session: "the Google token alone
authorizes it (Google returns only that account's own courses), which lets
the pre-sign-up gate offer the import too. Deployed with --no-verify-jwt
for exactly this reason" (:5-11). `import` requires the caller's Supabase
session JWT, verified against `/auth/v1/user` — and the function also
refuses the service key presented as a user token (:112-123):

```ts
  // ---- 3b. IMPORT: identify the caller (platform-verified session JWT). -
  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.toLowerCase().startsWith("bearer ") ? authHeader.slice(7).trim() : "";
  if (!jwt || jwt === SERVICE_KEY) return json({ error: "missing_bearer_token" }, 401);

  const meRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${jwt}` },
  });
  if (meRes.status !== 200) return json({ error: "invalid_session" }, 401);
  const me = await meRes.json();
  const uid: string | undefined = me?.id;
  if (!uid) return json({ error: "invalid_session" }, 401);
```

(fn_classroom-import.ts:113-123.)

**Authorization.** The picked ids are re-fetched from Google server-side
before anything is written: the function lists the account's ACTIVE courses
itself (paginated, :71-98) and intersects the picked ids with that list, so
"only ids Google just confirmed ACTIVE" proceed — "a stale/forged id stops
here" (:141-156). An empty intersection returns
`no_matching_active_courses`.

**Data processing.** For the import action the surviving courses are
pre-truncated to the RPC's shape guards (externalId ≤64, name ≤160, section
≤80) as defense in depth — "the RPC re-validates everything"
(:158-164).

**Database operations.** One privileged call: the
`import_student_classroom_courses` RPC invoked with the service headers
after the caller's identity was established. The service header set carries
the service key and nothing user-specific:

```ts
  const service = {
    apikey: SERVICE_KEY,
    Authorization: `Bearer ${SERVICE_KEY}`,
    "Content-Type": "application/json",
  };
```

(fn_classroom-import.ts:125-129.) The RPC call then passes the *verified*
user id and the re-fetched course payload — the user's authority comes from
the completed session check, not from anything the client sent in the body:

```ts
  const rpcRes = await fetch(`${SUPABASE_URL}/rest/v1/rpc/import_student_classroom_courses`, {
    method: "POST",
    headers: service,
    body: JSON.stringify({ p_user: uid, p_courses: payload }),
  });
```

(fn_classroom-import.ts:166-170.) The function then stamps the
`google_connections` row — connected status, the picked Google account email
(so later syncs pin to the same account), and a successful last-sync entry
(:131-138, :186-192).

**Response.** `status:"ok"` merged with the RPC's summary — `enrolled`,
`created`, `linked`, `matched`, `invalid`, `sectionsCreated` — plus the
echoed course payload (:194). The app parses these fields into
`ClassroomImportResult` (SupabaseClassroomImportRepository.kt:118-141).

**Error handling.** The same 405/500/400/401 ladder, plus
`no_courses_selected`, `no_matching_active_courses` with a plain-language
message, Google 401/403 with the reconnect message (:80-87), and
`rpc_<status>` failures that include a truncated RPC body for diagnosis
(:171-177).

**Security considerations.** The design assumption is that the body alone
proves nothing: without a verified session the import action stops at 401,
and without Google's own confirmation the course ids stop before the RPC.
After migration 0032 the RPC is service-context only, which makes this
function's verified-then-service-key path the single remaining caller
(Chapter 21 §21.3; Chapter 27). The `list` action being reachable without a
JWT is safe because it grants nothing: it reads the token owner's own course
names from Google and writes nothing.

**Actual callers.** The Android app's
`SupabaseClassroomImportRepository` — `listCourses` (:41-58) and
`importCourses` (:60-86) — behind the `ClassroomImportSheet` picker,
available at sign-up and later in Settings (FACTBASE §3; Chapter 12).
Nobody else calls it.

## 23.4 site

**Responsibility.** Serve the project's public web presence — the home page
and the privacy policy — on the project's own supabase.co domain
(fn_site.ts:1-19). The reason it exists at all is external: Google's OAuth
consent-screen verification requires branding URLs on domains the project
controls, and Google "refuses branding URLs hosted on domains the project
does not control" (:4-8).

**Input and routes.** Any HTTP method on `/functions/v1/site` or
`/site/home` returns the home page, `/site/privacy` returns the policy, and
anything else returns a styled 404 (:10-15, :177-191).

**Authentication and authorization.** None — the function is deployed with
`--no-verify-jwt`, and that is safe because these are static public pages:
there is no session-gated content, no database access, and no per-user
behavior of any kind (:15-18).

**Data processing, database operations, response.** None, none, and static
HTML with inline CSS and `Cache-Control: public, max-age=300` (:172-175).
The pages are generated from the publish-branding drafts and kept
ASCII-safe in source (:17-19); the privacy policy's content — read-only
Classroom scopes, transit-only tokens, the account-deletion email path —
matches the technical chapters (Chapter 12; Chapter 26).

**Error handling.** The 404 branch is the whole error surface; there is
nothing stateful to fail.

**Security considerations.** The function contains no secrets: the project
ref and the support email are public identifiers. The one honest caveat is
completeness, not security — a static page is a promise the rest of the
system has to keep, and the privacy policy's claims (read-only access, no
trackers, disconnect anytime) are the same ones Chapters 12 and 26 verify.

**Actual callers.** Public browsers and Google's consent-screen review.
No authenticated client calls it, and no other caller exists.

## 23.5 User-authenticated requests versus service-role operations

The distinction a reviewer must be able to draw is between *who is asking*
and *who is writing*. A user-authenticated request carries the caller's
session JWT; if that JWT were forwarded to the database, PostgREST would
apply RLS as that user — the app's ordinary table reads and writes work
exactly that way (Chapter 22). The Edge Functions use the JWT only to
establish identity, verified against `/auth/v1/user`; they never forward it
for the privileged writes. Instead, after verifying the user themselves,
they invoke the trusted RPCs with the service key. Inside such an RPC there
is no JWT at all — `auth.uid()` is null, the service-only guard passes, and
the function runs as the trusted, narrowly-privileged actor of Chapter 21.
The database trust boundary therefore sits at the RPC's EXECUTE grant, and
the human trust boundary sits at the function's own session check.

This is precisely the split migration 0032 hardened. Before 0032,
`import_student_classroom_courses` and `enroll_student_courses` accepted
`authenticated` EXECUTE as well, so the Edge Function's verification was a
convenience, not the boundary — a direct authenticated call could bypass it
(audit findings F2/F3; Chapter 27). After 0032, the RPCs are service-context
only: the Edge Function's verify-then-invoke-with-service-key sequence is
the only remaining path for the import RPC, and the enrollment RPC survives
only for the auth triggers' definer context (Chapter 21 §21.3). The
verification quoted in §23.3 is thus no longer optional hygiene — it is the
door. One related detail from `classroom-sync`: even its read of the
caller's enrollments runs with the service headers, scoped by an explicit
`user_id=eq.{uid}` filter in the query string rather than by RLS
(fn_classroom-sync.ts:137-141) — the same service-context discipline, with
the scoping done in the URL instead of the policy layer.

## 23.6 Limitations, verification state, and defense answer

The verification state of the two Classroom functions is exact: coursework
and announcement sync is BUILT & VERIFIED — live browser-verified on
2026-10-28 — while the Edge Functions were not re-exercised against real
Google OAuth in the 2026-10-30 SQL run (FACTBASE §3); that run verified the
database layer they call, not the Deno code paths. Synchronization remains
client-triggered only: no background service, no push, no Pub/Sub exists
anywhere in the functions or the migrations (FACTBASE §11; Chapter 15), so
if nobody syncs, a Classroom change is not reflected until the next
successful sync. The two `--no-verify-jwt` deployments are safe by
construction: `classroom-import`'s open surface is only the `list` action
(which grants nothing — it returns the token owner's own course names from
Google and writes nothing), with the privileged `import` action gated by
the function's own session verification, and `site` serves static public
pages. The 0032 hardening that completes this chapter's trust story is
tested locally and not yet deployed to the hosted project (FACTBASE §15;
Chapter 24).

The defense answer: every privileged write to the shared database happens
inside a Deno function that first proves who the caller is against the
platform's own auth endpoint, then acts with the service key through RPCs
that refuse every other caller — the client never holds a secret, Google
tokens are transit-only, and the two intentionally public surfaces expose
nothing but course names and static HTML.

---


# Chapter 24 — Database Migration History

The database's present shape — 23 tables, 4 views, one private bucket, every
policy and function from Chapters 20 through 23 — is not described by any
single file. It is the accumulated result of 33 ordered SQL migrations,
numbered 0000 through 0032, living under `supabase/migrations/` (FACTBASE
§5, §13). This chapter explains what that migration discipline is for,
lists every migration with its purpose, narrates the architectural turns,
details the final hardening migration 0032, and — most importantly for an
honest defense — separates what has been applied and tested locally from
what the hosted project actually runs today.

## 24.1 What versioned migrations are for

A migration is one SQL file that moves the schema from one state to the
next, and the files are named by timestamp prefixes so that lexicographic
order is application order. Student Codex's set runs 000000 through 003200;
this documentation cites them in the abbreviated `NNNN` form (0015, 0032)
and, where sibling chapters cite full filenames, in the sanitized
`2026010100NNNN_name.sql` form. Because each step is a file and the order
is fixed, the whole history is reproducible: a fresh database replays
0000 through 0032 and arrives at the current state, which is exactly what
the local test harness does before running the SQL test suites (Chapter 21
§21.3).

The discipline is append-only in practice. Nothing in the set edits an
earlier file; later changes arrive as new numbered files that redefine or
replace objects explicitly — `create or replace function` for bodies
(migrations 0015, 0019, 0023, 0027, 0031 all do this), `drop policy if
exists` followed by `create policy` for policies (mirror
`mig_001500_self_publish.sql:47`, `mig_001900_global_visibility.sql:45`),
and idempotent `DO` blocks or `on conflict do nothing` seeds for data
(mirror `mig_001500_self_publish.sql:134-200`,
`mig_000700_school_details.sql:78-138`). The payoff for this project is
specific: the security story can be read as a sequence of diffs — an open
teacher door in 0013, gates added in 0028 through 0031, doors revoked in
0032 — and every rule quoted in Chapter 22 can be traced to the migration
that wrote it.

## 24.2 The 33 migrations

Purposes come from the fact base's inventory (FACTBASE §13) and the
migrations' own header comments (quoted from the source mirrors).

| Migration | Purpose |
|---|---|
| 0000 | Core: `programs`, `profiles`, `user_roles`, `set_updated_at`, `has_role`, the auth trigger, first policies |
| 0001 | Academic structure: `courses`, `sections`, `enrollments` + the membership helpers |
| 0002 | Activity Beacon core: `activities`, `activity_sources`, `activity_reports`, grouping and participant tables, visibility helper, guards |
| 0003 | Student community: `posts`, `post_images`, `comments`, likes, `user_blocks`, first feed views |
| 0004 | Moderation: `content_reports`, triage guard and policies |
| 0005 | Storage: private bucket `community-images` + the four own-folder policies |
| 0006 | Profile names: first/last name columns, `derive_username`, `claim_username`, the profile-sync trigger |
| 0007 | School details: `campuses`, `year_levels`, `year_sections` lookups, seeds, profile columns, registry-validating triggers |
| 0008 | Phase completion: rate guards, `google_connections`, `upsert_activity_from_source`, extended feed views, `my_posts`, `section_workload_daily`, image-only posts |
| 0009 | Demo seed data, part 1 of 3 (fixed-UUID demo teacher/students — FACTBASE §13) |
| 0010 | Demo seed data, part 2 of 3 (demo courses/sections/enrollments — FACTBASE §13) |
| 0011 | Demo seed data, part 3 of 3 (demo activities/posts — FACTBASE §13) |
| 0012 | Campus binding: `programs.campus_id` becomes NOT NULL (FACTBASE §13) |
| 0013 | Teacher self-service sign-up RPC (`teacher_signup`) |
| 0014 | Purpose not documented in the fact base or the provided mirrors |
| 0015 | Student self-publish: instant section publish, reporter self-service edit, legacy queue drain |
| 0016 | Multi-class teacher sign-up (`teacher_signup_multi`, 12-group cap) |
| 0017 | Student course enrollment RPC (`enroll_student_courses`) |
| 0018 | Redefinition of `enroll_student_courses` (the fact base attributes the course-code path jointly to 0017/0018; 0018's own diff is not in the mirror set) |
| 0019 | Global teacher visibility: university-wide non-personal reads, `teacher_signup_global` RPC |
| 0020 | Manila due-date repair (FACTBASE §13) |
| 0021 | Course-entry redefinition of `enroll_student_courses` — whole-name entries with a junk guard (0032 header; 0027 comments) |
| 0022 | Classroom course import: `courses.external_course_id` + `import_student_classroom_courses` RPC |
| 0023 | Activity category tracking: `category_locked` columns, `suggest_activity_category`, lock-respecting upsert |
| 0024 | Classifier regex fix, 1 of 3 (FACTBASE §11) |
| 0025 | Classifier regex fix, 2 of 3 (FACTBASE §11) |
| 0026 | Classifier regex fix, 3 of 3 (FACTBASE §11) |
| 0027 | Cohort course convergence: `course_text_matches`, `cohort_section_name`, fuzzy tiers, cohort-section preference |
| 0028 | Teacher email verification: OTP/magic-link `amr` gate on both active teacher RPCs (superseded) |
| 0029 | Email-click verification step (FACTBASE §13; superseded) |
| 0030 | Verified-email DB gate on the teacher RPCs (retired by 0031) |
| 0031 | School-email domain gate `@parsu.edu.ph`, replacing 0030's gate |
| 0032 | RPC EXECUTE hardening: the F1/F2/F3 revokes (§24.5) |

> NOTE: the file for migration 0019 carries an internal header comment that
> labels it "migration 0020" (mirror `mig_001900_global_visibility.sql:3`),
> and one policy comment inside it says "0020". The documentation set, the
> fact base, and the dashboard's own comments consistently cite the file as
> 0019 (`WebView/app.js:2040`); the header comment is a numbering slip in
> the source file itself, and 0020 is the Manila due-date repair.

## 24.3 The anatomy of a migration

One migration is worth reading closely because they all share its shape.
Migration 0015 (student self-publish) is the best example since it touches
all four kinds of change in one file. It opens with a transaction wrapper
(`begin;` … `commit;`, mirror `mig_001500_self_publish.sql:42`, `:202`), so a
failure anywhere leaves the database untouched. Policy changes follow the
replace pattern rather than editing anything:

```sql
begin;

-- ---------------------------------------------------------------------------
-- 1. activities_insert — add the student self-publish path
-- ---------------------------------------------------------------------------
drop policy if exists activities_insert on public.activities;
```

(Evidence: mirror `mig_001500_self_publish.sql:42-48`.) Function changes use
`create or replace function` — the guard is redefined in place with its new
student-reported rule (`:74-109`, quoted in Chapter 21 §21.4.1). A new policy
(`activities_update_own_student_report`, `:116-127`) is added without
touching the existing update policy. And the one data change — draining the
legacy pending-report queue — is an idempotent `DO` block that re-runs as a
no-op once drained (`:134-200`). The result is a file a reviewer can read as
a proposition ("student reports publish instantly"), see implemented as
four coordinated changes, and replay safely on any database state.

The same anatomy recurs across the set: 0019 drops and recreates
`activities_select`, 0023 redefines the upsert RPC and the update guard,
0027 redefines both enrollment RPCs, 0031 redefines both teacher RPCs, and
0032 — uniquely — changes privileges only, with no body, policy, or data
edits at all. Migration 0007 shows the seed variant: registry inserts with
`on conflict do nothing` so re-runs are harmless (mirror
`mig_000700_school_details.sql:78-138`).

## 24.4 The architectural turns

**0009–0011 — demo seeds.** Three migrations seed fixed-UUID demo data — a
demo teacher, demo students, courses, sections, enrollments, activities,
and posts (FACTBASE §13) — so the dashboard and app have content to show out
of the box; the demo credentials are documented in the dashboard README
(values not reproduced here; FACTBASE §12). This data lives on the hosted
project, and what to do about it in production is an open roadmap item
(M5.3; FACTBASE §16).

**0012 — campus binding.** The registry became campus-specific: every
`programs` row now carries a NOT NULL `campus_id`, so a program choice
implies a campus. The teacher signup RPCs lean on this — a caller who
leaves campus empty gets the program's own campus as the fallback (mirror
`mig_001300_teacher_signup.sql:72-77`) — and the dashboard's campus filter
gains a sound data basis (Chapter 16).

**0015 — self-publish replaces the approval queue.** This is the product
decision that reshaped the activity domain: student reports publish
INSTANTLY as real `activities` rows, the teacher dashboard is view-only,
and the badge (`student-reported` vs `teacher-confirmed`) is "a LABEL, not
a gate" (mirror `mig_001500_self_publish.sql:4-10`). The migration changed
the insert policy, extended the guard, added reporter self-service edits,
and drained every legacy `pending` report into published activities —
"Nothing waits for approval again" (`:32-37`). Chapter 8 covers the
resulting semantics.

**0019/0020 — university-wide visibility.** Teacher sign-up stopped
collecting cohort choices; a teacher is now just an account with the role,
reading every non-personal activity across all campuses (mirror
`mig_001900_global_visibility.sql:4-10`; the 0020 file completed the
rework, per FACTBASE §13). Personal rows stay private from teachers, and
the enrollment-driven read gate was retired while the enrollment-driven
*write* gates (teacher-confirmed status, corrections) remained — the split
Chapters 17 and 19 examine.

**0022–0027 — Classroom import, category locking, cohort convergence.**
Five related changes built the import pipeline of Chapter 12: the
`external_course_id` exact link and the import RPC (0022), teacher
category corrections that survive re-syncs via `category_locked` plus the
title-token classifier (0023, with regex repairs 0024–0026), and the
convergence work (0027) that made a classmate's short-typed "CC4" resolve
to the imported full-name course row instead of creating a parallel one —
"fuzzy matching needs ≥1 significant token" and deliberately nothing
looser (mirror `mig_002700_cohort.sql:37-44`; Chapter 13).

**0028–0031 — the teacher email-verification saga.** With email
confirmation OFF on the hosted project, any address could become a working
teacher account. Migration 0028 demanded proof that the session was minted
by an emailed code, read from the JWT's signed `amr` claim — a claim the
client cannot forge:

```sql
  if not exists (
    select 1
    from jsonb_array_elements(coalesce(auth.jwt()->'amr', '[]'::jsonb)) as m
    where m->>'method' in ('otp', 'magiclink')
  ) then
    raise exception 'EMAIL_NOT_VERIFIED: teacher access needs a verified email - request a 6-digit code from the dashboard, enter it, then retry';
  end if;
```

(Evidence: mirror `mig_002800_email_verification.sql:55-61`; the header
explains the fail-closed semantics at `:19-24`.) Migrations 0029 and 0030
refined the machinery, and 0031 replaced all of it with the school-domain
gate — the school issues every teacher a `@parsu.edu.ph` address, "so the
domain IS the credential" (mirror `mig_003100_domain_gate.sql:5-8`). The
suffix proves eligibility, not mailbox ownership; the 0028–0030 machinery
remains as dormant fallback (FACTBASE §15; Chapter 19 §19.5).

**0032 — hardening.** The final migration closed the three audit doors;
it is important enough to deserve its own section.

## 24.5 Migration 0032 in detail

Migration 0032 exists because the 2026-10-29/30 audit found three
SECURITY DEFINER RPCs executable by `authenticated` even though no live
client needed that door: the legacy `teacher_signup` (F1 — any signed-in
user could self-grant the teacher role), `import_student_classroom_courses`
(F2 — a direct call could enroll arbitrary users into forged courses),
and `enroll_student_courses` (F3 — victims could be enrolled into
attacker-created courses). Chapter 27 reproduces each attack and its
verification; this section documents the fix itself.

The fix is three REVOKE statements:

```sql
-- F1: legacy single-group teacher signup — no live caller; close the door.
revoke execute on function public.teacher_signup(uuid, integer, uuid, uuid)
  from authenticated;

-- F2: Classroom course import — Edge Function (service role) only.
revoke execute on function public.import_student_classroom_courses(uuid, jsonb)
  from authenticated;

-- F3: student course enrollment — auth.users triggers (definer) only.
revoke execute on function public.enroll_student_courses(uuid, uuid, integer, uuid, jsonb)
  from authenticated;
```

(Evidence: migration 0032, mirror `mig_003200_hardening.sql:43-53`.)

Everything else about the migration is what it *refuses* to do, and that
restraint is the point. It is a pure privilege change: NO function body is
modified, so the tested logic of 0017–0027 runs byte-for-byte as before.
The legitimate paths are preserved by re-asserting the service_role grants
idempotently (`:57-60`) and re-asserting the creation-time `public`/`anon`
revokes (`:63-68`) so the file documents the intended end state by itself.
The two auth triggers keep working because a trigger executes as its
function's definer regardless of grants — "the authenticated grant was
never needed by them" (`:20-23`). And the active teacher doors are
untouched: `teacher_signup_global` / `teacher_signup_multi` keep their
authenticated grants and their 0031 domain gates, byte-for-byte
(FACTBASE §15). The effect is exactly the caller matrix of Chapter 21
§21.3: service key, trigger definer, or domain-gated teacher RPC — nothing
else.

The restrained shape has a practical benefit worth stating: because no
function body changed, every behavior verified by the earlier migrations'
own tests still applies, and the only new surface to verify is the privilege
matrix itself — which is exactly what `rpc_authorization_test.sql` asserts
(§24.6).

## 24.6 The verification suites

Four SQL test files verify the migration set, and they were all written for
the same harness: plain `DO` blocks with assertions, with identity simulated
"the Supabase way (role switch + request.jwt.claims, exactly what PostgREST
provides)" (mirror `test_rpc_authorization.sql:4-6`). The newest,
`rpc_authorization_test.sql`, was written for migration 0032 and maps its
ten scenarios explicitly:

- T01–T03 — an ordinary authenticated session can no longer directly invoke
  `teacher_signup` (F1), `import_student_classroom_courses` (F2), or
  `enroll_student_courses` (F3).
- T04 — anon AND authenticated hold no EXECUTE privilege on the three RPCs,
  PUBLIC inheritance included.
- T05 — the active teacher-registration doors keep working: authenticated
  still executes `teacher_signup_global` and `teacher_signup_multi`.
- T06 — the trusted service path keeps working: service_role still executes
  the Classroom import and student enrollment RPCs.
- T07 — the student sign-up door is intact end-to-end: inserting an
  `auth.users` row with school details and course codes still aligns the
  profile and creates the enrollments via the `handle_new_user` trigger —
  "the definer context EXECUTE revokes cannot touch".
- T08 — the Classroom import door is intact end-to-end as the service role
  (the Edge Function's exact call), including the idempotent re-run, the
  `external_course_id` link, and the resulting enrollment.
- T09 — the 0031 school-email domain gate is unchanged: a
  non-`@parsu.edu.ph` caller is rejected by BOTH active teacher RPCs.
- T10 — a `@parsu.edu.ph` caller still succeeds on both active teacher RPCs.

(Evidence: mirror `test_rpc_authorization.sql:9-35`, condensed.) The other
three predate 0032: `phase_completion_test.sql` covers the sign-up trigger
path, `gc_source_identity_test.sql` covers the source-key dedup of Chapter
14, and `policies_test.sql` covers the RLS matrix of Chapter 22. Their
results from the 2026-10-30 run appear in §24.7.

## 24.7 Local testing versus hosted deployment

These two states must never be conflated, and the distinction is an
honesty anchor for the whole documentation set.

**Local test application.** The 2026-10-30 verification run applied the
full migration set to a LOCAL PostgreSQL 17.11 instance carrying a
replicated Supabase platform surface (Docker being unavailable for the
standard harness; FACTBASE §15). Against that database,
`rpc_authorization_test.sql` PASSED across T01–T10 — the revokes hold
under an ordinary authenticated session, anon inherits nothing, the active
teacher doors still open, the service path still executes the import and
enrollment RPCs, the sign-up trigger still enrolls end-to-end, and the
0031 domain gate still rejects non-school callers (mirror
`test_rpc_authorization.sql:9-35`). `phase_completion_test.sql` PASSED, and
`gc_source_identity_test.sql` PASSED with a temporary compatibility shim
because its fixture predates 0012's campus_id. `policies_test.sql` was
PARTIALLY PASSED with two known issues that a control rebuild showed also
fail without 0032 — a programs fixture missing `campus_id`, and T08.1
expecting SQLSTATE 42501 where migration 0015's guard raises P0001
(FACTBASE §15). The overall capability status is IMPLEMENTED —
VERIFICATION INCOMPLETE, in the fact base's own words "locally tested, NOT
deployed to hosted" (FACTBASE §3).

**Hosted deployment.** The hosted Supabase project has migrations through
0028 applied. Migrations 0029–0032 exist as local files that are not yet
pushed — they sit in the same uncommitted working tree that holds most of
the current product (a 59-entry `git status` listing; FACTBASE §17) — and
deploying them is roadmap item M2.1, followed by M2.2's post-deploy hosted
verification (FACTBASE §18). Until that happens, hosted reality lags local
reality in exactly one respect that matters: non-mutating ACL probes on
2026-10-29/30 showed the three RPCs still executable by `authenticated`
ON THE HOSTED PROJECT (FACTBASE §15). Every claim in this documentation
therefore keeps the two states separate: 0032 is locally tested, NOT
hosted-deployed; the hosted project's policy set is the 0000–0028
intersection of what these chapters describe.

## 24.8 Defense answer

If a judge asks how the schema is managed, the answer is: 33 timestamped,
append-only SQL migrations under `supabase/migrations/` — every table,
policy, function, and grant in Chapters 20 through 23 is traceable to a
numbered file, so the security posture is reviewable as a diff history
rather than a snapshot. The final hardening migration is a pure privilege
change — three REVOKEs, no bodies touched, service paths re-asserted —
verified by a ten-scenario authorization test that passed locally on
2026-10-30; and we say plainly that the hosted project still runs through
migration 0028, with deploying and re-verifying 0029–0032 as the next
roadmap milestone.

---


# Chapter 25 — Authentication vs Authorization

This chapter separates two words that judges and reviewers use interchangeably
and that Student Codex keeps deliberately apart. Authentication answers "who
is this account?"; authorization answers "what may this account do?". In
Student Codex the first question is answered by Supabase Auth once, at
sign-in, and the second is answered by the database on every single request —
by role rows, row-level security policies, and function EXECUTE privileges
that no client can edit. The distinction is the backbone of the project's
security story, and it is the reason a tampered app or a stolen publishable
key still cannot make anyone a teacher.

## 25.1 Two questions, one request

In plain language: signing in proves you are you; it does not prove you are
allowed to touch anything. A student who signs in successfully has an
identity and nothing more — no teacher calendar, no moderator tools, no
ability to grant themselves anything. Every capability beyond "being an
account" is decided by a second, independent mechanism that reads database
rows the client cannot write.

The confusion is understandable because in many hackathon projects the two
collapse into one: "if you are logged in, you are admin". Student Codex was
built the other way around. The very first migration documents the decision:
trusted data such as roles has "no client write policies" so that "a student
must not be able to make themselves a teacher/moderator/admin"
(`supabase/migrations/` migration 000000, `user_roles` header comment). Every
layer described below exists to keep that promise.

The vocabulary maps onto the platform like this: Supabase Auth (GoTrue) owns
authentication and issues the session JWT; the `user_roles` table plus the
`has_role()` helper own role resolution; row-level security policies own
per-row decisions; and EXECUTE privileges own per-function decisions. A
request that fails any later layer still "worked" as authentication — and
that is exactly the outcome the design intends.

## 25.2 What a successful sign-in actually grants

Authentication in Student Codex is Supabase Auth (GoTrue) plus two entry
methods: email/password sign-in through `signIn`, and Google sign-in, which
fetches a Google ID token on-device through Credential Manager and exchanges
it through `signInWithGoogleIdToken`
(`app/src/main/java/com/example/studentcodex/data/auth/AuthRepository.kt:106-107`
and `:136`; onboarding flow in Chapter 6). What
the exchange yields is a session JWT for one account — and, on first
sign-up, a row in `auth.users`, from which the `handle_new_user` trigger
creates the bare `profiles` row automatically (migration 000000,
`handle_new_user` + `on_auth_user_created`).

That is the complete list. PostgREST then maps the request to one of three
PostgreSQL roles depending on what the caller presents: the publishable key
without a session resolves to `anon`, the publishable key with a session JWT
resolves to `authenticated`, and the service-role key resolves to
`service_role`, which bypasses RLS entirely. The project's own test harness
describes this mapping exactly — identity is "simulated the Supabase way
(role switch + request.jwt.claims, exactly what PostgREST provides)"
(`tests/rpc_authorization_test.sql:4-6`). Note what this means: every signed
in user, student or teacher or attacker, shares the same `authenticated`
database role. Sign-in cannot be where authorization decisions live.

## 25.3 Why signing in does NOT make someone a teacher

The teacher role is a row in `user_roles`, and that table is closed to
clients. It has a CHECK constraint over exactly four roles, a unique
`(user_id, role)` pair, and no insert/update/delete policies at all — the
schema comment states the intent verbatim:

```sql
-- user_roles: trusted, admin-managed role assignments. A student must never
-- be able to make themselves a teacher/moderator/admin. There are no client
-- write policies on this table (service role bypasses RLS).
create table if not exists public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null check (role in ('student', 'teacher', 'moderator', 'admin')),
  granted_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (user_id, role)
);
```

(Evidence: migration 000000, `user_roles` block; read policy
`user_roles_select_own` allows a user to read only their own rows, plus
moderator/admin reads.) Roles therefore enter the table through exactly two
kinds of doors, both server-side:

1. Gated RPCs for teachers. The dashboard's sign-up finishes through
   `teacher_signup_global` / `teacher_signup_multi`, which first require a
   signed-in session (`if v_uid is null then raise exception 'Sign in before
   signing up as a teacher'`) and then require the caller's `auth.users.email`
   to end with `@parsu.edu.ph`, read from the table server-side so forged JWT
   claims are irrelevant (migration 0031, gate block
   `supabase/migrations/20260101003100_teacher_school_email_domain.sql`).
   Only then is the role inserted, idempotently (`on conflict (user_id, role)
   do nothing`).
2. Auth triggers for students. `handle_new_user` and
   `handle_user_profile_sync` run on `auth.users` metadata changes in the
   GoTrue service context, filling the profile, deriving the username,
   granting the student role, and enrolling course codes (FACTBASE §7;
   migrations 0017/0018/0027 via `enroll_student_courses`).

The audit chapter tells the cautionary tale that proves the point: before
migration 0032, a legacy RPC called `teacher_signup` was still executable by
any `authenticated` session, and a sandbox attacker with a fresh gmail
account used it to self-grant the teacher role plus 6 enrollments — signing
in was enough, because the EXECUTE grant was the only missing door (finding
F1, migration 0013 grant lines 106-107, closed by migration 0032:43-45; full
account in Chapter 27). The lesson cuts both ways: identity alone grants
nothing, and a function privilege granted to `authenticated` grants
everything the function does.

## 25.4 Three layers: identity, role, per-row and per-function checks

Authorization in Student Codex is best explained as three layers that a
request must climb in order. Each layer answers a different question, and
each is enforced somewhere the client cannot reach.

| Layer | Question | Enforced by | If it fails |
|---|---|---|---|
| Identity | Which account is this? | Supabase Auth JWT, `auth.uid()` | Request treated as anon |
| Role | What is this account? | `user_roles` rows via `has_role()` | No teacher/moderator powers |
| Per-row / per-function | May this touch THIS row or function? | RLS policies + EXECUTE privileges | 0 rows, or 42501 error |

The third layer has two halves because the database exposes two kinds of
surface. Tables are guarded by row-level security policies, evaluated per
row: the current `activities_select` policy lets a teacher read every
non-personal row university-wide through the role helper, while students see
only their own, participant, or enrolled-section rows (migration 0019,
`activities_select`):

```sql
or (
  public.has_role('teacher')
  and scope in ('section', 'course')
)
```

Functions are guarded instead by EXECUTE privileges, and this half matters
because the sensitive RPCs are `SECURITY DEFINER`: they run as their owner
and bypass RLS, so a policy cannot protect them — only the privilege grant
can. This is precisely the F1/F2/F3 lesson from the audit (Chapter 27), and
it is why the hardened end state grants service-context RPCs to
`service_role` only, the pattern `upsert_activity_from_source` already used
(migration 0023:171-176, plus its in-body guard `if auth.uid() is not null
then raise exception 'upsert_activity_from_source is a service-only
operation'`, :106-108). The complete per-table policy inventory is
cataloged in Chapter 22; this chapter keeps only the examples needed to
show each layer at work.

A worked example walks all three layers. A teacher presses a category
correction on the dashboard (Chapters 18 and 19): the PATCH request carries
the publishable key and the teacher's session JWT — layer one, identity,
resolves to a user id. Layer two happens inside policy evaluation:
`activities_update` checks `is_section_teacher(section_id)`, which resolves
that account's enrollments, so the same PATCH from a student matches zero
rows (migration 000200, `activities_update`). Layer three's function half
fires on the write itself: `guard_activity_update` stamps the corrector and
rejects verification-status escalation to `teacher-confirmed` unless the
caller is a teacher of that section/course or an admin (migration 0023,
`guard_activity_update`). The client UI asked the same questions earlier to
decide whether to show the button — but the server never trusted those
answers.

## 25.5 Who can do what

The table below is the ground truth a defense answer can stand on. Every row
is backed by a policy, a guard, or a grant cited in this book; "cannot" rows
are enforced, not merely unexposed.

| Caller | Can do | Cannot do |
|---|---|---|
| anon (no session) | Load the public home page / privacy policy (site Edge Function) | Read or write any table; call gated RPCs |
| guest (app UI state) | Browse demo content in the app | Write community or Beacon data (a UI state, not a database role) |
| student (authenticated) | Own profile edits; personal + enrolled-section student-reported activities; community posts, comments, likes, reports under rate guards; own-folder image storage | See others' personal rows; become teacher; set `teacher-confirmed`/`imported` status; write `user_roles` |
| teacher (authenticated + role) | Read ALL non-personal activities university-wide; sign up via domain-gated RPCs; correct categories on sections they teach; create teacher-confirmed rows for their sections | See personal rows of students; edit rows in sections they do not teach; grant roles |
| moderator (role, schema only) | Community moderation deletes; read all `user_roles` | Any client UI exists to exercise these powers today |
| admin (role, schema only) | Update/delete activities; drive report triage; set teacher-confirmed status | Bypass guards — guards still validate caller context |
| service_role (Edge Functions only) | Execute `upsert_activity_from_source`, `import_student_classroom_courses`, `enroll_student_courses` post-0032; write connection registry | Appear in any client; the app has no path to this key |

Evidence anchors, in order: anon is "denied everywhere" per policies_test T03
(FACTBASE §13) and the public site function is deliberately the only
unauthenticated surface (FACTBASE §14, `functions/site`); guests are an
AuthGateScreen UI state that reads demo
content and cannot write (FACTBASE §7). Student capabilities come from
`profiles_update_own` (migration 000000), `activities_insert` with the
student-reported path (migration 0015), community own-row policies plus
rate guards (migrations 000300/000800 per FACTBASE §13), and storage
own-folder policies (migration 000500). Teacher reads come from
`activities_select` (migration 0019); corrections from `activities_update`
and `guard_activity_update` (migrations 000200/0023); the role door from
migration 0031. Moderator and admin powers exist in the policies
(`user_roles_select_own`, moderator deletes, admin branches in the activity
policies) but no client exposes a moderator queue (FACTBASE §3,
content_reports row). Service-role reach is the post-0032 grant set
(migration 0032:57-60).

Two honest nuances belong next to this table. First, the app UI is sometimes
narrower than the database: the DB policy `activities_update_own_student_report`
(migration 0015) would let a student edit their own section report rows, but
the app only offers edit/delete on personal manual rows
(BeaconScreen.kt:344; Chapter 8) — the server permits more than the client
exposes, never less. Second, on the hosted project today the three audited
RPCs are still executable by authenticated sessions because migration 0032
is locally tested but not deployed — that gap is Chapter 27's subject and
must be stated whenever this table is presented.

## 25.6 Limitations and the defense answer

Three limitations frame this chapter honestly. Email confirmation is OFF on
the hosted project — a testing configuration — so "authenticated" currently
means "registered with any address", not "verified owner of a mailbox"
(`supabase/config.toml`, `[auth.email] enable_confirmations = false`). The
`@parsu.edu.ph` gate proves eligibility, not ownership: it reads the address
from `auth.users` server-side, but a non-school mailbox simply cannot be
proven owned under this configuration, and production identity verification
is UNRESOLVED (roadmap M2.3). And the privilege hardening itself — migration
0032 — is `IMPLEMENTED — VERIFICATION INCOMPLETE`: locally tested, NOT
deployed to the hosted project, which still runs migrations through 0028
(FACTBASE §13, §15).

> NOTE: Say it in this order to a judge: "Signing in only tells us who you
> are. What you may do lives in three server-side layers — role rows the
> client cannot write, row-level security evaluated per row, and EXECUTE
> privileges on the privileged functions. The audit found three grants that
> blurred identity and authorization; migration 0032 closed them, and the
> hosted deployment of that fix is tracked as roadmap M2.1/M2.2."

The remaining chapters of this part build on this foundation: Chapter 26
covers the keys and tokens that carry identity, Chapter 27 documents the
F1/F2/F3 findings in full, and Chapter 28 covers what the database promises
about the data itself. The dashboard-specific walkthrough of the same ladder
is Chapter 19; the onboarding flow that provisions roles is Chapter 6.

---


# Chapter 26 — Secrets and Token Handling

Every multi-client system ships values that look secret and values that are
secret, and confusing the two categories is the fastest way to fail a
security review. Student Codex handles exactly six credential-like things:
the Supabase publishable key, the Supabase service-role key, the Supabase
session JWT, the Google OAuth client id, the Google access token, and one
file at the repository root that holds a live OAuth client secret. This
chapter classifies each one, shows where it lives, where it travels, and
where it is allowed to appear — and it deliberately never reproduces a
single credential value. Locations and classifications only, throughout.

## 26.1 The inventory: what is public by design and what is not

The classification is the defense. A value being visible in a client is a
problem only if that value grants power — and in Supabase the boundary
against power is row-level security, not key secrecy.

| Value | Classification | Where it lives | Boundary |
|---|---|---|---|
| Supabase publishable (anon) key | Public by design | Dashboard JS; Android BuildConfig | RLS decides every request |
| Supabase service-role key | Server secret | Edge Function env only | Never in any client |
| Supabase session JWT | Per-user credential | Browser/app memory, SharedPreferences session | Auth expiry + RLS |
| Google OAuth client id | Public identifier | `supabase/config.toml`, Android BuildConfig | Identifies, does not authenticate |
| Google access token | Short-lived user credential | Device memory, request body, transit only | Expires; revocable; never stored |
| `client.json` (repo root) | Live OAuth client secret | Repository root — flagged | Treat as compromised material |

The one-line summary a judge needs: nothing secret is embedded in either
client, every secret that exists lives server-side, and the two identifiers
that do ship in clients are public identifiers whose abuse is contained by
row-level security and OAuth audience checks respectively (Chapter 25;
Chapter 19 covers the dashboard-side reasoning in §19.2).

## 26.2 The publishable key: public by design, RLS is the boundary

The teacher dashboard states the model in its own header comment — it "talks
to hosted Supabase with the PUBLISHABLE key only" and "row-level security
decides what is visible" (`WebView/app.js:14-19`). The key is present in
plain text at the top of the file:

```text
const SUPABASE_URL = 'https://<project-ref>.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_<redacted>';
```

(Values redacted here; the literals sit at `WebView/app.js:26-27`.) The
Android app carries the same two values, but not hand-typed into source:
Gradle reads the git-ignored `.env` at the project root during configuration
and exposes only `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` through
`BuildConfig` (`app/build.gradle.kts:25-30`, `:74-75`, buildConfigField
declarations at `:151-160`). The header of that file states the rule: "only
the publishable key may ship inside the client" (`app/build.gradle.kts:11-23`).

The build script does not merely trust the developer — it fails the build on
the dangerous mistakes. A secret-format key is rejected outright:

```kotlin
if (key.startsWith("sb_secret_")) {
    throw GradleException(
        "SUPABASE_PUBLISHABLE_KEY in .env is a SECRET key. Secret/service-role keys " +
            "must NEVER be embedded in the Android app. ..."
```

(`app/build.gradle.kts:98-107`, redacted tail; legacy JWT-style keys are
decoded and refused if the payload carries `service_role`, `:108-133`.) All
of these failures print actionable messages that never echo the value
itself. Why is shipping the publishable key acceptable? Because with the
publishable key alone a caller is `anon` or, with a stolen session,
`authenticated` — and every table is behind RLS with anonymous denied
everywhere (Chapter 25). The key identifies the project; the session JWT and
the policy layer decide the rest.

## 26.3 The service-role key: server context only

The service-role key bypasses RLS, so it may exist in exactly one place: the
Edge Function runtime environment. Both Classroom functions read it from
Deno's injected environment and refuse to run without it:

```ts
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!SUPABASE_URL || !SERVICE_KEY) return json({ error: "server_misconfigured" }, 500);
```

(Evidence: `supabase/functions/classroom-import/index.ts:41-43`; identical
block in `supabase/functions/classroom-sync/index.ts:44-46`.) No client
contains the key, references the key, or has a code path that could reach
it: the Android app talks to PostgREST with the publishable key and to the
Edge Functions over HTTPS, and the dashboard is plain static files. The
Gradle guard in §26.2 exists precisely so that the one way the key could
accidentally reach a client — pasting it into `.env` — is a build failure
rather than a shipped APK.

The key's power is also confined by usage. The Edge Functions present it to
PostgREST only after verifying the caller's session JWT against
`/auth/v1/user` (Chapter 12 covers the full request flow), and the RPCs
they invoke with it carry their
own in-body guards — `upsert_activity_from_source` raises
`'upsert_activity_from_source is a service-only operation'` if
`auth.uid()` is not null (migration 0023:106-108), and migration 0032 makes
`service_role` the only role with EXECUTE on the two enrollment RPCs
(Chapter 27). Defense in depth runs in both directions.

## 26.4 Google OAuth client configuration: an identifier, not a secret

Google's OAuth model has public clients, and Student Codex is one. Two
configurations matter. First, the Supabase project's Google provider is
enabled with a client id:

```text
[auth.external.google]
client_id = "<redacted public identifier>"
enabled = true
```

(Evidence: `supabase/config.toml:341-343` — the value is a public
identifier and is still redacted in this book as policy.) Second, the
Android app optionally carries the same "Web application" client id as
`GOOGLE_SERVER_CLIENT_ID`, loaded from `.env` into BuildConfig — the Gradle
header calls it "A PUBLIC client identifier, not a secret - the only Google
value allowed in the app", and an empty value simply disables the Google
sign-in button with a setup notice rather than failing the build
(`app/build.gradle.kts:77-89`, `:161-167`). Credential Manager then fetches
a Google ID token whose audience is that client id, and Supabase Auth
verifies the token and issues its own session (GoogleAuthManager.kt
documentation block; Chapter 6).

There are no Google client secrets in either client. That is not an
omission — it is the platform's own design for installed apps and
server-side verification: the client id names the app, the ID token proves
the Google account consented to that app, and nothing reusable is stored on
the device. The one place a Google secret does exist in this repository is
the flagged file described in §26.8.

## 26.5 Google access tokens: minted per sync, transit-only

Classroom sync needs a second, separate authorization: the student's Google
consent for read-only Classroom scopes. The token lifecycle is deliberately
short. What it is: an access token minted on-device by the Google
Authorization API after the student sees Google's own consent sheet; the
requested scopes are strictly read-only — `classroom.courses.readonly`,
`classroom.coursework.me.readonly`, `classroom.announcements.readonly`
(ClassroomAuthorization.kt, `ClassroomScopes.READONLY`). Why per sync: the
token "is used for exactly one sync run and is never stored (no refresh
tokens, no client secret anywhere in the app): each sync re-authorizes,
which also means revoking in the Google account settings takes effect
immediately" (ClassroomAuthorization.kt:132-137, the class documentation
for `PlayServicesClassroomAuthorizer`).

How it travels: in the HTTPS request body to the `classroom-sync` Edge
Function — never in a header, never logged, never persisted. The function's
header states the rule: "Tokens are used in transit only — nothing is
stored server-side, so there is no refresh token to leak and no client
secret anywhere in the app" (`supabase/functions/classroom-sync/index.ts`,
design block; the token is read from the body at `:74-75`). What happens
internally: the function immediately exchanges it for read-only Classroom
API calls and discards it when the request ends; the only lasting record is
the sync outcome in `google_connections`, never the token. Account pinning
closes the last ambiguity: when the connection registry knows which Google
account the student chose, silent re-authorization is pinned to exactly that
account, and any pin failure is a skip — "a background import must never
quietly pull some OTHER account's roster" (ClassroomAuthorization.kt,
`fetchSilentAccessToken` documentation; the chosen account is itself an
explicit system account picker, Chapter 6).

Revocation semantics follow from the design. Because there is no stored
grant, a student revoking app access in their Google account settings simply
makes the next token request fail: Google returns 401/403, the Edge Function
marks the connection revoked/expired and answers "Google rejected the
authorization — reconnect Google Classroom"
(`supabase/functions/classroom-sync/index.ts:114-128`). No cleanup of stored
tokens is needed because none exist. Limitations, stated plainly: the
transit-only property depends on HTTPS and on the Edge Function runtime's
own log hygiene, and a consent sheet must appear on first connect — the
silent auto-sync path refuses to show one and skips instead
(ClassroomAutoSync.kt:41-48; Chapter 15).

## 26.6 Server-side versus client-side responsibilities

The division of labor is what keeps every token in its lane. The client
owns user intent and identity hand-off; the server owns verification and
every privileged write.

| Responsibility | Client (app / dashboard) | Server (Supabase / Edge Functions) |
|---|---|---|
| Session | Holds JWT, auto-refreshes | GoTrue issues and verifies it |
| Caller identity | Sends JWT in Authorization header | Edge Function verifies via /auth/v1/user before any RPC |
| Google consent | Shows picker + consent, mints token | Re-fetches courses from Google server-side |
| Privileged writes | Never | RPCs invoked with service-role key only |
| Data visibility | Renders what RLS returns | RLS evaluates every row |

Two consequences deserve emphasis. First, the Edge Functions trust nothing
the client says about itself: `classroom-import`'s "import" action re-fetches
the picked course ids from Google "so only real, currently-active Classroom
courses enter", and its session-JWT check is described in the source as
"the security boundary that protects the RPC"
(`supabase/functions/classroom-import/index.ts`, header block `:11-18`, the re-fetch at `:148-156`). Second, the client never
holds anything whose theft would escalate privilege: the worst-case steal is
one student's own session or one short-lived Classroom token, both of which
expire and both of which only ever authorize that student's own data
(Chapter 25).

## 26.7 Token storage and non-storage on the device

Local persistence is deliberately minimal — one mechanism, few keys. The
Android app uses SharedPreferences through multiplatform-settings (russhwolf)
and nothing else: no Room, no DataStore (FACTBASE §5). Three kinds of state
live there: the Supabase auth session (so sign-in survives app restarts),
the Classroom auto-sync toggle (a single boolean key,
`classroomAutoSyncEnabled` — ClassroomAutoSync.kt:22-31), and the Guidance
overlay preferences. That is the complete inventory.

What is conspicuously absent matters more. No Google access token is ever
written to disk — tokens live in memory for the duration of one sync run.
No refresh token exists to store, because the authorization flow requests
none (§26.5). No service key, no secrets, no Classroom credentials of any
kind touch device storage. The dashboard side is even simpler: supabase-js
keeps the session in browser storage with auto-refresh
(`WebView/app.js:239-241`, Chapter 19), and the page itself is static files.
What the clients store about users, and what they deliberately do not,
connects directly to the privacy discussion in Chapter 24.

## 26.8 Sensitive information exposure: what is flagged, and the roadmap

The audit surfaced exposure issues that live in the repository rather than
in any shipped client, and this book reports them the way the fact base
does — by location and classification, never by value. Four items:

1. `client.json` at the repository root holds a live OAuth client secret
   for the Google Cloud project. It is flagged in the fact base as a
   credential to treat seriously; its values are never reproduced anywhere
   in this documentation. Status: KNOWN LIMITATION — remediation is roadmap
   item M2.5 (credential hygiene).
2. `.env` exists at the project root and is git-ignored; it supplies the
   public configuration described in §26.2. The fact base records that it
   was never read by the documentation effort; this chapter likewise cites
   only its role, never its contents.
3. Demo credentials are documented in `WebView/README.md` (demo teacher
   accounts created during verification, including a multi-class teacher
   and two picker-exercise accounts) and additionally exist as constants in
   the dashboard source (`WebView/app.js:28-29`). Locations noted; values
   not reproduced. These are test conveniences for a demo deployment, and
   the README itself says to delete the accounts under Dashboard ->
   Authentication -> Users when no longer needed.
4. The working tree is uncommitted, with roughly ninety root-level
   developer-script files and the credentials above sitting in it
   (FACTBASE §17). Repository hygiene is roadmap item M2.4; credential
   hygiene is M2.5.

> WARNING: Do not demonstrate, screenshot, or read aloud any value from
> `client.json`, `.env`, or the README demo credentials during a defense.
> The strong position is the classification: "one live secret exists at the
> repo root, it is flagged, it is not consumed by any client, and removing
> it is tracked as M2.5."

## 26.9 Defense answer

The one-breath version for judges: "Both clients ship only public
identifiers — the publishable key, whose power is contained by row-level
security, and the Google client id, which is an audience marker. The
service-role key exists only inside Edge Functions and is read from the
server environment at request time. Google Classroom tokens are minted per
sync after visible consent, travel once through the request body, are never
stored, and include no refresh tokens or client secrets, so revocation
takes effect on the very next sync. The device stores only the Supabase
session and two preference flags. The known exposure is a flagged OAuth
secret at the repo root, tracked for cleanup in the roadmap — not in any
shipped client."

Limitations to concede proactively: the repo-root secret is real and must
be rotated before any production use (M2.5); demo accounts documented in
the README must be deleted for production (M5.3 covers production data
decisions); and none of this constitutes a certified secrets-management
process — it is a deliberately minimal, honest scheme appropriate to the
project's current stage. The token-exchange sequences are walked in
Chapter 12; the audit findings that motivated the privilege side of this
model are Chapter 27's subject.

---


# Chapter 27 — Known Security Findings and Remediation

This is the audit chapter, and it is written the way the project itself
records the audit: findings first, impact second, fix third, verification
fourth, and deployment honesty last. On 2026-10-29 and 2026-10-30 the
project was probed for authorization weaknesses; three findings — F1, F2,
and F3 — were confirmed by reproductions in a sandbox against the real
schema, and all three were fixed by one migration, 0032, whose status must
be stated exactly the same way every time: locally tested, NOT deployed to
the hosted project. The primary evidence is the 2026-10-31 full-repo audit
(`plan-push/evidence/AUDIT-EVIDENCE.md`) and the F1/F2/F3 verification
review (`plan-push/evidence/REVIEW-F1F2F3.md`), as recorded in the fact
base. Nothing in this chapter is speculative: every quoted line was read
from the source mirrors, and every reproduction is documented in the
evidence files.

## 27.1 The root cause: one pattern, three doors

All three findings share a single root cause, which is worth understanding
before the individual findings because it is the pattern a reviewer should
look for in any Supabase project. Student Codex keeps trusted operations in
`SECURITY DEFINER` RPCs — functions that run as their owner and therefore
bypass row-level security. RLS cannot protect such a function; the only
thing that can gate who may invoke it is the PostgreSQL EXECUTE privilege.
When one of those functions was granted `EXECUTE` to the `authenticated`
role, every signed-in user in the world could run it, and the function body
then did whatever it was written to do — including trusting a
caller-supplied user id.

The project already contained the correct pattern before the audit.
`upsert_activity_from_source`, the Classroom write path from migration 0023,
is granted to `service_role` only and additionally raises on any caller
with a JWT: `if auth.uid() is not null then raise exception
'upsert_activity_from_source is a service-only operation'` (migration
0023:106-108, grants at :171-176). Migration 0032's header calls this "the
house pattern already used by upsert_activity_from_source (migration 0023):
service-context RPCs are granted to service_role only" (migration 0032,
header comment :35-36; the full function and trigger catalog is Chapter
21's subject). The three findings were the three places the code base had
not yet applied it.

A second asymmetry makes the pattern dangerous in practice: the clients
never call these RPCs directly. The Android app makes zero direct RPC calls
(verified: REST tables and Edge Functions only, FACTBASE §4), the dashboard
calls only the teacher sign-up RPCs, and the Edge Functions call the
privileged RPCs with the service key. So the `authenticated` grants were
dead weight for every legitimate caller — and a live door for every
attacker with a curl command and a throwaway account.

## 27.2 F1 — legacy `teacher_signup`: any signed-in user becomes a teacher

### The original problem

`teacher_signup` was created in migration 0013 as the self-service teacher
sign-up door, a deliberate product decision of its era — the header
documented that sign-up "is open to any authenticated account in this
deployment" and listed hardening options for later (migration 0013,
decision note :15-20). The function is `SECURITY DEFINER`, and its only
in-body gate is a session check:

```sql
if v_uid is null then
  raise exception 'Sign in before signing up as a teacher';
end if;
```

(migration 0013, gate block :44-48.) The grant block at the bottom of the
migration is the exact line pair the audit flagged:

```sql
-- Execute: authenticated callers only (auth.uid() inside does the rest).
revoke execute on function public.teacher_signup(uuid, integer, uuid, uuid) from public, anon;
grant execute on function public.teacher_signup(uuid, integer, uuid, uuid) to authenticated;
```

(migration 0013:105-107.) At creation time this matched the product
decision. It survived three successor gates that were added to the newer
sign-up RPCs — 0028's email-ownership proof, 0030's verified-email database
gate, 0031's `@parsu.edu.ph` domain check — none of which were applied to
the legacy function. Meanwhile the dashboard had stopped calling it: 0020
normalized legacy single-group sign-ups into `teacher_signup_multi`, so "no
live caller" remained (migration 0032, header :7-12).

### The impact

The reproduction in the sandbox was direct: a gmail account — an account
with no relationship to the university — signed in, invoked
`teacher_signup` with the demo registry's program, year, and block, and
received the teacher role plus 6 section enrollments (the BSCS 2-A demo
cohort resolves to 6 courses; migration 0013's own verify block documents
"should return 6 for the demo registry"). With the teacher role the
attacker immediately gained university-wide read access to every
non-personal activity through the `activities_select` teacher branch
(migration 0019), which is precisely the visibility the 0031 domain gate
exists to protect. Every later gate was bypassed by construction, because
F1 was the unchecked door in front of all of them.

### The fix

Migration 0032 closes the door with a two-line revoke:

```sql
-- F1: legacy single-group teacher signup — no live caller; close the door.
revoke execute on function public.teacher_signup(uuid, integer, uuid, uuid)
  from authenticated;
```

(migration 0032:43-45.) No function body changed. Because no live caller
existed, nothing legitimate stopped working — verified by the test suite's
T05, which asserts the two ACTIVE teacher doors still execute for
`authenticated` (`tests/rpc_authorization_test.sql:130-141`), and by T09/T10
which exercise the live dashboard registration flow end-to-end through the
domain-gated RPCs instead.

## 27.3 F2 — `import_student_classroom_courses`: forged courses and a hijacked link tier

### The original problem

`import_student_classroom_courses(p_user, p_courses)` was created in
migration 0022 as the trusted import door for the `classroom-import` Edge
Function. The migration's own header described the intended trust model
correctly — "same trust model as enroll_student_courses: service-context
only, SECURITY DEFINER, pinned search_path" (migration 0022:48-49) — but
the grant block contradicted it:

```sql
revoke execute on function public.import_student_classroom_courses(uuid, jsonb) from public, anon;
grant execute on function public.import_student_classroom_courses(uuid, jsonb) to authenticated, service_role;
```

(migration 0022:238-239.) The `authenticated` half of that grant was never
needed by any client. The function takes `p_user` as a caller-supplied
argument and performs no `auth.uid()` check (parameter block, migration
0022:51-53; the body's first check is only `if p_user is null`, :74-76), so
the body trusts its caller completely — which is exactly what a
service-context function may do and a client-exposed function must never
do.

### The impact

The sandbox reproduction showed two concrete abuses. First, foreign-user
enrollment into forged courses: an attacker could invoke the RPC with any
victim's user id as `p_user` and a fabricated course payload, creating
brand-new course and section rows under the Classroom name and enrolling
the victim as a student of courses they never chose. Second, and more
subtle, `external_course_id` hijack of the exact-match tier: migration 0022
gave `courses.external_course_id` a partial unique index
(`create unique index ... on public.courses (external_course_id) where
external_course_id is not null`, migration 0022:42-43), making the
Classroom course id a one-to-one link that `classroom-sync` prefers ahead
of every name heuristic (tier 0, the exact link;
`supabase/functions/classroom-sync/index.ts:169-173`). An attacker who
created a course row carrying an id chosen by the attacker could capture
that exact-match tier: later legitimate syncs of the related Classroom
course would converge on the attacker-controlled row instead of the
correct one. The dedup and convergence machinery of Chapter 14 was
weaponized, not broken — the unique index faithfully linked whatever row
first claimed the id.

### The fix

```sql
-- F2: Classroom course import — Edge Function (service role) only.
revoke execute on function public.import_student_classroom_courses(uuid, jsonb)
  from authenticated;
```

(migration 0032:47-49.) After the revoke, the only remaining caller is the
`classroom-import` Edge Function, which calls the RPC with the service-role
key after verifying the caller's session JWT against `/auth/v1/user` and
re-fetching the picked course ids from Google — "a stale/forged course id
stops there" (function header, `supabase/functions/classroom-import/index.ts`
:11-19 and :148-156). The attack surface therefore collapses from "any
signed-in user, any payload" to "the server-side path that already proves
the user and re-validates the courses against Google".

## 27.4 F3 — `enroll_student_courses`: victims enrolled into attacker-created courses

### The original problem

`enroll_student_courses(p_user, ...)` has taken a caller-supplied user id
since migration 0017, and was granted `EXECUTE` to `authenticated` at
creation (migration 0017 grants, cited in the audit evidence and FACTBASE
§15; the 0017 file itself is not part of the doc-build mirror set, so its
exact line numbers are cited from the audit rather than reproduced here).
The function's legitimate callers are the two `auth.users` metadata
triggers — `handle_new_user` and `handle_user_profile_sync` — which run as
the SECURITY DEFINER owner (postgres) in GoTrue's service context and pass
the new user's id explicitly (migration 0032, header :20-23). The
`authenticated` grant was never needed by those triggers: definer-context
calls exercise owner privileges, not role grants.

### The impact

The reproduction enrolled a victim into attacker-created courses. Because
`p_user` is trusted, an attacker could supply any user id together with
course codes or course identifiers of their choosing; the function's
course-code self-service path would create the courses that did not exist
and enroll the named user in them (advisory locks, 32-code cap and all —
the guards limit volume, not identity). The victim's Beacon and section
visibility would then include attacker-chosen coursework, and the
victim's profile-side data would be polluted in ways the victim could not
see the origin of.

### The fix

```sql
-- F3: student course enrollment — auth.users triggers (definer) only.
revoke execute on function public.enroll_student_courses(uuid, uuid, integer, uuid, jsonb)
  from authenticated;
```

(migration 0032:51-53.) The remaining callers are exactly the two
auth.users triggers running as definer, whose execution is unaffected by
role grants — verified end-to-end by T07, which inserts an `auth.users`
row with school details and course codes (what GoTrue does at sign-up) and
asserts the profile is aligned AND the course enrollments exist through the
trigger path (`tests/rpc_authorization_test.sql:156-191`).

## 27.5 The fix as a whole: a pure privilege change

Migration 0032 is deliberately boring, and its boringness is the point —
it changes privileges only, so the risk of the fix itself is near zero.
The operative block, quoted in full:

```sql
-- F1: legacy single-group teacher signup — no live caller; close the door.
revoke execute on function public.teacher_signup(uuid, integer, uuid, uuid)
  from authenticated;

-- F2: Classroom course import — Edge Function (service role) only.
revoke execute on function public.import_student_classroom_courses(uuid, jsonb)
  from authenticated;

-- F3: student course enrollment — auth.users triggers (definer) only.
revoke execute on function public.enroll_student_courses(uuid, uuid, integer, uuid, jsonb)
  from authenticated;

-- Legitimate service paths stay open (idempotent re-assertion of 0027's
-- grants so this migration fully documents the intended end state):
grant execute on function public.import_student_classroom_courses(uuid, jsonb)
  to service_role;
grant execute on function public.enroll_student_courses(uuid, uuid, integer, uuid, jsonb)
  to service_role;

-- Belt and braces: the creation-time revokes, re-asserted (idempotent).
revoke execute on function public.teacher_signup(uuid, integer, uuid, uuid)
  from public, anon;
revoke execute on function public.import_student_classroom_courses(uuid, jsonb)
  from public, anon;
revoke execute on function public.enroll_student_courses(uuid, uuid, integer, uuid, jsonb)
  from public, anon;
```

(migration 0032:43-68.) The properties that matter for a defense answer:

1. NO function body is modified — the migration header states it outright
   ("pure privilege change ... NO function body is modified", :25-28), so
   no behavior, matching tier, guard, or trigger logic changed anywhere.
2. The `service_role` grants are re-asserted (:57-60) so the file documents
   the intended end state by itself; the Edge Function import path and the
   definer trigger path keep working.
3. The creation-time `public`/`anon` revokes are re-asserted (:63-68) as
   "belt and braces" — fail closed at every role.
4. The active teacher doors are untouched: `teacher_signup_global` /
   `teacher_signup_multi` keep their `authenticated` grants and their 0031
   domain gates "byte-for-byte unchanged" (migration 0032, header :31-33;
   the grants live in migration 0031:220-225).

## 27.6 Verification: what was tested, and where it ran

The fix was verified by `tests/rpc_authorization_test.sql`, a plain-SQL
harness of DO-block assertions that simulates identity the way PostgREST
does — role switch plus `request.jwt.claims` — so the tests exercise the
real privilege resolution, not an approximation. The full run of T01–T10
PASSED on 2026-10-30 against a local PostgreSQL 17.11 database carrying a
replicated Supabase platform surface (Docker was unavailable for that run;
FACTBASE §15). The test map:

| Test | Asserts | Result |
|---|---|---|
| T01 | authenticated can no longer execute `teacher_signup` (F1) | PASSED |
| T02 | authenticated can no longer execute `import_student_classroom_courses` (F2) | PASSED |
| T03 | authenticated can no longer execute `enroll_student_courses` (F3) | PASSED |
| T04 | anon AND authenticated hold no EXECUTE on any of the three, PUBLIC inheritance included | PASSED |
| T05 | the active teacher doors still execute for authenticated | PASSED |
| T06 | service_role still executes the import and enrollment RPCs | PASSED |
| T07 | sign-up trigger path end-to-end: profile aligned, course codes enrolled | PASSED |
| T08 | service import end-to-end: course created, external link set, student enrolled, re-run idempotent (enrolled=0) | PASSED |
| T09 | 0031 domain gate unchanged: non-school caller rejected, no role granted | PASSED |
| T10 | school-domain caller still succeeds on both teacher RPCs (live flow) | PASSED |

(Evidence: `tests/rpc_authorization_test.sql`, test map header :9-35 and
the individual DO blocks; final assertion line
`select 'ALL RPC AUTHORIZATION TESTS PASSED' as result;`, :356.) The same
2026-10-30 run exercised the companion suites: `phase_completion_test.sql`
PASSED; `gc_source_identity_test.sql` PASSED, with a temporary compatibility
shim because the fixture predates 0012's campus_id column; and
`policies_test.sql` was PARTIALLY PASSED with two known issues — a
programs fixture lacking campus_id, and T08.1 expecting SQLSTATE 42501
where migration 0015's guard raises P0001 — both unrelated to 0032 and
predating it; a control rebuild without 0032 showed the same failures
(FACTBASE §15). Those two fixture issues are roadmap item M1.2.

## 27.7 Deployment honesty: tested locally, NOT deployed

This is the caveat that must survive every retelling of this chapter.
Migration 0032 was applied and tested locally only. The hosted Supabase
project has migrations through 0028 applied; 0029–0032 exist as local,
untracked files in `supabase/migrations/` (FACTBASE §13, §17). Hosted ACL
probes run on 2026-10-29 and 2026-10-30 (non-mutating — privilege
inspection, no data changes) showed the three RPCs still executable by
authenticated sessions on the hosted project in its pre-0032 state, which
is exactly what the local migration state predicts: the doors F1/F2/F3
described are still open on the deployment a judge would actually reach.

> WARNING: Until migrations 0029–0032 are pushed, the hosted project still
> permits the F1/F2/F3 attacks. Deploying them is roadmap item M2.1, and
> re-running the authorization probes against hosted afterwards is M2.2.
> Any demonstration or claim must distinguish the local database, where
> the fix is verified, from the hosted database, where it is not yet
> applied.

The honest phrasing for a judge: "We found the weaknesses ourselves,
reproduced them in a sandbox, fixed them with a minimal privilege-only
migration, verified the fix with a ten-case test suite locally, and we are
explicit that the hosted deployment of the fix is the next roadmap step,
not a completed one." Finding and documenting one's own findings is a
strength; obscuring the deployment gap would not be.

## 27.8 Remaining configuration and production-readiness issues

The F1/F2/F3 fix is the largest item, not the only one. The audit surface
also includes these configuration-level issues, each with its roadmap
anchor:

1. Email confirmation is OFF. The hosted project's auth configuration has
   `[auth.email] enable_confirmations = false` (`supabase/config.toml:229-230`),
   a testing configuration chosen together with migration 0031 so that
   sign-up issues a session immediately. The consequence is plain: anyone
   can register with any address, including an address they do not own.
2. The `@parsu.edu.ph` suffix proves eligibility, not mailbox ownership.
   The 0031 gate reads `auth.users.email` server-side through SECURITY
   DEFINER rights, so forged JWT claims are irrelevant
   (`supabase/migrations/20260101003100_teacher_school_email_domain.sql`,
   gate block :65-75 in `teacher_signup_global` and :118-125 in
   `teacher_signup_multi`) — but with confirmations off, a non-school
   mailbox can simply not be proven owned. The domain check is a real gate
   against gmail-style outsiders; it is not proof that the holder of the
   school address registered the account.
3. The 0028–0030 verification machinery remains as dormant fallback. The
   OTP-gated RPCs (0028), the email-click verification flow (0029), and
   the verified-email database gate (0030) were superseded by 0031; the
   dashboard README documents that if confirmation is ever switched back
   on, sign-ups park on the waiting card again — but the domain, not the
   click, decides teacher eligibility either way (`WebView/README.md`,
   notes section). The dormant code is deliberate fallback, not active
   protection.
4. Production identity verification is UNRESOLVED. How a real deployment
   would prove that a teacher account belongs to a real teacher — invite
   codes, an admin approval queue, institutional SSO — is an open decision
   tracked as roadmap M2.3, not an implemented mechanism.
5. The working tree is uncommitted and credentials sit at the repository
   root. The entire current product is uncommitted working-tree state with
   roughly ninety root-level developer-script files (FACTBASE §17), and
   `client.json` at the repo root holds a live OAuth client secret flagged
   in the fact base (values never reproduced; Chapter 26 §26.8). Repository
   hygiene is M2.4; credential hygiene is M2.5.
6. Test-environment parity is imperfect. The 0032 verification ran on a
   local PostgreSQL 17.11 with a replicated Supabase platform surface
   because Docker was unavailable; closing the gap between that surface
   and the hosted platform (and re-running the suites) is roadmap M4.3.
   The hosted auth rate limit (`[auth.rate_limit] email_sent = 2`, managed
   on the dashboard, not via config push — `supabase/config.toml:198-203`)
   is an example of a hosted-only setting local runs cannot see.

## 27.9 What this project has NOT undergone

The boundaries of the audit must be as explicit as the audit itself. This
project has NOT undergone: a complete production security certification;
an external third-party penetration test; a hosted deployment of the 0032
fix (still pending, M2.1); a post-deploy hosted re-verification (M2.2); or
a production identity-verification scheme (UNRESOLVED, M2.3). The
reproductions were sandbox attacks against the real schema by the
project's own authors, and the verification suite ran locally. The
following claims are therefore never made anywhere in this documentation:
production security certification, deployed 0032, all tests green,
real-time sync, offline support, LLM guidance, guaranteed deduplication of
manual entries, or email-ownership proof (FACTBASE §15 "Never claim" list).

## 27.10 Defense answer

> NOTE: The strong version of this story, in three sentences: "Our own
> audit found that three SECURITY DEFINER RPCs still carried grants to the
> authenticated role — a legacy teacher self-grant, the Classroom import
> door, and the enrollment door. We reproduced each attack in a sandbox,
> closed all three with a single privilege-only migration that touched no
> function bodies, and verified the fix with a ten-case authorization test
> suite. The fix is verified locally and its hosted deployment is the
> explicitly tracked next step, together with the remaining
> production-readiness decisions on email and identity."

Read together with Chapters 25 and 26, this chapter completes the security
picture: Chapter 25 explains why identity, role, and privilege must be
separate layers; Chapter 26 covers the credentials that travel between
them; and this chapter documents what happens when a layer's boundary is
mis-granted — and what the project did about it.

---


# Chapter 28 — Reliability and Data Integrity

Reliability in Student Codex is not uptime engineering — it is the question
"can the data lie to us?". The system is online-first by design (no
offline mode; connectivity is required for every write), so the honest
reliability story has two halves: what the database and the import
pipeline structurally guarantee, and what they deliberately do not. This
chapter walks the guarantee side — constraints, source keys, idempotency,
error handling, soft deletion, provenance, and shared-record convergence —
and closes with two explicit lists, one of guarantees and one of
non-guarantees, that a defense answer can quote verbatim. The deeper
treatments of deduplication and synchronization behavior live in Chapters
14 and 15, and the schema inventory itself is cataloged in Chapter 20;
this chapter is about the mechanisms' reliability properties.

## 28.1 Database constraints: the first line of integrity

The schema itself refuses bad data, and it does so at the PostgreSQL engine
level, where no client — and no buggy repository class — can negotiate.
The canonical example is the `activities` table, whose declaration
constrains shape, enumeration domains, and referential links at once:

```sql
create table if not exists public.activities (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 200),
  activity_type text not null default 'other'
    check (activity_type in ('assignment', 'quiz', 'exam', 'project', 'announcement', 'other')),
  scope text not null default 'personal'
    check (scope in ('personal', 'section', 'course')),
  verification_status text not null default 'student-reported'
    check (verification_status in ('imported', 'teacher-confirmed', 'student-reported', 'needs-review')),
  created_by_user_id uuid not null references auth.users (id) on delete cascade,
  deleted_at timestamptz,
  constraint activities_scope_section_requires_section
    check (scope <> 'section' or section_id is not null),
  constraint activities_scope_course_requires_course
    check (scope <> 'course' or course_id is not null)
);
```

(Evidence: migration 000200, `activities` DDL, abbreviated as marked by
the omitted columns.) The two named constraints encode an invariant that
application code could easily get wrong: a section-scoped activity must
actually name a section, and a course-scoped one must name a course. The
same pattern runs through the schema: `user_roles` has a role CHECK plus
`unique (user_id, role)` and `profiles` a username partial unique index
(migration 000000), `programs` carries `unique (university_name,
program_name)`, and `enrollments` has a `(section_id, user_id)` unique
constraint that every idempotent enrollment insert targets with `on
conflict (section_id, user_id) do nothing` (migration 0013:86-92,
migration 0022:220-222). Foreign keys tie every row back to real registry
rows or real `auth.users` accounts, with cascades chosen per relationship
(`on delete cascade` for creators, `set null` for soft references).

What happens internally is the point a judge should hear: an invalid row
is rejected by the database no matter who sent it — the app, the teacher
dashboard, or the service-role Edge Function path all face the same
constraints. Integrity does not depend on every client remembering to
validate; it depends on one schema.

## 28.2 Source keys: one identity per Classroom item

Imported activities carry an external identity that the database enforces
as unique. Two indexes on `activity_sources` do the work:

```sql
create unique index if not exists activity_sources_source_key_key
  on public.activity_sources (source_key) where source_key is not null;
create unique index if not exists activity_sources_provider_external_key
  on public.activity_sources (provider, external_course_id, external_item_id)
  where external_item_id is not null;
```

(Evidence: migration 000200, `activity_sources` indexes :69-73.) The
`source_key` takes the form `google_classroom:{courseId}:{courseWorkId}`
or `google_classroom_announcement:{courseId}:{announcementId}`, and the
composite index on `(provider, external_course_id, external_item_id)`
stands as a second guard against the same provider item entering twice
under a different path. A third key sits one table up: `courses.
external_course_id` has its own partial unique index, making a Google
Classroom course id a one-to-one link to exactly one course row
(migration 0022:40-43).

Both indexes are partial — `where source_key is not null` — because manual
and student-reported activities have no external identity, and the
predicate is not cosmetic: the atomic upsert described next has a conflict
arbiter that must name the partial-index predicate exactly (FACTBASE §11).
Chapter 14 walks the full dedup design; here the relevant fact is that
uniqueness is an index property, enforced on every insert regardless of
caller.

## 28.3 Idempotency: retries converge instead of duplicating

Every network-shaped operation in the import pipeline is safe to run
twice. The core is `upsert_activity_from_source`, the service-only RPC
the `classroom-sync` Edge Function calls for each Classroom item: it
looks up the row by `source_key`, and either UPDATEs the canonical
activity — refreshing title, description, due date, and scope while
preserving a teacher-locked category — or INSERTs the activity and its
source row on first sight (migration 0023:113-168). The atomic form this
implies was verified directly: the retry-safe upsert `ON CONFLICT
(source_key) WHERE source_key IS NOT NULL DO UPDATE` requires the
partial-index predicate, and the test that proves it,
`gc_source_identity_test.sql`, PASSED in the 2026-10-30 run (FACTBASE
§11, §15). A repeated sync therefore refreshes the same shared row; it
can never create a second one.

Concurrency is handled with advisory locks rather than hope. Inside
`import_student_classroom_courses`, each Classroom course is serialized
with `perform pg_catalog.pg_advisory_xact_lock(
pg_catalog.hashtext('gc-course:' || v_ext))` and each target section with
a `gc-section:` lock (migration 0022:114-115 and :193-194). The loop
processes courses in a deterministic order — "Sorted by UPPER-CASED name:
deterministic order (same input = same result) AND a global lock order,
so two concurrent imports sharing courses can never deadlock on the
advisory locks below" (migration 0022:82-84) — and creation races that
slip past the lock are caught by `unique_violation` handlers that re-find
whichever row won (migration 0022:155-168, :201-213).

The same idempotency discipline appears wherever state is granted: role
inserts use `on conflict (user_id, role) do nothing` (migration 0013:67-69,
migration 0031:82-84), enrollment inserts use `on conflict (section_id,
user_id) do nothing`, and the Edge Function's re-import of the same
courses reports `enrolled=0` with everything moved to `matched`
(`tests/rpc_authorization_test.sql`, T08's idempotent re-run assertion
:237-255). This is why the auto-sync design of Chapter 15 can afford to
run "on EVERY app open" without a throttle window: an extra run always
converges the data instead of duplicating it (ClassroomAutoSync.kt
documentation block :34-39).

## 28.4 Error handling: loud where a human acts, quiet where nobody watches

The project's error policy splits cleanly along the line of user
attention. Where a student is looking at a screen, failures are loud and
actionable: the Beacon performs a one-shot load that publishes an Error
state with a retry button, and `retry()` simply re-runs the load
(BeaconViewModel.kt:108-120). Where nobody is watching — tab resumes and
background syncs — failures are silent by design: the on-resume refresh
"keeps the current content while fetching (no skeleton flash), and on
failure keeps whatever is on screen" (BeaconViewModel.kt:122-141). The
auto-sync path goes further and never throws at all: every step is
wrapped, an `AtomicBoolean` guards against overlapping runs, and every
skip condition — toggle off, not connected, a run already in flight,
Google needing interactive consent — returns null instead of raising
(ClassroomAutoSync.kt:60-90). The next app open is the retry.

The Edge Functions follow a skip-and-report discipline rather than a
fail-and-retry one. `classroom-sync` never force-creates anything: a
Classroom course with no matching local course is skipped with the reason
"no matching course code in your subjects", coursework the current scopes
cannot read is skipped with its own reason, and the final response is a
summary object — `status`, `imported`, `updated`, `classesTotal`,
`matchedClasses`, `skippedClasses`, `skippedCoursework`, `syncedAt` —
while the `google_connections` registry records `ok`/`partial`/`failed`
with a truncated error string for the Settings connection card
(`supabase/functions/classroom-sync/index.ts:166-184`, `:287-299`,
`:367-402`). Database-side, guard triggers convert policy violations into
exceptions with messages a human can act on, raising P0001 with text such
as `verification_status 'imported' is reserved for the sync service`
(migration 000200, `guard_activity_insert` :196-197; re-asserted in
migration 0015:85-95) or `SCHOOL_EMAIL_REQUIRED: ...` (migration 0031).
The one known mismatch in this area is a test-expectation artifact, not a
behavior gap: policies_test T08.1 expects SQLSTATE 42501 where the guard
deliberately raises P0001 (FACTBASE §15; roadmap M1.2).

## 28.5 Soft deletion: entries retire, they do not vanish

Deletion is a data-integrity decision, and Student Codex chose the
auditable one. Activities carry a nullable `deleted_at` column (migration
000200), the hot path indexes are partial over live rows
(`activities_due_at_idx ... where deleted_at is null`), and the current
select policy hides soft-deleted rows from everyone except their creator:

```sql
(deleted_at is null or created_by_user_id = auth.uid())
```

(Evidence: migration 0019, `activities_select`, first clause; the policy's
own comment explains that for UPDATE the SELECT policy's USING becomes a
WITH CHECK on the new row, which is exactly why the creator exception
exists — authors may soft-delete their own activities while everyone
else, and every feed, stops seeing the row.) The app implements deletion
as an update that stamps the timestamp — "Soft delete: the row gets
deleted_at and disappears from feeds" (SupabaseActivityRepository.kt:128-131)
— and its queries filter `deleted_at is null` up front
(SupabaseActivityRepository.kt:54). The dashboard's matching philosophy is
"past due = done": entries gray out the day after their due date and are
never deleted (`WebView/README.md`, "Past due = done" bullet). Creator-only
resurrection is thus a deliberate visibility rule: only the row's author
ever sees a deleted row again, and only through their own session.

## 28.6 Activity provenance: every row says where it came from

Integrity includes honesty about origin. Each activity carries a
`verification_status` — `imported`, `teacher-confirmed`,
`student-reported`, `needs-review` — and the app resolves the display
label from the row itself, never from client-side guesswork: an embedded
`activity_sources` array containing a `google_classroom` provider marks
the activity as Classroom-imported, otherwise a `student-reported`
status maps to the student-report source and everything else is manual
(SupabaseActivityRepository.kt:203-213). The labels are guarded, not
cosmetic: the insert guard reserves `imported` for the sync service and
requires `teacher-confirmed` to be set by a teacher of that
section/course or an admin, while a section-scoped `student-reported` row
requires its creator to be enrolled in that section (migration 0015,
`guard_activity_insert` :85-107). A student cannot relabel their report as
teacher-confirmed; a teacher cannot file a fake student report.

Provenance also survives time. A teacher's category correction is stamped
into `category_locked` / `category_locked_by` and every later re-sync
refreshes content but leaves the locked category alone (migration 0023;
Chapter 18), so the label and the correction together form a durable
audit trail of who decided what. On the read side the dashboard and the
app render these origins as distinct badges (Chapter 8; Chapter 16),
which is what makes the "recorded" data interpretable rather than merely
present.

## 28.7 Shared records: convergence, not duplication

The Classroom import is designed around one canonical row per real-world
item. Because Classroom course and coursework ids are shared across all
enrolled students, the unique `source_key` makes Student B's sync of what
Student A already synced an UPDATE of the same shared activity row —
"Classmates importing the same course converge on the same course +
section rows" (migration 0022, header :28-30), and repeated sync attempts
never equal duplicate records (FACTBASE §11; verified by
`gc_source_identity_test.sql`). The advisory locks of §28.3 are what make
that convergence safe under concurrency instead of merely likely.

Two properties follow. Freshness is shared too: any one student's
successful sync updates the row every other student sees. And the
convergence is bounded by the matching tiers — exact `external_course_id`
link, normalized name, then course creation (Chapter 13) — so rows merge
by identity or name, never silently. Chapter 14 covers the name tiers'
failure modes; the integrity mechanism itself is the unique key plus the
lock, and both are engine-enforced.

## 28.8 Synchronization limitations: client-triggered only

The sync model is deliberately pull-based. Synchronization happens in
exactly three situations: the opt-in auto-sync on app open, the manual
"Sync now" button, and the import picker (FACTBASE §11). There is no
background service, no WorkManager, no FCM push, and no Pub/Sub
integration — grep-verified with zero matches across functions and
migrations — so the system cannot know about a Classroom change until a
client asks. The direct consequence is a freshness limitation that must
be stated plainly: if a teacher edits a deadline in Google Classroom and
no student syncs, the edit is NOT reflected in Student Codex until the
next successful sync (FACTBASE §11; Chapter 15 documents the model and
the future event-driven alternative, roadmap M4.1).

Auto-sync softens but does not remove this: it runs on every app
start/return from background when enabled, pinned to the connected
account, and skips without error when Google would need a new consent
sheet (ClassroomAutoSync.kt; StudentCodexApp.kt:215-234 per FACTBASE §6);
the Beacon's on-resume refresh then surfaces whatever it brought in
(BeaconViewModel.kt:122-141). The honest statement: freshness is bounded
by student behavior, and every mechanism that would improve it
automatically is future work, not shipped behavior.

## 28.9 Manual reporting limitations: no duplicate detection

Manual entry is where the guarantees stop. Verified on 2026-11-01: the
Android app contains NO duplicate-checking prompt and no
similarity/matching logic for manual reports — BeaconScreen.kt and
BeaconViewModel.kt have no such code (grep-verified, FACTBASE §8). Two
students reporting the same face-to-face board announcement therefore
create two separate section-scoped rows, both labeled `student-reported`,
both visible. The title-token logic that exists in the database
(`suggest_activity_category`) only suggests a tracking category; it is a
classifier, not a deduplicator (migration 0023; Chapter 14).

This is a KNOWN LIMITATION, stated rather than hidden, and it compounds
with the coverage limitation: the dashboard and Beacon show recorded
information only, with no guarantee that all real-world university
activities have been entered (FACTBASE §12; Chapter 17). The Guidance
assistant's canned text that Student Codex "will ask whether it is the
same one before saving" overstates the app's behavior — a canned-text
drift documented in the fact base (§8) and surfaced in Chapter 10 as an
honesty point, not repeated here as fact.

## 28.10 The two lists

The chapter's contract, in quotable form. Every guarantee below is
enforced by a database object or a tested mechanism cited above; every
non-guarantee is a documented limitation, not an undiscovered bug.

What the system guarantees:

- Imported items never duplicate: unique `source_key` plus atomic
  retry-safe upsert; re-syncs UPDATE the shared row (migrations 000200,
  0023; `gc_source_identity_test.sql`).
- Referential and shape integrity: FKs, NOT NULLs, CHECKs, uniques
  reject invalid rows at the engine level (migrations 000000, 000200).
- Deletion is soft: `deleted_at` retires rows; only the creator still
  sees them (migration 0019; SupabaseActivityRepository.kt:128-131).
- Provenance is durable and guarded: origin labels cannot be forged by
  students, and teacher category corrections survive re-syncs
  (`category_locked`, migration 0023).
- One canonical row per Classroom item: classmates converge on shared
  course, section, and activity rows under advisory locks (migration 0022).
- Import and enrollment are idempotent: ON CONFLICT folding, advisory
  locks, deterministic ordering — retries are safe (migrations 0013,
  0022, 0023; T08 re-run assertion).
- Client tables are all RLS-gated and rate-guarded; failures degrade
  instead of crashing (Chapters 25 and 9; ClassroomAutoSync.kt).

What the system cannot guarantee:

- Complete real-world activity coverage — recorded data depends on
  students and teachers recording or importing it (Chapter 17).
- Freshness of Classroom changes until the next successful sync; sync is
  client-triggered only (Chapter 15).
- Correctness or completeness of manual student reports, or freedom from
  duplicate manual entries — no similarity detection exists (§28.9).
- Offline writes of any kind — the app is online-first and connectivity
  is required (roadmap M3.1 is the future offline cache).
- A production data set: demo seed data lives on the hosted project, and
  production data decisions are pending (roadmap M5.3).

## 28.11 Defense answer

> NOTE: "Reliability here means the data cannot quietly rot. The database
> enforces identity, shape, and referential integrity itself; imports are
> idempotent by unique source keys and advisory locks, so retries and
> concurrent classmates converge on one shared row instead of duplicating;
> deletion is soft and provenance labels are guarded so every row still
> says where it came from. What we do not guarantee we say out loud:
> coverage depends on people recording, freshness depends on someone
> syncing, and manual reports are not deduplicated."

Read with Chapter 27, the pair closes Part VII: the security chapters
establish who may touch the data, and this chapter establishes that what
they touch cannot corrupt the record.

---


# Chapter 29 — Complete Capability Matrix

This chapter is the exhaustive inventory of what Student Codex does and does not
do as of the verification date 2026-11-01. Every user-facing feature and every
backend capability with evidence in the verified fact base appears as a row in
the matrix in Section 29.2, with its actual capability, its verbatim status
label, its evidence, and its limitation. The matrix expands the 30-row verified
feature inventory (PLAN.md v2.2 §1.2, re-verified against the repository on
2026-11-01) and adds five backend capability rows the inventory implies:
row-level security on every client-exposed table, the three Edge Functions,
the private Storage bucket, the 33 versioned migrations, and the demo seed
data — while the inventory's own backend-adjacent rows (the F1/F2/F3 RPC
hardening and the public site pages) carry over unchanged.

This chapter deliberately overlaps its neighbors at a different angle. Chapter
2 maps problems to shipped solutions; this chapter catalogs capability by
module. Chapter 30 devotes a full section to each limitation compressed here
into one cell, and Chapter 31 turns the unfinished rows into a prioritized
roadmap. The matrix is the layer between them: the place where a reader can
see, in one pass, both the product that works and the work that remains.
Unfinished rows are not hidden — every `PARTIALLY IMPLEMENTED`, `PLANNED`, and
`DEFERRED` row stays in the table, because a capability matrix that omits its
gaps is a marketing document, not documentation.

Three rules governed the writing. Status labels are the project's seven labels,
used verbatim, and no status is ever upgraded beyond its evidence. Evidence is
repo-relative — file paths, class and function names, migration numbers, and
test files — with the Kotlin root
`app/src/main/java/com/example/studentcodex/` abbreviated to `…/studentcodex/`
after first use. The Limitation column carries the honesty anchors wherever
they apply: migration 0032 is locally tested and NOT hosted-deployed; email
confirmation is OFF (test configuration); the school-email domain suffix is not
mailbox-ownership proof; the app is online-first; sync is client-triggered; the
Guidance assistant is deterministic, not an LLM; recorded activity is not
complete real-world coverage; and title matching does not deduplicate manual
entries.

The matrix was assembled from four evidence streams, and a reader who wants to
check a row can pick the matching stream. Feature rows come from the verified
inventory in PLAN.md v2.2 §1.2, which was itself re-verified against the
repository on 2026-11-01 (56 source files fetched fresh and anchor-checked).
Backend rows come from the 2026-10-31 full-repo audit
(`plan-push/evidence/AUDIT-EVIDENCE.md`) and the F1/F2/F3 verification review
(`plan-push/evidence/REVIEW-F1F2F3.md`). Dashboard behavior carries the
2026-10-28 live browser verification. Database-layer claims carry the
2026-10-30 local SQL test run. Where the streams disagree in scope — the SQL
run did not re-exercise the Edge Functions — the Limitation column says so
rather than smoothing the difference over.

## 29.1 How to read the matrix

Each row answers six questions at once. The Module column says which of the
four modules owns the capability — the Android student app, the teacher
dashboard, the public site, or the shared backend. The Feature column names
the capability the way the verified inventory names it, so a reader can trace
every row back to PLAN.md v2.2 §1.2 or to the fact base. Actual Capability
describes what the build does today in one clause, phrased so that it never
implies more than the evidence supports. Status carries one of the seven
labels, verbatim. Evidence points at the file, function, migration, or test
where the claim can be checked. Limitation states the honest boundary of the
row — the place where the capability stops, including every honesty anchor
that applies to it.

The distinction between the Status and Limitation columns is easiest to see in
one worked example. The Classroom coursework sync row is `BUILT & VERIFIED`
because it was verified live in the browser on 2026-10-28, and its Limitation
cell records that the Edge Functions were not re-exercised against real Google
OAuth in the 2026-10-30 SQL run. Nothing about the capability changed between
those dates; what changed is the kind of evidence available. A reader who
quotes the status without the limitation overstates the recency of the
verification, and a reader who quotes the limitation without the status
understates the capability — the two cells are one claim, split for scanning.

| Module | Code location | Shape |
|---|---|---|
| Android student app | `app/src/main/java/com/example/studentcodex/` | Kotlin + Jetpack Compose (Material 3), single Activity, manual DI |
| Teacher dashboard | `WebView/` | Vanilla HTML/CSS/JS, 6 files (4 authored + 2 vendored), no build step |
| Public site | `supabase/functions/site` | Deno Edge Function serving static HTML (home + privacy policy) |
| Backend database | `supabase/migrations/` | 33 versioned SQL migrations, 000000–003200; 23 tables |
| Edge Functions | `supabase/functions/` | 3 Deno functions: classroom-import, classroom-sync, site |
| Storage | bucket `community-images` | Private bucket + 4 storage policies (migration 000500) |

The seven status labels, and how this chapter reads each one:

| Status label | What it means in this matrix |
|---|---|
| `BUILT & VERIFIED` | Working and evidenced by a test, a live verification pass, or source inspection in the latest verification |
| `IMPLEMENTED — VERIFICATION INCOMPLETE` | Built and evidenced during development, but not re-exercised in the latest verification pass |
| `PARTIALLY IMPLEMENTED` | Part of the capability exists (often the UI or the database layer) and part does not |
| `PLANNED` | Designed or scaffolded only; no working client path exists |
| `DEFERRED` | Explicitly postponed; a placeholder may mark its place in the UI |
| `KNOWN LIMITATION` | A confirmed gap or boundary the team accepts and discloses |
| `UNRESOLVED` | An open decision with no settled answer |

Evidence conventions used throughout the table:

- Migration numbers refer to the 33 files in `supabase/migrations/`, numbered
  000000–003200. The hosted project has migrations through 0028 applied;
  0029–0032 exist locally only.
- Dashboard evidence cites `WebView/app.js` (2,477 lines, 87 functions),
  browser-verified 2026-10-28.
- SQL test evidence cites `rpc_authorization_test.sql`,
  `phase_completion_test.sql`, `gc_source_identity_test.sql`, and
  `policies_test.sql`, whose latest run was 2026-10-30 on a local PostgreSQL
  17.11 with a replicated Supabase platform surface (Docker unavailable).
- Where a status carries a caveat in the inventory (for example the Classroom
  sync row), the caveat is preserved in the Limitation column rather than
  dropped.

## 29.2 The capability matrix

The table is ordered by module, following the student's journey first
(authentication, Beacon, Classroom, community, guidance), then the teacher
dashboard, the public site, and the backend. The backend block holds six rows
— row-level security, the Edge Functions, storage, the migrations, the RPC
hardening, and the demo seed — which are capabilities the feature inventory
implies but does not list as user-facing features. The final three rows are
the deliberately unfinished set (offline, push, community UI), placed last so
that the matrix ends on its honest edge rather than on its strongest row.
Rows are never sorted by status: a reader scanning the top must not get the
impression that everything early is finished, and a reader scanning the
bottom must not treat the tail as a footnote.

| Module | Feature | Actual Capability | Status | Evidence | Limitation |
|---|---|---|---|---|---|
| Android app | Email/password authentication | Sign-in, sign-up, sign-out, session handling via Supabase Auth | `BUILT & VERIFIED` | Android auth gate; `…/data/auth/AuthRepository.kt` | Email confirmation OFF (test config) |
| Android app | Google Sign-In | Credential Manager picker → Google ID token → Supabase auth | `IMPLEMENTED — VERIFICATION INCOMPLETE` | `…/data/auth/AuthRepository.kt`; `GoogleAuthManager.kt` | Verified during development; not re-exercised in the 2026-10-30 pass |
| Android app | Guest/demo mode | "Explore as guest" reads demo content, cannot write | `BUILT & VERIFIED` | `AuthGateScreen.kt` | Guests cannot write to community or Beacon |
| Android app | Profile completion (Google-first accounts) | CompletingProfile gate before SignedIn | `BUILT & VERIFIED` | `AuthGateScreen.kt:413`; `ProfileCompletionScreen.kt` | Google-first accounts must complete school details first |
| Android app | School registry dropdowns | Campus → program → year → section, multi-select class groups | `BUILT & VERIFIED` | Sign-up form; migration 000700 lookup tables | Registry limited to seeded ParSU data (50 programs) |
| Android app | Course enrollment by name | Self-service course creation with fuzzy matching tier | `BUILT & VERIFIED` | `enroll_student_courses` RPC (0017/0018/0027) | 32-code cap; invoked from sign-up/profile triggers only |
| Android app | Manual activity creation | Instant section publish, no approval queue | `BUILT & VERIFIED` | migration 0015 | Editor has no effort field; effort renders only on imported rows |
| Android app | Student-reported section activities | Real `activities` rows with verification_status student-reported | `BUILT & VERIFIED` | `…/data/repo/SupabaseActivityRepository.kt` | No duplicate detection; two students reporting one activity create two rows |
| Android app | Beacon list, filters, detail sheet | Date grouping, filters incl. Classroom-only, full-content sheet | `BUILT & VERIFIED` | `BeaconScreen.kt`; `ActivityDetailSheet.kt`; `BeaconViewModel.kt:123-131` | One-shot load + silent refresh on tab resume; no pull-to-refresh |
| Android app | Soft delete of own activities | `deleted_at` tombstone; RLS hides deleted rows from others | `BUILT & VERIFIED` | `activities.deleted_at` | UI offers edit/delete only for own manual personal rows |
| Android app | Import dedup + classification | Source-key upsert; title-token category suggestion | `BUILT & VERIFIED` | `upsert_activity_from_source`; `gc_source_identity_test.sql` | Dedups Classroom imports only; manual entries are NOT deduped |
| Android app | Classroom course import | Course picker at sign-up and Settings; server-side re-fetch | `BUILT & VERIFIED` | `supabase/functions/classroom-import`; `…/SupabaseClassroomImportRepository.kt` | list action deployed --no-verify-jwt (lists only, grants nothing) |
| Android app | Classroom coursework/announcement sync | Linked courses imported read-only as 'imported' activities | `BUILT & VERIFIED` | `supabase/functions/classroom-sync` (405 lines) | Edge Functions not re-exercised against real Google OAuth in the 2026-10-30 SQL run |
| Android app | Classroom auto-sync on app open | Opt-in ON_START observer, silent token, never throws | `BUILT & VERIFIED` | `…/ui/StudentCodexApp.kt:215-234`; `…/data/repo/ClassroomAutoSync.kt` | NOT a background service; no WorkManager/FCM (grep: 0) |
| Android app | Community feed, posts, likes | Text + one image posts; likes; anonymity-safe feed views | `BUILT & VERIFIED` | `…/data/repo/SupabaseCommunityRepository.kt` | One image per post in the app; schema allows 3 |
| Android app | Comments | Flat comment list per post | `PARTIALLY IMPLEMENTED` | `…/domain/model/Community.kt` (flat Comment model) | DB supports depth-5 nesting; no reply UI |
| Android app | Anonymous posting | Composer switch present in the UI | `PARTIALLY IMPLEMENTED` | `SupabaseCommunityRepository.kt:149` | Flag dropped; `is_anonymous` hard-wired false (comments likewise :110); DB/views support anonymity |
| Android app | Post reporting | 5 fixed reasons → `content_reports` with triage fields | `BUILT & VERIFIED` | `content_reports` (migration 000400) | DB level only; no moderator UI anywhere |
| Android app | Community image storage | Private bucket, own-folder layout, authenticated access | `BUILT & VERIFIED` | migration 000500; bucket `community-images` | Authenticated uploads/downloads only; images stored at position 1 |
| Android app | Guidance assistant | 6 keyword rules with precedence; honest fallback | `BUILT & VERIFIED` | `…/domain/guidance/GuidanceEngine.kt` (134 lines) | Deterministic, not an LLM; no context beyond the visible transcript |
| Android app | Floating assistant overlay | Draggable chat head / edge panel; mode persisted | `BUILT & VERIFIED` | `GuidanceOverlay` | None recorded |
| Teacher dashboard | Dashboard core | Sign-in/up, cohort filters, month calendar, detail sheets, corrections | `BUILT & VERIFIED` | `WebView/app.js` | Browser-verified 2026-10-28; vanilla JS, no framework, no build step |
| Teacher dashboard | Teacher registration domain gate | @parsu.edu.ph server-side check inside gated RPCs | `BUILT & VERIFIED` | migration 0031; SQL-tested T09/T10 | Suffix proves eligibility, NOT mailbox ownership; email confirmation OFF |
| Teacher dashboard | Student-reported feed + coverage card | Read-only reported feed; data-source coverage card | `BUILT & VERIFIED` | `WebView/app.js:1355-1410` | Coverage card reflects recorded data only (recorded ≠ complete) |
| Teacher dashboard | Workload analytics, proposed-deadline preview | DB view computes per-section/per-day counts + effort | `PLANNED` | view `section_workload_daily` (migration 000800) | No client consumes the view; no analytics or preview UI |
| Public site | Home page + privacy policy | Static HTML at /functions/v1/site[/home|/privacy] | `BUILT & VERIFIED` | `supabase/functions/site` (192 lines) | Deployed --no-verify-jwt; exists for OAuth consent-screen branding URLs |
| Backend | Row-level security | Policies on every client-exposed table; anonymous denied | `BUILT & VERIFIED` | policy blocks in migrations 000200/000300/0015/0019/0020/000500; policies_test T03 | policies_test.sql PARTIALLY PASSED — two stale fixture issues predating and unrelated to 0032 |
| Backend | Edge Functions (3) | classroom-import, classroom-sync, site | `BUILT & VERIFIED` | `supabase/functions/` | Classroom functions not re-exercised against real Google OAuth in the 2026-10-30 SQL run |
| Backend | Storage | One private bucket + 4 storage policies | `BUILT & VERIFIED` | migration 000500 | Private by design; no public uploads |
| Backend | Schema migrations (33) | Versioned DDL, 000000–003200 | `BUILT & VERIFIED` | `supabase/migrations/` | Hosted project has through 0028; 0029–0032 local-only |
| Backend | RPC EXECUTE hardening (F1/F2/F3) | Three REVOKEs close the SECURITY DEFINER doors | `IMPLEMENTED — VERIFICATION INCOMPLETE` | migration 0032 (:43-68); `rpc_authorization_test.sql` T01–T10 | Locally tested, NOT deployed to hosted; hosted ACL probes showed the RPCs still executable pre-0032 |
| Backend | Demo seed data | Fixed-UUID demo teacher/students/courses/activities/posts | `BUILT & VERIFIED` | migrations 0009/0010/0011 | Lives on the hosted project; production data decisions pending (M5.3) |
| Android app | Offline cache / outbox | Not built | `PLANNED` | `docs/OFFLINE-SYNC.md` (labeled future work) | Online-first; connectivity required except the on-device Guidance engine |
| Android app | Push notifications / reminders | Not built | `DEFERRED` | Settings placeholder row (`SettingsScreen.kt`) | No background sync, no push, no Pub/Sub (grep-verified 0) |
| Community + dashboard | Comment-likes UI, nested replies, moderation queue | Not built | `PLANNED` | — | DB already supports comment_likes, nested comments, content_reports triage |

## 29.3 What the totals say

| Status label | Rows | Reading |
|---|---|---|
| `BUILT & VERIFIED` | 27 | The working core of the product, spanning both clients and the backend |
| `IMPLEMENTED — VERIFICATION INCOMPLETE` | 2 | Google Sign-In and migration 0032 — built, evidenced during development, awaiting re-verification or deployment |
| `PARTIALLY IMPLEMENTED` | 2 | Comments and anonymous posting — the UI exists, the persistence or depth does not |
| `PLANNED` | 3 | Offline cache, workload analytics, and the community UI set — scaffolding or documents only |
| `DEFERRED` | 1 | Push notifications — explicitly postponed |

### The Android app

The Android app is the strongest module: its authentication and onboarding
chain, Beacon, Classroom integration, and Guidance overlay are all
`BUILT & VERIFIED`, and its two `PARTIALLY IMPLEMENTED` rows (comments,
anonymous posting) are narrow, precisely located gaps rather than broken
features — the database layer beneath both is complete. The Classroom block
is the deepest capability in the product: import, sync, and opt-in auto-sync
are each separately verified, and the auto-sync row's limitation states the
boundary that keeps it honest — it is an ON_START observer, not a background
service, and grep finds zero WorkManager or FCM usage.

### The teacher dashboard and the public site

The teacher dashboard is fully working for everything it shows, with its one
`PLANNED` row (workload analytics) representing value that exists only as a
database view. Its two judgment-sensitive rows carry their qualifications in
the Limitation column: the domain gate proves eligibility rather than
mailbox ownership, and the coverage card reflects recorded data rather than
complete real-world coverage. The public site row is small but real, and it
exists for a compliance reason: Google OAuth consent-screen verification
requires authorized-domain branding URLs, which the `site` Edge Function
serves.

### The backend

The backend rows tell the security and reliability story in miniature. RLS on
every client-exposed table, the three Edge Functions, the private Storage
bucket, and the 33 versioned migrations are `BUILT & VERIFIED`; the two
qualification-carrying rows in the whole matrix are Google Sign-In (client
side) and migration 0032 (server side). Migration 0032 deserves its exact
sentence every time it is mentioned: it is a pure privilege change, locally
tested with `rpc_authorization_test.sql` passing T01–T10, and NOT deployed
to the hosted project, which remains at 0028. The demo seed row is a
capability and a caveat at once — the seeds make the demo possible and they
live on the hosted project, which is why production data decisions are
roadmap item M5.3.

### The not-built rows

The four not-built rows close the matrix honestly. Offline cache is
`PLANNED` with design documentation only (`docs/OFFLINE-SYNC.md`, accurately
labeled as future work). Push notifications are `DEFERRED` with a Settings
placeholder marking the place. Workload analytics and the community UI set
are `PLANNED` with database scaffolding already in place — the view exists,
the nesting exists, the triage model exists — which means a future client has
something to consume, not that any client does today. The distinction between
scaffolding and capability is the whole point of keeping these rows visible:
one `PLANNED` row has a schema behind it and another has only a document, and
a reader deserves to see which is which.

## 29.4 Rows that need exact wording in defense

Six matrix rows attract judge attention disproportionate to their size, and
each has an exact sentence that keeps the answer inside the evidence. For the
Google Sign-In row: "It is implemented and was verified during development;
it was not re-exercised in the latest verification pass." For the Classroom
sync row: "The sync was verified live in the browser on 2026-10-28; the Edge
Functions were not re-exercised against real Google OAuth in the 2026-10-30
SQL run." For the RPC hardening row: "Migration 0032 is locally tested and
not deployed — the hosted project is at 0028, and deployment is roadmap item
M2.1." For the anonymous posting row: "The switch is UI-only; the flag is
dropped before the insert, so every post is saved with the author's name."
For the dedup row: "Deduplication is guaranteed for Classroom imports by the
unique source key, and it is not attempted for manual entries — two students
reporting the same activity create two rows." For the workload analytics
row: "The database view exists and computes the numbers; no client consumes
it yet, and building that client is roadmap item M3.2."

Two boundaries of the matrix itself must be stated. First, the matrix does
not describe repository hygiene — the uncommitted working tree, the two
commits, and the dead resource strings are environment facts, not
capabilities, and Chapter 30 gives each its own section. Second, the matrix
never describes the future: roadmap items appear only as limitation
cross-references (M2.1, M3.2, M5.3), and Chapter 31 is the only place where
future work is discussed as future work. A reader who quotes this chapter in
a Q&A is quoting the present, verified state — nothing more, nothing less.

## 29.5 Where each area is treated in depth

The matrix is one row per capability, which makes it scannable and makes it
shallow by design. The table below maps each area of the matrix to the
chapter that explains the mechanism in full, so a reader can move from "what
exists and at what status" to "how it actually works" without searching. The
mapping follows the chapter set as it exists: feature chapters 6 through 19
carry the mechanisms, and chapters 29 through 31 (this chapter and its two
neighbors) carry the inventory, the limitations, and the roadmap.

| Matrix area | Deep-dive chapter | What that chapter adds |
|---|---|---|
| Authentication and onboarding rows | Chapter 6 | The full gate flow, the sign-up trigger chain, profile completion |
| Beacon rows | Chapter 8 | List semantics, filters, editor fields, edit/delete affordances |
| Community rows | Chapter 9 | Posts, images, flat comments, the anonymous-flag path |
| Guidance rows | Chapter 10 | The six rules, precedence, the overlay, the canned-text drift |
| Profile and Settings surfaces | Chapter 11 | The Settings cards, the Classroom connect/sync/auto-sync controls |
| Classroom import, sync, auto-sync rows | Chapters 12 and 15 | The two Edge Functions end to end, the sync trigger model |
| Course matching and dedup rows | Chapters 13 and 14 | The three matching tiers, the source-key upsert in detail |
| Dashboard rows | Chapters 16 through 18 | Calendar rendering, cohort filters, category corrections |
| RLS, domain gate, RPC hardening rows | Chapter 19 | The authorization ladder and the publishable-key model |
| Limitation rows in full | Chapter 30 | One dedicated section per limitation, with judge visibility |
| Every roadmap cross-reference | Chapter 31 | Objective, current state, and missing work per milestone |

---


# Chapter 30 — Known Limitations

This chapter is the project's limitation ledger: every confirmed gap, boundary,
and stale verification state, each with its own section, stated as plainly as
the capabilities in Chapter 29. Nothing here is invented and nothing is
softened — every item traces to the verified fact base (re-verified
2026-11-01), and the single most cited gap, anonymous posting, leads the
chapter. The companion Chapter 31 maps each limitation that has one to a
roadmap milestone; this chapter explains the limitation itself: what is
missing, why it matters, what users actually experience, whether a judge can
see it during a competition demonstration, and the possible future solution.

One rule applies to every future-solution row in this chapter: all roadmap
items in PLAN.md v2.2 §10.3 are proposals. None is approved for
implementation, no dates are promised, and no milestone in this chapter should
be read as a commitment. Where a limitation has no dedicated roadmap
milestone, the section says so explicitly rather than borrowing a nearby one.

| # | Limitation | Judge visibility | Proposed fix |
|---|---|---|---|
| 1 | Anonymous posting not persisted | HIGH | M1.1 |
| 2 | Flat comments in the app | LOW | M3.4 |
| 3 | One image per post | LOW-MEDIUM | M3.4 |
| 4 | No effort field in the manual editor | LOW | No dedicated milestone |
| 5 | No offline cache or outbox | HIGH (if network fails) | M3.1 |
| 6 | No background sync or push notifications | MEDIUM | M3.5, M4.1 |
| 7 | No duplicate detection for manual entries | HIGH (in a two-student demo) | No dedicated milestone |
| 8 | Workload analytics not built | MEDIUM | M3.2 |
| 9 | No moderator UI | LOW | M3.3 |
| 10 | No pull-to-refresh | LOW | No dedicated milestone |
| 11 | Calendar coverage not guaranteed | MEDIUM-HIGH | Inherent boundary |
| 12 | Google-first accounts need profile completion | LOW | By design |
| 13 | Google Sign-In verification stale | MEDIUM | M1.4 |
| 14 | Edge Functions not re-exercised vs real OAuth | MEDIUM-HIGH | M1.5 |
| 15 | Migration 0032 locally tested, not hosted-deployed | HIGH (security Q&A) | M2.1, M2.2 |
| 16 | Email confirmation OFF | MEDIUM | M2.3 |
| 17 | Domain suffix is not mailbox ownership | MEDIUM | M2.3 |
| 18 | Test fixtures stale | LOW direct, HIGH for test claims | M1.2, M1.3 |
| 19 | Uncommitted working tree | MEDIUM (repo inspection) | M2.4 |
| 20 | Demo seed data on the hosted project | HIGH (by design) | M5.3 |
| 21 | Dead resources in code and styles | LOW | Closest: M2.4 |

## 30.1 App behavior gaps

The five limitations in this group are places where the shipped app does less
than its UI or its schema suggests — the gaps most likely to surface in
unguided hands-on exploration, which is exactly why they are volunteered
first: a judge who finds a gap the team did not mention trusts the team less
on everything else. None of the five is a data-loss or security issue; all
five are honesty issues with precise evidence locations.

### Anonymous posting is not persisted

The composer offers an anonymous switch, but the flag never reaches the
database: `CommunityViewModel.kt:166` drops it and
`SupabaseCommunityRepository.kt:149` hard-wires `is_anonymous=false` on every
post insert — comments likewise at `:110`; the switch itself lives at
`CommunityScreen.kt:347-360`. The asymmetry is stark because the server side
is ready: the `posts` table has the column, the feed views null the author
server-side, and the demo seeds include anonymous rows.

| Aspect | Detail |
|---|---|
| What is missing | Wiring the composer flag through the ViewModel into the insert — or removing the switch |
| Why it matters | The UI promises a privacy feature the product does not deliver; this is the most cited gap in the documentation |
| What users see | Toggle the switch, post, and the post appears with the author's name anyway |
| Demo visibility | HIGH — one tap exposes it; any judge exploring the community feed can hit it |
| Future solution | M1.1 (wire-or-remove) — proposed, not approved |
| Status today | `PARTIALLY IMPLEMENTED` |

### Comments are flat in the app

The app renders one flat comment list per post. The database supports
depth-5 nested replies (`comments.parent_id` self-reference), but the app's
`domain/model/Community.kt` models a flat Comment and no reply UI exists.

| Aspect | Detail |
|---|---|
| What is missing | A reply affordance and threaded rendering in the app |
| Why it matters | A schema capability sits unused; threaded discussion cannot form |
| What users see | A single-level list under each post with no reply button |
| Demo visibility | LOW — visible only if a judge specifically looks for threading |
| Future solution | M3.4 (community completeness) — proposed, not approved |
| Status today | `PARTIALLY IMPLEMENTED` |

### One image per post

The app attaches at most one image per post; the schema allows up to 3
(`post_images` ≤3). The Guidance assistant's canned answer ("up to three
images") describes the schema ceiling, not the app's writes — a known
canned-text drift.

| Aspect | Detail |
|---|---|
| What is missing | A multi-image attach flow in the composer (schema already supports 3) |
| Why it matters | Gap between what the canned text says and what the app does; under-used schema |
| What users see | One image attach control per post |
| Demo visibility | LOW-MEDIUM — only if a judge tries to attach a second image or quotes the assistant |
| Future solution | M3.4 (community completeness) — proposed, not approved |
| Status today | Feature `BUILT & VERIFIED`; image count is a `KNOWN LIMITATION` |

### No effort field in the manual editor

The Beacon editor collects title, notes, type (category), due date, and
course — no effort field. `effort_minutes` renders only on imported rows,
which means every manually created or student-reported row carries no effort
data.

| Aspect | Detail |
|---|---|
| What is missing | An effort input in the editor and persistence to `effort_minutes` |
| Why it matters | Manual rows lack effort data, so any future workload total under-counts them |
| What users see | No effort input; effort renders only on imported Classroom rows |
| Demo visibility | LOW — a detail a careful judge may notice on the detail sheet |
| Future solution | No dedicated milestone in PLAN.md v2.2 §10.3; M3.2 would consume the data once built — any fix is proposal-level only |
| Status today | `KNOWN LIMITATION` |

### No pull-to-refresh

The Beacon loads once and silently refreshes when the tab resumes
(`BeaconViewModel.kt:123-131`), keeping the current list on screen during the
fetch. There is no pull-to-refresh gesture anywhere in the app.

| Aspect | Detail |
|---|---|
| What is missing | A pull-to-refresh gesture on the list screens |
| Why it matters | Freshness depends on tab switches rather than an explicit, discoverable action |
| What users see | Swiping down does nothing; switching tabs or reopening the app refreshes |
| Demo visibility | LOW — judges familiar with mobile conventions may try it once |
| Future solution | No dedicated milestone in §10.3 — any fix is proposal-level only |
| Status today | `KNOWN LIMITATION` |

## 30.2 Connectivity and freshness

The three limitations in this group follow from one design decision:
Student Codex is online-first, and its Classroom synchronization is
client-triggered. The server holds the only copy of the truth and the client
holds almost nothing — the sole local persistence is SharedPreferences (the
session, the auto-sync toggle, the overlay preferences), and the only feature
that runs entirely on device is the deterministic Guidance engine.

### No offline cache or outbox

There is no Room cache and no WorkManager outbox; `docs/OFFLINE-SYNC.md`
describes the future design and is accurately labeled as unbuilt.

| Aspect | Detail |
|---|---|
| What is missing | Local persistence of activities and queued writes (Room + WorkManager per the design doc) |
| Why it matters | Online-first means connectivity is required for everything except the on-device Guidance engine |
| What users see | Any action without network fails with the app's error states |
| Demo visibility | HIGH if the demo venue network fails — every feature except Guidance stops |
| Future solution | M3.1 — proposed, not approved |
| Status today | `PLANNED` |

### No background sync or push notifications

Sync happens only when a client triggers it: app open (opt-in auto-sync via
ON_START, `StudentCodexApp.kt:215-234`), a manual "Sync now", or the import
picker. Grep across functions and migrations finds zero WorkManager, FCM, or
Pub/Sub usage.

| Aspect | Detail |
|---|---|
| What is missing | Server-initiated or OS-initiated refresh; notification delivery |
| Why it matters | A Classroom change (e.g. a deadline edit) is NOT reflected until the next successful sync |
| What users see | The student must open the app or press sync; nothing notifies them |
| Demo visibility | MEDIUM — the "will it notify me?" question must be answered with `DEFERRED` |
| Future solution | M3.5 (push notifications) and M4.1 (Pub/Sub event-driven sync, future only) — proposed, not approved |
| Status today | Push `DEFERRED`; sync triggers `BUILT & VERIFIED` |

### Calendar coverage is not guaranteed

The dashboard shows recorded information only. No mechanism guarantees that
all real-world university activities have been entered, and the dashboard
says so on its data-source coverage card (`WebView/app.js:1355-1410`).

| Aspect | Detail |
|---|---|
| What is missing | Nothing fixable — coverage depends on students and teachers recording or importing |
| Why it matters | Claiming a "complete university calendar" would be false; the coverage card exists to disclose it |
| What users see | A coverage card that separates Google Classroom imports from student reports |
| Demo visibility | MEDIUM-HIGH — judges may assume completeness; the team must say "recorded ≠ complete" |
| Future solution | No single milestone — this is an inherent product boundary, mitigated by the shipped coverage card |
| Status today | `KNOWN LIMITATION` |

## 30.3 Unbuilt product surfaces

The three limitations in this group share a shape: the database layer is
built, and no client surface consumes it — the clearest examples of the
project's honesty rule that scaffolding is not capability. Each has a
dedicated roadmap milestone, because finishing them is product work rather
than repair work.

### No duplicate detection for manual entries

Verified 2026-11-01: `BeaconScreen.kt` and `BeaconViewModel.kt` contain no
similarity or matching logic. Title-token logic exists only in the database
classifier `suggest_activity_category`, which suggests categories — it does
not deduplicate. The Guidance assistant's canned text ("Student Codex will
ask whether it is the same one before saving") overstates the app.

| Aspect | Detail |
|---|---|
| What is missing | Any duplicate check or merge prompt for manual/student-reported entries |
| Why it matters | Two students reporting the same face-to-face activity create TWO section rows; title matching does not guarantee manual dedup |
| What users see | Both rows on the Beacon and on the dashboard calendar |
| Demo visibility | HIGH if the demo shows two students reporting the same activity — the duplicate is on screen |
| Future solution | No dedicated milestone in §10.3 — any fix is proposal-level only |
| Status today | `KNOWN LIMITATION` |

### Workload analytics not built

The DB view `section_workload_daily` (security_invoker; per-section/per-day
activity_count and total_effort_minutes) exists from migration 000800, and
grep finds no client consuming it. Workload summaries, aggregate analytics,
and proposed-deadline preview are absent from `WebView/app.js`.

| Aspect | Detail |
|---|---|
| What is missing | Any dashboard panel that reads the view; the proposed-deadline preview |
| Why it matters | A headline teacher value proposition currently exists only as database scaffolding |
| What users see | Nothing — the dashboard has no analytics surface |
| Demo visibility | MEDIUM — if judges ask for analytics, the answer is "view exists, client not built" |
| Future solution | M3.2 — proposed, not approved; flagged as a competition-demonstration improvement |
| Status today | `PLANNED` |

### No moderator UI

`content_reports` (migration 000400) stores five fixed report reasons with
triage fields, and the moderator role exists in `user_roles`, but no queue UI
exists anywhere in either client.

| Aspect | Detail |
|---|---|
| What is missing | A moderation queue surface for moderators |
| Why it matters | The reporting pipeline dead-ends: reports are stored, nothing triages them |
| What users see | Report submission works; no visible follow-up |
| Demo visibility | LOW — surfaces only if a judge asks about moderation |
| Future solution | M3.3 — proposed, not approved |
| Status today | DB level `BUILT & VERIFIED`; UI `PLANNED` |

## 30.4 Verification gaps

The four limitations in this group are not missing features — they are stale
verification states and test debt, concerning things that were built and once
verified but whose latest verification either did not re-exercise them or
partially failed for reasons unrelated to the feature. Precision about these
rows is what separates an accurate test claim from a false one.

### Google Sign-In verification is stale

Google Sign-In (Credential Manager → Supabase ID token) is implemented in
`AuthRepository.kt` and was verified during development. It was not
re-exercised in the latest (2026-10-30) pass.

| Aspect | Detail |
|---|---|
| What is missing | A re-exercise of the Google sign-in path in the current build |
| Why it matters | If Google-side configuration drifted since development, the first failure would be live |
| What users see | Nothing — the flow either works or fails at sign-in |
| Demo visibility | MEDIUM — if it fails live, fall back to the documented email/password demo accounts |
| Future solution | M1.4 (Android current-build re-verification) — proposed, not approved |
| Status today | `IMPLEMENTED — VERIFICATION INCOMPLETE` |

### Edge Functions not re-exercised against real Google OAuth

The classroom-import and classroom-sync Edge Functions were live
browser-verified on 2026-10-28, but the 2026-10-30 run was a local SQL run —
the functions were not re-exercised against real Google OAuth then.

| Aspect | Detail |
|---|---|
| What is missing | A live OAuth re-verification pass of both Classroom Edge Functions |
| Why it matters | The Classroom demo path runs through these functions; consent or token-shape changes would surface only live |
| What users see | Nothing — the last live evidence is 2026-10-28 |
| Demo visibility | MEDIUM-HIGH — the Classroom segment of the demo depends on them |
| Future solution | M1.5 — proposed, not approved; flagged as a competition-demonstration improvement |
| Status today | `IMPLEMENTED — VERIFICATION INCOMPLETE` |

### Migration 0032 is locally tested, not hosted-deployed

Migration 0032 applies the F1/F2/F3 fixes — three REVOKEs closing the
`teacher_signup`, `import_student_classroom_courses`, and
`enroll_student_courses` EXECUTE doors for `authenticated` (:43-45, :47-49,
:51-53), with service-role grants re-asserted (:57-60). It passed
`rpc_authorization_test.sql` T01–T10 locally on 2026-10-30; the hosted
project has migrations through 0028 applied only.

| Aspect | Detail |
|---|---|
| What is missing | Deployment of 0029–0032 to the hosted project, then hosted re-verification |
| Why it matters | The fixes are NOT protecting the hosted project: hosted ACL probes (2026-10-29/30, non-mutating) showed the three RPCs still executable there |
| What users see | Nothing — it is a server-side privilege state |
| Demo visibility | HIGH in security Q&A — the exact sentence is "locally tested, not yet deployed" |
| Future solution | M2.1 (deploy 0029–0032) then M2.2 (post-deploy hosted verification) — proposed, not approved |
| Status today | `IMPLEMENTED — VERIFICATION INCOMPLETE` |

### Test fixtures are stale

In the 2026-10-30 local run, `policies_test.sql` PARTIALLY PASSED for two
known reasons: the programs fixture lacks `campus_id` (fails after migration
0012 made it NOT NULL), and T08.1 expects SQLSTATE 42501 while migration
0015's guard raises P0001. `gc_source_identity_test.sql` passed but needed a
temporary compatibility shim because its fixture predates 0012. A control
rebuild without 0032 reproduced the same failures — both issues predate and
are unrelated to 0032.

| Aspect | Detail |
|---|---|
| What is missing | Updated fixtures and corrected expectations in the two suites |
| Why it matters | "All tests pass" is false; the accurate claim is 3 passed (one with a shim), 1 partially, for documented fixture reasons |
| What users see | Nothing — test infrastructure only |
| Demo visibility | LOW direct — but HIGH for any Q&A answer about test results |
| Future solution | M1.2 (policies_test fixture + T08.1) and M1.3 (gc_source_identity_test fixture) — proposed, not approved |
| Status today | `KNOWN LIMITATION` |

## 30.5 Identity and configuration honesty

The three items in this group concern how strongly the project can claim a
registered account belongs to a real member of the university. The current
answer is deliberately weaker than production would require, and the
production-grade answer is an open decision (roadmap M2.3) rather than a
settled design — while one item, Google-first profile completion, is a
designed flow that behaves like a limitation in timing only.

### Google-first accounts need profile completion

A student who signs in with Google first lands in the CompletingProfile state
(`AuthGateScreen.kt:413`; `ProfileCompletionScreen.kt`) and must supply
school details before entering the app. The `handle_user_profile_sync`
trigger re-runs enrollment when metadata updates.

| Aspect | Detail |
|---|---|
| What is missing | Nothing broken — the extra step is required for enrollment and section visibility |
| Why it matters | Without campus/program/year/section data, RLS visibility and the Beacon cannot work |
| What users see | One extra screen after Google sign-up |
| Demo visibility | LOW — visible in the Google sign-up path; present it as deliberate |
| Future solution | No dedicated milestone — the flow is by design; M3.6 (profile editing) is adjacent but different |
| Status today | `BUILT & VERIFIED` |

### Email confirmation is OFF

`supabase/config.toml` sets `[auth.email] enable_confirmations = false` — a
testing configuration. Any address can register and act immediately. The
0028–0030 verification machinery (OTP-gated RPCs, email-click verification,
verified-email DB gate) remains in the schema as dormant fallback, and the
hosted rate limit is email_sent = 2/hour (dashboard-managed).

| Aspect | Detail |
|---|---|
| What is missing | Production confirmation configuration (a decision, not just a flag) |
| Why it matters | Account creation requires no mailbox at all today |
| What users see | Instant account activation with no confirmation email |
| Demo visibility | MEDIUM — visible whenever judges register a fresh account |
| Future solution | M2.3 (production teacher identity verification, decision needed) — proposed, not approved |
| Status today | `KNOWN LIMITATION` (test configuration) |

### Domain suffix is not mailbox ownership

The 0031 server-side gate checks that a teacher-registration email ends in
@parsu.edu.ph. That proves eligibility, NOT ownership: an address with the
right shape passes without anyone checking the mailbox.

| Aspect | Detail |
|---|---|
| What is missing | A proof that the registrant controls the mailbox (production identity verification) |
| Why it matters | Teacher registration's strength is eligibility filtering, not identity proof |
| What users see | Nothing — registration succeeds for any suffix-shaped address |
| Demo visibility | MEDIUM — answer honestly if asked how teacher identity is proven |
| Future solution | M2.3 — proposed, not approved |
| Status today | `KNOWN LIMITATION`; production identity verification `UNRESOLVED` |

## 30.6 Repository and data hygiene

The three items in this group concern the state of the code and the hosted
data rather than runtime behavior — invisible in a running demo, but fully
visible to a judge who inspects the repository or asks how the demo data came
to exist. They are also the items with the least glamorous fixes: committing,
cleaning, and deciding.

### The working tree is uncommitted

The repository has 2 commits total (`71e2661` initial import; `95e9b15`
auth-gate button tweak). The entire current product — the dashboard rework,
migrations 0021–0032, the classroom-import and site Edge Functions, four new
Kotlin files, and PLAN.md v2.2 — is uncommitted working-tree state, with a
59-entry `git status --porcelain` listing and roughly 90 root dev-script
debris files.

| Aspect | Detail |
|---|---|
| What is missing | Commits that capture the product, plus a .gitignore for the debris |
| Why it matters | No version history exists for most of the product; the working tree is the only copy |
| What users see | Nothing — repository state only |
| Demo visibility | MEDIUM if judges inspect the repository — the history shows almost nothing |
| Future solution | M2.4 — proposed, not approved |
| Status today | `KNOWN LIMITATION` |

### Demo seed data lives on the hosted project

Migrations 0009/0010/0011 seed fixed-UUID demo teacher, students, courses,
sections, enrollments, activities, and posts — and they are applied on the
hosted project, because hosted has migrations through 0028.

| Aspect | Detail |
|---|---|
| What is missing | A production data strategy (keep, split, or purge the demo identities) |
| Why it matters | The hosted database mixes demo identities with any real ones |
| What users see | Demo content appears as ordinary content — it IS the demo content |
| Demo visibility | HIGH by design — disclose it as seeded demo data, never as organic usage |
| Future solution | M5.3 (production data decisions) — proposed, not approved |
| Status today | `KNOWN LIMITATION` |

### Dead resources remain in the code

Three confirmed instances: the orphaned `profile_version_note` string (a
v2.1 footnote that is never rendered), the `comments_demo_note` string, and
legacy CSS classes in the dashboard stylesheet.

| Aspect | Detail |
|---|---|
| What is missing | Removal of the unused strings and classes |
| Why it matters | Dead code confuses readers and signals iteration history to inspectors |
| What users see | Nothing |
| Demo visibility | LOW — code inspection only |
| Future solution | Closest is M2.4 (repository hygiene); dead-resource cleanup is not an explicit roadmap line — proposal-level only |
| Status today | `KNOWN LIMITATION` |

## 30.7 Using this chapter in the defense

The order of operations in Q&A is the point of this chapter. When a question
touches one of these 21 items, name the limitation before characterizing the
capability: "Anonymous posting has a UI-only switch today — the flag is
dropped before the insert — and wiring or removing it is roadmap item M1.1."
That sentence pattern — limitation, evidence, milestone — answers the
question, proves the team knows its own system, and never promises that the
fix is done. The failure mode this chapter exists to prevent is the reverse
order: claiming the capability first and conceding the limitation only when
pressed, which reads as concealment even when it is not.

Three statements must never drift. Migration 0032 is locally tested and NOT
deployed to the hosted project. Email confirmation is OFF because this is a
test configuration, and the @parsu.edu.ph suffix proves eligibility, not
mailbox ownership. And the app is online-first with client-triggered sync —
no offline, no background refresh, no push — so freshness and availability
claims must be scoped exactly to what a client-triggered model delivers.
Every future-solution row above is a proposal; none of the 23 roadmap
milestones is approved work, and no dates are promised anywhere in this
documentation set.

---


# Chapter 31 — Future Development Roadmap

> WARNING: The roadmap below is a list of priorities, not commitments. Nothing
> in it is approved for implementation, no dates are promised, and no milestone
> should ever be presented as current capability. Every item is a proposal from
> PLAN.md v2.2 §10.3 (five tiers, 23 milestones), recorded here so the team can
> discuss the future honestly — and so no future item bleeds into a description
> of the present.

This chapter extracts the five-tier roadmap and reorganizes it for the reader
who asks "what happens next?". The five tiers in the source are: Tier 1
verification gaps, Tier 2 security and production-readiness, Tier 3 remaining
product functionality, Tier 4 reliability and integration, and Tier 5 release
preparation. This chapter keeps every milestone and every tier intact, but
groups them by the question a reader actually has: what must be re-verified
right now, what would strengthen the competition demonstration, what stands
between the current build and production, and what would make the product
better after that.

Every milestone entry states four things: its objective, the current state of
the related capability (with the project's verbatim status label), what is
missing to close it, and a flag saying whether it matters mainly for the
competition demonstration (Demo), for production readiness (Production), or
for future product value (Product). The flags are reading aids, not
classifications from the source: the same milestone can be both a
verification task and a demonstration improvement, and where that happens the
chapter says so explicitly rather than choosing one.

| ID | Milestone | Tier | Flag |
|---|---|---|---|
| M1.1 | Anonymous posting: wire or remove | Tier 1 | Demo + verification |
| M1.2 | policies_test fixture + T08.1 fix | Tier 1 | Verification |
| M1.3 | gc_source_identity_test fixture fix | Tier 1 | Verification |
| M1.4 | Android current-build visual re-verification | Tier 1 | Demo |
| M1.5 | Edge Function live-OAuth re-verification | Tier 1 | Demo |
| M2.1 | Deploy 0029–0032 to hosted | Tier 2 | Production |
| M2.2 | Post-deploy hosted verification of 0032 | Tier 2 | Production |
| M2.3 | Production teacher identity verification (decision) | Tier 2 | Production |
| M2.4 | Commit the working tree + .gitignore debris | Tier 2 | Production |
| M2.5 | Credential hygiene (client.json / .env) | Tier 2 | Production |
| M3.1 | Offline cache + write sync (Room/WorkManager) | Tier 3 | Product |
| M3.2 | Workload summaries + proposed-deadline preview | Tier 3 | Demo + product |
| M3.3 | Moderation queue UI | Tier 3 | Product |
| M3.4 | Community completeness | Tier 3 | Product |
| M3.5 | Push notifications | Tier 3 | Product |
| M3.6 | Profile editing | Tier 3 | Product |
| M4.1 | Classroom Pub/Sub event-driven sync (future only) | Tier 4 | Product |
| M4.2 | Android WebView embedding of the dashboard | Tier 4 | Product |
| M4.3 | Test-environment parity | Tier 4 | Production |
| M5.1 | Release engineering (signed APK) | Tier 5 | Production |
| M5.2 | OAuth consent-screen publishing | Tier 5 | Production |
| M5.3 | Production data decisions | Tier 5 | Production |
| M5.4 | Final acceptance run + documentation freeze (v2.3) | Tier 5 | Production |

## 31.1 Tier 1 — immediate verification tasks

Tier 1 exists because the latest verification pass (2026-10-30) was a local
SQL run: it re-proved the database layer, and it did not re-exercise the
Android build, the Google sign-in path, or the Edge Functions against real
Google OAuth. The tier's five milestones close that gap before anything else
is attempted, because every later claim inherits its credibility from these.
None of the five adds a new feature; four of them re-verify what exists, and
the fifth (M1.1) resolves a mismatch between what the UI promises and what
the app does.

| Milestone | Objective | Current state | What is missing | Flag |
|---|---|---|---|---|
| M1.1 | Wire the anonymous flag through to the insert, or remove the composer switch | `PARTIALLY IMPLEMENTED` — switch present, flag dropped (`SupabaseCommunityRepository.kt:149`) | The wiring decision and its implementation; DB/views already support anonymity | Demo + verification |
| M1.2 | Fix policies_test programs fixture (campus_id) and T08.1 expectation (P0001 vs 42501) | `KNOWN LIMITATION` — suite PARTIALLY PASSED for two documented reasons | Updated fixture rows and corrected SQLSTATE expectation | Verification |
| M1.3 | Update the gc_source_identity_test fixture to post-0012 shape | `KNOWN LIMITATION` — passed only with a temporary compatibility shim | A fixture that runs without the shim | Verification |
| M1.4 | Visually re-verify the current Android build end to end | Feature rows `BUILT & VERIFIED` from earlier passes; the current-build pass itself is outstanding | A fresh pass over the current build (covers Google Sign-In re-exercise) | Demo |
| M1.5 | Re-exercise both Classroom Edge Functions against real Google OAuth | `IMPLEMENTED — VERIFICATION INCOMPLETE` — live-verified 2026-10-28, not re-exercised 2026-10-30 | A live OAuth run of classroom-import and classroom-sync | Demo |

The two test-fixture milestones deserve their place in a verification tier
rather than a cleanup tier, because test results are claims. While M1.2 and
M1.3 remain open, the accurate statement of the 2026-10-30 run is: three
suites passed (one with a shim) and `policies_test.sql` partially passed for
fixture reasons that predate migration 0032 — a control rebuild reproduced
the same failures without it. Fixing the fixtures converts that sentence into
"all four suites pass", which is a materially stronger claim and the only
honest way to get there.

M1.4 and M1.5 carry a second rationale that is specific to a competition
context: they retire demonstration risk, not just documentation debt. The
riskiest moments in a live demonstration are the ones whose evidence is
oldest — the Google sign-in tap, and the consent-and-sync round trip through
the Edge Functions. A fresh visual pass over the current build (M1.4) and a
live OAuth re-run of both Classroom functions (M1.5) convert those moments
from "it worked on 2026-10-28" to "it worked this week", which is the
difference between citing evidence and hoping it still holds.

## 31.2 Competition-demonstration improvements

Three milestones are flagged Demo because completing them before a
competition demonstration changes what judges can see, not just what the
team can claim. M1.4 and M1.5 remove the two largest "it worked when we
built it" caveats from the demonstration's riskiest segments — the Android
build and the live Classroom sync. M3.2 is the one genuinely new surface on
the Demo list: building the workload summary client would let the
demonstration show the teacher value proposition that today exists only as
the `section_workload_daily` view.

| Milestone | What changes in the demo if done | Current state |
|---|---|---|
| M1.4 | The team demonstrates the current build with fresh visual evidence instead of citing earlier passes | Feature rows `BUILT & VERIFIED`; current-build pass outstanding |
| M1.5 | The live Classroom import and sync segments run on freshly re-verified Edge Functions | `IMPLEMENTED — VERIFICATION INCOMPLETE` |
| M3.2 | The dashboard gains workload summaries and a proposed-deadline preview; the DB view finally has a client | `PLANNED` — view exists (migration 000800), no client |

The Demo flag carries a caution in both directions. If these milestones are
done, they must be demoed as new work with its own verification story — not
folded silently into claims about the existing product. If they are not done,
the demonstration must not gesture at them as if they existed: the workload
answer stays "the view is built, the client is not", and the Classroom
segments are introduced with their 2026-10-28 verification date stated
plainly.

A visual re-verification pass under M1.4 has a concrete scope, because the
app's surfaces are enumerable: the auth gate states (CheckingSession,
SignedOut, CompletingProfile, SignedIn), the four top destinations (Home,
Beacon, Community, Settings), the pushed Profile route, the Beacon editor
and detail sheet, the Classroom import sheet, and the floating Guidance
overlay above every page (`…/ui/StudentCodexApp.kt`). A pass that exercises
each surface once, on the current build, is what upgrades the app's evidence
from "verified at earlier builds" to "verified now" — and it is also the
pass that would catch any regression hiding in the uncommitted working tree.

## 31.3 Production-readiness work

This section collects everything that stands between the current build and a
deployment the team would call production: the full Tier 2, plus the
production-flagged items from Tiers 4 and 5 (M4.3 test-environment parity,
and the Tier 5 release-preparation set M5.1–M5.4). The unifying theme is
that none of it adds user-facing value — it adds confidence, auditability,
and the right to make stronger claims than a hackathon build can make.

| Milestone | Objective | Current state | What is missing | Flag |
|---|---|---|---|---|
| M2.1 | Apply migrations 0029–0032 to the hosted project | `IMPLEMENTED — VERIFICATION INCOMPLETE` — 0032 locally tested; hosted at 0028 | The deployment itself | Production |
| M2.2 | Verify on the hosted project that the 0032 revokes hold | Depends on M2.1 | Post-deploy hosted ACL re-probing | Production |
| M2.3 | Decide and build production teacher identity verification | `UNRESOLVED` — email confirmation OFF (test config); suffix ≠ mailbox ownership | The decision, then the mechanism (dormant 0028–0030 machinery is fallback) | Production |
| M2.4 | Commit the working tree; .gitignore the ~90 debris files | `KNOWN LIMITATION` — 2 commits; the whole current product is uncommitted | The commits and the ignore rules | Production |
| M2.5 | Credential hygiene for client.json (live OAuth secret at repo root) and .env | `KNOWN LIMITATION` — flagged; .env never read | Secret rotation and removal from the tree | Production |
| M4.3 | Bring the local test environment to parity with the hosted platform | `KNOWN LIMITATION` — local PostgreSQL 17.11 with a replicated platform surface; Docker unavailable | A parity environment (would also carry M1.2/M1.3 fixtures) | Production |
| M5.1 | Release engineering: signed APK | `PLANNED` | Signing configuration and a release build | Production |
| M5.2 | Publish the OAuth consent screen | `PLANNED` — the `site` Edge Function already serves the required branding URLs | Consent-screen submission and verification | Production |
| M5.3 | Decide the fate of demo seed data on the hosted project | `KNOWN LIMITATION` — seeds applied on hosted (0009/0011) | Keep/split/purge decision and execution | Production |
| M5.4 | Final acceptance run; freeze documentation at v2.3 | `PLANNED` | The run itself and the freeze | Production |

Two dependencies inside this list are worth stating because judges ask about
order. M2.2 cannot start before M2.1 finishes — verifying a revoke that has
not been applied is meaningless. And M2.3 is a decision milestone, not a
build milestone: the 0028–0030 machinery (OTP-gated teacher RPCs, email-click
verification, verified-email DB gate) already exists in the schema as a
dormant fallback, so the work is choosing a production posture and enabling
it, not designing from zero. M2.5 exists because `client.json` at the repo
root holds a live OAuth client secret — flagged in the audit, treated as a
credential, and never reproduced in this documentation.

The remaining ordering facts are quieter but real. M4.3 (test-environment
parity) is the natural home for the M1.2 and M1.3 fixture work: a parity
environment is exactly where stale fixtures get rebuilt once, instead of
being patched per suite. M5.4 is the terminal milestone by definition — a
final acceptance run and a documentation freeze only mean something when
everything before them has settled, which is why it closes the roadmap
rather than appearing anywhere earlier. M5.2 has a prerequisite already
satisfied in the codebase: the `site` Edge Function serves the home page and
privacy policy that Google's consent-screen verification requires, so the
submission itself is the remaining work, not the branding.

## 31.4 Future product enhancements

This section holds the milestones that add user-facing value after — or
independently of — the verification and production tracks: the remaining
Tier 3 functionality and the Tier 4 integration work. All of Tier 5 is
collected under production-readiness in Section 31.3, so nothing is lost by
the regrouping. M3.2 appears in Section 31.2 with its Demo flag; it is
listed here only as a cross-reference so the Tier 3 set stays complete.

| Milestone | Objective | Current state | What is missing | Flag |
|---|---|---|---|---|
| M3.1 | Offline cache + write sync (Room + WorkManager per docs/OFFLINE-SYNC.md) | `PLANNED` — design document only | The entire client implementation | Product |
| M3.2 | Workload summaries + proposed-deadline preview (see Section 31.2) | `PLANNED` — view exists, no client | The dashboard client and preview UI | Demo + product |
| M3.3 | Moderation queue UI over content_reports | DB level `BUILT & VERIFIED`; UI `PLANNED` | The queue surface | Product |
| M3.4 | Community completeness: comment-likes UI, nested reply UI, remaining gaps | `PLANNED` — DB supports all three (comment_likes, depth-5 nesting, triage) | The UI work | Product |
| M3.5 | Push notifications and reminders | `DEFERRED` — Settings placeholder row marks the place | The notification pipeline | Product |
| M3.6 | Profile editing beyond the identity view | `PLANNED` — ProfileScreen is identity-only | Editable fields and persistence | Product |
| M4.1 | Classroom Pub/Sub event-driven sync | `DEFERRED` (future only) — sync is client-triggered today | Event infrastructure; explicitly future | Product |
| M4.2 | Android WebView embedding of the teacher dashboard | `PLANNED` — dashboard is browser-served | The embedded container | Product |

The order inside Tier 3 is a priority statement, not a schedule. M3.1 leads
because the absence of offline is the most consequential product gap
(Chapter 30, Section 30.2); M3.4 consolidates the small community gaps whose
database layers are already complete; M3.5 is last because it was explicitly
deferred and depends on infrastructure (a push pipeline) the project has
never had. M3.6 is the quietest item — ProfileScreen today displays identity
only (name, email, university, program, year), so profile editing would
close a gap users feel the first time a detail changes. M4.1 is marked
future-only in the source roadmap itself — event-driven sync would change
the freshness model from client-triggered to server-initiated, which is a
different architecture, not a patch. M4.2 is the only milestone that moves
existing capability rather than adding it: the dashboard already works in
the browser, and embedding it in an Android WebView would put the same
surface in a second client without rewriting either.

## 31.5 What the roadmap does not contain

Reading the roadmap's absences is as informative as reading its items, and
three absences are load-bearing. There is no milestone to make the Guidance
assistant an LLM — the engine is deterministic by design, and the roadmap
treats that as the product's identity rather than a deficit. There is no
milestone to deduplicate manual entries — Chapter 30 records that gap as a
`KNOWN LIMITATION` with no dedicated fix proposed, so any answer about it
must describe the present behavior, not promise a milestone. And there are
no dates, no effort estimates, and no approval anywhere in the five tiers —
the roadmap is a priority list that a future team could accept, reorder, or
reject wholesale.

The absence of committed dates deserves one more sentence, because it is the
most commonly probed. A roadmap without dates is not an incomplete roadmap
here; it is an honest one. The project's current state carries verification
dates (2026-10-28 for the browser pass, 2026-10-30 for the SQL run,
2026-11-01 for the fact-base re-verification), and those are the only dates
this documentation set stands behind.

## 31.6 How to talk about this roadmap

The roadmap's defense value is in what it says about the team's
self-knowledge, and the only way to keep that value is disciplined phrasing.
The pattern that works: name the current state with its verbatim label, then
name the milestone as a proposal. "Offline support is `PLANNED` — the design
document exists and M3.1 proposes building it" is a strong answer; "we're
adding offline soon" is an overclaim with a date attached. The blacklist in
Chapter 39 exists precisely because roadmap items are the easiest things to
accidentally present as current capability.

| If asked about | Say (label first, milestone second) |
|---|---|
| Offline support | "`PLANNED` — the design document exists; M3.1 proposes building it" |
| Notifications | "`DEFERRED` — a placeholder row marks it; M3.5 proposes the pipeline" |
| Workload analytics | "`PLANNED` — the DB view exists; M3.2 proposes the client" |
| Hosted hardening | "`IMPLEMENTED — VERIFICATION INCOMPLETE` — 0032 is locally tested; M2.1 proposes deploying it" |
| Teacher identity proof | "`UNRESOLVED` — the suffix gate exists (0031); M2.3 proposes the production decision" |
| Real-time Classroom updates | "Not current — sync is client-triggered; M4.1 is future-only" |

Three sentences close the chapter. Nothing in this roadmap is approved work;
the five tiers and 23 milestones are priorities recorded in PLAN.md v2.2
§10.3, and any of them could be re-ordered or dropped. No dates are promised
anywhere in this documentation set, because a hackathon team's calendar is
not a release plan. And the roadmap never changes the present: the verified
state of the product is exactly what Chapters 29 and 30 say it is, and it
stays that way until a milestone is implemented, verified, and re-documented.

---


# Chapter 37 — Technical Glossary

This glossary defines every technical term a judge, a new developer, or a
teammate from another discipline will meet in this documentation set. Each
entry has two deliberately separated parts: a plain-language definition that
stands on its own, and an "In Student Codex" definition that grounds the term
in this project — the file, function, table, or migration where it actually
appears. The second part is what makes the glossary usable in Q&A: a term
backed by a concrete repository location can be answered with evidence, while
a term answered from a textbook invites the follow-up "but where is that in
your system?". Entries are grouped by theme, and each cites its evidence the
same way the rest of the documentation does — repo-relative paths, with the
Kotlin root `app/src/main/java/com/example/studentcodex/` abbreviated to
`…/studentcodex/` after first use.

## 37.1 Product and protocol vocabulary

These seven terms describe the shape of the system and the protocols that
connect its parts. They are the vocabulary of the first five minutes of any
technical conversation about Student Codex — and the terms most likely to be
used imprecisely, which is why each entry pins the term to one meaning and
one place in the project.

### API

**Plain meaning.** An application programming interface is a defined set of
rules for how one program asks another to do something — which requests it
accepts, which data it expects, and which responses it returns.

**In Student Codex.** Two APIs matter. Supabase exposes the database through
the PostgREST API, so every table in the `public` schema becomes an HTTP
endpoint the clients call. Google exposes the Classroom REST API, which the
Edge Functions call server-side with the student's OAuth token.

### Backend

**Plain meaning.** The backend is the server-side part of a system: the
software that stores data, enforces rules, and does work the user's device
does not do itself.

**In Student Codex.** The backend is one hosted Supabase project shared by
both clients: Supabase Auth (GoTrue), PostgreSQL with row-level security
exposed through PostgREST, three Deno Edge Functions, and one private Storage
bucket — a single source of truth and one RLS rule set, with no
synchronization between two databases.

### Frontend

**Plain meaning.** The frontend is the part of a system the user sees and
touches — the interface that runs on the user's device and talks to the
backend.

**In Student Codex.** Two frontends share the backend. The student frontend
is the native Android app (Kotlin with Jetpack Compose, Material 3, single
Activity). The teacher frontend is the dashboard in `WebView/` — vanilla
HTML, CSS, and JavaScript with two vendored libraries, no framework and no
build step (`WebView/app.js`, 2,477 lines).

### REST API

**Plain meaning.** A REST API is an interface organized around resources,
where standard HTTP verbs (GET, POST, PATCH, DELETE) act on URLs that name
things, and responses carry the resource state.

**In Student Codex.** PostgREST maps the PostgreSQL schema to REST: the app's
supabase-kt client and the dashboard's vendored supabase-js both read and
write tables such as `activities` and `posts` with ordinary HTTP requests
that row-level security then filters per row. The Google Classroom API
consumed by the Edge Functions is also REST.

### OAuth

**Plain meaning.** OAuth is a standard for letting a user grant one
application limited access to their data on another service, without handing
over their password.

**In Student Codex.** Each student consents per Google account: the app
requests Classroom scopes (rosters and coursework, read-only) through the
on-device Authorization API, and the Edge Functions use the resulting token
to call Google. The OAuth client_id is a public identifier
(`supabase/config.toml`, `[auth.external.google]`); no client secret ships in
the app.

### Access token

**Plain meaning.** An access token is a short-lived credential presented to
an API to prove the request is authorized to act for a user.

**In Student Codex.** The Google access token is minted per sync, travels in
the request body to the `classroom-sync` Edge Function, and is transit-only —
never stored, no refresh tokens kept. Revoking Google access takes effect at
the next sync.

### JWT

**Plain meaning.** A JSON Web Token is a signed token that carries identity
claims (such as the user id) and can be verified without a database lookup.

**In Student Codex.** Supabase Auth issues a session JWT to each signed-in
client; PostgREST resolves it to `auth.uid()` for every RLS decision, and
both Classroom Edge Functions verify it server-side via /auth/v1/user before
doing privileged work (`classroom-import` :18; `classroom-sync` :48-59).
Token lifetime is one hour (`supabase/config.toml`, jwt_expiry 3600).

## 37.2 Architecture and code patterns

These three terms describe how the Android codebase is organized, and each
answers a specific objection: the repository pattern answers "what if you
change backends", and manual dependency injection answers "how do the pieces
get wired together".

### Repository pattern

**Plain meaning.** A repository is a class whose job is to hide where data
comes from: the rest of the code asks it for domain objects and never sees
the storage technology behind it.

**In Student Codex.** The interfaces live in `…/data/repo/Repositories.kt`
(ActivityRepository, CommunityRepository, ProfileRepository,
ContentReportRepository, and the Classroom repositories), and UI and
ViewModels depend only on those interfaces — they never see Supabase, HTTP,
or JSON rows, so swapping an implementation would not touch a single screen.

### Dependency injection

**Plain meaning.** Dependency injection means objects receive the
collaborators they need from outside instead of constructing them inside —
so wiring lives in one place and implementations can be swapped or faked in
tests.

**In Student Codex.** The app uses manual DI: `di/AppContainer.kt` builds
lazy singletons (supabaseClient, authRepository, the Classroom repositories,
the guidance engine, and the rest) and hands them to
`StudentCodexApp(container)` — "no DI framework for the MVP" (:36-38). The
unit tests under `app/src/test/java/com/example/studentcodex/` exploit
exactly this seam with fakes.

### Synchronization

**Plain meaning.** Synchronization is the process of keeping two systems'
views of the same data consistent — what is copied, when, and what happens
when the same thing changes in both places.

**In Student Codex.** Synchronization is client-triggered and one-directional
(read-only from Classroom): an app open with the opt-in auto-sync toggle
(`…/ui/StudentCodexApp.kt:215-234`), a manual "Sync now", or the import
picker starts it; the `classroom-sync` Edge Function then upserts coursework
and announcements into the shared `activities` table. There is no background
sync, no push, and no Pub/Sub — a Classroom change waits for the next
successful sync.

## 37.3 Security vocabulary

These four terms carry the project's security story, and they are the terms
most often conflated by questioners. The distinctions are load-bearing:
signing in is not being a teacher, and a public key is not a vulnerability
when row-level security decides every row.

### Authentication

**Plain meaning.** Authentication is answering "who is this?" — proving a
request comes from a particular account.

**In Student Codex.** Supabase Auth (GoTrue) handles it: email/password
sign-in, or a Google ID token from Credential Manager exchanged for a
Supabase session. Guests authenticate as nobody — they read demo content and
cannot write. Email confirmation is OFF (test configuration).

### Authorization

**Plain meaning.** Authorization is answering "what may this account do?" —
deciding which actions and rows an authenticated identity may touch.

**In Student Codex.** Authorization is enforced server-side by three
cooperating mechanisms: `user_roles` (the teacher role is granted only by the
gated registration RPCs and triggers — signing in never grants it), RLS
policies on every client-exposed table, and EXECUTE privileges on the
SECURITY DEFINER RPCs (migration 0032 revoked three of those grants from
`authenticated`).

### RLS

**Plain meaning.** Row-level security attaches a filter to the table itself:
every query, from any client, is silently narrowed to the rows the current
user is allowed to see.

**In Student Codex.** Every client-exposed table has RLS. The central example
is the `activities_select` policy (migrations 0019/0020): a caller sees their
own rows, rows of sections or courses they are enrolled in, and — if they
hold the teacher role — every non-personal section/course row
university-wide, while `deleted_at is null` hides soft-deleted rows from
everyone but their creator. Anonymous requests are denied everywhere
(`policies_test.sql` T03).

### SECURITY DEFINER

**Plain meaning.** A SECURITY DEFINER function runs with the privileges of
its owner rather than the caller — a way to let ordinary users do
precisely-scoped privileged work through a guarded doorway.

**In Student Codex.** The trusted writers are SECURITY DEFINER:
`upsert_activity_from_source` (raises if a non-service caller reaches it),
`import_student_classroom_courses`, `enroll_student_courses`, and the teacher
signup RPCs. The F1/F2/F3 audit findings were exactly this term's failure
mode — DEFER bodies that were safe, but EXECUTE grants that let any
signed-in user through the door; migration 0032 closed them with REVOKEs.

## 37.4 Database and backend vocabulary

These ten terms describe the machinery under the product, ordered from the
platform down to the integrity mechanisms. The last three — upsert,
idempotency, and the unique constraint — are the load-bearing trio behind
the Classroom deduplication story.

### PostgreSQL

**Plain meaning.** PostgreSQL is an open-source relational database: data
lives in tables with defined columns, and integrity rules live in the
database itself.

**In Student Codex.** The hosted project runs PostgreSQL; the schema is 23
tables defined by 33 versioned migrations (`supabase/migrations/`,
000000–003200). The latest test run (2026-10-30) executed on a local
PostgreSQL 17.11 replicating the platform surface.

### Supabase

**Plain meaning.** Supabase is a backend platform that wraps PostgreSQL with
managed authentication, an auto-generated REST API, serverless functions,
and file storage.

**In Student Codex.** One hosted Supabase project is the entire backend. Its
publishable (anon) key ships in both clients and is public by design — RLS
is the boundary. The service-role key exists only inside Edge Function
server context and never in any client.

### RPC

**Plain meaning.** A remote procedure call invokes a named function on the
server as if it were a local one; in Supabase, PostgreSQL functions are
exposed at a `/rpc/` endpoint.

**In Student Codex.** The RPCs are the privileged server-side doors:
`upsert_activity_from_source`, `import_student_classroom_courses`,
`enroll_student_courses`, `teacher_signup_global`, and
`teacher_signup_multi`. The Android app makes ZERO direct RPC calls
(verified: REST tables and Edge Functions only); RPCs are called by the Edge
Functions with the service key, by the auth triggers, or by the dashboard's
signup flow.

### Edge Function

**Plain meaning.** An edge function is a short piece of server-side code run
by a platform on demand, close to the network, without managing a server.

**In Student Codex.** Three Deno Edge Functions exist in
`supabase/functions/`: `classroom-import` (197 lines, course linking),
`classroom-sync` (405 lines, coursework and announcement import), and `site`
(192 lines, the public home page and privacy policy required for OAuth
consent-screen branding URLs). This is the only place the service-role key
is used.

### Foreign key

**Plain meaning.** A foreign key is a column that must reference an existing
row in another table — the database refuses orphaned data.

**In Student Codex.** The registry chain is built on them:
`programs.campus_id` references `campuses` (NOT NULL since migration 0012 —
the very change that out-dated two test fixtures), and every join from
`activities` to `sections`, `profiles`, and `courses` is FK-backed.

### Index

**Plain meaning.** An index is a lookup structure that lets the database find
rows without scanning the whole table.

**In Student Codex.** The important one is the partial unique index on
`activity_sources.source_key`, which both speeds conflict detection and
enforces one row per Classroom item. The `profiles.username` unique
constraint is enforced by an index as well.

### Unique constraint

**Plain meaning.** A unique constraint forbids two rows with the same value
in the constrained column(s) — the database rejects the second insert.

**In Student Codex.** `activity_sources.source_key` carries a UNIQUE partial
index (NULLs allowed for non-imported rows), backed by a composite unique on
(provider, external_course_id, external_item_id) as a second guard. This is
the mechanism that makes "one canonical activity row per Classroom item"
true.

### Trigger

**Plain meaning.** A trigger is database code that runs automatically when
something happens to a table — an insert, an update, a delete.

**In Student Codex.** `handle_new_user` fires on signup and fills `profiles`,
grants `user_roles`, and enrolls the student. Guards fire on writes:
`guard_activity_insert` (scope/role/enrollment checks, raises P0001),
`guard_activity_update` (stamps the category corrector), author-immutability
guards on posts, and the three rate-limit guards (migration 0008).

### Upsert

**Plain meaning.** An upsert inserts a row if it does not exist and updates
it if it does — one atomic operation instead of check-then-write.

**In Student Codex.** `upsert_activity_from_source` upserts on the source
key: `ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO UPDATE` — the
partial-index predicate is required. When Student B syncs what Student A
already synced, the same shared row is updated, never duplicated
(`gc_source_identity_test.sql`).

### Idempotency

**Plain meaning.** An operation is idempotent when doing it twice has the
same effect as doing it once — retries cannot corrupt the result.

**In Student Codex.** The whole sync path is idempotent: repeated syncs
converge on the same rows (source-key upsert), course linking uses advisory
locks so concurrent classmates converge on one course row, and
`upsert_activity_from_source` is retry-safe by construction.

## 37.5 Data-management vocabulary

These three terms describe how the project talks about its data: where a
record came from, what "deleted" means, and how the schema is pictured. Two
of them — provenance and soft deletion — are design decisions a judge can
test with one question each.

### Data provenance

**Plain meaning.** Provenance is the recorded origin of a piece of data —
where it came from and who put it there.

**In Student Codex.** Every activity row carries `source`
(GOOGLE_CLASSROOM / MANUAL / STUDENT_REPORT) and `verification_status`
('imported' / 'teacher-confirmed' / 'student-reported' / 'needs_review'),
resolved from the row itself (`SupabaseActivityRepository.kt:203-213`) and
rendered as the Classroom and Manual badges. Raw Classroom workType survives
in `source_meta`, and category corrections survive re-syncs via
`category_locked` — provenance is never laundered.

### Soft deletion

**Plain meaning.** Soft deletion marks a row as deleted instead of removing
it — the data stays recoverable and auditable.

**In Student Codex.** `activities.deleted_at` is the tombstone. RLS shows a
soft-deleted row only to its creator
(`deleted_at is null or created_by_user_id = auth.uid()`), so deletion is
private and reversible server-side while the record persists.

### ER diagram

**Plain meaning.** An entity-relationship diagram pictures the tables of a
database and the relationships between them — a map of what connects to what.

**In Student Codex.** The schema's core relationships: profiles—user_roles
(1:1), profiles—enrollments—sections—courses—programs—campuses,
activities—profiles (creator), activities—activity_sources (1:1),
activities—sections (scope), posts—profiles, posts—post_images,
posts—comments (self-referencing for nesting), post_likes and
comment_likes, content_reports, and google_connections—profiles — 23 tables
across 33 migrations.

---


# Chapter 38 — Developer Investigation Guide

This chapter is the map for the developer or judge who has a specific
question and wants the exact place to look — not a tour (Chapter 5 is the
tour) and not an explanation (the feature chapters explain). Every row of
the table in Section 38.2 was checked against the verified fact base
(re-verified 2026-11-01) and, where line numbers appear, against the source
mirrors under the doc-build inspection directory. Paths are repo-relative;
the Kotlin root `app/src/main/java/com/example/studentcodex/` is abbreviated
to `…/studentcodex/` after first use, and migration numbers refer to the 33
files in `supabase/migrations/` (000000–003200).

## 38.1 How to use this guide

Two reading rules keep this guide honest. First, "where to inspect" means
where the mechanism lives — the enforcement is usually server-side even when
the affordance is client-side (the dashboard offers a correction button, but
RLS and a guard trigger decide whether it succeeds). Second, the guide
distinguishes what is on the hosted project from what is local-only: the
hosted Supabase project has migrations through 0028 applied, while 0029–0032
exist locally only — so any question about the F1/F2/F3 revokes must be
answered from the local migration file and the local test run, not from the
hosted project. Section 38.3 expands this surface distinction, and Section
38.4 states exactly what each SQL test suite proves, so that quoting test
results never outruns their evidence.

## 38.2 The investigation table

| Question or Problem | Where to Inspect | Relevant Class / Function / Table |
|---|---|---|
| Where is authentication handled (app)? | `app/src/main/java/com/example/studentcodex/data/auth/` | `AuthRepository.kt` / `SupabaseAuthRepository.kt`; `GoogleAuthManager.kt`; `GoogleAccountResolution.kt`; Supabase Auth |
| Where is authentication handled (dashboard)? | `WebView/app.js` | `signIn` / `handleSession` (:1970-1979, :816-853); supabase-js client (:239-241) |
| Where does the Activity Beacon load its data? | `…/studentcodex/ui/BeaconScreen.kt`; `…/ui/BeaconViewModel.kt` | `load()` one-shot + `refresh()` silent on tab resume (:123-131); `SupabaseActivityRepository.getActivities`; table `activities` |
| Where is Google Classroom sync processed? | `supabase/functions/classroom-sync` | Edge Function (405 lines); `upsert_activity_from_source` RPC; tables `activities`, `activity_sources`, `google_connections` |
| Where is Google Classroom import processed? | `supabase/functions/classroom-import` | `action:"list"` and `action:"import"`; `import_student_classroom_courses` RPC; JWT check via /auth/v1/user (:18) |
| Where are duplicates prevented? | `supabase/migrations/` (0022/0023); `activity_sources` | `source_key` UNIQUE partial index; `upsert_activity_from_source` ON CONFLICT; verified by `gc_source_identity_test.sql` — manual entries are NOT deduped |
| Where is teacher visibility enforced? | `supabase/migrations/20260101001900_global_teacher_visibility.sql` | `activities_select` policy; `activity_visible_to_user`; `has_role('teacher')` |
| Where are category corrections saved? | `WebView/app.js:2189-2222` (set-category PATCH) | updates `activity_type` + `category_locked`; `guard_activity_update` stamps `category_locked_by` (migration 0023) |
| Where are community images stored? | Supabase Storage bucket `community-images` (migration 000500) | own-folder layout `{uid}/{postId}/{ts}.jpg`; upload in `SupabaseCommunityRepository.kt`; 4 storage policies |
| Where are database permissions defined? | RLS policy blocks across `supabase/migrations/` (000200, 000300, 0015, 0019, 0020, 000500) | `activities_select/insert/update`; community own-row policies; storage policies; checked by `policies_test.sql` |
| Where is the teacher registration gate? | `supabase/migrations/20260101003100_teacher_school_email_domain.sql` | @parsu.edu.ph check inside `teacher_signup_global` / `teacher_signup_multi`; client-side hint `SCHOOL_EMAIL_SUFFIX` in `WebView/app.js` |
| Where are the RPC revokes (F1/F2/F3)? | migration 0032 in `supabase/migrations/` | F1 `teacher_signup` :43-45; F2 import :47-49; F3 enroll :51-53; service grants :57-60; public/anon re-revoke :63-68 |
| Where are the tests? | SQL suites (migration 0032's header cites `tests/rpc_authorization_test.sql`); `app/src/test/java/com/example/studentcodex/` | `rpc_authorization_test.sql` (T01–T10), `phase_completion_test.sql`, `gc_source_identity_test.sql`, `policies_test.sql`; 11 unit-test files (PLAN cites 117 tests) |
| Where is the dashboard calendar rendered? | `WebView/app.js:1241-1298` | `calendarHtml`; day-detail dialog :1320-1342; legend category filters; filter bar `filterBarHtml` :1193-1237 |
| Where is auto-sync triggered? | `…/studentcodex/ui/StudentCodexApp.kt:215-234` | ON_START LifecycleEventObserver + toggle flip; logic in `…/data/repo/ClassroomAutoSync.kt` (AtomicBoolean in-flight guard) |
| Where is the guidance engine? | `…/studentcodex/domain/guidance/GuidanceEngine.kt` | `GuidanceEngine` interface + `DemoGuidanceEngine` (134 lines, 6 rules); tested by `DemoGuidanceEngineTest` |
| Where is the sign-up enrollment trigger? | auth.users triggers (migrations 0017/0018/0027) | `handle_new_user` / `handle_user_profile_sync` → `enroll_student_courses` (advisory locks, 32-code cap) |
| Where is the demo seed data? | `supabase/migrations/` 0009/0010/0011 | fixed-UUID demo teacher/students/courses/sections/enrollments/activities/posts — applied on the hosted project |
| Where is the config (email confirmation setting)? | `supabase/config.toml` | `[auth.email] enable_confirmations = false`; `[auth.external.google] enabled = true`; `[auth.rate_limit] email_sent = 2` |
| Where is the anonymous flag dropped? | `…/ui/CommunityViewModel.kt:166`; `…/data/repo/SupabaseCommunityRepository.kt` | `is_anonymous` hard-wired false at :149 (posts) and :110 (comments); switch at `CommunityScreen.kt:347-360` |
| Where is the coverage card rendered? | `WebView/app.js:1355-1410` | `studentReportsPanelHtml` + data-source coverage card (recorded ≠ complete) |
| Where are workload analytics (unbuilt)? | view `section_workload_daily` (migration 000800) | security_invoker view: per-section/per-day `activity_count` + `total_effort_minutes`; no client consumes it |
| Where is profile completion gated? | `…/ui/AuthGateScreen.kt:413`; `ProfileCompletionScreen.kt` | CompletingProfile state; `handle_user_profile_sync` re-runs enrollment |
| Where is publish-without-approval enforced? | `supabase/migrations/20260101001500_student_self_publish.sql` | `activities_insert` policy + `guard_activity_insert` (raises P0001); strings.xml:164 "No approval needed." |
| Where are the Edge Function JWT checks? | `supabase/functions/classroom-import` (:18); `supabase/functions/classroom-sync` (:48-59) | session JWT verified via /auth/v1/user before service-key RPC calls |
| Where is the school registry served from? | migration 000700; `…/data/SchoolDirectoryRepository.kt` | lookup tables `campuses`, `year_levels`, `year_sections`; in-memory reference cache |
| Where is the public site served from? | `supabase/functions/site` (192 lines) | static home page + privacy policy at /functions/v1/site[/home|/privacy]; exists for OAuth branding URLs |

## 38.3 Local versus hosted

Most confusion in an investigation comes from mixing the two deployment
surfaces, so the distinction deserves its own statement. The hosted Supabase
project — the one both clients talk to — has migrations through 0028
applied: the demo seed data (0009–0011), the student self-publish policies
(0015), global teacher visibility (0019), and the 0028 OTP-gated teacher
RPCs all live there. Migrations 0029–0032 — the email-click verification,
the verified-email database gate, the 0031 @parsu.edu.ph domain gate, and
the 0032 RPC revokes — exist locally only. The local surface, where those
four migrations have been applied and tested, is a local PostgreSQL 17.11
instance replicating the Supabase platform surface, used because Docker was
unavailable for the 2026-10-30 run.

The consequence for an investigator: a question about teacher registration
gating has two different answers depending on the surface asked about. On
the hosted project, the teacher signup RPCs are still the 0028 OTP-gated
definitions (superseded in the local line); locally, migration 0031's
@parsu.edu.ph domain gate is applied and SQL-tested (T09/T10), and 0032's
revokes are verified by `rpc_authorization_test.sql` T01–T10. Any probe of
"can authenticated still execute the three RPCs?" must therefore say which
database it means: on the hosted project, the 2026-10-29/30 non-mutating ACL
probes showed the three RPCs still executable pre-0032; locally, the revokes
hold. Stating the surface before the answer is not pedantry — it is the
difference between an accurate answer and a false one.

## 38.4 What the SQL suites prove

An investigator who runs the suites or quotes their results should know
exactly what each one covers, because they are not interchangeable. The
latest run (2026-10-30, local) produced: `rpc_authorization_test.sql`
PASSED (T01–T10 — revokes hold, teacher doors stay open, service paths and
triggers intact, domain gate intact); `phase_completion_test.sql` PASSED;
`gc_source_identity_test.sql` PASSED, with a temporary compatibility shim
because its fixture predates migration 0012's `campus_id` NOT NULL; and
`policies_test.sql` PARTIALLY PASSED — the programs fixture lacks
`campus_id`, and T08.1 expects SQLSTATE 42501 where migration 0015's guard
raises P0001. A control rebuild without 0032 reproduced both failures, so
they predate and are unrelated to the hardening migration.

The unit tests complement the SQL suites on the client side: eleven files
under `app/src/test/java/com/example/studentcodex/` cover the ViewModels,
the auto-syncer, the guidance engine, the overlay controller, and the client
factory, with PLAN.md citing 117 unit tests in total; five of those files
are modified in the uncommitted working tree. None of the SQL suites were
run against the hosted project in the latest pass, and no suite anywhere
covers the Edge Functions against real Google OAuth — the last live evidence
for those is the 2026-10-28 browser verification. An accurate one-sentence
summary for Q&A: the database layer is locally re-verified with one suite
partially passing for documented fixture reasons, the client layer has unit
tests, and the Edge Functions' live OAuth path was last verified 2026-10-28.

## 38.5 Worked investigation scenarios

The table answers "where do I look"; the scenarios below answer "how do I
reason once I am there". Each one starts from a symptom a judge or a tester
could realistically report, walks the first two places to inspect, and ends
with the sentence that closes the investigation. Every step reuses rows from
the table in Section 38.2, so the scenarios double as a demonstration of how
to use the guide under pressure.

**A student appears to see activities from a section they are not enrolled
in.** Start at the `activities_select` policy (migration 0019/0020), because
visibility is decided there and nowhere else: the policy returns own rows,
rows of enrolled sections, rows of enrolled courses, and — for teacher
accounts only — all non-personal rows. Then check the student's
`enrollments` rows: enrollment is written by the `enroll_student_courses`
RPC from the sign-up triggers, so an unexpected enrollment usually explains
an unexpected view. If neither explains it, the account may hold the teacher
role in `user_roles` — the role, not the sign-in, is what widens visibility.

**Two rows exist for what looks like the same Classroom coursework.** For
imported rows this should not happen, and the place to look is
`activity_sources`: each import must carry the same
`google_classroom:{courseId}:{courseWorkId}` source key, and the unique
partial index plus `upsert_activity_from_source`'s ON CONFLICT update
guarantee one row. If the two rows are manual or student-reported, the
duplicate is expected behavior: there is no similarity logic anywhere in
`BeaconScreen.kt` or `BeaconViewModel.kt`, and the title-token classifier
only suggests categories. The closing sentence differs by case — "the
upsert guarantees import identity" versus "manual entries are not
deduplicated by design."

**A teacher's category correction silently does nothing.** The correction
path is the set-category PATCH (`WebView/app.js:2189-2222`), which updates
`activity_type` only where RLS allows: the teacher must teach the row's
section (`is_section_teacher`) or the PATCH matches zero rows. Inspect the
teacher's `enrollments` (role in section), then the row's own
`activity_type` — if it equals the requested value, the UI blocked the
no-op. When the correction does land, `guard_activity_update` stamps
`category_locked_by` (migration 0023), which is what keeps the correction
alive across later re-syncs.

**A post shows the author's name even though the anonymous switch was on.**
This is not a bug to chase — it is the documented state. The flag is dropped
at `CommunityViewModel.kt:166` and the insert hard-wires `is_anonymous`
false at `SupabaseCommunityRepository.kt:149`. The investigation ends at
those two lines; the follow-up work is roadmap item M1.1 (wire or remove),
and the honest answer in the moment is "the switch is UI-only today."

**A student reports seeing nothing after signing up.** Check the Beacon load
path first (`BeaconViewModel.kt:123-131` — one-shot fetch plus silent
refresh on tab resume; a failed first load shows the retry state). If the
list is genuinely empty rather than errored, the data question follows the
enrollment chain: `handle_new_user` should have created the profile,
granted the student role, and enrolled the section via
`enroll_student_courses`. A profile without enrollments sees only personal
and imported rows — which is exactly why Google-first accounts are routed
through profile completion before entering the app.

---


# Chapter 39 — Final Defense Readiness Checklist

This chapter is the team's pre-defense instrument: a checkbox list a team
member can run against themselves, or teammates can run against each other,
before standing in front of judges. It covers understanding (the problem,
the architecture, the data, the flows), accuracy (limitations, test status,
claims), and execution (the rehearsed demonstration). Every factual statement
in the items below is anchored to the verified fact base (re-verified
2026-11-01); the checklist does not introduce new facts, it converts the
existing ones into things each team member must be able to say out loud.

How to use it: check a box only when the named team member can answer
unaided, in their own words, with the evidence named. A box that is checked
"mostly" is unchecked. The final section is the overclaim blacklist — the
short list of sentences that must never be said, because each is falsifiable
in minutes and each would invalidate every accurate claim made before it.
Run the checklist as a pass/fail gate: a section with any unchecked box is a
rehearsal topic, not a reason to adjust the checklist.

## 39.1 Problem and product framing

- [ ] Every team member can state the problem in one sentence: academic announcements are fragmented; Google Classroom covers online coursework only; face-to-face announcements (board notes, verbal deadlines) never reach it; and no tool gives university-wide visibility of recorded workload.
- [ ] Every team member can state what Student Codex is: an Android student app plus a teacher web dashboard plus one shared Supabase backend, with a read-only Google Classroom integration.
- [ ] Every team member can state what it is not: a Classroom replacement — Student Codex complements Classroom, it never writes back to it.

Why it matters: the first question in any defense is "what problem does this
solve", and a divergent first answer from two team members undermines every
answer that follows.

## 39.2 Architecture

- [ ] Can explain one shared backend, two clients: a single source of truth, one RLS rule set, and no synchronization between two databases.
- [ ] Can trace the request flows: Android via supabase-kt to PostgREST with RLS; dashboard via supabase-js with the publishable key; Edge Functions to the Google Classroom API with user-level OAuth tokens.
- [ ] Can state that the Android app makes ZERO direct RPC calls — verified: it uses REST tables and Edge Functions only.
- [ ] Can describe the dashboard as vanilla HTML/CSS/JS with two vendored libraries, no framework, no build step (`WebView/`, six files: four authored, two vendored).

Why it matters: architecture questions test whether the team built the
system or assembled a demo — tracing a request end to end is the proof.

## 39.3 Data model

- [ ] Can explain `activities` as the core table: title, description, activity_type, scope (personal/section/course), due_at, effort_minutes, verification_status, deleted_at, and category_locked from migration 0023.
- [ ] Can explain `activity_sources` as the import identity table: the 1:1 partner of `activities` holding source_key, provider, external ids, and source_meta.
- [ ] Can explain provenance labels resolved from the row: source GOOGLE_CLASSROOM / MANUAL / STUDENT_REPORT, and verification_status 'imported' / 'teacher-confirmed' / 'student-reported' / 'needs_review' (SupabaseActivityRepository.kt:203-213).
- [ ] Can name the supporting tables and the scale: profiles, user_roles, courses, sections, enrollments, posts, comments, content_reports, google_connections — 23 tables across 33 migrations.

Why it matters: "walk me through your schema" is the fastest credibility
test a technical judge has, and `activities` plus `activity_sources` is the
two-table answer that carries it.

## 39.4 Google Classroom flow

- [ ] Can distinguish import from sync: import links courses (picker at sign-up or Settings, via the classroom-import Edge Function); sync imports coursework and announcements of linked courses as read-only 'imported' activities (classroom-sync Edge Function).
- [ ] Can explain the course matching tiers: exact external_course_id link first; then normalized course-name match with the fuzzy tier and cohort preference; then a brand-new course row under the Classroom name — with classmates converging on the same rows under an advisory lock.
- [ ] Can explain shared identity: Classroom IDs are shared across enrolled students, so one canonical activity row exists per coursework item, and Student B's sync UPDATES what Student A already synced.
- [ ] Can explain the token model: short-lived access token minted per sync, transit-only, never stored, no refresh tokens, no client secrets in the app; revoking Google access takes effect next sync.

Why it matters: this is the differentiating integration — the team must own
its mechanics, including the exact tier order, or the integration reads as
glued-on.

## 39.5 Deduplication

- [ ] Can explain the source-key upsert: `activity_sources.source_key` (`google_classroom:{courseId}:{courseWorkId}`) under a UNIQUE partial index, with `upsert_activity_from_source` doing ON CONFLICT DO UPDATE — atomic and retry-safe, verified by `gc_source_identity_test.sql`.
- [ ] Can state the limit without prompting: manual entries are NOT deduplicated — there is no similarity logic in BeaconScreen or BeaconViewModel, so two students reporting the same activity create two rows.
- [ ] Knows the drift: the Guidance assistant's canned text ("will ask whether it is the same one before saving") overstates the app — say so before a judge reads it aloud.

Why it matters: guaranteed dedup is on the overclaim blacklist; precision
about what the upsert does and does not cover is where trust is earned.

## 39.6 Security and authorization

- [ ] Can explain the publishable key model: the key is public by design and RLS is the boundary — every request is filtered per row server-side.
- [ ] Can explain that role is not signed-in: the teacher role comes only from `user_roles` granted by the gated registration RPCs and triggers; a signed-in student gets nothing.
- [ ] Can tell the 0032 story exactly: the F1/F2/F3 audit found three SECURITY DEFINER RPCs executable by `authenticated`; migration 0032 revokes those grants (a pure privilege change, no bodies modified); it is locally tested (`rpc_authorization_test.sql` T01–T10 PASSED) and NOT deployed — the hosted project is at 0028.
- [ ] Can state that anonymous requests are denied everywhere (`policies_test.sql` T03) and that guests cannot write.

Why it matters: security judges probe exactly the gap between "signed in"
and "authorized" — and the 0032 deployment state is the project's most
quotable honesty anchor.

## 39.7 Limitations fluency

- [ ] Can state the offline position: online-first, no cache or outbox; connectivity is required for everything except the on-device Guidance engine.
- [ ] Can state the anonymity position: the composer switch is UI-only; the flag is dropped and `is_anonymous` is hard-wired false (SupabaseCommunityRepository.kt:149).
- [ ] Can state the sync position: client-triggered only (app open with opt-in auto-sync, manual Sync now, or the import picker); no background sync, no push, no Pub/Sub.
- [ ] Can state the analytics position: the `section_workload_daily` view exists and no client consumes it; workload analytics are `PLANNED`.

Why it matters: volunteering limitations before being asked converts them
from weaknesses into demonstrated self-knowledge — the opposite order reads
as concealment.

## 39.8 Test status accuracy

- [ ] Knows which suites passed in the latest run (2026-10-30, local): `rpc_authorization_test.sql` (T01–T10), `phase_completion_test.sql`, and `gc_source_identity_test.sql` — the last with a temporary compatibility shim.
- [ ] Knows which partially passed and why: `policies_test.sql` — the programs fixture lacks campus_id (fails after migration 0012), and T08.1 expects SQLSTATE 42501 while 0015's guard raises P0001; both predate and are unrelated to 0032 (a control rebuild reproduced them).
- [ ] Knows local versus hosted: the latest run was a local PostgreSQL 17.11 with a replicated platform surface (Docker unavailable); the hosted project has migrations through 0028; hosted ACL probes were non-mutating.
- [ ] Never claims all tests pass — the accurate sentence names three passes, one partial, and the fixture reasons.

Why it matters: one inaccurate test claim, once caught, invalidates every
other claim the team has made; the accurate version costs nothing to say.

## 39.9 Demo execution

- [ ] The demonstration flow is rehearsed end to end, with timings and a designated operator for each segment.
- [ ] A backup plan exists and is rehearsed: documented demo accounts and the demo seed data (migrations 0009/0010/0011) carry the demonstration if a live flow fails; the WebView README documents demo teacher credentials (locations, not values, belong in the defense notes).
- [ ] Demo data is introduced as seeded demo data — never presented as organic usage.
- [ ] The network dependency is acknowledged in the plan: online-first means the venue network is a single point of failure for everything except the Guidance engine.

Why it matters: live demonstrations fail on logistics, not features — and a
judge who watches a team switch calmly to a backup plan sees engineering
maturity, not a failed demo.

## 39.10 The overclaim blacklist

- [ ] No one claims real-time sync: synchronization is client-triggered; a Classroom change waits for the next successful sync.
- [ ] No one claims offline support: the app is online-first; offline cache and outbox are `PLANNED` (M3.1).
- [ ] No one calls the Guidance assistant AI or an LLM: it is deterministic, rule-based (`GuidanceEngine.kt`, 134 lines, six keyword rules).
- [ ] No one claims guaranteed deduplication: dedup covers Classroom imports only; manual entries are excluded.
- [ ] No one claims deployed 0032: it is locally tested, not hosted-deployed (deployment is M2.1).
- [ ] No one claims email-ownership proof: email confirmation is OFF (test config) and the @parsu.edu.ph suffix proves eligibility, not mailbox ownership.
- [ ] No one claims complete calendar coverage: the dashboard shows recorded information only (recorded ≠ complete).

Why it matters: each blacklisted claim is falsifiable in minutes — by
airplane mode, by the sync settings screen, by the source file, or by the
hosted project's migration list — and a falsified claim retroactively
discredits the accurate ones.

## 39.11 The honesty anchors

- [ ] Can say verbatim: migration 0032 is locally tested, NOT hosted-deployed (hosted is at 0028).
- [ ] Can say verbatim: email confirmation is OFF — a test configuration, not a product decision.
- [ ] Can say verbatim: the @parsu.edu.ph domain suffix proves eligibility, not mailbox ownership.
- [ ] Can say verbatim: the app is online-first — no offline cache or outbox exists.
- [ ] Can say verbatim: sync is client-triggered — no push, no background refresh, no Pub/Sub.
- [ ] Can say verbatim: the Guidance assistant is deterministic, not an LLM.
- [ ] Can say verbatim: recorded ≠ complete — the calendar shows what was recorded, not everything that exists.
- [ ] Can say verbatim: title matching does not deduplicate manual entries.

Why it matters: these eight sentences are the project's load-bearing honesty
anchors — they appear in the capability matrix (Chapter 29), the limitations
chapter (Chapter 30), and the roadmap (Chapter 31), and a team member who
has them memorized cannot be cornered into an overclaim by a fast follow-up
question.

## 39.12 Running the checklist

Treat the list as a gate, not a guideline. Every box in 39.1 through 39.8
must be checked for every team member who will speak; every box in 39.9 must
be checked by whoever runs the demonstration; 39.10 is checked only when
the team has rehearsed catching each other on it, because overclaims slip out
under pressure, not from intent; and 39.11 is checked when each anchor can
be produced verbatim on demand. If a box cannot be checked honestly, the
correct action is to prepare the accurate sentence for that topic — the
honest answer to every item in this chapter exists somewhere in Chapters 29
and 30, with its evidence attached. The checklist's only failure mode is
checking a box to feel ready; its purpose is to make readiness verifiable.

---


# STUDENT CODEX — HACKATHON DEFENSE HANDBOOK

(source for Student-Codex-Hackathon-Defense-Handbook.pdf)

# The Project Story

This part opens the Hackathon Defense Handbook, the presentation-focused
companion to the technical documentation. It exists so a presenter can tell
the project's story accurately under time pressure: what Student Codex is,
the problem it addresses, the solution as it actually shipped, and the four
properties that make it technically interesting to judges. Every claim here
comes from the verified fact base and carries its evidence inline, and every
capability status uses the project's status labels verbatim. The story never
contradicts the technical documentation — where this chapter compresses, the
documentation remains the authority.

## The 30-Second Elevator Pitch

Use this when a judge asks "so what is Student Codex?" in a hallway, or when
the presentation opening needs one prepared paragraph. It is about ninety
words — roughly thirty seconds at a normal speaking pace — and every sentence
survives follow-up questioning because each one maps to a verified mechanism
in the codebase. Deliver it slowly, one breath per sentence, and stop at the
end; the details live in the rest of this handbook.

```text
Student Codex is a hackathon project that puts every recorded academic
deadline in one place. University students use an Android app: they import
their Google Classroom coursework read-only, and they record the
face-to-face deadlines that never reach Classroom. Teachers use a web
dashboard with a university-wide calendar of recorded, non-personal
activities. Both clients share one Supabase backend — one database, one set
of row-level security rules — and every activity carries a provenance
label, so anyone can see whether an entry was imported from Google
Classroom or reported by a student.
```

If you get more than thirty seconds, add the sentence that most often earns
a nod: the same Classroom coursework that Student A imports is recognized
when Student B imports it, so the class converges on one shared record
instead of one private copy per student. If you get less, cut the final
sentence and keep the first three — they still name the users, the product,
and the architecture. Never extend the pitch with claims that are not in
this handbook; the strength of the pitch is that it is all verifiable.

The pitch also sets the order of the full presentation: problem, solution,
live product on both sides, then the architecture underneath. If a judge
interrupts mid-pitch with a specific question, answer from the relevant
handbook chapter and return to the thread — the pitch is a map of the whole
defense, not a fixed script to finish at all costs.

## The Problem: Fragmented Academic Announcements

The problem is not a shortage of academic information — it is that the
information exists in fragments no single tool assembles. Four facets of
that fragmentation are each real, each observable in ordinary university
practice, and each one maps to a specific shipped mechanism, which is what
keeps the story coherent when a judge pulls on any thread.

| Facet | What happens | Where it lives |
|---|---|---|
| Classroom holds online coursework only | Assignments and announcements a teacher deliberately posts online | Google Classroom |
| Face-to-face announcements never reach it | Board notes, verbal deadlines, lab-session dates | Notebooks, phone notes, group chats |
| Students juggle scattered deadlines | Triage across Classroom, chats, and notes; deadlines get missed | No consolidated view |
| Teachers cannot see across sections | One teacher's deadlines are invisible next to another teacher's | No university-wide view |

The face-to-face half is the half students forget, and it decays by
retelling: a date written on a board is copied into a notebook, summarized
into a group chat, and paraphrased from memory a week later. Teachers face
the mirror image — they cannot check whether the deadline they just set
collides with one set by a colleague in another section, because no tool
shows what has been recorded across sections at all. The gap, stated
precisely, is consolidation: one list per student of the deadlines they are
responsible for, and one university-wide view of recorded non-personal
workload for teachers. Google Classroom remains the system of record for
the online half; the problem is that the other half never gets a system of
record.

## The Solution: A Shared Activity Record

Student Codex consolidates recorded academic activities into one shared
`activities` table and gives that table two intake paths and two reading
surfaces. The intake paths are a read-only Google Classroom import and
manual recording in the app; the reading surfaces are the student's Activity
Beacon and the teacher's university-wide calendar. The verified core flow
is:

1. Students import Classroom coursework and record face-to-face activities
   themselves.
2. Both kinds of entry land in the shared `activities` table with
   provenance labels.
3. The Beacon shows each student their consolidated activities, and the
   dashboard calendar shows recorded non-personal activities
   university-wide.

Two properties of that record matter for the defense. First, provenance is
explicit on every row: a `source` of GOOGLE_CLASSROOM, MANUAL, or
STUDENT_REPORT plus a `verification_status` such as `imported` or
`student-reported`, resolved from the row itself and rendered as badges in
the app (`app/src/main/java/com/example/studentcodex/data/supabase/SupabaseActivityRepository.kt:203-213`).
Second, a student's report of a face-to-face activity publishes to their
section instantly, with no approval queue anywhere (migration 0015; the
editor's own hint reads "No approval needed." — strings.xml:164), while
personal activities stay private to their creator — invisible even to
teachers (migration 0019).

The solution is also a scope statement. Student Codex complements Google
Classroom through a read-only import and never writes back to Google's
side; teachers keep using Classroom exactly as they do today. The project
does not manage submissions, grading, or Classroom administration, and it
does not need teachers to change their Classroom habits for the calendar
to fill.

The deployment context is a single university, ParSU, identified by its
school-email domain `@parsu.edu.ph`. That domain is the server-side
gate for teacher registration (migration 0031), and the university registry
— campuses, programs, year levels, sections — is seeded in the database and
feeds every sign-up dropdown on both clients (migration 000700). One
sentence of context is enough for judges: "built for one university, with
the school registry and the school email domain as the two anchors of
who-is-who."

> NOTE: The honest boundary that travels with this solution statement: the
> dashboard shows recorded information only. Nothing guarantees that every
> real-world university activity has been entered, and the project does not
> claim it.

## What Makes It Technically Interesting

Four properties are genuinely interesting to technical judges, and each is
verifiable in the code rather than asserted. Lead with the one that matches
the judge's interest; all four are developed in depth in the technical
documentation (Chapters 12–14 for the Classroom pipeline, Chapter 22 for the
policy set, Chapter 27 for the audit and its fix).

### Shared Classroom identities, deduplicated server-side

Classroom coursework IDs are shared across every student enrolled in a
course, and the design exploits that. Each imported item is stored under a
source key of the form `google_classroom:{courseId}:{courseWorkId}` in
`activity_sources`, protected by a UNIQUE partial index (migration 0022).
The import runs through `upsert_activity_from_source`, an atomic upsert on
that key — so when Student B syncs coursework that Student A already synced,
the same shared row is updated, never duplicated, and the whole class
converges on one canonical record per coursework item. The behavior is
verified by a dedicated SQL test (`gc_source_identity_test.sql`, PASSED in
the 2026-10-30 local run).

### RLS as the single policy enforcement point

Both clients ship only Supabase's publishable key — public by design — and
every table a client can touch is governed by row-level security, so the
database is the one place where visibility is decided. The teacher
dashboard's university-wide calendar and the student's private Beacon are
the same query against the same table, separated only by RLS policies. That
is a deliberately small security surface to defend: one rule set in one
place, not per-client authorization logic that can drift between the app
and the dashboard.

### Edge Functions as the only privileged path

The service key exists only inside Edge Functions; no client ever holds it.
`classroom-import` and `classroom-sync` verify the caller's Supabase
session JWT server-side before invoking their SECURITY DEFINER RPCs with
the service key (`supabase/functions/classroom-import/index.ts`,
`supabase/functions/classroom-sync/index.ts`). Migration 0032 then revoked
direct client execution of those RPCs, closing the F1/F2/F3 audit findings
in which any signed-in user could have called privileged RPCs themselves.
State it precisely: 0032 is `IMPLEMENTED — VERIFICATION INCOMPLETE` —
locally tested, NOT deployed to the hosted project; deploying it is roadmap
item M2.1.

### Honest provenance labels

Every row records where it came from, and both clients surface it instead
of hiding it: Google-branded Classroom badges, manual badges, and
verification chips in the app; category-colored chips with dashed outlines
for student-reported entries on the dashboard. The same honesty extends to
the project's own limits — recorded is not complete, sync is
client-triggered rather than real-time, and the dashboard carries a
data-coverage card stating where its data comes from (`WebView/app.js`).
Judges who probe for overclaiming find labeled boundaries instead.

## Key Numbers

These numbers are the verified shape of the project. They are small enough
to memorize and precise enough to cite when a judge asks "how big is this
thing, really?"

| Number | What it counts | Evidence |
|---|---|---|
| 33 | SQL migrations, 000000–003200 | supabase/migrations/ |
| 23 | tables in the schema | migrations 000000–0023 |
| 3 | Edge Functions: classroom-import, classroom-sync, site | supabase/functions/ |
| 11 | Android unit-test files; 117 tests cited in PLAN.md | app/src/test/java/com/example/studentcodex/ |
| 4 | SQL test suites | supabase test scripts (see below) |
| 2,477 | lines in the dashboard's app.js | WebView/app.js |
| 1 | Activity in the Android app (single-activity Compose) | MainActivity.kt |
| 50 | program rows in the seeded school registry | programs table, migrations 000000–0012 |
| 6 | guidance-assistant rules (deterministic, not an LLM) | GuidanceEngine.kt |
| 12 | class groups a teacher may claim at sign-up | migration 0016 |

The four SQL suites are `rpc_authorization_test.sql`, `policies_test.sql`,
`phase_completion_test.sql`, and `gc_source_identity_test.sql`; the latest
run (2026-10-30, local PostgreSQL) had three PASSED and one PARTIALLY
PASSED — `policies_test.sql`, with two pre-existing fixture issues
unrelated to migration 0032. Say that plainly if asked, because "all tests
green" is not a claim this project makes.

Three more facts carry honesty anchors when the numbers invite a follow-up.
The hosted project has migrations through 0028 applied; 0029–0032 exist
locally only. The repository has 2 commits total, with the current product
largely uncommitted working-tree state (repository hygiene is roadmap item
M2.4) — volunteer that before a judge finds it. And the app is online-first
with no offline write path; the offline cache is `PLANNED` and exists only
as a design document (`docs/OFFLINE-SYNC.md`).

## Where This Story Continues

The next handbook part compresses the architecture into one page:
components, the four request flows, the security model in five lines, the
authorization ladder, and the dedup rule. Chapter 32, the Suggested
Presentation Flow, turns this story into a ten-minute talk with a spoken
script for each of its eleven parts, and Chapter 33, the Live Demonstration
Script, sequences every action that actually works in the current build.
For deep evidence, the technical documentation carries the mechanism
chapters — Chapter 3
(Complete System Architecture), Chapter 8 (the Activity Beacon), Chapters
12–14 (Classroom import, course matching, and dedup), Chapter 19 (Teacher
Dashboard Security), Chapter 22 (the RLS policy catalog), and Chapter 27
(the F1/F2/F3 audit and migration 0032).

---


# Architecture Quick Reference

This part is the one-page mental model to keep in reach during the whole
defense: the components, the four request flows that cover everything the
system actually does, the security model in five lines, the authorization
ladder, and the dedup rule. It compresses Chapter 3 of the technical
documentation and never replaces it — when a judge asks for depth, cite the
mechanism and the file, both of which are given here. Read it once before
the presentation and again five minutes before questions.

## The One-Page Mental Model

There is one backend and two clients, and the clients never talk to each
other. Every piece of data lives in one PostgreSQL schema behind row-level
security; the only code that runs with privileges is three Deno Edge
Functions on the server; and the only external dependency is the Google
Classroom API, reached with per-student, read-only OAuth tokens. If you can
draw this from memory, you can answer most architecture questions without
notes.

The one-backend choice is the load-bearing decision. A single source of
truth means one RLS rule set to audit instead of two authorization stacks,
and no synchronization job between an app database and a web database that
could disagree. The cost is equally explicit: both clients are online-first,
because the shared database is the only place data lives — there is no
offline cache in the shipped product.

```text
Android app (Kotlin/Compose)              Teacher dashboard (browser)
        |                                          |
        | supabase-kt, publishable key             | supabase-js, publishable key
        v                                          v
  +-----------------------------------------------------------+
  |  ONE shared Supabase project: Auth (GoTrue) + PostgreSQL   |
  |  with RLS (via PostgREST) + 3 Edge Functions + 1 private   |
  |  Storage bucket (community-images)                         |
  +-----------------------------------------------------------+
        |
        | service key, server context only
        v
  Google Classroom API (user-level OAuth, read-only scopes)
```

| Component | Form | Role |
|---|---|---|
| Android student app | Kotlin + Jetpack Compose (Material 3), single Activity | Beacon, community, Classroom import/sync, guidance |
| Teacher dashboard | Static HTML/CSS/JS in `WebView/`, no build step, no server | Sign-in, filters, calendar, corrections |
| Supabase backend | Auth, PostgreSQL + RLS, Edge Functions (Deno), Storage | One source of truth for both clients |
| Google Classroom API | REST, user-level OAuth, read-only scopes | Coursework and announcements, read-only |

## The Four Request Flows

Everything the system does is one of these four flows. Each is given in
four steps, in the order the bytes actually move, with the trust boundary
named — that is usually the detail judges probe.

### Flow 1 — App read-write via PostgREST + RLS

1. The app calls a table through supabase-kt with the publishable key and
   the signed-in user's session.
2. PostgREST turns the request into SQL against the target table.
3. RLS policies evaluate row by row — enrollment, scope, and role decide.
4. Only rows that pass the policies come back; the rest are filtered out.

The app itself makes ZERO direct RPC calls — verified: it uses REST tables
plus Edge Functions only (Chapter 3 of the technical documentation). That
keeps every student-facing data path on the single RLS-checked road.

### Flow 2 — Classroom course import via Edge Function + service-key RPC

1. The student picks a Google account and consents to the read-only
   Classroom scopes (Authorization API, on-device).
2. The app calls `classroom-import` with the Google token and the picked
   course ids.
3. The function verifies the caller's Supabase session JWT via
   `/auth/v1/user` — that check is the security boundary that protects the
   RPC (`supabase/functions/classroom-import/index.ts`).
4. It re-fetches the courses from Google server-side, then invokes
   `import_student_classroom_courses` with the service key.

Course matching then runs in tiers: exact `external_course_id` link first,
then normalized course-name match, then a brand-new course row under the
Classroom name (migrations 0022 and 0027). Classmates importing the same
course converge on the same course and section rows.

### Flow 3 — Classroom coursework sync via Edge Function + upsert

1. A client triggers sync: opt-in auto-sync on app open, a manual
   "Sync now", or the import picker — never a background service.
2. `classroom-sync` verifies the session JWT; the Google access token rides
   in the request body and is transit-only, never stored
   (`supabase/functions/classroom-sync/index.ts`).
3. The function calls `upsert_activity_from_source` with the service role.
4. The RPC upserts on the source key: new coursework INSERTs, coursework a
   classmate already synced UPDATEs the shared row — no second row exists.

### Flow 4 — Teacher dashboard via supabase-js + RLS

1. The browser loads the dashboard's static files — double-click
   `index.html` or serve the folder; there is no server of our own
   (`WebView/README.md`).
2. supabase-js signs the teacher in with the publishable key — the same
   key the Android app ships.
3. Every read goes through PostgREST, and RLS decides what a teacher sees:
   section-scoped, non-personal activities, university-wide (migration
   0019).
4. Sign-up grants the teacher role through `teacher_signup_global` /
   `teacher_signup_multi`, both gated by the `@parsu.edu.ph` domain check
   (migration 0031).

### Which screen uses which flow

During the live demonstration, name the flow as you touch the screen — it
is the cheapest way to sound precise. The mapping is one-to-one and easy
to remember.

| Screen action | Flow |
|---|---|
| Beacon, home, community posts and comments | Flow 1 |
| Classroom course picker, at sign-up or in Settings | Flow 2 |
| "Connect & Sync" / "Sync now" / auto-sync on open | Flow 3 |
| Dashboard sign-in, calendar, filters, corrections | Flow 4 |

## The Security Model in Five Lines

These five lines are the whole trust story; each one is one breath of
speaking time and each maps to a verifiable fact.

1. The publishable key is public by design — no secret ships in either
   client.
2. RLS decides — every client-exposed table has policies; the database is
   the single enforcement point.
3. The service key lives only server-side, inside Edge Functions.
4. Roles are gated by domain-checked RPCs — teacher sign-up requires an
   `@parsu.edu.ph` address (migration 0031).
5. Migration 0032 revoked direct RPC execution by authenticated clients —
   it is `IMPLEMENTED — VERIFICATION INCOMPLETE`: locally tested, NOT
   deployed to the hosted project (roadmap item M2.1).

> WARNING: Do not shorten line 5. Saying "we revoked client RPC execution"
> without the deployment status overstates the hosted project's state; the
> hosted project runs migrations through 0028.

## The Authorization Ladder

The sentence to say is: signed-in does not mean teacher. Authentication
proves who someone is; authorization is three further checks stacked on
top — the role row, the RLS policy, and the EXECUTE privilege on the RPC.
The ladder from bottom to top:

- Anonymous: denied everywhere — no client-exposed table answers an
  unauthenticated request (verified by `policies_test.sql`, T03).
- Signed-in student: reads and writes under RLS — own personal rows,
  enrolled-section rows; the student role is granted by the
  `handle_new_user` trigger at sign-up.
- Teacher: same RLS tables, wider read of section-scoped non-personal
  activities (migration 0019) — but the role itself comes only from
  `user_roles`, granted by the domain-gated sign-up RPCs.
- Edge Function service context: after migration 0032, the only remaining
  caller of the privileged import and sync RPCs.

The F1/F2/F3 audit (2026-10-29/30) found three rungs of that ladder
missing: the legacy `teacher_signup` let any signed-in user self-grant the
teacher role, and `import_student_classroom_courses` plus
`enroll_student_courses` were executable by authenticated clients with a
caller-supplied user id. Migration 0032 is the pure-privilege fix — no
function body changed, only grants revoked — verified locally by
`rpc_authorization_test.sql` (T01–T10 PASSED). Its hosted deployment, and
the post-deploy verification, are roadmap items M2.1 and M2.2.

## The Dedup Rule in Three Lines

Imported Classroom items have identity; manual entries do not. Three lines
carry the whole rule:

1. Identity is the source key `google_classroom:{courseId}:{courseWorkId}`
   — announcements use `google_classroom_announcement:{courseId}:{announcementId}`
   — held by a UNIQUE partial index on `activity_sources` (migration 0022).
2. The key is shared across students: whoever syncs first creates the row,
   and every classmate's later sync UPDATEs that same shared row through
   `upsert_activity_from_source`.
3. MANUAL and STUDENT_REPORT entries carry no source key and are NOT
   deduplicated — two students reporting the same real-world face-to-face
   activity create two separate rows.

If a judge asks about title matching: the title-token logic in
`suggest_activity_category` suggests a category; it is not a duplicate
check, and the app has no similarity prompt anywhere in the Beacon editor
(verified by grep, 2026-11-01). The guaranteed dedup is import-only.

## Numbers to Remember

| Number | Fact | Evidence |
|---|---|---|
| 1 | shared backend for both clients | one Supabase project |
| 2 | clients: Android app + teacher dashboard | MainActivity.kt, WebView/ |
| 3 | Edge Functions: classroom-import, classroom-sync, site | supabase/functions/ |
| 4 | request flows (this chapter) | Chapter 3, technical documentation |
| 4 | SQL test suites | rpc_authorization, policies, phase_completion, gc_source_identity |
| 6 | deterministic guidance rules | GuidanceEngine.kt |
| 11 | Android unit-test files (117 tests cited in PLAN.md) | app/src/test/java/com/example/studentcodex/ |
| 12 | class groups a teacher may claim at sign-up | migration 0016 |
| 23 | tables in the schema | migrations 000000–0023 |
| 33 | SQL migrations; hosted through 0028 | supabase/migrations/ |
| 50 | program rows in the seeded registry | programs table, migrations 000000–0012 |
| 2,477 | lines in WebView/app.js | WebView/app.js |

## Where to Point When a Judge Asks

The fastest credible answer is a file name. This table maps the questions
that actually come up to the exact place to point or open.

| If asked about | Point at |
|---|---|
| Beacon visibility rules | activities_select policy, migrations 0019/0020 |
| Import security boundary | supabase/functions/classroom-import/index.ts |
| Sync and token handling | supabase/functions/classroom-sync/index.ts |
| The dedup guarantee | upsert_activity_from_source + gc_source_identity_test.sql |
| Teacher registration gate | migrations 0031 and 0016 |
| The audit and its fix | migration 0032 + rpc_authorization_test.sql |
| Dashboard behavior | WebView/app.js |
| Test evidence | app/src/test/java/com/example/studentcodex/ + the 4 SQL suites |

Every entry above is a repo-relative path you can open live if the venue
allows it. If it does not, name the file anyway — citing the exact artifact
is usually worth more with technical judges than reading another paragraph
of prose.

## Three Sentences to Memorize

If nothing else from this chapter survives the nerves, keep these three
sentences; together they cover the security model, the dedup rule, and the
freshness boundary, which are the three areas judges probe hardest.

1. "The publishable key is public by design — row-level security in the
   database is the boundary."
2. "The service key exists only inside Edge Functions, and migration 0032
   revoked direct client execution of the privileged RPCs — tested locally,
   not yet deployed to the hosted project."
3. "Imported Classroom items are deduplicated by a shared source key, so a
   class converges on one row per coursework item; manually reported
   activities are not deduplicated at all."

Each sentence is deliberately a complete answer, not a teaser — say it,
then stop and let the judge choose the direction. The depth behind every
clause is one table or one file reference away in this chapter, and the
full mechanisms are Chapters 3, 12–14, 19, 22, and 27 of the technical
documentation.

---


# Chapter 32 — Suggested Presentation Flow

This chapter structures a realistic ten-minute defense presentation in
eleven parts, from the opening through the closing line. For every part it
gives the words to say (written out as a spoken script), what to show on
screen, which working feature to demonstrate, the one technical point to
emphasize, and the honest boundary of what not to claim. The scripts are
deliberately plain — no jargon dumps — because the technical depth belongs
to the emphasis sentence and to the question period afterwards. Everything
demonstrated here works in the current build; the exact keystrokes live in
Chapter 33, the Live Demonstration Script, and the one-line architecture
answers live in the Architecture Quick Reference.

## Time Budget at a Glance

The budget adds up to exactly ten minutes. Treat it as a contract: when a
part exceeds its slot, cut material inside the part, never the honesty
boundaries — the "do not claim" lines are what keeps the question period
safe.

| Part | Title | Window |
|---|---|---|
| 1 | Opening + project introduction | 0:00–0:30 |
| 2 | Problem statement | 0:30–1:30 |
| 3 | Proposed solution | 1:30–2:30 |
| 4 | Application architecture | 2:30–3:30 |
| 5 | Student app demonstration | 3:30–4:00 |
| 6 | Activity Beacon demonstration | 4:00–5:00 |
| 7 | Google Classroom integration demonstration | 5:00–6:30 |
| 8 | Teacher dashboard demonstration | 6:30–8:00 |
| 9 | Technical implementation highlights | 8:00–9:00 |
| 10 | Impact and future potential | 9:00–9:30 |
| 11 | Closing | 9:30–10:00 |

## Ground Rules for Delivery

- Say the plain sentence first and the technical term second — "the
  database decides who sees what; that mechanism is row-level security."
- Name the request flow when you touch a screen — "this list is Flow 1,
  PostgREST with RLS" — using the flow map in the Architecture Quick
  Reference.
- One emphasis per part. Deliver it, then stop talking; silence after a
  precise sentence reads as confidence.
- Volunteer the "do not claim" boundary before a judge finds it. "Sync is
  client-triggered, not real-time" costs five seconds and removes a whole
  line of attack.
- If a screen action fails, switch to Chapter 33's backup plan
  immediately — never debug in front of the room.

## Why This Order

The eleven parts run problem, solution, architecture, then four live
parts, then numbers, impact, and close — and the order is not cosmetic. A
talking part precedes each demonstrating part so the audience knows what
they are looking at before the screen changes, and the two trust-critical
demonstrations (Classroom integration, dashboard) sit in the middle where
attention peaks rather than at the end where it decays. The architecture
part comes before the demonstrations so that every flow you name on screen
was already drawn once; it comes after the solution so the diagram is an
answer to "how", not a lecture before anyone cares. The numbers arrive
ninth, after the judges have seen the product, because 33 migrations means
nothing at minute three and everything at minute nine.

## Part 1 — Opening and Project Introduction (0:00–0:30)

**What to say.** "Good morning, and thank you for the time. We are the
Student Codex team. Our project is an Android app for students and a web
dashboard for teachers, running on one shared database, built to put every
recorded academic deadline in one place. In the next ten minutes I will
show you the problem, the running application on both sides, and the
security architecture underneath it."

| Field | Content |
|---|---|
| Show | Title slide with the project name; emulator and browser staged side by side |
| Demonstrate | Nothing yet — hands off the keyboard for the first thirty seconds |
| Emphasize | One shared backend serves both clients; there is no second database and no server of our own |
| Do not claim | Production readiness or deployment scale — one hackathon build against one hosted Supabase project |
| Transition | "Let me start with why this exists." |

Delivery notes: keep the staging visible from the first second — the phone
and the browser window next to the slide tell the judges a live demo is
coming, which buys attention for the two talking parts that follow. Speak
the team name and the one-sentence product description slowly; everything
else in the talk depends on those two sentences landing.

## Part 2 — Problem Statement (0:30–1:30)

**What to say.** "Here is the problem. Google Classroom holds the online
half of a course — the assignments and announcements a teacher posts
there. The face-to-face half never reaches it: a deadline written on the
board or given verbally in a lecture stays in notebooks and group chats.
Students juggle those scattered sources and miss deadlines, and teachers
cannot see whether their deadline collides with another teacher's in a
different section. No existing tool gives a university-wide view of
recorded workload."

| Field | Content |
|---|---|
| Show | One slide with the four fragments: Classroom, board notes, chats, no university view |
| Demonstrate | None — this part is spoken; do not touch the devices |
| Emphasize | The gap is consolidation, not a shortage of tools; Classroom stays the system of record for the online half |
| Do not claim | That Classroom is inadequate as a product, or that this project replaces it — the integration is read-only and complementary |
| Transition | "Our answer is a shared activity record." |

Delivery notes: this is the emotional center of the talk, and it is the
part every student in the room will recognize — let each sentence finish
before starting the next. If you have a personal missed-deadline story
from university, one sentence of it here is worth more than any statistic;
keep it under ten seconds. Resist the urge to preview the solution — the
pause between the problem and the answer is doing real work.

## Part 3 — Proposed Solution (1:30–2:30)

**What to say.** "Our solution is one shared activity record with two ways
in. Students import their Google Classroom coursework — read-only — and
they record the face-to-face activities themselves, straight from the app.
Teachers get a university-wide calendar of recorded, non-personal
activities. Every entry carries a provenance label, so nobody has to guess
where a record came from."

| Field | Content |
|---|---|
| Show | One slide of the core flow: import + manual recording, then the shared activities table, then Beacon + calendar |
| Demonstrate | None yet — the demonstration starts at Part 5 |
| Emphasize | The record is shared: the same table serves the student's private view and the teacher's university-wide view, separated only by row-level security |
| Do not claim | Complete coverage — the dashboard shows recorded information only; nothing guarantees every real-world activity was entered |
| Transition | "Here is how that is built." |

Delivery notes: the words "read-only" and "provenance label" are the two
the judges will re-use in their questions, so pronounce them cleanly and
once each. Gesture at the flow diagram left to right — intake paths on the
left, the shared table in the middle, the two reading surfaces on the
right. If a judge interjects "so it's a calendar app?", answer "it's a
shared record with two intake paths; the calendar is one of two views" and
move on.

## Part 4 — Application Architecture (2:30–3:30)

**What to say.** "Architecturally, it is one shared backend and two thin
clients. The Android app and the teacher dashboard both talk to the same
Supabase project using a public key — row-level security in the database
decides what each user may see. The only privileged code runs in three
Edge Functions on the server, which hold the service key and talk to
Google Classroom. There is no second database and no server of our own to
operate."

| Field | Content |
|---|---|
| Show | The architecture slide — the same picture as the Architecture Quick Reference and Figure 1 of the technical documentation |
| Demonstrate | None |
| Emphasize | RLS is the single policy enforcement point — one rule set to audit instead of two client-side authorization stacks |
| Do not claim | That migration 0032, the RPC privilege hardening, is deployed — it is locally tested, hosted deployment pending; the hosted project runs migrations through 0028 |
| Transition | "Now let me show it running — student side first." |

Delivery notes: point at the diagram in the order data actually moves —
client, key, PostgREST, RLS, then the Edge Function branch to Google. The
phrase "the publishable key is public by design" reliably stops the
security-minded judge mid-note; say it and let it hang for a beat. Keep
this part to sixty seconds even though it is tempting to continue — the
architecture has an entire chapter behind it, and the question period is
where that pays off.

## Part 5 — Student App Demonstration (3:30–4:00)

**What to say.** "This is the student app — a single-activity Kotlin and
Compose application. After signing in with a real account, the student
lands on a home screen with their upcoming deadlines, and the bottom bar
carries four destinations: home, the Activity Beacon, the community, and
settings."

| Field | Content |
|---|---|
| Show | Emulator: sign in with email and password, land on HOME, point at the upcoming list, tap one row to open the detail sheet |
| Demonstrate | Sign-in and the home overview — Live Demonstration Script, Steps 1 and 2 |
| Emphasize | The UI never talks to Supabase directly — screens work through repository interfaces, so no screen code holds a client or an HTTP call (…/studentcodex/data/repo/Repositories.kt) |
| Do not claim | Offline support — the app is online-first; the offline cache is PLANNED and exists only as a design document |
| Transition | "The Beacon is where everything converges." |

Delivery notes: this is a short bridge part — its only job is to prove the
app is real and running on a real account, so do not tour the settings or
the profile here. Sign in before the audience's eyes even if the account
is pre-staged; typing six characters is the cheapest credibility you can
buy. If the keyboard overlays the list on a small emulator, rotate the
window or just point — the list is the point, not the typing.

## Part 6 — Activity Beacon Demonstration (4:00–5:00)

**What to say.** "The Activity Beacon is the consolidated list — everything
the student is responsible for, imported from Classroom and recorded by
hand, grouped by due date with filters for overdue and Classroom-only
items. Watch what happens when I record a face-to-face deadline right now:
it publishes to my section instantly. There is no approval queue, and the
row carries a label saying a student reported it."

| Field | Content |
|---|---|
| Show | BEACON tab: scroll the date-grouped list, tap a filter chip, open a detail sheet; then "Add school works", fill title, type, due date, course, save, and point at the new row |
| Demonstrate | Beacon browsing plus manual activity creation — Live Demonstration Script, Steps 3 and 6 |
| Emphasize | Instant publish with provenance — a student report becomes a real activities row with verification_status 'student-reported', visible to the section and to teachers, with no approval step (migration 0015) |
| Do not claim | Automatic duplicate detection for manual entries — two students reporting the same real-world activity create two rows; only Classroom imports are deduplicated |
| Transition | "Next, the Classroom side of that record." |

Delivery notes: the create-then-appears moment is the strongest thirty
seconds of the student side, so narrate the fields as you fill them and
stop talking while you type. Pre-decide the activity you will create — a
plausible course, a due date within the visible week, a one-word title —
so the editor never stalls on an empty field. If the saved row is not
immediately visible, switch to the "All" filter or briefly leave and
re-enter the tab (the list refreshes on tab resume) before apologizing;
ordering is newest-first, so the row is normally on top.

## Part 7 — Google Classroom Integration Demonstration (5:00–6:30)

**What to say.** "Now the Google Classroom integration — read-only. I open
the course importer, pick my Google account, and my active courses are
listed; I tick the ones I am taking and they become my enrollments. Then a
sync pulls the coursework and announcements as read-only activities — the
summary tells me how many were new and how many refreshed. One detail
worth pausing on: an item my classmate already synced is recognized by its
source key, so my sync updates the shared row instead of creating a
duplicate."

| Field | Content |
|---|---|
| Show | SETTINGS: the importer sheet with the account picker and course checkboxes, "Add selected courses"; then the Classroom card — "Connect & Sync" or "Sync now" — the result summary, and finally BEACON rows wearing the green Classroom badge |
| Demonstrate | Course import, sync, and the provenance badges — Live Demonstration Script, Steps 4, 5, and 7 |
| Emphasize | Server-side dedup via the source-key upsert — one canonical row per coursework item, shared across the class (gc_source_identity_test.sql) |
| Do not claim | Real-time sync — sync is client-triggered (opt-in on app open, or manual), with no background service, no push, no Pub/Sub; a Classroom-side change appears only at the next successful sync. Also: no write-back to Google, ever |
| Transition | "Teacher side now — the web dashboard." |

Delivery notes: this is the longest demonstration part because it carries
two trust stories at once — the OAuth consent and the dedup — so point at
the consent sheet when it appears and name it: "read-only scopes, chosen
by the student." The upsert story lands best if you pre-sync the same
coursework from a second student account before the talk and can say "my
classmate already synced this one." If the live Google path is slow or
fails, switch without drama to the pre-imported account described in
Chapter 33's backup plan.

## Part 8 — Teacher Dashboard Demonstration (6:30–8:00)

**What to say.** "This is the teacher dashboard — plain HTML and JavaScript
with no build step, opened straight from the folder. I sign in with a
teacher account and get a month calendar of recorded activities, with
filters for campus, program, year, and section across the whole
university. The dashed entries are student-reported — the deadline I
created a minute ago is already on this calendar. And a teacher can
correct a wrong category; the correction locks, so future re-syncs cannot
overwrite it."

| Field | Content |
|---|---|
| Show | Browser: dashboard sign-in, the month calendar with chips in the day boxes, a day-detail dialog, the student-reported feed, the cohort filter bar in action, and one category correction with its confirmation toast |
| Demonstrate | Dashboard sign-in, university-wide filters, calendar, category correction — Live Demonstration Script, Steps 10 through 13 |
| Emphasize | The dashboard ships the same publishable key and is governed by the same RLS policies — university-wide visibility comes from the teacher read of non-personal rows (migration 0019), not from a special server |
| Do not claim | Workload analytics — aggregate summaries and proposed-deadline preview are PLANNED; a database view exists but no client consumes it. And recorded is not complete coverage |
| Transition | "A few implementation highlights before we close." |

Delivery notes: switch windows decisively — the contrast between the phone
and the browser is itself the architecture argument, so give the audience
a second to register the platform change. Find the activity you created in
Part 6 on the calendar before the talk by pre-computing its due date, and
tap exactly that day box. The category correction is the one mutating
teacher action; do it on an imported row so the lock story is concrete,
and read the toast aloud — "future Classroom syncs keep it."

## Part 9 — Technical Implementation Highlights (8:00–9:00)

**What to say.** "A few implementation highlights. The schema is 33
migrations and 23 tables, with row-level security on every table a client
can touch. The Android side carries 11 unit-test files, and the database
has four SQL test suites — one of them proves the Classroom dedup. We also
audited the privileged RPCs, found three privilege gaps, and fixed them
with a pure privilege-revocation migration — tested locally; deploying it
to the hosted project is our next roadmap item."

| Field | Content |
|---|---|
| Show | One slide with the key-numbers table from the Project Story chapter; optionally the four SQL test file names |
| Demonstrate | None — or open the repository tree if the venue allows it |
| Emphasize | The audit story — the F1/F2/F3 review found any signed-in user could call privileged RPCs, and migration 0032 revoked those grants without touching a function body |
| Do not claim | All tests green — policies_test.sql is PARTIALLY PASSED with two pre-existing fixture issues; and 0032 is not deployed to the hosted project |
| Transition | "Where this goes next." |

Delivery notes: slow down for the numbers — they are the credibility
payload, and rattling them wastes them. The audit narrative is the part
judges remember from this section, so give it the shape of a story:
looked, found, fixed, tested, next step. Saying "locally tested, not yet
deployed" in the same breath as the fix is not a weakness; it is the
difference between a claim a judge can check and one they cannot.

## Part 10 — Impact and Future Potential (9:00–9:30)

**What to say.** "The impact we aim for is simple: fewer missed deadlines
for students, and fewer colliding deadlines for teachers, on records they
keep anyway. From here, the roadmap is offline caching, workload summaries
for teachers, and push notifications — each one scoped and documented in
the plan."

| Field | Content |
|---|---|
| Show | A roadmap slide: offline cache (PLANNED), workload analytics (PLANNED), notifications (DEFERRED), 0032 hosted deployment (roadmap item M2.1) |
| Demonstrate | None |
| Emphasize | The roadmap is documented with milestones, not improvised — the plan file is the authority for scope and order |
| Do not claim | Measured user impact — no user study or adoption data exists in the project; describe the aim, never results |
| Transition | "To close —" |

Delivery notes: thirty seconds, no more, and absolutely no invented
metrics — the moment a judge hears a fabricated percentage the whole
presentation is repriced. If you want one concrete future sentence, use
the dedup groundwork: the shared source-key record is what makes teacher
workload analytics a query instead of a project. Point at the roadmap
statuses as you name them; the verbatim labels do the honesty work for
you.

## Part 11 — Closing (9:30–10:00)

**What to say.** "So: one shared record. Classroom imports on one side,
face-to-face reporting on the other, an honest calendar for everyone —
with every entry labeled by where it came from. Thank you; we are happy
to take questions."

| Field | Content |
|---|---|
| Show | Closing slide with the project name and the team |
| Demonstrate | None — leave both devices on their final screens in case a question sends you back |
| Emphasize | Repeat the provenance line — it is the sentence you most want the judges to remember |
| Do not claim | A launch date, a production deployment, or anything not already demonstrated |
| Transition | Hand off to the question period; keep the Architecture Quick Reference in reach |

Delivery notes: the closing is three sentences and a stop — do not add a
paragraph because the room is quiet. Leave the emulator on the Beacon and
the browser on the calendar; most first questions are "show me that again,"
and being one tap away is worth more than any final flourish. When the
question period starts, answer from the handbook chapters by their
mechanism, and end every answer on a fact, not an adjective.

## If the Session Runs Long or Short

The eleven parts compress and expand along fixed seams, so the talk stays
honest at any length. The demonstrations and the honesty boundaries are
the last things to go; the slides are the first. Rehearse the cut once so
the compressed version is also a rehearsed version.

- Five-minute slot: keep Parts 1, 2, 3, 7, 8, and 11; fold the Beacon
  creation into Part 7's sync pass, and replace Part 9 with its emphasis
  sentence delivered in Part 8.
- Fifteen-minute slot: expand Part 9 into the authorization ladder from
  the Architecture Quick Reference, and walk the two-student dedup
  sequence live — Student A syncs, Student B syncs, one shared row.
- Question period: never re-open a slide to answer; go to the live app or
  the dashboard, or name the file. "That is upsert_activity_from_source in
  the migrations" ends more threads than another paragraph would.

## Rehearsal Plan

Rehearse in three passes on the real hardware, not on the development
machine, and time only the second pass. The first pass is for content —
say every script out loud and mark every sentence you stumble on; rewrite
those sentences in your own words rather than fighting them. The second
pass is for the clock — run the time-budget table strictly and note which
parts overflow; the overflow is always a demonstration, never a script.
The third pass is the failure drill — pick one demo action, break it on
purpose (airplane mode on the phone, wrong window focus on the browser),
and rehearse the switchover to the backup plan until it takes under ten
seconds and no apology.

Two small habits from rehearsal carry disproportionate value. Rehearse the
transitions as their own lines — the sentence that moves Part 6 to Part 7
is where most speakers lose five seconds and recover thirty. And rehearse
ending on time once with one full minute to spare; knowing the talk fits
in nine minutes is what lets the live ten-minute version breathe instead
of race.

---


# Chapter 33 — Live Demonstration Script

This chapter is the step-by-step checklist for the live portion of the
defense: thirteen actions in order, each of which works in the current
build. Every step states the action, the expected result, what the step
demonstrates, one or two sentences to say, and the failure or fallback —
because a demo you can recover is worth more than a demo that never
breaks. The order matches the demonstration parts of Chapter 32, the
Suggested Presentation Flow (Parts 5 through 8), and the one-line
architecture names to drop while acting are in the Architecture Quick
Reference. Nothing here asks you to touch a feature that is not
`BUILT & VERIFIED`; the two places with verification caveats are flagged
in the step itself.

## Pre-Demo Checklist

Run this list an hour before the room fills, then again five minutes
before. The two most common live failures are a device that is offline and
an account that was never exercised that morning — both are checked here.

| Item | Check |
|---|---|
| Device | Emulator or phone charged, online, screen sleep disabled |
| Google account | Signed in on the device; on an emulator add it under device Settings (strings.xml:69) |
| Student account | Demo student credentials at hand; signed in once that morning |
| Classroom account | Test Google account with ACTIVE courses in Classroom |
| Pre-imported rows | One import and one sync already run on the demo account |
| Auto-sync toggle | State known — if ON, every app open silently syncs (StudentCodexApp.kt:215-234) |
| Dashboard | Open and signed in, in a second window, on the demo teacher account |
| Demo activity | Its due date and month pre-chosen so you can find it on the calendar |
| Teacher-student pairing | Demo teacher teaches the demo student's section, so created rows appear on the calendar |
| Screenshots | Captured as the last-resort fallback for every major screen |
| Timing | Pure demo run timed — about five minutes inside the ten-minute budget |

## The Demonstration, Step by Step

The thirteen steps run login, the student app's three screens, the
Classroom pair (import then sync), the reporting and provenance pair, the
community and guidance pair, then five dashboard actions. Steps 4 and 5
depend on Google; every other step works with the pre-imported account
alone, which is what the backup plan exploits.

### Timing marks

The pure demonstration consumes about five minutes inside the ten-minute
talk, matching the demonstration windows of Parts 5 through 8 in Chapter
32. Steps 8 and 9 (community, guidance) are the flexible pair — they
compress to a sentence each when the clock is behind.

| Step | Belongs to | Target |
|---|---|---|
| 1 Login | Part 5 | 20 s |
| 2 Student home | Part 5 | 15 s |
| 3 Activity Beacon | Part 6 | 25 s |
| 6 Face-to-face reporting | Part 6 | 30 s |
| 4 Classroom import | Part 7 | 30 s |
| 5 Activity sync | Part 7 | 35 s |
| 7 Provenance | Part 7 | 15 s |
| 8 Community | Part 5 extension or after Part 6 | 25 s |
| 9 Guidance Assistant | Part 5 extension or after Part 6 | 25 s |
| 10 Teacher dashboard | Part 8 | 20 s |
| 11 University-wide filters | Part 8 | 20 s |
| 12 Calendar | Part 8 | 25 s |
| 13 Category correction | Part 8 | 20 s |

### Step 1 — Login (student app)

| Field | Content |
|---|---|
| Action | Launch the app; on the "Welcome back" card, sign in with the demo account's email and password |
| Expected | The auth gate resolves to the signed-in state and the bottom navigation appears: HOME, BEACON, COMMUNITY, SETTINGS |
| Demonstrates | A real Supabase Auth session — the publishable key plus a session RLS can key on |
| Say | "Sign-in is a real Supabase session — email and password. There's also a guest demo mode, but I'll use a real account." |

**Failure or fallback.** Prefer the email path live: Google Sign-In via
Credential Manager is `IMPLEMENTED — VERIFICATION INCOMPLETE` (verified
during development; not re-exercised in the 2026-10-30 pass). If "Continue
with Google" fails, the app itself prints guided reasons — Play services
or account missing, or the app's signing fingerprint not registered
(strings.xml:68-70) — so acknowledge the message and continue with
email/password. Email confirmation is OFF (test configuration), so a fresh
sign-up also receives a session immediately.

### Step 2 — Student home

| Field | Content |
|---|---|
| Action | Stay on HOME; point at the "Upcoming deadlines" list; tap one row to open the detail sheet |
| Expected | Upcoming activities with due metadata; the tap opens the full-content sheet with the See more / See less expansion |
| Demonstrates | The per-student consolidated view, read from the shared activities table under RLS |
| Say | "Everything I'm responsible for, in one list — this is the same table the teachers' calendar reads." |

**Failure or fallback.** If the list is empty, the screen states "Nothing
due soon" (strings.xml:126-127) — switch to the Beacon tab, which is
always populated on the pre-imported account. Do not linger on an empty
state; it reads as a broken demo even when it is correct behavior.

### Step 3 — Activity Beacon

| Field | Content |
|---|---|
| Action | Tap BEACON; scroll the date-grouped list; tap filter chips (All, Overdue, Classroom, Assignments); open a row's detail sheet |
| Expected | Newest-first grouped list; chips narrow the list; the Classroom chip isolates imported rows (BeaconScreen.kt:286-295) |
| Demonstrates | One list combining imported, manual, and student-reported entries with filters |
| Say | "One list — Classroom items and hand-recorded ones, grouped by due date, filterable." |

**Failure or fallback.** A filter with no matches shows a dedicated
empty-state message rather than a blank screen (BeaconScreen.kt:225-228) —
return to "All" and continue. The list refreshes silently on tab resume,
so a missing row usually appears after leaving and re-entering the tab
(BeaconViewModel.kt:123-131).

### Step 4 — Classroom course import

| Field | Content |
|---|---|
| Action | SETTINGS, then "Change school details", then "Import from Google Classroom"; choose the Google account in the system picker; tick courses; tap "Add selected courses" |
| Expected | "Connecting to Google Classroom…", then the course list with section labels; the ticked courses are added as enrollments |
| Demonstrates | Read-only OAuth consent plus the classroom-import Edge Function path — Flow 2 |
| Say | "Read-only scopes, my explicit account choice — and the server re-fetches the courses itself before writing anything." |

**Failure or fallback.** If the test account has no active courses the
sheet says so plainly (strings.xml:322) — switch to the prepared Classroom
test account. A transport failure shows "Google Classroom import failed —
try again." (strings.xml:326); retry once, then fall back to the
pre-imported account and narrate Flow 2 from the Architecture Quick
Reference. The picker requires Play services and a signed-in Google
account on the device — both are on the pre-demo checklist.

### Step 5 — Activity synchronization

| Field | Content |
|---|---|
| Action | In SETTINGS, on the Google Classroom card, tap "Connect & Sync" (first connection) or "Sync now" (already connected) |
| Expected | A "Syncing…" indicator, then the summary "Imported N new · refreshed M activities from K classes." (strings.xml:310); Beacon now shows green-badged Classroom rows |
| Demonstrates | Client-triggered sync — the Edge Function verifies the session JWT, then upserts on the source key — Flow 3 |
| Say | "Client-triggered, not real-time — and no duplicates: each item upserts on its source key." |

**Failure or fallback.** Declined consent yields "No Google authorization
given — nothing was synced." (strings.xml:313); a partial match yields
"…no match for: <classes>" (strings.xml:311), which is honest behavior —
name the matching tiers and move on. Remember the auto-sync toggle: if
"Auto-sync school works" is ON, opening the app has already synced
silently, so the summary may report zero new items; that is correct, not
broken (StudentCodexApp.kt:215-234). Status note if a judge asks how sync
was verified: `BUILT & VERIFIED` — live browser-verified 2026-10-28, with
the Edge Functions not re-exercised against real Google OAuth in the
2026-10-30 SQL run.

### Step 6 — Face-to-face activity reporting

| Field | Content |
|---|---|
| Action | BEACON, tap "Add school works"; fill title, notes, type, due date, course/section; save |
| Expected | The editor's hint reads "Shared with your course section — … No approval needed." (strings.xml:164); the new row appears in the list immediately |
| Demonstrates | Instant student self-publish with no approval queue (migration 0015) |
| Say | "A face-to-face deadline, recorded by a student, on the section calendar — no approval step anywhere." |

**Failure or fallback.** If save does not proceed, re-check the required
fields — the editor takes title, type, due date, and course. If the row is
not immediately visible, switch to the "All" filter or briefly leave and
re-enter the tab — the list refreshes on tab resume
(BeaconViewModel.kt:123-131), and ordering is newest-first, so the row is
normally at the top. The same row is the one you will find on the teacher
calendar in Step 12 — its due date was pre-chosen on the checklist for
exactly that reason.

### Step 7 — Activity provenance

| Field | Content |
|---|---|
| Action | In BEACON, contrast a Classroom row (green "Google Classroom" badge) with the manually created row (manual badge); open each detail sheet and point at the verification label |
| Expected | Distinct badges on the rows and distinct verification labels in the sheets |
| Demonstrates | Provenance resolved from the row itself, not inferred (SupabaseActivityRepository.kt:203-213) |
| Say | "Every row says where it came from — imported, manual, or student-reported." |

**Failure or fallback.** This step depends on Step 5 (or the pre-imported
account) having produced imported rows; if none exist, skip to the manual
row and make the provenance point verbally. Do not claim the app detects
duplicate manual reports — it does not, and the Beacon editor has no
similarity prompt anywhere.

### Step 8 — Community

| Field | Content |
|---|---|
| Action | Tap COMMUNITY; open the composer ("What's on your mind?"); type a short study post, optionally attach one photo, tap Post; like a post; open comments and add one |
| Expected | The post appears in the feed; the like toggles; the comment appears under the post |
| Demonstrates | The RLS-guarded social layer and the private community-images Storage bucket |
| Say | "Signed-in students only — guests can read but can't post, like, or comment." |

**Failure or fallback.** The composer is read-only for guests
(strings.xml:245), so be signed in before this step. Image upload needs
connectivity; if it stalls, post without the photo — the post itself is
the point. Rate-limit guards exist on posts, comments, and reports
(migration 0008), so do not post repeatedly in a burst during rehearsal
runs against the same account.

### Step 9 — Guidance Assistant

| Field | Content |
|---|---|
| Action | Drag the floating chat head; tap to open the panel; tap a suggested topic ("How does the Activity Beacon work?"); then type a nonsense question |
| Expected | A direct answer with follow-up suggestions; nonsense gets the honest fallback "I do not have a reliable answer for that yet…" (GuidanceEngine.kt:127-132) |
| Demonstrates | A deterministic, rule-based engine — six rules with precedence, no external model |
| Say | "Deterministic rules, not an LLM — and it says so when it doesn't know." |

**Failure or fallback.** The engine is local and rule-based, so this step
cannot fail on the network. If the overlay is hidden, re-enable it in
SETTINGS under "Floating assistant" — chat head or edge panel
(strings.xml:285-290). One honesty trap: the canned answer about adding
activities mentions a same-activity check before saving; the app has no
such prompt, so do not repeat that claim.

### Step 10 — Teacher dashboard

| Field | Content |
|---|---|
| Action | Switch to the second window: open `WebView/index.html` (double-click, or serve the folder); on the sign-in card tap "Use demo teacher credentials", then sign in |
| Expected | The dashboard loads with the cohort filter bar, the month calendar, the student-reported feed, and the data-coverage card |
| Demonstrates | The second client on the same backend — publishable key only, RLS deciding — Flow 4 |
| Say | "Same backend, same key, same rules — this is a static folder with no server of its own." |

**Failure or fallback.** The demo teacher accounts and their credentials
are documented in `WebView/README.md` — cite the location, never read the
values aloud; the fill button writes them into the form without typing
(WebView/app.js:746-749, 2101-2103). If sign-in fails, use one of the
other documented demo teacher accounts and re-check that the hosted
project is reachable. The dashboard needs the network like the app does.

### Step 11 — University-wide filters

| Field | Content |
|---|---|
| Action | Use the campus / program / year / block dropdowns; watch the live "N of M sections" count; tap Reset |
| Expected | The view narrows to the picked cohort, the count line updates, Reset restores the full registry |
| Demonstrates | Registry-driven university-wide filtering (filterBarHtml, WebView/app.js:1193-1237) |
| Say | "Every dropdown is fed by the live school registry — nothing here is hard-coded." |

**Failure or fallback.** A cohort none of your sections match shows the
inline no-match note — that is RLS keeping the data to taught sections,
not a failure; pick a cohort the demo teacher actually teaches, or Reset.
If the dropdowns feel slow, let the count line finish updating before
speaking; it is a live registry query, and the pause is explainable.

### Step 12 — Calendar

| Field | Content |
|---|---|
| Action | Navigate prev / next / Today; open a day with entries (day-detail dialog); open one entry (full activity sheet); toggle a legend category filter; point at the dashed student-reported chip and a grayed past-due entry |
| Expected | Type-colored chips inside day boxes; the day sheet lists entries; the full sheet shows course, section, time, effort, description, and verification badge; legend toggles filter categories |
| Demonstrates | The university-wide calendar of recorded non-personal activities under RLS (migration 0019) |
| Say | "The dashed one is the deadline a student reported minutes ago — recorded, which is not the same as complete coverage." |

**Failure or fallback.** An empty month simply has no recorded activities
— navigate to the month you pre-chose on the checklist, where the Step 6
activity and the imported rows live. Overlays stack correctly (day sheet,
then activity sheet on top), so if you land in the wrong sheet, close the
top one and re-tap the entry; Escape and backdrop clicks both close.

### Step 13 — Category correction

| Field | Content |
|---|---|
| Action | In an activity sheet, use the category row (six options) and pick a different type |
| Expected | A toast: "Category updated — Now tracked as <type>. Future Classroom syncs keep it." (WebView/app.js:2215-2218); the chip re-renders in the new category color |
| Demonstrates | Teacher category correction locked across re-syncs — category_locked (migration 0023) |
| Say | "The teacher's correction sticks — the next Classroom sync will keep it." |

**Failure or fallback.** Corrections are RLS-restricted to taught
sections; the refusal reads "You can only correct categories for sections
you teach." (WebView/app.js:2206) — switch to an entry in a taught
section and continue. The option buttons disable briefly while the update
round-trips (categoryBusy); wait for the toast rather than tapping twice.

## Backup Plan

Assume something will fail and decide the recovery before the room fills;
every fallback below preserves the honesty of the demo rather than the
theater of it. The three assets that make recovery painless are the
pre-imported demo account, the already-open dashboard window, and the
screenshot set — all on the pre-demo checklist.

### If Google authentication fails

Fall back to email/password sign-in, which is `BUILT & VERIFIED`, and let
the app's own guided error messages carry the explanation — the three
documented Google failure modes each print their reason on screen
(strings.xml:68-70). Skip the live import and sync (Steps 4 and 5) and
show their results instead: the pre-imported account already holds
imported rows with Classroom badges, and the Settings card still shows the
last sync summary. Narrate Flows 2 and 3 from the Architecture Quick
Reference — the account-choice step, the JWT check, the service-key RPC —
because the mechanism is the claim, not the animation.

### If the internet fails

Say it plainly: the app is online-first by design and there is no offline
path — the offline cache is `PLANNED`. Switch to the screenshot set and
keep the narration in the same order as the live steps, so the audience
can still follow the sequence. The dashboard window, if already loaded,
may continue to answer from its cached month data briefly, but treat that
as seconds, not minutes. Do not pretend a connection exists — a judge who
notices a fake live demo discounts everything after it.

### If the emulator itself fails

Keep a physical device with the app installed as the mirror of last
resort — the app runs from minSdk 26, so almost any recent phone qualifies
(`app/build.gradle.kts:143`). If the projected screen fails but the device
works, present with the device in hand and narrate harder; if both fail,
the dashboard window and the screenshot set still carry the story. A
mirroring failure is a venue problem, so say so once and continue — the
audience forgives cables, not confusion.

### The pre-imported demo account

Before the talk, sign into the demo student account and complete Steps 4
and 5 once — the import, the sync, and one manual activity — so the
account is fully populated no matter what happens live. Demo seed data
also lives on the hosted project (migrations 0009-0011: a demo teacher,
students, courses, sections, enrollments, activities, and posts), so the
dashboard is never empty either. Screenshots are the final tier: capture
the Beacon with mixed provenance, the sync summary, the dashboard
calendar with the student-reported chip, and the category-correction
toast — four images cover the whole story.

### Credentials and accounts

Never display a credential value on screen or read one aloud. The demo
teacher accounts are documented in `WebView/README.md`, and the sign-in
card's "Use demo teacher credentials" button fills the form without
typing (WebView/app.js:746-749) — cite the README's location if asked.
The hosted project's auth mailer is capped at 2 emails per hour
project-wide and email confirmation is OFF, so create any fresh accounts
before the day of the defense and never rely on a password-reset email
live.

## What Never to Do Live

- Do not debug an error in front of the room — switch to the fallback.
- Do not create a new account live unless sign-up itself is the point;
  use the prepared accounts.
- Do not toggle the auto-sync switch mid-demo without saying so — its
  effect at the next app open surprises presenters more than judges.
- Do not claim a status the fact base does not carry; when in doubt,
  say what the screen just showed and stop.
- Do not end on an error state; if a step fails, finish its point with
  the screenshot or the narration and move forward.

## After the Demonstration

Leave the emulator on the Beacon and the browser on the calendar — most
first questions are "show me that again," and being one tap away beats
any closing flourish. Rows created during the demo (the reported activity,
the community post) stay in the database: the app's edit and delete
affordance covers personal manual rows only (BeaconScreen.kt:344), so a
section-scoped demo row is not removable from the app UI — leave it, and
say it is demo data if asked. Decisions about demo and seed data on the
hosted project are a roadmap item (M5.3, production data decisions), not
something to improvise live; the demo seed rows from migrations 0009-0011
live there by design.

---


# Chapter 34 — Technical Judge Q&A (Part 1)

This file is the first half of the defense question bank for Student Codex. It
collects the questions technical judges ask most often about what the product is,
how it is built, and how the Google Classroom integration behaves, and it gives a
defensible answer for each. Every entry follows the same shape: the judge's
question; a direct answer in plain language first; then the technical mechanism
with the real names of the files, functions, migrations, and tests involved; then
an evidence line; and, where the system has an honest boundary, a limitation line.
Nothing in this file upgrades a capability. Classroom sync is client-triggered,
the app is online-first, manual reports publish unverified, and migration 0032 is
locally tested but not deployed to the hosted project — every answer below keeps
those anchors intact.

Citation conventions: the Kotlin root is
`app/src/main/java/com/example/studentcodex/`, abbreviated `…/studentcodex/`
after this first mention. SQL migrations live under `supabase/migrations/` and are
cited by file (000200, 001500, 002300, and so on) or by short number after first
use. Edge Functions are cited by name (`classroom-import`, `classroom-sync`,
`site`) with line numbers from their source. Capability status labels — for
example `PLANNED`, `DEFERRED`, `KNOWN LIMITATION`, and
`IMPLEMENTED — VERIFICATION INCOMPLETE` — are the project's verbatim labels and
are never upgraded anywhere in this document set.

> NOTE: Answers state boundaries on purpose. A judge trusts the team that says
> "no, we do not do that — here is what happens instead" far faster than the team
> that claims every capability and loses one challenge.

## Product, Positioning, and Architecture (Q1–Q5)

Opening questions are positioning questions, and the judge is listening for
whether the team knows whose problem they solve. The defensible stance is that
Student Codex complements Google Classroom rather than competing with it:
Classroom holds whatever a teacher publishes online, while face-to-face
announcements — a deadline written on the board, a verbal reminder in a
laboratory session — never reach it, and no existing tool gives teachers a
university-wide view of recorded workload. Architecture questions then probe the
three-part shape of the product: a native Android app, a static-file teacher
dashboard, and one shared Supabase backend. The position to hold is that one
database is the single source of truth with one row-level security rule set, so
there is no second copy of the data to synchronize and no application server whose
authorization code could be bypassed by a direct PostgREST call. The five answers
below give the exact mechanisms behind that stance.

### Q1 — Why build Student Codex when Google Classroom already exists?

**Q:** Google Classroom already tracks coursework and deadlines. Why did you build
a separate product instead of just using it?

**A:** Student Codex is a complement to Google Classroom, not a replacement.
Classroom contains only what a teacher publishes online; face-to-face
announcements such as board notes and verbal deadlines never reach it, and no
tool gives university-wide visibility of recorded workload. Student Codex
consolidates both channels into one activity list per student and one shared
calendar per course section.

The mechanism is a single table with provenance. The `classroom-sync` Edge
Function imports Classroom coursework and announcements as read-only rows into
the `activities` table; anything Classroom does not carry is typed once into the
Beacon editor and saved into the same table through the same schema. Every row
carries its origin — `GOOGLE_CLASSROOM`, `MANUAL`, or `STUDENT_REPORT` — resolved
from the row itself in `SupabaseActivityRepository.kt:203-213`, so the
consolidated list always shows where each deadline came from.

**Evidence:** read-only scopes in
`…/studentcodex/data/auth/ClassroomAuthorization.kt:75-81`; the `classroom-sync`
Edge Function; `…/studentcodex/data/supabase/SupabaseActivityRepository.kt:203-213`
(provenance resolution); migration 0015 for the manual channel.

**Limitation:** consolidation is only as complete as what students import or
record — recorded is not the same as complete coverage of real university
activity.

### Q2 — What problem does your application solve that Google Classroom does not?

**Q:** Name the gap precisely. What can a student or a teacher do here that
Classroom does not offer?

**A:** Two gaps. For students, face-to-face announcements have no system of
record: a deadline said aloud in class or written on the board exists nowhere
digital, so students reconstruct it from notes and group chats. For teachers, no
existing tool shows what has actually been recorded across a whole university —
workload visibility stops at the teacher's own Classroom courses.

Student Codex closes both gaps with one shared table. A student records the
face-to-face deadline once in the Beacon editor and it publishes instantly to
their course section (migration 0015); teachers then read every non-personal
section activity university-wide on the dashboard calendar (migration 0019),
including a read-only feed of student-reported entries and a data-source card
that states which provenance the view rests on.

**Evidence:** `supabase/migrations/001500_self_publish.sql` (instant section
publish, no approval queue); `supabase/migrations/001900_global_visibility.sql`
(university-wide teacher reads); `WebView/app.js:1355-1410` (student-reported
feed plus coverage card).

**Limitation:** the dashboard shows recorded information only — there is no
guarantee that all real-world university activities have been entered.

### Q3 — Why did you choose Supabase?

**Q:** What justified Supabase over a custom server, Firebase, or self-hosted
PostgreSQL?

**A:** The security model and the platform match. Both clients hold only the
publishable key, which is public by design, so authorization must live in the
database — and Supabase's PostgreSQL with row-level security is exactly that.
Supabase Auth handles email/password sign-in and the Google ID token
exchange. Three small Deno services — `classroom-import`, `classroom-sync`, and
the public `site` — are the entire custom server surface, each with one job,
which keeps the audit target small. Edge Functions are also the only server
context in which the service-role key exists, which is what the Google Classroom
API calls and the trusted import RPCs need. Storage supplies the private
community-images bucket, and the schema ships as 33 versioned SQL migrations, so
the database is reviewable as code.

**Evidence:** `…/studentcodex/di/AppContainer.kt:48-62` (one client built from
URL plus publishable key only); `app/build.gradle.kts:91-133` (the build rejects
secret or service-role keys outright); `supabase/migrations/` 000000–003200; the
decision is recorded in `docs/ADR-001-supabase-first.md` (referenced from
`AppContainer.kt:48-56`).

**Limitation:** the hosted project has migrations applied only through 0028;
0029–0032 exist locally, and deploying them is roadmap item M2.1.

### Q4 — Why use one shared database for both apps?

**Q:** Why do the Android app and the teacher dashboard share one backend instead
of each having their own?

**A:** One database means one source of truth, one RLS rule set, and no
database-to-database synchronization to build, run, or debug. A student's manual
report appears on the teacher's calendar immediately because both clients read
the same `activities` row — there is no export step, queue, or replication hop in
between.

The dashboard side barely needs to exist as a system: `WebView/` is six files of
vanilla HTML, CSS, and JavaScript with two vendored libraries, no build step, and
no server of its own (`WebView/README.md`). It talks to the same hosted Supabase
project through supabase-js with the same publishable key, and row-level security
decides what a teacher may read. The Android app reaches the same tables through
the supabase-kt client. One rule set protects both doors.

**Evidence:** shared-backend request flows, verified 2026-10-31
(`plan-push/evidence/AUDIT-EVIDENCE.md`); `WebView/README.md` (static files, no
framework, no build step); migration 0019 (the teacher read path).

**Limitation:** a shared backend also means shared deployment state — the hosted
project runs migrations through 0028, so the pending 0032 deployment affects both
clients at once.

### Q5 — How does the Android app communicate with the backend?

**Q:** What is actually on the wire? Does the app call your database functions
directly?

**A:** The app speaks HTTPS to PostgREST through the supabase-kt community
client (pinned via the Supabase BOM 3.6.0 with ktor-client-okhttp 3.4.3): reads
and writes go to RLS-checked tables. The app makes zero direct RPC calls —
verified across the code base, every call is either a REST table operation or an
Edge Function invocation. Classroom flows call the `classroom-import` and
`classroom-sync` Edge Functions with the Supabase session JWT in the
Authorization header and the short-lived Google access token in the request body.
Community images upload to the private Storage bucket, and the session itself
persists locally through multiplatform-settings. Every table request is scoped
by RLS to the signed-in user, so the client never receives rows it is not
allowed to see; the teacher dashboard is symmetric with this, using supabase-js
against the same PostgREST API.

**Evidence:** `…/studentcodex/di/AppContainer.kt:57-62` (the single client);
`app/build.gradle.kts:210-236` (auth-kt, postgrest-kt, storage-kt, functions-kt,
ktor-client-okhttp, multiplatform-settings); zero-RPC claim from the 2026-10-31
audit (`plan-push/evidence/AUDIT-EVIDENCE.md`).

**Limitation:** every data operation requires connectivity — the app is
online-first; only the on-device Guidance engine works without a network.

## Google Classroom Integration, Sync, and Deduplication (Q6–Q12)

This is the cluster judges probe hardest, because it is where the product touches
an external system with its own identity and timing semantics. Three anchor facts
hold every answer together. First, the integration is read-only: three readonly
scopes, import-only, never a write-back to Google. Second, it is
client-triggered: a sync runs only when the app is open — the opt-in auto-sync on
app start, the manual button, or the import picker — with no push channel and no
Pub/Sub anywhere. Third, imported identity is the source key
`google_classroom:{courseId}:{courseWorkId}`, enforced unique at the database
level. Everything else follows from those three: several students converge on one
canonical row, a teacher's deadline edit lands whenever some student next syncs,
and revoked consent surfaces on the next failed attempt. Expect the judge to test
the negative space — what the system does not do — and volunteer it before being
asked.

### Q6 — How does Google Classroom authentication work?

**Q:** Walk me through what happens when a student connects Classroom. Where do
tokens live?

**A:** Authorization is per run and per account. The app uses Google's on-device
Authorization API (play-services-auth) to request the three read-only Classroom
scopes; when consent is needed, the returned PendingIntent launches Google's own
consent sheet, and the completed handshake yields a short-lived access token.
That token is used for exactly one sync run and is never stored — no refresh
tokens and no client secrets exist anywhere in the app.

Two guards make the flow honest. First, the Google account is the student's
explicit choice: the system account picker with a 180-second timeout
(`GoogleAccountResolution.kt`), and later silent requests are pinned to exactly
that account, so a background run can never import another account's roster
(`ClassroomAuthorization.kt:125-128` and `:311-362`). Second, the Edge Function
independently verifies the caller's Supabase session JWT via `/auth/v1/user`
before touching anything (`classroom-sync` :48-59).

**Evidence:** `…/studentcodex/data/auth/ClassroomAuthorization.kt` (scopes
`:75-81`; token model `:131-137`); `…/data/auth/GoogleAccountResolution.kt`;
`classroom-sync` :48-59.

**Limitation:** tokens are minted per run, so a revoked or expired grant surfaces
only at the next sync attempt — there is no stored token state that could detect
it earlier.

### Q7 — How do you prevent imported activities from appearing multiple times?

**Q:** If a student syncs twice, or re-imports a course, what stops duplicate
rows?

**A:** Every imported item carries a provider identity that the database enforces
as unique. The `classroom-sync` Edge Function computes a source key such as
`google_classroom:{courseId}:{courseWorkId}` and calls the trusted RPC
`upsert_activity_from_source`, which resolves the key first: a first import
inserts the activity plus its `activity_sources` row; a re-import updates the
same shared row in place. The hard guarantee is the partial unique index on
`activity_sources.source_key` — a second row with the same key simply cannot
commit. Repeated sync attempts therefore converge the data instead of
duplicating it, and the sync summary reports `imported` versus `updated` counts
honestly rather than claiming everything is new. The `gc_source_identity_test.sql`
run also proved the retry-safe shape of the upsert against the partial index —
including the detail that `ON CONFLICT` needs the `WHERE source_key IS NOT NULL`
predicate in order to target it at all.

**Evidence:** `supabase/migrations/000200_activities.sql:49-73` (source key plus
both unique indexes); `supabase/migrations/002300_category.sql:86-169` (the
upsert RPC); `classroom-sync` :199-243 (`importItem`); `gc_source_identity_test.sql`
(PASSED 2026-10-30).

**Limitation:** the guarantee covers imported items only — manual entries have no
equivalent identity and are not deduplicated (see Q15).

### Q8 — What happens when several students synchronize the same course?

**Q:** Two classmates both connect Classroom and both sync the same course. Do
you get two copies of every assignment?

**A:** No — they converge on the same rows, because the identity comes from
Google, not from the student. Classroom course and coursework IDs are shared
across everyone enrolled, so both students compute the same source key and the
upsert resolves to one canonical activity row: the first sync creates it, the
second refreshes it.

Course-level convergence is handled in `import_student_classroom_courses`. A
partial unique index on `courses.external_course_id` makes each Classroom course
a one-to-one link to exactly one local course row. Advisory transaction locks
serialize concurrent imports per course and per section, in a deterministic
global order, so classmates racing to import the same course converge on the same
course and section rows instead of deadlocking or duplicating. Enrollment itself
is idempotent — `ON CONFLICT (section_id, user_id) DO NOTHING`.

**Evidence:** `supabase/migrations/002200_course_import.sql:111-115` (advisory
lock), `:119-170` (resolution tiers), `:220-225` (idempotent enrollment);
`002300_category.sql:113-141` (shared-row update); `classroom-sync` :199-243.

**Limitation:** two concurrent first-time imports of the same coursework item
race on the unique index; the losing run fails and converges on its next
attempt — duplicate rows still cannot commit.

### Q9 — How do you know two imported activities represent the same assignment?

**Q:** Deduplication by key sounds fine, but how do you know the key identifies
the same real-world assignment?

**A:** Because Google guarantees it, and the design does not second-guess the
provider. Classroom course IDs and coursework IDs are globally unique and stable
for the life of the item, and the source key is their concatenation —
`google_classroom:{courseId}:{courseWorkId}` for coursework, and
`google_classroom_announcement:{courseId}:{announcementId}` for announcements, a
separate namespace so a post and a coursework item can never collide. A composite
unique index on `(provider, external_course_id, external_item_id)` is the second
guard, and the `guard_activity_source_insert` trigger rejects any client attempt
to forge a `google_classroom` source row — only the trusted sync service may
create them. Identity is therefore a fact Google asserts, enforced twice at the
database and once at the trigger layer. In short, the same real-world assignment
always yields the same IDs from Google, whoever asks, and those IDs are the only
identity the import trusts — which is why classmates' syncs converge instead of
colliding.

**Evidence:** key construction in `classroom-sync` :305 and :338;
`000200_activities.sql:56-73` (table plus both unique indexes);
`000200_activities.sql:255-265` (source guard trigger).

**Limitation:** identity is provider-scoped. A manually entered look-alike is not
matched to the imported row — there is no cross-source dedup between Classroom
items and manual entries.

### Q10 — What happens when a professor changes an assignment deadline?

**Q:** A teacher edits a due date in Classroom. When do your users see the new
deadline?

**A:** On the next successful sync by any student in that course — not before.
The integration is client-triggered, with no push channel: sync runs happen on
app open (opt-in auto-sync), on the manual "Sync now" button, or through the
import picker. When one runs, the Edge Function re-fetches the current coursework
from Google, and `upsert_activity_from_source` updates the shared canonical row's
title, description, and `due_at` in place. Because that one row is what every
student in the section reads, the new deadline appears for everyone on their next
list load — one student syncing updates the record for all classmates. Due dates
that Classroom carries without a time are normalized to end-of-day 23:59
Asia/Manila (fixed +08:00, no DST). If a teacher has corrected the row's category
in Student Codex, that correction survives the re-import via `category_locked`;
the content fields always follow Classroom.

**Evidence:** the update branch in `002300_category.sql:117-134`; date
normalization in `classroom-sync` :245-258; the sync-trigger inventory (FACTBASE
§11, search-verified: no push, no Pub/Sub anywhere in functions or migrations).

**Limitation:** KNOWN LIMITATION — if nobody syncs, the old deadline stays; there
is no server-side change detection. Event-driven Pub/Sub sync is roadmap item
M4.1, `PLANNED` (future only).

### Q11 — Does the application synchronize in the background?

**Q:** Does anything run while the app is closed? What exactly is "auto-sync"?

**A:** No. Nothing runs while the app is closed — there is no background service,
no WorkManager, and no Firebase messaging anywhere in the code base
(search-verified: zero matches). All Classroom sync is client-triggered from three
places: the opt-in auto-sync on every app open or return from background
(`Lifecycle.Event.ON_START`), the manual sync button in Settings, and the course
import picker.

"Auto-sync" is precisely scoped. It is a SharedPreferences toggle; when on,
`ClassroomAutoSyncer.runIfDue` checks the connection state, requests a
silent-only token pinned to the connected Google account, and runs the same
idempotent Edge Function the manual button runs. If Google would need a consent
sheet, the run is skipped — never a dialog. Failures stay quiet and are retried
on the next open, and an AtomicBoolean guards against overlapping runs.

**Evidence:** `…/studentcodex/ui/StudentCodexApp.kt:215-234` (ON_START
observer); `…/studentcodex/data/repo/ClassroomAutoSync.kt:34-91`;
`…/studentcodex/ui/settings/SettingsScreen.kt:305-320`.

**Limitation:** KNOWN LIMITATION — no background or push delivery exists; push
notifications are `DEFERRED`, and event-driven sync is M4.1 `PLANNED`.

### Q12 — What happens when a student has no internet connection?

**Q:** You claim no offline mode. What does the user actually experience on
airplane mode?

**A:** The app degrades honestly. A first data load without connectivity lands in
the Error state with an explicit retry action; a silent refresh on tab resume
keeps whatever was last on screen, and on failure it keeps showing the last good
list. Writes are not queued anywhere — creating or editing an activity requires
connectivity and fails visibly. The only local persistence is SharedPreferences
via multiplatform-settings (the session, the auto-sync toggle, overlay
preferences); there is no Room or DataStore cache of any table. The one
capability that keeps working fully offline is the Guidance assistant, whose
deterministic rule engine runs entirely on-device with no network calls and an
honest fallback for input it cannot match. The persisted session keeps the student
signed in, and the last good list lives only in the ViewModel's memory — there is
no on-disk copy of any table anywhere in the app.

**Evidence:** `…/studentcodex/ui/beacon/BeaconViewModel.kt:96-141` (Loading and
Error states; silent refresh keeps the last good list); the technology-stack
inventory (FACTBASE §5: multiplatform-settings is the only local persistence);
`…/studentcodex/domain/guidance/GuidanceEngine.kt` (no network dependency).

**Limitation:** KNOWN LIMITATION — offline cache and a write outbox (Room plus
WorkManager) are `PLANNED` (roadmap M3.1); `docs/OFFLINE-SYNC.md` describes that
unbuilt design and is labeled as such.

## Manual Entries and the Online-First Boundary (Q13–Q16)

Manual entry is where the project's honesty policy does the most work, because
the honest answer is that the system trusts its users and says so in the
interface. A face-to-face deadline is recorded by one student, publishes
instantly to the whole section, and is labeled `student-reported` so every reader
can weigh it accordingly. No approval queue reviews it, no matching logic merges
duplicate reports of the same real-world task, and no offline queue lets a
student record anything without connectivity. Each of those is a deliberate MVP
boundary rather than an oversight, and each is documented in the code, the
strings, and the plan. The defense posture for this cluster is to state the
boundary first and the mechanism second. Judges consistently reward teams that
volunteer their limits instead of being cornered into them, and these four
questions are exactly the corner judges aim for.

### Q13 — How are face-to-face activities entered?

**Q:** A deadline was announced verbally in class. How does it get into the
system?

**A:** By hand, once, in the Beacon editor. The add button opens a sheet with
title, notes, a type, a due date, and a course picker fed by `getMySections()` —
the signed-in user's own sections, from enrollments plus taught sections for
teacher accounts. Saving writes one `activities` row scoped to that section and
publishes instantly to the cohort calendar: classmates and teachers see it with
no approval step. The creator's enrollment role decides the trust label — a
student saves as `verification_status='student-reported'`, a teacher as
`'teacher-confirmed'` — and the `guard_activity_insert` trigger raises an
exception if the role and the label disagree, so the labeling cannot be forged
client-side. The section picker is also the only cohort question the editor asks:
the section row itself encodes program, year, and block, so nothing about the
cohort is asked twice.

**Evidence:** `…/studentcodex/data/repo/Repositories.kt:26-42` (`ActivityDraft`)
and `:53-61` (`MySection`); migration 0015;
`000200_activities.sql:188-208` (`guard_activity_insert`);
`…/studentcodex/ui/beacon/BeaconScreen.kt` (editor sheet).

**Limitation:** instant publish with no approval queue, and the editor has no
effort field — estimated effort renders only on imported rows.

### Q14 — How do you prevent false manual reports?

**Q:** What stops a student from entering a fake deadline that everyone then
believes?

**A:** We do not prevent it; we label it and make trust visible. A student report
publishes instantly — there is no approval queue anywhere in the system — but the
row carries `verification_status='student-reported'`, so every reader sees it is
peer evidence, not a teacher-confirmed fact. The labeling is enforced, not
cosmetic: guard triggers reject a student saving as `'teacher-confirmed'`, and
reserve `'imported'` for the sync service; the UI renders the distinction as
provenance chips. Teachers get a read-only feed of student-reported entries plus
a data-source card on the dashboard, can correct categories (locked across
re-syncs), and the reporter can soft-delete their own entry, which withdraws it
from every calendar immediately. Community inserts carry separate rate-limit
guards, but the activity path deliberately relies on labeling rather than
throttling — a false report is visible as such, not blocked.

**Evidence:** migration 0015 (self-publish design); `res/values/strings.xml:164`
("No approval needed."); guard triggers `000200_activities.sql:188-243`;
`WebView/app.js:1355-1410` (reported feed and coverage card).

**Limitation:** KNOWN LIMITATION — nothing verifies the content of a manual
report; the system conveys provenance, not truth.

### Q15 — What happens if two students report the same face-to-face activity?

**Q:** Two students both record the same board deadline for the same section.
Does the system merge them?

**A:** No — two rows, and we say so plainly. The app has no duplicate-check
prompt and no similarity or matching logic anywhere in `BeaconScreen.kt` or
`BeaconViewModel.kt` (search-verified). Each report is a real section activity
with its own creator and its own `student-reported` label, and both appear on the
Beacon and on the teacher calendar. The title-token logic that does exist in the
database, `suggest_activity_category`, only suggests a tracking category from the
title — it is a classifier, not a dedup mechanism, and it never merges or blocks
rows. A teacher who notices the duplicate can still act, since both rows appear
on the dashboard calendar and category corrections apply per row — but the
system itself never merges them. Imported Classroom items are deduplicated by
their source key (Q7); manual entries deliberately have no equivalent.

**Evidence:** duplicate-reporting behavior verified 2026-11-01 — two separate
section rows (FACTBASE §8); `suggest_activity_category` in
`supabase/migrations/002300_category.sql`; `BeaconScreen.kt` and
`BeaconViewModel.kt` (no matching logic).

**Limitation:** KNOWN LIMITATION — with one honest disclosure: the Guidance
assistant's canned answer claims the app "will ask whether it is the same one
before saving," which overstates the shipped behavior. This canned-text drift is
documented rather than hidden — a known honesty point for the defense.

### Q16 — Why is the app online-first instead of offline-first?

**Q:** Most student tools advertise offline support. Why does yours require
connectivity?

**A:** Because the source of truth and the authorization boundary are both
server-side. Every read and write is an RLS-checked round trip to the hosted
PostgreSQL instance, so a local cache would be a second copy of the dataset
needing its own synchronization and conflict-resolution layer — a second hard
problem, not a shortcut. The Classroom import path already requires connectivity,
because a fresh Google access token is minted per run, so an offline queue would
only ever serve manual entries. For the MVP the deliberate scope was one dataset,
one rule set, and visible failure states instead of silent staleness. The only
local state that ships is preference and session flags in SharedPreferences.
Failure states are designed rather than accidental: each screen's sealed UiState
carries an explicit Error variant with a retry action, so connectivity loss is
always visible.

**Evidence:** the technology-stack inventory (FACTBASE §5: multiplatform-settings
is the only local persistence; no Room, no DataStore);
`…/studentcodex/di/AppContainer.kt:138-157` (preference stores);
`docs/OFFLINE-SYNC.md` (future design, accurately labeled as unbuilt).

**Limitation:** KNOWN LIMITATION — the offline cache plus write outbox (Room plus
WorkManager) is `PLANNED` as roadmap M3.1; no offline writes exist today.

## Android Application Engineering (Q17–Q20)

Android questions are engineering-judgment questions: the judge wants to know
whether the team chose its tools deliberately or by fashion. The app is a
single-Activity Jetpack Compose application with Material 3, manual dependency
injection through one readable container, a repository boundary that keeps every
Supabase and HTTP detail out of the UI layer, and per-screen MVVM state exposed
as sealed UiState flows. None of that is exotic, and that is the point — every
choice is small, testable, and defensible on its own terms, and the seams
(interfaces, fakes, lazy singletons) are exactly where a larger framework would
slot in later if the app outgrew hand wiring. Unit tests sit at those seams:
eleven test files exercise the ViewModels and engines on the JVM against in-memory
fakes, and `.plan/PLAN.md` v2.2 cites 117 unit tests. The four answers below name
the real files and the real trade-offs behind each decision.

### Q17 — Why Jetpack Compose and a single Activity?

**Q:** Why Compose, and why one Activity for the whole app?

**A:** The UI is declarative Jetpack Compose with Material 3, and the entire app
is one Activity: `MainActivity` does nothing but enable edge-to-edge, attach the
theme, and call `StudentCodexApp(container)` (`MainActivity.kt:10-21`). All
navigation is Compose Navigation over a `TopDestination` enum — HOME, BEACON,
COMMUNITY, SETTINGS — in a Material 3 navigation bar, plus a pushed profile route
from Settings, and the floating GuidanceOverlay sits above every page in the same
window. This shape suits the app's state model directly: each screen renders a
sealed UiState, the editor sheet is a pure function of state, and there is no
multi-activity back-stack juggling. The single window is also what lets the
draggable assistant live everywhere at once. Build configuration: minSdk 26,
targetSdk 36, compileSdk 37.

**Evidence:** `…/studentcodex/MainActivity.kt:10-21`;
`…/studentcodex/ui/StudentCodexApp.kt:190-263` (nav host, bottom bar, overlay);
`app/build.gradle.kts:135-187`.

### Q18 — Why manual dependency injection instead of Hilt or Koin?

**Q:** Why hand-write a service locator when DI frameworks are standard?

**A:** It is a deliberate MVP decision, stated in the code itself: "no DI
framework for the MVP" (`AppContainer.kt:36-38`), following the build plan's
no-dependency-sprawl rule. `AppContainer` is roughly 160 lines of lazy
singletons — the Supabase client, the auth repository, the Google authorization
boundary, the Classroom sync and import repositories, the auto-syncer, the
guidance engine — and every consumer depends on an interface, not on a concrete
class. Unit tests inject fakes at those seams. The trade is explicit: a few lines
of hand wiring in exchange for zero annotation processing, zero generated code,
and a container a reviewer can read top to bottom in one sitting and debug
without a framework in the stack trace. The container also doubles as
documentation: one screen of code names every dependency the app actually has,
which is more than most dependency graphs generate.

**Evidence:** `…/studentcodex/di/AppContainer.kt:35-160`; the interface seams in
`…/studentcodex/data/repo/Repositories.kt`; the eleven unit-test files under
`app/src/test/java/com/example/studentcodex/`.

**Limitation:** wiring changes must be made by hand when dependencies change —
acceptable at this scale, and the seams mean a framework could be introduced
later without touching any caller.

### Q19 — What is the repository pattern and how is it used here?

**Q:** Explain the repository pattern and where it appears in this code base.

**A:** Repositories are the app's data vocabulary: interfaces that name what the
UI can ask for — activities, community posts, profile, content reports, Classroom
connection state, sync, import — while hiding how it is fetched. The contract is
written in the file itself: "UI and ViewModels only ever see these interfaces -
never Supabase, Room, or HTTP details" (`Repositories.kt:6-9`). Supabase-backed
implementations live under `data/supabase/`, `AppContainer` wires them as lazy
singletons, and tests substitute in-memory fakes — which is why the ViewModels
run as JVM unit tests without a network or a device. The boundary also carries a
security property: Google tokens never cross it into long-lived app state; a
token is used inside one sync call and discarded. The vocabulary types —
`ActivityDraft`, `MySection`, `ClassroomSyncResult` — are plain Kotlin data
classes, so they are trivially fakeable in tests and carry no platform types.

**Evidence:** `…/studentcodex/data/repo/Repositories.kt` (seven interfaces,
`ActivityDraft`, `ClassroomConnectionState`); `…/di/AppContainer.kt:64-157`
(wiring); `…/data/supabase/SupabaseActivityRepository.kt` (one implementation).

### Q20 — How is state managed in the views?

**Q:** Describe your state management. How does a screen know what to render?

**A:** Model-view-viewmodel with unidirectional data flow. Each ViewModel exposes
one sealed UiState — Loading, Error, or Content — as a `StateFlow`; composables
collect it with `collectAsStateWithLifecycle` and render the UI as a function of
that state. Transient state lives beside it, in the Beacon's case a separate
`MutableStateFlow<ActivityEditorUiState?>` for the editor sheet. List loading is
one-shot plus a silent refresh on tab resume, and the navigation back stack keeps
ViewModels alive across tab switches. Two details are worth defending: the filter
chips are an enum whose predicates share one sampled "now" instant, so the chips
and the two-tier sort can never disagree about which side of a deadline an item
sits on; and there is exactly one shared GuidanceViewModel per signed-in session,
so the assistant transcript belongs to the account that asked.

**Evidence:** `…/studentcodex/ui/beacon/BeaconViewModel.kt:26-53` (filter enum
plus UiState) and `:96-141` (load and refresh);
`…/studentcodex/ui/StudentCodexApp.kt:195-213` (shared Guidance ViewModel).

**Limitation:** there is no pull-to-refresh gesture — refresh is automatic on
resume plus an explicit retry on hard errors (`BeaconViewModel.kt:123-131`).

## Database, Security, and Data Control (Q21–Q28)

The final cluster is where precision matters most, because two of these questions
carry audit history. The F1/F2/F3 security review (2026-10-29/30) found that
three SECURITY DEFINER RPCs were executable by any authenticated user even though
no live client needed that door; migration 0032 closed them with pure REVOKE
statements, and the local authorization test suite passed. But 0032 is not
deployed to the hosted project, which runs migrations through 0028 — and that
exact status, `IMPLEMENTED — VERIFICATION INCOMPLETE`, must be volunteered, not
discovered by the judge. The remaining questions cover the schema's shape, why row-level
security is the enforcement point for publishable-key clients, the read-only
OAuth scopes and their strings, import matching tiers, the source key, what the
auto-sync toggle really controls, and what revoking Google access does to a
student's data. Together they close the loop from "where does the data live" to
"who controls it."

### Q21 — How is the database structured?

**Q:** Give me the schema at a glance. What are the main tables?

**A:** Twenty-three tables defined by 33 versioned migrations, grouped by
concern:

| Group | Tables |
|---|---|
| Identity and registry | `profiles`, `user_roles`, `campuses`, `programs`, `year_levels`, `year_sections` |
| Academic structure | `courses` (with `external_course_id`), `sections`, `enrollments` |
| Activity core | `activities`, `activity_sources`, `activity_reports`, `activity_groups`, `activity_group_members`, `activity_participants` |
| Community | `posts`, `post_images`, `comments`, `post_likes`, `comment_likes`, `user_blocks` |
| Moderation | `content_reports` |
| Integration | `google_connections` |

The center is `activities`: title, description, type, scope
(personal/section/course), `due_at`, estimated effort, `verification_status`,
soft-delete `deleted_at`, and — from migration 0023 — `category_locked` and
`category_locked_by`. Its one-to-one evidence table `activity_sources` holds the
provider, the external IDs, the unique source key, and `source_meta` JSON. Views:
`feed_posts`, `my_posts`, `feed_comments` (anonymity-safe, author nulled
server-side), and `section_workload_daily`.

**Evidence:** `supabase/migrations/000200_activities.sql:18-73` (the activity
core); the verified table inventory (FACTBASE §13); migration 000500 for the
private storage bucket.

**Limitation:** `section_workload_daily` exists but no client consumes it
(analytics are `PLANNED`), and the hosted project runs migrations through 0028
only.

### Q22 — Why Row Level Security instead of server-side authorization code?

**Q:** Why push authorization into the database instead of an API layer you
control?

**A:** Because of the key model. Both clients are publishable-key clients — the
key is public by design, and anyone can call PostgREST directly with it. An
authorization layer living only in app or dashboard code would therefore be
advisory, not enforcing. The database is the one component every request must
pass through, so it is the policy enforcement point. Every client-exposed table
has RLS enabled, and the policies are written as row-local columns plus EXISTS
subqueries — deliberately not through the visibility helper, because a STABLE
function cannot see a row inserted by `INSERT ... RETURNING` in the same
statement, a pitfall documented in the migration's own design note. Invariants
RLS expresses poorly — role and verification consistency, author immutability —
are enforced by guard triggers instead. Anonymous requests are denied everywhere.

**Evidence:** `000200_activities.sql:328-372` (design note plus
`activities_select`); the key-model audit (`plan-push/evidence/AUDIT-EVIDENCE.md`);
`policies_test.sql` (T03: anonymous denied).

**Limitation:** the policy suite's latest run is PARTIALLY PASSED — two known
fixture and expectation issues that predate and are unrelated to migration 0032
(fix tracked as roadmap M1.2).

### Q23 — Why are some operations in SECURITY DEFINER functions?

**Q:** SECURITY DEFINER runs with elevated rights. Why do you need it, and what
stops abuse?

**A:** Because a few narrowly-privileged trusted actors must do cross-table work
that RLS would block, and each one is fenced. `handle_new_user` and
`handle_user_profile_sync` are triggers on `auth.users` that create profiles,
grant roles, and enroll students; `import_student_classroom_courses` and
`upsert_activity_from_source` act for the sync service. Every function pins its
`search_path`, and EXECUTE privileges gate who may call them at all.
`upsert_activity_from_source` goes further and raises an exception when
`auth.uid()` is not null — it is service-only by its own body
(`002300_category.sql:106-108`). After the F1/F2/F3 audit, migration 0032 revoked
the `authenticated` EXECUTE grant from the three RPCs that never needed it —
legacy `teacher_signup`, the import RPC, and `enroll_student_courses` — leaving
the Edge Function's service-key path and the definer-owned triggers as the only
callers. It is a pure privilege change: no function body was modified.

**Evidence:** `supabase/migrations/003200_hardening.sql:43-60` (the three
revokes plus re-asserted service grants); `002300_category.sql:102-108`;
`tests/rpc_authorization_test.sql` (T01–T10 PASSED locally, 2026-10-30).

**Limitation:** 0032 is `IMPLEMENTED — VERIFICATION INCOMPLETE`: applied and
tested locally only; the hosted project is still at 0028, so deployment and
post-deploy verification (M2.1, M2.2) remain open.

### Q24 — What are the Google Classroom OAuth scopes and why read-only?

**Q:** List the scopes you request and justify each.

**A:** Three read-only scopes, exactly as requested in code:

```text
https://www.googleapis.com/auth/classroom.courses.readonly
https://www.googleapis.com/auth/classroom.coursework.me.readonly
https://www.googleapis.com/auth/classroom.announcements.readonly
```

They are read-only because the integration is import-only: Student Codex never
writes back to Classroom — no submissions, no posts, no mutations — which is the
least privilege a read-side integration can ask for and the easiest consent
story to defend to students. `coursework.me` is the student-view coursework
scope, narrower than the teacher-side roster scopes. One visible consequence of
that narrowness: a class the account owns as a teacher may match by name, but its
coursework can be unreadable with student scopes — the sync function handles that
403 by skipping and reporting the class instead of failing the whole run. The
boundary is also visible to the user: Google's consent screen states that the
app can only view course lists, coursework, and announcements — never modify
them.

**Evidence:** `ClassroomScopes.READONLY` in
`…/studentcodex/data/auth/ClassroomAuthorization.kt:75-81`; the scope-limited 403
handling in `classroom-sync` :287-294.

**Limitation:** read-only means exactly that — a category a teacher corrects in
Student Codex never flows back to Classroom, by design.

### Q25 — How does course matching work when a Classroom course is imported?

**Q:** How does a Google Classroom course become one of the student's courses
here?

**A:** In resolution tiers, exact before fuzzy. Tier 1: a local course row
already carrying this Classroom course's `external_course_id` — an exact,
one-to-one link established by migration 0022, which `classroom-sync` checks
first (:169-177) before any name heuristic. Tier 2: an existing course that is
the same one by normalized name — uppercased with non-alphanumerics stripped,
matched against the course code or title — extended in migration 0027 with a
fuzzy `course_text_matches` tier and a `cohort_section_name` preference. Tier 3:
nobody knows the course yet, so a brand-new course row is created under its
Classroom name, attached to the student's program. Advisory transaction locks
serialize work per course so concurrent classmates converge on the same course
and section rows, and students already enrolled anywhere in the course are left
untouched. When several sections share a matched course, sync prefers the section
whose name matches the Classroom course's own section label.

**Evidence:** `supabase/migrations/002200_course_import.sql:119-170` (tiers) and
`:191-213` (section convergence); `supabase/migrations/002700_cohort.sql` (fuzzy
tier); `classroom-sync` :168-191.

**Limitation:** hand-typed courses fall through to the name heuristics — a
mistyped course name can leave a class unmatched, and unmatched classes are
skipped and reported, never force-created.

### Q26 — What is the source key and why does it matter?

**Q:** You keep citing a "source key." Define it and explain why it exists.

**A:** The source key is the provider-scoped identity of an imported item:
`google_classroom:{courseId}:{courseWorkId}` for coursework, and
`google_classroom_announcement:{courseId}:{announcementId}` for announcements. It
matters because it converts Google's stable, globally shared IDs into
database-enforced identity. A partial unique index on `activity_sources.source_key`
(`WHERE source_key IS NOT NULL`) makes the mapping strictly one-to-one, which
buys three properties at once: re-syncs update instead of duplicating; classmates
syncing the same item share one canonical activity row; and manual rows, whose
source key is NULL, are exempt from the constraint. The composite unique on
`(provider, external_course_id, external_item_id)` is a second guard, and
`source_meta` preserves what the key cannot — the raw Classroom workType, the
alternate link, the course name at import time. The key is also why the sync can
run repeatedly with no throttle window: every run re-derives the same keys, and
every key resolves to the row it already owns.

**Evidence:** `000200_activities.sql:49-73` (keys and indexes); key construction
in `classroom-sync` :305 and :338; the upsert in `002300_category.sql:86-169`;
`gc_source_identity_test.sql`.

**Limitation:** the key speaks only for provider items — it can say nothing about
two manual entries describing the same real-world task.

### Q27 — What does the auto-sync toggle actually do?

**Q:** Settings has an "Auto-sync school works" switch. What does it really
control?

**A:** It opts the student into a silent sync every time the app comes to the
foreground — nothing more and nothing less. The toggle is one SharedPreferences
boolean (`classroomAutoSyncEnabled`, stored through
`RusshwolfClassroomAutoSyncStore`). When it is on, `ClassroomAutoSyncer.runIfDue`
fires on every `ON_START` and once when the toggle is flipped on: it verifies the
Classroom connection is `Connected`, requests a silent-only token pinned to the
connected Google account, and runs the same idempotent Edge Function the manual
"Sync now" button runs. There is deliberately no throttle window — the
upsert-by-source-key design means an extra run converges the data rather than
duplicating it. When the token would require a consent sheet, the run is skipped
without any dialog; failures stay quiet and the next app open retries.

**Evidence:** `…/studentcodex/data/repo/ClassroomAutoSync.kt:15-31` (the store),
`:34-91` (the syncer, including the no-throttle rationale);
`…/ui/StudentCodexApp.kt:215-234`; `…/ui/settings/SettingsScreen.kt:305-320`.

**Limitation:** it is not a background service — with the app closed nothing
syncs; the toggle only affects what happens while the app is open.

### Q28 — What happens to my data if I revoke Google access?

**Q:** Suppose I revoke the app's Google consent tomorrow. What happens to my
account and my activities?

**A:** Your Student Codex data survives; the Classroom integration stops. Manual
entries, community posts, and your profile live in Supabase and are independent
of Google. On the next sync attempt, Google refuses the missing grant — a 401 or
403 on `courses.list` — and the Edge Function stamps the `google_connections`
registry row `revoked` (401) or `expired` (403) with the failure detail; the app
then shows the Revoked connection state with a reconnect prompt. Previously
imported activity rows are not deleted: they remain as read-only records, but
they stop receiving updates. Because access tokens are minted per run and never
stored, there is nothing to clean up on any server — revocation takes effect at
the very next sync attempt. A client-initiated `disconnect()` exists as the
deliberate counterpart for unlinking without touching Google.

**Evidence:** `classroom-sync` :114-128 (the 401/403 mapping to revoked/expired);
`ClassroomConnectionState` in `…/data/repo/Repositories.kt:288-311`; the token
model in `ClassroomAuthorization.kt:131-137`.

**Limitation:** imported rows go stale until the student reconnects; the system
neither archives nor removes imported data on revocation.

---


# Chapter 34 — Technical Judge Q&A (Part 2)

This is the second half of the defense question-and-answer chapter. The
numbering continues from Part 1, which carried questions Q1–Q28; here the
questions turn to the layers technical judges press hardest: who can see
what, why the database is the trust boundary, what the keys really are,
what happens when things fail, what the tests actually prove, and where
the honest boundary sits between this demo-stage system and production.
Every answer follows the same contract: the direct answer first in one to
three sentences, then the mechanism with real identifiers from the
repository, then the evidence trail, then the limitation where one exists.

> NOTE: The anchor fact for this entire half: migration 0032 (the F1/F2/F3
> RPC EXECUTE hardening) is LOCALLY TESTED, NOT DEPLOYED to the hosted
> project. The hosted project has migrations through 0028 applied;
> 0029–0032 exist locally only. Any answer below that says "cannot" about
> the three revoked RPCs describes the locally verified schema, not yet
> the running hosted service.

## Security and row-level authorization

The nine questions in this section cover visibility of student data, the
teacher dashboard's data path, the necessity of row-level security, key
exposure, request tampering, role self-granting, and the exact content and
deployment state of migration 0032. The short version for a judge in a
hurry: authorization lives in PostgreSQL RLS on the single shared backend,
the publishable key is public by design, the service-role key never leaves
the Edge Functions' server context, and the October 2026 audit's three
findings (F1/F2/F3) are fixed by a pure-privilege migration that is
verified locally and awaiting deployment (roadmap M2.1).

### Q29 — Can a teacher see a student's private activities?

**Q:** When a student records something as personal, is it invisible to
staff at the data level, or only hidden in the app's user interface?

**A:** It is invisible at the data level, not merely hidden in the app. An
activity row with `scope='personal'` is readable only by its creator (and
by participants the creator attached to it); the teacher read path never
opens for personal rows. What migration 0019 grants teachers is
university-wide read of non-personal rows only — `scope in
('section','course')` — and that check lives inside the `activities_select`
RLS policy, so a teacher's session simply never receives personal rows
from PostgREST, no matter which client they use or how the request is
shaped. Soft-deleted rows stay hidden from teachers as well.

**Evidence:** `activities_select` policy and the matching teacher branch in
the `activity_visible_to_user()` helper (migration 0019,
`supabase/migrations/`); FACTBASE §12 (university-wide visibility is
intentional; personal rows stay private to their creator).

**Limitation:** Teachers see recorded non-personal data only — there is no
guarantee that real-world university activities were ever entered, and the
dashboard's coverage card says so explicitly.

### Q30 — Where does the dashboard's university-wide data come from?

**Q:** The teacher dashboard shows every campus, program, and block. Does
it call a privileged admin API, or a cached warehouse?

**A:** Neither. The dashboard is a static HTML/JS application that talks to
the same shared Supabase backend as the Android app, using supabase-js
with the publishable key; every request runs under the signed-in teacher's
session, and RLS decides which rows come back. The university-wide breadth
comes from migration 0019's teacher branch in `activities_select` —
`has_role('teacher') and scope in ('section','course')` — not from any
server-side aggregation or admin endpoint. The cohort filter bar's
campus/program/year/block dropdowns read the live school registry tables
(the registry is readable to any session), and the month calendar, day
sheets, and student-reported feed are client-side renderings of the same
RLS-filtered activity rows.

**Evidence:** `WebView/app.js:26` (project URL), `:239` (`createClient`
with the publishable key), filter bar `:1193-1237`, student-reported feed
`:1355-1410`; `WebView/README.md` "Data & security model".

**Limitation:** There is no analytics layer: workload summaries and
aggregate views are absent, the `section_workload_daily` view is consumed
by no client, and everything on the dashboard reflects only what students
and teachers actually recorded.

### Q31 — Why is row-level security necessary in this architecture?

**Q:** You control both clients. Why enforce permissions in the database
instead of in the application code?

**A:** Because neither client is trustworthy. The Android app and the
teacher dashboard are both untrusted code holding a public key; anyone can
open browser DevTools, craft requests, or use the publishable key with
their own session. The only component both clients share is the database,
so that is where authorization must live. RLS also means one rule set
governs both clients — there is no dashboard-only permission model that
can drift out of sync with the app's. Notably, the Android app makes zero
direct RPC calls (verified: REST tables and Edge Functions only), so for
everything except the Edge Function paths, RLS policies are the only gate
standing between a request and the data.

**Evidence:** FACTBASE §4 request flows; RLS on every client-exposed table
across migrations 000000–0023 (for example `activities_select`,
`activities_insert` from 0015, community policies, storage policies from
0005); anonymous access denied everywhere (policies_test T03).

**Limitation:** RLS correctness depends on policy coverage and on the SQL
test suite, and `policies_test.sql` is currently PARTIALLY PASSED for two
known fixture-level issues unrelated to any recent change (see Q50).

### Q32 — What happens if somebody modifies a request from the browser?

**Q:** Suppose a judge edits a fetch in DevTools — swaps a user id, forges
a role claim, or calls an internal RPC directly. What breaks?

**A:** Tampering cannot escalate row access, and — after migration 0032 —
cannot invoke the privileged RPCs directly. Row access is re-evaluated
server-side per policy against the platform-verified session, so editing a
payload only shapes requests the caller was already allowed to make; a
forged JWT fails signature verification before PostgREST ever sees it. The
three SECURITY DEFINER RPCs named in the audit findings (`teacher_signup`,
`import_student_classroom_courses`, `enroll_student_courses`) are now
REVOKEd from `authenticated` by 0032, so a direct call dies with
`insufficient_privilege` — exactly what rpc_authorization_test T01–T04
asserts. The Classroom Edge Functions verify the session JWT themselves
via /auth/v1/user before touching any service-key path, and the 0031 gate
reads `auth.users` server-side rather than trusting JWT claims.

**Evidence:** rpc_authorization_test T01–T04 PASSED locally (2026-10-30);
migration 0032 :43-53; classroom-sync Edge Function (:48-59); migration
0031 (definer-rights email read).

**Limitation:** The revocation is locally tested only — the hosted project
still runs at 0028, where non-mutating probes showed the three RPCs still
executable by `authenticated` (deployment is roadmap M2.1). The
`classroom-import` "list" action and the public `site` pages intentionally
run without JWT verification and expose nothing privileged.

### Q33 — Is the Supabase client key safe to expose?

**Q:** Your dashboard source contains a Supabase key. Did you leak a
secret?

**A:** No — it is the publishable (anon) key, which is public by design:
it identifies the project, and every request still requires a valid
session before RLS decides what comes back. This is Supabase's intended
model for browser clients; treating the publishable key as a leak would be
a category error. The secret that matters — the service-role key, which
bypasses RLS — lives only in the Edge Functions' server environment and
appears in no client and no client-readable file. The Google OAuth
`client_id` used by the app is likewise a public identifier, not a
credential.

**Evidence:** `WebView/app.js:239` (`createClient` with
`SUPABASE_PUBLISHABLE_KEY`); FACTBASE §15 keys; `supabase/config.toml`
`[auth.external.google]` (client_id as a public identifier).

**Limitation:** One real credential is mishandled: `client.json` at the
repository root holds a live Google OAuth client secret (flagged; values
not reproduced here). That file is a genuine exposure tracked as roadmap
M2.5 credential hygiene — so the honest split is: publishable key, safe by
design; `client.json`, a known leak to fix.

### Q34 — How do you prevent students from granting themselves teacher permissions?

**Q:** A signed-in student can call the same endpoints the dashboard
calls. What stops role self-granting?

**A:** Role grants exist only behind gated RPCs, and the gates are
server-side. The active doors — `teacher_signup_global` and
`teacher_signup_multi` — require a signed-in session and verify the
caller's `auth.users.email` ends with `@parsu.edu.ph`, read from the table
under SECURITY DEFINER rights so forged JWT claims are irrelevant. The
legacy `teacher_signup` RPC (audit finding F1) previously let any
authenticated user self-grant the teacher role; migration 0032 revoked its
EXECUTE privilege from `authenticated`, closing that door. Policies never
read roles directly; they go through the `has_role()` SECURITY DEFINER
helper, which is what the whole schema trusts.

**Evidence:** migration 0031 domain gate (case-insensitive exact suffix;
look-alikes such as `@notparsu.edu.ph` and `@sub.parsu.edu.ph` rejected);
migration 0032 :43-45; rpc_authorization_test T01 (revocation holds) and
T09/T10 (gate rejects non-school callers, accepts school callers).

**Limitation:** 0032 is locally tested, not deployed — the hosted project
at 0028 still shows the legacy RPC executable there. And the domain check
proves eligibility, not mailbox ownership: with email confirmation OFF (a
testing configuration), production identity verification remains
UNRESOLVED (roadmap M2.3).

### Q35 — What did migration 0032 fix?

**Q:** Walk me through the security migration. What changed, and what did
you deliberately leave untouched?

**A:** 0032 is a pure privilege change closing audit findings F1, F2, and
F3. It REVOKEs EXECUTE on `teacher_signup` (F1), on
`import_student_classroom_courses` (F2), and on `enroll_student_courses`
(F3) from `authenticated`; it re-asserts the `service_role` grants so the
Edge Function import path and the auth.users triggers keep working, and
re-revokes `public`/`anon` idempotently so the file documents the intended
end state by itself. No function body was modified, and the active
teacher-registration doors (`teacher_signup_global` /
`teacher_signup_multi`, with their 0031 domain gates) are untouched
byte-for-byte. This matches the house pattern `upsert_activity_from_source`
already followed since migration 0023: service-context RPCs are granted to
`service_role` only.

**Evidence:** migration 0032 :43-53 (the three REVOKEs), :57-60
(service_role grants), :63-68 (public/anon re-revokes); verified by
`tests/rpc_authorization_test.sql` T01–T10 PASSED locally on PostgreSQL
17.11 with a replicated Supabase platform surface (run dated 2026-10-30).

**Limitation:** IMPLEMENTED — VERIFICATION INCOMPLETE: applied and tested
locally only; the hosted project is still at 0028, so deployment (M2.1)
and post-deploy hosted verification (M2.2) remain open.

### Q36 — Has the latest migration been deployed to the hosted project?

**Q:** Is the hardening live on your real backend, or only on the local
database?

**A:** Only locally. The hosted Supabase project has migrations through
0028 applied; 0029–0032 exist as local, currently untracked files and have
not been pushed. We state this plainly because it is the single most
important caveat in the security story: non-mutating ACL probes against
the hosted project (2026-10-29/30) confirmed the three RPCs are still
executable by `authenticated` there, pre-0032. Deploying 0029–0032 and then
re-verifying the RPC authorizations on hosted are the first two items of
the roadmap's Tier 2 (M2.1 and M2.2).

**Evidence:** FACTBASE §13 (hosted through 0028; 0029–0032 local-only,
untracked) and §15 (deployment state, including the hosted probe results).

**Limitation:** Until M2.1 runs, every 0032 guarantee in this handbook is
a locally verified property of the schema, not a property of the running
hosted service; the 0029/0030 email-verification machinery is likewise
dormant on hosted, superseded by 0031's domain gate.

### Q37 — What security limitations remain?

**Q:** If I audit this project tomorrow, what will I find that you already
know about?

**A:** Five known items, all on the roadmap and none hidden. First,
migration 0032 is not deployed to hosted (M2.1/M2.2). Second, production
teacher identity verification is UNRESOLVED: the @parsu.edu.ph suffix
proves eligibility, not mailbox ownership, and email confirmation is OFF as
a testing configuration (M2.3). Third, `client.json` at the repo root holds
a live Google OAuth client secret (M2.5). Fourth, repository hygiene — the
entire current product is uncommitted working-tree state: 2 commits, a
59-entry status listing, roughly 90 root dev-script debris files (M2.4).
Fifth, demo teacher credentials are documented in the dashboard README and
demo seed data lives on the hosted project (M5.3).

**Evidence:** FACTBASE §15, §17, §18; `WebView/README.md` (credential
locations noted; values not reproduced).

**Limitation:** This project holds no production security certification;
the honest framing is a demo-stage system with a verified, locally tested
hardening patch awaiting deployment.

## Reliability, scaling, and data integrity

The next six questions cover what happens under load, what happens when
things fail, how Google tokens are handled, and which database-level
guarantees the schema actually provides. Two themes repeat: integrity is
enforced in PostgreSQL (unique source keys, guards, idempotent upserts),
and the scaling story is deliberately modest — a managed Postgres instance
with per-row RLS checks, no load testing, and one hosted project. The
duplicate question also draws the line the fact base insists on: imported
rows are deduplicated by construction; manual and student-reported rows
are not.

### Q38 — How does the system scale when more students join?

**Q:** Ten thousand students open the app at once. What happens?

**A:** Honestly: we do not know, because no load testing has been done.
The backend is Supabase's managed PostgreSQL; every client query is
evaluated row-by-row against RLS policies, so read cost grows with the rows
a user may see; there is one hosted project, and demo seed data still
lives on it. What does exist: unique partial indexes (on
`activity_sources.source_key` and on `courses.external_course_id`) that
keep the import upsert path indexed; advisory locks that serialize
course creation without long transactions;
an API response cap (`max_rows = 1000` in `supabase/config.toml`); bounded
fetches in the Edge Functions (course listing paginated at 100 per page,
enrollment lists capped at 500); and SQL rate guards on community writes.
Student reads are naturally bounded by their own enrollments; the known
weak point is the university-wide teacher read — the dashboard fetches all
matching non-personal rows and filters client-side, with no aggregate
layer or cache.

**Evidence:** `supabase/config.toml` [api] max_rows; classroom-import Edge
Function (:76-78 pagination); classroom-sync Edge Function (:138 enrollment
limit); migration 0008 rate guards; FACTBASE §16.

**Limitation:** KNOWN LIMITATION, stated as such: no measured numbers
exist, and any scaling claim beyond the mechanisms above would be
invention.

### Q39 — What happens when an Edge Function fails?

**Q:** Google is slow, or the import RPC errors mid-sync. What does the
user see, and what does the database see?

**A:** The design rule is skip-and-report, never silent partial success.
Inside `classroom-sync`, a class that matches no local course is skipped
and named in the returned summary; coursework the current Google scopes
cannot read is skipped and named; a hard error on an import item aborts
the run and returns `{status:"failed"}` with the error recorded — items
already upserted stay, which is safe because the upsert is idempotent, so
a retry converges instead of duplicating. Every outcome is written to the
`google_connections` registry (status, `last_sync_status`,
`last_sync_error` truncated to 500 characters), so the Settings connection
card can show what happened. On the device, the silent auto-sync never
throws: `runIfDue` wraps each step in runCatching, skips when Google needs
interactive consent, and retries on the next app open; the manual "Sync
now" surfaces the error to the user.

**Evidence:** classroom-sync Edge Function (:97-105 fail path, :367-402
registry write and summary JSON with imported/updated/classesTotal/
skippedClasses/skippedCoursework); `…/data/repo/ClassroomAutoSync.kt:69-90`
(never throws; AtomicBoolean in-flight guard).

**Limitation:** There is no retry or backoff schedule beyond the next app
open, and no push-based trigger — a failed sync simply waits for the user
to return to the app.

### Q40 — How do you protect Google OAuth tokens?

**Q:** You send a Google access token to your server. Where is it stored,
and what stops it leaking?

**A:** It is transit-only. The token is minted on-device per sync by the
Google Authorization API after the student's explicit consent, travels
once in the POST body over HTTPS to the Edge Function, is used to call the
Classroom API, and is never stored anywhere server-side. There are no
refresh tokens in the app, and no client secrets — the app identifies
itself to Google with a public web client ID, which is an identifier, not
a credential. If the student revokes access in their Google account, the
next sync receives a 401, the connection registry is marked revoked, and
the app asks them to reconnect.

**Evidence:** classroom-sync Edge Function header (:10-13 — tokens used in
transit only, nothing stored server-side, no refresh token to leak);
`supabase/config.toml` `[auth.external.google]`; FACTBASE §11 tokens.

**Limitation:** The OAuth consent screen is not yet published (roadmap
M5.2 — the `site` Edge Function exists precisely to host the
authorized-domain branding URLs Google requires for it), and the Classroom
scopes are read-only (rosters + coursework), which bounds what a
short-lived leaked token could even read.

### Q41 — What makes your data model reliable?

**Q:** Which integrity guarantees does the schema actually give you,
rather than your application code?

**A:** The integrity lives in PostgreSQL, not in client discipline. The
unique partial index on `activity_sources.source_key` makes every imported
item a single canonical row; foreign keys, NOT NULL constraints, and CHECK
constraints (scope, reason, and status vocabularies) reject invalid rows
at insert time; guard triggers enforce invariants policies cannot express
— post-author immutability, category-lock stamping, report-substance
immutability, and write rate limits; soft deletion via `deleted_at`
preserves history instead of destroying it; provenance labels
(`verification_status`, source rows) record where every row came from;
and RLS runs on every client-exposed table. Imports are idempotent through
atomic upserts and advisory locks, so classmates converging on the same
course at the same time cannot create doubles.

**Evidence:** FACTBASE §16 guarantees; migrations 0002 (activities and
sources), 0008 (phase completion, rate guards), 0022 (source identity),
0023 (category lock); `gc_source_identity_test.sql` PASSED (with a
temporary shim) and `phase_completion_test.sql` PASSED.

**Limitation:** This is reliability of the record, not of reality:
nothing guarantees real-world activities were recorded, manual reports are
unverified by design, and Classroom changes lag until the next successful
sync because there is no push.

### Q42 — What prevents duplicate database records?

**Q:** Two students sync the same coursework; a classmate re-reports an
activity already reported. How many rows exist afterward?

**A:** For imported rows, exactly one. Identity is the `source_key` —
`google_classroom:{courseId}:{courseWorkId}` (or the announcement variant)
— under a UNIQUE partial index, with a composite unique on (provider,
external_course_id, external_item_id) as a second guard. The import path
is a single atomic upsert (`ON CONFLICT (source_key) WHERE source_key IS
NOT NULL DO UPDATE` — the partial-index predicate is required and is what
the identity test verifies). Because Classroom IDs are shared across
enrolled students, student B syncing what student A already synced
UPDATES the same shared row rather than inserting a second one, and
advisory locks serialize concurrent course creation. Re-running an import
is a no-op: the authorization test's T08 re-import reports `enrolled=0`
with the course listed as matched. For community and role rows, idempotent
`ON CONFLICT DO NOTHING` clauses fold re-submissions.

**Evidence:** migrations 0022/0027; `gc_source_identity_test.sql` PASSED;
rpc_authorization_test T08 (idempotent re-run, external_course_id link).

**Limitation:** Manual and student-reported entries have no deduplication:
the app contains no similarity or matching logic (grep-verified), so two
students reporting the same face-to-face activity create two legitimate
section rows; title-token matching exists only in the category classifier
(`suggest_activity_category`) and is not dedup.

### Q43 — What features are not yet implemented?

**Q:** What is on the box but not in the box?

**A:** An honest inventory, with the project's status labels verbatim:

| Missing feature | Status |
|---|---|
| Offline cache / write outbox | PLANNED |
| Push notifications / reminders | DEFERRED |
| Workload analytics, proposed-deadline preview | PLANNED (DB view exists, no client) |
| Comment-likes UI, nested reply UI, moderation queue UI | PLANNED |
| Anonymous posting (switch present, flag not persisted) | PARTIALLY IMPLEMENTED |
| Comments (flat in app; DB supports depth-5 nesting) | PARTIALLY IMPLEMENTED |

The unshipped surface clusters into persistence, analytics, and community
completeness. The anonymous-posting row is the one place the UI
overpromises: the composer switch exists, but the flag is dropped before
the network call.

**Evidence:** FACTBASE §3 feature inventory; `CommunityViewModel.kt:166`
(drops the flag); `SupabaseCommunityRepository.kt:149` (hard-wires
`is_anonymous=false`); `docs/OFFLINE-SYNC.md` (unbuilt future work).

**Limitation:** The Guidance assistant's canned text overstates two of
these (three images; anonymous posting) — documented canned-text drift.

## Registration, privacy, and moderation

The next five questions cover the teacher registration gate, the privacy
story, image storage, and what actually happens to reported content. The
pattern to defend: every gate that matters is server-side (domain check in
the RPC, storage policies on the bucket, guard triggers on reports), while
the remaining gaps are named precisely — the domain proves eligibility but
not mailbox ownership, and moderation exists as a complete database model
with no client to drive it.

### Q44 — Is the teacher registration flow secure?

**Q:** Self-service sign-up for staff accounts sounds risky. What gates
it, and what does it not prove?

**A:** It is layered and server-side, with two honest caveats. The flow:
sign-up creates the account, then `teacher_signup_global` or
`teacher_signup_multi` grants the role. Both RPCs require a signed-in
session, read the caller's email from `auth.users` under SECURITY DEFINER
rights (so forged JWT claims are irrelevant), and require the exact
`@parsu.edu.ph` suffix, case-insensitive — look-alike domains and
subdomains fail. Anon stays revoked, so the doors fail closed. The multi
RPC caps at 12 class groups, validates every group against the live
registry before writing anything, and aligns the profile only after all
groups validate, so a bad payload can never half-write. The client-side
suffix hint is convenience, not the gate; the legacy self-grant door (F1)
was closed by 0032.

**Evidence:** migration 0031 (:61-75 session and domain gates, :127-137
payload caps); migration 0032 :43-45; rpc_authorization_test T09/T10
PASSED; `WebView/app.js:219-222` maps SCHOOL_EMAIL_REQUIRED to plain
wording.

**Limitation:** The suffix proves eligibility, NOT mailbox ownership —
with email confirmation OFF (a testing configuration), GoTrue
auto-confirms sign-ups, so the gate cannot prove the caller controls the
address; production identity verification is UNRESOLVED (M2.3, with the
0029/0030 click-verification machinery dormant as fallback). And 0032 is
not yet deployed to hosted.

### Q45 — What data do you collect, and why?

**Q:** Walk me through your privacy posture. What is stored, and under
what claim?

**A:** Four categories, matching the published privacy policy. Account
information: email and display name, plus a password handled entirely by
Supabase Auth, never seen by application code. School details the user
enters: campus, program, year level, section, and course enrollments.
Activity records: manual entries, student reports, and — only
after the user explicitly connects — imported Classroom data (course
names, sections, roster information, coursework titles, descriptions, due
dates). Community content: posts, comments, likes, and content reports.
A `google_connections` registry row stores connection status, the chosen
Google account email, and last-sync outcomes so syncs stay pinned to the
account the student actually chose. Google access tokens are short-lived
and transit-only. The policy states no advertising, no trackers, no
profiling, and no selling, published at the `site` Edge Function's
/privacy route.

**Evidence:** privacy policy served by the `site` Edge Function
(functions/site, sections 1–4); FACTBASE §13 table inventory;
`google_connections` registry (migration 0008).

**Limitation:** Account deletion is by email request (processed within 30
days), not self-service in the app; the policy is a student-project
document with a personal support address; and community content is visible
to all signed-in peers by design, which is a product decision, not an
oversight.

### Q46 — Are community images private?

**Q:** Where do post images live, and who can fetch them?

**A:** In a private Supabase Storage bucket, enforced by policy. The
`community-images` bucket was created with `public = false`, so no public
URLs exist; reads are granted to authenticated users only, because the
community feed itself is visible to signed-in students. Writes are
confined to the uploader's own folder — the path convention is
`{uid}/{postId}/{ts}.jpg`, and the storage policies check
`(storage.foldername(name))[1] = auth.uid()::text` on insert, update, and
delete, so even a modified client cannot write into someone else's folder.
The app posts one image per post; the schema allows up to three.

**Evidence:** migration 0005 (bucket creation and the four
`storage.objects` policies); FACTBASE §4 storage flow; FACTBASE §9
community image rules.

**Limitation:** "Private" here means authenticated-only, not
per-recipient: any signed-in student who learns an object path can read
that image — the intended feed semantics, but not secrecy from other
users. The bucket's file-size limit is the platform default (50MiB in
`supabase/config.toml`).

### Q47 — What happens to a reported post?

**Q:** A student taps Report and picks a reason. Then what?

**A:** A row lands in `content_reports` with one of five fixed reasons
(spam, harassment, off-topic, inappropriate, other), optional details
capped at 1000 characters, and status `open`. The reporter can see their
own reports; moderators and admins can see the whole queue and are the
only roles permitted to move a report to `actioned` or `dismissed` —
enforced both by the RLS policies and by the
`guard_content_report_update` trigger, which makes report substance and
status immutable for non-staff. There is deliberately no delete policy:
reports are retained, not erased. A rate guard damps report spamming, and
the reporter identity is immutable.

**Evidence:** migration 0004 (`content_reports` table with the five-reason
CHECK, guard trigger, select/insert/update policies, no delete policy);
`guard_content_report_insert_rate` (migration 0008).

**Limitation:** BUILT & VERIFIED at the database level, but there is no
moderator UI anywhere — nothing currently consumes the queue, and no
automatic action is taken on the reported post itself. Overall status:
PARTIALLY IMPLEMENTED; the moderation queue UI is roadmap M3.3.

### Q48 — How do you handle moderation?

**Q:** Beyond recording reports, what is the moderation model?

**A:** A triage model at the database level, with the client side still
missing. The schema supports moderator and admin roles in `user_roles`;
community policies include moderator deletes of posts; `content_reports`
carries the queue with explicit status transitions; guard triggers keep
reporters from editing substance or status; and rate guards limit abuse.
The Android app contributes the report-submission path with the five-reason
picker through `ContentReportRepository`. That is all of it today: no
dashboard moderation view, no app queue, no client driving the moderator
delete path — a report is recorded and waits.

**Evidence:** migration 0004 (full moderation schema); community RLS
(own-row writes plus moderator deletes) per FACTBASE §13; reporting
interface in `…/data/repo/Repositories.kt`.

**Limitation:** PARTIALLY IMPLEMENTED, stated plainly: until M3.3 ships a
queue UI, acting on a report requires database-level access; we do not
demo the schema as if it were a finished feature.

## Testing and known failures

Three questions on evidence: what the test suites verify, why one suite is
partially red, and what a hosted outage would mean. The exact statuses
matter more here than anywhere else in the handbook — the project reports
`rpc_authorization_test` PASSED, `phase_completion_test` PASSED,
`gc_source_identity_test` PASSED with a temporary shim, and
`policies_test` PARTIALLY PASSED, and never rounds any of them up.

### Q49 — What is verified by tests, and what is not?

**Q:** Separate what your tests prove from what you believe.

**A:** Three layers, honestly separated. Unit tests: 117 tests across 11
Kotlin files cover the ViewModels (Auth, Beacon, Community, Guidance, Home,
Settings), the deterministic Guidance engine, the auto-syncer, and the
Supabase client factory — application logic, not network behavior; 5 of
those files are modified in the working tree and not yet committed. SQL
tests (latest run 2026-10-30, local PostgreSQL 17.11 with a replicated
Supabase platform surface): `rpc_authorization_test.sql` PASSED (T01–T10),
`phase_completion_test.sql` PASSED, `gc_source_identity_test.sql` PASSED
with a temporary compatibility shim. Browser verification: the teacher
dashboard was verified live on 2026-10-28, and Classroom sync was
live-verified then too — but the Edge Functions were not re-exercised
against real Google OAuth in the 2026-10-30 run, and Google Sign-In is
IMPLEMENTED — VERIFICATION INCOMPLETE (verified during development, not
re-exercised since).

**Evidence:** FACTBASE §6 (unit test file list; 117 tests per PLAN.md) and
§15 (exact SQL statuses); FACTBASE §3 (dashboard and sync verification
notes).

**Limitation:** Not verified anywhere: hosted deployment of 0032, load
behavior, production identity flows, and the current Android build's
visual state (roadmap M1.4 and M1.5 track the re-verification gaps).

### Q50 — Why do some SQL tests fail?

**Q:** You said a test suite is partially red. Is that a security
regression?

**A:** No — two known issues in `policies_test.sql`, both predating
migration 0032 and both unrelated to it. First, the programs fixture lacks
`campus_id`, so it fails the NOT NULL constraint that migration 0012
added; the fixture simply predates that migration. Second, test T08.1
expects PostgREST-style SQLSTATE 42501 (an RLS violation), but migration
0015's insert guard raises a deliberate P0001 exception instead — an
expectation mismatch in the test, not a hole in the policy. A control
rebuild without 0032 reproduced the same failures, confirming they are not
a regression. The `gc_source_identity_test` similarly needed a temporary
shim because its fixture also predates migration 0012's campus_id column.

**Evidence:** FACTBASE §15 test evidence (policies_test PARTIALLY PASSED;
both issues documented; control rebuild); roadmap M1.2 (fixture and T08.1
fix) and M1.3 (gc fixture fix).

**Limitation:** We report PARTIALLY PASSED verbatim rather than rounding
up to green: the failing assertions are test debt with scheduled fixes,
and claiming a fully green suite would be the one lie that destroys the
rest of this chapter's credibility.

### Q51 — What happens if the hosted Supabase project is unavailable?

**Q:** Your only backend goes down. What still works?

**A:** Almost nothing, and we say so. Student Codex is online-first:
sign-in, the Beacon, community, and Classroom import all require the hosted
project, and the only local persistence is SharedPreferences (session,
auto-sync toggle, overlay preferences — no Room, no DataStore, no cache or
outbox). The one component that keeps working offline is the Guidance
assistant, a 134-line deterministic Kotlin engine with no network
dependency. The dashboard's static files load from disk, but every data
call fails into error states and toasts.

**Evidence:** FACTBASE §16 (online-first; no offline writes); FACTBASE §5
(multiplatform-settings as the ONLY local persistence);
`…/domain/guidance/GuidanceEngine.kt` (deterministic, no network);
`WebView/app.js` error handling (:209-216).

**Limitation:** No offline cache or outbox exists — PLANNED as M3.1 (design
notes in `docs/OFFLINE-SYNC.md`, accurately labeled unbuilt) — and one
hosted project means one region, no failover.

## Production readiness and the future

The final four questions look forward: the concrete path to production,
the enumerated gap between the demo configuration and production
readiness, the prioritized next work, and the one architectural decision
worth redoing. The governing honesty rule is that the roadmap is NOT
approved work — it is a sequenced plan drawn from the verified current
state, presented as a plan and not as a promise.

### Q52 — How would you move this to production?

**Q:** Suppose this ships to the whole university next semester. What has
to happen first?

**A:** Follow the roadmap's Tier 2 before anything else, because security
debt precedes release engineering. Tier 2: deploy migrations 0029–0032 to
the hosted project (M2.1) and re-verify the RPC authorizations there
(M2.2); decide and implement production teacher identity verification
(M2.3 — the domain gate is an eligibility proof, not an ownership proof);
commit the working tree and clean the repository (M2.4 — currently 2
commits with the entire current product uncommitted); and finish
credential hygiene, removing or rotating the `client.json` OAuth secret and
auditing `.env` handling (M2.5). Tier 5 then covers release engineering: a
signed APK (M5.1); publishing the Google OAuth consent screen, for which
the `site` Edge Function already provides the authorized-domain branding
URLs (M5.2); production data decisions, including whether the demo seed
data stays on hosted (M5.3); and a final acceptance run with documentation
freeze (M5.4).

**Evidence:** FACTBASE §18 roadmap (5 tiers, 23 milestones); FACTBASE §17
git state; `supabase/config.toml` and `WebView/README.md` for the
configuration items named above.

**Limitation:** The roadmap is explicitly NOT approved work; presenting it
as a sequenced plan is honest, presenting it as committed delivery would
not be.

### Q53 — What is the difference between your demo configuration and production readiness?

**Q:** You keep saying "demo configuration." Enumerate the gap.

**A:** Concretely, in the current configuration: email confirmation is OFF
(`supabase/config.toml` `[auth.email] enable_confirmations = false`), so
sign-ups receive sessions instantly and no verification email is ever
sent; the hosted project's auth mailer is capped at 2 emails per hour;
demo teacher accounts with documented credentials exist (locations noted
in `WebView/README.md`, values not reproduced); demo seed data from
migrations 0009–0011 lives on the hosted project; migrations 0029–0032 are
not deployed; the working tree is uncommitted; a live OAuth client secret
sits in `client.json`; the OAuth consent screen is unpublished; and no
signed release APK exists. Production readiness inverts each item:
verified teacher identity, deployed hardening, a clean committed
repository, rotated credentials, a published consent screen, real data
decisions, and release engineering.

**Evidence:** `supabase/config.toml:230` (enable_confirmations = false)
and :198-203 (email_sent rate limit); FACTBASE §15, §17, §18;
`WebView/README.md` notes on demo accounts and the confirmation flip.

**Limitation:** The demo is fully functional end-to-end, which is exactly
why this enumeration matters: none of these gaps prevent the demo from
working, so they are easy to forget and must be listed rather than hidden.

### Q54 — What would you build next?

**Q:** You have one more month. What gets priority, and why?

**A:** Roadmap order, with reasons grounded in what already exists. First
M2.1/M2.2 — deploy 0032 to hosted and re-verify it there, because shipping
known security debt is indefensible. Then M2.3, the teacher identity
decision, for the same reason. Next M3.3, the moderation queue UI: the
entire backend is already BUILT & VERIFIED (`content_reports`, the role
model, guard triggers, triage policies), so the queue is pure client work
with immediate integrity value. Close behind, M1.1 — wire or remove the
anonymous posting switch, which is an honesty issue in the current UI
(`SupabaseCommunityRepository.kt:149` hard-wires `is_anonymous=false`
while the database fully supports anonymity). Then M3.2, workload
summaries: the `section_workload_daily` view already exists with
security_invoker semantics and no consumer, so the dashboard work is
rendering, not modeling. M3.1, the offline cache, is the biggest
student-value item; M4.1, Classroom Pub/Sub event-driven sync, is
future-only.

**Evidence:** FACTBASE §18 tiers 1–4; FACTBASE §3 feature statuses
(section_workload_daily exists unused; moderation model BUILT & VERIFIED
at DB level).

**Limitation:** NOT approved work; the sequencing reflects the audit's
priorities and could change with real user feedback, which the project has
not yet gathered at scale.

### Q55 — If you could redo one architectural decision, what would it be?

**Q:** One decision, hindsight-graded. Which one?

**A:** The EXECUTE grants on SECURITY DEFINER RPCs. When `teacher_signup`
(0013), `enroll_student_courses` (0017), and
`import_student_classroom_courses` (0022) were created, each carried an
`authenticated` grant even though none had a legitimate authenticated
caller — the enrollment triggers run as definer, and the import runs under
the Edge Function's service key. That one habit created all three audit
findings: the F1 sandbox reproduction showed a plain gmail account
self-granting the teacher role plus six enrollments, and F2/F3 reproduced
foreign-user enrollment and course hijack the same way. The corrective
pattern already existed in the codebase — `upsert_activity_from_source`
(migration 0023) is service-role-only — and 0032 simply applied that house
pattern everywhere as pure REVOKEs. Least-privilege at creation time would
have kept the attack surface closed from day one.

**Evidence:** FACTBASE §15 F1/F2/F3 findings and fixes; migration 0032
header ("no live client needs that door"); rpc_authorization_test T01–T10
PASSED locally.

**Limitation:** The findings were reproduced in a sandbox, not observed as
real abuse, and the fix's deployment state (local only, M2.1 pending) is
itself the open item — the lesson is applied in schema but not yet live on
hosted. A close second: committing incrementally — the uncommitted working
tree obscures exactly this kind of auditable history.

---


# Chapter 35 — Difficult Follow-Up Questions

A follow-up question is what the judge asks after the first answer has
already been given and challenged. The first answer introduced the
project; the follow-up tests whether you understand what you built or
were reciting it. Follow-ups arrive carrying a hidden premise, a wrong
premise, or an invitation to upgrade a claim. This chapter collects the
follow-ups most likely to arrive in a Student Codex defense, each worked
through the same fixed six-part structure.

## 35.1 How to use this chapter

Every entry has six parts, in fixed order: the judge's question, what
they are really testing, the strong factual answer, the technical
explanation, the evidence, and the honest limitation. Read the second
part before answering — several questions are not about the topic they
name, and answering the surface topic walks straight into the trap.
Every answer is grounded in the verified fact base; where the fact base
ends, the entry says so rather than improvising a plausible detail.
Chapter 36 lists the claims that must never appear in any answer, and
Chapter 37 carries the one-page honest status summary to re-read on
defense day. Entries are numbered Q1–Q16; cross-references point at the
fuller treatment instead of repeating it.

> NOTE: Two entries — Q5 and Q9 — rest on a false premise. Correct the
> premise politely first, then answer the real question behind it. Defending
> a false premise is the fastest way to lose a defense.

## 35.2 Architecture and reliability follow-ups

### Q1 — "One shared backend — isn't that a single point of failure?"

**Judge's question.** "You keep saying one shared backend — isn't that a
single point of failure?" **What they are really testing.** Whether you
understand the trade you made, or whether "single source of truth" is a
slogan that collapses when pushed the other way.

**Strong factual answer.** Yes, one availability domain — deliberate. We
traded failover for one source of truth, one RLS rule set, and no
cross-database synchronization to keep honest. If the backend is down,
both clients fail together — a clean total failure, not a split-brain
one.

**Technical explanation.** The app and the dashboard reach the same
PostgREST layer, with row-level security on every client-exposed table;
there is no second database whose divergence we would reconcile. Hosted
Postgres unreachable means no reads and no writes for anyone.
**Evidence.** Architecture and request flows (fact base §4); RLS per
client-exposed table (§13). **Honest limitation.** No high-availability
or failover configuration is documented, and no roadmap milestone
addresses it (§18). If pressed: "not yet; that is release-tier work."

### Q2 — "RLS policies in SQL — how do you test them at scale?"

**Judge's question.** "Your RLS policies live in SQL — how do you test
them, at scale?" **What they are really testing.** Whether policy
security is backed by executed tests or by confidence, and whether you
know what the suite covers.

**Strong factual answer.** As SQL against a real Postgres engine, not by
inspection. On 2026-10-30 the suite ran on a local PostgreSQL 17.11 with
a replicated Supabase platform surface — Docker was unavailable, so the
surface was replicated manually.

**Technical explanation.** Four suites ran: rpc_authorization_test.sql
PASSED (T01–T10 — revokes hold, teacher doors open, service paths,
triggers, domain gate intact); phase_completion_test.sql PASSED;
gc_source_identity_test.sql PASSED with a shim, its fixture predating
the 0012 campus_id column; policies_test.sql PARTIALLY PASSED — two
failures, both predating 0032 and reproduced by a control rebuild
without it. **Evidence.** The 2026-10-30 run record (fact base §15);
plan-push/evidence/AUDIT-EVIDENCE.md. **Honest limitation.** Correctness
tests with seeded fixtures — not load, fuzz, or penetration tests; the
policies_test fixes are open (M1.2); nothing exercises hosted post-0032.

### Q3 — "What if two students import the same course concurrently?"

**Judge's question.** "Two students import the same Google Classroom
course at the same time — what happens?"
**What they are really testing.** Whether you know that races are solved
in the database here, not in the app, and can name the mechanism.

**Strong factual answer.** The import path is serialized and idempotent
in Postgres: a per-course advisory lock inside
import_student_classroom_courses makes concurrent imports of the same
course converge on the same course and section rows instead of racing to
create duplicates.

**Technical explanation.** The matching tiers — exact external_course_id
link, normalized name match with fuzzy fallback, creation under the
Classroom name — run under that lock. At the activity level,
upsert_activity_from_source performs an atomic retry-safe upsert: ON
CONFLICT (source_key) WHERE source_key IS NOT NULL DO UPDATE, backed by
the unique partial index on activity_sources.source_key plus a composite
unique guard. **Evidence.** Migrations 0022 and 0027;
gc_source_identity_test.sql PASSED. **Honest limitation.** Verified
locally with seeded fixtures, not under real parallel load — "the
database guarantees it; we have not load-tested it."

## 35.3 Data quality and trust follow-ups

### Q4 — "Why should we trust student-reported deadlines at all?"

**Judge's question.** "Students can publish anything instantly — why
should anyone trust student-reported deadlines?"
**What they are really testing.** Whether you confuse trust with
labeling — whether the data-quality answer depends on students being
honest.

**Strong factual answer.** Nobody is asked to trust them blindly. Every
row carries provenance: verification_status separates imported,
teacher-confirmed, and student-reported, rendered as visible chips.
No-approval is a deliberate product decision — recording speed for
face-to-face announcements — and the label is the mitigation.

**Technical explanation.** A guard trigger stamps verification_status by
role and raises on mismatch, so a student cannot stamp teacher-confirmed
(migration 0015). The dashboard adds a coverage and data-source card
(WebView/app.js:1355-1410); provenance resolves from the row itself
(SupabaseActivityRepository.kt:203-213). **Evidence.** Migration 0015;
strings.xml:164; WebView/app.js:1355-1410. **Honest limitation.**
Recorded is not complete, and a wrong report stays wrong until its
reporter fixes it — the UI exposes edit only for the reporter's own
personal rows (BeaconScreen.kt:344).

### Q5 — "Your dedup is title-token based — isn't it fragile?"

**Judge's question.** "Your deduplication matches on title tokens —
isn't that fragile?" **What they are really testing.** Whether you know
what your own dedup actually is; the premise is false, and defending it
would be fatal.

**Strong factual answer.** The premise is wrong. Imported-activity dedup
is ID-based: each Classroom item carries a unique source key,
google_classroom:{courseId}:{courseWorkId}, with a unique partial index
and an atomic upsert — one coursework item is one shared row no matter
how many students sync it. Title tokens only classify categories
(suggest_activity_category). MANUAL and STUDENT_REPORT entries are not
deduplicated at all — say that plainly.

**Technical explanation.** Student B syncing what Student A already
synced hits the same source_key and UPDATEs the shared record; repeated
sync attempts never create duplicate rows. Two students reporting the
same face-to-face activity do create two separate section rows — no
similarity logic exists in the app (grep-verified in BeaconScreen.kt and
BeaconViewModel.kt). **Evidence.** Migration 0022;
gc_source_identity_test.sql PASSED; duplicate-reporting verification
dated 2026-11-01 (fact base §8). **Honest limitation.** Manual
duplication is an accepted gap, and the Guidance assistant's canned text
overstates it ("will ask whether it is the same one") — see Q16.

### Q6 — "Why should teachers trust a calendar students populate?"

**Judge's question.** "Why should teachers trust a calendar that
students populate?" **What they are really testing.** Whether the
teacher-side story is more than "labels exist" — what a teacher can
actually do about bad data.

**Strong factual answer.** Teachers do not have to trust it; they can
act on it. Every row is labeled teacher-confirmed or student-reported,
the teacher view is university-wide, and teachers can correct the
category of any activity in sections they teach — locked so later
re-syncs cannot overwrite it.

**Technical explanation.** The set-category PATCH updates activity_type
and sets category_locked and category_locked_by; the guard stamps the
corrector, and future imports preserve a locked category (migration
0023; WebView/app.js:2189-2222). RLS restricts corrections to taught
sections — PATCHing another section's row matches zero rows and gets the
refusal (WebView/app.js:2206). **Evidence.** Migration 0023; migration
0019 (university-wide teacher read). **Honest limitation.** Teachers can
correct categories, not rewrite or remove a student's report, and the
dashboard shows recorded information only — completeness is not
guaranteed.

### Q7 — "How is this different from a shared Google Calendar?"

**Judge's question.** "How is this different from just sharing a Google
Calendar?" **What they are really testing.** Whether the product has a
structural differentiator or a different skin on the same idea.

**Strong factual answer.** A shared calendar is free-form entries with
no provenance and no access model. Student Codex is structured,
RLS-protected data: every activity carries a source and verification
status, a scope (personal rows invisible even to teachers; section rows
visible university-wide), a category with teacher-correction locking, a
read-only Classroom import pipeline — plus a community layer.

**Technical explanation.** The differences are enforceable, not
cosmetic: verification_status and scope sit behind RLS policies
(activities_select, migrations 0019/0020); category corrections survive
re-imports (0023); teacher access is a per-row policy, not a shared
link; Classroom coursework arrives through the Edge Function upsert with
ID-based identity (see Q5). **Evidence.** Migrations 0019 and 0023;
scope semantics (fact base §8). **Honest limitation.** Be fair to the
calendar: it has real-time updates and offline support, and we have
neither (see Q10, Q11).

## 35.4 Security follow-ups

### Q8 — "The service-role key bypasses RLS — isn't that dangerous?"

**Judge's question.** "The service-role key bypasses RLS entirely —
isn't that dangerous?" **What they are really testing.** Whether you
understand that the danger of a bypass key is proportional to who can
reach it and what guards the path.

**Strong factual answer.** It bypasses RLS by design, and its scope is
deliberately narrow: the service-role key lives only in Edge Function
server context and never ships in any client. Exactly two Edge Functions
use it — classroom-import and classroom-sync — and both verify the
caller's Supabase session JWT against /auth/v1/user before any
privileged call.

**Technical explanation.** In classroom-import that manual check is
documented in the source as "the security boundary that protects the
RPC" (functions/classroom-import, header comment); classroom-sync
performs the same verification (functions/classroom-sync, :48-59) before
invoking upsert_activity_from_source with the service key. After
migration 0032, EXECUTE on the privileged RPCs is revoked from
authenticated. **Evidence.** Migration 0032 revokes (the F2 fix); both
Edge Function sources; fact base §15. **Honest limitation.** 0032 is
locally tested only — hosted sits at 0028, and hosted ACL probes on
2026-10-29/30 showed the RPCs still executable by authenticated there
(M2.1, M2.2).

### Q9 — "Email confirmation is off — couldn't anyone become a teacher?"

**Judge's question.** "Email confirmation is off — couldn't anyone sign
up and become a teacher?" **What they are really testing.** Whether you
know the exact state of your teacher gate, including the hole you found
yourself.

**Strong factual answer.** On the hosted project today, the honest
answer is yes — and we found it ourselves. The F1 audit finding: legacy
teacher_signup (migration 0013), granted to authenticated with only an
auth.uid()-is-not-null gate — a sandbox reproduction gave a gmail
account the teacher role and six enrollments. Migration 0032 revokes it.
The remaining doors, teacher_signup_global and teacher_signup_multi,
enforce the 0031 @parsu.edu.ph domain gate, which proves eligibility,
not mailbox ownership — email confirmation is off in the test
configuration (supabase/config.toml, enable_confirmations = false).

**Technical explanation.** The suffix check runs server-side inside the
sign-up RPCs, so a client cannot skip it; what it cannot do is verify
that the signer controls the address. The 0028–0030 OTP and email-click
machinery remains in the schema as dormant fallback. **Evidence.** F1
finding and sandbox reproduction (fact base §15); migration 0031
(SQL-tested T09/T10); migration 0032. **Honest limitation.** Production
teacher identity verification is UNRESOLVED (roadmap M2.3), and until
0032 is deployed the hosted door stays open.

## 35.5 Freshness and scope follow-ups

### Q10 — "What happens when Classroom changes an assignment after everyone already synced?"

**Judge's question.** "Google Classroom edits a deadline after all your
students synced — what happens?" **What they are really testing.**
Whether you will claim freshness you do not have.

**Strong factual answer.** Until the next successful sync, the shared
row is stale — plainly stated. There is no push, no Pub/Sub, and no
background service; sync happens when the app opens (opt-in auto-sync),
when the user presses Sync now, or during the import picker. The next
successful sync by any enrolled student updates the one canonical row
for everyone.

**Technical explanation.** Auto-sync runs on app ON_START via a
LifecycleEventObserver and when the toggle flips; it is silent-only,
pinned to the chosen Google account, skips when consent is needed, and
never throws (ClassroomAutoSync.kt; StudentCodexApp.kt:215-234). The
upsert updates the shared row, preserving any teacher-locked category
(migration 0023). **Evidence.** Grep-verified zero push/Pub/Sub matches
across Edge Functions and migrations (fact base §11).
**Honest limitation.** If nobody syncs, a Classroom change never
propagates; event-driven sync is future work only (roadmap M4.1).

### Q11 — "No offline support in 2026?"

**Judge's question.** "An academic app with no offline support in 2026 —
seriously?" **What they are really testing.** Whether you treat scope as
a decision or an oversight, and whether you know what works without
connectivity.

**Strong factual answer.** It is a deliberate MVP scope decision, not an
oversight: the app is online-first, and only the Guidance assistant
works fully offline because it is deterministic and on-device.
Everything else requires connectivity, and we say so rather than demoing
a cache that does not exist.

**Technical explanation.** There is no Room, DataStore, or WorkManager
in the app — the only local persistence is multiplatform-settings
(SharedPreferences) holding the session, the auto-sync toggle, and
overlay preferences. The offline design (Room cache plus WorkManager
write outbox) is documented in docs/OFFLINE-SYNC.md and accurately
labeled as unbuilt. **Evidence.** The dependency set in
app/build.gradle.kts (fact base §5); docs/OFFLINE-SYNC.md.
**Honest limitation.** Offline cache and write sync are roadmap M3.1,
PLANNED — no code exists toward it; the honest demo answer is
"connectivity required."

## 35.6 Evidence, process, and readiness follow-ups

### Q12 — "Your working tree isn't even committed — how do we audit it?"

**Judge's question.** "Only two commits — the whole product is
uncommitted. How do we audit any of this?"
**What they are really testing.** Process maturity, and whether your
documentation is honest about the state it describes.

**Strong factual answer.** Correct: two commits exist (the initial
import and an auth-gate button tweak), and the entire current product —
the dashboard rework, migrations 0021–0032, the classroom-import and
site Edge Functions, PLAN.md v2.2 — is uncommitted working-tree state,
alongside roughly ninety root-level dev-script debris files. Committing
it is roadmap M2.4.

**Technical explanation.** What makes the work auditable today is that
the documentation does not pretend otherwise: this handbook and the fact
base cite the working-tree state explicitly, and the 2026-10-31 audit
evidence files (plan-push/evidence/AUDIT-EVIDENCE.md, REVIEW-F1F2F3.md)
record what was inspected and how it was verified. **Evidence.** Git
state verified 2026-11-01: a 59-entry status listing (31 modified, 1
deleted, about 27 untracked). **Honest limitation.** Until M2.4 there is
no immutable history to diff against; auditability rests on the evidence
files, not on git log.

### Q13 — "What did you actually verify on 2026-10-30?"

**Judge's question.** "You keep saying 'verified' — what exactly did you
verify on 2026-10-30?" **What they are really testing.** Precision about
evidence, and whether "verified" means the same thing every time you say
it.

**Strong factual answer.** On 2026-10-30, on a local PostgreSQL 17.11
with a replicated Supabase platform surface (Docker unavailable), four
SQL suites ran: rpc_authorization_test.sql PASSED (T01–T10 — revokes
hold, teacher doors open, service paths, triggers, domain gate intact);
phase_completion_test.sql PASSED; gc_source_identity_test.sql PASSED
with a temporary shim, its fixture predating the 0012 campus_id column;
policies_test.sql PARTIALLY PASSED.

**Technical explanation.** The two policies_test failures are a programs
fixture lacking campus_id, and T08.1 expecting SQLSTATE 42501 where
migration 0015's guard raises P0001 — both unrelated to 0032 and
predating it; a control rebuild without 0032 reproduced them.
Separately, the dashboard and Classroom sync were browser-verified live
on 2026-10-28. **Evidence.** The test evidence record (fact base §15);
plan-push/evidence/AUDIT-EVIDENCE.md. **Honest limitation.** All of it
is local: hosted remains at 0028, and the Edge Functions were not
re-exercised against real Google OAuth in that run (roadmap M1.5).

### Q14 — "Is this production-ready?"

**Judge's question.** "Bottom line — is this production-ready?" **What
they are really testing.** Whether you can enumerate your own gap list
without being asked to.

**Strong factual answer.** No — it is a demo configuration, and the gap
list is written down. Roadmap Tier 2 is exactly this list: M2.1 deploy
migrations 0029–0032 to hosted; M2.2 verify 0032 there after deployment;
M2.3 decide production teacher identity verification (currently
UNRESOLVED); M2.4 commit the working tree; M2.5 credential hygiene for
client.json and .env.

**Technical explanation.** The blockers behind those items: the hosted
project still exposes the pre-0032 RPC doors (probed 2026-10-29/30),
email confirmation is off, demo seed data lives on the hosted database
with production data decisions pending (M5.3), and the auth rate limit
is a dashboard-managed test value (email_sent 2/hour). **Evidence.**
Roadmap Tier 2 (fact base §18); §15 and §16. **Honest limitation.** Tier
1 verification gaps ride along: the policies_test fixes (M1.2), the gc
fixture fix (M1.3), Android visual re-verification (M1.4), and Edge
live-OAuth re-verification (M1.5) — all open.

## 35.7 Product-edge follow-ups

### Q15 — "Does anonymous posting actually work?"

**Judge's question.** "Your community has an anonymous switch — does it
work?" **What they are really testing.** Whether you will demo a switch
whose effect is silently dropped three layers down.

**Strong factual answer.** No — anonymous posting is PARTIALLY
IMPLEMENTED, and we say that before anyone finds it. The composer switch
exists and toggles (CommunityScreen.kt:347-360), but the ViewModel drops
the flag when submitting (CommunityViewModel.kt:166), and the repository
hard-wires is_anonymous=false on posts and comments alike
(SupabaseCommunityRepository.kt:149 and :110).

**Technical explanation.** The backend is not the blocker: the schema,
views, and seeds support anonymity — feed views null the author
server-side — so the fix is wiring the flag through, tracked as roadmap
M1.1, "wire-or- remove": connect it or remove the switch. **Evidence.**
Line-level verification (fact base §9) and the source mirrors.
**Honest limitation.** Until M1.1, every post publishes with the
author's name regardless of the switch; demoing anonymity would
demonstrate something the app does not do.

### Q16 — "Which LLM does your Guidance assistant run?"

**Judge's question.** "Your Guidance assistant — which model is it
running?" **What they are really testing.** Whether you will accept a
flattering AI attribution for a deterministic component.

**Strong factual answer.** None. It is a rule-based deterministic
engine: six keyword and phrase rules over normalized input, each with an
explicit precedence (add-activity 30, beacon 25, classroom 20, community
15, study 10, planning 10); the highest precedence wins, and empty or
unrecognizable input gets an honest fallback asking the user to
rephrase.

**Technical explanation.** GuidanceEngine.kt defines the interface and
DemoGuidanceEngine; the rules are data, not screen code; there is no
context retention beyond the visible transcript and no external model.
It is unit-tested (DemoGuidanceEngineTest) and works fully offline (see
Q11). **Evidence.** GuidanceEngine.kt; fact base §10.
**Honest limitation.** Its canned text contains known overstatements — a
duplicate-check prompt the app does not have, plus "up to three images"
and anonymous posting the app does not support. Do not repeat its claims
as product facts.

## 35.8 How to drill this chapter

Drill these in pairs: one person reads only the judge's question and
improvises follow-up pressure, the other answers aloud in the six-part
shape, then both check the entry. If you can produce the testing intent,
the mechanism, the evidence, and the limitation in order, the answer is
defensible even when the exact question was never rehearsed. When a
question is not in this chapter, fall back to the discipline that
produced it: give the status label verbatim, attach the evidence path,
and state the limitation before the judge asks for it. Questions you
cannot ground that way should be answered "that is not documented" — an
acceptable answer in this defense; a fabricated one is not.

---


# Chapter 36 — Questions the Team Must Never Answer Incorrectly

A weak answer loses a point; a wrong answer loses the room. Under defense
pressure the typical failure is not ignorance but upgrade: PARTIALLY
IMPLEMENTED becomes "works", PLANNED becomes "built", and locally tested
becomes deployed, each spoken in the confident tone of someone describing
the system they intended to build rather than the one they verified. Judges
grade these sentences harder than any technical gap, because a team that
overstates one capability cannot be trusted on the rest.

The status label system exists to prevent exactly this. Seven labels —
BUILT & VERIFIED, IMPLEMENTED — VERIFICATION INCOMPLETE, PARTIALLY
IMPLEMENTED, PLANNED, DEFERRED, KNOWN LIMITATION, UNRESOLVED — were assigned
per capability from verified evidence, and no sentence in the defense room
may upgrade one. This chapter lists the twelve overclaims most likely to
slip out, the accurate statement to say instead, and why the distinction
matters. Chapter 35 rehearses the hard questions; this chapter polices the
answers.

> WARNING: If a sentence you are about to say is not supported by the
> accurate column below or by the fact base, do not say it. "That is not
> documented" is always available and always safe.

## 36.1 The warning table

Read the table before every rehearsal and again before entering the room. The
first column is the trap phrasing — all of it sounds natural in conversation,
which is precisely the danger. The second column is the replacement sentence,
which you should be able to deliver verbatim. The third column states what is
at stake if the overclaim survives unchallenged. In rehearsal, cold-read the
first column aloud and have the team answer with the second column from
memory; an answer that needs thinking time in the room is an answer that will
drift toward the overclaim under pressure.

| Overclaim (NEVER say) | The accurate statement | Why it matters |
|---|---|---|
| "We have complete real-time synchronization" | Client-triggered only: app open (opt-in), Sync now, import picker; no push, no Pub/Sub | Falsifiable in one follow-up question |
| "The app works fully offline" | Online-first; no Room, no outbox; only the on-device Guidance assistant works offline | A judge can ask for an offline demo |
| "Every face-to-face activity is automatically detected" | Students report them manually; recorded is not complete | Overstates the core product premise |
| "Manual reports cannot be incorrect" | Instant publish, no approval queue; provenance labels are the mitigation | The schema cannot guarantee correctness |
| "Title matching guarantees deduplication" | Imported dedup is ID-based source-key upsert; title tokens only classify categories; MANUAL entries have no dedup | Misstates your own architecture |
| "Teacher registration proves real email ownership" | The @parsu.edu.ph suffix proves eligibility only; email confirmation is OFF | A simply false security claim |
| "Migration 0032 has been deployed" | Locally tested only; hosted project is at 0028 | The most dangerous deployment overclaim |
| "All SQL tests pass" | policies_test is PARTIALLY PASSED; gc_source_identity needed a shim | Collapses under one follow-up |
| "The Guidance Assistant uses generative AI" | Deterministic keyword rules — six rules with explicit precedences | Accepting a false AI attribution |
| "Workload analytics exist" | The DB view exists; no client consumes it | A live demo request would expose it |
| "Anonymous posting works" | UI switch only; the flag is dropped in the ViewModel and hard-wired false in the repository | The switch is visible in any community demo |
| "The app makes direct RPC calls" | Zero direct RPC calls from the app; REST tables plus Edge Functions only | Judges can read the request path in code |

## 36.2 Corrective text, overclaim by overclaim

The table is for the room; these paragraphs are for the tongue. Each one
gives the full accurate statement with its evidence, so the correction can
survive a second and third follow-up rather than only the first.

**1. "We have complete real-time synchronization."** Sync is client-triggered
only, on three triggers: the opt-in auto-sync that runs when the app opens
(a LifecycleEventObserver on ON_START — not a background service; see
StudentCodexApp.kt:215-234 and ClassroomAutoSync.kt), the manual Sync now
control, and the import picker. There is no push, no Pub/Sub, no WorkManager,
and no FCM — grep-verified zero matches across Edge Functions and migrations.
A Classroom deadline edit is not reflected until the next successful sync by
any enrolled student. Say: "client-triggered sync; freshness ends at the
last successful sync."

**2. "The app works fully offline."** The app is online-first: every read and
write except the Guidance assistant requires connectivity. There is no Room,
DataStore, or WorkManager — the only local persistence is multiplatform-settings
(SharedPreferences) holding the session, the auto-sync toggle, and overlay
preferences. Only the Guidance assistant works offline, because it is a
deterministic on-device rule engine. The offline design (Room cache plus
WorkManager write outbox) is documented in docs/OFFLINE-SYNC.md and accurately
labeled as unbuilt; it is roadmap M3.1, PLANNED.

**3. "Every face-to-face activity is automatically detected."** Nothing
detects anything. Face-to-face announcements reach the system only when a
student types them in — that is the product: labeled recording, not sensing.
Every row carries provenance (imported, teacher-confirmed, student-reported),
and the dashboard's coverage and data-source card (WebView/app.js:1355-1410)
shows what has been recorded, never what exists in the real world. The
honest formula, used everywhere in this handbook: recorded is not complete.

**4. "Manual reports cannot be incorrect."** A student report is an instant
publish — no approval queue exists anywhere (migration 0015;
Repositories.kt:14-24; strings.xml:164, "No approval needed."). The
mitigations are labeling (verification_status), teacher category corrections
(migration 0023), and community reporting (content_reports) — not gating.
Two students reporting the same real-world activity create two separate
section rows, and a wrong report stays wrong until its reporter edits it;
the UI exposes edit only for the reporter's own personal rows
(BeaconScreen.kt:344).

**5. "Title matching guarantees deduplication."** Imported-activity
deduplication is ID-based: activity_sources.source_key
(google_classroom:{courseId}:{courseWorkId}) carries a unique partial index,
and upsert_activity_from_source performs an atomic retry-safe upsert — one
shared row per coursework item, updated by every later sync. Title tokens do
something else entirely: suggest_activity_category classifies categories.
MANUAL and STUDENT_REPORT entries are not deduplicated at all. Verified by
gc_source_identity_test.sql (PASSED, with a temporary compatibility shim
whose fixture predates the 0012 campus_id column).

**6. "Teacher registration proves real email ownership."** The 0031
@parsu.edu.ph domain gate runs server-side inside the sign-up RPCs and proves
eligibility — the address is school-shaped. It does not prove the signer
controls that mailbox, because email confirmation is off in the test
configuration (supabase/config.toml, enable_confirmations = false). The
0028–0030 OTP and email-click machinery remains as dormant fallback, and
production identity verification is UNRESOLVED (roadmap M2.3, decision
needed). The accurate sentence: "the gate proves eligibility, not ownership."

**7. "Migration 0032 has been deployed."** No. 0032 is applied and tested
locally only; the hosted project runs migrations through 0028, and 0029–0032
exist as local untracked files. Hosted ACL probes on 2026-10-29/30 (non-
mutating) showed the three hardened RPCs still executable by authenticated
on the hosted project — the pre-0032 state. Deployment is roadmap M2.1 and
post-deploy hosted verification is M2.2. This is the single most important
deployment sentence in the defense: 0032 is locally tested, NOT deployed.

**8. "All SQL tests pass."** The exact outcomes, from the 2026-10-30 run on
a local PostgreSQL 17.11 with a replicated Supabase platform surface:
rpc_authorization_test.sql PASSED (T01–T10); phase_completion_test.sql
PASSED; gc_source_identity_test.sql PASSED with a temporary compatibility
shim; policies_test.sql PARTIALLY PASSED — its programs fixture lacks the
0012 campus_id column, and T08.1 expects SQLSTATE 42501 where migration
0015's guard raises P0001. Both failures predate 0032 and were reproduced by
a control rebuild without it. Recite the list; precision here is credibility
everywhere.

**9. "The Guidance Assistant uses generative AI."** It does not, and the
team must not accept the flattering attribution. GuidanceEngine.kt defines a
deterministic engine: six keyword and phrase rules over normalized input,
each with an explicit precedence (add-activity 30, beacon 25, classroom 20,
community 15, study 10, planning 10); the highest precedence wins, and
unrecognizable input gets an honest fallback. It is unit-tested
(DemoGuidanceEngineTest). Note the extra trap: the assistant's own canned
text overstates two app behaviors (a duplicate-check prompt; "up to three
images" and anonymous posting) — do not repeat its claims as product facts.

**10. "Workload analytics exist."** The database view section_workload_daily
exists (security_invoker; per-section, per-day activity_count and
total_effort_minutes), but no client consumes it — the dashboard has no
workload summary, aggregate analytics, or proposed-deadline preview
(grep-verified zero matches in WebView/). Building the client is roadmap
M3.2, PLANNED. The accurate sentence: "the view exists; the analytics client
does not."

**11. "Anonymous posting works."** It is PARTIALLY IMPLEMENTED: the composer
switch exists and toggles (CommunityScreen.kt:347-360), but
CommunityViewModel.kt:166 drops the flag when submitting, and
SupabaseCommunityRepository.kt:149 hard-wires is_anonymous=false — the
comment path likewise at :110. The backend is ready (schema, views, and
seeds support anonymity; feed views null the author server-side), so the fix
is wiring, tracked as roadmap M1.1, "wire-or-remove." Until then, every post
publishes with the author's name.

**12. "The app makes direct RPC calls."** The Android app makes zero direct
RPC calls — verified: all reads and writes go through PostgREST REST on
tables, and the privileged paths go through the classroom-import and
classroom-sync Edge Functions. The teacher dashboard is the surface that
invokes RPCs directly at sign-up (teacher_signup_global /
teacher_signup_multi). Keeping this straight matters because the RPC layer
is exactly where the F1/F2/F3 hardening story lives (see Chapter 35, Q8).

## 36.3 Where the bait comes from

Three of the twelve overclaims are invited by the product's own surfaces,
which is why they slip out so easily. First, the Guidance assistant's canned
text overstates app behavior: it claims Student Codex will ask whether an
activity is the same one before saving (no duplicate-check prompt exists),
and its community answer promises up to three images and anonymous posting
(the app posts one image and does not persist the anonymous flag). Reading
that text aloud in a demo is how overclaims 5, 9, and 11 enter the room.
Second, the composer's anonymous switch is a visible affordance whose effect
is dropped three layers down — demonstrating it without stating its status is
how overclaim 11 survives. Third, the dashboard's coverage card and filter
bar look like analytics, but no workload summary or aggregate view exists
behind them — that is how overclaim 10 gets made.

The discipline: every surface you show carries a status label in your head
before you show it. The switch is PARTIALLY IMPLEMENTED; the coverage card is
recorded-not-complete; the assistant is deterministic-with-drift. Say the
label as you point at the surface, and the bait never lands.

## 36.4 The pattern behind the twelve

Every overclaim in the table is the same act: upgrading an honest label to
BUILT & VERIFIED under social pressure. Real-time is an upgrade of
client-triggered; offline is an upgrade of online-first; analytics is an
upgrade of a PLANNED client on top of a real view; deployment is an upgrade
of IMPLEMENTED — VERIFICATION INCOMPLETE. The defense against all twelve is
therefore one habit, not twelve facts: attach the status label to every
capability sentence before the sentence leaves your mouth, and let the label
cap the claim. The full status table is Chapter 37; the label definitions are
the fact base's own.

## 36.5 If you misspeak, recover like this

Stop, name the error, restate accurately, and give the evidence — in that
order, out loud, without softening. "Let me correct that: migration 0032 is
locally tested, not deployed — hosted is at 0028, and deployment is roadmap
M2.1" is a complete recovery in one sentence. What disqualifies is not the
mistake but the defense of it: softeners like "essentially deployed" or
"basically real-time" read as intent to mislead, and a judge who catches one
will re-audit every claim you made before it. Corrected immediately, a
misspeak costs a point; defended, it costs the defense.

---


# Appendix — Honest Status Summary & Defense Readiness Checklist

This chapter is the defense-room page: it condenses the honest status summary
of Chapter 29, the readiness checklist of Chapter 30, and the closing
discipline of Chapter 39 into one sequence designed to be read in five
minutes on the morning of the defense. Nothing here is new — every row and
item restates verified fact-base content in the order you will need it — but
the compression is the point. Under pressure you will not re-derive statuses;
you will remember whichever page you rehearsed last.

Read it in this order: the status table first, to cap every capability claim
at its verified level; the checklist second, to confirm you can produce each
defense-critical statement on demand; the five sentences last, because they
are the final thing you should say to yourself before entering the room. The
seven status labels are used verbatim throughout and may never be upgraded —
Chapter 36 explains what happens to a defense when one is. If the morning
allows only one rehearsal, rehearse this page, not the slides: the slides
describe the project you built, and this page describes the project you can
defend.

## A.1 The honest status summary

One table, the whole project. The Status column carries the seven labels
verbatim; qualifiers in the evidence column keep each row honest about what
"verified" means for that row. If you are ever unsure which label applies in
the room, choose the weaker one — a downgrade costs a point, an upgrade costs
credibility.

| Module | Status | One-line evidence |
|---|---|---|
| Android app (overall) | BUILT & VERIFIED | Auth gate, Beacon, Community, Settings; 11 unit-test files |
| Email/password auth | BUILT & VERIFIED | Android auth gate; AuthRepository.kt |
| Google Sign-In | IMPLEMENTED — VERIFICATION INCOMPLETE | Verified during development; not re-exercised in the 2026-10-30 pass |
| Guest/demo mode | BUILT & VERIFIED | AuthGateScreen |
| Profile completion (Google-first) | BUILT & VERIFIED | AuthGateScreen.kt:413 |
| School registry dropdowns | BUILT & VERIFIED | Sign-up form (campus/program/year/section) |
| Course enrollment by name | BUILT & VERIFIED | enroll_student_courses RPC (0017/0018/0027) |
| Classroom course import | BUILT & VERIFIED | classroom-import Edge Fn; SupabaseClassroomImportRepository.kt |
| Classroom coursework/announcement sync | BUILT & VERIFIED | classroom-sync Edge Fn; live browser-verified 2026-10-28; Edge Fns not re-exercised vs real Google OAuth in the 2026-10-30 SQL run |
| Auto-sync on app open | BUILT & VERIFIED | StudentCodexApp.kt ON_START + ClassroomAutoSync.kt; opt-in, not a background service |
| Manual activity publish | BUILT & VERIFIED | Migration 0015; instant section publish, no approval queue |
| Beacon list, filters, detail sheet | BUILT & VERIFIED | BeaconScreen.kt; ActivityDetailSheet.kt |
| Import dedup + classification | BUILT & VERIFIED | upsert_activity_from_source; gc_source_identity_test.sql |
| Teacher category corrections | BUILT & VERIFIED | category_locked (0023); corrections survive re-syncs |
| Community feed, posts, likes | BUILT & VERIFIED | SupabaseCommunityRepository.kt |
| Comments | PARTIALLY IMPLEMENTED | Flat in app; DB supports depth-5 nesting (Community.kt) |
| Anonymous posting | PARTIALLY IMPLEMENTED | Switch only; flag dropped (CommunityViewModel.kt:166); hard-wired false (SupabaseCommunityRepository.kt:149) |
| Post reporting + triage | BUILT & VERIFIED at DB level; no moderator UI | content_reports (000400) |
| Guidance assistant | BUILT & VERIFIED | GuidanceEngine.kt; deterministic rules, honest fallback |
| Teacher dashboard | BUILT & VERIFIED | Browser-verified 2026-10-28; WebView/app.js |
| Teacher domain gate | BUILT & VERIFIED | Migration 0031 @parsu.edu.ph; SQL-tested T09/T10 |
| RPC hardening (0032, F1/F2/F3) | IMPLEMENTED — VERIFICATION INCOMPLETE | Locally tested, NOT deployed; hosted at 0028 |
| Public home page + privacy policy | BUILT & VERIFIED | functions/site |
| Offline cache / outbox | PLANNED | docs/OFFLINE-SYNC.md only; Room/WorkManager design unbuilt |
| Push notifications / reminders | DEFERRED | Settings placeholder row |
| Workload analytics | PLANNED | section_workload_daily view exists; no client consumes it |
| Production teacher identity verification | UNRESOLVED | M2.3 decision needed; email confirmation OFF |
| Classroom change freshness | KNOWN LIMITATION | Stale until the next successful sync; no push/Pub/Sub |
| Manual-entry duplication | KNOWN LIMITATION | No dedup for MANUAL/STUDENT_REPORT; two reporters, two rows |
| Recorded coverage | KNOWN LIMITATION | Dashboard shows recorded data only; completeness not guaranteed |
| Repository hygiene | KNOWN LIMITATION | 2 commits; 59-entry working tree; roadmap M2.4 |

Two reading rules keep the table honest. First, the qualifiers are part of
the status: "BUILT & VERIFIED" for Classroom sync explicitly carries
"browser-verified 2026-10-28; Edge Functions not re-exercised against real
Google OAuth in the 2026-10-30 SQL run" — dropping the qualifier is an
upgrade by omission. Second, the four KNOWN LIMITATION rows are permanent
properties of the current design, not pending bugs: freshness, manual
duplication, recorded-not-complete, and the uncommitted tree each require a
product or process decision rather than a fix that is already written.

A third rule applies while speaking: the table is the ceiling, not the
target. If a judge asks about a module whose row you cannot recall, say the
weaker label you are sure of and offer to be corrected against the table —
never interpolate a status from memory in the upward direction. The table
takes five minutes to re-read; credibility, once spent on an upgrade, does
not come back in the room.

## A.2 The defense readiness checklist

Each item below is a capability you must be able to state aloud, with its
why. Tick an item only when the statement comes out complete on the first
try; a statement that needs rehearsal time in the room is not ready. The
themes follow the order a defense usually arrives: problem, architecture,
database, Classroom flow, dedup, authorization, limitations, then the
rehearsal and discipline items that keep the rest accurate. Forty items look
like a lot; spoken aloud they take under twenty minutes, and the failures
are the useful part — every unticked box is a sentence a judge would
otherwise hear you say badly before you learned to say it well.

### Problem

- [ ] State the problem in one breath — Classroom covers online coursework only, face-to-face announcements never reach it, nothing gives university-wide visibility — because judges grade the framing before the architecture.
- [ ] Say "complements Classroom, read-only import — it does not replace it" — because scope confusion reads as misunderstanding the ecosystem.
- [ ] Name both user groups and the shared-data premise — because every later answer depends on it.
- [ ] Say what a student does on day one — sign up with school dropdowns, enroll by course codes, optionally import Classroom — because concreteness beats abstraction in the first minute.

### Architecture

- [ ] Draw the one-backend picture — app and dashboard both to Supabase (Auth, PostgREST with RLS, Edge Functions, Storage), Edge Functions to the Classroom API — because every later answer depends on this shape.
- [ ] Say "single source of truth, one RLS rule set, no cross-database sync" — because it preempts the split-brain question.
- [ ] Name the three Edge Functions and their jobs (classroom-import, classroom-sync, site) — because miscounting your own functions is fatal.
- [ ] Say the app makes zero direct RPC calls — REST tables plus Edge Functions only — because the request path is readable in code and judges check it.

### Database

- [ ] State "33 migrations, 000000–003200; hosted through 0028; 0029–0032 local-only" — because the deployment line is your most testable claim.
- [ ] Name the guard-trigger layer — scope/role/enrollment checks, rate guards, category stamping — because it shows enforcement is server-side.
- [ ] Say activities carry soft delete (deleted_at) and provenance columns — because the data-integrity answers hang off them.
- [ ] Name the unique partial index on activity_sources.source_key — because it is the physical object behind the dedup guarantee.

### Classroom flow

- [ ] Walk the import path — account picker, consent, classroom-import with the session JWT verified and courses re-fetched server-side — because the security boundary sits in the middle of it.
- [ ] Recite exactly three sync triggers (app open opt-in, Sync now, import picker) and nothing more — because claiming more is the classic overclaim.
- [ ] Say the Google access token is transit-only and never stored — because it is the next question after the flow.
- [ ] Say due dates normalize to Asia/Manila 23:59, fixed +08:00 — because timezone handling is a detail that signals care.

### Dedup

- [ ] Say "ID-based source key, atomic upsert, one shared row per coursework item" — because this is the project's hardest-won guarantee.
- [ ] Say "title tokens classify categories only; MANUAL entries are not deduplicated" — because conflating the two systems gets the architecture wrong.
- [ ] Mention category_locked surviving re-syncs — because it proves teacher authority outlasts imports.
- [ ] State that Student B's sync of Student A's item UPDATEs the shared row — because "never a second row" is the sentence judges remember.

### RLS and authorization

- [ ] Separate authentication, teacher role, and per-row RLS — because "signed in" does not mean "teacher" in this system.
- [ ] State the university-wide teacher read rule (scope section or course; personal rows excluded) — because it is the dashboard's defining policy.
- [ ] Say the service-role key is Edge-Function-only and 0032 revokes authenticated EXECUTE — locally tested, not deployed — because the F1/F2/F3 story must carry its own deployment state.
- [ ] Say anonymous is denied everywhere by policy (policies_test T03) — because publishable-key questions end there.

### Limitations

- [ ] Say "recorded is not complete" unprompted — because it is the product's honest premise.
- [ ] List offline (PLANNED), push (DEFERRED), moderation UI (PLANNED), analytics client (PLANNED) in one breath — because a fluent gap list reads as control, not weakness.
- [ ] Say anonymous posting is a UI switch that is not persisted — because the switch is visible in any community demo.
- [ ] Know the one UI-narrower-than-DB case — section-report self-edit is policy-allowed (0015) but not exposed in the app — because the nuance proves you know the boundary.

### Demo rehearsal

- [ ] Know the last verified date of every live path you will show (dashboard and sync browser-verified 2026-10-28) — because "when did you last see this work" will be asked.
- [ ] Plan the connectivity answer before demoing — because the app is online-first and a network hiccup must not become an improvisation.
- [ ] Rehearse the teacher category correction and its refusal case — because the refusal is the proof that RLS, not the UI, decides.
- [ ] Rehearse the guest-mode boundary — guests read demo content and cannot write — because a judge may try it.

### Test-status accuracy

- [ ] Recite the four suites with exact outcomes — rpc_authorization PASSED (T01–T10), phase_completion PASSED, gc_source_identity PASSED with a shim, policies PARTIALLY PASSED — because precision here is credibility everywhere.
- [ ] Say the two policies_test failures predate 0032 and were reproduced by a control rebuild — because otherwise they look like your fix broke something.
- [ ] Distinguish the local PostgreSQL 17.11 replicated surface from the hosted project — because "verified" without venue is the biggest ambiguity in the room.
- [ ] State the hosted ACL probe result (2026-10-29/30, non-mutating): the RPCs are still executable by authenticated — because it is the evidence behind "not deployed".

### No-overclaims discipline

- [ ] Cold-read Chapter 36's first column once before entering — because those twelve rows are the exact traps.
- [ ] Attach a status label to every capability sentence — because labels cap claims under pressure.
- [ ] Correct any misspeak immediately, with the accurate statement and its evidence — because recovery is scored and concealment is disqualifying.
- [ ] Give one team member the label-enforcer role, catching upgrades in real time — because a second listener hears drift the speaker cannot.

## 37.3 The five sentences to memorize

If only five sentences survive the walk to the defense room, these are the
five. Each one compresses an entire chapter of honesty into a single sayable
line, and together they cover what the product is, how its central mechanism
works, what its security posture is, what is not deployed, and what is not
built. Memorize them verbatim; the wording is load-bearing. If a sentence
feels too negative in the room, that is the sentence working — every one of
them replaces an overclaim that would have sounded better and collapsed
under a single follow-up.

1. **What the product is.** "Student Codex is an Android student app plus a
   teacher web dashboard over one shared Supabase backend, combining
   read-only Google Classroom imports with student-reported face-to-face
   activities into one provenance-labeled, RLS-protected feed."
2. **How dedup works.** "Imported activities deduplicate by Google's own IDs
   through a unique source key and an atomic upsert — one shared row per
   coursework item — and manual and student-reported entries have no
   deduplication at all."
3. **What security is.** "Security is authentication plus row-level security
   on every client-exposed table, with the privileged RPCs locked to service
   context by migration 0032 — locally tested, not yet deployed to hosted."
4. **What is not deployed.** "The hosted project runs migrations through
   0028; migrations 0029 through 0032, including the RPC hardening, exist
   and pass locally only."
5. **What is not built.** "There is no offline cache, no push notifications,
   no moderation queue UI, and no workload-analytics client, and anonymous
   posting is a UI switch that is not persisted."

Each sentence defuses one family of overclaim from Chapter 36: the first
prevents scope inflation, the second kills the title-matching confusion, the
third states the security model without certification claims, the fourth is
the deployment truth, and the fifth is the gap list said plainly. A team that
can deliver these five, unprompted and unhurried, has already demonstrated
the thing the judges are actually testing — that every claim made about
Student Codex is one the team can ground in verified evidence.

> NOTE: Do not paraphrase the five sentences under pressure — paraphrase is
> where upgrades creep back in. If the exact wording is lost in the moment,
> fall back to the status label from the table above and offer to be checked
> against this chapter.

---

