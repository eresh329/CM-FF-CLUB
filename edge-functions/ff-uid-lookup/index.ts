import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const DAILY_LIMIT = 2;

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ ok: false, error: "method_not_allowed" }), { status: 405 });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user) {
    return new Response(JSON.stringify({ ok: false, error: "unauthorized" }), { status: 401 });
  }
  const userId = userData.user.id;

  let uid = "";
  try {
    const body = await req.json();
    uid = (body?.uid ?? "").toString().trim();
  } catch (_e) {
    return new Response(JSON.stringify({ ok: false, error: "bad_request" }), { status: 400 });
  }
  if (uid.length < 7) {
    return new Response(JSON.stringify({ ok: false, error: "invalid_uid" }), { status: 400 });
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  // 1) cache hit — no key usage, no rate-limit cost
  const { data: cached } = await admin
    .from("ff_uid_cache")
    .select("uid,name,level,region")
    .eq("uid", uid)
    .maybeSingle();

  if (cached) {
    await admin.from("ff_uid_lookup_log").insert({
      user_id: userId, uid, name: cached.name, level: cached.level, region: cached.region, from_cache: true,
    });
    return new Response(
      JSON.stringify({ ok: true, name: cached.name, level: cached.level, region: cached.region, from_cache: true }),
      { headers: { "Content-Type": "application/json" } }
    );
  }

  // 2) rate limit — enforced here, server-side, atomically. Client can no
  //    longer reset/bypass this via a direct table write.
  const { data: settings } = await admin.from("app_settings").select("uid_lookup_unlimited").eq("id", 1).maybeSingle();
  const unlimited = settings?.uid_lookup_unlimited === true;

  if (!unlimited) {
    const today = new Date().toISOString().slice(0, 10);
    const { data: row } = await admin
      .from("ai_uid_lookups")
      .select("lookup_count")
      .eq("user_id", userId)
      .eq("lookup_date", today)
      .maybeSingle();
    const currentCount = row?.lookup_count ?? 0;
    if (currentCount >= DAILY_LIMIT) {
      return new Response(JSON.stringify({ ok: false, error: "limit_reached" }), {
        status: 429,
        headers: { "Content-Type": "application/json" },
      });
    }
  }

  // 3) try providers by priority — keys never leave the server
  const { data: providers } = await admin
    .from("ff_uid_providers")
    .select("label,base_url,api_key_header,api_key")
    .eq("is_active", true)
    .order("priority", { ascending: true });

  let result: { name: string; level: number | null; region: string | null; raw: unknown } | null = null;
  let lastError = "lookup_failed";

  for (const p of providers ?? []) {
    try {
      const url = `${p.base_url}?uid=${encodeURIComponent(uid)}&region=BD`;
      const res = await fetch(url, { headers: { [p.api_key_header]: p.api_key } });

      if (res.status === 401 || res.status === 403) {
        await admin.from("ff_uid_providers").update({ last_error: `HTTP ${res.status}`, last_used_at: new Date().toISOString() }).eq("label", p.label);
        continue;
      }
      if (res.status === 402 || res.status === 404) {
        lastError = "not_found";
        break;
      }
      if (!res.ok) {
        lastError = res.status === 429 ? "rate_limited" : "lookup_failed";
        continue;
      }

      const data = await res.json();
      const info = data?.AccountInfo;
      const name = info?.AccountName;
      if (!name) {
        lastError = "not_found";
        continue;
      }
      result = {
        name,
        level: typeof info?.AccountLevel === "number" ? info.AccountLevel : null,
        region: info?.AccountRegion ?? null,
        raw: data,
      };
      await admin.from("ff_uid_providers").update({ last_used_at: new Date().toISOString() }).eq("label", p.label);
      break;
    } catch (_e) {
      lastError = "lookup_failed";
      continue;
    }
  }

  if (!result) {
    return new Response(JSON.stringify({ ok: false, error: lastError }), {
      status: lastError === "not_found" ? 404 : 502,
      headers: { "Content-Type": "application/json" },
    });
  }

  // 4) persist cache + count + log — all server-side now
  await admin.from("ff_uid_cache").upsert(
    { uid, name: result.name, level: result.level, region: result.region, raw: result.raw, updated_at: new Date().toISOString() },
    { onConflict: "uid" }
  );

  if (!unlimited) {
    const today = new Date().toISOString().slice(0, 10);
    const { data: row } = await admin
      .from("ai_uid_lookups")
      .select("lookup_count")
      .eq("user_id", userId)
      .eq("lookup_date", today)
      .maybeSingle();
    const nextCount = (row?.lookup_count ?? 0) + 1;
    await admin.from("ai_uid_lookups").upsert(
      { user_id: userId, lookup_date: today, lookup_count: nextCount },
      { onConflict: "user_id,lookup_date" }
    );
  }

  await admin.from("ff_uid_lookup_log").insert({
    user_id: userId, uid, name: result.name, level: result.level, region: result.region, from_cache: false,
  });

  return new Response(
    JSON.stringify({ ok: true, name: result.name, level: result.level, region: result.region, from_cache: false }),
    { headers: { "Content-Type": "application/json" } }
  );
});
