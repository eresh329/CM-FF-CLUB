-- ============================================================
-- SEED DATA — minimal rows the app expects to exist (id = 1
-- singleton rows). Fill in the real values afterwards from the
-- admin panel — do NOT commit real payment numbers/PINs to git.
-- Run AFTER 05_policies.sql
-- ============================================================

INSERT INTO public.app_settings (id, app_name, admin_pin, show_participants, shop_mode)
VALUES (1, 'My Tournament App', '1234', true, 'shop')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.spin_settings (id, max_winners_per_day, br_daily_limit, cs_daily_limit, lw_daily_limit, all_daily_limit)
VALUES (1, 4, 2, 2, 2, 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.app_update (id, version_code, version_name, force_update, package_name)
VALUES (1, 1, '1.0.0', false, 'com.example.yourapp')
ON CONFLICT (id) DO NOTHING;

-- Optional: a couple of starter categories so the home page isn't empty.
-- Edit/add more from the admin panel afterwards.
-- INSERT INTO public.categories (name, slot_mode) VALUES ('BR Solo', 'solo');
-- INSERT INTO public.categories (name, slot_mode) VALUES ('BR Duo', 'duo');
