# টুর্নামেন্ট অ্যাপ — নতুন Supabase সেটআপ গাইড

এই ফোল্ডারে তোমার টুর্নামেন্ট অ্যাপের সম্পূর্ণ ব্যাকএন্ড (ডেটাবেজ স্কিমা, ফাংশন, ট্রিগার, সিকিউরিটি পলিসি এবং Edge Functions) রয়েছে। এই গাইড অনুসরণ করে যে কেউ একটা নতুন Supabase প্রজেক্টে পুরো সিস্টেমটা থেকে-শুরু-করে বসাতে পারবে।

## ফোল্ডার স্ট্রাকচার

```
supabase_export/
├── SETUP_GUIDE.md          ← এই ফাইল
├── sql/
│   ├── 00_extensions.sql   ← PostgreSQL extensions
│   ├── 01_schema.sql       ← সব টেবিল + কলাম + ফরেন কী
│   ├── 02_indexes.sql      ← ইনডেক্স
│   ├── 03_functions.sql    ← সব RPC ফাংশন (৭০+)
│   ├── 04_triggers.sql     ← ৩টা ট্রিগার
│   ├── 05_policies.sql     ← Row Level Security পলিসি
│   └── 06_seed.sql         ← শুরুর জন্য দরকারি ডিফল্ট রো
└── edge-functions/
    ├── bright-api/         ← FCM পুশ নোটিফিকেশন পাঠায়
    ├── sms-webhook/        ← bKash/Nagad/Rocket SMS থেকে অটো-ডিপোজিট
    ├── sms-backfill/       ← মিস হওয়া SMS ম্যানুয়ালি রিপ্রসেস করার জন্য
    ├── secure-login/       ← username দিয়ে লগইন (email client-এ যায় না)
    ├── ai-support/         ← AI চ্যাট সাপোর্ট + FF UID লুকআপ
    ├── ff-uid-lookup/      ← শুধু FF UID → নাম লুকআপ (rate-limited)
    ├── admin-uid-usage/    ← অ্যাডমিন প্যানেলে API key ইউজেজ দেখানোর জন্য
    └── ff-key-usage/       ← একটা নির্দিষ্ট key-র ইউজেজ চেক করার জন্য
```

---

## ধাপ ১ — নতুন Supabase প্রজেক্ট তৈরি

1. [supabase.com](https://supabase.com) এ গিয়ে একটা নতুন প্রজেক্ট বানাও।
2. Region হিসেবে **Southeast Asia (Singapore)** নিলে বাংলাদেশ থেকে লেটেন্সি কম হবে।
3. একটা শক্তিশালী Database Password সেট করে রাখো (পরে লাগবে না, কিন্তু সেভ করে রাখো)।
4. প্রজেক্ট তৈরি হয়ে গেলে **Project Settings → General** থেকে **Reference ID** (যেমন `abcdxyzproj`) কপি করে রাখো — এটা পরে API URL আর একটা ফাংশনে লাগবে।
5. **Project Settings → API** থেকে `anon` `public` key এবং `service_role` key কপি করে রাখো (এগুলো তোমার অ্যাপ + Edge Functions এ লাগবে)।

## ধাপ ২ — SQL ফাইলগুলো চালানো

Supabase Dashboard → **SQL Editor** → **New query** এ গিয়ে, নিচের ফাইলগুলো **ঠিক এই ক্রমে**, একটার পর একটা, পুরোটা কপি-পেস্ট করে **Run** করো:

1. `sql/00_extensions.sql`
2. `sql/01_schema.sql`
3. `sql/02_indexes.sql`
4. `sql/03_functions.sql`
5. `sql/04_triggers.sql` — ⚠️ চালানোর আগে ভেতরের `trigger_send_push()` ফাংশনে থাকা `iiywltreljfwpjactrdr` টুকু নিজের প্রজেক্টের Reference ID দিয়ে বদলে নাও (ধাপ ১-এ কপি করা ID)। এটা এখনো না করলেও ফাইল চলবে, কিন্তু পুশ নোটিফিকেশন কাজ করবে না যতক্ষণ না এটা ঠিক করো।
6. `sql/05_policies.sql`
7. `sql/06_seed.sql`

প্রতিটা ফাইল Run করার পর নিচে কোনো লাল Error দেখাচ্ছে কিনা চেক করে পরেরটায় যাও।

## ধাপ ৩ — Authentication সেটআপ

1. **Authentication → Providers** এ গিয়ে **Email** প্রোভাইডার চালু আছে কিনা দেখো (ডিফল্ট চালুই থাকে)।
2. **Authentication → Email Templates → Confirm signup** — যদি ইমেইল কনফার্মেশন ছাড়াই সাইনআপের সাথে সাথে লগইন করাতে চাও (এই অ্যাপ যেভাবে কাজ করে), তাহলে **Authentication → Settings → "Confirm email"** অপশনটা **বন্ধ (OFF)** করে দাও।
3. `handle_new_user()` ফাংশনটা (যেটা `03_functions.sql`-এ আছে) `auth.users`-এ নতুন সাইনআপ হলেই অটোমেটিক একটা `profiles` রো বানিয়ে দেবে, সাথে ইউনিক ৫-ডিজিটের `oxn_id`ও জেনারেট করবে — এটার জন্য আলাদা কিছু করা লাগবে না, `04_triggers.sql` চালালেই এটা কানেক্টেড হয়ে যাবে।

## ধাপ ৪ — প্রথম অ্যাডমিন অ্যাকাউন্ট বানানো

1. তোমার অ্যাপ (বা Supabase Dashboard → Authentication → Users → "Add user") দিয়ে একটা সাধারণ ইউজার অ্যাকাউন্ট সাইনআপ করো — এতে `profiles` টেবিলে একটা রো অটো তৈরি হবে।
2. সেই ইউজারের UUID (Authentication → Users থেকে কপি করো) নিয়ে SQL Editor-এ রান করো:
   ```sql
   insert into public.admins (id, note) values ('<সেই ইউজারের UUID>', 'প্রথম অ্যাডমিন');
   ```
3. এখন এই অ্যাকাউন্ট দিয়ে লগইন করলে সব অ্যাডমিন RPC ফাংশন (`is_admin()` চেক পাস করা সব ফাংশন) কাজ করবে।
4. (ঐচ্ছিক) `spin_daily_wheel()` ফাংশনে একটা "unlimited spin" মালিক-অ্যাকাউন্ট হার্ডকোড করা আছে (UUID: `b220ad4f-067b-4b9a-8db1-e6ef5233cdf8` — এটা আগের প্রজেক্টের owner UUID)। চাইলে `03_functions.sql`-এ এই ফাংশনটা খুঁজে বের করে সেই UUID-টা তোমার নিজের অ্যাকাউন্টের UUID দিয়ে বদলে আবার `CREATE OR REPLACE` করে দাও, নাহলে ঐ "owner" ব্রাঞ্চটা তোমার কারো কাজে লাগবে না (ক্ষতিও করবে না)।

## ধাপ ৫ — Edge Functions ডিপ্লয়

Edge Functions ডিপ্লয় করতে [Supabase CLI](https://supabase.com/docs/guides/cli) লাগবে:

```bash
npm install -g supabase
supabase login
supabase link --project-ref <তোমার-প্রজেক্ট-রেফ>
```

তারপর প্রতিটা ফাংশন ডিপ্লয় করো (এই `supabase_export` ফোল্ডারের ভেতর থেকে):

```bash
supabase functions deploy bright-api --no-verify-jwt
supabase functions deploy sms-webhook --no-verify-jwt
supabase functions deploy sms-backfill --no-verify-jwt
supabase functions deploy secure-login --no-verify-jwt
supabase functions deploy ai-support
supabase functions deploy ff-uid-lookup
supabase functions deploy admin-uid-usage
supabase functions deploy ff-key-usage
```

> `--no-verify-jwt` শুধু ঐ ফাংশনগুলোতে যেগুলো নিজেরাই ভেতরে auth চেক করে (secure-login, sms-webhook ইত্যাদি)। `ai-support`, `ff-uid-lookup`, `admin-uid-usage`, `ff-key-usage` এগুলো normal JWT ভেরিফিকেশন চায়, তাই flag ছাড়া ডিপ্লয় করো।

### Edge Function Secrets (এনভায়রনমেন্ট ভ্যারিয়েবল)

Dashboard → **Edge Functions → (প্রতিটা ফাংশন) → Secrets**, অথবা CLI দিয়ে:

```bash
supabase secrets set FCM_PROJECT_ID=xxxx FCM_CLIENT_EMAIL=xxxx FCM_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----..."
supabase secrets set SMS_WEBHOOK_SECRET=তোমার-নিজের-গোপন-স্ট্রিং
```

- `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, `FCM_PRIVATE_KEY` — এগুলো Firebase প্রজেক্টের একটা **Service Account** থেকে পাওয়া যায় (Firebase Console → Project Settings → Service Accounts → Generate new private key)। এগুলো `bright-api` ফাংশনের জন্য (পুশ নোটিফিকেশন পাঠাতে)।
- `SMS_WEBHOOK_SECRET` — যেকোনো একটা লম্বা র‍্যান্ডম স্ট্রিং, নিজে বানাও। SMS ফরোয়ার্ডার অ্যাপ যখন `sms-webhook`-এ কল করবে, তখন এই সিক্রেটটা `x-sms-secret` হেডারে পাঠাতে হবে — নাহলে রিকোয়েস্ট রিজেক্ট হবে।
- `SUPABASE_URL` এবং `SUPABASE_SERVICE_ROLE_KEY` Edge Functions-এ অটোমেটিক ইনজেক্টেড থাকে, আলাদা করে সেট করা লাগে না।

## ধাপ ৬ — Realtime API Keys ও Provider সেটআপ (ডেটা নয়, শুধু স্ট্রাকচার এক্সপোর্ট করা হয়েছে)

নিচের টেবিলগুলোর **স্ট্রাকচার** তৈরি হয়ে গেছে কিন্তু এগুলোতে কোনো আসল ডেটা/সিক্রেট কপি করা হয়নি (এটা ইচ্ছাকৃত — সিক্রেট কী কখনো এভাবে শেয়ার করা উচিত না):

- `ff_uid_providers` — Free Fire UID লুকআপের জন্য থার্ড-পার্টি API (যেমন gameskinbo) — অ্যাডমিন প্যানেল থেকে নতুন key যোগ করো।
- `ai_chat_providers` — AI চ্যাটের জন্য (Groq বা অন্য OpenAI-compatible API) — `base_url`, `api_key`, `model` অ্যাডমিন প্যানেল থেকে বসাও।
- `ff_api_key_pool` — লিগ্যাসি key pool (নতুন সেটআপে খালি রাখলেও চলবে)।
- `system_secrets` — কোনো অতিরিক্ত গোপন কী/টোকেন রাখার জেনেরিক টেবিল, দরকার হলে ব্যবহার করো।

এগুলো সব অ্যাডমিন প্যানেল (`ADMIN_RD_v10.html`) থেকেই যোগ/এডিট করা যায় — কোনো SQL লাগবে না।

## ধাপ ৭ — অ্যাপ সাইড কনফিগারেশন

তোমার অ্যাপ (Android WebView অথবা ওয়েব অ্যাপ) এবং অ্যাডমিন প্যানেলে Supabase কানেক্ট করতে এই দুটো লাগবে:

```js
const SUPABASE_URL = "https://<তোমার-প্রজেক্ট-রেফ>.supabase.co";
const SUPABASE_ANON_KEY = "<ধাপ ১ থেকে কপি করা anon/public key>";
```

`service_role` key **কখনো** ক্লায়েন্ট-সাইড কোডে (অ্যাপ বা অ্যাডমিন HTML-এ) বসানো যাবে না — এটা শুধু Edge Functions-এর ভেতরে (যেখানে এটা অটোমেটিক পাওয়া যায়) ব্যবহার হয়।

## ধাপ ৮ — যাচাই করো (Sanity Check)

1. অ্যাপ দিয়ে একটা টেস্ট অ্যাকাউন্ট সাইনআপ করো → `profiles` টেবিলে রো তৈরি হলো কিনা দেখো।
2. অ্যাডমিন প্যানেলে লগইন করো (ধাপ ৪-এ বানানো অ্যাকাউন্ট দিয়ে) → Categories/Matches অ্যাড করতে পারছো কিনা দেখো।
3. একটা ম্যাচ বানিয়ে জয়েন করার চেষ্টা করো (`join_match` RPC)।
4. **Database → Advisors** এ গিয়ে Supabase-এর নিজস্ব সিকিউরিটি/পারফরম্যান্স চেকার চালিয়ে দেখো কোনো ওয়ার্নিং আসে কিনা।

## গুরুত্বপূর্ণ নোট

- **ম্যাচ ডিলিট করা**: `match_participants` টেবিলে সরাসরি কোনো DELETE পলিসি ইচ্ছাকৃতভাবেই নেই — তাই `matches` থেকে সরাসরি `DELETE` করলে (CASCADE-এর মাধ্যমে) RLS-এর কারণে ফেইল করতে পারে যদি participant থাকে। ম্যাচ ডিলিট/আর্কাইভের জন্য `admin_archive_match()` / `admin_unarchive_match()` ব্যবহার করো, অথবা service_role দিয়ে ডিলিট করো।
- সব টাকা-পয়সার কাজ (ডিপোজিট, উইথড্র, ম্যাচ জয়েন, রেজাল্ট ফাইনালাইজ) **SECURITY DEFINER ফাংশনের ভেতর দিয়ে** হয় — কখনো ক্লায়েন্ট থেকে সরাসরি `profiles.deposit` বা `profiles.winning` কলাম UPDATE করার চেষ্টা কোরো না, RLS সেটা ব্লক করবে এবং করাও উচিত না (এতে রেসকন্ডিশন/জালিয়াতির ঝুঁকি থাকে)।
- `04_triggers.sql`-এর `trigger_send_push()` ফাংশনের ভেতরের URL অবশ্যই নিজের প্রজেক্ট রেফ দিয়ে বদলাতে হবে (ধাপ ২-এ বলা হয়েছে), নাহলে নোটিফিকেশন insert হবে কিন্তু পুশ যাবে না।
