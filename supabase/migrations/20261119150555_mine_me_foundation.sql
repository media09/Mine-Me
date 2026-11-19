-- MINE-ME initial schema.
-- Signup trigger enforces a valid referral and an explicit, versioned consent record.
-- Client grants are minimal; every exposed public table has RLS enabled.

create schema if not exists private;
revoke all on schema private from public;
revoke all on schema private from anon, authenticated, service_role;
grant usage on schema private to supabase_auth_admin, authenticated;

-- One-time first-admin code. Kept outside the exposed public schema.
create table if not exists private.bootstrap_codes (
  token text primary key,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  consumed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table private.bootstrap_codes enable row level security;
revoke all on private.bootstrap_codes from public, anon, authenticated, service_role;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  role text not null default 'participant' check (role in ('participant', 'admin')),
  referral_code text not null unique,
  referred_by uuid references public.profiles(id),
  consent_version text not null,
  consented_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table if not exists public.referrals (
  id uuid primary key default gen_random_uuid(),
  inviter_id uuid not null references public.profiles(id) on delete cascade,
  invitee_id uuid not null unique references public.profiles(id) on delete cascade,
  referral_code text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  installation_id uuid not null,
  worker_code text not null unique default (
    'MM-' || upper(replace(gen_random_uuid()::text, '-', ''))
  ),
  label text,
  browser_family text,
  platform_family text,
  hardware_threads integer check (hardware_threads between 1 and 256),
  intensity_percent integer not null default 20 check (intensity_percent between 1 and 80),
  status text not null default 'enrolled'
    check (status in ('enrolled', 'running', 'paused', 'stopped', 'offline', 'blocked')),
  last_seen_at timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, installation_id)
);

create table if not exists public.device_events (
  id bigint generated always as identity primary key,
  device_id uuid not null references public.devices(id) on delete cascade,
  event_type text not null
    check (event_type in ('enrolled', 'started', 'paused', 'resumed', 'stopped', 'heartbeat', 'error')),
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Only pool-verified shares may be written by trusted reconciliation services.
create table if not exists public.mining_share_ledger (
  id bigint generated always as identity primary key,
  device_id uuid not null references public.devices(id) on delete cascade,
  pool_share_id text not null unique,
  accepted boolean not null,
  difficulty numeric(30, 8),
  verified_at timestamptz not null,
  created_at timestamptz not null default now()
);

-- Platform-level receipts only; this is not a participant wallet or withdrawable balance.
create table if not exists public.central_wallet_receipts (
  id bigint generated always as identity primary key,
  transaction_ref text not null unique,
  asset text not null,
  amount numeric(30, 12) not null check (amount > 0),
  network text not null,
  confirmed_at timestamptz not null,
  source text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.platform_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id),
  action text not null,
  target_type text,
  target_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- A trigger-only function in a non-exposed schema. It is not an RPC/API endpoint.
-- RLS helper for admin-only reads and settings control. It exposes no admin data.
create or replace function private.is_mine_me_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'
  );
$;

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

  -- Serialize the first signup so only one one-time code can create the initial admin.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('mine-me-first-admin-bootstrap'));

  if not exists (select 1 from public.profiles) then
    select b.token into v_bootstrap_token
    from private.bootstrap_codes b
    where b.token = v_referral_code
      and b.consumed_at is null
      and b.expires_at > now()
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
    select p.id into v_inviter_id
    from public.profiles p
    where p.referral_code = v_referral_code;

    if v_inviter_id is null then
      raise exception 'The referral code is invalid or no longer active.';
    end if;
  end if;

  loop
    v_own_code := upper(substr(replace(pg_catalog.gen_random_uuid()::text, '-', ''), 1, 10));
    exit when not exists (
      select 1 from public.profiles p where p.referral_code = v_own_code
    );
  end loop;

  insert into public.profiles (
    id, display_name, role, referral_code, referred_by, consent_version, consented_at
  ) values (
    new.id,
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'display_name', '')), ''),
    case when v_is_bootstrap then 'admin' else 'participant' end,
    v_own_code,
    v_inviter_id,
    v_consent_version,
    now()
  );

  if v_is_bootstrap then
    update private.bootstrap_codes
    set consumed_at = now(), consumed_by = new.id
    where token = v_bootstrap_token;
  else
    insert into public.referrals (inviter_id, invitee_id, referral_code)
    values (v_inviter_id, new.id, v_referral_code);
  end if;

  return new;
end;
$$;

revoke all on function private.handle_mine_me_signup() from public, anon, authenticated, service_role;

drop trigger if exists on_auth_user_created_mine_me on auth.users;
create trigger on_auth_user_created_mine_me
after insert on auth.users
for each row execute function private.handle_mine_me_signup();

-- RLS is enabled on every application table.
alter table public.profiles enable row level security;
alter table public.referrals enable row level security;
alter table public.devices enable row level security;
alter table public.device_events enable row level security;
alter table public.mining_share_ledger enable row level security;
alter table public.central_wallet_receipts enable row level security;
alter table public.platform_settings enable row level security;
alter table public.audit_logs enable row level security;

-- October 30, 2026 Supabase Data API change: expose only tables and privileges explicitly needed.
grant usage on schema public to authenticated, service_role;
grant select on public.profiles, public.referrals, public.devices,
  public.device_events, public.mining_share_ledger,
  public.central_wallet_receipts, public.platform_settings, public.audit_logs to authenticated;

-- Device enrollment can be performed by the signed-in participant without a service-role secret.
-- Identity and status are fixed by RLS/defaults; participants cannot write worker_code or status.
grant insert (user_id, installation_id, label, browser_family, platform_family, hardware_threads)
  on public.devices to authenticated;
grant update (label, browser_family, platform_family, hardware_threads, last_seen_at, intensity_percent)
  on public.devices to authenticated;
grant update (value, updated_at) on public.platform_settings to authenticated;

-- Trusted server-side services only. Keep the service-role key out of all browser bundles.
grant all on public.profiles, public.referrals, public.devices, public.device_events,
  public.mining_share_ledger, public.central_wallet_receipts,
  public.platform_settings, public.audit_logs to service_role;
grant usage, select on all sequences in schema public to service_role;

create policy profile_read_self on public.profiles
  for select to authenticated using (id = (select auth.uid()));

create policy profile_read_admin on public.profiles
  for select to authenticated using (private.is_mine_me_admin());

create policy referral_read_own on public.referrals
  for select to authenticated
  using (inviter_id = (select auth.uid()) or invitee_id = (select auth.uid()));

create policy referral_read_admin on public.referrals
  for select to authenticated using (private.is_mine_me_admin());

create policy device_read_self on public.devices
  for select to authenticated using (user_id = (select auth.uid()));

create policy device_read_admin on public.devices
  for select to authenticated using (private.is_mine_me_admin());

create policy device_enroll_self on public.devices
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and status = 'enrolled'
    and intensity_percent = 20
  );

create policy device_update_self on public.devices
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy device_events_read_own on public.device_events
  for select to authenticated
  using (exists (
    select 1 from public.devices d
    where d.id = device_id and d.user_id = (select auth.uid())
  ));

create policy device_events_read_admin on public.device_events
  for select to authenticated using (private.is_mine_me_admin());

create policy share_ledger_read_own on public.mining_share_ledger
  for select to authenticated
  using (exists (
    select 1 from public.devices d
    where d.id = device_id and d.user_id = (select auth.uid())
  ));

create policy share_ledger_read_admin on public.mining_share_ledger
  for select to authenticated using (private.is_mine_me_admin());

create policy central_wallet_receipts_read_admin on public.central_wallet_receipts
  for select to authenticated using (private.is_mine_me_admin());

create policy platform_settings_read_admin on public.platform_settings
  for select to authenticated using (private.is_mine_me_admin());

create policy platform_settings_update_admin on public.platform_settings
  for update to authenticated
  using (private.is_mine_me_admin())
  with check (private.is_mine_me_admin());

create policy audit_logs_read_admin on public.audit_logs
  for select to authenticated using (private.is_mine_me_admin());

create index if not exists devices_user_created_idx
  on public.devices (user_id, created_at desc);
create index if not exists referrals_inviter_created_idx
  on public.referrals (inviter_id, created_at desc);
create index if not exists device_events_device_created_idx
  on public.device_events (device_id, created_at desc);
create index if not exists mining_shares_device_verified_idx
  on public.mining_share_ledger (device_id, verified_at desc);
create index if not exists audit_logs_created_idx
  on public.audit_logs (created_at desc);

insert into public.platform_settings (key, value) values
  ('global_emergency_pause', 'true'::jsonb),
  ('global_max_intensity_percent', '80'::jsonb)
on conflict (key) do nothing;

-- Intentionally no client write policies. Central wallet, settings and audit tables are server-only.
