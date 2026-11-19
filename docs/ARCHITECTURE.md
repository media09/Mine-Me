# MINE-ME architecture

## Application services
1. Next.js application hosted under `/mineme`.
2. Supabase Auth and Postgres for accounts, consent records, referrals, device inventory, activity and audit records.
3. A persistent authenticated WSS pool gateway on an always-on service. Supabase Edge Functions are not a persistent Stratum bridge. The current implementation uses one gateway replica because active-device leases and replay IDs are in-memory; horizontal scaling requires a shared lease/replay store first.
4. Browser WebAssembly miner running in Web Workers, activated only after explicit participant consent.
5. Pool adapter with a fixed upstream allowlist, per-device credentials, quotas, rate limits and restricted egress.
6. Reconciliation service importing pool-accepted shares and central-wallet payout receipts.

## Non-negotiable invariants
- Referral code is validated inside the database signup trigger.
- Signup records the exact consent version and timestamp; no consent, no account creation.
- Participant controls intensity, pause and stop. Admin safety ceilings can limit intensity, never override consent.
- Browser compute only works while the browser session is active; background tabs can be throttled or suspended.
- No participant revenue share or withdrawable account balance. All proceeds belong to the platform.
- Pool-accepted shares and verified wallet receipts are authoritative; browser telemetry is not proof of earnings.
- No arbitrary client-selected pool host/port. Gateway connects only to a loopback Stratum proxy; that proxy is configured server-side for the approved HashVault Monero pool.
- HashVault NiceHash mode assigns a fixed nonce byte to each downstream worker. A browser worker increments only its 24-bit range and pauses when that range is exhausted; it never wraps into duplicate nonces.
- Never expose service-role keys, pool credentials or wallet private keys in frontend bundles.

## Release gates
- Implement and test signup, email verification and referral lifecycle.
- Implement server-side admin RBAC and audit every privileged operation.
- Select and audit a browser-compatible WASM miner and its license.
- Build and security-test the WSS-to-Stratum gateway.
- Verify pool accepted shares from the provider API.
- Reconcile an actual central-wallet payout.
- Test Chrome, Firefox and Android behavior, including tab suspension and pause/stop controls.
- Configure TLS, security headers, rate limiting, monitoring, backups and incident response.
