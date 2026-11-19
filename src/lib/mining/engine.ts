import type {
  RandomXMiningJob,
  RandomXWorkerCommand,
  RandomXWorkerEvent,
} from "./types";

export type RandomXWorkerListener = (event: RandomXWorkerEvent) => void;

/**
 * Thin browser-side wrapper for the RandomX Web Worker.
 * The caller must obtain jobs and submit candidate shares through the authenticated
 * MINE-ME WSS gateway. This class never connects directly to a pool.
 */
export class RandomXWorkerEngine {
  private worker: Worker;
  private disposed = false;

  constructor(listener: RandomXWorkerListener) {
    this.worker = new Worker(new URL("./randomx.worker.ts", import.meta.url), {
      type: "module",
      name: "mine-me-randomx",
    });
    this.worker.onmessage = (event: MessageEvent<RandomXWorkerEvent>) => {
      if (!this.disposed) listener(event.data);
    };
    this.worker.onerror = () => {
      if (!this.disposed) {
        listener({ type: "error", message: "Le worker de calcul du navigateur a rencontré une erreur." });
      }
    };
  }

  start(job: RandomXMiningJob, intensityPercent: number) {
    this.send({ type: "start", job, intensityPercent });
  }

  setJob(job: RandomXMiningJob) {
    this.send({ type: "set-job", job });
  }

  setIntensity(intensityPercent: number) {
    this.send({ type: "set-intensity", intensityPercent });
  }

  pause() {
    this.send({ type: "pause" });
  }

  resume() {
    this.send({ type: "resume" });
  }

  stop() {
    this.send({ type: "stop" });
  }

  dispose() {
    if (this.disposed) return;
    this.disposed = true;
    this.worker.postMessage({ type: "stop" } satisfies RandomXWorkerCommand);
    this.worker.terminate();
  }

  private send(command: RandomXWorkerCommand) {
    if (this.disposed) throw new Error("Le moteur RandomX a déjà été fermé.");
    this.worker.postMessage(command);
  }
}
