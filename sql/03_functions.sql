-- ============================================================
-- FUNCTIONS (all SECURITY DEFINER RPCs + helpers used by the app)
-- Run AFTER 01_schema.sql and 02_indexes.sql
-- ============================================================

CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists(select 1 from public.admins where id = auth.uid());
$function$;

CREATE OR REPLACE FUNCTION public.has_joined_match(p_match_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists(
    select 1 from public.match_participants
    where match_id = p_match_id and joined_by = auth.uid()
  );
$function$;

CREATE OR REPLACE FUNCTION public._moderator_category_allowed(p_moderator_id uuid, p_category_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select not exists(
    select 1 from public.moderator_category_locks
    where moderator_id = p_moderator_id and category_id = p_category_id
  );
$function$;

CREATE OR REPLACE FUNCTION public._moderator_id_from_token(p_token uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_mid uuid;
begin
  select ms.moderator_id into v_mid
  from public.moderator_sessions ms
  join public.moderators m on m.id = ms.moderator_id
  where ms.token = p_token and ms.expires_at > now() and m.active = true;

  if v_mid is null then
    raise exception 'INVALID_SESSION';
  end if;
  return v_mid;
end;
$function$;

CREATE OR REPLACE FUNCTION public.notify_user(p_uid uuid, p_title text, p_body text, p_category text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.notifications (title, body, to_user_id, category)
  values (p_title, p_body, p_uid, p_category);
end;
$function$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  new_oxn_id text;
  device_check text;
  ban_row public.banned_devices%rowtype;
  existing_count int;
begin
  device_check := new.raw_user_meta_data->>'device_id';

  if device_check is not null then
    select * into ban_row from public.banned_devices where device_id = device_check;
    if found then
      if ban_row.ban_type = 'temporary' and ban_row.ban_until is not null and ban_row.ban_until <= now() then
        null;
      else
        raise exception 'DEVICE_BANNED: %', coalesce(ban_row.reason, 'No reason provided');
      end if;
    end if;

    select count(*) into existing_count from public.profiles where device_id = device_check;
    if existing_count >= 3 then
      raise exception 'DEVICE_LIMIT_REACHED';
    end if;
  end if;

  loop
    new_oxn_id := lpad(floor(random() * 90000 + 10000)::text, 5, '0');
    exit when not exists (select 1 from public.profiles where oxn_id = new_oxn_id);
  end loop;

  insert into public.profiles (id, username, email, phone, oxn_id, device_id)
  values (
    new.id,
    new.raw_user_meta_data->>'username',
    new.email,
    new.raw_user_meta_data->>'phone',
    new_oxn_id,
    device_check
  );

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_email_by_username(uname text)
 RETURNS text
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select email from public.profiles where lower(username) = lower(uname) limit 1;
$function$;

CREATE OR REPLACE FUNCTION public.update_my_profile(p_username text DEFAULT NULL::text, p_photo_base64 text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if p_photo_base64 is not null then
    update public.profiles set photo_base64 = p_photo_base64 where id = auth.uid();
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.mark_notifications_seen()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.profiles set last_seen_notif_at = now() where id = auth.uid();
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_leaderboard_name(p_name text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  prof record;
begin
  if p_name is null or trim(p_name) = '' then
    raise exception 'NAME_REQUIRED';
  end if;
  if length(trim(p_name)) > 20 then
    raise exception 'NAME_TOO_LONG';
  end if;

  select * into prof from public.profiles where id = auth.uid();
  if not found then raise exception 'PROFILE_NOT_FOUND'; end if;

  if prof.leaderboard_name is null then
    update public.profiles
    set leaderboard_name = trim(p_name), leaderboard_name_updated_at = now()
    where id = auth.uid();
    return;
  end if;

  if now() - prof.leaderboard_name_updated_at < interval '7 days' then
    raise exception 'COOLDOWN_ACTIVE';
  end if;

  update public.profiles
  set leaderboard_name = trim(p_name), leaderboard_name_updated_at = now()
  where id = auth.uid();
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_leaderboard_name_status()
 RETURNS TABLE(leaderboard_name text, is_first_time boolean, cooldown_days_left numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    p.leaderboard_name,
    p.leaderboard_name is null as is_first_time,
    case
      when p.leaderboard_name is null then 0
      when now() - p.leaderboard_name_updated_at >= interval '7 days' then 0
      else ceil(extract(epoch from (p.leaderboard_name_updated_at + interval '7 days' - now())) / 86400.0)
    end as cooldown_days_left
  from public.profiles p
  where p.id = auth.uid();
$function$;

CREATE OR REPLACE FUNCTION public.get_leaderboard(p_period text DEFAULT 'alltime'::text)
 RETURNS TABLE(user_id uuid, username text, photo_base64 text, matches_played integer, total_earning numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p.id, coalesce(p.leaderboard_name, p.username), p.photo_base64, p.matches_played,
    coalesce(sum(e.amount) filter (
      where p_period = 'alltime'
         or (p_period = 'weekly' and e.created_at > now() - interval '7 days')
         or (p_period = 'monthly' and e.created_at > now() - interval '30 days')
    ), 0) as total_earning
  from public.profiles p
  left join public.earnings_log e on e.user_id = p.id
  where p.banned = false
  group by p.id, p.leaderboard_name, p.username, p.photo_base64, p.matches_played
  order by total_earning desc;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_leaderboard_rank(p_period text DEFAULT 'alltime'::text)
 RETURNS TABLE(rank bigint, username text, photo_base64 text, matches_played integer, total_earning numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with ranked as (
    select p.id, coalesce(p.leaderboard_name, p.username) as username, p.photo_base64, p.matches_played,
      coalesce(sum(e.amount) filter (
        where p_period = 'alltime'
           or (p_period = 'weekly' and e.created_at > now() - interval '7 days')
           or (p_period = 'monthly' and e.created_at > now() - interval '30 days')
      ), 0) as total_earning,
      row_number() over (order by coalesce(sum(e.amount) filter (
        where p_period = 'alltime'
           or (p_period = 'weekly' and e.created_at > now() - interval '7 days')
           or (p_period = 'monthly' and e.created_at > now() - interval '30 days')
      ), 0) desc) as rnk
    from public.profiles p
    left join public.earnings_log e on e.user_id = p.id
    where p.banned = false
    group by p.id, p.leaderboard_name, p.username, p.photo_base64, p.matches_played
  )
  select rnk, username, photo_base64, matches_played, total_earning
  from ranked where id = auth.uid();
$function$;

CREATE OR REPLACE FUNCTION public.current_app_version_code()
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce(
    (regexp_match(
      coalesce(current_setting('request.headers', true)::json->>'user-agent', ''),
      'OXNAppVer/([0-9]+)'
    ))[1]::int,
    0
  );
$function$;

CREATE OR REPLACE FUNCTION public.app_version_ok()
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select not coalesce((select force_update from public.app_update where id = 1), false)
      or public.current_app_version_code() >= coalesce((select version_code from public.app_update where id = 1), 0);
$function$;

CREATE OR REPLACE FUNCTION public.join_match(p_match_id uuid, p_names text[], p_slots integer[], p_use_coupon boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  m record;
  prof record;
  cat_name text;
  coupon_group text;
  n_count int;
  i int;
  remaining_dep numeric;
  remaining_win numeric;
  fee_from_dep numeric;
  fee_from_win numeric;
  cur_slot int;
  coupon_balance int;
  coupons_used int := 0;
  paid_count int;
  wallet_total numeric;
  coupon_value numeric;
  taken_slots int[];
  next_free_slot int;
  no_explicit_slots boolean;
begin
  n_count := array_length(p_names, 1);
  if n_count is null or n_count = 0 then
    raise exception 'NO_PLAYERS';
  end if;

  select * into m from public.matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  if m.status <> 'Upcoming' then raise exception 'MATCH_NOT_JOINABLE'; end if;
  if (m.joined + n_count) > m.total then raise exception 'MATCH_FULL'; end if;

  if exists (select 1 from public.match_participants where match_id = p_match_id and joined_by = auth.uid()) then
    raise exception 'ALREADY_JOINED';
  end if;

  select * into prof from public.profiles where id = auth.uid() for update;
  if not found then raise exception 'PROFILE_NOT_FOUND'; end if;

  select name into cat_name from public.categories where id = m.category_id;
  coupon_group := null;
  if cat_name is not null then
    if lower(trim(cat_name)) like 'br%' then coupon_group := 'BR';
    elsif lower(trim(cat_name)) like 'cs%' then coupon_group := 'CS';
    elsif lower(trim(cat_name)) like 'lw%' then coupon_group := 'LW';
    end if;
  end if;

  if p_use_coupon and coupon_group is not null then
    if coupon_group = 'BR' then coupon_balance := prof.spin_br_wins;
    elsif coupon_group = 'CS' then coupon_balance := prof.spin_cs_wins;
    elsif coupon_group = 'LW' then coupon_balance := prof.spin_lw_wins;
    end if;
    coupon_balance := coalesce(coupon_balance, 0);
    coupons_used := least(coupon_balance, n_count);
  end if;

  paid_count := n_count - coupons_used;
  wallet_total := m.entry * paid_count;
  coupon_value := m.entry * coupons_used;

  if paid_count > 0 and (prof.deposit + prof.winning) < wallet_total then
    raise exception 'INSUFFICIENT_BALANCE';
  end if;

  if coupons_used > 0 then
    if coupon_group = 'BR' then
      update public.profiles set spin_br_wins = spin_br_wins - coupons_used where id = auth.uid();
    elsif coupon_group = 'CS' then
      update public.profiles set spin_cs_wins = spin_cs_wins - coupons_used where id = auth.uid();
    elsif coupon_group = 'LW' then
      update public.profiles set spin_lw_wins = spin_lw_wins - coupons_used where id = auth.uid();
    end if;
  end if;

  remaining_dep := prof.deposit;
  remaining_win := prof.winning;

  no_explicit_slots := (p_slots is null) or (array_length(p_slots,1) is null)
    or (not exists (select 1 from unnest(p_slots) v where v is not null));

  if m.auto_slot and no_explicit_slots then
    select coalesce(array_agg(slot), '{}') into taken_slots from public.match_participants where match_id = p_match_id and slot is not null;
    next_free_slot := 1;
  end if;

  for i in 1..n_count loop
    cur_slot := null;
    if m.auto_slot and no_explicit_slots then
      while next_free_slot = any(taken_slots) loop
        next_free_slot := next_free_slot + 1;
      end loop;
      cur_slot := next_free_slot;
      taken_slots := array_append(taken_slots, cur_slot);
      next_free_slot := next_free_slot + 1;
    elsif p_slots is not null and array_length(p_slots,1) >= i then
      cur_slot := p_slots[i];
    end if;

    if i <= coupons_used then
      insert into public.match_participants (match_id, ign, joined_by, slot, paid_deposit, paid_winning, via_coupon)
      values (p_match_id, p_names[i], auth.uid(), cur_slot, 0, 0, true);
    else
      if remaining_dep >= m.entry then
        fee_from_dep := m.entry; fee_from_win := 0;
        remaining_dep := remaining_dep - m.entry;
      else
        fee_from_dep := remaining_dep; fee_from_win := m.entry - remaining_dep;
        remaining_win := remaining_win - fee_from_win;
        remaining_dep := 0;
      end if;

      insert into public.match_participants (match_id, ign, joined_by, slot, paid_deposit, paid_winning, via_coupon)
      values (p_match_id, p_names[i], auth.uid(), cur_slot, fee_from_dep, fee_from_win, false);
    end if;
  end loop;

  if paid_count > 0 then
    update public.profiles set deposit = remaining_dep, winning = remaining_win where id = auth.uid();
  end if;
  update public.matches set joined = joined + n_count where id = p_match_id;

  if coupons_used > 0 then
    insert into public.transactions (user_id, type, amount, status, method, note)
    values (auth.uid(), 'Match Join', coupon_value, 'Success', 'Coupon', coupons_used || 'x ' || coupon_group || ' coupon used');
  end if;
  if paid_count > 0 then
    insert into public.transactions (user_id, type, amount, status, method)
    values (auth.uid(), 'Match Join', wallet_total, 'Success', 'Wallet');
  end if;

  return jsonb_build_object(
    'success', true,
    'total_fee', wallet_total,
    'coupons_used', coupons_used,
    'paid_slots', paid_count
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.request_deposit(p_amount numeric, p_method text, p_trx_id text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  new_id uuid;
  existing record;
  v_trx text;
begin
  if p_amount < 10 or p_amount > 2000 then
    raise exception 'INVALID_AMOUNT';
  end if;

  v_trx := upper(regexp_replace(coalesce(p_trx_id, ''), '\s+', '', 'g'));
  if v_trx = '' then
    raise exception 'INVALID_TRX_ID';
  end if;

  select id, user_id, status into existing
  from public.deposit_requests
  where upper(regexp_replace(trx_id, '\s+', '', 'g')) = v_trx
  limit 1;

  if found then
    if existing.user_id <> auth.uid() then
      raise exception 'TRX_ALREADY_USED';
    elsif existing.status = 'approved' then
      raise exception 'TRX_ALREADY_APPROVED';
    elsif existing.status = 'rejected' then
      raise exception 'TRX_REJECTED_USE_NEW';
    else
      return existing.id;
    end if;
  end if;

  insert into public.deposit_requests (user_id, amount, method, trx_id)
  values (auth.uid(), p_amount, p_method, v_trx)
  returning id into new_id;

  return new_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.request_withdraw(p_amount numeric, p_method text, p_number text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  new_id uuid;
  cur_winning numeric;
begin
  if p_amount < 100 then raise exception 'MIN_WITHDRAW_100'; end if;

  select winning into cur_winning from public.profiles where id = auth.uid();
  if cur_winning < p_amount then raise exception 'INSUFFICIENT_BALANCE'; end if;

  update public.profiles set winning = winning - p_amount where id = auth.uid();

  insert into public.withdraw_requests (user_id, amount, method, mobile_number)
  values (auth.uid(), p_amount, p_method, p_number)
  returning id into new_id;

  return new_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.request_topup_order(p_package_id uuid, p_ff_uid text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  pkg record;
  cur_winning numeric;
  new_id uuid;
begin
  select * into pkg from public.topup_packages where id = p_package_id;
  if not found then raise exception 'PACKAGE_NOT_FOUND'; end if;

  select winning into cur_winning from public.profiles where id = auth.uid() for update;
  if cur_winning < pkg.price then raise exception 'INSUFFICIENT_BALANCE'; end if;

  update public.profiles set winning = winning - pkg.price where id = auth.uid();

  insert into public.topup_orders (user_id, package_id, package_name, amount, ff_uid)
  values (auth.uid(), p_package_id, pkg.name, pkg.price, p_ff_uid)
  returning id into new_id;

  insert into public.transactions (user_id, type, amount, status, note)
  values (auth.uid(), 'Top-Up Order', pkg.price, 'Pending', 'FF UID: ' || p_ff_uid);

  return new_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_adjust_balance(p_user_id uuid, p_deposit numeric, p_winning numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_old_winning numeric;
  v_diff numeric;
begin
  if not public.is_admin() then raise exception 'NOT_AUTHORIZED'; end if;

  select winning into v_old_winning from public.profiles where id = p_user_id;
  v_diff := p_winning - coalesce(v_old_winning, 0);

  update public.profiles set deposit = p_deposit, winning = p_winning where id = p_user_id;

  insert into public.transactions (user_id, type, amount, status, note)
  values (p_user_id, 'Balance Adjusted by Admin', 0, 'Success', format('Deposit: %s, Winning: %s', p_deposit, p_winning));

  if v_diff <> 0 then
    insert into public.earnings_log (user_id, amount, match_id)
    values (p_user_id, v_diff, null);
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_adjust_participant_winning(p_participant_id uuid, p_new_amount numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_participant record;
  v_old_amount numeric;
  v_diff numeric;
  v_current_winning numeric;
  v_match_num int;
begin
  if not public.is_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  if p_new_amount is null or p_new_amount < 0 then raise exception 'INVALID_AMOUNT'; end if;

  select mp.* into v_participant from public.match_participants mp where mp.id = p_participant_id;
  if not found then raise exception 'PARTICIPANT_NOT_FOUND'; end if;

  select match_num into v_match_num from public.matches where id = v_participant.match_id;

  v_old_amount := coalesce(v_participant.win, 0);
  v_diff := p_new_amount - v_old_amount;

  if v_diff <> 0 then
    select winning into v_current_winning from public.profiles where id = v_participant.joined_by for update;

    if v_current_winning + v_diff < 0 then
      raise exception 'INSUFFICIENT_BALANCE: user currently has only ৳% remaining winning balance, cannot reduce by ৳% (user likely already withdrew part of this)', v_current_winning, abs(v_diff);
    end if;

    update public.profiles set winning = winning + v_diff where id = v_participant.joined_by;

    insert into public.transactions (user_id, type, amount, status)
    values (v_participant.joined_by, 'Winning Adjustment', v_diff, 'Success');

    delete from public.earnings_log where match_id = v_participant.match_id and user_id = v_participant.joined_by;
    if p_new_amount > 0 then
      insert into public.earnings_log (user_id, amount, match_id) values (v_participant.joined_by, p_new_amount, v_participant.match_id);
    end if;

    perform public.notify_user(v_participant.joined_by, 'উইনিং আপডেট হয়েছে', format('Match #%s এর উইনিং এডমিন পরিবর্তন করেছেন। নতুন এমাউন্ট: ৳%s', v_match_num, p_new_amount), 'yours');
  end if;

  update public.match_participants set win = p_new_amount, admin_prize = p_new_amount where id = p_participant_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_approve_deposit(p_request_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  req record;
begin
  if not public.is_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  select * into req from public.deposit_requests where id = p_request_id and status = 'pending';
  if not found then raise exception 'REQUEST_NOT_FOUND'; end if;

  update public.profiles set deposit = deposit + req.amount where id = req.user_id;
  update public.deposit_requests set status = 'approved', processed_at = now() where id = p_request_id;

  insert into public.transactions (user_id, type, amount, status, method)
  values (req.user_id, 'Deposit (Approved)', req.amount, 'Success', req.method);

  perform public.notify_user(req.user_id, '💰 ডিপোজিট সফল হয়েছে', format('আপনার %s টাকার ডিপোজিট রিকোয়েস্ট অ্যাপ্রুভ হয়েছে।', req.amount), 'yours');
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_reject_deposit(p_request_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  req record;
begin
  if not public.is_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  select * into req from public.deposit_requests where id = p_request_id and status = 'pending';
  if not found then raise exception 'REQUEST_NOT_FOUND'; end if;

  update public.deposit_requests set status = 'rejected', processed_at = now() where id = p_request_id;
  perform public.notify_user(req.user_id, '❌ ডিপোজিট বাতিল হয়েছে', format('আপনার %s টাকার ডিপোজিট রিকোয়েস্ট বাতিল হয়েছে।', req.amount), 'yours');
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_approve_withdraw(p_request_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  req record;
begin
  if not public.is_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  select * into req from public.withdraw_requests where id = p_request_id and status = 'pending';
  if not found then raise exception 'REQUEST_NOT_FOUND'; end if;

  update public.withdraw_requests set status = 'approved', processed_at = now() where id = p_request_id;
  insert into public.transactions (user_id, type, amount, status, method)
  values (req.user_id, 'Withdraw', req.amount, 'Success', req.method);

  perform public.notify_user(req.user_id, '✅ উইথড্র সফল হয়েছে', format('আপনার %s টাকার উইথড্র সম্পন্ন হয়েছে।', req.amount), 'yours');
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_reject_withdraw(p_request_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  req record;
begin
  if not public.is_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  select * into req from public.withdraw_requests where id = p_request_id and status = 'pending';
  if not found then raise exception 'REQUEST_NOT_FOUND'; end if;

  update public.profiles set winning = winning + req.amount where id = req.user_id;
  update public.withdraw_requests set status = 'rejected', processed_at = now() where id = p_request_id;
  insert into public.transactions (user_id, type, amount, status, method, note)
  values (req.user_id, 'Withdraw Rejected (Refund)', req.amount, 'Refunded', req.method, 'Auto refunded');

  perform public.notify_user(req.user_id, '❌ উইথড্র বাতিল হয়েছে', format('আপনার %s টাকার উইথড্র বাতিল হয়েছে, টাকা ফেরত দেওয়া হয়েছে।', req.amount), 'yours');
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_approve_topup_order(p_order_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  ord record;
begin
  if not public.is_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  select * into ord from public.topup_orders where id = p_order_id and status = 'pending';
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;

  update public.topup_orders set status = 'approved', processed_at = now() where id = p_order_id;
  update public.profiles set deposit = deposit + ord.amount where id = ord.user_id;

  insert into public.transactions (user_id, type, amount, status, note)
  values (ord.user_id, 'Top-Up Approved', ord.amount, 'Success', 'FF UID: ' || ord.ff_uid);

  perform public.notify_user(ord.user_id, '✅ Top-Up সফল হয়েছে', format('আপনার %s অর্ডারটি সম্পন্ন হয়েছে।', ord.package_name), 'yours');
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_reject_topup_order(p_order_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  ord record;
begin
  if not public.is_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  select * into ord from public.topup_orders where id = p_order_id and status = 'pending';
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;

  update public.profiles set winning = winning + ord.amount where id = ord.user_id;
  update public.topup_orders set status = 'rejected', processed_at = now() where id = p_order_id;

  insert into public.transactions (user_id, type, amount, status, note)
  values (ord.user_id, 'Top-Up Rejected (Refund)', ord.amount, 'Refunded', 'Order refunded');

  perform public.notify_user(ord.user_id, '❌ Top-Up বাতিল হয়েছে', format('আপনার %s অর্ডারটি বাতিল হয়েছে, টাকা ফেরত দেওয়া হয়েছে।', ord.package_name), 'yours');
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_archive_match(p_match_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  update public.matches set archived = true where id = p_match_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_unarchive_match(p_match_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  update public.matches set archived = false where id = p_match_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_ban_user(p_user_id uuid, p_reason text, p_ban_type text, p_duration_hours integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  prof record;
  ban_until_val timestamptz;
begin
  if not public.is_admin() then raise exception 'NOT_AUTHORIZED'; end if;

  select * into prof from public.profiles where id = p_user_id;
  if not found then raise exception 'USER_NOT_FOUND'; end if;

  ban_until_val := case when p_ban_type = 'temporary' then now() + (p_duration_hours || ' hours')::interval else null end;

  update public.profiles
  set banned = true, ban_reason = p_reason, ban_type = p_ban_type, ban_until = ban_until_val
  where id = p_user_id;

  if prof.device_id is not null then
    insert into public.banned_devices (device_id, reason, ban_type, ban_until, uid, username)
    values (prof.device_id, p_reason, p_ban_type, ban_until_val, p_user_id, prof.username)
    on conflict (device_id) do update
      set reason = excluded.reason, ban_type = excluded.ban_type, ban_until = excluded.ban_until;
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_unban_user(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  prof record;
begin
  if not public.is_admin() then raise exception 'NOT_AUTHORIZED'; end if;

  select * into prof from public.profiles where id = p_user_id;
  if not found then raise exception 'USER_NOT_FOUND'; end if;

  update public.profiles
  set banned = false, ban_reason = null, ban_type = null, ban_until = null
  where id = p_user_id;

  if prof.device_id is not null then
    delete from public.banned_devices where device_id = prof.device_id;
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_refund_participant(p_participant_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  p record;
begin
  if not public.is_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  select * into p from public.match_participants where id = p_participant_id;
  if not found then raise exception 'PARTICIPANT_NOT_FOUND'; end if;

  update public.profiles
  set deposit = deposit + coalesce(p.paid_deposit,0), winning = winning + coalesce(p.paid_winning,0)
  where id = p.joined_by;

  update public.matches set joined = greatest(0, joined - 1) where id = p.match_id;
  delete from public.match_participants where id = p_participant_id;

  insert into public.transactions (user_id, type, amount, status)
  values (p.joined_by, 'Match Refund', coalesce(p.paid_deposit,0)+coalesce(p.paid_winning,0), 'Success');

  perform public.notify_user(p.joined_by, '↩️ ম্যাচ রিফান্ড', 'আপনার ম্যাচ এন্ট্রি ফি রিফান্ড করা হয়েছে।', 'yours');
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_finalize_match_results(p_match_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  rec record;
  idx int := 0;
  winner_names text[] := '{}';
  winner_total numeric := 0;
  m_title text;
  m_num int;
begin
  if not public.is_admin() then raise exception 'NOT_AUTHORIZED'; end if;

  select title, match_num into m_title, m_num from public.matches where id = p_match_id;

  for rec in
    select * from public.match_participants
    where match_id = p_match_id and admin_position is not null and trim(admin_position) <> ''
  loop
    update public.match_participants
    set "position" = nullif(rec.admin_position,'')::int, win = coalesce(rec.admin_prize,0), kills = coalesce(rec.admin_kills, kills)
    where id = rec.id;

    if coalesce(rec.admin_prize,0) > 0 then
      update public.profiles set winning = winning + rec.admin_prize where id = rec.joined_by;
      insert into public.transactions (user_id, type, amount, status) values (rec.joined_by, 'Match Win', rec.admin_prize, 'Success');
      insert into public.earnings_log (user_id, amount, match_id) values (rec.joined_by, rec.admin_prize, p_match_id);
      perform public.notify_user(rec.joined_by, '🎁 Reward Received!', format('অভিনন্দন! Match #%s থেকে আপনি ৳%s জিতেছেন। প্লেয়ার: %s', m_num, rec.admin_prize, rec.ign), 'yours');
    else
      perform public.notify_user(rec.joined_by, 'ম্যাচ রেজাল্ট', format('Match #%s এ আপনি জিততে পারেননি। পরের বার আবার চেষ্টা করুন!', m_num), 'yours');
    end if;

    if rec.starred then winner_names := array_append(winner_names, rec.ign); winner_total := winner_total + coalesce(rec.admin_prize,0); end if;
  end loop;

  idx := 0;
  for rec in
    select * from public.match_participants
    where match_id = p_match_id and (admin_position is null or trim(admin_position) = '')
    order by coalesce(admin_prize,0) desc, random()
  loop
    idx := idx + 1;
    update public.match_participants
    set "position" = idx, win = coalesce(rec.admin_prize,0), kills = coalesce(rec.admin_kills, kills)
    where id = rec.id;

    if coalesce(rec.admin_prize,0) > 0 then
      update public.profiles set winning = winning + rec.admin_prize where id = rec.joined_by;
      insert into public.transactions (user_id, type, amount, status) values (rec.joined_by, 'Match Win', rec.admin_prize, 'Success');
      insert into public.earnings_log (user_id, amount, match_id) values (rec.joined_by, rec.admin_prize, p_match_id);
      perform public.notify_user(rec.joined_by, '🎁 Reward Received!', format('অভিনন্দন! Match #%s থেকে আপনি ৳%s জিতেছেন। প্লেয়ার: %s', m_num, rec.admin_prize, rec.ign), 'yours');
    else
      perform public.notify_user(rec.joined_by, 'ম্যাচ রেজাল্ট', format('Match #%s এ আপনি জিততে পারেননি। পরের বার আবার চেষ্টা করুন!', m_num), 'yours');
    end if;

    if rec.starred then winner_names := array_append(winner_names, rec.ign); winner_total := winner_total + coalesce(rec.admin_prize,0); end if;
  end loop;

  update public.matches set status = 'Finished', winner_name = array_to_string(winner_names, ', '), winner_amount = winner_total, results_finalized_at = now() where id = p_match_id;
  update public.profiles p set matches_played = matches_played + 1 where p.id in (select joined_by from public.match_participants where match_id = p_match_id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_save_winner_draft(p_match_id uuid, p_updates jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  item jsonb;
begin
  if not public.is_admin() then raise exception 'NOT_AUTHORIZED'; end if;

  for item in select * from jsonb_array_elements(p_updates) loop
    update public.match_participants
    set admin_position = nullif(item->>'position',''),
        admin_prize = nullif(item->>'prize','')::numeric,
        admin_kills = nullif(item->>'kills','')::int,
        starred = coalesce((item->>'starred')::boolean, false)
    where id = (item->>'participant_id')::uuid and match_id = p_match_id;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_edit_finalized_result(p_match_id uuid, p_updates jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  item jsonb;
  v_participant record;
  v_new_prize numeric;
  v_new_position int;
  v_new_kills int;
  v_new_starred boolean;
  v_delta numeric;
  m_num int;
  winner_names text[];
  winner_total numeric;
begin
  if not public.is_admin() then raise exception 'NOT_AUTHORIZED'; end if;

  select match_num into m_num from public.matches where id = p_match_id;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;

  for item in select * from jsonb_array_elements(p_updates) loop
    select * into v_participant from public.match_participants
      where id = (item->>'participant_id')::uuid and match_id = p_match_id;
    if not found then continue; end if;

    v_new_prize := coalesce(nullif(item->>'prize','')::numeric, 0);
    v_new_position := nullif(item->>'position','')::int;
    v_new_kills := coalesce(nullif(item->>'kills','')::int, v_participant.kills);
    v_new_starred := coalesce((item->>'starred')::boolean, false);

    v_delta := v_new_prize - coalesce(v_participant.win, 0);

    if v_delta <> 0 then
      update public.profiles set winning = greatest(coalesce(winning,0) + v_delta, 0) where id = v_participant.joined_by;
      insert into public.transactions (user_id, type, amount, status, note)
        values (v_participant.joined_by, 'Result Correction', v_delta, 'Success', format('Match #%s ফলাফল সংশোধন', m_num));
      insert into public.earnings_log (user_id, amount, match_id) values (v_participant.joined_by, v_delta, p_match_id);
      perform public.notify_user(
        v_participant.joined_by,
        '✏️ ফলাফল সংশোধন হয়েছে',
        format('Match #%s এর ফলাফল আপডেট করা হয়েছে। নতুন প্রাইজ: ৳%s (পরিবর্তন: %s৳%s)', m_num, v_new_prize, (case when v_delta > 0 then '+' else '' end), v_delta),
        'yours'
      );
    end if;

    update public.match_participants
      set win = v_new_prize,
          "position" = v_new_position,
          kills = v_new_kills,
          starred = v_new_starred,
          admin_position = nullif(item->>'position',''),
          admin_prize = v_new_prize,
          admin_kills = v_new_kills
      where id = v_participant.id;
  end loop;

  select coalesce(array_agg(ign order by win desc), '{}'), coalesce(sum(win), 0)
    into winner_names, winner_total
    from public.match_participants
    where match_id = p_match_id and starred = true;

  update public.matches
    set winner_name = array_to_string(winner_names, ', '),
        winner_amount = winner_total,
        results_updated_at = now()
    where id = p_match_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_create_moderator(p_name text, p_password text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  if p_name is null or trim(p_name) = '' then raise exception 'NAME_REQUIRED'; end if;
  if p_password is null or length(p_password) < 4 then raise exception 'PASSWORD_TOO_SHORT'; end if;

  insert into public.moderators (name, password_hash)
  values (trim(p_name), extensions.crypt(p_password, extensions.gen_salt('bf')))
  returning id into v_id;

  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_delete_moderator(p_moderator_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  delete from public.moderators where id = p_moderator_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_reset_moderator_password(p_moderator_id uuid, p_new_password text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.is_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  if p_new_password is null or length(p_new_password) < 4 then raise exception 'PASSWORD_TOO_SHORT'; end if;

  update public.moderators set password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf'))
  where id = p_moderator_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_set_moderator_active(p_moderator_id uuid, p_active boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  update public.moderators set active = p_active where id = p_moderator_id;
  if p_active = false then
    delete from public.moderator_sessions where moderator_id = p_moderator_id;
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_list_moderators()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_result jsonb;
begin
  if not public.is_admin() then raise exception 'NOT_AUTHORIZED'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', m.id, 'name', m.name, 'active', m.active, 'created_at', m.created_at,
    'locked_categories', (select coalesce(jsonb_agg(l.category_id), '[]'::jsonb) from public.moderator_category_locks l where l.moderator_id = m.id)
  ) order by m.created_at desc), '[]'::jsonb) into v_result
  from public.moderators m;

  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_toggle_moderator_category_lock(p_moderator_id uuid, p_category_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_locked boolean;
begin
  if not public.is_admin() then raise exception 'NOT_AUTHORIZED'; end if;

  if exists(select 1 from public.moderator_category_locks where moderator_id=p_moderator_id and category_id=p_category_id) then
    delete from public.moderator_category_locks where moderator_id=p_moderator_id and category_id=p_category_id;
    v_locked := false;
  else
    insert into public.moderator_category_locks(moderator_id, category_id) values (p_moderator_id, p_category_id);
    v_locked := true;
  end if;

  return v_locked;
end;
$function$;

CREATE OR REPLACE FUNCTION public.moderator_login(p_name text, p_password text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_mod record;
  v_token uuid;
begin
  select * into v_mod from public.moderators where name = p_name and active = true;

  if v_mod is null or v_mod.password_hash <> extensions.crypt(p_password, v_mod.password_hash) then
    raise exception 'INVALID_CREDENTIALS';
  end if;

  insert into public.moderator_sessions (moderator_id) values (v_mod.id) returning token into v_token;

  return jsonb_build_object('token', v_token, 'moderator_id', v_mod.id, 'name', v_mod.name);
end;
$function$;

CREATE OR REPLACE FUNCTION public.moderator_logout(p_token uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  delete from public.moderator_sessions where token = p_token;
end;
$function$;

CREATE OR REPLACE FUNCTION public.moderator_my_locked_categories(p_token uuid)
 RETURNS SETOF uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_mid uuid;
begin
  v_mid := public._moderator_id_from_token(p_token);
  return query select category_id from public.moderator_category_locks where moderator_id = v_mid;
end;
$function$;

CREATE OR REPLACE FUNCTION public.moderator_list_participants(p_token uuid, p_match_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_mid uuid;
  v_cat uuid;
  v_result jsonb;
begin
  v_mid := public._moderator_id_from_token(p_token);
  select category_id into v_cat from public.matches where id = p_match_id;
  if v_cat is null then raise exception 'MATCH_NOT_FOUND'; end if;
  if not public._moderator_category_allowed(v_mid, v_cat) then raise exception 'CATEGORY_LOCKED'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', mp.id, 'ign', mp.ign, 'oxn_id', pr.oxn_id, 'username', pr.username,
    'kills', mp.kills, 'paid_deposit', mp.paid_deposit, 'paid_winning', mp.paid_winning,
    'joined_at', mp.joined_at, 'slot', mp.slot
  ) order by mp.joined_at), '[]'::jsonb)
  into v_result
  from public.match_participants mp
  left join public.profiles pr on pr.id = mp.joined_by
  where mp.match_id = p_match_id;

  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.moderator_match_history(p_token uuid, p_limit integer DEFAULT 60)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_mid uuid;
  v_result jsonb;
begin
  v_mid := public._moderator_id_from_token(p_token);

  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb) into v_result
  from (
    select
      m.id, m.title, m.match_time, m.timestamp_ms, m.status, c.name as category_name,
      (select coalesce(jsonb_agg(jsonb_build_object(
          'ign', mp.ign, 'oxn_id', pr.oxn_id, 'joined_at', mp.joined_at
        ) order by mp.joined_at), '[]'::jsonb)
       from public.match_participants mp
       left join public.profiles pr on pr.id = mp.joined_by
       where mp.match_id = m.id) as participants
    from public.matches m
    join public.categories c on c.id = m.category_id
    where not exists (
      select 1 from public.moderator_category_locks l
      where l.moderator_id = v_mid and l.category_id = m.category_id
    )
    order by m.timestamp_ms desc nulls last
    limit p_limit
  ) t;

  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.moderator_set_room(p_token uuid, p_match_id uuid, p_room_id text, p_room_pass text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_mid uuid; v_cat uuid;
begin
  v_mid := public._moderator_id_from_token(p_token);
  select category_id into v_cat from public.matches where id = p_match_id;
  if v_cat is null then raise exception 'MATCH_NOT_FOUND'; end if;
  if not public._moderator_category_allowed(v_mid, v_cat) then raise exception 'CATEGORY_LOCKED'; end if;

  update public.matches set room_id = p_room_id, room_pass = p_room_pass where id = p_match_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.moderator_refund_participant(p_token uuid, p_participant_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_mid uuid;
  p record;
  v_cat uuid;
begin
  v_mid := public._moderator_id_from_token(p_token);

  select * into p from public.match_participants where id = p_participant_id;
  if not found then raise exception 'PARTICIPANT_NOT_FOUND'; end if;

  select category_id into v_cat from public.matches where id = p.match_id;
  if not public._moderator_category_allowed(v_mid, v_cat) then raise exception 'CATEGORY_LOCKED'; end if;

  update public.profiles
  set deposit = deposit + coalesce(p.paid_deposit,0), winning = winning + coalesce(p.paid_winning,0)
  where id = p.joined_by;

  update public.matches set joined = greatest(0, joined - 1) where id = p.match_id;
  delete from public.match_participants where id = p_participant_id;

  insert into public.transactions (user_id, type, amount, status)
  values (p.joined_by, 'Match Refund', coalesce(p.paid_deposit,0)+coalesce(p.paid_winning,0), 'Success');

  perform public.notify_user(p.joined_by, '↩️ ম্যাচ রিফান্ড', 'আপনার ম্যাচ এন্ট্রি ফি রিফান্ড করা হয়েছে।', 'yours');
end;
$function$;

CREATE OR REPLACE FUNCTION public.moderator_submit_winner_request(p_token uuid, p_match_id uuid, p_entries jsonb, p_description text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_mid uuid;
  v_mod_name text;
  v_cat uuid;
  v_id uuid;
begin
  v_mid := public._moderator_id_from_token(p_token);
  select name into v_mod_name from public.moderators where id = v_mid;

  select category_id into v_cat from public.matches where id = p_match_id;
  if v_cat is null then raise exception 'MATCH_NOT_FOUND'; end if;
  if not public._moderator_category_allowed(v_mid, v_cat) then raise exception 'CATEGORY_LOCKED'; end if;
  if p_entries is null or jsonb_array_length(p_entries) = 0 then raise exception 'NO_PLAYERS_SELECTED'; end if;

  insert into public.winner_requests (match_id, moderator_id, moderator_name, entries, description)
  values (p_match_id, v_mid, v_mod_name, p_entries, p_description)
  returning id into v_id;

  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_list_winner_requests(p_status text DEFAULT 'pending'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_result jsonb;
begin
  if not public.is_admin() then raise exception 'NOT_AUTHORIZED'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', wr.id, 'match_id', wr.match_id, 'match_title', m.title, 'match_num', m.match_num,
    'category_name', c.name, 'moderator_name', wr.moderator_name,
    'entries', wr.entries, 'description', wr.description, 'status', wr.status,
    'created_at', wr.created_at
  ) order by wr.created_at desc), '[]'::jsonb) into v_result
  from public.winner_requests wr
  join public.matches m on m.id = wr.match_id
  left join public.categories c on c.id = m.category_id
  where (p_status is null or wr.status = p_status);

  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_approve_winner_request(p_request_id uuid, p_final_entries jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_req record;
  item jsonb;
begin
  if not public.is_admin() then raise exception 'NOT_AUTHORIZED'; end if;

  select * into v_req from public.winner_requests where id = p_request_id;
  if not found then raise exception 'REQUEST_NOT_FOUND'; end if;
  if v_req.status <> 'pending' then raise exception 'ALREADY_REVIEWED'; end if;

  for item in select * from jsonb_array_elements(p_final_entries) loop
    update public.match_participants
    set admin_prize = nullif(item->>'amount','')::numeric,
        starred = true
    where id = (item->>'participant_id')::uuid and match_id = v_req.match_id;
  end loop;

  perform public.admin_finalize_match_results(v_req.match_id);

  update public.winner_requests set status = 'approved', reviewed_at = now() where id = p_request_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_reject_winner_request(p_request_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  update public.winner_requests
  set status = 'rejected', reviewed_at = now(), reviewed_note = p_reason
  where id = p_request_id and status = 'pending';
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_effective_spin_next_at(p_device_id text DEFAULT NULL::text)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_owner_uid uuid := 'b220ad4f-067b-4b9a-8db1-e6ef5233cdf8'::uuid;
  v_last_spin timestamptz;
  v_device_last_spin timestamptz;
  v_effective timestamptz;
  v_now timestamptz := now();
  v_device text := nullif(trim(p_device_id), '');
begin
  if v_uid is null then
    return null;
  end if;

  if v_uid = v_owner_uid then
    return v_now;
  end if;

  select spin_last_at into v_last_spin from public.profiles where id = v_uid;

  if v_device is not null then
    select max(spin_last_at) into v_device_last_spin
    from public.profiles
    where device_id = v_device and id <> v_uid;
  end if;

  v_effective := greatest(coalesce(v_last_spin, 'epoch'::timestamptz), coalesce(v_device_last_spin, 'epoch'::timestamptz));

  if v_effective = 'epoch'::timestamptz then
    return v_now;
  end if;

  return v_effective + interval '24 hours';
exception when others then
  return v_now;
end;
$function$;

-- NOTE: 'b220ad4f-067b-4b9a-8db1-e6ef5233cdf8' below is the original owner's
-- auth.users UUID (unlimited-spin account) — replace it with your own admin
-- user's UUID after you create your account, or remove the "is owner" branch
-- entirely if you don't want an unlimited-spin account.
CREATE OR REPLACE FUNCTION public.spin_daily_wheel(p_device_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_owner_uid uuid := 'b220ad4f-067b-4b9a-8db1-e6ef5233cdf8'::uuid;
  v_is_owner boolean;
  v_last_spin timestamptz;
  v_device_last_spin timestamptz;
  v_effective_last_spin timestamptz;
  v_now timestamptz := now();
  v_today date := current_date;
  v_pool record;
  v_settings record;
  v_roll numeric;
  v_result text;
  v_slot_available boolean;
  v_device text := nullif(trim(p_device_id), '');
  v_br_ok boolean;
  v_cs_ok boolean;
  v_lw_ok boolean;
  v_all_ok boolean;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  v_is_owner := (v_uid = v_owner_uid);

  select spin_last_at into v_last_spin from public.profiles where id = v_uid for update;

  if not v_is_owner then
    if v_device is not null then
      select max(spin_last_at) into v_device_last_spin
      from (
        select spin_last_at from public.profiles
        where device_id = v_device and id <> v_uid
        for update
      ) locked_rows;
    end if;

    v_effective_last_spin := greatest(coalesce(v_last_spin, 'epoch'::timestamptz), coalesce(v_device_last_spin, 'epoch'::timestamptz));

    if v_effective_last_spin > 'epoch'::timestamptz and v_now < v_effective_last_spin + interval '24 hours' then
      return jsonb_build_object('ok', false, 'error', 'cooldown', 'next_spin_at', v_effective_last_spin + interval '24 hours');
    end if;

    select * into v_settings from public.spin_settings where id = 1;

    insert into public.daily_spin_pool (spin_date, max_winners, br_limit, cs_limit, lw_limit, all_limit)
      values (v_today, coalesce(v_settings.max_winners_per_day, 4), coalesce(v_settings.br_daily_limit, 2),
              coalesce(v_settings.cs_daily_limit, 2), coalesce(v_settings.lw_daily_limit, 2), coalesce(v_settings.all_daily_limit, 1))
      on conflict (spin_date) do nothing;
    select * into v_pool from public.daily_spin_pool where spin_date = v_today for update;

    v_slot_available := v_pool.winners_count < v_pool.max_winners;
    v_br_ok := v_slot_available and v_pool.br_wins < v_pool.br_limit;
    v_cs_ok := v_slot_available and v_pool.cs_wins < v_pool.cs_limit;
    v_lw_ok := v_slot_available and v_pool.lw_wins < v_pool.lw_limit;
    v_all_ok := v_slot_available and v_pool.all_wins < v_pool.all_limit;

    v_roll := random();

    if v_roll < 0.93 then
      v_result := 'no_reward';
    elsif v_roll < 0.9475 then
      v_result := case when v_br_ok then 'br_match' else 'no_reward' end;
    elsif v_roll < 0.965 then
      v_result := case when v_cs_ok then 'cs_match' else 'no_reward' end;
    elsif v_roll < 0.9825 then
      v_result := case when v_lw_ok then 'lw_match' else 'no_reward' end;
    else
      v_result := case when v_all_ok then 'all_match' else 'no_reward' end;
    end if;

    if v_result <> 'no_reward' then
      update public.daily_spin_pool
      set winners_count = winners_count + 1,
          br_wins = br_wins + case when v_result='br_match' then 1 else 0 end,
          cs_wins = cs_wins + case when v_result='cs_match' then 1 else 0 end,
          lw_wins = lw_wins + case when v_result='lw_match' then 1 else 0 end,
          all_wins = all_wins + case when v_result='all_match' then 1 else 0 end
      where spin_date = v_today;
    end if;
  else
    v_roll := random();

    if v_roll < 0.01 then
      v_result := 'no_reward';
    elsif v_roll < 0.2575 then
      v_result := 'br_match';
    elsif v_roll < 0.505 then
      v_result := 'cs_match';
    elsif v_roll < 0.7525 then
      v_result := 'lw_match';
    else
      v_result := 'all_match';
    end if;
  end if;

  update public.profiles
  set spin_last_at = v_now,
      spin_br_wins = spin_br_wins + case when v_result='br_match' then 1 else 0 end,
      spin_cs_wins = spin_cs_wins + case when v_result='cs_match' then 1 else 0 end,
      spin_lw_wins = spin_lw_wins + case when v_result='lw_match' then 1 else 0 end,
      spin_all_wins = spin_all_wins + case when v_result='all_match' then 1 else 0 end,
      deposit = deposit + case when v_result='all_match' then 60 else 0 end
  where id = v_uid;

  if not v_is_owner and v_device is not null then
    update public.profiles
    set spin_last_at = v_now
    where device_id = v_device and id <> v_uid;
  end if;

  if v_result = 'all_match' then
    insert into public.transactions (user_id, type, amount, status, method, note)
    values (v_uid, 'Spin Reward', 60, 'Success', 'Spin Wheel', 'Daily Spin - ALL reward');
  end if;

  insert into public.spin_history (user_id, result, spin_date) values (v_uid, v_result, v_today);

  return jsonb_build_object('ok', true, 'result', v_result, 'next_spin_at', case when v_is_owner then v_now else v_now + interval '24 hours' end);
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_spin_dashboard(p_days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_overview jsonb;
  v_daily jsonb;
  v_winners jsonb;
begin
  if not public.is_admin() then raise exception 'NOT_AUTHORIZED'; end if;

  select jsonb_build_object(
    'total_spins', count(*),
    'total_won', count(*) filter (where result <> 'no_reward'),
    'total_no_reward', count(*) filter (where result = 'no_reward'),
    'total_br', count(*) filter (where result = 'br_match'),
    'total_cs', count(*) filter (where result = 'cs_match'),
    'total_lw', count(*) filter (where result = 'lw_match'),
    'total_all', count(*) filter (where result = 'all_match')
  ) into v_overview
  from public.spin_history;

  select v_overview
    || jsonb_build_object(
      'total_coupon_value', coalesce((select sum(amount) from public.transactions where type = 'Match Join' and method = 'Coupon' and status = 'Success'), 0),
      'total_cash_value', coalesce((select sum(amount) from public.transactions where type = 'Spin Reward' and status = 'Success'), 0)
    )
  into v_overview;

  select coalesce(jsonb_agg(row_to_json(d) order by d.day desc), '[]'::jsonb) into v_daily
  from (
    select
      sh.spin_date as day,
      count(*) as spins,
      count(*) filter (where sh.result <> 'no_reward') as wins,
      count(*) filter (where sh.result = 'no_reward') as no_rewards,
      coalesce((
        select sum(t.amount) from public.transactions t
        where t.type = 'Match Join' and t.method = 'Coupon' and t.status = 'Success'
          and t.created_at::date = sh.spin_date
      ), 0) as coupon_value,
      coalesce((
        select sum(t.amount) from public.transactions t
        where t.type = 'Spin Reward' and t.status = 'Success'
          and t.created_at::date = sh.spin_date
      ), 0) as cash_value
    from public.spin_history sh
    where sh.spin_date >= (current_date - (p_days - 1))
    group by sh.spin_date
  ) d;

  select coalesce(jsonb_agg(row_to_json(w) order by w.last_win_at desc), '[]'::jsonb) into v_winners
  from (
    select
      p.id as user_id,
      p.username,
      p.oxn_id,
      max(sh.created_at) as last_win_at,
      count(sh2.id) filter (where sh2.result <> 'no_reward') as total_won,
      count(sh2.id) filter (where sh2.result = 'no_reward') as total_missed,
      coalesce((select sum(t.amount) from public.transactions t where t.user_id = p.id and t.type in ('Deposit (Approved)','deposit') and t.status = 'Success'), 0) as total_deposit,
      coalesce((select sum(t.amount) from public.transactions t where t.user_id = p.id and t.type = 'Withdraw' and t.status = 'Success'), 0) as total_withdraw,
      coalesce((select sum(t.amount) from public.transactions t where t.user_id = p.id and t.type = 'Match Win' and t.status = 'Success'), 0)
        + coalesce((select sum(t.amount) from public.transactions t where t.user_id = p.id and t.type = 'Spin Reward' and t.status = 'Success'), 0)
        + coalesce((select sum(t.amount) from public.transactions t where t.user_id = p.id and t.type = 'Match Join' and t.method = 'Coupon' and t.status = 'Success'), 0) as total_win_amount,
      coalesce((select sum(t.amount) from public.transactions t where t.user_id = p.id and t.type = 'Match Join' and t.method = 'Wallet' and t.status = 'Success'), 0) as total_loss_amount
    from public.profiles p
    join public.spin_history sh on sh.user_id = p.id and sh.result <> 'no_reward'
    join public.spin_history sh2 on sh2.user_id = p.id
    group by p.id, p.username, p.oxn_id
  ) w;

  return jsonb_build_object('overview', v_overview, 'daily', v_daily, 'winners', v_winners);
end;
$function$;

CREATE OR REPLACE FUNCTION public.trigger_send_push()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform net.http_post(
    url := 'https://iiywltreljfwpjactrdr.supabase.co/functions/v1/bright-api',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := jsonb_build_object('record', to_jsonb(NEW))
  );
  return NEW;
end;
$function$;
-- IMPORTANT: replace iiywltreljfwpjactrdr above with your new project's ref
-- (Project Settings > General > Reference ID) AFTER you deploy the
-- bright-api edge function (see edge-functions/bright-api/index.ts).

CREATE OR REPLACE FUNCTION public.process_sms_payment(p_trx_id text, p_amount numeric, p_method text, p_raw_sender text, p_raw_body text, p_sender_number text DEFAULT NULL::text, p_txn_type text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_log_id uuid;
    v_req record;
begin
    if p_txn_type is not null and p_txn_type <> 'send_money' then
        insert into sms_logs (raw_sender, raw_body, parsed_trx_id, parsed_amount, parsed_method, parsed_sender_number, parsed_txn_type, match_status)
        values (p_raw_sender, p_raw_body, p_trx_id, p_amount, p_method, p_sender_number, p_txn_type, 'ignored_not_send_money');
        return jsonb_build_object('status', 'ignored_not_send_money', 'txn_type', p_txn_type);
    end if;

    if p_trx_id is null or regexp_replace(p_trx_id, '\s+', '', 'g') = '' or p_amount is null or p_amount <= 0 then
        insert into sms_logs (raw_sender, raw_body, parsed_trx_id, parsed_amount, parsed_method, parsed_sender_number, parsed_txn_type, match_status)
        values (p_raw_sender, p_raw_body, p_trx_id, p_amount, p_method, p_sender_number, p_txn_type, 'parse_failed');
        return jsonb_build_object('status', 'parse_failed');
    end if;

    p_trx_id := upper(regexp_replace(p_trx_id, '\s+', '', 'g'));

    insert into sms_logs (raw_sender, raw_body, parsed_trx_id, parsed_amount, parsed_method, parsed_sender_number, parsed_txn_type, match_status)
    values (p_raw_sender, p_raw_body, p_trx_id, p_amount, p_method, p_sender_number, p_txn_type, 'processing')
    returning id into v_log_id;

    begin
        insert into consumed_trx_ids (trx_id, sms_log_id, amount) values (p_trx_id, v_log_id, p_amount);
    exception when unique_violation then
        update sms_logs set match_status = 'duplicate', processed_at = now() where id = v_log_id;
        return jsonb_build_object('status', 'duplicate', 'trx_id', p_trx_id);
    end;

    select * into v_req from deposit_requests
    where upper(regexp_replace(trx_id, '\s+', '', 'g')) = p_trx_id and status = 'pending' and amount = p_amount
    order by created_at asc limit 1
    for update;

    if v_req.id is null then
        update sms_logs set match_status = 'unmatched', processed_at = now() where id = v_log_id;
        delete from consumed_trx_ids where trx_id = p_trx_id and sms_log_id = v_log_id;
        return jsonb_build_object('status', 'unmatched', 'trx_id', p_trx_id, 'amount', p_amount);
    end if;

    update deposit_requests set status = 'approved', processed_at = now() where id = v_req.id;
    update profiles set deposit = coalesce(deposit,0) + p_amount where id = v_req.user_id;
    insert into transactions (user_id, type, amount, status, method, note)
    values (v_req.user_id, 'deposit', p_amount, 'Success', p_method, 'Auto SMS Verified — TrxID: ' || p_trx_id || coalesce(' — From: ' || p_sender_number, ''));

    update consumed_trx_ids set deposit_request_id = v_req.id where trx_id = p_trx_id;
    update sms_logs set match_status = 'matched', matched_deposit_id = v_req.id, matched_user_id = v_req.user_id, processed_at = now() where id = v_log_id;

    return jsonb_build_object('status', 'matched', 'user_id', v_req.user_id, 'amount', p_amount, 'trx_id', p_trx_id, 'deposit_request_id', v_req.id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.try_match_deposit_with_existing_sms()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_log record;
  v_trx text;
begin
  v_trx := upper(regexp_replace(coalesce(new.trx_id, ''), '\s+', '', 'g'));
  if v_trx = '' then
    return new;
  end if;

  select * into v_log
  from sms_logs
  where match_status = 'unmatched'
    and upper(regexp_replace(parsed_trx_id, '\s+', '', 'g')) = v_trx
    and parsed_amount = new.amount
  order by received_at asc
  limit 1
  for update;

  if v_log.id is null then
    return new;
  end if;

  begin
    insert into consumed_trx_ids (trx_id, sms_log_id, amount, deposit_request_id)
    values (v_trx, v_log.id, new.amount, new.id);
  exception when unique_violation then
    return new;
  end;

  update deposit_requests set status = 'approved', processed_at = now() where id = new.id;
  update profiles set deposit = coalesce(deposit,0) + new.amount where id = new.user_id;

  insert into transactions (user_id, type, amount, status, method, note)
  values (new.user_id, 'deposit', new.amount, 'Success', new.method, 'Auto SMS Verified — TrxID: ' || v_trx);

  update sms_logs set match_status = 'matched', matched_deposit_id = new.id, matched_user_id = new.user_id, processed_at = now() where id = v_log.id;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.manual_match_sms(p_sms_log_id uuid, p_deposit_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_log record;
    v_req record;
begin
    if not exists (select 1 from public.admins where id = auth.uid()) then
        raise exception 'শুধুমাত্র অ্যাডমিন এই কাজ করতে পারবে';
    end if;

    select * into v_log from sms_logs where id = p_sms_log_id;
    select * into v_req from deposit_requests where id = p_deposit_request_id;

    if v_log.id is null or v_req.id is null then
        return jsonb_build_object('status', 'error', 'message', 'SMS বা রিকোয়েস্ট পাওয়া যায়নি');
    end if;
    if v_req.status != 'pending' then
        return jsonb_build_object('status', 'error', 'message', 'এই রিকোয়েস্ট আর pending নেই');
    end if;
    if exists (select 1 from consumed_trx_ids where sms_log_id = p_sms_log_id) then
        return jsonb_build_object('status', 'error', 'message', 'এই SMS আগেই ব্যবহার হয়ে গেছে');
    end if;

    insert into consumed_trx_ids (trx_id, sms_log_id, deposit_request_id, amount)
    values (coalesce(v_log.parsed_trx_id, 'MANUAL-'||p_sms_log_id::text), p_sms_log_id, p_deposit_request_id, v_req.amount)
    on conflict (trx_id) do nothing;

    update deposit_requests set status = 'approved', processed_at = now() where id = p_deposit_request_id;
    update profiles set deposit = coalesce(deposit,0) + v_req.amount where id = v_req.user_id;
    insert into transactions (user_id, type, amount, status, method, note)
    values (v_req.user_id, 'deposit', v_req.amount, 'Success', v_req.method, 'Manually Matched by Admin — SMS Log: ' || p_sms_log_id::text);

    update sms_logs set match_status = 'matched', matched_deposit_id = p_deposit_request_id, matched_user_id = v_req.user_id, processed_at = now() where id = p_sms_log_id;

    return jsonb_build_object('status', 'matched');
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_unmatch_deposit(p_sms_log_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_log record;
    v_req record;
begin
    if not exists (select 1 from public.admins where id = auth.uid()) then
        raise exception 'শুধুমাত্র অ্যাডমিন এই কাজ করতে পারবে';
    end if;

    select * into v_log from sms_logs where id = p_sms_log_id;
    if v_log.id is null then
        return jsonb_build_object('status', 'error', 'message', 'SMS log পাওয়া যায়নি');
    end if;
    if v_log.match_status <> 'matched' then
        return jsonb_build_object('status', 'error', 'message', 'এই SMS matched অবস্থায় নেই');
    end if;

    select * into v_req from deposit_requests where id = v_log.matched_deposit_id;

    if v_req.id is not null then
        update profiles set deposit = coalesce(deposit,0) - v_req.amount where id = v_req.user_id;
        update deposit_requests set status = 'pending', processed_at = null where id = v_req.id;
        insert into transactions (user_id, type, amount, status, method, note)
        values (v_req.user_id, 'deposit_reversal', v_req.amount, 'Reversed', v_req.method,
                'Admin Unmatched — SMS Log: ' || p_sms_log_id::text || ', TrxID: ' || coalesce(v_log.parsed_trx_id, ''));
    end if;

    delete from consumed_trx_ids where sms_log_id = p_sms_log_id;

    update sms_logs
    set match_status = 'unmatched', matched_deposit_id = null, matched_user_id = null, processed_at = received_at
    where id = p_sms_log_id;

    return jsonb_build_object('status', 'unmatched', 'sms_log_id', p_sms_log_id, 'deposit_request_id', v_req.id, 'reversed_amount', v_req.amount);
end;
$function$;

CREATE OR REPLACE FUNCTION public.ff_uid_cache_upsert(p_uid text, p_name text, p_level integer, p_region text, p_raw jsonb)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  insert into ff_uid_cache(uid, name, level, region, raw, updated_at)
  values (p_uid, p_name, p_level, p_region, p_raw, now())
  on conflict (uid) do update set
    name = excluded.name, level = excluded.level, region = excluded.region,
    raw = excluded.raw, updated_at = now();
$function$;

CREATE OR REPLACE FUNCTION public.ff_uid_lookup_is_unlimited()
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(uid_lookup_unlimited, false) from app_settings where id = 1;
$function$;

CREATE OR REPLACE FUNCTION public.ff_uid_lookup_try_increment(p_daily_limit integer DEFAULT 2)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user uuid := auth.uid();
  v_today date := current_date;
  v_unlimited boolean;
  v_count integer;
begin
  if v_user is null then
    return false;
  end if;

  select coalesce(uid_lookup_unlimited, false) into v_unlimited from app_settings where id = 1;
  if v_unlimited then
    return true;
  end if;

  select lookup_count into v_count from ai_uid_lookups where user_id = v_user and lookup_date = v_today;
  if v_count is null then
    v_count := 0;
  end if;

  if v_count >= p_daily_limit then
    return false;
  end if;

  insert into ai_uid_lookups(user_id, lookup_date, lookup_count)
  values (v_user, v_today, 1)
  on conflict (user_id, lookup_date)
  do update set lookup_count = ai_uid_lookups.lookup_count + 1;

  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION public.try_uid_lookup(p_user_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_count int;
begin
  insert into public.ai_uid_lookups(user_id, lookup_date, lookup_count)
  values (p_user_id, current_date, 1)
  on conflict (user_id, lookup_date)
  do update set lookup_count = ai_uid_lookups.lookup_count + 1
    where ai_uid_lookups.lookup_count < 2
  returning lookup_count into v_count;

  return v_count is not null;
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_active_api_keys(p_provider text)
 RETURNS TABLE(id bigint, api_key text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select id, api_key
  from public.ff_api_key_pool
  where provider = p_provider and is_active = true
  order by (last_used_at is not null), last_used_at asc, id asc;
$function$;

CREATE OR REPLACE FUNCTION public.mark_api_key_used(p_id bigint)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  update public.ff_api_key_pool set last_used_at = now() where id = p_id;
$function$;

CREATE OR REPLACE FUNCTION public.report_api_key_failure(p_id bigint, p_error text, p_permanent boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_fail_count int;
begin
  if p_permanent then
    delete from public.ff_api_key_pool where id = p_id;
    return;
  end if;

  update public.ff_api_key_pool
    set fail_count = fail_count + 1, last_error = p_error
    where id = p_id
    returning fail_count into v_fail_count;

  if v_fail_count is not null and v_fail_count >= 5 then
    delete from public.ff_api_key_pool where id = p_id;
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.record_ff_key_failure(key_id bigint, http_status integer DEFAULT NULL::integer, err_msg text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  if http_status in (401, 403) then
    delete from ff_uid_providers where id = key_id;
  else
    update ff_uid_providers
      set fail_count = fail_count + 1, last_error = coalesce(err_msg, 'unknown_error'), last_used_at = now()
      where id = key_id;
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.record_ff_key_success(key_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
  cur ff_uid_providers%rowtype;
begin
  select * into cur from ff_uid_providers where id = key_id for update;
  if not found then return; end if;

  if (cur.used_count + 1) >= cur.monthly_limit then
    delete from ff_uid_providers where id = key_id;
  else
    update ff_uid_providers
      set used_count = used_count + 1, fail_count = 0, last_used_at = now(), last_error = null
      where id = key_id;
  end if;
end;
$function$;

-- reserve_ff_key: two overloads (no-arg version and ignore-limits version)
CREATE OR REPLACE FUNCTION public.reserve_ff_key()
 RETURNS SETOF ff_uid_providers
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
  r ff_uid_providers%rowtype;
begin
  for r in
    select * from ff_uid_providers
    where is_active = true
      and used_count < monthly_limit
    order by priority asc, id asc
    for update skip locked
  loop
    if r.window_start is null or now() - r.window_start >= interval '1 minute' then
      update ff_uid_providers
        set window_start = now(), window_count = 1
        where ff_uid_providers.id = r.id;
      return query select * from ff_uid_providers where id = r.id;
      return;
    elsif r.window_count < 5 then
      update ff_uid_providers
        set window_count = window_count + 1
        where ff_uid_providers.id = r.id;
      return query select * from ff_uid_providers where id = r.id;
      return;
    end if;
  end loop;
  return;
end;
$function$;

CREATE OR REPLACE FUNCTION public.reserve_ff_key(p_ignore_limits boolean DEFAULT false)
 RETURNS SETOF ff_uid_providers
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
  r ff_uid_providers%rowtype;
begin
  if p_ignore_limits then
    for r in
      select * from ff_uid_providers
      where is_active = true
      order by priority asc, id asc
      for update skip locked
      limit 1
    loop
      update ff_uid_providers set last_used_at = now() where ff_uid_providers.id = r.id;
      return query select * from ff_uid_providers where id = r.id;
      return;
    end loop;
    return;
  end if;

  for r in
    select * from ff_uid_providers
    where is_active = true
      and used_count < monthly_limit
    order by priority asc, id asc
    for update skip locked
  loop
    if r.window_start is null or now() - r.window_start >= interval '1 minute' then
      update ff_uid_providers
        set window_start = now(), window_count = 1
        where ff_uid_providers.id = r.id;
      return query select * from ff_uid_providers where id = r.id;
      return;
    elsif r.window_count < 5 then
      update ff_uid_providers
        set window_count = window_count + 1
        where ff_uid_providers.id = r.id;
      return query select * from ff_uid_providers where id = r.id;
      return;
    end if;
  end loop;
  return;
end;
$function$;
