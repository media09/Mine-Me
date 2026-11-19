-- The safety trigger may change a requested "running" status to "paused".
-- Clear the gateway lease after making that final decision.

create or replace function private.enforce_device_safety_bounds()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_max_intensity integer := 80;
  v_emergency_pause boolean := true;
  v_mining_enabled boolean := false;
  v_member_active boolean := false;
  v_has_consent boolean := false;
  v_is_admin boolean := false;
begin
  select (ps.value #>> '{}')::integer into v_max_intensity
  from public.platform_settings ps
  where ps.key = 'global_max_intensity_percent';
  v_max_intensity := least(80, greatest(1, coalesce(v_max_intensity, 80)));
  new.intensity_percent := least(greatest(1, coalesce(new.intensity_percent, 20)), v_max_intensity);

  select coalesce((ps.value #>> '{}')::boolean, true) into v_emergency_pause
  from public.platform_settings ps
  where ps.key = 'global_emergency_pause';

  select coalesce((ps.value #>> '{}')::boolean, false) into v_mining_enabled
  from public.platform_settings ps
  where ps.key = 'mining_enabled';

  select exists (
    select 1 from public.profiles p
    where p.id = new.user_id and p.account_status = 'active'
  ) into v_member_active;

  select exists (
    select 1 from public.profiles p
    where p.id = new.user_id
      and p.consent_version = '2026-11-19-v1'
      and p.consented_at is not null
  ) into v_has_consent;

  if not v_member_active or not v_has_consent then
    new.status := 'blocked';
  elsif tg_op = 'UPDATE'
    and old.status is distinct from new.status
    and (select auth.uid()) = new.user_id then
    select private.is_mine_me_admin() into v_is_admin;
    if not v_is_admin and new.status not in ('paused', 'stopped', 'enrolled') then
      raise exception 'Participants may only pause, stop, or explicitly re-enroll their own device.';
    end if;
  end if;

  if new.status = 'running'
     and (coalesce(v_emergency_pause, true) or not coalesce(v_mining_enabled, false)) then
    new.status := 'paused';
  end if;

  if new.status <> 'running' then
    new.active_session_id := null;
  end if;

  return new;
end;
$$;

revoke all on function private.enforce_device_safety_bounds() from public, anon, authenticated, service_role;
