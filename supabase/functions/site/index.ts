// ============================================================================
// Student Codex Edge Function - site
//
// Serves the app's PUBLIC WEB PRESENCE (home page + privacy policy) on the
// project's own supabase.co domain, which is an AUTHORIZED DOMAIN in the
// Google Cloud Console OAuth consent screen. Google refuses branding URLs
// hosted on domains the project does not control (e.g. sites.google.com ->
// "Missing domain: google.com"), so both pages live here instead.
//
// Routes (any HTTP method):
//   /functions/v1/site            -> home page
//   /functions/v1/site/home       -> home page
//   /functions/v1/site/privacy    -> privacy policy
//   anything else                 -> 404
//
// Deployed with --no-verify-jwt: these are public marketing/legal pages,
// there is nothing session-gated here. Content is static HTML generated
// from the publish-branding/ drafts (kept ASCII-safe in source).
// ============================================================================

const PROJECT_REF = "wzhkfhijjwhteqkrlzfm";
const PRIVACY_URL = `https://${PROJECT_REF}.supabase.co/functions/v1/site/privacy`;
const SUPPORT_EMAIL = "kirbypaladan24@gmail.com";

const STYLE = `
  :root { --ink:#1e293b; --sub:#475569; --accent:#0d9488; --line:#e2e8f0; }
  * { box-sizing:border-box; }
  body { margin:0; font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif; color:var(--ink); background:#f8fafc; line-height:1.65; }
  .wrap { max-width:720px; margin:0 auto; padding:48px 24px 40px; }
  header.hero { border-bottom:3px solid var(--accent); padding-bottom:24px; margin-bottom:32px; }
  h1 { font-size:2rem; margin:0 0 6px; letter-spacing:-0.02em; }
  .tag { color:var(--accent); font-weight:600; margin:0; font-size:1.05rem; }
  .card { background:#ffffff; border:1px solid var(--line); border-radius:12px; padding:24px 28px; }
  h2 { font-size:1.15rem; margin:28px 0 8px; }
  h2:first-child { margin-top:0; }
  ul { margin:8px 0; padding-left:22px; }
  li { margin:7px 0; color:var(--sub); }
  p { color:var(--sub); }
  strong { color:var(--ink); }
  footer { margin-top:36px; padding-top:18px; border-top:1px solid var(--line); color:var(--sub); font-size:0.9rem; }
  a { color:var(--accent); }
  .muted { font-size:0.85rem; color:#94a3b8; }
`;

const HOME_HTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Student Codex</title>
<style>${STYLE}</style>
</head>
<body>
<div class="wrap">
  <header class="hero">
    <h1>Student Codex</h1>
    <p class="tag">Your school life, in one place.</p>
  </header>

  <div class="card">
    <h2>What it does</h2>
    <ul>
      <li><strong>Import courses straight from Google Classroom.</strong> You choose which Google account and which courses &mdash; it is never a guessing game.</li>
      <li><strong>Automatic coursework sync.</strong> New assignments appear in the app without you lifting a finger.</li>
      <li><strong>Deadlines that are actually upcoming.</strong> The Beacon counts what is due in the next 7 days so nothing sneaks up on you.</li>
      <li><strong>Enroll in courses manually</strong> or pick them during sign-up.</li>
      <li><strong>Sign in</strong> with email and password, or with your Google account.</li>
    </ul>
  </div>

  <div class="card" style="margin-top:20px;">
    <h2>Privacy first</h2>
    <ul>
      <li><strong>Read-only access.</strong> Student Codex never modifies your Google Classroom.</li>
      <li><strong>No ads, no trackers, no data selling.</strong></li>
      <li><strong>Disconnect Google Classroom anytime</strong> from Settings.</li>
    </ul>
    <p>See the <a href="${PRIVACY_URL}">Privacy Policy</a> for full details.</p>
  </div>

  <footer>
    <p><a href="${PRIVACY_URL}">Privacy Policy</a> &middot; ${SUPPORT_EMAIL}</p>
    <p class="muted">Student Codex is a personal companion app for university students.</p>
  </footer>
</div>
</body>
</html>`;

const PRIVACY_HTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Student Codex &mdash; Privacy Policy</title>
<style>${STYLE}</style>
</head>
<body>
<div class="wrap">
  <header class="hero">
    <h1>Privacy Policy</h1>
    <p class="tag">Student Codex</p>
  </header>

  <div class="card">
    <p><em>Last updated: October 26, 2026</em></p>
    <p>This privacy policy explains how Student Codex (&ldquo;the app&rdquo;) handles your information when you use it. Student Codex is a personal school companion app for university students: it shows your Google Classroom coursework, assignments, and deadlines in one clean view (the Beacon) together with the courses you are enrolled in.</p>
    <p>If you have any questions about this policy, contact us at <a href="mailto:${SUPPORT_EMAIL}">${SUPPORT_EMAIL}</a>.</p>

    <h2>1. Information we collect</h2>
    <p><strong>A. Account information</strong></p>
    <ul><li>The email address and display name you provide when you create an account (email and password sign-up, or Google Sign-In).</li></ul>
    <p><strong>B. Course and school details you enter</strong></p>
    <ul><li>The courses you enroll in manually and any school details you fill in during sign-up or later in Settings.</li></ul>
    <p><strong>C. Google Classroom data (only after YOU connect your account)</strong></p>
    <ul>
      <li>The names, sections, and teacher/roster information of the Google Classroom courses you choose to import.</li>
      <li>The coursework in those courses: titles, descriptions, due dates, and completion status.</li>
      <li>The Google account email you selected when importing, so that future syncs keep using the exact account you chose.</li>
    </ul>
    <p>The app uses <strong>read-only</strong> Google Classroom permissions. It never posts, edits, submits, or deletes anything in your Google Classroom.</p>
    <p><strong>D. Authorization tokens</strong></p>
    <ul><li>Short-lived Google access tokens used to read the data above while a sync is running.</li></ul>

    <h2>2. How we use the information</h2>
    <ul>
      <li>To display <strong>your own</strong> coursework, deadlines, and classes inside the app.</li>
      <li>To re-sync your coursework in the background so deadlines stay current.</li>
      <li>To keep your account working across reinstalls and devices.</li>
    </ul>
    <p>We do <strong>not</strong> use your information for advertising, profiling, analytics, or any purpose other than the features of the app itself.</p>

    <h2>3. Where data is stored and how it is protected</h2>
    <ul>
      <li>Your account, enrolled courses, and synced coursework are stored in the app&rsquo;s backend database (Supabase).</li>
      <li>Data is transmitted over HTTPS.</li>
      <li>Google access tokens are used only to call Google&rsquo;s Classroom API during a sync, and are never sold or shared with anyone.</li>
    </ul>

    <h2>4. Sharing with third parties</h2>
    <ul>
      <li>We never sell, rent, or trade your personal information.</li>
      <li>The app contains no third-party advertising or tracking SDKs.</li>
      <li>Data is disclosed only when legally required.</li>
    </ul>

    <h2>5. Your controls</h2>
    <ul>
      <li><strong>Disconnect Google Classroom at any time</strong> from Settings. This stops all syncing immediately.</li>
      <li><strong>Delete your account and all associated data</strong> by emailing <a href="mailto:${SUPPORT_EMAIL}">${SUPPORT_EMAIL}</a> with the subject &ldquo;Delete my account&rdquo;. Deletion requests are processed within 30 days.</li>
    </ul>

    <h2>6. Data retention</h2>
    <p>Your account and coursework data are kept while your account exists, so the app can keep showing them. Everything is permanently deleted when you request account deletion, or when you delete courses from the app.</p>

    <h2>7. Children</h2>
    <p>Student Codex is intended for university students. It is not directed at children under 13, and we do not knowingly collect data from children.</p>

    <h2>8. Changes to this policy</h2>
    <p>If this policy changes, the updated version will be posted on this page with a new &ldquo;last updated&rdquo; date.</p>

    <h2>9. Contact</h2>
    <p>Questions, concerns, or deletion requests: <a href="mailto:${SUPPORT_EMAIL}">${SUPPORT_EMAIL}</a></p>
  </div>

  <footer>
    <p><a href="https://${PROJECT_REF}.supabase.co/functions/v1/site">Student Codex home</a> &middot; ${SUPPORT_EMAIL}</p>
  </footer>
</div>
</body>
</html>`;

const HTML_HEADERS = {
  "Content-Type": "text/html; charset=utf-8",
  "Cache-Control": "public, max-age=300",
};

Deno.serve((req: Request) => {
  const path = new URL(req.url).pathname.toLowerCase();

  if (path.endsWith("/privacy")) {
    return new Response(PRIVACY_HTML, { headers: HTML_HEADERS });
  }
  if (path.endsWith("/site") || path.endsWith("/site/") || path.endsWith("/home") || path.endsWith("/index")) {
    return new Response(HOME_HTML, { headers: HTML_HEADERS });
  }

  return new Response(
    `<!DOCTYPE html><html><head><meta charset="utf-8"><title>Not found</title></head><body style="font-family:sans-serif;color:#475569;"><p>Not found. Try the <a style="color:#0d9488;" href="https://${PROJECT_REF}.supabase.co/functions/v1/site">home page</a>.</p></body></html>`,
    { status: 404, headers: HTML_HEADERS },
  );
});
