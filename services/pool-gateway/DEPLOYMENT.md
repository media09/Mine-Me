# MINE-ME pool gateway deployment

This service is separate from the Next.js website and must run continuously on an always-on Linux host or container platform. It accepts authenticated MINE-ME browser and native-client WebSocket connections and forwards Stratum traffic only to the local HashVault proxy.

## Required services

- Next.js web app at `https://app.sharedboost.com/mineme`.
- Persistent Node.js 22+ pool gateway (this package).
- HashVault `vltrig-proxy` process, listening only on `127.0.0.1:3333`.
- TLS reverse proxy for the gateway (WSS).

Supabase Edge Functions are not the persistent WebSocket-to-Stratum service.

## Gateway environment

Copy `.env.example` to a protected server-only environment file. Set:
- `SUPABASE_URL` to the MINE-ME project URL.
- `SUPABASE_SERVICE_ROLE_KEY` to a server-only Supabase secret key. Never expose it to the browser or commit it.
- `MINING_GATEWAY_TOKEN_SECRET` to a high-entropy secret of at least 32 bytes. Use the exact same value in the Next.js server environment.
- `ALLOWED_WEB_ORIGINS=https://YOUR-MINE-ME-APP-ORIGIN` (exact browser origin; native clients authenticate with a short-lived signed session token and do not send an Origin header).
- `POOL_PROXY_HOST=127.0.0.1` and `POOL_PROXY_PORT=3333`.
- Set `TRUST_PROXY_HEADERS=true` only when the gateway is reachable exclusively through your own reverse proxy, and configure that proxy to overwrite `X-Real-IP`. Keep `MAX_ACTIVE_WORKERS`, `MAX_PENDING_AUTH_CONNECTIONS` and `MAX_CONNECTION_ATTEMPTS_PER_MINUTE` within the capacity of the gateway host.

Set the web application server environment:
- `MINING_GATEWAY_TOKEN_SECRET`: same secret as the gateway.
- `MINING_GATEWAY_PUBLIC_URL=wss://YOUR-GATEWAY-HOST/ws`.

Do not set these values as `NEXT_PUBLIC_*`. The token secret and service-role key must remain server-side.

## HashVault Stratum proxy

Use the official HashVault release for the chosen host OS/architecture. Verify the release checksum/signature and review the upstream GPL-3.0 terms before installation:

- https://github.com/HashVault/vltrig-proxy
- https://hashvault.pro/monero/

Create `/etc/vltrig-proxy/config.json` from `services/pool-proxy/config.example.json`, replacing only the central wallet placeholder with the platform's Monero payout wallet. Keep:
- proxy listener bound to `127.0.0.1:3333`;
- proxy HTTP management API disabled;
- NiceHash mode and worker tracking enabled;
- TLS enabled for the HashVault upstream;
- pool host `pool.hashvault.pro:443`;
- custom difficulty at zero.

Never expose port 3333 to the public internet. The browser must never connect directly to this TCP listener.

Run the proxy under a process supervisor. Ensure outbound TLS to the pool is permitted.

## Reverse proxy example

Terminate TLS at Nginx (or an equivalent reverse proxy) and forward WebSocket upgrades to the local gateway:

```nginx
server {
    listen 443 ssl http2;
    server_name YOUR-GATEWAY-HOST;

    # Configure real certificate and key paths for this host.
    ssl_certificate     /etc/letsencrypt/live/YOUR-GATEWAY-HOST/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/YOUR-GATEWAY-HOST/privkey.pem;

    location /ws {
        proxy_pass http://127.0.0.1:8081/ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
    }
}
```

Build the gateway container from the repository root so the workspace lockfile is available:

`docker build -f services/pool-gateway/Dockerfile -t mine-me-pool-gateway .`

The gateway health endpoint is `http://127.0.0.1:8081/healthz`; keep it private or expose it only through an authenticated monitoring network. Do not expose the local Stratum proxy or its admin interface.

## Pre-activation checklist

1. Confirm that the web host supports Next.js Node runtime and the `/mineme` base path.
2. Confirm the gateway host supports long-running Node processes, outbound TCP/TLS and WebSocket upgrades.
3. Confirm HashVault permits the intended browser-worker/proxy deployment and traffic volume.
4. Set the same high-entropy token secret in web and gateway environments.
5. Start the local proxy and verify it connects upstream over TLS.
6. Start the gateway and verify `/healthz`.
7. Confirm only the exact web origin can upgrade to `/ws`.
8. Run controlled tests with disposable browser, Android and desktop workers and confirm pool-side accepted and rejected share acknowledgements.
9. Confirm gateway revalidation disconnects a worker after account suspension, consent mismatch, admin pause, device pause or emergency stop.
10. Configure exactly one platform-owned HashVault Monero wallet address (public address only; never a seed/private key), verify every proxy worker submits through it, and reconcile a real central-wallet payout before public activation.
11. Confirm the gateway rejects duplicate/replayed tokens, duplicate device sessions, paused devices, suspended accounts, invalid consent versions and exhausted per-device nonce partitions.
12. Confirm reward allocations are posted only from pool-verified accepted-share contribution weights against confirmed payouts received by the one central wallet; member balances are internal ledger entries, not individual HashVault wallets.
13. Configure monitoring for pending-auth caps, per-IP connection throttles, proxy reconnects, pool rejection rates and DB cleanup failures.

Keep `mining_enabled=false` and `global_emergency_pause=true` until every item above is complete. A configured gateway URL is not proof that the proxy or upstream pool is healthy.


## One central HashVault wallet and member reward accounting

MINE-ME uses exactly one platform-owned Monero receiving address for every member and every device. The VLTRig Proxy configuration has a primary HashVault endpoint and a failover endpoint; both entries must use the same platform wallet address and the same central worker identity. Never substitute a member's personal address.

After the platform owner has supplied and verified the public Monero receiving address, configure the singleton record in the Supabase SQL editor:

```sql
insert into public.central_wallet_identity (id, wallet_address)
values (true, 'REPLACE_WITH_THE_PLATFORM_PUBLIC_MONERO_ADDRESS');
```

Only the public receiving address belongs in this record. Never store a mnemonic, seed, private spend key or private view key in Supabase, the gateway, the proxy configuration, or a client application.

For each confirmed HashVault payout received by this one wallet, the trusted reconciliation process records the payout in `public.pool_payouts`, including the actual contribution window associated with the pool's PPLNS accounting. It then calls `private.allocate_central_pool_reward_for_window` with the payout transaction reference and that verified window. The function aggregates pool-accepted share difficulty from `mining_share_ledger` by member and posts idempotent internal credits to `member_reward_ledger`.

Do not infer a PPLNS window from a device's hashrate, a client-reported share, or an arbitrary clock interval. If the pool cannot establish the correct contribution window or payout amount, keep the payout unreconciled and do not credit member balances. Member XMR balances are internal platform accounting entries; they are not separate HashVault wallets or automatic on-chain withdrawals.
