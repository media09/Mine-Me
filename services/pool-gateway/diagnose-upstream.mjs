import { randomBytes } from "node:crypto";
import { createConnection } from "node:net";

const host = process.env.POOL_PROXY_HOST || "127.0.0.1";
const port = Number(process.env.POOL_PROXY_PORT || 3333);
const timeoutMs = 12_000;

if (host !== "127.0.0.1" && host !== "::1") {
  throw new Error("Diagnostic is restricted to a loopback proxy.");
}
if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error("POOL_PROXY_PORT is invalid.");
}

const workerCode = "MM-" + randomBytes(16).toString("hex").toUpperCase();
const socket = createConnection({ host, port });
let buffer = "";
let finished = false;

function finish(ok, reason) {
  if (finished) return;
  finished = true;
  clearTimeout(timer);
  if (ok) {
    process.stdout.write(JSON.stringify({
      ok: true,
      proxyLogin: "accepted",
      nicehashNonceSplitting: true,
      initialPoolJob: true,
      submittedShares: 0,
    }) + "\n");
  } else {
    process.stderr.write(JSON.stringify({ ok: false, reason }) + "\n");
    process.exitCode = 1;
  }
  socket.destroy();
}

const timer = setTimeout(() => finish(false, "UPSTREAM_LOGIN_TIMEOUT"), timeoutMs);
socket.setTimeout(timeoutMs);
socket.once("connect", () => {
  const login = {
    id: 1,
    jsonrpc: "2.0",
    method: "login",
    params: {
      login: workerCode,
      pass: "x",
      agent: "MINE-ME-DIAGNOSTIC/1.0",
      rigid: workerCode,
      algo: ["rx/0"],
    },
  };
  socket.write(JSON.stringify(login) + "\n");
});
socket.on("data", (chunk) => {
  buffer += chunk.toString("utf8");
  if (buffer.length > 256 * 1024) return finish(false, "UPSTREAM_RESPONSE_TOO_LARGE");
  let newline;
  while ((newline = buffer.indexOf("\n")) >= 0) {
    const line = buffer.slice(0, newline).trim();
    buffer = buffer.slice(newline + 1);
    if (!line) continue;
    let message;
    try {
      message = JSON.parse(line);
    } catch {
      return finish(false, "UPSTREAM_INVALID_JSON");
    }
    if (message.id !== 1) continue;
    const result = message.result;
    if (message.error || !result || result.status !== "OK") {
      return finish(false, "UPSTREAM_LOGIN_REJECTED");
    }
    if (!Array.isArray(result.extensions) || !result.extensions.includes("nicehash")) {
      return finish(false, "NICEHASH_NONCE_SPLITTING_NOT_NEGOTIATED");
    }
    if ((typeof result.id !== "string" && typeof result.id !== "number") ||
        !result.job || typeof result.job !== "object") {
      return finish(false, "INITIAL_POOL_JOB_MISSING");
    }
    return finish(true);
  }
});
socket.once("error", (error) => {
  const code = typeof error.code === "string" ? error.code : "PROXY_CONNECTION_FAILED";
  finish(false, code);
});
socket.once("timeout", () => finish(false, "UPSTREAM_LOGIN_TIMEOUT"));
socket.once("close", () => {
  if (!finished) finish(false, "PROXY_CLOSED_BEFORE_LOGIN");
});
