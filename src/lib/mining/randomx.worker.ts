/// <reference lib="webworker" />

import { randomx_create_vm, randomx_init_cache } from "randomx.js";
import {
  bytesToHex,
  hexToBytes,
  incrementRandomXNonce,
  parseRandomXTarget,
  RANDOMX_NONCE_OFFSET,
} from "./protocol";
import type {
  RandomXMiningJob,
  RandomXWorkerCommand,
  RandomXWorkerEvent,
} from "./types";

type RandomXVm = ReturnType<typeof randomx_create_vm>;

let vm: RandomXVm | null = null;
let activeSeedHash = "";
let activeJob: RandomXMiningJob | null = null;
let activeBlob: Uint8Array | null = null;
let activeTarget = 0n;
let intensityPercent = 20;
let running = false;
let paused = true;
let loopPromise: Promise<void> | null = null;
let hashesSinceReport = 0;
let reportStartedAt = 0;

function emit(event: RandomXWorkerEvent) {
  self.postMessage(event);
}

async function initialiseSeed(seedHash: string) {
  const normalized = seedHash.toLowerCase();
  if (vm && activeSeedHash === normalized) return;

  emit({ type: "initialising", message: "Initialisation du moteur RandomX…" });

  // The pool seed is a 32-byte binary key, not its 64-character hex text.
  const seed = hexToBytes(normalized, 32);
  const cache = randomx_init_cache(seed);
  vm = randomx_create_vm(cache);
  activeSeedHash = normalized;
}

function installJob(job: RandomXMiningJob) {
  if (!job.jobId || job.jobId.length > 256) {
    throw new Error("Identifiant de travail invalide.");
  }
  const blob = hexToBytes(job.blob);
  if (blob.length <= RANDOMX_NONCE_OFFSET + 4) {
    throw new Error("Le blob du pool est trop court pour un nonce RandomX.");
  }
  const target = parseRandomXTarget(job.target);

  activeJob = job;
  activeBlob = blob;
  activeTarget = target;
}

function delay(ms: number) {
  return new Promise<void>((resolve) => setTimeout(resolve, ms));
}

async function runLoop() {
  if (loopPromise) return loopPromise;

  loopPromise = (async () => {
    hashesSinceReport = 0;
    reportStartedAt = performance.now();

    while (running) {
      if (paused || !vm || !activeJob || !activeBlob) {
        await delay(100);
        continue;
      }

      const jobAtHashStart = activeJob;
      const blob = activeBlob;
      const startedAt = performance.now();
      const hash = vm.calculate_hash(blob);
      const hashDuration = Math.max(0.1, performance.now() - startedAt);
      hashesSinceReport += 1;

      // Let queued job/pause/stop messages run before emitting a candidate share.
      await delay(0);
      if (!running) break;

      if (jobAtHashStart === activeJob && activeBlob === blob) {
        const hashView = new DataView(hash.buffer, hash.byteOffset, hash.byteLength);
        if (hash.byteLength !== 32) {
          throw new Error("Le moteur RandomX a retourné une empreinte invalide.");
        }

        if (hashView.getBigUint64(24, true) < activeTarget) {
          const nonce = blob.slice(RANDOMX_NONCE_OFFSET, RANDOMX_NONCE_OFFSET + 4);
          emit({
            type: "share-found",
            jobId: jobAtHashStart.jobId,
            nonce: bytesToHex(nonce),
            result: bytesToHex(hash),
          });
        }
        // Advance the 32-bit nonce for the next RandomX input (little-endian, as in XMRig).
        incrementRandomXNonce(blob);
      }

      const now = performance.now();
      if (now - reportStartedAt >= 2000) {
        const elapsedSeconds = (now - reportStartedAt) / 1000;
        emit({
          type: "hashrate",
          hashesPerSecond: hashesSinceReport / elapsedSeconds,
          hashesComputed: hashesSinceReport,
        });
        hashesSinceReport = 0;
        reportStartedAt = now;
      }

      // The participant's chosen setting is a time-duty-cycle on this worker.
      // It limits CPU occupancy; it does not silently spawn extra threads.
      const safeIntensity = Math.max(1, Math.min(80, intensityPercent));
      const idleTime = hashDuration * (100 / safeIntensity - 1);
      if (idleTime > 0) await delay(idleTime);
    }
  })().catch((error: unknown) => {
    running = false;
    paused = true;
    emit({
      type: "error",
      message: error instanceof Error ? error.message : "Erreur inconnue du moteur RandomX.",
    });
  }).finally(() => {
    loopPromise = null;
    if (!running) emit({ type: "stopped" });
  });

  return loopPromise;
}

self.onmessage = (message: MessageEvent<RandomXWorkerCommand>) => {
  const command = message.data;

  void (async () => {
    try {
      switch (command.type) {
        case "start":
          intensityPercent = Math.max(1, Math.min(80, Math.trunc(command.intensityPercent)));
          await initialiseSeed(command.job.seedHash);
          installJob(command.job);
          running = true;
          paused = false;
          emit({ type: "ready", message: "Moteur RandomX prêt dans ce navigateur." });
          void runLoop();
          break;

        case "set-job":
          await initialiseSeed(command.job.seedHash);
          installJob(command.job);
          break;

        case "set-intensity":
          intensityPercent = Math.max(1, Math.min(80, Math.trunc(command.intensityPercent)));
          break;

        case "pause":
          paused = true;
          emit({ type: "paused" });
          break;

        case "resume":
          if (vm && activeJob && activeBlob) {
            running = true;
            paused = false;
            void runLoop();
          }
          break;

        case "stop":
          running = false;
          paused = true;
          activeJob = null;
          activeBlob = null;
          break;
      }
    } catch (error) {
      // A malformed/new job must not leave the worker hashing a stale job indefinitely.
      running = false;
      paused = true;
      activeJob = null;
      activeBlob = null;
      emit({
        type: "error",
        message: error instanceof Error ? error.message : "Erreur inconnue du moteur RandomX.",
      });
    }
  })();
};

export {};
