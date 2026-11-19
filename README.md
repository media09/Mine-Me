# MINE-ME

A French-first, consent-first browser-compute platform with referral-only registration and centralized platform-owned mining proceeds.

## Current state

The feature branch contains the Next.js member/admin application, Supabase security foundation, browser device enrollment, a RandomX WebAssembly Worker prototype, signed mining-session endpoint, and a WSS gateway that bridges browser shares to a local HashVault `vltrig-proxy`.

**Production mining remains disabled.** The database currently has `mining_enabled=false` and `global_emergency_pause=true`. The live gateway and proxy have not been deployed or tested against the actual HashVault pool; do not enable public mining yet.

## Stack

- Next.js App Router, TypeScript and React
- Supabase Auth, Postgres, RLS and Realtime
- RandomX WebAssembly in a dedicated browser Worker
- Separate Node.js WSS gateway and HashVault `vltrig-proxy`
- Application base path: `/mineme`

## Local web app

Use Node.js 22 or later:
1. Copy `.env.example` to `.env.local`.
2. Set the Supabase URL, publishable/anon key and app URL.
3. Leave the mining gateway secret and public URL unset until the gateway has been deployed securely.
4. Run `npm install`, `npm run dev`, `npm run typecheck`, `npm test` and `npm run test:gateway`.

## Deployment prerequisites

The web host must support the Next.js standalone Node.js runtime at `https://app.sharedboost.com/mineme`. A separate always-on host/container is required for the gateway and Stratum proxy, outbound TCP/TLS to HashVault, and a TLS reverse proxy that supports WebSocket upgrades.

See `services/pool-gateway/DEPLOYMENT.md` for the service topology and pre-activation checklist.

## Safety and accounting invariants

- Signup requires a one-time owner bootstrap token for the first administrator, then a valid referral code.
- Signup requires explicit, versioned consent to device compute and the centralized proceeds model.
- Participants control intensity, pause and stop; the platform can enforce a safety ceiling but cannot override consent.
- Browser compute runs only while the tab/session is active; browsers and mobile operating systems may throttle or suspend background tabs.
- All mining proceeds belong to the platform. Participants receive no revenue share and have no withdrawable balance.
- Pool-confirmed share acknowledgements and independently verified central-wallet receipts are authoritative.
- Browser-reported hashrate is stored as device diagnostic telemetry, labelled indicative in member/admin views. It can be falsified and is not evidence of accepted shares, pool revenue or participant earnings.
- Only proxy-confirmed share responses enter the verified share ledger. The pool gateway is currently designed for one replica until a shared replay/lease store is added.
- Pool host/port and wallet destination are server-side only. No client-selected upstream, open proxy, or exposed secrets.
- Never expose Supabase service-role credentials, gateway signing secrets, pool credentials, or wallet private keys in browser code.
- Do not fabricate hashrate, shares, earnings, or payouts.
