# First administrator bootstrap

The signup trigger refuses account creation unless the request carries the current consent version and either (a) a valid referral code belonging to an existing profile, or (b) the one-time bootstrap token while the profiles table is empty.

After the migration is reviewed and applied, use the Supabase SQL Editor as the project owner to create a one-time token:

```sql
insert into private.bootstrap_codes (token, expires_at)
values (
  upper(replace(gen_random_uuid()::text, '-', '')),
  now() + interval '24 hours'
)
returning token;
```

Copy the returned token into the first administrator signup URL:

`https://app.sharedboost.com/mineme/register?ref=THE_RETURNED_TOKEN`

The token is held in the non-exposed `private` schema, expires after 24 hours and is consumed in the same transaction that creates the first admin profile. A transaction-level advisory lock ensures that only one concurrent first signup can become the initial administrator.

The initial administrator must also check the consent box and verify their email if email confirmation is enabled. Once the first profile exists, all further registrations require a normal referral code.

Do not publish the bootstrap token. After setup, the initial admin can distribute referral links from the member dashboard.

This is a one-time owner setup step, not a participant installation or command-line task.
