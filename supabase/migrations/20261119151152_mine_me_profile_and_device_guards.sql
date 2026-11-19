-- Enforce profile and bootstrap invariants for admin-managed account/referral state.
create or replace function private.enforce_profile_admin_bounds()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.role = 'admin' and old.account_status = 'active' and new.account_status = 'suspended'
     and not exists (select 1 from public.profiles p where p.role='admin'
       and p.account_status='active' and p.id <> old.id) then
    raise exception 'The last active administrator cannot be suspended.';
  end if;
  if new.account_status <> 'active' and new.referral_enabled then
    new.referral_enabled := false;
  end if;
  return new;
end;
$$;
revoke all on function private.enforce_profile_admin_bounds() from public, anon, authenticated, service_role;
drop trigger if exists profiles_enforce_admin_bounds on public.profiles;
create trigger profiles_enforce_admin_bounds before update of account_status, referral_enabled
on public.profiles for each row execute function private.enforce_profile_admin_bounds();

create or replace function private.enforce_device_safety_bounds()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  v_max_intensity integer := 80;
  v_emergency_pause boolean := true;
  v_member_active boolean := false;
  v_has_consent boolean := false;
begin
  select (ps.value #>> '{}')::integer into v_max_intensity
    from public.platform_settings ps where ps.key='global_max_intensity_percent';
  v_max_intensity := least(80, greatest(1, coalesce(v_max_intensity,80)));
  new.intensity_percent := least(greatest(1,coalesce(new.intensity_percent,20)),v_max_intensity);
  select coalesce((ps.value #>> '{}')::boolean,true) into v_emergency_pause
    from public.platform_settings ps where ps.key='global_emergency_pause';
  select exists(select 1 from public.profiles p where p.id=new.user_id and p.account_status='active')
    into v_member_active;
  select exists(select 1 from public.profiles p where p.id=new.user_id
    and p.consent_version='2026-11-19-v1' and p.consented_at is not null)
    into v_has_consent;
  if not v_member_active or not v_has_consent then
    new.status := 'blocked';
  elsif new.status='running' and coalesce(v_emergency_pause,true) then
    new.status := 'paused';
  end if;
  return new;
end;
$$;
revoke all on function private.enforce_device_safety_bounds() from public, anon, authenticated, service_role;
