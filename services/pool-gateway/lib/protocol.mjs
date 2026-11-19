import { createHmac, timingSafeEqual } from "node:crypto";

export const TOKEN_ISSUER = "mine-me-web";
export const TOKEN_AUDIENCE = "mine-me-pool-gateway";
export const TOKEN_MAX_TTL_SECONDS = 120;

function decodeBase64Url(value) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]+$/.test(value)) {
    throw new Error("Malformed session token encoding.");
  }
  return Buffer.from(value, "base64url");
}

export function signSessionToken(payload, secret) {
  if (typeof secret !== "string" || Buffer.byteLength(secret) < 32) {
    throw new Error("MINING_GATEWAY_TOKEN_SECRET must contain at least 32 bytes.");
  }
  const encodedPayload = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const signature = createHmac("sha256", secret).update(encodedPayload).digest("base64url");
  return encodedPayload + "." + signature;
}

export function verifySessionToken(token, secret, nowSeconds = Math.floor(Date.now() / 1000)) {
  if (typeof secret !== "string" || Buffer.byteLength(secret) < 32) {
    throw new Error("Gateway token secret is not configured safely.");
  }
  if (typeof token !== "string" || token.length > 4096) throw new Error("Invalid token size.");
  const parts = token.split(".");
  if (parts.length !== 2) throw new Error("Malformed session token.");

  const expected = createHmac("sha256", secret).update(parts[0]).digest();
  const actual = decodeBase64Url(parts[1]);
  if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) {
    throw new Error("Invalid session signature.");
  }

  const payload = JSON.parse(decodeBase64Url(parts[0]).toString("utf8"));
  if (payload.iss !== TOKEN_ISSUER || payload.aud !== TOKEN_AUDIENCE) {
    throw new Error("Invalid session token issuer or audience.");
  }
  if (!Number.isInteger(payload.iat) || !Number.isInteger(payload.exp)) {
    throw new Error("Invalid session token time claims.");
  }
  if (payload.iat > nowSeconds + 30 || payload.exp <= nowSeconds) {
    throw new Error("Session token is expired or not yet valid.");
  }
  if (payload.exp - payload.iat > TOKEN_MAX_TTL_SECONDS) {
    throw new Error("Session token lifetime exceeds the maximum.");
  }
  if (
    typeof payload.sub !== "string" ||
    typeof payload.deviceId !== "string" ||
    typeof payload.workerCode !== "string" ||
    typeof payload.jti !== "string" ||
    payload.jti.length < 16 ||
    payload.consentVersion !== "2026-11-19-v1" ||
    !Number.isInteger(payload.intensityPercent) ||
    payload.intensityPercent < 1 ||
    payload.intensityPercent > 80
  ) {
    throw new Error("Invalid device session claims.");
  }
  if (!/^MM-[0-9A-F]{32}$/.test(payload.workerCode)) {
    throw new Error("Invalid worker identifier.");
  }
  return payload;
}

export function normalisePoolJob(job) {
  if (!job || typeof job !== "object") throw new Error("Malformed pool job.");
  const jobId = job.job_id;
  const blob = job.blob;
  const target = job.target;
  const seedHash = job.seed_hash;
  const algorithm = job.algo;

  if (typeof jobId !== "string" || jobId.length < 1 || jobId.length > 256) {
    throw new Error("Invalid pool job identifier.");
  }
  if (typeof blob !== "string" || !/^(?:[0-9a-fA-F]{2}){43,}$/.test(blob)) {
    throw new Error("Invalid RandomX job blob.");
  }
  if (typeof target !== "string" || !/^(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{16})$/.test(target)) {
    throw new Error("Unsupported pool target encoding.");
  }
  if (typeof seedHash !== "string" || !/^[0-9a-fA-F]{64}$/.test(seedHash)) {
    throw new Error("RandomX pool seed hash is missing or malformed.");
  }
  if (algorithm !== "rx/0") throw new Error("Pool algorithm is not RandomX rx/0.");

  return { jobId, blob, target, seedHash, algorithm };
}

export function validateShareMessage(message, currentJobId) {
  if (!message || message.type !== "submit") return false;
  if (typeof message.jobId !== "string" || message.jobId !== currentJobId) return false;
  if (typeof message.nonce !== "string" || !/^[0-9a-fA-F]{8}$/.test(message.nonce)) return false;
  if (typeof message.result !== "string" || !/^[0-9a-fA-F]{64}$/.test(message.result)) return false;
  return true;
}

export function buildProxyLogin(workerCode) {
  if (!/^MM-[0-9A-F]{32}$/.test(workerCode)) throw new Error("Invalid worker code.");
  return {
    id: 1,
    jsonrpc: "2.0",
    method: "login",
    params: {
      login: workerCode,
      pass: "x",
      agent: "MINE-ME-Browser/0.1",
      rigid: workerCode,
      algo: ["rx/0"],
    },
  };
}

export function normaliseProxyLine(line) {
  if (typeof line !== "string" || line.length > 65536) {
    throw new Error("Proxy response exceeded the allowed size.");
  }
  const parsed = JSON.parse(line);
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("Malformed proxy response.");
  }
  return parsed;
}
