# MINE-ME implementation phases

## Phase 1 — Application foundation
- [x] Create isolated feature branch.
- [x] Add Next.js/TypeScript application skeleton and `/mineme` base path.
- [x] Add French dark-mode landing, registration, login, terms, member and admin pages.
- [x] Add Supabase browser/server clients and Next.js 16 proxy session refresh.
- [x] Define RLS schema, referral + consent signup trigger and single-use first-admin bootstrap.
- [x] Apply and verify database migrations on the intended Supabase project.
- [x] Add CI, dependency audit, TypeScript checks, unit tests and production build.

## Phase 2 — Identity and referrals
- [x] Email-confirmation callback and sign-in.
- [x] Referral-only signup, attribution, personal referral link and copy control.
- [x] Account suspension and referral-code enable/disable controls with database audit.
- [ ] Add password reset, invitation expiry/revocation UI and abuse/rate-limit policy for signup.

## Phase 3 — User devices
- [x] Automatic browser enrollment after consented signup/login.
- [x] Server-issued unique worker identifiers and one stable installation ID per browser profile.
- [x] Browser capability estimate and participant intensity preference.
- [x] Participant pause, stop and re-enroll controls.
- [x] Browser Worker status, local hashrate diagnostics and proxy-confirmed share feedback.
- [x] No background-mining promises; browser tab/session remains the compute boundary.
- [ ] Add multi-thread scheduling after per-device thermal, memory and battery testing.

## Phase 4 — Pool gateway and verified mining
- [x] Audit and pin the RandomX WASM library; include its BSD-3-Clause license and known-answer test.
- [x] Add RandomX worker protocol tests for target comparison and fixed per-worker nonce-byte preservation.
- [x] Add short-lived HMAC-signed session tokens tied to user, consent, device and worker.
- [x] Add database-backed per-device gateway leases so reconnects and stale socket cleanup do not race.
- [x] Add persistent Node.js WSS gateway with exact-origin allowlist, pre-auth/per-IP rate limits and session authentication.
- [x] Add fixed loopback Stratum proxy target and HashVault proxy configuration template.
- [x] Add gateway tests for signed tokens, message framing, job validation and worker identity.
- [ ] Deploy gateway + HashVault proxy on an always-on host and verify TLS/upstream connectivity.
- [ ] Run live end-to-end pool tests and validate actual accepted/rejected shares from HashVault.
- [ ] Verify behaviour under gateway restarts, stale sessions, network loss and multiple tabs.

## Phase 5 — Admin and accounting
- [x] Server-enforced admin roles and audit logs for privileged actions.
- [x] Admin user, referral, device, share ledger, receipt and audit tables.
- [x] Member suspension, referral disablement and device block controls.
- [x] Global mining enablement gate, emergency pause and maximum intensity ceiling enforced in the database.
- [x] Central-wallet receipt schema; no participant wallet balance or payout capability.
- [x] Store and display bounded browser-reported per-device hashrate diagnostics, clearly separated from pool shares and earnings.
- [ ] Add live pool health and server-verified heartbeat/accepted-share telemetry in the admin console.
- [ ] Implement pool API reconciliation and central-wallet transaction verification.
- [ ] Prove share-to-worker attribution across proxy sessions without accepting browser-declared earnings.

## Phase 6 — Release
- [ ] Cross-browser and device tests on Windows, Android, Chrome, Firefox and Safari.
- [ ] Measure CPU load, memory, heat, battery impact, and sustained hashrate on the initial 16-device fleet.
- [ ] Confirm the app.sharedboost.com/mineme host supports the Next.js Node runtime and base path.
- [ ] Configure TLS, WebSocket upgrades, monitoring, security headers, backups and incident response.
- [ ] Keep mining disabled until the live pool and central wallet have been verified.
- [ ] Complete an actual central-wallet withdrawal test before public activation.
