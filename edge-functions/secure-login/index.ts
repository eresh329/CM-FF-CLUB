import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

// username diye login korle email kokhono client-e ferot jay na —
// shob shomoy service-role diye server-e-i resolve kora hoy.
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return json({ error: "METHOD_NOT_ALLOWED" }, 405);
  }

  try {
    const body = await req.json();
    const identifier = (body?.identifier ?? "").toString().trim();
    const password = (body?.password ?? "").toString();

    if (!identifier || !password) {
      return json({ error: "MISSING_FIELDS" }, 400);
    }

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
    let email = identifier;

    if (!identifier.includes("@")) {
      const { data: profile, error: profileErr } = await admin
        .from("profiles")
        .select("id")
        .ilike("username", identifier)
        .maybeSingle();

      if (profileErr || !profile) {
        return json({ error: "INVALID_CREDENTIALS" }, 401);
      }

      const { data: userData, error: userErr } = await admin.auth.admin.getUserById(profile.id);
      if (userErr || !userData?.user?.email) {
        return json({ error: "INVALID_CREDENTIALS" }, 401);
      }
      email = userData.user.email;
    }

    const anon = createClient(SUPABASE_URL, ANON_KEY);
    const { data: signInData, error: signInErr } = await anon.auth.signInWithPassword({ email, password });

    if (signInErr || !signInData.session) {
      return json({ error: "INVALID_CREDENTIALS" }, 401);
    }

    return json({
      access_token: signInData.session.access_token,
      refresh_token: signInData.session.refresh_token,
      user_id: signInData.user.id,
    });
  } catch (e) {
    return json({ error: "SERVER_ERROR" }, 500);
  }
});
