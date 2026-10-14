-- ============================================================
-- INDEXES (beyond primary keys / the two unique indexes already
-- created inside 01_schema.sql)
-- Run AFTER 01_schema.sql
-- ============================================================
CREATE INDEX IF NOT EXISTS ai_chats_user_created_idx ON public.ai_chats USING btree (user_id, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS app_update_package_name_unique ON public.app_update USING btree (package_name);
CREATE UNIQUE INDEX IF NOT EXISTS device_fcm_tokens_token_key ON public.device_fcm_tokens USING btree (token);
CREATE INDEX IF NOT EXISTS idx_ff_api_key_pool_active ON public.ff_api_key_pool USING btree (provider, is_active, fail_count, last_used_at);
CREATE INDEX IF NOT EXISTS idx_ff_uid_lookup_log_oxn_id ON public.ff_uid_lookup_log USING btree (oxn_id);
CREATE INDEX IF NOT EXISTS idx_ff_uid_lookup_log_uid ON public.ff_uid_lookup_log USING btree (uid);
CREATE INDEX IF NOT EXISTS idx_ff_uid_lookup_log_user_id ON public.ff_uid_lookup_log USING btree (user_id);
CREATE INDEX IF NOT EXISTS idx_matches_timestamp ON public.matches USING btree (timestamp_ms);
CREATE INDEX IF NOT EXISTS idx_moderator_sessions_moderator ON public.moderator_sessions USING btree (moderator_id);
CREATE UNIQUE INDEX IF NOT EXISTS moderators_name_key ON public.moderators USING btree (name);
CREATE UNIQUE INDEX IF NOT EXISTS profiles_oxn_id_key ON public.profiles USING btree (oxn_id);
CREATE UNIQUE INDEX IF NOT EXISTS profiles_username_key ON public.profiles USING btree (username);
CREATE INDEX IF NOT EXISTS idx_sms_logs_match_status ON public.sms_logs USING btree (match_status);
CREATE INDEX IF NOT EXISTS idx_sms_logs_received_at ON public.sms_logs USING btree (received_at DESC);
CREATE INDEX IF NOT EXISTS idx_sms_logs_trx_id ON public.sms_logs USING btree (parsed_trx_id);
CREATE INDEX IF NOT EXISTS idx_support_tickets_status ON public.support_tickets USING btree (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_winner_requests_match ON public.winner_requests USING btree (match_id);
CREATE INDEX IF NOT EXISTS idx_winner_requests_status ON public.winner_requests USING btree (status);
