# MINE-ME

French-first, consent-first browser-compute platform.

## Current status
This repository starts with the secure application foundation. Production mining is intentionally disabled until a reviewed browser WASM miner, authenticated WSS pool gateway, pool-side accepted-share verification, and central-wallet payout reconciliation are implemented and tested.

## Stack
- Next.js App Router and TypeScript
- Supabase Auth, Postgres and Realtime
- Deployed under `/mineme`
- Browser compute only; no native installation or terminal setup for participants

## Development
1. Copy `.env.example` to `.env.local`.
2. Add the Supabase project URL and public anon key.
3. Use Node.js 20+, run `npm install`, then `npm run dev`.

## Hosting requirements
The target host must support a Next.js standalone Node.js process or a compatible reverse proxy. Static-only hosting cannot run application server routes or the persistent WSS pool gateway.

## Safety and accounting invariants
- Signup requires a valid referral code.
- Mining requires explicit, versioned participant consent.
- Participants control intensity, pause and stop.
- Browser compute runs only while the browser session is active; background tabs may be throttled or suspended.
- All mining proceeds belong to the platform. Participants have no revenue share or withdrawable balance.
- Pool-accepted shares and independently verified wallet receipts are authoritative.
- Never expose Supabase service-role credentials, pool credentials, or wallet private keys in browser code.
- Do not fabricate hashrate, shares, earnings, or payout metrics.
