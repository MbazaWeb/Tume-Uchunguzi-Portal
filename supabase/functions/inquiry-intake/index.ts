import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const bucket = "inquiry-evidence";
const maxFileBytes = 50 * 1024 * 1024;

const allowedTypes = new Set([
  "application/pdf",
  "application/msword",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  "image/jpeg", "image/png", "image/webp",
  "video/mp4", "video/webm", "video/quicktime",
  "audio/mpeg", "audio/wav", "audio/mp4", "audio/ogg",
]);

const extensions: Record<string, string> = {
  "application/pdf": "pdf",
  "application/msword": "doc",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
  "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp",
  "video/mp4": "mp4", "video/webm": "webm", "video/quicktime": "mov",
  "audio/mpeg": "mp3", "audio/wav": "wav", "audio/mp4": "m4a", "audio/ogg": "ogg",
};

const incidentDates = new Set([
  "2025-10-25","2025-10-26","2025-10-27","2025-10-28",
  "2025-10-29","2025-10-30","2025-10-31",
]);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

function getAdminClient() {
  const url = Deno.env.get("SUPABASE_URL");
  let secretKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  if (!secretKey) {
    try { secretKey = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}").default || ""; } catch {}
  }
  if (!url || !secretKey) throw new Error("Supabase server config missing");
  return createClient(url, secretKey, { auth: { autoRefreshToken: false, persistSession: false } });
}

async function getAuthenticatedUser(req: Request) {
  const url = Deno.env.get("SUPABASE_URL");
  let publishableKey = Deno.env.get("SUPABASE_ANON_KEY") || "";
  if (!publishableKey) {
    try { publishableKey = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") || "{}").default || ""; } catch {}
  }
  const token = req.headers.get("authorization")?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!url || !publishableKey || !token) return null;
  const client = createClient(url, publishableKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const { data, error } = await client.auth.getUser(token);
  return error ? null : data.user;
}

async function verifyTurnstile(token: string, ip: string | null) {
  const secret = Deno.env.get("TURNSTILE_SECRET_KEY");
  if (!secret) return false;
  const body = new FormData();
  body.set("secret", secret);
  body.set("response", token);
  if (ip) body.set("remoteip", ip);
  const res = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
    method: "POST", body,
  });
  if (!res.ok) return false;
  return Boolean((await res.json()).success);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "Invalid request" }, 400); }

  const user = await getAuthenticatedUser(req);

  let admin: any;
  try { admin = getAdminClient(); } catch { return json({ error: "Intake not configured" }, 503); }

  // ==========================================================
  // ACTION: create
  // ==========================================================
  if (body.action === "create") {
    if (String(body.website || "").trim()) return json({ error: "Invalid request" }, 400);

    const report = body.report || {};
    const attachments = Array.isArray(body.attachments) ? body.attachments : [];
    const anonymousMode = Boolean(report.anonymous);

    // Turnstile required for every submission
    const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || null;
    if (!(await verifyTurnstile(String(body.turnstileToken || ""), ip))) {
      return json({ error: "Verification failed" }, 403);
    }

    // Anonymous allowed without login; identified requires login
    if (!anonymousMode && !user) {
      return json({ error: "Sign in required" }, 401);
    }

    const incidentDate = String(report.incidentDate || "");
    if (!incidentDates.has(incidentDate)) {
      return json({ error: "Invalid incident date" }, 400);
    }

    const title = String(report.title || "").trim().slice(0, 200) || "Untitled";
    const description = String(report.description || "").trim();

    if (!title) return json({ error: "Title required" }, 400);
    if (description.length < 100 || description.length > 10000) {
      return json({ error: "Description must be 100-10000 characters" }, 400);
    }
    if (!String(report.region || "").trim()) return json({ error: "Region required" }, 400);
    if (report.truthDeclared !== true) return json({ error: "Declaration required" }, 400);
    if (attachments.length > 5) return json({ error: "Max 5 files" }, 400);

    if (attachments.some((f: any) =>
      !allowedTypes.has(String(f.type)) ||
      !Number.isInteger(f.size) ||
      f.size < 1 ||
      f.size > maxFileBytes
    )) {
      return json({ error: "Invalid attachment type or size" }, 400);
    }

    const submissionUserId = anonymousMode ? null : (user?.id || null);

    const { data: submission, error: insertError } = await admin
      .from("inquiry_submissions")
      .insert({
        user_id: submissionUserId,
        title,
        submission_type: String(report.submissionType || "other"),
        reporter_role: String(report.reporterRole || (anonymousMode ? "anonymous" : "witness")),
        submission_mode: anonymousMode ? "anonymous" : String(report.submissionMode || "identified"),
        incident_time: String(report.incidentTime || "unknown"),
        ward: String(report.ward || "").trim(),
        street_village: String(report.streetVillage || "").trim(),
        short_title_category: String(report.shortTitleCategory || "").trim(),
        people_involved: String(report.peopleInvolved || "").trim(),
        people_involved_data: Array.isArray(report.peopleInvolvedData) ? report.peopleInvolvedData : [],
        violation_types: Array.isArray(report.violationTypes) ? report.violationTypes : [],
        authorities_present: String(report.authoritiesPresent || "unsure"),
        reported_elsewhere: Boolean(report.reportedElsewhere),
        reporting_place: String(report.reportingPlace || "").trim(),
        evidence_category: String(report.evidenceCategory || "none"),
        contact_method: report.contactConsent ? String(report.contactMethod || "none") : "none",
        contact_consent: Boolean(report.contactConsent),
        truth_declared: true,
        anonymous_flag: anonymousMode,
        details: typeof report.details === "object" && report.details !== null ? report.details : {},
        full_name: anonymousMode ? null : (String(report.fullName || "").trim() || null),
        contact: anonymousMode
          ? null
          : (report.contactConsent
              ? (report.contactMethod === "email"
                  ? String(report.email || "").trim()
                  : String(report.phone || "").trim()) || null
              : null),
        incident_date: incidentDate,
        region: String(report.region || "").trim(),
        district: String(report.district || "").trim(),
        location: String(report.location || "").trim(),
        description,
        status: "uploading",
      })
      .select("id, reference_code")
      .single();

    if (insertError || !submission) {
      console.error("Insert error:", insertError);
      return json({ error: "Unable to create submission" }, 500);
    }

    const storagePrefix = submissionUserId
      ? `${submissionUserId}/${submission.id}`
      : `anonymous/${submission.id}`;

    const storedFiles: any[] = [];
    const uploads: any[] = [];

    for (const file of attachments) {
      const path = `${storagePrefix}/${crypto.randomUUID()}.${extensions[file.type] || "bin"}`;
      const { data: upload, error } = await admin.storage
        .from(bucket)
        .createSignedUploadUrl(path);

      if (error || !upload) {
        await admin.from("inquiry_submissions").delete().eq("id", submission.id);
        return json({ error: "Unable to prepare upload" }, 500);
      }

      storedFiles.push({
        path,
        name: String(file.name || "evidence").slice(0, 180),
        type: file.type,
        size: file.size,
        description: String(file.description || "").trim().slice(0, 500),
        captured_at: file.capturedAt || null,
        original_unmodified: Boolean(file.originalUnmodified),
        evidence_type: String(file.evidenceType || "other"),
      });

      uploads.push({ path, token: upload.token });
    }

    const { error: filesError } = await admin
      .from("inquiry_submissions")
      .update({ attachments: storedFiles })
      .eq("id", submission.id);

    if (filesError) {
      await admin.from("inquiry_submissions").delete().eq("id", submission.id);
      return json({ error: "Unable to save attachments" }, 500);
    }

    return json({
      id: submission.id,
      referenceCode: submission.reference_code,
      uploads,
    });
  }

  // ==========================================================
  // ACTION: finalize
  // ==========================================================
  if (body.action === "finalize") {
    const id = String(body.id || "");
    if (!/^[0-9a-f-]{36}$/i.test(id)) return json({ error: "Invalid submission" }, 400);

    const base = admin
      .from("inquiry_submissions")
      .select("id,reference_code,user_id,anonymous_flag,attachments,status")
      .eq("id", id)
      .eq("status", "uploading");

    const filter = user ? base : base.eq("anonymous_flag", true);
    const { data: submission, error } = await filter.maybeSingle();

    if (error || !submission) return json({ error: "Submission not found" }, 404);
    if (submission.user_id && user && submission.user_id !== user.id) {
      return json({ error: "Submission not found" }, 404);
    }

    const ownerPrefix = submission.user_id
      ? `${submission.user_id}/${id}/`
      : `anonymous/${id}/`;

    for (const file of submission.attachments || []) {
      if (!String(file.path || "").startsWith(ownerPrefix)) {
        return json({ error: "Invalid attachment path" }, 400);
      }
    }

    const { error: updateError } = await admin
      .from("inquiry_submissions")
      .update({ status: "submitted" })
      .eq("id", id)
      .eq("status", "uploading");

    if (updateError) return json({ error: "Unable to finalize" }, 500);
    return json({ referenceCode: submission.reference_code });
  }

  return json({ error: "Unsupported action" }, 400);
});