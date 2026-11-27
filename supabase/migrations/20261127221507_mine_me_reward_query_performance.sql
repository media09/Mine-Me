-- Applied to the connected production project as version 20261127221507.
-- Index the pool payout wallet foreign key and consolidate the member reward
-- SELECT policies into one equivalent policy to remove duplicate permissive checks.

create index if not exists pool_payouts_central_wallet_id_idx
  on public.pool_payouts (central_wallet_id);

drop policy if exists member_reward_ledger_read_admin
  on public.member_reward_ledger;
drop policy if exists member_reward_ledger_read_own
  on public.member_reward_ledger;

create policy member_reward_ledger_read_member_or_admin
  on public.member_reward_ledger
  for select
  to authenticated
  using (
    member_id = (select auth.uid())
    or private.is_mine_me_admin()
  );
