-- Clear a gateway lease whenever a device is not running, regardless
-- of which earlier state it transitioned from.

create or replace function private.clear_device_session_lease_on_stop()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status <> 'running' then
    new.active_session_id := null;
  end if;
  return new;
end;
$$;

revoke all on function private.clear_device_session_lease_on_stop() from public, anon, authenticated, service_role;
