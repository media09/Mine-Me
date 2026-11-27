# Cloudflare Workers deployment

This branch deploys the MINE-ME Next.js application using the OpenNext Cloudflare adapter.

- Public application URL: `https://mine-me.671btweb.workers.dev/minime`
- Browser origin (without path): `https://mine-me.671btweb.workers.dev`
- Build: `npm run build:cloudflare`
- Deploy: `npx wrangler deploy`
- Runtime: Cloudflare Workers with `nodejs_compat`
- The pool gateway is a separate persistent Node.js service hosted at SharedBoost; it is not the public website.
- Browser WSS endpoint: `wss://app.sharedboost.com/mineme/ws`
- Supabase URL and publishable key are public client configuration only.

## Required Worker secrets

Configure these as Cloudflare Worker secrets (never as plain-text variables and never as `NEXT_PUBLIC_*`):

- `MINING_GATEWAY_TOKEN_SECRET`: same high-entropy value as the SharedBoost Gateway.
- `SUPABASE_SERVICE_ROLE_KEY`: server-only Supabase service-role/secret key required by the admin payout reconciliation route.

The Worker already has `MINING_GATEWAY_PUBLIC_URL` as a non-secret variable. Do not add a second URL or expose server secrets in the browser.

## Safety

Mining remains disabled and the global emergency pause remains enabled until the SharedBoost gateway, upstream pool authentication, accepted-share accounting, central wallet identity, and payout reconciliation have all been independently verified. A healthy Worker deployment or Gateway health endpoint alone is not proof that mining is safe to activate.
