import test from "node:test";
import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import {
  TOKEN_AUDIENCE,
  TOKEN_ISSUER,
  buildProxyLogin,
  normalisePoolJob,
  normaliseProxyLine,
  signSessionToken,
  validateShareMessage,
  verifySessionToken,
} from "./lib/protocol.mjs";

const secret = "unit-test-secret-with-more-than-32-bytes";
const claims = {
  iss: TOKEN_ISSUER,
  aud: TOKEN_AUDIENCE,
  sub: "00000000-0000-4000-8000-000000000001",
  deviceId: "00000000-0000-4000-8000-000000000002",
  workerCode: "MM-0123456789ABCDEF0123456789ABCDEF",
  consentVersion: "2026-11-19-v1",
  intensityPercent: 20,
  iat: 1_800_000_000,
  exp: 1_800_000_090,
  jti: "f8bc5b0c-3b96-4e44-8d8a-42c09aab8d22",
};

test("signed device token verifies once within its bounded lifetime", () => {
  const token = signSessionToken(claims, secret);
  assert.deepEqual(verifySessionToken(token, secret, claims.iat + 1), claims);
});

test("tampered token signature is rejected", () => {
  const token = signSessionToken(claims, secret);
  const [payload, signature] = token.split(".");
  const replacement = (signature[0] === "A" ? "B" : "A") + signature.slice(1);
  assert.throws(() => verifySessionToken(payload + "." + replacement, secret, claims.iat + 1));
});

test("expired token is rejected", () => {
  const token = signSessionToken(claims, secret);
  assert.throws(() => verifySessionToken(token, secret, claims.exp));
});

test("token with excessive lifetime is rejected", () => {
  const token = signSessionToken({ ...claims, exp: claims.iat + 121 }, secret);
  assert.throws(() => verifySessionToken(token, secret, claims.iat + 1));
});

test("token with short signing secret is rejected", () => {
  assert.throws(() => signSessionToken(claims, "too-short"));
});

test("pool job is normalised only for RandomX and fixed-size seed/target fields", () => {
  const job = normalisePoolJob({
    job_id: "job-123",
    blob: "ab".repeat(80),
    target: "01000000",
    seed_hash: "cd".repeat(32),
    algo: "rx/0",
  });
  assert.deepEqual(job, {
    jobId: "job-123",
    blob: "ab".repeat(80),
    target: "01000000",
    seedHash: "cd".repeat(32),
    algorithm: "rx/0",
  });
});

test("non-RandomX job and malformed pool fields are rejected", () => {
  const base = {
    job_id: "job-123",
    blob: "ab".repeat(80),
    target: "01000000",
    seed_hash: "cd".repeat(32),
  };
  assert.throws(() => normalisePoolJob({ ...base, algo: "cn/r" }));
  assert.throws(() => normalisePoolJob({ ...base, seed_hash: "bad", algo: "rx/0" }));
});

test("browser share must match current job and strict nonce/result sizes", () => {
  assert.equal(validateShareMessage({
    type: "submit", jobId: "job-123", nonce: "0102037a", result: "ab".repeat(32),
  }, "job-123"), true);
  assert.equal(validateShareMessage({
    type: "submit", jobId: "old-job", nonce: "0102037a", result: "ab".repeat(32),
  }, "job-123"), false);
  assert.equal(validateShareMessage({
    type: "submit", jobId: "job-123", nonce: "010203", result: "ab".repeat(32),
  }, "job-123"), false);
});

test("proxy login is pinned to the device worker identity and RandomX algorithm", () => {
  const login = buildProxyLogin(claims.workerCode);
  assert.equal(login.method, "login");
  assert.equal(login.params.rigid, claims.workerCode);
  assert.deepEqual(login.params.algo, ["rx/0"]);
  assert.throws(() => buildProxyLogin("wallet-address-from-browser"));
});

test("proxy JSON framing rejects arrays and overlong messages", () => {
  assert.deepEqual(normaliseProxyLine('{"id":1,"result":{"status":"OK"}}'), {
    id: 1, result: { status: "OK" },
  });
  assert.throws(() => normaliseProxyLine("[]"));
  assert.throws(() => normaliseProxyLine("x".repeat(65537)));
});
