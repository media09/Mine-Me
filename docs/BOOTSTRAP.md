# First administrator bootstrap

The signup trigger refuses all account creation unless the request contains the current consent version and either (a) a valid referral code from an existing profile, or (b) the one-time bootstrap code while the profiles table is empty.

After the database migration is reviewed and applied, use the Supabase SQL Editor as the project owner to create a one-time code:

```sql
insert into private.bootstrap_codes (token, expires_at)
values (
  upper(replace(gen_random_uuid()::text, '-', '')),
  now() + interval '24 hours'
)
returning token;
```

Copy the returned token directly into the initial administrator signup link:

`https://app.sharedboost.com/mineme/register?ref=THE_RETURNED_TOKEN`

The token is stored in the non-exposed `private` schema, expires after 24 hours, and is consumed in the same transaction that creates the first admin profile. The bootstrap code can only create the first profile; once a profile exists, all further registrations require a valid referral code issued by a participant.

Do not publish the bootstrap token. After the first admin account is created, it can distribute referral links through the application.

This is a one-time owner setup step, not a participant installation or command-line task.
