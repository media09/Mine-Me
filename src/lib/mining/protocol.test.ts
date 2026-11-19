import { afterAll, describe, expect, it } from "vitest";
import { randomx_create_vm, randomx_init_cache } from "randomx.js";
import {
  incrementRandomXNonce,
  parseRandomXTarget,
  RANDOMX_NONCE_OFFSET,
} from "./protocol";

describe("RandomX Stratum helpers", () => {
  it("parses the 64-bit target in little-endian order", () => {
    expect(parseRandomXTarget("0100000000000000")).toBe(1n);
  });

  it("expands the pool's compact 32-bit target using XMRig's rule", () => {
    expect(parseRandomXTarget("01000000")).toBe(0x1_0000_0001n);
  });

  it("rejects zero and unsupported targets", () => {
    expect(() => parseRandomXTarget("00000000")).toThrow();
    expect(() => parseRandomXTarget("010203")).toThrow();
  });

  it("increments the 4-byte nonce as a little-endian uint32", () => {
    const blob = new Uint8Array(RANDOMX_NONCE_OFFSET + 4);
    const view = new DataView(blob.buffer);
    view.setUint32(RANDOMX_NONCE_OFFSET, 0x01020304, true);
    incrementRandomXNonce(blob);
    expect(view.getUint32(RANDOMX_NONCE_OFFSET, true)).toBe(0x01020305);
  });

  it("wraps the nonce at uint32 max", () => {
    const blob = new Uint8Array(RANDOMX_NONCE_OFFSET + 4);
    const view = new DataView(blob.buffer);
    view.setUint32(RANDOMX_NONCE_OFFSET, 0xffff_ffff, true);
    incrementRandomXNonce(blob);
    expect(view.getUint32(RANDOMX_NONCE_OFFSET, true)).toBe(0);
  });
});

describe("RandomX WASM known-answer test", () => {
  it("matches the upstream reference vector", () => {
    const cache = randomx_init_cache("test key 000");
    const vm = randomx_create_vm(cache);

    expect(vm.calculate_hex_hash("This is a test")).toBe(
      "639183aae1bf4c9a35884cb46b09cad9175f04efd7684e7262a0ac1c2f0b4e3f",
    );
    expect(vm.calculate_hex_hash("Lorem ipsum dolor sit amet")).toBe(
      "300a0adb47603dedb42228ccb2b211104f4da45af709cd7547cd049e9489c969",
    );
  });
});
