#!/usr/bin/env bash
set -Eeuo pipefail

: "${SUPABASE_URL:?SUPABASE_URL is required}"
: "${SUPABASE_SERVICE_ROLE_KEY:?SUPABASE_SERVICE_ROLE_KEY is required}"
: "${MINING_GATEWAY_TOKEN_SECRET:?MINING_GATEWAY_TOKEN_SECRET is required}"
: "${CENTRAL_MONERO_WALLET_ADDRESS:?CENTRAL_MONERO_WALLET_ADDRESS is required}"
: "${ALLOWED_WEB_ORIGINS:?ALLOWED_WEB_ORIGINS is required}"

export GATEWAY_BIND_HOST="0.0.0.0"
export GATEWAY_PORT="${PORT:-10000}"
export POOL_PROXY_HOST="127.0.0.1"
export POOL_PROXY_PORT="3333"

node --input-type=module <<'NODE'
import fs from "node:fs";

const secret = process.env.MINING_GATEWAY_TOKEN_SECRET;
if (Buffer.byteLength(secret, "utf8") < 32) {
  throw new Error("MINING_GATEWAY_TOKEN_SECRET must contain at least 32 bytes.");
}
const wallet = process.env.CENTRAL_MONERO_WALLET_ADDRESS;
if (!/^[48][1-9A-HJ-NP-Za-km-z]{94,105}$/.test(wallet)) {
  throw new Error("CENTRAL_MONERO_WALLET_ADDRESS is not a valid Monero public address.");
}
const config = JSON.parse(fs.readFileSync("services/pool-proxy/config.example.json", "utf8"));
for (const pool of config.pools) pool.user = wallet;
fs.mkdirSync("/tmp/mine-me-proxy", { recursive: true, mode: 0o700 });
fs.writeFileSync("/tmp/mine-me-proxy/config.json", JSON.stringify(config), { mode: 0o600 });
NODE

vltrig-proxy --config=/tmp/mine-me-proxy/config.json &
PROXY_PID=$!
GATEWAY_PID=""

cleanup() {
  if [[ -n "${GATEWAY_PID}" ]]; then kill "${GATEWAY_PID}" 2>/dev/null || true; fi
  kill "${PROXY_PID}" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Wait for the proxy's loopback Stratum listener before accepting WSS sessions.
for attempt in $(seq 1 30); do
  if ! kill -0 "${PROXY_PID}" 2>/dev/null; then
    echo "vltrig-proxy exited before opening its local Stratum listener." >&2
    exit 1
  fi
  if node --input-type=module -e 'import net from "node:net"; const s=net.connect(3333,"127.0.0.1"); s.once("connect",()=>{s.end();process.exit(0)}); s.once("error",()=>process.exit(1)); setTimeout(()=>process.exit(1),700);' >/dev/null 2>&1; then
    break
  fi
  if [[ "${attempt}" == "30" ]]; then
    echo "vltrig-proxy did not open 127.0.0.1:3333 within 30 seconds." >&2
    exit 1
  fi
  sleep 1
done

npm run start --workspace=@mine-me/pool-gateway &
GATEWAY_PID=$!

set +e
wait -n "${PROXY_PID}" "${GATEWAY_PID}"
STATUS=$?
set -e
echo "A required MINE-ME mining process exited (status ${STATUS}); stopping the other process." >&2
exit "${STATUS}"
