-- Member/referral/device administration through guarded RPC functions.
-- The exposed SECURITY DEFINER RPCs in this migration are removed by the next hardening migration.

alter table public.profiles
  add column if not exists account_status text not null default 'active'
    check (account_status in ('active', 'suspended')),
  add column if not exists referral_enabled boolean not null default true;

create or replace function private.is_mine_me_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'
      and p.account_status = 'active'
  );
$$;

revoke all on function private.is_mine_me_admin() from public, anon, service_role;
grant execute on function private.is_mine_me_admin() to authenticated;

create or replace function private.handle_mine_me_signup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_referral_code text;
  v_inviter_id uuid;
  v_own_code text;
  v_consent_version text;
  v_bootstrap_token text;
  v_is_bootstrap boolean := false;
begin
  v_referral_code := upper(trim(coalesce(new.raw_user_meta_data ->> 'referral_code', '')));
  v_consent_version := coalesce(new.raw_user_meta_data ->> 'consent_version', '');

  if v_referral_code = '' then
    raise exception 'A valid invitation or referral code is required to create a MINE-ME account.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('mine-me-first-admin-bootstrap'));

  if not exists (select 1 from public.profiles) then
    select b.token into v_bootstrap_token
    from private.bootstrap_codes b
    where b.token = v_referral_code and b.consumed_at is null and b.expires_at > now()
    for update;

    if v_bootstrap_token is null then
      raise exception 'The initial administrator invitation is invalid or expired.';
    end if;
    v_is_bootstrap := true;
  end if;

  if coalesce(new.raw_user_meta_data ->> 'consent_to_compute', 'false') <> 'true'
     or v_consent_version <> '2026-11-19-v1' then
    raise exception 'Explicit acceptance of the current MINE-ME participation terms is required.';
  end if;

  if not v_is_bootstrap then
    select p.id into v_inviter_id from public.profiles p
    where p.referral_code = v_referral_code
      and p.referral_enabled = true
      and p.account_status = 'active';
    if v_inviter_id is null then
      raise exception 'The referral code is invalid, disabled, or no longer active.';
    end if;
  end if;

  loop
    v_own_code := upper(substr(replace(pg_catalog.gen_random_uuid()::text, '-', ''), 1, 10));
    exit when not exists (select 1 from public.profiles p where p.referral_code = v_own_code);
  end loop;

  insert into public.profiles (
    id, display_name, role, referral_code, referred_by,
    consent_version, consented_at, account_status, referral_enabled
  ) values (
    new.id,
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'display_name', '')), ''),
    case when v_is_bootstrap then 'admin' else 'participant' end,
    v_own_code, v_inviter_id, v_consent_version, now(), 'active', true
  );

  if v_is_bootstrap then
    update private.bootstrap_codes set consumed_at = now(), consumed_by = new.id
    where token = v_bootstrap_token;
  else
    insert into public.referrals (inviter_id, invitee_id, referral_code)
    values (v_inviter_id, new.id, v_referral_code);
  end if;

  return new;
end;
$$;

revoke all on function private.handle_mine_me_signup() from public, anon, authenticated, service_role;

create or replace function private.enforce_device_safety_bounds()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_max_intensity integer := 80;
  v_emergency_pause boolean := true;
  v_member_active boolean := false;
  v_has_consent boolean := false;
begin
  select (ps.value #>> '{}')::integer into v_max_intensity
  from public.platform_settings ps where ps.key = 'global_max_intensity_percent';
  v_max_intensity := least(80, greatest(1, coalesce(v_max_intensity, 80)));
  new.intensity_percent := least(greatest(1, coalesce(new.intensity_percent, 20)), v_max_intensity);

  select coalesce((ps.value #>> '{}')::boolean, true) into v_emergency_pause
  from public.platform_settings ps where ps.key = 'global_emergency_pause';

  select exists (select 1 from public.profiles p
    where p.id = new.user_id and p.account_status = 'active') into v_member_active;
  select exists (select 1 from public.profiles p
    where p.id = new.user_id and p.consent_version = '2026-11-19-v1'
      and p.consented_at is not null) into v_has_consent;

  if not v_member_active or not v_has_consent then
    new.status := 'blocked';
  elsif new.status = 'running' and coalesce(v_emergency_pause, true) then
    new.status := 'paused';
  end if;
  return new;
end;
$$;

revoke all on function private.enforce_device_safety_bounds() from public, anon, authenticated, service_role;

create or replace function public.admin_set_member_status(p_member_id uuid, p_status text)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_member_role text;
begin
  if not private.is_mine_me_admin() then raise exception 'Administrator access required.'; end if;
  if p_status not in ('active', 'suspended') then raise exception 'Invalid member status.'; end if;
  select role into v_member_role from public.profiles where id = p_member_id for update;
  if v_member_role is null then raise exception 'Member not found.'; end if;
  if v_member_role = 'admin' and p_status = 'suspended'
     and not exists (select 1 from public.profiles p where p.role='admin'
       and p.account_status='active' and p.id <> p_member_id) then
    raise exception 'The last active administrator cannot be suspended.';
  end if;
  update public.profiles set account_status = p_status where id = p_member_id;
  if p_status = 'suspended' then update public.devices set status='blocked' where user_id=p_member_id; end if;
  insert into public.audit_logs (actor_id, action, target_type, target_id, metadata)
  values ((select auth.uid()), 'member_status_updated', 'profile', p_member_id::text, jsonb_build_object('status',p_status));
end;
$$;

create or replace function public.admin_set_referral_enabled(p_member_id uuid, p_enabled boolean)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_status text;
begin
  if not private.is_mine_me_admin() then raise exception 'Administrator access required.'; end if;
  select account_status into v_status from public.profiles where id=p_member_id for update;
  if v_status is null then raise exception 'Member not found.'; end if;
  if p_enabled and v_status <> 'active' then raise exception 'A suspended member cannot have an active referral code.'; end if;
  update public.profiles set referral_enabled=p_enabled where id=p_member_id;
  insert into public.audit_logs (actor_id, action, target_type, target_id, metadata)
  values ((select auth.uid()), 'member_referral_toggled', 'profile', p_member_id::text, jsonb_build_object('referral_enabled',p_enabled));
end;
$$;

create or replace function public.admin_set_device_status(p_device_id uuid, p_status text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not private.is_mine_me_admin() then raise exception 'Administrator access required.'; end if;
  if p_status not in ('enrolled', 'paused', 'stopped', 'blocked') then raise exception 'Invalid administrative device status.'; end if;
  update public.devices set status=p_status where id=p_device_id;
  if not found then raise exception 'Device not found.'; end if;
  insert into public.audit_logs (actor_id, action, target_type, target_id, metadata)
  values ((select auth.uid()), 'device_status_updated', 'device', p_device_id::text, jsonb_build_object('status',p_status));
end;
$$;

revoke all on function public.admin_set_member_status(uuid,text) from public, anon;
revoke all on function public.admin_set_referral_enabled(uuid,boolean) from public, anon;
revoke all on function public.admin_set_device_status(uuid,text) from public, anon;
grant execute on function public.admin_set_member_status(uuid,text) to authenticated;
grant execute on function public.admin_set_referral_enabled(uuid,boolean) to authenticated;
grant execute on function public.admin_set_device_status(uuid,text) to authenticated;
