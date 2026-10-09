import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {createClient} from "npm:@supabase/supabase-js@2";

const bucket = "inquiry-evidence";
const maxFileBytes = 50 * 1024 * 1024;
const allowedTypes = new Set(["application/pdf", "application/msword", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "image/jpeg", "image/png", "image/webp", "video/mp4", "video/webm", "video/quicktime", "audio/mpeg", "audio/wav", "audio/mp4", "audio/ogg"]);
const extensions: Record<string, string> = {"application/pdf": "pdf", "application/msword": "doc", "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx", "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "video/mp4": "mp4", "video/webm": "webm", "video/quicktime": "mov", "audio/mpeg": "mp3", "audio/wav": "wav", "audio/mp4": "m4a", "audio/ogg": "ogg"};
const submissionTypes = new Set(["eyewitness", "photo", "video", "document", "audio", "other"]);
const reporterRoles = new Set(["victim", "witness", "third_party", "anonymous"]);
const violationTypes = new Set(["physical_violence", "arrest", "intimidation", "property_damage", "death", "sexual_violence", "other"]);
const evidenceCategories = new Set(["none", "image", "video", "audio", "document", "other", "mixed"]);
const validShortTitles = new Set(["mwonekano_wa_polisi", "kukamatwa", "vurugu_zabuvu", "vurugu_za_kimwili", "moyo_unaondoka", "mali_ilipotea", "vitisho", "ukatili_wa_kingono", "mabavu_kamati", "ukosefu_wa_haki", "kutoweka_kwa_mtindo", "kukosekana_kwa_usalama", "kutokea_kwa_migogoro", "mengineyo", ""]);
const validPeopleRoles = new Set(["civilian", "police", "military", "government_official", "politician", "journalist", "lawyer", "doctor", "witness", "victim", "perpetrator", "unknown"]);

function evidenceKind(type: string) {
  if (type.startsWith("image/")) return "image";
  if (type.startsWith("video/")) return "video";
  if (type.startsWith("audio/")) return "audio";
  if (type === "application/pdf" || type.includes("word")) return "document";
  return "other";
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};
const json = (body: Record<string, unknown>, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

function getAdminClient() {
  const url = Deno.env.get("SUPABASE_URL");
  let secretKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  if (!secretKey) { try { secretKey = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}").default || ""; } catch {} }
  if (!url || !secretKey) throw new Error("Supabase server configuration is missing");
  return createClient(url, secretKey, { auth: { autoRefreshToken: false, persistSession: false } });
}

async function getAuthenticatedUser(req: Request) {
  const url = Deno.env.get("SUPABASE_URL");
  let publishableKey = Deno.env.get("SUPABASE_ANON_KEY") || "";
  if (!publishableKey) { try { publishableKey = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") || "{}").default || ""; } catch {} }
  const token = req.headers.get("authorization")?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!url || !publishableKey || !token) return null;
  const client = createClient(url, publishableKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const { data, error } = await client.auth.getUser(token);
  return error ? null : data.user;
}

async function verifyTurnstile(token: string, ip: string | null) {
  const secret = Deno.env.get("TURNSTILE_SECRET_KEY");
  if (!secret) return false;
  const body = new FormData(); body.set("secret", secret); body.set("response", token); if (ip) body.set("remoteip", ip);
  const response = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", { method: "POST", body });
  if (!response.ok) return false;
  return Boolean((await response.json()).success);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  let body: any;
  try { body = await req.json(); } catch { return json({ error: "Invalid request" }, 400); }
  const user = await getAuthenticatedUser(req);
  let admin: any;
  try { admin = getAdminClient(); } catch { return json({ error: "Intake service is not configured" }, 503); }

  if (body.action === "create") {
    if (String(body.website || "").trim()) return json({ error: "Invalid request" }, 400);
    const report = body.report || {}, attachments = body.attachments;
    const anonymousMode = Boolean(report.anonymous);

    // Anonymous submissions require turnstile verification even when no files attached.
    if (!await verifyTurnstile(String(body.turnstileToken || ""), req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || null)) return json({ error: "Verification failed" }, 403);
    if (anonymousMode && !user) {
      // Anonymous submission: skip the auth-required check, but require turnstile to pass.
      // Note: we still passed the turnstile check above.
    } else if (!user) {
      return json({ error: "Sign in required" }, 401);
    }

    const incidentDate = String(report.incidentDate || "");
    const validDate = /^\\d{4}-\\d{2}-\\d{2}$/.test(incidentDate) && incidentDate >= "2025-10-25" && incidentDate <= "2025-11-01";
    const title = String(report.title || "").trim(), description = String(report.description || "").trim();
    const violations = Array.isArray(report.violationTypes) ? report.violationTypes.map(String) : [];
    if (!validDate || !title || title.length > 200 || !String(report.region || "").trim() || !String(report.district || "").trim() || description.length < 100 || description.length > 10000) return json({ error: "Required fields are invalid" }, 400);
    if (!submissionTypes.has(String(report.submissionType)) || !reporterRoles.has(String(report.reporterRole)) || !['identified', 'confidential', 'anonymous'].includes(String(report.submissionMode)) || !['morning', 'afternoon', 'evening', 'night', 'unknown'].includes(String(report.incidentTime)) || !['police', 'military', 'unknown', 'no', 'unsure'].includes(String(report.authoritiesPresent)) || !evidenceCategories.has(String(report.evidenceCategory)) || !['phone', 'sms', 'email', 'none'].includes(String(report.contactMethod))) return json({ error: "Submission choices are invalid" }, 400);
    if (!validShortTitles.has(String(report.shortTitleCategory || ""))) return json({ error: "Short title is invalid" }, 400);
    // Validate the structured people-involved data (optional; falls back to the joined string).
    const peopleData = Array.isArray(report.peopleInvolvedData) ? report.peopleInvolvedData : [];
    if (peopleData.some((p: any) => !p || typeof p.name !== "string" || typeof p.role !== "string" || !validPeopleRoles.has(p.role))) return json({ error: "People involved data is invalid" }, 400);

    if (violations.some((type: string) => !violationTypes.has(type)) || report.truthDeclared !== true || typeof report.reportedElsewhere !== "boolean" || typeof report.contactConsent !== "boolean" || report.reportedElsewhere && !String(report.reportingPlace || "").trim() || (!anonymousMode && report.submissionMode === 'identified' && !String(report.fullName || "").trim()) || report.contactConsent && report.contactMethod === 'none' || report.contactConsent && report.contactMethod === 'phone' && !String(report.phone || "").trim() || report.contactConsent && report.contactMethod === 'email' && !String(report.email || "").trim()) return json({ error: "Review the declaration and incident details" }, 400);
    if (!Array.isArray(attachments) || attachments.length > 5) return json({ error: "Invalid attachments" }, 400);
    if ((attachments.length === 0 && report.evidenceCategory !== 'none') || (attachments.length > 0 && report.evidenceCategory === 'none') || report.submissionType === 'photo' && !attachments.length || report.submissionType === 'video' && !attachments.length || report.submissionType === 'audio' && !attachments.length || report.submissionType === 'document' && !attachments.length) return json({ error: "Add the evidence files for the selected type" }, 400);
    if (attachments.some((file: any) => !allowedTypes.has(String(file.type)) || !Number.isInteger(file.size) || file.size < 1 || file.size > maxFileBytes || String(file.description || "").length > 500 || file.capturedAt && !/^\d{4}-\d{2}-\d{2}$/.test(String(file.capturedAt)) || report.evidenceCategory !== 'mixed' && report.evidenceCategory !== 'none' && evidenceKind(String(file.type)) !== report.evidenceCategory)) return json({ error: "Attachment type or size is not allowed" }, 400);

    // For anonymous submissions we set user_id to NULL. The draft tracking features
    // are only available to logged-in users, so anonymous submissions simply skip them.
    const submissionUserId = anonymousMode ? null : user?.id || null;

    const { data: submission, error: insertError } = await admin.from("inquiry_submissions").insert({
      user_id: submissionUserId,
      title,
      submission_type: report.submissionType,
      reporter_role: report.reporterRole,
      submission_mode: anonymousMode ? "anonymous" : report.submissionMode,
      incident_time: report.incidentTime,
      ward: String(report.ward || "").trim(),
      street_village: String(report.streetVillage || "").trim(),
      short_title_category: String(report.shortTitleCategory || "").trim(),
      people_involved: String(report.peopleInvolved || "").trim(),
      people_involved_data: peopleData,
      violation_types: violations,
      authorities_present: report.authoritiesPresent,
      reported_elsewhere: Boolean(report.reportedElsewhere),
      reporting_place: String(report.reportingPlace || "").trim(),
      evidence_category: report.evidenceCategory,
      contact_method: report.contactConsent ? report.contactMethod : "none",
      contact_consent: Boolean(report.contactConsent),
      truth_declared: true,
      anonymous_flag: anonymousMode,
      details: {
        residenceRegion: String(report.residenceRegion || "").trim(),
        email: (anonymousMode || report.submissionMode === 'anonymous') ? null : String(report.email || "").trim() || null,
        phone: (anonymousMode || report.submissionMode === 'anonymous') ? null : String(report.phone || "").trim() || null
      },
      full_name: (anonymousMode || report.submissionMode === 'anonymous') ? null : String(report.fullName || "").trim() || null,
      contact: (anonymousMode || report.submissionMode === 'anonymous' || !report.contactConsent) ? null : (report.contactMethod === 'email' ? String(report.email || "").trim() : String(report.phone || "").trim()) || null,
      incident_date: incidentDate,
      region: String(report.region).trim(),
      district: String(report.district).trim(),
      location: String(report.location || "").trim(),
      description,
      status: "uploading"
    }).select("id,reference_code").single();
    if (insertError || !submission) return json({ error: "Unable to create submission" }, 500);

    // For anonymous submissions we cannot rely on user.id for the storage path prefix,
    // so we use the submission id directly. The RLS policy for the bucket still
    // requires admin access for reads, which is what we want.
    const storagePrefix = submissionUserId ? `${submissionUserId}/${submission.id}` : `anonymous/${submission.id}`;

    const storedFiles = [];
    const uploads = [];
    for (const file of attachments) {
      const path = `${storagePrefix}/${crypto.randomUUID()}.${extensions[file.type]}`;
      const { data: upload, error } = await admin.storage.from(bucket).createSignedUploadUrl(path);
      if (error || !upload) {
        await admin.from("inquiry_submissions").delete().eq("id", submission.id);
        return json({ error: "Unable to prepare private upload" }, 500);
      }
      storedFiles.push({ path, name: String(file.name || "evidence").slice(0, 180), type: file.type, size: file.size, description: String(file.description || "").trim().slice(0, 500), captured_at: file.capturedAt || null, original_unmodified: Boolean(file.originalUnmodified), evidence_type: String(file.evidenceType || "other") });
      uploads.push({ path, token: upload.token });
    }
    const { error: filesError } = await admin.from("inquiry_submissions").update({ attachments: storedFiles }).eq("id", submission.id);
    if (filesError) {
      await admin.from("inquiry_submissions").delete().eq("id", submission.id);
      return json({ error: "Unable to save attachment details" }, 500);
    }
    return json({ id: submission.id, referenceCode: submission.reference_code, uploads });
  }

  if (body.action === "finalize") {
    const id = String(body.id || "");
    if (!/^[0-9a-f-]{36}$/i.test(id)) return json({ error: "Invalid submission" }, 400);

    // Allow finalize either by the same authenticated user, or by an anonymous
    // submission that was created without auth (in which case we trust the id).
    const submissionFilter = user ? admin.from("inquiry_submissions").select("id,reference_code,user_id,anonymous_flag,attachments,status").eq("id", id).eq("status", "uploading") : admin.from("inquiry_submissions").select("id,reference_code,user_id,anonymous_flag,attachments,status").eq("id", id).eq("anonymous_flag", true).eq("status", "uploading");
    const { data: submission, error } = await submissionFilter.maybeSingle();
    if (error || !submission) return json({ error: "Submission not found" }, 404);

    // If the submission belongs to a real user, ensure the caller is that user.
    if (submission.user_id && user && submission.user_id !== user.id) return json({ error: "Submission not found" }, 404);

    const storageOwnerPrefix = submission.user_id ? `${submission.user_id}/${id}/` : `anonymous/${id}/`;
    for (const file of submission.attachments || []) {
      if (!String(file.path || "").startsWith(storageOwnerPrefix)) return json({ error: "Invalid attachment path" }, 400);
      const { data: info, error: infoError } = await admin.storage.from(bucket).info(file.path);
      if (infoError || !info || Number(info.size) !== Number(file.size) || !allowedTypes.has(String(info.mimetype || info.contentType || file.type))) return json({ error: "An attachment is missing or invalid" }, 409);
    }
    const { error: updateError } = await admin.from("inquiry_submissions").update({ status: "submitted" }).eq("id", id).eq("status", "uploading");
    if (updateError) return json({ error: "Unable to finalize submission" }, 500);
    return json({ referenceCode: submission.reference_code });
  }

  return json({ error: "Unsupported action" }, 400);
});
