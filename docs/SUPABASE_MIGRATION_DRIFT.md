# Supabase migration history reconciliation

Production project: `mine-me` (`mqyqpflamkplhlphrngn`).

The connected production database already contains the following migration versions whose SQL files are not present in the original application branch:

- `20261123104458_first_signup_is_participant`
- `20261123110522_fix_device_browser_enrollment_insert_privilege`
- `20261123110530_fix_device_enrollment_event_insert_privilege`
- `20261127130844_mining_device_diagnostics`

These versions are recorded as applied in Supabase. Their exact original SQL has not yet been recovered from the repository, so this document deliberately does not invent replacement SQL or mark them as no-op migrations.

The central-wallet migration was present in GitHub under version `20261127103000`, while production records the same migration name as applied at `20261127132644`. The canonical file has been aligned to the production version `20261127132644`. Do not apply the old `20261127103000` version.

The reward query-performance migration `20261127221507_mine_me_reward_query_performance` has been applied to production and its exact SQL is now committed in this repository.

## Rules for future database work

1. Never reset production or blindly replay migrations to resolve this drift.
2. Before provisioning a fresh environment, recover the four missing migration SQL files from the original change history or reconstruct a complete baseline from the live schema and review it.
3. Keep the migration filenames and versions aligned with `supabase migration list`.
4. After every schema change, run Supabase security and performance advisors and verify the resulting policies, grants, constraints, and indexes.
