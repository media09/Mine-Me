-- Persist the active gateway connection lease so a stale socket cannot
-- mark a newer device session offline after a reconnect.

alter table public.devices
  add column if not exists active_session_id uuid;

create or replace function private.clear_device_session_lease_on_stop()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status = 'running' and new.status <> 'running' then
    new.active_session_id := null;
  end if;
  return new;
end;
$$;

revoke all on function private.clear_device_session_lease_on_stop() from public, anon, authenticated, service_role;

drop trigger if exists devices_clear_session_lease_on_stop on public.devices;
create trigger devices_clear_session_lease_on_stop
before update of status on public.devices
for each row execute function private.clear_device_session_lease_on_stop();
