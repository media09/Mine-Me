# HashVault vltrig-proxy dependency

MINE-ME does not vendor, modify or redistribute the HashVault `vltrig-proxy` binary. It runs as a separate server-side process in the same host/network namespace as the MINE-ME WSS gateway.

- Source and releases: https://github.com/HashVault/vltrig-proxy
- License: GNU GPL version 3. Review the upstream license before use or distribution.
- Pool page: https://hashvault.pro/monero/
- Pool API: https://api.hashvault.pro/v3/monero

The `config.example.json` follows the XMRig/HashVault proxy config format:
- `pool.hashvault.pro:443` with TLS and SNI;
- the platform's central Monero wallet as the only payout destination;
- `rx/0` (Monero RandomX);
- NiceHash mode and downstream worker tracking;
- custom difficulty disabled;
- proxy HTTP management UI disabled;
- downstream Stratum listener bound to `127.0.0.1:3333` only.

NiceHash mode assigns a fixed nonce byte to every downstream worker. MINE-ME preserves this byte and increments only the lower 24-bit nonce counter in the browser Worker. The WSS gateway forwards a worker's candidate share to this local proxy, and records the result only after the proxy returns the share response.

Use an official release for the server's OS/architecture and verify its release checksum/signature against upstream metadata. Do not expose TCP port 3333 publicly or enable the proxy HTTP admin UI on a public interface. The gateway itself should only reach this proxy over loopback.

This dependency runs on the MINE-ME server. Participants do not install anything on their computers or phones.
