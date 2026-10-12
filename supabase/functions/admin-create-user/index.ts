import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

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

const ALLOWED_ROLES = ["citizen", "reviewer", "committee", "admin"];

function getAdminClient() {
  const url = Deno.env.get("SUPABASE_URL");
  let secretKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  if (!secretKey) {
    try { secretKey = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}").default || ""; } catch {}
  }
  if (!url || !secretKey) throw new Error("Supabase server config missing");
  return createClient(url, secretKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

async function getAuthenticatedUser(req: Request) {
  const url = Deno.env.get("SUPABASE_URL");
  let publishableKey = Deno.env.get("SUPABASE_ANON_KEY") || "";
  if (!publishableKey) {
    try { publishableKey = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") || "{}").default || ""; } catch {}
  }
  const token = req.headers.get("authorization")?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!url || !publishableKey || !token) return null;
  const client = createClient(url, publishableKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data, error } = await client.auth.getUser(token);
  return error ? null : data.user;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const caller = await getAuthenticatedUser(req);
  if (!caller) return json({ error: "Authentication required" }, 401);

  let admin: any;
  try {
    admin = getAdminClient();
  } catch {
    return json({ error: "Server not configured" }, 503);
  }

  // Check caller is admin
  const { data: callerProfile } = await admin
    .from("profiles")
    .select("role")
    .eq("id", caller.id)
    .maybeSingle();

  if (callerProfile?.role !== "admin") {
    return json({ error: "Admin access required" }, 403);
  }

  // Parse body
  let body: any;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request" }, 400);
  }

  const email = String(body.email || "").trim().toLowerCase();
  const password = String(body.password || "");
  const displayName = String(body.displayName || "").trim();
  const role = String(body.role || "citizen");

  // Validate
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return json({ error: "Valid email required" }, 400);
  }
  if (password.length < 8) {
    return json({ error: "Password must be at least 8 characters" }, 400);
  }
  if (!displayName || displayName.length < 2) {
    return json({ error: "Display name must be at least 2 characters" }, 400);
  }
  if (!ALLOWED_ROLES.includes(role)) {
    return json({ error: "Invalid role" }, 400);
  }

  // Create user
  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { display_name: displayName },
  });

  if (createError) {
    console.error("Create user error:", createError);
    const msg = createError.message || "";
    if (msg.toLowerCase().includes("already") || msg.toLowerCase().includes("exists")) {
      return json({ error: "Email already registered" }, 409);
    }
    return json({ error: "Unable to create user" }, 500);
  }

  const newUserId = created.user?.id;
  if (!newUserId) return json({ error: "User created but no ID returned" }, 500);

  // Update profile role
  const { error: profileError } = await admin
    .from("profiles")
    .upsert({
      id: newUserId,
      display_name: displayName,
      role,
    }, { onConflict: "id" });

  if (profileError) {
    console.error("Profile update error:", profileError);
    // User was created but role update failed — try to clean up
    await admin.auth.admin.deleteUser(newUserId);
    return json({ error: "Unable to set user role" }, 500);
  }

  return json({
    ok: true,
    user: {
      id: newUserId,
      email,
      display_name: displayName,
      role,
    },
  });
});