-- MINE-ME initial schema.
-- The auth trigger enforces both referral validation and the consent version on signup.
-- The public client receives read access only where an explicit RLS policy allows it.
-- Trusted server code must own all operational writes.

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
  worker_code text not null unique,
  label text,
  browser_family text,
  platform_family text,
  hardware_threads integer check (hardware_threads between 1 and 256),
  intensity_percent integer not null default 20 check (intensity_percent between 1 and 80),
  status text not null default 'enrolled'
    check (status in ('enrolled', 'running', 'paused', 'stopped', 'offline', 'blocked')),
  last_seen_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.device_events (
  id bigint generated always as identity primary key,
  device_id uuid not null references public.devices(id) on delete cascade,
  event_type text not null
    check (event_type in ('enrolled', 'started', 'paused', 'resumed', 'stopped', 'heartbeat', 'error')),
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Only pool-verified shares may be inserted by trusted backend reconciliation.
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

-- Signup requires a valid existing referral and the current consent acknowledgement.
create or replace function public.handle_mine_me_signup()
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
begin
  v_referral_code := upper(trim(coalesce(new.raw_user_meta_data ->> 'referral_code', '')));
  v_consent_version := coalesce(new.raw_user_meta_data ->> 'consent_version', '');

  if v_referral_code = '' then
    raise exception 'A valid referral code is required to create a MINE-ME account.';
  end if;

  if coalesce(new.raw_user_meta_data ->> 'consent_to_compute', 'false') <> 'true'
     or v_consent_version <> '2026-11-19-v1' then
    raise exception 'Explicit acceptance of the current MINE-ME participation terms is required.';
  end if;

  select p.id into v_inviter_id
  from public.profiles p
  where p.referral_code = v_referral_code;

  if v_inviter_id is null then
    raise exception 'The referral code is invalid or no longer active.';
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
    'participant',
    v_own_code,
    v_inviter_id,
    v_consent_version,
    now()
  );

  insert into public.referrals (inviter_id, invitee_id, referral_code)
  values (v_inviter_id, new.id, v_referral_code);

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_mine_me on auth.users;
create trigger on_auth_user_created_mine_me
after insert on auth.users
for each row execute function public.handle_mine_me_signup();

-- RLS is enabled on every application table.
alter table public.profiles enable row level security;
alter table public.referrals enable row level security;
alter table public.devices enable row level security;
alter table public.device_events enable row level security;
alter table public.mining_share_ledger enable row level security;
alter table public.central_wallet_receipts enable row level security;
alter table public.platform_settings enable row level security;
alter table public.audit_logs enable row level security;

-- Minimum client grants; rows are further restricted by RLS.
grant select on public.profiles, public.referrals, public.devices,
  public.device_events, public.mining_share_ledger to authenticated;

create policy profile_read_self on public.profiles
  for select to authenticated using (id = (select auth.uid()));

create policy referral_read_own on public.referrals
  for select to authenticated
  using (inviter_id = (select auth.uid()) or invitee_id = (select auth.uid()));

create policy device_read_self on public.devices
  for select to authenticated using (user_id = (select auth.uid()));

create policy device_events_read_own on public.device_events
  for select to authenticated
  using (exists (
    select 1 from public.devices d
    where d.id = device_id and d.user_id = (select auth.uid())
  ));

create policy share_ledger_read_own on public.mining_share_ledger
  for select to authenticated
  using (exists (
    select 1 from public.devices d
    where d.id = device_id and d.user_id = (select auth.uid())
  ));

-- There are deliberately no client write policies.
-- Central wallet receipts, settings, audit data and admin operations are server-only.
-- Never put a service-role key in browser code. Apply this migration only after reviewing it.
