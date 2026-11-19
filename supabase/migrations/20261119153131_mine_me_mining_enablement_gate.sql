-- Separate enablement from the emergency pause and enforce both at the DB boundary.
-- Mining remains disabled by default until the WSS gateway and upstream proxy are tested.

insert into public.platform_settings (key, value)
values ('mining_enabled', 'false'::jsonb)
on conflict (key) do nothing;

-- Safe runtime flags are visible to authenticated clients; only admins can update them.
drop policy if exists platform_settings_read_admin on public.platform_settings;
create policy platform_settings_read_safe_or_admin
  on public.platform_settings
  for select to authenticated
  using (
    key in ('mining_enabled', 'global_emergency_pause', 'global_max_intensity_percent')
    or private.is_mine_me_admin()
  );

create or replace function private.audit_platform_setting_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.audit_logs (actor_id, action, target_type, target_id, metadata)
  values (
    (select auth.uid()),
    'platform_setting_updated',
    'platform_settings',
    new.key,
    jsonb_build_object('old_value', old.value, 'new_value', new.value)
  );

  if (new.key = 'global_emergency_pause' and (new.value #>> '{}')::boolean = true)
     or (new.key = 'mining_enabled' and (new.value #>> '{}')::boolean = false) then
    update public.devices
    set status = 'paused'
    where status = 'running';
  end if;

  return new;
end;
$$;

revoke all on function private.audit_platform_setting_change() from public, anon, authenticated, service_role;

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

  return new;
end;
$$;

revoke all on function private.enforce_device_safety_bounds() from public, anon, authenticated, service_role;

-- Restore only from paused/stopped/offline; never allow participant-originated "running".
create or replace function private.guard_device_participant_transition()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_is_admin boolean := false;
begin
  if tg_op = 'UPDATE'
     and old.status is distinct from new.status
     and (select auth.uid()) = new.user_id then
    select private.is_mine_me_admin() into v_is_admin;
    if not v_is_admin then
      if new.status not in ('paused', 'stopped', 'enrolled') then
        raise exception 'Participant cannot set a worker to a running or blocked state.';
      end if;
      if new.status = 'enrolled' and old.status not in ('paused', 'stopped', 'offline') then
        raise exception 'This device is not in a state that can be re-enrolled.';
      end if;
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.guard_device_participant_transition() from public, anon, authenticated, service_role;

drop trigger if exists devices_guard_participant_transition on public.devices;
create trigger devices_guard_participant_transition
before update of status on public.devices
for each row execute function private.guard_device_participant_transition();
