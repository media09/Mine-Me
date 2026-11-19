# Supabase setup

Project reference: `mqyqpflamkplhlphrngn` (region `eu-west-1`).

## Before applying the migration
1. Confirm this is the intended MINE-ME project.
2. Review `supabase/migrations/202611190001_mine_me_foundation.sql`.
3. Confirm the Data API exposes the `public` schema. New public tables require explicit grants as of the October 30, 2026 rollout; this migration grants only the intended privileges.
4. Confirm the application origin and redirect URL below.

## Authentication URL configuration
Configure the Supabase Auth Site URL as:

`https://app.sharedboost.com/mineme`

Add the exact allowed redirect URL:

`https://app.sharedboost.com/mineme/auth/callback`

For local development, also allow the local callback URL used by the developer environment.

## Public browser environment
- `NEXT_PUBLIC_SUPABASE_URL`: project URL
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`: publishable key (or legacy anon key while migrating)

Never put a Supabase secret/service-role key into any `NEXT_PUBLIC_*` environment variable or browser bundle.

## Apply and verify
Apply the migration only after reviewing it. Then verify:
- The expected tables and policies exist.
- The `private` schema is not in the Data API exposed schema list.
- The first-admin bootstrap table is not reachable through the public API.
- An invalid referral cannot create an account.
- A signup without consent cannot create an account.
- A valid first-admin bootstrap token is consumed exactly once.
- A regular referral signup is attributed to the correct inviter.
- Users can select only their own profile, referrals, devices, device events and verified shares.
- The central wallet receipts, platform settings and audit logs are not readable by normal participants.
- Run Supabase Security and Performance Advisors after applying the migration.

The Auth trigger executes in the same transaction as account creation. Any trigger error rejects signup, so test the positive and negative cases before opening registration publicly.
