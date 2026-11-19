# Browser mining feasibility and pool selection (19 November 2026)

## Current recommendation

**Monero RandomX is the leading browser-mining test candidate, not a production-approved choice.** HashVault is the leading pool candidate for a small controlled proof of concept because it exposes public pool/network data and wallet/worker API endpoints. Do not connect public users until the service design, pool permission and accepted-share flow are tested.

## Browser hashing engine

Candidate library:
- `l1mey112/randomx.js` version 0.1.3, BSD-3-Clause.
- It provides RandomX hashing in WebAssembly and a JavaScript API (`randomx_init_cache`, `randomx_create_vm`, `calculate_hash`).
- Its upstream repository was archived on 4 February 2026, so pin the exact package/source, retain the BSD notice, run known-answer tests and review the implementation before release.
- The library documentation reports approximately 241 H/s for a 16-thread desktop browser test in its light/verification mode. This is one developer's benchmark, not a general device promise. Its documentation says the initialised full 2 GiB dataset is not supported and the light mode uses substantially less memory but is slower.
- The shared-memory version needs browser cross-origin isolation (COOP/COEP) and must be tested across Chrome, Firefox, Safari and Android browsers before it is relied on.

Sources:
- https://github.com/l1mey112/randomx.js
- https://github.com/l1mey112/randomx.js/blob/master/LICENSE
- https://github.com/tevador/RandomX

## Pool candidate: HashVault Monero

The HashVault public API currently reports:
- PPLNS pool fee: 0.9%.
- Minimum wallet payout: 0.001 XMR; default wallet payout: 0.11 XMR.
- Payout interval: hourly; block maturity depth: 30.
- Monero network difficulty: 806,959,129,605.
- Current block reward: 0.6198927 XMR.
- Reference XMR price in that response: $503.70.
- Pool collective hashrate in that response: 567,378,335 H/s.

The API values are dynamic. They must be fetched at runtime and timestamped, not hard-coded as current production metrics.

Official endpoints and policy:
- Public API base: https://api.hashvault.pro/v3/monero
- Pool page: https://hashvault.pro/monero/
- HashVault's policy says a Stratum proxy is strictly required for lots of workers, including workers sharing the same name; it identifies VLTRig Proxy or XMRig Proxy as examples and reserves the right to restrict abusive connections/hosting.

**Important:** The public pool page's displayed fee/payout wording can differ from its live API configuration. The API response observed on 19 November 2026 reported 0.9% PPLNS fee and 0.001 XMR minimum wallet payout. Re-fetch the API before choosing the final terms.

## Illustrative gross-revenue calculation

Using the API snapshot above, the expected daily payout before device costs is estimated by:

`daily XMR = hashrate (H/s) × 86,400 ÷ network difficulty × block reward`

`daily USD = daily XMR × XMR/USD price × (1 − pool fee)`

At a sustained **1,000 H/s**:
- about 0.00006577 XMR/day after the 0.9% pool fee;
- about $0.0331/day, or $0.99 per 30 days at the snapshot price;
- roughly 1,509 days to accrue $50 at unchanged conditions.

Illustrative scaling only, using that same snapshot:
- 250 H/s: about $0.25/month; approximately 16.4 years to $50.
- 1,000 H/s: about $0.99/month; approximately 4.1 years to $50.
- 15,000 H/s: about $14.91/month; approximately 100 days to $50.

These are mathematical estimates, not guaranteed payouts. Actual pool luck, difficulty, block rewards, XMR price, pool fees, rejected/stale shares, uptime and payout eligibility all change. Electricity, mobile data, cooling, battery wear, hardware wear, hosting, gateway costs and taxes are excluded. Only concurrently active browser tabs contribute; enrolled devices that are offline or background-suspended do not produce continuously.

**Commercial warning:** browser RandomX at low H/s is not an attractive income source at a small fleet scale. Measure actual H/s and electricity/device impact on the real fleet before recruiting a large community or promising any return. The $50 verified central-wallet withdrawal is a test milestone, not a promised date or earning.

## Required service architecture

1. Browser UI obtains a short-lived, device-scoped mining session from the authenticated application server.
2. A visible, consent-checked browser Worker runs the audited WASM algorithm. The worker only receives jobs from the configured gateway; it cannot choose a pool host, port, wallet, or payout target.
3. Browser communicates only over WSS to the MINE-ME gateway.
4. The gateway verifies the short-lived session, user/device state, current consent, global emergency pause, per-device intensity limit and rate limits.
5. The gateway forwards only to a fixed local Stratum proxy / approved upstream. Pool host, port, TLS and central wallet are server-side configuration, never client parameters.
6. Device IDs map to unique pool worker labels for internal attribution. The central wallet address is the sole pool payout destination.
7. Only server-observed pool-accepted/rejected share acknowledgements and pool API records are written to the verified share ledger. Browser telemetry is a separate diagnostic signal, not accounting evidence.
8. Central-wallet transaction receipts are reconciled separately from pool estimate/hashrate data.

## Critical deployment dependency

A persistent WSS-to-Stratum gateway and a Stratum proxy must run continuously and accept outbound TCP/TLS connections to the pool. Supabase Edge Functions are not a persistent WebSocket/Stratum process. The existing app host must explicitly support a long-running Node service, WebSocket upgrades, outbound TCP/TLS, and a persistent worker process—or a separate always-on service is required.

No miner should be enabled until the hosting plan and pool operator permit this traffic pattern. Do not use an unauthenticated generic WebSocket-to-TCP proxy or accept any client-supplied upstream hostname/port.
