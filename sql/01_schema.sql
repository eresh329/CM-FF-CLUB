-- ============================================================
-- SCHEMA: tables, columns, defaults, checks, primary keys
-- Generated from the live OXN-TOUR Supabase project
-- ============================================================

CREATE TABLE IF NOT EXISTS public."profiles" (
  "id" uuid NOT NULL,
  "username" text NOT NULL UNIQUE,
  "email" text NOT NULL,
  "phone" text,
  "oxn_id" text UNIQUE,
  "deposit" numeric DEFAULT 0,
  "winning" numeric DEFAULT 0,
  "matches_played" integer DEFAULT 0,
  "device_id" text,
  "photo_base64" text,
  "banned" boolean DEFAULT false,
  "ban_reason" text,
  "ban_type" text,
  "ban_until" timestamptz,
  "created_at" timestamptz DEFAULT now(),
  "last_seen_notif_at" timestamptz,
  "leaderboard_name" text,
  "leaderboard_name_updated_at" timestamptz,
  "spin_last_at" timestamptz,
  "spin_br_wins" integer DEFAULT 0 NOT NULL,
  "spin_cs_wins" integer DEFAULT 0 NOT NULL,
  "spin_lw_wins" integer DEFAULT 0 NOT NULL,
  "spin_all_wins" integer DEFAULT 0 NOT NULL,
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."admins" (
  "id" uuid NOT NULL,
  "note" text,
  "created_at" timestamptz DEFAULT now(),
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."banned_devices" (
  "device_id" text NOT NULL,
  "reason" text,
  "ban_type" text,
  "ban_until" timestamptz,
  "uid" uuid,
  "username" text,
  "banned_at" timestamptz DEFAULT now(),
  PRIMARY KEY ("device_id")
);

CREATE TABLE IF NOT EXISTS public."deposit_requests" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "user_id" uuid NOT NULL,
  "amount" numeric NOT NULL,
  "method" text NOT NULL,
  "trx_id" text NOT NULL,
  "status" text DEFAULT 'pending'::text,
  "created_at" timestamptz DEFAULT now(),
  "processed_at" timestamptz,
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."withdraw_requests" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "user_id" uuid NOT NULL,
  "amount" numeric NOT NULL,
  "method" text NOT NULL,
  "mobile_number" text NOT NULL,
  "status" text DEFAULT 'pending'::text,
  "created_at" timestamptz DEFAULT now(),
  "processed_at" timestamptz,
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."transactions" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "user_id" uuid NOT NULL,
  "type" text NOT NULL,
  "amount" numeric NOT NULL,
  "status" text DEFAULT 'Success'::text,
  "method" text,
  "note" text,
  "created_at" timestamptz DEFAULT now(),
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."categories" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "name" text NOT NULL,
  "img" text,
  "rules" text,
  "created_at" timestamptz DEFAULT now(),
  "cat_title_enabled" boolean DEFAULT false,
  "cat_title_text" text,
  "cat_title_position" text DEFAULT 'center'::text,
  "default_title" text,
  "slot_mode" text CHECK (slot_mode IS NULL OR (slot_mode = ANY (ARRAY['off'::text, 'solo'::text, 'duo'::text, 'squad'::text]))),
  "slot_mandatory" boolean DEFAULT false NOT NULL,
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."category_match_counter" (
  "category_id" uuid NOT NULL,
  "counter" integer DEFAULT 0,
  PRIMARY KEY ("category_id")
);

CREATE TABLE IF NOT EXISTS public."matches" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "category_id" uuid,
  "match_num" integer,
  "title" text,
  "match_time" text,
  "timestamp_ms" bigint,
  "type" text,
  "map" text,
  "entry" numeric DEFAULT 0,
  "total_prize" numeric DEFAULT 0,
  "per_kill" numeric DEFAULT 0,
  "total" integer DEFAULT 48,
  "status" text DEFAULT 'Upcoming'::text,
  "prize_desc" text,
  "joined" integer DEFAULT 0,
  "room_id" text,
  "room_pass" text,
  "winner_name" text,
  "winner_amount" numeric,
  "created_at" timestamptz DEFAULT now(),
  "results_finalized_at" timestamptz,
  "archived" boolean DEFAULT false NOT NULL,
  "results_updated_at" timestamptz,
  "auto_slot" boolean DEFAULT false NOT NULL,
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."match_participants" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "match_id" uuid,
  "ign" text NOT NULL,
  "joined_by" uuid NOT NULL,
  "kills" integer DEFAULT 0,
  "win" numeric DEFAULT 0,
  "slot" integer,
  "joined_at" timestamptz DEFAULT now(),
  "paid_deposit" numeric DEFAULT 0,
  "paid_winning" numeric DEFAULT 0,
  "admin_position" text,
  "admin_prize" numeric,
  "admin_kills" integer,
  "starred" boolean DEFAULT false,
  "position" integer,
  "via_coupon" boolean DEFAULT false NOT NULL,
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."notifications" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "title" text NOT NULL,
  "body" text NOT NULL,
  "to_user_id" uuid,
  "created_at" timestamptz DEFAULT now(),
  "category" text DEFAULT 'app'::text,
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."device_fcm_tokens" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "user_id" uuid NOT NULL,
  "token" text NOT NULL UNIQUE,
  "updated_at" timestamptz DEFAULT now(),
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."app_settings" (
  "id" integer DEFAULT 1 NOT NULL CHECK (id = 1),
  "app_name" text,
  "app_logo" text,
  "notice" text,
  "bkash_number" text,
  "nagad_number" text,
  "rocket_number" text,
  "how_to_add_money_link" text,
  "how_to_get_room_id_link" text,
  "how_to_play_link" text,
  "support_link" text,
  "shop_link" text,
  "show_participants" boolean DEFAULT true,
  "dev_photo" text,
  "dev_about" text,
  "dev_notice" text,
  "dev_telegram_link" text,
  "dev_whatsapp_link" text,
  "dev_maintenance_notice" text,
  "dev_hide" boolean DEFAULT false,
  "dev_maintenance" boolean DEFAULT false,
  "show_popup" boolean DEFAULT false,
  "popup_text" text,
  "banners" jsonb DEFAULT '[]'::jsonb,
  "updated_at" timestamptz DEFAULT now(),
  "admin_pin" text DEFAULT '1234'::text,
  "channel_link" text,
  "ai_support_enabled" boolean DEFAULT true NOT NULL,
  "telegram_support_enabled" boolean DEFAULT true NOT NULL,
  "uid_lookup_unlimited" boolean DEFAULT false NOT NULL,
  "how_to_withdraw_link" text,
  "shop_mode" text DEFAULT 'shop'::text NOT NULL CHECK (shop_mode = ANY (ARRAY['shop'::text, 'topup'::text, 'product'::text])),
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."topup_packages" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "name" text NOT NULL,
  "price" numeric NOT NULL,
  "created_at" timestamptz DEFAULT now(),
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."topup_orders" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "user_id" uuid NOT NULL,
  "package_id" uuid,
  "package_name" text,
  "amount" numeric NOT NULL,
  "ff_uid" text NOT NULL,
  "status" text DEFAULT 'pending'::text,
  "created_at" timestamptz DEFAULT now(),
  "processed_at" timestamptz,
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."earnings_log" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "user_id" uuid NOT NULL,
  "amount" numeric NOT NULL,
  "match_id" uuid,
  "created_at" timestamptz DEFAULT now(),
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."daily_spin_pool" (
  "spin_date" date DEFAULT CURRENT_DATE NOT NULL,
  "winners_count" integer DEFAULT 0 NOT NULL,
  "max_winners" integer DEFAULT 4 NOT NULL,
  "br_wins" integer DEFAULT 0 NOT NULL,
  "cs_wins" integer DEFAULT 0 NOT NULL,
  "lw_wins" integer DEFAULT 0 NOT NULL,
  "all_wins" integer DEFAULT 0 NOT NULL,
  "br_limit" integer DEFAULT 2 NOT NULL,
  "cs_limit" integer DEFAULT 2 NOT NULL,
  "lw_limit" integer DEFAULT 2 NOT NULL,
  "all_limit" integer DEFAULT 1 NOT NULL,
  PRIMARY KEY ("spin_date")
);

CREATE TABLE IF NOT EXISTS public."spin_history" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "user_id" uuid NOT NULL,
  "result" text NOT NULL,
  "spin_date" date DEFAULT CURRENT_DATE NOT NULL,
  "created_at" timestamptz DEFAULT now() NOT NULL,
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."sms_logs" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "raw_sender" text,
  "raw_body" text NOT NULL,
  "parsed_trx_id" text,
  "parsed_amount" numeric,
  "parsed_method" text,
  "match_status" text DEFAULT 'processing'::text NOT NULL,
  "matched_deposit_id" uuid,
  "matched_user_id" uuid,
  "received_at" timestamptz DEFAULT now() NOT NULL,
  "processed_at" timestamptz,
  "parsed_sender_number" text,
  "parsed_txn_type" text,
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."consumed_trx_ids" (
  "trx_id" text NOT NULL,
  "sms_log_id" uuid,
  "deposit_request_id" uuid,
  "amount" numeric,
  "consumed_at" timestamptz DEFAULT now() NOT NULL,
  PRIMARY KEY ("trx_id")
);

CREATE TABLE IF NOT EXISTS public."system_secrets" (
  "key" text NOT NULL,
  "value" text NOT NULL,
  "updated_at" timestamptz DEFAULT now() NOT NULL,
  PRIMARY KEY ("key")
);

CREATE TABLE IF NOT EXISTS public."ff_api_key_pool" (
  "id" bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  "provider" text NOT NULL CHECK (provider = ANY (ARRAY['groq'::text, 'gameskinbo'::text])),
  "api_key" text NOT NULL,
  "label" text,
  "is_active" boolean DEFAULT true NOT NULL,
  "fail_count" integer DEFAULT 0 NOT NULL,
  "last_used_at" timestamptz,
  "last_error" text,
  "created_at" timestamptz DEFAULT now() NOT NULL,
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."ai_uid_lookups" (
  "user_id" uuid NOT NULL,
  "lookup_date" date DEFAULT CURRENT_DATE NOT NULL,
  "lookup_count" integer DEFAULT 0 NOT NULL,
  PRIMARY KEY ("user_id", "lookup_date")
);

CREATE TABLE IF NOT EXISTS public."ai_chats" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "user_id" uuid NOT NULL,
  "role" text NOT NULL CHECK (role = ANY (ARRAY['user'::text, 'assistant'::text])),
  "content" text NOT NULL,
  "is_uid_result" boolean DEFAULT false,
  "uid_name" text,
  "uid_value" text,
  "created_at" timestamptz DEFAULT now() NOT NULL,
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."ai_chat_providers" (
  "id" bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  "label" text NOT NULL,
  "base_url" text NOT NULL,
  "api_key" text NOT NULL,
  "model" text NOT NULL,
  "priority" integer DEFAULT 100 NOT NULL,
  "is_active" boolean DEFAULT true NOT NULL,
  "last_error" text,
  "last_used_at" timestamptz,
  "created_at" timestamptz DEFAULT now() NOT NULL,
  "fail_count" integer DEFAULT 0 NOT NULL,
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."ff_uid_providers" (
  "id" bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  "label" text NOT NULL,
  "base_url" text NOT NULL,
  "api_key_header" text DEFAULT 'x-api-key'::text NOT NULL,
  "api_key" text NOT NULL,
  "priority" integer DEFAULT 100 NOT NULL,
  "is_active" boolean DEFAULT true NOT NULL,
  "last_error" text,
  "last_used_at" timestamptz,
  "created_at" timestamptz DEFAULT now() NOT NULL,
  "fail_count" integer DEFAULT 0 NOT NULL,
  "monthly_limit" integer DEFAULT 100 NOT NULL,
  "used_count" integer DEFAULT 0 NOT NULL,
  "window_start" timestamptz,
  "window_count" integer DEFAULT 0 NOT NULL,
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."support_tickets" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "user_id" uuid NOT NULL,
  "oxn_id" text,
  "category" text NOT NULL CHECK (category = ANY (ARRAY['match'::text, 'deposit'::text, 'withdraw'::text, 'other'::text])),
  "match_id" uuid,
  "trx_id" text,
  "payment_method" text,
  "phone" text,
  "amount" numeric,
  "message" text NOT NULL,
  "status" text DEFAULT 'pending'::text NOT NULL CHECK (status = ANY (ARRAY['pending'::text, 'in_progress'::text, 'resolved'::text, 'rejected'::text])),
  "admin_note" text,
  "created_at" timestamptz DEFAULT now() NOT NULL,
  "resolved_at" timestamptz,
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."ff_uid_cache" (
  "uid" text NOT NULL,
  "name" text NOT NULL,
  "level" integer,
  "region" text,
  "raw" jsonb,
  "created_at" timestamptz DEFAULT now() NOT NULL,
  "updated_at" timestamptz DEFAULT now() NOT NULL,
  PRIMARY KEY ("uid")
);

CREATE TABLE IF NOT EXISTS public."ff_uid_lookup_log" (
  "id" bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  "user_id" uuid,
  "oxn_id" text,
  "username" text,
  "uid" text NOT NULL,
  "name" text,
  "level" integer,
  "region" text,
  "from_cache" boolean DEFAULT false NOT NULL,
  "created_at" timestamptz DEFAULT now() NOT NULL,
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."moderators" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "name" text NOT NULL UNIQUE,
  "password_hash" text NOT NULL,
  "active" boolean DEFAULT true NOT NULL,
  "created_at" timestamptz DEFAULT now() NOT NULL,
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."moderator_sessions" (
  "token" uuid DEFAULT gen_random_uuid() NOT NULL,
  "moderator_id" uuid NOT NULL,
  "created_at" timestamptz DEFAULT now() NOT NULL,
  "expires_at" timestamptz DEFAULT (now() + '12:00:00'::interval) NOT NULL,
  PRIMARY KEY ("token")
);

CREATE TABLE IF NOT EXISTS public."moderator_category_locks" (
  "moderator_id" uuid NOT NULL,
  "category_id" uuid NOT NULL,
  "locked_at" timestamptz DEFAULT now() NOT NULL,
  PRIMARY KEY ("moderator_id", "category_id")
);

CREATE TABLE IF NOT EXISTS public."winner_requests" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "match_id" uuid NOT NULL,
  "moderator_id" uuid NOT NULL,
  "moderator_name" text NOT NULL,
  "entries" jsonb NOT NULL,
  "description" text,
  "status" text DEFAULT 'pending'::text NOT NULL CHECK (status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])),
  "created_at" timestamptz DEFAULT now() NOT NULL,
  "reviewed_at" timestamptz,
  "reviewed_note" text,
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."products" (
  "id" bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  "name" text NOT NULL,
  "price" numeric NOT NULL,
  "image_url" text,
  "created_at" timestamptz DEFAULT now() NOT NULL,
  "description" text,
  "stock" integer DEFAULT 0 NOT NULL,
  "out_of_stock" boolean DEFAULT false NOT NULL,
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."spin_settings" (
  "id" integer DEFAULT 1 NOT NULL CHECK (id = 1),
  "max_winners_per_day" integer DEFAULT 4 NOT NULL,
  "br_daily_limit" integer DEFAULT 2 NOT NULL,
  "cs_daily_limit" integer DEFAULT 2 NOT NULL,
  "lw_daily_limit" integer DEFAULT 2 NOT NULL,
  "all_daily_limit" integer DEFAULT 1 NOT NULL,
  "updated_at" timestamptz DEFAULT now() NOT NULL,
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."app_update" (
  "id" integer DEFAULT 1 NOT NULL CHECK (id = 1),
  "version_code" integer DEFAULT 1 NOT NULL,
  "version_name" text DEFAULT '1.0.0'::text NOT NULL,
  "apk_url" text,
  "changelog" text,
  "force_update" boolean DEFAULT false NOT NULL,
  "updated_at" timestamptz DEFAULT now() NOT NULL,
  "package_name" text NOT NULL UNIQUE,
  PRIMARY KEY ("id")
);

-- ============================================================
-- unique index used by match_participants (partial unique)
-- ============================================================
CREATE UNIQUE INDEX IF NOT EXISTS uq_match_slot ON public.match_participants USING btree (match_id, slot) WHERE (slot IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS uq_ff_uid_providers_api_key ON public.ff_uid_providers USING btree (api_key);

-- ============================================================
-- FOREIGN KEYS (added after all tables exist)
-- ============================================================
ALTER TABLE public."profiles" ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES auth.users("id") ON DELETE CASCADE;
ALTER TABLE public."admins" ADD CONSTRAINT "admins_id_fkey" FOREIGN KEY ("id") REFERENCES auth.users("id") ON DELETE CASCADE;
ALTER TABLE public."deposit_requests" ADD CONSTRAINT "deposit_requests_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES auth.users("id") ON DELETE CASCADE;
ALTER TABLE public."withdraw_requests" ADD CONSTRAINT "withdraw_requests_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES auth.users("id") ON DELETE CASCADE;
ALTER TABLE public."transactions" ADD CONSTRAINT "transactions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES auth.users("id") ON DELETE CASCADE;
ALTER TABLE public."category_match_counter" ADD CONSTRAINT "category_match_counter_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES public.categories("id") ON DELETE CASCADE;
ALTER TABLE public."matches" ADD CONSTRAINT "matches_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES public.categories("id") ON DELETE SET NULL;
ALTER TABLE public."match_participants" ADD CONSTRAINT "match_participants_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES public.matches("id") ON DELETE CASCADE;
ALTER TABLE public."match_participants" ADD CONSTRAINT "match_participants_joined_by_fkey" FOREIGN KEY ("joined_by") REFERENCES auth.users("id") ON DELETE CASCADE;
ALTER TABLE public."notifications" ADD CONSTRAINT "notifications_to_user_id_fkey" FOREIGN KEY ("to_user_id") REFERENCES auth.users("id") ON DELETE CASCADE;
ALTER TABLE public."device_fcm_tokens" ADD CONSTRAINT "device_fcm_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES auth.users("id") ON DELETE CASCADE;
ALTER TABLE public."topup_orders" ADD CONSTRAINT "topup_orders_package_id_fkey" FOREIGN KEY ("package_id") REFERENCES public.topup_packages("id") ON DELETE SET NULL;
ALTER TABLE public."topup_orders" ADD CONSTRAINT "topup_orders_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES auth.users("id") ON DELETE CASCADE;
ALTER TABLE public."earnings_log" ADD CONSTRAINT "earnings_log_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES public.matches("id") ON DELETE SET NULL;
ALTER TABLE public."earnings_log" ADD CONSTRAINT "earnings_log_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES auth.users("id") ON DELETE CASCADE;
ALTER TABLE public."spin_history" ADD CONSTRAINT "spin_history_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES auth.users("id") ON DELETE CASCADE;
ALTER TABLE public."consumed_trx_ids" ADD CONSTRAINT "consumed_trx_ids_sms_log_id_fkey" FOREIGN KEY ("sms_log_id") REFERENCES public.sms_logs("id") ON DELETE SET NULL;
ALTER TABLE public."consumed_trx_ids" ADD CONSTRAINT "consumed_trx_ids_deposit_request_id_fkey" FOREIGN KEY ("deposit_request_id") REFERENCES public.deposit_requests("id") ON DELETE SET NULL;
ALTER TABLE public."sms_logs" ADD CONSTRAINT "sms_logs_matched_deposit_id_fkey" FOREIGN KEY ("matched_deposit_id") REFERENCES public.deposit_requests("id") ON DELETE SET NULL;
ALTER TABLE public."sms_logs" ADD CONSTRAINT "sms_logs_matched_user_id_fkey" FOREIGN KEY ("matched_user_id") REFERENCES auth.users("id") ON DELETE SET NULL;
ALTER TABLE public."ai_uid_lookups" ADD CONSTRAINT "ai_uid_lookups_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES auth.users("id") ON DELETE CASCADE;
ALTER TABLE public."ai_chats" ADD CONSTRAINT "ai_chats_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES auth.users("id") ON DELETE CASCADE;
ALTER TABLE public."support_tickets" ADD CONSTRAINT "support_tickets_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES auth.users("id") ON DELETE CASCADE;
ALTER TABLE public."support_tickets" ADD CONSTRAINT "support_tickets_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES public.matches("id") ON DELETE SET NULL;
ALTER TABLE public."ff_uid_lookup_log" ADD CONSTRAINT "ff_uid_lookup_log_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES public.profiles("id") ON DELETE SET NULL;
ALTER TABLE public."moderator_sessions" ADD CONSTRAINT "moderator_sessions_moderator_id_fkey" FOREIGN KEY ("moderator_id") REFERENCES public.moderators("id") ON DELETE CASCADE;
ALTER TABLE public."moderator_category_locks" ADD CONSTRAINT "moderator_category_locks_moderator_id_fkey" FOREIGN KEY ("moderator_id") REFERENCES public.moderators("id") ON DELETE CASCADE;
ALTER TABLE public."moderator_category_locks" ADD CONSTRAINT "moderator_category_locks_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES public.categories("id") ON DELETE CASCADE;
ALTER TABLE public."winner_requests" ADD CONSTRAINT "winner_requests_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES public.matches("id") ON DELETE CASCADE;
ALTER TABLE public."winner_requests" ADD CONSTRAINT "winner_requests_moderator_id_fkey" FOREIGN KEY ("moderator_id") REFERENCES public.moderators("id") ON DELETE CASCADE;
