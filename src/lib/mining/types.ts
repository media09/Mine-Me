export type RandomXMiningJob = {
  jobId: string;
  blob: string;
  target: string;
  seedHash: string;
};

export type RandomXWorkerCommand =
  | { type: "start"; job: RandomXMiningJob; intensityPercent: number }
  | { type: "set-job"; job: RandomXMiningJob }
  | { type: "set-intensity"; intensityPercent: number }
  | { type: "pause" }
  | { type: "resume" }
  | { type: "stop" };

export type RandomXWorkerEvent =
  | { type: "initialising"; message: string }
  | { type: "ready"; message: string }
  | { type: "hashrate"; hashesPerSecond: number; hashesComputed: number }
  | { type: "share-found"; jobId: string; nonce: string; result: string }
  | { type: "paused" }
  | { type: "stopped" }
  | { type: "error"; message: string };
