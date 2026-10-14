# Reusable Prompt — Full-Auto Supabase Backend Deploy

## How to use
1. Attach `supabase_backend_template.zip` (contains the SQL export + edge functions)
2. Attach your HTML app file(s) (user app, admin app — however many you have)
3. (Optional, only if you want full rebranding) Attach your app logo image file
4. Scroll to the bottom of this prompt, fill in your values in the **FILL IN YOUR VALUES** block
5. Copy the whole prompt (instructions + your filled-in values) and send it to an AI (Claude) that has your Supabase project connected via MCP (Settings → Connectors → Supabase → Connect)

---

## PROMPT (copy from here)

You will do a complete Supabase backend deployment + frontend wiring job for me, start to finish, on your own, without asking me step-by-step questions along the way. What I'm giving you:

- A zip file containing: extensions/schema/indexes/functions/triggers/policies/seed SQL files, an `edge-functions/` folder (one or more Deno edge functions, each with its own `index.ts`), and a `SETUP_GUIDE.md`
- One or more HTML files (Android WebView app frontend code — user app / admin app)
- (Maybe) an app logo image file
- My values, filled in at the bottom of this prompt

### Steps you will follow, in this order

**1. Inspect the zip**
- Extract it, look at the folder structure, read `SETUP_GUIDE.md` if present
- Understand the SQL file order (typically: extensions → schema → indexes → functions → triggers → policies → seed)

**2. Check for bugs before applying the schema**
- If the schema file has any column using `DEFAULT nextval('xxx_id_seq'::regclass)` but that sequence is never created anywhere with `CREATE SEQUENCE`, that's broken — convert that column to `GENERATED ALWAYS AS IDENTITY` instead (this is a common issue with pg_dump-style exports)
- Note any other hardcoded reference (like an old project's ref/UUID) — you'll fix it in a later step

**3. Apply in order (using the Supabase MCP `apply_migration` / `execute_sql` tools)**
1. extensions (`uuid-ossp`, `pgcrypto`, `pg_net` — whatever's needed)
2. schema (with the bug fix above applied)
3. indexes
4. functions — if the file is too large to send in one call, split it at function boundaries (`CREATE OR REPLACE FUNCTION`) into a few chunks and apply them one by one, without skipping any function
5. triggers
6. policies (enable RLS + every policy)
7. seed data — for `app_name`, use my `APP_FULL_NAME` if I gave one, otherwise leave whatever generic/default value is already in the seed file; for `package_name`, use mine if given, otherwise leave the default placeholder and mention in your final summary that it needs to match the real Android app ID later

**4. Find and fix hardcoded URLs/refs inside functions**
- If any function body (e.g. a `net.http_post` call inside a push-notification trigger) has another (old/placeholder) project's URL or ref hardcoded, replace it with my real project ref (derived from my Supabase URL below) at apply time — don't ask me first, just fix it

**5. Deploy the edge functions**
- Each subfolder under `edge-functions/` is a separate function; the folder name is the function slug
- Call `deploy_edge_function` for each one, with the full, exact content of its `index.ts`
- Decide `verify_jwt` like this:
  - A function that checks its own auth/secret internally (e.g. a webhook, a custom login endpoint) → `verify_jwt: false`
  - A function that expects a normal logged-in user's Supabase JWT in the Authorization header → `verify_jwt: true`
  - If unsure, read the function's code to see how it authenticates
- Any provider-based feature (Free Fire UID lookup, AI chat support, etc.) must keep working with **zero providers configured** — the code already has a graceful "not configured" fallback for this; do not treat missing provider API keys as an error or ask me for them. I'll add real providers later from the admin panel if I want that feature.

**6. Run the security advisor**
- Run `get_advisors` (security). If it flags a table with RLS enabled but no policy, figure out whether that's intentional (e.g. a table that's only ever touched through admin-only RPC functions, so no direct table policy is needed) — mention it to me in one line if relevant, but don't stop the work for it

**7. Create the first admin account directly via SQL (no app-based signup needed)**
Creating an admin through the app's normal signup flow runs into the email-confirmation problem (turning off "Confirm email" is a dashboard setting you can't reach). So create an already-confirmed admin directly:

```sql
do $$
declare
  v_user_id uuid := gen_random_uuid();
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, recovery_token,
    email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000', v_user_id, 'authenticated', 'authenticated',
    '{{ADMIN_EMAIL}}',
    extensions.crypt('{{ADMIN_PASSWORD}}', extensions.gen_salt('bf')),
    now(), '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('username', '{{ADMIN_USERNAME}}'),
    now(), now(), '', '', '', ''
  );

  insert into auth.identities (
    id, user_id, provider_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  ) values (
    gen_random_uuid(), v_user_id, v_user_id::text,
    jsonb_build_object('sub', v_user_id::text, 'email', '{{ADMIN_EMAIL}}'),
    'email', now(), now(), now()
  );

  -- The profiles row should auto-create via the on_auth_user_created trigger.
  -- Insert into the admins table in a separate statement after that, using
  -- the same v_user_id:
  insert into public.admins (id, note)
  values (v_user_id, 'First admin (auto-created)')
  on conflict (id) do nothing;
end $$;
```
> Table/column names can differ by schema — check the actual schema file and adjust the `admins` table name/columns if needed. If there's no trigger auto-creating a `profiles`-type row, insert that manually too.

**8. Wire both HTML files with the Supabase config**
- Find placeholders like `YOUR_SUPABASE_PROJECT_URL` / `YOUR_SUPABASE_ANON_KEY` and replace them with my real URL and key from the fill-in block
- **Important safety check:** if the HTML has any other third-party SDK (Firebase, etc.) being initialized with placeholder config (`YOUR_FIREBASE_...`-style) — first grep the whole file to see whether that SDK is actually used anywhere (real calls like `getDatabase(`, `signInWithEmailAndPassword(`, etc.). If it's only imported and initialized but never actually called anywhere else, safely remove/neutralize that init code (because initializing with placeholder config will throw and can crash the entire app). If it genuinely is used, don't remove it — tell me it needs real config instead

**9. Optional full rebranding — only do this if I gave you both `APP_FULL_NAME` and a logo image file**
If I did NOT give both, skip this entire step and leave all existing app name/logo/branding text exactly as-is in the HTML — do not rebrand partially.

If I DID give both:
1. Work out a 3-letter uppercase short code from `APP_FULL_NAME` (e.g. first letter of each of the first 3 words, or first 3 letters of the first word if it's a single word — use your judgment to pick something that reads naturally)
2. Read through the HTML file(s) and find every place the *current* app brand name/short-code appears repeatedly (page `<title>`, splash/header text, login/signup screen headings, app-bar titles, etc.) — this is usually easy to spot since the same short brand word repeats in many places
3. Replace every one of those occurrences with my new `APP_FULL_NAME` (or the new short code, matching how the old one was used — e.g. if the old one showed "XYZ TOUR" as a big splash title, show "{new short code} TOUR" or the full new name, whichever reads better in that spot) consistently across every file
4. Do **not** touch unrelated "Powered by ..." builder/platform credit lines that are not the app's own brand — only replace the client-facing app name, not a third-party attribution footer
5. Replace the logo: find every place the current logo image is referenced (an `<img src="...">`, a CSS `background-image`, a base64 data URI, etc.) and swap in my provided logo image the same way (same embedding method as the original, so nothing breaks)
6. Use `APP_FULL_NAME` for the `app_name` seed value in step 3 as well

**10. Self-verify (don't ask me to manually test in the app UI)**
Instead of telling me to go test in the app at the end, verify things yourself via SQL/logs:
- Table count and function count match what's expected (`select count(*) from pg_proc ...` etc.)
- `list_edge_functions` shows everything ACTIVE
- Confirm with one query that the admin account really has `email_confirmed_at` set and is in the `admins` table
- Re-run `get_advisors` and check nothing critical was missed

Only ask me to "go test it" for things you genuinely cannot verify from the backend (e.g. whether a push notification actually reached a phone).

**11. What to hand back to me**
- All the fully updated HTML files, ready to download
- A short summary — what you did, as a one-line-per-item list
- **A detailed, step-by-step guide only for the things you genuinely couldn't do yourself** (not possible via Supabase MCP tools) — for each one, name the exact dashboard menu, tab, and button, and exactly where to click and what value to enter. Each step should be clear enough to follow without needing a screenshot
- This manual-only list will typically include (context-dependent): turning off the "Confirm email" dashboard toggle (for future regular user signups), creating a Firebase service account key and adding it to edge function secrets for push notifications, setting an SMS webhook secret (if applicable), and rebuilding/reinstalling the Android APK after the HTML files are updated

### Rules you always follow
- Don't ask me a pile of questions before starting — make a reasonable assumption for anything unclear and proceed; tell me what you assumed in one line at the end
- Don't skip steps or say "do the rest yourself" — finish everything that's possible through your tools
- The app must work correctly with only the 5 required values below filled in — nothing else should ever be required
- Never repeat a secret/password back in plain chat text (beyond using it inside SQL)
- Answer in Bengali

---

## FILL IN YOUR VALUES BELOW

```
SUPABASE_URL = 
SUPABASE_PUBLISHABLE_KEY = 
ADMIN_EMAIL = 
ADMIN_PASSWORD = 
ADMIN_USERNAME = 
```

### Optional — only fill in if you want full rebranding (needs a logo file attached too)
```
APP_FULL_NAME (optional) = 
```

## END OF PROMPT (stop copying here)
