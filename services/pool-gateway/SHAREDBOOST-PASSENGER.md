# MINE-ME Gateway on SharedBoost (Passenger)

This is a deployment adapter for the existing cPanel Node.js application at
`/home/sharfys/mineme`. It does not replace the Cloudflare Next.js application.

## Architecture

Browser WSS `/mineme/ws` -> Passenger HTTP/WebSocket app -> private loopback
Gateway -> private loopback VLTRig Proxy -> HashVault TLS Stratum.

Passenger owns the public HTTP listener. The adapter starts the proxy and
Gateway as child processes, binds both only to loopback, and forwards the
`/mineme` subpath to the Gateway. The proxy management API remains disabled.

## Files to place in the existing cPanel application root

- Rename `passenger-app.cjs` to `app.js`.
- Rename `sharedboost-package.json` to `package.json`.
- Copy the complete `services/pool-gateway/` directory, including `lib/`.
- Copy `services/pool-proxy/config.example.json` to the same relative path.
- Place the official Linux x64 `vltrig-proxy` executable in `bin/vltrig-proxy`.

Do not replace the current app until the files and environment are ready.
Use cPanel Node.js Selector's **Run NPM Install** after placing package.json.

## Required cPanel environment variables

- `MINE_ME_GATEWAY_ENABLED=true` (leave unset/false until all checks are complete)
- `SUPABASE_URL=https://mqyqpflamkplhlphrngn.supabase.co`
- `SUPABASE_SERVICE_ROLE_KEY` (server-only; never put in a browser or GitHub file)
- `MINING_GATEWAY_TOKEN_SECRET` (at least 32 random bytes; keep it private)
- `ALLOWED_WEB_ORIGINS=https://app.sharedboost.com`
- `CENTRAL_MONERO_WALLET_ADDRESS` (platform public receiving address only)
- `VLTRIG_PROXY_PATH=bin/vltrig-proxy`

The adapter sets `GATEWAY_BIND_HOST=127.0.0.1`, `GATEWAY_WS_PATH=/ws`,
`POOL_PROXY_HOST=127.0.0.1`, `POOL_PROXY_PORT=3333`, and a private Gateway
port automatically. Do not expose port 3333 or the Gateway's private port.

## Safety

- Do not store a Monero seed, mnemonic, private spend key, or private view key.
- The public central wallet address is written to a private runtime proxy
  configuration under `tmp/mine-me-proxy/`, with restrictive file permissions.
- The app does not enable mining in Supabase. Keep
  `mining_enabled=false` and `global_emergency_pause=true` until end-to-end
  tests and payout reconciliation are complete.
- The adapter does not log proxy output because it may contain pool/account
  details.
- Verify the official binary release and SHA-256 before uploading it. Ensure
  the file has execute permission in cPanel File Manager.
- If SharedBoost terminates child processes or blocks execution, stop here;
  do not attempt to bypass hosting restrictions.

## Health check

After a controlled deployment, `GET /mineme/healthz` reports whether the
proxy and Gateway child processes started. A healthy response does not prove
HashVault login, accepted shares, or reward accounting. Those require separate
controlled tests while global mining remains disabled for members.
