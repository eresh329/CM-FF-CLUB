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
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      "Content-Type": "application/json",
      ...(init.headers || {}),
    },
  });
  return res;
}

async function isAdmin(userId: string): Promise<boolean> {
  const res = await pgrest(`admins?id=eq.${userId}&select=id`);
  if (!res.ok) return false;
  const rows = await res.json();
  return Array.isArray(rows) && rows.length > 0;
}

// শুধু Games Kinbo-র নিজের /api/usage endpoint সাপোর্ট করে (base_url-এ ff-info/get থাকলে সেই root ধরে usage নেয়)
function usageUrlFor(baseUrl: string): string | null {
  try {
    const u = new URL(baseUrl);
    return `${u.protocol}//${u.host}/api/usage`;
  } catch {
    return null;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const userId = getUserIdFromAuthHeader(req);
    if (!userId || !(await isAdmin(userId))) {
      return json({ error: "unauthorized" }, 403);
    }

    const res = await pgrest(`ff_uid_providers?select=id,label,base_url,api_key_header,api_key&order=priority.asc`);
    const providers = res.ok ? await res.json() : [];

    const results = await Promise.all(
      providers.map(async (p: any) => {
        const usageUrl = usageUrlFor(p.base_url);
        if (!usageUrl) {
          return { id: p.id, label: p.label, ok: false, error: "invalid_base_url" };
        }
        try {
          const r = await fetch(usageUrl, { headers: { [p.api_key_header]: p.api_key } });
          if (!r.ok) {
            return { id: p.id, label: p.label, ok: false, error: `HTTP ${r.status}` };
          }
          const data = await r.json();
          return {
            id: p.id,
            label: p.label,
            ok: true,
            used: data.used,
            limit: data.limit,
            remaining: data.remaining,
            plan: data.plan,
          };
        } catch (e) {
          return { id: p.id, label: p.label, ok: false, error: String(e) };
        }
      })
    );

    return json({ results });
  } catch (e) {
    return json({ error: "internal_error" }, 500);
  }
});
