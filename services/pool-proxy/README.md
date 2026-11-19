# HashVault vltrig-proxy dependency

MINE-ME does not vendor, modify or redistribute the HashVault `vltrig-proxy` binary. It is a separate server-side dependency installed on the same machine as the MINE-ME WSS gateway.

- Upstream source and prebuilt releases: https://github.com/HashVault/vltrig-proxy
- License: GNU GPL version 3 (review the upstream LICENSE before use/distribution).
- Pool-specific documentation: https://hashvault.pro/monero/
- Pool API: https://api.hashvault.pro/v3/monero

The template in `config.example.json` is configured for HashVault Monero using TLS, NiceHash nonce splitting, worker tracking, no custom difficulty, no proxy HTTP UI, and a loopback-only TCP listener on 127.0.0.1:3333. It intentionally contains no wallet address.

NiceHash mode assigns a fixed nonce byte per downstream worker. MINE-ME's WASM worker must preserve that byte and increment only the lower 24 bits; this behavior is covered by tests. The proxy itself performs the upstream nonce/connection aggregation.

Use the official prebuilt release for the server's operating system/architecture and verify its release checksum/signature against the upstream release metadata. Do not expose TCP port 3333 publicly. Do not enable the proxy HTTP admin UI on a public interface.

This dependency is not installed on the participant's computer or phone. It runs only on the MINE-ME server.
