-- Replace exposed SECURITY DEFINER admin RPCs with column-level grants and RLS.
create policy bootstrap_codes_deny_all
  on private.bootstrap_codes for all to authenticated using (false) with check (false);

drop policy if exists profile_read_self on public.profiles;
drop policy if exists profile_read_admin on public.profiles;
create policy profile_read_self_or_admin on public.profiles
  for select to authenticated using (id = (select auth.uid()) or private.is_mine_me_admin());

drop policy if exists referral_read_own on public.referrals;
drop policy if exists referral_read_admin on public.referrals;
create policy referral_read_own_or_admin on public.referrals
  for select to authenticated using (
    inviter_id = (select auth.uid()) or invitee_id = (select auth.uid()) or private.is_mine_me_admin()
  );

drop policy if exists device_read_self on public.devices;
drop policy if exists device_read_admin on public.devices;
create policy device_read_self_or_admin on public.devices
  for select to authenticated using (user_id = (select auth.uid()) or private.is_mine_me_admin());

drop policy if exists device_events_read_own on public.device_events;
drop policy if exists device_events_read_admin on public.device_events;
create policy device_events_read_own_or_admin on public.device_events
  for select to authenticated using (
    private.is_mine_me_admin()
    or exists (select 1 from public.devices d where d.id = device_id and d.user_id = (select auth.uid()))
  );

drop policy if exists share_ledger_read_own on public.mining_share_ledger;
drop policy if exists share_ledger_read_admin on public.mining_share_ledger;
create policy share_ledger_read_own_or_admin on public.mining_share_ledger
  for select to authenticated using (
    private.is_mine_me_admin()
    or exists (select 1 from public.devices d where d.id = device_id and d.user_id = (select auth.uid()))
  );

create index if not exists bootstrap_codes_consumed_by_idx on private.bootstrap_codes (consumed_by);
create index if not exists profiles_referred_by_idx on public.profiles (referred_by);
create index if not exists audit_logs_actor_id_idx on public.audit_logs (actor_id);
