-- Browser-reported device telemetry is operational diagnostics only.
-- It is not evidence of accepted pool shares, mining revenue or a participant balance.

create table if not exists public.device_telemetry (
  device_id uuid primary key references public.devices(id) on delete cascade,
  reported_hashrate numeric(20, 6) not null default 0
    check (reported_hashrate >= 0 and reported_hashrate <= 1000000),
  hashes_computed bigint not null default 0
    check (hashes_computed >= 0),
  sample_seconds numeric(8, 3) not null default 2
    check (sample_seconds > 0 and sample_seconds <= 60),
  measured_at timestamptz not null,
  received_at timestamptz not null default now()
);

alter table public.device_telemetry enable row level security;

grant select on public.device_telemetry to authenticated;
grant all on public.device_telemetry to service_role;

create policy device_telemetry_read_own_or_admin
  on public.device_telemetry
  for select to authenticated
  using (
    private.is_mine_me_admin()
    or exists (
      select 1 from public.devices d
      where d.id = device_id and d.user_id = (select auth.uid())
    )
  );

create index if not exists device_telemetry_received_idx
  on public.device_telemetry (received_at desc);
