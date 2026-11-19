# MINE-ME implementation phases

## Phase 1 — Application foundation
- [x] Create isolated feature branch.
- [x] Add Next.js/TypeScript application skeleton and `/mineme` base path.
- [x] Add French dark-mode landing, registration, login, terms, member and admin entry pages.
- [x] Add Supabase browser/server clients and session-refresh middleware.
- [x] Define initial RLS schema and server-only signup trigger enforcing referral + consent.
- [x] Define single-use first-admin bootstrap procedure.
- [ ] Install dependencies, generate lockfile, run typecheck and production build.
- [ ] Review and apply database migration to the intended Supabase project.

## Phase 2 — Identity and referrals
- Email verification, sign-in, password reset and session protection.
- Referral link creation, attribution, dashboard and abuse/rate-limit controls.
- Server-side invitation revocation and referral reporting.

## Phase 3 — User devices
- Server-issued unique worker identifiers.
- Browser capability estimate and conservative defaults.
- Participant intensity controls, pause, stop and visible running state.
- Device history, heartbeat and activity events.
- No background-mining promises.

## Phase 4 — Pool gateway and verified mining
- Audit browser-compatible WASM miner source and license.
- Persistent WSS bridge to a fixed pool allowlist.
- Per-device authentication, quotas and rate limits.
- Accepted/rejected share ingestion from pool-side evidence.
- No arbitrary target host/port, public open proxy or client-declared earnings.

## Phase 5 — Admin and accounting
- Server-enforced roles and audit logs for privileged actions.
- Users, referrals, devices, worker histories and safety controls.
- Global emergency pause that never overrides participant consent.
- Pool health, accepted shares and central-wallet receipt reconciliation.
- No participant wallet balance or payout capability.

## Phase 6 — Release
- Cross-browser/device tests and security review.
- Configure hosting for `https://app.sharedboost.com/mineme`.
- Production smoke tests and actual verified withdrawal to the platform's central wallet.
