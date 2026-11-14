# Student Codex — Replication Specification

> **Document status — v2.2, authoritative, 31 October 2026. Supersedes v2.1
> (28 October 2026, with the 29 October 2026 teacher email-verification
> addendum). New in v2.2: migrations 0029–0032 documented (including the
> 2026-10-30/31 RPC execute hardening — migration 0032 is locally tested and
> NOT yet deployed to the hosted project), an honest SQL test-status register
> (Appendix C), corrected stale claims, and a reality-based development
> roadmap (§10.3).**
> This document REPLACES the previous build plan as the authoritative project document.
> It is a complete, self-contained specification of the Student Codex application
> **as it exists today**: the Android student app, the standalone teacher web dashboard,
> and the shared Supabase backend. It is written so that another engineering agent can
> reproduce the current implementation faithfully — same architecture, same behavior,
> same visual appearance — without access to prior conversations.
>
> **Rules of this document:** it describes what IS implemented (grounded in the current
> source code, database migrations, Edge Functions, and browser-verified behavior of the
> teacher dashboard on 28 October 2026, re-audited 31 October 2026). Superseded ideas
> from the original build plan are quarantined in Appendix A (clearly labeled
> HISTORICAL — never follow them). Deliberate product decisions and honest gaps are
> listed in §10. Configuration values are identified by NAME and FILE LOCATION only —
> no credentials, keys, or passwords appear in this document.
>
> **Evidence base:** workspace sources read in full on 2026-10-28 and re-audited
> 2026-10-31 (Android Kotlin sources, `WebView/` website, **33 SQL migrations**,
> 3 Edge Functions, **4 SQL test files**, docs/); live browser verification of the
> teacher dashboard (sign-in, calendar, day dialog, activity sheet, category
> correction picker, legend filters, comboboxes, mobile layout — 28 October 2026);
> Android emulator UI-hierarchy dumps and screenshots from the development window;
> local PostgreSQL 17.11 test execution of the full 33-migration chain and all four
> SQL suites (30 October 2026 — results and limitations in Appendix C). See
> Appendix B for the evidence register and remaining uncertainties.

---

## 0. How to read this document

- **Status labels (v2.2 system — used in §1.2 and throughout):**
  - **BUILT & VERIFIED** — implemented and supported by actual test or runtime
    evidence (SQL test, unit test, or live browser/emulator verification).
  - **IMPLEMENTED — VERIFICATION INCOMPLETE** — source exists, but the required
    behavior is not fully verified (e.g. only statically inspected, or verified
    locally but not on the hosted project).
  - **PARTIALLY IMPLEMENTED** — only some of the required behavior exists.
  - **PLANNED** — agreed future work that is not implemented.
  - **DEFERRED** — deliberately postponed.
  - **UNRESOLVED** — needs a decision.
  - **KNOWN LIMITATION** — existing behavior that must be documented honestly
    rather than silently "fixed".
  - Mapping from the pre-v2.2 labels: `[BUILT]` → BUILT & VERIFIED (or
    IMPLEMENTED — VERIFICATION INCOMPLETE where the evidence is weaker);
    `[BUILT—gap]` → PARTIALLY IMPLEMENTED or KNOWN LIMITATION; `[PLANNED]` and
    `[DEFERRED]` unchanged.
- File paths are workspace-relative (e.g. `app/src/main/java/.../BeaconScreen.kt`,
  `supabase/migrations/...`, `WebView/app.js`).
- "Manila time" means `Asia/Manila` (UTC+8, no DST) — the university's zone; the date
  semantics of the whole product are pinned to it (§6.4).
- UI text quoted in backticks is the exact user-facing string from
  `app/src/main/res/values/strings.xml` (Android) or the literal in `WebView/app.js`.

## 1. Product overview

**Student Codex** is a two-surface academic companion for Partido State University
(Philippines):

1. **Android student app** (Kotlin + Jetpack Compose, package
   `com.example.studentcodex`): one sign-in gate, four bottom tabs — **Home**,
   **Activity Beacon** (the deadline hub), **Community**, **Settings** — plus a pushed
   Profile page and a floating **Guidance Assistant** overlay that rides above every
   page. Online-first: every read and write goes to Supabase through repository
   interfaces; there is no local database.
2. **Teacher web dashboard** (`WebView/` — standalone vanilla HTML/JS/CSS, no build
   step): teacher sign-in/sign-up, a university-wide cohort filter bar, a month
   calendar of section activities with six color-coded categories, day/activity
   detail sheets, and one-tap category corrections that survive Google Classroom
   re-imports.
3. **Shared backend**: one Supabase project (Auth + PostgreSQL with RLS + Edge
   Functions + Storage) is the single source of truth for both surfaces.
4. **Public web presence** — BUILT & VERIFIED: an Edge Function `site` serves a home
   page and privacy policy on the project's Supabase domain (required for the Google
   OAuth consent screen branding URLs — see §8.3).

### 1.1 Users

- **Students** (primary): juggle deadlines from Google Classroom, face-to-face classes
  and personal tasks. They import courses, report class activities for their section,
  post in the campus community, and ask the deterministic guidance assistant questions.
- **Teachers** (secondary): view the aggregated deadline calendar across campuses,
  programs, years and sections; correct wrongly-classified imported activities.

### 1.2 Feature inventory (implementation status — v2.2 labels)

| Feature | Status | Where |
|---|---|---|
| Email/password sign-in, sign-up, sign-out | BUILT & VERIFIED | Android auth gate; §4.1–4.2 |
| Google Sign-In (Credential Manager → Supabase ID-token) | IMPLEMENTED — VERIFICATION INCOMPLETE (needs OAuth config, §8.3; verified during development, not re-exercised this pass) | §6.1 |
| Guest / demo exploration mode | BUILT & VERIFIED | §4.1, §6.1 |
| Profile completion for Google-first accounts | BUILT & VERIFIED | §4.3 |
| School registry (campus/program/year/section) sign-up dropdowns | BUILT & VERIFIED | §4.2 |
| Course enrollment by name (self-service course creation + fuzzy tier) | BUILT & VERIFIED | §6.2 |
| Google Classroom course import (picker at sign-up & Settings) | BUILT & VERIFIED | §6.3 |
| Google Classroom coursework/announcement sync | BUILT & VERIFIED (live browser-verified 2026-10-28; Edge Functions NOT re-exercised against real Google OAuth in the 2026-10-30 SQL run — Appendix C) | §6.3 |
| Classroom auto-sync on app open (opt-in toggle; NOT a background service) | BUILT & VERIFIED | §6.3 |
| Manual activity creation — instant section publish (no approval) | BUILT & VERIFIED | §6.4 |
| Student-reported section activities | BUILT & VERIFIED | §6.4 |
| Activity Beacon list + filters + date grouping + detail sheet | BUILT & VERIFIED | §4.5 |
| Soft delete of own activities | BUILT & VERIFIED | §6.4 |
| Import dedup (source-key upsert) + classification (title tokens) | BUILT & VERIFIED (gc_source_identity_test) | §7.3 |
| Teacher category corrections, locked across re-syncs | BUILT & VERIFIED | §5.6, §6.3 |
| Community feed + posts (1 image) + likes | BUILT & VERIFIED | §4.6 |
| Comments (flat in app; DB supports nesting to depth 5) | PARTIALLY IMPLEMENTED | §4.6, §10 |
| Anonymous posting (UI switch present; not persisted by repo) | PARTIALLY IMPLEMENTED | §4.6, §10 |
| Post reporting (5 reasons) + moderator triage model | BUILT & VERIFIED at DB level; no moderator UI | §6.5 |
| Guidance assistant — rule-based, deterministic, honest fallback | BUILT & VERIFIED | §4.9, §6.6 |
| Floating assistant: chat head / edge panel, draggable, persisted | BUILT & VERIFIED | §4.9 |
| Teacher dashboard: sign-in/sign-up, filters, calendar, sheets, corrections | BUILT & VERIFIED (live browser-verified 2026-10-28) | §5 |
| Teacher registration domain gate (`@parsu.edu.ph`, migration 0031) | BUILT & VERIFIED (SQL-tested T09/T10) | §5.3, §7.4 |
| RPC execute hardening (migration 0032, findings F1/F2/F3) | IMPLEMENTED — VERIFICATION INCOMPLETE — locally tested (Appendix C), NOT yet deployed to the hosted project | §7.4, Appendix C |
| Student-reported feed + coverage card on dashboard | BUILT & VERIFIED | §5.8 |
| Public home page + privacy policy (Edge Function `site`) | BUILT & VERIFIED | §8.7 |
| Offline cache / outbox (Room + WorkManager) | PLANNED | §10, docs/OFFLINE-SYNC.md |
| Push notifications / reminders | DEFERRED | §10 |
| Teacher workload/coverage analytics, proposed-deadline preview | PLANNED (DB view exists, no client consumes it) | §10 |
| Comment likes UI, nested reply UI, moderation queue UI | PLANNED | §10 |
| activity_reports matching workflow (report → teacher confirm) | BUILT at DB level; no longer the app's flow (§6.4) | §7 |

### 1.3 Product facts

- App name (Android label): `Student Codex`; application id `com.example.studentcodex`;
  versionName `1.0`, versionCode 1.
- Website title: `Student Codex — Teacher Dashboard`.
- University: Partido State University (7 campuses, 50 program-campus rows, year
  levels 1st–5th, section blocks A–F and 1–3 — the registry data is seeded by
  migrations, §7.6).
- All user-visible product text is English.
- Time zone: Asia/Manila everywhere (see §6.4 for the due-date semantics).
- Minimum Android 8.0 (minSdk 26); targets SDK 36; compiles against SDK 37.

## 2. System architecture (as built)

```text
Android app (Kotlin 2.2.10, Compose BOM 2026.02.01, manual DI)
│  UI: Compose screens + ViewModels (StateFlow<UiState>)  ── unidirectional
│  Data: repository interfaces in data/repo + data/auth + data/school
│        implementations in data/supabase (supabase-kt 3.6.0 behind them)
│        NO Room, NO WorkManager — online-first, one-shot loads
│        session persistence: supabase-kt default Settings (SharedPreferences)
│        prefs (assistant style, auto-sync): multiplatform-settings (russhwolf)
▼  https (publishable key + user JWT)
Supabase (single project)
│  Auth: Supabase Auth (email+password, Google ID-token)
│  Data: PostgreSQL + RLS on every table; views for feed reads
│  Storage: private bucket community-images
│  Edge Functions (Deno): classroom-import, classroom-sync, site
│        service-role inside functions; tokens transit-only
▼                                    ▼
Google Classroom API (read-only)    Teacher website (WebView/)
   OAuth via on-device consent        vanilla JS + vendored supabase-js
   (play-services-auth)               same Supabase project + RLS
```

### 2.1 Key architectural decisions (current truth)

1. **Supabase-first** (docs/ADR-001): one project; Auth UUID = `profiles.id`; RLS on
   every API-exposed table; Edge Functions are the only privileged path. The Android
   client is the community `supabase-kt` pinned via BOM **3.6.0** with
   `ktor-client-okhttp 3.4.3` (see §8.1 for the exact pinning rationale).
2. **Online-first Android app — no Room, no WorkManager.** The original plan's local
   cache/outbox was never built; every screen is a one-shot load with retry, plus a
   silent on-resume refresh on Beacon. The offline design survives only as a design
   document (docs/OFFLINE-SYNC.md — [PLANNED], §10).
3. **Teacher website is standalone HTML/JS/CSS** (`WebView/`), NOT the originally
   planned React+Vite/TS app. It loads three files: `styles.css`,
   `vendor/supabase.min.js` (vendored supabase-js v2), `vendor/lucide.min.js`
   (vendored Lucide). No build step; opens by double-click or any static server.
4. **Instant-publish community model.** Students create section activities that go
   live for their whole section immediately (`scope='section'`,
   `verification_status='student-reported'`); there is no approval queue anywhere.
   The legacy `activity_reports` pending→matched workflow still exists at the
   database level (tables, triggers, RLS — §7) but the Android app's "report" path
   publishes directly instead of filing a pending report.
5. **Google Classroom tokens are transit-only.** The app mints a short-lived access
   token per sync via the on-device Google Authorization API consent sheet
   (`play-services-auth`), sends it in the Edge Function request body, and never
   stores it. Revoking access in Google account settings takes effect on the next
   sync. No refresh tokens, no client secrets in the app.
6. **Guidance is a floating overlay, not a tab.** The assistant renders above every
   page as a draggable chat head or edge panel (user's choice, persisted); one shared
   transcript per signed-in session.
7. **Classification of imported activities is a database function**
   (`suggest_activity_category`) with teacher corrections locked by
   `category_locked`/`category_locked_by` (§7.3).
8. **Auth metadata is the enrollment transport.** Sign-up/completion/school-edit all
   write user metadata (`first_name`, `last_name`, `program_id`, `year_level`,
   `campus_id`, `year_section_id`, `course_codes`); `auth.users` triggers
   (`handle_new_user` / `handle_user_profile_sync`) validate, fill `profiles`, derive
   the username, and enroll the student in sections (§7.3–7.4).

9. **Teacher registration is domain-gated self-service with class groups**
(2026-10-31 state). The dashboard sign-up collects up to 12 class groups via a
multi-select chip picker; the role grant runs server-side through
`teacher_signup_multi(p_groups)` / `teacher_signup_global()`, both gated on the
caller's `auth.users.email` ending `@parsu.edu.ph` (migration 0031 —
case-insensitive suffix, read via SECURITY DEFINER so forged JWT claims are
irrelevant). Email confirmation is OFF and there is NO email-verification step
in the current flow (§8.7 documents the full 0028–0031 history). Teachers need
taught-section enrollments because category corrections are RLS-restricted to
taught sections (§5.6).
### 2.2 Repository / module map (Android)

```text
app/src/main/java/com/example/studentcodex/
├─ MainActivity.kt                 # edge-to-edge, StudentCodexTheme + StudentCodexApp
├─ StudentCodexApplication.kt      # owns AppContainer
├─ di/AppContainer.kt              # manual DI: one lazy SupabaseClient + all repos
├─ ui/
│  ├─ StudentCodexApp.kt           # auth gate → Scaffold(NavHost 4 tabs + profile) + GuidanceOverlay
│  ├─ auth/       AuthGateScreen.kt (gate + shared form parts), AuthViewModel.kt
│  ├─ home/       HomeScreen.kt, HomeViewModel.kt
│  ├─ beacon/     BeaconScreen.kt, BeaconViewModel.kt
│  ├─ community/  CommunityScreen.kt, CommunityViewModel.kt
│  ├─ settings/   SettingsScreen.kt, SettingsViewModel.kt
│  ├─ profile/    ProfileScreen.kt, ProfileViewModel.kt
│  ├─ guidance/   GuidanceViewModel.kt, GuidanceConversationParts.kt
│  │              overlay/ (GuidanceOverlay, ChatHeadPanel, FloatingChatHead,
│  │              EdgePanelHandle, GuidanceChatPanel, GuidanceOverlayController)
│  ├─ components/ StateViews.kt (skeletons/empty/error/AuthorMark/type icons),
│  │              ActivityDetailSheet.kt, ClassroomBadge.kt,
│  │              ClassroomImportSheet.kt (+ launcher), Formatters.kt
│  └─ theme/      Color.kt, Type.kt, Shape.kt, Spacing.kt, Theme.kt
├─ data/
│  ├─ auth/       AuthRepository.kt (SupabaseAuthRepository + SessionInfo + errors),
│  │              GoogleAuthManager.kt (CredentialManager), GoogleAccountResolution.kt,
│  │              ClassroomAuthorization.kt (PlayServicesClassroomAuthorizer)
│  ├─ repo/       Repositories.kt (all repository interfaces + drafts/results),
│  │              ClassroomAutoSync.kt (auto-syncer + preference store)
│  ├─ school/     SchoolDirectoryRepository.kt (registry + course-code rules)
│  ├─ supabase/   SupabaseClientFactory, PostgrestJson, AppContextHolder,
│  │              Supabase{Activity,Community,Profile,ClassroomConnection,
│  │              ClassroomImport,ClassroomSync}Repository
│  └─ fake/       FakeData.kt, FakeRepositories.kt  (unit-test fakes ONLY —
│                 not wired in AppContainer; guest mode is a session flag, §6.1)
├─ domain/
│  ├─ model/      Activity.kt, Community.kt, Guidance.kt
│  ├─ guidance/   GuidanceEngine.kt (DemoGuidanceEngine rules)
│  └─ SchoolTime.kt               # Asia/Manila zone + toDueInstant() = 23:59
└─ res/values/strings.xml         # every user-facing string (§4 quotes them)
```

Conventions enforced throughout: no API/database logic inside Composables; ViewModels
expose one `StateFlow<UiState>`; all user-facing text in `strings.xml`; every data
screen renders loading / empty / error / content; the single Supabase client is built
lazily in `AppContainer` and consumed only by repositories (ADR-001/ADR-002).

## 3. Android design system (exact tokens)

Visual identity: **"library green on warm paper."** A scholarly study companion —
warm paper canvas (never pure neutral), deep library green as the single accent,
brass tertiary used only for demo/awareness notices. Every neutral is tinted a few
percent toward the dominant hue so surfaces feel like one material. Deliberately NOT
used: purple/indigo, cyan/teal accents, pure grays, neon-on-slate dark mode.
All values below are verbatim from `ui/theme/Color.kt`, `Type.kt`, `Shape.kt`,
`Spacing.kt`, `Theme.kt`.

### 3.1 Color tokens — light scheme (default)

| Token | Hex | Role |
|---|---|---|
| Primary | `#2F5B41` | deep library green — actions, due emphasis |
| OnPrimary | `#FFFFFF` | |
| PrimaryContainer | `#C4EFD2` | pale sage fills |
| OnPrimaryContainer | `#0B2114` | |
| Secondary | `#48554E` | ink green — supporting content |
| OnSecondary | `#FFFFFF` | |
| SecondaryContainer | `#D3DED5` | |
| OnSecondaryContainer | `#12231A` | |
| Tertiary | `#715C24` | brass — demo/awareness notices only |
| OnTertiary | `#FFFFFF` | |
| TertiaryContainer | `#F5E3A6` | |
| OnTertiaryContainer | `#231A00` | |
| Error | `#B3362E` | muted warm red, harmonized with paper |
| OnError | `#FFFFFF` | |
| ErrorContainer | `#F9D9D4` | |
| OnErrorContainer | `#410903` | |
| Background / Surface | `#FAF9F4` | warm paper canvas |
| OnBackground / OnSurface | `#1A1F1B` | green-tinted ink |
| SurfaceVariant | `#E1E7DE` | paper darkened toward green |
| OnSurfaceVariant | `#404B44` | metadata ink (calmer than body ink) |
| Outline | `#707E75` | |
| OutlineVariant | `#C4CCC2` | row dividers |
| SurfaceContainerLowest | `#FDFCF8` | |
| SurfaceContainerLow | `#F1EFE5` | post cards, chat bubbles |
| SurfaceContainer | `#EAE8DC` | bottom navigation, menus |
| SurfaceContainerHigh | `#E2E0D3` | |
| SurfaceContainerHighest | `#DCDACB` | filter chips |

The surfaceContainer ramp gives exactly one level of elevation above the canvas:
cards and chat bubbles sit on `Low` (a sheet of paper on the desk); chrome (bottom
nav, menus) sits on `Container`.

### 3.2 Color tokens — dark scheme (green-tinted charcoal)

| Token | Hex | | Token | Hex |
|---|---|---|---|---|
| Primary | `#9BD5AE` | | Error | `#EFB8B2` |
| OnPrimary | `#0A1F12` | | OnError | `#601410` |
| PrimaryContainer | `#2C5238` | | ErrorContainer | `#8C1D18` |
| OnPrimaryContainer | `#B8EFC8` | | OnErrorContainer | `#FFDAD5` |
| Secondary | `#B6C4B9` | | Background/Surface | `#121713` |
| OnSecondary | `#222E26` | | OnBackground/OnSurface | `#E1E6DF` |
| SecondaryContainer | `#3A4640` | | SurfaceVariant | `#414C44` |
| OnSecondaryContainer | `#C9D7CD` | | OnSurfaceVariant | `#C1C9C0` |
| Tertiary | `#D9C27A` | | Outline | `#8B998F` |
| OnTertiary | `#38300A` | | OutlineVariant | `#414C44` |
| TertiaryContainer | `#524619` | | SurfaceContainerLowest | `#0D110E` |
| OnTertiaryContainer | `#F1E1A9` | | SurfaceContainerLow | `#1A211C` |
| | | | SurfaceContainer | `#212A24` |
| | | | SurfaceContainerHigh | `#2A342D` |
| | | | SurfaceContainerHighest | `#333E36` |

(All values are complete pairs; `Theme.kt` maps every token above into
`lightColorScheme(...)` / `darkColorScheme(...)` including all five
`surfaceContainer*` slots.)

### 3.3 Theme behavior

- `StudentCodexTheme(darkTheme = isSystemInDarkTheme(), dynamicColor = false)` —
  dark mode follows the system; **dynamic color (Material You) is OFF by default**
  so the brand palette reads consistently in demos and screenshots.
- One hardcoded brand color outside the scheme: the Google Classroom provenance
  badge uses **`#0F9D58`** (Google brand green) with white content (§4.10).

### 3.4 Typography

Typeface: **DM Sans** (SIL OFL), bundled as ONE variable font
`res/font/dmsans.ttf` (~240 KB) and instanced per weight via
`FontVariation.Settings(FontVariation.weight(n))` for 400/500/600/700
(`CodexFontFamily`). Hierarchy comes from size + weight — never ALL CAPS or
letter-spaced labels. Nothing renders below 12sp; 14sp is the working size for
reading and row labels (dense, scan-first tool).

| Style | Weight | Size/Line-height | Letter-spacing | Usage |
|---|---|---|---|---|
| headlineSmall | SemiBold | 22/28 | — | screen titles (one per screen, sentence case) |
| headlineMedium | SemiBold | 28/34 | — | reserved (auth gate app title) |
| headlineLarge | SemiBold | 32/38 | — | reserved, unused |
| titleLarge | SemiBold | 20/26 | — | profile display name; activity detail title |
| titleMedium | SemiBold | 16/22 | 0.1sp | section headers, card/sheet titles |
| titleSmall | SemiBold | 14/20 | 0.1sp | row primary labels (workhorse) |
| bodyLarge | Normal | 16/24 | — | composer placeholder |
| bodyMedium | Normal | 14/20 | — | reading text |
| bodySmall | Normal | 12/16 | — | captions, secondary metadata |
| labelLarge | Medium | 13/16 | 0.1sp | buttons, interactive chips |
| labelMedium | Medium | 12/16 | 0.1sp | metadata (due times, counts, sources) |
| labelSmall | Medium | 12/16 | 0.1sp | smallest chrome (12sp floor) |

### 3.5 Shapes, spacing, elevation

`CodexShapes`: extraSmall = **8dp** (micro badges), small = **12dp**, medium =
**12dp** (primary — chips, cards, bubbles, inputs), large = **16dp** (sheets and
overlays), extraLarge = **16dp**. Pills (50% rounded) are reserved for tags,
provenance badges, the composer bar, and Material components' internal chips. No
other radii exist.

`Spacing` object: xs=**4**, sm=**8**, md=**12**, lg=**16**, xl=**24**, xxl=**32**
(dp). Screen content padding is typically horizontal `lg` (16) with top `md` (12);
forms use horizontal `xl` (24).

Elevation is expressed through the surfaceContainer ramp, not shadows, except:
guidance panel card (tonal 3dp + shadow 12dp), floating chat head (shadow 8dp),
edge handle (shadow 6dp), unread badge (shadow 4dp).

### 3.6 Icons and assets

- Navigation icons (Material rounded): Home=`Icons.Rounded.Home`,
  Beacon=`Icons.Rounded.TrackChanges`, Community=`Icons.Rounded.Forum`,
  Settings=`Icons.Rounded.Settings`.
- Activity type icons (`StateViews.ActivityTypeIcon`, tint onSurfaceVariant, 20dp):
  Assignment→`Assignment`, Quiz→`Quiz`, Exam→`MenuBook`, Project→`Assignment`,
  Announcement→`Campaign`, Activity(other)→`MenuBook`.
- Guidance: head = `Lightbulb`; edge handle chevron points toward screen middle.
- Google logo: `res/drawable/ic_google_logo.xml` (vector, 20dp in the button).
- Launcher: adaptive icon `ic_launcher` / `ic_launcher_round` (mipmap webp set +
  anydpi XML; foreground vector + `ic_launcher_background.xml` green).
- Emulator-captured geometry reference (1080×2400 portrait): app content region
  starts below the status-bar inset; bottom nav bar is 210px tall with 4 equal
  ~254px slots; selected tab is `clickable=false, selected=true`.

### 3.7 Skeleton animation

All list skeletons pulse: `boneAlpha()` infinite transition 0.30 ↔ 0.10 alpha,
`tween(650ms)`, `RepeatMode.Reverse`; bone color `onSurface.copy(alpha)`; the whole
skeleton carries `contentDescription = "Loading"` via `clearAndSetSemantics`.
## 4. Android application specification

### 4.0 App shell, navigation, and lifecycle

**Startup:** `MainActivity` (single activity, `enableEdgeToEdge()`) →
`StudentCodexTheme { StudentCodexApp(container) }`. The container is
`StudentCodexApplication`'s manual-DI `AppContainer` (§2.2).

**Auth gate states** (`AuthViewModel.uiState`, collected with lifecycle awareness):

| State | Meaning |
|---|---|
| `CheckingSession` | restoring the persisted Supabase session — full-screen centered `CircularProgressIndicator` on background |
| `SignedOut(mode, ...form fields...)` | the gate (§4.1); `AuthMode.SIGN_IN` / `SIGN_UP` |
| `CompletingProfile(email, hasPasswordCredential, ...)` | Google-first account without a name yet (§4.3) |
| `SignedIn(session: SessionInfo)` | main app; `SessionInfo(userId, email, isGuest=false, displayName, profileCompleted, hasEmailCredential)` |

Session restore: `currentSession()` awaits `auth.sessionStatus` (2s timeout) →
null ⇒ `SignedOut`; `profileCompleted == false` ⇒ `CompletingProfile`; else
`SignedIn`. Guest sessions are memory-only (`userId=null, isGuest=true`) and skip
remote sign-out.

**Main scaffold** (`StudentCodexMain`): `Scaffold` with a Material 3 `NavigationBar`
(4 items — Home/Beacon/Community/Settings, icon + label each) and a `NavHost`
(`startDestination = "home"`, padded by full `innerPadding` — edge-to-edge, headers
sit below the status bar). Tab navigation is single-top with state save/restore:
`popUpTo(startDestination){saveState=true} launchSingleTop restoreState=true`.
`PROFILE_ROUTE = "profile"` is a pushed route from Settings (Back returns to
Settings). `GuidanceOverlay(controller, viewModel)` is mounted AFTER the Scaffold
inside a root `Box` — it rides above every page including Settings.

**One shared guidance conversation** per signed-in session: `GuidanceViewModel` is
created at `StudentCodexMain` level; `DisposableEffect(Unit){ onDispose { clearConversation() } }`
wipes the transcript when the session goes away (questions belong to the account).

**Classroom auto-sync hook:** a `LifecycleEventObserver` on `ON_START` runs
`container.classroomAutoSyncer.runIfDue(activity)` (§6.3) whenever the student has
the toggle on. The import launcher for the auth gate (sign-up/completion forms) is
also wired here (`rememberClassroomImportLauncher`, §4.10).

### 4.1 Auth gate — sign-in / sign-up (`AuthGateScreen`)

Purpose: the only entry to the app; real Supabase email/password auth, Google
Sign-In, and an explicit guest bypass.

Layout (one vertically scrollable `Column`, `systemBarsPadding + imePadding`,
horizontal padding `xl`, centered horizontally):

1. `Text(app_name)` — headlineMedium, centered ("Student Codex").
2. `Text(auth_app_tagline)` — bodyMedium, onSurfaceVariant:
   `Deadlines, workload and campus help in one place.`
3. Spacer xxl.
4. Mode title — titleLarge, fillMaxWidth: `Welcome back` (sign-in) /
   `Create your account` (sign-up).
5. Sign-up only — First name / Last name `OutlinedTextField` row (weight 1f each,
   spacedBy md, ImeAction.Next, `shapes.medium`).
6. Email field (`KeyboardType.Email`).
7. Password field with visibility `IconButton` (Visibility/VisibilityOff icons,
   contentDescriptions `Show password` / `Hide password`); ImeAction.Go submits on
   sign-in mode.
8. Sign-up only — Confirm password field (ImeAction.Done).
9. Sign-up only — **SchoolDetailsFields** (§4.2) and **CourseCodesField** (§4.2,
   with the Classroom import button + sheet).
10. Error line (bodySmall, error color) via `errorText(state.error)` mapping (§4.1.1).
11. Sign-up success awaiting email confirmation — `ConfirmationNotice` card
    (surfaceContainerLow, shapes.medium, padding md): title `Check your email`,
    body `Account created. Click the confirmation link we sent you, then sign in here.`
    + `Got it` TextButton.
12. Submit `Button` — fillMaxWidth, height **48dp**, label `Sign in` /
    `Create account`; while loading shows a 20dp/2dp `CircularProgressIndicator`
    (onPrimary).
13. Google `OutlinedButton` — fillMaxWidth, height 48dp: `ic_google_logo` (20dp) +
    sm spacer + `Continue with Google`. No separate Google sign-up (Supabase creates
    the account on first sign-in, then the name is collected once).
14. Mode-switch `TextButton`: `New here? Create an account` /
    `Already have an account? Sign in`.
15. Divider row: `HorizontalDivider` — `or` (labelMedium, onSurfaceVariant) — divider.
16. Guest `OutlinedButton` (fillMaxWidth, 48dp): `Explore without an account`,
    followed by `Demo mode — sample data, nothing is synced or saved online.`
    (labelSmall, onSurfaceVariant).
17. `GoogleSetupDialog` (AlertDialog) when the Google button is tapped while
    `GOOGLE_SERVER_CLIENT_ID` is unconfigured: title `Google sign-in is not set up yet`
    + setup instructions + `Got it`.

Validation order (sign-up): EMAIL → NAME → SCHOOL → PASSWORD_LENGTH (min 6) →
PASSWORD_MISMATCH → COURSES. Email validation = exactly one `@`, non-empty local
and domain parts, no spaces.

**Error taxonomy** (`AuthError`): `Validation{EMAIL,NAME,SCHOOL,COURSES,
PASSWORD_LENGTH,PASSWORD_MISMATCH}`, `EmailTaken`, `Google{NO_ACCOUNT, REJECTED,
GENERIC, detail}` (each with its own actionable message string), `Remote(message)`.

### 4.2 Sign-up form parts (shared by gate, completion, and Settings sheet)

**SchoolDetailsFields** — four registry dropdowns; **Campus comes FIRST**: picking
one narrows the Program list to that campus's offerings; before that all campuses'
programs are listed with duplicates disambiguated as `"{program} — {campus name}"`
(em dash). Year level and Section sit in one row (weight 1f each). All values come
from the database registry (§7.6); while the directory loads the fields are replaced
by a spinner + `Loading programs and campuses…`; on failure an inline error +
`Try again` TextButton. Each dropdown is an `ExposedDropdownMenuBox` whose field
doubles as a live search box while open (placeholder `Search`), rows carry a check
icon on the selected option, an empty filter shows a disabled `No match` row, and
collapsing the menu clears the query.

**CourseCodesField** — the student's subjects:

- Selected courses render as removable `InputChip`s (Close trailing icon 16dp,
  contentDescription `Remove {code}`), FlowRow spacedBy xs.
- **`Import from Google Classroom`** `OutlinedButton` (CloudDownload icon 18dp) +
  hint `Tap to choose which Google account to import from.` — opens the account
  chooser then the `ClassroomImportSheet` (§4.10). Import runs at the gate level
  and lands the picked courses after the account is created (§6.3).
- **CoursePickerDropdown** — an `ExposedDropdownMenuBox` field labeled
  `Course name`, placeholder `Search or type a course name`; while open it live-
  filters the catalog (max **30** rows rendered) by code or title (case-insensitive
  contains); already-added courses show a check; a typed unknown-but-valid name is
  offered as `Add {name} as a new course` (leading Add icon) — the server creates
  the course at save time (§6.2). Junk input shows the inline error
  `That doesn't look like a course name — type the whole name of the course as it
  appears in Google Classroom, like MEETING or Application Development 2.`
  The hint above the field tells students to type the FULL course name exactly as
  in Google Classroom.
- Course-code shape rule (`looksLikeCourseCode`): 1–160 chars, first char
  letter/digit, remaining chars letters/digits or one of ` .,:;()/&+-` — the same
  shape the server enforces (migration 0021).

### 4.3 Profile completion (`ProfileCompletionScreen`)

For a Google-first sign-in whose account has no name yet. Same visual skeleton as
the gate: app title (headlineMedium) → `Finish setting up your account`
(titleLarge) → `Signed in as {email} via Google` (bodySmall, onSurfaceVariant) →
First/Last name row → SchoolDetailsFields → CourseCodesField (with Classroom
import) → **password fields only when `!hasPasswordCredential`** (Password +
Confirm, with the note `This password lets you sign in with your email too — you
keep the Google button either way.`) → error line → `Save and continue` Button
(48dp) → `Sign out instead` TextButton.

On submit (`completeGoogleProfile`) the names/school/codes travel as user metadata
(the `on_auth_user_profile_sync` trigger fills the profile, derives the username and
enrolls sections — §7.3) and the password is set if provided.
### 4.4 Home

Start destination. One aggregated overview; data loads once (no observing flow).

`HomeUiState`: `Loading` → `Content(nextActivities, recentPosts, dueSoonCount)` /
`Error(message)`; `retry()`. Content pipeline: `getActivities()` filtered to
`dueAt` in the future, sorted by dueAt, top **3**; `getRecentPosts()` top **2**;
`dueSoonCount` = activities due within 7 days. Overdue items are excluded from the
list and the count.

Layout — `LazyColumn` (contentPadding start/end/top lg, bottom xl):
1. Header: greeting (`Good morning` <12h / `Good afternoon` <18h / `Good evening`)
   in headlineSmall; workload subtitle in bodyMedium onSurfaceVariant —
   `No deadlines in the next 7 days.` / `One deadline in the next 7 days.` /
   `{n} deadlines in the next 7 days.`
2. `SectionHeader("Upcoming deadlines")` (titleMedium).
3. Empty → `EmptyState("Nothing due soon", "When activities have deadlines they
   will show up here.")`; else **UpcomingActivityRow**s (key = activity id) + a
   final `All activities` TextButton with ChevronRight (navigates to the Beacon tab).
4. `SectionHeader("From the community")`.
5. Empty → `EmptyState("No posts yet", ...)`; else **PostPreviewRow**s + (implicitly
   through row tap) navigation to Community.
6. `Ask a study question` TextButton + ChevronRight — does NOT push a page; it calls
   `overlayController.expand()` (opens the same shared guidance panel as the floating
   assistant, §4.9).
7. Tapping any upcoming row opens the shared **ActivityDetailSheet** (§4.10) in a
   local `detailActivity` state.

**UpcomingActivityRow anatomy** (Row, padding vertical md, CenterVertically,
clickable with `onClickLabel = "View details of {title}"`): `ActivityTypeIcon`
(20dp) → md spacer → Column(weight 1f): title (titleSmall, maxLines 2, Ellipsis);
meta row — ClassroomBadge (§4.10) when imported, then meta line
(`course · {n} min estimated`, bodySmall onSurfaceVariant, maxLines 1) → md spacer
→ **DueBlock**: Column aligned end, minWidth 64dp — due label (labelMedium;
color = `error` when overdue else `primary`) over time (bodySmall,
onSurfaceVariant); `No deadline` (labelSmall) when undated. Rows separated by
`HorizontalDivider(outlineVariant)` except the last.

**PostPreviewRow anatomy**: author row (AuthorMark 20dp + name or `Anonymous`,
labelMedium) → post text (bodyMedium, maxLines 2) → engagement line
(`{n} comments · {n} likes`, bodySmall onSurfaceVariant).

Due label formats (`Formatters.dueLabel`, Manila zone, locale from
`LocalConfiguration.current.locales[0]`): `Overdue` · `Due within an hour` ·
`Due in {n} hour(s)` · `Tomorrow` · `Due in {n} day(s)` (≤7) · else `EEE, MMM d, yyyy`.

### 4.5 Activity Beacon

The deadline hub: full filtered list, date-grouped, with manual activity CRUD.

`BeaconUiState`: `Loading` → `Content(filtered, selectedFilter, isEmptyOverall)` /
`Error`. `BeaconFilter` enum in chip order: **All, Classroom, Assignments, Exams,
Quizzes, Projects, Activity** (predicates: true / source==GOOGLE_CLASSROOM /
type==ASSIGNMENT / EXAM / QUIZ / PROJECT / OTHER). Sort:
`compareByDescending<Activity>{dueAt}.thenBy{title}` — newest due first, undated last.
Grouping key: `dueAt.atZone(Asia/Manila).toLocalDate()` (null group last, header
`No deadline`).

**Screen layout** (Column fillMaxSize):
1. Header: `Activity Beacon` (headlineSmall) + `Your deadlines, synced from your
   courses` (labelMedium, onSurfaceVariant).
2. Guests: `Sign in to record activities.` (bodySmall). Signed-in: full-width
   `Add school works` Button (Add icon 18dp) that opens the editor sheet.
3. State area: Loading → `ActivityListSkeleton` (7 rows); Error → `ErrorState`;
   Content → ① filter `LazyRow` (contentPadding horizontal lg, spacedBy sm) of
   `FilterChip`s (labels only, no icons); ② overall empty → `EmptyState("No
   activities yet", "Record a manual activity, or ask your teacher when Google
   Classroom sync is enabled — your deadlines will appear here.", icon = Add tinted
   primary); ③ filter-empty → `EmptyState("Nothing in this filter", "No activities
   match the selected filter right now.")`; ④ `LazyColumn` of date groups —
   group header (dateHeader, titleSmall, **primary**, padding top md bottom xs:
   `Today` / `Tomorrow` / `EEEE, MMM d, yyyy` / `No deadline`) then rows.

**BeaconActivityRow** (same skeleton as Home's row) with additions: provenance chip
under the title — `ClassroomBadge` (imported) or `ManualBadge` (`Added manually`,
secondaryContainer pill with Edit icon); meta line =
`course · {verification label} · [Personal] · [{n} min estimated]` joined by `" · "`
(verification labels: `imported`, `teacher-confirmed`, `student-reported`,
`needs review`); trailing edit/delete `IconButton`s (36dp, Outlined.Edit /
Outlined.Delete icons 18dp, onSurfaceVariant) ONLY when
`canEdit && source != GOOGLE_CLASSROOM && isPersonal`. Row tap → detail sheet.

**Manual activity editor** — `ModalBottomSheet` (`skipPartiallyExpanded=true`),
Column (verticalScroll, horizontal padding lg, imePadding):
1. Sheet title: `New activity` / `Edit activity` (titleMedium).
2. `Title` OutlinedTextField (singleLine).
3. `Notes (optional)` OutlinedTextField (minLines 2, maxLines 4).
4. Type picker: `Type` label (labelMedium onSurfaceVariant) + LazyRow of FilterChips
   in enum order — `Assignment, Quiz, Exam, Project, Announcement, Activity`.
5. `Due date` readOnly OutlinedTextField (value = `yyyy-MM-dd` or blank) with a
   trailing calendar IconButton → **DatePickerDialog** (`rememberDatePickerState`
   seeded from the current date; OK/Cancel TextButtons; selection converts through
   Manila zone to a `LocalDate.toString()`).
6. **Audience section (NEW activities only)**: label `Which course?`; while sections
   load — spinner + `Loading your courses…`; if the student has none —
   `No courses yet — add your course names under Settings → School details, then
   try again.`; else **CourseSectionDropdown** (same searchable exposed-dropdown
   mechanic as sign-up; rows show `courseCode · sectionName` + course title subtitle,
   check icon on the selection) and the sharing hint:
   `Shared with your course section — your teacher and classmates see it on the
   calendar instantly. No approval needed.`
   Sections are re-fetched (`getMySections()`) on every open; a single section is
   auto-selected. When EDITING an existing class (non-personal) activity, no picker
   appears — a fixed note `Course activity — shared with your section.` /
   `Course activity for {course} — shared with your section.`
7. Error line (bodySmall, error): `Give the activity a title.` /
   `Pick which course this belongs to.`
8. Save Button (fillMaxWidth): `Save activity` / `Save changes`; 18dp/2dp spinner
   while saving. Save semantics in §6.4 — every new activity is a CLASS activity
   published straight to the section (student ⇒ `student-reported`, teacher ⇒
   `teacher-confirmed`); the due date is stored as **23:59 Manila** end-of-day
   (`LocalDate.toDueInstant()`); success closes the sheet and silently reloads
   keeping the active filter.

**Delete flow**: delete IconButton → `AlertDialog` — `Delete activity?` /
   `" {title}" will be removed from your list. This cannot be undone.` /
   `Delete` / `Keep`. Confirm performs a soft delete (`deleted_at = now()`, §6.4).

**On-resume refresh**: `DisposableEffect(lifecycleOwner)` observes `ON_RESUME` →
`refresh()` — a SILENT reload (no skeleton, keeps filter; failures swallowed) so
auto-synced Classroom rows appear when returning to the tab.

### 4.6 Community

Feed + composer + comments + reports. `CommunityViewModel` exposes three sheet
flows besides the feed: `composerSheet`, `commentsSheet`, `reportSheet`.

Feed `CommunityUiState`: `Loading` → `Content(posts)` / `Error`; load =
`getRecentPosts()` (view read, newest first, limit 50 — §7.8).

**Screen layout** (Column):
1. Header: `Community` (headlineSmall) + subtitle (labelMedium, onSurfaceVariant) —
   signed-in: `Posts from students on your campus`; guest: `Sign in to post,
   comment, and like.`; md spacer.
2. **ComposerBar** — a pill `Surface(RoundedCornerShape(percent=50), color=surface,
   border=BorderStroke(1dp, outlineVariant))`, Row padding sm, spacedBy md:
   AuthorMark (36dp) + `What's on your mind?` (bodyLarge, onSurfaceVariant, weight
   1f, maxLines 1) + gallery Icon (`Icons.Rounded.Image`, 26dp, tint **primary**,
   contentDescription `Add a photo to your post`). Tap opens the composer sheet.
3. State: Loading → `PostListSkeleton` (4 cards); Error → ErrorState; empty →
   `EmptyState("No posts yet", "Be the first to share something study-related with
   your campus.")`; else `LazyColumn` (contentPadding lg/xl, spacedBy md) of
   **PostCards**, auto-scrolled to the top when a new post is prepended
   (`LaunchedEffect(posts.firstOrNull()?.id)`).

**PostCard** — `Surface(shapes.medium, surfaceContainerLow)`, Column padding md:
- Header row: AuthorMark (32dp; VisibilityOff icon for anonymous) + Column
  (name or `Anonymous` titleSmall maxLines 1; timestamp labelSmall onSurfaceVariant)
  + (signed-in) report `IconButton` (32dp, Flag icon 16dp) + like row
  (semantics contentDescription `Like this post. {n} likes so far.` /
  `Remove your like. {n} likes so far.`): Favorite/FavoriteBorder IconButton
  (tint primary when liked) + count (labelMedium). Like toggle is optimistic and
  disabled for guests.
- Optional text (bodyMedium) — skipped when blank (photo-only post).
- Optional **PostImage** (§ below).
- Comment doorway row: clickable, clip(shapes.small), padding horizontal xs /
  vertical 4dp — ChatBubbleOutline icon 16dp + `{n} comments` (labelMedium,
  onSurfaceVariant). Opens the comments sheet.

**Timestamps** (`postTimestamp`, Manila zone): `Just now` (<1 min) ·
`{n} minute(s) ago` (<60) · else `MMM d, yyyy · HH:mm`.

**PostImage**: async decode via an in-app `PostImageLoader` — LRU cache (12
entries) + Mutex on Dispatchers.IO; `content://` uris resolve through the
ContentResolver, bare storage paths download through
`downloadPostImage(path)` (authenticated bucket read, §7.6). Bitmaps are
downsampled (sampleSize doubling while a dimension ÷2 ≥ 800). Render: Image
(ContentScale.Crop, fillMaxWidth, heightIn max **260dp**, clip shapes.medium),
contentDescription `Photo attached to this post`; while loading a 160dp
surfaceContainerHigh placeholder with a 22dp spinner; a failed decode renders
nothing (text-only card).

**ComposerSheet** — `ModalBottomSheet(skipPartiallyExpanded=true)` with a
`PickVisualMedia` (ImageOnly) photo launcher (system Photo Picker — no storage
permission). Column (horizontal padding lg, imePadding):
1. `Create post` (titleMedium).
2. Identity row: AuthorMark (32dp) + name / `Anonymous` + (when anonymous) note
   `Your name is hidden from other students` (labelSmall).
3. `OutlinedTextField` (placeholder `Say something study-related…`, minLines 3,
   maxLines 6).
4. **Post anonymously** row: Checkbox + label (bodyMedium).
   [BUILT—gap] The checkbox drives the sheet's identity preview only — the
   repository call does not carry the flag, and posts are always inserted with
   `is_anonymous=false` (§6.5, §10).
5. Attached photo preview (PostImage with a TopEnd FilledIconButton remove
   control, contentDescription `Remove the selected photo`).
6. Actions row: gallery IconButton (enabled unless posting/guest) + `Post` Button
   (weight 1f; enabled when not posting, not guest, and text or photo present).
7. Footnote (labelSmall onSurfaceVariant): guest — `Browsing as a guest — sign in
   to post, like, comment, or report.`; signed-in — `Posts are shared with
   signed-in students on your campus.`
Guests open the composer to find a preset explainer error
(`Sign in to post — community posts need an account.`) and disabled actions;
failed submits keep draft + photo; a successful post is prepended to the feed.

**CommentsSheet** — ModalBottomSheet; header `Comments` (titleMedium); states:
Loading (200dp centered spinner), Error (ErrorState with retry), Content — the
post's text preview (bodySmall, maxLines 3), then either
`EmptyState("No comments yet", "Be the first to reply.")` or a `LazyColumn`
(heightIn max **340dp**, spacedBy md) of flat **CommentRows** (Row Top-aligned:
AuthorMark 24dp + Column{name/titleSmall + timestamp/labelSmall; text/bodyMedium}),
then the reply row (Bottom-aligned): `OutlinedTextField` (placeholder
`Add a comment…`, maxLines 4, weight 1f) + send IconButton (AutoMirrored.Send,
tint primary when the draft is non-blank; 20dp/2dp spinner while sending;
contentDescription `Send comment`). [BUILT—gap] replies are flat — the app never
writes `parent_comment_id`, though the database supports nesting to depth 5 (§7).
Send failures keep the draft and show a sendError line; comment count is bumped in
both the sheet and the feed card.

**ReportPostSheet** — `AlertDialog` `Report post`: reason chips in two rows
(Spam, Harassment / Off topic, Inappropriate, Other — `FilterChip`s bound to the
DB wire values `spam|harassment|off-topic|inappropriate|other`), optional details
field (`Anything else we should know? (optional)`, minLines 2, maxLines 4, details
capped at 1000 chars), submit TextButton (`Submit report`, 16dp spinner while
sending), success line `Report submitted. Thank you for keeping the community
safe.` Guests (no repository) get `Sign in to report posts.`

### 4.7 Settings

One scrollable Column (verticalScroll + imePadding) of action cards
(`Surface(shapes.medium, surfaceContainerLow)`; Row padding md with leading Icon
20dp onSurfaceVariant, title titleSmall + note bodySmall onSurfaceVariant,
trailing ChevronRight when actionable). Floating assistant stays visible over this
page so switching its style previews live.

Order of sections:
1. Header: `Settings` (headlineSmall) + `Your profile, account, school details,
   and the floating assistant.` (bodyMedium).
2. **Profile** card (Person icon) — `View your profile and connected services.` →
   pushes the Profile route.
3. **Floating assistant** preference card: title `Floating assistant`, hint
   `Shows on the other pages while you browse. Pick the style you like.`,
   then a `SingleChoiceSegmentedButtonRow` — `Chat head` (ChatBubble icon) /
   `Edge panel` (ViewSidebar icon). Selection persists immediately through the
   overlay controller (§4.9) and closes any open panel.
4. Signed-in only — account cards:
   a. **Change password** (Password icon) → `ChangePasswordSheet` (ModalBottomSheet):
      hint `Choose a new password for signing in with your email.`, New/Confirm
      password fields (PasswordVisualTransformation), inline `SaveFeedback` line
      (`Password needs at least 6 characters.` / `Passwords do not match.` /
      remote error / `Password updated.`), `Change password` Button.
   b. **Change school details** (School icon) → `SchoolDetailsSheet`
      (ModalBottomSheet): header `School details` + hint, then the SAME
      SchoolDetailsFields + CourseCodesField (including the Classroom import
      button) as sign-up, a SaveFeedback line, and `Save school details` Button →
      `updateSchoolDetails` via user metadata (§6.2).
   c. **Google Classroom connection card** (Link/LinkOff icon, title
      `Google Classroom`): status note per `ClassroomConnectionState` —
      `Connected{ (email)} · last sync MMM d, HH:mm[ · last sync failed]}` /
      `Sync is not enabled yet. Activities arrive here as soon as your teacher's
      Classroom integration is connected.` / `Access was revoked on the Google
      side — reconnect when sync is enabled.` / `Authorization expired — reconnect
      when sync is enabled.` / `Disconnected. Your activities stay; new syncing
      is off.` Buttons: `Connect & Sync` (OutlinedButton with Link icon) or, when
      connected, `Sync now` + a disconnect IconButton (LinkOff). While syncing:
      `Syncing…` note; after sync — result line (primary): `Imported {n} new ·
      refreshed {n} activities from {n} classes.` or the partial variant with
      unmatched class names; errors in error color (`Sync failed: {message}` /
      `No Google authorization given — nothing was synced.` / `Google refused the
      request (code {n}) — the app is not registered in the Google Cloud project.
      See the Classroom setup notes.`). The connect flow pins the Google account:
      a connected `googleEmail` is silently re-used; otherwise the system account
      chooser appears first (§6.3).
   d. **Auto-sync card** (visible when connected): Autorenew icon, title
      `Auto-sync school works`, hint `Quietly imports new Google Classroom work
      every time you open the app.`, trailing `Switch`. Turning it ON persists the
      preference and fires one immediate silent sync.
5. **Notifications** card (disabled-looking, no chevron): `Notifications` +
   `Deferred - not part of the first release.`
6. **Sign out / Exit demo mode** card (Logout icon, no chevron): guest variant
   uses `Exit demo mode` + `Returns to the sign-in screen. Demo data is not
   saved.`; signed-in uses `Sign out` + `Returns to the sign-in screen.`

Guests see a `surfaceContainerLow` note instead of the account cards:
`Sign in to manage account and school settings. The floating assistant works
either way.`


### 4.8 Profile

Pushed route (Back IconButton top-left, contentDescription `Go back to settings`;
title `Profile` headlineSmall). Content Column (scroll, horizontal padding lg):
identity Row — AuthorMark **56dp** + Column: display name (titleLarge, maxLines 1);
`{university} · {program} · {yearLevel}` (bodyMedium, onSurfaceVariant, maxLines 2);
guests: `Demo mode — not signed in` (labelSmall, **tertiary**); signed-in:
account name (labelMedium) and `Signed in as {email}` (labelSmall). **No footer
note renders** — the build-era string `profile_version_note` ("…lists and
community content are demo data, not synced yet.", `strings.xml:333`) still exists
in resources but is referenced by NO Kotlin file; the current ProfileScreen
(`ProfileScreen.kt:59-148`) renders identity only, and its own comment states
that every action moved to Settings (v2.2 correction of the v2.1 claim that the
page "shows" the footnote — the orphan string is a cleanup candidate, §10.2).
Data: `profileRepository.getProfile()` (profiles join, §7.8);
states Loading (`ProfileSkeleton`) / Error / Content. No actions on this page —
all account operations live in Settings.

### 4.9 Guidance Assistant (rule-based engine + floating overlay)

**Engine** (`domain/guidance/GuidanceEngine.kt`, implementation
`DemoGuidanceEngine`) — deterministic, keyword matching over normalized input with
explicit rule precedence; low confidence produces an honest fallback; it never
invents official policies/dates. `normalize(input)`: lowercase, trim, strip
`[^a-z0-9\s]`→space, collapse whitespace. Match = substring containment of any
keyword; winner = highest `precedence`. `suggestedTopics` (fixed):
`How do I add an activity?`, `How does the Activity Beacon work?`,
`Study tips for exams`, `Community rules`.

Rules (keywords → precedence → answer → follow-up suggestions), verbatim from code:

| Keywords | Prec | Answer (verbatim) | Suggestions |
|---|---|---|---|
| add activity, add an activity, manual activity, create activity, new activity, record activity | 30 | `Manual activities are for deadlines your teachers give you face-to-face or that are not published online: open the Activity Beacon tab, and use the add button on the upcoming list. You choose the course, a due date, and an optional effort estimate. If a similar activity already exists, Student Codex will ask whether it is the same one before saving - nothing is merged silently.` | How does matching work? · How does the Activity Beacon work? |
| activity beacon, beacon, workload, upcoming, deadline(s), calendar | 25 | `The Activity Beacon combines every deadline you are responsible for: items imported from Google Classroom once you connect it, and activities you record manually. Each item is counted exactly once - if several sources describe the same assignment they are linked to one activity, not duplicated. The list is grouped by due date so you can see what lands today, tomorrow, and this week.` | How do I connect Google Classroom? · How do I add an activity? |
| classroom, google, sync, import, connect | 20 | `Google Classroom import is read-only: Student Codex only ever reads the coursework and announcements you are authorized to see, and you connect it from your Profile tab. Connecting is per-account - it never shares other students' data, and disconnecting removes access at any time.` | How does the Activity Beacon work? |
| community, post, anonymous, comment, reply, report, moderation | 15 | `The community is for study-related posts with up to three images. You can post anonymously - your name is hidden from other students, and you can edit or delete only your own posts and comments. If something breaks the rules, report it and moderators will review it.` | Community rules · Study tips for exams |
| study, exam, test, cram, review, memorize, focus, concentrate | 10 | `A dependable pattern: split the material into short sessions across days instead of one long cram, test yourself instead of re-reading, and start from the topics with the nearest deadlines - the Activity Beacon list is sorted exactly for that. Sleep before the exam beats one extra overnight hour.` | How do I plan my week? · How does the Activity Beacon work? |
| plan, time management, schedule, week, prioritize, procrastinate | 10 | `Start from what is due, not from what feels urgent: check the Beacon list, block the nearest deadlines first, and leave a buffer for the ones with no effort estimate yet. Two review moments a week - for example Sunday and Wednesday - are usually enough to keep the plan honest.` | Study tips for exams · How does the Activity Beacon work? |

Fallback (no rule matched): `I do not have a reliable answer for that yet, and I
would rather not guess. Try one of the topics below, or rephrase your question - for
official university policies, dates, or instructor instructions, always check the
official source.` + first two suggested topics. Empty input: `Ask me anything about
using Student Codex, planning your study time, or the community rules.` + all topics.

**GuidanceViewModel** (synchronous, no loading state): `messages:
StateFlow<List<GuidanceMessage>>` (`GuidanceMessage(id, isFromUser, text,
suggestions)`), `unreadReplies: StateFlow<Int>`, `send(text)` (appends user +
engine reply, increments unread), `markSeen()`, `sendSuggestion(topic)`,
`clearConversation()` (session end).

**Overlay presentation** — `GuidanceOverlayController` (a ViewModel over an
`OverlayStore`; production store = Russhwolf `Settings()`). State: `mode`
(CHAT_HEAD default | EDGE_PANEL), `expanded` (Boolean), `headAnchor` (side + y
fraction; default RIGHT 0.40), `edgeAnchor` (default RIGHT 0.50). Persistence keys:
`guidance.overlay.mode`, `guidance.overlay.head.side`, `guidance.overlay.head.y`,
`guidance.overlay.edge.side`, `guidance.overlay.edge.y`. `selectMode` persists and
closes any open panel; anchors sanitize y to 0..1.

`GuidanceOverlay` root: `BoxWithConstraints(fillMaxSize,
windowInsetsPadding(WindowInsets.safeDrawing))` — the bubble/handle never dock
under system bars; the panel stays above the keyboard. When collapsed:
**FloatingChatHead** (chat-head mode) or **EdgePanelHandle** (edge mode); when
expanded: the shared **ChatHeadPanel** wrapping **GuidanceChatPanel**.

- **FloatingChatHead**: 56dp circle (Surface CircleShape, **primary**, 2dp surface
  border, shadow 8dp) with a 28dp `Lightbulb` icon (contentDescription
  `Guidance chat head. Drag to move it, tap to ask a question.`). Draggable via
  `Animatable(Offset)` — clamped; released heads spring to the nearest side,
  tucking **30%** off-screen. Unread badge: 20dp error-colored circle (1.5dp surface
  border) with the count (`9+` beyond nine), offset 4dp, positioned TopEnd/TopStart
  by half.
- **EdgePanelHandle**: 30×96dp vertical pill (RoundedCornerShape(50%),
  surfaceContainerHigh, 1dp outlineVariant border, shadow 6dp) on the screen edge
  with a small chevron pointing toward the middle (KeyboardArrowRight when docked
  left, else KeyboardArrowLeft; contentDescription `Guidance edge panel. Drag the
  handle to move it, tap or pull it toward the middle to open.`). Pulling ≥48dp
  toward center OPENS the panel (handle quietly re-docks); taps open too.
- **ChatHeadPanel** (the one panel both entry styles open): scrim fade 160ms
  (`Color.Black.copy(alpha=0.32f)`, tap to close); card enter
  `fadeIn(180)+scaleIn(0.55f, 220ms)` from the docked corner (transformOrigin at
  the anchor edge), exit mirrored; card = `fillMaxWidth(0.92f) × fillMaxHeight(0.72f)`,
  shapes.large, surfaceContainerLow, tonalElevation 3dp, shadowElevation 12dp,
  1dp outlineVariant border.
- **GuidanceChatPanel**: header Row (Lightbulb 22dp primary + `Guidance` titleMedium
  + close IconButton `Close the guidance assistant`) → divider → transcript
  LazyColumn (empty state: `Ask me anything` + the honesty intro
  `I answer questions about using Student Codex, planning your study time, and
  community rules. When I am not sure, I will say so.`) → `SuggestedTopics`
  (AssistChips) while the transcript has ≤1 message → input row:
  `OutlinedTextField` (placeholder `Ask a question…`, ImeAction.Send) + 48dp
  `FilledIconButton` (ArrowUpward, enabled when non-blank). New messages
  auto-scroll; opening the panel marks replies seen.

Conversation parts (`MessageBubble`): user bubbles right-aligned
primary/onPrimary; assistant bubbles left-aligned surfaceContainerLow; width cap
300dp; suggestions render as `Try: {text}` links (labelMedium, primary).

### 4.10 Shared components

**StateViews.kt** — the state language of every list screen:

| Composable | Signature / rendering |
|---|---|
| `ActivityListSkeleton` | `(modifier, rowCount=7)` — rows of pulsing bones (20×20 icon bone, 62%×14 title, 38%×12 meta, trailing 56/36dp bones) separated by 40%-alpha dividers |
| `PostListSkeleton` | `(modifier, rowCount=4)` — card bones (32dp circle, 96/64dp bars, full + 72% bars) on surfaceContainerLow cards |
| `ProfileSkeleton` | `(modifier)` — 56dp circle + name bars + 3 section blocks |
| `EmptyState` | `(title, message, modifier, icon?)` — Column centered, padding xxl; title titleMedium; message bodyMedium onSurfaceVariant |
| `ErrorState` | `(message, onRetry)` — `Something went wrong` (titleMedium, error) + message + `Try again` FilledTonalButton |
| `SectionHeader` | `(title)` — titleMedium onSurface, vertical padding sm |
| `ActivityTypeIcon` | type→icon mapping (§3.6), 20dp, onSurfaceVariant, contentDescription = type label |
| `AuthorMark` | `(isAnonymous, authorName, markSize=32dp)` — circle surfaceVariant with Person/VisibilityOff icon at 55% of the mark; contentDescription `Profile photo placeholder for {name}` / `Anonymous author mark` |
| `EffortLabel` | `{n} min estimated`, labelSmall onSurfaceVariant (renders nothing when null) |

**ClassroomBadge / ManualBadge** (provenance chips, 12dp icons + labelSmall in a
50% pill, padding horizontal 8dp vertical 3dp):
- ClassroomBadge: background **`#0F9D58`** (Google green), white content, School
  icon, label `Google Classroom`.
- ManualBadge: secondaryContainer/onSecondaryContainer, Edit icon, label
  `Added manually`.

**ActivityDetailSheet** — `ModalBottomSheet(skipPartiallyExpanded=true)`, keyed on
the activity id; Column (scroll, horizontal padding lg, spacedBy md):
1. Header row: ActivityTypeIcon + title (**titleLarge**, uncapped).
2. Chip row: ClassroomBadge or ManualBadge + `VerificationChip` — a
   surfaceVariant pill (padding 8/3) with the verification label.
3. Divider (outlineVariant).
4. Fact rows (label labelSmall onSurfaceVariant over value bodyMedium): `Type`,
   `Course` (`code - title`), `Due` (`{dueLabel}, {time}` colored error/primary),
   `Effort` (`{n} min estimated`).
5. Notes: `No notes on this school work.` (bodySmall onSurfaceVariant) or a label
   + **ExpandableNotes** — bodyMedium clamped to 8 lines with a `See more` /
   `See less` TextButton only when the text actually overflows.
6. Full-width `Close` TextButton.

**ClassroomImportSheet + launcher** — `ClassroomImportUiState`: `Idle` (hidden) →
`Authorizing` (consent sheet up) → `LoadingCourses` → `Picking(courses, selected)` →
`Importing` → `Failed(message)`. Sheet (ModalBottomSheet): title `Import from
Google Classroom`; progress states show a 24dp spinner + `Connecting to Google
Classroom…` / `Loading your Google Classroom courses…` / `Importing your
courses…`; Picking shows the hint `Tick the courses you are taking — they are
added as your courses. You can still type any other course by hand.`, an empty
state `No active courses in your Google Classroom yet.`, or a 320dp scrollable
list of Checkbox rows (course name bodyLarge + `Section {label}` subtitle), and
`Add selected courses` (enabled when ≥1 ticked); Failed shows the message (or
`Google Classroom import failed — try again.` for JSON noise) + `Close`.
`rememberClassroomImportLauncher(authorizer, onStart, onAuthorized, onCancelled,
onError)`: coroutine launcher that first shows the **system Google account chooser**
(`awaitGoogleAccountChoice`, AccountPicker, every account + Add-account row,
180s timeout), then `authorizer.fetchAccessToken(activity, email)`; a picked
account is cached for the screen session; outcome mapping per §6.3.
## 5. Teacher website specification (WebView/)

Standalone, zero-build website: `index.html` + `styles.css` + `app.js` (single IIFE,
innerHTML rendering) + two vendored libraries. Served by double-clicking
`index.html`, any static server, or embedded in the Android app's assets
(`app/src/main/assets/webview/index.html`, `file:///android_asset/webview/index.html`).
Verified live in a browser on 2026-10-28 (Appendix B).

### 5.1 Structure & runtime

`index.html` (lang en): meta charset UTF-8, viewport
`width=device-width, initial-scale=1.0, viewport-fit=cover`,
`color-scheme light`, description; `<title>Student Codex — Teacher
Dashboard</title>`; inline data-URI SVG favicon (32×32, rx 7, `#2f5b41` rounded
square + white graduation-cap path). Loads, in order: `styles.css`,
`vendor/supabase.min.js`, `vendor/lucide.min.js`, `app.js`. Static mount points:
`#app` (`.app-root` — everything renders here), `#overlays` (stacked dialogs),
`#toasts` (`aria-live=polite`, label `Notifications`).

Supabase client: `window.supabase.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY,
{ auth: { persistSession: true, autoRefreshToken: true } })` — both constants are
hardcoded at the top of `app.js` (copy them from the live file or the project
dashboard; they are publishable values, safe for the browser). If the vendor script
is missing, a destructive alert gate renders instead. Demo teacher credentials
(`demo.teacher@studentcodex.app` + password) are hardcoded for the `Use demo teacher
credentials` button — values live in `app.js`/`WebView/README.md` and are seeded by
migration 20260101000900.

Lucide icons render via `ic(name, cls)` → `<i data-lucide="..." class="ic ...">` +
`window.lucide.createIcons()` after every render. Size classes: `.ic`=1em,
`.ic-3`=12, `.ic-3h`=14, `.ic-4`=16, `.ic-5`=20, `.ic-6`=24, `.ic-7`=28px.

### 5.2 Visual design tokens (styles.css `:root`, quoted verbatim)

```css
--background: #f6f7f4;      --foreground: #1c2620;
--card: #ffffff;            --card-foreground: #1c2620;
--primary: #2f5b41;         --primary-foreground: #f2f7f3;
--secondary: #e2eae4;       --secondary-foreground: #2a4032;
--muted: #edf0ea;           --muted-foreground: #5c6a5f;
--accent: #dfe9e1;          --accent-foreground: #22382a;
--destructive: #a63a2b;     --border: #dae1da;   --input: #c9d4ca;   --ring: #2f5b41;
--r-sm: 0.1875rem; --r-md: 0.25rem; --r-lg: 0.375rem; --r-xl: 0.5rem; --r-full: 9999px;
--shadow-sm: 0 1px 2px 0 rgb(28 38 32 / 0.06);
--shadow-md: 0 4px 10px -2px rgb(28 38 32 / 0.10);
--font: ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto,
        "Helvetica Neue", Arial, sans-serif;
```

Base: `font-size 14px`, `line-height 1.45`, antialiased; system font stack only
(no webfont); `::selection` `#cfe3d4`/`#1c2620`; thin `#b7c3b8` scrollbars;
`color-mix()` used for hover tints. **No dark mode** (light only).

Component styles (essentials):
- `.btn` — inline-flex, 36px height, `0 16px` padding, radius `--r-md`, 13px/500,
  .15s transitions, focus-visible ring 2px; variants primary (green bg/white),
  outline (white bg, `--border`), ghost, destructive `#a63a2b`, onprimary (10%→20%
  white overlay for use on the green month bar); sizes sm 32px/12px, xs 28px/11px.
- `.card` — white, 1px `--border`, radius `--r-lg`, `--shadow-sm`; `.card-head`
  padding `16px 16px 12px` (title 15px/600 + icon gap 8); body 16px.
- `.chip` — flex, `1px dashed transparent` border, radius `--r-sm`, `4px 6px`
  padding, **10px/600 uppercase** text, 12px icons, 2-line webkit clamp.
- `.input`/`.select` — 36px height, 1px `--input`, radius `--r-md`, 13px; focus =
  primary border + 2px ring tint; select has a custom chevron data-URI.
- `.overlay` — fixed inset 0, z 60, `rgb(28 38 32 / .45)` + 2px blur backdrop,
  fadeIn .15s; `.dialog` max-width 32rem, `max-height calc(100dvh - 32px)`,
  radius `--r-lg`, `--shadow-md`, popIn .16s (`translateY(8px) scale(.985)`).
- `.day-item`/`.report-item` — bordered rows, radius `--r-md`, white, 12px padding;
  hover = primary-tinted border + `--muted` bg; `[data-action]` rows get pointer +
  focus rings.
- `.badge` — radius full, 10px/500, `2px 8px` padding; variants below.
- `.toast` — fixed right/bottom 16px, z 80, `min(24rem, calc(100vw - 32px))`, white
  card with 3px left border (primary / destructive), slide-in .18s.
- `.spinner` — 24px circle, 2.5px border with primary top arc, .7s spin; sm 16px/2px;
  onprimary white variant. (Skeleton/shimmer CSS exists but is unused.)


### 5.3 Auth views

**Sign-in** (stage `signin`): centered `.auth-col` — brand head (28dp graduation
cap in a badge + `Student Codex — Teacher Dashboard` h1 + subtitle), `.auth-card`
with a two-tab `role=tablist` (`Sign in` / `Create teacher account`,
`data-action="auth-mode"`), then the form:
- Email (`#si-email`, autocomplete=email) + Password (`#si-password`, inside
  `.pw-wrap` with an eye-toggle button that flips the input type in place — the
  caret never leaves the field; re-hidden on tab switch or sign-out),
  field-level errors (`.field-error`), a resend-confirmation row (renders only
  when the hosted project has email confirmation ON — dormant while it is OFF,
  §8.7), primary block submit `Sign in` (spinner + `Signing in…` while busy), and
  a `.demo-box` with the `Use demo teacher credentials` button.
- Friendly error mapping: invalid credentials → `Incorrect email or password…`;
  email not confirmed → confirmation notice + resend; rate limit → wait message;
  else raw message. Drafts survive re-renders via `data-draft` bindings.
- Sign-in itself: `sb.auth.signInWithPassword` (`app.js:657,691,1972`). No
  magic-link/OTP path remains active in the UI (migration 0029 removed the
  typed-code path; `WebView/README.md:129-135`).

**Sign-up** (2026-10-31 state — the multi-select class-group flow with the 0031
school-email domain gate): First/Last name (`.grid-2`), `School email`, Password
(minlength 6 + hint `At least 6 characters.`), then the **class-group picker** —
four multi-select dropdowns fed by the live ParSU registry: Campus (optional
filter), Program (all 50 offerings, searchable), Year level and Block. Each stays
collapsed (label + live summary + chevron, e.g. `BSCS`, `2nd, 3rd`, `A, B, C +5`)
and rolls its checkbox panel down only while open — click again, click outside,
or press Escape to roll it back up; only one panel is open at a time. Every
checked combination instantly becomes a removable chip (display caps at 3 with a
`+N` more counter; the per-account cap is 12 groups — the RPC's server-side cap,
`20260101001600_teacher_signup_multi.sql:135-137`, enforced with inline feedback);
`Clear all` resets the checkboxes too. A client-side school-domain pre-check
(`SCHOOL_EMAIL_SUFFIX`, `app.js:35`) rejects non-`@parsu.edu.ph` addresses before
they reach Supabase (a UX pre-filter — the real gate is server-side, §7.4).
`signUpTeacher()`: `sb.auth.signUp` (`app.js:2009`) with
`{teacher_signup: true, first_name, last_name}` metadata; because the hosted
project issues a session immediately (email confirmation OFF), the role grant
follows at once — `teacher_signup_global()` (`app.js:616,2024,2059`) and, for
accounts with class-group metadata, `teacher_signup_multi(p_groups jsonb)`
(`app.js:2058`) — both gated server-side by the 0031 `@parsu.edu.ph` domain
check. **No email-verification step exists in the current flow**: the 0028–0030
machinery (OTP `amr` claim, emailed sign-in link, `email_confirmed_at` gate,
verify-email card) is dormant fallback only — the migration chain
0028 → 0029 → 0030 → 0031 progressively replaced it (§8.7). `PGRST202` (RPC
missing) → the "run `supabase db push`" notice.

**Not-teacher gate**: an account without the teacher role sees an alert
(`This account has no teacher access`) + optional `Activate teacher access` card
(legacy accounts whose metadata carries class groups → `teacher_signup_multi`
RPC with `p_groups` = `[{program_id, year_level, year_section_id, campus_id?}]`;
identity-only accounts → `teacher_signup_global`) + `Sign out`. Role check:
`user_roles.select('role').eq('user_id', uid)` must contain `teacher`.

Session handling: `sb.auth.getSession()` at boot (gate spinner
`Restoring your session…`), `onAuthStateChange` (SIGNED_OUT resets all state;
new-uid sign-ins re-handle), sign-out button in the dashboard header.

Security model: publishable key only; RLS decides (`app.js:14-19`,
README:90-96). Client config constants (Supabase URL + publishable key) and the
demo teacher credentials sit at the top of `app.js` (`:26-29`) — publishable /
seeded values, locations noted, values never reproduced in this document.

### 5.4 Dashboard shell

- `header.dash-header` (green brand bar): `.dash-logo` graduation cap, `.dash-title`
  (h1 + count subtitle), `.dash-me` (teacher name/email + initials avatar) and an
  outline `Sign out` button.
- `main.dash-main`: optional destructive `.alert` + `Retry` (`data-action=refresh`)
  on load errors; the **filter bar card**; `.dash-grid` = `cal-col` (calendar card)
  + `side-col` (Student-reported card + Data-coverage card); `.app-footer`.
- **Filter bar** (`.card.filter-bar`): head row — `.ftitle` (filter icon +
  `Filter sections`) + `.filter-count` (`{N} of M sections · {K} scheduled in
  {Month}`, aria-live). Grid of **4 searchable combobox widgets** (Campus /
  Program / Year / Section). Each: a `.combo-btn` trigger (current value +
  chevron-down) opening a `.combo-pop` panel with a pinned search input, live
  match count (`N campuses` / `N of M match`), scrollable options (max-height
  264px), no-match row. Sentinel option `__all__` labeled `All campuses` /
  `All programs` / `All years` / `All sections`. Registry mode (default once the
  anon-readable registry loads): all campuses; programs cascade to the chosen
  campus (duplicate names get `· {Campus}` suffixes); years as `{label} year`
  (searchable by ordinals); sections as `Section {name}`. Keyboard: ↑/↓ cycle,
  Enter picks, Home/End, Tab closes; Esc/outside-click closes. Campus picks
  re-validate the program. Reset button `reset-filter`. **All filtering is
  client-side** — the month query is always university-wide (§5.7).
- **Auto-refresh**: on tab-visible / window focus, if >10s since last refresh and
  stage ready → `refresh()` (re-fetch bundle + month, repaint).

### 5.5 Month calendar

- **Grid**: 42 cells (6×7) starting on **Sunday** of the week containing the 1st
  (`start.setDate(1 - first.getDay())`); out-of-month cells are `.cal-cell.blank`
  (muted, aria-hidden, min-height 44px mobile / 56px ≥640px); in-month cells are
  `button.cal-cell[data-action=open-day][data-day=YYYY-MM-DD]` with a checkerboard
  tint class; **today** = `.today` (accent background + 2px inset primary-tinted
  ring; the date disc turns primary/white).
- **Month bar**: h2 `{MonthName} {year}` (uppercase, 20→24px ≥640px, letter-spacing
  .03em) + inline loading spinner; nav = `Previous month` / `Today` / `Next month`
  (chevrons + label, `.btn-sm.btn-onprimary`).
- **Day cell content**: `.cal-date` (24→28px disc with the day number) +
  `.cal-chips` (flex column, gap 4px): up to **3 chips** then `.chip-more`
  (`+{n} more`, 10px muted). Chips sort by `due_at` string.
- **Chips**: `span.chip.chip-{type}[.student-reported][.past]` — 12px lucide
  icon + 2-line-clamped uppercase label; tooltip = `["Done · "][
  "Student-reported · "]"{Label}: {title}`. Exact palette:

| Category (slug) | Background | Text | Legend label |
|---|---|---|---|
| assignment | `#ffcc00` | `#000` | Assignment |
| quiz | `#2563eb` | `#fff` | Quiz |
| exam | `#dc2626` | `#fff` | Exam |
| project | `#ccfbf1` | `#134e4a` | Project |
| announcement | `#9333ea` | `#fff` | Announcement |
| other (Activity) | `#8b4513` | `#fff` | Activity |
| `.past` (any, past due) | `#15803d` solid | `#fff` | — |
| `.student-reported` | dashed outline `color-mix(currentColor 55%)` | — | — |

- **Past-due semantics**: `activityDueKey(a) < localDateKey(today)` — whole-day
  granularity by local date string compare; due-today stays live until midnight;
  a past student-reported chip keeps its dashed outline under the green fill.
- **Empty month**: `.cal-emptyhint` (role=status) `Nothing scheduled in {Month}.`
  plus `jump-month` chips (`{n} activities in {Month} ‹/›`) built from a
  neighbor-month probe (only when the unfiltered month is truly empty).

### 5.6 Day dialog & activity sheet (stacked overlays)

**Day dialog** (`daySheet(dayKey)`): head h3 = full local date
(`{Weekday}, {Month} {day}, {year}`), p = `{n} scheduled activities for the
filtered sections.` / `Nothing scheduled for this day.`; body = `.day-list`
(max-height 60vh) of `.day-item` rows (sorted by due_at): a 32×32 `.dicon`
icon square in the category color (green `#15803d` on past days) → `.dtitle`
(title) → `.dmeta` = `[{Label} · ][{courseCode} {sectionName} · ]due {time}[ ·
{effort}]` → `.ddesc` 4-line clamp → badge row (verification badge + optional
`Done` badge on past days). Rows are buttons (Enter/Space activate) and open the
activity sheet.

**Activity sheet** (`activitySheet(activity)`): head h3 = title; p = metaLine
`[{Label} · ][{course} {section} · ]due {sheetDueLabel}[ · {effort}]` — the
**sheetDueLabel** always carries the DATE because the sheet has no day context:
`Today, 3:59 PM` / `Oct 9, 3:59 PM` (month short + numeric day, Today
special-case, else `timeLabel` = `toLocaleTimeString` hour/2-digit-minute).
Body: `.a-badges` — verification badge (`Classroom-imported` [download icon,
secondary], `Teacher-confirmed` [badge-check, primary/white], `Student-reported`
[message-square, primary-tinted], `Needs review` [amber `#fffbeb`/`#92400e`]) +
extra `Student-reported` secondary badge (megaphone) + `Done` badge (green
`#15803d`). Then the **category correction row** (only when the teacher teaches
that activity's section or course — enrollments role=teacher): label `Category`,
a `teacher-corrected` tag when `category_locked`, a `role=radiogroup` of six
`.a-cat-opt` pills (current = `.is-current`, aria-checked), busy-disabled while
saving, and the hint `Corrections save immediately and are preserved on future
Google Classroom syncs.` Then **Notes**: `No notes on this entry.` or the label +
full description (`pre-wrap`, 8-line 12.8em clamp with a `See more`/`See less`
toggle shown only when overflowing). Foot: `Close`.
Overlays stack (day → activity); Esc/backdrop/Close pops only the top.

**Category correction write**: `activities.update({activity_type, category_locked:
true}).eq('id', id).select('id, activity_type, category_locked')` — success toast
`Category updated` / `Now tracked as {Label}. Future Classroom syncs keep it.` and
the in-memory row + month cache mutate, the sheet meta-line updates, and a full
re-render re-colors every chip (chips derive their class from `activity_type`).
An empty update result throws `You can only correct categories for sections you
teach.` (RLS mirrors this). The WebView never sets `category_locked_by` — the
DB trigger stamps the authenticated teacher (§7.4).

### 5.7 Data retrieval (website)

One university-wide month query drives everything:

```js
// ACTIVITY_COLUMNS includes category_locked; scope='section' only
sb.from('activities')
  .select(ACTIVITY_COLUMNS)
  .eq('scope','section').is('deleted_at', null)
  .gte('due_at', fromIso).lte('due_at', toIso)   // first-of-month .. last-day 23:59:59.999 local
  .order('due_at', {ascending:true}).limit(500)
```

Plus: registry tables (`campuses`, `programs`, `year_levels`, `year_sections` —
anon-readable, module-level cached with in-flight dedupe); teacher's
`enrollments` (role filter derives `teacherSectionIds`/`teacherCourseIds`);
`sections` (ALL sections, university-wide) + `courses`/`programs` enrichment by
id; `profiles` rows for reporter names and the teacher's own name;
`google_connections` (own row) for the coverage card. Month results are cached
per `YYYY-MM` key; empty months trigger a neighbor probe. All reads run under the
signed-in session; the publishable key alone grants only the registry.

### 5.8 Side panels

- **Student-reported card** (read-only feed): the month's student-reported
  activities as `.report-item` rows — title, meta (`{course} {section} · due
  {Mon d}`), 3-line-clamped notes, reporter name resolved from `profiles`;
  `.done` styling (dark-green `done-tag` pill) when past. Empty state:
  `None in {Month}` + hint.
- **Data-coverage card**: (1) Google Classroom sync line — `Google Classroom
  sync: {google_email}` when the teacher's own connection row is `connected`,
  else `Google Classroom sync not enabled yet`, with sub-text; (2) `Last refresh`
  timestamp + `Refresh` button; (3) privacy note `Teachers see section-scoped
  records across every campus and program. Personal student activities remain
  private by design.` **No workload/effort analytics are computed** (§10).

### 5.9 Legend (interactive filters)

Calendar footer `.cal-legend`: lead `Filter:`; six category toggles
(`data-action=type-filter`, swatch `.sw-{slug}` — project swatch `#5eead4`);
`Dashed outline = student-reported` and `Dark green = past due (done)` flag
toggles (`data-flag=reported|past`, `.sw-done` `#15803d`); while active: status
line (`{n} hidden by category filters` / `Category filters are on`) + `Clear
filters`. Filters apply to calendar chips, day dialogs and the feed at once
(`visibleActivities`), matching `activity_type`, `verification_status ===
'student-reported'`, and past flags respectively.

### 5.10 Responsive behavior

| Breakpoint | Changes |
|---|---|
| ≤639px | single-letter weekday headers (`S M T W T F S`); `.hide-sm` swaps to sr-only (sign-out); cells 44px min-height; raised touch targets (`.btn-sm` ≥36px, tabs ≥44px) |
| ≥640px | full weekday names; header padding 24px; subtitle + `.who` block; monthbar 24px h2; cells ≥112px; `.cal-date` 28px/14px |
| ≥768px | filter grid → 4 columns |
| ≥1024px | `.dash-grid` → `minmax(0,2fr) minmax(0,1fr)` two-column |
| ≤420px | sign-up `.grid-2` collapses |

Dialogs stay centered at all sizes (`max-height calc(100dvh - 32px)`,
`viewport-fit=cover`, safe-area-inset-bottom on the footer). Chip text clamps so
the grid never scrolls horizontally (`minmax(0,1fr)` columns).

### 5.11 Interaction states & toasts

Toasts (`toast({title, description, variant})`): bottom-right stack, auto-dismiss
6000ms (8000ms destructive), close button. No confirm dialogs exist (view-only
surface; category corrections are instant with toast feedback). Loading = gate
spinner, month-bar spinner, busy-button spinners; errors = field errors (auth),
destructive alert + Retry (loads), destructive toasts (corrections). All user data
is HTML-escaped (`esc()`); delegated `data-action` click routing + Enter/Space
activation for `role=button` rows.
## 6. Feature behavior — end to end

### 6.1 Authentication & sessions (Android)

**Email sign-in:** trim email → `auth.signInWith(Email)` → session →
`SessionInfo` (displayName from `full_name` metadata; `profileCompleted` from
`profile_completed`; `hasEmailCredential` from appMetadata providers containing
`email`). Duplicate-account errors map to `DuplicateAccountException` (AuthRestException
codes EmailExists/UserAlreadyExists/IdentityAlreadyExists or message heuristics).
Sessions persist via supabase-kt's default `SettingsSessionManager`
(SharedPreferences) — stay-signed-in across restarts; `CheckingSession` gate with a
2s restore timeout.

**Sign-up:** `auth.signUpWith(Email)` carrying user metadata
`{first_name, last_name, full_name, profile_completed:true, program_id, year_level,
campus_id, year_section_id, course_codes:[...]}`. The `on_auth_user_created`
trigger (§7.4) inserts `profiles(id)`, validates each registry id (invalid ones
null), updates name/school fields with coalesce, claims a username via
`derive_username`→`claim_username` (lowercase given+family, accents folded,
non-alphanumerics→`_`, ≤24 chars; collisions append `_2.._21`), and calls
`enroll_student_courses` (§6.2). If signUp returns a user but no session → email
confirmation required → `ConfirmationRequired` notice (the live project has
confirmation DISABLED since 2026-10-24, so this path is dormant).

**Google Sign-In:** Credential Manager `GetGoogleIdOption` (serverClientId =
`GOOGLE_SERVER_CLIENT_ID`, `filterByAuthorizedAccounts(false)` — every on-device
account offered; no auto-select) → `GoogleIdTokenCredential.idToken` →
`auth.signInWith(IDToken, provider=Google)`. First-time ⇒ `CompletingProfile`
(name suggested from the Google profile); existing email not linked to Google ⇒
duplicate error with the "continue with Google using that same email" hint.
Device failures: NO_ACCOUNT / REJECTED (GMS code 13 — SHA-1 fingerprint not
registered, §8.3) / GENERIC, each with its own actionable string; unconfigured
client id ⇒ the setup dialog, email sign-in unaffected.

**Profile completion** (§4.3): `auth.updateUser` with the same 9 metadata keys +
optional password (only when the account has no email credential). The
`on_auth_user_profile_sync` trigger (fires on metadata change with
`profile_completed=true`) mirrors the same fill/enroll logic idempotently.

**Guest mode:** `SessionInfo(isGuest=true)` in memory only — no Supabase account,
no network writes. Screens render read-only variants (§4); sign-out is local.
Guests still see real registry feeds but cannot post/like/comment/report/edit
(guards in §7 RLS + UI disables).

**School-details edit (Settings):** `auth.updateUser` metadata (names absent —
the trigger coalesces) → same enrollment path; idempotent.

**Password change:** `auth.updateUser { password }` (min 6 validated client-side).

### 6.2 Course enrollment & the course catalog

Courses are enrolled **by NAME** (the "course code" concept is the full course
name, e.g. `Application Development 2` or `MEETING`). Paths:

1. **Sign-up / completion / Settings course chips** — `course_codes` metadata →
   `enroll_student_courses(p_user, p_program, p_year, p_block_id, p_codes)`:
   ≤32 distinct trimmed codes sorted `upper(code)` (global advisory-lock order);
   junk guard `^[A-Za-z0-9][A-Za-z0-9 .,:;()/&+\-]{0,159}$` → `invalid`;
   case-insensitive course resolution preferring the student's own program;
   **fuzzy tier (migration 0027)**: an entry that RESEMBLES an existing course
   (`course_text_matches` — token-subset in EITHER direction; tokens = alnum
   runs ≥3 chars, pure digits and stop-words dropped from the typed side;
   own program first, longest candidate code wins) enrolls into THAT course
   instead of creating a parallel row, so "CC4" / "CC4 - Data Structures and
   Algorithms" converge on the imported "CC4 - Data Structures and
   Algorithms 2026-2027" and share its cohort section (reported in the
   `fuzzy_matched` return array; "CC42"/"MEET"/"GE7"/"and"/"2026" never match);
   **unknown courses are CREATED** (`code = title = entry`, attached to the
   program) then enrolled; the cohort section is matched by suffix
   `'% {year}-{block}'` (preferring own-program prefix) or created as
   `cohort_section_name(program, year, block)` = `left(prog-short,72) + ' ' +
   year + '-' + block`. Returns
   `{enrolled, matched, unknown, no_section, invalid, fuzzy_matched,
   created_courses, created_sections, skipped}`.
2. **Classroom import** (§6.3) — `import_student_classroom_courses` with the
   exact `external_course_id` link.

Section semantics: a student's cohort section for course C is the section whose
name ends with `{year}-{block}`; one course can have many sections (one per
cohort), each with its own activity rows.

**Student-facing course catalog:** the picker offered by sign-up / profile
completion / Settings lists **manually-entered courses only**. The catalog
query selects `id, code, title, external_course_id` and skips rows whose
`external_course_id` is set (imported/Classroom-linked courses, migration
0022) — those reach a student exclusively through the Classroom import flow,
so one batch's imported courses never appear in a later batch's menu.
Enrollment by a typed name still resolves server-side (the RPCs are
unchanged); the teacher dashboard continues to see every course.

### 6.3 Google Classroom integration

**Scopes (read-only, exact):**
`classroom.courses.readonly`, `classroom.coursework.me.readonly`,
`classroom.announcements.readonly` — requested as
`"oauth2:" + scopes.join(" ")` via GoogleAuthUtil, or as an
`AuthorizationRequest` for the interactive sheet.

**Authorization (on-device):** the student first picks WHICH Google account —
the system AccountPicker chooser (`awaitGoogleAccountChoice`, every account +
Add-account; 180s timeout) — then:
- Pinned path (known email): `GoogleAuthUtil.getToken(activity, Account(email),
  scopeString)`; `UserRecoverableAuthException` → consent sheet (retry once);
  `GoogleAuthException`/`AccountNotPresent` → `PinUnresolved` (fall back to the
  chooser); IOException → network error.
- Unpinned path: `Identity.AuthorizationClient.authorize(request)`; pending intent
  → consent sheet via `StartIntentSenderForResult`; silent-needed →
  `SilentUnavailable`; outcomes `Token / Cancelled / Declined / Rejected(code 13) /
  Error`. All flows serialize behind one mutex.
**Tokens are transit-only**: one access token per sync, sent in the Edge Function
body, never stored anywhere (device or DB); revocation in Google settings takes
effect the next sync.

**Edge Function `classroom-import`** (deployed `--no-verify-jwt` because the
LIST action must work pre-sign-up):
- `POST {action:"list", googleAccessToken}` → `{status:"ok", courses:[{id, name
  ≤160, section ≤80|null}]}` — the account's ACTIVE courses (paginated ≤5×100);
  Google 401/403 → `{status:"failed", error:"google_401|403", message:"Google
  rejected the authorization — reconnect Google Classroom."}`
- `POST {action:"import", googleAccessToken, courseIds:[...], accountEmail?}` —
  requires the caller's Supabase session JWT (manually verified against
  `/auth/v1/user`; service key rejected); re-fetches the course list so only
  currently-ACTIVE ids enter; runs `import_student_classroom_courses(p_user,
  p_courses:[{externalId ≤64, name ≤160, section ≤80|null}])` (§6.2 tiered
  resolution: exact `external_course_id` link → normalized-name match with
  link-back → fuzzy `course_text_matches` resemblance with link-back
  (migration 0027) → create under the GC name; enrollment lands in the
  importer's COHORT section — resolved/created via `cohort_section_name`,
  GC section label as the no-cohort fallback); stamps `google_connections {status:"connected", google_email,
  last_sync_*}`. Response: `{status:"ok", enrolled, created, linked, matched,
  invalid, sectionsCreated, courses}`.
- App usage: at the sign-up gate (chips are added immediately by name; the RPC
  import + one follow-up sync run after the account lands — errors deliberately
  swallowed, the name-chips already enrolled the courses) and in the Settings
  school sheet.

**Edge Function `classroom-sync`** (JWT verified):
- Body `{googleAccessToken, accountEmail?}`; identifies the caller, then:
  lists ACTIVE courses → loads the user's `enrollments ⋈ sections ⋈ courses`
  (with `external_course_id`) → **matches each Classroom course to a local
  section**: Tier 0 = exact `external_course_id` link; else normalized-name match
  (`norm()` = uppercase, strip non-alphanumerics; equal OR Classroom name
  startswith course code); multiple candidates prefer the section whose name
  matches the Classroom `section` label; unmatched classes are skipped and
  reported (never force-created).
- Imports each PUBLISHED coursework item via `upsert_activity_from_source`:
  `source_key = google_classroom:{courseId}:{courseWorkId}`; type from workType
  (ASSIGNMENT→assignment; SHORT_ANSWER/MULTIPLE_CHOICE→quiz; else other) — but the
  final category comes from `suggest_activity_category(title, type)` (§7.3);
  due = Classroom dueDate+dueTime at Manila wall clock, **date-only ⇒ 23:59
  Manila**; `source_meta = {courseName, sectionLabel, workType, alternateLink}`;
  scope `section`, verification `imported`; effort null. Announcements:
  `source_key = google_classroom_announcement:{courseId}:{annId}`, title =
  first 80 chars of the text, due pinned to the post time (lands on its calendar
  day), type `announcement` (immune to reclassification).
- A teacher's own class may 403 on coursework (student scopes) → that class's
  coursework is skipped with a reason; announcements may still import.
- Response: `{status:"ok"|"partial", imported, updated, classesTotal,
  matchedClasses:[{classroomName, courseCode, sectionName}], skippedClasses:
  [{classroomName, reason}], skippedCoursework, syncedAt}`; stamps
  `google_connections` (status connected, email, last_sync_at/status partial|ok|
  failed + truncated error). Google 401/403 on the course list ⇒ connection
  status `revoked` / `expired` — surfaced by the app's connection card (§4.7).
- **Idempotency/dedup:** `upsert_activity_from_source` is service-only (JWT
  callers rejected), resolves by the unique partial index on `source_key`, updates
  content + `activity_type = case when category_locked then keep else
  suggest_activity_category(...) end` — **teacher corrections survive re-syncs** —
  and refreshes `source_meta`. Existing rows count as `updated`, new as `imported`.

**Auto-sync (Android):** toggle stored in SharedPreferences key
`classroomAutoSyncEnabled` (multiplatform-settings). `ClassroomAutoSyncer.runIfDue`
runs on every `ON_START` when enabled AND the connection row is `Connected`:
silent-only token fetch for the pinned `google_email` (consent-needed accounts
are skipped quietly — never a dialog), then one sync; `AtomicBoolean` prevents
overlap; failures are silent (next open retries); imported rows surface via the
Beacon on-resume refresh. No throttle window — every sync is idempotent by
source key.

### 6.4 Activity Beacon semantics

**Creation (the instant-publish model).** The manual editor (§4.5) always saves a
class activity: `activities` insert with `scope='section'`, `section_id`/`course_id`
from the picked cohort section, `verification_status = 'teacher-confirmed'` when
the creator is enrolled as a teacher in that section (guard-verified) else
`'student-reported'`, `created_by_user_id = caller`, due = picked date at
**23:59 Asia/Manila** (SchoolTime.toDueInstant) regardless of device zone,
`estimated_effort_minutes` null (the editor exposes no effort field — effort
displayed only for imported rows). RLS `activities_insert` enforces: creator =
caller AND (personal scope OR section scope with student-reported + enrolled-as-
student OR teacher of the section OR course scope taught). Guard
`guard_activity_insert` blocks client-forged `imported` status and un-earned
`teacher-confirmed`. There is NO approval step and NO `activity_sources` row for
manual creations — the visible provenance pill is the neutral `Added manually`.

**Student-reported rows** flow straight onto the section calendar (the teacher
dashboard shows them dashed, §5.5). Soft delete (`deleted_at = now()`) hides the
row from every list — the creator's own list AND the teacher's calendar (a
withdraw).

**The legacy report workflow** (`activity_reports`: pending→matched/confirmed/
rejected/needs_review, reporter withdraw) still exists fully at the DB level
(§7) but the app no longer files reports — the migration `20260101001500` drained
all pending reports into published student-reported activities, and the app's
create path replaced the queue. Replicate the DB objects (tests T11 cover them)
but do NOT build a report UI.

**Visibility (RLS `activities_select`):** non-deleted rows where creator =
viewer, OR viewer is a participant, OR viewer is a teacher (any section/course
scope — university-wide teacher visibility, migration 0019), OR scope=section AND
viewer enrolled in that section, OR scope=course AND viewer enrolled in any
section of that course. Soft-deleted rows are visible only to their creator.

**Ordering & grouping** are client-side (§4.5); personal activities carry a
`Personal` label; imported rows show the green Classroom badge.

### 6.5 Community semantics

- **Post creation:** text (≤5000 chars by DB check) or one photo; app inserts
  `posts {author_id, content, is_anonymous:false}` (§4.6 gap note), then uploads
  the image to the private `community-images` bucket at
  `{uid}/{postId}/{timestamp}.jpg` and inserts `post_images {post_id,
  storage_path, position:1}`; the canonical row is re-read from `feed_posts`.
  Rate limit: ≥8 posts per rolling 10 minutes ⇒ DB error `posting too quickly`.
- **Display:** `feed_posts` view (§7.2) — anonymous posts null the author id/name
  server-side (names never leak), aggregates like/comment counts, `liked_by_me`,
  and `image_paths` (ordered). Images render via authenticated bucket downloads
  (no public/signed URLs).
- **Likes:** toggle inserts/deletes `post_likes` then re-reads the canonical row
  (server counts). Comment likes exist in the schema/views but have no UI.
- **Comments:** insert `comments {post_id, author_id, content, is_anonymous:false}`;
  DB enforces same-post live parent + depth ≤5; the app always writes flat
  (no parent). Rate limit ≥30/10min. `feed_comments` view mirrors the anonymity
  nulling.
- **Reports:** `content_reports {reporter_id, target_type:'post', target_id,
  reason∈{spam,harassment,off-topic,inappropriate,other}, details?≤1000,
  status:'open'}`; moderators/admins triage (guard restricts updates to them);
  no moderation UI exists anywhere yet.
- **Blocking:** `user_blocks` hides blocked authors' posts/comments from the
  blocker (policies + feed views). No UI ships for blocking.
- **Moderation deletes:** moderator/admin DELETE policies exist on posts/comments;
  no UI.

### 6.6 Guidance assistant behavior

Pure client-side: send → normalize → rule match (highest precedence wins,
§4.9) → answer + suggestions appended to the shared transcript. The transcript is
shared by the chat head card, the edge panel card, and the Home CTA; it survives
tab switches (ViewModel at app level) and is cleared on sign-out. Suggestions are
sent as new questions when tapped. No network, no logging.

### 6.7 Teacher dashboard data flow

Boot → restore session → verify teacher role → fetch bundle (profile, ALL
sections, own enrollments, google connection; then courses/programs enrichment)
→ render → fetch current month (university-wide scope='section' query, §5.7) →
client-side cohort filter + category filters → calendar. Interactions per §5.
The dashboard performs no writes except category corrections (§5.6).

## 7. Data & API contracts

33 migrations under `supabase/migrations/` (`20260101000000_core.sql` …
`20260101003200_rpc_execute_hardening.sql`) — apply in order. All tables are in the
`public` schema; RLS is enabled on every API-exposed table; `service_role` bypasses
RLS everywhere (and the guard triggers exempt callers with `auth.uid() IS NULL`);
`anon` has SELECT policies only on the five registry tables.

**Tracked vs working-tree:** migrations 000000–002000 are committed in git;
002100–003200 (12 files) exist only as untracked working-tree files — the
repository has exactly two commits (`71e2661` initial import, `95e9b15` one
auth-gate UI tweak), so the entire dashboard rework, migrations 0021–0032, two
of the three Edge Functions, and this document itself are uncommitted working
tree (committing is roadmap M2.4).

**Hosted deployment state (verified 2026-10-29/31):** the hosted Supabase
project has migrations 000000–002800 applied (0028 pushed live 2026-10-29
04:45 UTC). **Migrations 002900–003200 are LOCAL-ONLY** — applied and tested in
the local PostgreSQL test environment (Appendix C) but **NOT deployed to the
hosted project**. Never describe 0029–0032 as hosted or production-deployed.

### 7.1 Migration index

| Migration | Creates / changes (essentials) | Tracked? |
|---|---|---|
| 000000 core | `programs`, `profiles`, `user_roles`; `set_updated_at`, `handle_new_user`, `guard_profile_update`, `has_role`; trigger `on_auth_user_created`; RLS | committed |
| 000100 academic | `courses`, `sections`, `enrollments`; `is_enrolled`, `is_section_teacher`, `is_course_teacher` | committed |
| 000200 activities | `activities`, `activity_sources`, `activity_reports`, `activity_groups`(+members), `activity_participants`; `activity_visible_to_user`, guards; full RLS | committed |
| 000300 community | `posts`, `post_images`, `comments`, `post_likes`, `comment_likes`, `user_blocks`; guards; views `feed_posts`, `feed_comments` | committed |
| 000400 moderation | `content_reports` + guard | committed |
| 000500 storage | private bucket `community-images` + 4 storage policies | committed |
| 000600 profile_names | `profiles.first_name/last_name`; `derive_username`, `claim_username`; trigger `on_auth_user_profile_sync` | committed |
| 000700 school_details | `campuses`, `year_levels`, `year_sections`; profile FKs; seeds registry; `try_uuid` | committed |
| 000800 phase_completion | posts content ≤5000 (photo-only); rate-limit guards; `google_connections`; `upsert_activity_from_source`; views `my_posts`, `section_workload_daily` | committed |
| 000900 demo_seed | fixed-UUID demo users/teacher/courses/sections/enrollments/activities/posts (idempotent) | committed |
| 001000–001200 | demo identity/password/shape fixes; `programs.campus_id` + 42 official rows (fixed ids `e1000000-…-0001..002a`) | committed |
| 001300 teacher_signup | RPC `teacher_signup(p_program,p_year_level,p_year_section,p_campus)` single-group | committed |
| 001400 registry_completion | +8 program rows → 50 total | committed |
| 001500 student_self_publish | replaces `activities_insert` (student self-publish); `activities_update_own_student_report`; drains pending reports | committed |
| 001600 teacher_signup_multi | RPC `teacher_signup_multi(p_groups jsonb)` (≤12 groups) | committed |
| 001700 student_course_signup | RPC `enroll_student_courses`; course signup wired into the auth triggers; `courses_select_public` (anon) | committed |
| 001800 student_course_selfservice | rewrites it: unknown-code creation, advisory locks, 32-code cap | committed |
| 001900 global_teacher_visibility | teachers read ALL non-personal activities; `teacher_signup_global()` | committed |
| 002000 due_at_manila_repair | one-time data repair (23:59 UTC → Manila) | committed |
| 002100 course_name_shape | code length ≤160; junk-guard widened to full course-name punctuation | untracked |
| 002200 classroom_course_import | `courses.external_course_id` (+partial unique); RPC `import_student_classroom_courses` | untracked |
| 002300 activity_category_tracking | `category_locked`/`category_locked_by`; `suggest_activity_category`; upsert/guard rewrites; reclassification pass | untracked |
| 002400/002500 quiz regex fixes | `QUIZ(ZES?)?` token | untracked |
| 002600 activity title token | `ACTIVIT(Y\|IES)` → `other` | untracked |
| 002700 cohort_convergence | helpers `course_text_matches` + `cohort_section_name`; enroll fuzzy tier (+`fuzzy_matched`); import Tier 2b fuzzy + cohort-section preference | untracked |
| 002800 teacher_email_verification | OTP-gated teacher role RPCs (JWT `amr` claim `otp`/`magiclink` → `EMAIL_NOT_VERIFIED`); legacy `teacher_signup` deliberately left unguarded (header: no reachable caller) — **applied to the hosted project 2026-10-29** | untracked |
| 002900 email_click_verification | email-click verification (link → `site` function → verified-email gate); removed the dashboard's typed-code path — local only | untracked |
| 003000 verified_email_db_gate | `email_confirmed_at` gate read from `auth.users` (JWT claim not signed by hosted GoTrue) — local only | untracked |
| 003100 teacher_school_email_domain | `@parsu.edu.ph` domain gate on `teacher_signup_global`/`teacher_signup_multi` (case-insensitive suffix, SECURITY DEFINER read of `auth.users.email`); retires 0030's gate — local only | untracked |
| 003200 rpc_execute_hardening | F1/F2/F3 EXECUTE revokes — pure privilege change, NO function body modified (§7.4, Appendix C) — local only, hosted deployment pending | untracked |

Also present in the working tree: `.backup-0028/` (`app.js`, `styles.css`
backups) and `.backup-0032/` (migration set up to 0031 + 3 test files) —
untracked working backups, not part of the migration chain.

### 7.2 Tables (final shape — key columns; all ids uuid `gen_random_uuid()` PK, created_at/updated_at timestamptz default now(), `set_updated_at` triggers)

- **profiles**: id (=auth.users.id, FK CASCADE), username (unique partial,
  `^[a-z0-9_]{3,24}$`, immutable once set), first_name, last_name, program_id (FK
  SET NULL), year_level int 1–8 FK→year_levels(level) (NO ACTION — unique among
  FKs), campus_id, year_section_id.
- **user_roles**: user_id FK, role ∈ {student, teacher, moderator, admin}, unique
  (user_id, role). Admin-managed; no client write policies.
- **programs**: university_name, program_name, campus_id (NOT NULL, FK CASCADE);
  unique (university_name, program_name, campus_id); 50 seeded rows.
- **campuses** (7, unique name, sort_order) · **year_levels** (level 1–5 PK, label
  `1st`..`5th`) · **year_sections** (A–F, 1–3, unique name, sort_order).
- **courses**: program_id FK, code 1–160, title 1–200, unique (code, title),
  external_course_id (partial unique where not null).
- **sections**: course_id FK CASCADE, name 1–80, term; unique (course_id, name,
  coalesce(term,'')).
- **enrollments**: section_id, user_id, role ∈ {student, teacher}; unique
  (section_id, user_id).
- **activities**: title 1–200, description, activity_type ∈ {assignment, quiz,
  exam, project, announcement, other} default other, course_id/section_id FKs,
  due_at timestamptz, estimated_effort_minutes 1–10080, scope ∈ {personal,
  section, course} default personal, verification_status ∈ {imported,
  teacher-confirmed, student-reported, needs-review} default student-reported,
  created_by_user_id NOT NULL FK CASCADE, deleted_at (soft delete),
  category_locked bool default false, category_locked_by FK. CHECKs:
  scope=section ⇒ section_id present; scope=course ⇒ course_id present.
  Indexes: due_at (partial where deleted_at is null), section, course, creator.
- **activity_sources**: activity_id FK CASCADE, provider ∈ {google_classroom,
  student_manual, teacher_manual}, external_course_id, external_item_id,
  source_key (partial unique), reported_by_user_id, source_meta jsonb default {}.
  Unique (provider, external_course_id, external_item_id) where external_item_id
  not null. Guard: client (JWT) cannot forge google_classroom rows.
- **activity_reports**: reporter_user_id, activity_id, title, due_at, course_id,
  section_id, notes, status ∈ {pending, matched, confirmed, rejected,
  needs_review, withdrawn}.
- **activity_groups / members / participants**: cross-section grouping + sharing
  (participants make personal activities visible to others).
- **posts**: author_id FK CASCADE, content ≤5000 (photo-only allowed),
  is_anonymous, edited_at, deleted_at. **post_images**: post_id, storage_path
  1–500, position 1–3, unique (post_id, position) — DB-enforced 3-image max
  (app uses 1).
- **comments**: post_id, parent_comment_id (self-FK CASCADE — nesting), author_id,
  content 1–2000, is_anonymous, edited_at, deleted_at. Guard: parent must be in
  the same post, live, depth ≤5.
- **post_likes** / **comment_likes**: unique (target, user_id).
- **user_blocks**: blocker, blocked, CHECK blocker<>blocked.
- **content_reports**: reporter_id, target_type ∈ {post, comment}, target_id
  (polymorphic, no FK), reason ∈ {spam, harassment, off-topic, inappropriate,
  other}, details ≤1000, status ∈ {open, actioned, dismissed}.
- **google_connections**: user_id PK, google_email, status ∈ {connected,
  disconnected, revoked, expired}, last_sync_at, last_sync_status ∈ {ok, partial,
  failed}, last_sync_error. No client INSERT/DELETE; owner may only UPDATE status
  → 'disconnected' (guard).

### 7.3 Views (all `security_invoker = true`)

- **feed_posts**: non-deleted posts LEFT JOIN profiles; for anonymous posts the
  author_id/name are NULLed at the view (identity never leaks); like_count,
  comment_count (non-deleted only), image_count, liked_by_me (EXISTS post_likes
  for auth.uid()), image_paths (jsonb_agg ordered by position).
- **my_posts**: own non-deleted posts incl. anonymous (author_id always exposed).
- **feed_comments**: same pattern for comments (+like_count, liked_by_me).
- **section_workload_daily**: per section+due-date aggregates (activity_count,
  total_effort_minutes) for scope='section' — used by NO client today (the
  workload feature is [PLANNED]); retained for it.

### 7.4 Functions (33) — the load-bearing ones

- **has_role(role)**, is_enrolled(section), is_section_teacher(section),
  is_course_teacher(course): SECURITY DEFINER STABLE helpers used by every policy.
- **handle_new_user** (AFTER INSERT on auth.users): bare profiles insert; reads
  raw_user_meta_data {first_name, last_name, program_id (try_uuid), year_level,
  campus_id, year_section_id}; validates against registry (invalid → NULL);
  coalesces into profiles; claims username once; finally PERFORM
  enroll_student_courses(uid, program, year, section, course_codes).
- **handle_user_profile_sync** (AFTER UPDATE when metadata changed, gated on
  profile_completed=true): same, idempotent.
- **guard_profile_update**: id immutable; username immutable + lowercased +
  shape-validated.
- **guard_activity_insert**: caller NULL passes; `imported` reserved for the sync
  service; `teacher-confirmed` requires section/course teacher or admin;
  section-scoped `student-reported` requires enrolled-as-student or admin.
- **guard_activity_update**: creator immutable; locking stamps
  category_locked_by = caller; status changes INTO teacher-confirmed/imported
  require teachership.
- **guard_comment_insert**: same-post live parent; ancestor walk, depth < 5.
- **Rate guards**: posts ≥8/10min, comments ≥30/10min, reports ≥10/1h (service
  exempt) — distinct error strings ("posting too quickly", etc.).
- **upsert_activity_from_source(...)** (service-only; JWT callers rejected):
  dedup by source_key; on re-import updates content and
  `activity_type = CASE WHEN category_locked THEN activity_type ELSE
  suggest_activity_category(...) END` (corrections survive); inserts with
  verification `imported`, scope from args, and the activity_sources row.
- **suggest_activity_category(title, fallback)** — the classification contract
  (EXACT priority): ① fallback='announcement' ⇒ 'announcement'; ② title token
  PROJECTS?|CAPSTONE|MACHINE[ -]?PROBLEMS?|MACHINE[ -]?PROJECTS? ⇒ 'project';
  ③ EXAMS?|MID[ -]?TERMS?|FINALS|FINAL[ -]?EXAMS?|FINAL[ -]?EXAMINATIONS?|
  PRELIMINARY|PRELIMS? ⇒ 'exam'; ④ QUIZ(ZES?)? ⇒ 'quiz'; ⑤ ACTIVIT(Y|IES) ⇒
  'other' (word boundaries — "Interactive" never matches); ⑥ valid fallback kept
  (never defaulted to assignment); ⑦ 'other'.
- **course_text_matches(typed, code, title)** / **cohort_section_name(program,
  year, block)** (migration 0027): shared helpers — the conservative fuzzy
  matcher (§6.2) and the single source of the "BSCS 2-B" naming convention.

- **enroll_student_courses / import_student_classroom_courses /
  teacher_signup / teacher_signup_multi / teacher_signup_global**: §6.2–6.3 and
  §5.3. **Execute privileges after migration 0032 (Appendix C):**
  `teacher_signup_global` / `teacher_signup_multi` remain granted to
  `authenticated` only (0031 also revoked `anon`) and both carry the
  `@parsu.edu.ph` domain gate; legacy `teacher_signup` is revoked from
  `authenticated` (F1 — no caller exists); `enroll_student_courses` and
  `import_student_classroom_courses` are `service_role`-only (F2/F3) — the two
  `auth.users` triggers (definer context, `auth.uid()` NULL) and the
  service-key Edge Function calls are unaffected, while direct
  `authenticated` calls now fail with 42501. `upsert_activity_from_source` +
  `suggest_activity_category` remain service-only. The two enrollment RPCs
  carry the cohort-convergence tiers of migration 0027 (§6.2). **Caveat:** the
  0032 privilege state is verified in the LOCAL test environment only — the
  hosted project still runs pre-0032 ACLs until M2.1/M2.2 (Appendix C).

### 7.5 RLS policy matrix (summary; full DDL in the migrations)

- Registry (programs/courses/campuses/year_levels/year_sections): SELECT to
  authenticated (+anon) — no client writes.
- profiles: SELECT all authenticated; UPDATE own.
- user_roles/enrollments: SELECT own (or teacher-of-section / moderator / admin).
- activities: SELECT = visible-to-viewer (§6.4) with soft-delete visibility rule;
  INSERT = self-publish rules; UPDATE/DELETE = owner-of-personal, section/course
  teacher, admin, plus `activities_update_own_student_report` (own student-
  reported section rows).
- activity_sources: SELECT follows activity visibility; INSERT only student_manual
  (own activity) / teacher_manual (taught); DELETE analogous; no UPDATE
  (immutable evidence).
- activity_reports: reporter CRUD-own + staff triage (guards enforce status
  transitions).
- community: posts/comments SELECT = non-deleted minus blocks (author sees own
  soft-deleted); INSERT author=caller; UPDATE/DELETE own (+ moderator/admin
  delete); images SELECT follows post, INSERT on own non-deleted post; likes
  unique-per-user with visible-target checks.
- content_reports: INSERT own status open; moderator/admin update/select-all;
  reporters see own.
- google_connections: SELECT/UPDATE own (guard: only status→disconnected).
- storage: community-images private; read all authenticated; write/update/delete
  only inside `auth.uid()` folder (`{uid}/{postId}/{filename}`).


Migration 0032 adds NO RLS policies and NO function bodies — it changes
FUNCTION EXECUTE privileges only (Appendix C). University-wide teacher
visibility of non-personal section activities and the privacy of personal
student activities are unchanged by it (verified: rpc_authorization_test T08 +
the 0019/0020 policy set re-run in the local environment).

### 7.6 Storage

One bucket `community-images` (private). Path convention `{auth.uid()}/{post_id}/{filename}`
(app uploads `.jpg` named by a millisecond timestamp; one image per post, position 1).
Reads use authenticated downloads (`downloadAuthenticated`) — no public URLs.

### 7.7 Edge Function contracts

All three live in `supabase/functions/<name>/index.ts` (Deno). Shared conventions:
JSON in/out; `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` from the function env
(never in the client); errors as `{status:"failed", error, message?}`.

| | classroom-import | classroom-sync | site |
|---|---|---|---|
| Verify JWT | list: NO (import action: YES, manual) | YES | NO (`--no-verify-jwt`, public pages) |
| Request | `{action:"list"\|"import", googleAccessToken, courseIds?, accountEmail?}` | `{googleAccessToken, accountEmail?}` | any method, path routes |
| Behavior | §6.3 | §6.3 | serves HOME_HTML / PRIVACY_HTML (static, from publish-branding drafts), 404 otherwise; Cache-Control public max-age=300 |
| Side effects | import RPC + google_connections stamp | upserts + google_connections status/last-sync | none |

`site` exists to host the OAuth consent screen's home/privacy URLs on the
project's own (authorized) Supabase domain — Google rejects branding URLs on
domains the project doesn't control.

### 7.8 Android repository layer (the client's exact wire behavior)

- `SupabaseClientFactory.createSupabaseClient(url, key)`: installs Auth, Postgrest,
  Storage, Functions; OkHttp engine from the Gradle dep; no custom session
  manager (Android default = SharedPreferences persistence).
- `SupabaseActivityRepository.getActivities()`: `activities` select
  `id,title,description,activity_type,due_at,estimated_effort_minutes,scope,
  verification_status,deleted_at,course:courses(id,code,title),activity_sources
  (provider)` filter `deleted_at IS NULL` order `due_at ASC` (no limit). Insert
  per §6.4; update = title/description/type/due/effort by id; delete = set
  `deleted_at`. `getMySections()`: enrollments join section+course, order
  enrolled_at.
- `SupabaseCommunityRepository`: feed = `feed_posts` (columns §7.2) order
  created_at DESC limit **50**; comments = `feed_comments` filter post_id order
  created_at ASC limit **200**; createPost/toggleLike/addComment/reportPost per
  §6.5 (all re-read canonical rows after writes).
- `SupabaseProfileRepository.getProfile()`: profiles + joins for display labels.
- `SupabaseClassroomConnectionRepository`: google_connections own row → state
  machine (NeverConnected/Connected/Revoked/Expired/Disconnected); disconnect =
  UPDATE status.
- `SupabaseClassroomImportRepository` / `SupabaseClassroomSyncRepository`: Edge
  Function invocations per §6.3 (session JWT auto-attached; Google token in body).
- `SupabaseSchoolDirectoryRepository`: registry loads (§5.7 columns), 10-minute
  in-memory cache; `programsForCampus`, `programLabel` (campus-suffix
  disambiguation), `normalizeCourseCode`, `looksLikeCourseCode` (§4.2),
  `sanitizeClassroomCourseName`; the course-catalog load skips rows with
  `external_course_id` set (student pickers show manual courses only, §6.2).
- `PostgrestJson`: runtime JSON parsing (no serialization codegen — AGP's Kotlin
  compiler doesn't run the plugin), `instantValue` with `+0000`→`+00:00` fallback.

### 7.9 Website data access

§5.7 — one month query + registry + enrollments + profiles + google_connections;
writes limited to the category correction UPDATE. supabase-js surface:
signInWithPassword / signUp / signOut / resend / getSession / onAuthStateChange /
from().select().eq().is().gte().lte().order().limit() / from().update().eq().select()
/ rpc().
## 8. Build, configuration & test

### 8.1 Toolchain (exact pins)

| Component | Version |
|---|---|
| AGP | 9.2.1 |
| Kotlin | 2.2.10 (compiler metadata ceiling 2.3.0 — the reason for the supabase pin below) |
| Gradle wrapper | 9.4.1, JDK 21 toolchain (auto-provisioned) |
| Compose BOM | 2026.02.01 |
| navigation-compose | 2.9.0 |
| lifecycle (runtime/viewmodel/compose) | 2.11.0 |
| activity-compose | 1.13.0 · core-ktx 1.19.1 |
| supabase-kt BOM | **3.6.0** (auth-kt, postgrest-kt, storage-kt, functions-kt) — 3.7/3.8 are built with Kotlin 2.4.0 metadata unreadable by Kotlin 2.2.10 |
| ktor-client-okhttp | 3.4.3 (the release supabase 3.6.0 is built against) |
| multiplatform-settings-no-arg | 1.3.0 (SharedPreferences-backed sessions + prefs) |
| androidx.credentials + play-services bridge | 1.5.0 |
| googleid | 1.1.1 |
| play-services-auth | 21.3.0 (Classroom consent) |
| kotlinx-serialization-json | 1.11.0 (runtime API only) |
| compileSdk / targetSdk / minSdk | 37 (release) / 36 / 26 |
| tests | junit 4.13.2 · kotlinx-coroutines-test 1.10.2 |

Website: no build at all — vendored `supabase.min.js` (supabase-js v2) and
`lucide.min.js`; any static server. Backend: Supabase CLI (`supabase db push`).

### 8.2 Environment & configuration (names + locations ONLY — never commit values)

- **`.env` at the project root** (git-ignored; parsed by `app/build.gradle.kts` at
  configuration time into `BuildConfig`):
  - `SUPABASE_URL` (required, must be https)
  - `SUPABASE_PUBLISHABLE_KEY` (required; the build FAILS on `sb_secret_…`
    keys, on legacy JWT keys carrying `service_role`, on control characters/`$`;
    values escaped into string literals)
  - `GOOGLE_SERVER_CLIENT_ID` (optional; must end `apps.googleusercontent.com`;
    empty ⇒ Google button shows the setup dialog instead of failing)
- **`client.json`** at the workspace root: the Google Cloud OAuth **Web
  application** client credentials download (contains a client SECRET — keep it
  out of the app, the repo, and any documentation; it is pasted into the Supabase
  Google provider settings only).
- **`local.properties`**: Android SDK path (machine-specific).
- **`supabase/.temp/`**: CLI link artifacts (project ref etc.).
- Edge Function secrets (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`) are injected
  by the platform.
- Demo teacher/student credentials: seeded by migration 20260101000900; documented
  in `WebView/README.md` (also hardcoded for the dashboard's demo-fill button).

### 8.3 Google OAuth setup (required for Google Sign-In & Classroom)

Per `docs/GOOGLE-SIGNIN.md` (authoritative setup guide):
1. Google Cloud Console: OAuth consent screen (External, app "Student Codex");
   create a **Web application** OAuth client with redirect
   `https://{project-ref}.supabase.co/auth/v1/callback` → client ID + secret.
2. **REQUIRED (not optional):** create an **Android** OAuth client in the SAME
   project with package `com.example.studentcodex` + the signing keystore's
   SHA-1 fingerprint (`gradlew signingReport`; every machine has its own debug
   keystore; add the release SHA-1 too). Without it Play services refuses with
   GMS code 13 before any account picker appears.
3. Supabase dashboard → Authentication → Providers → Google: enable with the Web
   client ID + secret.
4. `.env`: `GOOGLE_SERVER_CLIENT_ID={web client id}` and rebuild.
5. Branding URLs: home + privacy policy must be hosted on the project's own
   domain — that is exactly what the `site` Edge Function provides
   (§8.7/`publish-branding/STEPS-TO-PUBLISH.txt`, which also documents publishing
   the consent screen to production and the "unverified app" warning students
   see for sensitive Classroom scopes).

### 8.4 Android build & test commands (Windows host)

```powershell
.\gradlew.bat :app:compileDebugKotlin --console=plain
.\gradlew.bat :app:testDebugUnitTest          # unit suite
.\gradlew.bat :app:lintDebug                  # 0 errors expected
.\gradlew.bat :app:assembleDebug              # debug APK
```

**Unit test inventory** (app/src/test): AuthViewModelTest (largest — auth flows,
validation, google completion, classroom import during sign-up),
BeaconViewModelTest (state transitions incl. retry-recovery + editor),
CommunityViewModelTest, SettingsViewModelTest, HomeViewModelTest,
GuidanceViewModelTest, GuidanceOverlayControllerTest, ClassroomAutoSyncerTest,
DemoGuidanceEngineTest (7 rule/fallback tests), SupabaseClientFactoryTest,
ExampleUnitTest. Historical release-candidate count: 117 automated tests, 0 lint
errors. Instrumented: only the template ExampleInstrumentedTest.


### 8.5 Database workflow

- Apply: `supabase link --project-ref {ref}` then `supabase db push` (Option A,
  hosted — the project's actual path). Local stack (Option B, Docker) also works:
  `supabase start` / `supabase test db` / `supabase db reset`.
- **Never edit an applied migration** — add a fix migration (the project's db push
  history is clean; local == remote for 000000–002800; **002900–003200 are
  local-only and NOT yet pushed** — Appendix C).
- Tests (plain-SQL DO blocks; run via `supabase test db` or any psql):
  `supabase/tests/policies_test.sql` (23 scenarios T01–T23, 92 assertion guards —
  RLS enablement, anon denials, profile/user-role immutability, activity
  visibility/insert/verification, sources, reports, participants, posts/images/
  comments/likes ownership + anonymity-leak checks, blocking, storage, feed
  aggregation), `gc_source_identity_test.sql` (source-key convergence +
  composite-identity rejection), `phase_completion_test.sql` (53 assertions —
  seed sanity, Kirby visibility, report workflow, rate limits, google_connections
  guards, service-context upsert behavior, workload view), and
  `rpc_authorization_test.sql` (T01–T10 — migration 0032's suite: the three
  hardened RPCs reject anon/authenticated; service_role retains F2/F3; active
  teacher doors + 0031 domain gates unchanged; trigger chains and the
  service-role import door verified end-to-end).
- **Local test environment (2026-10-30 run — Appendix C):** rootless PostgreSQL
  17.11 with a replicated Supabase platform surface (roles, `auth` schema,
  `storage` schema), ALL 33 migrations applied in order. This was NOT the
  official `supabase start` Docker stack — Docker Desktop was unavailable in the
  development environment (it lacked the necessary administrative permissions).
  A portable-PostgreSQL mock of the Supabase platform was previously used to
  iterate migrations to green — the equivalent is any Postgres with the fixtures
  in the test files.
- **Honest test-status register (2026-10-30):** `rpc_authorization_test.sql`
  PASSED (exit 0) · `phase_completion_test.sql` PASSED (exit 0) ·
  `gc_source_identity_test.sql` PASSED with a temporary harness compatibility
  shim · `policies_test.sql` PARTIALLY PASSED (pre-existing fixture + T08.1
  failures, independent of 0032). Full detail: Appendix C. **Never summarize
  these results as "all tests passed."**

### 8.6 Website deployment

Static hosting: double-click `index.html`, `python -m http.server`, or any host.
Android embedding: copy the WebView/ contents to
`app/src/main/assets/webview/` and load
`file:///android_asset/webview/index.html` (documented in `WebView/README.md`).
Configuration is baked into `app.js` (Supabase URL + publishable key constants
at the top — copy from the live file).


### 8.7 Release engineering state

- `publish-branding/` holds the live copy drafts: HOMEPAGE.txt, PRIVACY-POLICY.txt
  (backing the `site` Edge Function output), and STEPS-TO-PUBLISH.txt (OAuth
  branding + production publish walkthrough — includes redeploying the function:
  `supabase functions deploy site --no-verify-jwt`).
- Release build: `isMinifyEnabled = false`, default proguard files; versionCode 1.
- **Email confirmation is OFF project-wide** (since 2026-10-24; the README
  documents flipping it back via `supabase config pull/push`; the hosted
  `[auth.rate_limit] email_sent = 2` cap is dashboard-managed, not config-push
  managed). **Teacher-verification history (deliberate, current testing
  configuration):** 0028 gated the teacher role RPCs on an OTP/magic-link `amr`
  claim with a dashboard verify-email card; 0029 moved to an emailed link →
  `site` function → verified-email gate and removed the typed-code path; 0030
  read `email_confirmed_at` from `auth.users`; **0031 replaced all of it with
  the `@parsu.edu.ph` domain gate** — the current flow has NO verification step
  (instant, email-free sign-up for school-domain addresses). The 0028–0030
  machinery remains as dormant fallback (migration headers;
  `WebView/README.md:108-143`). **The suffix check is not proof of mailbox
  ownership** — production-ready identity verification is roadmap Tier 2
  (M2.3, §10.3).

## 9. Acceptance criteria & verification

### 9.1 Functional acceptance (observable behavior a replica must reproduce)

**Auth:** cold start restores a session (≤2s gate, else signed-out); sign-up with
all fields creates the account, a profile with derived username, and section
enrollments; duplicate email surfaces the "already exists" message; Google
sign-in completes or shows its specific failure/setup states; guest mode enters
without network; sign-out returns to the gate and wipes the guidance transcript.

**Beacon:** filters show/hide correctly; date groups order newest-first with
Today/Tomorrow headers; creating an activity via the editor publishes it to the
section instantly (visible to a teacher account's dashboard calendar — verified
live 2026-10-28); edit/delete of own manual rows works; imported rows are
read-only (no edit affordances); undated items group last; due labels follow
§4.4's ladder; manual dates land at 23:59 Manila.

**Classroom:** import list shows the account's ACTIVE courses; import enrolls
courses (unknown → created); a subsequent sync imports coursework/announcements
with categories per §7.3; re-sync refreshes (no duplicates — same source keys);
teacher-corrected categories survive a re-sync; revoked/expired Google consent
flips the connection card to its specific note; auto-sync runs silently on app
open when toggled; the account is always the student's explicit choice.

**Community:** feed renders named + anonymous posts (anonymous shows no name
anywhere — server-nulls); like toggles round-trip through the server; comments
append and bump counts; photo posts upload (private bucket, authenticated
downloads) and render; posting >8/10min surfaces the rate-limit error; guests
get every disable state; reports submit with the 5 reasons.

**Guidance:** each rule's exact answer for its keywords; fallback for unknown
input; suggestions send as questions; the transcript is shared across entry
points and cleared on sign-out; chat head drags/docks/springs; edge panel pulls
open at ≥48dp; mode persists across restarts (Russhwolf keys §4.9); unread badge
counts and clears on open.


**Teacher dashboard:** sign-in (incl. demo button); sign-up with the
multi-select class-group picker (≤12 groups, chip display) + `@parsu.edu.ph`
domain gate → role grant → dashboard; non-teacher gate with activation card;
registry-backed comboboxes with search/keyboard support and campus→program
cascade; university-wide month query → correct day chips (≤3 + "+N more") with
the exact §5.5 palette; day dialog → activity sheet with date-bearing due label;
category picker only on taught sections, corrections save instantly, toast
feedback, chips re-color live, and survive re-syncs; legend/flag filters hide
rows everywhere at once; student-reported rows render dashed; past-due rows
render solid dark green with Done badges; refresh-on-return (>10s); mobile
breakpoints per §5.10.

### 9.2 Visual verification procedure

1. **Tokens first**: diff the replica's Color.kt/Type.kt/Shape.kt/Spacing.kt and
   styles.css `:root` against §3/§5.2 — every value must match exactly.
2. **Teacher website**: the live dashboard (the production Supabase project,
   reached through the workspace's configured URL) is its own reference — open it
   and the replica side by side at 1440×900 and 390×844; compare the sign-in card,
   header, filter bar, month bar, one busy week of chips, the day dialog, an
   activity sheet with the category picker, the legend, and the side panels.
   (The 2026-10-28 verification screenshots are preserved in the development
   environment, not the workspace.)
3. **Android**: run on a 1080×2400-class emulator; compare the four tabs, the
   guidance panel (both entry styles), the create-post sheet, and the editor
   sheet against §4's layouts and the §3 tokens. The development-window emulator
   UI dumps (bounds/text) are in the project's mirror folders (Appendix B).
4. Dark mode (Android system dark): spot-check Home/Beacon/Community cards and
   the guidance panel against §3.2.


### 9.3 Test-to-feature mapping

`policies_test` T01–T23 cover the RLS matrix (§7.5) including the anonymity-leak
(T17) and storage (T19) rules; `gc_source_identity` covers dedup convergence;
`phase_completion` covers seeds, visibility, rate limits, connection guards, and
the service-context upsert; `rpc_authorization_test` T01–T10 covers migration
0032's privilege surface (the three hardened RPCs, the two active teacher doors
with the 0031 domain gate, the auth-trigger chains, and the service-role import
path — Appendix C). Android unit tests cover every ViewModel's state machine and
the guidance rules. No Compose UI tests exist beyond the template. **Do not
treat a green SQL run as proof that the Android UI, the web dashboard, or the
external Google integrations work end to end** — the SQL suites verify the
database contract only.

## 10. Known limitations, deliberate decisions & planned work

### 10.1 Deliberate decisions (reproduce, don't "fix")

- **Instant-publish section activities** — no approval queue anywhere (a student
  report IS the activity; migration 0015).
- **Online-first Android app** — no Room, no WorkManager; one-shot loads plus a
  silent on-resume refresh on Beacon.
- **Transit-only Classroom tokens** — minted per sync via on-device consent,
  never stored.
- **Standalone website** — no framework, no build step, no dark mode.
- **University-wide teacher visibility** of non-personal section activities
  (migration 0019) — intentional; personal student activities remain private to
  their creator, invisible to everyone else including teachers.
- **DB-side classification with locked corrections** —
  `suggest_activity_category` + `category_locked`/`category_locked_by`.
- **Guest mode is a UI state**, not fake data; guidance is deterministic with an
  honest fallback; no pull-to-refresh anywhere in the Android app.
- **Teacher registration is domain-gated self-service (current testing
  configuration)** — email confirmation is intentionally OFF; the
  `@parsu.edu.ph` suffix check (0031) is an eligibility gate, NOT proof of
  mailbox ownership. This is a demonstration configuration, distinct from
  production-ready identity verification (M2.3). Do not change the confirmation
  settings or the active registration functions without an explicit decision.
- **Classroom sync is client-triggered** (app open / manual / import), not a
  continuously running background synchronization service; no push
  notifications and no Pub/Sub exist in any Edge Function or migration.
- **Student-reported entries are distinguishable by their source label**; the
  system does not guarantee that every real-world activity is reported, and
  title matching does not automatically prevent every manual duplicate.
- **Classroom course and coursework identifiers are shared, not per-student** —
  stable source identities mean any student syncing the same coursework
  converges on the same canonical activity, and re-importing an existing source
  UPDATES the shared record rather than creating another activity.

### 10.2 Known limitations & shipped gaps (verified 2026-10-31)

- **Anonymous posting — PARTIALLY IMPLEMENTED:** the composer's `Post
  anonymously` switch never reaches the repository — the ViewModel drops the
  flag and `SupabaseCommunityRepository.createPost` hard-wires
  `is_anonymous=false` (comments likewise). The DB, feed views, and seed data
  fully support anonymity.
- **Comments — PARTIALLY IMPLEMENTED:** flat single-level in the app (no reply
  threading UI, no comment-likes UI) although the schema/views support depth-5
  nesting and comment likes.
- **One image per post in the app** (schema allows 3) — KNOWN LIMITATION.
- **No effort field in the manual editor** — effort renders only on imported
  rows — KNOWN LIMITATION.
- **Dead resources:** the unused `comments_demo_note` string and the legacy
  `.msel/.pick-chip` CSS classes — KNOWN LIMITATION (cleanup candidate).
- **Profile footnote — CORRECTED in v2.2:** the build-era string
  `profile_version_note` (`strings.xml:333`) still exists in resources but is
  rendered by NO screen; the v2.1 claim that the Profile page "shows" it is
  outdated (`ProfileScreen.kt:59-148` renders identity only).
- **`WebView/teacher/*.tsx` — CORRECTED in v2.2:** that folder does NOT exist
  in the repository (verified twice on 2026-10-31); the v2.1 claim is outdated.
  The vanilla dashboard in `WebView/` is the only dashboard.
- **Teacher workload summaries & proposed-deadline preview — PLANNED, not
  built:** zero references in `app.js`; the DB-side view
  `section_workload_daily` exists but no client consumes it.
- **Calendar coverage is not guaranteed:** the dashboard renders only what has
  been recorded (Classroom imports + manual/student entries); it does not
  promise complete university-wide activity coverage.
- **Migration 0032 — IMPLEMENTED, VERIFICATION INCOMPLETE:** applied and tested
  locally only; hosted deployment pending (Appendix C; M2.1).
- **SQL test fixtures:** `policies_test.sql` (campus_id fixture + T08.1) and
  `gc_source_identity_test.sql` (campus_id fixture) pre-date migration 0012 —
  documented in Appendix C; the test files were intentionally NOT modified by
  the documentation task (M1.2/M1.3).
- **Edit/delete/correction limits (actual):** students edit/delete only their
  own manual rows (soft delete; imported rows read-only); category corrections
  are restricted to sections the teacher teaches and lock only the category —
  no bulk edit, no reassignment, no delete of others' entries.

### 10.3 Development roadmap (v2.2 — rebuilt around verified reality)

Priorities, not deadlines: no dates are promised and nothing here is approved
for implementation. Each milestone records what exists, what is missing, and
how completion would be verified. "Demo" marks competition/demo requirements;
"Production" marks future production requirements.

#### Tier 1 — Existing implementation & verification gaps

- **M1.1 Complete or remove anonymous community posting.**
  - Objective: make the anonymity switch honest or remove it.
  - Current state: PARTIALLY IMPLEMENTED — UI switch present
    (`CommunityScreen.kt:347-360`, `ComposerUiState.isAnonymous`), flag dropped
    by `CommunityViewModel.kt:166`, hard-wired false in
    `SupabaseCommunityRepository.kt:149` (comments `:110`).
  - Missing: plumbing `isAnonymous` through the repository interface and the
    Postgrest insert — or the UI removal.
  - Files: `ui/community/CommunityViewModel.kt`, `data/repo/Repositories.kt`,
    `data/supabase/SupabaseCommunityRepository.kt`,
    `ui/community/CommunityScreen.kt`.
  - Dependencies: none.
  - Acceptance: an anonymous post renders with no author name anywhere (feed
    views already null it server-side); policies_test T17 stays green.
  - Tests: `CommunityViewModelTest` + manual feed check. **Demo.**
- **M1.2 Modernize `policies_test.sql` (fixture + T08.1).**
  - Objective: the suite runs green against the current 33-migration schema.
  - Current state: PARTIALLY PASSED — programs fixture lacks `campus_id`
    (`:30-38`, fails after 0012 NOT NULL); T08.1 (`:353-357`) expects 42501 but
    `guard_activity_insert()` (0015) raises P0001, aborting the DO block.
  - Missing: fixture campus_id + a T08.1 expectation fix (catch P0001 with the
    0015 message, or assert the guard's error).
  - Files: `supabase/tests/policies_test.sql`.
  - Dependencies: none. Acceptance: exit 0 on a fresh 33-migration database.
  - Tests: the suite itself. **Production** (test hygiene).
- **M1.3 `gc_source_identity_test.sql` fixture (campus_id).**
  - Objective: same as M1.2 for this suite — remove the temporary harness shim.
  - Current state: PASSED only WITH the shim (fixture `:36-37` lacks campus_id).
  - Missing: campus_id in the fixture. Files: the test file. Dependencies: none.
  - Acceptance: exit 0 without the shim. **Production** (test hygiene).
- **M1.4 Android current-build visual re-verification.**
  - Objective: refresh the §9.2 step-4 evidence on an emulator.
  - Current state: visual claims rest on exact tokens + code + demo-era dumps;
    no current-build screenshots exist (Appendix B uncertainty 1).
  - Missing: one emulator pass (4 tabs, guidance both styles, composer, editor)
    against §3/§4.
  - Files: none (verification only). Dependencies: emulator host available.
  - Acceptance: screenshots archived; §9.2 step 4 signed off. **Demo.**
- **M1.5 Edge Function live-OAuth re-verification.**
  - Objective: re-exercise `classroom-import`/`classroom-sync` against real
    Google in the current state.
  - Current state: verified live during development and by SQL-level door tests
    (T08); NOT re-exercised end-to-end in the 2026-10-30 run (Appendix C).
  - Missing: one live import + sync cycle from a real account.
  - Files: none (verification only). Dependencies: Google OAuth consent screen,
    a test account with Classroom courses.
  - Acceptance: import summary + sync summary recorded; no source changes.
  - **Demo.**

#### Tier 2 — Security & production-readiness

- **M2.1 Deploy migrations 0029–0032 to the hosted project.**
  - Objective: bring the hosted database to the locally verified state.
  - Current state: hosted at 0028; 0029–0032 local-only (Appendix C).
  - Missing: `supabase db push` (or Dashboard SQL editor) + the deploy order
    confirmation (0029→0032 are additive privilege/config migrations).
  - Files: `supabase/migrations/20260101002900…003200*.sql`.
  - Dependencies: M1.2/M1.3 NOT required (independent), but a fresh local
    green run right before push is prudent.
  - Acceptance: hosted migration list shows 33 applied; dashboard sign-up flow
    unchanged (0031 gate already local-verified).
  - Tests: hosted ACL probe (below). **Production.**
- **M2.2 Post-deployment hosted verification of 0032.**
  - Objective: prove the hardening on the hosted project.
  - Current state: pre-0032 ACLs verified executable by authenticated
    (non-mutating probes, 2026-10-29/30).
  - Missing: re-run the probes — expect 42501 for all three RPCs from an
    authenticated session; teacher registration E2E; student import E2E.
  - Files: `audit-f123/hosted-acl-probe.mjs` (probe script, local sandbox).
  - Dependencies: M2.1. Acceptance: probe log shows 42501s; no functional
    regressions. **Production.**
- **M2.3 Teacher eligibility verification for production.**
  - Objective: decide and implement production identity verification.
  - Current state: UNRESOLVED — the domain suffix is not mailbox ownership;
    email confirmation is OFF (§8.7); the 0028–0030 machinery is dormant
    fallback.
  - Missing: a decision (email confirmation ON with institutional mail,
    SSO/LDAP, or manual allowlist) + its implementation.
  - Files: `supabase/config.toml` (auth settings), teacher RPC migrations.
  - Dependencies: institutional policy input.
  - Acceptance: a production sign-up cannot be completed by an attacker who
    controls a non-institutional mailbox. **Production.**
- **M2.4 Repository hygiene: commit the working tree.**
  - Objective: make the product's history real.
  - Current state: 2 commits; the entire current product (dashboard rework,
    migrations 0021–0032, 2 Edge Functions, 4 Kotlin files, PLAN.md) is
    uncommitted (61-entry porcelain + ~90 untracked dev-script debris files).
  - Missing: a `.gitignore` for the debris (adb/launch/diag scripts, logcat
    dumps, screenshots, `crash.txt`, `.backup-*`), then a clean commit of the
    source tree.
  - Files: `.gitignore`, everything. Dependencies: none.
  - Acceptance: `git status` clean-ish (only intentional untracked remains);
    build + tests still green. **Production.**
- **M2.5 Credential hygiene.**
  - Objective: keep secrets out of the repository permanently.
  - Current state: `client.json` (live OAuth client secret) and `.env` sit
    untracked at the root; PLAN.md documents locations only.
  - Missing: confirm `.gitignore` covers them before M2.4's commit; rotate the
    OAuth client secret if it was ever exposed.
  - Dependencies: M2.4. Acceptance: `git ls-files` shows neither file.
  - **Production.**

#### Tier 3 — Remaining product functionality

- **M3.1 Offline cache + write synchronization.**
  - Objective: the planned offline layer.
  - Current state: PLANNED — design doc only (`docs/OFFLINE-SYNC.md`:
    "Nothing on this page is claimed to be running today"); app is online-first
    with zero Room/WorkManager references (verified by grep).
  - Missing: Room entities/DAOs, outbox, conflict rules, sync worker.
  - Files: `app/build.gradle.kts`, new `data/local/…`, repositories.
  - Dependencies: schema freeze (M2.4). Acceptance: the OFFLINE-SYNC contract
    (exactly-once delivery, conflict rules) demonstrated in a unit + instrumented
    test. **Production.**
- **M3.2 Teacher workload summaries + proposed-deadline preview.**
  - Objective: the analytics features from the original product vision.
  - Current state: PLANNED — `section_workload_daily` view exists
    (security_invoker), zero client consumers.
  - Missing: dashboard panels consuming the view; the proposed-deadline preview
    interaction.
  - Files: `WebView/app.js`, `styles.css`. Dependencies: none.
  - Acceptance: workload card renders per filtered cohort; preview shows
    affected sections for a candidate date. **Demo + Production.**
- **M3.3 Moderation queue UI.**
  - Objective: give moderators the triage surface the DB already supports.
  - Current state: BUILT at DB level (`content_reports` + guard + policies,
    T21); no UI anywhere.
  - Missing: a moderator view (list/open/action/dismiss) — web or Android.
  - Files: `WebView/app.js` or a new Android screen. Dependencies: none.
  - Acceptance: T21 semantics unchanged; a moderated post disappears from
    feeds. **Production.**
- **M3.4 Community completeness.**
  - Objective: close the §10.2 community gaps.
  - Current state: PARTIALLY IMPLEMENTED (anonymity switch dead, flat comments,
    1 image, no comment-likes UI).
  - Missing: M1.1 wiring (or removal), reply threading + comment likes UI,
    3-image support.
  - Files: `ui/community/*`, `data/supabase/SupabaseCommunityRepository.kt`.
  - Dependencies: M1.1 decision. Acceptance: policies_test T13–T17 green with
    the new UI paths. **Production.**
- **M3.5 Push notifications / reminders.**
  - Objective: deadline reminders.
  - Current state: DEFERRED — Settings shows an honest placeholder row
    (`SettingsScreen.kt:330-341`, non-clickable); no FCM anywhere.
  - Missing: FCM integration, server-side scheduling, user preferences.
  - Files: `AndroidManifest.xml`, new service, Edge Function.
  - Dependencies: production hosting decisions. **Production.**
- **M3.6 Profile editing beyond school details.**
  - Objective: name/username editing etc.
  - Current state: PLANNED — Profile is identity-only (§4.8); username is
    immutable by guard.
  - Missing: the editing UI + guard relaxation decisions.
  - Files: `ui/profile/*`, `guard_profile_update`. Dependencies: none.
  - Acceptance: guard rules still hold. **Production.**

#### Tier 4 — Reliability & integration improvements

- **M4.1 Google Classroom event-driven synchronization (Pub/Sub push).**
  - Objective: sync without opening the app.
  - Current state: NOT IMPLEMENTED and correctly absent from this spec — all
    sync is client-triggered (§6.3); no Pub/Sub in any function/migration
    (grep-verified).
  - Missing: a public ingest endpoint, Google Pub/Sub subscription
    management, verification of Google's signed push, idempotent processing on
    top of the existing source-key upsert.
  - Files: new Edge Function + migrations. Dependencies: Google Cloud project
    ownership, OAuth verification (sensitive scopes). Acceptance: a coursework
    change appears without any client action. **Production.**
- **M4.2 Android WebView embedding of the teacher dashboard.**
  - Objective: the README's documented plan — ship the dashboard inside the
    app.
  - Current state: PLANNED — no `assets/webview` in the app; no WebView usage
    in sources (verified).
  - Missing: asset copy + WebView wiring + session strategy.
  - Files: `app/src/main/assets/webview/`, a new screen. Dependencies: none.
  - Acceptance: dashboard opens in-app against the same project. **Demo
    (optional) / Production.**
- **M4.3 Test-environment parity.**
  - Objective: a reproducible official local stack.
  - Current state: the 2026-10-30 run used a rootless PostgreSQL 17.11
    replicated surface because Docker Desktop was unavailable (no admin
    permissions) — not the official `supabase start` stack (Appendix C).
  - Missing: either Docker availability or permanent documentation of the
    rootless harness (the pgsandbox fixtures).
  - Files: `pgsandbox/` (local sandbox). Dependencies: machine permissions.
  - Acceptance: a documented, repeatable environment for future migration
    testing. **Production (tooling).**

#### Tier 5 — Release preparation & final delivery

- **M5.1 Release engineering.**
  - Objective: a shippable APK.
  - Current state: versionCode 1, minify off, default proguard; no signing
    config for release.
  - Missing: signing keystore workflow, versioning policy, minify/shrink
    decision, Play Store listing material.
  - Files: `app/build.gradle.kts`. Dependencies: M2.4.
  - Acceptance: a signed release build installs and runs. **Production.**
- **M5.2 OAuth consent-screen publishing.**
  - Objective: remove the "unverified app" warning for students.
  - Current state: STEPS-TO-PUBLISH.txt documents the walkthrough; the consent
    screen is in testing; branding URLs served by the `site` function.
  - Missing: executing the publish steps (verification for sensitive Classroom
    scopes).
  - Dependencies: M5.1 (domain/branding). Acceptance: no unverified-app
    interstitial for new student accounts. **Production.**
- **M5.3 Production data decisions.**
  - Objective: decide the fate of demo seeds and demo accounts.
  - Current state: demo teacher/student accounts + fixed-UUID seeds are live on
    the hosted project (documented in `WebView/README.md`); the Android fake
    repositories exist for unit tests only.
  - Missing: a cleanup/retention decision per account type.
  - Dependencies: M2.1. Acceptance: production project contains only intended
    data. **Production.**
- **M5.4 Final acceptance run + documentation freeze.**
  - Objective: the §9 checklist executed end to end on the release build, then
    this document re-baselined (v2.3) from the verified state.
  - Current state: §9 was last fully exercised 2026-10-28 (browser) with SQL
    re-verification 2026-10-30 (Appendix C).
  - Missing: the full pass on the release build.
  - Dependencies: M5.1, M2.2. Acceptance: §9.1 checklist green; Appendix B/C
    refreshed. **Demo + Production.**

## Appendix A — Superseded decisions (HISTORICAL — do NOT follow)

> This appendix records the original plan's decisions that changed during the
> October 2026 build. It exists so history is not lost and so no one mistakes an
> obsolete instruction for a requirement. **The current implementation (§1–§10) is
> the only authority.**

| Original plan (v1) | What actually shipped | Why it changed |
|---|---|---|
| Teacher website: React + TypeScript + Vite + supabase-js | Standalone vanilla HTML/JS/CSS in `WebView/` with vendored libraries (an interim React prototype existed — its `.tsx` sources still sit unused in `WebView/teacher/`) | shippable with zero build; embedding in the Android WebView assets; same RLS model |
| Android local cache: Room + sync outbox + WorkManager (Phase 4/5) | Online-first: no Room, no WorkManager; one-shot loads + on-resume refresh | the product's data lives server-side and the MVP never needed offline; the offline design is preserved as docs/OFFLINE-SYNC.md for the planned phase |
| Five bottom tabs including Guidance | Four tabs (Home/Beacon/Community/Settings) + floating Guidance overlay (chat head / edge panel) + pushed Profile route | guidance is ambient help, not a destination; the overlay rides every page |
| Student reports go to a pending `activity_reports` queue for teacher matching/confirmation; manual candidate matching with confirmation prompts | Instant publish: students create section activities directly (`student-reported`); the reports machinery survives only at the DB level (migration 0015 drained the queue) | the approval loop added friction with no moderation capacity behind it |
| Community: approval-based publishing, nested replies with automatic @references, edit UI, blocking UI, moderation queues | Instant publish; flat comments; report-only moderation; blocking exists only at the DB/RLS layer | MVP scope; privacy-critical paths (RLS) built first, UI later |
| Token storage on device for Classroom sync | Transit-only tokens minted per sync via on-device consent | security posture — revocation is immediate, nothing to leak |
| Dynamic-color-first theming | Dynamic color opt-in, OFF by default | brand consistency in demos/screenshots |
| `section_workload_daily` driving a teacher workload view | View exists; no client uses it yet | dashboard shipped calendar + corrections first; analytics is planned work |
| compileSdk 36.1 | compileSdk 37 (release) | androidx.core 1.19.1 + lifecycle 2.11.0 require 37; target stays 36 |
| 0020: teacher sign-up is identity-only (no class groups; `teacher_signup_global` grants university-wide access with zero enrollments) | Sign-up carries the multi-select class-group picker again (≤12 groups); role grant via `teacher_signup_multi(p_groups)` / `teacher_signup_global` (0031-era) | teachers need taught-section enrollments — category corrections are RLS-restricted to taught sections (§5.6); the 0031 domain gate made instant email-free sign-up acceptable for the demo configuration |
| 0028: OTP/magic-link email verification gates the teacher role RPCs; dashboard verify-email card (typed-code fallback) | `@parsu.edu.ph` domain gate only (0031); verification machinery dormant; no verification step in the UI | demo-grade friction removal while keeping a server-side eligibility gate; production identity verification remains roadmap M2.3 |


**Phase history in one paragraph** (from the Development Chronicle, 29 tracked
work packages, 117 unit tests, 33 migrations, 0 lint errors): Phase 0–1
foundation and design system → Phase 2 database with RLS test-driven in a
portable-Postgres mock → Phases 3–5 real auth, manual activities, dedup →
Phase 6 Classroom integration (import + sync Edge Functions) → visual-precision
passes and the floating assistant restructure → hardening and release candidate
(chronicle record no. 1, 24 October 2026) → teacher dashboard build-out
(standalone WebView), registry/teacher sign-up, student self-publish, category
corrections with lock-through-sync, classifier fixes (migrations 0023–0026),
and due-label/indicator polish through 28 October 2026 → teacher email
verification evolution (migrations 0028–0031, 29–31 October 2026: OTP gating →
emailed link → `email_confirmed_at` → `@parsu.edu.ph` domain gate) → F1/F2/F3
RPC execute hardening (migration 0032, 30–31 October 2026 — locally verified,
Appendix C; hosted deployment pending).

## Appendix B — Evidence & uncertainty register

**How this spec was grounded (v2 — 2026-10-28):**

- **Source-verified:** every Android Kotlin file under `app/src/main` (all screens,
  ViewModels, components, theme, data layer, domain), `AndroidManifest.xml`,
  `build.gradle.kts`, `libs.versions.toml`, `strings.xml`; all of `WebView/`
  (index.html, app.js 95,923 B byte-verified at the time, styles.css, README); the
  then-current 27 migrations + 3 test files; all 3 Edge Functions; docs/ (PRD,
  ARCHITECTURE, ADR-001, ADR-002, GOOGLE-SIGNIN, OFFLINE-SYNC);
  `School_Details/`, `publish-branding/`, `supabase/README.md`.
- **Browser-verified (live, against the production Supabase project):** teacher
  dashboard sign-in (demo credentials), October 2026 calendar rendering with real
  data, day dialog (Oct 9 — "Group activity" classified Activity, the migration
  0026 behavior confirmed live), full-content activity sheet (Qwk4-5 —
  Classroom-imported + Done badges, date-bearing due label "due Oct 2, 7:59 AM"),
  the category correction picker on a taught section (six pills + persistence
  hint), legend filter (22→5 chips, "17 HIDDEN BY CATEGORY FILTERS" status),
  combobox open/search, mobile 390×844 layout, side panels (11 screenshots
  captured — they remain in the development environment's storage, not the
  workspace; the live site itself is the durable visual reference). Icon
  rendering during that verification used a CDN build of the same Lucide library
  (the vendored file exceeds the file-transfer cap) — visually equivalent, but
  the vendored `lucide.min.js` remains the runtime truth.
- **Emulator evidence (development window, demo-era data):** uiautomator hierarchy
  dumps (24 captures: Home, Guidance panel welcome + conversation, Community feed,
  create-post sheet incl. photo states, system photo picker, Settings with both
  assistant styles, Profile) and screenshots — geometry (1080×2400, bottom-nav
  bounds), exact strings, and content-descs match the current code; these predate
  the live-data era, so content shown in them ("Demo data - posting arrives in
  Phase 9") reflects the demo repositories of that time, not current behavior.

**How v2.2 was grounded (2026-10-31 re-audit):**

- **Full-tree re-audit through the workspace bridge while healthy** (308 files,
  92 directories, zero tool failures): `.plan/PLAN.md` re-read in full; the
  Android Kotlin tree re-inventoried (all file sizes); `WebView/` verified to
  contain EXACTLY the vanilla files — README.md, `app.js` (111,550 B, 2477
  lines), `index.html` (1,204 B), `styles.css` (47,522 B), and the two vendored
  libraries — with NO `teacher/` subfolder (the v2.1 stale claim, removed);
  all 33 migrations inventoried with purposes and tracked/untracked status; the
  three Edge Functions re-read; `supabase/config.toml` auth settings re-checked
  (`[auth.email] enable_confirmations = false`; `[auth.rate_limit] email_sent
  = 2` hosted-only); the four SQL test files re-read including the new
  `rpc_authorization_test.sql`; git state captured (2 commits; 61-entry
  porcelain status; PLAN.md itself an uncommitted +2002/−702 rewrite of the
  committed original).
- **Local test execution (2026-10-30):** all 33 migrations applied to a rootless
  PostgreSQL 17.11 replicated-Supabase surface; the four SQL suites run — exact
  results and limitations in Appendix C.
- **Static inspection:** migrations 0029/0030/0031/0032 contents; the current
  `WebView/README.md` registration-flow documentation; the bridge activity
  journal (every prior tool run, who/what/result).

**Residual uncertainties (could not be fully established):**

1. **Current-build Android runtime rendering** was not re-screenshot (no emulator
   session this pass); Android visual claims rest on the exact theme tokens
   (§3), layout code (§4), and the demo-era dumps/screenshots. Residual risk:
   pixel-level nuances (e.g., final paddings after later refactors) — re-verify
   per §9.2 step 4 when an emulator is available (M1.4).
2. **Google flows on a fresh device** (consent sheet wording, account-chooser
   variants) depend on the Google Play services version; the code paths are
   specified exactly, the Google-rendered chrome is not.
3. **Supabase dashboard settings** (provider toggles, confirmation off,
   authorized domains) are configuration state, not code — documented as facts
   in §8.3/§8.7 but not reproducible from this file alone.
4. The **auth trigger's exact error surfaces** (unique_violation fallback path in
   username claiming) are covered by tests but were not exercised live this pass.
5. The **exact conditional wiring between `teacher_signup_global` and
   `teacher_signup_multi` at the current sign-up form** was established from the
   2026-10-31 audit + README (`app.js:2009/2058/2059`), not by re-reading the
   live `app.js` line-by-line — the local mirror predates the 0029–0031 rework.
   Re-verify §5.3's sign-up paragraph against the live file before relying on it
   for reimplementation.
6. The **v2.1 addendum block** (the 80-line 2026-10-29 edit documenting the
   0028-era verification flow) was superseded by this rewrite rather than
   merged; if any undocumented 0028-era detail matters, recover it from git
   history once the working tree is committed (M2.4).

**Sensitive material intentionally excluded:** all credential VALUES (Supabase
publishable key, service-role key, Google client secret in `client.json`, demo
passwords, the authoring machine's SHA-1 fingerprint). Their locations and
handling rules are documented in §8.2/§8.3. `client.json` at the workspace root
contains a live OAuth client secret — treat it as a credential file: never commit,
never copy into docs, rotate if exposed.

---

## Appendix C — F1/F2/F3 RPC authorization hardening — test execution report

**What changed (migration `20260101003200_rpc_execute_hardening.sql`, 71 lines):**
a REVOKE-only privilege hardening addressing three previously identified SECURITY
DEFINER RPC authorization issues. **No function body was modified.**

- **F1** (lines 43-45): `revoke execute on function public.teacher_signup(uuid,
  integer, uuid, uuid) from authenticated;` — the legacy single-group door let
  ANY signed-in account self-grant the teacher role (its only gate was
  `auth.uid() is not null`); it has had no caller since the dashboard stopped
  calling it (0020 era).
- **F2** (lines 47-49): `revoke execute on function
  public.import_student_classroom_courses(uuid, jsonb) from authenticated;` —
  the RPC's own header always claimed service-context-only; its sole caller is
  the `classroom-import` Edge Function, which manually verifies the caller's
  session JWT and invokes the RPC with the service key.
- **F3** (lines 51-53): `revoke execute on function
  public.enroll_student_courses(uuid, uuid, integer, uuid, jsonb) from
  authenticated;` — the only callers are the two `auth.users` triggers
  (`handle_new_user`, `handle_user_profile_sync`) running in definer context
  (`auth.uid()` NULL) plus service-role contexts.
- service_role grants preserved/re-asserted for F2/F3 (lines 57-60);
  belt-and-braces re-assertion of creation-time revokes from `public`+`anon`
  for all three (lines 63-68); active teacher registration functions
  (`teacher_signup_global`, `teacher_signup_multi`) left byte-identical with
  their 0031 domain gates.

**Execution environment (2026-10-30):** rootless PostgreSQL 17.11 with a
replicated Supabase platform surface (roles, `auth` schema, `storage` schema);
ALL 33 migrations applied in order. This was NOT the official `supabase start`
Docker stack — Docker Desktop was unavailable in the development environment,
which lacked the necessary administrative permissions. **The hosted Supabase
project was not touched: migration 0032 has NOT been deployed to the hosted
project** (hosted state: migrations 000000–002800 applied; 0028 pushed live
2026-10-29 04:45 UTC).

**Results (exact — never summarize as "all tests passed"):**

| Test | Result |
|---|---|
| `supabase/tests/rpc_authorization_test.sql` | **PASSED — exit code 0** (T01–T10) |
| `supabase/tests/phase_completion_test.sql` | **PASSED — exit code 0** |
| `supabase/tests/gc_source_identity_test.sql` | **PASSED — with a temporary harness compatibility shim** (fixture pre-dates migration 0012's `campus_id NOT NULL`) |
| `supabase/tests/policies_test.sql` | **PARTIALLY PASSED — known fixture and T08.1 failures** |

**Verified through execution (local):**

- Migration 0032's privilege state (T04): `anon` AND `authenticated` hold no
  EXECUTE on the three RPCs (PUBLIC inheritance included).
- The three RPCs reject execution by `authenticated` (42501) — T01–T03.
- `service_role` retains F2/F3 execute (T06); the Edge-Function-equivalent
  service-role import door works end-to-end, idempotently, with the
  external_course_id link and enrollment (T08).
- The student sign-up trigger chain is unaffected (T07 — definer context).
- Active teacher registration unchanged: `teacher_signup_global` /
  `teacher_signup_multi` still execute for `authenticated` (T05); the 0031
  domain gate rejects non-`@parsu.edu.ph` callers with `SCHOOL_EMAIL_REQUIRED`
  and grants no role (T09, case-insensitive verified with a mixed-case
  address); school-domain callers succeed (T10).
- University-wide teacher visibility of non-personal section activities
  remains intact; personal student activities remain private from teachers.

**Verified through static inspection only:** the migrations' contents
(0029–0032), the tracked/untracked inventory, and `config.toml` auth settings.

**Verified in the hosted environment (non-mutating probes, 2026-10-29/30):**
the hosted project's CURRENT pre-0032 ACL state — all three RPCs were
executable by an authenticated session there (input-validation errors, not
privilege errors). The fix's hosted effect is therefore NOT yet verified
(blocked on M2.1/M2.2 deployment).

**Known failures & limitations (documented; the test files were intentionally
NOT modified by the documentation task — they are outstanding plan items
M1.2/M1.3):**

- `policies_test.sql` fixture inserts `public.programs` without `campus_id`
  (lines 30-38) — incompatible with migration 0012's NOT NULL; fails on any
  database migrated past 0012.
- `policies_test.sql` T08.1 (lines 353-357) expects SQLSTATE `42501`
  (`insufficient_privilege`) for a non-member student's section-activity
  INSERT, but since migration 0015 `guard_activity_insert()` raises `P0001`
  (`raise_exception`, "requires the creator to be enrolled in that section") —
  the `exception when insufficient_privilege` handler does not catch it and the
  DO block aborts. **Reproduced with AND without 0032's revokes (control
  rebuild) — pre-existing and independent of the migration.**
- `gc_source_identity_test.sql` has the same 0012 fixture issue without the
  temporary harness shim (no campus_id in its fixture, lines 36-37).
- The Edge Functions were NOT fully exercised against real Google OAuth during
  this SQL test run.
- The environment was a replicated surface, not the official `supabase start`
  Docker stack (Docker Desktop unavailable — no administrative permissions).

**Evidence classification for the hardening claims:**

| Claim | Class |
|---|---|
| 0032 privilege state; the three RPCs reject anon/authenticated; service_role retention; teacher doors + domain gates; trigger chains; import door | Verified through actual execution (local, 2026-10-30) |
| 0028–0032 migration contents; tracked/untracked state; config.toml auth settings | Verified through static inspection (2026-10-31) |
| Hosted migration state 000000–0028 applied; hosted pre-0032 ACLs executable by authenticated | Verified in the hosted environment (non-mutating probes) |
| 0032's effect on the hosted project | NOT TESTED (pending M2.1/M2.2) |
| Edge Functions against real Google OAuth (this pass) | NOT TESTED |
| Official Docker local stack | Blocked by environment limitations (no admin permissions for Docker Desktop) |

---

*End of the Student Codex Replication Specification. Predecessor documents: the
original build plan (v0, 23 October 2026), the reconciled plan (v1, 28 October
2026, with inline STATUS notes), and the v2/v2.1 replication specification
(28–29 October 2026) — superseded by this file; their decisions are preserved
in Appendix A. Document history: v2 (28 Oct 2026) → v2.1 (29 Oct 2026, teacher
email-verification addendum, migration 0028) → **v2.2 (31 Oct 2026, migrations
0029–0032, honest test-status register, corrected stale claims, reality-based
roadmap).***
