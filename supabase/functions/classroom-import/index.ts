// ============================================================================
// Student Codex Edge Function — classroom-import
//
// The student-facing COURSE IMPORT (companion to classroom-sync):
//   * action "list": the ACTIVE courses of the Google account whose access
//     token rides in the body — the app shows them as a picker. This
//     action needs NO Supabase session: the Google token alone authorizes
//     it (Google returns only that account's own courses), which lets the
//     pre-sign-up gate offer the import too. Deployed with
//     --no-verify-jwt for exactly this reason;
//   * action "import": the picked course ids are re-fetched from Google
//     (so only real, currently-active Classroom courses enter), then run
//     through import_student_classroom_courses() — the trusted, idempotent
//     RPC from migration 0022 — which resolves each course to an exact
//     external_course_id link (created or name-linked) and enrolls the
//     student in it. THIS action requires the caller's Supabase session
//     JWT (Authorization header), verified manually below — that check is
//     the security boundary that protects the RPC.
//
// Imported/linked courses then match classroom-sync EXACTLY by course id,
// ahead of the name heuristics. Tokens are used in transit only — nothing
// is stored server-side.
// ============================================================================

const jsonHeaders = { "Content-Type": "application/json" };
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: jsonHeaders });

const nowIso = () => new Date().toISOString();
const truncate = (s: string, n: number) => (s.length > n ? s.slice(0, n - 1) + "…" : s);

interface ClassroomCourse {
  id: string;
  name?: string;
  section?: string;
}

// Teachers append a school-year tag to the Google Classroom course name to
// tell yearly offerings apart ("Numerical Methods 2B(2026-2027)",
// "Physics 1 [SY 2026-27]"). Student Codex's own catalog never carries it —
// the subject name is the name — so the tag is stripped wherever a
// Classroom course name crosses into the app: the picker display AND the
// imported course rows (code/title), which is what re-created the tagged
// names on every re-import. Matching in classroom-sync keeps the RAW name
// (its tier-0 external-id link dominates; its startsWith tier already
// tolerates a suffix), so this is display/import shaping only.
const SCHOOL_YEAR_SUFFIX =
  /\s*[\(\[]\s*(?:SY|S\.Y\.|School\s+Year)?\s*(?:19|20)\d{2}\s*[-–—]\s*(?:(?:19|20)\d{2}|\d{2})\s*[\)\]]\s*$/i;
const cleanCourseName = (raw: string): string => {
  const cleaned = raw.replace(SCHOOL_YEAR_SUFFIX, "").trim();
  // A name that was ONLY the year tag: keep the raw name (never empty).
  return cleaned.length > 0 ? cleaned : raw.trim();
};

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
  const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!SUPABASE_URL || !SERVICE_KEY) return json({ error: "server_misconfigured" }, 500);

  // ---- 1. Google access token + requested action from the body. ---------
  let body: {
    action?: string;
    googleAccessToken?: string;
    courseIds?: string[];
    accountEmail?: string;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const action = body.action === "import" ? "import" : "list";
  const accessToken = (body.googleAccessToken ?? "").trim();
  if (!accessToken) return json({ error: "missing_google_access_token" }, 400);
  // Which Google account the token was minted for (the app knows it from
  // its explicit account choice). Shape-checked; a bad value is ignored.
  const accountEmail = (body.accountEmail ?? "").trim().slice(0, 254);
  const validAccountEmail =
    /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(accountEmail) ? accountEmail : null;

  const googleGet = async (path: string) =>
    await fetch(`https://classroom.googleapis.com/v1/${path}`, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });

  // ---- 2. List the account's ACTIVE Classroom courses (the probe). ------
  // Paginated: most accounts fit one page, a handful of teachers do not.
  const courses: ClassroomCourse[] = [];
  let pageToken: string | undefined;
  try {
    for (let page = 0; page < 5; page++) {
      const path = `courses?courseStates=ACTIVE&pageSize=100` +
        (pageToken ? `&pageToken=${encodeURIComponent(pageToken)}` : "");
      const res = await googleGet(path);
      if (res.status === 401 || res.status === 403) {
        // Google refused the token: revoked/expired consent or scope.
        return json({
          status: "failed",
          error: `google_${res.status}`,
          message: "Google rejected the authorization — reconnect Google Classroom.",
        });
      }
      if (!res.ok) {
        return json({ status: "failed", error: `google_${res.status} on courses.list` });
      }
      const pageJson = await res.json();
      courses.push(...((pageJson.courses ?? []) as ClassroomCourse[]));
      pageToken = pageJson.nextPageToken;
      if (!pageToken) break;
    }
  } catch (e) {
    return json({ status: "failed", error: `network_error: ${(e as Error).message}` });
  }

  // ---- 3a. LIST: hand the courses to the app's picker. No session. -----
  if (action === "list") {
    return json({
      status: "ok",
      courses: courses.map((c) => ({
        id: c.id,
        name: cleanCourseName(c.name ?? c.id).slice(0, 160),
        section: c.section ? c.section.slice(0, 80) : null,
      })),
    });
  }

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

  const service = {
    apikey: SERVICE_KEY,
    Authorization: `Bearer ${SERVICE_KEY}`,
    "Content-Type": "application/json",
  };

  /** Writes the connection-state registry row (service context). */
  const setConnection = async (fields: Record<string, unknown>) => {
    await fetch(`${SUPABASE_URL}/rest/v1/google_connections`, {
      method: "POST",
      headers: { ...service, Prefer: "resolution=merge-duplicates" },
      body: JSON.stringify({ user_id: uid, ...fields }),
    });
  };

  // ---- 4. Import: run the picked ids through the trusted RPC. ----------
  const wanted = new Set(
    Array.isArray(body.courseIds)
      ? body.courseIds.filter((id): id is string => typeof id === "string" && id.length > 0)
      : [],
  );
  if (wanted.size === 0) return json({ error: "no_courses_selected" }, 400);

  // Only ids Google just confirmed ACTIVE — a stale/forged id stops here.
  const picked = courses.filter((c) => wanted.has(c.id));
  if (picked.length === 0) {
    return json({
      status: "failed",
      error: "no_matching_active_courses",
      message: "None of the picked courses are active in Google Classroom anymore.",
    });
  }

  // Pre-truncate to the RPC's shape guards (defense in depth; the RPC
  // re-validates everything).
  const payload = picked.map((c) => ({
    externalId: c.id.slice(0, 64),
    name: cleanCourseName(c.name ?? c.id).slice(0, 160),
    section: c.section ? c.section.trim().slice(0, 80) : null,
  }));

  const rpcRes = await fetch(`${SUPABASE_URL}/rest/v1/rpc/import_student_classroom_courses`, {
    method: "POST",
    headers: service,
    body: JSON.stringify({ p_user: uid, p_courses: payload }),
  });
  if (!rpcRes.ok) {
    return json({
      status: "failed",
      error: `rpc_${rpcRes.status}`,
      message: truncate(await rpcRes.text(), 300),
    });
  }
  const summary = await rpcRes.json();

  // The Classroom link was just used successfully — stamp it connected so
  // the Settings connection card reflects reality immediately, and record
  // WHICH Google account the student picked so every later sync pins to
  // it (a background run must never quietly import another account's
  // roster). A follow-up sync (the app fires one right after importing)
  // refines last_sync_*.
  await setConnection({
    status: "connected",
    ...(validAccountEmail ? { google_email: validAccountEmail } : {}),
    last_sync_at: nowIso(),
    last_sync_status: "ok",
    last_sync_error: null,
  });

  return json({ status: "ok", ...summary, courses: payload });
});
