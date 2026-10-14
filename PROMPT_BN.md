# পুনরায় ব্যবহারযোগ্য প্রম্পট — Supabase ব্যাকএন্ড ফুল-অটো ডিপ্লয়

## ব্যবহারের নিয়ম
1. `supabase_backend_template.zip` attach করো (SQL এক্সপোর্ট + edge functions সহ)
2. তোমার HTML app ফাইল(গুলো) attach করো (user app, admin app — যতগুলো থাকে)
3. (ঐচ্ছিক — শুধু পুরো রিব্র্যান্ডিং চাইলে) তোমার অ্যাপের লোগো ইমেজ ফাইলটাও attach করো
4. প্রম্পটের নিচে **FILL IN YOUR VALUES** ব্লকে নিজের তথ্য বসাও
5. পুরো প্রম্পটটা কপি করে AI-কে (Claude, যার সাথে Supabase কানেক্ট করা আছে) পাঠাও

**শর্ত:** AI-এর সাথে অবশ্যই তোমার Supabase প্রজেক্ট MCP দিয়ে connect করা থাকতে হবে (Settings → Connectors → Supabase → Connect)।

---

## প্রম্পট (এখান থেকে কপি শুরু করো)

তুমি আমার জন্য একটা সম্পূর্ণ Supabase ব্যাকএন্ড ডিপ্লয়মেন্ট + ফ্রন্টএন্ড ওয়্যারিং-এর কাজ করবে, শুরু থেকে শেষ পর্যন্ত, নিজে থেকে, আমাকে ধাপে ধাপে জিজ্ঞেস না করে। আমি যা দিচ্ছি:

- একটা zip ফাইল, যেখানে আছে: extensions/schema/indexes/functions/triggers/policies/seed SQL ফাইল এবং একটা `edge-functions/` ফোল্ডার (একাধিক Deno edge function, প্রতিটার নিজের `index.ts`), এবং একটা `SETUP_GUIDE.md`
- একটা বা একাধিক HTML ফাইল (Android WebView অ্যাপের ফ্রন্টএন্ড কোড — user app / admin app)
- (হয়তো) অ্যাপের লোগো ইমেজ ফাইল
- আমার তথ্য, প্রম্পটের নিচে দেওয়া

### তোমার কাজের ধাপ (এই ক্রমেই করবে)

**১. জিপ পরীক্ষা**
- zip extract করো, ফোল্ডার স্ট্রাকচার দেখো, `SETUP_GUIDE.md` থাকলে পড়ো
- SQL ফাইলগুলোর ক্রম বুঝে নাও (সাধারণত: extensions → schema → indexes → functions → triggers → policies → seed)

**২. স্কিমা প্রয়োগের আগে বাগ চেক**
- schema ফাইলে যদি কোনো কলাম `DEFAULT nextval('xxx_id_seq'::regclass)` ব্যবহার করে কিন্তু সেই sequence কোথাও `CREATE SEQUENCE` দিয়ে তৈরি না হয়ে থাকে, সেটা ভাঙা — তখন সেই কলামটাকে `GENERATED ALWAYS AS IDENTITY` দিয়ে বদলে দাও
- অন্য কোনো hardcoded reference (যেমন পুরনো প্রজেক্টের ref/UUID) থাকলে নোট করে রাখো, পরের ধাপে ঠিক করবে

**৩. প্রয়োগের ক্রম (Supabase MCP-এর apply_migration/execute_sql tool দিয়ে)**
1. extensions (`uuid-ossp`, `pgcrypto`, `pg_net` — যা যা লাগে)
2. schema (উপরের বাগ ফিক্স সহ)
3. indexes
4. functions — ফাইলটা বড় হলে ফাংশন বাউন্ডারি ধরে কয়েক ভাগে ভাগ করে প্রয়োগ করো, কোনো ফাংশন বাদ না দিয়ে
5. triggers
6. policies (RLS enable + প্রতিটা policy)
7. seed data — `app_name`-এর জায়গায় আমি `APP_FULL_NAME` দিলে সেটা বসাও, না দিলে seed ফাইলের ডিফল্ট জেনেরিক মানই রেখে দাও; `package_name`-ও একইভাবে — আমি দিলে বসাও, না দিলে ডিফল্ট প্লেসহোল্ডার রেখে শেষের সামারিতে জানিয়ে দাও যে এটা পরে আসল Android app ID দিয়ে বদলাতে হবে

**৪. ফাংশনের ভেতরে hardcoded URL/ref খুঁজে ঠিক করা**
- কোনো ফাংশনে (যেমন push notification trigger-এর `net.http_post` কল) অন্য কোনো পুরনো/প্লেসহোল্ডার প্রজেক্টের URL/ref hardcoded থাকলে, সেটা আমার আসল প্রজেক্ট রেফ (নিচের URL থেকে বের করা) দিয়ে বদলে দাও, প্রয়োগ করার সময়ই — আমাকে জিজ্ঞেস না করে

**৫. Edge Functions ডিপ্লয়**
- `edge-functions/`-এর প্রতিটা সাবফোল্ডার = একটা function, ফোল্ডারের নাম-ই slug
- প্রতিটার জন্য `deploy_edge_function` কল করো, `index.ts`-এর পুরো কনটেন্ট হুবহু দিয়ে
- `verify_jwt` ঠিক করো: নিজে auth/secret চেক করে এমন ফাংশন (webhook, কাস্টম লগইন) → `false`; সাধারণ লগইন করা ইউজারের JWT আশা করে এমন ফাংশন → `true`; নিশ্চিত না হলে কোড পড়ে বোঝো
- Free Fire UID lookup বা AI chat-এর মতো provider-নির্ভর ফিচার **কোনো provider সেটআপ ছাড়াই** ঠিকঠাক কাজ করতে হবে (কোডে আগে থেকেই "not configured" গ্রেসফুল ফলব্যাক আছে) — provider key না থাকাটা কোনো এরর হিসেবে ধরবে না, আমাকে জিজ্ঞেসও করবে না। পরে দরকার হলে অ্যাডমিন প্যানেল দিয়ে আমি নিজে যোগ করে নেব

**৬. অ্যাডভাইজর চেক**
- `get_advisors` (security) চালাও। RLS enabled কিন্তু policy নেই এমন warning এলে ইচ্ছাকৃত কিনা বুঝে নাও, দরকার হলে এক লাইনে জানাও, কাজ থামিও না

**৭. প্রথম অ্যাডমিন অ্যাকাউন্ট সরাসরি SQL দিয়ে তৈরি**
অ্যাপের সাইনআপ ফ্লো দিয়ে অ্যাডমিন বানাতে গেলে email-confirmation-এর ঝামেলা হয়। তাই সরাসরি SQL দিয়ে already-confirmed অ্যাডমিন বানাও:

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

  -- profiles রো অটো-তৈরি হবে on_auth_user_created ট্রিগার দিয়ে।
  -- admins insert-টা ওই ট্রিগার শেষ হওয়ার পর আলাদা statement-এ করো, একই v_user_id দিয়ে:
  insert into public.admins (id, note)
  values (v_user_id, 'প্রথম অ্যাডমিন (auto-created)')
  on conflict (id) do nothing;
end $$;
```
> স্কিমাভেদে টেবিল/কলামের নাম আলাদা হতে পারে — schema ফাইল দেখে `admins` টেবিলের আসল নাম/কলাম বসাও। `profiles`-জাতীয় টেবিলে trigger থেকে অটো insert না হলে সেটাও ম্যানুয়ালি insert করে দাও।

**৮. দুটো HTML ফাইলেই Supabase কনফিগ বসানো**
- `YOUR_SUPABASE_PROJECT_URL` / `YOUR_SUPABASE_ANON_KEY`-জাতীয় প্লেসহোল্ডার খুঁজে আমার আসল URL/key বসাও
- **সেফটি চেক:** HTML-এ অন্য কোনো third-party SDK (Firebase ইত্যাদি) placeholder কনফিগ দিয়ে init হলে — সেটা আসলে কোথাও ব্যবহার হচ্ছে কিনা (real call আছে কিনা) চেক করো; ব্যবহার না হলে সেই init কোড নিরাপদে বাদ দাও (নাহলে placeholder config দিয়ে ক্র্যাশ করে পুরো অ্যাপ ভাঙতে পারে); সত্যিই ব্যবহার হলে বাদ না দিয়ে আমাকে জানাও

**৯. ঐচ্ছিক পুরো রিব্র্যান্ডিং — শুধু তখনই করবে যখন আমি `APP_FULL_NAME` আর একটা লোগো ফাইল দুটোই দিয়েছি**
দুটোর একটাও না দিলে এই পুরো ধাপ স্কিপ করো — HTML-এর বর্তমান অ্যাপ নাম/লোগো/ব্র্যান্ডিং টেক্সট যেমন আছে তেমনই রেখে দাও, আংশিক রিব্র্যান্ড করবে না।

দুটোই দিলে:
1. `APP_FULL_NAME` থেকে একটা ৩-অক্ষরের ক্যাপিটাল শর্ট কোড বানাও (যেমন প্রথম ৩টা শব্দের প্রথম অক্ষর, অথবা এক শব্দ হলে সেই শব্দের প্রথম ৩ অক্ষর — যেটা স্বাভাবিক শোনায় সেটা বেছে নাও)
2. HTML ফাইল(গুলো) পড়ে বর্তমান ব্র্যান্ড নাম/শর্ট-কোড যেখানে যেখানে বারবার এসেছে সেগুলো খুঁজে বের করো (page `<title>`, স্প্ল্যাশ/হেডার টেক্সট, লগইন/সাইনআপ স্ক্রিনের হেডিং, app-bar টাইটেল ইত্যাদি)
3. প্রতিটা জায়গায় সেটা নতুন `APP_FULL_NAME` (বা নতুন শর্ট কোড, পুরনোটা যেভাবে ব্যবহার হয়েছিল সেভাবেই — যেমন স্প্ল্যাশে বড় টাইটেল হিসেবে "XYZ TOUR" থাকলে "{নতুন শর্ট কোড} TOUR" বা পুরো নতুন নাম, যেটা সেখানে ভালো মানায়) দিয়ে বদলে দাও, সব ফাইলে সমানভাবে
4. **"Powered by ..." টাইপ builder/platform credit লাইন বদলাবে না** — শুধু ক্লায়েন্ট-facing অ্যাপ নাম বদলাবে, কোনো third-party attribution ফুটার না
5. লোগো বদলাও: বর্তমান লোগো ইমেজ যেখানে যেখানে রেফারেন্স করা আছে (`<img src="...">`, CSS `background-image`, base64 data URI ইত্যাদি) সেখানে আমার দেওয়া নতুন লোগো একই পদ্ধতিতে বসাও (আগে যেভাবে embed করা ছিল ঠিক সেভাবেই, যাতে কিছু ভেঙে না যায়)
6. `APP_FULL_NAME`-টাই ধাপ ৩-এর seed-এর `app_name` মান হিসেবেও ব্যবহার করো

**১০. নিজে নিজে ভেরিফাই করা**
শেষে UI-তে গিয়ে ম্যানুয়ালি টেস্ট করতে বলার বদলে নিজে SQL/log দিয়ে যাচাই করো: টেবিল/ফাংশন সংখ্যা মিলছে কিনা, `list_edge_functions` সব ACTIVE কিনা, অ্যাডমিন অ্যাকাউন্ট কনফার্মড আর `admins` টেবিলে আছে কিনা (এক query দিয়ে), `get_advisors` আবার চালিয়ে critical কিছু বাদ পড়েনি তো দেখো। শুধু সত্যিকারের ব্যতিক্রম ছাড়া (যেমন push notification আসলেই ফোনে পৌঁছাচ্ছে কিনা) কোনো ম্যানুয়াল টেস্ট চাইবে না।

**১১. আমাকে যা ফেরত দেবে**
- সম্পূর্ণ আপডেটেড HTML ফাইল(গুলো), ডাউনলোডযোগ্য
- সংক্ষিপ্ত বাংলা সামারি — কী কী করেছ, প্রতিটা এক লাইনে
- **শুধু সেই কাজগুলোর বিস্তারিত ধাপে-ধাপে বাংলা গাইড যেগুলো তুমি নিজে করতে পারোনি** — প্রতিটার জন্য নির্দিষ্ট ড্যাশবোর্ড মেনু/ট্যাব/বাটনের নাম, কোথায় ক্লিক করতে হবে, কী মান বসাতে হবে। স্ক্রিনশট ছাড়াই অনুসরণযোগ্য হতে হবে
- এতে সাধারণত থাকবে: "Confirm email" টগল অফ করা, Firebase push notification secrets বসানো, SMS webhook secret বসানো (থাকলে), HTML আপডেটের পর Android APK rebuild করা

### নিয়ম যা সবসময় মানবে
- শুরুর আগে একগাদা প্রশ্ন করবে না — অস্পষ্ট কিছুতে যুক্তিসঙ্গত ধারণা নিয়ে এগিয়ে যাও, শেষে এক লাইনে জানাও কী ধারণা নিয়েছ
- কোনো ধাপ স্কিপ করবে না
- **নিচের ৫টা মান দিলেই যেন অ্যাপ পুরোপুরি কাজ করে** — এর বাইরে আর কিছুই বাধ্যতামূলক না
- কোনো secret/password প্লেইনটেক্সটে চ্যাটে repeat করবে না (SQL-এ ব্যবহার করা ছাড়া)
- সব উত্তর বাংলায় দেবে

---

## FILL IN YOUR VALUES BELOW

```
SUPABASE_URL = 
SUPABASE_PUBLISHABLE_KEY = 
ADMIN_EMAIL = 
ADMIN_PASSWORD = 
ADMIN_USERNAME = 
```

### ঐচ্ছিক — শুধু পুরো রিব্র্যান্ডিং চাইলে ভরো (লোগো ফাইলও attach করতে হবে)
```
APP_FULL_NAME (ঐচ্ছিক) = 
```

## প্রম্পট শেষ (এখানে কপি থামাও)
