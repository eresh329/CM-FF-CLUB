-- ============================================================
-- ROW LEVEL SECURITY
-- Run AFTER 03_functions.sql and 04_triggers.sql
-- Enables RLS on every table, then recreates every policy exactly
-- as they exist in the live project. Tables with RLS enabled but no
-- policy below (admins, ai_chat_providers insert/update/delete side,
-- daily_spin_pool, earnings_log, ff_uid_providers select side is
-- covered, moderators, moderator_sessions, moderator_category_locks,
-- system_secrets, winner_requests direct access, ff_api_key_pool
-- select-only side) are intentionally locked down to SECURITY DEFINER
-- RPC calls only — that is correct, do not add open policies to them.
-- ============================================================

ALTER TABLE public.admins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_chat_providers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_uid_lookups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_update ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.banned_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.category_match_counter ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.consumed_trx_ids ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_spin_pool ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deposit_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.device_fcm_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.earnings_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ff_api_key_pool ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ff_uid_cache ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ff_uid_lookup_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ff_uid_providers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.match_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.moderator_category_locks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.moderator_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.moderators ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sms_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.spin_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.spin_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_secrets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.topup_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.topup_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.winner_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.withdraw_requests ENABLE ROW LEVEL SECURITY;

-- ai_chat_providers
CREATE POLICY "admins_manage_ai_chat_providers" ON public.ai_chat_providers FOR ALL USING (is_admin()) WITH CHECK (is_admin());

-- ai_chats
CREATE POLICY "own chat delete" ON public.ai_chats FOR DELETE USING (auth.uid() = user_id);
CREATE POLICY "own chat insert" ON public.ai_chats FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "own chat select" ON public.ai_chats FOR SELECT USING (auth.uid() = user_id);

-- ai_uid_lookups
CREATE POLICY "user can read own ai_uid_lookups" ON public.ai_uid_lookups FOR SELECT TO authenticated USING (user_id = auth.uid());

-- app_settings
CREATE POLICY "admin can read app settings" ON public.app_settings FOR SELECT USING (is_admin());
CREATE POLICY "admin can update app settings" ON public.app_settings FOR UPDATE USING (is_admin()) WITH CHECK (is_admin());
-- NOTE: app_settings has no public SELECT policy — the app reads it through
-- a SECURITY DEFINER RPC / the admin session, not a direct anon SELECT.
-- If your client reads app_settings directly as an anon user, add:
-- CREATE POLICY "anyone can read app settings" ON public.app_settings FOR SELECT USING (true);

-- app_update
CREATE POLICY "Anyone can read app_update" ON public.app_update FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "app_update_public_read" ON public.app_update FOR SELECT USING (true);
CREATE POLICY "app_update_admin_write" ON public.app_update FOR UPDATE USING (EXISTS (SELECT 1 FROM admins a WHERE a.id = auth.uid())) WITH CHECK (EXISTS (SELECT 1 FROM admins a WHERE a.id = auth.uid()));

-- banned_devices
CREATE POLICY "anyone can check banned devices" ON public.banned_devices FOR SELECT USING (true);

-- categories
CREATE POLICY "admin can manage categories" ON public.categories FOR ALL USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "anyone can read categories" ON public.categories FOR SELECT USING (true);

-- category_match_counter
CREATE POLICY "admin only counter" ON public.category_match_counter FOR ALL USING (is_admin()) WITH CHECK (is_admin());

-- consumed_trx_ids
CREATE POLICY "admins can view consumed_trx_ids" ON public.consumed_trx_ids FOR SELECT USING (is_admin());

-- deposit_requests
CREATE POLICY "app_version_gate_deposit_insert" ON public.deposit_requests AS RESTRICTIVE FOR INSERT WITH CHECK (app_version_ok());
CREATE POLICY "user can insert own deposit request" ON public.deposit_requests FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "user can view own deposit requests" ON public.deposit_requests FOR SELECT USING (auth.uid() = user_id OR is_admin());

-- device_fcm_tokens
CREATE POLICY "user can manage own token" ON public.device_fcm_tokens FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- ff_api_key_pool
CREATE POLICY "admin can manage ff api key pool" ON public.ff_api_key_pool FOR ALL USING (is_admin()) WITH CHECK (is_admin());

-- ff_uid_cache
CREATE POLICY "admins_manage_ff_uid_cache" ON public.ff_uid_cache FOR ALL USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "authenticated can read ff_uid_cache" ON public.ff_uid_cache FOR SELECT TO authenticated USING (true);

-- ff_uid_lookup_log
CREATE POLICY "admins_manage_ff_uid_lookup_log" ON public.ff_uid_lookup_log FOR ALL USING (is_admin()) WITH CHECK (is_admin());

-- ff_uid_providers
CREATE POLICY "admins_manage_ff_uid_providers" ON public.ff_uid_providers FOR ALL USING (is_admin()) WITH CHECK (is_admin());

-- match_participants
CREATE POLICY "joined users or admin can view participants" ON public.match_participants FOR SELECT USING (is_admin() OR has_joined_match(match_id));
-- NOTE: there is intentionally no direct INSERT/UPDATE/DELETE policy here —
-- joining, editing kills/results, and deleting participants all go through
-- SECURITY DEFINER functions (join_match, admin_finalize_match_results,
-- admin_refund_participant, etc). If you delete a match directly with
-- `DELETE FROM matches`, the ON DELETE CASCADE to match_participants
-- still requires a role that can bypass RLS on match_participants (the
-- service_role key, or a SECURITY DEFINER function) — deleting matches
-- as a plain authenticated/admin-flagged user via the anon/authenticated
-- role WILL be blocked by RLS on the cascade. Use a SECURITY DEFINER
-- "admin_delete_match" RPC (see the setup guide) rather than a raw
-- client-side `.delete()` call for matches with participants.

-- matches
CREATE POLICY "admin can manage matches" ON public.matches FOR ALL USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "anyone can read matches" ON public.matches FOR SELECT USING (true);

-- notifications
CREATE POLICY "admin can insert notifications" ON public.notifications FOR INSERT WITH CHECK (is_admin());
CREATE POLICY "user can view own or broadcast notifications" ON public.notifications FOR SELECT USING (to_user_id IS NULL OR to_user_id = auth.uid());

-- products
CREATE POLICY "admin can manage products" ON public.products FOR ALL USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "anyone can read products" ON public.products FOR SELECT USING (true);

-- profiles
CREATE POLICY "admin can view all profiles" ON public.profiles FOR SELECT USING (is_admin());
CREATE POLICY "user can read own profile" ON public.profiles FOR SELECT USING (auth.uid() = id);
-- NOTE: no direct UPDATE policy — profile edits go through
-- update_my_profile() / set_leaderboard_name() (SECURITY DEFINER).

-- sms_logs
CREATE POLICY "admins can view sms_logs" ON public.sms_logs FOR SELECT USING (is_admin());

-- spin_history
CREATE POLICY "user can read own spin history" ON public.spin_history FOR SELECT TO authenticated USING (user_id = auth.uid());

-- spin_settings
CREATE POLICY "anyone can read spin settings" ON public.spin_settings FOR SELECT USING (true);
CREATE POLICY "admin can update spin settings" ON public.spin_settings FOR UPDATE USING (is_admin()) WITH CHECK (is_admin());

-- support_tickets
CREATE POLICY "support_tickets_admin_all" ON public.support_tickets FOR ALL USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "support_tickets_insert_own" ON public.support_tickets FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "support_tickets_select_own" ON public.support_tickets FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- topup_orders
CREATE POLICY "user can view own orders" ON public.topup_orders FOR SELECT USING (auth.uid() = user_id OR is_admin());
-- NOTE: inserts go through request_topup_order() (SECURITY DEFINER).

-- topup_packages
CREATE POLICY "admin can manage topup packages" ON public.topup_packages FOR ALL USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "anyone can read topup packages" ON public.topup_packages FOR SELECT USING (true);

-- transactions
CREATE POLICY "admin can view all transactions" ON public.transactions FOR SELECT USING (is_admin());
CREATE POLICY "user can view own transactions" ON public.transactions FOR SELECT USING (auth.uid() = user_id);

-- withdraw_requests
CREATE POLICY "user can view own withdraw requests" ON public.withdraw_requests FOR SELECT USING (auth.uid() = user_id OR is_admin());
-- NOTE: inserts go through request_withdraw() (SECURITY DEFINER).

-- Tables with RLS enabled and NO policy at all (correct, on purpose —
-- these are only ever touched by SECURITY DEFINER functions running as
-- the function owner, which bypasses RLS):
--   admins, daily_spin_pool, earnings_log, moderators, moderator_sessions,
--   moderator_category_locks, system_secrets, winner_requests
