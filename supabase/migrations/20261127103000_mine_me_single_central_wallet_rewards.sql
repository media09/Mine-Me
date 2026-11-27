-- MINE-ME has exactly ONE HashVault Monero wallet for the entire platform.
-- Members/devices are accounting identities only; they never get pool wallets.
-- This migration is intentionally not applied to production by this development task.

create table if not exists public.central_wallet_identity (
  id boolean primary key default true check (id = true),
  provider text not null default 'HashVault' check (provider = 'HashVault'),
  asset text not null default 'XMR' check (asset = 'XMR'),
  network text not null default 'monero-mainnet' check (network = 'monero-mainnet'),
  wallet_address text not null check (length(wallet_address) between 90 and 110),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.central_wallet_identity is
  'The single platform-owned HashVault Monero wallet. Never create member or device pool wallets.';
comment on column public.central_wallet_identity.wallet_address is
  'Public Monero receiving address only. Never store a seed phrase or private spend/view key here.';

create table if not exists public.pool_payouts (
  id bigint generated always as identity primary key,
  central_wallet_id boolean not null default true
    references public.central_wallet_identity(id) on delete restrict,
  transaction_ref text not null unique,
  asset text not null default 'XMR' check (asset = 'XMR'),
  gross_amount numeric(30, 12) not null check (gross_amount > 0),
  network_fee numeric(30, 12) not null default 0 check (network_fee >= 0),
  share_window_start timestamptz,
  share_window_end timestamptz,
  received_at timestamptz not null,
  pool_height bigint,
  source text not null default 'hashvault_api' check (source in ('hashvault_api', 'admin_reconciliation')),
  created_at timestamptz not null default now(),
  check (network_fee <= gross_amount),
  check (share_window_start is null or share_window_end is null or share_window_start < share_window_end)
);

create table if not exists public.reward_distribution_batches (
  id uuid primary key default gen_random_uuid(),
  payout_id bigint not null unique references public.pool_payouts(id) on delete restrict,
  policy text not null default 'verified_contribution_weight'
    check (policy = 'verified_contribution_weight'),
  total_contribution_weight numeric(38, 12) not null check (total_contribution_weight > 0),
  allocated_amount numeric(30, 12) not null check (allocated_amount >= 0),
  platform_reserve_amount numeric(30, 12) not null check (platform_reserve_amount >= 0),
  share_window_start timestamptz not null,
  share_window_end timestamptz not null,
  status text not null default 'posted' check (status in ('posted', 'reversed')),
  created_at timestamptz not null default now(),
  check (share_window_start < share_window_end)
);

-- This is an internal accounting ledger, not a Monero wallet or direct pool payout.
create table if not exists public.member_reward_ledger (
  id bigint generated always as identity primary key,
  batch_id uuid not null references public.reward_distribution_batches(id) on delete restrict,
  member_id uuid not null references public.profiles(id) on delete restrict,
  asset text not null default 'XMR' check (asset = 'XMR'),
  amount numeric(30, 12) not null check (amount > 0),
  contribution_weight numeric(38, 12) not null check (contribution_weight > 0),
  accepted_share_count bigint not null check (accepted_share_count > 0),
  status text not null default 'available' check (status in ('available', 'held', 'reversed')),
  created_at timestamptz not null default now(),
  unique (batch_id, member_id)
);

alter table public.central_wallet_identity enable row level security;
alter table public.pool_payouts enable row level security;
alter table public.reward_distribution_batches enable row level security;
alter table public.member_reward_ledger enable row level security;

revoke all on public.central_wallet_identity, public.pool_payouts,
  public.reward_distribution_batches, public.member_reward_ledger
  from public, anon, authenticated;

grant select on public.central_wallet_identity, public.pool_payouts,
  public.reward_distribution_batches to authenticated;
grant select on public.member_reward_ledger to authenticated;
grant all on public.central_wallet_identity, public.pool_payouts,
  public.reward_distribution_batches, public.member_reward_ledger to service_role;
grant usage, select on sequence public.member_reward_ledger_id_seq to service_role;

create policy central_wallet_identity_admin_read
  on public.central_wallet_identity for select to authenticated
  using (private.is_mine_me_admin());

create policy pool_payouts_admin_read
  on public.pool_payouts for select to authenticated
  using (private.is_mine_me_admin());

create policy reward_batches_admin_read
  on public.reward_distribution_batches for select to authenticated
  using (private.is_mine_me_admin());

create policy member_reward_ledger_read_own
  on public.member_reward_ledger for select to authenticated
  using (member_id = (select auth.uid()));

create policy member_reward_ledger_read_admin
  on public.member_reward_ledger for select to authenticated
  using (private.is_mine_me_admin());

create index if not exists pool_payouts_received_idx
  on public.pool_payouts (received_at desc);
create index if not exists reward_ledger_member_created_idx
  on public.member_reward_ledger (member_id, created_at desc);
create index if not exists reward_ledger_batch_idx
  on public.member_reward_ledger (batch_id);

-- Only the trusted reconciliation worker may post a distribution. The input
-- weights must originate from pool-verified accepted shares, never client telemetry.
create or replace function private.allocate_central_pool_reward(
  p_transaction_ref text,
  p_contributions jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payout public.pool_payouts%rowtype;
  v_batch_id uuid;
  v_total_weight numeric(38, 12);
  v_allocated numeric(30, 12);
  v_reserve numeric(30, 12);
  v_count integer;
  v_distinct_count integer;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Trusted reconciliation service required.';
  end if;
  if p_transaction_ref is null or length(trim(p_transaction_ref)) < 8 then
    raise exception 'Invalid central pool payout reference.';
  end if;
  if jsonb_typeof(p_contributions) <> 'array' or jsonb_array_length(p_contributions) = 0 then
    raise exception 'Verified member contribution data is required.';
  end if;

  select * into v_payout
  from public.pool_payouts
  where transaction_ref = p_transaction_ref
  for update;
  if not found then raise exception 'Central wallet payout not found.'; end if;

  select count(*), count(distinct member_id), sum(weight)
    into v_count, v_distinct_count, v_total_weight
  from jsonb_to_recordset(p_contributions)
    as c(member_id uuid, weight numeric, accepted_share_count bigint);

  if v_count = 0 or v_count <> v_distinct_count or v_total_weight is null or v_total_weight <= 0 then
    raise exception 'Contribution weights are invalid or duplicated.';
  end if;
  if exists (
    select 1
    from jsonb_to_recordset(p_contributions)
      as c(member_id uuid, weight numeric, accepted_share_count bigint)
    left join public.profiles p on p.id = c.member_id
    where p.id is null or c.weight is null or c.weight <= 0
       or c.accepted_share_count is null or c.accepted_share_count <= 0
  ) then
    raise exception 'Contribution data contains an invalid member or weight.';
  end if;

  insert into public.reward_distribution_batches (
    payout_id, total_contribution_weight, allocated_amount, platform_reserve_amount,
    share_window_start, share_window_end
  ) values (
    v_payout.id,
    v_total_weight,
    v_payout.gross_amount - v_payout.network_fee,
    0,
    v_payout.share_window_start,
    v_payout.share_window_end
  )
  returning id into v_batch_id;

  insert into public.member_reward_ledger (
    batch_id, member_id, amount, contribution_weight, accepted_share_count
  )
  select
    v_batch_id,
    c.member_id,
    round((v_payout.gross_amount - v_payout.network_fee) * c.weight / v_total_weight, 12),
    c.weight,
    c.accepted_share_count
  from jsonb_to_recordset(p_contributions)
    as c(member_id uuid, weight numeric, accepted_share_count bigint)
  where round((v_payout.gross_amount - v_payout.network_fee) * c.weight / v_total_weight, 12) > 0;

  select coalesce(sum(amount), 0) into v_allocated
  from public.member_reward_ledger where batch_id = v_batch_id;
  v_reserve := (v_payout.gross_amount - v_payout.network_fee) - v_allocated;

  update public.reward_distribution_batches
  set allocated_amount = v_allocated,
      platform_reserve_amount = greatest(0, v_reserve)
  where id = v_batch_id;

  return v_batch_id;
end;
$$;

revoke all on function private.allocate_central_pool_reward(text, jsonb)
  from public, anon, authenticated, service_role;
grant usage on schema private to service_role;
grant execute on function private.allocate_central_pool_reward(text, jsonb)
  to service_role;

-- No participant can create a wallet, insert a payout, or credit their own ledger.
-- There is deliberately no member_wallets table and no member pool-address field.

-- This is the only public-to-service entry point for reward posting. Contribution
-- weights are aggregated from the server-side ledger of pool-accepted shares.
create or replace function private.allocate_central_pool_reward_for_window(
  p_transaction_ref text,
  p_window_start timestamptz,
  p_window_end timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_contributions jsonb;
  v_batch_id uuid;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Trusted reconciliation service required.';
  end if;
  if p_window_start is null or p_window_end is null or p_window_start >= p_window_end then
    raise exception 'A valid pool contribution window is required.';
  end if;

  update public.pool_payouts
  set share_window_start = p_window_start,
      share_window_end = p_window_end
  where transaction_ref = p_transaction_ref
    and share_window_start is null
    and share_window_end is null;

  if not exists (
    select 1 from public.pool_payouts
    where transaction_ref = p_transaction_ref
      and share_window_start = p_window_start
      and share_window_end = p_window_end
  ) then
    raise exception 'Central payout not found or already assigned to a different contribution window.';
  end if;

  select jsonb_agg(jsonb_build_object(
    'member_id', contribution.member_id,
    'weight', contribution.total_difficulty,
    'accepted_share_count', contribution.accepted_share_count
  ))
  into v_contributions
  from (
    select
      d.user_id as member_id,
      sum(s.difficulty)::numeric(38, 12) as total_difficulty,
      count(*)::bigint as accepted_share_count
    from public.mining_share_ledger s
    join public.devices d on d.id = s.device_id
    join public.profiles p on p.id = d.user_id
    where s.accepted = true
      and s.difficulty is not null
      and s.difficulty > 0
      and s.verified_at >= p_window_start
      and s.verified_at < p_window_end
      and p.account_status = 'active'
    group by d.user_id
  ) contribution;

  if v_contributions is null or jsonb_array_length(v_contributions) = 0 then
    raise exception 'No pool-accepted contribution exists in the specified window.';
  end if;

  v_batch_id := private.allocate_central_pool_reward(p_transaction_ref, v_contributions);

  update public.reward_distribution_batches
  set share_window_start = p_window_start,
      share_window_end = p_window_end
  where id = v_batch_id;

  return v_batch_id;
end;
$$;

revoke all on function private.allocate_central_pool_reward_for_window(text, timestamptz, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function private.allocate_central_pool_reward_for_window(text, timestamptz, timestamptz)
  to service_role;

-- The raw JSON allocator is internal to the window aggregator; clients and
-- reconciliation workers cannot bypass the accepted-share ledger.
revoke all on function private.allocate_central_pool_reward(text, jsonb)
  from public, anon, authenticated, service_role;
