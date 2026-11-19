# MINE-ME implementation phases

## Phase 1 — Application foundation
- [x] Create isolated feature branch.
- [x] Add Next.js/TypeScript application skeleton.
- [x] Configure the `/mineme` base path.
- [x] Add dark French public landing page.
- [x] Define initial Supabase schema with RLS and a referral + consent signup trigger.
- [ ] Install dependencies and run typecheck/build in a Node.js environment.
- [ ] Review and apply database migration to the intended Supabase project.

## Phase 2 — Identity and referrals
- Signup only through a valid referral.
- Store explicit consent version and timestamp before account creation.
- Email verification, sign-in, password reset and session protection.
- Referral dashboard and abuse/rate-limit controls.

## Phase 3 — User devices
- Server-issued unique worker identifiers.
- Browser capability estimates and conservative defaults.
- Participant intensity controls, pause, stop and visible running state.
- Device history, heartbeat and activity events.
- No background-mining promises.

## Phase 4 — Pool gateway and verified mining
- Audit WASM miner source and license.
- Persistent WSS bridge to a fixed pool allowlist.
- Per-device authentication and quotas.
- Accepted/rejected share ingestion from pool-side evidence.
- No arbitrary target host/port, public open proxy or client-declared earnings.

## Phase 5 — Admin and accounting
- Server-enforced roles and privileged action audit logs.
- Users, referrals, devices, worker histories and safety controls.
- Global emergency pause that never overrides participant consent.
- Pool health, accepted shares, central-wallet receipt reconciliation.
- No participant wallet balance or payout capability.

## Phase 6 — Release
- Cross-browser/device tests.
- Security review and database policy review.
- Configure hosting for `https://app.sharedboost.com/mineme`.
- Production smoke tests and actual verified withdrawal to the platform's central wallet.
