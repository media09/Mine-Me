-- Consolidate device UPDATE policy and allow participants to pause/stop their own device record.
-- Participants cannot set a device to running. Only the trusted worker service may do so.

drop policy if exists device_update_self on public.devices;
drop policy if exists devices_admin_manage on public.devices;
create policy devices_update_self_or_admin
  on public.devices
  for update to authenticated
  using (
    user_id = (select auth.uid())
    or private.is_mine_me_admin()
  )
  with check (
    user_id = (select auth.uid())
    or private.is_mine_me_admin()
  );

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
  v_is_admin boolean := false;
begin
  select (ps.value #>> '{}')::integer into v_max_intensity
  from public.platform_settings ps where ps.key = 'global_max_intensity_percent';
  v_max_intensity := least(80, greatest(1, coalesce(v_max_intensity, 80)));
  new.intensity_percent := least(greatest(1, coalesce(new.intensity_percent, 20)), v_max_intensity);

  select coalesce((ps.value #>> '{}')::boolean, true) into v_emergency_pause
  from public.platform_settings ps where ps.key = 'global_emergency_pause';

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
    if not v_is_admin and new.status not in ('paused', 'stopped') then
      raise exception 'Participants may only pause or stop their own device. Mining start is controlled by the verified worker service.';
    end if;
  end if;

  if new.status = 'running' and coalesce(v_emergency_pause, true) then
    new.status := 'paused';
  end if;

  return new;
end;
$$;

revoke all on function private.enforce_device_safety_bounds() from public, anon, authenticated, service_role;
