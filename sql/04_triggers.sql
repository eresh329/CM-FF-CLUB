-- ============================================================
-- TRIGGERS
-- Run AFTER 03_functions.sql
-- ============================================================

-- 1) Auto-create a profiles row (with a unique 5-digit oxn_id) whenever
--    someone signs up via Supabase Auth.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 2) When a new deposit_requests row is inserted, immediately try to
--    auto-match it against any SMS that already arrived (race-condition
--    safety net for process_sms_payment()).
DROP TRIGGER IF EXISTS trg_match_deposit_with_existing_sms ON public.deposit_requests;
CREATE TRIGGER trg_match_deposit_with_existing_sms
  AFTER INSERT ON public.deposit_requests
  FOR EACH ROW EXECUTE FUNCTION public.try_match_deposit_with_existing_sms();

-- 3) Fire a push notification (via the bright-api edge function) whenever
--    a new row is inserted into notifications.
DROP TRIGGER IF EXISTS on_notification_insert ON public.notifications;
CREATE TRIGGER on_notification_insert
  AFTER INSERT ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.trigger_send_push();
