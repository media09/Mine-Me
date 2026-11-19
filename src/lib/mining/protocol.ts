export const RANDOMX_NONCE_OFFSET = 39;
export const RANDOMX_NONCE_SIZE = 4;

const UINT32_MAX = 0xffff_ffffn;
const UINT64_MAX = 0xffff_ffff_ffff_ffffn;

export function hexToBytes(value: string, expectedBytes?: number): Uint8Array {
  const normalized = value.trim().toLowerCase();
  if (!normalized || normalized.length % 2 !== 0 || !/^[0-9a-f]+$/.test(normalized)) {
    throw new Error("Donnée hexadécimale de travail invalide.");
  }
  const bytes = new Uint8Array(normalized.length / 2);
  for (let index = 0; index < bytes.length; index += 1) {
    bytes[index] = Number.parseInt(normalized.slice(index * 2, index * 2 + 2), 16);
  }
  if (expectedBytes !== undefined && bytes.length !== expectedBytes) {
    throw new Error("Longueur de donnée RandomX invalide.");
  }
  return bytes;
}

export function bytesToHex(value: Uint8Array): string {
  return Array.from(value, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function parseRandomXTarget(targetHex: string): bigint {
  const bytes = hexToBytes(targetHex);
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);

  if (bytes.length === 4) {
    const compactTarget = BigInt(view.getUint32(0, true));
    if (compactTarget === 0n) throw new Error("La difficulté du pool est invalide.");
    return UINT64_MAX / (UINT32_MAX / compactTarget);
  }

  if (bytes.length === 8) {
    const target = view.getBigUint64(0, true);
    if (target === 0n) throw new Error("La difficulté du pool est invalide.");
    return target;
  }

  throw new Error("Le pool a envoyé une cible RandomX non prise en charge.");
}

/**
 * vltrig-proxy's NiceHash mode assigns the last nonce byte to the downstream miner.
 * Preserve that fixed byte and increment only the lower 24-bit per-miner nonce.
 */
export function incrementRandomXNonce(blob: Uint8Array): void {
  if (blob.length < RANDOMX_NONCE_OFFSET + RANDOMX_NONCE_SIZE) {
    throw new Error("Le blob du pool est trop court pour un nonce RandomX.");
  }
  const view = new DataView(blob.buffer, blob.byteOffset, blob.byteLength);
  const current = view.getUint32(RANDOMX_NONCE_OFFSET, true);
  const fixedByte = current & 0xff00_0000;
  const nextCounter = ((current & 0x00ff_ffff) + 1) & 0x00ff_ffff;
  view.setUint32(RANDOMX_NONCE_OFFSET, fixedByte | nextCounter, true);
}

export function randomXHashMeetsTarget(hash: Uint8Array, target: bigint): boolean {
  if (hash.byteLength !== 32) {
    throw new Error("Une empreinte RandomX doit contenir exactement 32 octets.");
  }
  const view = new DataView(hash.buffer, hash.byteOffset, hash.byteLength);
  return view.getBigUint64(24, true) < target;
}
