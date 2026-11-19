import { createServer } from "node:http";
import { createConnection, isIP } from "node:net";
import { randomUUID } from "node:crypto";
import { createClient } from "@supabase/supabase-js";
import { WebSocket, WebSocketServer } from "ws";
import {
  buildProxyLogin,
  normalisePoolJob,
  normaliseProxyLine,
  verifySessionToken,
  validateShareMessage,
} from "./lib/protocol.mjs";

const env = process.env;
const config = {
  bindHost: env.GATEWAY_BIND_HOST || "127.0.0.1",
  port: Number(env.GATEWAY_PORT || 8081),
  wsPath: env.GATEWAY_WS_PATH || "/ws",
  allowedOrigins: (env.ALLOWED_WEB_ORIGINS || "").split(",").map((v) => v.trim()).filter(Boolean),
  proxyHost: env.POOL_PROXY_HOST || "127.0.0.1",
  proxyPort: Number(env.POOL_PROXY_PORT || 3333),
  maxWorkers: Math.min(1000, Math.max(1, Number(env.MAX_ACTIVE_WORKERS || 1000))),
  maxPendingAuthConnections: Math.min(200, Math.max(10, Number(env.MAX_PENDING_AUTH_CONNECTIONS || 100))),
  maxConnectionAttemptsPerMinute: Math.min(300, Math.max(10, Number(env.MAX_CONNECTION_ATTEMPTS_PER_MINUTE || 60))),
  trustProxyHeaders: env.TRUST_PROXY_HEADERS === "true",
  authTimeoutMs: 7000,
  revalidateMs: 5000,
  keepAliveMs: 20000,
  maxMessageBytes: 16 * 1024,
  maxPendingShares: 12,
  maxMessagesPerSecond: 12,
};

const required = ["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY", "MINING_GATEWAY_TOKEN_SECRET"];
for (const key of required) {
  if (!env[key]) throw new Error(`Missing required environment variable: ${key}`);
}
if (Buffer.byteLength(env.MINING_GATEWAY_TOKEN_SECRET) < 32) {
  throw new Error("MINING_GATEWAY_TOKEN_SECRET must contain at least 32 bytes.");
}
if (!config.allowedOrigins.length) {
  throw new Error("ALLOWED_WEB_ORIGINS must contain the exact MINE-ME app origin.");
}
if (config.proxyHost !== "127.0.0.1" && config.proxyHost !== "::1") {
  throw new Error("POOL_PROXY_HOST must be a loopback address; the Stratum proxy must not be exposed.");
}
if (!Number.isInteger(config.maxWorkers) || !Number.isInteger(config.maxPendingAuthConnections) ||
    !Number.isInteger(config.maxConnectionAttemptsPerMinute)) {
  throw new Error("Worker and connection rate limits must be valid integers.");
}
if (!Number.isInteger(config.port) || config.port < 1 || config.port > 65535) {
  throw new Error("GATEWAY_PORT is invalid.");
}
if (!Number.isInteger(config.proxyPort) || config.proxyPort < 1 || config.proxyPort > 65535) {
  throw new Error("POOL_PROXY_PORT is invalid.");
}

const supabase = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
});

const activeDevices = new Map();
const usedTokenIds = new Map();
const connectionAttempts = new Map();
const sessions = new Set();

function log(event, fields = {}) {
  // Never log session tokens, e-mail addresses, wallet addresses or secrets.
  process.stdout.write(JSON.stringify({ at: new Date().toISOString(), event, ...fields }) + "\n");
}

function send(ws, message) {
  if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(message));
}

function safeClose(ws, code, reason) {
  if (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING) {
    try { ws.close(code, String(reason).slice(0, 120)); } catch { ws.terminate(); }
  }
}

function readScalar(value) {
  if (typeof value === "boolean") return value;
  if (typeof value === "string") return value;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  return null;
}

async function readPlatformState(claims) {
  const [profileResult, deviceResult, settingsResult] = await Promise.all([
    supabase.from("profiles")
      .select("id, role, account_status, consent_version, consented_at")
      .eq("id", claims.sub)
      .maybeSingle(),
    supabase.from("devices")
      .select("id, user_id, worker_code, status, intensity_percent, last_seen_at")
      .eq("id", claims.deviceId)
      .eq("user_id", claims.sub)
      .maybeSingle(),
    supabase.from("platform_settings")
      .select("key, value")
      .in("key", ["mining_enabled", "global_emergency_pause", "global_max_intensity_percent"]),
  ]);

  if (profileResult.error || deviceResult.error || settingsResult.error) {
    throw new Error("Unable to verify current member/device state.");
  }

  const profile = profileResult.data;
  const device = deviceResult.data;
  if (!profile || !device) throw new Error("Member or device not found.");
  if (profile.account_status !== "active") throw new Error("Member account is not active.");
  if (profile.consent_version !== claims.consentVersion || !profile.consented_at) {
    throw new Error("Current computing consent is missing.");
  }
  if (device.worker_code !== claims.workerCode) throw new Error("Worker identity mismatch.");

  const settings = new Map((settingsResult.data || []).map((row) => [row.key, readScalar(row.value)]));
  const miningEnabled = settings.get("mining_enabled") === true;
  const emergencyPause = settings.get("global_emergency_pause") !== false;
  const maxIntensity = Math.min(80, Math.max(1, Number(settings.get("global_max_intensity_percent") ?? 80)));

  if (!miningEnabled) throw new Error("Browser mining is globally disabled.");
  if (emergencyPause) throw new Error("The global emergency pause is enabled.");
  if (claims.intensityPercent > maxIntensity || device.intensity_percent < claims.intensityPercent) {
    throw new Error("Device intensity has changed; obtain a new mining session.");
  }

  return { profile, device, maxIntensity };
}

async function markDeviceRunning(claims) {
  const { data, error } = await supabase
    .from("devices")
    .update({ status: "running", last_seen_at: new Date().toISOString() })
    .eq("id", claims.deviceId)
    .eq("user_id", claims.sub)
    .eq("status", "enrolled")
    .select("id, status, intensity_percent")
    .maybeSingle();

  if (error || !data || data.status !== "running") {
    throw new Error("The device could not enter the running state.");
  }
  return data;
}

async function markDeviceOffline(claims) {
  if (!claims?.deviceId || !claims?.sub) return;
  try {
    await supabase.from("devices")
      .update({ status: "offline", last_seen_at: new Date().toISOString() })
      .eq("id", claims.deviceId)
      .eq("user_id", claims.sub)
      .eq("status", "running");
  } catch {
    // Preserve paused/stopped/blocked state. A cleanup failure is logged, not hidden.
    log("device_offline_cleanup_failed", { deviceId: claims.deviceId });
  }
}

async function recordShare(session, pending, accepted, reason) {
  const poolShareRef = `hashvault:${session.claims.deviceId}:${pending.jobId}:${pending.nonce.toLowerCase()}`;
  const { error } = await supabase.from("mining_share_ledger").insert({
    device_id: session.claims.deviceId,
    pool_share_id: poolShareRef,
    accepted,
    difficulty: null,
    verified_at: new Date().toISOString(),
  });

  if (error && error.code !== "23505") {
    log("share_ledger_write_failed", { deviceId: session.claims.deviceId, code: error.code });
  }

  send(session.ws, {
    type: "share-result",
    shareRef: poolShareRef,
    accepted,
    reason: accepted ? null : String(reason || "Pool rejected the share").slice(0, 120),
  });
}

function parseProxyJob(session, rawJob) {
  const job = normalisePoolJob(rawJob);
  const nonceOffset = 39;
  const fixedNonceByte = job.blob.slice((nonceOffset + 3) * 2, (nonceOffset + 4) * 2).toLowerCase();
  if (!/^[0-9a-f]{2}$/.test(fixedNonceByte)) throw new Error("The pool proxy did not assign a worker nonce byte.");
  session.currentJobId = job.jobId;
  session.fixedNonceByte = fixedNonceByte;
  session.submittedNonces.clear();
  return job;
}

function cleanupSession(session, reason = "closed") {
  if (session.closed) return;
  session.closed = true;
  sessions.delete(session);
  if (session.claims?.deviceId) activeDevices.delete(session.claims.deviceId);
  if (session.authTimer) clearTimeout(session.authTimer);
  if (session.keepAliveTimer) clearInterval(session.keepAliveTimer);
  if (session.revalidateTimer) clearInterval(session.revalidateTimer);
  if (session.proxySocket && !session.proxySocket.destroyed) {
    try { session.proxySocket.end(); } catch { session.proxySocket.destroy(); }
  }
  if (session.ws.readyState === WebSocket.OPEN) safeClose(session.ws, 1000, reason);
  if (session.claims) {
    void markDeviceOffline(session.claims).then(() => {
      log("worker_disconnected", { deviceId: session.claims.deviceId, reason });
    });
  } else {
    log("unauthenticated_socket_closed", { reason });
  }
}

async function revalidateSession(session) {
  if (session.closed) return;
  try {
    const state = await readPlatformState(session.claims);
    if (state.device.status !== "running") throw new Error("Device is no longer in running state.");
    await supabase.from("devices")
      .update({ last_seen_at: new Date().toISOString() })
      .eq("id", session.claims.deviceId)
      .eq("status", "running");
  } catch (error) {
    cleanupSession(session, "authorization changed");
    log("worker_session_revoked", {
      deviceId: session.claims.deviceId,
      reason: error instanceof Error ? error.message : "state check failed",
    });
  }
}

function processProxyMessage(session, message) {
  if (session.closed) return;

  if (message.id === 1 && !session.proxyAuthenticated) {
    if (message.error || !message.result || message.result.status !== "OK") {
      throw new Error("The pool proxy rejected the downstream login.");
    }
    if (!Array.isArray(message.result.extensions) || !message.result.extensions.includes("nicehash")) {
      throw new Error("The pool proxy did not negotiate per-worker nonce splitting.");
    }
    if (typeof message.result.id !== "string" && typeof message.result.id !== "number") {
      throw new Error("The pool proxy returned an invalid miner session identifier.");
    }

    session.proxyAuthenticated = true;
    session.proxyMinerId = message.result.id;
    const job = parseProxyJob(session, message.result.job);
    void markDeviceRunning(session.claims).then(() => {
      if (session.closed) return;
      send(session.ws, {
        type: "ready",
        workerCode: session.claims.workerCode,
        pool: "HashVault Monero",
      });
      send(session.ws, { type: "job", job });
      session.keepAliveTimer = setInterval(() => {
        if (!session.proxySocket?.destroyed && session.proxyAuthenticated) {
          const keepAlive = {
            id: session.nextProxyRequestId++,
            jsonrpc: "2.0",
            method: "keepalived",
            params: { id: session.proxyMinerId },
          };
          session.proxySocket.write(JSON.stringify(keepAlive) + "\n");
        }
      }, config.keepAliveMs);
      session.revalidateTimer = setInterval(() => void revalidateSession(session), config.revalidateMs);
      log("worker_connected", { deviceId: session.claims.deviceId, workerCode: session.claims.workerCode });
    }).catch((error) => {
      send(session.ws, { type: "error", message: "Impossible d’activer cet appareil. Vérifiez son autorisation et les paramètres globaux." });
      cleanupSession(session, "device state refused");
    });
    return;
  }

  if (message.method === "job" && message.params) {
    const job = parseProxyJob(session, message.params);
    send(session.ws, { type: "job", job });
    return;
  }

  if (message.id !== undefined && session.pendingShares.has(Number(message.id))) {
    const pending = session.pendingShares.get(Number(message.id));
    session.pendingShares.delete(Number(message.id));
    const accepted = !message.error && message.result?.status === "OK";
    void recordShare(session, pending, accepted, message.error?.message || message.error);
    return;
  }

  if (message.method === "client.reconnect") {
    send(session.ws, { type: "error", message: "Le service de minage demande une reconnexion. Veuillez patienter puis actualiser la page." });
    cleanupSession(session, "proxy requested reconnect");
  }
}

function attachProxySocket(session, proxySocket) {
  session.proxySocket = proxySocket;
  proxySocket.setNoDelay(true);
  proxySocket.setKeepAlive(true, 20000);

  let buffer = "";
  proxySocket.on("data", (chunk) => {
    buffer += chunk.toString("utf8");
    if (buffer.length > 256 * 1024) {
      cleanupSession(session, "proxy response buffer limit");
      return;
    }
    let newline;
    while ((newline = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, newline).trim();
      buffer = buffer.slice(newline + 1);
      if (!line) continue;
      try {
        const parsed = normaliseProxyLine(line);
        processProxyMessage(session, parsed);
      } catch (error) {
        log("invalid_proxy_response", {
          deviceId: session.claims.deviceId,
          reason: error instanceof Error ? error.message : "invalid response",
        });
        cleanupSession(session, "invalid proxy response");
        return;
      }
    }
  });

  proxySocket.on("error", (error) => {
    log("proxy_socket_error", { deviceId: session.claims.deviceId, code: error.code || "ERR_PROXY" });
    send(session.ws, { type: "error", message: "La connexion au pool est momentanément indisponible." });
    cleanupSession(session, "proxy socket error");
  });

  proxySocket.on("close", () => cleanupSession(session, "proxy closed"));
}

function connectToLocalProxy(session) {
  return new Promise((resolve, reject) => {
    const socket = createConnection({ host: config.proxyHost, port: config.proxyPort });
    const timeout = setTimeout(() => {
      socket.destroy(new Error("Local Stratum proxy connection timed out."));
    }, 7000);

    socket.once("connect", () => {
      clearTimeout(timeout);
      attachProxySocket(session, socket);
      const login = buildProxyLogin(session.claims.workerCode);
      socket.write(JSON.stringify(login) + "\n");
      resolve();
    });
    socket.once("error", (error) => {
      clearTimeout(timeout);
      reject(error);
    });
  });
}

function resolveClientIp(request) {
  if (config.trustProxyHeaders) {
    const forwardedIp = request.headers["x-real-ip"];
    if (typeof forwardedIp === "string" && isIP(forwardedIp) !== 0) return forwardedIp;
  }
  return request.socket.remoteAddress || "unknown";
}

function allowConnectionAttempt(ip) {
  const now = Date.now();
  let bucket = connectionAttempts.get(ip);
  if (!bucket || now - bucket.windowStart >= 60_000) {
    bucket = { windowStart: now, count: 0 };
    connectionAttempts.set(ip, bucket);
  }
  bucket.count += 1;
  if (connectionAttempts.size > 10_000) {
    for (const [key, value] of connectionAttempts) {
      if (now - value.windowStart >= 60_000) connectionAttempts.delete(key);
    }
  }
  return bucket.count <= config.maxConnectionAttemptsPerMinute;
}

function consumeMessageRate(session) {
  const now = Date.now();
  if (now - session.rateWindowStart >= 1000) {
    session.rateWindowStart = now;
    session.messageCount = 0;
  }
  session.messageCount += 1;
  return session.messageCount <= config.maxMessagesPerSecond;
}

async function authenticateBrowserSession(session, rawMessage) {
  if (session.authenticated) throw new Error("A session is already authenticated.");
  if (!rawMessage || rawMessage.type !== "auth" || typeof rawMessage.token !== "string") {
    throw new Error("The first WebSocket message must contain a session token.");
  }

  const claims = verifySessionToken(rawMessage.token, env.MINING_GATEWAY_TOKEN_SECRET);
  const now = Math.floor(Date.now() / 1000);
  for (const [jti, expiresAt] of usedTokenIds) if (expiresAt <= now) usedTokenIds.delete(jti);
  if (usedTokenIds.has(claims.jti)) throw new Error("This mining session token has already been used.");
  if (activeDevices.has(claims.deviceId)) throw new Error("This device already has an active mining connection.");
  if (sessions.size >= config.maxWorkers) throw new Error("The mining service has reached its current worker limit.");

  const state = await readPlatformState(claims);
  if (state.device.status !== "enrolled") {
    throw new Error("Device must be enrolled and not paused or stopped.");
  }
  usedTokenIds.set(claims.jti, claims.exp);
  activeDevices.set(claims.deviceId, session);
  session.claims = claims;
  session.authenticated = true;
  clearTimeout(session.authTimer);
  session.nextProxyRequestId = 100;
  session.pendingShares = new Map();
  session.currentJobId = null;
  session.fixedNonceByte = null;
  session.submittedNonces = new Set();
  session.proxyAuthenticated = false;

  await connectToLocalProxy(session);
}

async function handleBrowserMessage(session, rawData) {
  if (session.closed) return;
  if (rawData.length > config.maxMessageBytes) {
    cleanupSession(session, "browser message too large");
    return;
  }
  if (!consumeMessageRate(session)) {
    cleanupSession(session, "browser message rate exceeded");
    return;
  }

  let message;
  try {
    message = JSON.parse(rawData.toString("utf8"));
  } catch {
    cleanupSession(session, "invalid browser message");
    return;
  }

  if (!session.authenticated) {
    try {
      await authenticateBrowserSession(session, message);
    } catch (error) {
      log("worker_auth_failed", { reason: error instanceof Error ? error.message : "authentication failed" });
      send(session.ws, { type: "error", message: "Cette session de calcul n’est plus valide. Actualisez votre espace MINE-ME." });
      safeClose(session.ws, 4001, "unauthorized");
    }
    return;
  }

  if (message.type === "heartbeat") {
    send(session.ws, { type: "heartbeat-ack", at: new Date().toISOString() });
    return;
  }

  if (!validateShareMessage(message, session.currentJobId)) {
    cleanupSession(session, "invalid or stale share submission");
    return;
  }

  if (message.nonce.slice(6, 8).toLowerCase() !== session.fixedNonceByte) {
    cleanupSession(session, "worker nonce partition mismatch");
    return;
  }

  const nonceKey = `${message.jobId}:${message.nonce.toLowerCase()}`;
  if (session.submittedNonces.has(nonceKey)) {
    cleanupSession(session, "duplicate nonce submitted by browser");
    return;
  }
  if (session.pendingShares.size >= config.maxPendingShares) {
    cleanupSession(session, "too many unconfirmed shares");
    return;
  }

  const requestId = session.nextProxyRequestId++;
  session.submittedNonces.add(nonceKey);
  session.pendingShares.set(requestId, {
    jobId: message.jobId,
    nonce: message.nonce.toLowerCase(),
  });

  const submit = {
    id: requestId,
    jsonrpc: "2.0",
    method: "submit",
    params: {
      id: session.proxyMinerId,
      job_id: message.jobId,
      nonce: message.nonce.toLowerCase(),
      result: message.result.toLowerCase(),
      algo: "rx/0",
    },
  };

  try {
    session.proxySocket.write(JSON.stringify(submit) + "\n");
  } catch {
    session.pendingShares.delete(requestId);
    cleanupSession(session, "share submission failed");
  }
}

const server = createServer((request, response) => {
  if (request.method === "GET" && request.url === "/healthz") {
    response.writeHead(200, { "content-type": "application/json", "cache-control": "no-store" });
    response.end(JSON.stringify({ ok: true, service: "mine-me-pool-gateway" }));
    return;
  }
  response.writeHead(404, { "content-type": "application/json" });
  response.end(JSON.stringify({ error: "not_found" }));
});

const wss = new WebSocketServer({
  noServer: true,
  maxPayload: config.maxMessageBytes,
  perMessageDeflate: false,
});

server.on("upgrade", (request, socket, head) => {
  const origin = request.headers.origin;
  const pathname = new URL(request.url || "/", "http://localhost").pathname;
  const clientIp = resolveClientIp(request);
  let pendingAuthCount = 0;
  for (const session of sessions) {
    if (!session.authenticated) pendingAuthCount += 1;
  }

  if (pathname !== config.wsPath || !origin || !config.allowedOrigins.includes(origin)) {
    socket.write("HTTP/1.1 403 Forbidden\\r\\nConnection: close\\r\\n\\r\\n");
    socket.destroy();
    return;
  }
  if (
    pendingAuthCount >= config.maxPendingAuthConnections ||
    !allowConnectionAttempt(clientIp)
  ) {
    socket.write("HTTP/1.1 429 Too Many Requests\\r\\nRetry-After: 60\\r\\nConnection: close\\r\\n\\r\\n");
    socket.destroy();
    log("websocket_connection_limited", { clientIp, pendingAuthCount });
    return;
  }

  wss.handleUpgrade(request, socket, head, (ws) => wss.emit("connection", ws, request));
});
wss.on("connection", (ws) => {
  const session = {
    ws,
    claims: null,
    authenticated: false,
    closed: false,
    rateWindowStart: Date.now(),
    messageCount: 0,
    authTimer: null,
    keepAliveTimer: null,
    revalidateTimer: null,
    proxySocket: null,
    pendingShares: new Map(),
    submittedNonces: new Set(),
  };
  sessions.add(session);
  session.authTimer = setTimeout(() => {
    if (!session.authenticated) cleanupSession(session, "authentication timeout");
  }, config.authTimeoutMs);

  ws.on("message", (data) => void handleBrowserMessage(session, data));
  ws.on("close", () => cleanupSession(session, "browser disconnected"));
  ws.on("error", () => cleanupSession(session, "browser websocket error"));
});

server.listen(config.port, config.bindHost, () => {
  log("gateway_started", {
    bindHost: config.bindHost,
    port: config.port,
    wsPath: config.wsPath,
    allowedOrigins: config.allowedOrigins,
    proxyTarget: `${config.proxyHost}:${config.proxyPort}`,
    maxWorkers: config.maxWorkers,
    maxPendingAuthConnections: config.maxPendingAuthConnections,
    maxConnectionAttemptsPerMinute: config.maxConnectionAttemptsPerMinute,
  });
});

function shutdown(signal) {
  log("gateway_stopping", { signal });
  for (const session of [...sessions]) cleanupSession(session, "gateway shutdown");
  wss.close(() => server.close(() => process.exit(0)));
  setTimeout(() => process.exit(1), 5000).unref();
}
process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
