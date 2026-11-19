"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { RandomXWorkerEngine } from "@/lib/mining/engine";
import type { RandomXMiningJob, RandomXWorkerEvent } from "@/lib/mining/types";

type Device = {
  id: string;
  worker_code: string;
  label: string | null;
  status: string;
  intensity_percent: number;
  last_seen_at: string | null;
};

type MiningSessionResponse = {
  token: string;
  gatewayUrl: string;
  workerCode: string;
  intensityPercent: number;
  expiresAt: number;
};

type GatewayMessage = {
  type?: string;
  message?: string;
  job?: RandomXMiningJob;
  accepted?: boolean;
  reason?: string | null;
};

function statusLabel(status: string) {
  switch (status) {
    case "running": return "Calcul en cours";
    case "connecting": return "Connexion au pool…";
    case "enrolled": return "Associé — en attente";
    case "paused": return "En pause";
    case "stopped": return "Arrêté";
    case "offline": return "Hors ligne";
    case "blocked": return "Bloqué par l’administration";
    case "disabled": return "Minage désactivé";
    case "error": return "Connexion indisponible";
    default: return status;
  }
}

export default function DeviceControl({
  device,
  maxIntensityPercent,
}: {
  device: Device;
  maxIntensityPercent: number;
}) {
  const router = useRouter();
  const [intensity, setIntensity] = useState(Math.min(device.intensity_percent, maxIntensityPercent));
  const [savedIntensity, setSavedIntensity] = useState(Math.min(device.intensity_percent, maxIntensityPercent));
  const [deviceStatus, setDeviceStatus] = useState(device.status);
  const [miningState, setMiningState] = useState(
    device.status === "running" ? "offline" : device.status,
  );
  const [hashrate, setHashrate] = useState(0);
  const [acceptedShares, setAcceptedShares] = useState(0);
  const [rejectedShares, setRejectedShares] = useState(0);
  const [busy, setBusy] = useState(false);
  const [feedback, setFeedback] = useState("");
  const [connectionAttempt, setConnectionAttempt] = useState(0);
  const socketRef = useRef<WebSocket | null>(null);
  const engineRef = useRef<RandomXWorkerEngine | null>(null);
  const intentionalCloseRef = useRef(false);

  function closeConnection(intentional = true) {
    intentionalCloseRef.current = intentional;
    const engine = engineRef.current;
    engineRef.current = null;
    if (engine) engine.dispose();

    const socket = socketRef.current;
    socketRef.current = null;
    if (socket && socket.readyState < WebSocket.CLOSING) socket.close(1000, "member control");
  }

  useEffect(() => {
    let cancelled = false;
    let heartbeatTimer: ReturnType<typeof setInterval> | null = null;
    let socket: WebSocket | null = null;
    let engine: RandomXWorkerEngine | null = null;

    async function connect() {
      if (deviceStatus !== "enrolled" && deviceStatus !== "offline") {
        setMiningState(deviceStatus === "running" ? "offline" : deviceStatus);
        return;
      }

      setMiningState("connecting");
      setFeedback("");

      try {
        const response = await fetch("/mineme/api/mining/session", {
          method: "POST",
          headers: { "content-type": "application/json" },
          credentials: "same-origin",
          cache: "no-store",
          body: JSON.stringify({ deviceId: device.id }),
        });

        const payload = await response.json().catch(() => ({})) as Partial<MiningSessionResponse> & { error?: string };
        if (!response.ok) {
          if (response.status === 409 && payload.error?.toLowerCase().includes("désactivé")) {
            setMiningState("disabled");
          } else {
            setMiningState("error");
          }
          setFeedback(payload.error || "Le service de calcul n’est pas disponible.");
          return;
        }

        if (
          cancelled ||
          typeof payload.token !== "string" ||
          typeof payload.gatewayUrl !== "string" ||
          typeof payload.intensityPercent !== "number"
        ) return;

        const session = payload as MiningSessionResponse;
        socket = new WebSocket(session.gatewayUrl);
        socketRef.current = socket;
        intentionalCloseRef.current = false;

        socket.onopen = () => {
          if (cancelled || socket?.readyState !== WebSocket.OPEN) return;
          socket.send(JSON.stringify({ type: "auth", token: session.token }));
          heartbeatTimer = setInterval(() => {
            if (socket?.readyState === WebSocket.OPEN) {
              socket.send(JSON.stringify({ type: "heartbeat" }));
            }
          }, 20_000);
        };

        socket.onmessage = (event) => {
          let message: GatewayMessage;
          try {
            message = JSON.parse(String(event.data)) as GatewayMessage;
          } catch {
            setMiningState("error");
            setFeedback("Réponse invalide reçue du service de calcul.");
            closeConnection(false);
            return;
          }

          if (message.type === "ready") {
            setMiningState("running");
            setDeviceStatus("running");
            return;
          }

          if (message.type === "job" && message.job) {
            const job = message.job;
            if (!engine) {
              engine = new RandomXWorkerEngine((workerEvent: RandomXWorkerEvent) => {
                if (workerEvent.type === "hashrate") {
                  setHashrate(workerEvent.hashesPerSecond);
                } else if (workerEvent.type === "share-found") {
                  if (socket?.readyState === WebSocket.OPEN) {
                    socket.send(JSON.stringify({
                      type: "submit",
                      jobId: workerEvent.jobId,
                      nonce: workerEvent.nonce,
                      result: workerEvent.result,
                    }));
                  }
                } else if (workerEvent.type === "error") {
                  setMiningState("error");
                  setFeedback(workerEvent.message);
                  closeConnection(false);
                }
              });
              engineRef.current = engine;
              engine.start({
                jobId: job.jobId,
                blob: job.blob,
                target: job.target,
                seedHash: job.seedHash,
              }, session.intensityPercent);
            } else {
              engine.setJob({
                jobId: job.jobId,
                blob: job.blob,
                target: job.target,
                seedHash: job.seedHash,
              });
            }
            return;
          }

          if (message.type === "share-result") {
            if (message.accepted) setAcceptedShares((count) => count + 1);
            else setRejectedShares((count) => count + 1);
            return;
          }

          if (message.type === "error") {
            setMiningState("error");
            setFeedback(message.message || "Le service de calcul a interrompu la connexion.");
            closeConnection(false);
          }
        };

        socket.onerror = () => {
          if (!cancelled) {
            setMiningState("error");
            setFeedback("Impossible de joindre la passerelle de calcul sécurisée.");
          }
        };

        socket.onclose = () => {
          if (heartbeatTimer) clearInterval(heartbeatTimer);
          if (engine) {
            engine.dispose();
            engine = null;
          }
          if (engineRef.current) engineRef.current = null;
          const wasCurrentSocket = socketRef.current === socket;
          if (wasCurrentSocket) socketRef.current = null;

          if (wasCurrentSocket && !cancelled && !intentionalCloseRef.current) {
            setMiningState((current) => current === "running" || current === "connecting" ? "offline" : current);
          }
        };
      } catch {
        if (!cancelled) {
          setMiningState("error");
          setFeedback("Le service de calcul n’est pas encore configuré ou accessible.");
        }
      }
    }

    void connect();

    return () => {
      cancelled = true;
      if (heartbeatTimer) clearInterval(heartbeatTimer);
      if (engine) {
        engine.dispose();
        engine = null;
      }
      if (engineRef.current) engineRef.current = null;
      if (socket && socket.readyState < WebSocket.CLOSING) {
        intentionalCloseRef.current = true;
        socket.close(1000, "dashboard closed");
      }
      if (socketRef.current === socket) socketRef.current = null;
    };
  }, [device.id, connectionAttempt]);

  async function saveIntensity() {
    setBusy(true);
    setFeedback("");
    const wasRunning = deviceStatus === "running" || miningState === "running";

    try {
      const supabase = createClient();
      const { data: { user }, error: authError } = await supabase.auth.getUser();
      if (authError || !user) throw new Error("Session membre introuvable.");

      // Pause first so the session's original intensity claim cannot remain active
      // while a lower participant setting is being saved.
      const patch = wasRunning
        ? { intensity_percent: intensity, status: "paused" as const }
        : { intensity_percent: intensity };

      const { data, error } = await supabase
        .from("devices")
        .update(patch)
        .eq("id", device.id)
        .eq("user_id", user.id)
        .select("intensity_percent")
        .single();

      if (error) throw error;

      setIntensity(data.intensity_percent);
      setSavedIntensity(data.intensity_percent);

      if (wasRunning) {
        closeConnection(true);
        const { error: resumeError } = await supabase
          .from("devices")
          .update({ status: "enrolled" })
          .eq("id", device.id)
          .eq("user_id", user.id)
          .eq("status", "paused");

        if (resumeError) throw resumeError;
        setDeviceStatus("enrolled");
        setMiningState("connecting");
        setConnectionAttempt((value) => value + 1);
        setFeedback("Intensité enregistrée. Reconnexion avec votre nouvelle préférence…");
      } else {
        setFeedback("Préférence d’intensité enregistrée.");
      }
      router.refresh();
    } catch (error) {
      setFeedback(error instanceof Error ? error.message : "Impossible d’enregistrer cette préférence.");
    } finally {
      setBusy(false);
    }
  }

  async function changeParticipation(nextStatus: "paused" | "stopped" | "enrolled") {
    setBusy(true);
    setFeedback("");
    try {
      const supabase = createClient();
      const { data: { user }, error: authError } = await supabase.auth.getUser();
      if (authError || !user) throw new Error("Session membre introuvable.");

      const { error } = await supabase
        .from("devices")
        .update({ status: nextStatus })
        .eq("id", device.id)
        .eq("user_id", user.id);

      if (error) throw error;

      if (nextStatus === "enrolled") {
        setDeviceStatus("enrolled");
        setMiningState("connecting");
        setConnectionAttempt((value) => value + 1);
        setFeedback("Appareil réautorisé. Connexion au service de calcul…");
      } else {
        setDeviceStatus(nextStatus);
        setMiningState(nextStatus);
        setHashrate(0);
        closeConnection(true);
        setFeedback(nextStatus === "paused" ? "Appareil mis en pause." : "Participation arrêtée sur cet appareil.");
      }
      router.refresh();
    } catch (error) {
      setFeedback(error instanceof Error ? error.message : "Impossible de modifier l’état de cet appareil.");
    } finally {
      setBusy(false);
    }
  }

  const canResume = deviceStatus === "paused" || deviceStatus === "stopped" || deviceStatus === "offline";
  const canPause = deviceStatus === "enrolled" || deviceStatus === "running" || miningState === "connecting" || miningState === "running";
  const canStop = deviceStatus !== "stopped" && deviceStatus !== "blocked";

  return (
    <article className="device-row device-card">
      <div className="device-main">
        <div className="device-title">
          <strong>{device.label || device.worker_code}</strong>
          <span className={miningState === "running" ? "device-status device-status-live" : "device-status"}>{statusLabel(miningState)}</span>
        </div>
        <small>{device.worker_code}</small>
        <div className="mining-live-stats">
          <div><span>HASHRATE NAVIGATEUR</span><strong>{hashrate > 0 ? `${hashrate.toFixed(2)} H/s` : "—"}</strong></div>
          <div><span>SHARES ACCEPTÉES</span><strong>{acceptedShares}</strong></div>
          <div><span>SHARES REJETÉES</span><strong>{rejectedShares}</strong></div>
        </div>
        <div className="intensity-editor">
          <div className="intensity-label"><label htmlFor={`intensity-${device.id}`}>Intensité souhaitée</label><strong>{intensity}%</strong></div>
          <input id={`intensity-${device.id}`} type="range" min="1" max={maxIntensityPercent} step="1" value={intensity} onChange={(event) => {
            const next = Number(event.target.value);
            setIntensity(next);
            engineRef.current?.setIntensity(next);
          }} />
          <div className="intensity-scale"><span>Économie</span><span>Plus actif</span></div>
          <p className="device-mini-note">Réglage de l’activité d’un worker RandomX dans le navigateur (un thread). Plafond autorisé par la plateforme : {maxIntensityPercent}%. Ce pourcentage ne représente pas directement l’utilisation totale de tous les cœurs.</p>
          <div className="device-actions">
            {deviceStatus === "enrolled" && miningState !== "running" && miningState !== "connecting" &&
              <button className="mini-action" type="button" disabled={busy} onClick={() => setConnectionAttempt((value) => value + 1)}>Relancer la connexion</button>}
            <button className="save-intensity" type="button" onClick={saveIntensity} disabled={busy || intensity === savedIntensity}>{busy ? "Enregistrement…" : "Enregistrer l’intensité"}</button>
            {canPause && <button className="mini-action" type="button" disabled={busy} onClick={() => changeParticipation("paused")}>Mettre en pause</button>}
            {canResume && <button className="mini-action" type="button" disabled={busy} onClick={() => changeParticipation("enrolled")}>Reprendre le calcul</button>}
            {canStop && <button className="mini-action danger-action" type="button" disabled={busy} onClick={() => changeParticipation("stopped")}>Arrêter</button>}
          </div>
          {feedback && <p className="device-feedback" role="status">{feedback}</p>}
          <p className="device-mini-note">Le calcul s’exécute dans ce navigateur. Fermer cet onglet ou le suspendre interrompt le travail.</p>
        </div>
      </div>
    </article>
  );
}
