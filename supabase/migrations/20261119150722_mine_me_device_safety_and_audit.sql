-- Enforce global safety limits at the database boundary.
-- Browser clients cannot change worker status; trusted worker services must also pass these guards.

create or replace function private.enforce_device_safety_bounds()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_max_intensity integer := 80;
  v_emergency_pause boolean := true;
  v_has_consent boolean := false;
begin
  select (ps.value #>> '{}')::integer into v_max_intensity
  from public.platform_settings ps
  where ps.key = 'global_max_intensity_percent';

  v_max_intensity := least(80, greatest(1, coalesce(v_max_intensity, 80)));
  new.intensity_percent := least(
    greatest(1, coalesce(new.intensity_percent, 20)),
    v_max_intensity
  );

  select coalesce((ps.value #>> '{}')::boolean, true) into v_emergency_pause
  from public.platform_settings ps
  where ps.key = 'global_emergency_pause';

  if new.status = 'running' and coalesce(v_emergency_pause, true) then
    new.status := 'paused';
  end if;

  if new.status in ('running', 'paused') then
    select exists (
      select 1 from public.profiles p
      where p.id = new.user_id
        and p.consent_version = '2026-11-19-v1'
        and p.consented_at is not null
    ) into v_has_consent;

    if not v_has_consent then
      new.status := 'blocked';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function private.enforce_device_safety_bounds() from public, anon, authenticated, service_role;

drop trigger if exists devices_enforce_safety_bounds on public.devices;
create trigger devices_enforce_safety_bounds
before insert or update of intensity_percent, status on public.devices
for each row execute function private.enforce_device_safety_bounds();

-- Only record an enrollment event from the browser. Mining lifecycle events are trusted-service only.
grant insert (device_id, event_type, details) on public.device_events to authenticated;

create policy device_event_enrollment_self on public.device_events
  for insert to authenticated
  with check (
    event_type = 'enrolled'
    and exists (
      select 1 from public.devices d
      where d.id = device_id and d.user_id = (select auth.uid())
    )
  );

-- Every platform safety-setting change is recorded for administrator accountability.
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
  return new;
end;
$$;

revoke all on function private.audit_platform_setting_change() from public, anon, authenticated, service_role;

drop trigger if exists platform_settings_audit_update on public.platform_settings;
create trigger platform_settings_audit_update
after update of value on public.platform_settings
for each row
when (old.value is distinct from new.value)
execute function private.audit_platform_setting_change();
