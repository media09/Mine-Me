# MINE-ME

French-first, consent-first browser-compute platform.

## Current status
This repository contains the initial application, authentication, referral-consent and database foundation. Production mining is intentionally disabled until the audited browser miner, authenticated WSS pool gateway, pool-side share verification and central-wallet payout reconciliation are implemented and tested.

## Stack
- Next.js App Router and TypeScript
- Supabase Auth, Postgres and Realtime
- Deployed under `/mineme`
- Browser compute only; no native installation or terminal setup for participants

## Development
Use Node.js 22 or later. Copy `.env.example` to `.env.local`, set the Supabase public URL, publishable/anon key and app URL, then run `npm install`, `npm run dev`, and `npm run typecheck`.

## Hosting requirements
The host must support a Next.js standalone Node.js process or a compatible reverse proxy. Static-only hosting cannot run the application server routes or persistent WSS pool gateway.

## Safety and accounting invariants
- Signup requires the one-time bootstrap token for the first admin, then a valid referral code.
- Signup requires explicit, versioned consent to device compute and the centralized proceeds model.
- Participants control intensity, pause and stop.
- Browser compute runs only while the browser session is active; background tabs may be throttled or suspended.
- All mining proceeds belong to the platform. Participants have no revenue share or withdrawable balance.
- Pool-accepted shares and independently verified wallet receipts are authoritative.
- Never expose Supabase service-role/secret credentials, pool credentials, or wallet private keys in browser code.
- Do not fabricate hashrate, shares, earnings, or payout metrics.
