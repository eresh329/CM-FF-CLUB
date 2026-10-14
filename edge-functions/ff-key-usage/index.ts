import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

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

function getUserIdFromAuthHeader(req: Request): string | null {
  const authHeader = req.headers.get("Authorization") || "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  try {
    const payloadJson = atob(parts[1].replace(/-/g, "+").replace(/_/g, "/"));
    const payload = JSON.parse(payloadJson);
    return payload.sub || null;
  } catch {
    return null;
  }
}

async function pgrest(path: string, init: RequestInit = {}) {
  return await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      "Content-Type": "application/json",
      ...(init.headers || {}),
    },
  });
}

async function isAdmin(userId: string) {
  const res = await pgrest(`admins?id=eq.${userId}&select=id`);
  if (!res.ok) return false;
  const rows = await res.json();
  return Array.isArray(rows) && rows.length > 0;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    const userId = getUserIdFromAuthHeader(req);
    if (!userId || !(await isAdmin(userId))) {
      return json({ error: "unauthorized" }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const keyId = body.key_id;
    if (!keyId) return json({ error: "key_id required" }, 400);

    const keyRes = await pgrest(`ff_uid_providers?id=eq.${keyId}&select=api_key,api_key_header,base_url`);
    const row = (await keyRes.json().catch(() => []))?.[0];
    if (!row) return json({ error: "key not found" }, 404);

    const usageUrl = new URL(row.base_url).origin + "/api/usage";
    const res = await fetch(usageUrl, {
      headers: { [row.api_key_header || "x-api-key"]: row.api_key, "X-Forwarded-For": "127.0.0.1" },
    });
    const data = await res.json().catch(() => null);
    if (!res.ok || !data) {
      return json({ error: `provider_error_${res.status}` }, 502);
    }
    return json({ used: data.used, limit: data.limit, remaining: data.remaining, plan: data.plan });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
